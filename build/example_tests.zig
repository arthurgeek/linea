//! Runs `linea test` on every root beneath `examples/` that declares a test.
//!
//! Usage: `example-tests <examples directory> <linea> [workers]`.
//! Choosing the roots is `source.zig`'s job; this file only runs the compiler
//! and reports. It fails when it finds no root, when a test sits in a source
//! no manifest encloses, and when any root's tests fail.

const std = @import("std");
const source = @import("source.zig");
const process = @import("process");

/// Longest one root's tests may take to build and run.
const root_timeout_seconds = 600;

const default_workers = 2;

const Outcome = struct {
    passed: bool = false,
    output: []const u8 = "",
};

const Walk = struct {
    io: std.Io,
    linea: []const u8,
    examples: []const u8,
    roots: []const []const u8,
    outcomes: []Outcome,
    next: *std.atomic.Value(usize),

    fn run(self: Walk, arena: *std.heap.ArenaAllocator) void {
        while (true) {
            const index = self.next.fetchAdd(1, .monotonic);
            if (index >= self.roots.len) return;
            self.outcomes[index] = self.one(arena.allocator(), self.roots[index]) catch |err| .{
                .output = std.fmt.allocPrint(arena.allocator(), "could not run: {s}\n", .{@errorName(err)}) catch "out of memory\n",
            };
        }
    }

    fn one(self: Walk, gpa: std.mem.Allocator, root: []const u8) !Outcome {
        const path = try std.fs.path.join(gpa, &.{ self.examples, root });
        const result = process.run(gpa, self.io, .{
            .argv = &.{ "/bin/sh", "-c", "exec \"$0\" \"$@\" 2>&1", self.linea, "test", path },
            .timeout = .{ .duration = .{ .raw = .fromSeconds(root_timeout_seconds), .clock = .awake } },
        }) catch |err| switch (err) {
            error.Timeout => return .{ .output = "did not finish in time\n" },
            else => |e| return e,
        };
        const passed = switch (result.term) {
            .exited => |code| code == 0,
            else => false,
        };
        return .{ .passed = passed, .output = result.stdout };
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
    const wanted: usize = if (args.len > 3) try std.fmt.parseInt(usize, args[3], 10) else default_workers;

    const files = try source.exampleSource(gpa, io, std.Io.Dir.cwd(), args[1]);
    const found = source.exampleTestRoots(gpa, files);
    for (found.unowned) |path| {
        std.debug.print("{s}/{s}: declares a test, and no linea.json encloses it, so no root runs it\n", .{ args[1], path });
    }
    if (found.roots.len == 0) {
        std.debug.print("no example declared a test\n", .{});
        return 1;
    }

    const outcomes = try gpa.alloc(Outcome, found.roots.len);
    @memset(outcomes, .{});
    const count = @min(found.roots.len, @max(1, wanted));
    const arenas = try gpa.alloc(std.heap.ArenaAllocator, count);
    for (arenas) |*arena| arena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var next: std.atomic.Value(usize) = .init(0);
    const walk: Walk = .{
        .io = io,
        .linea = args[2],
        .examples = args[1],
        .roots = found.roots,
        .outcomes = outcomes,
        .next = &next,
    };
    const threads = try gpa.alloc(std.Thread, count);
    for (threads, arenas) |*thread, *arena| thread.* = try std.Thread.spawn(.{}, Walk.run, .{ walk, arena });
    for (threads) |thread| thread.join();

    var failed: usize = 0;
    for (outcomes, found.roots) |outcome, root| {
        std.debug.print(">>> {s}/{s}\n", .{ args[1], root });
        if (!outcome.passed) {
            failed += 1;
            std.debug.print("{s}FAILED: {s}\n", .{ outcome.output, root });
        }
    }
    std.debug.print("examples: {d} root(s) tested, {d} failed, {d} with an unreachable test\n", .{ found.roots.len, failed, found.unowned.len });
    return if (failed + found.unowned.len == 0) 0 else 1;
}
