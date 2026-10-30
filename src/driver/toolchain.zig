const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const runtime_symbols = @import("../support/runtime_symbols.zig");

/// The programs a build runs, in the order it runs them.
///
/// All are found on `PATH`. Naming them here rather than at each call site is
/// what lets a failure say which one failed without the caller repeating it,
/// and it is also what the outcome cache stamps: the salt is built by walking
/// every member, so a tool a build runs and this enum does not name is a tool a
/// recorded outcome cannot notice moving.
pub const Tool = enum {
    mlir_opt,
    mlir_translate,
    cc,

    /// What to spell on the command line. Not `@tagName`, because two of these
    /// are spelled with a hyphen and an enum member cannot be. Every argv
    /// below is built from this, so the name the outcome cache stamps and the
    /// name the process runs cannot drift apart.
    pub fn command(self: Tool) []const u8 {
        return switch (self) {
            .mlir_opt => "mlir-opt",
            .mlir_translate => "mlir-translate",
            .cc => "cc",
        };
    }
};

/// Why a build stopped. Held rather than printed so the driver decides how a
/// failure is rendered, the same as every other diagnostic.
pub const Failure = struct {
    tool: Tool,
    /// What the tool wrote, or an empty string when it wrote nothing. A user
    /// should not have to run the tool again to find out why it refused.
    output: []const u8,
    /// True when the program could not be started at all, which almost always
    /// means it is not installed.
    missing: bool = false,
};

/// Which allocator a program links.
///
/// The checking allocator gives every allocation pages of its own and never
/// reuses an address, so a use of freed storage, a second disposal or a store
/// outside an allocation aborts where the ordinary allocator would let it
/// through. It changes nothing else a program can observe, and it costs a
/// system call per allocation and per disposal and a page per live allocation.
pub const Storage = enum {
    unchecked,
    checked,

    /// The archive holding this allocator.
    pub fn archive(self: Storage) []const u8 {
        return switch (self) {
            .unchecked => runtime_symbols.archive_name,
            .checked => runtime_symbols.checked_archive_name,
        };
    }
};

test "each allocator is its own archive" {
    try testing.expectEqualStrings("liblinea_rt.a", Storage.unchecked.archive());
    try testing.expectEqualStrings("liblinea_rt_checked.a", Storage.checked.archive());
}

/// The variable naming a runtime to use instead of the one beside the
/// compiler. A packager splitting the two, or a test exercising a runtime it
/// just built, needs to say where it is.
pub const runtime_override = "LINEA_RUNTIME";

/// The variable naming the sanitizer the runtime was built with.
///
/// One fact with the runtime path rather than two. A static library and the
/// instrumentation compiled into it are a single choice, and a link naming the
/// first without the second leaves every sanitizer routine unresolved -- so a
/// compiler told where a sanitized runtime is has to be told what it is. The
/// alternative, reading the archive to find out, would answer from the artefact
/// a question its builder already knew.
pub const sanitize_override = "LINEA_SANITIZE";

/// The sanitizer to name at the link, or null for an ordinary build.
///
/// Empty is absent, the same as it is for the runtime path: a variable set to
/// nothing is how a shell spells "not set" when it cannot unset one.
pub fn findSanitize(environ: std.process.Environ) ?[]const u8 {
    const named = environ.getPosix(sanitize_override) orelse return null;
    return if (named.len > 0) named else null;
}

/// The environment variable that tells a spawned compiler which sanitizer its
/// runtime archive was built with, or null for an ordinary build.
pub fn sanitizeVariable(sanitize: ?[]const u8) ?struct { name: []const u8, value: []const u8 } {
    const value = sanitize orelse return null;
    return .{ .name = sanitize_override, .value = value };
}

test "a sanitized build tells the spawned compiler its sanitizer" {
    try testing.expect(sanitizeVariable(null) == null);
    const variable = sanitizeVariable("address").?;
    try testing.expectEqualStrings("LINEA_SANITIZE", variable.name);
    try testing.expectEqualStrings("address", variable.value);
}

