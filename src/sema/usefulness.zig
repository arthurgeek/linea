//! Which values a list of patterns leaves untaken.
//!
//! One question answers every coverage rule: whether a row of patterns is
//! *useful* after a matrix of earlier rows, meaning some value matches the row
//! and no earlier one. A `match` arm that is not useful after the arms before
//! it is [T-Unreachable]; a wildcard that is useful after every arm names a
//! value the `match` leaves untaken ([T-Cover]); and a pattern a wildcard is
//! useful after misses a value ([T-Refutable]). The answer carries a witness,
//! a pattern for such a value, which is what a diagnostic prints.
//!
//! The algorithm is Maranget's ("Warnings for pattern matching", 2007). A
//! column is split by the constructors its type has: an enum's variants, the
//! one constructor of a struct, tuple or newtype, and for an integer the
//! intervals the column's literals and ranges cut its range into. A type with
//! no constructors a pattern can name -- text, a type parameter -- is matched
//! only by a wildcard.
//!
//! Deciding whether nested patterns cover a type is NP-complete, so the work
//! of one question is bounded by a budget of matrix cells rather than by an
//! argument about the patterns written. A matrix whose rows never put a
//! wildcard where another row names a constructor follows one path per row,
//! and costs the size of its patterns per question. A wildcard over a column
//! whose constructors are all named branches once per constructor; a column
//! naming only some of them does not branch, because every absent constructor
//! answers alike. What is left is bounded by `max_cells`.

const std = @import("std");
const testing = std.testing;

/// The cells a set of questions about one construct may build, past which the
/// construct is refused as too intricate to check ([T-CoverLimit]).
pub const max_cells: usize = 1 << 20;

/// A closed interval of integers, in arithmetic wide enough for `UInt64`'s
/// maximum and `Int64`'s minimum together.
pub const Interval = struct {
    lo: i128,
    hi: i128,

    fn contains(self: Interval, other: Interval) bool {
        return self.lo <= other.lo and other.hi <= self.hi;
    }
};

/// What constructors a type is built by, as far as a pattern can name them.
pub const Kind = union(enum) {
    /// An enum with this many variants.
    variants: u32,
    /// A struct, tuple or newtype: one constructor of this many parts.
    product: u32,
    /// An integer type with these bounds.
    integer: Interval,
    /// Nothing a pattern names: only a wildcard matches it.
    opaque_,
};

/// One constructor of a type.
pub const Ctor = union(enum) {
    variant: u32,
    product,
    /// An interval no other boundary of its column falls inside.
    integers: Interval,
};

/// A pattern as coverage reads it. A binder and `_` are both wildcards.
pub const Pattern = union(enum) {
    wild,
    /// A variant and the patterns for what it carries, or none where the
    /// pattern leaves its payload unnamed.
    variant: struct { index: u32, args: []const *const Pattern },
    /// The one constructor of a struct, tuple or newtype, with a pattern for
    /// each part in declaration order.
    product: []const *const Pattern,
    /// An integer literal or range.
    integers: Interval,
};

pub const wild: Pattern = .wild;

