const std = @import("std");
const testing = std.testing;
const runtime_symbols = @import("runtime_symbols");

const Kind = enum { affinity_guard, guarded_native, neutral_native, runtime_guarded, linea_direct, linea_indirect, linea_address, system_entry, llvm_intrinsic };
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

fn replaceableBody(line: []const u8) bool {
    const attribute = std.mem.indexOf(u8, line, "llvm.linkage") orelse return false;
    const start = std.mem.indexOfScalarPos(u8, line, attribute, '<') orelse return true;
    const end = std.mem.indexOfScalarPos(u8, line, start + 1, '>') orelse return true;
    const linkage = std.mem.trim(u8, line[start + 1 .. end], " \t");
    return !std.mem.eql(u8, linkage, "internal") and !std.mem.eql(u8, linkage, "private");
}

fn isEntryGuard(name: []const u8) bool {
    return std.mem.eql(u8, name, "linea_fiber_restrict_current") or std.mem.eql(u8, name, "linea_foreign_enter");
}

const Callable = struct { target: []const u8, abi: []const u8, pointer: bool = false };

fn withoutLocation(text: []const u8) []const u8 {
    const end = std.mem.indexOf(u8, text, " loc(") orelse text.len;
    return std.mem.trim(u8, text[0..end], " \t\r");
}

const Evidence = struct { target: []const u8, abi: []const u8, seen: bool = false };
const Proof = struct {
    body: []const u8,
    present: bool = false,
    origins: std.ArrayList(Evidence) = .empty,
    sites: std.ArrayList(Evidence) = .empty,

    fn deinit(self: *Proof, gpa: std.mem.Allocator) void {
        self.origins.deinit(gpa);
        self.sites.deinit(gpa);
    }
};

// This is a compiler-owned debug artifact from a successful full source build,
// not authorization to trust arbitrary IR or to activate runtime migration.
fn readProof(gpa: std.mem.Allocator, text: []const u8) !Proof {
    const marker = "// linea-callable-proof-v1 ";
    const at = if (std.mem.startsWith(u8, text, marker)) @as(usize, 0) else (std.mem.indexOf(u8, text, "\n" ++ marker) orelse return .{ .body = text }) + 1;
    const end = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse return error.CallableProofMismatch;
    var proof: Proof = .{ .body = text[0..at], .present = true };
    errdefer proof.deinit(gpa);
    const metadata = text[end + 1 ..];
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(proof.body);
    hash.update(metadata);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    if (!std.mem.eql(u8, text[at + marker.len .. end], &std.fmt.bytesToHex(digest, .lower)))
        return error.CallableProofMismatch;
    var lines = std.mem.splitScalar(u8, metadata, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const kind = fields.next() orelse return error.CallableProofMismatch;
        const target = symbol(fields.next() orelse return error.CallableProofMismatch) orelse return error.CallableProofMismatch;
        const abi = fields.next() orelse return error.CallableProofMismatch;
        if (fields.next() != null or abi.len == 0) return error.CallableProofMismatch;
        const entries = if (std.mem.eql(u8, kind, "// callable-origin")) &proof.origins else if (std.mem.eql(u8, kind, "// callable-site")) &proof.sites else return error.CallableProofMismatch;
        try entries.append(gpa, .{ .target = target, .abi = abi });
    }
    return proof;
}