/// Finds the runtime library holding `storage`'s allocator, or null when there
/// is none to find. An override names the runtime every build links, whichever
/// allocator it holds. Otherwise the archive is looked for in the install
/// tree's `lib/` and then beside the compiler, so the binary works from an
/// install tree and from the build output alike.
pub fn findRuntime(gpa: std.mem.Allocator, io: std.Io, environ: std.process.Environ, storage: Storage) !?[]const u8 {
    if (environ.getPosix(runtime_override)) |named| {
        if (named.len > 0) return try gpa.dupe(u8, named);
    }

    const dir = try std.process.executableDirPathAlloc(io, gpa);
    defer gpa.free(dir);

    for ([_][]const u8{ "../lib", "." }) |rel| {
        const path = try std.fs.path.join(gpa, &.{ dir, rel, storage.archive() });
        if (std.Io.Dir.cwd().access(io, path, .{})) |_| return path else |_| gpa.free(path);
    }
    return null;
}

/// A directory for one `run` invocation's executable and intermediates.
///
/// It is made under the host's scratch directory, never beside the source: a
/// source directory is one somebody wrote, and for a corpus case one whose
/// contents are compared against goldens. A random name and atomic creation
/// keep overlapping runs of one source apart.
///
/// Nothing a run builds outlives it, however it ends. `remove` deletes the
/// directory on every path the driver returns through, and a janitor process
/// deletes it when this process ends any other way: a signal, including one
/// that cannot be caught, or the program replacing this process. The janitor
/// reads its standard input, a pipe only this process holds the other end of
/// and which closes when this process exits or executes the program. It then
/// waits until this process id is gone, because the program runs under it
/// and on Darwin the kernel kills a signed program whose file is deleted
/// while it runs. It sits in a process group of its own and ignores the
/// signals a terminal sends, so the interrupt that stops the run does not
/// stop it too.
pub const RunOutput = struct {
    directory: []const u8,
    path: []const u8,
    janitor: std.process.Child,

    /// Exits at once when told the directory is removed. Otherwise, once its
    /// input ends and the process named by its second argument is gone,
    /// deletes the directory named by its first, retrying while a tool the run
    /// started may still be writing into it.
    const janitor_script =
        \\trap '' HUP INT TERM
        \\while read -r line; do [ "$line" = removed ] && exit 0; done
        \\while kill -0 "$2" 2>/dev/null; do sleep 1; done
        \\for attempt in 1 2 3 4 5 6 7 8 9 10; do
        \\    rm -rf "$1"
        \\    [ -e "$1" ] || exit 0
        \\    sleep 1
        \\done
    ;

    pub fn create(gpa: std.mem.Allocator, io: std.Io, scratch_root: []const u8) !RunOutput {
        const this_process: std.posix.pid_t = if (builtin.os.tag == .linux) std.os.linux.getpid() else std.c.getpid();
        return createWatching(gpa, io, scratch_root, this_process);
    }

    /// `create`, with the janitor waiting on `watched` rather than on this
    /// process, which is what lets a test stand in for this process ending.
    fn createWatching(gpa: std.mem.Allocator, io: std.Io, scratch_root: []const u8, watched: std.posix.pid_t) !RunOutput {
        var pid_text: [24]u8 = undefined;
        const pid_arg = try std.fmt.bufPrint(&pid_text, "{d}", .{watched});
        while (true) {
            var random: u64 = undefined;
            io.random(@ptrCast(&random));
            const directory = try std.fmt.allocPrint(gpa, "{s}/linea-run-{s}", .{ scratch_root, std.fmt.hex(random) });
            errdefer gpa.free(directory);
            std.Io.Dir.cwd().createDir(io, directory, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    gpa.free(directory);
                    continue;
                },
                else => return err,
            };
            errdefer std.Io.Dir.cwd().deleteTree(io, directory) catch {};
            const path = try std.fs.path.join(gpa, &.{ directory, "program" });
            errdefer gpa.free(path);
            const janitor = try std.process.spawn(io, .{
                .argv = &.{ "/bin/sh", "-c", janitor_script, "linea-run-janitor", directory, pid_arg },
                .stdin = .pipe,
                .stdout = .ignore,
                .stderr = .ignore,
                .pgid = 0,
            });
            return .{ .directory = directory, .path = path, .janitor = janitor };
        }
    }

    /// Deletes the directory and everything built in it, and lets the janitor
    /// go.
    pub fn remove(self: *RunOutput, io: std.Io) void {
        std.Io.Dir.cwd().deleteTree(io, self.directory) catch {};
        if (self.janitor.stdin) |stdin| {
            stdin.writeStreamingAll(io, "removed\n") catch {};
            stdin.close(io);
            self.janitor.stdin = null;
            _ = self.janitor.wait(io) catch {};
        }
    }

    pub fn deinit(self: RunOutput, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.directory);
    }
};

