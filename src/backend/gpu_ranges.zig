//! Exact representability facts for device integer values. Source UInt64
//! arithmetic remains UInt64; only values proved to fit may use device i32.
const std = @import("std");
const mir_mod = @import("../mir/mir.zig");
const loops_mod = @import("../mir/index_loops.zig");
const InstId = mir_mod.InstId;
const Mir = mir_mod.Mir;

pub const Interval = struct {
    min: u32,
    max: u32,
    /// Guaranteed zero low bits, capped at the Float32 word alignment.
    alignment: u2 = 0,
    empty: bool = false,

    pub fn constant(value: u32) Interval {
        return .{ .min = value, .max = value, .alignment = if (value % 4 == 0) 2 else if (value % 2 == 0) 1 else 0 };
    }
};

pub const Ranges = struct {
    items: []?Interval,
    loops: loops_mod.Facts,
    mir: *const Mir,

    pub fn init(gpa: std.mem.Allocator, mir: *const Mir) !?Ranges {
        var loops = switch (try loops_mod.analyze(gpa, mir)) {
            .valid => |facts| facts,
            .invalid => return null,
        };
        errdefer loops.deinit(gpa);
        const items = try gpa.alloc(?Interval, mir.insts.len);
        @memset(items, null);
        var result: Ranges = .{ .items = items, .loops = loops, .mir = mir };
        for (items, 0..) |*item, i| item.* = result.derive(InstId.at(@intCast(i)));
        return result;
    }

    pub fn deinit(self: *Ranges, gpa: std.mem.Allocator) void {
        gpa.free(self.items);
        self.loops.deinit(gpa);
        self.* = undefined;
    }

    pub fn at(self: *const Ranges, value: InstId, use: InstId) ?Interval {
        if (self.loops.counterBound(value, use)) |bound| {
            if (bound.max > std.math.maxInt(u32)) return null;
            return .{ .min = 0, .max = @intCast(bound.max), .empty = bound.empty };
        }
        return self.items[value.index()];
    }

    pub fn knownBranch(self: *const Ranges, terminal: InstId) ?mir_mod.BlockId {
        const branch = self.mir.branchOf(terminal);
        const condition = self.at(branch.cond, terminal) orelse return null;
        if (condition.empty or condition.min != condition.max) return null;
        return if (condition.min == 0) branch.else_block else branch.then_block;
    }

    fn derive(self: *const Ranges, id: InstId) ?Interval {
        const mir = self.mir;
        const ty = mir.typeOf(id);
        if (ty != .u64 and ty != .bool_) return null;
        return switch (mir.tagOf(id)) {
            .constant => if (mir.constantOf(id) >= 0 and mir.constantOf(id) <= std.math.maxInt(u32)) Interval.constant(@intCast(mir.constantOf(id))) else null,
            .load => if (self.loops.counterBound(id, id)) |bound|
                if (bound.max <= std.math.maxInt(u32)) .{ .min = 0, .max = @intCast(bound.max) } else null
            else
                null,
            .add,
            .sub,
            .mul,
            .div,
            .rem,
            .cmp_eq,
            .cmp_ne,
            .cmp_lt,
            .cmp_le,
            .cmp_gt,
            .cmp_ge,
            => blk: {
                const pair = mir.binaryOf(id);
                const left = self.at(pair.lhs, id) orelse break :blk if (ty == .bool_) .{ .min = 0, .max = 1 } else null;
                const right = self.at(pair.rhs, id) orelse break :blk if (ty == .bool_) .{ .min = 0, .max = 1 } else null;
                break :blk operation(mir.tagOf(id), left, right);
            },
            .check => blk: {
                const check = mir.checkOf(id);
                const value = self.at(check.value, id) orelse break :blk null;
                if (value.empty or mir.resultRoleOf(check.value) != .value or ty != mir.typeOf(check.value)) break :blk null;
                const proven = switch (check.kind) {
                    // An exact UInt32 interval is also an exact UInt64 result.
                    .overflow, .conversion_out_of_range => ty == .u64,
                    .division_by_zero => ty == .u64 and value.min > 0,
                    .index_out_of_bounds, .misaligned_access => ty == .bool_ and value.min == 1 and value.max == 1,
                    else => false,
                };
                break :blk if (proven) value else null;
            },
            else => null,
        };
    }
};

