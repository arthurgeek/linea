//! Generated programs over heap storage, and mutations of them toward
//! unsoundness.
//!
//! The generator builds by construction, as `generate.zig` does: every
//! statement is chosen from those the program's state admits, so nothing is
//! discarded for being refused. The state that matters here is which owners an
//! observation is live over. A mutation is only ever written against an owner
//! nothing observes, and an observation's scope ends before anything changes
//! its owner -- so a program that walks one vector while it pushes into
//! another, or reads through a view inside a closure, is still a program the
//! compiler must accept. A refused one is the generator and the compiler
//! disagreeing about the language, and either may be wrong.
//!
//! It is a generator of its own rather than a production of `generate.zig`,
//! because vectors, slices and maps live in the standard library and the
//! programs that generator writes are compiled without it by every property
//! that reads them.
//!
//! Each program is also interpreted as it is written: the generator keeps a
//! model of every owner's contents and of the running total, and `main`
//! answers 0 only when the total it computed is the model's. So an accepted
//! program is held to what it means as well as to running clean.
//!
//! Every place where an observation is live and used again later is recorded
//! as a site. A mutant inserts, at one site, an operation that may move, grow
//! or free the observed owner's storage -- the first axis of the soundness
//! matrix -- and is held to being refused, or to running clean.

const std = @import("std");
const testing = std.testing;

const choices_mod = @import("choices.zig");
const Choices = choices_mod.Choices;
const matrix = @import("matrix.zig");
const loader = @import("../driver/loader.zig");
const SourceText = @import("../support/source.zig").Source;
const FileTable = @import("../support/source.zig").FileTable;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const lowerProgram = @import("../mir/lower.zig").lowerProgram;
const verify = @import("../mir/verify.zig").verify;

/// How many choice bytes one program is drawn from. The stream wraps, so this
/// bounds how different two programs can be rather than how large one is.
pub const stream_length = 256;

/// Fills a choice stream from a seed, for a run that replays from one number.
pub fn choicesFromSeed(gpa: std.mem.Allocator, seed: u64) ![]u8 {
    return choices_mod.fromSeed(gpa, seed, stream_length);
}

test "a seed fills a whole stream and replays it" {
    const first = try choicesFromSeed(testing.allocator, 79);
    defer testing.allocator.free(first);
    const second = try choicesFromSeed(testing.allocator, 79);
    defer testing.allocator.free(second);
    try testing.expectEqual(@as(usize, stream_length), first.len);
    try testing.expectEqualSlices(u8, first, second);
}

/// How many vectors and maps a program may own.
const max_vecs = 2;
const max_maps = 1;

/// How deeply statements nest: loops, walks and observation scopes alike.
/// Termination may not rest on the choice stream, which wraps.
const max_depth = 3;

/// The most statements one block holds.
const max_block = 3;

/// The most top-level phases `main` holds.
const max_phases = 8;

pub const Generated = struct {
    text: []const u8,
    /// The total `main` compares against, which is the model's.
    expected: u64,
    sites: []const Site,
    /// How far generation read into the choice stream. Mutations read on
    /// from here, so a mutant is a function of the program's own choices.
    choices_read: usize,
};

/// Where a mutation may insert an operation: the start of a line inside a
/// scope where an observation of `target` is live and is used afterwards.
pub const Site = struct {
    offset: usize,
    depth: u32,
    target: Target,
    /// Inside a loop, where a consuming operation is refused by the move
    /// rules whatever it observes, so a mutation writes none there.
    in_loop: bool,
};

/// What a site's observation observes.
pub const Target = union(enum) {
    vec: u8,
    map: u8,
    /// The running total, lent `inout` to a closure.
    total,

    fn storage(self: Target) matrix.Storage {
        return switch (self) {
            .vec => .vec,
            .map => .map,
            .total => .scalar,
        };
    }

    fn write(self: Target, w: *std.Io.Writer) !void {
        switch (self) {
            .vec => |k| try w.print("v{d}", .{k}),
            .map => |k| try w.print("m{d}", .{k}),
            .total => try w.writeAll("total"),
        }
    }
};

/// A scalar value a statement uses: a literal, or a binder in scope.
const Value = union(enum) {
    literal: u8,
    binder: Binder,
};

/// A name bound to a scalar, and how it is read.
const Binder = struct {
    id: u32,
    /// How a use spells it: `*item_3` for a borrowed item, `item_3` for an
    /// owned one, `item_3.value` for a map entry.
    kind: enum { borrowed, owned, entry },
    prefix: []const u8,
};

/// A read-only view the program holds: a slice of a vector, whole or a part.
const View = struct {
    id: u32,
    prefix: []const u8,
    owner: u8,
};

/// What a `for` loop walks.
const Source = union(enum) {
    /// `vK.as_slice()`.
    slice: u8,
    /// `copy(view_N)`.
    view: View,
    /// `vK.as_slice().map(...)`, adding `add` to every item.
    mapped: struct { owner: u8, add: u8 },
    /// `vK.as_slice().filter(...)`, keeping items above `above`.
    filtered: struct { owner: u8, above: u8 },
    /// `vK.as_slice().map(...).filter(...)`.
    mapped_filtered: struct { owner: u8, add: u8, above: u8 },
    /// `mK.entries()`.
    entries: u8,

    fn observed(self: Source) Target {
        return switch (self) {
            .slice => |k| .{ .vec = k },
            .view => |v| .{ .vec = v.owner },
            .mapped => |m| .{ .vec = m.owner },
            .filtered => |f| .{ .vec = f.owner },
            .mapped_filtered => |m| .{ .vec = m.owner },
            .entries => |k| .{ .map = k },
        };
    }

    fn itemKind(self: Source) @FieldType(Binder, "kind") {
        return switch (self) {
            .slice, .view, .filtered => .borrowed,
            .mapped, .mapped_filtered => .owned,
            .entries => .entry,
        };
    }
};

/// An iterator the program advances by hand.
const Stepped = union(enum) {
    slice: u8,
    mapped: struct { owner: u8, add: u8 },
    filtered: struct { owner: u8, above: u8 },

    fn source(self: Stepped) Source {
        return switch (self) {
            .slice => |k| .{ .slice = k },
            .mapped => |m| .{ .mapped = .{ .owner = m.owner, .add = m.add } },
            .filtered => |f| .{ .filtered = .{ .owner = f.owner, .above = f.above } },
        };
    }
};