/// A path under `scratch_root` that no other build names: `prefix`, a dash and
/// sixty-four random bits in hex. A clock reading is not unique, since two
/// builds that start in the same tick would write and then delete each other's
/// intermediates, and a sharded CI job or a watch loop starts builds together.
pub fn uniqueTarget(gpa: std.mem.Allocator, io: std.Io, scratch_root: []const u8, prefix: []const u8) std.mem.Allocator.Error![]const u8 {
    var random: u64 = undefined;
    io.random(@ptrCast(&random));
    return std.fmt.allocPrint(gpa, "{s}/{s}-{s}", .{ scratch_root, prefix, std.fmt.hex(random) });
}

/// The files a build writes between the module and the executable, named in
/// one place from the executable's own name. One routine, because whoever
/// removes them must spell them the way the build did -- a cleanup keeping an
/// extension list of its own is a cleanup that misses the file whose name
/// moved.
pub const Intermediates = struct {
    /// The emitted MLIR.
    ir: []const u8,
    /// MLIR bytecode exchanged by conversion and translation.
    lowered: []const u8,
    /// The translated LLVM IR. Kept as a real file rather than a pipe so a
    /// failing build leaves something to look at.
    assembly: []const u8,

    pub fn of(gpa: std.mem.Allocator, out_path: []const u8) std.mem.Allocator.Error!Intermediates {
        const ir = try std.fmt.allocPrint(gpa, "{s}.mlir", .{out_path});
        errdefer gpa.free(ir);
        const lowered = try std.fmt.allocPrint(gpa, "{s}.llvm", .{ir});
        errdefer gpa.free(lowered);
        const assembly = try std.fmt.allocPrint(gpa, "{s}.ll", .{out_path});
        return .{ .ir = ir, .lowered = lowered, .assembly = assembly };
    }

    pub fn deinit(self: Intermediates, gpa: std.mem.Allocator) void {
        gpa.free(self.ir);
        gpa.free(self.lowered);
        gpa.free(self.assembly);
    }

    /// Removes whatever of the three exists, quietly: a caller cleans up on
    /// paths where some of them were never written.
    pub fn remove(self: Intermediates, io: std.Io) void {
        std.Io.Dir.cwd().deleteFile(io, self.ir) catch {};
        std.Io.Dir.cwd().deleteFile(io, self.lowered) catch {};
        std.Io.Dir.cwd().deleteFile(io, self.assembly) catch {};
    }
};

/// What a build produces.
pub const Artifact = enum { executable, object };

/// The optimisation levels a build offers, which are the ones `cc` takes: a
/// level is passed through as `-O<level>`.
///
/// Every level preserves the language contracts. The emitted module carries no
/// wrap flags, no aliasing metadata and no fast-math, so an optimiser has no
/// premise that could make two levels disagree about what a program does.
pub const levels = [_][]const u8{ "0", "1", "2", "3", "s", "z" };

/// The level a build uses when none is named.
pub const default_level = "2";

test "the default optimisation level is one of the levels a build offers" {
    var found = false;
    for (levels) |level| found = found or std.mem.eql(u8, level, default_level);
    try testing.expect(found);
}