/// The usefulness check over one kind of type, `Context.Ty`.
///
/// `Context` answers what a type is built by: `kind(ty) Kind`,
/// `arity(ty, ctor) u32` and `part(ty, ctor, i) Ty`.
pub fn Coverage(comptime Context: type) type {
    return struct {
        const Self = @This();
        pub const Ty = Context.Ty;

        context: Context,
        /// Where every matrix and witness is built; freed by the caller when
        /// the construct is checked.
        arena: std.mem.Allocator,
        /// The cells built so far, held against `max_cells`.
        cells: usize = 0,
        limit: usize = max_cells,

        pub const Error = error{ OutOfMemory, TooIntricate };

        pub const Cell = struct { pattern: *const Pattern, ty: Ty };
        pub const Row = []const Cell;

        /// A value the rows leave untaken, as a pattern.
        pub const Witness = struct {
            ty: Ty,
            shape: union(enum) {
                wild,
                variant: struct { index: u32, args: []const Witness },
                product: []const Witness,
                integers: Interval,
            },

            /// Whether the witness names nothing a wildcard does not.
            pub fn isWild(self: Witness) bool {
                return switch (self.shape) {
                    .wild => true,
                    .product => |parts| for (parts) |p| {
                        if (!p.isWild()) break false;
                    } else true,
                    else => false,
                };
            }
        };

        /// A value `row` matches and no row of `rows` does, or null where
        /// there is none.
        pub fn useful(self: *Self, rows: []const Row, row: Row) Error!?[]const Witness {
            return self.usefulAt(rows, row);
        }

        /// A value of `ty` no row of `rows`, each a single pattern, matches.
        pub fn missing(self: *Self, rows: []const Row, ty: Ty) Error!?Witness {
            const q = try self.arena.alloc(Cell, 1);
            q[0] = .{ .pattern = &wild, .ty = ty };
            const found = try self.usefulAt(rows, q) orelse return null;
            return found[0];
        }

        fn usefulAt(self: *Self, rows: []const Row, q: Row) Error!?[]const Witness {
            if (q.len == 0) return if (rows.len == 0) &.{} else null;
            const head = q[0];
            switch (head.pattern.*) {
                .wild => return self.usefulWild(rows, q),
                .variant => |v| return self.usefulCtor(rows, q, .{ .variant = v.index }),
                .product => return self.usefulCtor(rows, q, .product),
                .integers => |range| {
                    const atoms = try self.split(rows, head.ty, range);
                    for (atoms) |atom| {
                        if (!range.contains(atom)) continue;
                        if (try self.usefulCtor(rows, q, .{ .integers = atom })) |w| return w;
                    }
                    return null;
                },
            }
        }

        fn usefulWild(self: *Self, rows: []const Row, q: Row) Error!?[]const Witness {
            const ty = q[0].ty;
            const kind = self.context.kind(ty);
            switch (kind) {
                .opaque_ => {},
                .variants => |count| {
                    var named = try std.DynamicBitSetUnmanaged.initEmpty(self.arena, count);
                    for (rows) |r| switch (r[0].pattern.*) {
                        .variant => |v| if (v.index < count) named.set(v.index),
                        else => {},
                    };
                    if (named.count() == count) {
                        for (0..count) |k| {
                            if (try self.usefulCtor(rows, q, .{ .variant = @intCast(k) })) |w| return w;
                        }
                        return null;
                    }
                    const rest = try self.usefulAt(try self.defaultRows(rows), q[1..]) orelse return null;
                    // The first variant no row names, carrying anything; with
                    // none named, the value is any value at all.
                    const absent: Witness = if (named.count() == 0)
                        .{ .ty = ty, .shape = .wild }
                    else blk: {
                        var k: u32 = 0;
                        while (named.isSet(k)) k += 1;
                        break :blk try self.applied(ty, .{ .variant = k }, null);
                    };
                    return try self.prepend(absent, rest);
                },
                .product => {
                    for (rows) |r| {
                        if (r[0].pattern.* == .product) return self.usefulCtor(rows, q, .product);
                    }
                },
                .integer => |bounds| {
                    const atoms = try self.split(rows, ty, bounds);
                    const gap: ?Interval = for (atoms) |atom| {
                        if (!self.columnCovers(rows, atom)) break atom;
                    } else null;
                    if (gap) |g| {
                        const rest = try self.usefulAt(try self.defaultRows(rows), q[1..]) orelse return null;
                        // A gap that is the whole range is any value at all.
                        const whole = g.lo == bounds.lo and g.hi == bounds.hi;
                        return try self.prepend(if (whole) .{ .ty = ty, .shape = .wild } else .{ .ty = ty, .shape = .{ .integers = g } }, rest);
                    }
                    for (atoms) |atom| {
                        if (try self.usefulCtor(rows, q, .{ .integers = atom })) |w| return w;
                    }
                    return null;
                },
            }
            const rest = try self.usefulAt(try self.defaultRows(rows), q[1..]) orelse return null;
            return try self.prepend(.{ .ty = ty, .shape = .wild }, rest);
        }

        /// Whether some row's head takes every integer of `atom`.
        fn columnCovers(_: *const Self, rows: []const Row, atom: Interval) bool {
            for (rows) |r| switch (r[0].pattern.*) {
                .integers => |range| if (range.contains(atom)) return true,
                else => {},
            };
            return false;
        }

        fn usefulCtor(self: *Self, rows: []const Row, q: Row, c: Ctor) Error!?[]const Witness {
            const ty = q[0].ty;
            const arity = self.context.arity(ty, c);
            var specialised: std.ArrayList(Row) = .empty;
            for (rows) |r| {
                if (try self.specialise(r, c, arity)) |s| try specialised.append(self.arena, s);
            }
            const sq = try self.specialise(q, c, arity) orelse return null;
            const inner = try self.usefulAt(specialised.items, sq) orelse return null;
            const out = try self.arena.alloc(Witness, inner.len - arity + 1);
            out[0] = try self.applied(ty, c, inner[0..arity]);
            @memcpy(out[1..], inner[arity..]);
            return out;
        }

        /// The row with its head replaced by the parts of constructor `c`, or
        /// null where its head is another constructor.
        fn specialise(self: *Self, r: Row, c: Ctor, arity: u32) Error!?Row {
            const head = r[0];
            const parts: []const *const Pattern = switch (head.pattern.*) {
                .wild => &.{},
                .variant => |v| switch (c) {
                    .variant => |k| if (v.index == k) v.args else return null,
                    else => return null,
                },
                .product => |args| args,
                .integers => |range| switch (c) {
                    .integers => |atom| if (range.contains(atom)) &.{} else return null,
                    else => return null,
                },
            };
            const out = try self.take(arity + r.len - 1);
            for (0..arity) |i| {
                out[i] = .{
                    .pattern = if (parts.len == arity) parts[i] else &wild,
                    .ty = self.context.part(head.ty, c, @intCast(i)),
                };
            }
            @memcpy(out[arity..], r[1..]);
            return out;
        }

        /// The rows whose head is a wildcard, without it.
        fn defaultRows(self: *Self, rows: []const Row) Error![]const Row {
            var out: std.ArrayList(Row) = .empty;
            for (rows) |r| {
                if (r[0].pattern.* != .wild) continue;
                const rest = try self.take(r.len - 1);
                @memcpy(rest, r[1..]);
                try out.append(self.arena, rest);
            }
            return out.items;
        }

        /// Room for `n` cells, held against the budget.
        fn take(self: *Self, n: usize) Error![]Cell {
            self.cells += n;
            if (self.cells > self.limit) return error.TooIntricate;
            return self.arena.alloc(Cell, n);
        }

        /// The intervals `bounds` is cut into by every boundary of the
        /// column's integer patterns: each one is taken whole or not at all by
        /// every row. At most twice the rows, plus one.
        fn split(self: *Self, rows: []const Row, ty: Ty, bounds: Interval) Error![]const Interval {
            const whole = switch (self.context.kind(ty)) {
                .integer => |b| b,
                else => bounds,
            };
            var points: std.ArrayList(i128) = .empty;
            try points.append(self.arena, whole.lo);
            try points.append(self.arena, whole.hi + 1);
            for (rows) |r| switch (r[0].pattern.*) {
                .integers => |range| {
                    if (range.lo > whole.lo and range.lo <= whole.hi) try points.append(self.arena, range.lo);
                    if (range.hi >= whole.lo and range.hi < whole.hi) try points.append(self.arena, range.hi + 1);
                },
                else => {},
            };
            if (bounds.lo > whole.lo and bounds.lo <= whole.hi) try points.append(self.arena, bounds.lo);
            if (bounds.hi >= whole.lo and bounds.hi < whole.hi) try points.append(self.arena, bounds.hi + 1);
            std.mem.sort(i128, points.items, {}, std.sort.asc(i128));
            var atoms: std.ArrayList(Interval) = .empty;
            var i: usize = 0;
            while (i + 1 < points.items.len) : (i += 1) {
                if (points.items[i] == points.items[i + 1]) continue;
                try atoms.append(self.arena, .{ .lo = points.items[i], .hi = points.items[i + 1] - 1 });
            }
            return atoms.items;
        }

        /// The witness for constructor `c` of `ty`, its parts given or each
        /// a wildcard.
        fn applied(self: *Self, ty: Ty, c: Ctor, parts: ?[]const Witness) Error!Witness {
            const arity = self.context.arity(ty, c);
            const args = try self.arena.alloc(Witness, arity);
            for (0..arity) |i| {
                args[i] = if (parts) |p| p[i] else .{ .ty = self.context.part(ty, c, @intCast(i)), .shape = .wild };
            }
            return .{ .ty = ty, .shape = switch (c) {
                .variant => |k| .{ .variant = .{ .index = k, .args = args } },
                .product => .{ .product = args },
                .integers => |atom| .{ .integers = atom },
            } };
        }

        fn prepend(self: *Self, first: Witness, rest: []const Witness) Error![]const Witness {
            const out = try self.arena.alloc(Witness, rest.len + 1);
            out[0] = first;
            @memcpy(out[1..], rest);
            return out;
        }
    };
}