const Stmt = union(enum) {
    /// `total += V`.
    add: Value,
    push: struct { owner: u8, value: Value },
    /// `match &vK.pop() { Some(p) => { total += p }, None => {} }`.
    pop: struct { owner: u8, id: u32 },
    /// The same with `remove(index)`, which answers `None` past the end.
    remove: struct { owner: u8, index: u8, id: u32 },
    clear: u8,
    truncate: struct { owner: u8, length: u8 },
    reserve: struct { owner: u8, additional: u8 },
    /// `if index < vK.length() { vK[index] = V }`.
    write: struct { owner: u8, index: u8, value: Value },
    /// `vK.release()` and a fresh vector in its place.
    release: u8,
    /// Walks a drain of the vector lent, then releases it and opens a fresh
    /// vector in its place.
    drain: struct { owner: u8, id: u32 },
    insert: struct { map: u8, key: u8, value: Value },
    /// `match &mK.remove(key) { Some(entry) => { total += entry.value }, None => {} }`.
    remove_key: struct { map: u8, key: u8, id: u32 },
    merge: struct { map: u8, key: u8, value: Value },
    update: struct { map: u8, key: u8, add: u8, id: u32 },
    /// `for item in SOURCE { total += ITEM; body }`.
    /// `for item in SOURCE { total += ITEM; body }`, or, where `reads` is
    /// false, `for _item in SOURCE { body }`: a walk whose only use of what it
    /// walks is the walk itself.
    walk: struct { source: Source, item: Binder, reads: bool, body: []const Stmt },
    /// `let view = vK.as_slice()`, then `body`, then a read of the view.
    view: struct { view: View, body: []const Stmt },
    /// A part of the vector matched out of `subspan`, then `body`, then a read.
    part: struct { view: View, start: u8, count: u8, body: []const Stmt },
    /// An element borrowed out of `get`, then `body`, then a read of it.
    element: struct { owner: u8, index: u8, item: Binder, body: []const Stmt },
    /// A map value borrowed out of `get`, then `body`, then a read of it.
    lookup: struct { map: u8, key: u8, item: Binder, body: []const Stmt },
    /// `total += sum_view(view)`: a view passed through a function.
    sum_view: View,
    /// A closure capturing a view, called `calls` times; `walks` says whether
    /// its body walks the view or passes it on.
    peek: struct { view: View, id: u32, walks: bool, calls: u8 },
    /// An iterator advanced by hand: each step is a `next`, a lent walk, or
    /// statements run between the two; a `next` always comes last.
    stepped: struct { iterator: Stepped, id: u32, steps: []const Step },
    /// A closure lent the vector `inout`, called `calls` times. Its body
    /// changes nothing but the vector.
    grow: struct { owner: u8, id: u32, body: []const Stmt, calls: u8 },
    /// A closure lent `total` `inout`, called `calls` times.
    bump: struct { id: u32, add: u8, calls: u8 },
    /// `for _round in 0..count { body }`, or the `while` it stands for.
    loop: struct { id: u32, form: enum { range, hand_written }, count: u8, body: []const Stmt },
};

const Step = union(enum) {
    next: u32,
    /// A walk of the iterator lent, stopping after `limit` items.
    lent: struct { item: Binder, stop: u32, limit: u8, body: []const Stmt },
    stmts: []const Stmt,
};

/// What each owner starts with.
const Setup = struct {
    vecs: u8,
    maps: u8,
    vec_values: [max_vecs][]const u8,
    map_entries: [max_maps][]const [2]u8,
};

const Program = struct {
    setup: Setup,
    body: []const Stmt,
};

/// A program over heap storage, built from a stream of choices.
pub fn generate(gpa: std.mem.Allocator, bytes: []const u8) !Generated {
    var g: Gen = .{ .gpa = gpa, .choices = .{ .bytes = bytes } };
    const program = try g.program();
    var model: Model = try .init(gpa, program.setup);
    try model.run(program.body);
    var r: Render = .{ .gpa = gpa, .out = .init(gpa), .subject = &program };
    try r.program(model.total);
    return .{
        .text = try r.out.toOwnedSlice(),
        .expected = model.total,
        .sites = try r.sites.toOwnedSlice(gpa),
        .choices_read = g.choices.at,
    };
}

test "a program is a function of its choices" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    for (0..16) |seed| {
        const bytes = try choicesFromSeed(gpa, seed);
        const first = try generate(gpa, bytes);
        const second = try generate(gpa, bytes);
        try testing.expectEqualStrings(first.text, second.text);
        try testing.expectEqual(first.expected, second.expected);
        try testing.expectEqual(first.sites.len, second.sites.len);
    }
}

test "some generated program walks storage without reading what it walks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var found = false;
    for (0..64) |seed| {
        const generated = try generate(gpa, try choicesFromSeed(gpa, seed));
        found = found or std.mem.indexOf(u8, generated.text, "for _item_") != null;
    }
    try testing.expect(found);
}

/// What generation may do at one point.
const Context = struct {
    depth: u32 = 0,
    /// Owners some live observation reads. Nothing may change them.
    observed_vecs: [max_vecs]bool = @splat(false),
    observed_maps: [max_maps]bool = @splat(false),
    /// Scalars in scope a value may read.
    scalars: []const Binder = &.{},
    /// Views in scope.
    views: []const View = &.{},

    fn observing(self: Context, target: Target) Context {
        var next = self;
        switch (target) {
            .vec => |k| next.observed_vecs[k] = true,
            .map => |k| next.observed_maps[k] = true,
            .total => {},
        }
        return next;
    }

    fn deeper(self: Context) Context {
        var next = self;
        next.depth += 1;
        return next;
    }
};

