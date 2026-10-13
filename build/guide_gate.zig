//! Compiles every complete program the guide pastes and holds the output
//! pasted beside it to what the compiler prints.
//!
//! Usage: `guide-gate <guide directory> <linea> <scratch directory> <tests directory> [walkers]`.
//! Reading the guide is `source.zig`'s job and judging a result is too; this
//! file only runs the compiler and reports.

const std = @import("std");
const source = @import("source.zig");
const process = @import("process");

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
    next: *std.atomic.Value(usize),

    fn run(self: Walk, arena: *std.heap.ArenaAllocator) void {
        while (true) {
            const index = self.next.fetchAdd(1, .monotonic);
            if (index >= self.programs.len) return;
            self.outcomes[index] = self.one(arena.allocator(), index) catch |err| .{
                .failure = std.fmt.allocPrint(
                    arena.allocator(),
                    "{s}:{d}: the gate could not run this program: {s}\n",
                    .{ self.programs[index].chapter, self.programs[index].line, @errorName(err) },
                ) catch "out of memory\n",
            };
        }
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
        // The shell joins the two streams the way a terminal shows them, which
        // is how the guide pastes a program that writes to both.
        const result = process.run(gpa, self.io, .{
            .argv = &.{ "/bin/sh", "-c", "exec \"$0\" \"$@\" 2>&1", self.linea, @tagName(program.command), program.target },
            .cwd = .{ .path = directory },
            .timeout = .{ .duration = .{ .raw = .fromSeconds(program_timeout_seconds), .clock = .awake } },
        }) catch |err| switch (err) {
            error.Timeout => return .{ .failure = try std.fmt.allocPrint(
                gpa,
                "{s}:{d}: `linea {s} {s}` did not finish in {d} seconds; write `<!-- guide: unchecked REASON -->` above a program that cannot\n",
                .{ program.chapter, program.line, @tagName(program.command), program.target, program_timeout_seconds },
            ) },
            else => |e| return e,
        };
        const succeeded = switch (result.term) {
            .exited => |code| code == 0,
            else => false,
        };
        cwd.deleteTree(self.io, directory) catch {};
        return .{ .failure = source.judgeGuideProgram(gpa, program, result.stdout, succeeded), .output = result.stdout };
    }
};

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len < 5) {
        std.debug.print("usage: guide-gate <guide directory> <linea> <scratch directory> <tests directory> [walkers]\n", .{});
        return 2;
    }
    const guide = args[1];
    const wanted: ?usize = if (args.len > 5) try std.fmt.parseInt(usize, args[5], 10) else null;

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
    const count = @min(programs.items.len, @max(1, wanted orelse std.Thread.getCpuCount() catch 1));
    const arenas = try gpa.alloc(std.heap.ArenaAllocator, count);
    for (arenas) |*arena| arena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var next: std.atomic.Value(usize) = .init(0);
    const walk: Walk = .{
        .io = io,
        .linea = args[2],
        .scratch = args[3],
        .programs = programs.items,
        .outcomes = outcomes,
        .next = &next,
    };
    const threads = try gpa.alloc(std.Thread, count);
    for (threads, arenas) |*thread, *arena| thread.* = try std.Thread.spawn(.{}, Walk.run, .{ walk, arena });
    for (threads) |thread| thread.join();

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
