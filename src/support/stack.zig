//! The stack the compiler's passes run on.
//!
//! The passes walk a tree recursively, and the parser bounds the tree's
//! height at `max_tree_height`. That bound only holds acceptance constant
//! across builds if every build can recurse that far: a Debug frame of the
//! checker is far larger than an optimised one, so a tree within the bound
//! overflowed the 8 MiB main stack. Passes therefore run on a thread whose
//! stack is sized for the bound in the largest frames, and the reservation is
//! address space the system commits only as the stack grows.

const std = @import("std");
const testing = std.testing;

/// Room for `max_tree_height` levels of the largest Debug frames the passes
/// use per level, about 20 KiB, with more than ten times to spare.
pub const compiler_stack_bytes: usize = 256 * 1024 * 1024;

/// The configuration of a thread that runs compiler passes.
pub const spawn_config: std.Thread.SpawnConfig = .{ .stack_size = compiler_stack_bytes };

fn ReturnOf(comptime function: anytype) type {
    return @typeInfo(@TypeOf(function)).@"fn".return_type.?;
}

/// Calls `function(args)` on a thread with `compiler_stack_bytes` of stack and
/// returns what it returns, or the error that kept the thread from starting.
/// The call never runs on the caller's stack: a tree within the parser's
/// height bound can need more than the caller has.
pub fn run(comptime function: anytype, args: anytype) std.Thread.SpawnError!ReturnOf(function) {
    return runOn(std.Thread.spawn, function, args);
}

/// `run`, starting the thread with `spawn`. What `run` does when the thread
/// cannot start is decided here, so a test that refuses the thread sees it.
fn runOn(comptime spawn: anytype, comptime function: anytype, args: anytype) std.Thread.SpawnError!ReturnOf(function) {
    return runThrough(spawn, compiler_stack_bytes, function, args);
}

/// Calls `function(args)` on a thread with `stack_bytes` of stack and returns
/// what it returns, or the error that kept the thread from starting.
pub fn runWithin(stack_bytes: usize, comptime function: anytype, args: anytype) std.Thread.SpawnError!ReturnOf(function) {
    return runThrough(std.Thread.spawn, stack_bytes, function, args);
}

/// `runWithin`, starting the thread with `spawn`.
fn runThrough(comptime spawn: anytype, stack_bytes: usize, comptime function: anytype, args: anytype) std.Thread.SpawnError!ReturnOf(function) {
    const Args = @TypeOf(args);
    const Job = struct {
        args: Args,
        result: ReturnOf(function) = undefined,

        fn go(job: *@This()) void {
            job.result = @call(.auto, function, job.args);
        }
    };
    var job: Job = .{ .args = args };
    const thread = try spawn(.{ .stack_size = stack_bytes }, Job.go, .{&job});
    thread.join();
    return job.result;
}

fn spawnRefused(_: std.Thread.SpawnConfig, comptime _: anytype, _: anytype) std.Thread.SpawnError!std.Thread {
    return error.SystemResources;
}

fn recordCall(called: *bool) void {
    called.* = true;
}

test "a call whose thread cannot start is not made, and answers with the error" {
    var called = false;
    try testing.expectError(error.SystemResources, runOn(spawnRefused, recordCall, .{&called}));
    try testing.expect(!called);
}

/// Recurses `levels` deep through frames of 64 KiB and answers how deep it got.
fn descend(levels: usize) usize {
    var frame: [64 * 1024]u8 = undefined;
    @memset(&frame, 1);
    std.mem.doNotOptimizeAway(&frame);
    if (levels == 0) return 0;
    return descend(levels - 1) + frame[levels % frame.len];
}

test "a call through run recurses far past the main thread's stack" {
    // 2000 frames of 64 KiB are 125 MiB, where the main stack holds 8 MiB.
    try testing.expectEqual(@as(usize, 2000), try run(descend, .{2000}));
}