const Gen = struct {
    gpa: std.mem.Allocator,
    choices: Choices,
    next_id: u32 = 0,
    setup: Setup = undefined,

    fn id(self: *Gen) u32 {
        const n = self.next_id;
        self.next_id += 1;
        return n;
    }

    fn program(self: *Gen) !Program {
        var setup: Setup = .{
            .vecs = @intCast(self.choices.between(1, max_vecs)),
            .maps = @intCast(self.choices.below(max_maps + 1)),
            .vec_values = @splat(&.{}),
            .map_entries = @splat(&.{}),
        };
        for (0..setup.vecs) |k| {
            const values = try self.gpa.alloc(u8, self.choices.between(1, 4));
            for (values) |*v| v.* = @intCast(self.choices.below(10));
            setup.vec_values[k] = values;
        }
        for (0..setup.maps) |k| {
            const entries = try self.gpa.alloc([2]u8, self.choices.between(1, 3));
            for (entries) |*e| e.* = .{ @intCast(self.choices.below(5)), @intCast(self.choices.below(10)) };
            setup.map_entries[k] = entries;
        }
        self.setup = setup;

        var body: std.ArrayList(Stmt) = .empty;
        const phases = self.choices.between(3, max_phases);
        for (0..phases) |_| try body.append(self.gpa, try self.phase());
        return .{ .setup = setup, .body = try body.toOwnedSlice(self.gpa) };
    }

    /// One top-level phase: the only place an owner may be consumed and
    /// opened again, since a loop would consume it twice.
    fn phase(self: *Gen) !Stmt {
        const top: Context = .{};
        if (self.choices.odds(10)) {
            const owner = self.aVec();
            return if (self.choices.odds(2)) .{ .release = owner } else .{ .drain = .{ .owner = owner, .id = self.id() } };
        }
        return self.stmt(top);
    }

    fn aVec(self: *Gen) u8 {
        return @intCast(self.choices.below(self.setup.vecs));
    }

    fn block(self: *Gen, ctx: Context) ![]const Stmt {
        var out: std.ArrayList(Stmt) = .empty;
        // Mostly bodies with something in them, since an observation's scope
        // is where the sites are; now and then an empty one.
        const n = if (self.choices.odds(5)) 0 else self.choices.between(1, max_block);
        for (0..n) |_| try out.append(self.gpa, try self.stmt(ctx));
        return out.toOwnedSlice(self.gpa);
    }

    fn value(self: *Gen, ctx: Context) Value {
        if (ctx.scalars.len != 0 and self.choices.odds(2)) {
            return .{ .binder = ctx.scalars[self.choices.below(@intCast(ctx.scalars.len))] };
        }
        return .{ .literal = @intCast(self.choices.below(10)) };
    }

    fn withScalar(self: *Gen, ctx: Context, b: Binder) !Context {
        var next = ctx;
        const scalars = try self.gpa.alloc(Binder, ctx.scalars.len + 1);
        @memcpy(scalars[0..ctx.scalars.len], ctx.scalars);
        scalars[ctx.scalars.len] = b;
        next.scalars = scalars;
        return next;
    }

    fn withView(self: *Gen, ctx: Context, v: View) !Context {
        var next = ctx;
        const views = try self.gpa.alloc(View, ctx.views.len + 1);
        @memcpy(views[0..ctx.views.len], ctx.views);
        views[ctx.views.len] = v;
        next.views = views;
        return next;
    }

    /// A vector nothing observes, or null where every one is observed.
    fn freeVec(self: *Gen, ctx: Context) ?u8 {
        var free: [max_vecs]u8 = undefined;
        var n: u32 = 0;
        for (0..self.setup.vecs) |k| if (!ctx.observed_vecs[k]) {
            free[n] = @intCast(k);
            n += 1;
        };
        if (n == 0) return null;
        return free[self.choices.below(n)];
    }

    fn freeMap(self: *Gen, ctx: Context) ?u8 {
        if (self.setup.maps == 0 or ctx.observed_maps[0]) return null;
        return 0;
    }

    fn stmt(self: *Gen, ctx: Context) Error!Stmt {
        // Nested constructs stop at the depth bound. A choice the state does
        // not admit falls through to an addition rather than drawing again:
        // the stream wraps, so one that kept choosing it would never end.
        const nests = ctx.depth < max_depth;
        {
            switch (self.choices.below(16)) {
                0 => return .{ .add = self.value(ctx) },
                1, 2 => if (self.freeVec(ctx)) |owner| return self.mutation(ctx, owner),
                3 => if (self.freeMap(ctx)) |map| return self.mapMutation(ctx, map),
                4, 5 => if (nests) return self.walk(ctx),
                6 => if (nests) return self.view(ctx),
                7 => if (nests) return self.part(ctx),
                8 => if (nests) return self.element(ctx),
                9 => if (nests and self.setup.maps != 0) return self.lookup(ctx),
                10 => if (ctx.views.len != 0) {
                    const v = ctx.views[self.choices.below(@intCast(ctx.views.len))];
                    if (self.choices.odds(2)) return .{ .sum_view = v };
                    return .{ .peek = .{ .view = v, .id = self.id(), .walks = self.choices.odds(2), .calls = @intCast(self.choices.between(1, 2)) } };
                },
                11 => if (nests) return self.stepped(ctx),
                12 => if (nests) if (self.freeVec(ctx)) |owner| return self.grow(ctx, owner),
                13 => return .{ .bump = .{ .id = self.id(), .add = @intCast(self.choices.below(5)), .calls = @intCast(self.choices.between(2, 3)) } },
                14, 15 => if (nests) return .{ .loop = .{
                    .id = self.id(),
                    .form = if (self.choices.odds(2)) .range else .hand_written,
                    .count = @intCast(self.choices.between(1, 3)),
                    .body = try self.block(ctx.deeper()),
                } },
                else => unreachable,
            }
        }
        return .{ .add = self.value(ctx) };
    }

    fn mutation(self: *Gen, ctx: Context, owner: u8) !Stmt {
        return switch (self.choices.below(8)) {
            0, 1 => .{ .push = .{ .owner = owner, .value = self.value(ctx) } },
            2 => .{ .pop = .{ .owner = owner, .id = self.id() } },
            3 => .{ .remove = .{ .owner = owner, .index = @intCast(self.choices.below(4)), .id = self.id() } },
            4 => .{ .clear = owner },
            5 => .{ .truncate = .{ .owner = owner, .length = @intCast(self.choices.below(3)) } },
            6 => .{ .reserve = .{ .owner = owner, .additional = @intCast(self.choices.between(1, 16)) } },
            7 => .{ .write = .{ .owner = owner, .index = @intCast(self.choices.below(4)), .value = self.value(ctx) } },
            else => unreachable,
        };
    }

    fn mapMutation(self: *Gen, ctx: Context, map: u8) !Stmt {
        const key: u8 = @intCast(self.choices.below(5));
        return switch (self.choices.below(4)) {
            0 => .{ .insert = .{ .map = map, .key = key, .value = self.value(ctx) } },
            1 => .{ .remove_key = .{ .map = map, .key = key, .id = self.id() } },
            2 => .{ .merge = .{ .map = map, .key = key, .value = self.value(ctx) } },
            3 => .{ .update = .{ .map = map, .key = key, .add = @intCast(self.choices.below(5)), .id = self.id() } },
            else => unreachable,
        };
    }

    fn walkSource(self: *Gen, ctx: Context) Source {
        if (self.setup.maps != 0 and self.choices.odds(5)) return .{ .entries = 0 };
        if (ctx.views.len != 0 and self.choices.odds(3)) {
            return .{ .view = ctx.views[self.choices.below(@intCast(ctx.views.len))] };
        }
        const owner = self.aVec();
        return switch (self.choices.below(5)) {
            0, 1 => .{ .slice = owner },
            2 => .{ .mapped = .{ .owner = owner, .add = @intCast(self.choices.below(4)) } },
            3 => .{ .filtered = .{ .owner = owner, .above = @intCast(self.choices.below(6)) } },
            4 => .{ .mapped_filtered = .{ .owner = owner, .add = @intCast(self.choices.below(4)), .above = @intCast(self.choices.below(8)) } },
            else => unreachable,
        };
    }

    fn walk(self: *Gen, ctx: Context) !Stmt {
        const source = self.walkSource(ctx);
        const reads = !self.choices.odds(4);
        const item: Binder = .{ .id = self.id(), .kind = source.itemKind(), .prefix = if (reads) "item" else "_item" };
        var inner = ctx.deeper().observing(source.observed());
        // A map is walked in an order of its own, so what its body does must
        // not depend on which entry comes first: the entry is added to the
        // total, and nothing else reads it.
        if (reads and source != .entries) inner = try self.withScalar(inner, item);
        return .{ .walk = .{ .source = source, .item = item, .reads = reads, .body = try self.block(inner) } };
    }

    fn view(self: *Gen, ctx: Context) !Stmt {
        const v: View = .{ .id = self.id(), .prefix = "view", .owner = self.aVec() };
        const inner = try self.withView(ctx.deeper().observing(.{ .vec = v.owner }), v);
        return .{ .view = .{ .view = v, .body = try self.block(inner) } };
    }

    fn part(self: *Gen, ctx: Context) !Stmt {
        const v: View = .{ .id = self.id(), .prefix = "part", .owner = self.aVec() };
        const start: u8 = @intCast(self.choices.below(3));
        const count: u8 = @intCast(self.choices.below(3));
        const inner = try self.withView(ctx.deeper().observing(.{ .vec = v.owner }), v);
        return .{ .part = .{ .view = v, .start = start, .count = count, .body = try self.block(inner) } };
    }

    fn element(self: *Gen, ctx: Context) !Stmt {
        const owner = self.aVec();
        const item: Binder = .{ .id = self.id(), .kind = .borrowed, .prefix = "element" };
        const inner = try self.withScalar(ctx.deeper().observing(.{ .vec = owner }), item);
        return .{ .element = .{ .owner = owner, .index = @intCast(self.choices.below(4)), .item = item, .body = try self.block(inner) } };
    }

    fn lookup(self: *Gen, ctx: Context) !Stmt {
        const item: Binder = .{ .id = self.id(), .kind = .borrowed, .prefix = "found" };
        const inner = try self.withScalar(ctx.deeper().observing(.{ .map = 0 }), item);
        return .{ .lookup = .{ .map = 0, .key = @intCast(self.choices.below(5)), .item = item, .body = try self.block(inner) } };
    }

    fn stepped(self: *Gen, ctx: Context) !Stmt {
        const owner = self.aVec();
        const iterator: Stepped = switch (self.choices.below(3)) {
            0 => .{ .slice = owner },
            1 => .{ .mapped = .{ .owner = owner, .add = @intCast(self.choices.below(4)) } },
            2 => .{ .filtered = .{ .owner = owner, .above = @intCast(self.choices.below(6)) } },
            else => unreachable,
        };
        const inner = ctx.deeper().observing(.{ .vec = owner });
        var steps: std.ArrayList(Step) = .empty;
        const n = self.choices.between(1, 3);
        for (0..n) |_| {
            switch (self.choices.below(3)) {
                0 => try steps.append(self.gpa, .{ .next = self.id() }),
                1 => {
                    const item: Binder = .{ .id = self.id(), .kind = iterator.source().itemKind(), .prefix = "item" };
                    const walked = try self.withScalar(inner, item);
                    try steps.append(self.gpa, .{ .lent = .{
                        .item = item,
                        .stop = self.id(),
                        .limit = @intCast(self.choices.between(1, 3)),
                        .body = try self.block(walked),
                    } });
                },
                2 => try steps.append(self.gpa, .{ .stmts = try self.block(inner) }),
                else => unreachable,
            }
        }
        // A last `next` uses the iterator after every step before it, so the
        // observation is live across all of them.
        try steps.append(self.gpa, .{ .next = self.id() });
        return .{ .stepped = .{ .iterator = iterator, .id = self.id(), .steps = try steps.toOwnedSlice(self.gpa) } };
    }

    fn grow(self: *Gen, ctx: Context, owner: u8) !Stmt {
        // The body reads nothing but the vector it is lent, so it is written
        // from a context that has no scalars or views in scope.
        const body_ctx: Context = .{ .depth = ctx.depth + 1 };
        var body: std.ArrayList(Stmt) = .empty;
        const n = self.choices.between(1, 2);
        for (0..n) |_| {
            const s = try self.mutation(body_ctx, owner);
            try body.append(self.gpa, switch (s) {
                // A closure body has no `total` to add a popped value to, so
                // what it takes out is dropped.
                .pop, .remove => .{ .clear = owner },
                else => s,
            });
        }
        return .{ .grow = .{ .owner = owner, .id = self.id(), .body = try body.toOwnedSlice(self.gpa), .calls = @intCast(self.choices.between(1, 3)) } };
    }
};

