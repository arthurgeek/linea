const std = @import("std");
const testing = std.testing;
const runtime_symbols = @import("runtime_symbols");

const Kind = enum { affinity_guard, guarded_native, runtime_guarded, linea_direct, linea_address, system_entry, llvm_intrinsic };
const Row = struct { function: []const u8, line: usize, kind: Kind, target: []const u8 };
const Lookup = *const fn ([]const u8) runtime_symbols.MigrationContract;

fn nativeContract(name: []const u8) runtime_symbols.MigrationContract {
    return if (runtime_symbols.signatureOf(name)) |signature| signature.migration_contract else .unknown;
}

fn symbol(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trimStart(u8, text, " \t\r");
    if (trimmed.len < 2 or trimmed[0] != '@') return null;
    const tail = trimmed[1..];
    if (tail[0] == '"') {
        const end = std.mem.indexOfScalarPos(u8, tail, 1, '"') orelse return null;
        return tail[1..end];
    }
    const end = std.mem.indexOfAny(u8, tail, " (\t\r") orelse tail.len;
    return tail[0..end];
}

fn after(text: []const u8, needle: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, text, needle)) return null;
    return symbol(text[needle.len..]);
}

fn functionName(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, "func.func ")) return null;
    var tail = std.mem.trimStart(u8, line["func.func ".len..], " \t");
    if (std.mem.startsWith(u8, tail, "private ")) tail = tail["private ".len..];
    return symbol(tail);
}

fn isEntryGuard(name: []const u8) bool {
    return std.mem.eql(u8, name, "linea_fiber_restrict_current") or std.mem.eql(u8, name, "linea_foreign_enter");
}

/// Inspect the emitted module independently of the MIR emitter. The bounded
/// fixture has no indirect call sites; introducing one requires target coverage.
fn inspectCalls(gpa: std.mem.Allocator, text: []const u8, lookup: Lookup) ![]Row {
    var definitions: std.StringHashMapUnmanaged(void) = .empty;
    defer definitions.deinit(gpa);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (functionName(line)) |name| {
            if (std.mem.endsWith(u8, line, "{")) try definitions.put(gpa, name, {});
        }
    }
    if (definitions.count() == 0) return error.NoFunctionBodies;
    var rows: std.ArrayList(Row) = .empty;
    errdefer rows.deinit(gpa);
    var current: ?[]const u8 = null;
    var indentation: usize = 0;
    var previous_guard = false;
    var number: usize = 0;
    lines.reset();
    while (lines.next()) |raw| {
        number += 1;
        const left = std.mem.trimStart(u8, raw, " \t");
        const line = std.mem.trimEnd(u8, left, " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "//")) continue;
        if (functionName(line)) |name| {
            current = if (std.mem.endsWith(u8, line, "{")) name else null;
            indentation = raw.len - left.len;
            previous_guard = false;
            continue;
        }
        if (std.mem.eql(u8, line, "}") and raw.len - left.len == indentation) {
            current = null;
            previous_guard = false;
            continue;
        }
        var operation = line;
        if (std.mem.startsWith(u8, operation, "%")) {
            const assignment = std.mem.indexOfScalar(u8, operation, '=') orelse return error.UnclassifiedCall;
            operation = std.mem.trimStart(u8, operation[assignment + 1 ..], " \t");
        }
        if (after(operation, "func.constant ")) |target| {
            if (current == null or !definitions.contains(target)) return error.ExternalCallableAddress;
            try rows.append(gpa, .{ .function = current.?, .line = number, .kind = .linea_address, .target = target });
            previous_guard = false;
            continue;
        }
        if (after(operation, "func.call ")) |target| {
            const function = current orelse return error.CallOutsideBody;
            const kind: Kind = classify: {
                if (definitions.contains(target)) break :classify .linea_direct;
                if (isEntryGuard(target) or std.mem.eql(u8, target, "linea_foreign_leave")) break :classify .affinity_guard;
                if (std.mem.eql(u8, target, "linea_set_args") and std.mem.eql(u8, function, "main")) break :classify .system_entry;
                if (std.mem.eql(u8, target, "llvm.assume") or std.mem.eql(u8, target, "llvm.is.constant.i1")) break :classify .llvm_intrinsic;
                if (lookup(target) == .runtime_guarded) break :classify .runtime_guarded;
                if (previous_guard) break :classify .guarded_native;
                return error.NativeCallWithoutGuard;
            };
            try rows.append(gpa, .{ .function = function, .line = number, .kind = kind, .target = target });
            previous_guard = isEntryGuard(target);
            continue;
        }
        if (std.mem.startsWith(u8, operation, "func.call") or std.mem.startsWith(u8, operation, "func.constant")) return error.UnclassifiedCall;
        if (std.mem.startsWith(u8, operation, "llvm.call")) return error.IndirectCall;
        if (std.mem.startsWith(u8, operation, "llvm.intr.") or std.mem.startsWith(u8, operation, "\"llvm.intr.")) {
            try rows.append(gpa, .{ .function = current orelse return error.CallOutsideBody, .line = number, .kind = .llvm_intrinsic, .target = line });
        }
        previous_guard = false;
    }
    return rows.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 2) return error.ExpectedEmittedModulePath;
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], gpa, .limited(32 << 20));
    const rows = try inspectCalls(gpa, text, nativeContract);
    var has_clock = false;
    for (rows) |row| {
        if (row.kind == .runtime_guarded and std.mem.eql(u8, row.target, "linea_clock_sleep")) has_clock = true;
    }
    if (!has_clock) return error.MissingAuditedClockInvocation;
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &output.interface;
    try writer.writeAll("function\tline\tkind\ttarget\n");
    for (rows) |row| try writer.print("{s}\t{d}\t{s}\t{s}\n", .{ row.function, row.line, @tagName(row.kind), row.target });
    try writer.flush();
}

