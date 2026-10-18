const std = @import("std");
const testing = std.testing;

const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const ExprId = node.ExprId;
const StmtId = node.StmtId;
const DeclId = node.DeclId;
const Convention = node.Convention;
const BitTable = @import("../support/table.zig").BitTable;
const resolve_mod = @import("../sema/resolve.zig");
const BindingId = resolve_mod.BindingId;
const Resolution = resolve_mod.Resolution;
const Typing = @import("../sema/types.zig").Typing;
const Span = @import("../support/span.zig").Span;

pub const BindingBits = BitTable(BindingId);

pub const BlockId = enum(u32) {
    entry = 0,
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: usize) BlockId {
        return @enumFromInt(@as(u32, @intCast(i)));
    }

    pub fn index(self: BlockId) usize {
        return @intFromEnum(self);
    }
};

pub const BlockBits = BitTable(BlockId);

/// One binding's place on the stack of what is live.
pub const ScopeId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: usize) ScopeId {
        return @enumFromInt(@as(u32, @intCast(i)));
    }

    pub fn index(self: ScopeId) usize {
        return @intFromEnum(self);
    }
};

/// A binding, and everything that was live beneath it when it was declared.
///
/// The live stack is kept as a tree rather than copied, so that a scope exit
/// can name the stretch of it that ends instead of listing the bindings in
/// that stretch. A `?`, a `return` and a `break` each end every scope between
/// where they are written and where control lands, so a body of n early exits
/// over n live bindings lists n squared of them -- and every walk over the
/// graph pays for that list again.
///
/// Nodes are minted in the order the walk declares bindings, which is
/// depth-first: a node's subtree is therefore the contiguous run of indices
/// from it to `last`, which is what makes membership of a stretch a comparison
/// rather than a walk.
pub const Scope = struct {
    binding: BindingId,
    /// What was live beneath it, and `.none` at the bottom of a function's
    /// stack.
    outer: ScopeId,
    /// How many bindings are live at and beneath this one.
    depth: u32,
    /// The greatest index in this scope's subtree, itself where nothing was
    /// declared inside it.
    last: u32,
};

/// Where a value appears, which is what decides whether it moves.
///
/// Linearity adds a settlement obligation; it does not decide the position.
pub const Position = enum { reading, consuming };

/// A count of syntactically enclosing loops.
pub const LoopDepth = u16;

/// A binding and its projection depth for whole-binding move rules.
/// Observation dependencies intern the exact selected fields per function.
pub const Place = struct {
    root: BindingId,
    /// How many steps from the root. Moving a part is distinct from moving
    /// the whole binding, independently of which field that part names.
    depth: u32 = 0,

    pub fn isWhole(self: Place) bool {
        return self.depth == 0;
    }
};

pub const Projection = union(enum) {
    whole,
    field: @import("../support/interner.zig").StringId,
    payload: struct { variant: u32, index: u32 },
    element,
    /// One component of the element an owning loop takes each iteration, for
    /// a tuple pattern's binder.
    element_component: @import("../support/interner.zig").StringId,
    /// A lending loop whose checked indexing selects its element's place.
    index: ExprId,
};