const Error = std.mem.Allocator.Error;
const RenderError = Error || std.Io.Writer.Error;

/// The program's meaning: each owner's contents and the running total, as a
/// run of it computes them.
const Model = struct {
    gpa: std.mem.Allocator,
    vecs: [max_vecs]std.ArrayList(u64),
    maps: [max_maps]std.AutoArrayHashMapUnmanaged(u64, u64),
    total: u64 = 0,
    /// What each scalar binder holds while its scope runs.
    scalars: std.AutoHashMapUnmanaged(u32, u64) = .empty,
    /// The views live in the scope that runs now, and what each shows. A view
    /// of a part keeps its bounds from when it was matched out.
    views: std.AutoHashMapUnmanaged(u32, struct { owner: u8, start: usize, count: usize }) = .empty,

    fn init(gpa: std.mem.Allocator, setup: Setup) !Model {
        var model: Model = .{ .gpa = gpa, .vecs = @splat(.empty), .maps = @splat(.empty) };
        for (0..setup.vecs) |k| {
            for (setup.vec_values[k]) |v| try model.vecs[k].append(gpa, v);
        }
        for (0..setup.maps) |k| {
            for (setup.map_entries[k]) |e| try model.maps[k].put(gpa, e[0], e[1]);
        }
        return model;
    }

    fn value(self: *Model, v: Value) u64 {
        return switch (v) {
            .literal => |n| n,
            .binder => |b| self.scalars.get(b.id).?,
        };
    }

    fn bind(self: *Model, b: Binder, v: u64) !void {
        try self.scalars.put(self.gpa, b.id, v);
    }

    /// The items a source yields, in the order a walk sees them.
    fn items(self: *Model, source: Source) ![]const u64 {
        var out: std.ArrayList(u64) = .empty;
        switch (source) {
            .slice => |k| try out.appendSlice(self.gpa, self.vecs[k].items),
            .view => |v| try out.appendSlice(self.gpa, self.viewItems(v)),
            .mapped => |m| for (self.vecs[m.owner].items) |x| try out.append(self.gpa, x + m.add),
            .filtered => |f| for (self.vecs[f.owner].items) |x| if (x > f.above) try out.append(self.gpa, x),
            .mapped_filtered => |m| for (self.vecs[m.owner].items) |x| if (x + m.add > m.above) try out.append(self.gpa, x + m.add),
            .entries => |k| try out.appendSlice(self.gpa, self.maps[k].values()),
        }
        return out.items;
    }

    fn viewItems(self: *Model, v: View) []const u64 {
        const shown = self.views.get(v.id).?;
        return self.vecs[shown.owner].items[shown.start..][0..shown.count];
    }

    fn run(self: *Model, body: []const Stmt) Error!void {
        for (body) |s| try self.stmt(s);
    }

    fn stmt(self: *Model, s: Stmt) Error!void {
        switch (s) {
            .add => |v| self.total += self.value(v),
            .push => |p| try self.vecs[p.owner].append(self.gpa, self.value(p.value)),
            .pop => |p| if (self.vecs[p.owner].pop()) |x| {
                self.total += x;
            },
            .remove => |r| if (r.index < self.vecs[r.owner].items.len) {
                self.total += self.vecs[r.owner].orderedRemove(r.index);
            },
            .clear => |k| self.vecs[k].clearRetainingCapacity(),
            .truncate => |t| if (t.length < self.vecs[t.owner].items.len) {
                self.vecs[t.owner].shrinkRetainingCapacity(t.length);
            },
            .reserve => {},
            .write => |w| if (w.index < self.vecs[w.owner].items.len) {
                self.vecs[w.owner].items[w.index] = self.value(w.value);
            },
            .release => |k| self.vecs[k].clearRetainingCapacity(),
            .drain => |d| {
                // A drain hands items over from the last to the first.
                for (self.vecs[d.owner].items) |x| self.total += x;
                self.vecs[d.owner].clearRetainingCapacity();
            },
            .insert => |i| try self.maps[i.map].put(self.gpa, i.key, self.value(i.value)),
            .remove_key => |r| if (self.maps[r.map].fetchSwapRemove(r.key)) |entry| {
                self.total += entry.value;
            },
            .merge => |m| {
                const incoming = self.value(m.value);
                const slot = try self.maps[m.map].getOrPut(self.gpa, m.key);
                slot.value_ptr.* = if (slot.found_existing) slot.value_ptr.* + incoming else incoming;
            },
            .update => |u| if (self.maps[u.map].getPtr(u.key)) |held| {
                held.* += u.add;
            },
            .walk => |w| {
                const walked = try self.items(w.source);
                for (walked) |x| {
                    try self.bind(w.item, x);
                    if (w.reads) self.total += x;
                    try self.run(w.body);
                }
            },
            .view => |v| {
                try self.views.put(self.gpa, v.view.id, .{ .owner = v.view.owner, .start = 0, .count = self.vecs[v.view.owner].items.len });
                try self.run(v.body);
                self.total += sum(self.viewItems(v.view));
            },
            .part => |p| {
                const len = self.vecs[p.view.owner].items.len;
                if (@as(usize, p.start) + p.count <= len) {
                    try self.views.put(self.gpa, p.view.id, .{ .owner = p.view.owner, .start = p.start, .count = p.count });
                    try self.run(p.body);
                    self.total += sum(self.viewItems(p.view));
                }
            },
            .element => |e| if (e.index < self.vecs[e.owner].items.len) {
                const x = self.vecs[e.owner].items[e.index];
                try self.bind(e.item, x);
                self.total += x;
                try self.run(e.body);
                self.total += x;
            },
            .lookup => |l| if (self.maps[l.map].get(l.key)) |x| {
                try self.bind(l.item, x);
                self.total += x;
                try self.run(l.body);
                self.total += x;
            },
            .sum_view => |v| self.total += sum(self.viewItems(v)),
            .peek => |p| self.total += p.calls * sum(self.viewItems(p.view)),
            .stepped => |st| {
                const walked = try self.items(st.iterator.source());
                var at: usize = 0;
                for (st.steps) |step| switch (step) {
                    .next => if (at < walked.len) {
                        self.total += walked[at];
                        at += 1;
                    },
                    .lent => |lent| {
                        var taken: u8 = 0;
                        while (at < walked.len) {
                            const x = walked[at];
                            at += 1;
                            try self.bind(lent.item, x);
                            self.total += x;
                            try self.run(lent.body);
                            taken += 1;
                            if (taken == lent.limit) break;
                        }
                    },
                    .stmts => |body| try self.run(body),
                };
            },
            .grow => |g| for (0..g.calls) |_| try self.run(g.body),
            .bump => |b| self.total += @as(u64, b.add) * b.calls,
            .loop => |l| for (0..l.count) |_| try self.run(l.body),
        }
    }

    fn sum(values: []const u64) u64 {
        var s: u64 = 0;
        for (values) |x| s += x;
        return s;
    }
};