pub const Options = struct {
    /// The between-stages files, `mid.ir` already written with the emitted
    /// module. Composed by `Intermediates.of`, so the caller that deletes
    /// them and the build that writes them cannot disagree about a name.
    mid: Intermediates,
    /// The file to produce.
    out_path: []const u8,
    runtime_path: []const u8,
    /// What to produce, and so whether anything is linked.
    ///
    /// A library has no entry point, so there is nothing for a linker to start
    /// from and nothing it could produce. What it leaves is the object, which
    /// is what a library is until something decides how to reach into one.
    artifact: Artifact = .executable,
    /// The `-O` level `cc` compiles the generated IR at, one of `levels`.
    /// Every level preserves the language contracts, including the permitted
    /// platform-dependent precision of transcendental operations.
    opt: []const u8 = default_level,
    /// A sanitizer the runtime was built with, which the link has to name too
    /// so its support library is pulled in. Null for an ordinary build.
    sanitize: ?[]const u8 = null,
    /// C sources compiled at the same level and linked into the executable.
    native: []const []const u8 = &.{},
    /// C libraries linked into the executable, each passed as `-l<name>`.
    link: []const []const u8 = &.{},
};

/// The conversion pipeline the emitter is written against, confirmed by
/// driving a hand-written module through it before any of it was emitted.
///
/// Order matters between the first three passes: each lowers its own dialect
/// and leaves the others alone, so a pass that runs before the dialect it feeds
/// has nothing to do. `--reconcile-unrealized-casts` is last and is not
/// optional -- the conversions leave casts between the type systems they
/// straddle, and a module still holding one is refused by translation rather
/// than by this step.
///
/// `--allow-unregistered-dialect` is absent and must stay absent. It is what
/// makes an operation no dialect defines an error rather than something carried
/// through untouched: with the flag such a module is accepted, the operation
/// lowers to nothing, and the program is missing the work rather than refusing
/// to build.
///
/// Turns emitted MLIR into an executable, returning what failed if anything
/// did: `mlir-opt` lowers the printed dialects to the LLVM dialect,
/// `mlir-translate` writes LLVM IR, and `cc` compiles and links it directly --
/// no assembler step of this compiler's own, because `cc` takes the IR as an
/// input language. The steps are separate processes rather than a library call,
/// which is what keeps emission a function producing a value.
pub fn build(
    gpa: std.mem.Allocator,
    io: std.Io,
    opts: Options,
) !?Failure {
    if (try lowerToLlvm(gpa, io, opts.mid)) |f| return f;

    // Each C source becomes an object beside the IR, compiled by the same `cc`
    // at the same level, and instrumented when the runtime is.
    const objects = try gpa.alloc([]const u8, opts.native.len);
    defer gpa.free(objects);
    // Every object made so far is removed whichever way the build ends, so a
    // source that fails to compile leaves none of the earlier ones behind.
    var made: usize = 0;
    defer for (objects[0..made]) |object| std.Io.Dir.cwd().deleteFile(io, object) catch {};
    for (opts.native, 0..) |source, i| {
        objects[i] = try std.fmt.allocPrint(gpa, "{s}.{d}.o", .{ opts.mid.assembly, i });
        made = i + 1;
        var compile: std.ArrayList([]const u8) = .empty;
        defer compile.deinit(gpa);
        try compile.appendSlice(gpa, &.{
            Tool.cc.command(),
            try std.fmt.allocPrint(gpa, "-O{s}", .{opts.opt}),
            "-c",
            "-o",
            objects[i],
            source,
        });
        try appendSanitizeLink(gpa, &compile, opts.sanitize);
        if (try runTool(gpa, io, .cc, compile.items)) |f| return f;
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    // `-x ir` rather than trusting the extension, and `-Wno-override-module`
    // because the emitted module names no target while `cc` supplies the
    // host's -- which is the arrangement, not an accident to warn about.
    //
    // The level is stated because it is this invocation's decision, not
    // whatever a host's wrapper injects: the wrapper in the pinned shell
    // already added `-O2` silently, so every golden and every differential
    // ran over optimised output, and a host without that wrapper would
    // otherwise build the one binary no test has ever exercised. The
    // optimiser is safe over this module by construction -- the emitted IR
    // carries no wrap flags, no aliasing metadata and no fast-math, so there
    // is no premise for it to exploit, only the proofs that are absent.
    try argv.appendSlice(gpa, &.{
        Tool.cc.command(),
        try std.fmt.allocPrint(gpa, "-O{s}", .{opts.opt}),
        "-Wno-override-module",
    });

    // `-c` stops after the object, which is the whole of the difference. The
    // runtime is not named either: it is what a program starts through, and
    // nothing here starts.
    if (opts.artifact == .object) try argv.append(gpa, "-c");

    // An object built with C of its own is the module's object and the C's
    // joined into one by a relocatable link, so whoever links the library's
    // object finds every symbol its `extern` declarations name.
    const joins = opts.artifact == .object and objects.len > 0;
    const module_object = if (joins) try std.fmt.allocPrint(gpa, "{s}.module.o", .{opts.mid.assembly}) else opts.out_path;
    defer if (joins) {
        std.Io.Dir.cwd().deleteFile(io, module_object) catch {};
        gpa.free(module_object);
    };

    try argv.appendSlice(gpa, &.{
        "-o",
        module_object,
        "-x",
        "ir",
        opts.mid.assembly,
    });

    if (opts.artifact == .executable) {
        try argv.appendSlice(gpa, &.{ "-x", "none" });
        try argv.appendSlice(gpa, objects);
        try argv.append(gpa, opts.runtime_path);
        // After the runtime and the objects that reference them, which is the
        // order a static archive among the libraries needs.
        for (opts.link) |name| try argv.append(gpa, try std.fmt.allocPrint(gpa, "-l{s}", .{name}));
        try appendSystemLink(gpa, &argv);
    }

    try appendSanitizeLink(gpa, &argv, opts.sanitize);

    if (try runTool(gpa, io, .cc, argv.items)) |f| return f;
    if (!joins) return null;

    var join: std.ArrayList([]const u8) = .empty;
    defer join.deinit(gpa);
    try join.appendSlice(gpa, &.{ Tool.cc.command(), "-r", "-o", opts.out_path, module_object });
    try join.appendSlice(gpa, objects);
    return runTool(gpa, io, .cc, join.items);
}

/// Links a C driver against a module already compiled to an object.
///
/// What a person linking against a published library does, spelled once: the
/// object, the source that calls into it, and the runtime the object reaches
/// for are one link, and the driver is what holds the entry point.
///
/// Here rather than at the caller because this file is what the outcome cache
/// stamps -- the salt reads this module's source, so a change to how any build
/// command is assembled invalidates every recorded outcome. An argv built
/// beside the runner would be a build command the cache could not see change.
pub fn linkDriver(
    gpa: std.mem.Allocator,
    io: std.Io,
    out_path: []const u8,
    driver_path: []const u8,
    object_path: []const u8,
    runtime_path: []const u8,
    sanitize: ?[]const u8,
    /// The libraries the object's manifests name under `link`.
    link: []const []const u8,
) !?Failure {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);

    try argv.appendSlice(gpa, &.{
        Tool.cc.command(),
        "-o",
        out_path,
        driver_path,
        object_path,
    });
    try argv.append(gpa, runtime_path);
    for (link) |name| try argv.append(gpa, try std.fmt.allocPrint(gpa, "-l{s}", .{name}));
    try appendSystemLink(gpa, &argv);

    try appendSanitizeLink(gpa, &argv, sanitize);

    return runTool(gpa, io, .cc, argv.items);
}

