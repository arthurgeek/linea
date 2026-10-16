const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

/// Whether the tree- and token-dump subcommands are reachable from the command
/// line. Their output has no stability guarantee, and confining them to debug
/// builds keeps a released binary from offering a surface anyone could come to
/// depend on.
///
/// The dump functions themselves always compile: the conformance suite calls
/// them directly rather than through the command line.
const expose_dumps = builtin.mode == .Debug;

const source_mod = @import("../support/source.zig");
const FileTable = @import("../support/source.zig").FileTable;
const Source = source_mod.Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const render = @import("../diagnostics/render.zig");
const render_json = @import("../diagnostics/render_json.zig");
const token = @import("../lexer/token.zig");
const tokenize = @import("../lexer/lexer.zig").tokenize;
const dumpAst = @import("../syntax/dump.zig").dumpAst;
const dumpExpanded = @import("../syntax/expanded_dump.zig").dumpExpanded;
const lexer_dump = @import("../lexer/dump.zig");
const lower = @import("../mir/lower.zig").lowerProgram;
const Purpose = @import("../mir/lower.zig").Purpose;
const runner = @import("runner.zig");

/// Where a test binary, or the program `run` executes, is built.
///
/// Not beside the source: a root is a directory somebody wrote, and for a
/// corpus case it is one whose contents are compared against goldens. The
/// variable a host sets is honoured so a sandbox can say where writing is
/// allowed, and `/tmp` is the fallback every POSIX host has.
fn scratchDir(environ: std.process.Environ) []const u8 {
    if (environ.getPosix("TMPDIR")) |named| {
        if (named.len > 0) return std.mem.trimEnd(u8, named, "/");
    }
    return "/tmp";
}
const mir = @import("../mir/mir.zig");

const dumpMir = @import("../mir/dump.zig").dumpModule;
const emitMlir = @import("../backend/mlir.zig").emit;
const toolchain = @import("toolchain.zig");
const runtime_symbols = @import("../support/runtime_symbols.zig");
const loader = @import("loader.zig");
const library = @import("library.zig");

const Program = @import("../syntax/program.zig").Program;
const loadFromDisk = @import("loader.zig").loadFromDisk;
const loadFromMemory = @import("loader.zig").loadFromMemory;
const checkProgram = @import("loader.zig").checkProgram;
const annotated = @import("../fmt/annotated.zig");

pub const exit_ok: u8 = 0;
pub const exit_diagnostics: u8 = 1;
pub const exit_usage: u8 = 64;
/// A module the backend refused to emit, because it is not what emitting it
/// assumes. Its own status rather than the one a rejected program gets: the
/// file in front of the user was accepted by every rule the language states,
/// and a script cannot be asked to tell the two apart from a shared number.
pub const exit_defect: u8 = 70;
pub const exit_io: u8 = 74;

/// What a tool that started and then refused says about whose fault it is.
///
/// The two that read only generated text are judging what this compiler
/// emitted -- their pinned version rides in the same flake as the compiler,
/// so a refusal is not an installation being older than the emitter -- and a
/// refusal carries the defect status the emission verifier's own refusal
/// does. `cc` also takes what the machine provides, the runtime archive and
/// the linker's view of the world, so its failure stays an environment's. A
/// tool that could not start at all says nothing about the program and is
/// classified before this is asked.
fn refusalStatus(tool: toolchain.Tool) u8 {
    return switch (tool) {
        .mlir_opt, .mlir_translate => exit_defect,
        .cc => exit_io,
    };
}

test "a refusal of generated text is a defect, and a link failure is not" {
    try std.testing.expectEqual(exit_defect, refusalStatus(.mlir_opt));
    try std.testing.expectEqual(exit_defect, refusalStatus(.mlir_translate));
    try std.testing.expectEqual(exit_io, refusalStatus(.cc));
}

/// Whether a level is one a build offers. The value is passed through as
/// `-O<value>`, so what is accepted here is exactly what is spelled there, and
/// a level the tool would refuse is a usage error before anything compiles.
fn knownOptLevel(value: []const u8) bool {
    for (toolchain.levels) |k| if (std.mem.eql(u8, value, k)) return true;
    return false;
}

test "an optimisation level is one the compiler will spell" {
    for ([_][]const u8{ "0", "1", "2", "3", "s", "z" }) |v| {
        try std.testing.expect(knownOptLevel(v));
    }
    for ([_][]const u8{ "fast", "4", "", "O2", "-O2", "S" }) |v| {
        try std.testing.expect(!knownOptLevel(v));
    }
}

/// Use the source file's stem or module directory as the default output name.
/// `prime_sieve.lin` builds `prime_sieve`; `discounts/` builds `discounts`.
/// Preserve a name such as `.lin` when removing the extension would leave it empty.
fn defaultOutputName(path: []const u8) []const u8 {
    const base = std.fs.path.basename(std.mem.trimEnd(u8, path, "/"));
    if (std.mem.endsWith(u8, base, ".lin") and base.len > ".lin".len) {
        return base[0 .. base.len - ".lin".len];
    }
    return base;
}

test "a build is named after its source" {
    try std.testing.expectEqualStrings("prime_sieve", defaultOutputName("examples/prime_sieve.lin"));
    try std.testing.expectEqualStrings("main", defaultOutputName("main.lin"));
    try std.testing.expectEqualStrings("discounts", defaultOutputName("examples/discounts/"));
    try std.testing.expectEqualStrings("discounts", defaultOutputName("examples/discounts"));
    try std.testing.expectEqualStrings(".lin", defaultOutputName(".lin"));
}