/// A small type world for the tests: `Bit` is a two-variant enum, `Opt` an
/// option of a `Byte` (an integer from 0 to 3), `Pair` a pair of options,
/// `Nest` an option of an option, and `Text` matched only by a wildcard.
const TestTypes = struct {
    pub const Ty = enum { bit, byte, opt, pair, nest, text };

    pub fn kind(_: TestTypes, ty: Ty) Kind {
        return switch (ty) {
            .bit => .{ .variants = 2 },
            .byte => .{ .integer = .{ .lo = 0, .hi = 3 } },
            .opt, .nest => .{ .variants = 2 },
            .pair => .{ .product = 2 },
            .text => .opaque_,
        };
    }

    pub fn arity(_: TestTypes, ty: Ty, c: Ctor) u32 {
        return switch (ty) {
            .opt, .nest => switch (c) {
                .variant => |k| if (k == 0) 1 else 0,
                else => 0,
            },
            .pair => 2,
            else => 0,
        };
    }

    pub fn part(_: TestTypes, ty: Ty, _: Ctor, _: u32) Ty {
        return switch (ty) {
            .opt => .byte,
            .nest => .opt,
            .pair => .opt,
            else => .text,
        };
    }
};

const TestCoverage = Coverage(TestTypes);

fn some(arena: std.mem.Allocator, inner: *const Pattern) !*const Pattern {
    const args = try arena.alloc(*const Pattern, 1);
    args[0] = inner;
    const p = try arena.create(Pattern);
    p.* = .{ .variant = .{ .index = 0, .args = args } };
    return p;
}