/// Writes the program and records its sites.
const Render = struct {
    gpa: std.mem.Allocator,
    out: std.Io.Writer.Allocating,
    subject: *const Program,
    sites: std.ArrayList(Site) = .empty,

    /// What the scope being written observes, for the sites inside it.
    const Scope = struct {
        depth: u32,
        in_loop: bool = false,
        observed: []const Target = &.{},

        /// The same scope with one more observation live in it.
        fn with(self: Scope, gpa: std.mem.Allocator, target: Target) !Scope {
            const observed = try gpa.alloc(Target, self.observed.len + 1);
            @memcpy(observed[0..self.observed.len], self.observed);
            observed[self.observed.len] = target;
            return .{ .depth = self.depth, .in_loop = self.in_loop, .observed = observed };
        }

        fn nested(self: Scope) Scope {
            return .{ .depth = self.depth + 1, .in_loop = self.in_loop, .observed = self.observed };
        }

        fn looping(self: Scope) Scope {
            var next = self.nested();
            next.in_loop = true;
            return next;
        }
    };

    fn w(self: *Render) *std.Io.Writer {
        return &self.out.writer;
    }

    fn indent(self: *Render, depth: u32) !void {
        for (0..depth) |_| try self.w().writeAll("    ");
    }

    fn line(self: *Render, depth: u32, comptime fmt: []const u8, args: anytype) !void {
        try self.indent(depth);
        try self.w().print(fmt, args);
        try self.w().writeByte('\n');
    }

    /// Records the start of the next line as a site for every observation
    /// live in `scope`.
    fn site(self: *Render, scope: Scope) !void {
        for (scope.observed) |target| try self.sites.append(self.gpa, .{
            .offset = self.out.written().len,
            .depth = scope.depth,
            .target = target,
            .in_loop = scope.in_loop,
        });
    }

    fn program(self: *Render, expected: u64) !void {
        const p = self.subject;
        if (p.setup.maps != 0) try self.w().writeAll("import std.collections\n");
        try self.w().writeAll("import std.mem\n\n");
        if (usesSumView(p.body)) try self.w().writeAll(
            \\fn sum_view(view: mem.Slice[UInt64]) -> UInt64 {
            \\    var sum: UInt64 = 0
            \\    for item in copy(view) {
            \\        sum += *item
            \\    }
            \\    sum
            \\}
            \\
            \\
        );
        try self.w().writeAll("fn main() -> UInt8 {\n");
        try self.line(1, "var total: UInt64 = 0", .{});
        for (0..p.setup.vecs) |k| {
            try self.line(1, "var v{d}: Vec[UInt64, mem.SystemAllocator] = Vec.new()", .{k});
            for (p.setup.vec_values[k]) |v| try self.line(1, "&v{d}.push({d}).unwrap()", .{ k, v });
        }
        for (0..p.setup.maps) |k| {
            try self.line(1, "var m{d}: collections.Map[UInt64, UInt64, mem.SystemAllocator] = collections.Map.new()", .{k});
            for (p.setup.map_entries[k]) |e| try self.line(1, "&m{d}.insert({d}, {d}).unwrap().release()", .{ k, e[0], e[1] });
        }
        const top: Scope = .{ .depth = 1 };
        for (p.body) |s| try self.stmt(top, s);
        for (0..p.setup.vecs) |k| try self.line(1, "v{d}.release()", .{k});
        for (0..p.setup.maps) |k| try self.line(1, "m{d}.release()", .{k});
        try self.line(1, "if total == {d} {{", .{expected});
        try self.line(2, "0", .{});
        try self.line(1, "}} else {{", .{});
        try self.line(2, "1", .{});
        try self.line(1, "}}", .{});
        try self.w().writeAll("}\n");
    }

    fn block(self: *Render, scope: Scope, body: []const Stmt) RenderError!void {
        for (body) |s| {
            try self.site(scope);
            try self.stmt(scope, s);
        }
        try self.site(scope);
    }

    fn value(self: *Render, v: Value) !void {
        switch (v) {
            .literal => |n| try self.w().print("{d}", .{n}),
            .binder => |b| try self.binder(b),
        }
    }

    fn binder(self: *Render, b: Binder) !void {
        switch (b.kind) {
            .borrowed => try self.w().print("*{s}_{d}", .{ b.prefix, b.id }),
            .owned => try self.w().print("{s}_{d}", .{ b.prefix, b.id }),
            .entry => try self.w().print("{s}_{d}.value", .{ b.prefix, b.id }),
        }
    }

    fn source(self: *Render, s: Source) !void {
        const mapper = "|sink item: borrow UInt64| -> UInt64 where carries() {{ *item + {d} }}";
        switch (s) {
            .slice => |k| try self.w().print("v{d}.as_slice()", .{k}),
            .view => |v| try self.w().print("copy({s}_{d})", .{ v.prefix, v.id }),
            .mapped => |m| try self.w().print("v{d}.as_slice().map(" ++ mapper ++ ")", .{ m.owner, m.add }),
            .filtered => |f| try self.w().print("v{d}.as_slice().filter(|item| *item > {d})", .{ f.owner, f.above }),
            .mapped_filtered => |m| try self.w().print("v{d}.as_slice().map(" ++ mapper ++ ").filter(|item| item > {d})", .{ m.owner, m.add, m.above }),
            .entries => |k| try self.w().print("m{d}.entries()", .{k}),
        }
    }

    fn stmt(self: *Render, scope: Scope, s: Stmt) RenderError!void {
        const d = scope.depth;
        switch (s) {
            .add => |v| {
                try self.indent(d);
                try self.w().writeAll("total += ");
                try self.value(v);
                try self.w().writeByte('\n');
            },
            .push => |p| {
                try self.indent(d);
                try self.w().print("&v{d}.push(", .{p.owner});
                try self.value(p.value);
                try self.w().writeAll(").unwrap()\n");
            },
            .pop => |p| try self.takeOut(d, "pop()", p.owner, p.id),
            .remove => |r| {
                try self.takeOut(d, try std.fmt.allocPrint(self.gpa, "remove({d})", .{r.index}), r.owner, r.id);
            },
            .clear => |k| try self.line(d, "&v{d}.clear()", .{k}),
            .truncate => |t| try self.line(d, "&v{d}.truncate({d})", .{ t.owner, t.length }),
            .reserve => |r| try self.line(d, "&v{d}.reserve({d}).unwrap()", .{ r.owner, r.additional }),
            .write => |wr| {
                try self.line(d, "if {d} < v{d}.length() {{", .{ wr.index, wr.owner });
                try self.indent(d + 1);
                try self.w().print("v{d}[{d}] = ", .{ wr.owner, wr.index });
                try self.value(wr.value);
                try self.w().writeByte('\n');
                try self.line(d, "}}", .{});
            },
            .release => |k| {
                try self.line(d, "v{d}.release()", .{k});
                try self.line(d, "v{d} = Vec.new()", .{k});
            },
            .drain => |dr| {
                try self.line(d, "var drain_{d} = v{d}.drain()", .{ dr.id, dr.owner });
                try self.line(d, "for taken in &drain_{d} {{", .{dr.id});
                try self.line(d + 1, "total += taken", .{});
                try self.line(d, "}}", .{});
                try self.line(d, "drain_{d}.release()", .{dr.id});
                try self.line(d, "v{d} = Vec.new()", .{dr.owner});
            },
            .insert => |i| {
                try self.indent(d);
                try self.w().print("&m{d}.insert({d}, ", .{ i.map, i.key });
                try self.value(i.value);
                try self.w().writeAll(").unwrap().release()\n");
            },
            .remove_key => |r| {
                try self.line(d, "match &m{d}.remove({d}) {{", .{ r.map, r.key });
                try self.line(d + 1, "Some(removed_{d}) => {{", .{r.id});
                try self.line(d + 2, "total += removed_{d}.value", .{r.id});
                try self.line(d + 1, "}},", .{});
                try self.line(d + 1, "None => {{}},", .{});
                try self.line(d, "}}", .{});
            },
            .merge => |m| {
                try self.indent(d);
                try self.w().print("&m{d}.merge({d}, ", .{ m.map, m.key });
                try self.value(m.value);
                try self.w().writeAll(", |sink held: UInt64, sink incoming: UInt64| held + incoming).unwrap()\n");
            },
            .update => |u| try self.line(d, "let _updated_{d} = &m{d}.update({d}, |sink held: UInt64| held + {d})", .{ u.id, u.map, u.key, u.add }),
            .walk => |wk| {
                try self.indent(d);
                try self.w().print("for {s}_{d} in ", .{ wk.item.prefix, wk.item.id });
                try self.source(wk.source);
                try self.w().writeAll(" {\n");
                const inner = try scope.looping().with(self.gpa, wk.source.observed());
                if (wk.reads) {
                    try self.indent(d + 1);
                    try self.w().writeAll("total += ");
                    try self.binder(wk.item);
                    try self.w().writeByte('\n');
                }
                try self.block(inner, wk.body);
                try self.line(d, "}}", .{});
            },
            .view => |v| {
                try self.line(d, "let {s}_{d} = v{d}.as_slice()", .{ v.view.prefix, v.view.id, v.view.owner });
                try self.block(try scope.with(self.gpa, .{ .vec = v.view.owner }), v.body);
                try self.line(d, "total += sum_view({s}_{d})", .{ v.view.prefix, v.view.id });
            },
            .part => |p| {
                try self.line(d, "match v{d}.as_slice().subspan({d}, {d}) {{", .{ p.view.owner, p.start, p.count });
                try self.line(d + 1, "Some({s}_{d}) => {{", .{ p.view.prefix, p.view.id });
                const inner = try scope.nested().nested().with(self.gpa, .{ .vec = p.view.owner });
                try self.block(inner, p.body);
                try self.line(d + 2, "total += sum_view({s}_{d})", .{ p.view.prefix, p.view.id });
                try self.line(d + 1, "}},", .{});
                try self.line(d + 1, "None => {{}},", .{});
                try self.line(d, "}}", .{});
            },
            .element => |e| {
                try self.line(d, "match v{d}.as_slice().get({d}) {{", .{ e.owner, e.index });
                try self.bodyOfSome(scope, e.item, .{ .vec = e.owner }, e.body);
                try self.line(d, "}}", .{});
            },
            .lookup => |l| {
                try self.line(d, "match m{d}.get({d}) {{", .{ l.map, l.key });
                try self.bodyOfSome(scope, l.item, .{ .map = l.map }, l.body);
                try self.line(d, "}}", .{});
            },
            .sum_view => |v| try self.line(d, "total += sum_view({s}_{d})", .{ v.prefix, v.id }),
            .peek => |p| {
                if (p.walks) {
                    try self.line(d, "let peek_{d} = [{s}_{d}] || {{", .{ p.id, p.view.prefix, p.view.id });
                    try self.line(d + 1, "var seen: UInt64 = 0", .{});
                    try self.line(d + 1, "for item in copy({s}_{d}) {{", .{ p.view.prefix, p.view.id });
                    try self.line(d + 2, "seen += *item", .{});
                    try self.line(d + 1, "}}", .{});
                    try self.line(d + 1, "seen", .{});
                    try self.line(d, "}}", .{});
                } else {
                    try self.line(d, "let peek_{d} = [{s}_{d}] || sum_view({s}_{d})", .{ p.id, p.view.prefix, p.view.id, p.view.prefix, p.view.id });
                }
                for (0..p.calls) |_| try self.line(d, "total += peek_{d}()", .{p.id});
            },
            .stepped => |st| try self.stepped(scope, st.iterator, st.id, st.steps),
            .grow => |g| {
                try self.line(d, "var grow_{d} = inout [inout v{d}] || {{", .{ g.id, g.owner });
                const body_scope: Scope = .{ .depth = d + 1, .in_loop = scope.in_loop };
                for (g.body) |b| try self.stmt(body_scope, b);
                try self.line(d, "}}", .{});
                // The lend lasts from the closure to its last call.
                const lent = try scope.with(self.gpa, .{ .vec = g.owner });
                for (0..g.calls) |k| {
                    if (k != 0) try self.site(lent);
                    try self.line(d, "&grow_{d}()", .{g.id});
                }
            },
            .bump => |b| {
                try self.line(d, "var bump_{d} = inout [inout total] || {{", .{b.id});
                try self.line(d + 1, "total += {d}", .{b.add});
                try self.line(d, "}}", .{});
                const lent = try scope.with(self.gpa, .total);
                for (0..b.calls) |k| {
                    if (k != 0) try self.site(lent);
                    try self.line(d, "&bump_{d}()", .{b.id});
                }
            },
            .loop => |l| switch (l.form) {
                .range => {
                    try self.line(d, "for _round_{d} in UInt64(0)..{d} {{", .{ l.id, l.count });
                    try self.block(scope.looping(), l.body);
                    try self.line(d, "}}", .{});
                },
                .hand_written => {
                    try self.line(d, "var round_{d}: UInt64 = 0", .{l.id});
                    try self.line(d, "while round_{d} < {d} {{", .{ l.id, l.count });
                    try self.block(scope.looping(), l.body);
                    try self.line(d + 1, "round_{d} += 1", .{l.id});
                    try self.line(d, "}}", .{});
                },
            },
        }
    }

    fn takeOut(self: *Render, d: u32, call: []const u8, owner: u8, id: u32) !void {
        try self.line(d, "match &v{d}.{s} {{", .{ owner, call });
        try self.line(d + 1, "Some(taken_{d}) => {{", .{id});
        try self.line(d + 2, "total += taken_{d}", .{id});
        try self.line(d + 1, "}},", .{});
        try self.line(d + 1, "None => {{}},", .{});
        try self.line(d, "}}", .{});
    }

    /// The `Some` arm of a borrowed element or value: its body, then a read
    /// of the borrow, so the borrow is live across the whole body.
    fn bodyOfSome(self: *Render, scope: Scope, item: Binder, observed: Target, body: []const Stmt) !void {
        const d = scope.depth;
        try self.line(d + 1, "Some({s}_{d}) => {{", .{ item.prefix, item.id });
        try self.indent(d + 2);
        try self.w().writeAll("total += ");
        try self.binder(item);
        try self.w().writeByte('\n');
        const inner = try scope.nested().nested().with(self.gpa, observed);
        try self.block(inner, body);
        try self.indent(d + 2);
        try self.w().writeAll("total += ");
        try self.binder(item);
        try self.w().writeByte('\n');
        try self.line(d + 1, "}},", .{});
        try self.line(d + 1, "None => {{}},", .{});
    }

    fn stepped(self: *Render, scope: Scope, iterator: Stepped, id: u32, steps: []const Step) !void {
        const d = scope.depth;
        try self.indent(d);
        try self.w().print("var steps_{d} = ", .{id});
        switch (iterator) {
            .slice => |k| try self.w().print("v{d}.as_slice().iterate()", .{k}),
            else => try self.source(iterator.source()),
        }
        try self.w().writeByte('\n');
        const owner = iterator.source().observed();
        const live = try scope.with(self.gpa, owner);
        const kind = iterator.source().itemKind();
        for (steps, 0..) |step, k| {
            if (k != 0) try self.site(live);
            switch (step) {
                .next => |n| {
                    const item: Binder = .{ .id = n, .kind = kind, .prefix = "next" };
                    try self.line(d, "match Iterator.next(&steps_{d}) {{", .{id});
                    try self.line(d + 1, "Some(next_{d}) => {{", .{n});
                    try self.indent(d + 2);
                    try self.w().writeAll("total += ");
                    try self.binder(item);
                    try self.w().writeByte('\n');
                    try self.line(d + 1, "}},", .{});
                    try self.line(d + 1, "None => {{}},", .{});
                    try self.line(d, "}}", .{});
                },
                .lent => |lent| {
                    try self.line(d, "var stop_{d}: UInt64 = 0", .{lent.stop});
                    try self.line(d, "for {s}_{d} in &steps_{d} {{", .{ lent.item.prefix, lent.item.id, id });
                    try self.indent(d + 1);
                    try self.w().writeAll("total += ");
                    try self.binder(lent.item);
                    try self.w().writeByte('\n');
                    var walked = live;
                    walked.depth = d + 1;
                    walked.in_loop = true;
                    try self.block(walked, lent.body);
                    try self.line(d + 1, "stop_{d} += 1", .{lent.stop});
                    try self.line(d + 1, "if stop_{d} == {d} {{", .{ lent.stop, lent.limit });
                    try self.line(d + 2, "break", .{});
                    try self.line(d + 1, "}}", .{});
                    try self.line(d, "}}", .{});
                },
                .stmts => |body| for (body) |s| {
                    try self.stmt(.{ .depth = d, .in_loop = scope.in_loop, .observed = live.observed }, s);
                    try self.site(live);
                },
            }
        }
    }
};