/// A writer the driver hands out.
///
/// Nothing the compiler writes is bounded by anything but the input: a token
/// is as long as the text it came from, a formatted file is longer than the
/// file it was made from, a diff writes a line and a file without newlines is
/// one line, and a failing tool's output is as long as it likes. A single call
/// asking the host to move more than it will fails with a code the standard
/// library treats as impossible -- a panic in a debug build and a
/// `WriteFailed` in a release one, which is one input with two outcomes
/// decided by optimisation level.
///
/// This is the only place the driver opens a writer, so bounding it here is
/// what leaves no route around it. A consumer is handed a `std.Io.Writer` and
/// nothing else, and stays bounded without knowing it -- including consumers
/// not written yet, which is what a rule applied at each call site cannot say.
pub const Out = struct {
    buffer: [4096]u8 = undefined,
    file: std.Io.File.Writer = undefined,
    bounded: source_mod.Piecewise = undefined,

    /// The writer for `file`. Borrows `self`, which must outlive every use of
    /// what comes back. It writes at the file's shared offset rather than at a
    /// position of its own, so standard output and standard error redirected
    /// to one file append to it in turn instead of overwriting each other.
    pub fn open(self: *Out, io: std.Io, file: std.Io.File) *std.Io.Writer {
        self.file = file.writerStreaming(io, &.{});
        self.bounded = .init(&self.file.interface, &self.buffer);
        return &self.bounded.writer;
    }

    pub fn flush(self: *Out) std.Io.Writer.Error!void {
        return self.bounded.writer.flush();
    }
};

/// Renders what a compile reported. Every command that compiles renders
/// through this once: where it goes on to run what it built, before running
/// it, so its notes precede the program's own output; otherwise as it exits.
const Report = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    out: *Out,
    color: ColorArg,
    error_format: ErrorFormat,

    fn emit(self: Report, table: *FileTable, sink: *Sink) !void {
        if (sink.items().len == 0) return;
        // Prepare every remaining source map before rendering.
        try table.buildMaps(self.gpa);
        const w = &self.out.bounded.writer;
        switch (self.error_format) {
            .human => {
                const use_color: render.Color = switch (self.color) {
                    .always => .always,
                    .never => .never,
                    .auto => if (self.file.isTty(self.io) catch false) .always else .never,
                };
                try render.renderAll(w, table, sink, .{ .color = use_color });
            },
            .json => try render_json.renderAllJson(w, table, sink),
        }
        try self.out.flush();
    }
};

pub const ColorArg = enum { auto, always, never };
pub const ErrorFormat = enum { human, json };

pub fn parseColor(s: []const u8) ?ColorArg {
    return std.meta.stringToEnum(ColorArg, s);
}

const cli = @import("../support/cli.zig");
const format = @import("format.zig");
const init = @import("init.zig");

/// The debugging aids, described whether or not this build offers them: a
/// build that hides one still has to be able to say which name it hid.
const dump_commands = [_]cli.Command{
    .{ .tag = .dump_tokens, .debug = true, .name = "dump-tokens", .operand = "<file>", .help = "print the token stream" },
    .{ .tag = .dump_ast, .debug = true, .name = "dump-ast", .operand = "<file>", .help = "print the syntax tree" },
    .{ .tag = .dump_expanded, .debug = true, .name = "dump-expanded", .operand = "<file>", .help = "print generated derive files" },
    .{ .tag = .dump_mir, .debug = true, .name = "dump-mir", .operand = "<file>", .help = "print the code that will be generated" },
    .{ .tag = .dump_inferred, .debug = true, .name = "dump-inferred", .operand = "<file>", .help = "print the source with what the checker settled written in" },
    .{ .tag = .dump_mono, .debug = true, .name = "dump-mono", .operand = "<file>", .help = "print the program with its generics gone" },
    .{
        .tag = .dump_asm,
        .debug = true,
        .name = "dump-asm",
        .operand = "<file>",
        .help = "print the assembly the build would ship",
        .options = &.{
            .{ .name = "-O", .arity = .value, .metavar = "0|1|2|3|s|z", .help = "optimisation level for the generated code (default: 2)" },
        },
    },
};

/// Whether `name` is a debugging aid: a command a Debug build offers and a
/// release build keeps off the command line.
///
/// A command case drives a real binary, and one naming an aid the binary does
/// not offer has nothing to assert: what a user of that build sees is a usage
/// error, not the case's subject. The conformance runner asks this rather than
/// keeping its own list of the aids, so a name that moves between the two
/// groups cannot leave the two disagreeing.
pub fn isDebuggingAid(name: []const u8) bool {
    for (dump_commands) |c| {
        if (std.mem.eql(u8, c.name, name)) return true;
    }
    return false;
}

/// Links the checking allocator, which `test` always links: a use of freed
/// storage, a second disposal or a store outside an allocation aborts.
const check_storage_option: cli.Option = .{ .name = "--check-storage", .arity = .flag, .help = "abort on a use of freed storage (slower; always on for `test`)" };