/// Every accepted arithmetic result is exact, rather than a modulo-32
/// approximation. An unknown or overflowing range makes admission refuse it.
pub fn operation(tag: mir_mod.Inst.Tag, left: Interval, right: Interval) ?Interval {
    if (left.empty or right.empty) return .{ .min = 0, .max = 0, .empty = true };
    const a: u64 = left.min;
    const b: u64 = left.max;
    const c: u64 = right.min;
    const d: u64 = right.max;
    var min: u64 = 0;
    var max: u64 = 0;
    var alignment: u2 = 0;
    switch (tag) {
        .add => {
            min = a + c;
            max = b + d;
            alignment = @min(left.alignment, right.alignment);
        },
        .sub => {
            if (a < d) return null;
            min = a - d;
            max = b - c;
            alignment = @min(left.alignment, right.alignment);
        },
        .mul => {
            min = a * c;
            max = b * d;
            alignment = @intCast(@min(@as(u3, left.alignment) + right.alignment, 2));
        },
        .div => {
            if (c == 0) return null;
            min = a / d;
            max = b / c;
            if (c == 1 and d == 1) alignment = left.alignment;
        },
        .rem => {
            if (c == 0) return null;
            max = @min(b, d - 1);
            // x % y = x - (x / y) * y retains every factor of two
            // shared by x and y.
            alignment = @min(left.alignment, right.alignment);
        },
        .cmp_lt => return comparison(b < c, a >= d),
        .cmp_le => return comparison(b <= c, a > d),
        .cmp_gt => return comparison(a > d, b <= c),
        .cmp_ge => return comparison(a >= d, b < c),
        .cmp_eq => return comparison(a == b and c == d and a == c, b < c or d < a),
        .cmp_ne => return comparison(b < c or d < a, a == b and c == d and a == c),
        else => return null,
    }
    if (max > std.math.maxInt(u32)) return null;
    if (min == max) return Interval.constant(@intCast(min));
    return .{ .min = @intCast(min), .max = @intCast(max), .alignment = alignment };
}

fn comparison(always: bool, never: bool) Interval {
    return if (always) Interval.constant(1) else if (never) Interval.constant(0) else .{ .min = 0, .max = 1 };
}

test "device index ranges reject narrowing overflow and preserve word alignment" {
    const testing = std.testing;
    const max = Interval.constant(std.math.maxInt(u32));
    try testing.expect(operation(.add, max, Interval.constant(1)) == null);
    try testing.expect(operation(.mul, max, Interval.constant(2)) == null);
    try testing.expect(operation(.sub, Interval.constant(0), Interval.constant(1)) == null);
    try testing.expect(operation(.div, max, Interval.constant(0)) == null);
    try testing.expect(operation(.rem, max, Interval.constant(0)) == null);
    const position: Interval = .{ .min = 0, .max = 63 };
    const bytes = operation(.mul, position, Interval.constant(4)).?;
    try testing.expectEqual(@as(u32, 252), bytes.max);
    try testing.expectEqual(@as(u2, 2), bytes.alignment);
    try testing.expectEqual(Interval.constant(1), operation(.cmp_lt, position, Interval.constant(64)).?);
    try testing.expectEqual(Interval.constant(0), operation(.cmp_ge, position, Interval.constant(64)).?);
}

// Check the operation on concrete members, including low bits that the
// interval bounds alone cannot express.
fn checkMembers(tag: mir_mod.Inst.Tag, left: Interval, right: Interval) !void {
    const interval = operation(tag, left, right) orelse return;
    try std.testing.expectEqual(left.empty or right.empty, interval.empty);
    if (interval.empty) return;
    var x: u64 = left.min;
    while (x <= left.max) : (x += 1) {
        if (x % (@as(u64, 1) << left.alignment) != 0) continue;
        var y: u64 = right.min;
        while (y <= right.max) : (y += 1) {
            if (y % (@as(u64, 1) << right.alignment) != 0) continue;
            const actual = switch (tag) {
                .add => x + y,
                .sub => try std.math.sub(u64, x, y),
                .mul => x * y,
                .div, .rem => blk: {
                    try std.testing.expect(y > 0);
                    break :blk if (tag == .div) x / y else x % y;
                },
                .cmp_eq => @intFromBool(x == y),
                .cmp_ne => @intFromBool(x != y),
                .cmp_lt => @intFromBool(x < y),
                .cmp_le => @intFromBool(x <= y),
                .cmp_gt => @intFromBool(x > y),
                .cmp_ge => @intFromBool(x >= y),
                else => unreachable,
            };
            try std.testing.expect(actual >= interval.min and actual <= interval.max);
            try std.testing.expectEqual(@as(u64, 0), actual % (@as(u64, 1) << interval.alignment));
        }
    }
}

