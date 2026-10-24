//! `linea init` — start a program, or a library, in a directory it names.

const std = @import("std");
const testing = std.testing;

const driver = @import("driver.zig");
const cli = @import("../support/cli.zig");
const loader = @import("loader.zig");
const program_mod = @import("../syntax/program.zig");

/// Initializes one explicitly named directory. Argument validation finishes
/// before any directory is created or source is written.
///
/// Two files, and neither is overwritten. A manifest that already exists means
/// the directory is already a program, which is a mistake to report rather
/// than a state to impose: the one thing this must never do is rewrite a
/// project's configuration because it was run twice.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const []const u8,
    stderr: *std.Io.Writer,
) !u8 {
    var named: ?[]const u8 = null;
    var kind: program_mod.Kind = .program;
    var answered_yes = false;
    const cmd = driver.spec.find("init").?;
    var it: cli.Iterator = .{ .spec = driver.spec, .command = cmd, .args = args };
    while (it.next()) |item| switch (item) {
        .option => |option| {
            if (std.mem.eql(u8, option.name, "--library")) {
                kind = .library;
            } else if (std.mem.eql(u8, option.name, "--yes")) {
                answered_yes = true;
            }
        },
        .operand => |path| {
            if (named != null) {
                try stderr.print("error: `init` starts one program, and was given several\n", .{});
                return driver.exit_usage;
            }
            named = loader.trimmedEntry(path);
        },
    };
    if (it.problem) |problem| {
        try problem.report(stderr);
        try driver.spec.writeCommandUsage(stderr, cmd);
        return driver.exit_usage;
    }
    const root = named orelse {
        // Named rather than defaulted, because the working directory is
        // whatever the shell was pointing at and starting a project into it by
        // accident is the one mistake this command can make that cannot be
        // undone by deleting a file.
        try stderr.print(
            "error: `init` names the directory to start: `linea init <name>`, or `linea init .` for this one\n",
            .{},
        );
        return driver.exit_usage;
    };

    const opened = openOrCreate(io, root) catch |err| {
        try stderr.print("error: cannot open '{s}': {s}\n", .{ root, @errorName(err) });
        return driver.exit_io;
    };
    defer opened.close(io);

    // A directory holding a manifest is already a root, which `into` reports
    // below; anything else in one is a project this would be writing into
    // rather than starting, and that is worth a question.
    if (!try holdsManifest(io, opened) and try holdsAnything(gpa, io, opened)) {
        if (!answered_yes and !try agreed(io, root, stderr)) {
            try stderr.print("nothing was written\n", .{});
            return driver.exit_diagnostics;
        }
    }

    return switch (try into(gpa, io, opened, kind)) {
        .started => driver.exit_ok,
        .already_a_program => blk: {
            try stderr.print("error: '{s}' already holds a {s}\n", .{ root, loader.manifest_name });
            break :blk driver.exit_diagnostics;
        },
    };
}

/// Whether the directory already holds a manifest, and so is already a root.
fn holdsManifest(io: std.Io, dir: std.Io.Dir) !bool {
    const opened = dir.openFile(io, loader.manifest_name, .{}) catch return false;
    var f = opened;
    f.close(io);
    return true;
}