/// One thing that happens to a place.
pub const Op = struct {
    tag: Tag,
    place: Place,
    /// Where it was written. Every message this pass emits points at one of
    /// these, which is the reason the graph carries names at all.
    at: ExprId,
    /// Whether this operation sits in a reading position. A `copied` op
    /// checks whether a copy has an effect; a captured field records whether
    /// it observes its source.
    reading: bool = false,
    /// Whether a closure-construction `value` operation lends its capture's
    /// source `inout`: the environment field observes the place exclusively.
    exclusive: bool = false,
    /// The value assigned or joined by a dependency-flow operation, or the
    /// place a `copied` operation reads.
    source: ExprId = .none,
    /// An assignment replaces an existing place; a declaration introduces it.
    replaces: bool = false,
    /// Which part a pattern or iteration binder receives, or the environment
    /// field a closure-construction `value` operation initializes.
    projection: Projection = .whole,
    /// The `defer`'s expression this operation was placed for, or `.none`
    /// where the program wrote the operation itself.
    ///
    /// One disposal is written and the schedule may reach a path where the
    /// value is already gone. A written consume of a moved place is [O-Move]
    /// and a placed one is nothing, so the two have to be told apart -- and
    /// where they sit is what tells them.
    ///
    /// Not defaulted, and neither is `exit`: a placement's operations are read
    /// as a contiguous run, so an operation inside one that says it is outside
    /// splits the run and the values after the split are judged on their own.
    /// A default is what lets a site be written that never says.
    schedule: ExprId,
    /// Which exit placed it. A schedule fires on some paths and not others, so
    /// what is cancelled is a *pair*: this expression, at this exit.
    exit: ExprId,
    /// The construct a transfer belongs to: the one whose completion closes it
    /// for a `consume` or a `transferred`, the one control left for an
    /// `escaped`. `ExprId.none` everywhere else, which is every transfer that
    /// hands a value over outright: a `let`, a `return`'s operand, a disposal.
    pending_for: ExprId = ExprId.none,
    /// How many loops enclose this operation. A move is rejected when it sits
    /// inside more loops than the binding it moves was declared in, which is
    /// the whole of the loop rule and needs no fixpoint to decide.
    loops: LoopDepth = 0,
    /// Which scopes a `dies` ends. Empty on every other operation.
    run: Run = .{},

    /// A stretch of the live stack, which is what one scope exit ends.
    pub const Run = struct {
        /// The innermost scope that ends, and the deepest: everything from
        /// here down to `mark` goes with it.
        top: ScopeId = .none,
        /// How many bindings the exit leaves live.
        mark: u32 = 0,
    };

    pub const Tag = enum {
        /// An expression result, with `source` set for a control-flow join.
        /// A field projection initializes one closure environment field from
        /// `source` before the following capture initializer is evaluated.
        value,
        /// A value crossing the function boundary.
        returned,
        /// Observed. Reading a moved place is the error; reading an
        /// initialised one is nothing.
        read,
        /// Taken. The place is moved afterwards, and reading it is an error.
        consume,
        /// A value no place names, yielded to whatever the expression sits in.
        ///
        /// A call's result, a literal, what a `?` takes out of an enum: some of
        /// those are made here and some existed already, and the difference
        /// does not matter to ownership. What matters is that no place names
        /// the value, so it changes no binding's state, nothing later can refer
        /// to it, and the expression that yielded it is the only name a message
        /// can give it.
        transferred,
        /// A pattern names a part without acquiring its ownership obligation.
        lent,
        /// Becomes initialised: a `let`, a parameter's arrival, an assignment
        /// refilling a hole.
        init,
        /// A `copy` of this place. Carries no state change -- a copy reads
        /// its source and yields something else -- and exists so the two rules
        /// about a pointless copy have somewhere to be asked.
        copied,
        /// A stretch of scopes ends here, named by `run` rather than by a
        /// place. A Linear binding still initialised at one is a leak, and
        /// this is the only operation that says where "still" is.
        dies,
        /// Taken apart and none of it named. A consuming `match` moves the
        /// value in, so by the arm it reads as disposed of -- indistinguishable
        /// from one given to something that takes it. This says the difference:
        /// the value was destroyed and nothing holds what it held.
        discarded,
        /// A field a structure literal writes, replacing the one its base
        /// held. The base was taken whole, so the replaced part is destroyed
        /// and nothing holds what it held. `at` is the field's label and
        /// `source` the base.
        replaced,
        /// A construct that takes several values has taken them. Every
        /// transfer opened by an operand of this construct closes here.
        ///
        /// The graph records where a value is given up and, without this,
        /// nothing about where it is received -- so the interval in which it
        /// is owned by neither is not something a walk could see.
        committed,
        /// Control leaves here, past a construct that has not completed. One
        /// of these per construct the jump escapes, outermost first.
        ///
        /// Which constructs a jump escapes is a question about where it was
        /// written -- a `break` leaves the loops between it and the one it
        /// names, and a `return` leaves everything -- so it is answered where
        /// that is known and recorded, rather than rediscovered from edges
        /// that no longer say which construct enclosed which. Whether anything
        /// was in flight when it happened is a separate question, asked of the
        /// transfers open at this point.
        escaped,
        /// The statement anchored at `at` ends, and so does every temporary
        /// it evaluated for a borrow. A value still borrowing one is used
        /// after the storage it observes is gone.
        temporaries_end,
        /// A refused construct names this place, and whether it would have
        /// taken the value is unknown: a call whose operation or callee was
        /// never found, or a closure refused for naming a binding it did not
        /// capture. An initialised place becomes unknown on this path, so
        /// neither a later use nor a scope ending with it held is reported
        /// there; every other path keeps what it knew.
        unsettled,
    };
};

/// A closure body naming a binding of the body around it that it did not
/// capture. `takes` is whether the body places the binding where it is
/// taken; `changes` whether it assigns it or lends it to be changed.
pub const Uncaptured = struct {
    lambda: ExprId,
    free: ExprId,
    takes: bool,
    changes: bool,
};

pub const OpRange = struct { start: u32, end: u32 };

pub const OpId = enum(u32) {
    _,

    pub fn at(i: u32) OpId {
        return @enumFromInt(i);
    }

    pub fn index(self: OpId) usize {
        return @intFromEnum(self);
    }
};

pub const OpList = std.MultiArrayList(Op);

pub const OpIds = struct {
    at: u32,
    end: u32,

    pub fn next(self: *OpIds) ?OpId {
        if (self.at == self.end) return null;
        defer self.at += 1;
        return OpId.at(self.at);
    }
};

fn emptyOps() OpList.Slice {
    var ops: OpList = .empty;
    return ops.toOwnedSlice();
}

/// A basic block: operations in order, then where control may go.
pub const Block = struct {
    ops: OpRange,
    /// Indices into the graph's edge array.
    edges: OpRange,
    /// The construct this block belongs to, so a message about the block --
    /// a merge, which has no operation of its own -- has somewhere to point.
    at: ExprId = ExprId.none,
};

/// One written deferred expression at the exit that runs it.
pub const Placement = struct { schedule: ExprId, exit: ExprId };