/// The command line, described once. Usage text and validation are generated
/// from this, so a command cannot advertise an option it rejects or accept one
/// it does not document.
pub const spec: cli.Spec = .{
    .commands = &([_]cli.Command{
        .{
            .tag = .run,
            .name = "run",
            .operand = "<path> [-- <args>...]",
            .help = "compile a file or program root, run it, and exit as it did",
            .passthrough = true,
            .options = &.{
                .{ .name = "-O", .arity = .value, .metavar = "0|1|2|3|s|z", .help = "optimisation level for the generated code (default: 2)" },
                check_storage_option,
            },
        },
        .{ .tag = .check, .name = "check", .operand = "<path>", .help = "report diagnostics without generating code" },
        .{
            .tag = .emit_mlir,
            .name = "emit-mlir",
            .operand = "<path>",
            .help = "write MLIR to standard output",
            .options = &.{
                .{ .name = "--tests", .arity = .flag, .help = "build what the tests reach, with the entry point that runs one" },
            },
        },
        .{
            .tag = .build,
            .name = "build",
            .operand = "<path>",
            .help = "compile a file or root to an executable, or a library to an object",
            .options = &.{
                .{ .name = "-o", .arity = .value, .metavar = "<path>", .help = "output path (default: the source's own name)" },
                .{ .name = "-O", .arity = .value, .metavar = "0|1|2|3|s|z", .help = "optimisation level for the generated code (default: 2)" },
                .{ .name = "--keep", .arity = .flag, .help = "keep the intermediate .mlir, .mlir.llvm and .ll files" },
                check_storage_option,
            },
        },
        .{
            .tag = .fmt,
            .name = "fmt",
            .operand = "<path>...",
            .help = "rewrite source in canonical form, in place",
            .options = &.{
                .{ .name = "--stdin", .arity = .flag, .help = "read one file from stdin, write to stdout" },
                .{ .name = "--check", .arity = .flag, .help = "report what would change, writing nothing" },
            },
        },
        .{ .tag = .@"test", .name = "test", .operand = "<root>", .help = "run every test beneath a program root" },
        .{ .tag = .lsp, .name = "lsp", .operand = "", .help = "serve the Language Server Protocol on standard input and output", .common_options = false },
        .{
            .tag = .init,
            .name = "init",
            .common_options = false,
            .operand = "<directory>",
            .help = "start a program or library in the named directory",
            .options = &.{
                .{ .name = "--library", .arity = .flag, .help = "start a library with no entry point" },
                .{ .name = "--yes", .arity = .flag, .help = "start in a nonempty directory without prompting" },
            },
        },
    } ++ if (expose_dumps) dump_commands else [_]cli.Command{}),
    .common = &.{
        .{ .name = "--color", .arity = .value, .metavar = "auto|always|never", .help = "colour output (default: auto)" },
        .{ .name = "--error-format", .arity = .value, .metavar = "human|json", .help = "diagnostic format (default: human)" },
    },
};

const BuildRequest = struct {
    mir: *const @import("../mir/mir.zig").Module,
    /// Emission prepares the indexes for the files its functions use.
    table: *FileTable,
    /// Where the backend says why it refused to emit. Every other failure here
    /// belongs to a tool and is quoted from that tool's own output; this one is
    /// the compiler's, so it renders with everything else the compilation had
    /// to say.
    sink: *Sink,
    out_path: []const u8,
    /// The `-O` level `cc` compiles the generated IR at.
    opt: []const u8,
    keep: bool,
    /// What to produce. A library stops at the object: it declares no entry
    /// point, so there is nothing to link a program around.
    artifact: toolchain.Artifact = .executable,
    /// Which allocator the executable links.
    storage: toolchain.Storage,
};

/// Writes IR, assembles it and links it against the runtime.
///
/// Returns a status when the build could not finish, and null when it did.
/// A tool's own message is quoted rather than summarised, because a user
/// should not have to run the tool again to find out why it refused -- but the
/// line saying which tool failed is ours, since the tool does not know it is
/// part of a Linea build.
fn compileToExecutable(
    gpa: std.mem.Allocator,
    io: std.Io,
    environ: std.process.Environ,
    err: *std.Io.Writer,
    req: BuildRequest,
) !?u8 {
    const runtime = try toolchain.findRuntime(gpa, io, environ, req.storage) orelse {
        try err.print("error: cannot find {s} beside the compiler\n", .{
            req.storage.archive(),
        });
        return exit_io;
    };
    defer gpa.free(runtime);

    // A runtime named by `LINEA_RUNTIME` decides whether storage is checked,
    // so a checked build linking one without the checking allocator says so.
    // A sanitized runtime leaves the checking to its sanitizer.
    const sanitize = toolchain.findSanitize(environ);
    if (req.storage == .checked and sanitize == null) {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, runtime, gpa, .unlimited) catch "";
        if (!runtime_symbols.holdsStorageChecks(bytes)) try err.print(
            "warning: {s} holds no checking allocator, so storage is not checked\n",
            .{runtime},
        );
    }

    const mid = try toolchain.Intermediates.of(gpa, req.out_path);
    defer mid.deinit(gpa);

    {
        const file = std.Io.Dir.cwd().createFile(io, mid.ir, .{}) catch {
            try err.print("error: cannot write '{s}'\n", .{mid.ir});
            return exit_io;
        };
        defer file.close(io);

        var out: Out = .{};
        // A module the backend refuses leaves an empty file rather than half a
        // program: it wrote nothing, and what it wrote nothing about is in the
        // sink for the renderer at the end of the run.
        if (!try emitMlir(gpa, out.open(io, file), req.mir, req.table, req.sink)) return exit_defect;
        try out.flush();
    }

    // Intermediates are removed on success only. A failed build leaves them
    // behind, which is the one time anyone wants to read them.
    const build_opts: toolchain.Options = .{
        .mid = mid,
        .out_path = req.out_path,
        .runtime_path = runtime,
        .artifact = req.artifact,
        .opt = req.opt,
        // Read from the same place the runtime path is, because it is the same
        // decision: whoever put a sanitized library there is the only one that
        // knows the link has to name what instruments it.
        .sanitize = sanitize,
    };
    const failure = try toolchain.build(gpa, io, build_opts);

    if (failure) |f| {
        if (f.missing) {
            try err.print("error: {s} is not installed\n", .{f.tool.command()});
            return exit_io;
        }
        try err.print("error: {s} failed\n", .{f.tool.command()});
        if (f.output.len > 0) try err.writeAll(f.output);
        return refusalStatus(f.tool);
    }

    if (!req.keep) mid.remove(io);
    return null;
}

