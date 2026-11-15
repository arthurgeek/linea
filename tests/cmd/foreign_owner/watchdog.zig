const std = @import("std");
const testing = std.testing;

const Mode = enum { nonreturning, terminal };
const Limits = struct {
    startup: std.Io.Duration = .fromSeconds(60),
    grace: std.Io.Duration = .fromSeconds(1),
};

fn deadline(io: std.Io, duration: std.Io.Duration) std.Io.Clock.Timestamp {
    return .fromNow(io, .{ .raw = duration, .clock = .awake });
}

fn pollStatus(child: *std.process.Child, reaped: *bool) !?u32 {
    var status: c_int = 0;
    while (true) {
        const result = std.c.waitpid(child.id.?, &status, std.posix.W.NOHANG);
        if (result == 0) return null;
        if (result > 0) {
            reaped.* = true;
            return @bitCast(status);
        }
        switch (std.posix.errno(result)) {
            .INTR => continue,
            else => return error.WaitFailed,
        }
    }
}

fn waitForExit(child: *std.process.Child, io: std.Io, until: std.Io.Clock.Timestamp, reaped: *bool) !u32 {
    while (true) {
        if (try pollStatus(child, reaped)) |status| return status;
        if (until.durationFromNow(io).raw.toNanoseconds() <= 0) return error.Timeout;
        try io.sleep(.fromMilliseconds(10), .awake);
    }
}

fn cleanup(child: *std.process.Child, io: std.Io, pid: std.posix.pid_t, reaped: bool) void {
    std.posix.kill(-pid, .KILL) catch {};
    if (!reaped) {
        child.kill(io);
        return;
    }
    // A nonblocking wait already reaped the child. Do not pass a stale PID
    // to Child.kill or wait for it twice; close only the remaining pipes.
    if (child.stdout) |file| file.close(io);
    if (child.stderr) |file| file.close(io);
    if (child.stdin) |file| file.close(io);
    child.stdout = null;
    child.stderr = null;
    child.stdin = null;
    child.id = null;
}

fn boundedFill(reader: *std.Io.File.MultiReader, until: std.Io.Clock.Timestamp) !void {
    try reader.fill(4096, .{ .deadline = until });
    if (reader.reader(0).buffered().len + reader.reader(1).buffered().len > 65536) return error.OutputLimit;
}

fn drain(reader: *std.Io.File.MultiReader, until: std.Io.Clock.Timestamp) !void {
    while (boundedFill(reader, until)) |_| {} else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
    try reader.checkAnyError();
}

fn hasJoinMarker(reader: *std.Io.File.MultiReader) bool {
    return std.mem.indexOf(u8, reader.reader(0).buffered(), "JOIN_ATTEMPT") != null or
        std.mem.indexOf(u8, reader.reader(1).buffered(), "JOIN_ATTEMPT") != null;
}

fn exactLines(output: []const u8, expected: []const []const u8) bool {
    var lines = std.mem.splitScalar(u8, output, '\n');
    for (expected) |want| {
        var got = lines.next() orelse return false;
        if (std.mem.endsWith(u8, got, "\r")) got = got[0 .. got.len - 1];
        if (!std.mem.eql(u8, got, want)) return false;
    }
    if (lines.next()) |tail| return tail.len == 0 and lines.next() == null;
    return true;
}

fn terminalOutput(output: []const u8) bool {
    var line = output;
    if (std.mem.endsWith(u8, line, "\r\n")) line = line[0 .. line.len - 2] else if (std.mem.endsWith(u8, line, "\n") or std.mem.endsWith(u8, line, "\r")) line = line[0 .. line.len - 1];
    return std.mem.indexOfAny(u8, line, "\r\n") == null and
        std.mem.startsWith(u8, line, "linea: panic: EXPLICIT_TERMINAL_POLICY_NO_NORMAL_SETTLEMENT at ");
}

