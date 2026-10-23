//! Compiles every complete program the guide pastes and holds the output
//! pasted beside it to what the compiler prints.
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

    const listed = source.guideChapters(gpa, try read(io, gpa, guide, "README.md"));
    if (listed.len == 0) {
        std.debug.print("guide: {s}/README.md links to no chapter\n", .{guide});
        return 1;
    }
    var programs: std.ArrayList(source.GuideProgram) = .empty;
    var problems: usize = 0;
    var fragments: usize = 0;
    var excluded: usize = 0;
    var unrun_output: std.ArrayList(source.GuideBlock) = .empty;
    for (listed) |entry| {
        var chapter = entry;
        chapter.text = try read(io, gpa, guide, chapter.file);
        chapter.root = .{ .io = io, .dir = root };
        const reading = source.readGuideChapter(gpa, chapter);
        for (reading.problems) |problem| {
            std.debug.print("{s}/{s}:{d}: {s}\n", .{ guide, problem.chapter, problem.line, problem.message });
        }
        problems += reading.problems.len;
        fragments += reading.fragments;
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
    for (outcomes, programs.items) |outcome, program| {
        if (program.expected != null) compared += 1;
        const failure = outcome.failure orelse continue;
        failed += 1;
        std.debug.print("{s}/{s}", .{ guide, failure });
    }
    std.debug.print(
        "guide: {d} programs compiled, {d} with their pasted output compared; {d} fragments, {d} excluded by a marker, whose {d} pasted output blocks were held to the compiler's wording; {d} failed, {d} unaccounted for\n",
        .{ programs.items.len, compared, fragments, excluded, unrun_output.items.len, failed + invented, problems },
    );
    return if (failed + invented + problems == 0) 0 else 1;
}