/// Names at the link the sanitizer the runtime archive was compiled with.
///
/// Both link commands call this, so an executable and a driver cannot disagree
/// about which support library a sanitized archive needs. Address checking
/// keeps bookkeeping while the program runs, so its support library is linked
/// here. Selecting one also stops the undefined-behaviour checks
/// trapping in place, so they need the routines they report through; naming
/// only the selected sanitizer leaves those unresolved.
fn appendSanitizeLink(
    gpa: std.mem.Allocator,
    argv: *std.ArrayList([]const u8),
    sanitize: ?[]const u8,
) !void {
    const name = sanitize orelse return;
    try argv.append(gpa, try std.fmt.allocPrint(gpa, "-fsanitize={s}", .{name}));
    try argv.append(gpa, "-fsanitize=undefined");
}

test "a sanitized runtime is linked with its sanitizer and the undefined-behaviour runtime" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var argv: std.ArrayList([]const u8) = .empty;
    try appendSanitizeLink(arena.allocator(), &argv, null);
    try testing.expectEqual(@as(usize, 0), argv.items.len);
    try appendSanitizeLink(arena.allocator(), &argv, "address");
    try testing.expectEqual(@as(usize, 2), argv.items.len);
    try testing.expectEqualStrings("-fsanitize=address", argv.items[0]);
    try testing.expectEqualStrings("-fsanitize=undefined", argv.items[1]);
}