pub fn run(process: std.process.Init) !u8 {
    const gpa = process.arena.allocator();
    const io = process.io;

    const args = try process.minimal.args.toSlice(gpa);

    const stderr_file = std.Io.File.stderr();
    var stderr: Out = .{};
    const stderr_w = stderr.open(io, stderr_file);
    defer stderr.flush() catch {};

    const global_help = args.len == 2 and
        (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "help"));
    const help_target: ?[]const u8 = if (args.len == 3 and std.mem.eql(u8, args[1], "help"))
        args[2]
    else if (args.len == 3 and std.mem.eql(u8, args[2], "--help"))
        args[1]
    else
        null;
    if (global_help or help_target != null) {
        const selected = if (help_target) |name| spec.find(name) orelse {
            try spec.writeUsage(stderr_w);
            return exit_usage;
        } else null;
        var stdout: Out = .{};
        const stdout_w = stdout.open(io, std.Io.File.stdout());
        defer stdout.flush() catch {};
        if (selected) |cmd| {
            try spec.writeCommandUsage(stdout_w, cmd);
        } else {
            try spec.writeUsage(stdout_w);
        }
        return exit_ok;
    }

    // Handled before the general parsing below, which takes exactly one path at
    // a fixed position.
    if (args.len >= 2 and std.mem.eql(u8, args[1], "fmt")) {
        return format.run(gpa, io, args[2..], stderr_w);
    }

    // The general-purpose allocator and not the process arena every other
    // command runs on. A command is one compilation and exits; a server is a
    // session of thousands, and an arena that reclaims nothing until the
    // process ends holds every one of them at once.
    if (args.len >= 2 and std.mem.eql(u8, args[1], "lsp")) {
        if (args.len != 2) {
            try spec.writeCommandUsage(stderr_w, spec.find("lsp").?);
            return exit_usage;
        }
        return @import("../lsp/server.zig").serve(process.gpa, process.arena.child_allocator, io);
    }

    // Initializes a directory and writes files rather than compiling source.
    if (args.len >= 2 and std.mem.eql(u8, args[1], "init")) {
        return init.run(gpa, io, args[2..], stderr_w);
    }

    if (args.len < 2) {
        try spec.writeUsage(stderr_w);
        return exit_usage;
    }

    const command = args[1];
    const cmd = spec.find(command) orelse {
        try spec.writeUsage(stderr_w);
        return exit_usage;
    };

    var color: ColorArg = .auto;
    var error_format: ErrorFormat = .human;
    var out_path: ?[]const u8 = null;
    var opt_level: []const u8 = toolchain.default_level;
    var keep = false;
    var storage: toolchain.Storage = if (cmd.tag == .@"test") .checked else .unchecked;
    // What a lowering is for. Only `emit-mlir` offers the choice today, and
    // it offers it so that a test binary's generated entry point can be read
    // before anything trusts it.
    var purpose: Purpose = if (cmd.tag == .@"test") .tests else .program;
    var path: ?[]const u8 = null;

    var it: cli.Iterator = .{ .spec = spec, .command = cmd, .args = args[2..] };
    while (it.next()) |item| switch (item) {
        .operand => |p| {
            if (path != null) {
                try stderr_w.print("error: `{s}` takes one file\n", .{command});
                try spec.writeCommandUsage(stderr_w, cmd);
                return exit_usage;
            }
            path = p;
        },
        .option => |o| {
            if (std.mem.eql(u8, o.name, "-o")) {
                out_path = o.value;
            } else if (std.mem.eql(u8, o.name, "-O")) {
                if (!knownOptLevel(o.value)) {
                    try stderr_w.writeAll("error: invalid -O value\n");
                    try spec.writeCommandUsage(stderr_w, cmd);
                    return exit_usage;
                }
                opt_level = o.value;
            } else if (std.mem.eql(u8, o.name, "--keep")) {
                keep = true;
            } else if (std.mem.eql(u8, o.name, "--check-storage")) {
                storage = .checked;
            } else if (std.mem.eql(u8, o.name, "--tests")) {
                purpose = .tests;
            } else if (std.mem.eql(u8, o.name, "--color")) {
                color = parseColor(o.value) orelse {
                    try stderr_w.writeAll("error: invalid --color value\n");
                    return exit_usage;
                };
            } else if (std.mem.eql(u8, o.name, "--error-format")) {
                error_format = std.meta.stringToEnum(ErrorFormat, o.value) orelse {
                    try stderr_w.writeAll("error: invalid --error-format value\n");
                    return exit_usage;
                };
            }
        },
    };
    if (it.problem) |problem| {
        try problem.report(stderr_w);
        try spec.writeCommandUsage(stderr_w, cmd);
        return exit_usage;
    }

    // What the program being run is started with, which is empty for every
    // command that runs nothing. Read off the iterator rather than scanned for
    // here: where the separator sits is the iterator's answer, and a second
    // search for it would be the same rule implemented twice.
    const program_args = it.rest;

    // A command with no path is about the project the working directory sits
    // in, which its manifest marks. Only where there is no such project is
    // there nothing to act on and a usage to print: naming a path stays the
    // way to act on something else, and on a file under no manifest at all.
    const found_here = if (path != null) null else try loader.rootFromHere(gpa, io);
    defer if (found_here) |here| gpa.free(here);

    const file_path = path orelse found_here orelse {
        try spec.writeCommandUsage(stderr_w, cmd);
        return exit_usage;
    };

    // Read from the command the spec already resolved, rather than compared
    // against the spellings it holds. The table is where a command exists, and
    // a run of string comparisons beside it is that table written twice: one
    // added to the spec and to nothing else compiled and did nothing.
    const is_run = cmd.tag == .run;
    const is_dump_tokens = expose_dumps and cmd.tag == .dump_tokens;
    const is_dump_ast = expose_dumps and cmd.tag == .dump_ast;
    const is_dump_expanded = expose_dumps and cmd.tag == .dump_expanded;
    const is_dump_mir = expose_dumps and cmd.tag == .dump_mir;
    const is_dump_asm = expose_dumps and cmd.tag == .dump_asm;
    const is_dump_inferred = expose_dumps and cmd.tag == .dump_inferred;
    const is_dump_mono = expose_dumps and cmd.tag == .dump_mono;
    // Not a debugging aid: this is the compiler's output in another form,
    // and the shape a person reads when generated code misbehaves.
    const is_emit_mlir = cmd.tag == .emit_mlir;
    const is_test = cmd.tag == .@"test";
    const is_build = cmd.tag == .build;
    const is_check = cmd.tag == .check;

    var table: FileTable = .empty;
    defer table.deinit(gpa);

    var sink = Sink.init(gpa);
    const report: Report = .{ .gpa = gpa, .io = io, .file = stderr_file, .out = &stderr, .color = color, .error_format = error_format };
    var interner: Interner = .empty;

    // Whether the backend refused to emit what it was handed. Tracked apart
    // from the sink because it decides a status of its own: everything else in
    // there is a rule this program broke, and this is a rule the compiler did.
    var defect = false;

    // Every root loads from disk, the standard library's included: its
    // manifest is what makes it the library, wherever it sits.
    var program = loadFromDisk(gpa, io, &table, &sink, &interner, file_path, purpose, true) catch |e| {
        // A manifest that was read and says what its root cannot be is not a
        // read failure, so it is said on its own.
        if (e == error.ManifestNamesTheLibrary) {
            try stderr_w.print(
                "error: a program may not be named `std`\n" ++
                    "  the {s} for '{s}' names it `std`, the library every program depends on: give it another name, or make it a library\n",
                .{ loader.manifest_name, file_path },
            );
            return exit_usage;
        }
        try stderr_w.print("error: cannot read '{s}'\n", .{file_path});
        // Add specific explanations for a missing path and loader validation
        // failures. The entry path may name a directory, so these errors do
        // not claim to identify the individual source or manifest that failed.
        switch (e) {
            error.FileNotFound => try stderr_w.writeAll(
                "  no file or directory of that name\n",
            ),
            error.SourceTooLarge => try stderr_w.print(
                "  a source is larger than the {d} bytes a position can address\n",
                .{source_mod.max_bytes},
            ),
            error.ManifestNotJson => try stderr_w.print(
                "  the {s} marking its program is not JSON\n",
                .{loader.manifest_name},
            ),
            error.ManifestKindUnknown => try stderr_w.print(
                "  the {s} names a kind that is not `program` or `library`\n",
                .{loader.manifest_name},
            ),
            error.ManifestSourceLeavesRoot => try stderr_w.print(
                "  the `source` in its {s} leaves the directory holding it; name a directory inside that one\n",
                .{loader.manifest_name},
            ),
            else => {},
        }
        return exit_io;
    };
    const ast = program.ast;

    // A library has nothing to run: it declares no entry point, and [M-Entry]
    // refuses one written in it. Refused here rather than diagnosed against the
    // source, because the source is not what is wrong -- the command is. So
    // this reads as a misuse of `run` and exits as one.
    // A library stops at an object and links no runtime, so there is no
    // allocator for the flag to choose.
    if (is_build and program.kind == .library and storage == .checked) {
        try stderr_w.writeAll(
            "error: a library links no runtime, so `--check-storage` has nothing to check\n" ++
                "  link the object against liblinea_rt_checked.a instead\n",
        );
        return exit_usage;
    }

    if (is_run and program.kind == .library) {
        try stderr_w.print(
            "error: a library has nothing to run\n" ++
                "  its {s} names it a library: build it, or test it\n",
            .{loader.manifest_name},
        );
        return exit_usage;
    }

    if (is_dump_tokens) {
        const stdout_file = std.Io.File.stdout();
        var stdout: Out = .{};
        const stdout_w = stdout.open(io, stdout_file);
        defer stdout.flush() catch {};

        // A token's span indexes the file that produced it, so each part is
        // dumped against its own text and its own run of the array.
        for (ast.parts) |part| {
            if (part.file == .none) continue;
            try lexer_dump.dumpTokens(stdout_w, part.source, ast.tokens, part.token_start, part.token_end);
        }
    } else {
        {
            if (is_dump_ast) {
                const stdout_file = std.Io.File.stdout();
                var stdout: Out = .{};
                const stdout_w = stdout.open(io, stdout_file);
                defer stdout.flush() catch {};

                try dumpAst(stdout_w, &ast, program.ownDeclarations());
            } else {
                // `run` and `check` differ only in whether the value is printed,
                // so a file that checks clean is a file that runs.
                var settled = try checkProgram(gpa, process.gpa, &program, &interner, &sink, purpose);
                defer settled.deinit(gpa);
                const res = &settled.res;
                const typing = &settled.typing;
                const disposals = &settled.disposals;

                if (is_dump_expanded and !sink.hasErrors()) {
                    const stdout_file = std.Io.File.stdout();
                    var stdout: Out = .{};
                    const stdout_w = stdout.open(io, stdout_file);
                    defer stdout.flush() catch {};

                    try dumpExpanded(&settled.expanded, settled.expanded.modules, stdout_w);
                }

                // Only where the passes were happy. Both of these render the
                // program as source, and a tree with an error node in it has
                // no source to render -- the frontend always returns a tree,
                // and it is the driver that decides whether to go on.
                if (is_dump_inferred and !sink.hasErrors()) {
                    const stdout_file = std.Io.File.stdout();
                    var stdout: Out = .{};
                    const stdout_w = stdout.open(io, stdout_file);
                    defer stdout.flush() catch {};

                    try annotated.dumpInferred(gpa, stdout_w, &ast, res, typing, program.ownDeclarations());
                }

                if (is_dump_mono and !sink.hasErrors()) {
                    if (try lower(gpa, &settled.expanded, res, typing, disposals, &sink, .program)) |m| {
                        const stdout_file = std.Io.File.stdout();
                        var stdout: Out = .{};
                        const stdout_w = stdout.open(io, stdout_file);
                        defer stdout.flush() catch {};

                        try annotated.dumpMono(gpa, stdout_w, &settled.expanded, typing, &m);
                    }
                }

                if (is_dump_mir and !sink.hasErrors()) {
                    if (try lower(gpa, &settled.expanded, res, typing, disposals, &sink, .program)) |lowered| {
                        const stdout_file = std.Io.File.stdout();
                        var stdout: Out = .{};
                        const stdout_w = stdout.open(io, stdout_file);
                        defer stdout.flush() catch {};

                        try dumpMir(stdout_w, &lowered);
                    }
                }

                if (is_dump_asm and !sink.hasErrors()) {
                    if (try lower(gpa, &settled.expanded, res, typing, disposals, &sink, .program)) |lowered| {
                        // In the scratch directory and named for the run, for
                        // the reasons the test build is: nothing lands beside
                        // anything the user wrote, and two dumps at once do
                        // not overwrite each other.
                        const at = std.Io.Clock.awake.now(io);
                        const target = try std.fmt.allocPrint(
                            gpa,
                            "{s}/linea-asm-{d}",
                            .{ scratchDir(process.minimal.environ), at.nanoseconds },
                        );
                        const mid = try toolchain.Intermediates.of(gpa, target);
                        defer mid.deinit(gpa);
                        const asm_path = try std.fmt.allocPrint(gpa, "{s}.s", .{target});
                        defer {
                            mid.remove(io);
                            std.Io.Dir.cwd().deleteFile(io, asm_path) catch {};
                        }

                        {
                            const file = std.Io.Dir.cwd().createFile(io, mid.ir, .{}) catch {
                                try stderr_w.print("error: cannot write '{s}'\n", .{mid.ir});
                                return exit_io;
                            };
                            defer file.close(io);
                            var out: Out = .{};
                            if (!try emitMlir(gpa, out.open(io, file), &lowered, &table, &sink)) return exit_defect;
                            try out.flush();
                        }

                        if (try toolchain.assemble(gpa, io, mid, asm_path, opt_level)) |f| {
                            if (f.missing) {
                                try stderr_w.print("error: {s} is not installed\n", .{f.tool.command()});
                                return exit_io;
                            }
                            try stderr_w.print("error: {s} failed\n", .{f.tool.command()});
                            if (f.output.len > 0) try stderr_w.writeAll(f.output);
                            return refusalStatus(f.tool);
                        }

                        const text = std.Io.Dir.cwd().readFileAlloc(io, asm_path, gpa, .limited(1 << 26)) catch {
                            try stderr_w.print("error: cannot read '{s}'\n", .{asm_path});
                            return exit_io;
                        };
                        const stdout_file = std.Io.File.stdout();
                        var stdout: Out = .{};
                        const stdout_w = stdout.open(io, stdout_file);
                        defer stdout.flush() catch {};
                        try stdout_w.writeAll(text);
                    }
                }

                if (is_test) {
                    if (!sink.hasErrors()) {
                        if (try lower(gpa, &settled.expanded, res, typing, disposals, &sink, purpose)) |lowered| {
                            // Beside nothing the user wrote. `run` builds next
                            // to the source so an interrupted one leaves
                            // something recognisable, and that is wrong here
                            // twice over: a test root is somebody's source
                            // directory, and a corpus case's root is a
                            // directory whose contents are compared against
                            // goldens.
                            //
                            // Named for the run rather than for the root, so
                            // two at once do not delete each other's binary and
                            // report the loss as tests that could not be run --
                            // a watch loop and a sharded CI job are both two at
                            // once.
                            const at = std.Io.Clock.awake.now(io);
                            const target = try std.fmt.allocPrint(
                                gpa,
                                "{s}/linea-test-{d}",
                                .{ scratchDir(process.minimal.environ), at.nanoseconds },
                            );

                            const stopped = try compileToExecutable(gpa, io, process.minimal.environ, stderr_w, .{
                                .mir = &lowered,
                                .table = &table,
                                .sink = &sink,
                                .out_path = target,
                                .opt = opt_level,
                                .keep = keep,
                                .storage = storage,
                            });

                            // Removed whatever happened, including where the
                            // link failed and left them: what a failed test
                            // build leaves behind is not something anyone reads,
                            // and it is not in a directory anyone is looking at.
                            defer {
                                std.Io.Dir.cwd().deleteFile(io, target) catch {};
                                if (toolchain.Intermediates.of(gpa, target)) |mid| {
                                    mid.remove(io);
                                    mid.deinit(gpa);
                                } else |_| {}
                            }

                            if (stopped) |status| {
                                if (status != exit_defect) return status;
                                defect = true;
                            } else {
                                // One compile, one link, and one child per
                                // test. What each said is held until its line
                                // is due, because the order they finish in is
                                // not the order they are read in -- and written
                                // the moment it is due, so a suite reports as
                                // it goes.
                                try report.emit(&table, &sink);
                                const stdout_file = std.Io.File.stdout();
                                var stdout: Out = .{};
                                const stdout_w = stdout.open(io, stdout_file);
                                const passed = try runner.run(
                                    gpa,
                                    io,
                                    target,
                                    res.tests,
                                    std.Thread.getCpuCount() catch 1,
                                    stdout_w,
                                );
                                try stdout.flush();

                                return if (passed) exit_ok else exit_diagnostics;
                            }
                        }
                    }
                }

                // A module a named file selected is checked whether or not it
                // declares `main`, but only a `main` can be run or built. Said
                // as a misuse of the command, like running a library.
                if ((is_build or is_run) and program.named_module and res.entry == .none and !sink.hasErrors()) {
                    try report.emit(&table, &sink);
                    try stderr_w.print(
                        "error: the module of '{s}' declares no `main`, so there is nothing to {s}\n" ++
                            "  name a file of a module that declares one, or the program's own directory\n",
                        .{ file_path, if (is_run) "run" else "build" },
                    );
                    return exit_usage;
                }

                if (is_build or is_run) {
                    if (!sink.hasErrors()) {
                        if (try lower(gpa, &settled.expanded, res, typing, disposals, &sink, .program)) |lowered| {
                            // Each run owns a directory under the scratch root,
                            // keeping overlapping invocations' builds and cleanup
                            // separate and the source tree untouched.
                            const scratch_root = scratchDir(process.minimal.environ);
                            var run_output = if (is_run) toolchain.RunOutput.create(gpa, io, scratch_root) catch {
                                try stderr_w.print("error: cannot create a directory to build in under '{s}'\n", .{scratch_root});
                                return exit_io;
                            } else null;
                            defer if (run_output) |*output| {
                                output.remove(io);
                                output.deinit(gpa);
                            };
                            const target = if (run_output) |output| output.path else out_path orelse defaultOutputName(file_path);

                            // The name a module directory earns is its own,
                            // which sits exactly where the directory does --
                            // so a build from beside it would hand the linker
                            // a path that is the source. Refused with the
                            // answer, not as whatever a tool says about
                            // opening a directory for writing.
                            if (std.Io.Dir.cwd().openDir(io, target, .{ .iterate = true })) |d| {
                                var dir = d;
                                dir.close(io);
                                try stderr_w.print("error: '{s}' is a directory; pass -o to name the executable\n", .{target});
                                return exit_io;
                            } else |_| {}

                            const stopped = try compileToExecutable(gpa, io, process.minimal.environ, stderr_w, .{
                                .mir = &lowered,
                                .table = &table,
                                .sink = &sink,
                                .out_path = target,
                                .opt = opt_level,
                                .keep = keep,
                                .artifact = if (program.kind == .library) .object else .executable,
                                .storage = storage,
                            });

                            // A refusal to emit falls through to the renderer
                            // rather than returning past it: what it says is in
                            // the sink, and a status with nothing printed under
                            // it is the one shape of failure nobody can act on.
                            if (stopped) |status| {
                                if (status != exit_defect) return status;
                                defect = true;
                            } else if (is_run) {
                                try report.emit(&table, &sink);
                                // What this process wrote reaches its streams
                                // before the program takes the process over.
                                try stderr_w.flush();
                                toolchain.replaceWith(gpa, io, target, program_args) catch {};
                                try stderr_w.print(
                                    "error: cannot execute '{s}'\n",
                                    .{target},
                                );
                                return exit_io;
                            }
                        }
                    }
                } else if (is_emit_mlir) {
                    // Generating code is not running it. A program whose result
                    // overflows traps where it runs rather than being refused
                    // here, so nothing at this point can report a failure that
                    // belongs to execution.
                    if (!sink.hasErrors()) {
                        if (try lower(gpa, &settled.expanded, res, typing, disposals, &sink, purpose)) |lowered| {
                            const stdout_file = std.Io.File.stdout();
                            var stdout: Out = .{};
                            const stdout_w = stdout.open(io, stdout_file);
                            defer stdout.flush() catch {};

                            if (!try emitMlir(gpa, stdout_w, &lowered, &table, &sink)) {
                                defect = true;
                            }
                        }
                    }
                } else if (is_check) {
                    try loader.checkInstantiations(gpa, &settled, &sink);
                }
            }
        }
    }

    try report.emit(&table, &sink);

    if (defect) return exit_defect;
    return if (sink.hasErrors()) exit_diagnostics else exit_ok;
}