fn fixture(gpa: std.mem.Allocator, body: []const u8) ![]const u8 {
    return std.fmt.allocPrint(gpa, "module {{\n func.func private @lin.body() {{\n{s}\n }}\n}}\n", .{body});
}

fn unknownContract(_: []const u8) runtime_symbols.MigrationContract {
    return .unknown;
}

test "guarded unknown native calls are recorded" {
    const text = try fixture(testing.allocator, "func.call @linea_fiber_restrict_current()\nfunc.call @unclassified_native()");
    defer testing.allocator.free(text);
    const rows = try inspectCalls(testing.allocator, text, unknownContract);
    defer testing.allocator.free(rows);
    try testing.expectEqual(@as(usize, 2), rows.len);
    try testing.expectEqual(Kind.affinity_guard, rows[0].kind);
    try testing.expectEqual(Kind.guarded_native, rows[1].kind);
}

test "omitting a native guard is refused" {
    const text = try fixture(testing.allocator, "func.call @unclassified_native()");
    defer testing.allocator.free(text);
    try testing.expectError(error.NativeCallWithoutGuard, inspectCalls(testing.allocator, text, unknownContract));
}

test "a guard does not cross a basic block" {
    const text = try fixture(testing.allocator, "func.call @linea_fiber_restrict_current()\n^bb1:\nfunc.call @unclassified_native()");
    defer testing.allocator.free(text);
    try testing.expectError(error.NativeCallWithoutGuard, inspectCalls(testing.allocator, text, unknownContract));
}

test "an external callable address is refused" {
    const text = try fixture(testing.allocator, "%f = func.constant @unclassified_native : () -> ()");
    defer testing.allocator.free(text);
    try testing.expectError(error.ExternalCallableAddress, inspectCalls(testing.allocator, text, unknownContract));
}

test "runtime-checked paths require the canonical registry contract" {
    const text = try fixture(testing.allocator, "func.call @linea_clock_sleep(%duration)");
    defer testing.allocator.free(text);
    try testing.expectError(error.NativeCallWithoutGuard, inspectCalls(testing.allocator, text, unknownContract));
    const rows = try inspectCalls(testing.allocator, text, nativeContract);
    defer testing.allocator.free(rows);
    try testing.expectEqual(Kind.runtime_guarded, rows[0].kind);
}

test "indirect calls require separate target coverage" {
    const text = try fixture(testing.allocator, "%r = llvm.call %callee() : !llvm.ptr, () -> i64");
    defer testing.allocator.free(text);
    try testing.expectError(error.IndirectCall, inspectCalls(testing.allocator, text, unknownContract));
}

test "unexpected direct LLVM calls are refused" {
    const text = try fixture(testing.allocator, "llvm.call @unclassified_native()");
    defer testing.allocator.free(text);
    try testing.expectError(error.IndirectCall, inspectCalls(testing.allocator, text, unknownContract));
}

test "a module without emitted bodies is refused" {
    try testing.expectError(error.NoFunctionBodies, inspectCalls(testing.allocator, "module {}", unknownContract));
}

test "quoted internal function and callback addresses are recorded" {
    const text =
        \\module {
        \\  func.func private @"lin.body;UInt64"() {
        \\    %f = func.constant @"lin.body;UInt64" : () -> ()
        \\    func.call @"lin.body;UInt64"()
        \\  }
        \\}
    ;
    const rows = try inspectCalls(testing.allocator, text, unknownContract);
    defer testing.allocator.free(rows);
    try testing.expectEqual(@as(usize, 2), rows.len);
    try testing.expectEqual(Kind.linea_address, rows[0].kind);
    try testing.expectEqual(Kind.linea_direct, rows[1].kind);
    try testing.expectEqualStrings("lin.body;UInt64", rows[0].target);
}

test "a guard cannot authorize calls in the next function" {
    const text =
        \\module {
        \\  func.func private @lin.first() {
        \\    func.call @linea_fiber_restrict_current()
        \\  }
        \\  func.func private @lin.second() {
        \\    func.call @unclassified_native()
        \\  }
        \\}
    ;
    try testing.expectError(error.NativeCallWithoutGuard, inspectCalls(testing.allocator, text, unknownContract));
}

test "native calls outside a function are refused" {
    const text = "module {\n func.func @main() {\n }\n func.call @unclassified_native()\n}";
    try testing.expectError(error.CallOutsideBody, inspectCalls(testing.allocator, text, unknownContract));
}

test "unrecognized call and callable-address forms are refused" {
    for ([_][]const u8{ "func.call_indirect %callee()", "func.call invalid()", "%f = func.constant %callee" }) |body| {
        const text = try fixture(testing.allocator, body);
        defer testing.allocator.free(text);
        try testing.expectError(error.UnclassifiedCall, inspectCalls(testing.allocator, text, unknownContract));
    }
}

test "call text in a source location is not an operation" {
    const text = try fixture(testing.allocator, "%v = arith.constant 1 : i64 loc(\"func.call @unclassified_native()\":1:1)");
    defer testing.allocator.free(text);
    const rows = try inspectCalls(testing.allocator, text, unknownContract);
    defer testing.allocator.free(rows);
    try testing.expectEqual(@as(usize, 0), rows.len);
}
