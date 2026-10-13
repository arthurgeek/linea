const std = @import("std");
const types = @import("types.zig");
const TypeId = types.TypeId;
const Allocator = std.mem.Allocator;
const FileId = @import("../support/source.zig").FileId;
const Span = @import("../support/span.zig").Span;
const ExprId = @import("../syntax/node.zig").ExprId;

/// Where a variable was created or settled, for diagnostic labels.
pub const Site = struct { file: FileId, span: Span };

pub const Outcome = union(enum) {
    /// The variable already had this type.
    agreed,
    /// The variable took this type now.
    settled,
    /// The variable already has a different type, carried here.
    conflict: TypeId,
};

pub const Origin = struct { site: Site, forced: bool };

/// A value folded while its type was open, checked against the range of the
/// type it finally has.
pub const Pending = struct {
    v: u32,
    expr: ExprId,
    value: i128,
    /// Which rule the value answers to: a literal as written, a negation, or
    /// the result of an arithmetic operation.
    rule: enum { literal, negation, operation },
};

/// The variables one body created, as a prefix length of `body_created`.
pub const Body = struct { start: u32 };

/// Types the checker has not settled yet: an integer literal's, and each type
/// parameter a function value leaves for its uses to select.
///
/// One entry per literal site that met no expected type and per parameter of
/// a function value named without one, so the table grows with the source
/// rather than with any product of it. A root holds the concrete type once one
/// is chosen; the rest point at their root.
pub const OpenTypes = struct {
    parent: std.ArrayList(u32) = .empty,
    /// Whether the variable's type must be an integer, read at its root. A
    /// literal's variable must; a function value's parameter need not, until
    /// it is joined with one that must.
    integer: std.ArrayList(bool) = .empty,
    type_of: std.ArrayList(TypeId) = .empty,
    /// The pool type standing for each variable, so joined variables that are
    /// still open resolve to one type: their root's.
    named: std.ArrayList(TypeId) = .empty,
    origin_of: std.ArrayList(?Origin) = .empty,
    body_created: std.ArrayList(u32) = .empty,
    /// One entry per open literal, in the order the literals were checked.
    pending: std.ArrayList(Pending) = .empty,

    pub fn deinit(self: *OpenTypes, gpa: Allocator) void {
        self.parent.deinit(gpa);
        self.integer.deinit(gpa);
        self.type_of.deinit(gpa);
        self.named.deinit(gpa);
        self.origin_of.deinit(gpa);
        self.body_created.deinit(gpa);
        self.pending.deinit(gpa);
    }

    /// A fresh variable for an integer literal.
    pub fn create(self: *OpenTypes, gpa: Allocator) !u32 {
        return self.createOf(gpa, true);
    }

    /// A fresh variable for a type parameter, which may settle on any type.
    pub fn createType(self: *OpenTypes, gpa: Allocator) !u32 {
        return self.createOf(gpa, false);
    }

    test "a type variable settles on any type and has no fallback" {
        var table: OpenTypes = .{};
        defer table.deinit(std.testing.allocator);
        const v = try table.createType(std.testing.allocator);
        table.fallback(v, .i64);
        try std.testing.expectEqual(@as(?TypeId, null), table.settled(v));
        try std.testing.expectEqual(Outcome.settled, table.settle(v, .bool_, null));
        try std.testing.expectEqual(@as(?TypeId, .bool_), table.settled(v));
    }

    fn createOf(self: *OpenTypes, gpa: Allocator, integer: bool) !u32 {
        const v: u32 = @intCast(self.parent.items.len);
        try self.parent.append(gpa, v);
        try self.integer.append(gpa, integer);
        try self.type_of.append(gpa, .poison);
        try self.named.append(gpa, .poison);
        try self.origin_of.append(gpa, null);
        try self.body_created.append(gpa, v);
        return v;
    }

    pub fn find(self: *OpenTypes, v: u32) u32 {
        var root = v;
        while (self.parent.items[root] != root) root = self.parent.items[root];
        var at = v;
        while (self.parent.items[at] != root) {
            const next = self.parent.items[at];
            self.parent.items[at] = root;
            at = next;
        }
        return root;
    }

    /// Records the pool type minted for variable `v`.
    pub fn name(self: *OpenTypes, v: u32, t: TypeId) void {
        self.named.items[v] = t;
    }

    /// What `v` stands for now: its settled type, or its root's open type.
    pub fn resolved(self: *OpenTypes, v: u32) TypeId {
        const root = self.find(v);
        const held = self.type_of.items[root];
        return if (held == .poison) self.named.items[root] else held;
    }

    /// Whether `v`'s type must be an integer.
    pub fn isInteger(self: *OpenTypes, v: u32) bool {
        return self.integer.items[self.find(v)];
    }

    test "a type variable joined with a literal's must be an integer and falls back" {
        var table: OpenTypes = .{};
        defer table.deinit(std.testing.allocator);
        const parameter = try table.createType(std.testing.allocator);
        const literal = try table.create(std.testing.allocator);
        try std.testing.expect(!table.isInteger(parameter));
        _ = table.join(parameter, literal);
        try std.testing.expect(table.isInteger(parameter));
        try std.testing.expectEqual(literal, table.find(parameter));
        table.fallback(parameter, .i64);
        try std.testing.expectEqual(@as(?TypeId, .i64), table.settled(parameter));
    }

    /// Settles an open integer variable to `to` with no place to name as the
    /// reason, as falling back at the end of a body does. A variable that
    /// need not be an integer has no type to fall back to and stays open.
    pub fn fallback(self: *OpenTypes, v: u32, to: TypeId) void {
        const root = self.find(v);
        if (!self.integer.items[root]) return;
        if (self.type_of.items[root] == .poison) self.type_of.items[root] = to;
    }

    /// Stands `v` for poison once its unsettled parameter has been reported,
    /// so every type mentioning it resolves to a type already diagnosed.
    pub fn abandon(self: *OpenTypes, v: u32) void {
        self.named.items[self.find(v)] = .poison;
    }

    test "an abandoned variable resolves to poison" {
        var table: OpenTypes = .{};
        defer table.deinit(std.testing.allocator);
        const v = try table.createType(std.testing.allocator);
        table.name(v, .u8);
        table.abandon(v);
        try std.testing.expectEqual(TypeId.poison, table.resolved(v));
    }

    pub fn settled(self: *OpenTypes, v: u32) ?TypeId {
        const t = self.type_of.items[self.find(v)];
        return if (t == .poison) null else t;
    }

    /// Settles `v` on `to`, remembering `at` as where, when there is a place
    /// to name.
    pub fn settle(self: *OpenTypes, v: u32, to: TypeId, at: ?Site) Outcome {
        const root = self.find(v);
        const held = self.type_of.items[root];
        if (held == to) return .agreed;
        if (held != .poison) return .{ .conflict = held };
        self.type_of.items[root] = to;
        if (at) |site| self.origin_of.items[root] = .{ .site = site, .forced = false };
        return .settled;
    }

    /// Makes `a` and `b` one variable. The root is `a`'s unless only `b`'s
    /// must be an integer, so a joined literal keeps its integer type's name.
    pub fn join(self: *OpenTypes, a: u32, b: u32) Outcome {
        var ra = self.find(a);
        var rb = self.find(b);
        if (ra == rb) return .agreed;
        if (self.integer.items[rb] and !self.integer.items[ra]) std.mem.swap(u32, &ra, &rb);
        const ta = self.type_of.items[ra];
        const tb = self.type_of.items[rb];
        if (ta != .poison and tb != .poison and ta != tb) return .{ .conflict = ta };
        self.parent.items[rb] = ra;
        self.integer.items[ra] = self.integer.items[ra] or self.integer.items[rb];
        if (ta == .poison) {
            self.type_of.items[ra] = tb;
            self.origin_of.items[ra] = self.origin_of.items[rb];
        }
        return .agreed;
    }

    pub fn pushBody(self: *const OpenTypes) Body {
        return .{ .start = @intCast(self.body_created.items.len) };
    }

    /// Settles every variable the body created and left open, then forgets
    /// the body's list so an enclosing body walks only its own.
    pub fn fallbackBody(self: *OpenTypes, body: Body, to: TypeId) void {
        for (self.body_created.items[body.start..]) |v| self.fallback(v, to);
        self.body_created.shrinkRetainingCapacity(body.start);
    }

    /// Settles every integer variable still open, wherever it was created.
    /// A variable created outside any body's scope is still owed a type.
    pub fn fallbackAll(self: *OpenTypes, to: TypeId) void {
        for (self.type_of.items, 0..) |held, v| {
            if (self.parent.items[v] == v and self.integer.items[v] and held == .poison) self.type_of.items[v] = to;
        }
    }

    pub fn forced(self: *OpenTypes, v: u32, to: TypeId, at: Site) void {
        const root = self.find(v);
        if (!self.integer.items[root] or self.type_of.items[root] != .poison) return;
        self.type_of.items[root] = to;
        self.origin_of.items[root] = .{ .site = at, .forced = true };
    }

    pub fn origin(self: *OpenTypes, v: u32) ?Origin {
        return self.origin_of.items[self.find(v)];
    }

    /// Keeps a folded value until its variable's type is final, when the
    /// range the type holds is known.
    pub fn awaitRange(self: *OpenTypes, gpa: Allocator, waiting: Pending) !void {
        try self.pending.append(gpa, waiting);
    }
};

