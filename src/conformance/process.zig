const std = @import("std");

pub const Options = struct {
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map = null,
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
/// waits on the other cannot deadlock.
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

    var buffers: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(gpa, io, buffers.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (reader.fill(4096, options.timeout)) |_| {
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
    const term = try child.wait(io);
    const stdout = try reader.toOwnedSlice(0);
    errdefer gpa.free(stdout);
    const stderr = try reader.toOwnedSlice(1);
    return .{ .term = term, .stdout = stdout, .stderr = stderr };
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
