const std = @import("std");
const test_roots = @import("build/test_roots.zig");

// Copy the pinned provider unchanged: Zig forbids sharing its source files
// between the standard-library module and this integer-only entry point.
// Returns the copy of `convert_slow.zig`, the provider's root.
fn decimalProvider(b: *std.Build) std.Build.LazyPath {
    const lib_directory = b.graph.zig_lib_directory.path orelse @panic("Zig library directory is required");
    const files = b.addWriteFiles();
    const directory = b.pathJoin(&.{ lib_directory, "std", "fmt", "parse_float" });
    const root = files.addCopyFile(.{ .cwd_relative = b.pathJoin(&.{ directory, "convert_slow.zig" }) }, "convert_slow.zig");
    for ([_][]const u8{ "decimal.zig", "common.zig", "FloatStream.zig" }) |name| {
        _ = files.addCopyFile(.{ .cwd_relative = b.pathJoin(&.{ directory, name }) }, name);
    }
    _ = files.addCopyFile(b.path("runtime/zig-float-LICENSE"), "LICENSE");
    return root;
}

/// What a test run's binaries are watched by.
///
/// A sanitizer works by instrumenting code as it is compiled -- redzones
/// around a frame, shadow memory beside it -- and it instruments only
/// functions carrying its attribute (`sanitize_address`, `sanitize_thread`).
/// Clang's frontend adds that attribute while it lowers C, so the runtime is
/// instrumented. The generated program reaches `cc` as printed LLVM IR
/// (`-x ir`), so the emitter writes the attribute itself on every function the
/// module defines when the build names a sanitizer (`LINEA_SANITIZE`): a read
/// of freed or out-of-bounds storage in generated Linea code is caught as one
/// in the runtime is. A sanitized run also watches every allocation and free
/// through the intercepted allocator (a double or invalid free), leaks at
/// exit, and crashes.
///
/// `address` also answers for the language's central promise. Its leak
/// checker is the only run-time check for a leak: it runs at every clean exit
/// on Linux, and ownership claims no value is abandoned -- so a corpus
/// program that leaks is not an untidy test, it is ownership and lowering
/// disagreeing about a disposal, caught at run time from outside the compiler
/// entirely. A trapping program aborts past the leak check, which is right:
/// what a trap leaves behind is not a leak, it is a stopped program.
///
/// A `memory` sanitizer ran beside it as an experiment, sound only where every
/// store a value passes through is instrumented. In its run it found one
/// defect, and not in the runtime: the conformance runner handed a spawned
/// program a writable descriptor at 9 that the standard library's spawn path
/// had opened without close-on-exec, which two cases asserting that
/// descriptor is closed then read (fixed in 6050688e). It found nothing in
/// the runtime or in generated code over two and a half months, and it is no
/// longer offered.
///
/// Undefined-behaviour checks are not listed because they are not a choice:
/// the runtime is always compiled with them, trapping alone or reporting
/// when a selected sanitizer needs its routines reachable -- and generated
/// IR cannot take them at all, because UBSan instruments while a frontend
/// lowers source and no frontend runs over printed IR. What stands for it in
/// generated code is the language: every operation is defined or refused,
/// and the trap checks are already printed into the module.
///
/// `thread` watches for data races: tasks run on threads the runtime
/// creates, and every synchronisation between them -- a session's mutex and
/// condition variable, the owning task's call queue, the join, the checking
/// allocator's lock -- is in the runtime's C. Generated code is instrumented
/// as well, so a race between two tasks' Linea code that the compiler
/// accepted is reported at run time: the language refuses such a program
/// ([O-Cross], [O-Borrow]), and this run is what catches the compiler when it
/// does not. The two sanitizers cannot share a process, so each is its own
/// run. A type sanitizer
/// stays absent by decision rather than omission: it checks the promises
/// TBAA metadata makes, and this compiler deliberately emits none -- proofs
/// are handed to the optimiser, never premises. The data-flow instrumentation
/// is a taint framework a program must call into, not a detector to run a
/// corpus under.
///
/// None of this works on Darwin, which is where the compiler is developed:
/// the runtime hangs before reaching `main` on a C program that does nothing
/// but return a constant, so the fault is under the toolchain rather than in
/// anything generated. It is selected here and exercised on Linux.
const Sanitize = enum {
    none,
    address,
    thread,

    fn flag(self: Sanitize) ?[]const u8 {
        return switch (self) {
            .none => null,
            else => @tagName(self),
        };
    }
};

/// The library's files, as a Zig source listing them.
///
/// `@embedFile` takes a path it can see at compile time, so a library that
/// grows by a directory rather than by an edit needs the list generated. The
/// sources are copied beside the generated file so that each `@embedFile` is
/// an ordinary relative path -- which is also what makes the compiler rebuild
/// when one of them changes.
fn libraryManifest(b: *std.Build) std.Build.LazyPath {
    const wf = b.addWriteFiles();

    var text: std.ArrayList(u8) = .empty;
    text.appendSlice(b.allocator,
        \\pub const File = struct { path: []const u8, text: []const u8 };
        \\
        \\pub const files = [_]File{
        \\
    ) catch @panic("OOM");

    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, "std", .{ .iterate = true }) catch
        @panic("the standard library is missing");
    defer dir.close(io);

    var walker = dir.walk(b.allocator) catch @panic("OOM");
    defer walker.deinit();

    // Sorted, so the generated file is the same however the directory is read
    // and a build does not churn on filesystem order.
    //
    // Nothing here is freed: `b.allocator` is the build graph's arena, which
    // lives as long as the process that walks this directory once. Freeing a
    // path would return it to an allocator that is about to be discarded
    // whole.
    var found: std.ArrayList([]const u8) = .empty;
    while (walker.next(io) catch @panic("cannot read the standard library")) |entry| {
        if (entry.kind != .file) continue;
        // Every file but the library's documentation travels with the
        // sources: the manifest says this root is the library named `std`, for
        // the copy compiled in as for the directory, and any other file is one
        // a library module may `embed`, which the copy must hold to read.
        if (std.mem.endsWith(u8, entry.basename, ".md")) continue;
        found.append(b.allocator, b.dupe(entry.path)) catch @panic("OOM");
    }
    std.mem.sort([]const u8, found.items, {}, lessThanSlice);

    for (found.items) |rel| {
        // The loader reads a module out of a directory, so the path it is
        // given has to be the one the library is laid out under.
        _ = wf.addCopyFile(b.path(b.fmt("std/{s}", .{rel})), rel);

        // Escaped, because this goes into a Zig string literal and a path is
        // whatever the filesystem allows -- a quote or a backslash in one
        // would end the literal early and the generated file would not parse.
        const quoted = zigString(b, rel);
        text.appendSlice(b.allocator, b.fmt(
            "    .{{ .path = \"std/{s}\", .text = @embedFile(\"{s}\") }},\n",
            .{ quoted, quoted },
        )) catch @panic("OOM");
    }

    text.appendSlice(b.allocator, "};\n") catch @panic("OOM");
    return wf.add("manifest.zig", text.items);
}

/// A path as the body of a Zig string literal.
fn zigString(b: *std.Build, s: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |ch| {
        switch (ch) {
            '"', '\\' => out.append(b.allocator, '\\') catch @panic("OOM"),
            else => {},
        }
        out.append(b.allocator, ch) catch @panic("OOM");
    }
    return out.items;
}

/// Every source the runtime is built from, as a Zig source listing them: its
/// C headers and files and its Zig files, without the tests. Walked rather
/// than listed, so a new runtime file is read by the test that holds the
/// runtime's signature table to it without anybody adding it here.
fn runtimeSources(b: *std.Build) std.Build.LazyPath {
    const wf = b.addWriteFiles();
    var text: std.ArrayList(u8) = .empty;
    text.appendSlice(b.allocator,
        \\pub const File = struct { path: []const u8, text: []const u8 };
        \\
        \\pub const files = [_]File{
        \\
    ) catch @panic("OOM");

    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, "runtime", .{ .iterate = true }) catch
        @panic("the runtime is missing");
    defer dir.close(io);
    var iterator = dir.iterate();
    var found: std.ArrayList([]const u8) = .empty;
    while (iterator.next(io) catch @panic("cannot read the runtime")) |entry| {
        if (entry.kind != .file) continue;
        const readable = std.mem.endsWith(u8, entry.name, ".h") or std.mem.endsWith(u8, entry.name, ".c") or std.mem.endsWith(u8, entry.name, ".zig");
        if (!readable or std.mem.endsWith(u8, entry.name, "_test.c")) continue;
        found.append(b.allocator, b.dupe(entry.name)) catch @panic("OOM");
    }
    std.mem.sort([]const u8, found.items, {}, lessThanSlice);
    for (found.items) |name| {
        _ = wf.addCopyFile(b.path(b.fmt("runtime/{s}", .{name})), name);
        const quoted = zigString(b, name);
        text.appendSlice(b.allocator, b.fmt(
            "    .{{ .path = \"runtime/{s}\", .text = @embedFile(\"{s}\") }},\n",
            .{ quoted, quoted },
        )) catch @panic("OOM");
    }
    text.appendSlice(b.allocator, "};\n") catch @panic("OOM");
    return wf.add("runtime_sources.zig", text.items);
}

/// One runtime source compiled to the object an archive holds.
/// The native tests of the runtime's C: each is a binary built from C files
/// and run.
const NativeTests = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sanitize: Sanitize,
    install_step: ?*std.Build.Step = null,

    /// One C file of a test and the flags it is compiled with.
    const Source = struct {
        file: []const u8,
        flags: []const []const u8,
        // Runtime implementation files this fixture includes to interpose calls.
        includes: []const []const u8 = &.{},
    };

    /// Builds the test `name` from `sources` and runs it as part of `step`.
    /// With no sanitizer selected, Zig compiles and links it. A sanitizer's
    /// runtime is one only the C toolchain links, so a sanitized test is
    /// compiled and linked by `cc`, as a sanitized program is, with each file
    /// compiled alone because each takes its own flags. A report stops the
    /// test (`-fno-sanitize-recover=all`): an undefined-behaviour check that
    /// printed and carried on would leave the run's status clean.
    fn add(self: NativeTests, step: *std.Build.Step, name: []const u8, sources: []const Source) void {
        const b = self.b;
        const linux = self.target.result.os.tag == .linux;
        var linked: std.ArrayList(Source) = .empty;
        linked.appendSlice(b.allocator, sources) catch @panic("OOM");
        var has_execution = false;
        var execution_flags = sources[0].flags;
        for (sources) |input| {
            if (std.mem.eql(u8, input.file, "runtime/loop.c")) execution_flags = input.flags;
            if (std.mem.eql(u8, input.file, "runtime/loop.c") or std.mem.eql(u8, input.file, "runtime/park.c")) has_execution = true;
        }
        if (has_execution) for ([_][]const u8{ "runtime/fiber.c", "runtime/completion.c", "runtime/context.c", "runtime/foreign.c", "runtime/park.c", "runtime/loop.c", "runtime/linea_rt.c" }) |file| {
            var found = false;
            for (linked.items) |input| {
                if (std.mem.eql(u8, input.file, file)) found = true;
                for (input.includes) |included| if (std.mem.eql(u8, included, file)) {
                    found = true;
                };
            }
            if (!found) linked.append(b.allocator, .{ .file = file, .flags = execution_flags }) catch @panic("OOM");
        };
        if (self.sanitize.flag()) |sanitizer| {
            const san_arg = b.fmt("-fsanitize={s}", .{sanitizer});
            const link = b.addSystemCommand(&.{ "cc", san_arg, "-fsanitize=undefined", "-fno-sanitize-recover=all", "-g" });
            for (linked.items) |input| {
                const compile = b.addSystemCommand(&.{ "cc", "-c", "-g", "-O1", san_arg, "-fsanitize=undefined", "-fno-sanitize-recover=all" });
                compile.addPrefixedDirectoryArg("-I", b.path("runtime"));
                compile.addArgs(input.flags);
                compile.addFileArg(b.path(input.file));
                compile.addArg("-o");
                link.addFileArg(compile.addOutputFileArg(b.fmt("{s}.o", .{std.fs.path.stem(input.file)})));
            }
            link.addArg("-o");
            const binary = link.addOutputFileArg(name);
            if (linux) link.addArgs(&.{ "-lm", "-lpthread" });
            const run = std.Build.Step.Run.create(b, b.fmt("run {s}", .{name}));
            run.addFileArg(binary);
            // The runtime answers a request the C allocator refuses with null,
            // and the tests hold it to that; a sanitizer's allocator stops the
            // program instead unless told to return null as `calloc` does.
            run.setEnvironmentVariable(
                if (self.sanitize == .thread) "TSAN_OPTIONS" else "ASAN_OPTIONS",
                "allocator_may_return_null=1",
            );
            step.dependOn(&run.step);
            return;
        }
        const module = b.createModule(.{ .target = self.target, .optimize = self.optimize, .link_libc = true });
        module.addIncludePath(b.path("runtime"));
        for (linked.items) |input| module.addCSourceFile(.{ .file = b.path(input.file), .flags = input.flags });
        if (linux) module.linkSystemLibrary("m", .{});
        const executable = b.addExecutable(.{ .name = name, .root_module = module });
        if (self.install_step) |install_step| {
            install_step.dependOn(&b.addInstallArtifact(executable, .{}).step);
        }
        step.dependOn(&b.addRunArtifact(executable).step);
    }
};

fn runtimeObject(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    name: []const u8,
    file: std.Build.LazyPath,
    flags: []const []const u8,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = .ReleaseSmall,
        .link_libc = true,
    });
    module.addSystemIncludePath(.{ .cwd_relative = b.graph.zig_lib_directory.path orelse "." });
    module.addCSourceFile(.{ .file = file, .flags = flags });
    return b.addObject(.{ .name = name, .root_module = module });
}

/// The target with the CPU model of the build machine replaced by the baseline
/// model of its architecture. A target that names its CPU is left alone.
fn baselineCpu(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.ResolvedTarget {
    var query = target.query;
    if (query.isNativeCpu()) query.cpu_model = .baseline;
    return b.resolveTargetQuery(query);
}

fn lessThanSlice(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// What the gates below read out of the project's own text.
///
/// A module rather than functions here, because `zig build` runs no `test`
/// block in this file: a heuristic deciding whether a build fails is worth
/// cases, and only code outside a build script can have them.
const source = @import("build/source.zig");

/// The runtime archive and symbols an installed compiler goes looking for.
const runtime_symbols = @import("src/support/runtime_symbols.zig");
const toolchain = @import("src/driver/toolchain.zig");
const tree_sitter_dir = "editor-support/tree-sitter-linea";

/// Tracy's client, compiled from its own source rather than through a binding.
/// A binding pins the client's version, and a client whose protocol does not
/// match the installed profiler refuses the connection. Here the version is
/// this dependency's, chosen to match what the profiler on the machine is.
///
/// Every module that compiles `src/` needs it, not just the runner: the zones
/// sit in the passes themselves, so any binary that typechecks a program
/// references the client's symbols and fails to link without it.
/// The value every step running the compiler or the conformance runner gives
/// `LINEA_CACHE_DIR`; empty turns the cache off. Set once by `build`.
var library_cache_dir: []const u8 = "";

/// Points `run` at the build's checked-library cache.
fn shareLibraryCache(run: *std.Build.Step.Run) void {
    run.setEnvironmentVariable("LINEA_CACHE_DIR", library_cache_dir);
}

fn linkTracyClient(b: *std.Build, m: *std.Build.Module, profiling: bool) void {
    if (!profiling) return;
    const tracy_src = b.dependency("tracy_src", .{});
    m.addCSourceFile(.{
        .file = tracy_src.path("public/TracyClient.cpp"),
        .flags = &.{"-DTRACY_ENABLE"},
    });
    m.addIncludePath(tracy_src.path("public"));
    m.link_libcpp = true;
}

/// The files the compiler embeds, given to a module that compiles it.
///
/// Every binary built from `src/` needs all five: a test reads the runtime's
/// source to check the two agree about traps, a diagnostic's code is an index
/// into the semantics, the standard library travels inside the binary, the
/// fuzz corpus is replayed on every run, and the language server's protocol
/// types enable IDE support. Every test scope receives the same compiler
/// inputs even when it selects only one part of the test universe.
fn addCompilerAssets(
    m: *std.Build.Module,
    runtime_source: std.Build.LazyPath,
    semantics: std.Build.LazyPath,
    library: std.Build.LazyPath,
    corpus: *std.Build.Module,
    lsp_kit: *std.Build.Dependency,
    options: *std.Build.Step.Options,
) void {
    m.addOptions("build_options", options);
    m.addAnonymousImport("runtime_source", .{ .root_source_file = runtime_source });
    m.addAnonymousImport("semantics", .{ .root_source_file = semantics });
    m.addAnonymousImport("library_manifest", .{ .root_source_file = library });
    m.addImport("fuzz_corpus", corpus);
    m.addImport("lsp", lsp_kit.module("lsp"));
}

/// The generated and hand-written editor descriptions conformance tests read.
fn addConformanceAssets(b: *std.Build, m: *std.Build.Module) void {
    m.addAnonymousImport("grammar_json", .{
        .root_source_file = b.path(tree_sitter_dir ++ "/src/grammar.json"),
    });
    m.addAnonymousImport("highlights_scm", .{
        .root_source_file = b.path(tree_sitter_dir ++ "/queries/highlights.scm"),
    });
    m.addAnonymousImport("sublime_syntax", .{
        .root_source_file = b.path("editor-support/sublime-linea/linea.sublime-syntax"),
    });
}

/// Whether CI runs every sanitizer this build offers.
///
/// `Sanitize` is the only executable statement of the set: `flag()` derives
/// the `-fsanitize=` name from the tag, and the tag salts the conformance
/// outcome cache. The CI workflow and the README are text beside it, and the
/// enum's own doc says these "are selected here and exercised on Linux" --
/// which is a claim about a file this one has no other reason to read.
///
/// None of them work on Darwin, where the compiler is developed, so adding a
/// sanitizer and not adding it to the workflow means it is never run anywhere
/// and nothing says so.
fn checkCiRunsEverySanitizer(b: *std.Build) void {
    const io = b.graph.io;
    const workflow = b.build_root.handle.readFileAlloc(
        io,
        ".github/workflows/ci.yml",
        b.allocator,
        .limited(1 << 20),
    ) catch @panic("the CI workflow is missing or unreadable");

    const matrix_key = "sanitizer: [";
    const matrix_start = std.mem.indexOf(u8, workflow, matrix_key) orelse
        @panic("the CI workflow names no sanitizer matrix");
    const matrix_rest = workflow[matrix_start + matrix_key.len ..];
    const matrix = matrix_rest[0 .. std.mem.indexOfScalar(u8, matrix_rest, ']') orelse
        @panic("the CI sanitizer matrix is unterminated")];

    var missing = false;
    for (std.enums.values(Sanitize)) |sanitizer| {
        // `.none` is the default and names no runtime to link, so it is not a
        // matrix entry.
        const name = sanitizer.flag() orelse continue;
        var entries = std.mem.splitSequence(u8, matrix, ", ");
        const listed = while (entries.next()) |entry| {
            if (std.mem.eql(u8, std.mem.trim(u8, entry, " "), name)) break true;
        } else false;
        if (listed) continue;
        std.debug.print("sanitize: CI does not run `{s}`\n", .{name});
        missing = true;
    }
    if (missing) @panic("a sanitizer this build offers is never run");
}

/// Whether the editor config indents by what the formatter indents by.
///
/// ADR 0038 refuses to make the width configurable, so there is one number by
/// decision -- and it was written twice, once in the formatter and once in a
/// `.helix/languages.toml` that also sets `auto-format = true` and points at
/// `linea fmt`. So the editor indents a partial line by its own number and the
/// formatter rewrites the file by the other, and the disagreement shows up as
/// the editor undoing itself while you type.
///
/// Read from the sources rather than shared between them: an editor config is
/// not a thing the compiler can import, which is the whole reason the number
/// is written twice.
fn checkTheEditorIndentsByWhatTheFormatterDoes(b: *std.Build) void {
    const io = b.graph.io;
    const fmt_source = b.build_root.handle.readFileAlloc(
        io,
        "src/fmt/fmt.zig",
        b.allocator,
        .limited(1 << 22),
    ) catch @panic("the formatter is missing");

    const spelled_width = source.between(fmt_source, "const indent_width = ", ";") orelse
        @panic("the formatter no longer states an indent width");
    const width = std.fmt.parseInt(usize, spelled_width, 10) catch
        @panic("the formatter's indent width is not a number");

    const config = b.build_root.handle.readFileAlloc(
        io,
        ".helix/languages.toml",
        b.allocator,
        .limited(1 << 20),
    ) catch return;

    const spelled = source.between(config, "unit = \"", "\"") orelse
        @panic("the editor config states no indent unit");

    if (spelled.len == width and std.mem.allEqual(u8, spelled, ' ')) return;
    std.debug.print(
        "indent: the formatter writes {d} spaces and .helix/languages.toml says \"{s}\"\n",
        .{ width, spelled },
    );
    @panic("the editor and the formatter disagree about indentation");
}

/// Whether the prelude publishes the names the compiler asks it for, and
/// nothing beyond them but the documented core vocabulary.
///
/// A name the syntax requires is one the compiler looks up by prelude
/// identity -- a literal has a type, `?` answers with one, `a[i]` is a call on
/// a trait. Every such lookup must find a published name, or a program is
/// refused for a name it never wrote.
///
/// Every other published name must be listed in the core-vocabulary table of
/// the semantics document, the one list recording which names the prelude
/// adds by decision rather than by syntax. A `pub use` added to the manifest
/// without a row there fails here, so the prelude cannot grow one convenience
/// at a time without the decision being written down. The table is held to
/// the manifest in the other direction too: a row naming nothing the prelude
/// publishes, or a name the compiler also looks up, is a table that lies.
///
/// Read out of the sources rather than shared between them. The compiler
/// cannot import the library's text -- the library is Linea and the lookup is
/// Zig -- so the three say it separately, which is exactly the shape that
/// drifts.
fn checkThePreludeIsDocumented(b: *std.Build) void {
    const io = b.graph.io;
    const gpa = b.allocator;

    const read = struct {
        fn file(bb: *std.Build, i: anytype, path: []const u8) []const u8 {
            return bb.build_root.handle.readFileAlloc(i, path, bb.allocator, .limited(1 << 22)) catch
                std.debug.panic("the prelude gate cannot read {s}", .{path});
        }
    }.file;

    // What the compiler asks the prelude for: every name a lookup is written
    // with, and every name a row of the traits it implements itself spells.
    var wanted: std.StringArrayHashMapUnmanaged(void) = .empty;
    const checker = read(b, io, "src/sema/typecheck.zig");
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, checker, at, "preludeDecl(")) |found| {
        at = found + "preludeDecl(".len;
        // A call handed a variable names nothing here; what reaches it is a row
        // below, which is read as a row.
        const name = source.quotedOnLine(checker, at) orelse continue;
        wanted.put(gpa, name, {}) catch @panic("out of memory");
    }

    const resolver = read(b, io, "src/sema/resolve.zig");
    const table = "const ambient_array_traits = ";
    const opened = std.mem.indexOf(u8, resolver, table) orelse
        @panic("the resolver no longer states which traits it implements itself");
    for (source.quotedIn(gpa, source.indentedUnder(resolver, opened + table.len))) |name| {
        wanted.put(gpa, name, {}) catch @panic("out of memory");
    }

    // The declarations tuple syntax names, which the resolver finds by
    // identity and every later pass reads from it.
    const tuples = "const tuple_names = ";
    const tuples_opened = std.mem.indexOf(u8, resolver, tuples) orelse
        @panic("the resolver no longer states which declarations tuple syntax names");
    for (source.quotedIn(gpa, source.indentedUnder(resolver, tuples_opened + tuples.len))) |name| {
        wanted.put(gpa, name, {}) catch @panic("out of memory");
    }

    if (wanted.count() == 0) @panic("the prelude gate found no lookup to read");

    // What the prelude publishes. A re-export names the module it came from,
    // and the name is what a program writes.
    var published: std.StringArrayHashMapUnmanaged(void) = .empty;
    const prelude = read(b, io, "std/std.lin");
    var lines = std.mem.splitScalar(u8, prelude, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "pub use ")) continue;
        const path = std.mem.trim(u8, line["pub use ".len..], " \r");
        const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse continue;
        published.put(gpa, path[dot + 1 ..], {}) catch @panic("out of memory");
    }

    // What the semantics document says the prelude adds beyond the syntax.
    const semantics = read(b, io, "docs/linea-semantics.md");
    const vocabulary = source.tableNamesAfter(gpa, semantics, "**The core vocabulary**");
    if (vocabulary.len == 0) @panic("the prelude gate found no core-vocabulary table in docs/linea-semantics.md");
    var documented: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (vocabulary) |name| documented.put(gpa, name, {}) catch @panic("out of memory");

    var failed = false;
    for (wanted.keys()) |name| {
        if (published.contains(name)) continue;
        std.debug.print(
            "prelude: the compiler looks up `{s}` and std/std.lin does not publish it\n",
            .{name},
        );
        failed = true;
    }
    for (published.keys()) |name| {
        if (wanted.contains(name) or documented.contains(name)) continue;
        std.debug.print(
            "prelude: std/std.lin publishes `{s}`, which no syntax requires and the " ++
                "core-vocabulary table in docs/linea-semantics.md does not list\n",
            .{name},
        );
        failed = true;
    }
    for (documented.keys()) |name| {
        if (!published.contains(name)) {
            std.debug.print(
                "prelude: docs/linea-semantics.md lists `{s}` as core vocabulary and std/std.lin does not publish it\n",
                .{name},
            );
            failed = true;
        }
        if (wanted.contains(name)) {
            std.debug.print(
                "prelude: docs/linea-semantics.md lists `{s}` as core vocabulary and the compiler looks it up for syntax\n",
                .{name},
            );
            failed = true;
        }
    }
    if (failed) @panic("the prelude and its documented vocabulary disagree");
}