// Compiles the tests `OpenTypes` holds beside the functions they test.
comptime {
    _ = OpenTypes;
}

test "a pending literal follows the variable it was joined into" {
    var table: OpenTypes = .{};
    defer table.deinit(std.testing.allocator);
    const site: Site = .{ .file = .from(0), .span = .{ .start = 0, .end = 1 } };
    const a = try table.create(std.testing.allocator);
    const b = try table.create(std.testing.allocator);
    try table.awaitRange(std.testing.allocator, .{ .v = b, .expr = ExprId.at(2), .value = 300, .rule = .literal });
    _ = table.join(a, b);
    _ = table.settle(a, .u8, site);
    const waiting = table.pending.items[0];
    try std.testing.expectEqual(@as(i128, 300), waiting.value);
    try std.testing.expectEqual(@as(?TypeId, .u8), table.settled(waiting.v));
}

test "a settled variable agrees with its type and conflicts with another" {
    var table: OpenTypes = .{};
    defer table.deinit(std.testing.allocator);
    const site: Site = .{ .file = .from(0), .span = .{ .start = 0, .end = 1 } };
    const v = try table.create(std.testing.allocator);
    try std.testing.expectEqual(@as(?TypeId, null), table.settled(v));
    try std.testing.expectEqual(Outcome.settled, table.settle(v, .u8, site));
    try std.testing.expectEqual(Outcome.agreed, table.settle(v, .u8, site));
    try std.testing.expectEqual(Outcome{ .conflict = .u8 }, table.settle(v, .u16, site));
}