/// The system libraries the runtime archive references, which follow it:
/// the math library and the threads a task runs on. macOS supplies both in
/// libSystem, which the host C compiler already links.
fn appendSystemLink(gpa: std.mem.Allocator, argv: *std.ArrayList([]const u8)) !void {
    if (builtin.os.tag == .linux) try argv.appendSlice(gpa, &.{ "-lm", "-lpthread" });
}

/// Holds an emitted module to MLIR's own verifier, without lowering it.
///
/// The suite calls this over every module it records, so an emitter defect
/// that prints an invalid operation is a red case naming the module, rather
/// than a build failure discovered by whoever compiles that program next --
/// `emit-mlir` claims its output is MLIR, and a claim the suite cannot fail
/// is a claim.
pub fn verifyEmitted(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !?Failure {
    return runTool(gpa, io, .mlir_opt, &.{ Tool.mlir_opt.command(), "-o", "/dev/null", path });
}

/// Lowers the emitted module to LLVM IR: the conversion pipeline, then the
/// translation. The converted module uses MLIR's bytecode transport; the
/// emitted module and translated LLVM IR remain text. The front half of a
/// build and assembly dump share this routine.
fn lowerToLlvm(gpa: std.mem.Allocator, io: std.Io, mid: Intermediates) !?Failure {
    if (try runTool(gpa, io, .mlir_opt, &.{
        Tool.mlir_opt.command(),
        "--convert-arith-to-llvm",
        "--convert-cf-to-llvm",
        "--convert-func-to-llvm",
        "--reconcile-unrealized-casts",
        "--emit-bytecode",
        "-o",
        mid.lowered,
        mid.ir,
    })) |f| return f;

    return runTool(gpa, io, .mlir_translate, &.{
        Tool.mlir_translate.command(), "--mlir-to-llvmir", "-o", mid.assembly, mid.lowered,
    });
}

/// Turns emitted MLIR into the assembly a build would ship, for a debugging
/// aid: the same lowering a build runs, then `cc -S` at the same level,
/// stopping before any link -- so no runtime is needed and what lands at
/// `asm_path` is exactly what a build at that level compiles, with no
/// stability promised about its text.
pub fn assemble(
    gpa: std.mem.Allocator,
    io: std.Io,
    mid: Intermediates,
    asm_path: []const u8,
    opt: []const u8,
) !?Failure {
    if (try lowerToLlvm(gpa, io, mid)) |f| return f;

    return runTool(gpa, io, .cc, &.{
        Tool.cc.command(),
        try std.fmt.allocPrint(gpa, "-O{s}", .{opt}),
        "-Wno-override-module",
        "-S",
        "-o",
        asm_path,
        "-x",
        "ir",
        mid.assembly,
    });
}

/// Compiles one C file for its diagnostics alone, answering with what `cc`
/// said where it refused.
///
/// Here with every other invocation of a tool, so the name this runs and the
/// name the outcome cache stamps cannot drift apart. Nothing is produced:
/// the caller's file carries its own assertions, so a refusal *is* the answer
/// and there is no artefact to read back.
pub fn checkC(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !?Failure {
    return runTool(gpa, io, .cc, &.{ Tool.cc.command(), "-fsyntax-only", path });
}

fn runTool(
    gpa: std.mem.Allocator,
    io: std.Io,
    tool: Tool,
    argv: []const []const u8,
) !?Failure {
    const result = std.process.run(gpa, io, .{ .argv = argv }) catch |err| switch (err) {
        error.FileNotFound => return Failure{ .tool = tool, .output = "", .missing = true },
        else => return err,
    };

    switch (result.term) {
        .exited => |code| if (code == 0) {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
            return null;
        },
        else => {},
    }
    // A refusing tool explains itself on whichever stream it prefers, and a
    // user should not have to run it again to hear the one this did not read.
    if (result.stderr.len > 0) {
        gpa.free(result.stdout);
        return Failure{ .tool = tool, .output = result.stderr };
    }
    gpa.free(result.stderr);
    return Failure{ .tool = tool, .output = result.stdout };
}

/// How a built program is named to the thing that will spawn it.
///
/// A bare name is searched for on PATH, so a program built into the current
/// directory would not be found where it was just written. Saying where it is
/// makes the lookup a path rather than a search.
///
/// Here rather than at each spawn, because there are two -- a program `run`
/// executes and a test binary the runner does -- and a second answer is a
/// second chance to get it wrong in only one of them.
pub fn spawnName(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '/') != null) {
        return gpa.dupe(u8, path);
    }
    return std.fmt.allocPrint(gpa, "./{s}", .{path});
}