/// Whether the directory holds anything at all.
///
/// Any entry, not only source: a directory holding a `README` or a `.git` is
/// somebody's project, and starting one inside it is a different act from
/// starting one in an empty directory.
fn holdsAnything(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !bool {
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    return try walker.next(io) != null;
}

/// Asks whether to start a project inside a directory that already holds
/// something, and answers false where nobody is there to ask.
///
/// A question nobody can answer is a hang, and this runs in scripts and in CI
/// as readily as in a shell -- so a terminal is what makes the question
/// askable, and `--yes` is how everything else answers it in advance.
fn agreed(io: std.Io, root: []const u8, stderr: *std.Io.Writer) !bool {
    const in = std.Io.File.stdin();
    if (!(in.isTty(io) catch false)) {
        try stderr.print(
            "error: '{s}' already holds files, and there is no terminal to ask\n" ++
                "  pass `--yes` to start a project in it anyway\n",
            .{root},
        );
        return false;
    }

    try stderr.print("'{s}' already holds files. Start a project in it anyway? [y/N] ", .{root});
    try stderr.flush();

    // Whatever the line holds, bounded: an answer is one word and a terminal
    // that sends more than this is not answering the question.
    var buffer: [64]u8 = undefined;
    var reader = in.reader(io, &buffer);
    const line = reader.interface.takeDelimiterExclusive('\n') catch return false;
    const answer = std.mem.trim(u8, line, " \t\r");
    return std.mem.eql(u8, answer, "y") or std.mem.eql(u8, answer, "Y");
}

const Started = enum { started, already_a_program };

/// Writes a program's manifest into `dir`, and an entry point beneath it where
/// there is no source at all.
///
/// Takes the directory rather than a path so that what it writes can be
/// checked against a directory nothing else owns. Resolving from the working
/// directory here would mean the only way to test it is to write into the
/// checkout.
///
/// What the manifest says is decided by what is already there. A directory
/// holding `.lin` files of its own is the module those files are in, and a
/// manifest naming `src` would leave every one of them part of no program at
/// all -- the files untouched and their meaning rewritten. Such a directory is
/// marked as the flat program it already was.
///
/// The entry point is written only where the source root holds no `.lin` file
/// at all. Running this inside an existing tree marks it and leaves its source
/// alone; a second `main` beside the one already there is the shape the
/// manifest exists to avoid.
fn into(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    kind: program_mod.Kind,
) !Started {
    if (dir.openFile(io, loader.manifest_name, .{})) |existing| {
        var f = existing;
        f.close(io);
        return .already_a_program;
    } else |_| {}

    if (try holdsSource(gpa, io, dir, .directly)) {
        try writeFile(io, dir, loader.manifest_name, switch (kind) {
            .program => "{}\n",
            .library => "{\n    \"kind\": \"library\"\n}\n",
        });
        return .started;
    }

    // The layout is named rather than left to default, so a new root says
    // where its source is instead of leaving whoever reads it to assume.
    try writeFile(io, dir, loader.manifest_name, switch (kind) {
        .program => "{\n    \"source\": \"src\"\n}\n",
        .library => "{\n    \"source\": \"src\",\n    \"kind\": \"library\"\n}\n",
    });

    const source_root = "src";
    const source = try openOrCreateIn(io, dir, source_root);
    defer source.close(io);

    if (try holdsSource(gpa, io, source, .anywhere_beneath)) return .started;

    // What a starter says is the shape of the language, not the smallest thing
    // that compiles: a declaration, a test over it, and -- for a program -- an
    // entry point that calls it. So `run` and `test` both do something on a
    // root nobody has written a line into yet.
    //
    // A library is handed no entry point, because one here would fail
    // [M-Entry] on its own first build, and its file is not called `main`
    // either: neither name means anything to the compiler -- a module is a
    // directory and every `.lin` file in it belongs to that module -- so the
    // name is what a reader is told and nothing more.
    switch (kind) {
        .program => try writeFile(io, source, "main.lin", starting_program),
        .library => try writeFile(io, source, "lib.lin", starting_library),
    }
    return .started;
}

/// What `init` writes into a program it started.
///
/// A declaration, a test over it, and an entry point that calls it and prints
/// what it answered -- so `run` and `test` both do something visible on a root
/// nobody has written a line into yet.
const starting_program =
    \\import std.testing
    \\import std.io
    \\
    \\use io.IoError
    \\use io.println
    \\
    \\fn square(num: UInt8) -> UInt8 {
    \\    num * num
    \\}
    \\
    \\test fn a_square_is_a_number_times_itself() -> Result[(), testing.Failure] {
    \\    testing.assert_eq(square(3), 9, "three squared is nine")?
    \\
    \\    return .Ok(())
    \\}
    \\
    \\fn main() -> Result[UInt8, IoError] {
    \\    let answer = square(3)
    \\    println("3 squared is {answer}")?
    \\
    \\    return .Ok(0)
    \\}
    \\
;

/// What `init --library` writes into a library it started.
///
/// A public declaration and its test, with no entry point. Nothing here prints:
/// what a library does is decided by whatever calls it.
const starting_library =
    \\import std.testing
    \\
    \\pub fn square(num: UInt8) -> UInt8 {
    \\    num * num
    \\}
    \\
    \\test fn a_square_is_a_number_times_itself() -> Result[(), testing.Failure] {
    \\    testing.assert_eq(square(3), 9, "three squared is nine")?
    \\
    \\    return .Ok(())
    \\}
    \\
;

/// How far down a search for source looks: the module a directory is, or the
/// whole subtree it stands over.
const Depth = enum { directly, anywhere_beneath };

/// Whether a directory already holds a `.lin` file.
///
/// Costs one walk of the subtree, which is what a directory nobody has marked
/// yet is worth reading once.
fn holdsSource(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, depth: Depth) !bool {
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".lin")) continue;
        // A `.lin` below a subdirectory belongs to that submodule, and stays
        // in it whichever way this directory is marked.
        if (depth == .directly and std.mem.indexOfScalar(u8, entry.path, '/') != null) continue;
        return true;
    }
    return false;
}

