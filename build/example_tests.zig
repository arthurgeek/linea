//! Runs `linea test` on every root beneath `examples/`.
//!
//! Usage: `example-tests <examples directory> <linea> [workers]`.
//! Choosing the roots and reading a run's test count are `source.zig`'s job;
//! this file only runs the compiler and reports. Which of a root's files
//! declare tests is the compiler's answer, so this file counts what the runs
//! report and fails when that is none, when any root fails, when a root's run
//! ends without a count, and when a `.lin` file lies outside every root's reach.
//!
//! A root with no test is not a failure: most examples teach a program rather
//! than test one, and requiring a test of each would make the gate a list of
//! exemptions. The floor is the sum, and the per-root counts are printed.

const std = @import("std");
const source = @import("source.zig");
const pool = @import("pool.zig");

/// Longest one root's tests may take to build and run.
const root_timeout_seconds = 600;

const Outcome = struct {
    failure: ?[]const u8 = null,
    output: []const u8 = "",
    tests: usize = 0,
};

const Walk = struct {
    io: std.Io,
    linea: []const u8,
    examples: []const u8,
    roots: []const []const u8,
    outcomes: []Outcome,

    fn run(self: Walk, gpa: std.mem.Allocator, index: usize) void {
        self.outcomes[index] = self.one(gpa, self.roots[index]) catch |err| .{
            .failure = std.fmt.allocPrint(gpa, "could not run: {s}\n", .{@errorName(err)}) catch "out of memory\n",
        };
    }

    fn one(self: Walk, gpa: std.mem.Allocator, root: []const u8) !Outcome {
        const path = try std.fs.path.join(gpa, &.{ self.examples, root });
        const finished = try pool.runMerged(gpa, self.io, &.{ self.linea, "test", path }, .inherit, root_timeout_seconds);
        if (finished.timed_out) {
            const command = try std.fmt.allocPrint(gpa, "linea test {s}", .{path});
            return .{ .failure = try pool.timeoutMessage(gpa, command, root_timeout_seconds, finished.output) };
        }
        // The count is the closing line `runner.run` prints in
        // `src/driver/runner.zig`, which build/ cannot import; a change to that
        // line fails every root here with the message below.
        const tests = source.testsReported(finished.output);
        const failure: ?[]const u8 = if (!finished.succeeded)
            finished.output
        else if (tests == null)
            "the run ended without a `N passed, M failed` or `no tests found in` line\n"
        else
            null;
        return .{ .failure = failure, .output = finished.output, .tests = tests orelse 0 };
    }
};

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len < 3) {
        std.debug.print("usage: example-tests <examples directory> <linea> [workers]\n", .{});
        return 2;
    }
    const wanted: ?usize = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else null;

    const entries = switch (try source.exampleLayout(gpa, io, std.Io.Dir.cwd(), args[1])) {
        .entries => |entries| entries,
        .symlink => |path| {
            std.debug.print("{s}/{s} is a symlink; examples hold real files, since `linea` does not follow one inside a root\n", .{ args[1], path });
            return 1;
        },
    };
    const roots = source.exampleRoots(gpa, entries);
    const unreached = source.unreachedSources(gpa, entries, roots);
    for (unreached.files) |path| std.debug.print("{s}/{s} belongs to no example root\n", .{ args[1], path });
    for (unreached.problems) |problem| std.debug.print("{s}/{s}\n", .{ args[1], problem });
    const outcomes = try gpa.alloc(Outcome, roots.len);
    @memset(outcomes, .{});
    try pool.forEach(gpa, roots.len, wanted, Walk{
        .io = io,
        .linea = args[2],
        .examples = args[1],
        .roots = roots,
        .outcomes = outcomes,
    }, Walk.run);

    var failed: usize = 0;
    var tests: usize = 0;
    for (outcomes, roots) |outcome, root| {
        tests += outcome.tests;
        const failure = outcome.failure orelse {
            std.debug.print(">>> {s}: {d} test(s)\n", .{ root, outcome.tests });
            continue;
        };
        failed += 1;
        std.debug.print(">>> {s}: FAILED\n{s}\n", .{ root, failure });
    }
    std.debug.print("examples: {d} root(s), {d} test(s), {d} root(s) failed\n", .{ roots.len, tests, failed });
    if (unreached.files.len + unreached.problems.len > 0) return 1;
    if (tests == 0) {
        std.debug.print("no example root ran a test\n", .{});
        return 1;
    }
    return if (failed == 0) 0 else 1;
}