/// The ordered deferred expressions that ownership permits at each exit, and
/// what the program does with each place it names.
/// No scheduling, cancellation or move decision remains for lowering.
///
/// Storage is O(P + E + U), where P is the number of surviving placements, E
/// is the number of exits with schedules and U is the number of place uses
/// the program wrote. Lookup is expected O(1), followed
/// by one traversal of the expressions that exit actually runs.
pub const DisposalPlan = struct {
    expressions: []const ExprId = &.{},
    by_exit: std.AutoHashMapUnmanaged(ExprId, Range) = .empty,
    /// How the program wrote each place use that names a place ownership
    /// follows, or a constant's static storage. A use absent here is no place:
    /// a value the program computed on the spot.
    uses: std.AutoHashMapUnmanaged(ExprId, Use) = .empty,

    /// What a position does with the place it names.
    pub const Use = enum {
        /// Written in a consuming position: the value moves out of its place.
        taken,
        /// Written in a reading position, or a scalar snapshot of a consuming
        /// one: the value is copied out and the place stays held.
        read,
    };

    const Range = struct { start: u32, end: u32 };
    pub const empty: DisposalPlan = .{};

    pub fn init(
        gpa: std.mem.Allocator,
        placements: []const Placement,
        cancelled: *const std.AutoHashMapUnmanaged(Placement, void),
        ops: OpList.Slice,
        static_reads: *const std.AutoHashMapUnmanaged(ExprId, void),
    ) !DisposalPlan {
        var plan: DisposalPlan = .empty;
        errdefer plan.deinit(gpa);
        // A deferred expression is lowered at each exit that runs it, through
        // the same blits as any other expression, so a consume written inside
        // it is a take. Only the schedule's own root is excluded: a placed
        // disposal consumes where its schedule says, not where the program
        // wrote a place. A root-less read names no place, and a use that is
        // both taken and read was taken.
        for (ops.items(.tag), ops.items(.at), ops.items(.schedule), ops.items(.place)) |tag, at, schedule, place| {
            switch (tag) {
                .consume => if (at != schedule) try plan.uses.put(gpa, at, .taken),
                .read => if (place.root != .none) {
                    const use = try plan.uses.getOrPut(gpa, at);
                    if (!use.found_existing) use.value_ptr.* = .read;
                },
                else => {},
            }
        }
        var constants = static_reads.keyIterator();
        while (constants.next()) |at| {
            const use = try plan.uses.getOrPut(gpa, at.*);
            if (!use.found_existing) use.value_ptr.* = .read;
        }
        var expressions: std.ArrayList(ExprId) = .empty;
        defer expressions.deinit(gpa);
        var at: usize = 0;
        while (at < placements.len) {
            const exit = placements[at].exit;
            const start: u32 = @intCast(expressions.items.len);
            while (at < placements.len and placements[at].exit == exit) : (at += 1) {
                const placement = placements[at];
                if (!cancelled.contains(placement)) try expressions.append(gpa, placement.schedule);
            }
            const end: u32 = @intCast(expressions.items.len);
            if (end == start) continue;
            // Each syntax exit is visited once; deferred bodies cannot place
            // nested schedules while their enclosing schedule is being walked.
            std.debug.assert(!plan.by_exit.contains(exit));
            try plan.by_exit.put(gpa, exit, .{ .start = start, .end = end });
        }
        plan.expressions = try expressions.toOwnedSlice(gpa);
        return plan;
    }

    /// Copies two immutable plans into the attached expression domain. The
    /// mapping must preserve expression identity and point into the expanded
    /// program whose resolution and typing accompany the retained body set.
    /// Neither input is changed or borrowed by the returned plan.
    pub fn imported(
        gpa: std.mem.Allocator,
        cached: *const DisposalPlan,
        expressions: []const ExprId,
        fresh: *const DisposalPlan,
    ) (std.mem.Allocator.Error || error{InvalidDisposalImport})!DisposalPlan {
        var plan: DisposalPlan = .empty;
        errdefer plan.deinit(gpa);
        const total = std.math.add(usize, cached.expressions.len, fresh.expressions.len) catch return error.OutOfMemory;
        if (total > std.math.maxInt(u32)) return error.OutOfMemory;
        const combined = try gpa.alloc(ExprId, total);
        plan.expressions = combined;
        for (cached.expressions, combined[0..cached.expressions.len]) |old, *new| {
            new.* = try relocatedExpression(expressions, old);
        }
        @memcpy(combined[cached.expressions.len..], fresh.expressions);
        var old_exits = cached.by_exit.iterator();
        while (old_exits.next()) |entry| {
            const exit = try relocatedExpression(expressions, entry.key_ptr.*);
            const inserted = try plan.by_exit.getOrPut(gpa, exit);
            if (inserted.found_existing) return error.InvalidDisposalImport;
            inserted.value_ptr.* = entry.value_ptr.*;
        }
        const offset: u32 = @intCast(cached.expressions.len);
        var new_exits = fresh.by_exit.iterator();
        while (new_exits.next()) |entry| {
            const inserted = try plan.by_exit.getOrPut(gpa, entry.key_ptr.*);
            if (inserted.found_existing) return error.InvalidDisposalImport;
            inserted.value_ptr.* = .{ .start = offset + entry.value_ptr.start, .end = offset + entry.value_ptr.end };
        }
        var old_uses = cached.uses.iterator();
        while (old_uses.next()) |entry| try plan.uses.put(gpa, try relocatedExpression(expressions, entry.key_ptr.*), entry.value_ptr.*);
        var new_uses = fresh.uses.iterator();
        while (new_uses.next()) |entry| try plan.uses.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
        return plan;
    }

    fn relocatedExpression(expressions: []const ExprId, old: ExprId) error{InvalidDisposalImport}!ExprId {
        if (old == .none or old.index() >= expressions.len) return error.InvalidDisposalImport;
        const new = expressions[old.index()];
        if (new == .none) return error.InvalidDisposalImport;
        return new;
    }

    pub fn schedulesAt(self: *const DisposalPlan, exit: ExprId) []const ExprId {
        const range = self.by_exit.get(exit) orelse return &.{};
        return self.expressions[range.start..range.end];
    }

    /// Whether the program wrote `use` in a consuming position, so the value
    /// it names is moved out of its place.
    pub fn takes(self: *const DisposalPlan, use: ExprId) bool {
        return (self.uses.get(use) orelse return false) == .taken;
    }

    /// Whether the program wrote `use` as a place it only reads, so the value
    /// is copied out of a place that stays held: a binding's place in a
    /// reading position, or a constant's static storage in any.
    pub fn reads(self: *const DisposalPlan, use: ExprId) bool {
        return (self.uses.get(use) orelse return false) == .read;
    }

    pub fn deinit(self: *DisposalPlan, gpa: std.mem.Allocator) void {
        gpa.free(self.expressions);
        self.by_exit.deinit(gpa);
        self.uses.deinit(gpa);
        self.* = undefined;
    }
};