test "dumpTokens emits index, tag, span and escaped text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "t.lin", .text = "let x // c\n" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try lexer_dump.dumpTokens(&out.writer, source.text, tokens.slice(), 0, @intCast(tokens.len));

    try testing.expectEqualStrings(
        \\0 keyword_let 0..3 "let"
        \\1 identifier 4..5 "x"
        \\2 comment 6..10 "// c"
        \\3 eof 11..11 ""
        \\
    , out.written());
}

test "dumpTokens escapes newlines, tabs, quotes and backslashes" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try lexer_dump.writeEscaped(&out.writer, "a\nb\tc\"d\\e");
    try testing.expectEqualStrings("a\\nb\\tc\\\"d\\\\e", out.written());
}

test "run is listed as a command" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try spec.writeUsage(&out.writer);
    const usage_text = out.written();
    try testing.expect(std.mem.indexOf(u8, usage_text, "  run ") != null);
}

test "dump-ast is listed only when dumps are exposed" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try spec.writeUsage(&out.writer);
    const usage_text = out.written();

    if (expose_dumps) {
        try testing.expect(std.mem.indexOf(u8, usage_text, "dump-ast") != null);
    } else {
        try testing.expect(std.mem.indexOf(u8, usage_text, "dump-ast") == null);
    }
}