const none: Pattern = .{ .variant = .{ .index = 1, .args = &.{} } };

fn pairOf(arena: std.mem.Allocator, a: *const Pattern, b: *const Pattern) !*const Pattern {
    const args = try arena.alloc(*const Pattern, 2);
    args[0] = a;
    args[1] = b;
    const p = try arena.create(Pattern);
    p.* = .{ .product = args };
    return p;
}

fn integers(arena: std.mem.Allocator, lo: i128, hi: i128) !*const Pattern {
    const p = try arena.create(Pattern);
    p.* = .{ .integers = .{ .lo = lo, .hi = hi } };
    return p;
}

fn rowOf(arena: std.mem.Allocator, p: *const Pattern, ty: TestTypes.Ty) !TestCoverage.Row {
    const r = try arena.alloc(TestCoverage.Cell, 1);
    r[0] = .{ .pattern = p, .ty = ty };
    return r;
}

test "a pair of options is covered by its four shapes, and the missing one is named" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var c: TestCoverage = .{ .context = .{}, .arena = arena };

    const rows = [_]TestCoverage.Row{
        try rowOf(arena, try pairOf(arena, try some(arena, &wild), try some(arena, &wild)), .pair),
        try rowOf(arena, try pairOf(arena, try some(arena, &wild), &none), .pair),
        try rowOf(arena, try pairOf(arena, &none, &none), .pair),
    };
    const missing = (try c.missing(&rows, .pair)).?;
    // `(None, Some)`: a pair whose first part is `None` and whose second is
    // `Some` of anything.
    try testing.expectEqual(@as(u32, 1), missing.shape.product[0].shape.variant.index);
    try testing.expectEqual(@as(u32, 0), missing.shape.product[1].shape.variant.index);

    const all = rows ++ [_]TestCoverage.Row{try rowOf(arena, try pairOf(arena, &none, try some(arena, &wild)), .pair)};
    try testing.expectEqual(@as(?TestCoverage.Witness, null), try c.missing(&all, .pair));
}

test "an arm inside an earlier one is not useful, and an arm beside it is" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var c: TestCoverage = .{ .context = .{}, .arena = arena };

    const earlier = [_]TestCoverage.Row{try rowOf(arena, try some(arena, &wild), .nest)};
    const inside = try rowOf(arena, try some(arena, try some(arena, &wild)), .nest);
    try testing.expect(try c.useful(&earlier, inside) == null);
    try testing.expect(try c.useful(&earlier, try rowOf(arena, &none, .nest)) != null);
}