test "disposal imports relocate exits and preserve schedule order" {
    const gpa = testing.allocator;
    const cancelled: std.AutoHashMapUnmanaged(Placement, void) = .empty;
    var cached_ops: OpList = .empty;
    defer cached_ops.deinit(gpa);
    try cached_ops.append(gpa, .{ .tag = .consume, .place = .{ .root = .none }, .at = .at(5), .schedule = .none, .exit = .none });
    try cached_ops.append(gpa, .{ .tag = .read, .place = .{ .root = .none }, .at = .at(6), .schedule = .none, .exit = .none });
    try cached_ops.append(gpa, .{ .tag = .consume, .place = .{ .root = .none }, .at = .at(7), .schedule = .at(3), .exit = .at(10) });
    try cached_ops.append(gpa, .{ .tag = .consume, .place = .{ .root = .none }, .at = .at(3), .schedule = .at(3), .exit = .at(10) });
    try cached_ops.append(gpa, .{ .tag = .read, .place = .{ .root = @enumFromInt(1) }, .at = .at(8), .schedule = .none, .exit = .none });
    try cached_ops.append(gpa, .{ .tag = .read, .place = .{ .root = @enumFromInt(1) }, .at = .at(5), .schedule = .none, .exit = .none });
    var fresh_ops: OpList = .empty;
    defer fresh_ops.deinit(gpa);
    try fresh_ops.append(gpa, .{ .tag = .consume, .place = .{ .root = .none }, .at = .at(95), .schedule = .none, .exit = .none });
    try fresh_ops.append(gpa, .{ .tag = .read, .place = .{ .root = @enumFromInt(1) }, .at = .at(92), .schedule = .none, .exit = .none });
    var statics: std.AutoHashMapUnmanaged(ExprId, void) = .empty;
    defer statics.deinit(gpa);
    try statics.put(gpa, .at(4), {});
    const no_statics: std.AutoHashMapUnmanaged(ExprId, void) = .empty;
    var cached = try DisposalPlan.init(gpa, &.{
        .{ .exit = .at(10), .schedule = .at(3) },
        .{ .exit = .at(10), .schedule = .at(4) },
        .{ .exit = .at(20), .schedule = .at(8) },
    }, &cancelled, cached_ops.slice(), &statics);
    defer cached.deinit(gpa);
    var fresh = try DisposalPlan.init(gpa, &.{.{ .exit = .at(90), .schedule = .at(91) }}, &cancelled, fresh_ops.slice(), &no_statics);
    defer fresh.deinit(gpa);
    var expressions: [21]ExprId = @splat(.none);
    expressions[5] = .at(105);
    expressions[7] = .at(107);
    expressions[3] = .at(103);
    expressions[4] = .at(104);
    expressions[8] = .at(108);
    expressions[10] = .at(110);
    expressions[20] = .at(120);
    var combined = try DisposalPlan.imported(gpa, &cached, &expressions, &fresh);
    defer combined.deinit(gpa);
    try testing.expectEqualSlices(ExprId, &.{ .at(103), .at(104) }, combined.schedulesAt(.at(110)));
    try testing.expectEqualSlices(ExprId, &.{.at(108)}, combined.schedulesAt(.at(120)));
    try testing.expectEqualSlices(ExprId, &.{.at(91)}, combined.schedulesAt(.at(90)));
    try testing.expectEqual(@as(usize, 0), combined.schedulesAt(.at(10)).len);
    try testing.expect(cached.takes(.at(5)));
    try testing.expect(!cached.takes(.at(6)));
    try testing.expect(cached.takes(.at(7)));
    try testing.expect(!cached.takes(.at(3)));
    try testing.expect(combined.takes(.at(105)));
    try testing.expect(combined.takes(.at(107)));
    try testing.expect(combined.takes(.at(95)));
    try testing.expect(!combined.takes(.at(5)));
    try testing.expect(!combined.takes(.at(6)));
    // A read of a binding's place is a use, a read that names no place is not,
    // a place both read and taken was taken, and a constant is read.
    try testing.expect(cached.reads(.at(8)) and !cached.takes(.at(8)));
    try testing.expect(!cached.reads(.at(6)) and !cached.takes(.at(6)));
    try testing.expect(cached.takes(.at(5)) and !cached.reads(.at(5)));
    try testing.expect(cached.reads(.at(4)));
    try testing.expect(combined.reads(.at(108)) and combined.reads(.at(104)) and combined.reads(.at(92)));
    try testing.expect(!combined.reads(.at(105)) and combined.takes(.at(105)));
    try testing.expectEqualSlices(ExprId, &.{ .at(3), .at(4) }, cached.schedulesAt(.at(10)));

    expressions[20] = .at(110);
    try testing.expectError(error.InvalidDisposalImport, DisposalPlan.imported(gpa, &cached, &expressions, &fresh));
    expressions[20] = .at(120);
    expressions[10] = .at(90);
    try testing.expectError(error.InvalidDisposalImport, DisposalPlan.imported(gpa, &cached, &expressions, &fresh));
    expressions[10] = .none;
    try testing.expectError(error.InvalidDisposalImport, DisposalPlan.imported(gpa, &cached, &expressions, &fresh));
    try testing.expectError(error.InvalidDisposalImport, DisposalPlan.imported(gpa, &cached, &.{}, &fresh));
}