test "joined variables settle together" {
    var table: OpenTypes = .{};
    defer table.deinit(std.testing.allocator);
    const site: Site = .{ .file = .from(0), .span = .{ .start = 0, .end = 1 } };
    const a = try table.create(std.testing.allocator);
    const b = try table.create(std.testing.allocator);
    _ = table.join(a, b);
    _ = table.settle(b, .u64, site);
    try std.testing.expectEqual(@as(?TypeId, .u64), table.settled(a));
}

test "joining two settled variables of different types conflicts" {
    var table: OpenTypes = .{};
    defer table.deinit(std.testing.allocator);
    const site: Site = .{ .file = .from(0), .span = .{ .start = 0, .end = 1 } };
    const a = try table.create(std.testing.allocator);
    const b = try table.create(std.testing.allocator);
    _ = table.settle(a, .u8, site);
    _ = table.settle(b, .u16, site);
    try std.testing.expectEqual(Outcome{ .conflict = .u8 }, table.join(a, b));
}

test "a body falls back only the variables it created and left open" {
    var table: OpenTypes = .{};
    defer table.deinit(std.testing.allocator);
    const site: Site = .{ .file = .from(0), .span = .{ .start = 0, .end = 1 } };
    const outer = try table.create(std.testing.allocator);
    const body = table.pushBody();
    const inner_open = try table.create(std.testing.allocator);
    const inner_settled = try table.create(std.testing.allocator);
    _ = table.settle(inner_settled, .u8, site);
    table.fallbackBody(body, .i64);
    try std.testing.expectEqual(@as(?TypeId, .i64), table.settled(inner_open));
    try std.testing.expectEqual(@as(?TypeId, .u8), table.settled(inner_settled));
    try std.testing.expectEqual(@as(?TypeId, null), table.settled(outer));
}

test "falling back everything settles every variable still open" {
    var table: OpenTypes = .{};
    defer table.deinit(std.testing.allocator);
    const site: Site = .{ .file = .from(0), .span = .{ .start = 0, .end = 1 } };
    const open = try table.create(std.testing.allocator);
    const settled_one = try table.create(std.testing.allocator);
    _ = table.settle(settled_one, .u8, site);
    table.fallbackAll(.i64);
    try std.testing.expectEqual(@as(?TypeId, .i64), table.settled(open));
    try std.testing.expectEqual(@as(?TypeId, .u8), table.settled(settled_one));
}

test "a forced fallback is remembered as the origin" {
    var table: OpenTypes = .{};
    defer table.deinit(std.testing.allocator);
    const site: Site = .{ .file = .from(0), .span = .{ .start = 3, .end = 6 } };
    const v = try table.create(std.testing.allocator);
    table.forced(v, .i64, site);
    const why = table.origin(v).?;
    try std.testing.expect(why.forced);
    try std.testing.expectEqual(@as(u32, 3), why.site.span.start);
}