/// Whether the runtime's trap messages are the compiler's trap kinds.
///
/// The two sides of a trap agree on a small integer: generated code passes
/// `@intFromEnum` of a `TrapKind`, and the runtime indexes `what[]` with it.
/// The number is the whole interface, so the tables must have the same length
/// in the same order saying the same words -- and nothing checks that but
/// this, because the compiler is Zig and the runtime is C, so neither can
/// read the other's table at compile time. A kind appended on one side only
/// is a trap reporting the wrong message, or reading past the table.
///
/// The kind's message is taken from `describe`'s arms by name, then ordered
/// by the enum's own member order: the integer is the member's position, not
/// the arm's, and a switch reordered without renumbering anything would
/// otherwise read as drift.
///
/// Deliberately coupled to the declaration's shape -- bare members before the
/// first `pub fn`, one arm per line. Reshaping `TrapKind` means reshaping
/// this gate, and the gate says so: a shape it cannot read is a panic naming
/// what moved, never a silent pass.
fn checkTheRuntimeSpeaksEveryTrapKind(b: *std.Build) void {
    const io = b.graph.io;
    const gpa = b.allocator;
    const read = struct {
        fn file(bb: *std.Build, i: anytype, path: []const u8) []const u8 {
            return bb.build_root.handle.readFileAlloc(i, path, bb.allocator, .limited(1 << 22)) catch
                std.debug.panic("the trap gate cannot read {s}", .{path});
        }
    }.file;

    const mir = read(b, io, "src/mir/mir.zig");
    const opened = std.mem.indexOf(u8, mir, "pub const TrapKind = enum(u8) {") orelse
        @panic("src/mir/mir.zig no longer declares TrapKind where the trap gate reads it");
    const body = source.indentedUnder(mir, opened);

    // The members, in declaration order: a bare name ending in a comma,
    // before the first function the enum declares.
    var members: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \r");
        if (std.mem.startsWith(u8, t, "pub fn")) break;
        if (t.len < 2 or t[t.len - 1] != ',' or std.mem.startsWith(u8, t, "//")) continue;
        const name = t[0 .. t.len - 1];
        var word = name.len > 0;
        for (name) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') word = false;
        }
        if (!word) continue;
        members.append(gpa, name) catch @panic("out of memory");
    }
    if (members.items.len == 0) @panic("the trap gate read no TrapKind members");

    // Each member's message, found by the arm that names it.
    var failed = false;
    var messages: std.ArrayList([]const u8) = .empty;
    for (members.items) |name| {
        const arm = std.fmt.allocPrint(gpa, ".{s} => ", .{name}) catch @panic("out of memory");
        const at = std.mem.indexOf(u8, body, arm) orelse {
            std.debug.print("trap: `describe` has no arm for `{s}`\n", .{name});
            failed = true;
            continue;
        };
        const said = source.quotedOnLine(body, at + arm.len) orelse {
            std.debug.print("trap: the arm for `{s}` names no message\n", .{name});
            failed = true;
            continue;
        };
        messages.append(gpa, said) catch @panic("out of memory");
    }

    const rt = read(b, io, "runtime/linea_rt.c");
    const table = std.mem.indexOf(u8, rt, "static const char *const what[] = {") orelse
        @panic("runtime/linea_rt.c no longer declares what[] where the trap gate reads it");
    const end = std.mem.indexOfPos(u8, rt, table, "};") orelse
        @panic("the trap gate cannot find the end of what[]");
    const spoken = source.quotedIn(gpa, rt[table..end]);

    if (spoken.len != messages.items.len) {
        std.debug.print(
            "trap: the compiler numbers {d} kinds and the runtime speaks {d}\n",
            .{ messages.items.len, spoken.len },
        );
        failed = true;
    }
    for (messages.items, 0..) |said, i| {
        if (i >= spoken.len) break;
        if (std.mem.eql(u8, said, spoken[i])) continue;
        std.debug.print(
            "trap: kind {d} is \"{s}\" to the compiler and \"{s}\" to the runtime\n",
            .{ i, said, spoken[i] },
        );
        failed = true;
    }
    if (failed) @panic("the runtime does not speak the compiler's trap kinds");
}

/// Whether std reads the runtime's I/O category numbers as the runtime
/// numbers them.
///
/// `linea_io_category` returns a small integer and `IoError.from_os` maps it to
/// a member by retyped literals, with a fallback arm for every number it does
/// not know. Std's enum has members the runtime never produces, so the ordinal
/// cannot stand in, and nothing else holds the two together: a category added
/// to the runtime and mapped nowhere reads as `Other` with no diagnostic.
fn checkTheRuntimeSpeaksEveryIoCategory(b: *std.Build) void {
    const io = b.graph.io;
    const header = b.build_root.handle.readFileAlloc(io, "runtime/io.h", b.allocator, .limited(1 << 22)) catch
        @panic("the io category gate cannot read runtime/io.h");
    const std_text = b.build_root.handle.readFileAlloc(io, "std/io/core/error.lin", b.allocator, .limited(1 << 22)) catch
        @panic("the io category gate cannot read std/io/core/error.lin");
    const found = source.ioCategoryDisagreements(b.allocator, header, std_text);
    for (found) |line| std.debug.print("io category: {s}\n", .{line});
    if (found.len != 0) @panic("std and the runtime disagree about the I/O categories");
}

/// Whether `docs/learn/errors.md` indexes exactly the diagnostics the guide
/// shows.
///
/// The page restates what the chapters paste -- every code, where it first
/// appears, and the section of the semantics that defines its rule -- so the
/// two drift the moment a chapter gains or loses an error. The page is computed
/// here from the chapters the guide's index links to and from the semantics,
/// and a page that differs is refused with the page it should be, which is then
/// pasted in by hand. A code the guide shows or names that no rule defines is
/// refused on its own, since no page could link it.
fn checkTheGuideIndexesItsErrors(b: *std.Build) void {
    const io = b.graph.io;
    const gpa = b.allocator;
    const read = struct {
        fn file(bb: *std.Build, i: anytype, path: []const u8) []const u8 {
            return bb.build_root.handle.readFileAlloc(i, path, bb.allocator, .limited(1 << 22)) catch
                std.debug.panic("the guide's error-index gate cannot read {s}", .{path});
        }
    }.file;

    const listed = source.guideChapters(gpa, read(b, io, "docs/learn/README.md"));
    if (listed.len == 0) @panic("the guide's error-index gate found no chapter in docs/learn/README.md");
    const chapters = gpa.alloc(source.GuideChapter, listed.len) catch @panic("out of memory");
    for (listed, chapters) |chapter, *filled| {
        filled.* = chapter;
        filled.text = read(b, io, b.pathJoin(&.{ "docs/learn", chapter.file }));
    }
    const index = source.guideErrorIndex(gpa, chapters, read(b, io, "docs/linea-semantics.md"));
    for (index.undefined_codes) |code| {
        std.debug.print("guide: the chapters show or name `{s}`, and no rule in docs/linea-semantics.md defines it\n", .{code});
    }
    for (index.unclassified) |bare| {
        std.debug.print(
            "guide: {s} writes `{s}` bare in a heading or a table row, where it cannot be told from a word; " ++
                "write it `[{s}]` or `` `{s}` ``: {s}\n",
            .{ bare.file, bare.code, bare.code, bare.code, bare.line },
        );
    }
    if (index.undefined_codes.len > 0) @panic("the guide names a diagnostic the semantics does not define");
    if (index.unclassified.len > 0) @panic("the guide writes a rule code the gate cannot classify");

    const page = read(b, io, "docs/learn/errors.md");
    const difference = source.firstDifference(index.page, page) orelse return;
    std.debug.print(
        "guide: docs/learn/errors.md does not index the errors the chapters show. Line {d} should read\n" ++
            "  {s}\nand reads\n  {s}\nThe whole page should read:\n\n{s}\n",
        .{ difference.number, difference.expected, difference.found, index.page },
    );
    @panic("docs/learn/errors.md is stale");
}

/// Whether the decision index agrees with itself about what refines what.
///
/// The index restates a standing the record owns, so the two can drift; the
/// records are append-only and the index is edited, which decides which way
/// they drift. A record's own `Status:` line is prose and its wording is not
/// worth matching, but the relations the index states are mechanical -- and a
/// relation has a direction, so every one of them is written twice by
/// construction and the two spellings must name each other.
///
/// This is what a bare eye does not do: a row saying "refined by 0042" reads
/// exactly like a row saying "refined by 0046", and the wrong one sat in the
/// index for a milestone naming a superseded record about parser nesting.
fn checkTheDecisionIndexIsReciprocal(b: *std.Build) void {
    const io = b.graph.io;
    const text = b.build_root.handle.readFileAlloc(
        io,
        "docs/adr/README.md",
        b.allocator,
        .limited(1 << 22),
    ) catch @panic("the decision index is missing");

    const rows = source.indexRows(b.allocator, text);

    // Before a single relation is resolved. Resolution takes the first row
    // carrying a number, so under a duplicate every complaint below is about
    // whichever record sorted earlier rather than the one that stated the
    // relation -- the gate stays red and stops naming what is wrong.
    if (source.numberClaimedTwice(b.allocator, rows)) |number| {
        std.debug.print(
            "decisions: {s} names two records, so a reference to it has two referents\n",
            .{number},
        );
        @panic("a decision number names two records");
    }

    var complaints: std.ArrayList([]const u8) = .empty;
    for (rows) |row| {
        var at: usize = 0;
        while (source.findRelation(row.status, at)) |found| {
            at = found.after;

            // Every record the relation names, not the first: "extends 0029
            // and 0055" states one relation about two records, and each of
            // them has to state it back.
            var targets: source.Numbers = .{ .rest = found.targets };
            while (targets.next()) |target| {
                const other = for (rows) |r| {
                    if (std.mem.eql(u8, r.number, target)) break r;
                } else {
                    complaints.append(b.allocator, b.fmt(
                        "{s} is {s} {s}, which the index does not list",
                        .{ row.number, found.says, target },
                    )) catch @panic("OOM");
                    continue;
                };

                if (!source.statesRelation(other.status, found.back, row.number)) {
                    complaints.append(b.allocator, b.fmt(
                        "{s} says \"{s} {s}\", but {s} does not say \"{s} {s}\" -- it says \"{s}\"",
                        .{ row.number, found.says, target, target, found.back, row.number, other.status },
                    )) catch @panic("OOM");
                }
            }
        }
    }

    if (complaints.items.len == 0) return;
    std.debug.print("decisions: the index disagrees with itself\n", .{});
    for (complaints.items) |c| std.debug.print("  {s}\n", .{c});
    @panic("the decision index is not reciprocal");
}

/// Whether every property the conformance runner reports accounts for what it
/// counted.
///
/// A property that counts on its own is the defect this project makes most
/// often, and it is invisible from the outside: a check with a counter beside
/// it and a line reporting the number reads exactly like one asked of the whole
/// corpus, and the number it prints is true. What is missing is the population
/// -- so a property asked of two programs while its line says the corpus keeps
/// saying so, and every one of them was found by a reading rather than by a
/// run.
///
/// The runner's answer to that is `Property`: a member carries a population, is
/// counted through `tally` onto one of the two sides, and the loop that reports
/// the counts checks `accountsFor` -- `checked + passed_over` against the
/// population, by equality. This holds the runner to using it: a member nothing
/// tallies is counted somewhere else or not at all, and either way the printed
/// line answers to nothing.
///
/// One pass over the runner's text per member, and the runner is one file.
///
/// What this establishes is that the accounting is *called*, and not that the
/// population it is called with is the right one: a property can name a
/// population smaller than what it claims and account for it perfectly. That
/// still rests on someone reading `populationIn`. So does a count kept outside
/// the enum entirely -- a counter of its own with a `conformance:` line beside
/// it is what this gate wants a property written as instead, and it cannot tell
/// one from an informational line.
fn checkEveryPropertyAccountsForItself(b: *std.Build) void {
    const io = b.graph.io;
    const runner = b.build_root.handle.readFileAlloc(
        io,
        "src/conformance_main.zig",
        b.allocator,
        .limited(1 << 22),
    ) catch @panic("the conformance runner is missing");

    const accounting = source.accountingOf(b.allocator, runner, "Property", "tally");
    // Nothing declared is this gate reading a file it no longer understands.
    // Silence is what it exists to stop, so it does not answer with its own.
    if (accounting.declared == 0) @panic("the conformance runner declares no properties");

    var failed = false;
    for (accounting.uncounted) |property| {
        std.debug.print(
            "property: nothing tallies `{s}`, so the run accounts for nothing it counted\n",
            .{property},
        );
        failed = true;
    }
    if (!source.reportsAndAccounts(b.allocator, runner, "Property", "conformance:", "accountsFor")) {
        std.debug.print(
            "property: the run reports what each property counted and holds it to no population\n",
            .{},
        );
        failed = true;
    }
    if (failed) @panic("a property counts without accounting for what it counted");
}

/// What a directory under `src/` is, and therefore what it may import.
///
/// A pass may not import the driver: the driver imports every pass, so an
/// import back closes a cycle. A harness drives the compiler from outside and
/// may -- the conformance runner has to build a module the way the compiler
/// does, and asking the driver is the alternative to keeping a second copy of
/// its pass order.
///
/// Every directory is named. A new one is a build failure until someone says
/// which it is, because there is no safe default: calling it a pass exempts a
/// harness from nothing and calls a legitimate import a violation, while
/// calling it a harness lets a real pass import the driver unremarked -- and
/// that one is silent, which is the direction this gate exists to stop.
///
/// One import runs the other way and is not checked here: `mir/verify.zig`
/// reaches the generator in `conformance/` for its fuzz target, which needs
/// programs that are well-typed by construction. Zig has no test-only import,
/// and the target has to sit in the binary a fuzzing run keeps -- which is the
/// unit tests rather than the conformance runner's own.
const Layer = enum { pass, harness };

const layers = [_]struct { dir: []const u8, is: Layer }{
    .{ .dir = "backend", .is = .pass },
    .{ .dir = "conformance", .is = .harness },
    .{ .dir = "diagnostics", .is = .pass },
    .{ .dir = "driver", .is = .harness },
    .{ .dir = "fmt", .is = .pass },
    .{ .dir = "lexer", .is = .pass },
    .{ .dir = "lsp", .is = .harness },
    .{ .dir = "mir", .is = .pass },
    .{ .dir = "ownership", .is = .pass },
    .{ .dir = "parser", .is = .pass },
    .{ .dir = "sema", .is = .pass },
    .{ .dir = "support", .is = .pass },
    .{ .dir = "syntax", .is = .pass },
};

/// A tree of Zig source these gates read, and what a root of it is.
///
/// Two of them: the compiler under `src/`, and under `build/` the analysis the
/// gates themselves are written in. The second is held to the same rules for
/// the reason it exists -- it was extracted so a heuristic deciding whether a
/// build fails could be run against cases, and a dead declaration in the file
/// that reports dead declarations is the same defect as one anywhere else.
///
/// The layering rule is `src/`'s alone, and not by exemption: it says which
/// directory under a tree is a pass and which is a harness, and `build/` holds
/// neither. It is read by `build.zig` before a compiler exists.
const Tree = struct {
    dir: []const u8,
    /// The files a test build is rooted at. Each names, in a `comptime` block,
    /// every file whose tests it wants compiled.
    roots: []const []const u8,
    /// A file outside the tree that imports into it, or null where none does.
    /// The build script is what names `build/`'s module and is part of no tree
    /// it reads.
    imported_by: ?[]const u8 = null,
    /// Whether this tree's directories are passes and harnesses.
    layered: bool,
    /// The manifests whose direct `comptime` imports make test-bearing files
    /// part of the tree's test universe.
    test_manifests: []const []const u8,
    /// One test root joining several manifests into one Zig module.
    joined: ?struct { root: []const u8, manifests: []const []const u8 } = null,
};

const trees = [_]Tree{
    .{
        .dir = "src",
        .roots = &.{ "main.zig", "conformance_main.zig", "test_main.zig" },
        .layered = true,
        .test_manifests = &.{ "main.zig", "conformance_main.zig" },
        .joined = .{ .root = "test_main.zig", .manifests = &.{ "main.zig", "conformance_main.zig" } },
    },
    .{
        .dir = "build",
        .roots = &.{ "source_test.zig", "guide_gate.zig", "example_tests.zig", "fiber_call_coverage.zig", "fiber_migration_metrics.zig", "fiber_scheduling_measurements.zig", "fiber_object_entry.zig" },
        .imported_by = "build.zig",
        .layered = false,
        .test_manifests = &.{ "source_test.zig", "fiber_call_coverage.zig", "fiber_migration_metrics.zig", "fiber_scheduling_measurements.zig", "fiber_object_entry.zig" },
    },
    .{
        .dir = "runtime",
        .roots = &.{"float.zig"},
        .layered = false,
        .test_manifests = &.{"float.zig"},
    },
};