fn usesSumView(body: []const Stmt) bool {
    for (body) |s| switch (s) {
        .view, .part, .sum_view => return true,
        .peek => |p| if (!p.walks) return true,
        .walk => |w| if (usesSumView(w.body)) return true,
        .element => |e| if (usesSumView(e.body)) return true,
        .lookup => |l| if (usesSumView(l.body)) return true,
        .loop => |l| if (usesSumView(l.body)) return true,
        .stepped => |st| for (st.steps) |step| switch (step) {
            .next => {},
            .lent => |lent| if (usesSumView(lent.body)) return true,
            .stmts => |stmts| if (usesSumView(stmts)) return true,
        },
        else => {},
    };
    return false;
}

/// A generated program with one owner operation inserted at a site.
pub const Mutant = struct {
    text: []const u8,
    site: Site,
    operation: matrix.Operation,
};

/// How many mutants each generated program yields.
pub const mutants_per_program = 4;

/// The `ordinal`th mutant of a generated program, or null where it has no
/// site. The site and the operation are read from the program's own choice
/// stream, past where generation stopped, so a mutant replays from the same
/// bytes the program does.
pub fn mutant(gpa: std.mem.Allocator, generated: Generated, bytes: []const u8, ordinal: u32) !?Mutant {
    if (generated.sites.len == 0) return null;
    var choices: Choices = .{ .bytes = bytes, .at = generated.choices_read + 2 * ordinal };
    const site = generated.sites[choices.below(@intCast(generated.sites.len))];
    var operations: [std.enums.values(matrix.Operation).len]matrix.Operation = undefined;
    var n: u32 = 0;
    for (std.enums.values(matrix.Operation)) |operation| {
        if (operation.storage() != site.target.storage()) continue;
        // Consuming the owner inside a loop is refused whatever observes it.
        if (site.in_loop and operation.consumes()) continue;
        operations[n] = operation;
        n += 1;
    }
    const operation = operations[choices.below(n)];

    var owner: std.Io.Writer.Allocating = .init(gpa);
    try site.target.write(&owner.writer);
    const statements = try matrix.operationText(gpa, operation, owner.written());

    var out: std.Io.Writer.Allocating = .init(gpa);
    try out.writer.writeAll(generated.text[0..site.offset]);
    var lines = std.mem.splitScalar(u8, statements, '\n');
    while (lines.next()) |one| {
        for (0..site.depth) |_| try out.writer.writeAll("    ");
        try out.writer.writeAll(one);
        try out.writer.writeByte('\n');
    }
    try out.writer.writeAll(generated.text[site.offset..]);
    return .{ .text = try out.toOwnedSlice(), .site = site, .operation = operation };
}

