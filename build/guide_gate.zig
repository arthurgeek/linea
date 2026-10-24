//! Compiles every program and fragment the guide pastes and holds the output
//! pasted beside each to what the compiler prints.
//!
//! Usage: `guide-gate <guide directory> <linea> <scratch directory> <tests directory> <repository root> [walkers]`.
//! Reading the guide is `source.zig`'s job and judging a result is too; this
//! file only runs the compiler and reports.

const std = @import("std");
const source = @import("source.zig");
const pool = @import("pool.zig");

/// Longest a pasted program may take to compile and run. A program that needs
/// more is a server or a loop, and is excluded by name.
const program_timeout_seconds = 120;

const Outcome = struct {
    failure: ?[]const u8 = null,
    /// What the compiler printed, which the wording check reads.
    output: []const u8 = "",
};

const Walk = struct {
    io: std.Io,
    linea: []const u8,
    scratch: []const u8,
    programs: []const source.GuideProgram,
    outcomes: []Outcome,

    fn run(self: Walk, gpa: std.mem.Allocator, index: usize) void {
        self.outcomes[index] = self.one(gpa, index) catch |err| .{
            .failure = std.fmt.allocPrint(
                gpa,
                "{s}:{d}: the gate could not run this program: {s}\n",
                .{ self.programs[index].chapter, self.programs[index].line, @errorName(err) },
            ) catch "out of memory\n",
        };
    }

    fn one(self: Walk, gpa: std.mem.Allocator, index: usize) !Outcome {
        const program = self.programs[index];
        const directory = try std.fmt.allocPrint(gpa, "{s}/{s}-{d}", .{ self.scratch, program.chapter, program.line });
        const cwd = std.Io.Dir.cwd();
        cwd.deleteTree(self.io, directory) catch {};
        try cwd.createDirPath(self.io, directory);
        for (program.files) |file| {
            const path = try std.fs.path.join(gpa, &.{ directory, file.path });
            if (std.fs.path.dirname(path)) |parent| try cwd.createDirPath(self.io, parent);
            const text = try std.mem.concat(gpa, u8, &.{ file.text, "\n" });
            try cwd.writeFile(self.io, .{ .sub_path = path, .data = text });
        }
        const finished = try pool.runMerged(
            gpa,
            self.io,
            &.{ self.linea, @tagName(program.command), program.target },
            .{ .path = directory },
            program_timeout_seconds,
        );
        if (finished.timed_out) {
            const command = try std.fmt.allocPrint(gpa, "linea {s} {s}", .{ @tagName(program.command), program.target });
            return .{ .failure = try std.fmt.allocPrint(
                gpa,
                "{s}:{d}: {s}write `<!-- guide: unchecked REASON -->` above a program that cannot finish\n",
                .{ program.chapter, program.line, try pool.timeoutMessage(gpa, command, program_timeout_seconds, finished.output) },
            ) };
        }
        cwd.deleteTree(self.io, directory) catch {};
        return .{ .failure = source.judgeGuideProgram(gpa, program, finished.output, finished.succeeded), .output = finished.output };
    }
};

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len < 6) {
        std.debug.print("usage: guide-gate <guide directory> <linea> <scratch directory> <tests directory> <repository root> [walkers]\n", .{});
        return 2;
    }
    const guide = args[1];
    var root = try std.Io.Dir.cwd().openDir(io, args[5], .{});
    defer root.close(io);
    const wanted: ?usize = if (args.len > 6) try std.fmt.parseInt(usize, args[6], 10) else null;

    const read = struct {
        fn file(i: std.Io, a: std.mem.Allocator, directory: []const u8, name: []const u8) ![]const u8 {
            const path = try std.fs.path.join(a, &.{ directory, name });
            return std.Io.Dir.cwd().readFileAlloc(i, path, a, .limited(1 << 22));
        }
    }.file;

    const listed = source.guidePages(gpa, try read(io, gpa, guide, "README.md"));
    if (listed.len == 0) {
        std.debug.print("guide: {s}/README.md links to no page\n", .{guide});
        return 1;
    }
    var problems: usize = 0;
    // A Markdown page beside the index that it does not link is read by no
    // gate, so it is refused.
    var names: std.ArrayList([]const u8) = .empty;
    {
        var directory = try std.Io.Dir.cwd().openDir(io, guide, .{ .iterate = true });
        defer directory.close(io);
        var entries = directory.iterate();
        while (try entries.next(io)) |entry| {
            if (entry.kind == .file) try names.append(gpa, try gpa.dupe(u8, entry.name));
        }
    }
    for (source.unlinkedGuidePages(gpa, listed, names.items)) |name| {
        std.debug.print("{s}/{s}: the page is not linked from {s}/README.md, so the gate reads none of it; link it, or move it out of the guide\n", .{ guide, name, guide });
        problems += 1;
    }
    // The pages as paths from the repository root, which an excerpt names.
    // `build.zig` passes both directories absolute, so no working directory
    // takes part.
    const relative = try std.fs.path.relative(gpa, "/", null, args[5], guide);
    const pages = try gpa.alloc([]const u8, listed.len);
    for (listed, pages) |entry, *page| page.* = try std.fs.path.join(gpa, &.{ relative, entry.file });
    var programs: std.ArrayList(source.GuideProgram) = .empty;
    var excerpts: usize = 0;
    var excluded: usize = 0;
    var unrun_output: std.ArrayList(source.GuideBlock) = .empty;
    for (listed) |entry| {
        var chapter = entry;
        chapter.text = try read(io, gpa, guide, chapter.file);
        chapter.root = .{ .io = io, .dir = root };
        chapter.pages = pages;
        const reading = source.readGuideChapter(gpa, chapter);
        for (reading.problems) |problem| {
            std.debug.print("{s}/{s}:{d}: {s}\n", .{ guide, problem.chapter, problem.line, problem.message });
        }
        problems += reading.problems.len;
        excerpts += reading.excerpts;
        excluded += reading.excluded;
        try unrun_output.appendSlice(gpa, reading.unrun_output);
        try programs.appendSlice(gpa, reading.programs);
    }

    const outcomes = try gpa.alloc(Outcome, programs.items.len);
    @memset(outcomes, .{});
    try pool.forEach(gpa, programs.items.len, wanted, Walk{
        .io = io,
        .linea = args[2],
        .scratch = args[3],
        .programs = programs.items,
        .outcomes = outcomes,
    }, Walk.run);

    // The pasted errors of programs the gate does not run must read as
    // diagnostics the compiler prints: those of the programs it did run, and
    // the goldens of the corpus.
    var wording: source.DiagnosticWording = .{};
    for (outcomes) |outcome| wording.addOutput(gpa, outcome.output);
    var corpus = try std.Io.Dir.cwd().openDir(io, args[4], .{ .iterate = true });
    defer corpus.close(io);
    var walker = try corpus.walk(gpa);
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".stderr")) continue;
        wording.addOutput(gpa, try corpus.readFileAlloc(io, entry.path, gpa, .limited(1 << 22)));
    }
    var invented: usize = 0;
    for (unrun_output.items) |block| {
        const failure = wording.judge(gpa, block) orelse continue;
        invented += 1;
        std.debug.print("{s}/{s}", .{ guide, failure });
    }

    var failed: usize = 0;
    var compared: usize = 0;
    var compiled: [@typeInfo(source.GuideSource).@"enum".fields.len]usize = @splat(0);
    for (outcomes, programs.items) |outcome, program| {
        compiled[@intFromEnum(program.source)] += 1;
        if (program.expected != null) compared += 1;
        const failure = outcome.failure orelse continue;
        failed += 1;
        std.debug.print("{s}/{s}", .{ guide, failure });
    }
    var check_only: usize = 0;
    for (programs.items) |program| check_only += @intFromBool(program.check_only);
    std.debug.print(
        "guide: {d} programs, {d} fragments and {d} edits compiled ({d} checked and not run), {d} with their pasted output compared; {d} excerpts held to their files; {d} excluded by a marker, {d} of them checked to still fail, whose {d} pasted output blocks and those of programs not run were held to the compiler's wording; {d} failed, {d} unaccounted for\n",
        .{
            compiled[@intFromEnum(source.GuideSource.program)], compiled[@intFromEnum(source.GuideSource.fragment)],
            compiled[@intFromEnum(source.GuideSource.edit)],    check_only,
            compared,                                           excerpts,
            excluded,                                           compiled[@intFromEnum(source.GuideSource.unchecked)],
            unrun_output.items.len,                             failed + invented,
            problems,
        },
    );
    return if (failed + invented + problems == 0) 0 else 1;
}
