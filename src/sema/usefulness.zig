//! Which values a list of patterns leaves untaken, and which of them no value
//! reaches.
//!
//! Every coverage rule asks about *usefulness*: a row of patterns is useful
//! when some value matches it and no row before it. A `match` arm that is not
//! useful is [T-Unreachable]; a wildcard row after every arm is useful exactly
//! when some value no arm takes exists ([T-Cover]); and a wildcard after a
//! single pattern is useful when that pattern misses a value ([T-Refutable]).
//! The answer for the wildcard row carries witnesses, patterns for such
//! values, which is what a diagnostic prints.
//!
//! The algorithm is Maranget's ("Warnings for pattern matching", 2007),
//! answered for every row in one pass, as rustc does. A column is split by the
//! constructors its type has: an enum's variants, the one constructor of a
//! struct, tuple or newtype, and for an integer the intervals its rows'
//! literals and ranges cut its range into. Each constructor a row names gets a
//! branch holding the rows that match it, a row with a wildcard there going to
//! every branch; constructors no row names share one branch of the wildcard
//! rows. A type with no constructors a pattern can name -- text, a type
//! parameter -- is matched only by a wildcard. A row is useful when, in some
//! branch, it is the first row left once every column is consumed.
//!
//! **Cost.** A row whose head names a constructor goes to that constructor's
//! branch alone, and a row with a wildcard there goes to every branch of the
//! column; the cells copied into branches are the work. So a matrix whose rows
//! never put a wildcard where another row names a constructor costs the size
//! of its patterns, and each wildcard row adds one copy per constructor its
//! column splits into. Integer rows are bucketed by binary search over the
//! sorted cut points, so an integer column costs its rows times the logarithm
//! of its cut points plus the copies. Deciding whether nested patterns cover a
//! type is NP-complete, so the copies are bounded by a budget, `max_cells`,
//! rather than by an argument about the patterns written.

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
        /// Where every branch and witness is built; freed by the caller when
        /// the construct is checked.
        arena: std.mem.Allocator,
        /// The cells built so far, held against `limit`.
        cells: usize = 0,
        limit: usize = max_cells,

        pub const Error = error{ OutOfMemory, TooIntricate };

        pub const Cell = struct { pattern: *const Pattern, ty: Ty };
        pub const Row = []const Cell;

        /// The most values the wildcard row's witnesses name; past them a
        /// report says there are more.
        pub const max_witnesses = 9;

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

        /// What one pass answers.
        pub const Outcome = struct {
            /// Whether each row is useful after the rows before it.
            reached: []const bool,
            /// Values of the queried type no row matches, at most
            /// `max_witnesses`, or none where there was no query or every
            /// value is matched.
            missing: []const Witness,
        };

        const Ref = struct { cells: []const Cell, id: u32 };

        /// One step down the column the pass is splitting: the constructor a
        /// branch matched, or the values no row names, which the wildcard rows
        /// alone take.
        const Step = struct {
            ty: Ty,
            choice: union(enum) {
                ctor: Ctor,
                /// What a value the rows name none of may be, as witnesses.
                absent: []const Witness,
            },
        };

        const Pass = struct {
            reached: []bool,
            query: ?u32,
            missing: std.ArrayList(Witness) = .empty,
            path: std.ArrayList(Step) = .empty,
        };

        /// Answers, in one pass, which of `rows` are useful after the rows
        /// before them and, where `query` is a type, which of its values no
        /// row matches.
        pub fn check(self: *Self, rows: []const Row, query: ?Ty) Error!Outcome {
            const count = rows.len + @intFromBool(query != null);
            const refs = try self.arena.alloc(Ref, count);
            for (rows, 0..) |r, i| refs[i] = .{ .cells = r, .id = @intCast(i) };
            if (query) |ty| {
                const cell = try self.take(1);
                cell[0] = .{ .pattern = &wild, .ty = ty };
                refs[rows.len] = .{ .cells = cell, .id = @intCast(rows.len) };
            }
            var pass: Pass = .{
                .reached = try self.arena.alloc(bool, count),
                .query = if (query != null) @intCast(rows.len) else null,
            };
            @memset(pass.reached, false);
            try self.walk(&pass, refs);
            return .{ .reached = pass.reached[0..rows.len], .missing = pass.missing.items };
        }

        /// One branch of a column: the step that names it and the rows it
        /// holds.
        const Branch = struct { step: Step, rows: []const Ref };

        /// Walks the matrix to every leaf. A column that splits into one
        /// branch is followed in place rather than by a call, so a wide row
        /// costs no depth of recursion; only a column that splits recurses.
        fn walk(self: *Self, pass: *Pass, start: []const Ref) Error!void {
            const depth = pass.path.items.len;
            defer pass.path.shrinkRetainingCapacity(depth);
            var rows = start;
            while (true) {
                if (rows.len == 0) return;
                // Every column consumed: the first row left matches what the
                // path describes, and every row after it is behind it.
                if (rows[0].cells.len == 0) {
                    const first = rows[0].id;
                    pass.reached[first] = true;
                    if (pass.query == first and pass.missing.items.len < max_witnesses) try self.record(pass);
                    return;
                }
                const branches = try self.split_column(rows);
                if (branches.len == 1) {
                    try pass.path.append(self.arena, branches[0].step);
                    rows = branches[0].rows;
                    continue;
                }
                for (branches) |b| {
                    try pass.path.append(self.arena, b.step);
                    try self.walk(pass, b.rows);
                    _ = pass.path.pop();
                }
                return;
            }
        }

        /// The branches the head column splits into, in order: each
        /// constructor a row names, then the values none names.
        fn split_column(self: *Self, rows: []const Ref) Error![]const Branch {
            const ty = rows[0].cells[0].ty;
            var out: std.ArrayList(Branch) = .empty;
            switch (self.context.kind(ty)) {
                .product => try out.append(self.arena, try self.branch(rows, ty, .product)),
                .variants => |count| {
                    // The variants the rows name, sorted, and nothing sized by
                    // the enum: a column split again under every branch of the
                    // one before it pays for what its rows name each time,
                    // never for every variant the enum declares.
                    var named: std.ArrayList(u32) = .empty;
                    for (rows) |r| switch (r.cells[0].pattern.*) {
                        .variant => |v| if (v.index < count) try named.append(self.arena, v.index),
                        else => {},
                    };
                    std.mem.sort(u32, named.items, {}, std.sort.asc(u32));
                    var kept: usize = 0;
                    for (named.items) |k| {
                        if (kept > 0 and named.items[kept - 1] == k) continue;
                        named.items[kept] = k;
                        kept += 1;
                    }
                    named.shrinkRetainingCapacity(kept);
                    try self.charge(named.items.len);
                    try self.variantBranches(&out, rows, ty, named.items);
                    if (named.items.len == count) return out.items;
                    // The variants no row names: any of them, carrying
                    // anything; with none named, any value at all. Found by
                    // walking the named ones in order, so the walk stops after
                    // the named ones and the witnesses it keeps.
                    var absent: std.ArrayList(Witness) = .empty;
                    if (named.items.len == 0) {
                        try absent.append(self.arena, .{ .ty = ty, .shape = .wild });
                    } else {
                        var k: u32 = 0;
                        var next: usize = 0;
                        while (k < count and absent.items.len < max_witnesses) : (k += 1) {
                            if (next < named.items.len and named.items[next] == k) {
                                next += 1;
                                continue;
                            }
                            try absent.append(self.arena, try self.applied(ty, .{ .variant = k }, null));
                        }
                    }
                    try out.append(self.arena, try self.rest(rows, ty, absent.items));
                },
                .integer => |bounds| try self.integers(&out, rows, ty, bounds),
                .opaque_ => try out.append(self.arena, try self.rest(rows, ty, &.{.{ .ty = ty, .shape = .wild }})),
            }
            return out.items;
        }

        /// One branch per variant a row names, in variant order, built in one
        /// pass over the rows: a row naming a variant joins that variant's
        /// branch alone, and a row with a wildcard joins every one. So the
        /// work is the rows plus one entry per wildcard row and named variant,
        /// not the rows once per variant.
        fn variantBranches(
            self: *Self,
            out: *std.ArrayList(Branch),
            rows: []const Ref,
            ty: Ty,
            named: []const u32,
        ) Error!void {
            const buckets = try self.arena.alloc(std.ArrayList(Ref), named.len);
            for (buckets) |*b| b.* = .empty;
            for (rows) |r| {
                switch (r.cells[0].pattern.*) {
                    .variant => |v| {
                        const at = std.sort.binarySearch(u32, named, v.index, orderIndex).?;
                        const arity = self.context.arity(ty, .{ .variant = v.index });
                        try buckets[at].append(self.arena, (try self.specialise(r, .{ .variant = v.index }, arity)).?);
                    },
                    else => for (named, buckets) |k, *b| {
                        const arity = self.context.arity(ty, .{ .variant = k });
                        try b.append(self.arena, (try self.specialise(r, .{ .variant = k }, arity)).?);
                    },
                }
            }
            for (named, buckets) |k, b| {
                try out.append(self.arena, .{ .step = .{ .ty = ty, .choice = .{ .ctor = .{ .variant = k } } }, .rows = b.items });
            }
        }

        fn orderIndex(key: u32, item: u32) std.math.Order {
            return std.math.order(key, item);
        }

        /// The branch for constructor `c`: each row naming it, with its head
        /// replaced by the constructor's parts, and each row with a wildcard
        /// there, in their order.
        fn branch(self: *Self, rows: []const Ref, ty: Ty, c: Ctor) Error!Branch {
            const arity = self.context.arity(ty, c);
            var kept: std.ArrayList(Ref) = .empty;
            for (rows) |r| {
                if (try self.specialise(r, c, arity)) |s| try kept.append(self.arena, s);
            }
            return .{ .step = .{ .ty = ty, .choice = .{ .ctor = c } }, .rows = kept.items };
        }

        /// The branch for the values no row's head names: the rows with a
        /// wildcard there, their tails shared.
        fn rest(self: *Self, rows: []const Ref, ty: Ty, absent: []const Witness) Error!Branch {
            var kept: std.ArrayList(Ref) = .empty;
            for (rows) |r| {
                if (r.cells[0].pattern.* != .wild) continue;
                try self.charge(1);
                try kept.append(self.arena, .{ .cells = r.cells[1..], .id = r.id });
            }
            return .{ .step = .{ .ty = ty, .choice = .{ .absent = absent } }, .rows = kept.items };
        }

        /// An integer column, cut at every boundary its rows' literals and
        /// ranges write. Each interval a row names gets a branch; the
        /// intervals none names share one branch of the wildcard rows.
        fn integers(self: *Self, out: *std.ArrayList(Branch), rows: []const Ref, ty: Ty, bounds: Interval) Error!void {
            const atoms = try self.split(rows, bounds);
            // Which rows each interval holds, in row order: a range's rows by
            // binary search over the cut points, a wildcard's in all.
            const buckets = try self.arena.alloc(std.ArrayList(Ref), atoms.len);
            const named = try self.arena.alloc(bool, atoms.len);
            for (buckets) |*b| b.* = .empty;
            @memset(named, false);
            for (rows) |r| {
                const rest_cells = r.cells[1..];
                switch (r.cells[0].pattern.*) {
                    .integers => |range| {
                        var a = atomAt(atoms, range.lo);
                        while (a < atoms.len and atoms[a].lo <= range.hi) : (a += 1) {
                            named[a] = true;
                            try self.charge(1);
                            try buckets[a].append(self.arena, .{ .cells = rest_cells, .id = r.id });
                        }
                    },
                    else => for (buckets) |*b| {
                        try self.charge(1);
                        try b.append(self.arena, .{ .cells = rest_cells, .id = r.id });
                    },
                }
            }
            var gaps: std.ArrayList(Witness) = .empty;
            for (atoms, 0..) |atom, a| {
                if (!named[a]) {
                    if (gaps.items.len < max_witnesses) try gaps.append(self.arena, .{ .ty = ty, .shape = .{ .integers = atom } });
                    continue;
                }
                try out.append(self.arena, .{ .step = .{ .ty = ty, .choice = .{ .ctor = .{ .integers = atom } } }, .rows = buckets[a].items });
            }
            if (gaps.items.len == 0) return;
            // A gap that is the whole range is any value at all.
            if (gaps.items.len == 1 and gaps.items[0].shape.integers.lo == bounds.lo and gaps.items[0].shape.integers.hi == bounds.hi) {
                gaps.items[0] = .{ .ty = ty, .shape = .wild };
            }
            try out.append(self.arena, try self.rest(rows, ty, gaps.items));
        }

        /// The interval holding `value`. `atoms` is sorted and covers the
        /// type's range without gaps.
        fn atomAt(atoms: []const Interval, value: i128) usize {
            var lo: usize = 0;
            var hi: usize = atoms.len;
            while (lo < hi) {
                const mid = (lo + hi) / 2;
                if (atoms[mid].hi < value) lo = mid + 1 else hi = mid;
            }
            return lo;
        }

        /// The row with its head replaced by the parts of constructor `c`, or
        /// null where its head is another constructor.
        fn specialise(self: *Self, r: Ref, c: Ctor, arity: u32) Error!?Ref {
            const head = r.cells[0];
            const parts: []const *const Pattern = switch (head.pattern.*) {
                .wild => &.{},
                .variant => |v| switch (c) {
                    .variant => |k| if (v.index == k) v.args else return null,
                    else => return null,
                },
                .product => |args| args,
                .integers => return null,
            };
            // A constructor with no parts drops the head, and the row's tail
            // is shared rather than copied.
            if (arity == 0) {
                try self.charge(1);
                return .{ .cells = r.cells[1..], .id = r.id };
            }
            const out = try self.take(arity + r.cells.len - 1);
            for (0..arity) |i| {
                out[i] = .{
                    .pattern = if (parts.len == arity) parts[i] else &wild,
                    .ty = self.context.part(head.ty, c, @intCast(i)),
                };
            }
            @memcpy(out[arity..], r.cells[1..]);
            return .{ .cells = out, .id = r.id };
        }

        /// Room for `n` cells, held against the budget.
        fn take(self: *Self, n: usize) Error![]Cell {
            try self.charge(n);
            return self.arena.alloc(Cell, n);
        }

        /// Holds `n` cells of work against the budget: cells copied, or a
        /// row's tail shared into a branch.
        fn charge(self: *Self, n: usize) Error!void {
            self.cells += n;
            if (self.cells > self.limit) return error.TooIntricate;
        }

        /// The intervals `bounds` is cut into by every boundary of the
        /// column's integer patterns: each one is taken whole or not at all by
        /// every row. At most twice the rows, plus one.
        fn split(self: *Self, rows: []const Ref, bounds: Interval) Error![]const Interval {
            var points: std.ArrayList(i128) = .empty;
            try points.append(self.arena, bounds.lo);
            try points.append(self.arena, bounds.hi + 1);
            for (rows) |r| switch (r.cells[0].pattern.*) {
                .integers => |range| {
                    if (range.lo > bounds.lo and range.lo <= bounds.hi) try points.append(self.arena, range.lo);
                    if (range.hi >= bounds.lo and range.hi < bounds.hi) try points.append(self.arena, range.hi + 1);
                },
                else => {},
            };
            std.mem.sort(i128, points.items, {}, std.sort.asc(i128));
            var atoms: std.ArrayList(Interval) = .empty;
            var i: usize = 0;
            while (i + 1 < points.items.len) : (i += 1) {
                if (points.items[i] == points.items[i + 1]) continue;
                try atoms.append(self.arena, .{ .lo = points.items[i], .hi = points.items[i + 1] - 1 });
            }
            return atoms.items;
        }

        /// Adds the values the path to the query row describes, as witnesses:
        /// one per choice where a step stands for several absent values.
        fn record(self: *Self, pass: *Pass) Error!void {
            var at: usize = 0;
            const built = try self.build(pass.path.items, &at);
            for (built) |w| {
                if (pass.missing.items.len == max_witnesses) break;
                try pass.missing.append(self.arena, w);
            }
        }

        /// The witnesses the steps from `at.*` describe, reading the path in
        /// preorder: a constructor step takes as many witnesses after it as
        /// the constructor has parts. Several choices at one step multiply,
        /// up to `max_witnesses`.
        fn build(self: *Self, path: []const Step, at: *usize) Error![]const Witness {
            const step = path[at.*];
            at.* += 1;
            switch (step.choice) {
                .absent => |choices| return choices,
                .ctor => |c| {
                    const arity = self.context.arity(step.ty, c);
                    var combos: std.ArrayList([]Witness) = .empty;
                    try combos.append(self.arena, try self.arena.alloc(Witness, arity));
                    for (0..arity) |i| {
                        const options = try self.build(path, at);
                        var next: std.ArrayList([]Witness) = .empty;
                        for (combos.items) |combo| for (options) |o| {
                            if (next.items.len == max_witnesses) break;
                            const copy = try self.arena.dupe(Witness, combo);
                            copy[i] = o;
                            try next.append(self.arena, copy);
                        };
                        combos = next;
                    }
                    const out = try self.arena.alloc(Witness, combos.items.len);
                    for (combos.items, 0..) |parts, n| out[n] = .{ .ty = step.ty, .shape = switch (c) {
                        .variant => |k| .{ .variant = .{ .index = k, .args = parts } },
                        .product => .{ .product = parts },
                        .integers => |atom| .{ .integers = atom },
                    } };
                    return out;
                },
            }
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

/// The first value of `ty` the rows leave untaken, or null.
fn firstMissing(c: *TestCoverage, rows: []const TestCoverage.Row, ty: TestTypes.Ty) !?TestCoverage.Witness {
    const outcome = try c.check(rows, ty);
    return if (outcome.missing.len == 0) null else outcome.missing[0];
}

/// Whether `row` is useful after `rows`.
fn usefulAfter(c: *TestCoverage, rows: []const TestCoverage.Row, row: TestCoverage.Row) !bool {
    const all = try c.arena.alloc(TestCoverage.Row, rows.len + 1);
    @memcpy(all[0..rows.len], rows);
    all[rows.len] = row;
    return (try c.check(all, null)).reached[rows.len];
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
    const missing = (try firstMissing(&c, &rows, .pair)).?;
    // `(None, Some)`: a pair whose first part is `None` and whose second is
    // `Some` of anything.
    try testing.expectEqual(@as(u32, 1), missing.shape.product[0].shape.variant.index);
    try testing.expectEqual(@as(u32, 0), missing.shape.product[1].shape.variant.index);

    const all = rows ++ [_]TestCoverage.Row{try rowOf(arena, try pairOf(arena, &none, try some(arena, &wild)), .pair)};
    try testing.expect(try firstMissing(&c, &all, .pair) == null);
}

test "an arm inside an earlier one is not useful, and an arm beside it is" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var c: TestCoverage = .{ .context = .{}, .arena = arena };

    const earlier = [_]TestCoverage.Row{try rowOf(arena, try some(arena, &wild), .nest)};
    const inside = try rowOf(arena, try some(arena, try some(arena, &wild)), .nest);
    try testing.expect(!try usefulAfter(&c, &earlier, inside));
    try testing.expect(try usefulAfter(&c, &earlier, try rowOf(arena, &none, .nest)));
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
    const gap = (try firstMissing(&c, &rows, .opt)).?;
    const inner = gap.shape.variant.args[0].shape.integers;
    try testing.expectEqual(@as(i128, 1), inner.lo);
    try testing.expectEqual(@as(i128, 3), inner.hi);

    // A range taking part of what an earlier one took is still useful for the
    // rest, and one inside it is not.
    const covered = [_]TestCoverage.Row{try rowOf(arena, try integers(arena, 0, 2), .byte)};
    try testing.expect(try usefulAfter(&c, &covered, try rowOf(arena, try integers(arena, 2, 3), .byte)));
    try testing.expect(!try usefulAfter(&c, &covered, try rowOf(arena, try integers(arena, 1, 2), .byte)));
}

test "a type no pattern names is covered by a wildcard alone" {
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var c: TestCoverage = .{ .context = .{}, .arena = arena };

    try testing.expect(try firstMissing(&c, &.{}, .text) != null);
    const rows = [_]TestCoverage.Row{try rowOf(arena, &wild, .text)};
    try testing.expect(try firstMissing(&c, &rows, .text) == null);
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
    try testing.expectError(error.TooIntricate, c.check(&rows, .pair));
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
        _ = try c.check(rows.items, .pair);
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
        const found = try usefulAfter(&c, &rows, try rowOf(arena, q, .opt));
        try testing.expectEqual(expected, found);
    };
}