/// Exact attached declarations whose body, nested closures, resolution and
/// typing are unchanged from a successful ownership check. Membership cannot
/// be inferred from a library flag: generated application bodies remain new.
/// The snapshot and mapping are borrowed only for the continuation call.
pub const CheckedOwnership = struct {
    declarations: *const std.AutoHashMapUnmanaged(DeclId, void),
    disposals: *const DisposalPlan,
    expressions: []const ExprId,
};

/// What the ownership pass walks.
///
/// A graph rather than an instruction language: nothing consumes it and
/// nothing is lowered from it. The edges are the entire reason it exists —
/// the syntax tree has names and no edges, MIR has edges and no names, and a
/// pass that must say *which name* on *which path* needs both at once.
pub const Cfg = struct {
    /// One per function, in declaration order among the program's functions.
    functions: []const Function,
    blocks: []const Block,
    ops: OpList.Slice,
    edges: []const BlockId,
    /// Whether reaching the end of each block leaves the function. An exit
    /// block is where `O-Leak` and `O-Reinit` are asked.
    exits: BlockBits.Frozen,
    /// How many loops enclosed each binding's declaration, by `BindingId`. A
    /// binding declared inside a loop is fresh on every iteration, so moving
    /// it there moves a different value each time.
    declared_in_loops: []const LoopDepth,
    /// Which bindings are lends: `match read`, `let read`, `for read`, and
    /// `for inout` binders, which name parts or elements of a value the
    /// construct did not take. Taking one takes what the value's owner still
    /// holds.
    lends: BindingBits.Frozen,
    /// Which lends last until their last use rather than until the construct
    /// that lent them ends: `let read` binders. No construct around them keeps
    /// the place they name from changing, so each use of one is checked
    /// against that place instead.
    lasting_lends: BindingBits.Frozen = .empty,
    /// Every live stack the walk stood on, as one tree.
    scopes: []const Scope,
    /// Which node of it each binding holds, by `BindingId`. `.none` for a
    /// name no scope ever held: a function or a type, which are not values,
    /// and a parameter whose value the callee was not given.
    scope_of: []const ScopeId,
    /// Written schedules in execution order, grouped by the exit that places them.
    placements: []const Placement = &.{},
    /// The statement each borrowed temporary belongs to, named by the
    /// expression that anchors the statement's `temporaries_end`. Sized by
    /// the program's borrowed temporaries, which are the values that are
    /// borrowed where they are written without being places.
    temporary_statements: std.AutoHashMapUnmanaged(ExprId, ExprId) = .empty,
    /// The uses of a constant's static storage, which has no state for an
    /// operation to track and is read wherever it is written. Sized by the
    /// program's uses of constants.
    static_reads: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// Closures refused for naming a binding they did not capture, in the
    /// order they were met, with what their bodies do with it. Sized by the
    /// refused closures, which is normally none.
    uncaptured: []const Uncaptured = &.{},

    pub fn deinit(self: *Cfg, gpa: std.mem.Allocator) void {
        // A function's `inouts` is the one allocation the graph holds that is
        // not one of its own arrays, so it is the one a caller freeing the
        // graph cannot free by freeing them.
        for (self.functions) |*f| f.deinitOne(gpa);
        gpa.free(self.functions);
        gpa.free(self.blocks);
        self.ops.deinit(gpa);
        gpa.free(self.edges);
        self.exits.deinit(gpa);
        gpa.free(self.declared_in_loops);
        self.lends.deinit(gpa);
        self.lasting_lends.deinit(gpa);
        gpa.free(self.uncaptured);
        gpa.free(self.scopes);
        gpa.free(self.scope_of);
        gpa.free(self.placements);
        self.temporary_statements.deinit(gpa);
        self.static_reads.deinit(gpa);
        self.* = undefined;
    }

    pub fn opsOf(_: *const Cfg, b: Block) OpIds {
        return .{ .at = b.ops.start, .end = b.ops.end };
    }

    pub fn opTag(self: *const Cfg, id: OpId) Op.Tag {
        return self.ops.items(.tag)[id.index()];
    }

    pub fn opPlace(self: *const Cfg, id: OpId) Place {
        return self.ops.items(.place)[id.index()];
    }

    pub fn opAt(self: *const Cfg, id: OpId) ExprId {
        return self.ops.items(.at)[id.index()];
    }

    pub fn opReading(self: *const Cfg, id: OpId) bool {
        return self.ops.items(.reading)[id.index()];
    }

    pub fn opSchedule(self: *const Cfg, id: OpId) ExprId {
        return self.ops.items(.schedule)[id.index()];
    }

    pub fn opExit(self: *const Cfg, id: OpId) ExprId {
        return self.ops.items(.exit)[id.index()];
    }

    pub fn opPendingFor(self: *const Cfg, id: OpId) ExprId {
        return self.ops.items(.pending_for)[id.index()];
    }

    pub fn opLoops(self: *const Cfg, id: OpId) LoopDepth {
        return self.ops.items(.loops)[id.index()];
    }

    pub fn opRun(self: *const Cfg, id: OpId) Op.Run {
        return self.ops.items(.run)[id.index()];
    }

    pub fn edgesOf(self: *const Cfg, b: Block) []const BlockId {
        return self.edges[b.edges.start..b.edges.end];
    }

    /// The function's blocks in reverse postorder from its entry.
    ///
    /// A block's index is the order lowering minted it, and a merge is minted
    /// before the arms that reach it, so index order runs against the flow: a
    /// sweep carries what it learns one block per pass and a chain of `if`s
    /// needs one sweep each. In reverse postorder every block on a path is
    /// reached before the blocks it reaches, so one sweep carries a
    /// straight-line chain end to end and only a back edge needs another.
    ///
    /// Returned indexes are relative to this function. Unreachable blocks are
    /// absent. The walk uses O(blocks + edges) time and O(blocks) storage.
    pub fn reversePostorder(
        self: *const Cfg,
        gpa: std.mem.Allocator,
        f: *const Function,
    ) std.mem.Allocator.Error![]u32 {
        const count = f.blocks.end - f.blocks.start;
        const seen = try gpa.alloc(bool, count);
        defer gpa.free(seen);
        @memset(seen, false);

        var order: std.ArrayList(u32) = try .initCapacity(gpa, count);
        errdefer order.deinit(gpa);

        // An explicit stack: the graph is as deep as the source nests, and
        // recursion here would put a program's nesting on the compiler's.
        const Frame = struct { block: u32, next: usize };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(gpa);

        const first: u32 = @intCast(f.entry.index() - f.blocks.start);
        seen[first] = true;
        try stack.append(gpa, .{ .block = first, .next = 0 });
        while (stack.items.len > 0) {
            const at = stack.items.len - 1;
            const block = stack.items[at].block;
            const edges = self.edgesOf(self.blocks[f.blocks.start + block]);

            if (stack.items[at].next < edges.len) {
                const edge = edges[stack.items[at].next];
                stack.items[at].next += 1;
                if (edge == .none) continue;
                const to: u32 = @intCast(edge.index() - f.blocks.start);
                if (!seen[to]) {
                    seen[to] = true;
                    // Appended after the index is read back, never through a
                    // pointer into the stack: appending may move it.
                    try stack.append(gpa, .{ .block = to, .next = 0 });
                }
                continue;
            }

            // Postorder: a block is placed once every block it reaches is.
            order.appendAssumeCapacity(block);
            _ = stack.pop();
        }

        std.mem.reverse(u32, order.items);
        return order.toOwnedSlice(gpa);
    }

    pub fn isExit(self: *const Cfg, block: BlockId) bool {
        return self.exits.get(block);
    }

    pub fn isLend(self: *const Cfg, b: BindingId) bool {
        return self.lends.get(b);
    }

    pub fn isLastingLend(self: *const Cfg, b: BindingId) bool {
        return self.lasting_lends.get(b);
    }

    /// Whether a scope exit is where `b`'s scope ends.
    ///
    /// The one place that answers it, because it is asked twice about the same
    /// exit: once of the operations after a `copy` and again of every block
    /// reachable from it, and a rule with two implementations is a rule that
    /// drifts.
    ///
    /// A stretch of the live stack is the ancestors of its top, so `b` is in
    /// it when its own node is deep enough and the top sits inside its
    /// subtree. Depth alone would answer for a binding of a sibling scope that
    /// happens to sit at the same height.
    pub fn endsScopeOf(self: *const Cfg, run: Op.Run, b: BindingId) bool {
        if (run.top == .none) return false;
        if (b.index() >= self.scope_of.len) return false;
        const held = self.scope_of[b.index()];
        if (held == .none) return false;

        const scope = self.scopes[held.index()];
        if (scope.depth <= run.mark) return false;
        return held.index() <= run.top.index() and run.top.index() <= scope.last;
    }
};