/// Four things the project's own source is held to, from one reading of each
/// tree.
///
/// Each exists because nothing else can catch it. Zig reports an unused local
/// and says nothing about a declaration nobody names, or a file nobody imports;
/// and a cycle in the module graph is a compile error while a pass importing the
/// driver is not.
fn checkTheCompilerIsTidy(b: *std.Build) void {
    var failed = false;
    for (trees) |tree| checkTreeIsTidy(b, tree, &failed);
    if (failed) @panic("the compiler's source is not tidy");
}

fn checkTreeIsTidy(b: *std.Build, tree: Tree, failed: *bool) void {
    const files = source.compilerSource(b.allocator, b.graph.io, b.build_root.handle, tree.dir);

    if (tree.joined) |joined| {
        const root = for (files) |file| {
            if (std.mem.eql(u8, file.path, joined.root)) break file;
        } else {
            std.debug.print("test root: {s}/{s} is missing\n", .{ tree.dir, joined.root });
            failed.* = true;
            return;
        };
        if (!source.importsExactly(b.allocator, root, joined.manifests, files)) {
            std.debug.print("test root: {s}/{s} does not import exactly its test manifests\n", .{ tree.dir, joined.root });
            failed.* = true;
        }
    }

    // A pass may not import the driver.
    //
    // Every other layering constraint is a compile error, because a cycle in
    // the graph is one. This is the shape Zig permits between separate files,
    // so the rule survives only as long as someone remembers it -- and it did
    // not: two files reached through the driver for renderers sitting in it.
    // The driver composes and does not decide, so a pass with a question for it
    // is a pass asking about a decision that should not live there.
    if (tree.layered) for (files) |f| {
        // The entry point and the conformance runner drive the compiler rather
        // than being part of it, and asking the driver what its command line
        // offers is a question only it can answer.
        const cut = std.mem.indexOfScalar(u8, f.path, '/') orelse continue;

        const layer = for (layers) |l| {
            if (std.mem.eql(u8, l.dir, f.path[0..cut])) break l.is;
        } else {
            std.debug.print("layering: {s}/{s}/ is neither a pass nor a harness\n", .{ tree.dir, f.path[0..cut] });
            failed.* = true;
            continue;
        };
        if (layer == .harness) continue;

        // Every file of the driver, rather than its entry point alone: the
        // loader and the toolchain close the same cycle, and a gate naming one
        // file reads as a gate on the directory while being a gate on a
        // filename.
        if (std.mem.indexOf(u8, f.text, "driver/") == null) continue;
        std.debug.print("layering: a pass may not import the driver -- {s}/{s}\n", .{ tree.dir, f.path });
        failed.* = true;
    };

    // A file nothing imports is a file nothing runs.
    //
    // The two roots are named in this file as root source files rather than
    // imported, which is what makes them roots.
    //
    // Matched on the path an `@import` resolves to, not on the basename it
    // ends with. `src/` holds three `dump.zig`: under a basename match, any
    // one of them being imported answered for all three, so a dead one was
    // reported live by a live sibling it has nothing to do with. The loop
    // already excluded itself by path, so the two identities in one comparison
    // were the whole defect.
    // A file outside the tree that imports into it, read once. Its imports name
    // the tree by the path the build root holds it under, which is what the
    // comparison below is against.
    const outside: ?source.SourceFile = if (tree.imported_by) |path| .{
        .path = path,
        .text = b.build_root.handle.readFileAlloc(b.graph.io, path, b.allocator, .limited(1 << 22)) catch
            @panic("the file that imports this tree is missing"),
    } else null;

    // Every path some other file imports, collected in one pass over each
    // file rather than by asking every file about every other.
    var imported_paths: std.StringHashMapUnmanaged(void) = .empty;
    for (files) |other| {
        for (source.importedPaths(b.allocator, other)) |path| {
            if (std.mem.eql(u8, path, other.path)) continue;
            imported_paths.put(b.allocator, path, {}) catch @panic("out of memory");
        }
    }
    const outside_paths: []const []const u8 = if (outside) |script| source.importedPaths(b.allocator, script) else &.{};

    for (files) |f| {
        const root = for (tree.roots) |name| {
            if (std.mem.eql(u8, f.path, name)) break true;
        } else false;
        if (root) continue;

        var imported = imported_paths.contains(f.path);
        if (!imported) {
            const from_outside = b.fmt("{s}/{s}", .{ tree.dir, f.path });
            for (outside_paths) |path| {
                if (std.mem.eql(u8, path, from_outside)) imported = true;
            }
        }
        if (imported) continue;
        std.debug.print("dead file: nothing imports {s}/{s}\n", .{ tree.dir, f.path });
        failed.* = true;
    }

    // A file holding tests that no root's `comptime` block names.
    //
    // Zig analyses a file only where something in it is used, and a test build
    // never analyses `main` -- so a module reached solely from another module's
    // code is a module whose `test` blocks compile to nothing at all. The
    // roots name every such file in a `comptime` block for exactly that
    // reason, and nothing held them to it: a file added under `src/lsp/` with
    // a deliberately failing test in it compiled to nothing, `zig build test`
    // reported `All 0 tests passed`, and the build stayed green.
    //
    // The check above cannot stand in for this one. It is satisfied by any
    // importer at all, and being imported is what the unnamed file already
    // was.
    for (files) |f| {
        if (std.mem.indexOf(u8, f.text, "\ntest ") == null) continue;

        var named = false;
        for (tree.test_manifests) |name| {
            if (std.mem.eql(u8, f.path, name)) {
                named = true;
                break;
            }
            const root = for (files) |r| {
                if (std.mem.eql(u8, r.path, name)) break r;
            } else continue;
            if (source.importsPath(b.allocator, .{ .path = root.path, .text = source.comptimeBlock(root.text) }, f.path)) {
                named = true;
                break;
            }
        }
        if (named) continue;
        std.debug.print("untested file: no root names {s}/{s}, so its tests never compile\n", .{ tree.dir, f.path });
        failed.* = true;
    }

    // A container holding tests that no file-level `comptime` block names.
    //
    // A test inside a struct compiles only once something makes the compiler
    // look inside that struct, and a filtered build keeps nothing that would:
    // a run filtered to such a test reported nothing and passed. A test in a
    // container a function builds or holds has no name to write there, so it
    // is refused outright.
    for (files) |f| {
        if (std.mem.indexOf(u8, f.text, "    test ") == null) continue;
        for (source.unreachedNestedTests(b.allocator, f.text)) |path| {
            std.debug.print("unreached tests: {s}/{s} holds tests in `{s}`, which no `comptime {{ _ = {s}; }}` names\n", .{ tree.dir, f.path, path, path });
            failed.* = true;
        }
    }

    // A unit test named `slow:` that does not skip itself under
    // `-Dslow-tests=false`, a test that skips itself, or reads the option,
    // under another name.
    //
    // Only the tree the unit-test binary is built from: the build tree's own
    // cases quote the statement inside strings.
    if (tree.joined != null) for (files) |f| {
        if (std.mem.indexOf(u8, f.text, "test \"slow: ") == null and
            std.mem.indexOf(u8, f.text, "skipUnlessRun") == null and
            std.mem.indexOf(u8, f.text, "test_options") == null) continue;
        for (source.slowTestMismatches(b.allocator, f)) |mismatch| {
            std.debug.print("slow test: {s}/{s}, {s}\n", .{ tree.dir, f.path, mismatch });
            failed.* = true;
        }
    };

    // An error a pass hands to no one.
    //
    // Inside a pass an error is a refused allocation, and one that is
    // discarded can lose a report, so a program whose one error was lost
    // checks clean. Every discard in a pass file is refused unless
    // `discards_allowed` names it with a reason.
    if (std.mem.eql(u8, tree.dir, "src")) for (source.unexplainedDiscards(b.allocator, files, &source.discards_allowed)) |discard| {
        std.debug.print("discarded failure: src/{s}\n", .{discard});
        failed.* = true;
    };

    // Outside the passes, where an error is often the answer to a question
    // put to the file system, only a report whose failure is discarded.
    for (files) |f| {
        if (std.mem.eql(u8, tree.dir, "src") and source.isPassFile(f.path)) continue;
        if (std.mem.indexOf(u8, f.text, "catch") == null) continue;
        for (source.swallowedReports(b.allocator, f)) |swallow| {
            std.debug.print("swallowed report: {s}/{s}, {s}\n", .{ tree.dir, f.path, swallow });
            failed.* = true;
        }
    }

    // A declaration nobody names.
    //
    // [N-Unused] makes this an error in the language this compiler implements,
    // and the compiler was exempt from its own rule: Zig reports an unused
    // local and accepts a private function nothing calls, forever. Private
    // declarations only, because those are the ones whose every use is in the
    // file that declares them.
    //
    // One pass over the text rather than over a tree, so a name reached by
    // anything but being written is missed. That is the same heuristic and the
    // same limit the reserved-word gates have, and it is worth what it costs:
    // it holds today and fails the moment something stops being named.
    for (files) |f| {
        const counts = source.wordCounts(b.allocator, f.text);
        var lines = std.mem.splitScalar(u8, f.text, '\n');
        while (lines.next()) |line| {
            const name = source.privateDeclaration(line) orelse continue;
            if ((counts.get(name) orelse 0) > 1) continue;
            std.debug.print("dead declaration: nothing names `{s}` in {s}/{s}\n", .{ name, tree.dir, f.path });
            failed.* = true;
        }
    }
}

/// The gates that hold the documentation to the compiler and to itself: the
/// decision index, the guide's index of errors, and the prelude's
/// documentation. Each prints what it found and stops the build.
fn checkTheDocumentation(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = options;
    const b = step.owner;
    checkTheDecisionIndexIsReciprocal(b);
    checkTheGuideIndexesItsErrors(b);
    checkThePreludeIsDocumented(b);
}

/// Every heavy step a suite runs, made by one routine each.
///
/// The suites share one of each. A sequential run (`-Dsequential`) asks for
/// copies of its own and chains them, so the order it adds is held by steps
/// only that run reaches: another top-level step gains nothing from it. A copy
/// of a compile is the same compilation, so it reuses the cached result.
const HeavySteps = struct {
    b: *std.Build,
    compiler_module: *std.Build.Module,
    runner_module: *std.Build.Module,
    unit_module: *std.Build.Module,
    /// The runtime archives a compiler links, which must exist before it is
    /// built.
    runtime_steps: [2]*std.Build.Step,
    /// The runtime archives installed beside the compiler, where an installed
    /// compiler looks for them.
    runtime_installs: [2]*std.Build.Step,
    generate_grammar: *std.Build.Step,
    guide_gate: *std.Build.Step.Compile,
    example_tests: *std.Build.Step.Compile,
    checked_runtime_archive: std.Build.LazyPath,
    test_filters: []const []const u8,
    scratch: []const u8,
    walkers: ?u32,
    sanitize: Sanitize,
    programs: u32,
    seed: u64,
    update: bool,
    opt_levels: bool,

    fn compiler(self: *const HeavySteps) *std.Build.Step.Compile {
        const exe = self.b.addExecutable(.{ .name = "linea", .root_module = self.compiler_module });
        // A build cannot run before the libraries it links exist.
        for (self.runtime_steps) |step| exe.step.dependOn(step);
        return exe;
    }

    fn runner(self: *const HeavySteps) *std.Build.Step.Compile {
        return self.b.addExecutable(.{ .name = "conformance", .root_module = self.runner_module });
    }

    fn unitTests(self: *const HeavySteps) *std.Build.Step.Compile {
        const tests = self.b.addTest(.{ .root_module = self.unit_module, .filters = self.test_filters });
        tests.step.dependOn(self.generate_grammar);
        return tests;
    }

    fn unitRun(self: *const HeavySteps, tests: *std.Build.Step.Compile) *std.Build.Step.Run {
        return self.b.addRunArtifact(tests);
    }

    fn corpus(self: *const HeavySteps, runner_step: *std.Build.Step.Compile, compiler_step: *std.Build.Step.Compile) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(runner_step);
        shareLibraryCache(run);
        run.addArg(b.pathFromRoot("tests"));
        // The runner builds and runs generated programs, so it is told where the
        // runtime is and where to put intermediates. It does not run from an
        // install tree and cannot find either on its own.
        run.addArg("--compiler");
        run.addFileArg(compiler_step.getEmittedBin());
        run.addArg("--runtime");
        run.addFileArg(self.checked_runtime_archive);
        run.addArg("--scratch");
        // Deliberately outside the build cache. A recorded outcome is keyed on the
        // emitted IR, the runtime, the commands a build assembles and a stamp of
        // each tool it runs them with -- where the tool resolved on `PATH`, and the
        // size and modification time of the file there, rather than its bytes. That
        // identifies a toolchain on one machine and not across machines, where the
        // same size and time can name different bytes, so the outcomes must not
        // travel the way a cached build directory does.
        run.addArg(self.scratch);
        if (self.walkers) |n| {
            run.addArg("--walkers");
            run.addArg(b.fmt("{d}", .{n}));
        }
        run.addArg("--sanitize");
        run.addArg(@tagName(self.sanitize));
        // A sanitized run watches what runs: the cases that record an exit
        // status, the examples, and the transcripts that build or run a program.
        // It watches the generated code and the runtime (see `Sanitize`), every
        // allocation and free, and a leak check at each clean exit. The runner
        // leaves every other case, and the
        // corpus-wide frontend and editor properties, to the unsanitized walk.
        // Generated programs are held to the metamorphic properties beside the
        // corpus. The seeds are consecutive from zero, so a run generates the same
        // programs as the last one and their outcomes stay cached -- the cost is
        // paid once rather than on every build. A sanitized run generates none.
        // Only a run over the whole corpus can be held to what each rewrite must
        // reach, and a sanitized run is not one. Held to the floors anyway it
        // would report that a rule nobody narrowed away had stopped being covered.
        if (self.sanitize == .none) run.addArg("--floors");
        run.addArg("--programs");
        run.addArg(b.fmt("{d}", .{if (self.sanitize == .none) self.programs else 0}));
        run.addArg("--seed");
        run.addArg(b.fmt("{d}", .{self.seed}));
        if (self.update) run.addArg("--update");
        // A run over the whole corpus must have found something for every
        // metamorphic property. The examples run below is a smaller set on purpose
        // and is not held to it, and neither is a sanitized run, for the same
        // reason: a property finding nothing there is a statement about what was
        // built, not about the property.
        if (self.sanitize == .none) run.addArg("--every-property");
        if (self.opt_levels) run.addArg("--levels");
        // Golden files change on disk between runs, so the result is never cacheable.
        run.has_side_effects = true;
        return run;
    }

    fn properties(self: *const HeavySteps, runner_step: *std.Build.Step.Compile, compiler_step: *std.Build.Step.Compile) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(runner_step);
        shareLibraryCache(run);
        run.addArg(b.pathFromRoot("tests"));
        run.addArgs(&.{ "--properties", "--property-cases", b.pathFromRoot("build/property-cases.txt"), "--every-property" });
        run.addArg("--compiler");
        run.addFileArg(compiler_step.getEmittedBin());
        run.addArg("--runtime");
        run.addFileArg(self.checked_runtime_archive);
        run.addArgs(&.{ "--scratch", b.pathJoin(&.{ self.scratch, "properties" }), "--sanitize", @tagName(self.sanitize) });
        if (self.walkers) |n| run.addArgs(&.{ "--walkers", b.fmt("{d}", .{n}) });
        run.has_side_effects = true;
        return run;
    }

    /// The examples are held to the same standard as the corpus: they are
    /// built and run, so one cannot quietly stop compiling as the language
    /// moves. Their goldens sit in `tests/examples/`, which the corpus walk
    /// leaves to this one.
    fn examples(self: *const HeavySteps, runner_step: *std.Build.Step.Compile) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(runner_step);
        shareLibraryCache(run);
        run.addArg(b.pathFromRoot("examples"));
        run.addArg("--runtime");
        run.addFileArg(self.checked_runtime_archive);
        run.addArg("--scratch");
        // Both corpus processes number their LSP fixtures from zero and clear
        // that directory on startup, so concurrent walks need separate roots.
        run.addArg(b.pathJoin(&.{ self.scratch, "examples" }));
        run.addArg("--sanitize");
        run.addArg(@tagName(self.sanitize));
        if (self.update) run.addArg("--update");
        run.has_side_effects = true;
        return run;
    }

    /// Every program and fragment the guide pastes is compiled, and the output
    /// pasted beside it is held to what the compiler prints. The guide shows
    /// real errors and real output, so a compiler change that moves one makes
    /// the page false without any test noticing. It stands beside the
    /// error-index check but runs the compiler, so it is a step of the suites
    /// that build the compiler, and `zig build` alone never pays for it.
    ///
    /// `installed` puts the compiler and its runtime where the gate runs it.
    fn guide(self: *const HeavySteps, installed: *std.Build.Step) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(self.guide_gate);
        shareLibraryCache(run);
        run.addArg(b.pathFromRoot("docs/learn"));
        // The installed compiler finds the runtime beside itself.
        run.addArg(b.getInstallPath(.bin, "linea"));
        run.step.dependOn(installed);
        // The installed runtime is the sanitized one, so the compiler it runs
        // has to be told which sanitizer the link must name.
        if (toolchain.sanitizeVariable(self.sanitize.flag())) |variable| run.setEnvironmentVariable(variable.name, variable.value);
        run.addArg(b.pathJoin(&.{ self.scratch, "guide" }));
        run.addArg(b.pathFromRoot("tests"));
        run.addArg(b.pathFromRoot("."));
        if (self.walkers) |n| run.addArg(b.fmt("{d}", .{n}));
        run.has_side_effects = true;
        return run;
    }

    /// `linea test` on every root beneath `examples/`, including a library
    /// nested under an application, which the application's own run does not
    /// reach. The suite runs some of these as cases and compares a transcript,
    /// which `-Dupdate` can rewrite to hold a failure; this step asserts the
    /// exit status, which cannot be accepted.
    fn exampleTests(self: *const HeavySteps, installed: *std.Build.Step) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(self.example_tests);
        shareLibraryCache(run);
        run.addArg(b.pathFromRoot("examples"));
        run.addArg(b.getInstallPath(.bin, "linea"));
        run.step.dependOn(installed);
        if (toolchain.sanitizeVariable(self.sanitize.flag())) |variable| run.setEnvironmentVariable(variable.name, variable.value);
        if (self.walkers) |n| run.addArg(b.fmt("{d}", .{n}));
        run.has_side_effects = true;
        return run;
    }

    /// Fresh copies of the heavy steps `order` names, each waiting for the
    /// one before it; returns the last, or null when there are none.
    fn sequence(self: *const HeavySteps, order: []const test_roots.Heavy) ?*std.Build.Step {
        var compiler_copy: ?*std.Build.Step.Compile = null;
        var runner_copy: ?*std.Build.Step.Compile = null;
        var unit_copy: ?*std.Build.Step.Compile = null;
        var earlier: ?*std.Build.Step = null;
        for (order) |heavy| {
            const this: *std.Build.Step = switch (heavy) {
                .compile_compiler => step: {
                    compiler_copy = self.compiler();
                    break :step &compiler_copy.?.step;
                },
                .compile_runner => step: {
                    runner_copy = self.runner();
                    break :step &runner_copy.?.step;
                },
                .compile_unit_tests => step: {
                    unit_copy = self.unitTests();
                    break :step &unit_copy.?.step;
                },
                .unit_tests => &self.unitRun(unit_copy.?).step,
                .corpus => &self.corpus(runner_copy.?, compiler_copy.?).step,
                .properties => &self.properties(runner_copy.?, compiler_copy.?).step,
                .examples => &self.examples(runner_copy.?).step,
                .guide => step: {
                    const install = self.b.addInstallArtifact(compiler_copy.?, .{});
                    for (self.runtime_installs) |runtime_install| install.step.dependOn(runtime_install);
                    break :step &self.guide(&install.step).step;
                },
            };
            if (earlier) |before| this.dependOn(before);
            earlier = this;
        }
        return earlier;
    }
};

