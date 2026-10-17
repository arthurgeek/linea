//! What the gates that run `linea` over many inputs share: a pool of workers
//! and one way to run a child with its two streams read as a terminal shows
//! them.

const std = @import("std");
const process = @import("process");

/// How many workers run `count` jobs: `wanted`, or one per core, and never
/// more than there are jobs.
pub fn workers(count: usize, wanted: ?usize) usize {
    return @min(count, @max(1, wanted orelse std.Thread.getCpuCount() catch 1));
}

/// Calls `work(context, allocator, index)` once for each index below `count`,
/// on `workers(count, wanted)` threads. Each thread allocates from an arena of
/// its own that is never freed, because what `work` stores in `context` for the
/// caller to read afterwards lives in it until the process exits.
pub fn forEach(
    gpa: std.mem.Allocator,
    count: usize,
    wanted: ?usize,
    context: anytype,
    comptime work: fn (@TypeOf(context), std.mem.Allocator, usize) void,
) !void {
    const n = workers(count, wanted);
    var next: std.atomic.Value(usize) = .init(0);
    const Thread = struct {
        fn run(ctx: @TypeOf(context), counter: *std.atomic.Value(usize), total: usize, arena: *std.heap.ArenaAllocator) void {
            while (true) {
                const index = counter.fetchAdd(1, .monotonic);
                if (index >= total) return;
                work(ctx, arena.allocator(), index);
            }
        }
    };
    const arenas = try gpa.alloc(std.heap.ArenaAllocator, n);
    for (arenas) |*arena| arena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const threads = try gpa.alloc(std.Thread, n);
    for (threads, arenas) |*thread, *arena| thread.* = try std.Thread.spawn(.{}, Thread.run, .{ context, &next, count, arena });
    for (threads) |thread| thread.join();
}

pub const Finished = struct {
    succeeded: bool,
    /// Standard output and standard error, interleaved as the child wrote them.
    output: []const u8,
    /// Set when the child was killed at the deadline; `output` is then what it
    /// had written by then.
    timed_out: bool = false,
};

/// Runs `argv`, with its standard error folded into its standard output, and
/// kills it after `timeout_seconds`.
pub fn runMerged(
    gpa: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    cwd: std.process.Child.Cwd,
    timeout_seconds: u32,
) !Finished {
    var shell_argv: std.ArrayList([]const u8) = .empty;
    try shell_argv.appendSlice(gpa, &.{ "/bin/sh", "-c", "exec \"$0\" \"$@\" 2>&1" });
    try shell_argv.appendSlice(gpa, argv);
    var partial: []u8 = &.{};
    const result = process.run(gpa, io, .{
        .argv = shell_argv.items,
        .cwd = cwd,
        .timeout = .{ .duration = .{ .raw = .fromSeconds(timeout_seconds), .clock = .awake } },
        .partial = &partial,
    }) catch |err| switch (err) {
        error.Timeout => return .{ .succeeded = false, .output = partial, .timed_out = true },
        else => |e| return e,
    };
    return .{
        .succeeded = switch (result.term) {
            .exited => |code| code == 0,
            else => false,
        },
        .output = result.stdout,
    };
}

/// The sentence both gates report for a run killed at its deadline, followed
/// by what it had written.
pub fn timeoutMessage(gpa: std.mem.Allocator, command: []const u8, timeout_seconds: u32, output: []const u8) ![]const u8 {
    return std.fmt.allocPrint(gpa, "`{s}` did not finish in {d} seconds; it had written:\n{s}\n", .{ command, timeout_seconds, output });
}