/// One function's graph, and what its parameters promised.
pub const Function = struct {
    /// The declaration this graph represents, or none for a closure.
    decl: DeclId,
    /// The lambda this graph represents, or none for a declaration.
    lambda: ExprId = .none,
    /// The declaration whose contextual constraints apply inside this body.
    owner: DeclId,
    entry: BlockId,
    /// The normalized callable boundary and parameter order, including closures.
    signature: @import("../sema/types.zig").TypeId = .poison,
    parameters: []const BindingId = &.{},
    /// The blocks belonging to this function, so an analysis can iterate one
    /// function without walking the whole program.
    blocks: OpRange,
    /// The live-scope nodes belonging to this function.
    scopes: OpRange,
    /// The bindings of this function's `inout` parameters, which must be
    /// initialised on every path to an exit.
    inouts: []const BindingId,
    /// Whether the result's contract was left undecided because inference
    /// found several sources. The ambiguity is already reported, so the body
    /// is not checked against the empty contract that stands in for it.
    contract_declined: bool = false,
    /// The parameter whose carrier type supplied the contract of a function
    /// that wrote no clause, for the report of a body that does not keep it.
    default_carrier: ?u32 = null,

    pub fn deinitOne(self: *const Function, gpa: std.mem.Allocator) void {
        gpa.free(self.inouts);
    }
};