pub fn build(b: *std.Build) void {
    checkTheCompilerIsTidy(b);
    checkEveryPropertyAccountsForItself(b);
    checkTheEditorIndentsByWhatTheFormatterDoes(b);
    checkCiRunsEverySanitizer(b);
    checkTheRuntimeSpeaksEveryTrapKind(b);
    checkTheRuntimeSpeaksEveryIoCategory(b);
    const target = b.standardTargetOptions(.{});
    // `zig build` stays a debug build for the edit-compile loop, and
    // `zig build -Drelease` is the distributed one. The unit tests run in the
    // mode the build selects: Debug here, ReleaseSafe in the `optimised-unit`
    // CI lane and, on its weekly and manual runs, ReleaseFast too.
    const optimize = test_roots.optimizeMode(b.release_mode, b.option(bool, "release", "optimize for end users"));

    // Where recorded outcomes and build intermediates go.
    //
    // Overridable because `actions/checkout` runs `git clean -ffdx`, which
    // deletes anything under the workspace between runs. On a persistent
    // machine that throws away the one cache that makes a second run cheap --
    // and a persistent machine is exactly where the cache is *valid*, since a
    // recorded outcome is keyed on a stamp of each tool as that machine sees
    // it. Pointed outside the workspace, the outcomes survive the clean while
    // the checkout stays honest.
    // Tracy, off unless asked for.
    //
    // The suite's own timers answer how long a phase took, summed over a run.
    // They cannot answer why a thread was not running, because a thread that
    // is blocked is inside the phase that blocked it and looks the same as one
    // doing work. That question came up with a 42-second hole no amount of
    // bracketing would localise, and a timeline per thread is the instrument
    // for it.
    //
    // Off by default and absent from the binary when off: this is for
    // answering a question, not a thing the suite carries.
    const profiling = b.option(bool, "tracy", "Build with Tracy zones") orelse false;
    const tracy_options = b.addOptions();
    tracy_options.addOption(bool, "tracy", profiling);

    // How many walkers the corpus is divided between. Defaults to one per core.
    //
    // Worth naming because this box is not the only consumer: CI runs several
    // jobs on one machine, so a run that takes every core makes the other jobs
    // wait for it. It is also the only way to measure what the parallelism is
    // actually buying, by asking for one.
    const walkers = b.option(u32, "walkers", "How many workers the corpus walk, the guide gate, the example tests and the soundness run use (default: one per core)");

    const scratch = b.option(
        []const u8,
        "scratch",
        "Where recorded outcomes and build intermediates go (default: .zig-cache/conformance-scratch)",
    ) orelse b.pathFromRoot(".zig-cache/conformance-scratch");

    // One checked-library cache for every `linea` a step runs and for the
    // conformance runner itself, inside the build's cache rather than the
    // user's home: a second run, and every parallel worker of one, reads
    // the library a first wrote. `off` runs them without it.
    const library_cache_option = b.option(
        []const u8,
        "library-cache",
        "Where the checked standard library is kept between runs, or `off` (default: linea-cache in the scratch directory)",
    ) orelse b.pathJoin(&.{ scratch, "linea-cache" });
    library_cache_dir = if (std.mem.eql(u8, library_cache_option, "off")) "" else b.pathFromRoot(library_cache_option);

    const sanitize = b.option(
        Sanitize,
        "sanitize",
        "Build the runtime library with a sanitizer and link every program with it; generated code is not instrumented",
    ) orelse .none;

    const migration_supported = (target.result.os.tag == .linux and
        (target.result.cpu.arch == .aarch64 or target.result.cpu.arch == .x86_64)) or
        (target.result.os.tag == .macos and target.result.cpu.arch == .aarch64 and sanitize == .none);

    const update_goldens = b.option(
        bool,
        "update",
        "Rewrite conformance expectations instead of failing",
    ) orelse false;

    // Narrows the Zig test binaries to tests whose name contains a substring.
    // Integration gates without named tests are excluded; pointing the
    // conformance executable at a narrower directory is how one corpus case is
    // isolated.
    const test_filter = b.option(
        []const u8,
        "test-filter",
        "Run only unit tests whose name contains this substring",
    );
    const test_filters: []const []const u8 =
        if (test_filter) |f| &.{f} else &.{};
    const fuzz_filter = b.option(
        []const u8,
        "fuzz-filter",
        "Run only fuzz targets whose name contains this text",
    );
    const sweep_filter = b.option(
        []const u8,
        "sweep-filter",
        "Run only release sweep dimensions whose names contain this text",
    );
    // How many programs the generator supplies to the metamorphic properties.
    // Enough by default that a regression is caught, and raised for a run that
    // is looking rather than checking.
    const programs = b.option(
        u32,
        "programs",
        "How many generated programs to check against the metamorphic properties",
    ) orelse 32;

    // Where the seed sequence starts. Zero by default, so an ordinary run
    // generates the programs the last one did and their outcomes stay cached.
    // A run that is looking rather than checking moves the window: seeds are
    // consecutive from here, so a failure still names one number that
    // reproduces it, and nightly ground nobody has walked costs only the cache
    // it gives up.
    const seed = b.option(
        u64,
        "seed",
        "The first seed the generator uses, for a run that wants new programs",
    ) orelse 0;

    // How many generated storage programs the soundness step checks, each
    // with its mutants. Seeds start at `-Dseed` as the generated programs'
    // do, so an ordinary run checks the same programs as the last one and
    // serves them from the outcome cache.
    const storage_programs = b.option(
        u32,
        "storage-programs",
        "How many generated storage programs, with their mutants, the soundness step checks",
    ) orelse 16;

    // Whether the soundness step checks the matrix as well as the generated
    // programs. A search over new seeds leaves it out: its cells are the same
    // whatever the seed.
    const soundness_matrix = b.option(
        bool,
        "soundness-matrix",
        "Check the soundness matrix as well as the generated storage programs (default: true)",
    ) orelse true;

    // The conformance runner compiles and rewrites generated programs in
    // process; the generated-program phase of a Debug runner takes several
    // times as long as a ReleaseSafe one's. The compiler under test and the
    // unit tests keep the optimisation level the build selects.
    const safe_runner = b.option(
        bool,
        "safe-runner",
        "Build the conformance runner with ReleaseSafe when the build would otherwise be Debug",
    ) orelse false;

    // Each heavy step of a suite holds several gigabytes -- a compile of the
    // compiler, of the conformance runner or of the unit tests, the unit
    // tests, the corpus walk and the walks beside it -- and a machine of
    // seven, such as a hosted CI runner, cannot hold two at once. `-j1` does
    // not stop them overlapping, so this orders them one after another, in
    // whichever of the test suites is asked for (`test`, `test-corpus`,
    // `test-support`, `test-unit`, `conformance`). The build runner's
    // `--maxrss` would too, but on Zig 0.16 a step it holds back is started
    // without counting against the limit.
    const sequential = b.option(
        bool,
        "sequential",
        "Run a test suite's heavy steps one after another, for a machine with little memory",
    ) orelse false;

    // The guide compiles and runs about two hundred programs with the Debug
    // compiler. A pull request's `check` run leaves it to the `optimised-unit`
    // lane, which runs before the pull request merges, and passes
    // `-Dguide=false`; everywhere else `test` runs it.
    const guide_in_test = b.option(
        bool,
        "guide",
        "Run the guide gate as part of `test` (default: true)",
    ) orelse true;

    // The unit tests named `slow:` take ten seconds or more each in a Debug
    // binary and together most of its run. A pull request's `check` run builds
    // its Debug unit tests with them skipped and passes `-Dslow-tests=false`,
    // because the `optimised-unit` lane runs every unit test under
    // ReleaseSafe, which keeps Debug's safety checks and assertions, before
    // the pull request merges; everywhere else they run.
    const slow_tests = b.option(
        bool,
        "slow-tests",
        "Run the unit tests named `slow:` (default: true)",
    ) orelse true;
    const test_options = b.addOptions();
    test_options.addOption(bool, "slow_tests", slow_tests);

    // Every case that runs, built again at every other optimisation level and
    // held to answering alike. Off by default because it builds each case six
    // times rather than once; no CI lane sets it.
    const opt_levels = b.option(
        bool,
        "opt-levels",
        "Build every corpus case that runs at every optimisation level and hold it to answering alike",
    ) orelse false;

    // Install the runtime beside the compiler so generated programs can link
    // it without a source checkout. Ordinary builds trap on sanitizer failures;
    // instrumented builds link the reporting runtime selected below.
    var runtime_flags: std.ArrayList([]const u8) = .empty;
    runtime_flags.appendSlice(b.allocator, &.{
        "-std=c99",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-pedantic",
        "-fsanitize=undefined",
        "-fsanitize=integer",
        "-fsanitize=implicit-conversion",
        "-fsanitize=local-bounds",
        "-fsanitize=nullability",
        // Platform constants differ in signedness between targets, and the
        // implicit-conversion trap above only fires on the target that
        // spells one unsigned. Warning here turns that into a build error on
        // every target the runtime is compiled for.
        "-Wconversion",
        "-Wsign-conversion",
        "-fstack-protector-strong",
        "-fno-omit-frame-pointer",
        "-fvisibility=hidden",
        "-Wstrict-prototypes",
        "-Wundef",
        "-Wshadow",
        "-Wformat-security",
    }) catch @panic("OOM");

    if (sanitize.flag()) |name| {
        // A sanitizer that reports has to be able to reach its reporting
        // routine, so trapping is off wherever one is selected. A trap would
        // abort with no account of what it found. `LINEA_SANITIZED` tells the
        // runtime and its tests to leave faults to the sanitizer's own
        // handler; the build defines it because it is the one place that knows
        // a sanitizer was selected, whichever C compiler builds the file.
        runtime_flags.appendSlice(b.allocator, &.{
            b.fmt("-fsanitize={s}", .{name}),
            "-DLINEA_SANITIZED=1",
        }) catch @panic("OOM");
    } else {
        runtime_flags.append(b.allocator, "-fsanitize-trap=all") catch @panic("OOM");
    }

    var math_flags: std.ArrayList([]const u8) = .empty;
    math_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    math_flags.appendSlice(b.allocator, &.{
        "-std=c11",        "-fno-fast-math",        "-ffp-contract=off", "-frounding-math",
        "-ftrapping-math", "-fno-finite-math-only", "-fhonor-nans",      "-fno-math-errno",
    }) catch @panic("OOM");
    // A sanitized runtime leaves storage checking to the sanitizer, whose
    // shadow memory cannot see pages the checking allocator maps itself, so
    // the checking allocator is compiled only where no sanitizer is selected.
    var checked_flags: std.ArrayList([]const u8) = .empty;
    checked_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    if (sanitize == .none) checked_flags.append(b.allocator, "-DLINEA_CHECK_STORAGE=1") catch @panic("OOM");

    const native: NativeTests = .{ .b = b, .target = target, .optimize = optimize, .sanitize = sanitize };

    const native_math_step = b.step("test-native-math", "Check strict binary64 runtime operations against independent reference vectors");
    native.add(native_math_step, "native-math-tests", &.{
        .{ .file = "runtime/math.c", .flags = math_flags.items },
        .{ .file = "tests/native/math_test.c", .flags = math_flags.items },
    });

    const native_io_step = b.step("test-native-io", "Check native byte transport and filesystem operations");
    var transport_flags: std.ArrayList([]const u8) = .empty;
    transport_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    transport_flags.appendSlice(b.allocator, &.{
        "-Dread=linea_test_read",
        "-Dwrite=linea_test_write",
        "-Dclose=linea_test_close",
        "-Dgetentropy=linea_test_getentropy",
        // glibc's fortified read would call the real read past the rename
        // above; `unfortified.h` turns it off.
        "-include",
        b.pathFromRoot("runtime/unfortified.h"),
    }) catch @panic("OOM");
    native.add(native_io_step, "native-io-tests", &.{
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io_test.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
    });
    // The fault tests stand in for the allocator to see what I/O reports to
    // it; the others link the allocator itself.
    native.add(native_io_step, "native-io-fault-tests", &.{
        .{ .file = "runtime/io.c", .flags = transport_flags.items },
        .{ .file = "runtime/io_fault_test.c", .flags = runtime_flags.items },
    });

    const native_net_step = b.step("test-native-net", "Check native socket listen, accept, connect and address operations, and the simulated clock and network");
    var socket_flags: std.ArrayList([]const u8) = .empty;
    socket_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    socket_flags.appendSlice(b.allocator, &.{
        "-Dsocket=linea_test_socket",
        "-Dsetsockopt=linea_test_setsockopt",
        "-Dbind=linea_test_bind",
        "-Dlisten=linea_test_listen",
        "-Dfcntl=linea_test_fcntl",
        "-Daccept=linea_test_accept",
        "-Dconnect=linea_test_connect",
        "-Dgetpeername=linea_test_getpeername",
        "-Dgetsockname=linea_test_getsockname",
        "-Dgetsockopt=linea_test_getsockopt",
        "-Dread=linea_test_read",
        "-Dsend=linea_test_send",
        "-Dpoll=linea_test_poll",
        "-Dnanosleep=linea_test_nanosleep",
        "-Dlinea_clock_read=linea_test_clock_read",
        // glibc's fortified wrappers would call the real poll and read past
        // the renames above; `unfortified.h` turns them off.
        "-include",
        b.pathFromRoot("runtime/unfortified.h"),
    }) catch @panic("OOM");
    inline for (.{ false, true }) |faults| {
        native.add(native_net_step, if (faults) "native-net-fault-tests" else "native-net-tests", &.{
            .{ .file = "runtime/net.c", .flags = if (faults) socket_flags.items else runtime_flags.items },
            .{ .file = "runtime/io.c", .flags = runtime_flags.items },
            .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
            .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
            .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
            .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
            .{ .file = if (faults) "runtime/net_fault_test.c" else "runtime/net_test.c", .flags = runtime_flags.items },
        });
    }
    native.add(native_net_step, "native-sim-tests", &.{
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim_test.c", .flags = runtime_flags.items },
    });
    var sim_fault_flags: std.ArrayList([]const u8) = .empty;
    sim_fault_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    sim_fault_flags.append(b.allocator, "-Dmalloc=linea_test_malloc") catch @panic("OOM");
    native.add(native_net_step, "native-sim-fault-tests", &.{
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = sim_fault_flags.items },
        .{ .file = "runtime/sim_fault_test.c", .flags = runtime_flags.items },
    });

    const native_clock_step = b.step("test-native-clock", "Check native clock reads and the monotonic sleep");
    var clock_flags: std.ArrayList([]const u8) = .empty;
    clock_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    clock_flags.appendSlice(b.allocator, &.{
        "-Dclock_gettime=linea_test_clock_gettime",
        "-Dnanosleep=linea_test_nanosleep",
    }) catch @panic("OOM");
    inline for (.{ false, true }) |faults| {
        native.add(native_clock_step, if (faults) "native-clock-fault-tests" else "native-clock-tests", &.{
            .{ .file = "runtime/clock.c", .flags = if (faults) clock_flags.items else runtime_flags.items },
            .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
            .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
            .{ .file = if (faults) "runtime/clock_fault_test.c" else "runtime/clock_test.c", .flags = runtime_flags.items },
        });
    }

    const native_runtime_step = b.step("test-native-runtime", "Check the generated-code runtime's allocation, arguments, environment, aborts, and the storage its I/O entries are handed");
    inline for (.{ false, true }) |checked| {
        const flags = if (checked) checked_flags.items else runtime_flags.items;
        native.add(native_runtime_step, if (checked) "native-checked-runtime-tests" else "native-runtime-tests", &.{
            .{ .file = "runtime/linea_rt.c", .flags = flags },
            .{ .file = "runtime/io.c", .flags = runtime_flags.items },
            .{ .file = "runtime/linea_rt_test.c", .flags = flags },
        });
    }
    var busy_table_flags: std.ArrayList([]const u8) = .empty;
    busy_table_flags.appendSlice(b.allocator, checked_flags.items) catch @panic("OOM");
    busy_table_flags.appendSlice(b.allocator, &.{ "-Dmprotect=linea_test_mprotect", "-Dnanosleep=linea_test_nanosleep" }) catch @panic("OOM");
    native.add(native_runtime_step, "native-storage-busy-tests", &.{
        .{ .file = "runtime/linea_rt.c", .flags = busy_table_flags.items },
        .{ .file = "runtime/storage_busy_test.c", .flags = runtime_flags.items },
    });
    var preempted_flags: std.ArrayList([]const u8) = .empty;
    preempted_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    preempted_flags.append(b.allocator, "-Dclock_gettime=linea_test_clock_gettime") catch @panic("OOM");
    native.add(native_runtime_step, "native-preempted-fault-tests", &.{
        .{ .file = "runtime/linea_rt.c", .flags = preempted_flags.items },
        .{ .file = "runtime/preempted_fault_test.c", .flags = runtime_flags.items },
    });
    var interrupted_flags: std.ArrayList([]const u8) = .empty;
    interrupted_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    interrupted_flags.append(b.allocator, "-Dmemcmp=linea_test_memcmp") catch @panic("OOM");
    native.add(native_runtime_step, "native-interrupted-fault-tests", &.{
        .{ .file = "runtime/linea_rt.c", .flags = interrupted_flags.items },
        .{ .file = "runtime/interrupted_fault_test.c", .flags = runtime_flags.items },
    });

    const native_task_step = b.step("test-native-task", "Check native task threads, rendezvous sessions, joins, stack overflow reports and concurrent allocation");
    native.add(native_task_step, "native-fiber-tests", &.{
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/fiber_test.c", .flags = runtime_flags.items },
    });
    const native_migration_step = b.step("test-native-fiber-migration", "Check scheduler authority and native migration safety");
    native_task_step.dependOn(native_migration_step);
    native.add(native_migration_step, "native-fiber-migration-tests", &.{
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/fiber_migration_test.c", .flags = runtime_flags.items, .includes = &.{"runtime/fiber.c"} },
    });
    native.add(native_task_step, "native-fiber-failure-tests", &.{
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/fiber_failure_test.c", .flags = runtime_flags.items, .includes = &.{"runtime/fiber.c"} },
    });
    native.add(native_task_step, "native-sim-cancel-tests", &.{
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim_cancel_test.c", .flags = runtime_flags.items, .includes = &.{"runtime/fiber.c"} },
    });
    native.add(native_task_step, "native-foreign-tests", &.{
        .{ .file = "runtime/foreign_test.c", .flags = runtime_flags.items },
    });
    native.add(native_task_step, "native-parallelism-tests", &.{
        .{ .file = "runtime/parallelism_test.c", .flags = runtime_flags.items },
    });
    var fiber_race_flags: std.ArrayList([]const u8) = .empty;
    fiber_race_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    fiber_race_flags.append(b.allocator, "-DLINEA_FIBER_PAUSES=1") catch @panic("OOM");
    native.add(native_task_step, "native-fiber-race-tests", &.{
        .{ .file = "runtime/fiber.c", .flags = fiber_race_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/fiber_race_test.c", .flags = fiber_race_flags.items },
    });
    const native_fiber_scale_step = b.step("test-native-fiber-scale", "Check 10000 TCP connections parked on two carriers with bounded OS threads");
    // Zig's Darwin launcher caps its descendants at OPEN_MAX (10,240).
    // Build separately so a shell can run the acceptance binary with its own
    // descriptor limit; Linux can use the normal build-and-run step.
    var scale_native = native;
    scale_native.install_step = b.step("build-native-fiber-scale", "Install the 10000-connection test for execution outside Zig on Darwin");
    scale_native.add(native_fiber_scale_step, "native-fiber-scale-tests", &.{
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/fiber.c", .flags = fiber_race_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/fiber_scale_test.c", .flags = fiber_race_flags.items },
    });
    native.add(native_task_step, "native-fiber-fault-tests", &.{
        .{ .file = "runtime/fiber.c", .flags = fiber_race_flags.items },
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/fiber_fault_test.c", .flags = fiber_race_flags.items },
    });
    native.add(native_task_step, "native-sim-fiber-tests", &.{
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim_fiber_test.c", .flags = runtime_flags.items },
    });
    native.add(native_task_step, "native-sim-waitset-tests", &.{
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim_waitset_test.c", .flags = runtime_flags.items },
    });
    native.add(native_task_step, "native-sim-foreign-tests", &.{
        .{ .file = "runtime/task.c", .flags = runtime_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .file = "runtime/clock.c", .flags = runtime_flags.items },
        .{ .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim_foreign_test.c", .flags = runtime_flags.items },
    });
    const native_context_step = b.step("test-native-context", "Compare ABI context switches with ucontext at every optimisation level");
    // glibc fortification requires optimisation. Nix's wrapper appends its
    // define after user flags, so undefine it before headers only in the O0
    // oracle/candidate builds. Optimised and production builds retain it.
    const unoptimized_context = b.addWriteFiles().add("context-unoptimized.h", "#undef _FORTIFY_SOURCE\n");
    for ([_][]const u8{ "0", "1", "2", "3", "s", "z" }) |level| {
        inline for (.{ false, true }) |reference| {
            const compile = b.addSystemCommand(&.{ "cc", "-std=c99", "-pedantic", "-Wall", "-Wextra", "-Werror", "-Wconversion", "-Wsign-conversion", "-Wshadow", "-Wundef", "-Wno-deprecated-declarations", "-fno-omit-frame-pointer" });
            compile.addArg(b.fmt("-O{s}", .{level}));
            if (std.mem.eql(u8, level, "0")) {
                compile.addArg("-include");
                compile.addFileArg(unoptimized_context);
            }
            if (reference) compile.addArg("-DLINEA_CONTEXT_REFERENCE=1");
            compile.addFileArg(b.path("runtime/context_test.c"));
            if (!reference) compile.addFileArg(b.path("runtime/context.c"));
            compile.addArg("-o");
            const binary = compile.addOutputFileArg(b.fmt("context-{s}-{s}", .{ if (reference) "reference" else "candidate", level }));
            if (target.result.os.tag == .linux) compile.addArg("-lm");
            const run = std.Build.Step.Run.create(b, "check context ABI");
            run.addFileArg(binary);
            native_context_step.dependOn(&run.step);
        }
    }
    native_task_step.dependOn(native_context_step);
    var refused_task_flags: std.ArrayList([]const u8) = .empty;
    refused_task_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    refused_task_flags.appendSlice(b.allocator, &.{
        "-Dpthread_create=linea_test_pthread_create",
        "-Dpthread_join=linea_test_pthread_join",
        "-Dmmap=linea_test_mmap",
        "-Dmunmap=linea_test_munmap",
        "-Dcalloc=linea_test_calloc",
        "-Dclock_gettime=linea_test_clock_gettime",
        "-Dpthread_cond_wait=linea_test_pthread_cond_wait",
    }) catch @panic("OOM");
    var refused_signal_flags: std.ArrayList([]const u8) = .empty;
    refused_signal_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    refused_signal_flags.append(b.allocator, "-Dsigaltstack=linea_test_sigaltstack") catch @panic("OOM");
    inline for (.{ false, true }) |checked| {
        native.add(native_task_step, if (checked) "native-checked-task-tests" else "native-task-tests", &.{
            .{ .file = "runtime/task.c", .flags = runtime_flags.items },
            .{ .file = "runtime/park.c", .flags = runtime_flags.items },
            .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
            .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
            .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
            .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
            .{ .file = "runtime/linea_rt.c", .flags = if (checked) checked_flags.items else runtime_flags.items },
            .{ .file = "runtime/task_test.c", .flags = runtime_flags.items },
        });
    }
    // The wait set's race tests stop a thread at each linearization point of
    // the registration protocol, and the signal router's handler before it
    // chains to the host's action, so the task, the set and the router are
    // compiled with the pauses the tests supply.
    var paused_flags: std.ArrayList([]const u8) = .empty;
    paused_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    paused_flags.append(b.allocator, "-DLINEA_WAITSET_PAUSES=1") catch @panic("OOM");
    native.add(native_task_step, "native-waitset-tests", &.{
        .{ .file = "runtime/task.c", .flags = paused_flags.items },
        .{ .file = "runtime/waitset.c", .flags = paused_flags.items },
        .{ .file = "runtime/park.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = paused_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
        .{ .file = "runtime/waitset_test.c", .flags = paused_flags.items },
    });
    native.add(native_task_step, "native-task-fault-tests", &.{
        .{ .file = "runtime/task.c", .flags = refused_task_flags.items },
        .{ .file = "runtime/park.c", .flags = refused_task_flags.items },
        .{ .file = "runtime/waitset.c", .flags = runtime_flags.items },
        .{ .file = "runtime/signals.c", .flags = runtime_flags.items },
        .{ .file = "runtime/sim.c", .flags = runtime_flags.items },
        .{ .file = "runtime/loop.c", .flags = runtime_flags.items },
        .{ .file = "runtime/linea_rt.c", .flags = refused_signal_flags.items },
        .{ .file = "runtime/task_fault_test.c", .flags = runtime_flags.items },
    });

    // The runtime is compiled for Linux and for macOS as well as for the host,
    // so a platform constant that is signed on one and unsigned on the other,
    // or a branch only one platform takes, is a build error on either
    // checkout and not a failure on the first run on the other.
    for ([_]struct { os: []const u8, query: std.Target.Query }{
        .{ .os = "linux", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu } },
        .{ .os = "linux_arm", .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu } },
        .{ .os = "macos", .query = .{ .cpu_arch = .aarch64, .os_tag = .macos } },
    }) |platform| {
        const platform_target = b.resolveTargetQuery(platform.query);
        // `linea_rt.c` is built three ways, each keeping code the others leave
        // out: checking storage, plain, and as a sanitized build compiles it.
        var sanitized_runtime_flags: std.ArrayList([]const u8) = .empty;
        sanitized_runtime_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
        sanitized_runtime_flags.append(b.allocator, "-DLINEA_SANITIZED=1") catch @panic("OOM");
        for ([_]struct { name: []const u8, file: []const u8, flags: []const []const u8 }{
            .{ .name = "linea_rt_checked", .file = "runtime/linea_rt.c", .flags = checked_flags.items },
            .{ .name = "linea_rt", .file = "runtime/linea_rt.c", .flags = runtime_flags.items },
            .{ .name = "linea_rt_sanitized", .file = "runtime/linea_rt.c", .flags = sanitized_runtime_flags.items },
            .{ .name = "io", .file = "runtime/io.c", .flags = runtime_flags.items },
            .{ .name = "net", .file = "runtime/net.c", .flags = runtime_flags.items },
            .{ .name = "clock", .file = "runtime/clock.c", .flags = runtime_flags.items },
            .{ .name = "task", .file = "runtime/task.c", .flags = runtime_flags.items },
            .{ .name = "park", .file = "runtime/park.c", .flags = runtime_flags.items },
            .{ .name = "waitset", .file = "runtime/waitset.c", .flags = runtime_flags.items },
            .{ .name = "signals", .file = "runtime/signals.c", .flags = runtime_flags.items },
            .{ .name = "loop", .file = "runtime/loop.c", .flags = runtime_flags.items },
            .{ .name = "fiber", .file = "runtime/fiber.c", .flags = runtime_flags.items },
            .{ .name = "completion", .file = "runtime/completion.c", .flags = runtime_flags.items },
            .{ .name = "foreign", .file = "runtime/foreign.c", .flags = runtime_flags.items },
            .{ .name = "parallelism", .file = "runtime/parallelism.c", .flags = runtime_flags.items },
            .{ .name = "context", .file = "runtime/context.c", .flags = runtime_flags.items },
            .{ .name = "sim", .file = "runtime/sim.c", .flags = runtime_flags.items },
        }) |input| {
            const name = b.fmt("{s}_{s}", .{ input.name, platform.os });
            native_runtime_step.dependOn(&runtimeObject(b, platform_target, name, b.path(input.file), input.flags).step);
        }
        // The runtime's own tests too, as written and as a sanitized build
        // compiles them, since a test only one platform or one build runs is
        // otherwise an unused function the others refuse. These objects are
        // only compiled: the native test steps run the tests on the host, and
        // the sanitize lanes run them sanitized on Linux.
        var sanitized_test_flags: std.ArrayList([]const u8) = .empty;
        sanitized_test_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
        sanitized_test_flags.append(b.allocator, "-DLINEA_SANITIZED=1") catch @panic("OOM");
        for ([_][]const u8{
            "linea_rt_test",
            "storage_busy_test",
            "preempted_fault_test",
            "interrupted_fault_test",
            "io_test",
            "io_fault_test",
            "net_test",
            "net_fault_test",
            "sim_test",
            "clock_test",
            "clock_fault_test",
            "task_test",
            "task_fault_test",
            "waitset_test",
            "fiber_test",
            "fiber_race_test",
            "fiber_scale_test",
            "fiber_fault_test",
            "fiber_failure_test",
            "sim_fiber_test",
            "sim_cancel_test",
            "sim_waitset_test",
            "sim_foreign_test",
            "foreign_test",
            "parallelism_test",
        }) |test_name| {
            const file = b.path(b.fmt("runtime/{s}.c", .{test_name}));
            native_runtime_step.dependOn(&runtimeObject(b, platform_target, b.fmt("{s}_{s}", .{ test_name, platform.os }), file, runtime_flags.items).step);
            native_runtime_step.dependOn(&runtimeObject(b, platform_target, b.fmt("{s}_{s}_sanitized", .{ test_name, platform.os }), file, sanitized_test_flags.items).step);
        }
    }

    // The runtime objects are compiled for the baseline CPU of the target
    // rather than the CPU of the machine building them. The outcome cache
    // hashes the archive's bytes, and the same source built for two CPU models
    // is two different archives, so a runner whose CPU model changed between
    // runs would discard every recorded outcome.
    const runtime_target = baselineCpu(b, target);

    // Compile Zig's Ryu formatter through C so ASan and MSan instrument its
    // memory accesses too. Passing Zig LLVM IR to Clang would not add the
    // function attributes that enable those checks.
    //
    // The C is emitted with one job. Zig's C backend names each generic
    // instance after its index in the compiler's intern pool, and with several
    // jobs that index depends on how the threads were scheduled, so a busy
    // machine writes different static names into the object. The outcome
    // cache hashes the archive's bytes, and those names alone would discard
    // every recorded outcome on each build. `Step.Compile` cannot pass `-j`,
    // so this runs the compiler directly.
    const float_source = b.addSystemCommand(&.{ b.graph.zig_exe, "build-obj", "-ofmt=c", "-OReleaseSmall", "-j1" });
    float_source.addArgs(&.{
        "-target",
        runtime_target.query.zigTriple(b.allocator) catch @panic("OOM"),
        "-mcpu",
        runtime_target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM"),
        "--dep",
        "decimal_provider",
    });
    float_source.addPrefixedFileArg("-Mroot=", b.path("runtime/float.zig"));
    float_source.addPrefixedFileArg("-Mdecimal_provider=", decimalProvider(b));
    float_source.addArgs(&.{ "--cache-dir", b.cache_root.path orelse ".", "--global-cache-dir", b.graph.global_cache_root.path orelse "." });
    const float_c = float_source.addPrefixedOutputFileArg("-femit-bin=", "linea_float.c");
    var float_flags: std.ArrayList([]const u8) = .empty;
    float_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    float_flags.appendSlice(b.allocator, &.{
        "-std=c11",
        // Zig emits unused target metadata and implements wrapping operations
        // with defined unsigned C arithmetic. Keep all other runtime checks.
        "-Wno-unused-const-variable",
        "-Wno-conversion",
        "-Wno-sign-conversion",
        "-fno-sanitize=unsigned-integer-overflow",
    }) catch @panic("OOM");
    // Archive basenames in source order. Compiler-generated archives include
    // cache paths, which change outcome-cache keys without changing code.
    //
    // Two archives share every object but the one holding the allocator:
    // `linea test` and the conformance runner link the checking one, and
    // `linea build` and `linea run` the other unless asked to check.
    const runtime = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcsD" });
    const runtime_archive = runtime.addOutputFileArg(runtime_symbols.archive_name);
    const checked_runtime = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcsD" });
    const checked_runtime_archive = checked_runtime.addOutputFileArg(runtime_symbols.checked_archive_name);
    var ordinary_nonfiber_objects: std.ArrayList(*std.Build.Step.Compile) = .empty;
    var checked_nonfiber_objects: std.ArrayList(*std.Build.Step.Compile) = .empty;
    for ([_]struct { name: []const u8, file: std.Build.LazyPath, flags: []const []const u8, checked_flags: ?[]const []const u8 = null }{
        .{ .name = "linea_rt", .file = b.path("runtime/linea_rt.c"), .flags = runtime_flags.items, .checked_flags = checked_flags.items },
        .{ .name = "io", .file = b.path("runtime/io.c"), .flags = runtime_flags.items },
        .{ .name = "net", .file = b.path("runtime/net.c"), .flags = runtime_flags.items },
        .{ .name = "clock", .file = b.path("runtime/clock.c"), .flags = runtime_flags.items },
        .{ .name = "task", .file = b.path("runtime/task.c"), .flags = runtime_flags.items },
        .{ .name = "park", .file = b.path("runtime/park.c"), .flags = runtime_flags.items },
        .{ .name = "waitset", .file = b.path("runtime/waitset.c"), .flags = runtime_flags.items },
        .{ .name = "signals", .file = b.path("runtime/signals.c"), .flags = runtime_flags.items },
        .{ .name = "loop", .file = b.path("runtime/loop.c"), .flags = runtime_flags.items },
        .{ .name = "fiber", .file = b.path("runtime/fiber.c"), .flags = runtime_flags.items },
        .{ .name = "completion", .file = b.path("runtime/completion.c"), .flags = runtime_flags.items },
        .{ .name = "foreign", .file = b.path("runtime/foreign.c"), .flags = runtime_flags.items },
        .{ .name = "parallelism", .file = b.path("runtime/parallelism.c"), .flags = runtime_flags.items },
        .{ .name = "context", .file = b.path("runtime/context.c"), .flags = runtime_flags.items },
        .{ .name = "sim", .file = b.path("runtime/sim.c"), .flags = runtime_flags.items },
        .{ .name = "linea_float", .file = float_c, .flags = float_flags.items },
        .{ .name = "math", .file = b.path("runtime/math.c"), .flags = math_flags.items },
    }) |input| {
        const object = runtimeObject(b, runtime_target, input.name, input.file, input.flags);
        runtime.addArtifactArg(object);
        const checked_object = if (input.checked_flags) |flags| runtimeObject(b, runtime_target, input.name, input.file, flags) else object;
        checked_runtime.addArtifactArg(checked_object);
        if (!std.mem.eql(u8, input.name, "fiber")) {
            ordinary_nonfiber_objects.append(b.allocator, object) catch @panic("OOM");
            checked_nonfiber_objects.append(b.allocator, checked_object) catch @panic("OOM");
        }
    }
    const runtime_installs = [_]*std.Build.Step{
        &b.addInstallLibFile(runtime_archive, runtime_symbols.archive_name).step,
        &b.addInstallLibFile(checked_runtime_archive, runtime_symbols.checked_archive_name).step,
    };
    for (runtime_installs) |install| b.getInstallStep().dependOn(install);
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("runtime/zig-float-LICENSE"), "share/licenses/linea/Zig-MIT").step);

    // The compiler reads the runtime's source to check that the two agree on
    // what each trap kind means. Naming it here is what lets a test embed a
    // file from outside `src/`.
    const runtime_source = b.path("runtime/linea_rt.c");

    // A diagnostic's code is an index into the semantics, so a test reads the
    // document to check that every rule it can emit is actually written there.
    const semantics = b.path("docs/linea-semantics.md");

    // The standard library travels in the binary for the reason the semantics
    // does: what `std` names cannot depend on what sits beside the program.
    // Which files it is made of is read from the directory, so adding a module
    // is adding a directory and nothing else.
    const library = libraryManifest(b);

    // Every input the fuzzer has ever found, replayed by every run after it.
    // A list rather than a directory walk: the list is where a reader learns
    // what each input broke, which a filename cannot carry.
    const corpus = b.createModule(.{ .root_source_file = b.path("tests/fuzz/corpus.zig") });

    // The language server's protocol types. Named here rather than imported by
    // path, because it is a package rather than a file of this compiler.
    const lsp_kit = b.dependency("lsp_kit", .{ .target = target, .optimize = optimize });

    const compiler_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addCompilerAssets(compiler_module, runtime_source, semantics, library, corpus, lsp_kit, tracy_options);
    linkTracyClient(b, compiler_module, profiling);
    // Filled in as each part it builds from is made; every heavy step below,
    // and each copy a sequential run orders, comes from it.
    var heavy: HeavySteps = .{
        .b = b,
        .compiler_module = compiler_module,
        .runtime_steps = .{ &runtime.step, &checked_runtime.step },
        .runtime_installs = runtime_installs,
        .checked_runtime_archive = checked_runtime_archive,
        .scratch = scratch,
        .walkers = walkers,
        .sanitize = sanitize,
        .programs = programs,
        .seed = seed,
        .update = update_goldens,
        .opt_levels = opt_levels,
        .test_filters = test_filters,
        .runner_module = undefined,
        .unit_module = undefined,
        .generate_grammar = undefined,
        .guide_gate = undefined,
        .example_tests = undefined,
    };
    const exe = heavy.compiler();
    b.installArtifact(exe);

    const call_coverage_module = b.createModule(.{
        .root_source_file = b.path("build/fiber_call_coverage.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    call_coverage_module.addAnonymousImport("runtime_symbols", .{ .root_source_file = b.path("src/support/runtime_symbols.zig") });
    const call_coverage_tests = b.addTest(.{ .root_module = call_coverage_module });
    const run_coverage_tests = b.addRunArtifact(call_coverage_tests);
    const call_coverage_step = b.step("test-fiber-call-coverage", "Check emitted native-call coverage and omission refusals");
    call_coverage_step.dependOn(&run_coverage_tests.step);
    native_task_step.dependOn(call_coverage_step);
    const call_coverage_tool = b.addExecutable(.{ .name = "fiber-call-coverage", .root_module = call_coverage_module });

    const migration_metrics_module = b.createModule(.{
        .root_source_file = b.path("build/fiber_migration_metrics.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .link_libc = true,
    });
    const migration_metrics_tool = b.addExecutable(.{ .name = "fiber-migration-metrics", .root_module = migration_metrics_module });
    const migration_metrics_tests = b.addRunArtifact(b.addTest(.{ .root_module = migration_metrics_module }));
    const migration_metrics_step = b.step("test-fiber-migration-metrics", "Validate bounded R/N/C/X observations of actual Linea continuation transfers");
    migration_metrics_step.dependOn(&migration_metrics_tests.step);
    native_task_step.dependOn(&migration_metrics_tests.step);

    const scheduling_module = b.createModule(.{
        .root_source_file = b.path("build/fiber_scheduling_measurements.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const scheduling_tool = b.addExecutable(.{ .name = "fiber-scheduling-measurements", .root_module = scheduling_module });
    const scheduling_tests = b.addRunArtifact(b.addTest(.{ .root_module = scheduling_module }));
    native_task_step.dependOn(&scheduling_tests.step);

    const owner_watchdog_step = b.step("test-foreign-owner-watchdog", "Check foreign-owner watchdog deadlines and refusal paths");
    const owner_watchdog_module = b.createModule(.{
        .root_source_file = b.path("tests/cmd/foreign_owner/watchdog.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .link_libc = true,
    });
    const owner_watchdog_tests = b.addTest(.{ .root_module = owner_watchdog_module });
    owner_watchdog_step.dependOn(&b.addRunArtifact(owner_watchdog_tests).step);
    native_task_step.dependOn(owner_watchdog_step);

    const handoff_proof = b.step("test-fiber-handoff-proof", "Compile and force one started Linea continuation across two carriers");
    const completed_wait_proof = b.step("test-fiber-completed-waits", "Force started Linea continuations across completed session and timer waits");
    const completed_io_proof = b.step("test-fiber-completed-io", "Force a started Linea continuation across completed socket I/O");
    const waitset_proof = b.step("test-fiber-waitset-migration", "Migrate a Linea wait-set continuation with retained registrations");
    const join_proof = b.step("test-fiber-completed-joins", "Migrate a Linea continuation after a structured child join");
    const handoff_measurement = b.step("measure-fiber-handoff", "Collect matched plain/traced forced-handoff observations on an idle host");
    const platform_proof = b.step("test-fiber-platform-state", "Check FP, signal and protected-frame state across actual Linea handoffs");
    const task_entry_proof = b.step("test-fiber-task-entry", "Migrate a Linea task through compiler-owned entry eligibility");
    const stealing_proof = b.step("test-fiber-work-stealing", "Resume started Linea continuations through normal idle-carrier stealing");
    const busy_stealing_proof = b.step("test-fiber-busy-stealing", "Steal an already-started Linea continuation while its source runs another Linea task");
    const new_work_proof = b.step("test-fiber-new-work-stealing", "Start queued Linea work on an idle carrier while its source runs another task");
    const completion_proof = b.step("test-fiber-completion-backend", "Run actual Linux completion I/O and timeout retirement before migration");
    const scheduling_proof = b.step("test-fiber-scheduling-controls", "Check matched pinned, placement, forced and stealing Linea workloads without recording measurements");
    const scheduling_measurement = b.step("measure-fiber-scheduling", "Compare scheduling controls on an idle host with matched Linea workloads");
    if (target.result.os.tag != .linux) {
        const unavailable = b.addSystemCommand(&.{ "sh", "-c", "echo 'io_uring completion proof requires Linux' >&2; exit 1" });
        completion_proof.dependOn(&unavailable.step);
    }
    if (migration_supported) {
        if (sanitize == .none) {
            native_task_step.dependOn(scheduling_proof);
            const files = b.addWriteFiles();
            const scheduling_source = files.addCopyFile(b.path("runtime/tests/fiber_migration/scheduling_workload.lin"), "main.lin");
            var binaries: [4]std.Build.LazyPath = undefined;
            var diagnostics: [4]std.Build.LazyPath = undefined;
            var manifests: [6]std.Build.LazyPath = undefined;
            for ([_]bool{ false, true }, 0..) |diagnostic, variant| {
                for ([_][]const u8{ "pinned", "forced", "stealing" }, 0..) |policy, i| {
                    var flags: std.ArrayList([]const u8) = .empty;
                    flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
                    if (diagnostic) flags.appendSlice(b.allocator, &.{ "-DLINEA_FIBER_MIGRATION_TRACE_TEST=1", "-DLINEA_FIBER_SCHEDULING_COUNTS_TEST=1" }) catch @panic("OOM");
                    if (i == 0) flags.append(b.allocator, "-DLINEA_FIBER_SCHEDULING_PINNED_TEST=1") catch @panic("OOM");
                    if (i == 1) flags.appendSlice(b.allocator, &.{ "-DLINEA_FIBER_MIGRATION_TEST=1", "-DLINEA_FIBER_FORCED_HANDOFF_TEST=1", "-DLINEA_FIBER_PAUSES=1" }) catch @panic("OOM");
                    const archive = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcsD" });
                    const scheduling_archive = archive.addOutputFileArg(runtime_symbols.archive_name);
                    for (ordinary_nonfiber_objects.items) |object| archive.addArtifactArg(object);
                    archive.addArtifactArg(runtimeObject(b, runtime_target, b.fmt("fiber_scheduling_{s}_{d}", .{ policy, variant }), b.path("runtime/fiber.c"), flags.items));
                    const compile = b.addSystemCommand(&.{"env"});
                    compile.addPrefixedFileArg("LINEA_RUNTIME=", scheduling_archive);
                    compile.addFileArg(exe.getEmittedBin());
                    compile.addArgs(&.{ "build", "--keep" });
                    compile.addFileArg(scheduling_source);
                    compile.addArg("-o");
                    const binary = compile.addOutputFileArg("scheduling-workload");
                    const selected = if (diagnostic) &diagnostics else &binaries;
                    selected[if (i == 0) 0 else i + 1] = binary;
                    if (i == 0) selected[1] = binary;
                    const coverage = b.addRunArtifact(call_coverage_tool);
                    coverage.addFileArg(binary.dirname().path(b, "scheduling-workload.mlir"));
                    coverage.step.dependOn(&compile.step);
                    coverage.step.dependOn(&run_coverage_tests.step);
                    manifests[variant * 3 + i] = coverage.captureStdOut(.{});
                }
            }
            const populations = b.addRunArtifact(scheduling_tool);
            populations.addArg("--populations");
            for (diagnostics) |binary| populations.addFileArg(binary);
            for (manifests[3..]) |manifest| populations.addFileInput(manifest);
            populations.step.dependOn(&scheduling_tests.step);
            populations.has_side_effects = true;
            const population_report = populations.captureStdOut(.{});
            scheduling_proof.dependOn(&populations.step);
            scheduling_measurement.dependOn(&b.addInstallFile(population_report, "fiber-scheduling-populations.tsv").step);
            for ([_]bool{ false, true }) |measure| {
                const run = b.addRunArtifact(scheduling_tool);
                run.addArg(if (measure) "--measure" else "--check");
                for (binaries) |binary| run.addFileArg(binary);
                for (manifests) |manifest| run.addFileInput(manifest);
                run.step.dependOn(&scheduling_tests.step);
                run.has_side_effects = true;
                if (measure) {
                    run.step.dependOn(&populations.step);
                    const observations = run.captureStdOut(.{});
                    scheduling_measurement.dependOn(&b.addInstallFile(observations, "fiber-scheduling-measurements.tsv").step);
                } else scheduling_proof.dependOn(&run.step);
            }
        } else {
            const unavailable = b.addSystemCommand(&.{ "sh", "-c", "echo 'scheduling comparison requires an unsanitized runtime' >&2; exit 1" });
            scheduling_proof.dependOn(&unavailable.step);
            scheduling_measurement.dependOn(&unavailable.step);
        }
        native_task_step.dependOn(stealing_proof);
        native_task_step.dependOn(busy_stealing_proof);
        native_task_step.dependOn(new_work_proof);
        const busy_files = b.addWriteFiles();
        const busy_source = busy_files.addCopyFile(b.path("runtime/tests/fiber_migration/busy_source.lin"), "main.lin");
        var busy_flags: std.ArrayList([]const u8) = .empty;
        busy_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
        busy_flags.append(b.allocator, "-DLINEA_FIBER_BUSY_SOURCE_TEST=1") catch @panic("OOM");
        const busy_fiber = runtimeObject(b, runtime_target, "fiber_busy_source", b.path("runtime/fiber.c"), busy_flags.items);
        const new_files = b.addWriteFiles();
        const new_source = new_files.addCopyFile(b.path("runtime/tests/fiber_migration/new_work.lin"), "main.lin");
        var new_flags: std.ArrayList([]const u8) = .empty;
        new_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
        new_flags.append(b.allocator, "-DLINEA_FIBER_NEW_WORK_TEST=1") catch @panic("OOM");
        const new_fiber = runtimeObject(b, runtime_target, "fiber_new_work", b.path("runtime/fiber.c"), new_flags.items);
        const AllocationMode = struct {
            name: []const u8,
            archive: std.Build.LazyPath,
            objects: []const *std.Build.Step.Compile,
        };
        for ([_]AllocationMode{
            .{ .name = runtime_symbols.archive_name, .archive = runtime_archive, .objects = ordinary_nonfiber_objects.items },
            .{ .name = runtime_symbols.checked_archive_name, .archive = checked_runtime_archive, .objects = checked_nonfiber_objects.items },
        }) |allocation| {
            const stealing_archive = allocation.archive;
            for ([_]bool{ false, true }) |new_work| {
                const busy_runtime = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcsD" });
                const busy_archive = busy_runtime.addOutputFileArg(allocation.name);
                for (allocation.objects) |object| busy_runtime.addArtifactArg(object);
                busy_runtime.addArtifactArg(if (new_work) new_fiber else busy_fiber);
                const compile_busy = b.addSystemCommand(&.{"env"});
                compile_busy.addPrefixedFileArg("LINEA_RUNTIME=", busy_archive);
                if (toolchain.sanitizeVariable(sanitize.flag())) |variable| compile_busy.setEnvironmentVariable(variable.name, variable.value);
                compile_busy.addFileArg(exe.getEmittedBin());
                compile_busy.addArg("build");
                compile_busy.addFileArg(if (new_work) new_source else busy_source);
                compile_busy.addArg("-o");
                const busy_binary = compile_busy.addOutputFileArg("busy-stealing");
                const run_busy = b.addRunArtifact(migration_metrics_tool);
                run_busy.addArg(if (new_work) "--check-new-work-run" else "--check-busy-run");
                run_busy.addFileArg(busy_binary);
                if (sanitize == .address) run_busy.setEnvironmentVariable("ASAN_OPTIONS", "detect_stack_use_after_return=1:detect_leaks=1:halt_on_error=1");
                if (sanitize == .thread) run_busy.setEnvironmentVariable("TSAN_OPTIONS", "halt_on_error=1:exitcode=66");
                run_busy.has_side_effects = true;
                run_busy.expectExitCode(0);
                (if (new_work) new_work_proof else busy_stealing_proof).dependOn(&run_busy.step);
            }
            for ([_][]const u8{ "stealing.lin", "stealing_owner.lin", "pinned.lin", "unknown_pinned.lin" }) |fixture| {
                const files = b.addWriteFiles();
                const main_source = files.addCopyFile(b.path(b.fmt("runtime/tests/fiber_migration/{s}", .{fixture})), "main.lin");
                if (std.mem.eql(u8, fixture, "stealing_owner.lin")) {
                    _ = files.addCopyFile(b.path("runtime/tests/fiber_migration/owner_resource/owner_resource.lin"), "owner_resource/owner_resource.lin");
                }
                const compile = b.addSystemCommand(&.{"env"});
                compile.addPrefixedFileArg("LINEA_RUNTIME=", stealing_archive);
                if (toolchain.sanitizeVariable(sanitize.flag())) |variable| compile.setEnvironmentVariable(variable.name, variable.value);
                compile.addFileArg(exe.getEmittedBin());
                compile.addArg("build");
                compile.addFileArg(main_source);
                compile.addArg("-o");
                const binary = compile.addOutputFileArg("fiber-stealing");
                const run = b.addRunArtifact(migration_metrics_tool);
                run.addArg("--check-run");
                run.addFileArg(binary);
                if (sanitize == .address) run.setEnvironmentVariable("ASAN_OPTIONS", "detect_stack_use_after_return=1:detect_leaks=1:halt_on_error=1");
                if (sanitize == .thread) run.setEnvironmentVariable("TSAN_OPTIONS", "halt_on_error=1:exitcode=66");
                run.has_side_effects = true;
                run.expectExitCode(0);
                stealing_proof.dependOn(&run.step);
            }
        }
        native_task_step.dependOn(handoff_proof);
        native_task_step.dependOn(completed_wait_proof);
        native_task_step.dependOn(completed_io_proof);
        native_task_step.dependOn(waitset_proof);
        native_task_step.dependOn(join_proof);
        native_task_step.dependOn(migration_metrics_step);
        native_task_step.dependOn(platform_proof);
        native_task_step.dependOn(task_entry_proof);
        var measurement_binaries: [2]?std.Build.LazyPath = .{ null, null };
        var measurement_manifests: [2]?std.Build.LazyPath = .{ null, null };
        var entry_archive: ?std.Build.LazyPath = null;
        const ProofCase = struct {
            source: []const u8,
            completed_wait: bool = true,
            delay_notifier: bool = false,
            stale_cookie: bool = false,
            trace: bool = false,
            refusal_probes: bool = false,
            platform: bool = false,
            entry_provenance: bool = false,
            pinned_start: bool = false,
            keep: bool = true,
            guard_fault: bool = false,
            sanitizer_fault: bool = false,
            normal_execution: bool = false,
            checked: bool = true,
            ring: enum { none, ordinary, own_first, cancel_first, partial_submit, interrupted, shortage, unsupported, unavailable, cancel_retry, capacity, stale_reuse, accept_failure, accept_tie, counter_wrap, generation_limit } = .none,
            completion: enum { ordinary, rearm, timer_tie, rearm_failure } = .ordinary,
        };
        for ([_]ProofCase{
            .{ .source = "continuation.lin", .completed_wait = false },
            .{ .source = "continuation.lin", .completed_wait = false, .entry_provenance = true },
            .{ .source = "continuation.lin", .completed_wait = false, .entry_provenance = true, .keep = false },
            .{ .source = "unproven.lin", .completed_wait = false, .entry_provenance = true, .pinned_start = true },
            .{ .source = "pinned.lin", .completed_wait = false, .entry_provenance = true },
            .{ .source = "unknown_pinned.lin", .completed_wait = false, .entry_provenance = true },
            .{ .source = "continuation.lin", .completed_wait = false, .platform = true },
            .{ .source = "continuation.lin", .completed_wait = false, .platform = true, .sanitizer_fault = true },
            .{ .source = "overflow_after_handoff.lin", .completed_wait = false, .platform = true, .guard_fault = true },
            .{ .source = "continuation.lin", .completed_wait = false, .trace = true },
            .{ .source = "continuation.lin", .completed_wait = false, .trace = true, .refusal_probes = true },
            .{ .source = "pinned.lin", .completed_wait = false },
            .{ .source = "unknown_pinned.lin", .completed_wait = false, .trace = true },
            .{ .source = "unproven.lin", .completed_wait = false, .trace = true },
            .{ .source = "session.lin" },
            .{ .source = "timer.lin" },
            .{ .source = "owner.lin" },
            .{ .source = "io.lin" },
            .{ .source = "io.lin", .ring = .ordinary },
            .{ .source = "io_timeout.lin", .ring = .ordinary },
            .{ .source = "io_buffer_reuse.lin", .ring = .ordinary },
            .{ .source = "io_failure.lin", .ring = .ordinary },
            .{ .source = "io_eof.lin", .ring = .ordinary },
            .{ .source = "io_accept.lin", .ring = .ordinary },
            .{ .source = "io_connect.lin", .ring = .ordinary },
            .{ .source = "io_connect_timeout.lin", .ring = .ordinary },
            .{ .source = "io_write.lin", .ring = .ordinary },
            .{ .source = "io_capacity.lin", .ring = .capacity },
            .{ .source = "io_stale_reuse.lin", .ring = .stale_reuse },
            .{ .source = "io_accept_failure.lin", .ring = .accept_failure },
            .{ .source = "io_accept.lin", .ring = .accept_tie },
            .{ .source = "io.lin", .ring = .counter_wrap },
            .{ .source = "io_stale_reuse.lin", .ring = .generation_limit },
            .{ .source = "io_normal.lin", .ring = .ordinary, .normal_execution = true },
            .{ .source = "io_normal.lin", .ring = .ordinary, .normal_execution = true, .checked = false },
            .{ .source = "io_timeout.lin", .ring = .own_first },
            .{ .source = "io_timeout.lin", .ring = .cancel_first },
            .{ .source = "io_timeout.lin", .ring = .partial_submit },
            .{ .source = "io.lin", .ring = .interrupted },
            .{ .source = "io.lin", .ring = .shortage },
            .{ .source = "io.lin", .ring = .unsupported },
            .{ .source = "io.lin", .ring = .unavailable },
            .{ .source = "io_timeout.lin", .ring = .cancel_retry },
            .{ .source = "io.lin", .trace = true },
            .{ .source = "io.lin", .stale_cookie = true },
            .{ .source = "io.lin", .completion = .rearm },
            .{ .source = "io.lin", .completion = .timer_tie },
            .{ .source = "io_timeout.lin" },
            .{ .source = "io_failure.lin" },
            .{ .source = "io_rearm_failure.lin", .completion = .rearm_failure },
            .{ .source = "join.lin" },
            .{ .source = "waitset.lin" },
            .{ .source = "waitset.lin", .delay_notifier = true },
            .{ .source = "waitset_io.lin" },
            .{ .source = "timed_session.lin" },
            .{ .source = "session.lin", .delay_notifier = true },
            .{ .source = "session.lin", .delay_notifier = true, .trace = true },
        }) |proof_case| {
            // Sanitizers own stack-fault reporting. This case observes the
            // unsanitized runtime's exact handler and is tested in that mode.
            if (proof_case.guard_fault and sanitize != .none) continue;
            if (proof_case.sanitizer_fault and sanitize == .none) continue;
            if (proof_case.ring != .none and target.result.os.tag != .linux) continue;
            const completed_wait = proof_case.completed_wait;
            const files = b.addWriteFiles();
            const main_source = files.addCopyFile(b.path(b.fmt("runtime/tests/fiber_migration/{s}", .{proof_case.source})), "main.lin");
            if (std.mem.eql(u8, proof_case.source, "owner.lin")) {
                _ = files.addCopyFile(b.path("runtime/tests/fiber_migration/owner_resource/owner_resource.lin"), "owner_resource/owner_resource.lin");
            }
            if (std.mem.startsWith(u8, proof_case.source, "io_")) {
                _ = files.addCopyFile(b.path("runtime/tests/fiber_migration/io_errors/io_errors.lin"), "io_errors/io_errors.lin");
            }
            // The application is entirely Linea. Link canonical checked runtime
            // objects with an internal deterministic scheduling configuration;
            // no project-native files replace runtime definitions.
            var handoff_flags: std.ArrayList([]const u8) = .empty;
            handoff_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
            handoff_flags.appendSlice(b.allocator, &.{ "-DLINEA_FIBER_MIGRATION_TEST=1", "-DLINEA_FIBER_FORCED_HANDOFF_TEST=1", "-DLINEA_FIBER_PAUSES=1" }) catch @panic("OOM");
            if (completed_wait) handoff_flags.append(b.allocator, "-DLINEA_FIBER_WAIT_FOR_PARK_TEST=1") catch @panic("OOM");
            if (proof_case.delay_notifier) handoff_flags.append(b.allocator, "-DLINEA_FIBER_DELAY_NOTIFIER_TEST=1") catch @panic("OOM");
            if (proof_case.stale_cookie) handoff_flags.append(b.allocator, "-DLINEA_FIBER_STALE_COOKIE_TEST=1") catch @panic("OOM");
            if (proof_case.trace) handoff_flags.append(b.allocator, "-DLINEA_FIBER_MIGRATION_TRACE_TEST=1") catch @panic("OOM");
            if (proof_case.refusal_probes) handoff_flags.append(b.allocator, "-DLINEA_FIBER_REFUSAL_PROBES_TEST=1") catch @panic("OOM");
            if (proof_case.platform) handoff_flags.appendSlice(b.allocator, &.{ "-DLINEA_FIBER_PLATFORM_STATE_TEST=1", "-fstack-protector-all" }) catch @panic("OOM");
            if (proof_case.sanitizer_fault) handoff_flags.append(b.allocator, "-DLINEA_FIBER_SANITIZER_FAULT_TEST=1") catch @panic("OOM");
            if (proof_case.ring != .none) handoff_flags.append(b.allocator, "-DLINEA_FIBER_RING_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .none) handoff_flags.append(b.allocator, "-DLINEA_FIBER_READINESS_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .own_first) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_OWN_FIRST_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .cancel_first) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_CANCEL_FIRST_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .partial_submit) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_PARTIAL_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .interrupted) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_INTERRUPTED_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .shortage) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_SHORTAGE_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .unsupported) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_UNSUPPORTED_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .unavailable) handoff_flags.appendSlice(b.allocator, &.{ "-DLINEA_COMPLETION_DENIED_TEST=1", "-DLINEA_FIBER_RING_FALLBACK_TEST=1" }) catch @panic("OOM");
            if (proof_case.ring == .cancel_retry) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_CANCEL_RETRY_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .capacity) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_CAPACITY_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .stale_reuse) handoff_flags.appendSlice(b.allocator, &.{ "-DLINEA_FIBER_STALE_COOKIE_TEST=1", "-DLINEA_COMPLETION_STALE_COOKIE_TEST=1" }) catch @panic("OOM");
            if (proof_case.ring == .accept_failure) handoff_flags.append(b.allocator, "-DLINEA_NET_ACCEPT_CONFIGURE_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .accept_tie) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_ACCEPT_TIE_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .counter_wrap) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_COUNTER_TEST=1") catch @panic("OOM");
            if (proof_case.ring == .generation_limit) handoff_flags.append(b.allocator, "-DLINEA_COMPLETION_GENERATION_TEST=1") catch @panic("OOM");
            if (proof_case.entry_provenance) handoff_flags.append(b.allocator, "-DLINEA_FIBER_ENTRY_PROVENANCE_TEST=1") catch @panic("OOM");
            if (std.mem.eql(u8, proof_case.source, "unproven.lin") and !proof_case.entry_provenance) handoff_flags.append(b.allocator, "-DLINEA_FIBER_UNPROVEN_ENTRY_TEST=1") catch @panic("OOM");
            switch (proof_case.completion) {
                .ordinary => {},
                .rearm => handoff_flags.append(b.allocator, "-DLINEA_FIBER_FORCE_REARM_TEST=1") catch @panic("OOM"),
                .timer_tie => handoff_flags.append(b.allocator, "-DLINEA_FIBER_FORCE_TIMER_TIE_TEST=1") catch @panic("OOM"),
                .rearm_failure => handoff_flags.append(b.allocator, "-DLINEA_FIBER_FORCE_REARM_FAILURE_TEST=1") catch @panic("OOM"),
            }
            const handoff_runtime = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcsD" });
            const handoff_archive = handoff_runtime.addOutputFileArg(if (proof_case.checked) runtime_symbols.checked_archive_name else runtime_symbols.archive_name);
            for (if (proof_case.checked) checked_nonfiber_objects.items else ordinary_nonfiber_objects.items) |object| {
                if (proof_case.ring != .none and std.mem.eql(u8, object.name, "completion")) {
                    handoff_runtime.addArtifactArg(runtimeObject(b, runtime_target, "completion_order", b.path("runtime/completion.c"), handoff_flags.items));
                } else if (proof_case.ring == .accept_failure and std.mem.eql(u8, object.name, "net")) {
                    handoff_runtime.addArtifactArg(runtimeObject(b, runtime_target, "net_accept_failure", b.path("runtime/net.c"), handoff_flags.items));
                } else if (proof_case.pinned_start and std.mem.eql(u8, object.name, "task")) {
                    var pinned_flags: std.ArrayList([]const u8) = .empty;
                    pinned_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
                    pinned_flags.append(b.allocator, "-Dlinea_task_start_migratable=linea_task_start_unavailable_test") catch @panic("OOM");
                    handoff_runtime.addArtifactArg(runtimeObject(b, runtime_target, "task_pinned_start", b.path("runtime/task.c"), pinned_flags.items));
                } else handoff_runtime.addArtifactArg(object);
            }
            handoff_runtime.addArtifactArg(runtimeObject(b, runtime_target, "fiber_handoff", b.path("runtime/fiber.c"), if (proof_case.normal_execution) runtime_flags.items else handoff_flags.items));
            if (proof_case.entry_provenance and !proof_case.pinned_start and proof_case.keep and std.mem.eql(u8, proof_case.source, "continuation.lin")) entry_archive = handoff_archive;
            const compile = b.addSystemCommand(&.{"env"});
            compile.addPrefixedFileArg("LINEA_RUNTIME=", handoff_archive);
            if (toolchain.sanitizeVariable(sanitize.flag())) |variable| compile.setEnvironmentVariable(variable.name, variable.value);
            compile.addFileArg(exe.getEmittedBin());
            compile.addArg("build");
            if (proof_case.keep) compile.addArg("--keep");
            compile.addFileArg(main_source);
            compile.addArg("-o");
            const binary = compile.addOutputFileArg("fiber-handoff");
            const manifest: ?std.Build.LazyPath = if (proof_case.keep) blk: {
                const check_calls = b.addRunArtifact(call_coverage_tool);
                check_calls.addFileArg(binary.dirname().path(b, "fiber-handoff.mlir"));
                if (sanitize.flag()) |name| check_calls.addArg(name);
                check_calls.step.dependOn(&compile.step);
                check_calls.step.dependOn(&run_coverage_tests.step);
                break :blk check_calls.captureStdOut(.{});
            } else null;
            if (std.mem.eql(u8, proof_case.source, "continuation.lin") and !proof_case.refusal_probes and !proof_case.platform and !proof_case.entry_provenance) {
                const index: usize = @intFromBool(proof_case.trace);
                measurement_binaries[index] = binary;
                measurement_manifests[index] = manifest;
            }
            const run_proof = b.addSystemCommand(&.{"env"});
            if (sanitize == .address) run_proof.setEnvironmentVariable("ASAN_OPTIONS", "detect_stack_use_after_return=1:detect_leaks=1:halt_on_error=1");
            if (sanitize == .thread) run_proof.setEnvironmentVariable("TSAN_OPTIONS", "halt_on_error=1:exitcode=66");
            run_proof.addFileArg(binary);
            if (manifest) |coverage| run_proof.addFileInput(coverage);
            run_proof.has_side_effects = true;
            if (proof_case.sanitizer_fault) {
                run_proof.expectExitCode(if (sanitize == .thread) 66 else 1);
                run_proof.expectStdErrMatch("native migration: injecting a sanitizer fault after transfer");
                run_proof.expectStdErrMatch(if (sanitize == .thread) "ThreadSanitizer: data race" else "AddressSanitizer: stack-buffer-overflow");
            } else if (proof_case.guard_fault) {
                run_proof.addCheck(.{ .expect_term = .{ .signal = .ABRT } });
                run_proof.expectStdErrEqual("linea: a stack overflowed\n");
            } else {
                run_proof.expectExitCode(0);
                if (proof_case.platform) run_proof.expectStdErrEqual("native migration: FP control, carrier signals and protected frames passed\n");
            }
            if (proof_case.stale_cookie) run_proof.expectStdErrEqual("native migration: stale poll cookie rejected after reclamation\n");
            if (proof_case.normal_execution) {
                run_proof.expectStdErrMatch("native completion: kernel connect readiness canceled");
            } else if (proof_case.ring != .none and proof_case.ring != .unavailable) run_proof.expectStdErrMatch("native completion: own and control requests retired before migration");
            if (proof_case.ring == .own_first) run_proof.expectStdErrMatch("native completion: own CQE retired before cancel CQE");
            if (proof_case.ring == .cancel_first) run_proof.expectStdErrMatch("native completion: cancel CQE retired before own CQE");
            if (proof_case.ring == .partial_submit) run_proof.expectStdErrMatch("native completion: partial submission retained the unconsumed control");
            if (proof_case.ring == .interrupted) run_proof.expectStdErrMatch("native completion: interrupted submission retained its request");
            if (proof_case.ring == .shortage) run_proof.expectStdErrMatch("native completion: submission shortage retained its request");
            if (proof_case.ring == .unsupported) run_proof.expectStdErrMatch("native completion: unsupported operation retired before readiness fallback");
            if (proof_case.ring == .unavailable) run_proof.expectStdErrMatch("native completion: unavailable kernel used readiness fallback");
            if (proof_case.ring == .cancel_retry) run_proof.expectStdErrMatch("native completion: transient cancellation failure retained its original");
            if (proof_case.ring == .capacity) {
                run_proof.expectStdErrMatch("native completion: admission preserved its live original");
                run_proof.expectStdErrMatch("native completion: both rings drained after overflow");
            }
            if (proof_case.ring == .stale_reuse) run_proof.expectStdErrMatch("native completion: reclaimed cookie rejected during slot reuse");
            if (proof_case.ring == .accept_failure) {
                run_proof.expectStdErrMatch("native completion: kernel accept retired");
                run_proof.expectStdErrMatch("native completion: unconfigured accepted descriptor closed");
            }
            if (proof_case.ring == .accept_tie) run_proof.expectStdErrMatch("native completion: accepted descriptor won its expired deadline");
            if (proof_case.ring == .counter_wrap) run_proof.expectStdErrMatch("native completion: ring counter wrap preserves distances");
            if (proof_case.ring == .generation_limit) run_proof.expectStdErrMatch("native completion: exhausted generation refused slot reuse");
            if (proof_case.ring != .none and std.mem.eql(u8, proof_case.source, "io_accept.lin")) run_proof.expectStdErrMatch("native completion: kernel accept retired");
            if (proof_case.ring != .none and std.mem.eql(u8, proof_case.source, "io_connect.lin")) run_proof.expectStdErrMatch("native completion: kernel connect readiness completed");
            if (proof_case.ring != .none and std.mem.eql(u8, proof_case.source, "io_connect_timeout.lin")) run_proof.expectStdErrMatch("native completion: kernel connect readiness canceled");
            if (proof_case.ring != .none and std.mem.eql(u8, proof_case.source, "io_write.lin")) run_proof.expectStdErrMatch("native completion: kernel send retired");
            if ((proof_case.ring == .ordinary or proof_case.ring == .interrupted or proof_case.ring == .shortage) and std.mem.eql(u8, proof_case.source, "io.lin")) run_proof.expectStdErrMatch("native completion: kernel receive completed");
            if (proof_case.ring != .none and std.mem.eql(u8, proof_case.source, "io_eof.lin")) run_proof.expectStdErrMatch("native completion: kernel receive completed");
            if (proof_case.ring != .none and std.mem.eql(u8, proof_case.source, "io_failure.lin")) run_proof.expectStdErrMatch("native completion: kernel receive reported reset");
            switch (proof_case.completion) {
                .ordinary => {},
                .rearm => run_proof.expectStdErrEqual("native migration: spurious readiness rearmed with a new cookie\n"),
                .timer_tie => run_proof.expectStdErrEqual("native migration: timer-first readiness tie completed\n"),
                .rearm_failure => run_proof.expectStdErrEqual("native migration: rearm failure propagated after retirement\n"),
            }
            if (proof_case.trace) {
                const trace = run_proof.captureStdErr(.{});
                const inspect_trace = b.addRunArtifact(migration_metrics_tool);
                inspect_trace.addFileArg(trace);
                if (proof_case.refusal_probes) inspect_trace.addArg("refusal_probes");
                if (proof_case.delay_notifier) inspect_trace.addArg("source_busy");
                if (std.mem.eql(u8, proof_case.source, "unknown_pinned.lin")) inspect_trace.addArg("pinned");
                if (std.mem.eql(u8, proof_case.source, "unproven.lin")) inspect_trace.addArg("unproven");
                inspect_trace.step.dependOn(&migration_metrics_tests.step);
                migration_metrics_step.dependOn(&inspect_trace.step);
            } else if (proof_case.ring != .none) {
                completion_proof.dependOn(&run_proof.step);
            } else if (proof_case.entry_provenance) {
                task_entry_proof.dependOn(&run_proof.step);
            } else if (proof_case.platform) {
                platform_proof.dependOn(&run_proof.step);
            } else {
                (if (std.mem.eql(u8, proof_case.source, "join.lin")) join_proof else if (std.mem.startsWith(u8, proof_case.source, "waitset")) waitset_proof else if (std.mem.startsWith(u8, proof_case.source, "io")) completed_io_proof else if (completed_wait) completed_wait_proof else handoff_proof).dependOn(&run_proof.step);
            }
        }
        const object_files = b.addWriteFiles();
        const object_source = object_files.addCopyFile(b.path("runtime/tests/fiber_migration/entry_object.lin"), "main.lin");
        _ = object_files.add("linea.json", "{\"kind\":\"library\"}\n");
        const compile_object = b.addSystemCommand(&.{"env"});
        if (toolchain.sanitizeVariable(sanitize.flag())) |variable| compile_object.setEnvironmentVariable(variable.name, variable.value);
        compile_object.addFileArg(exe.getEmittedBin());
        compile_object.addArgs(&.{ "build", "--keep" });
        compile_object.addFileArg(object_source);
        compile_object.addArg("-o");
        const entry_object = compile_object.addOutputFileArg("entry.o");
        const check_object_calls = b.addRunArtifact(call_coverage_tool);
        check_object_calls.addFileArg(entry_object.dirname().path(b, "entry.o.mlir"));
        if (sanitize.flag()) |name| check_object_calls.addArg(name);
        check_object_calls.step.dependOn(&compile_object.step);
        check_object_calls.step.dependOn(&run_coverage_tests.step);
        const object_manifest = check_object_calls.captureStdOut(.{});
        const object_test_module = b.createModule(.{
            .root_source_file = b.path("build/fiber_object_entry.zig"),
            .target = target,
            .optimize = .Debug,
            .link_libc = true,
        });
        object_test_module.addAnonymousImport("object_ir", .{ .root_source_file = entry_object.dirname().path(b, "entry.o.mlir") });
        const run_object_test = if (sanitize.flag()) |sanitizer| sanitized: {
            // Let the C toolchain supply its matching sanitizer runtime. The
            // Zig harness only calls the separately compiled Linea entry.
            const harness = b.addTest(.{ .root_module = object_test_module, .emit_object = true });
            const link = b.addSystemCommand(&.{ "cc", b.fmt("-fsanitize={s}", .{sanitizer}), "-fsanitize=undefined", "-fno-sanitize-recover=all" });
            link.addArtifactArg(harness);
            link.addFileArg(entry_object);
            link.addFileArg(entry_archive.?);
            link.addArgs(&.{ "-lm", "-lpthread", "-o" });
            const binary = link.addOutputFileArg("object-entry");
            const run = b.addSystemCommand(&.{"env"});
            run.addFileArg(binary);
            break :sanitized run;
        } else ordinary: {
            object_test_module.addObjectFile(entry_object);
            object_test_module.addObjectFile(entry_archive.?);
            break :ordinary b.addRunArtifact(b.addTest(.{ .root_module = object_test_module }));
        };
        run_object_test.addFileInput(object_manifest);
        run_object_test.has_side_effects = true;
        task_entry_proof.dependOn(&run_object_test.step);
        const measure = b.addRunArtifact(migration_metrics_tool);
        measure.addArg("--measure");
        for (measurement_binaries, measurement_manifests) |binary, manifest| {
            measure.addFileArg(binary.?);
            measure.addFileInput(manifest.?);
        }
        measure.step.dependOn(&migration_metrics_tests.step);
        measure.has_side_effects = true;
        const measurements = measure.captureStdOut(.{});
        handoff_measurement.dependOn(&b.addInstallFile(measurements, "fiber-handoff-measurements.tsv").step);
    } else {
        const unavailable = b.addSystemCommand(&.{ "sh", "-c", "echo 'forced handoff proof is unavailable on this target or sanitizer' >&2; exit 1" });
        handoff_proof.dependOn(&unavailable.step);
        completed_io_proof.dependOn(&unavailable.step);
        waitset_proof.dependOn(&unavailable.step);
        join_proof.dependOn(&unavailable.step);
        migration_metrics_step.dependOn(&unavailable.step);
        completed_wait_proof.dependOn(&unavailable.step);
        handoff_measurement.dependOn(&unavailable.step);
        platform_proof.dependOn(&unavailable.step);
        task_entry_proof.dependOn(&unavailable.step);
        stealing_proof.dependOn(&unavailable.step);
        busy_stealing_proof.dependOn(&unavailable.step);
        new_work_proof.dependOn(&unavailable.step);
        completion_proof.dependOn(&unavailable.step);
        scheduling_proof.dependOn(&unavailable.step);
        scheduling_measurement.dependOn(&unavailable.step);
    }

    const run_step = b.step("run", "Run the compiler");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    // The editor grammar is generated rather than committed, so the gates read
    // real output and no stale artefact can exist. `grammar.js` is the only
    // source of it in the tree.
    const ts_dir = tree_sitter_dir;

    // The CLI finds grammars through a per-user configuration, and what it
    // does without one depends on its version: some fall back to the grammar
    // in the working directory, and some parse nothing and exit 0 -- the
    // vacuous pass the refused chain below exists to catch, which it did, on
    // a runner whose home directory had never been configured. The build
    // writes its own configuration and points every invocation at it, so
    // the gates read the same grammar on every machine and no host's
    // dotfiles are part of the answer.
    const ts_config_dir = b.pathFromRoot(".zig-cache/tree-sitter");
    {
        const io = b.graph.io;
        b.build_root.handle.createDirPath(io, ".zig-cache/tree-sitter") catch {};
        b.build_root.handle.writeFile(io, .{
            .sub_path = ".zig-cache/tree-sitter/config.json",
            .data = b.fmt("{{\"parser-directories\": [\"{s}\"]}}", .{b.pathFromRoot("editor-support")}),
        }) catch {};
    }

    const generate_grammar = b.addSystemCommand(&.{ "tree-sitter", "generate", "-o", "src" });
    generate_grammar.setCwd(b.path(ts_dir));
    generate_grammar.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
    // Declared so the step reruns when the source changes rather than never.
    generate_grammar.addFileInput(b.path(ts_dir ++ "/grammar.js"));
    generate_grammar.has_side_effects = true;

    // The conformance suite drives the real pipeline through a real binary,
    // so the goldens record what a user would see.
    const conformance_module = b.createModule(.{
        .root_source_file = b.path("src/conformance_main.zig"),
        .target = target,
        .optimize = if (safe_runner and optimize == .Debug) .ReleaseSafe else optimize,
    });
    addCompilerAssets(conformance_module, runtime_source, semantics, library, corpus, lsp_kit, tracy_options);
    linkTracyClient(b, conformance_module, profiling);

    heavy.runner_module = conformance_module;
    heavy.generate_grammar = &generate_grammar.step;
    const conformance = heavy.runner();
    const conformance_runner = b.step("conformance-runner", "Build the conformance runner for narrowed corpus checks");
    conformance_runner.dependOn(&b.addInstallArtifact(conformance, .{}).step);
    // Relative imports from `test_main` make shared compiler files one module
    // instance. The unit-only scope runs this same universe without integrations.
    const debug_test_module = joined: {
        const module = b.createModule(.{
            .root_source_file = b.path("src/test_main.zig"),
            .target = target,
            .optimize = optimize,
        });
        addCompilerAssets(module, runtime_source, semantics, library, corpus, lsp_kit, tracy_options);
        addConformanceAssets(b, module);
        module.addOptions("test_options", test_options);
        linkTracyClient(b, module, profiling);
        break :joined module;
    };
    heavy.unit_module = debug_test_module;
    const debug_tests = heavy.unitTests();
    const run_debug_tests = heavy.unitRun(debug_tests);
    // Cache hashing reads declared inputs even when their tests are filtered
    // out. The same manifest reaches every fuzzer without editor assets.
    const fuzz_module = b.createModule(.{
        .root_source_file = debug_test_module.root_source_file,
        .target = target,
        .optimize = optimize,
    });
    addCompilerAssets(fuzz_module, runtime_source, semantics, library, corpus, lsp_kit, tracy_options);
    fuzz_module.addOptions("test_options", test_options);
    linkTracyClient(b, fuzz_module, profiling);
    // Every fuzz target by default. A target whose one input compiles whole
    // programs is named `fuzz-slow:` so it can be searched apart with a run
    // count of its own; `-Dfuzz-filter=fuzz:` or `-Dfuzz-filter=fuzz-slow:`
    // selects one group. CI searches only `fuzz:`, weekly.
    const fuzz_filters: []const []const u8 =
        if (fuzz_filter) |f| &.{f} else &.{ "fuzz:", "fuzz-slow:" };
    const fuzz_tests = b.addTest(.{ .root_module = fuzz_module, .filters = fuzz_filters });
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);

    const run_conformance = heavy.corpus(conformance, exe);

    // The soundness matrix, and generated programs over heap storage with
    // their mutants toward unsoundness. A live matrix program or a mutant must
    // be refused by the invalidation rule; acceptance is the failure, decided
    // before anything runs. An ended matrix program and a generated program
    // must be accepted, built, run clean and compute what they mean; each
    // generated program is also built at every optimisation level and held to
    // answering alike. Outcomes are cached by module, level and toolchain, so
    // a run over unchanged programs builds nothing. A selected sanitizer
    // watches the runtime, the allocator and crashes, not the generated code
    // (see `Sanitize`).
    //
    // Programs link the checking runtime, so a use of freed storage, a second
    // disposal or a store outside an allocation in an accepted program aborts
    // instead of passing.
    //
    // Programs are compiled in process against the checked library; only
    // what is accepted reaches the toolchain. A program that declares a
    // closure checks the library again, which is most of the cost: about a
    // minute with an optimised runner and six with a debug one, even with
    // every outcome cached. So it is a step of its own, run by the
    // `optimised-soundness` CI lane. `-Dsoundness-matrix=false` leaves the matrix out of a search
    // over new seeds, since the matrix does not depend on the seed.
    const run_soundness = b.addRunArtifact(conformance);
    shareLibraryCache(run_soundness);
    run_soundness.addArg(b.pathFromRoot("tests"));
    run_soundness.addArgs(&.{ "--soundness", "--storage-programs", b.fmt("{d}", .{storage_programs}), "--seed", b.fmt("{d}", .{seed}) });
    if (!soundness_matrix) run_soundness.addArg("--skip-matrix");
    run_soundness.addArg("--runtime");
    run_soundness.addFileArg(checked_runtime_archive);
    run_soundness.addArgs(&.{ "--scratch", b.pathJoin(&.{ scratch, "soundness" }), "--sanitize", @tagName(sanitize) });
    if (walkers) |n| run_soundness.addArgs(&.{ "--walkers", b.fmt("{d}", .{n}) });
    run_soundness.has_side_effects = true;
    const soundness_step = b.step("soundness", "Check the soundness matrix and generated storage programs with their mutants");
    soundness_step.dependOn(&run_soundness.step);

    const run_properties = heavy.properties(conformance, exe);
    const property_tests = b.step("test-properties", "Run recompilation properties over selected corpus cases (skipped with test-filter)");
    if (test_filter == null) property_tests.dependOn(&run_properties.step);

    // What each input dimension costs, and how that cost grows.
    //
    // Its own step rather than part of `test`, because it is the one gate that
    // reads a clock. `test` asserts what a compilation asked for, which is
    // counted and so is the same number on every machine; a walk inside a walk
    // allocates nothing and runs straight past it. Catching that shape means
    // timing something, and a timing gate inside the suite would fail on a
    // busy machine and teach everyone to re-run the suite.
    //
    // So it stands alone: cheap to run, cheap to re-run, and a failure names a
    // dimension rather than a case.
    const run_sweep = b.addRunArtifact(conformance);
    run_sweep.addArg(b.pathFromRoot("tests"));
    run_sweep.addArg("--sweep");
    if (sweep_filter) |filter| {
        run_sweep.addArg("--sweep-filter");
        run_sweep.addArg(filter);
    }
    // A slowdown emits the same bytes, so a cached answer is exactly what a
    // regression would produce.
    run_sweep.has_side_effects = true;
    const sweep_step = b.step("sweep", "Report what each input dimension costs, and refuse a dimension that grows faster than its input");
    sweep_step.dependOn(&run_sweep.step);

    const run_examples = heavy.examples(conformance);

    // `zig build conformance -- <path>` walks that directory, case or
    // transcript alone, as the runner does when pointed at it: its cases,
    // goldens and transcripts, with no coverage floors, generated programs or
    // examples, since a part of the corpus cannot answer for what the whole
    // must reach. Naming `examples/` or one example walks it against its
    // goldens in `tests/examples/`.
    const narrowed_conformance: ?*std.Build.Step = if (test_roots.walkOf(b.args)) |walk| switch (walk) {
        .whole => null,
        .narrowed => |directory| narrowed: {
            const run_narrowed = b.addRunArtifact(conformance);
            shareLibraryCache(run_narrowed);
            run_narrowed.addArg(b.pathFromRoot(directory));
            run_narrowed.addArg("--compiler");
            run_narrowed.addFileArg(exe.getEmittedBin());
            run_narrowed.addArg("--runtime");
            run_narrowed.addFileArg(checked_runtime_archive);
            run_narrowed.addArg("--scratch");
            run_narrowed.addArg(b.pathJoin(&.{ scratch, "narrowed" }));
            if (walkers) |n| run_narrowed.addArgs(&.{ "--walkers", b.fmt("{d}", .{n}) });
            run_narrowed.addArg("--sanitize");
            run_narrowed.addArg(@tagName(sanitize));
            if (update_goldens) run_narrowed.addArg("--update");
            if (opt_levels) run_narrowed.addArg("--levels");
            run_narrowed.has_side_effects = true;
            break :narrowed &run_narrowed.step;
        },
    } else |_| &b.addFail("zig build conformance walks one directory: name at most one after `--`").step;

    heavy.guide_gate = b.addExecutable(.{
        .name = "guide-gate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/guide_gate.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    heavy.guide_gate.root_module.addAnonymousImport("process", .{ .root_source_file = b.path("src/conformance/process.zig") });
    heavy.guide_gate.root_module.addAnonymousImport("manifest_source", .{ .root_source_file = b.path("src/support/manifest_source.zig") });
    const run_guide = heavy.guide(b.getInstallStep());
    const guide_step = b.step("guide", "Check the guide's programs and fragments and hold their pasted output to what the compiler prints");
    guide_step.dependOn(&run_guide.step);

    heavy.example_tests = b.addExecutable(.{
        .name = "example-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/example_tests.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    heavy.example_tests.root_module.addAnonymousImport("process", .{ .root_source_file = b.path("src/conformance/process.zig") });
    // The loader's rule for a manifest's `source`, which the check of what
    // each example root reaches applies too.
    heavy.example_tests.root_module.addAnonymousImport("manifest_source", .{ .root_source_file = b.path("src/support/manifest_source.zig") });
    const example_tests_step = b.step("example-tests", "Run `linea test` on every root beneath examples/");
    example_tests_step.dependOn(&heavy.exampleTests(b.getInstallStep()).step);

    // Fidelity, as a checked claim rather than an impression. Reserved-word
    // parity only reaches the surface: a grammar can mangle impl blocks or
    // match arms entirely while every keyword is present and every other gate
    // is green.
    //
    // One invocation rather than one per file -- the CLI takes many paths, and
    // a process spawn per corpus file would be the slowest thing in the suite.
    // Its exit status covers a MISSING node as well as an ERROR one, which
    // matters: an unterminated block makes tree-sitter insert a token rather
    // than give up, and a check blind to that passes on a grammar hallucinating
    // its own delimiters.
    // Compile the generated parser before anything parses with it.
    //
    // The CLI builds the library as a side effect of the first `parse`, and
    // that invocation answers about no file: it exits 0 having parsed nothing.
    // For the sweep, which expects 0, that is an invisible pass over the whole
    // corpus; for a `refused` step, which expects 1, it is a failure with no
    // cause a reader can see. Chaining the steps orders them but does not help,
    // because whichever runs first still pays for the build -- and `generate`
    // rewrites `src/parser.c` on every build, so the library is stale again
    // every time and the first parse is always the one that suffers.
    //
    // An explicit build makes the compile a step with its own name, one that
    // fails as itself rather than as whichever parse drew the short straw.
    const build_grammar = b.addSystemCommand(&.{"tree-sitter"});
    build_grammar.addArg("build");
    // Into the cache the build owns, not beside the grammar. Without this the
    // CLI writes the compiled library into the source tree, where it is a
    // hundred kilobytes of build output waiting for someone's `git add -A`.
    build_grammar.addArg("-o");
    build_grammar.addArg(b.pathFromRoot(".zig-cache/tree-sitter/linea.dylib"));
    build_grammar.setCwd(b.path(ts_dir));
    build_grammar.setEnvironmentVariable("TREE_SITTER_LIBDIR", b.pathFromRoot(".zig-cache/tree-sitter"));
    build_grammar.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
    build_grammar.step.dependOn(&generate_grammar.step);
    // The library lands beside the checkout while the manifest that records
    // this step lives in the cache, and the cache is shared between checkouts.
    // So one workspace's run can satisfy another's, which leaves the second
    // holding a verdict of "already built" and no library -- and every parse
    // after it reports that no parser directory is configured. Always running
    // it costs a second and makes the two agree.
    build_grammar.has_side_effects = true;

    // The CLI writes the file it failed on to standard output, which the build
    // shows only for a check rather than a failed exit; the files it refused
    // are repeated on standard error, so a failure names them.
    const sweep = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\out=$(tree-sitter parse --quiet --stat "$@"); status=$?
        \\printf '%s\n' "$out"
        \\printf '%s\n' "$out" | grep -E '\((ERROR|MISSING)' >&2
        \\exit $status
        ,
        "tree-sitter-parse",
    });
    sweep.setCwd(b.path(ts_dir));
    // The CLI compiles the generated parser into a cache of its own and decides
    // from that cache whether to rebuild. A cache in the user's home outlives
    // any one checkout, so a parser built for a different grammar can answer
    // here -- which reports ERROR nodes on source this grammar accepts, and
    // would as readily accept source it rejects. Pointed at a directory the
    // build owns, the gate depends on nothing outside the build.
    sweep.setEnvironmentVariable("TREE_SITTER_LIBDIR", b.pathFromRoot(".zig-cache/tree-sitter"));
    sweep.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
    sweep.step.dependOn(&build_grammar.step);
    // On a host with no parser configuration the CLI can parse *nothing* and
    // exit 0, which turns every gate in this file into a check that cannot
    // fail: the sweep passes over a corpus it never read, and only the refused
    // chain below notices, by expecting a refusal and getting the vacuous
    // success. The stat line is printed per file actually parsed, so requiring
    // it makes an empty run fail as itself.
    sweep.addCheck(.{ .expect_stdout_match = "successful parses:" });
    sweep.expectExitCode(0);
    addCorpusPaths(b, sweep);

    // The other direction: every file the sweep above leaves out is a file the
    // grammar has to actually refuse. An exclusion list is a restatement of
    // the parser's verdict, and an entry that stopped being one -- because the
    // grammar learned the form, or because the case changed -- silently shrinks
    // what the sweep covers and reads as an audited exemption. One invocation
    // per file, because the CLI reports failure for the batch and the question
    // is about each.
    // Chained rather than fanned out. The CLI compiles the generated parser
    // into `TREE_SITTER_LIBDIR` on first use, so several of these running at
    // once race on building it -- and one that starts before the library is
    // ready parses nothing and exits 0, which reads here as a file the grammar
    // accepts. Each waits for the one before it.
    var previous: *std.Build.Step = &build_grammar.step;
    for (rejected_by_the_compiler) |path| {
        const refused = b.addSystemCommand(&.{ "tree-sitter", "parse", "--quiet" });
        refused.setCwd(b.path(ts_dir));
        refused.setEnvironmentVariable("TREE_SITTER_LIBDIR", b.pathFromRoot(".zig-cache/tree-sitter"));
        refused.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
        refused.step.dependOn(previous);
        refused.addArg(b.pathJoin(&.{ "..", "..", path }));
        refused.expectExitCode(1);
        previous = &refused.step;
    }
    sweep.step.dependOn(previous);

    // What the highlighter actually paints, rather than what the query file
    // says somewhere. A query is matched in order and the last pattern to
    // capture a node is the one that colours it, so a narrower rule written
    // above the general one it refines matches and is then overwritten --
    // which is a file that reads correctly, passes every gate that greps it,
    // and highlights nothing. `tree-sitter test` runs the assertions beside
    // the fixture and reports the capture each token actually received.
    //
    // The output is checked because the CLI answers a missing fixture with
    // exit 0 and silence, which is the same verdict a passing run gives.
    const highlights_test = b.addSystemCommand(&.{ "tree-sitter", "test" });
    highlights_test.setCwd(b.path(ts_dir));
    highlights_test.setEnvironmentVariable("TREE_SITTER_LIBDIR", b.pathFromRoot(".zig-cache/tree-sitter"));
    highlights_test.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
    highlights_test.step.dependOn(&build_grammar.step);
    highlights_test.addFileInput(b.path(ts_dir ++ "/queries/highlights.scm"));
    highlights_test.addCheck(.{ .expect_stdout_match = "syntax highlighting:" });
    highlights_test.addCheck(.{ .expect_stdout_match = "assertions" });
    highlights_test.expectExitCode(0);
    // After the parses, for the reason they are chained to each other: the
    // library they share is built on first use.
    highlights_test.step.dependOn(&sweep.step);

    // The editor gates alone, which CI runs ahead of the suite: they take a
    // few seconds, and a grammar that stopped parsing a file is otherwise
    // reported after everything else has run.
    const editor_step = b.step("editor", "Check the editor grammar parses the corpus and highlights what its queries say");
    editor_step.dependOn(&sweep.step);
    editor_step.dependOn(&highlights_test.step);

    // What the gates read out of the project's own text, run as ordinary code
    // against ordinary cases. `zig build` evaluates this file and runs no test
    // in it, so a heuristic that stays here is a heuristic nothing can fail --
    // which is why the analysis lives in a module and the module has a test
    // binary of its own.
    const source_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/source_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = test_filters,
    });
    source_tests.root_module.addAnonymousImport("runtime_archive", .{ .root_source_file = runtime_archive });
    // The gates' worker pool is tested here, and it runs children through
    // the conformance runner's process module.
    source_tests.root_module.addAnonymousImport("process", .{ .root_source_file = b.path("src/conformance/process.zig") });
    // The runtime's signature table and every source it describes, so a test
    // holds the one to the other.
    source_tests.root_module.addAnonymousImport("runtime_symbols", .{ .root_source_file = b.path("src/support/runtime_symbols.zig") });
    source_tests.root_module.addAnonymousImport("runtime_sources", .{ .root_source_file = runtimeSources(b) });
    source_tests.root_module.addAnonymousImport("manifest_source", .{ .root_source_file = b.path("src/support/manifest_source.zig") });
    const run_source_tests = b.addRunArtifact(source_tests);
    const runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/float.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = test_filters,
    });
    runtime_tests.root_module.addImport("decimal_provider", b.createModule(.{
        .root_source_file = decimalProvider(b),
        .target = target,
        .optimize = optimize,
    }));
    runtime_tests.root_module.link_libc = true;
    if (target.result.os.tag == .linux) runtime_tests.root_module.linkSystemLibrary("m", .{});
    const run_runtime_tests = b.addRunArtifact(runtime_tests);

    // The documentation gates read Markdown rather than source, so they run
    // as a step of the suites instead of on every evaluation of this file: a
    // `zig build` that only compiles does not pay for reading the decision
    // index, the guide and the library's documentation.
    const documentation_gates = b.allocator.create(std.Build.Step) catch @panic("OOM");
    documentation_gates.* = .init(.{
        .id = .custom,
        .name = "documentation gates",
        .owner = b,
        .makeFn = checkTheDocumentation,
    });

    const suites = .{
        .{ test_roots.Suite.full, "test", "Run unit tests and the conformance suite" },
        .{ test_roots.Suite.corpus, "test-corpus", "Run the complete corpus and generated programs with coverage floors (skipped with test-filter)" },
        .{ test_roots.Suite.support, "test-support", "Run full test coverage except the corpus: units, examples, and editor checks" },
        .{ test_roots.Suite.unit, "test-unit", "Run compiler and build machinery unit tests without integrations" },
        .{ test_roots.Suite.conformance, "conformance", "Run the corpus and examples with the selected runtime, or only the directory, case or transcript named after --" },
        .{ test_roots.Suite.fuzz, "fuzz", "Run only the compiler's fuzz entry points" },
    };
    inline for (suites) |suite| {
        const selected = test_roots.select(.{ .suite = suite[0], .optimize = optimize, .filtered = test_filter != null });
        const step = b.step(suite[1], suite[2]);
        if (selected.source) {
            step.dependOn(documentation_gates);
            step.dependOn(&run_source_tests.step);
            step.dependOn(&run_runtime_tests.step);
            if (test_filter == null) {
                step.dependOn(native_io_step);
                step.dependOn(native_net_step);
                step.dependOn(native_clock_step);
                step.dependOn(native_math_step);
                step.dependOn(native_runtime_step);
                step.dependOn(native_task_step);
            }
        }
        const narrowed = suite[0] == .conformance and narrowed_conformance != null;
        const properties = selected.corpus and (suite[0] == .full or suite[0] == .corpus) and test_filter == null;
        if (selected.selected == .fuzz) step.dependOn(&run_fuzz_tests.step);
        if (narrowed) step.dependOn(narrowed_conformance.?);
        if (sequential and !narrowed) {
            const order = test_roots.heavyOrder(selected, .{ .properties = properties, .guide = guide_in_test });
            if (heavy.sequence(order.slice())) |last| step.dependOn(last);
        } else {
            if (selected.selected == .joined) step.dependOn(&run_debug_tests.step);
            if (!narrowed) {
                if (selected.examples) step.dependOn(&run_examples.step);
                if (selected.guide and guide_in_test) step.dependOn(&run_guide.step);
                if (selected.corpus) step.dependOn(&run_conformance.step);
            }
            if (properties) step.dependOn(property_tests);
        }
        if (selected.editor) {
            step.dependOn(&sweep.step);
            step.dependOn(&highlights_test.step);
        }
    }
}

