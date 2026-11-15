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
///
/// Every index is worked however many threads the host starts. A thread it
/// declines to start leaves its share to the others and to the calling
/// thread, and the call returns only once every thread that did start has
/// been joined: each borrows this call's counter and the caller's context.
pub fn forEach(
    gpa: std.mem.Allocator,
    count: usize,
    wanted: ?usize,
    context: anytype,
    comptime work: fn (@TypeOf(context), std.mem.Allocator, usize) void,
) !void {
    return forEachSpawning(gpa, count, wanted, context, work, std.Thread.spawn);
}

/// `forEach`, starting its threads through `spawn`, so a test can have the
/// host decline one.
fn forEachSpawning(
    gpa: std.mem.Allocator,
    count: usize,
    wanted: ?usize,
    context: anytype,
    comptime work: fn (@TypeOf(context), std.mem.Allocator, usize) void,
    comptime spawn: anytype,
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

    var started: usize = 0;
    while (started < n) : (started += 1) {
        threads[started] = spawn(.{}, Thread.run, .{ context, &next, count, &arenas[started] }) catch break;
    }
    // Indexes are handed out one at a time from the shared counter, so the
    // calling thread working until none is left covers every thread that
    // never started.
    if (started < n) Thread.run(context, &next, count, &arenas[started]);
    for (threads[0..started]) |thread| thread.join();
}

test "every index is worked once, however many threads the host starts" {
    const gpa = std.testing.allocator;
    const jobs = 200;

    // Starts `allowed` threads and declines every one after.
    const Declining = struct {
        var allowed: usize = 0;

        fn spawn(config: std.Thread.SpawnConfig, comptime function: anytype, args: anytype) std.Thread.SpawnError!std.Thread {
            if (allowed == 0) return error.SystemResources;
            allowed -= 1;
            return std.Thread.spawn(config, function, args);
        }
    };
    const Tally = struct {
        worked: *[jobs]std.atomic.Value(u32),

        // Counted only after a delay, so a call that returned before joining
        // a thread it started would return with that thread's index uncounted.
        fn work(self: @This(), _: std.mem.Allocator, index: usize) void {
            var spins: u32 = 0;
            while (spins < 200_000) : (spins += 1) std.atomic.spinLoopHint();
            _ = self.worked[index].fetchAdd(1, .monotonic);
        }
    };

    for ([_]usize{ 0, 1, 3 }) |allowed| {
        var worked: [jobs]std.atomic.Value(u32) = @splat(.init(0));
        Declining.allowed = allowed;
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        try forEachSpawning(arena.allocator(), jobs, 4, Tally{ .worked = &worked }, Tally.work, Declining.spawn);
        for (&worked) |*times| try std.testing.expectEqual(@as(u32, 1), times.load(.monotonic));
    }
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
    if (output.len == 0) {
        return std.fmt.allocPrint(gpa, "`{s}` did not finish in {d} seconds; it wrote nothing before the deadline\n", .{ command, timeout_seconds });
    }
    return std.fmt.allocPrint(gpa, "`{s}` did not finish in {d} seconds; it had written:\n{s}\n", .{ command, timeout_seconds, output });
}