/// Whether control leaves at `exit` through a jump written in the source:
/// a `return`, `break`, `continue` or `?`.
pub fn leavesExplicitly(ast: *const Ast, exit: ExprId) bool {
    return switch (ast.exprTag(exit)) {
        .return_, .break_, .continue_, .try_ => true,
        else => false,
    };
}

/// Where a label about leaving at `exit` points: the keyword or `?` a jump
/// is written with, the closing brace of a block that ends, and the whole
/// expression of a scope that is not a block.
pub fn exitSpan(ast: *const Ast, exit: ExprId) Span {
    if (leavesExplicitly(ast, exit)) return ast.tokenSpan(ast.exprMain(exit));
    if (ast.exprTag(exit) != .block) return ast.exprSpan(exit);
    // The token range runs through trailing comments, so the brace is the
    // last token that is not trivia.
    const span = ast.exprExtent(exit);
    if (span.end > span.start) return .{ .start = span.end - 1, .end = span.end };
    return span;
}

test "a block's exit is its closing brace and a jump's is its keyword" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text = "fn main() -> UInt8 { loop { break } 0 } // done";
    const Sink = @import("../diagnostics/sink.zig").Sink;
    var sink = Sink.init(gpa);
    var interner: @import("../support/interner.zig").Interner = .empty;
    const source: @import("../support/source.zig").Source = .{ .path = "exit.lin", .text = text };
    const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
    var seen_block = false;
    var seen_break = false;
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        const span = exitSpan(&ast, id);
        switch (ast.exprTag(id)) {
            .block => if (std.mem.eql(u8, text[span.start..span.end], "}")) {
                seen_block = true;
            },
            .break_ => {
                try testing.expect(leavesExplicitly(&ast, id));
                try testing.expectEqualStrings("break", text[span.start..span.end]);
                seen_break = true;
            },
            else => {},
        }
    }
    try testing.expect(seen_block and seen_break);
}

test "operation ranges walk typed column entries" {
    var building: OpList = .empty;
    try building.append(testing.allocator, .{
        .tag = .read,
        .place = .{ .root = BindingId.at(2) },
        .at = ExprId.at(4),
        .schedule = .none,
        .exit = .none,
    });
    try building.append(testing.allocator, .{
        .tag = .consume,
        .place = .{ .root = BindingId.at(3), .depth = 1 },
        .at = ExprId.at(5),
        .loops = 2,
        .schedule = ExprId.at(7),
        .exit = ExprId.at(8),
    });

    var cfg: Cfg = .{
        .functions = &.{},
        .blocks = &.{.{ .ops = .{ .start = 0, .end = 2 }, .edges = .{ .start = 0, .end = 0 } }},
        .ops = building.toOwnedSlice(),
        .edges = &.{},
        .exits = .empty,
        .declared_in_loops = &.{},
        .lends = .empty,
        .scopes = &.{},
        .scope_of = &.{},
    };
    defer cfg.ops.deinit(testing.allocator);

    var ids = cfg.opsOf(cfg.blocks[0]);
    const first = ids.next().?;
    const second = ids.next().?;
    try testing.expectEqual(Op.Tag.read, cfg.opTag(first));
    try testing.expectEqual(BindingId.at(2), cfg.opPlace(first).root);
    try testing.expectEqual(Op.Tag.consume, cfg.opTag(second));
    try testing.expectEqual(@as(u32, 1), cfg.opPlace(second).depth);
    try testing.expectEqual(@as(LoopDepth, 2), cfg.opLoops(second));
    try testing.expectEqual(ExprId.at(7), cfg.opSchedule(second));
    try testing.expectEqual(ExprId.at(8), cfg.opExit(second));
    try testing.expectEqual(@as(?OpId, null), ids.next());
}

test "ownership loop depths use their bounded domain" {
    comptime {
        if (@FieldType(Op, "loops") != LoopDepth) @compileError("Op.loops must use LoopDepth");
        if (@typeInfo(@FieldType(Cfg, "declared_in_loops")).pointer.child != LoopDepth) {
            @compileError("declaration loop depths must use LoopDepth");
        }
    }
    try testing.expectEqual(@as(usize, 2), @sizeOf(LoopDepth));
}