/// The corpus files the grammar is not asked to derive.
///
/// Files the compiler does not parse either, so the grammar is not asked to do
/// what the language does not. Named rather than inferred from what goldens a
/// case carries, because a list is easier to audit than a rule -- but a list
/// is also a restatement of the parser's verdict, so `sweepRejects` below
/// holds every entry to actually being one the grammar refuses. It found the
/// first line of this list, which the grammar parsed perfectly well: excluding
/// it hid nothing and quietly shrank the sweep by a file.
const rejected_by_the_compiler = [_][]const u8{
    "tests/traits/a_grouped_type_is_not_a_derive_target.lin",
    "tests/traits/a_grouped_tuple_head_is_reported_once.lin",
    "tests/tuples/a_pattern_refused_by_the_parser_is_reported_once.lin",
    "tests/tuples/a_refused_tuple_arm_does_not_make_the_next_arm_unreachable.lin",
    "tests/patterns/a_part_that_is_no_pattern_leaves_the_tuple_whole.lin",
    "tests/patterns/an_unclosed_tuple_pattern_has_no_arity_judged.lin",
    "tests/patterns/a_part_that_compares_is_reported_by_its_form.lin",
    "tests/structs/named_literals/a_named_literal_requires_its_closing_brace.lin",
    "tests/struct_update/the_base_comes_last.lin",
    "tests/struct_update/a_base_needs_an_expression.lin",
    "tests/struct_update/a_second_base_is_still_read.lin",
    "tests/structs/a_literal_value_without_a_field_name_is_one_mistake.lin",
    "tests/closure_captures/invocation_mode_requires_capture_list.lin",
    "tests/decl/an_export_does_not_sit_in_a_trait.lin",
    "tests/decl/a_trait_holds_signatures_projections_types_and_tests.lin",
    "tests/decl/only_a_function_is_a_test_in_a_trait.lin",
    "tests/decl/a_lambda_parameter_list_is_closed.lin",
    "tests/ranges/a_chain_in_a_pattern_is_one_mistake.lin",
    "tests/decl/impl_takes_no_modifier.lin",
    "tests/decl/an_impl_is_not_a_test.lin",
    "tests/decl/a_test_is_not_generic.lin",
    "tests/decl/a_test_is_named_by_a_string_and_nothing_else.lin",
    "tests/decl/a_test_without_a_body_is_reported_at_the_test.lin",
    "tests/decl/a_test_takes_no_parameters.lin",
    "tests/decl/only_a_function_is_a_test.lin",
    "tests/diag/invalid_run.lin",
    "tests/decl/a_destructure_is_introduced_by_let.lin",
    "tests/derive_from/a_derive_entry_missing_its_closing_bracket_is_reported_once.lin",
    "tests/derive_from/a_derive_entry_with_trailing_garbage_is_reported_once.lin",
    "tests/derive_from/a_derive_list_missing_its_closer_stops_at_the_declaration.lin",
    "tests/derive_from/a_derive_list_with_garbage_and_no_closer_stops_at_the_declaration.lin",
    "tests/derive_from/a_derive_list_with_no_closer_leaves_the_declarations_after_it.lin",
    "tests/derive_from/a_refused_byte_in_a_derive_list_is_reported_once.lin",
    "tests/derive_from/a_derive_entry_without_a_source_is_reported_once.lin",
    "tests/derive_from/a_derive_request_missing_its_closing_parenthesis_is_reported_once.lin",
    "tests/derive_from/a_from_derive_stays_silent_after_a_written_unit_result.lin",
    "tests/traits/an_unnamed_callable_parameter_in_two_implementations_is_refused_by_the_parser.lin",
    "tests/defer_let/a_defer_let_binds_one_name.lin",
    "tests/defer_let/a_defer_let_read_binds_nothing_to_release.lin",
    "tests/tuples/var_does_not_take_a_tuple_apart.lin",
    "tests/pattern_parameters/a_label_and_a_second_name_are_refused.lin",
    "tests/traits/a_grouped_type_is_not_an_implementation_head.lin",
    "tests/decl/borrowed_lets/a_borrowed_pattern_is_not_a_var_declaration.lin",
    "tests/decl/borrowed_lets/read_requires_an_irrefutable_pattern.lin",
    "tests/ownership/a_catch_all_is_the_bare_underscore/main.lin",
    "tests/traits/a_trait_projection_has_no_body.lin",
    "tests/traits/a_settling_with_nothing_after_it_says_what_is_missing.lin",
    "tests/traits/a_settled_reference_the_parser_could_not_finish_is_one_report.lin",
    "tests/text/an_extern_declares_no_body.lin",
    "tests/text/an_unclosed_literal_inside_an_interpolation_is_reported_once.lin",
    "tests/text/an_unclosed_literal_in_a_call_written_over_two_lines_is_reported_once.lin",
    "tests/text/an_unclosed_literal_in_an_array_written_over_two_lines_is_reported_once.lin",
    "tests/text/an_unclosed_literal_in_a_match_arm_is_reported_once.lin",
    "tests/text/an_unclosed_literal_ending_a_one_line_match_is_reported_once.lin",
    "tests/text/an_unclosed_literal_ending_a_one_line_call_is_reported_once.lin",
    "tests/text/a_call_holding_an_unclosed_literal_is_held_to_the_arguments_written_before_it.lin",
    "tests/text/a_closed_call_holding_a_refused_byte_is_held_to_its_arguments.lin",
    "tests/text/a_refused_byte_in_an_argument_list_ends_at_the_next_comma.lin",
    "tests/text/a_refused_byte_before_an_unclosed_bracket_leaves_the_next_statements.lin",
    "tests/text/an_unclosed_literal_in_a_tuple_written_over_two_lines_is_reported_once.lin",
    "tests/patterns/a_refused_byte_ending_a_line_of_a_tuple_pattern_is_reported_once.lin",
    "tests/text/an_unclosed_literal_in_a_structure_literal_excuses_only_its_own_line.lin",
    "tests/diag/a_byte_no_token_begins_ending_a_line_of_an_array_is_reported_once.lin",
    "tests/traits/an_implementation_head_holding_a_refused_type_in_a_callable_is_compared_with_no_other.lin",
    "tests/traits/a_trait_is_never_closed.lin",
    "tests/lsp/a_call_that_was_never_closed_still_says_what_is_in_scope/main.lin",
    "tests/lsp/a_dot_on_a_type_being_written_offers_its_trait_operations/main.lin",
    "tests/arrays/a_bracket_says_where_it_closes.lin",
    "tests/arrays/an_array_type_missing_its_semicolon_poisons_its_binding.lin",
    "tests/unit_value/the_unit_value_is_not_a_pattern.lin",
    "tests/diag/unexpected_character.lin",
    "tests/diag/unterminated_string.lin",
    "tests/raw_strings/an_unterminated_raw_literal.lin",
    "tests/raw_strings/a_raw_literal_is_one_token.lin",
    "tests/raw_strings/a_raw_literal_opens_with_at_most_eight_hashes.lin",
    "tests/multiline_strings/a_line_cannot_begin_inside_an_interpolation.lin",
    "tests/multiline_strings/an_arm_after_a_multiline_literal_needs_its_comma.lin",
    "tests/diag/an_interpolation_format_spec_is_written_in_order.lin",
    "tests/diag/an_unclosed_interpolation_ends_at_its_line.lin",
    "tests/lexer/delimiters.lin",
    "tests/newtypes/a_proven_value_has_nothing_to_decline.lin",
    "tests/newtypes/a_clause_the_file_ends_inside_is_refused.lin",
    "tests/modules/a_dangling_dot_off_a_qualified_type_is_one_mistake/main.lin",
    "tests/iter/a_for_names_what_it_walks.lin",
    "tests/arrays/inferred_length/missing_bracket_recovers.lin",
    "tests/arrays/inferred_length/missing_initializer_recovers.lin",
    "tests/decl/a_constant_takes_no_modifier.lin",
    "tests/decl/a_function_takes_no_modifier.lin",
    "tests/borrows/contracts/a_carrier_mark_belongs_to_a_struct_or_an_enum.lin",
    "tests/decl/attributes/a_bare_carrier_is_refused.lin",
    "tests/decl/attributes/a_bare_carrier_after_a_visibility_is_refused.lin",
    "tests/decl/attributes/a_lone_carrier_is_refused.lin",
    "tests/decl/attributes/a_group_closes_before_its_declaration.lin",
    "tests/decl/attributes/a_group_separates_its_items.lin",
    "tests/decl/attributes/a_malformed_attribute_preserves_the_following_declaration.lin",
    "tests/decl/attributes/an_attribute_group_is_not_empty.lin",
    "tests/decl/attributes/an_attribute_requires_a_following_declaration.lin",
    "tests/decl/attributes/attribute_names_are_closed.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_constants.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_fields.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_functions.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_implementations.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_imports/main.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_statements.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_traits.lin",
    "tests/decl/attributes/attributes_do_not_disappear_on_implementations.lin",
    "tests/decl/attributes/derive_attributes_do_not_attach_to_implementations.lin",
    "tests/decl/attributes/the_bare_copyable_prefix_is_removed.lin",
    "tests/decl/attributes/the_bare_linear_prefix_is_removed.lin",
    "tests/decl/attributes/the_bare_opaque_prefix_is_removed.lin",
    "tests/decl/borrowed_lets/a_borrowed_name_is_refused_without_moving_its_place.lin",
    "tests/decl/borrowed_lets/read_marks_the_pattern_not_the_place.lin",
    "tests/modules/a_reexport_takes_no_modifier/mid/mid.lin",
    "tests/traits/a_trait_takes_no_modifier.lin",
    "tests/construction_derive/malformed_argument_keeps_parser_diagnostic.lin",
    "tests/decl/a_unit_result_is_not_written/main.lin",
    "tests/testing_signatures/a_written_unit_result_says_what_a_test_and_main_answer.lin",
    "tests/embed/embed_is_reserved.lin",
    "tests/embed/the_path_is_a_literal.lin",
};

/// Every corpus file the grammar is asked to derive.
fn addCorpusPaths(b: *std.Build, run: *std.Build.Step.Run) void {
    const io = b.graph.io;
    // The library too. Its files are Linea, they are compiled into every
    // binary the compiler produces, and leaving them out meant the grammar was
    // never asked to parse the code every program depends on.
    for ([_][]const u8{ "examples", "tests", "std" }) |root| {
        var dir = b.build_root.handle.openDir(io, root, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var walker = dir.walk(b.allocator) catch @panic("OOM");
        defer walker.deinit();
        while (walker.next(io) catch @panic("walking the corpus failed")) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".lin")) continue;

            const path = b.pathJoin(&.{ root, entry.path });
            if (std.mem.indexOf(u8, path, "recovery") != null) continue;
            var skip = false;
            for (rejected_by_the_compiler) |r| {
                if (std.mem.eql(u8, path, r)) skip = true;
            }
            if (skip) continue;

            // Relative to the grammar directory the sweep runs in.
            run.addArg(b.pathJoin(&.{ "..", "..", path }));
        }
    }
}