/// Inspect the emitted module independently of the MIR emitter. The bounded
/// Only an exact local SSA function constant currently proves an indirect
/// target. Loaded or erased callables still require separate memory provenance.
fn inspectCalls(gpa: std.mem.Allocator, text: []const u8, lookup: Lookup) ![]Row {
    var proof = try readProof(gpa, text);
    defer proof.deinit(gpa);
    var definitions: std.StringHashMapUnmanaged(bool) = .empty;
    defer definitions.deinit(gpa);
    var lines = std.mem.splitScalar(u8, proof.body, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (functionName(line)) |name| {
            if (std.mem.endsWith(u8, line, "{")) try definitions.put(gpa, name, replaceableBody(line));
        }
    }
    if (definitions.count() == 0) return error.NoFunctionBodies;
    for (proof.origins.items) |origin| if (definitions.get(origin.target) orelse true) return error.ExternalCallableAddress;
    var rows: std.ArrayList(Row) = .empty;
    errdefer rows.deinit(gpa);
    var current: ?[]const u8 = null;
    var indentation: usize = 0;
    var previous_guard = false;
    var callables: std.StringHashMapUnmanaged(Callable) = .empty;
    defer callables.deinit(gpa);
    var number: usize = 0;
    var indirect_index: usize = 0;
    lines.reset();
    while (lines.next()) |raw| {
        number += 1;
        const left = std.mem.trimStart(u8, raw, " \t");
        const line = std.mem.trimEnd(u8, left, " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "//")) continue;
        if (functionName(line)) |name| {
            callables.clearRetainingCapacity();
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
        var result_name: ?[]const u8 = null;
        if (std.mem.startsWith(u8, operation, "%")) {
            const assignment = std.mem.indexOfScalar(u8, operation, '=') orelse return error.UnclassifiedCall;
            result_name = std.mem.trimEnd(u8, operation[0..assignment], " \t");
            // Never retain a stale classification for a different definition.
            _ = callables.remove(result_name.?);
            operation = std.mem.trimStart(u8, operation[assignment + 1 ..], " \t");
        }
        if (std.mem.startsWith(u8, operation, "\"func.call\"") or
            std.mem.startsWith(u8, operation, "\"llvm.call\"") or
            std.mem.startsWith(u8, operation, "\"func.constant\"")) return error.UnclassifiedCall;
        if (after(operation, "func.constant ")) |target| {
            if (current == null or (definitions.get(target) orelse true)) return error.ExternalCallableAddress;
            const abi_start = std.mem.indexOf(u8, operation, " : ") orelse return error.UnclassifiedCall;
            try callables.put(gpa, result_name orelse return error.UnclassifiedCall, .{
                .target = target,
                .abi = withoutLocation(operation[abi_start + 3 ..]),
            });
            for (proof.origins.items) |*origin| {
                if (std.mem.eql(u8, origin.target, target) and std.mem.eql(u8, origin.abi, withoutLocation(operation[abi_start + 3 ..])))
                    origin.seen = true;
            }
            try rows.append(gpa, .{ .function = current.?, .line = number, .kind = .linea_address, .target = target });
            previous_guard = false;
            continue;
        }
        if (std.mem.startsWith(u8, operation, "builtin.unrealized_conversion_cast ")) {
            const tail = withoutLocation(operation["builtin.unrealized_conversion_cast ".len..]);
            const abi_start = std.mem.indexOf(u8, tail, " : ");
            if (abi_start) |start| {
                if (callables.get(tail[0..start])) |reference| {
                    const suffix = " to !llvm.ptr";
                    const conversion = tail[start + 3 ..];
                    if (!reference.pointer and std.mem.endsWith(u8, conversion, suffix) and
                        std.mem.eql(u8, reference.abi, conversion[0 .. conversion.len - suffix.len]))
                    {
                        try callables.put(gpa, result_name orelse return error.UnclassifiedCall, .{
                            .target = reference.target,
                            .abi = reference.abi,
                            .pointer = true,
                        });
                    }
                }
            }
            previous_guard = false;
            continue;
        }
        if (after(operation, "func.call ")) |target| {
            const function = current orelse return error.CallOutsideBody;
            const kind: Kind = classify: {
                if (definitions.get(target)) |replaceable| if (!replaceable) break :classify .linea_direct;
                if (isEntryGuard(target) or std.mem.eql(u8, target, "linea_foreign_leave")) break :classify .affinity_guard;
                if (std.mem.eql(u8, target, "linea_set_args") and std.mem.eql(u8, function, "main")) break :classify .system_entry;
                if (std.mem.eql(u8, target, "llvm.assume") or std.mem.eql(u8, target, "llvm.is.constant.i1")) break :classify .llvm_intrinsic;
                if (lookup(target) == .neutral) break :classify .neutral_native;
                if (lookup(target) == .runtime_guarded) break :classify .runtime_guarded;
                if (previous_guard) break :classify .guarded_native;
                return error.NativeCallWithoutGuard;
            };
            try rows.append(gpa, .{ .function = function, .line = number, .kind = kind, .target = target });
            previous_guard = isEntryGuard(target);
            continue;
        }
        if (std.mem.startsWith(u8, operation, "func.call") or std.mem.startsWith(u8, operation, "func.constant")) return error.UnclassifiedCall;
        if (std.mem.startsWith(u8, operation, "llvm.call")) {
            const function = current orelse return error.CallOutsideBody;
            if (!std.mem.startsWith(u8, operation, "llvm.call %")) return error.IndirectCall;
            const tail = operation["llvm.call ".len..];
            const open = std.mem.indexOfScalar(u8, tail, '(') orelse return error.IndirectCall;
            const abi_start = std.mem.indexOf(u8, tail, " : !llvm.ptr, ") orelse return error.IndirectCall;
            const abi = withoutLocation(tail[abi_start + " : !llvm.ptr, ".len ..]);
            if (proof.present) {
                const matched = for (proof.sites.items) |*site| {
                    if (!site.seen and std.mem.eql(u8, site.target, function) and std.mem.eql(u8, site.abi, abi)) {
                        site.seen = true;
                        break true;
                    }
                } else false;
                if (!matched) return error.CallableSiteMismatch;
                indirect_index += 1;
            }
            if (callables.get(tail[0..open])) |callable| {
                if (!callable.pointer) return error.IndirectCall;
                if (!std.mem.eql(u8, callable.abi, abi)) return error.CallableAbiMismatch;
                try rows.append(gpa, .{ .function = function, .line = number, .kind = .linea_indirect, .target = callable.target });
            } else {
                if (!proof.present) return error.IndirectCall;
                var candidates: usize = 0;
                for (proof.origins.items) |origin| {
                    if (!std.mem.eql(u8, origin.abi, abi)) continue;
                    try rows.append(gpa, .{ .function = function, .line = number, .kind = .linea_indirect, .target = origin.target });
                    candidates += 1;
                }
                if (candidates == 0) return error.IndirectCall;
            }
            previous_guard = false;
            continue;
        }
        if (std.mem.startsWith(u8, operation, "llvm.intr.") or std.mem.startsWith(u8, operation, "\"llvm.intr.")) {
            try rows.append(gpa, .{ .function = current orelse return error.CallOutsideBody, .line = number, .kind = .llvm_intrinsic, .target = line });
        }
        previous_guard = false;
    }
    if (indirect_index != proof.sites.items.len) return error.CallableSiteMismatch;
    for (proof.origins.items) |origin| if (!origin.seen) return error.CallableOriginMismatch;
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

fn proofFixture(gpa: std.mem.Allocator, body: []const u8, evidence: []const u8) ![]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(body);
    hash.update(evidence);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(gpa, "{s}// linea-callable-proof-v1 {s}\n{s}", .{ body, std.fmt.bytesToHex(digest, .lower), evidence });
}

test "source-verified callable origins cover a typed erased dispatch" {
    const body = try fixture(testing.allocator, "%f = func.constant @lin.body : () -> ()\n" ++
        "%loaded = llvm.load %storage : !llvm.ptr -> !llvm.ptr\n" ++
        "llvm.call %loaded() : !llvm.ptr, () -> ()");
    defer testing.allocator.free(body);
    const text = try proofFixture(testing.allocator, body, "// callable-origin\t@lin.body\t() -> ()\n" ++
        "// callable-site\t@lin.body\t() -> ()\n");
    defer testing.allocator.free(text);
    const rows = try inspectCalls(testing.allocator, text, unknownContract);
    defer testing.allocator.free(rows);
    try testing.expectEqualStrings("linea_indirect", @tagName(rows[1].kind));
    try testing.expectEqualStrings("lin.body", rows[1].target);
}

test "changing emitted bytes invalidates callable evidence" {
    const text = try proofFixture(testing.allocator, "module {}\n", "");
    defer testing.allocator.free(text);
    text[0] = 'M';
    try testing.expectError(error.CallableProofMismatch, inspectCalls(testing.allocator, text, unknownContract));
}

test "callable evidence requires complete sites and matching emitted origins" {
    const body = try fixture(testing.allocator, "%f = func.constant @lin.body : () -> ()\n" ++
        "%loaded = llvm.load %storage : !llvm.ptr -> !llvm.ptr\n" ++
        "llvm.call %loaded() : !llvm.ptr, () -> ()");
    defer testing.allocator.free(body);
    const Case = struct { evidence: []const u8, expected: anyerror };
    for ([_]Case{
        .{ .evidence = "// callable-origin\t@lin.body\t() -> ()\n", .expected = error.CallableSiteMismatch },
        .{ .evidence = "// callable-origin\t@lin.body\t() -> ()\n// callable-site\t@lin.body\t() -> i64\n", .expected = error.CallableSiteMismatch },
        .{ .evidence = "// callable-site\t@lin.body\t() -> ()\n", .expected = error.IndirectCall },
        .{ .evidence = "// callable-origin\t@outside\t() -> ()\n// callable-site\t@lin.body\t() -> ()\n", .expected = error.ExternalCallableAddress },
        .{ .evidence = "// callable-origin\t@lin.body\t() -> ()\n// callable-origin\t@lin.body\t() -> i64\n// callable-site\t@lin.body\t() -> ()\n", .expected = error.CallableOriginMismatch },
        .{ .evidence = "// callable-origin\t@lin.body\t() -> ()\n// callable-site\t@lin.body\t() -> ()\n// callable-site\t@lin.body\t() -> ()\n", .expected = error.CallableSiteMismatch },
    }) |case| {
        const text = try proofFixture(testing.allocator, body, case.evidence);
        defer testing.allocator.free(text);
        try testing.expectError(case.expected, inspectCalls(testing.allocator, text, unknownContract));
    }
}

test "callable evidence cannot hide an unguarded native call in a candidate body" {
    const body = try fixture(testing.allocator, "%f = func.constant @lin.body : () -> ()\n" ++
        "func.call @unclassified_native()\n" ++
        "%loaded = llvm.load %storage : !llvm.ptr -> !llvm.ptr\n" ++
        "llvm.call %loaded() : !llvm.ptr, () -> ()");
    defer testing.allocator.free(body);
    const text = try proofFixture(testing.allocator, body, "// callable-origin\t@lin.body\t() -> ()\n// callable-site\t@lin.body\t() -> ()\n");
    defer testing.allocator.free(text);
    try testing.expectError(error.NativeCallWithoutGuard, inspectCalls(testing.allocator, text, unknownContract));
}

test "changing callable evidence invalidates its byte binding" {
    const text = try proofFixture(testing.allocator, "module {}\n", "// callable-origin\t@local\t() -> ()\n");
    defer testing.allocator.free(text);
    text[text.len - 2] = 'x';
    try testing.expectError(error.CallableProofMismatch, inspectCalls(testing.allocator, text, unknownContract));
}

test "generic quoted call and address syntax fails closed" {
    for ([_][]const u8{
        "\"func.call\"() <{callee = @unknown}> : () -> ()",
        "\"llvm.call\"() <{callee = @unknown}> : () -> ()",
        "%f = \"func.constant\"() <{value = @unknown}> : () -> i64",
    }) |operation| {
        const text = try fixture(testing.allocator, operation);
        defer testing.allocator.free(text);
        try testing.expectError(error.UnclassifiedCall, inspectCalls(testing.allocator, text, unknownContract));
    }
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

test "a local SSA callable carries its exact target and ABI" {
    const text = try fixture(testing.allocator, "%f = func.constant @lin.body : () -> ()\n" ++
        "%p = builtin.unrealized_conversion_cast %f : () -> () to !llvm.ptr\n" ++
        "llvm.call %p() : !llvm.ptr, () -> ()");
    defer testing.allocator.free(text);
    const rows = try inspectCalls(testing.allocator, text, unknownContract);
    defer testing.allocator.free(rows);
    try testing.expectEqual(@as(usize, 2), rows.len);
    try testing.expectEqualStrings("linea_indirect", @tagName(rows[1].kind));
    try testing.expectEqualStrings("lin.body", rows[1].target);
}

test "a callable ABI mismatch is refused even with a known local target" {
    const text = try fixture(testing.allocator, "%f = func.constant @lin.body : () -> ()\n" ++
        "%p = builtin.unrealized_conversion_cast %f : () -> () to !llvm.ptr\n" ++
        "%r = llvm.call %p() : !llvm.ptr, () -> i64");
    defer testing.allocator.free(text);
    try testing.expectError(error.CallableAbiMismatch, inspectCalls(testing.allocator, text, unknownContract));
}

test "a callable cast cannot change its ABI or originate from an unknown value" {
    for ([_][]const u8{
        "%p = builtin.unrealized_conversion_cast %unknown : () -> () to !llvm.ptr",
        "%p = builtin.unrealized_conversion_cast %f : () -> i64 to !llvm.ptr",
        "%p = builtin.unrealized_conversion_cast %f : () -> () to i64",
    }) |cast| {
        const body = try std.fmt.allocPrint(testing.allocator, "%f = func.constant @lin.body : () -> ()\n{s}\nllvm.call %p() : !llvm.ptr, () -> ()", .{cast});
        defer testing.allocator.free(body);
        const text = try fixture(testing.allocator, body);
        defer testing.allocator.free(text);
        try testing.expectError(error.IndirectCall, inspectCalls(testing.allocator, text, unknownContract));
    }
}

test "a function reference without the canonical pointer cast is refused" {
    const text = try fixture(testing.allocator, "%f = func.constant @lin.body : () -> ()\nllvm.call %f() : !llvm.ptr, () -> ()");
    defer testing.allocator.free(text);
    try testing.expectError(error.IndirectCall, inspectCalls(testing.allocator, text, unknownContract));
}

test "a callable from another function's SSA scope is refused" {
    const text =
        \\module {
        \\ func.func private @lin.first() {
        \\  %f = func.constant @lin.first : () -> ()
        \\ }
        \\ func.func private @lin.second() {
        \\  llvm.call %f() : !llvm.ptr, () -> ()
        \\ }
        \\}
    ;
    try testing.expectError(error.IndirectCall, inspectCalls(testing.allocator, text, unknownContract));
}

test "a replaceable fallback body does not prove an unguarded native target" {
    const text =
        \\module {
        \\ func.func @linea_task_start_migratable() attributes {llvm.linkage = #llvm.linkage<weak>} {
        \\ }
        \\ func.func private @lin.caller() {
        \\  func.call @linea_task_start_migratable()
        \\ }
        \\}
    ;
    const inspected = inspectCalls(testing.allocator, text, unknownContract);
    defer if (inspected) |rows| testing.allocator.free(rows) else |_| {};
    try testing.expectError(error.NativeCallWithoutGuard, inspected);
}

test "a replaceable fallback requires a guard and cannot prove a callable origin" {
    const guarded =
        \\module {
        \\ func.func @linea_task_start_migratable() attributes {llvm.linkage = #llvm.linkage< weak >} {
        \\ }
        \\ func.func private @lin.caller() {
        \\  func.call @linea_fiber_restrict_current()
        \\  func.call @linea_task_start_migratable()
        \\ }
        \\}
    ;
    const rows = try inspectCalls(testing.allocator, guarded, unknownContract);
    defer testing.allocator.free(rows);
    try testing.expectEqual(Kind.guarded_native, rows[1].kind);
    const address =
        \\module {
        \\ func.func @lin.replaceable() attributes {llvm.linkage = #llvm.linkage<linkonce>} {
        \\ }
        \\ func.func private @lin.caller() {
        \\  %f = func.constant @lin.replaceable : () -> ()
        \\ }
        \\}
    ;
    try testing.expectError(error.ExternalCallableAddress, inspectCalls(testing.allocator, address, unknownContract));
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

fn neutralTestContract(name: []const u8) runtime_symbols.MigrationContract {
    return if (std.mem.eql(u8, name, "audited_native")) .neutral else .unknown;
}

test "explicit neutral native calls are covered without weakening unknown fallback" {
    const text = try fixture(testing.allocator, "func.call @audited_native()");
    defer testing.allocator.free(text);
    try testing.expectError(error.NativeCallWithoutGuard, inspectCalls(testing.allocator, text, unknownContract));
    const rows = try inspectCalls(testing.allocator, text, neutralTestContract);
    defer testing.allocator.free(rows);
    try testing.expectEqual(Kind.neutral_native, rows[0].kind);
}