test "device index interval operations contain every aligned scalar result" {
    const ops = [_]mir_mod.Inst.Tag{ .add, .sub, .mul, .div, .rem, .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge };
    // Bounds need not be members: a remainder with aligned operands can
    // have an upper bound of three while its only represented value is zero.
    for (0..8) |a| for (a..8) |b| for (0..3) |al| {
        const left: Interval = .{ .min = @intCast(a), .max = @intCast(b), .alignment = @intCast(al) };
        if (std.mem.alignForward(usize, a, @as(usize, 1) << @intCast(al)) > b) continue;
        for (0..8) |c| for (c..8) |d| for (0..3) |ar| {
            const right: Interval = .{ .min = @intCast(c), .max = @intCast(d), .alignment = @intCast(ar) };
            if (std.mem.alignForward(usize, c, @as(usize, 1) << @intCast(ar)) > d) continue;
            for (ops) |tag| try checkMembers(tag, left, right);
        };
    };
    const empty: Interval = .{ .min = 0, .max = 0, .empty = true };
    const high: Interval = .{ .min = std.math.maxInt(u32) - 7, .max = std.math.maxInt(u32), .alignment = 2 };
    for (ops) |tag| {
        try checkMembers(tag, high, high);
        try checkMembers(tag, high, Interval.constant(4));
        try checkMembers(tag, empty, high);
        try checkMembers(tag, high, empty);
        try std.testing.expect(operation(tag, empty, high).?.empty);
        try std.testing.expect(operation(tag, high, empty).?.empty);
    }
    const scaled = operation(.mul, .{ .min = 0, .max = 5 }, Interval.constant(4)).?;
    const remainder = operation(.rem, scaled, Interval.constant(8)).?;
    try std.testing.expectEqual(@as(u2, 2), remainder.alignment);
    const base = Interval.constant(std.math.maxInt(u32) - 7);
    const address = operation(.add, remainder, base).?;
    for (0..6) |lane| {
        const byte = @as(u64, base.min) + (lane * 4) % 8;
        try std.testing.expect(byte >= address.min and byte <= address.max);
        try std.testing.expectEqual(@as(u64, 0), byte % (@as(u64, 1) << address.alignment));
    }
    try checkMembers(.add, remainder, base);
    try std.testing.expect(operation(.add, remainder, high) == null);
}

test "device index ranges consume verified loop witnesses without truncation" {
    const testing = std.testing;
    const gpa = testing.allocator;
    for ([_]u64{ 0, 4, std.math.maxInt(u32), @as(u64, std.math.maxInt(u32)) + 1, std.math.maxInt(u64) }) |count| {
        var mir = try loops_mod.Test.counted(gpa, count);
        defer mir.deinit(gpa);
        var ranges = (try Ranges.init(gpa, &mir)).?;
        defer ranges.deinit(gpa);
        const loop = mir.index_loops[0];
        const header = ranges.at(loop.position, loop.position);
        const next = ranges.at(mir.storeOf(loop.step).value, loop.step);
        if (count > std.math.maxInt(u32)) {
            try testing.expect(header == null);
            try testing.expect(next == null);
        } else {
            try testing.expectEqual(@as(u32, @intCast(count)), header.?.max);
            try testing.expectEqual(count == 0, next.?.empty);
            if (count != 0) try testing.expectEqual(@as(u32, @intCast(count)), next.?.max);
        }
    }
}

test "device index checks require exact values and satisfied predicates" {
    const span = @import("../support/span.zig").Span.empty;
    const TypeId = @import("../sema/types.zig").TypeId;
    const gpa = std.testing.allocator;
    const cases = [_]struct { kind: mir_mod.TrapKind, ty: TypeId, input: i128, accepted: bool }{
        .{ .kind = .overflow, .ty = .u64, .input = std.math.maxInt(u32), .accepted = true },
        .{ .kind = .overflow, .ty = .u64, .input = -1, .accepted = false },
        .{ .kind = .conversion_out_of_range, .ty = .u64, .input = std.math.maxInt(u32), .accepted = true },
        .{ .kind = .conversion_out_of_range, .ty = .u64, .input = @as(i128, 1) << 32, .accepted = false },
        .{ .kind = .division_by_zero, .ty = .u64, .input = 1, .accepted = true },
        .{ .kind = .division_by_zero, .ty = .u64, .input = 0, .accepted = false },
        .{ .kind = .index_out_of_bounds, .ty = .bool_, .input = 1, .accepted = true },
        .{ .kind = .index_out_of_bounds, .ty = .bool_, .input = 0, .accepted = false },
        .{ .kind = .misaligned_access, .ty = .bool_, .input = 1, .accepted = true },
        .{ .kind = .misaligned_access, .ty = .bool_, .input = 0, .accepted = false },
        .{ .kind = .assertion_failed, .ty = .bool_, .input = 1, .accepted = false },
    };
    for (cases) |case| {
        var builder = Mir.Builder.init(gpa);
        defer builder.deinit();
        const block = try builder.addBlock();
        const operand = try builder.addInst(block, .{ .tag = .constant, .ty = case.ty, .span = span, .data = .{ .constant = case.input } });
        const check = try builder.addInst(block, .{ .tag = .check, .ty = case.ty, .span = span, .data = .{ .check = .{ .value = operand, .kind = case.kind } } });
        _ = try builder.setTerminator(block, .{ .tag = .ret, .ty = .unit, .span = span, .data = .{ .unary = check } });
        var mir = try builder.finish(block, .from(0));
        defer mir.deinit(gpa);
        var ranges = (try Ranges.init(gpa, &mir)).?;
        defer ranges.deinit(gpa);
        const result = ranges.at(check, check);
        try std.testing.expectEqual(case.accepted, result != null);
        if (result) |interval| try std.testing.expectEqual(Interval.constant(@intCast(case.input)), interval);
    }
}