test "lsp help advertises no operand or options" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try spec.writeCommandUsage(&out.writer, spec.find("lsp").?);
    try testing.expect(std.mem.startsWith(u8, out.written(), "usage: linea lsp\n"));
}

test "init help and validation expose only its own options" {
    const cmd = spec.find("init").?;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try spec.writeCommandUsage(&out.writer, cmd);
    try testing.expect(std.mem.indexOf(u8, out.written(), "--library") != null);
    try testing.expect(std.mem.indexOf(u8, out.written(), "--yes") != null);
    try testing.expect(std.mem.indexOf(u8, out.written(), "--color") == null);
    try testing.expect(std.mem.indexOf(u8, out.written(), "--error-format") == null);

    var own: cli.Iterator = .{ .spec = spec, .command = cmd, .args = &.{"--library"} };
    try testing.expectEqualStrings("--library", own.next().?.option.name);
    try testing.expect(own.problem == null);
    var diagnostic: cli.Iterator = .{ .spec = spec, .command = cmd, .args = &.{"--color=never"} };
    try testing.expect(diagnostic.next() == null);
    try testing.expectEqualStrings("--color", diagnostic.problem.?.unknown);
}

test "a command rejects an option that belongs to another" {
    var it: cli.Iterator = .{
        .spec = spec,
        .command = spec.find("check").?,
        .args = &.{ "main.lin", "--keep" },
    };
    while (it.next()) |_| {}
    try testing.expectEqualStrings("check", it.problem.?.wrong_command.used_with);
}