test "a place is whole only when nothing has been selected from it" {
    const whole: Place = .{ .root = BindingId.at(0) };
    const part: Place = .{ .root = BindingId.at(0), .depth = 1 };

    try testing.expect(whole.isWhole());
    try testing.expect(!part.isWhole());
    // Same root, different places: a move takes the whole binding, so the two
    // must not compare equal.
    try testing.expectEqual(whole.root, part.root);
}

test "block exit state is stored outside the row" {
    try testing.expect(!@hasField(Block, "exits"));
    try testing.expectEqual(@as(usize, 20), @sizeOf(Block));
    try testing.expectEqual(@as(usize, 4), @alignOf(Block));
    try testing.expect(@FieldType(Cfg, "exits") == BlockBits.Frozen);
}

test "O-Reinit block exits are independent from outgoing edges" {
    const blocks = [_]Block{
        .{
            .ops = .{ .start = 0, .end = 0 },
            .edges = .{ .start = 0, .end = 0 },
        },
        .{
            .ops = .{ .start = 0, .end = 0 },
            .edges = .{ .start = 0, .end = 0 },
        },
    };
    var exits = try BlockBits.initEmpty(testing.allocator, blocks.len);
    errdefer exits.deinit(testing.allocator);
    exits.set(.at(0), true);

    var cfg: Cfg = .{
        .functions = &.{},
        .blocks = &blocks,
        .ops = emptyOps(),
        .edges = &.{},
        .exits = exits.freeze(),
        .declared_in_loops = &.{},
        .lends = .empty,
        .scopes = &.{},
        .scope_of = &.{},
    };
    defer cfg.exits.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 0), cfg.edgesOf(blocks[0]).len);
    try testing.expectEqual(@as(usize, 0), cfg.edgesOf(blocks[1]).len);
    try testing.expect(cfg.isExit(.at(0)));
    try testing.expect(!cfg.isExit(.at(1)));
    try testing.expect(!cfg.isExit(.none));
}

test "a scope exit ends the scopes above its mark and no sibling of them" {
    // Two bindings in one scope and a third in a sibling of it, which is the
    // shape depth alone cannot tell apart: the sibling sits at the same height
    // as the first, and its scope has already ended where this exit stands.
    const scopes = [_]Scope{
        .{ .binding = BindingId.at(0), .outer = .none, .depth = 1, .last = 1 },
        .{ .binding = BindingId.at(1), .outer = .at(0), .depth = 2, .last = 1 },
        .{ .binding = BindingId.at(2), .outer = .none, .depth = 1, .last = 2 },
    };
    const scope_of = [_]ScopeId{ .at(0), .at(1), .at(2) };
    const cfg: Cfg = .{
        .functions = &.{},
        .blocks = &.{},
        .ops = emptyOps(),
        .edges = &.{},
        .exits = .empty,
        .declared_in_loops = &.{},
        .lends = .empty,
        .scopes = &scopes,
        .scope_of = &scope_of,
    };

    const exit: Op = .{
        .tag = .dies,
        .place = .{ .root = BindingId.none },
        .at = ExprId.none,
        .schedule = ExprId.none,
        .exit = ExprId.none,
        .run = .{ .top = .at(1), .mark = 0 },
    };

    try testing.expect(cfg.endsScopeOf(exit.run, BindingId.at(0)));
    try testing.expect(cfg.endsScopeOf(exit.run, BindingId.at(1)));
    try testing.expect(!cfg.endsScopeOf(exit.run, BindingId.at(2)));
    try testing.expect(!cfg.endsScopeOf(exit.run, BindingId.none));
}

test "reverse postorder visits diamond arms before their join" {
    const gpa = testing.allocator;
    const empty: Block = .{ .ops = .{ .start = 0, .end = 0 }, .edges = .{ .start = 0, .end = 0 } };
    var blocks = [_]Block{empty} ** 8;
    blocks[2].edges = .{ .start = 0, .end = 2 };
    blocks[3].edges = .{ .start = 2, .end = 3 };
    blocks[4].edges = .{ .start = 3, .end = 4 };
    blocks[5].edges = .{ .start = 4, .end = 5 };
    blocks[6].edges = .{ .start = 5, .end = 6 };
    const function: Function = .{
        .decl = .none,
        .owner = .none,
        .entry = .at(2),
        .blocks = .{ .start = 2, .end = 8 },
        .scopes = .{ .start = 0, .end = 0 },
        .inouts = &.{},
    };
    for ([_]bool{ false, true }) |back_edge| {
        const edges = [_]BlockId{ .at(4), .at(5), .at(6), .at(3), .at(3), if (back_edge) .at(2) else .none };
        const cfg: Cfg = .{
            .functions = &.{},
            .blocks = &blocks,
            .ops = emptyOps(),
            .edges = &edges,
            .exits = .empty,
            .declared_in_loops = &.{},
            .lends = .empty,
            .scopes = &.{},
            .scope_of = &.{},
        };
        const order = try cfg.reversePostorder(gpa, &function);
        defer gpa.free(order);
        // The unreachable final block is absent; the earlier-numbered join
        // follows both arms even when the exit loops back to the entry.
        try testing.expectEqualSlices(u32, &.{ 0, 3, 2, 1, 4 }, order);
    }
}