fn observe(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8, mode: Mode, limits: Limits) !void {
    try std.posix.setrlimit(.CORE, .{ .cur = 0, .max = 0 });
    var child = try std.process.spawn(io, .{ .argv = argv, .pgid = 0, .stdin = .ignore, .stdout = .pipe, .stderr = .pipe });
    const pid = child.id.?;
    var reaped = false;
    defer cleanup(&child, io, pid, reaped);
    var buffers: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(gpa, io, buffers.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    const startup = deadline(io, limits.startup);
    if (mode == .terminal) {
        try drain(&reader, startup);
        const status = try waitForExit(&child, io, startup, &reaped);
        if (!std.posix.W.IFSIGNALED(status) or std.posix.W.TERMSIG(status) != .ABRT) return error.ExpectedAbort;
    } else {
        while (!hasJoinMarker(&reader)) {
            boundedFill(&reader, startup) catch |err| switch (err) {
                error.EndOfStream => return error.JoinEscaped,
                else => return err,
            };
        }
        if (try pollStatus(&child, &reaped) != null) return error.JoinEscaped;
        const grace = deadline(io, limits.grace);
        while (boundedFill(&reader, grace)) |_| {} else |err| switch (err) {
            error.Timeout => {},
            error.EndOfStream => return error.JoinEscaped,
            else => return err,
        }
        // A descendant can keep a pipe open after the parent exits. A read
        // timeout alone therefore does not establish that the join blocked.
        if (try pollStatus(&child, &reaped) != null) return error.JoinEscaped;
        try std.posix.kill(-pid, .KILL);
        const stopped = deadline(io, .fromSeconds(10));
        const status = try waitForExit(&child, io, stopped, &reaped);
        if (!std.posix.W.IFSIGNALED(status) or std.posix.W.TERMSIG(status) != .KILL) return error.JoinEscaped;
        try drain(&reader, stopped);
    }
    const output = try std.mem.concat(gpa, u8, &.{ reader.reader(0).buffered(), reader.reader(1).buffered() });
    defer gpa.free(output);
    const correct = switch (mode) {
        .terminal => terminalOutput(output),
        .nonreturning => exactLines(output, &.{ "UNRELATED_FIBER_PROGRESS", "JOIN_ATTEMPT" }),
    };
    if (!correct) return error.UnexpectedOutput;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 3) return error.ExpectedExecutableAndMode;
    const mode = std.meta.stringToEnum(Mode, args[2]) orelse return error.UnknownMode;
    try observe(gpa, init.io, &.{args[1]}, mode, .{});
    var buffer: [256]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(switch (mode) {
        .terminal => "terminal policy observed; no normal settlement claimed\n",
        .nonreturning => "unrelated fiber progressed; native call and join remain blocked\n",
    });
    try output.interface.flush();
}

const short_limits: Limits = .{ .startup = .fromSeconds(5), .grace = .fromMilliseconds(20) };

test "an escaped join is refused even after printing both progress markers" {
    try testing.expectError(error.JoinEscaped, observe(testing.allocator, testing.io, &.{
        "/bin/sh", "-c", "printf 'UNRELATED_FIBER_PROGRESS\\nJOIN_ATTEMPT\\nFORBIDDEN_JOIN_RETURNED\\n'",
    }, .nonreturning, short_limits));
}

test "an abort cannot conceal an additional diagnostic" {
    try testing.expectError(error.UnexpectedOutput, observe(testing.allocator, testing.io, &.{
        "/bin/sh", "-c", "printf 'linea: panic: EXPLICIT_TERMINAL_POLICY_NO_NORMAL_SETTLEMENT at fixture:1:1\\n'; printf 'unexpected storage failure\\n' >&2; kill -ABRT $$",
    }, .terminal, short_limits));
}

test "a normal exit cannot masquerade as terminal settlement" {
    try testing.expectError(error.ExpectedAbort, observe(testing.allocator, testing.io, &.{
        "/bin/sh", "-c", "printf 'linea: panic: EXPLICIT_TERMINAL_POLICY_NO_NORMAL_SETTLEMENT at fixture:1:1\\n'",
    }, .terminal, short_limits));
}

test "a blocked process without unrelated progress is refused" {
    try testing.expectError(error.UnexpectedOutput, observe(testing.allocator, testing.io, &.{
        "/bin/sh", "-c", "printf 'JOIN_ATTEMPT\\n'; exec sleep 60",
    }, .nonreturning, short_limits));
}

test "the startup deadline bounds a process that never reaches join" {
    try testing.expectError(error.Timeout, observe(testing.allocator, testing.io, &.{
        "/bin/sh", "-c", "exec sleep 60",
    }, .nonreturning, .{ .startup = .fromMilliseconds(50) }));
}

test "closed output streams do not bypass the terminal deadline" {
    try testing.expectError(error.Timeout, observe(testing.allocator, testing.io, &.{
        "/bin/sh", "-c", "exec >/dev/null 2>&1; exec sleep 60",
    }, .terminal, .{ .startup = .fromMilliseconds(50) }));
}
