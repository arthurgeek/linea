const std = @import("std");

pub const Options = struct {
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map = null,
    /// Bounds the whole run: reading both streams and waiting for the child
    /// to exit, which it may do long after it closed them. A duration counts
    /// from the start of the run.
    timeout: std.Io.Timeout = .none,
    stdout_limit: std.Io.Limit = .unlimited,
    stderr_limit: std.Io.Limit = .unlimited,
    cwd: std.process.Child.Cwd = .inherit,
    /// Start the child as the leader of its own process group, and kill that
    /// group when the run ends before the child does, so background jobs the
    /// child started die with it instead of holding its output pipes open.
    process_group: bool = false,
    /// On `error.Timeout`, receives the standard output and then the standard
    /// error read before the deadline, allocated from `gpa`.
    partial: ?*[]u8 = null,
};

/// Capture both output streams of a child whose standard input is empty.
/// Both pipes are drained together, so a child filling one while the runner
/// waits on the other cannot deadlock. Answers `error.Timeout` once
/// `options.timeout` passes, having killed the child, and its process group
/// where `options.process_group` asks for one.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    options: Options,
) std.process.RunError!std.process.RunResult {
    // Command cases require descriptors above stdio to be closed in the child.
    // Mark immediately before spawning, including lazy descriptors opened by
    // previous process launches.
    switch (@import("builtin").os.tag) {
        .linux => {
            var fd: i32 = 3;
            while (fd < 1024) : (fd += 1) {
                const got = std.os.linux.fcntl(fd, std.os.linux.F.GETFD, 0);
                if (std.os.linux.errno(got) != .SUCCESS) continue;
                _ = std.os.linux.fcntl(fd, std.os.linux.F.SETFD, got | std.posix.FD_CLOEXEC);
            }
        },
        .macos => {
            var fd: std.c.fd_t = 3;
            while (fd < 1024) : (fd += 1) {
                const flags = std.c.fcntl(fd, std.posix.F.GETFD);
                if (flags < 0) continue;
                _ = std.c.fcntl(fd, std.posix.F.SETFD, flags | @as(c_int, std.posix.FD_CLOEXEC));
            }
        },
        else => {},
    }
    var child = try std.process.spawn(io, .{
        .argv = options.argv,
        .cwd = options.cwd,
        .pgid = if (options.process_group) 0 else null,
        .environ_map = options.environ_map,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(io);
    defer if (options.process_group) if (child.id) |pid| std.posix.kill(-pid, .KILL) catch {};

    // One deadline for every read and the wait, so output arriving in time
    // does not extend the run.
    const deadline = options.timeout.toDeadline(io);
    var buffers: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(gpa, io, buffers.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (reader.fill(4096, deadline)) |_| {
        if (options.stdout_limit.toInt()) |limit| {
            if (reader.reader(0).buffered().len > limit) return error.StreamTooLong;
        }
        if (options.stderr_limit.toInt()) |limit| {
            if (reader.reader(1).buffered().len > limit) return error.StreamTooLong;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.Timeout => {
            if (options.partial) |out| out.* = try std.mem.concat(gpa, u8, &.{
                reader.reader(0).buffered(),
                reader.reader(1).buffered(),
            });
            return error.Timeout;
        },
        else => |e| return e,
    }
    try reader.checkAnyError();
    const term = try waitUntil(io, &child, deadline, options.process_group);
    const stdout = try reader.toOwnedSlice(0);
    errdefer gpa.free(stdout);
    const stderr = try reader.toOwnedSlice(1);
    return .{ .term = term, .stdout = stdout, .stderr = stderr };
}

/// Waits for `child` to exit, or kills it, and its process group where
/// `group` says it leads one, once `deadline` passes and answers
/// `error.Timeout`.
fn waitUntil(io: std.Io, child: *std.process.Child, deadline: std.Io.Timeout, group: bool) !std.process.Child.Term {
    if (deadline == .none) return child.wait(io);
    const Raced = union(enum) {
        exited: std.process.Child.WaitError!std.process.Child.Term,
        expired: std.Io.Cancelable!void,
    };
    var slots: [2]Raced = undefined;
    var race: std.Io.Select(Raced) = .init(io, &slots);
    // Cancelling the wait may leave it blocked until the child exits, so a
    // child still running is killed before the race is cancelled.
    defer race.cancelDiscard();
    const pid = child.id.?;
    try race.concurrent(.exited, std.process.Child.wait, .{ child, io });
    try race.concurrent(.expired, std.Io.Timeout.sleep, .{ deadline, io });
    switch (try race.await()) {
        .exited => |term| return term,
        .expired => |slept| {
            try slept;
            if (group) std.posix.kill(-pid, .KILL) catch {};
            std.posix.kill(pid, .KILL) catch {};
            return error.Timeout;
        },
    }
}

test "both output streams drain beyond pipe capacity" {
    const testing = std.testing;
    const io = testing.io;
    const size = 256 * 1024;
    const result = try run(testing.allocator, io, .{
        .argv = &.{ "/bin/sh", "-c", "head -c 262144 /dev/zero | tee /dev/stderr" },
        .timeout = .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } },
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(usize, size), result.stdout.len);
    try testing.expectEqual(@as(usize, size), result.stderr.len);
    try testing.expect(std.mem.allEqual(u8, result.stdout, 0));
    try testing.expect(std.mem.allEqual(u8, result.stderr, 0));
}

test "a child's standard input is empty" {
    const testing = std.testing;
    const result = try run(testing.allocator, testing.io, .{
        .argv = &.{"/bin/cat"},
        .timeout = .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } },
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stdout);
    try testing.expectEqualStrings("", result.stderr);
}

test "the timeout bounds a child that keeps writing" {
    const testing = std.testing;
    const io = testing.io;
    var partial: []u8 = &.{};
    defer testing.allocator.free(partial);
    const started = std.Io.Clock.awake.now(io);
    const result = run(testing.allocator, io, .{
        .argv = &.{ "/bin/sh", "-c", "i=0; while [ $i -lt 100 ]; do echo x; sleep 0.1; i=$((i+1)); done" },
        .timeout = .{ .duration = .{ .raw = .fromSeconds(1), .clock = .awake } },
        .partial = &partial,
    });
    if (result) |finished| {
        testing.allocator.free(finished.stdout);
        testing.allocator.free(finished.stderr);
        return error.TestExpectedError;
    } else |err| try testing.expectEqual(error.Timeout, err);
    // A deadline restarted by every line would let the child run to its end,
    // ten seconds and more after it started.
    try testing.expect(started.durationTo(std.Io.Clock.awake.now(io)).toSeconds() < 8);
    try testing.expect(std.mem.startsWith(u8, partial, "x\n"));
}

test "the timeout bounds a child that closes its streams and keeps running" {
    const testing = std.testing;
    const io = testing.io;
    const started = std.Io.Clock.awake.now(io);
    const result = run(testing.allocator, io, .{
        .argv = &.{ "/bin/sh", "-c", "exec >&- 2>&-; sleep 30" },
        .timeout = .{ .duration = .{ .raw = .fromSeconds(1), .clock = .awake } },
    });
    if (result) |finished| {
        testing.allocator.free(finished.stdout);
        testing.allocator.free(finished.stderr);
        return error.TestExpectedError;
    } else |err| try testing.expectEqual(error.Timeout, err);
    try testing.expect(started.durationTo(std.Io.Clock.awake.now(io)).toSeconds() < 20);
}