test "a qualified payloadless variant records every namespace expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var program = try loadFromMemory(gpa, &table, &sink, &interner, "m/main.lin", &.{.{
        .path = "m/main.lin",
        .text =
        \\import std.mem
        \\fn main() -> UInt8 {
        \\    let failure = mem.Oom.Exhausted
        \\    match failure { Exhausted => 0 }
        \\}
        ,
    }}, .program, true, .borrow);
    const settled = try checkProgram(gpa, testing.allocator, &program, &interner, &sink, .program);
    try testing.expect(!sink.hasErrors());
    const ast = &settled.expanded.ast;
    for (0..ast.exprCount()) |i| {
        const expression = @import("../syntax/node.zig").ExprId.at(@intCast(i));
        if (ast.fileOfExpr(expression) != program.primaryFile()) continue;
        try testing.expect(settled.typing.exprType(expression) != .poison);
    }
}

test "a call reaching a generic operation through a trait says both" {
    // The two notes land in different places, so a call that settles the
    // operation's own parameters and settles `Self` writes both. Not a
    // conformance case because an operation declaring type parameters of its
    // own is source the editor grammar does not yet parse, and the corpus is
    // swept with it.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;

    var program = try loadFromMemory(gpa, &table, &sink, &interner, "m/main.lin", &.{.{
        .path = "m/main.lin",
        .text =
        \\struct Coins {
        \\    count: UInt8,
        \\}
        \\
        \\trait Measure {
        \\    fn of[U](x: Self, u: U) -> UInt8
        \\}
        \\
        \\impl Measure for Coins {
        \\    fn of[U](x: Self, _u: U) -> UInt8 {
        \\        x.count
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let c: Coins = .{ count = 3 }
        \\    let flag: Bool = true
        \\    Measure.of(c, flag)
        \\}
        \\
        ,
    }}, .program, true, .borrow);

    var settled = try checkProgram(gpa, testing.allocator, &program, &interner, &sink, .program);
    try testing.expect(!sink.hasErrors());

    var out: std.Io.Writer.Allocating = .init(gpa);
    try annotated.dumpInferred(gpa, &out.writer, &program.ast, &settled.res, &settled.typing, program.ownDeclarations());
    try testing.expect(std.mem.indexOf(
        u8,
        out.written(),
        "Measure[Coins].of[Bool](c, flag)",
    ) != null);
}

test "parseColor accepts the documented values" {
    try testing.expectEqual(ColorArg.always, parseColor("always").?);
    try testing.expectEqual(ColorArg.never, parseColor("never").?);
    try testing.expectEqual(ColorArg.auto, parseColor("auto").?);
    try testing.expect(parseColor("purple") == null);
}
