//! Checks validated SPIR-V disassembly used by the GPU hardware regressions.
const std = @import("std");

fn check(gpa: std.mem.Allocator, text: []const u8, wanted_barriers: usize) !void {
    var barriers: usize = 0;
    var integers: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeAny(u8, line, " \t\r");
        var opcode = words.next() orelse continue;
        if (opcode[0] == ';') continue;
        if (opcode[0] == '%') {
            if (!std.mem.eql(u8, words.next() orelse return error.MalformedDisassembly, "="))
                return error.MalformedDisassembly;
            opcode = words.next() orelse return error.MalformedDisassembly;
        }
        if (std.mem.eql(u8, opcode, "OpTypeFloat")) return error.FloatingPointType;
        if (std.mem.eql(u8, opcode, "OpTypeInt")) {
            const width = words.next() orelse return error.MalformedDisassembly;
            if (!std.mem.eql(u8, width, "32")) return error.IntegerWidth;
            integers += 1;
        }
        if (std.mem.eql(u8, opcode, "OpControlBarrier")) barriers += 1;
    }
    if (integers == 0) return error.MissingIntegerType;
    if (barriers != wanted_barriers) return error.BarrierCount;
    try checkReachability(gpa, text);
}

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 3) {
        std.debug.print("usage: gpu-spirv-check <disassembly> <barrier count>\n", .{});
        return 2;
    }
    const wanted = try std.fmt.parseInt(usize, args[2], 10);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], gpa, .limited(64 << 20));
    check(gpa, bytes, wanted) catch |err| {
        std.debug.print("{s}: GPU shader check failed: {s}\n", .{ args[1], @errorName(err) });
        return 1;
    };
    return 0;
}

test "integer-only shader checks type definitions and actual barrier instructions" {
    const valid =
        \\; OpTypeFloat in a comment is not an instruction
        \\%uint = OpTypeInt 32 0
        \\OpName %uint "OpTypeFloat"
        \\OpControlBarrier %workgroup %workgroup %memory
    ;
    try check(std.testing.allocator, valid, 1);
    try std.testing.expectError(error.BarrierCount, check(std.testing.allocator, valid, 7));
    try std.testing.expectError(error.FloatingPointType, check(std.testing.allocator, "%float = OpTypeFloat 32\n", 0));
    try std.testing.expectError(error.IntegerWidth, check(std.testing.allocator, "%wide = OpTypeInt 64 0\n", 0));
    try std.testing.expectError(error.MissingIntegerType, check(std.testing.allocator, "; empty\n", 0));
}

// SPIR-V functions are reached only through entry points and direct calls.
// Walk edges from those roots; a disconnected cycle is still unreachable.
fn checkReachability(gpa: std.mem.Allocator, text: []const u8) !void {
    const Function = struct { callees: std.ArrayList([]const u8) = .empty };
    var functions: std.StringHashMap(Function) = .init(gpa);
    defer {
        var values = functions.valueIterator();
        while (values.next()) |value| value.callees.deinit(gpa);
        functions.deinit();
    }
    var pending: std.ArrayList([]const u8) = .empty;
    defer pending.deinit(gpa);
    var current: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeAny(u8, line, " \t\r");
        const first = words.next() orelse continue;
        if (first[0] == ';') continue;
        var opcode = first;
        var result: ?[]const u8 = null;
        if (first[0] == '%') {
            result = first;
            if (!std.mem.eql(u8, words.next() orelse return error.MalformedDisassembly, "=")) return error.MalformedDisassembly;
            opcode = words.next() orelse return error.MalformedDisassembly;
        }
        if (std.mem.eql(u8, opcode, "OpEntryPoint")) {
            _ = words.next() orelse return error.MalformedDisassembly; // execution model
            try pending.append(gpa, words.next() orelse return error.MalformedDisassembly);
        } else if (std.mem.eql(u8, opcode, "OpFunction")) {
            if (current != null) return error.MalformedDisassembly;
            current = result orelse return error.MalformedDisassembly;
            const entry = try functions.getOrPut(current.?);
            if (entry.found_existing) return error.MalformedDisassembly;
            entry.value_ptr.* = .{};
        } else if (std.mem.eql(u8, opcode, "OpFunctionEnd")) {
            if (current == null) return error.MalformedDisassembly;
            current = null;
        } else if (std.mem.eql(u8, opcode, "OpFunctionCall")) {
            _ = words.next() orelse return error.MalformedDisassembly; // result type
            const callee = words.next() orelse return error.MalformedDisassembly;
            const caller = functions.getPtr(current orelse return error.MalformedDisassembly).?;
            try caller.callees.append(gpa, callee);
        }
    }
    if (current != null) return error.MalformedDisassembly;
    var reached: std.StringHashMap(void) = .init(gpa);
    defer reached.deinit();
    while (pending.pop()) |name| {
        const entry = try reached.getOrPut(name);
        if (entry.found_existing) continue;
        const function = functions.get(name) orelse return error.MissingFunction;
        try pending.appendSlice(gpa, function.callees.items);
    }
    if (functions.count() != reached.count()) return error.UnreachableFunction;
}

test "shader function reachability follows transitive calls from every entry point" {
    const gpa = std.testing.allocator;
    const roots =
        \\OpEntryPoint GLCompute %main "main"
        \\OpEntryPoint GLCompute %second "second"
        \\%leaf = OpFunction %void None %type
        \\OpFunctionEnd
        \\%helper = OpFunction %void None %type
        \\%r = OpFunctionCall %void %leaf
        \\OpFunctionEnd
        \\%main = OpFunction %void None %type
        \\%s = OpFunctionCall %void %helper
        \\%t = OpFunctionCall %void %helper
        \\OpFunctionEnd
        \\%second = OpFunction %void None %type
        \\OpFunctionEnd
    ;
    try checkReachability(gpa, roots);
    try std.testing.expectError(error.UnreachableFunction, checkReachability(gpa, roots ++ "\n%orphan = OpFunction %void None %type\nOpFunctionEnd\n"));
    try std.testing.expectError(error.UnreachableFunction, checkReachability(gpa, roots ++ "\n%cycle = OpFunction %void None %type\n%u = OpFunctionCall %void %cycle\nOpFunctionEnd\n"));
    try std.testing.expectError(error.MissingFunction, checkReachability(gpa, "OpEntryPoint GLCompute %absent \"absent\"\n"));
    try std.testing.expectError(error.MalformedDisassembly, checkReachability(gpa, "%r = OpFunctionCall %void %leaf\n"));
}