test "a mutant inserts an operation on the owner its site observes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var made: usize = 0;
    for (0..32) |seed| {
        const bytes = try choicesFromSeed(gpa, seed);
        const generated = try generate(gpa, bytes);
        for (0..mutants_per_program) |k| {
            const m = (try mutant(gpa, generated, bytes, @intCast(k))) orelse continue;
            made += 1;
            try testing.expect(m.text.len > generated.text.len);
            try testing.expectEqual(m.operation.storage(), m.site.target.storage());
            try testing.expectEqualStrings(generated.text[0..m.site.offset], m.text[0..m.site.offset]);
        }
    }
    try testing.expect(made > 0);
}

test "every site starts a line inside the program's main" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sites: usize = 0;
    for (0..64) |seed| {
        const generated = try generate(gpa, try choicesFromSeed(gpa, seed));
        const main_at = std.mem.indexOf(u8, generated.text, "fn main()").?;
        for (generated.sites) |site| {
            try testing.expect(site.offset > main_at);
            try testing.expect(generated.text[site.offset - 1] == '\n');
        }
        sites += generated.sites.len;
    }
    // Observations are common enough that a run's mutants have somewhere to
    // go; a generator that stopped writing them would leave this at zero.
    try testing.expect(sites > 64);
}

test "every generated program and mutant parses whole" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    for (0..64) |seed| {
        const bytes = try choicesFromSeed(gpa, seed);
        const generated = try generate(gpa, bytes);
        var texts: std.ArrayList([]const u8) = .empty;
        try texts.append(gpa, generated.text);
        for (0..mutants_per_program) |k| {
            if (try mutant(gpa, generated, bytes, @intCast(k))) |m| try texts.append(gpa, m.text);
        }
        for (texts.items) |text| {
            const source: SourceText = .{ .path = "main.lin", .text = text };
            var sink = Sink.init(gpa);
            var interner: Interner = .empty;
            const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
            _ = try parse(gpa, &source, .from(0), tokens, &sink);
            if (sink.hasErrors()) {
                std.debug.print("seed {d} does not parse:\n{s}\n", .{ seed, text });
                return error.TestUnexpectedResult;
            }
        }
    }
}