/// The directory at `path`, created along with its parents if it is not there,
/// and opened to be walked as well as written into.
fn openOrCreate(io: std.Io, path: []const u8) !std.Io.Dir {
    std.Io.Dir.cwd().createDirPath(io, path) catch {};
    return std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
}

/// A source root, created if it is not there, and opened to be walked as well
/// as written into.
///
/// `iterate` is what makes the walk legal. A directory opened without it can
/// still be iterated on some hosts and not on others, so the flag is the
/// difference between a command that works everywhere and one that works where
/// it was written.
fn openOrCreateIn(io: std.Io, dir: std.Io.Dir, name: []const u8) !std.Io.Dir {
    dir.createDirPath(io, name) catch {};
    return dir.openDir(io, name, .{ .iterate = true });
}

fn writeFile(io: std.Io, dir: std.Io.Dir, name: []const u8, text: []const u8) !void {
    const file = try dir.createFile(io, name, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, text);
}

test "init starts programs and libraries the compiler accepts" {
    const FileTable = @import("../support/source.zig").FileTable;
    const Sink = @import("../diagnostics/sink.zig").Sink;
    const Interner = @import("../support/interner.zig").Interner;

    for ([_]program_mod.Kind{ .program, .library }) |kind| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var tmp = testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        try testing.expectEqual(Started.started, try into(gpa, testing.io, tmp.dir, kind));
        try tmp.dir.access(testing.io, switch (kind) {
            .program => "src/main.lin",
            .library => "src/lib.lin",
        }, .{});
        if (kind == .program) {
            const generated = try tmp.dir.readFileAlloc(testing.io, "src/main.lin", gpa, .unlimited);
            const exercised = try std.Io.Dir.cwd().readFileAlloc(
                testing.io,
                "tests/cmd/fixtures/a_started_program_exits_successfully/src/main.lin",
                gpa,
                .unlimited,
            );
            try testing.expectEqualStrings(exercised, generated);
        }
        const root = try tmp.dir.realPathFileAlloc(testing.io, ".", gpa);
        var files: FileTable = .{};
        var sink = Sink.init(gpa);
        var interner: Interner = .{};
        const program = try loader.loadFromDisk(gpa, testing.io, &files, &sink, &interner, root, .tests, true);
        try testing.expect(!sink.hasErrors());
        try testing.expectEqual(kind, program.kind);
        const semantics = try loader.checkWhole(gpa, testing.allocator, &program, &interner, &sink, .tests);
        try testing.expect(!sink.hasErrors());
        try testing.expectEqual(@as(usize, 1), semantics.res.tests.len);
        if (kind == .library) {
            const square = for (semantics.res.declaredIn(semantics.res.moduleScope(.from(0)))) |binding| {
                if (semantics.res.kindOf(binding) != .function) continue;
                const decl = semantics.res.declaredBy(binding);
                if (!program.root().decls.contains(decl)) continue;
                if (std.mem.eql(u8, program.ast.tokenText(program.ast.declName(decl)), "square")) break binding;
            } else return error.TestExpectedPublicExample;
            try testing.expectEqual(.public, semantics.res.namingReachOf(square));
        }
    }
}

test "init refuses a directory that is already a program" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try testing.expectEqual(Started.started, try into(gpa, testing.io, tmp.dir, .program));
    // The second run must not rewrite what the first wrote: a manifest is a
    // project's configuration, and running a command twice is not consent to
    // replace it.
    try testing.expectEqual(Started.already_a_program, try into(gpa, testing.io, tmp.dir, .program));
}

test "init marks a flat tree as the flat program it already was" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    {
        const written = try tmp.dir.createFile(testing.io, "tally.lin", .{});
        defer written.close(testing.io);
        try written.writeStreamingAll(testing.io, "fn main() -> UInt8 {\n    1\n}\n");
    }

    try testing.expectEqual(Started.started, try into(gpa, testing.io, tmp.dir, .program));

    // The files directly inside a directory are its module. A manifest naming
    // `src` would leave them part of no program at all, which is a rewrite of
    // what they mean rather than a mark on the directory.
    const manifest = try tmp.dir.readFileAlloc(testing.io, loader.manifest_name, gpa, .unlimited);
    defer gpa.free(manifest);
    try testing.expectEqualStrings("{}\n", manifest);
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "src/main.lin", .{}));
}

test "init marks a tree that already holds source, and adds no second main" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, "src");
    {
        const written = try tmp.dir.createFile(testing.io, "src/tally.lin", .{});
        defer written.close(testing.io);
        try written.writeStreamingAll(testing.io, "fn main() -> UInt8 {\n    1\n}\n");
    }

    try testing.expectEqual(Started.started, try into(gpa, testing.io, tmp.dir, .program));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "src/main.lin", .{}));
}