/// The argument list a built program is started with: its own name first,
/// because that is where a program looks for it, then what the caller hands
/// over. One place decides both how a program is named and where its
/// arguments start.
pub fn programArgv(gpa: std.mem.Allocator, path: []const u8, args: []const []const u8) ![]const []const u8 {
    const argv = try gpa.alloc([]const u8, args.len + 1);
    errdefer gpa.free(argv);
    argv[0] = try spawnName(gpa, path);
    @memcpy(argv[1..], args);
    return argv;
}

/// Replaces this process with the built program. It keeps this process id,
/// terminal and process group, so a signal sent to `linea run` or typed at the
/// terminal reaches the program alone, once, with the disposition the run was
/// started with, and the shell sees how the program ended. Returns only when
/// the program cannot be executed.
pub fn replaceWith(gpa: std.mem.Allocator, io: std.Io, path: []const u8, args: []const []const u8) !noreturn {
    const argv = try programArgv(gpa, path, args);
    defer {
        gpa.free(argv[0]);
        gpa.free(argv);
    }
    return std.process.replace(io, .{ .argv = argv });
}

test "a tool names the program it runs" {
    try testing.expectEqualStrings("cc", Tool.cc.command());
    // Spelled rather than derived: `@tagName` would answer `mlir_opt`, and a
    // program by that name exists nowhere.
    try testing.expectEqualStrings("mlir-opt", Tool.mlir_opt.command());
    try testing.expectEqualStrings("mlir-translate", Tool.mlir_translate.command());
}

test "an override names the runtime instead of searching" {
    if (std.process.Environ.Block != std.process.Environ.PosixBlock) return error.SkipZigTest;
    const named = [_:null]?[*:0]const u8{"LINEA_RUNTIME=/packaged/liblinea_rt.a"};
    for (std.enums.values(Storage)) |storage| {
        const path = (try findRuntime(testing.allocator, testing.io, .{ .block = .{ .slice = &named } }, storage)).?;
        defer testing.allocator.free(path);
        try testing.expectEqualStrings("/packaged/liblinea_rt.a", path);
    }
}

test "a bare output name is executed from where it was written" {
    const cases = .{
        .{ "a.out", "./a.out" },
        .{ "example.lin.run", "./example.lin.run" },
        .{ "/tmp/a.out", "/tmp/a.out" },
        .{ "./a.out", "./a.out" },
        .{ "build/a.out", "build/a.out" },
    };
    inline for (cases) |case| {
        const argv0 = try spawnName(testing.allocator, case[0]);
        defer testing.allocator.free(argv0);
        try testing.expectEqualStrings(case[1], argv0);
    }
}

test "a program's arguments follow its own name" {
    const gpa = testing.allocator;
    const argv = try programArgv(gpa, "program", &.{ "serve", "--port", "0" });
    defer {
        gpa.free(argv[0]);
        gpa.free(argv);
    }
    try testing.expectEqual(@as(usize, 4), argv.len);
    try testing.expectEqualStrings("./program", argv[0]);
    try testing.expectEqualStrings("serve", argv[1]);
    try testing.expectEqualStrings("0", argv[3]);
}