/// Whether a value of type `T` can hold a `TypeId` anywhere inside it.
/// Whether `T` holds a `TypeId` that `rewriteTypeIds` reaches. Storage that
/// holds one where the walk cannot follow is a compile error rather than a
/// silent omission.
fn containsTypeId(comptime T: type, comptime depth: u8) bool {
    if (T == TypeId) return true;
    if (depth == 0) @compileError("storage nested too deeply for rewriteTypeIds: " ++ @typeName(T));
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "Slice") and @hasDecl(T, "Field") and @hasDecl(T, "get")) {
        const Elem = @typeInfo(@TypeOf(T.get)).@"fn".return_type.?;
        if (containsTypeId(Elem, depth - 1)) @compileError("rewriteTypeIds cannot follow a MultiArrayList of " ++ @typeName(Elem));
        return false;
    }
    return switch (@typeInfo(T)) {
        .pointer => |p| switch (p.size) {
            .slice => containsTypeId(p.child, depth - 1),
            // What a single pointer reaches belongs to another owner.
            .one => false,
            .many, .c => if (p.child != u8 and p.child != anyopaque and containsTypeId(p.child, depth - 1))
                @compileError("rewriteTypeIds cannot follow an unbounded pointer to " ++ @typeName(p.child))
            else
                false,
        },
        .optional => |o| containsTypeId(o.child, depth - 1),
        .array => |a| containsTypeId(a.child, depth - 1),
        .@"union" => |u| blk: {
            inline for (u.fields) |f| if (containsTypeId(f.type, depth - 1)) break :blk true;
            break :blk false;
        },
        .@"struct" => |s| blk: {
            if (@hasDecl(T, "KV") and @hasDecl(T, "valueIterator")) break :blk containsTypeId(@FieldType(T.KV, "value"), depth - 1);
            inline for (s.fields) |f| if (containsTypeId(f.type, depth - 1)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

/// Replaces every `TypeId` inside `value` with `ctx.map(id)`.
///
/// Walks slices, optionals, arrays, unions, struct fields and hash-map
/// values. A single-item pointer is not followed: what it points at belongs
/// to another owner. A hash map's keys are left alone, since changing a key
/// in place would break its bucket.
pub fn rewriteTypeIds(ctx: anytype, value: anytype) std.mem.Allocator.Error!void {
    const T = @typeInfo(@TypeOf(value)).pointer.child;
    if (comptime !containsTypeId(T, 16)) return;
    if (T == TypeId) {
        value.* = try ctx.map(value.*);
        return;
    }
    switch (@typeInfo(T)) {
        .pointer => |p| if (p.size == .slice) {
            for (@constCast(value.*)) |*item| try rewriteTypeIds(ctx, item);
        },
        .optional => if (value.*) |*inner| try rewriteTypeIds(ctx, inner),
        .array => for (value) |*item| try rewriteTypeIds(ctx, item),
        .@"union" => switch (value.*) {
            inline else => |*payload| try rewriteTypeIds(ctx, payload),
        },
        .@"struct" => |s| {
            if (comptime @hasDecl(T, "KV") and @hasDecl(T, "valueIterator")) {
                var values = value.valueIterator();
                while (values.next()) |item| try rewriteTypeIds(ctx, item);
                return;
            }
            inline for (s.fields) |f| try rewriteTypeIds(ctx, &@field(value, f.name));
        },
        else => {},
    }
}

test "rewriting reaches type ids through slices, optionals, unions and map values" {
    const Row = struct { ty: TypeId, other: ?TypeId, choice: union(enum) { none, some: TypeId } };
    var rows = [_]Row{.{ .ty = .i64, .other = .i64, .choice = .{ .some = .i64 } }};
    var by_key: std.AutoHashMapUnmanaged(u32, TypeId) = .empty;
    defer by_key.deinit(std.testing.allocator);
    try by_key.put(std.testing.allocator, 1, .i64);
    const Holder = struct { rows: []Row, by_key: std.AutoHashMapUnmanaged(u32, TypeId) };
    var holder: Holder = .{ .rows = &rows, .by_key = by_key };
    const Swap = struct {
        fn map(_: @This(), t: TypeId) !TypeId {
            return if (t == .i64) .u8 else t;
        }
    };
    try rewriteTypeIds(Swap{}, &holder);
    try std.testing.expectEqual(TypeId.u8, rows[0].ty);
    try std.testing.expectEqual(@as(?TypeId, .u8), rows[0].other);
    try std.testing.expectEqual(TypeId.u8, rows[0].choice.some);
    try std.testing.expectEqual(TypeId.u8, holder.by_key.get(1).?);
}