test "integer patterns leave the interval between them, which is named whole" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var c: TestCoverage = .{ .context = .{}, .arena = arena };

    const rows = [_]TestCoverage.Row{
        try rowOf(arena, try some(arena, try integers(arena, 0, 0)), .opt),
        try rowOf(arena, &none, .opt),
    };
    const gap = (try c.missing(&rows, .opt)).?;
    const inner = gap.shape.variant.args[0].shape.integers;
    try testing.expectEqual(@as(i128, 1), inner.lo);
    try testing.expectEqual(@as(i128, 3), inner.hi);

    // A range taking part of what an earlier one took is still useful for the
    // rest, and one inside it is not.
    const covered = [_]TestCoverage.Row{try rowOf(arena, try integers(arena, 0, 2), .byte)};
    try testing.expect(try c.useful(&covered, try rowOf(arena, try integers(arena, 2, 3), .byte)) != null);
    try testing.expect(try c.useful(&covered, try rowOf(arena, try integers(arena, 1, 2), .byte)) == null);
}

test "a type no pattern names is covered by a wildcard alone" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var c: TestCoverage = .{ .context = .{}, .arena = arena };

    try testing.expect(try c.missing(&.{}, .text) != null);
    const rows = [_]TestCoverage.Row{try rowOf(arena, &wild, .text)};
    try testing.expect(try c.missing(&rows, .text) == null);
}

test "a match whose check outgrows its budget is refused" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var c: TestCoverage = .{ .context = .{}, .arena = arena, .limit = 4 };

    const rows = [_]TestCoverage.Row{
        try rowOf(arena, try pairOf(arena, try some(arena, &wild), &wild), .pair),
        try rowOf(arena, try pairOf(arena, &wild, try some(arena, &wild)), .pair),
    };
    try testing.expectError(error.TooIntricate, c.missing(&rows, .pair));
}

test "the cells a matrix with no overlapping wildcards builds grow with its rows" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();

    // One arm per value of a pair's first byte, each with `Some` beside it:
    // every row follows one path, so the question costs what the rows hold.
    var spent: [2]usize = undefined;
    for ([_]usize{ 4, 8 }, 0..) |n, at| {
        var c: TestCoverage = .{ .context = .{}, .arena = arena };
        var rows: std.ArrayList(TestCoverage.Row) = .empty;
        for (0..n) |i| {
            const first = try some(arena, try integers(arena, @intCast(i % 4), @intCast(i % 4)));
            try rows.append(arena, try rowOf(arena, try pairOf(arena, first, try some(arena, &wild)), .pair));
        }
        _ = try c.missing(rows.items, .pair);
        spent[at] = c.cells;
    }
    try testing.expect(spent[1] <= 3 * spent[0]);
}

test "usefulness agrees with checking every value of a small type" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();

    // Every pattern over `Opt` (a `Byte` from 0 to 3, or none) is one of
    // eight shapes; every pair of rows of them is checked against the six
    // values the type has.
    const shapes = [_]*const Pattern{
        &wild,
        &none,
        try some(arena, &wild),
        try some(arena, try integers(arena, 0, 0)),
        try some(arena, try integers(arena, 1, 2)),
        try some(arena, try integers(arena, 0, 3)),
        try some(arena, try integers(arena, 3, 3)),
        try some(arena, try integers(arena, 2, 3)),
    };
    // The values: `None`, then `Some(0)` through `Some(3)`.
    const values = [_]?i128{ null, 0, 1, 2, 3 };
    const matches = struct {
        fn at(p: *const Pattern, v: ?i128) bool {
            return switch (p.*) {
                .wild => true,
                .variant => |variant| if (variant.index == 1) v == null else v != null and (variant.args.len == 0 or at(variant.args[0], v)),
                .integers => |range| v != null and range.lo <= v.? and v.? <= range.hi,
                .product => false,
            };
        }
    }.at;

    for (shapes) |a| for (shapes) |b| for (shapes) |q| {
        var c: TestCoverage = .{ .context = .{}, .arena = arena };
        const rows = [_]TestCoverage.Row{ try rowOf(arena, a, .opt), try rowOf(arena, b, .opt) };
        var expected = false;
        for (values) |v| {
            if (matches(q, v) and !matches(a, v) and !matches(b, v)) expected = true;
        }
        const found = try c.useful(&rows, try rowOf(arena, q, .opt));
        try testing.expectEqual(expected, found != null);
    };
}