test "the sanitizer a link names is read from the environment" {
    // A sanitized runtime is instrumented, and the routines that
    // instrumentation calls live in the sanitizer's own library. So a link that
    // names the library without naming the sanitizer resolves none of them, and
    // fails -- which is what this reads, one step before the link.
    //
    // Emptiness is absence, because a shell that cannot unset a variable spells
    // it that way, and the runtime path is read the same. Two answers to "is
    // this set" is exactly the drift that gets found here.
    if (std.process.Environ.Block != std.process.Environ.PosixBlock) return error.SkipZigTest;

    const named = [_:null]?[*:0]const u8{"LINEA_SANITIZE=address"};
    try testing.expectEqualStrings("address", findSanitize(.{ .block = .{ .slice = &named } }).?);

    const emptied = [_:null]?[*:0]const u8{"LINEA_SANITIZE="};
    try testing.expectEqual(@as(?[]const u8, null), findSanitize(.{ .block = .{ .slice = &emptied } }));

    const absent = [_:null]?[*:0]const u8{"PATH=/usr/bin"};
    try testing.expectEqual(@as(?[]const u8, null), findSanitize(.{ .block = .{ .slice = &absent } }));
}

test "a missing tool is distinguished from one that refused" {
    const gpa = testing.allocator;
    const missing = (try runTool(gpa, testing.io, .cc, &.{"/no-such-linea-tool/cc"})).?;
    try testing.expect(missing.missing);
    try testing.expectEqualStrings("", missing.output);

    const refused = (try runTool(gpa, testing.io, .cc, &.{ "/bin/sh", "-c", "printf 'undefined symbol' >&2; exit 1" })).?;
    defer gpa.free(refused.output);
    try testing.expect(!refused.missing);
    try testing.expectEqualStrings("undefined symbol", refused.output);
}

test "overlapping runs keep their own directories under the scratch root" {
    const gpa = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);

    var first = try RunOutput.create(gpa, io, root);
    defer first.deinit(gpa);
    defer first.remove(io);
    var second = try RunOutput.create(gpa, io, root);
    defer second.deinit(gpa);
    defer second.remove(io);
    try testing.expect(std.mem.startsWith(u8, first.directory, root));
    try testing.expect(!std.mem.eql(u8, first.directory, second.directory));
    const second_mid = try Intermediates.of(gpa, second.path);
    defer second_mid.deinit(gpa);

    // Pause the second run before linking while the first finishes cleanup.
    for ([_][]const u8{ first.path, second.path, second_mid.ir, second_mid.lowered, second_mid.assembly }) |path| {
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        file.close(io);
    }
    first.remove(io);
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, first.directory, .{}));
    for ([_][]const u8{ second.path, second_mid.ir, second_mid.lowered, second_mid.assembly }) |path| {
        try std.Io.Dir.cwd().access(io, path, .{});
    }
}

test "a target name ends in sixteen hex digits, and a thousand of them are all distinct" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(gpa);
    for (0..1000) |_| {
        const name = try uniqueTarget(arena.allocator(), testing.io, "/tmp", "linea-test");
        try testing.expect(std.mem.startsWith(u8, name, "/tmp/linea-test-"));
        const digits = name["/tmp/linea-test-".len..];
        try testing.expectEqual(@as(usize, 16), digits.len);
        for (digits) |c| try testing.expect(std.ascii.isHex(c));
        try testing.expect(!(try seen.getOrPut(gpa, name)).found_existing);
    }
}

test "a run's directory is deleted when the process that made it ends" {
    const gpa = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);

    // A process that has already ended stands in for this one having ended.
    var ended = try std.process.spawn(io, .{ .argv = &.{ "/bin/sh", "-c", "exit 0" } });
    const ended_pid = ended.id.?;
    _ = try ended.wait(io);

    var output = try RunOutput.createWatching(gpa, io, root, ended_pid);
    defer output.deinit(gpa);
    const file = try std.Io.Dir.cwd().createFile(io, output.path, .{});
    file.close(io);
    // A process that ends for any reason closes its end of the janitor's
    // input; closing it here without deleting anything stands in for that.
    output.janitor.stdin.?.close(io);
    output.janitor.stdin = null;
    _ = try output.janitor.wait(io);
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, output.directory, .{}));
}