/// How a program compiled in process against the checked library came out.
const Verdict = enum {
    /// Refused, and by the invalidation rule alone.
    refused_by_invalidation,
    /// Refused by some other rule as well, or instead.
    refused_otherwise,
    verified,
    unverified,
};

/// The rule that refuses an operation while an observation of its owner is
/// still to be used.
const invalidation_rule = "O-Borrow";

/// Compiles one program against the library and, where it is accepted, holds
/// the module lowering produced to the verifier.
fn compileAndVerify(gpa: std.mem.Allocator, prefix: *const loader.CheckedLibrary, text: []const u8) !Verdict {
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const files = [_]loader.InMemoryFile{.{ .path = "main.lin", .text = text }};
    var loaded = try prefix.loadFromMemory(gpa, &table, &sink, &interner, "main.lin", &files, .program, .borrow);
    try table.buildMaps(gpa);
    var settled = try prefix.checkProgram(gpa, std.heap.page_allocator, &loaded, &interner, &sink, .program);
    defer settled.deinit(gpa);
    const module = if (sink.hasErrors())
        null
    else
        try lowerProgram(gpa, &settled.expanded, &settled.res, &settled.typing, &settled.disposals, &sink, .program);
    if (module == null) {
        for (sink.items()) |d| {
            if (d.severity == .note) continue;
            const code = d.code orelse return .refused_otherwise;
            if (!std.mem.eql(u8, code.ruleName(), invalidation_rule)) return .refused_otherwise;
        }
        return .refused_by_invalidation;
    }
    return if (try verify(gpa, &module.?, &sink)) .verified else .unverified;
}

/// Property: the generator and the compiler agree, and the compiler refuses
/// every mutant. Every program the generator writes is accepted and lowers to
/// a module the verifier accepts. Every mutant uses an observation after an
/// operation that may move, grow or free its storage, so it is refused by the
/// invalidation rule alone; accepting one is the failure this exists to find.
///
/// This half runs in process, so a fuzzer can steer the choice stream. What
/// an accepted program does when it runs -- clean, and answering its model's
/// total -- is the soundness step's half, which builds what this accepts.
fn checkChoices(gpa: std.mem.Allocator, prefix: *const loader.CheckedLibrary, bytes: []const u8) !void {
    const generated = try generate(gpa, bytes);
    switch (try compileAndVerify(gpa, prefix, generated.text)) {
        .verified => {},
        .refused_by_invalidation, .refused_otherwise => {
            std.debug.print("{s}\n", .{generated.text});
            return error.AGeneratedStorageProgramWasRefused;
        },
        .unverified => {
            std.debug.print("{s}\n", .{generated.text});
            return error.AWellFormedModuleWasRefused;
        },
    }
    for (0..mutants_per_program) |k| {
        const m = (try mutant(gpa, generated, bytes, @intCast(k))) orelse break;
        switch (try compileAndVerify(gpa, prefix, m.text)) {
            .refused_by_invalidation => {},
            .refused_otherwise => {
                std.debug.print("{s}\n", .{m.text});
                return error.AMutantWasRefusedByAnotherRule;
            },
            .verified, .unverified => {
                std.debug.print("{s}\n", .{m.text});
                return error.AMutantWasAccepted;
            },
        }
    }
}

/// The fuzz target over `checkChoices`. The checked library is the fuzz
/// context, made once by the test: checking it is most of the cost of one
/// compilation, and a fuzzer calls the target many thousands of times.
fn fuzzStorage(prefix: *const loader.CheckedLibrary, smith: *std.testing.Smith) anyerror!void {
    var buf: [stream_length]u8 = undefined;
    const len = smith.slice(&buf);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try checkChoices(arena.allocator(), prefix, buf[0..len]);
}

test "fuzz-slow: a generated storage program is accepted and its mutants are refused" {
    const prefix = try loader.CheckedLibrary.init(testing.allocator);
    defer prefix.deinit();
    try std.testing.fuzz(@as(*const loader.CheckedLibrary, prefix), fuzzStorage, .{ .corpus = @import("fuzz_corpus").storage });
}

test "every storage program the fuzzer found still passes" {
    if (@import("fuzz_corpus").storage.len == 0) return;
    const prefix = try loader.CheckedLibrary.init(testing.allocator);
    defer prefix.deinit();
    for (@import("fuzz_corpus").storage) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try fuzzStorage(prefix, &smith);
    }
}

test "the fuzz property holds over seeds whose mutants keep a walk across an operation" {
    // Seeds 3, 10, 12, 13 and 15 each write a mutant that changes a vector or
    // a map while a walk over it continues, the shape a walk's own
    // invalidation is what refuses.
    const prefix = try loader.CheckedLibrary.init(testing.allocator);
    defer prefix.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for ([_]u64{ 3, 10, 12, 13, 15 }) |seed| {
        try checkChoices(arena.allocator(), prefix, try choicesFromSeed(arena.allocator(), seed));
    }
}

test "a stream that keeps choosing what the state refuses still ends" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Every byte picks the same production, including ones that nest past
    // the depth bound or need a map the program does not own.
    for ([_]u8{ 4, 9, 11, 14 }) |byte| {
        const bytes: [stream_length]u8 = @splat(byte);
        _ = try generate(arena.allocator(), &bytes);
    }
}
