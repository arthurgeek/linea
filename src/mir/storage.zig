//! The storage-ownership phase of MIR verification: no path uses an
//! observation after the storage it observes was moved, lent for writing or
//! written, and no path reads an aggregate after it was moved out.
//!
//! Everything here is re-derived from instructions and callable signatures.
//! It reads nothing the ownership pass produced, because what it exists to
//! catch is an answer ownership got wrong. It is an under-approximation of
//! ownership's refusals: every refusal made here is one ownership makes on
//! the same program, so a refusal is a defect in ownership, in lowering, or
//! in this file, and never a difference of opinion.

const std = @import("std");
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const diagnostic = @import("../diagnostics/diagnostic.zig");
const Label = diagnostic.Label;
const Sink = @import("../diagnostics/sink.zig").Sink;
const types_mod = @import("../sema/types.zig");
const TypeId = types_mod.TypeId;
const Convention = @import("../syntax/node.zig").Convention;

const mir_mod = @import("mir.zig");
const Mir = mir_mod.Mir;
const Module = mir_mod.Module;
const InstId = mir_mod.InstId;
const BlockId = mir_mod.BlockId;
const LocalId = mir_mod.LocalId;
const FunctionId = mir_mod.FunctionId;
const verify_mod = @import("verify.zig");
const Address = verify_mod.Address;
const Step = verify_mod.Step;

const defect_note = "report this as a compiler bug: the program is well formed and no code was generated";

/// A slot or an instruction value: the things that hold dependencies and the
/// things that own storage. Slots come first, then instructions in order.
const Entity = u32;
const no_entity: Entity = std.math.maxInt(u32);

/// A handle to a shared dependency set; zero is the empty set.
const SetId = u32;
const empty_set: SetId = 0;

/// A handle to a shared set of marks; zero is the empty set.
const MarkId = u32;

/// The held range of a dependency that sits everywhere in its carrier: what
/// a holder retains, and what a call result carries.
const held_whole: u32 = std.math.maxInt(u32);

/// One dependency: a byte range of one root's storage, and where in the
/// carrier it is held, so that a read of one part of the carrier uses only
/// the observations stored in that part. A stale mark is the same record in
/// the carrier's chain of marks, apart from the live dependencies: marking
/// adds the record and nothing else, so a dependency marked twice is marked
/// once and the marks on every path join by union.
///
/// The same record, with `cause` set, is an event: one change a root's
/// storage underwent, held per root so that a refusal can name the
/// instruction that changed the bytes a stale observation covers. Its
/// held offset is the instruction's rank, so the latest event leads.
const Dep = struct {
    /// Where the carrier holds it: an offset and length within the carrier
    /// (within the referent, for a pointer value), or `held_whole`.
    hoff: u32,
    hlen: u32,
    root: Entity,
    off: u32,
    len: u32,
    role: Role = .held,
    cause: InstId = .none,

    /// What a dependency is to its carrier. A pointer value observes the
    /// place it points at, which is not something the bytes at that place
    /// hold; a value copied or loaded out of those bytes carries what they
    /// hold and nothing of the pointer's own observation.
    const Role = enum(u32) {
        /// Stored in the carrier: a view some part of it holds.
        held,
        /// The carrier's own observation of the place it points into.
        view,
    };

    fn isWhole(self: Dep) bool {
        return self.hlen == held_whole;
    }

    /// The order a set's chain keeps, greatest first: by held offset, so the
    /// parts held in one range of the carrier are adjacent, the whole-held
    /// ones lead, and the parts a literal stores in field order and the
    /// marks their owners' changes make in that order each go at the head
    /// in one step; then by root, so a view of a newer place -- the larger
    /// entity -- goes at the head in one step.
    fn greater(a: Dep, b: Dep) bool {
        const ah: u32 = if (a.isWhole()) held_whole else a.hoff;
        const bh: u32 = if (b.isWhole()) held_whole else b.hoff;
        if (ah != bh) return ah > bh;
        if (a.root != b.root) return a.root > b.root;
        if (a.off != b.off) return a.off > b.off;
        if (a.len != b.len) return a.len > b.len;
        if (a.hlen != b.hlen) return a.hlen > b.hlen;
        if (a.role != b.role) return @intFromEnum(a.role) > @intFromEnum(b.role);
        return @intFromEnum(a.cause) > @intFromEnum(b.cause);
    }

    fn heldOverlaps(self: Dep, a: Access) bool {
        return self.isWhole() or a.meets(self.hoff, self.hlen);
    }

    fn heldWithin(self: Dep, off: u32, len: u32) bool {
        return !self.isWhole() and self.hoff >= off and self.hoff + self.hlen <= off + len;
    }

    fn ownerOverlaps(self: Dep, a: Access) bool {
        return a.meets(self.off, self.len);
    }
};

/// A byte range: an offset and a length.
const Range = struct { off: u32, len: u32 };

/// The bytes an address covers: a range, or, for an address computed steps
/// reached, one part of every element at every level of the arrays they
/// indexed -- the set `off + k0 * elem0 + at1 + k1 * elem1 + ... + inner` of
/// `len` bytes each, for every `k` whose element lies within its array's
/// extent. Ownership tracks which field an access names and not which
/// element, so this set is what it counts as read or written, and a later
/// step narrows it by composing: the strides of the steps multiply out and
/// never merge into the bytes of the array a step indexed.
const Access = struct {
    off: u32,
    len: u32,
    steps: [verify_mod.max_computed_steps]Step = [_]Step{.{}} ** verify_mod.max_computed_steps,
    depth: u8 = 0,
    inner: u32 = 0,

    fn whole(len: u32) Access {
        return .{ .off = 0, .len = len };
    }

    fn isStrided(self: Access) bool {
        return self.depth != 0;
    }

    /// The bytes from `off` that the first array holds, or the range's
    /// own length.
    fn span(self: Access) u32 {
        return if (self.isStrided()) self.steps[0].extent else self.len;
    }

    /// Whether the bytes `[at, at + count)` meet the access.
    fn meets(self: Access, at: u32, count: u32) bool {
        if (!self.isStrided()) return at < self.off + self.len and self.off < at + count;
        const lo = @max(at, self.off);
        const hi = @min(at +| count, self.off +| self.steps[0].extent);
        if (lo >= hi) return false;
        return self.meetsArray(0, lo - self.off, hi - self.off);
    }

    /// Whether a window of the bytes of the array step `d` indexed, relative
    /// to its start, meets the access.
    fn meetsArray(self: Access, d: usize, lo: u32, hi_in: u32) bool {
        const step = self.steps[d];
        const hi = @min(hi_in, step.extent);
        if (lo >= hi) return false;
        // A window at least one element long holds a whole element, and so
        // the part accessed in it.
        if (hi - lo >= step.elem) return true;
        // Otherwise the window, taken modulo the element, is one or two
        // intervals of the element, and the part accessed is one more.
        const p = lo % step.elem;
        const q = p + (hi - lo);
        if (self.meetsElement(d, p, @min(q, step.elem))) return true;
        return q > step.elem and self.meetsElement(d, 0, q - step.elem);
    }

    /// Whether a window of one element of the array step `d` indexed,
    /// relative to the element's start, meets the access.
    fn meetsElement(self: Access, d: usize, lo: u32, hi: u32) bool {
        if (d + 1 == self.depth) return lo < self.inner + self.len and self.inner < hi;
        const next = self.steps[d + 1];
        if (hi <= next.at) return false;
        return self.meetsArray(d + 1, lo -| next.at, hi - next.at);
    }

    /// The part of the first element at every level: where a dependency
    /// made or stored through the access is recorded, which misses the other
    /// elements and so refuses nothing ownership accepts.
    fn first(self: Access) Access {
        if (!self.isStrided()) return self;
        var off = self.off + self.inner;
        for (self.steps[1..self.depth]) |step| off += step.at;
        return .{ .off = off, .len = self.len };
    }

    /// Where a part held at `[hoff, hoff + hlen)` of the carrier sits
    /// relative to the accessed bytes, when it lies within them: within the
    /// window of a range, or within the part of one element of a strided
    /// access. Null when it lies across the boundary.
    fn relative(self: Access, hoff: u32, hlen: u32) ?Range {
        if (!self.isStrided()) {
            const start = @max(hoff, self.off);
            const stop = @min(hoff +| hlen, self.off + self.len);
            if (start >= stop) return null;
            return .{ .off = start - self.off, .len = stop - start };
        }
        if (hoff < self.off) return null;
        var x = hoff - self.off;
        for (self.steps[0..self.depth]) |step| {
            if (x < step.at) return null;
            const y = x - step.at;
            if (y +| hlen > step.extent) return null;
            x = y % step.elem;
        }
        if (x < self.inner or x +| hlen > self.inner + self.len) return null;
        return .{ .off = x - self.inner, .len = hlen };
    }
};

test "two computed steps cover one part of every element of every row" {
    // `[[Pair; 2]; 2]` with 8-byte parts: rows of 32 bytes, pairs of 16, and
    // the part accessed is the first word of a pair.
    const access: Access = .{
        .off = 0,
        .len = 8,
        .depth = 2,
        .steps = .{ .{ .at = 0, .extent = 64, .elem = 32 }, .{ .at = 0, .extent = 32, .elem = 16 }, .{} },
    };
    const meeting = [_]struct { at: u32, count: u32, met: bool }{
        .{ .at = 0, .count = 8, .met = true },
        .{ .at = 8, .count = 8, .met = false },
        .{ .at = 16, .count = 8, .met = true },
        .{ .at = 24, .count = 8, .met = false },
        .{ .at = 32, .count = 8, .met = true },
        .{ .at = 40, .count = 8, .met = false },
        .{ .at = 48, .count = 8, .met = true },
        .{ .at = 56, .count = 8, .met = false },
        .{ .at = 8, .count = 16, .met = true },
        .{ .at = 56, .count = 16, .met = false },
        .{ .at = 24, .count = 16, .met = true },
    };
    for (meeting) |case| try testing.expectEqual(case.met, access.meets(case.at, case.count));
    try testing.expectEqual(@as(?Range, .{ .off = 0, .len = 8 }), access.relative(48, 8));
    try testing.expectEqual(@as(?Range, null), access.relative(8, 8));
    try testing.expectEqual(@as(u32, 0), access.first().off);
}

test "a second computed step composes with the offset between the steps" {
    // `[Outer; 2]` where `Outer` is a 8-byte tag, then two 16-byte pairs:
    // the part is the first word of a pair, 8 bytes into each element.
    const access: Access = .{
        .off = 0,
        .len = 8,
        .depth = 2,
        .steps = .{ .{ .at = 0, .extent = 80, .elem = 40 }, .{ .at = 8, .extent = 32, .elem = 16 }, .{} },
    };
    try testing.expect(!access.meets(0, 8));
    try testing.expect(access.meets(8, 8));
    try testing.expect(!access.meets(16, 8));
    try testing.expect(access.meets(24, 8));
    try testing.expect(!access.meets(40, 8));
    try testing.expect(access.meets(48, 8));
    try testing.expectEqual(@as(u32, 8), access.first().off);
}

/// Sets are cons lists sharing their tails, so copying one is copying a
/// handle. A chain is sorted greatest first and every `(dep, next)` pair is
/// interned, so two sets with the same content are the same handle and a
/// comparison is one of handles.
const Node = struct {
    dep: Dep,
    next: SetId,
    /// The chain's length.
    count: u32,
    /// Whether every dependency from here down is held whole, so a set that
    /// is carried whole into a result is the same handle.
    all_whole: bool,
    /// Whether any dependency from here down is the carrier's own observation.
    any_view: bool = false,
    /// Whether the set is entered in the index under each of its roots, for
    /// the carriers registered as its holders.
    registered: bool = false,
    /// The carriers holding exactly this set and registered through it, as a
    /// list through `holder_next` and `holder_prev`.
    holder_first: Entity = no_entity,
    /// The set's index entries, as a list through `Entry.of_set_next`.
    entry_first: u32 = no_entry,
};

const Cons = struct { dep: Dep, next: SetId };

/// Marks are a set of dependencies held as a treap, so adding a mark costs
/// the depth of the tree whichever order the owners end in: the elements
/// greater than a node's dependency are its left subtree and the lesser its
/// right, and a node's priority is a hash of its dependency, so the shape is
/// the same for the same content. Every `(dep, left, right)` triple is
/// interned, so two sets with the same content are the same handle and a
/// comparison is one of handles.
const MarkNode = struct {
    dep: Dep,
    left: MarkId,
    right: MarkId,
    /// The set's size.
    count: u32,
    /// Whether every dependency from here down is held whole.
    all_whole: bool,
    /// Whether any dependency from here down is the carrier's own observation.
    any_view: bool = false,
    priority: u64,
};

const MarkCons = struct { dep: Dep, left: MarkId, right: MarkId };

/// The index an invalidation reads: for each root, the dependencies on it
/// held by someone. An entry names one dependency and either the carrier
/// holding it or a set holding it, whose holders are the carriers. A carrier
/// whose set grows by parts enters each new part under its root, one step
/// each; a carrier taking a whole set enters the set once, however many
/// carriers share it.
const Entry = struct {
    dep: Dep,
    holder: union(enum) { carrier: Entity, set: SetId },
    /// The list of entries under the root.
    prev: u32,
    next: u32,
    /// The list of the carrier's or the set's own entries.
    of_owner_next: u32,
    /// Whether the entry is out of the root's list: once its mark is made,
    /// a carrier's entry has nothing left to do.
    dead: bool = false,
};

const no_entry: u32 = std.math.maxInt(u32);

/// An address as this phase reads it: the entity whose dependencies a read
/// through it uses, the root it points into with the offset there, and how a
/// computed step moved it. The verifier's attribution walk answers all of
/// it; this is that answer in entity numbering, plus one rule of this
/// phase's own: an aggregate loaded through an address is that address,
/// because the value is where it lives.
const Base = struct {
    carrier: Entity = no_entity,
    root: Entity = no_entity,
    off: u32 = 0,
    steps: [verify_mod.max_computed_steps]Step = [_]Step{.{}} ** verify_mod.max_computed_steps,
    depth: u8 = 0,
    inner: u32 = 0,
    /// Whether the address points into what a pointer value points at, so a
    /// read through it carries what those bytes hold and not the pointer's
    /// own observation of them.
    through: bool = false,

    fn computed(self: Base) bool {
        return self.depth != 0;
    }
};

const RootKind = enum(u8) { none, owned, lent, temp };

/// The whole per-entity state, held as parallel arrays and changed only
/// through `set`, which logs the previous values on the trail: whether a
/// root was moved out and by what, the live dependencies, the marks, and,
/// for a root, the changes its storage underwent.
const Values = struct {
    moved: bool = false,
    moved_at: InstId = .none,
    deps: SetId = empty_set,
    stale: MarkId = empty_set,
    events: SetId = empty_set,
};

const Change = union(enum) {
    state: struct { entity: Entity, old: Values, new: Values },
    entry_add: u32,
    entry_remove: u32,
    holder_add: Entity,
    holder_remove: struct { entity: Entity, set: SetId },
    registered: struct { set: SetId, was: bool },
    /// An owner's list of entries emptied of its dead ones.
    carrier_entries_reset: struct { entity: Entity, was: u32 },
    set_entries_reset: struct { set: SetId, was: u32 },
};

const Segment = struct { start: u32, len: u32 };

const Refusal = struct { kind: enum { stale, moved }, at: InstId, entity: Entity, cause: InstId };

/// Whether the dense dual runs beside the trail. It repeats the fixpoint with
/// one state per block and scans every entity at each invalidation, which is
/// the cost the trail and the index exist to avoid, so it runs only in a
/// build with runtime safety and only while both the matrix and that scan are
/// small enough not to dominate a test run.
const dual_cells_max: usize = 1 << 20;
const dual_work_max: usize = 1 << 26;

pub const Phase = struct {
    gpa: std.mem.Allocator,
    module: *const Module,
    mir: *const Mir,
    id: FunctionId,
    sink: *Sink,
    ok: bool = true,

    slot_count: u32,
    entity_count: u32,
    root_kind: []RootKind,
    /// The byte extent of each root, for whole-root moves and writes.
    root_extent: []u32,
    base: []Base,
    moved: []bool,
    moved_at: []InstId,
    deps: []SetId,
    stale: []MarkId,
    events: []SetId,
    /// The set each carrier is registered as a holder of, `empty_set` when
    /// none; its dependencies above that set are entered as the carrier's own.
    base_set: []SetId,
    holder_next: []Entity,
    holder_prev: []Entity,
    /// The first index entry under each root, the first of each carrier's
    /// own entries, and how many of those are live.
    root_entry_first: []u32,
    carrier_entry_first: []u32,
    live_entries: []u32,
    entries: std.ArrayList(Entry) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    interned: std.AutoHashMapUnmanaged(Cons, SetId) = .empty,
    marks: std.ArrayList(MarkNode) = .empty,
    marks_interned: std.AutoHashMapUnmanaged(MarkCons, MarkId) = .empty,
    last_added: ?struct { dep: Dep, onto: MarkId, result: MarkId } = null,
    /// The elements an insertion, a union or a projection rebuilds in front
    /// of the chain it shares, reused across calls.
    prefix: std.ArrayList(Dep) = .empty,
    trail: std.ArrayList(Change) = .empty,
    /// Where the trail's last state record of each entity sits, and where
    /// the block being walked began: a block that changes an entity again
    /// rewrites that entity's record, so the trail holds one per entity and
    /// block and not one per change.
    state_at: []u32,
    block_start: u32 = 0,
    saved: std.ArrayList(Change) = .empty,
    /// Whether the trail logs. The dense dual runs the same transfer without
    /// a log and scans every entity instead of the index.
    logging: bool = true,
    reporting: bool = true,
    refusals: std.ArrayList(Refusal) = .empty,
    /// Which instructions already refused, so a re-walk of a loop reports
    /// each use once.
    refused_at: []bool,

    // Control flow, over reachable blocks only.
    order: []BlockId = &.{},
    rpo_index: []u32,
    idom: []u32,
    child_first: []u32,
    child_next: []u32,
    pred_first: []u32,
    pred_next: []u32,
    pred_block: []u32,
    segment: []Segment,
    segment_valid: []bool,
    /// Per block, how many edges from it enter the block being joined, and
    /// whether it lies on a predecessor's chain to the dominator; both zero
    /// outside a join.
    pred_times: []u32,
    on_chain: []bool,
    /// How many edges into the block being joined leave each block's
    /// subtree, counted over the blocks on a chain; zero outside a join.
    chain_preds: []u32,
    /// Each block's entry and exit number in one walk of the dominator tree.
    tree_enter: []u32,
    tree_exit: []u32,
    /// The join a block applied when it was last entered, for deciding whether
    /// a loop header's join grew.
    applied: []std.ArrayList(Applied),
    exit_mark: []u32,
    /// The state at each block's entry as the trail walk saw it, compared
    /// against the dense fixpoint afterwards.
    dual_entry: ?[]Values = null,
    /// Whether an edge enters a loop other than at a block dominating it.
    irreducible: bool = false,

    const Applied = struct { entity: Entity, values: Values };
    const none: u32 = std.math.maxInt(u32);

    pub fn run(gpa: std.mem.Allocator, module: *const Module, mir: *const Mir, id: FunctionId, addresses: []const Address, sink: *Sink) std.mem.Allocator.Error!bool {
        var phase = try init(gpa, module, mir, id, sink);
        defer phase.deinit();
        try phase.check(addresses);
        return phase.ok;
    }

    fn init(gpa: std.mem.Allocator, module: *const Module, mir: *const Mir, id: FunctionId, sink: *Sink) !Phase {
        const slot_count: u32 = @intCast(mir.locals.len);
        const entity_count: u32 = slot_count + @as(u32, @intCast(mir.insts.len));
        const block_count = mir.blocks.len;

        const root_kind = try gpa.alloc(RootKind, entity_count);
        errdefer gpa.free(root_kind);
        @memset(root_kind, .none);
        const root_extent = try gpa.alloc(u32, entity_count);
        errdefer gpa.free(root_extent);
        @memset(root_extent, 0);
        const base = try gpa.alloc(Base, mir.insts.len);
        errdefer gpa.free(base);
        const moved = try gpa.alloc(bool, entity_count);
        errdefer gpa.free(moved);
        @memset(moved, false);
        const moved_at = try gpa.alloc(InstId, entity_count);
        errdefer gpa.free(moved_at);
        @memset(moved_at, .none);
        const deps = try gpa.alloc(SetId, entity_count);
        errdefer gpa.free(deps);
        @memset(deps, empty_set);
        const stale = try gpa.alloc(MarkId, entity_count);
        errdefer gpa.free(stale);
        @memset(stale, empty_set);
        const state_at = try gpa.alloc(u32, entity_count);
        errdefer gpa.free(state_at);
        @memset(state_at, no_entry);
        const events = try gpa.alloc(SetId, entity_count);
        errdefer gpa.free(events);
        @memset(events, empty_set);
        const base_set = try gpa.alloc(SetId, entity_count);
        errdefer gpa.free(base_set);
        @memset(base_set, empty_set);
        const holder_next = try gpa.alloc(Entity, entity_count);
        errdefer gpa.free(holder_next);
        const holder_prev = try gpa.alloc(Entity, entity_count);
        errdefer gpa.free(holder_prev);
        const root_entry_first = try gpa.alloc(u32, entity_count);
        errdefer gpa.free(root_entry_first);
        @memset(root_entry_first, no_entry);
        const carrier_entry_first = try gpa.alloc(u32, entity_count);
        errdefer gpa.free(carrier_entry_first);
        @memset(carrier_entry_first, no_entry);
        const live_entries = try gpa.alloc(u32, entity_count);
        errdefer gpa.free(live_entries);
        @memset(live_entries, 0);
        const refused_at = try gpa.alloc(bool, mir.insts.len);
        errdefer gpa.free(refused_at);
        @memset(refused_at, false);

        const rpo_index = try gpa.alloc(u32, block_count);
        errdefer gpa.free(rpo_index);
        @memset(rpo_index, none);
        const idom = try gpa.alloc(u32, block_count);
        errdefer gpa.free(idom);
        @memset(idom, none);
        const child_first = try gpa.alloc(u32, block_count);
        errdefer gpa.free(child_first);
        @memset(child_first, none);
        const child_next = try gpa.alloc(u32, block_count);
        errdefer gpa.free(child_next);
        @memset(child_next, none);
        const pred_first = try gpa.alloc(u32, block_count);
        errdefer gpa.free(pred_first);
        @memset(pred_first, none);
        const segment = try gpa.alloc(Segment, block_count);
        errdefer gpa.free(segment);
        const segment_valid = try gpa.alloc(bool, block_count);
        errdefer gpa.free(segment_valid);
        @memset(segment_valid, false);
        const pred_times = try gpa.alloc(u32, block_count);
        errdefer gpa.free(pred_times);
        @memset(pred_times, 0);
        const on_chain = try gpa.alloc(bool, block_count);
        errdefer gpa.free(on_chain);
        @memset(on_chain, false);
        const chain_preds = try gpa.alloc(u32, block_count);
        errdefer gpa.free(chain_preds);
        @memset(chain_preds, 0);
        const tree_enter = try gpa.alloc(u32, block_count);
        errdefer gpa.free(tree_enter);
        @memset(tree_enter, 0);
        const tree_exit = try gpa.alloc(u32, block_count);
        errdefer gpa.free(tree_exit);
        @memset(tree_exit, 0);
        const applied = try gpa.alloc(std.ArrayList(Applied), block_count);
        errdefer gpa.free(applied);
        @memset(applied, .empty);
        const exit_mark = try gpa.alloc(u32, block_count);
        errdefer gpa.free(exit_mark);

        var phase: Phase = .{
            .gpa = gpa,
            .module = module,
            .mir = mir,
            .id = id,
            .sink = sink,
            .slot_count = slot_count,
            .entity_count = entity_count,
            .root_kind = root_kind,
            .root_extent = root_extent,
            .base = base,
            .moved = moved,
            .moved_at = moved_at,
            .deps = deps,
            .stale = stale,
            .state_at = state_at,
            .events = events,
            .base_set = base_set,
            .holder_next = holder_next,
            .holder_prev = holder_prev,
            .root_entry_first = root_entry_first,
            .carrier_entry_first = carrier_entry_first,
            .live_entries = live_entries,
            .refused_at = refused_at,
            .rpo_index = rpo_index,
            .idom = idom,
            .child_first = child_first,
            .child_next = child_next,
            .pred_first = pred_first,
            .pred_next = &.{},
            .pred_block = &.{},
            .segment = segment,
            .segment_valid = segment_valid,
            .pred_times = pred_times,
            .on_chain = on_chain,
            .chain_preds = chain_preds,
            .tree_enter = tree_enter,
            .tree_exit = tree_exit,
            .applied = applied,
            .exit_mark = exit_mark,
        };
        // The empty set is node zero, which no chain reaches.
        try phase.nodes.append(gpa, .{
            .dep = .{ .hoff = 0, .hlen = 0, .root = no_entity, .off = 0, .len = 0 },
            .next = 0,
            .count = 0,
            .all_whole = true,
        });
        try phase.marks.append(gpa, .{
            .dep = .{ .hoff = 0, .hlen = 0, .root = no_entity, .off = 0, .len = 0 },
            .left = 0,
            .right = 0,
            .count = 0,
            .all_whole = true,
            .priority = 0,
        });
        return phase;
    }

    fn deinit(self: *Phase) void {
        const gpa = self.gpa;
        gpa.free(self.root_kind);
        gpa.free(self.root_extent);
        gpa.free(self.base);
        gpa.free(self.moved);
        gpa.free(self.moved_at);
        gpa.free(self.deps);
        gpa.free(self.stale);
        gpa.free(self.state_at);
        gpa.free(self.events);
        gpa.free(self.base_set);
        gpa.free(self.holder_next);
        gpa.free(self.holder_prev);
        gpa.free(self.root_entry_first);
        gpa.free(self.carrier_entry_first);
        gpa.free(self.live_entries);
        gpa.free(self.refused_at);
        gpa.free(self.order);
        gpa.free(self.rpo_index);
        gpa.free(self.idom);
        gpa.free(self.child_first);
        gpa.free(self.child_next);
        gpa.free(self.pred_first);
        gpa.free(self.pred_next);
        gpa.free(self.pred_block);
        gpa.free(self.segment);
        gpa.free(self.segment_valid);
        gpa.free(self.pred_times);
        gpa.free(self.on_chain);
        gpa.free(self.chain_preds);
        gpa.free(self.tree_enter);
        gpa.free(self.tree_exit);
        for (self.applied) |*a| a.deinit(gpa);
        gpa.free(self.applied);
        gpa.free(self.exit_mark);
        if (self.dual_entry) |d| gpa.free(d);
        self.entries.deinit(gpa);
        self.nodes.deinit(gpa);
        self.interned.deinit(gpa);
        self.marks.deinit(gpa);
        self.marks_interned.deinit(gpa);
        self.prefix.deinit(gpa);
        self.trail.deinit(gpa);
        self.saved.deinit(gpa);
        self.refusals.deinit(gpa);
        self.* = undefined;
    }

    // -- Entities, roots and the address column. --

    fn slotEntity(local: LocalId) Entity {
        return local.index();
    }

    fn instEntity(self: *const Phase, id: InstId) Entity {
        return self.slot_count + id.index();
    }

    fn layoutSize(self: *const Phase, ty: TypeId) u32 {
        return self.module.layoutOf(ty).size;
    }

    fn isDataPointer(self: *const Phase, ty: TypeId) bool {
        return self.module.representationOf(ty).computation == .data_pointer;
    }

    /// Roots: owned aggregate slots, managed-address parameter slots, and
    /// call results handed back through caller storage. The address column
    /// is the verifier's attribution in entity numbering.
    fn prepare(self: *Phase, addresses: []const Address) void {
        const mir = self.mir;
        for (mir.locals, 0..) |ty, i| {
            const local = LocalId.at(@intCast(i));
            const e = slotEntity(local);
            if (mir.slotRoleOf(local) == .managed_address) {
                self.root_kind[e] = .lent;
                self.root_extent[e] = self.layoutSize(ty);
            } else if (self.module.representationOf(ty).storage == .bytes) {
                self.root_kind[e] = .owned;
                self.root_extent[e] = self.module.slotExtentOf(mir, local);
            }
        }

        for (addresses, 0..) |a, i| {
            const id = InstId.at(@intCast(i));
            const e = self.instEntity(id);
            if (mir.tagOf(id) == .load_indirect and mir.resultRoleOf(id) == .managed_address) {
                self.base[i] = self.base[mir.unaryOf(id).index()];
                continue;
            }
            const carrier: Entity = switch (a.carrier) {
                .none => no_entity,
                .slot => |l| slotEntity(l),
                .inst => |v| self.instEntity(v),
            };
            var b: Base = .{
                .carrier = carrier,
                .steps = a.steps,
                .depth = a.depth,
                .inner = a.inner,
            };
            switch (a.origin) {
                .slot => |p| {
                    const s = slotEntity(p.local);
                    if (self.root_kind[s] == .owned) {
                        b.root = s;
                        b.off = p.off;
                    }
                },
                .lent => |p| {
                    b.root = slotEntity(p.local);
                    b.off = p.off;
                },
                .returned => |p| {
                    // The temporary is the call that produced it, which is
                    // the carrier of every address formed from its result.
                    if (carrier == e) {
                        self.root_kind[e] = .temp;
                        self.root_extent[e] = self.layoutSize(p.ty);
                    }
                    b.root = carrier;
                    b.off = p.off;
                },
                .heap => b.through = true,
                .static, .none => {},
            }
            self.base[i] = b;
        }
    }

    // -- Dependency sets. --

    /// The chain `dep` in front of `next`, made once.
    fn consOnto(self: *Phase, dep: Dep, next: SetId) !SetId {
        const got = try self.interned.getOrPut(self.gpa, .{ .dep = dep, .next = next });
        if (got.found_existing) return got.value_ptr.*;
        const id: SetId = @intCast(self.nodes.items.len);
        const below = self.nodes.items[next];
        try self.nodes.append(self.gpa, .{
            .dep = dep,
            .next = next,
            .count = below.count + 1,
            .all_whole = dep.isWhole() and below.all_whole,
            .any_view = dep.role == .view or below.any_view,
        });
        got.value_ptr.* = id;
        return id;
    }

    /// The elements in `prefix`, greatest first, in front of `tail`.
    fn rebuilt(self: *Phase, tail: SetId) !SetId {
        var out = tail;
        var i = self.prefix.items.len;
        while (i > 0) {
            i -= 1;
            out = try self.consOnto(self.prefix.items[i], out);
        }
        return out;
    }

    /// The set with `dep` added. The elements greater than `dep` are rebuilt
    /// in front of it, so adding a view of a newer root than any the set
    /// holds whole costs one step, which is what a holder growing by
    /// `retains` does on every call; so does adding a part held past every
    /// part already held, which is what a literal built in field order does;
    /// and so does a mark by a later instruction than any mark before it.
    fn cons(self: *Phase, dep: Dep, onto: SetId) !SetId {
        self.prefix.clearRetainingCapacity();
        var at = onto;
        while (at != empty_set) : (at = self.nodes.items[at].next) {
            const d = self.nodes.items[at].dep;
            if (!d.greater(dep)) {
                if (std.meta.eql(d, dep)) return onto;
                break;
            }
            try self.prefix.append(self.gpa, d);
        }
        return self.rebuilt(try self.consOnto(dep, at));
    }

    /// The union of two sets: a merge of the two chains down to the first
    /// chain they share, which is rebuilt in front of it. The cost is the
    /// elements before that point, so two sets differing in a few elements
    /// cost those few, and one extended from the other costs the extension.
    fn unionOf(self: *Phase, a: SetId, b: SetId) !SetId {
        if (a == b or b == empty_set) return a;
        if (a == empty_set) return b;
        self.prefix.clearRetainingCapacity();
        var x = a;
        var y = b;
        while (x != y and x != empty_set and y != empty_set) {
            const dx = self.nodes.items[x].dep;
            const dy = self.nodes.items[y].dep;
            if (dx.greater(dy)) {
                try self.prefix.append(self.gpa, dx);
                x = self.nodes.items[x].next;
            } else if (dy.greater(dx)) {
                try self.prefix.append(self.gpa, dy);
                y = self.nodes.items[y].next;
            } else {
                try self.prefix.append(self.gpa, dx);
                x = self.nodes.items[x].next;
                y = self.nodes.items[y].next;
            }
        }
        return self.rebuilt(if (x == empty_set) y else x);
    }

    /// Where a projected dependency is held afterwards.
    const Placement = union(enum) {
        /// Relative to the bytes read: what a pointer to them holds, so a
        /// later read through the pointer at an offset finds the parts
        /// stored there. A whole-held dependency stays whole.
        pointee,
        /// Everywhere in the result: what a call result carries.
        whole,
        /// At a range of the destination, each part shifted to where the
        /// bytes read land there; a whole-held dependency, a part lying
        /// across the boundary of what is read, or every dependency when
        /// `structure` is false, covers the whole range.
        at: struct { off: u32, len: u32, structure: bool },
    };

    /// What a projection does with the dependencies that are a pointer's own
    /// view of the place it points into.
    const Views = enum {
        /// They stay views: a pointer derived from the pointer, or a value
        /// moved whole.
        keep,
        /// They are dropped: the bytes read through a pointer hold what is
        /// stored in them and nothing of the pointer's own observation.
        skip,
        /// They become held: a pointer to an aggregate takes what the
        /// aggregate holds, and a pointer stored in it is part of that.
        hold,
    };

    /// How a read through `b` treats a pointer's own views: the bytes an
    /// address reaches through a pointer hold none of them.
    fn viewsRead(b: Base) Views {
        return if (b.through) .skip else .keep;
    }

    /// How a pointer made from `b` treats the views its carrier holds: a
    /// pointer made from a pointer observes what that one observes, and one
    /// made from an aggregate holds the pointers stored in it.
    fn viewsBorrowed(b: Base) Views {
        return if (b.through) .keep else .hold;
    }

    /// `d` as a projection places it: null when it is held outside `window`,
    /// else where the placement holds it afterwards. Dependencies and marks
    /// project by this one rule.
    fn placed(d: Dep, window: Access, to: Placement, views: Views) ?Dep {
        if (views == .skip and d.role == .view) return null;
        if (!d.heldOverlaps(window)) return null;
        var out = d;
        if (views == .hold) out.role = .held;
        switch (to) {
            .whole => {
                out.hoff = 0;
                out.hlen = held_whole;
            },
            .pointee => if (!d.isWhole()) {
                if (window.relative(d.hoff, d.hlen)) |r| {
                    out.hoff = r.off;
                    out.hlen = r.len;
                } else {
                    out.hoff = 0;
                    out.hlen = held_whole;
                }
            },
            .at => |t| {
                const r: ?Range = if (t.structure and !d.isWhole()) window.relative(d.hoff, d.hlen) else null;
                if (r) |part| {
                    out.hoff = t.off + part.off;
                    out.hlen = part.len;
                } else {
                    out.hoff = t.off;
                    out.hlen = t.len;
                }
            },
        }
        return out;
    }

    /// Sorts the projected elements greatest first and drops repeats, because
    /// a placement can bring two parts together.
    fn sortedUnique(self: *Phase) void {
        std.mem.sort(Dep, self.prefix.items, {}, struct {
            fn lessThan(_: void, a: Dep, b: Dep) bool {
                return a.greater(b);
            }
        }.lessThan);
        var kept: usize = 0;
        for (self.prefix.items, 0..) |d, i| {
            if (i > 0 and std.meta.eql(d, self.prefix.items[kept - 1])) continue;
            self.prefix.items[kept] = d;
            kept += 1;
        }
        self.prefix.items.len = kept;
    }

    /// The dependencies of `s` held in the bytes `window` covers -- a
    /// whole-held one always is -- placed as `to` says. The result is sorted
    /// and deduplicated, because a placement can bring two parts together;
    /// it is `s` itself when nothing moves.
    fn project(self: *Phase, s: SetId, window: Access, to: Placement, views: Views) !SetId {
        if (s == empty_set) return s;
        const unchanged = views == .keep or !self.nodes.items[s].any_view;
        const all_whole = self.nodes.items[s].all_whole and unchanged;
        switch (to) {
            .whole => if (all_whole) return s,
            .pointee => if (!window.isStrided() and window.off == 0 and all_whole) return s,
            .at => |t| if (unchanged and t.structure and !window.isStrided() and window.off == 0 and t.off == 0 and t.len == window.len and self.partsWithin(s, window.len)) return s,
        }
        self.prefix.clearRetainingCapacity();
        var at = s;
        while (at != empty_set) : (at = self.nodes.items[at].next) {
            if (placed(self.nodes.items[at].dep, window, to, views)) |d| try self.prefix.append(self.gpa, d);
        }
        self.sortedUnique();
        return self.rebuilt(empty_set);
    }

    /// Whether every dependency is part-held within the first `len` bytes,
    /// so that placing the first `len` bytes at offset zero changes nothing.
    fn partsWithin(self: *const Phase, s: SetId, len: u32) bool {
        var at = s;
        while (at != empty_set) : (at = self.nodes.items[at].next) {
            const d = self.nodes.items[at].dep;
            if (d.isWhole() or d.hoff + d.hlen > len) return false;
        }
        return true;
    }

    /// The set without the dependencies an exact write to `[off, off + len)`
    /// replaced: those held within it. The parts held past the range lead
    /// the chain and are rebuilt; what is held before it is shared.
    fn afterWrite(self: *Phase, s: SetId, off: u32, len: u32) !SetId {
        if (s == empty_set) return s;
        self.prefix.clearRetainingCapacity();
        var at = s;
        var dropped = false;
        while (at != empty_set) : (at = self.nodes.items[at].next) {
            const d = self.nodes.items[at].dep;
            if (!d.isWhole() and d.hoff + d.hlen <= off) break;
            if (d.heldWithin(off, len)) {
                dropped = true;
                continue;
            }
            try self.prefix.append(self.gpa, d);
        }
        if (!dropped) return s;
        return self.rebuilt(at);
    }

    // -- Marks. --

    fn markPriority(d: Dep) u64 {
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&d));
    }

    /// Whether `a` is above `b` in a tree: the greater priority, and for equal
    /// priorities the greater dependency, so the order is total.
    fn markAbove(a: Dep, pa: u64, b: Dep, pb: u64) bool {
        return if (pa != pb) pa > pb else a.greater(b);
    }

    /// The interned node for `(dep, left, right)`. A whole-held dependency
    /// has held offset zero: `Dep.greater` treats two of them that differ
    /// only there as equal, and the treap holds one of any two equal ones.
    fn markNode(self: *Phase, dep: Dep, left: MarkId, right: MarkId) !MarkId {
        std.debug.assert(!dep.isWhole() or dep.hoff == 0);
        const got = try self.marks_interned.getOrPut(self.gpa, .{ .dep = dep, .left = left, .right = right });
        if (got.found_existing) return got.value_ptr.*;
        const id: MarkId = @intCast(self.marks.items.len);
        const l = self.marks.items[left];
        const r = self.marks.items[right];
        try self.marks.append(self.gpa, .{
            .dep = dep,
            .left = left,
            .right = right,
            .count = l.count + r.count + 1,
            .all_whole = dep.isWhole() and l.all_whole and r.all_whole,
            .any_view = dep.role == .view or l.any_view or r.any_view,
            .priority = markPriority(dep),
        });
        got.value_ptr.* = id;
        return id;
    }

    const MarkSplit = struct { greater: MarkId, lesser: MarkId };

    /// The elements of `t` greater than `d` and those lesser; `d` itself is
    /// in neither.
    fn markSplit(self: *Phase, t: MarkId, d: Dep) std.mem.Allocator.Error!MarkSplit {
        if (t == empty_set) return .{ .greater = empty_set, .lesser = empty_set };
        const n = self.marks.items[t];
        if (n.dep.greater(d)) {
            const s = try self.markSplit(n.right, d);
            return .{ .greater = try self.markNode(n.dep, n.left, s.greater), .lesser = s.lesser };
        }
        if (d.greater(n.dep)) {
            const s = try self.markSplit(n.left, d);
            return .{ .greater = s.greater, .lesser = try self.markNode(n.dep, s.lesser, n.right) };
        }
        std.debug.assert(std.meta.eql(n.dep, d));
        return .{ .greater = n.left, .lesser = n.right };
    }

    test "splitting a mark set at a dependency leaves that dependency in neither half" {
        var p: Phase = undefined;
        try markTestInit(&p);
        defer markTestDeinit(&p);
        const items = markTestDeps(8);
        const all = try p.markBuild(&items);
        const s = try p.markSplit(all, items[3]);
        try testing.expectEqual(@as(u32, 3), p.marks.items[s.greater].count);
        try testing.expectEqual(@as(u32, 4), p.marks.items[s.lesser].count);
        try testing.expectEqual(all, try p.markUnion(try p.markNode(items[3], empty_set, empty_set), try p.markUnion(s.greater, s.lesser)));
    }

    /// The union of two sets. Each level splits the lower root's tree at the
    /// upper root, so the cost is the depth for each element the sets do not
    /// share, and subtrees both sets hold are one comparison of handles.
    fn markUnion(self: *Phase, a: MarkId, b: MarkId) std.mem.Allocator.Error!MarkId {
        if (a == b or b == empty_set) return a;
        if (a == empty_set) return b;
        const na = self.marks.items[a];
        const nb = self.marks.items[b];
        if (markAbove(nb.dep, nb.priority, na.dep, na.priority)) return self.markUnion(b, a);
        const s = try self.markSplit(b, na.dep);
        return self.markNode(na.dep, try self.markUnion(na.left, s.greater), try self.markUnion(na.right, s.lesser));
    }

    test "the union of mark sets is the same handle in either order and holds each element once" {
        var p: Phase = undefined;
        try markTestInit(&p);
        defer markTestDeinit(&p);
        const items = markTestDeps(10);
        const a = try p.markBuild(items[0..6]);
        const b = try p.markBuild(items[4..10]);
        const ab = try p.markUnion(a, b);
        try testing.expectEqual(ab, try p.markUnion(b, a));
        try testing.expectEqual(@as(u32, 10), p.marks.items[ab].count);
        try testing.expectEqual(ab, try p.markUnion(ab, a));
        try testing.expectEqual(ab, try p.markUnion(a, ab));
        try testing.expectEqual(a, try p.markUnion(a, empty_set));
        try testing.expectEqual(b, try p.markUnion(empty_set, b));
        try testing.expectEqual(ab, try p.markBuild(&items));
    }

    test "a mark set grew into a superset and not into a subset" {
        var p: Phase = undefined;
        try markTestInit(&p);
        defer markTestDeinit(&p);
        const items = markTestDeps(9);
        const small = try p.markBuild(items[2..5]);
        const large = try p.markBuild(&items);
        try testing.expect(try p.marksGrew(small, large));
        try testing.expect(try p.marksGrew(empty_set, large));
        try testing.expect(try p.marksGrew(large, large));
        try testing.expect(!try p.marksGrew(large, small));
        try testing.expect(!try p.marksGrew(try p.markBuild(items[0..3]), small));
    }

    /// The marks with `d` added; the same handle when it is marked already.
    /// The last addition is remembered: an invalidation adds one dependency to
    /// every carrier it marks, and carriers that share a set hold the same
    /// marks, so they find the answer here. Carriers holding different marks
    /// miss and compute the union; the memo saves work and never changes the
    /// result.
    fn markAdd(self: *Phase, d: Dep, onto: MarkId) !MarkId {
        if (self.last_added) |last| {
            if (last.onto == onto and std.meta.eql(last.dep, d)) return last.result;
        }
        const result = try self.markUnion(onto, try self.markNode(d, empty_set, empty_set));
        self.last_added = .{ .dep = d, .onto = onto, .result = result };
        return result;
    }

    test "marks added in any order are one handle, and equal marks are one node" {
        var p: Phase = undefined;
        try markTestInit(&p);
        defer markTestDeinit(&p);
        const items = markTestDeps(12);
        var forward: MarkId = empty_set;
        for (items) |d| forward = try p.markAdd(d, forward);
        var reverse: MarkId = empty_set;
        var i = items.len;
        while (i > 0) : (i -= 1) reverse = try p.markAdd(items[i - 1], reverse);
        try testing.expectEqual(forward, reverse);
        var prng = std.Random.DefaultPrng.init(7);
        for (0..8) |_| {
            var order = items;
            prng.random().shuffle(Dep, &order);
            var shuffled: MarkId = empty_set;
            for (order) |d| shuffled = try p.markAdd(d, shuffled);
            try testing.expectEqual(forward, shuffled);
        }
        try testing.expectEqual(@as(u32, 12), p.marks.items[forward].count);
        // Building the set again interns to nodes that exist already.
        const nodes_before_build = p.marks.items.len;
        try testing.expectEqual(forward, try p.markBuild(&items));
        try testing.expectEqual(nodes_before_build, p.marks.items.len);
        try testing.expectEqual(forward, try p.markAdd(items[5], forward));
    }

    /// The tree of the elements in `items`, sorted greatest first and unique.
    fn markBuild(self: *Phase, items: []const Dep) std.mem.Allocator.Error!MarkId {
        if (items.len == 0) return empty_set;
        var top: usize = 0;
        var top_priority = markPriority(items[0]);
        for (items[1..], 1..) |d, i| {
            const p = markPriority(d);
            if (markAbove(d, p, items[top], top_priority)) {
                top = i;
                top_priority = p;
            }
        }
        const left = try self.markBuild(items[0..top]);
        const right = try self.markBuild(items[top + 1 ..]);
        return self.markNode(items[top], left, right);
    }

    test "a mark set reads greatest first, and the first mark over a range leads" {
        var p: Phase = undefined;
        try markTestInit(&p);
        defer markTestDeinit(&p);
        const items = markTestDeps(10);
        const t = try p.markBuild(&items);
        var seen: std.ArrayList(Dep) = .empty;
        defer seen.deinit(testing.allocator);
        try markTestWalk(&p, t, &seen);
        try testing.expectEqual(items.len, seen.items.len);
        for (seen.items[1..], 0..) |d, i| try testing.expect(seen.items[i].greater(d));
        // Each element is held at offset `hoff` of the carrier.
        const first = p.staleWithin(t, .{ .off = 0, .len = 4096 }).?;
        try testing.expect(std.meta.eql(first, seen.items[0]));
        // A whole-held mark is in every range, and the greatest ones are whole.
        try testing.expect(seen.items[0].isWhole());
        try testing.expect(std.meta.eql(p.staleWithin(t, .{ .off = 100000, .len = 4 }).?, seen.items[0]));
        try testing.expect(p.staleWithin(empty_set, .{ .off = 0, .len = 4 }) == null);
    }

    /// Appends the marks of `t` that `placed` holds, greatest first.
    fn markPlaced(self: *Phase, t: MarkId, window: Access, to: Placement, views: Views) !void {
        if (t == empty_set) return;
        const n = self.marks.items[t];
        try self.markPlaced(n.left, window, to, views);
        if (placed(n.dep, window, to, views)) |d| try self.prefix.append(self.gpa, d);
        try self.markPlaced(n.right, window, to, views);
    }

    /// Whether every mark is part-held within the first `len` bytes, so that
    /// placing them at offset zero changes nothing.
    fn markPartsWithin(self: *const Phase, t: MarkId, len: u32) bool {
        if (t == empty_set) return true;
        const n = self.marks.items[t];
        if (n.dep.isWhole() or n.dep.hoff + n.dep.hlen > len) return false;
        return self.markPartsWithin(n.left, len) and self.markPartsWithin(n.right, len);
    }

    /// The marks of `s` held in the bytes `window` covers, placed as `to`
    /// says by the rule dependencies project by.
    fn projectMarks(self: *Phase, s: MarkId, window: Access, to: Placement, views: Views) !MarkId {
        if (s == empty_set) return s;
        const unchanged = views == .keep or !self.marks.items[s].any_view;
        const all_whole = self.marks.items[s].all_whole and unchanged;
        switch (to) {
            .whole => if (all_whole) return s,
            .pointee => if (!window.isStrided() and window.off == 0 and all_whole) return s,
            .at => |t| if (unchanged and t.structure and !window.isStrided() and window.off == 0 and t.off == 0 and t.len == window.len and self.markPartsWithin(s, window.len)) return s,
        }
        self.prefix.clearRetainingCapacity();
        try self.markPlaced(s, window, to, views);
        self.sortedUnique();
        return self.markBuild(self.prefix.items);
    }

    test "marks placed where they already are are the same set, and marks moved are not" {
        var p: Phase = undefined;
        try markTestInit(&p);
        defer markTestDeinit(&p);
        var parts: [6]Dep = undefined;
        for (&parts, 0..) |*d, i| d.* = .{ .hoff = @intCast((5 - i) * 8), .hlen = 8, .root = 3, .off = 0, .len = 8 };
        const t = try p.markBuild(&parts);
        const window = Access.whole(48);
        const nodes = p.marks.items.len;
        try testing.expectEqual(t, try p.projectMarks(t, window, .{ .at = .{ .off = 0, .len = 48, .structure = true } }, .keep));
        try testing.expectEqual(nodes, p.marks.items.len);
        const moved = try p.projectMarks(t, window, .{ .at = .{ .off = 8, .len = 48, .structure = true } }, .keep);
        try testing.expect(moved != t);
        try testing.expectEqual(@as(u32, 6), p.marks.items[moved].count);
        const flattened = try p.projectMarks(t, window, .{ .at = .{ .off = 0, .len = 48, .structure = false } }, .keep);
        try testing.expectEqual(@as(u32, 1), p.marks.items[flattened].count);
    }

    /// Whether every mark of `old` is in `new`.
    fn marksGrew(self: *Phase, old: MarkId, new: MarkId) !bool {
        if (old == new or old == empty_set) return true;
        if (self.marks.items[old].count > self.marks.items[new].count) return false;
        return (try self.markUnion(old, new)) == new;
    }

    /// The first mark, greatest first, held in the bytes the access covers.
    fn staleWithin(self: *const Phase, marks: MarkId, a: Access) ?Dep {
        if (marks == empty_set) return null;
        const n = self.marks.items[marks];
        if (self.staleWithin(n.left, a)) |d| return d;
        if (n.dep.heldOverlaps(a)) return n.dep;
        return self.staleWithin(n.right, a);
    }

    // -- State changes, logged. --

    fn valuesOf(self: *const Phase, e: Entity) Values {
        return .{ .moved = self.moved[e], .moved_at = self.moved_at[e], .deps = self.deps[e], .stale = self.stale[e], .events = self.events[e] };
    }

    fn store(self: *Phase, e: Entity, v: Values) void {
        self.moved[e] = v.moved;
        self.moved_at[e] = v.moved_at;
        self.deps[e] = v.deps;
        self.stale[e] = v.stale;
        self.events[e] = v.events;
    }

    fn fullyStale(self: *const Phase, v: Values) bool {
        return v.deps != empty_set and self.marks.items[v.stale].count >= self.nodes.items[v.deps].count;
    }

    /// Enters an entry in the index under its root; `entryAdd` then enters
    /// it in its owner's list, where it stays for its lifetime.
    fn entryLink(self: *Phase, id: u32) void {
        const e = &self.entries.items[id];
        const root = e.dep.root;
        e.dead = false;
        e.prev = no_entry;
        e.next = self.root_entry_first[root];
        if (e.next != no_entry) self.entries.items[e.next].prev = id;
        self.root_entry_first[root] = id;
        if (e.holder == .carrier) self.live_entries[e.holder.carrier] += 1;
    }

    /// Takes an entry out of the root's list; it stays in its owner's list,
    /// dead, until the owner's entries are removed together or a rollback
    /// restores it.
    fn entryUnlink(self: *Phase, id: u32) void {
        const e = &self.entries.items[id];
        if (e.prev != no_entry) self.entries.items[e.prev].next = e.next else self.root_entry_first[e.dep.root] = e.next;
        if (e.next != no_entry) self.entries.items[e.next].prev = e.prev;
        e.dead = true;
        if (e.holder == .carrier) self.live_entries[e.holder.carrier] -= 1;
    }

    fn entryAdd(self: *Phase, dep: Dep, holder: @FieldType(Entry, "holder")) !void {
        const id: u32 = @intCast(self.entries.items.len);
        try self.entries.append(self.gpa, .{ .dep = dep, .holder = holder, .prev = no_entry, .next = no_entry, .of_owner_next = no_entry });
        self.entryLink(id);
        const e = &self.entries.items[id];
        switch (holder) {
            .carrier => |c| {
                e.of_owner_next = self.carrier_entry_first[c];
                self.carrier_entry_first[c] = id;
            },
            .set => |st| {
                e.of_owner_next = self.nodes.items[st].entry_first;
                self.nodes.items[st].entry_first = id;
            },
        }
        try self.trail.append(self.gpa, .{ .entry_add = id });
    }

    /// Removes every live entry of a carrier or a set, walking its own list.
    fn entriesRemove(self: *Phase, first: u32) !void {
        var id = first;
        while (id != no_entry) {
            const next = self.entries.items[id].of_owner_next;
            if (!self.entries.items[id].dead) {
                self.entryUnlink(id);
                try self.trail.append(self.gpa, .{ .entry_remove = id });
            }
            id = next;
        }
    }

    fn holderLink(self: *Phase, e: Entity, s: SetId) void {
        self.base_set[e] = s;
        self.holder_prev[e] = no_entity;
        self.holder_next[e] = self.nodes.items[s].holder_first;
        if (self.holder_next[e] != no_entity) self.holder_prev[self.holder_next[e]] = e;
        self.nodes.items[s].holder_first = e;
    }

    fn holderUnlink(self: *Phase, e: Entity) void {
        const s = self.base_set[e];
        if (self.holder_prev[e] != no_entity) self.holder_next[self.holder_prev[e]] = self.holder_next[e] else self.nodes.items[s].holder_first = self.holder_next[e];
        if (self.holder_next[e] != no_entity) self.holder_prev[self.holder_next[e]] = self.holder_prev[e];
        self.base_set[e] = empty_set;
    }

    /// Enters a set under each root it holds a dependency on, once.
    fn setRegister(self: *Phase, s: SetId) !void {
        if (self.nodes.items[s].registered) return;
        var at = s;
        while (at != empty_set) : (at = self.nodes.items[at].next) {
            try self.entryAdd(self.nodes.items[at].dep, .{ .set = s });
        }
        self.nodes.items[s].registered = true;
        try self.trail.append(self.gpa, .{ .registered = .{ .set = s, .was = false } });
    }

    /// Takes a set out of the index once no carrier holds it through it.
    fn setUnregister(self: *Phase, s: SetId) !void {
        if (!self.nodes.items[s].registered or self.nodes.items[s].holder_first != no_entity) return;
        try self.entriesRemove(self.nodes.items[s].entry_first);
        try self.trail.append(self.gpa, .{ .set_entries_reset = .{ .set = s, .was = self.nodes.items[s].entry_first } });
        self.nodes.items[s].entry_first = no_entry;
        self.nodes.items[s].registered = false;
        try self.trail.append(self.gpa, .{ .registered = .{ .set = s, .was = true } });
    }

    /// Takes a carrier out of the index altogether.
    fn unregister(self: *Phase, e: Entity) !void {
        if (self.carrier_entry_first[e] != no_entry) {
            try self.entriesRemove(self.carrier_entry_first[e]);
            try self.trail.append(self.gpa, .{ .carrier_entries_reset = .{ .entity = e, .was = self.carrier_entry_first[e] } });
            self.carrier_entry_first[e] = no_entry;
        }
        const s = self.base_set[e];
        if (s != empty_set) {
            self.holderUnlink(e);
            try self.trail.append(self.gpa, .{ .holder_remove = .{ .entity = e, .set = s } });
            try self.setUnregister(s);
        }
    }

    /// Keeps the index true to a carrier's change of dependencies. A set
    /// that extends the one it held -- the old chain is a tail of the new --
    /// enters only the new parts, under the carrier's own name; any other
    /// set is entered once, with the carrier as a holder. A carrier whose
    /// every dependency is marked leaves the index: nothing is left to mark.
    fn reindex(self: *Phase, e: Entity, old: Values, new: Values) !void {
        if (new.deps == empty_set or self.fullyStale(new)) return self.unregister(e);
        // A write took marks away, so the entries that retired when those
        // marks were made have work again: the carrier re-enters whole.
        if (old.stale != new.stale and !try self.marksGrew(old.stale, new.stale)) {
            try self.unregister(e);
            return self.hold(e, new.deps);
        }
        if (new.deps == old.deps) {
            if (!self.indexed(e)) try self.hold(e, new.deps);
            return;
        }
        if (old.deps != empty_set and self.indexed(e) and self.extends(new.deps, old.deps)) {
            var part = new.deps;
            while (part != old.deps) : (part = self.nodes.items[part].next) {
                try self.entryAdd(self.nodes.items[part].dep, .{ .carrier = e });
            }
            return;
        }
        try self.unregister(e);
        try self.hold(e, new.deps);
    }

    /// Whether `old` is a tail of `new`: the new chain is the old one with
    /// parts in front.
    fn extends(self: *const Phase, new: SetId, old: SetId) bool {
        const old_count = self.nodes.items[old].count;
        var at = new;
        while (at != empty_set and self.nodes.items[at].count > old_count) : (at = self.nodes.items[at].next) {}
        return at == old;
    }

    /// Whether the carrier is in the index at all: a holder of a set, or the
    /// owner of a live entry.
    fn indexed(self: *const Phase, e: Entity) bool {
        return self.base_set[e] != empty_set or self.live_entries[e] > 0;
    }

    fn hold(self: *Phase, e: Entity, s: SetId) !void {
        try self.setRegister(s);
        self.holderLink(e, s);
        try self.trail.append(self.gpa, .{ .holder_add = e });
    }

    fn set(self: *Phase, e: Entity, v: Values) !void {
        const old = self.valuesOf(e);
        if (std.meta.eql(old, v)) return;
        if (self.logging) try self.logState(e, old, v);
        self.store(e, v);
        if (self.logging) try self.reindex(e, old, v);
    }

    /// Logs a change of an entity's values. One the block already logged for
    /// the entity rewrites that record's new values and keeps its old ones,
    /// which is all a rollback to the block's start and a join over the
    /// block's segment read of it.
    fn logState(self: *Phase, e: Entity, old: Values, new: Values) !void {
        const at = self.state_at[e];
        if (at != no_entry and at >= self.block_start and at < self.trail.items.len) {
            switch (self.trail.items[at]) {
                .state => |*c| if (c.entity == e) {
                    c.new = new;
                    return;
                },
                else => {},
            }
        }
        self.state_at[e] = @intCast(self.trail.items.len);
        try self.trail.append(self.gpa, .{ .state = .{ .entity = e, .old = old, .new = new } });
    }

    fn rollback(self: *Phase, mark: u32) void {
        while (self.trail.items.len > mark) {
            const change = self.trail.pop().?;
            switch (change) {
                .state => |c| self.store(c.entity, c.old),
                .entry_add => |id| {
                    if (!self.entries.items[id].dead) self.entryUnlink(id);
                    const e = self.entries.items[id];
                    switch (e.holder) {
                        .carrier => |c| self.carrier_entry_first[c] = e.of_owner_next,
                        .set => |st| self.nodes.items[st].entry_first = e.of_owner_next,
                    }
                },
                .entry_remove => |id| self.entryLink(id),
                .holder_add => |e| self.holderUnlink(e),
                .holder_remove => |c| self.holderLink(c.entity, c.set),
                .registered => |c| self.nodes.items[c.set].registered = c.was,
                .carrier_entries_reset => |c| self.carrier_entry_first[c.entity] = c.was,
                .set_entries_reset => |c| self.nodes.items[c.set].entry_first = c.was,
            }
        }
    }

    // -- The transfer function. --

    /// A fresh definition of an instruction value: whatever a previous pass of
    /// a loop left on it is gone.
    fn define(self: *Phase, id: InstId, deps: SetId, stale: MarkId) !void {
        try self.set(self.instEntity(id), .{ .deps = deps, .stale = stale });
    }

    fn refuse(self: *Phase, kind: @FieldType(Refusal, "kind"), at: InstId, entity: Entity, cause: InstId) !void {
        if (!self.reporting) return;
        if (self.refused_at[at.index()]) return;
        self.refused_at[at.index()] = true;
        try self.refusals.append(self.gpa, .{ .kind = kind, .at = at, .entity = entity, .cause = cause });
    }

    /// Whether a value of this type can hold a dependency at all. A read of a
    /// part that cannot -- the scalar payload of a result whose other variant
    /// carries a view -- reads no observation, so it is not a use ownership
    /// refuses. The table covers every type of the pool, so a type outside it
    /// is a defect, not a type that carries.
    fn mayCarry(self: *const Phase, ty: TypeId) bool {
        std.debug.assert(ty.index() < self.module.types.dependency_containment.len);
        return self.module.types.mayCarryDependencies(ty);
    }

    /// A read of `ty` through an address, or of a carrier's value itself:
    /// refused when the root was moved out, or when a mark is held in the
    /// part read and what is read can hold a dependency. A value used whole
    /// -- passed, returned, or the carrier of the address being the value
    /// itself -- uses every part; a read through an address uses the bytes
    /// the address covers.
    fn use(self: *Phase, at: InstId, b: Base, ty: TypeId, whole: bool) !void {
        if (b.carrier != no_entity and self.stale[b.carrier] != empty_set and self.mayCarry(ty)) {
            const a: Access = if (whole) Access.whole(held_whole - 1) else self.accessOf(b, ty);
            if (self.staleWithin(self.stale[b.carrier], a)) |d| try self.refuse(.stale, at, b.carrier, self.causeOf(d));
        }
        if (b.root != no_entity and self.moved[b.root]) try self.refuse(.moved, at, b.root, self.moved_at[b.root]);
    }

    fn useValue(self: *Phase, at: InstId, v: InstId) !void {
        const b = self.base[v.index()];
        try self.use(at, b, self.mir.typeOf(v), b.carrier == self.instEntity(v));
    }

    /// Records the change as one of the root's events, and marks, in every
    /// carrier observing the bytes the access covers, the dependency that
    /// observes them: the index's entries under the root, each a carrier --
    /// whose entry has then done its work and leaves the list -- or a set
    /// whose holders are carriers.
    fn invalidate(self: *Phase, root: Entity, a: Access, at: InstId) !void {
        var r = self.valuesOf(root);
        r.events = try self.cons(.{ .hoff = at.index() + 1, .hlen = 0, .root = root, .off = a.off, .len = a.span(), .cause = at }, r.events);
        try self.set(root, r);
        if (self.logging) {
            var id = self.root_entry_first[root];
            while (id != no_entry) {
                // Marking may take the entry's owner out of the index, so the
                // next entry is read first.
                const this = id;
                const entry = self.entries.items[this];
                id = entry.next;
                if (entry.dead or !entry.dep.ownerOverlaps(a)) continue;
                switch (entry.holder) {
                    .carrier => |c| {
                        try self.markStale(c, entry.dep);
                        if (!self.entries.items[this].dead) {
                            self.entryUnlink(this);
                            try self.trail.append(self.gpa, .{ .entry_remove = this });
                        }
                    },
                    .set => |s| {
                        var h = self.nodes.items[s].holder_first;
                        while (h != no_entity) {
                            const next = self.holder_next[h];
                            try self.markStale(h, entry.dep);
                            h = next;
                        }
                    },
                }
            }
            return;
        }
        for (0..self.entity_count) |i| {
            const e: Entity = @intCast(i);
            var v = self.valuesOf(e);
            var n = v.deps;
            while (n != empty_set) : (n = self.nodes.items[n].next) {
                const d = self.nodes.items[n].dep;
                if (d.root != root or !d.ownerOverlaps(a)) continue;
                v.stale = try self.markAdd(d, v.stale);
            }
            try self.set(e, v);
        }
    }

    /// Marks a dependency in a carrier; marking one already marked changes
    /// nothing, so the marks on a path are the dependencies whose owners
    /// changed on it, whatever the order.
    fn markStale(self: *Phase, e: Entity, d: Dep) !void {
        var v = self.valuesOf(e);
        v.stale = try self.markAdd(d, v.stale);
        try self.set(e, v);
    }

    /// The instruction that last changed the bytes a stale dependency
    /// observes, from the owner's events: the latest leads.
    fn causeOf(self: *const Phase, d: Dep) InstId {
        var at = self.events[d.root];
        while (at != empty_set) : (at = self.nodes.items[at].next) {
            const ev = self.nodes.items[at].dep;
            if (ev.off < d.off + d.len and d.off < ev.off + ev.len) return ev.cause;
        }
        return .none;
    }

    /// The bytes an address of `ty` covers.
    fn accessOf(self: *const Phase, b: Base, ty: TypeId) Access {
        if (!b.computed() or b.steps[0].elem == 0) return .{ .off = b.off, .len = self.layoutSize(ty) };
        return .{ .off = b.off, .len = self.layoutSize(ty), .steps = b.steps, .depth = b.depth, .inner = b.inner };
    }

    fn wholeRoot(self: *const Phase, b: Base, ty: TypeId) bool {
        return b.root != no_entity and !b.computed() and b.off == 0 and self.layoutSize(ty) == self.root_extent[b.root];
    }

    /// A write into a root: dependents of the bytes written go stale, a
    /// moved root is held again, the dependencies an exact write replaced
    /// leave the root, and what the written value carries joins it where it
    /// was written.
    ///
    /// Every mark leaves on any write, because MIR cannot tell a binding
    /// initialised part by part -- which is what a `let` of a literal is,
    /// and what a loop does with it on every pass -- from one field assigned
    /// into a value holding a stale view elsewhere. Ownership accepts the
    /// first, so this accepts both.
    fn writeFrom(self: *Phase, at: InstId, dst: Base, ty: TypeId, from: SetId, from_marks: MarkId) !void {
        if (dst.root == no_entity) return;
        const a = self.accessOf(dst, ty);
        try self.invalidate(dst.root, a, at);
        var v = self.valuesOf(dst.root);
        v.moved = false;
        v.moved_at = .none;
        v.deps = if (self.wholeRoot(dst, ty)) empty_set else if (a.isStrided()) v.deps else try self.afterWrite(v.deps, a.off, a.len);
        v.deps = try self.unionOf(v.deps, from);
        v.stale = from_marks;
        try self.set(dst.root, v);
    }

    /// What a register value carries once stored through an address of
    /// `ty`: at the bytes written, or at the part of the first element for
    /// a strided write.
    fn storedAt(self: *Phase, value: InstId, a: Access) !struct { deps: SetId, marks: MarkId } {
        const e = self.instEntity(value);
        const r = a.first();
        const to: Placement = .{ .at = .{ .off = r.off, .len = r.len, .structure = false } };
        return .{
            .deps = try self.project(self.deps[e], Access.whole(held_whole - 1), to, .keep),
            .marks = try self.projectMarks(self.stale[e], Access.whole(held_whole - 1), to, .keep),
        };
    }

    fn moveOut(self: *Phase, at: InstId, src: Base, ty: TypeId) !void {
        if (!self.wholeRoot(src, ty)) return;
        if (self.root_kind[src.root] == .lent) return;
        try self.invalidate(src.root, Access.whole(self.root_extent[src.root]), at);
        var v = self.valuesOf(src.root);
        v.moved = true;
        v.moved_at = at;
        try self.set(src.root, v);
    }

    fn step(self: *Phase, id: InstId) !void {
        const mir = self.mir;
        switch (mir.tagOf(id)) {
            .load => {
                const local = mir.localOf(id);
                if (mir.slotRoleOf(local) == .managed_address) return self.define(id, empty_set, empty_set);
                const s = slotEntity(local);
                try self.define(id, self.deps[s], self.stale[s]);
            },
            .store => {
                const st = mir.storeOf(id);
                const v = self.instEntity(st.value);
                try self.set(slotEntity(st.local), .{ .deps = self.deps[v], .stale = self.stale[v] });
            },
            .borrow, .address_bits => {
                const a = mir.unaryOf(id);
                const b = self.base[a.index()];
                try self.use(id, b, mir.typeOf(a), false);
                // The address's type is what sits there: the referent a
                // borrow observes, or the array a view spans. The pointer
                // holds what those bytes hold, relative to them, and observes
                // them as a whole -- the part of the first element, for an
                // element chosen at run time.
                const window = self.accessOf(b, mir.typeOf(a));
                var deps = if (b.carrier != no_entity) try self.project(self.deps[b.carrier], window, .pointee, viewsBorrowed(b)) else empty_set;
                const marks = if (b.carrier != no_entity) try self.projectMarks(self.stale[b.carrier], window, .pointee, viewsBorrowed(b)) else empty_set;
                if (b.root != no_entity) {
                    const r = window.first();
                    deps = try self.cons(.{ .hoff = 0, .hlen = r.len, .root = b.root, .off = r.off, .len = r.len, .role = .view }, deps);
                }
                try self.define(id, deps, marks);
            },
            .load_indirect => {
                const a = mir.unaryOf(id);
                const b = self.base[a.index()];
                try self.use(id, b, mir.typeOf(id), false);
                if (mir.resultRoleOf(id) == .managed_address) return;
                if (self.isDataPointer(mir.typeOf(id)) and b.carrier != no_entity) {
                    const window = self.accessOf(b, mir.typeOf(id));
                    try self.define(id, try self.project(self.deps[b.carrier], window, .pointee, viewsRead(b)), try self.projectMarks(self.stale[b.carrier], window, .pointee, viewsRead(b)));
                } else {
                    try self.define(id, empty_set, empty_set);
                }
            },
            .store_indirect => {
                // The stored value carries what it holds into the bytes it
                // is written to: a data pointer's observation, or the integer
                // `address_bits` made of an array's address, which is how a
                // view over an array reaches the slot that holds it.
                const p = mir.binaryOf(id);
                const dst = self.base[p.lhs.index()];
                if (dst.root == no_entity) return;
                const stored = try self.storedAt(p.rhs, self.accessOf(dst, mir.typeOf(id)));
                try self.writeFrom(id, dst, mir.typeOf(id), stored.deps, stored.marks);
            },
            .copy_value, .move_value => {
                const p = mir.binaryOf(id);
                const ty = mir.typeOf(id);
                const src = self.base[p.rhs.index()];
                const dst = self.base[p.lhs.index()];
                try self.use(id, src, ty, false);
                // The source is taken before the destination is written, so
                // a self-assignment leaves its place holding the value. The
                // parts the source holds in the copied bytes land at the same
                // places in the destination.
                var carried: SetId = empty_set;
                var carried_marks: MarkId = empty_set;
                if (src.carrier != no_entity and dst.root != no_entity) {
                    const from = self.accessOf(src, ty);
                    const to = self.accessOf(dst, ty).first();
                    const placement: Placement = .{ .at = .{ .off = to.off, .len = to.len, .structure = true } };
                    carried = try self.project(self.deps[src.carrier], from, placement, viewsRead(src));
                    carried_marks = try self.projectMarks(self.stale[src.carrier], from, placement, viewsRead(src));
                }
                if (mir.tagOf(id) == .move_value) try self.moveOut(id, src, ty);
                try self.writeFrom(id, dst, ty, carried, carried_marks);
            },
            .call, .call_noreturn => {
                const c = mir.callOf(id);
                const callee = self.module.functionOf(c.func);
                try self.callEffects(id, c.args, self.signatureOf(callee.signature));
            },
            .call_indirect, .call_indirect_noreturn => {
                const c = mir.indirectCallOf(id);
                try self.useValue(id, c.callee);
                try self.callEffects(id, c.args, self.signatureOf(mir.typeOf(c.callee)));
            },
            .ret => try self.useValue(id, mir.unaryOf(id)),
            // An address carries nothing of its own: a read through it uses
            // the carrier the address column names.
            .addr_of,
            .field_addr,
            .check,
            .observe,
            .constant,
            .bytes_addr,
            .static_addr,
            .load_raw,
            .store_raw,
            .storage_addr,
            .add,
            .sub,
            .mul,
            .div,
            .rem,
            .neg,
            .cmp_eq,
            .cmp_ne,
            .cmp_lt,
            .cmp_le,
            .cmp_gt,
            .cmp_ge,
            .int_to_float,
            .float_to_int,
            .float_math,
            .function_addr,
            .jump,
            .branch,
            .trap,
            => if (!mir.tagOf(id).isTerminator()) try self.define(id, empty_set, empty_set),
        }
    }

    /// The signature a call applies. Every callee is a callable: a call
    /// through an erased closure goes through its entry, whose signature
    /// takes the environment as integer words under `read`, which is why it
    /// lends and moves nothing here.
    fn signatureOf(self: *const Phase, ty: TypeId) types_mod.CallableSignature {
        return self.module.types.get(ty).callable;
    }

    /// Every argument is read; a sink argument moves its whole root out; an
    /// inout argument changes the bytes it lends; the signature's clauses
    /// say what the result and the retained roots carry afterwards.
    fn callEffects(self: *Phase, id: InstId, args: []const InstId, s: types_mod.CallableSignature) !void {
        const mir = self.mir;
        for (args) |a| try self.useValue(id, a);
        const params = self.module.types.callableParams(s);
        // The callable phase before this one holds every call to its
        // signature's arity.
        std.debug.assert(params.len == args.len);

        // What the result and the retained destinations carry, from the
        // arguments as they stand before the call changes them: what the
        // argument's bytes hold, carried whole into a result and held at the
        // destination's bytes by `retains`.
        var result_deps: SetId = empty_set;
        var result_marks: MarkId = empty_set;
        // A result whose type holds no dependency carries none, whatever the
        // signature promises: a generic signature's clause names what `T`
        // might hold, and ownership reads an instance that cannot hold a view
        // as independent.
        const result_carries = self.mayCarry(s.result);
        for (s.contracts) |contract| {
            if (contract.source.root != .parameter or contract.source.fields.len != 0) continue;
            const p = contract.source.root.parameter;
            if (p >= args.len) continue;
            const b = self.base[args[p].index()];
            const a = self.accessOf(b, params[p].ty);
            // A register argument is the carrier itself and holds its
            // dependencies relative to its referent; the whole value goes.
            const window: Access = if (b.carrier == self.instEntity(args[p])) Access.whole(held_whole - 1) else a;
            const to: Placement = switch (contract.kind) {
                .borrows, .carries => .whole,
                .retains => blk: {
                    const dest = contract.destination orelse continue;
                    if (dest.root != .parameter or dest.fields.len != 0) continue;
                    const d = dest.root.parameter;
                    if (d >= args.len) continue;
                    const db = self.base[args[d].index()];
                    if (db.root == no_entity) continue;
                    const r = self.accessOf(db, params[d].ty).first();
                    break :blk .{ .at = .{ .off = r.off, .len = r.len, .structure = false } };
                },
            };
            // A register argument is the carrier itself, and what a result
            // derived from it observes is what it observes.
            const views: Views = if (b.carrier == self.instEntity(args[p]))
                .keep
            else if (contract.kind == .borrows or contract.borrows_source)
                viewsBorrowed(b)
            else
                viewsRead(b);
            var carried: SetId = if (b.carrier != no_entity) try self.project(self.deps[b.carrier], window, to, views) else empty_set;
            const carried_marks: MarkId = if (b.carrier != no_entity) try self.projectMarks(self.stale[b.carrier], window, to, views) else empty_set;
            if (contract.kind == .borrows or contract.borrows_source) {
                if (b.root != no_entity) {
                    const r = a.first();
                    const held: Range = switch (to) {
                        .at => |t| .{ .off = t.off, .len = t.len },
                        else => .{ .off = 0, .len = held_whole },
                    };
                    const role: Dep.Role = if (to == .at) .held else .view;
                    carried = try self.cons(.{ .hoff = held.off, .hlen = held.len, .root = b.root, .off = r.off, .len = r.len, .role = role }, carried);
                }
            }
            switch (contract.kind) {
                .borrows, .carries => {
                    if (!result_carries or !targetCarriesWhole(contract.target)) continue;
                    result_deps = try self.unionOf(result_deps, carried);
                    result_marks = try self.markUnion(result_marks, carried_marks);
                },
                .retains => {
                    const db = self.base[args[contract.destination.?.root.parameter].index()];
                    var v = self.valuesOf(db.root);
                    v.deps = try self.unionOf(v.deps, carried);
                    v.stale = try self.markUnion(v.stale, carried_marks);
                    try self.set(db.root, v);
                },
            }
        }

        for (args, params) |a, param| {
            const b = self.base[a.index()];
            switch (param.convention) {
                .sink => try self.moveOut(id, b, param.ty),
                .inout => if (b.root != no_entity) try self.invalidate(b.root, self.accessOf(b, param.ty), id),
                .read => {},
            }
        }

        if (mir.tagOf(id) == .call or mir.tagOf(id) == .call_indirect) {
            try self.set(self.instEntity(id), .{ .deps = result_deps, .stale = result_marks });
        }
    }

    /// Whether a result target lets the clause reach the whole result. A
    /// variant payload does: any use of the enum value reads it, which is
    /// what ownership refuses too. A field target does not, because a read of
    /// a sibling field is not a use ownership refuses, so the clause is a miss.
    fn targetCarriesWhole(target: []const types_mod.ResultSelector) bool {
        for (target) |selector| {
            if (selector != .payload) return false;
        }
        return true;
    }

    // -- Control flow: reachable blocks, reverse postorder, dominators. --

    fn controlFlow(self: *Phase) !void {
        const mir = self.mir;
        const gpa = self.gpa;
        const count = mir.blocks.len;

        // Postorder over reachable blocks, iteratively.
        var post: std.ArrayList(BlockId) = .empty;
        defer post.deinit(gpa);
        const seen = try gpa.alloc(bool, count);
        defer gpa.free(seen);
        @memset(seen, false);
        const Frame = struct { block: BlockId, next: u8 };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(gpa);
        seen[mir.entry.index()] = true;
        try stack.append(gpa, .{ .block = mir.entry, .next = 0 });
        while (stack.items.len > 0) {
            const top = &stack.items[stack.items.len - 1];
            const successors = mir.successorsOf(mir.terminatorOf(top.block));
            if (top.next < 2) {
                const which = top.next;
                top.next += 1;
                if (successors[which]) |s| {
                    if (!seen[s.index()]) {
                        seen[s.index()] = true;
                        try stack.append(gpa, .{ .block = s, .next = 0 });
                    }
                }
                continue;
            }
            try post.append(gpa, top.block);
            _ = stack.pop();
        }

        const order = try gpa.alloc(BlockId, post.items.len);
        for (order, 0..) |*o, i| o.* = post.items[post.items.len - 1 - i];
        self.order = order;
        for (order, 0..) |b, i| self.rpo_index[b.index()] = @intCast(i);

        // Predecessors of reachable blocks, as intrusive lists.
        var edges: u32 = 0;
        for (order) |b| for (mir.successorsOf(mir.terminatorOf(b))) |s| {
            if (s != null) edges += 1;
        };
        const pred_next = try gpa.alloc(u32, edges);
        const pred_block = try gpa.alloc(u32, edges);
        self.pred_next = pred_next;
        self.pred_block = pred_block;
        var at: u32 = 0;
        for (order) |b| for (mir.successorsOf(mir.terminatorOf(b))) |successor| {
            const s = successor orelse continue;
            pred_block[at] = b.index();
            pred_next[at] = self.pred_first[s.index()];
            self.pred_first[s.index()] = at;
            at += 1;
        };

        // Immediate dominators by semidominators: a depth-first numbering,
        // each vertex's semidominator from its predecessors -- an earlier
        // vertex directly, a later one through the least semidominator on
        // the path down to it, found with path compression -- and then one
        // walk up the tree per vertex to where the semidominator is reached.
        // A block entered from many deeper blocks, which a loop of many
        // conditional exits has, costs that block one walk and not one per
        // predecessor.
        try self.dominators();

        // An edge back to a block that does not dominate its source is a
        // loop no walk of the dominator tree joins at a header, which
        // structured lowering never emits; it is reported, not analysed.
        for (order) |b| {
            var p = self.pred_first[b.index()];
            while (p != none) : (p = pred_next[p]) {
                const pb = pred_block[p];
                if (self.rpo_index[pb] >= self.rpo_index[b.index()] and !self.dominatesByChain(b.index(), pb)) self.irreducible = true;
            }
        }

        // Children in reverse postorder, so a forward predecessor's subtree
        // is walked before the block it reaches.
        var i = order.len;
        while (i > 1) {
            i -= 1;
            const b = order[i].index();
            const d = self.idom[b];
            self.child_next[b] = self.child_first[d];
            self.child_first[d] = b;
        }

        // Entry and exit numbers of one walk of the dominator tree, so that
        // one block dominating another is a comparison of intervals.
        var visit: std.ArrayList(u32) = .empty;
        defer visit.deinit(gpa);
        var cursor: std.ArrayList(u32) = .empty;
        defer cursor.deinit(gpa);
        var clock: u32 = 0;
        try visit.append(gpa, mir.entry.index());
        try cursor.append(gpa, self.child_first[mir.entry.index()]);
        self.tree_enter[mir.entry.index()] = clock;
        clock += 1;
        while (visit.items.len > 0) {
            const top = visit.items[visit.items.len - 1];
            const next = cursor.items[cursor.items.len - 1];
            if (next != none) {
                cursor.items[cursor.items.len - 1] = self.child_next[next];
                self.tree_enter[next] = clock;
                clock += 1;
                try visit.append(gpa, next);
                try cursor.append(gpa, self.child_first[next]);
                continue;
            }
            self.tree_exit[top] = clock;
            clock += 1;
            _ = visit.pop();
            _ = cursor.pop();
        }
    }

    fn dominators(self: *Phase) !void {
        const mir = self.mir;
        const gpa = self.gpa;
        const count = mir.blocks.len;
        const entry = mir.entry.index();
        const pre = try gpa.alloc(u32, count);
        defer gpa.free(pre);
        @memset(pre, none);
        const parent = try gpa.alloc(u32, count);
        defer gpa.free(parent);
        const vertex = try gpa.alloc(u32, self.order.len);
        defer gpa.free(vertex);
        const sdom = try gpa.alloc(u32, count);
        defer gpa.free(sdom);
        const label = try gpa.alloc(u32, count);
        defer gpa.free(label);
        const ancestor = try gpa.alloc(u32, count);
        defer gpa.free(ancestor);
        @memset(ancestor, none);

        // Preorder of the depth-first tree over successors, iteratively.
        var numbered: u32 = 0;
        const Frame = struct { block: u32, next: u8 };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(gpa);
        pre[entry] = 0;
        vertex[0] = entry;
        parent[entry] = none;
        numbered = 1;
        try stack.append(gpa, .{ .block = entry, .next = 0 });
        while (stack.items.len > 0) {
            const top = &stack.items[stack.items.len - 1];
            if (top.next >= 2) {
                _ = stack.pop();
                continue;
            }
            const successors = mir.successorsOf(mir.terminatorOf(BlockId.at(top.block)));
            const which = top.next;
            top.next += 1;
            const s = (successors[which] orelse continue).index();
            if (pre[s] != none) continue;
            pre[s] = numbered;
            vertex[numbered] = s;
            parent[s] = top.block;
            numbered += 1;
            try stack.append(gpa, .{ .block = s, .next = 0 });
        }
        std.debug.assert(numbered == self.order.len);
        for (0..count) |b| {
            sdom[b] = pre[b];
            label[b] = @intCast(b);
        }

        var path: std.ArrayList(u32) = .empty;
        defer path.deinit(gpa);
        var i = numbered;
        while (i > 1) {
            i -= 1;
            const v = vertex[i];
            var p = self.pred_first[v];
            while (p != none) : (p = self.pred_next[p]) {
                const u = self.pred_block[p];
                const candidate = if (pre[u] < pre[v]) pre[u] else sdom[try evalCompressed(u, ancestor, label, sdom, &path, gpa)];
                if (candidate < sdom[v]) sdom[v] = candidate;
            }
            ancestor[v] = parent[v];
        }

        self.idom[entry] = entry;
        for (vertex[1..]) |v| {
            var d = parent[v];
            while (pre[d] > sdom[v]) d = self.idom[d];
            self.idom[v] = d;
        }
    }

    /// The vertex with the least semidominator on the path from `v` up to
    /// the root of its tree in the forest, compressing the path so that the
    /// next question about any vertex on it is one step.
    fn evalCompressed(v: u32, ancestor: []u32, label: []u32, sdom: []const u32, path: *std.ArrayList(u32), gpa: std.mem.Allocator) !u32 {
        if (ancestor[v] == none) return v;
        path.clearRetainingCapacity();
        var at = v;
        while (ancestor[ancestor[at]] != none) : (at = ancestor[at]) try path.append(gpa, at);
        // `at` hangs directly off the root; everything on the path is
        // relinked to the root with the least label found above it.
        var j = path.items.len;
        while (j > 0) {
            j -= 1;
            const x = path.items[j];
            const above = ancestor[x];
            if (sdom[label[above]] < sdom[label[x]]) label[x] = label[above];
            ancestor[x] = ancestor[above];
        }
        return label[v];
    }

    fn dominates(self: *const Phase, a: u32, b: u32) bool {
        return self.tree_enter[a] <= self.tree_enter[b] and self.tree_exit[b] <= self.tree_exit[a];
    }

    /// Dominance up the immediate-dominator chain, for before the tree is
    /// numbered.
    fn dominatesByChain(self: *const Phase, a: u32, b: u32) bool {
        var at = b;
        while (true) {
            if (at == a) return true;
            if (at == self.mir.entry.index()) return false;
            at = self.idom[at];
        }
    }

    // -- The walk. --

    fn check(self: *Phase, addresses: []const Address) !void {
        const mir = self.mir;
        self.prepare(addresses);
        try self.controlFlow();

        const cells = @as(usize, self.order.len) * self.entity_count;
        const work = @as(usize, mir.insts.len) * self.entity_count;
        if (std.debug.runtime_safety and cells <= dual_cells_max and work <= dual_work_max and cells > 0) {
            const dual = try self.gpa.alloc(Values, cells);
            @memset(dual, .{});
            self.dual_entry = dual;
        }

        if (self.irreducible) {
            self.ok = false;
            try self.sink.add(.{
                .severity = .err,
                .message = try std.fmt.allocPrint(self.sink.arena, "compiler defect: in `{s}`, an edge enters a loop other than at the block that dominates it", .{self.module.nameOf(self.id)}),
                .labels = &.{},
                .notes = &.{defect_note},
            });
            return;
        }

        try self.walk(mir.entry.index());
        try self.report();

        if (self.dual_entry != null) try self.dense();
    }

    /// One block on the walk's own stack: which child comes next, and
    /// whether the block's own instructions have been stepped since it was
    /// last entered.
    const Pending = struct { block: u32, child: u32, entered: bool };

    /// A block's entry is its dominator's exit plus the join of what every
    /// predecessor changed after that dominator; then its own instructions;
    /// then its dominator-tree children, each from this block's exit. A back
    /// edge's predecessor is a descendant, so the join is recomputed once the
    /// subtree is done and the subtree walked again while it grows. The
    /// stack is explicit, because a dominator tree is as deep as a function
    /// has sequential conditionals.
    fn walk(self: *Phase, root: u32) std.mem.Allocator.Error!void {
        const entry = self.mir.entry.index();
        var pending: std.ArrayList(Pending) = .empty;
        defer pending.deinit(self.gpa);
        try pending.append(self.gpa, .{ .block = root, .child = none, .entered = false });
        while (pending.items.len > 0) {
            const top = &pending.items[pending.items.len - 1];
            const b = top.block;
            if (!top.entered) {
                const d = self.idom[b];
                self.rollback(if (b == entry) 0 else self.exit_mark[d]);
                const start: u32 = @intCast(self.trail.items.len);
                self.block_start = start;
                // The entry block joins too where a back edge reaches it.
                if (b != entry or self.pred_first[b] != none) try self.join(b);
                if (self.dual_entry) |dual| {
                    const row = dual[@as(usize, self.rpo_index[b]) * self.entity_count ..][0..self.entity_count];
                    for (row, 0..) |*v, e| v.* = self.valuesOf(@intCast(e));
                }
                const block = BlockId.at(b);
                for (self.mir.instsOf(block)) |id| try self.step(id);
                try self.step(self.mir.terminatorOf(block));
                self.exit_mark[b] = @intCast(self.trail.items.len);
                try self.saveSegment(b, start);
                top.entered = true;
                top.child = self.child_first[b];
                continue;
            }
            if (top.child != none) {
                const c = top.child;
                top.child = self.child_next[c];
                try pending.append(self.gpa, .{ .block = c, .child = none, .entered = false });
                continue;
            }
            if (self.hasBackEdge(b) and try self.joinGrew(b)) {
                top.entered = false;
                continue;
            }
            _ = pending.pop();
            if (pending.items.len > 0) self.rollback(self.exit_mark[pending.items[pending.items.len - 1].block]);
        }
    }

    fn hasBackEdge(self: *const Phase, b: u32) bool {
        var p = self.pred_first[b];
        while (p != none) : (p = self.pred_next[p]) {
            if (self.dominates(b, self.pred_block[p])) return true;
        }
        return false;
    }

    fn saveSegment(self: *Phase, b: u32, start: u32) !void {
        const changes = self.trail.items[start..];
        const at: u32 = @intCast(self.saved.items.len);
        for (changes) |c| if (c == .state) try self.saved.append(self.gpa, c);
        self.segment[b] = .{ .start = at, .len = @intCast(self.saved.items.len - at) };
        self.segment_valid[b] = true;
    }

    /// One entity's join in progress: what the predecessors that touched it
    /// gave it, and how many did.
    const Joined = struct { values: Values, touched: u32 };

    /// One step of a join's walk down the dominator tree: a block on some
    /// predecessor's chain, the child to visit next, and where its entries
    /// in the undo log begin.
    const Descent = struct { block: u32, child: u32, undo_mark: u32 };

    /// A value a segment gave an entity, and how many predecessors see it as
    /// their last: those entering from the segment's subtree, less those
    /// under a deeper segment that gave the entity another value.
    const Given = struct { entity: Entity, values: Values, seen_by: u32 };

    const Undo = struct { entity: Entity, old: ?u32 };

    /// The last value each predecessor gave each entity since the dominator,
    /// OR-ed and unioned across predecessors, over the entities any of them
    /// touched. A predecessor that left an entity alone contributes the
    /// dominator's exit value, which is the current one; an entity every
    /// predecessor rewrote takes only what they wrote.
    ///
    /// A predecessor's values are the dominator's exit plus the segments on
    /// its chain up the dominator tree, and predecessors share the top of
    /// their chains. So the chains are marked up to the first block already
    /// marked, and two walks down the tree over the marked blocks do the
    /// rest: the first counts the predecessors below each block, the second
    /// replays each segment once, crediting each value it gives an entity
    /// with the predecessors below and debiting the value it overrides. The
    /// cost is the segments on the chains, not the chains times their
    /// length.
    fn joined(self: *Phase, b: u32, out: *std.AutoArrayHashMapUnmanaged(Entity, Values)) !void {
        const d = self.idom[b];
        var partial: std.AutoArrayHashMapUnmanaged(Entity, Joined) = .empty;
        defer partial.deinit(self.gpa);
        var given: std.ArrayList(Given) = .empty;
        defer given.deinit(self.gpa);
        var current: std.AutoArrayHashMapUnmanaged(Entity, u32) = .empty;
        defer current.deinit(self.gpa);
        var undo: std.ArrayList(Undo) = .empty;
        defer undo.deinit(self.gpa);
        var descent: std.ArrayList(Descent) = .empty;
        defer descent.deinit(self.gpa);

        // How many times each block enters `b`, and which blocks lie on a
        // chain; all cleared again before returning.
        var preds: u32 = 0;
        var p = self.pred_first[b];
        while (p != none) : (p = self.pred_next[p]) {
            const pb = self.pred_block[p];
            if (!self.segment_valid[pb]) continue;
            preds += 1;
            self.pred_times[pb] += 1;
            var at = pb;
            while (at != d and !self.on_chain[at]) : (at = self.idom[at]) self.on_chain[at] = true;
        }
        defer {
            var q = self.pred_first[b];
            while (q != none) : (q = self.pred_next[q]) {
                const pb = self.pred_block[q];
                self.pred_times[pb] = 0;
                var at = pb;
                while (at != d and self.on_chain[at]) : (at = self.idom[at]) {
                    self.on_chain[at] = false;
                    self.chain_preds[at] = 0;
                }
            }
        }

        // The predecessors below each block on a chain, summed on the way
        // out of the first walk.
        try descent.append(self.gpa, .{ .block = d, .child = self.child_first[d], .undo_mark = 0 });
        while (descent.items.len > 0) {
            const top = &descent.items[descent.items.len - 1];
            const child = top.child;
            if (child != none) {
                top.child = self.child_next[child];
                if (!self.on_chain[child]) continue;
                self.chain_preds[child] = self.pred_times[child];
                try descent.append(self.gpa, .{ .block = child, .child = self.child_first[child], .undo_mark = 0 });
                continue;
            }
            const done = descent.pop().?;
            if (descent.items.len > 0 and done.block != d) {
                const parent = descent.items[descent.items.len - 1].block;
                if (parent != d) self.chain_preds[parent] += self.chain_preds[done.block];
            }
        }

        try descent.append(self.gpa, .{ .block = d, .child = self.child_first[d], .undo_mark = 0 });
        while (descent.items.len > 0) {
            const top = &descent.items[descent.items.len - 1];
            const child = top.child;
            if (child != none) {
                top.child = self.child_next[child];
                if (!self.on_chain[child]) continue;
                const mark: u32 = @intCast(undo.items.len);
                const below = self.chain_preds[child];
                const seg = self.segment[child];
                for (self.saved.items[seg.start..][0..seg.len]) |c| {
                    const e = c.state.entity;
                    const got = try current.getOrPut(self.gpa, e);
                    if (got.found_existing) given.items[got.value_ptr.*].seen_by -= below;
                    try undo.append(self.gpa, .{ .entity = e, .old = if (got.found_existing) got.value_ptr.* else null });
                    got.value_ptr.* = @intCast(given.items.len);
                    try given.append(self.gpa, .{ .entity = e, .values = c.state.new, .seen_by = below });
                }
                try descent.append(self.gpa, .{ .block = child, .child = self.child_first[child], .undo_mark = mark });
                continue;
            }
            const done = descent.pop().?;
            while (undo.items.len > done.undo_mark) {
                const u = undo.pop().?;
                if (u.old) |old| current.putAssumeCapacity(u.entity, old) else _ = current.swapRemove(u.entity);
            }
        }

        for (given.items) |g| {
            if (g.seen_by == 0) continue;
            const got = try partial.getOrPut(self.gpa, g.entity);
            if (!got.found_existing) {
                got.value_ptr.* = .{ .values = g.values, .touched = g.seen_by };
            } else {
                got.value_ptr.values = try self.meet(got.value_ptr.values, g.values);
                got.value_ptr.touched += g.seen_by;
            }
        }
        for (partial.keys(), partial.values()) |e, j| {
            const values = if (j.touched < preds) try self.meet(j.values, self.valuesOf(e)) else j.values;
            try out.put(self.gpa, e, values);
        }
    }

    fn meet(self: *Phase, a: Values, b: Values) !Values {
        return .{
            .moved = a.moved or b.moved,
            .moved_at = if (a.moved_at != .none) a.moved_at else b.moved_at,
            .deps = try self.unionOf(a.deps, b.deps),
            .stale = try self.markUnion(a.stale, b.stale),
            .events = try self.unionOf(a.events, b.events),
        };
    }

    fn join(self: *Phase, b: u32) !void {
        var out: std.AutoArrayHashMapUnmanaged(Entity, Values) = .empty;
        defer out.deinit(self.gpa);
        try self.joined(b, &out);
        self.applied[b].clearRetainingCapacity();
        for (out.keys(), out.values()) |e, v| {
            try self.applied[b].append(self.gpa, .{ .entity = e, .values = v });
            try self.set(e, v);
        }
    }

    /// Whether recomputing a header's join, now that its back edges have
    /// segments, changes what was applied.
    fn joinGrew(self: *Phase, b: u32) !bool {
        var out: std.AutoArrayHashMapUnmanaged(Entity, Values) = .empty;
        defer out.deinit(self.gpa);
        // From the dominator's exit state, as `join` sees it.
        self.rollback(if (b == self.mir.entry.index()) 0 else self.exit_mark[self.idom[b]]);
        try self.joined(b, &out);
        if (out.count() != self.applied[b].items.len) return true;
        for (self.applied[b].items) |was| {
            const now = out.get(was.entity) orelse return true;
            if (!std.meta.eql(now, was.values)) return true;
        }
        return false;
    }

    // -- The dense dual. --

    /// The same fixpoint with one state per block, compared against what the
    /// trail walk saw at each block's entry.
    fn dense(self: *Phase) !void {
        const dual = self.dual_entry.?;
        const n = self.order.len;
        const width = self.entity_count;
        const in = try self.gpa.alloc(Values, n * width);
        defer self.gpa.free(in);
        @memset(in, .{});
        const computed = try self.gpa.alloc(bool, n);
        defer self.gpa.free(computed);
        @memset(computed, false);
        computed[0] = true;

        self.logging = false;
        self.reporting = false;
        defer self.logging = true;
        defer self.reporting = true;

        var changed = true;
        while (changed) {
            changed = false;
            for (self.order, 0..) |b, i| {
                if (!computed[i]) continue;
                const row = in[i * width ..][0..width];
                for (row, 0..) |v, e| self.store(@intCast(e), v);
                const block = b;
                for (self.mir.instsOf(block)) |id| try self.step(id);
                try self.step(self.mir.terminatorOf(block));
                for (self.mir.successorsOf(self.mir.terminatorOf(block))) |successor| {
                    const s = successor orelse continue;
                    const si = self.rpo_index[s.index()];
                    const target = in[si * width ..][0..width];
                    if (!computed[si]) {
                        for (target, 0..) |*t, e| t.* = self.valuesOf(@intCast(e));
                        computed[si] = true;
                        changed = true;
                        continue;
                    }
                    for (target, 0..) |*t, e| {
                        const now = self.valuesOf(@intCast(e));
                        const met = try self.meet(t.*, now);
                        if (!std.meta.eql(met, t.*)) {
                            t.* = met;
                            changed = true;
                        }
                    }
                }
            }
        }

        for (0..n) |i| {
            const trail_row = dual[i * width ..][0..width];
            const dense_row = in[i * width ..][0..width];
            for (trail_row, dense_row, 0..) |t, d, e| {
                if (!std.meta.eql(t, d)) {
                    std.debug.print("DUAL MISMATCH in `{s}` block @{d} (rpo {d}) entity {d} (slots {d}): trail moved={} deps={d} stale={d} events={d}; dense moved={} deps={d} stale={d} events={d}\n", .{
                        self.module.nameOf(self.id), self.order[i].index(), i, e, self.slot_count, t.moved, t.deps, t.stale, t.events, d.moved, d.deps, d.stale, d.events,
                    });
                }
                std.debug.assert(std.meta.eql(t, d));
            }
        }
    }

    // -- Reporting. --

    fn nameOf(self: *const Phase, arena: std.mem.Allocator, e: Entity) ![]const u8 {
        if (e < self.slot_count) return std.fmt.allocPrint(arena, "slot ${d}", .{e});
        return std.fmt.allocPrint(arena, "%{d}", .{e - self.slot_count});
    }

    fn report(self: *Phase) !void {
        const arena = self.sink.arena;
        for (self.refusals.items) |r| {
            self.ok = false;
            const name = try self.nameOf(arena, r.entity);
            const what = switch (r.kind) {
                .stale => try std.fmt.allocPrint(arena, "%{d} uses {s} after %{d} {s} the storage it observes", .{
                    r.at.index(), name, r.cause.index(), self.causeVerb(r.cause),
                }),
                .moved => try std.fmt.allocPrint(arena, "%{d} reads {s} after %{d} moved it out", .{
                    r.at.index(), name, r.cause.index(),
                }),
            };
            const labels = try arena.alloc(Label, 2);
            labels[0] = .{
                .file = self.mir.file,
                .span = self.mir.spanOf(r.at),
                .message = "the code generated from here would not be what this says",
                .style = .primary,
            };
            labels[1] = .{
                .file = self.mir.file,
                .span = self.mir.spanOf(r.cause),
                .message = switch (r.kind) {
                    .stale => "the storage changed here",
                    .moved => "the value moved out here",
                },
                .style = .secondary,
            };
            try self.sink.add(.{
                .severity = .err,
                .message = try std.fmt.allocPrint(arena, "compiler defect: in `{s}`, {s}", .{ self.module.nameOf(self.id), what }),
                .labels = labels,
                .notes = &.{defect_note},
            });
        }
    }

    fn causeVerb(self: *const Phase, cause: InstId) []const u8 {
        return switch (self.mir.tagOf(cause)) {
            .call, .call_indirect, .call_noreturn, .call_indirect_noreturn => "lent for writing or took",
            .move_value => "moved",
            else => "wrote",
        };
    }
};

comptime {
    _ = Phase;
}

// -- Tests --
//
// Every refusal is provoked from a hand-built `Mir`, and every accepted shape
// is one the corpus holds and ownership accepts: a loop initialising a slot
// part by part, a view re-created on each pass. The Debug dual runs under
// each of them, so the trail and the dense fixpoint are held equal here too.

const Harness = verify_mod.Harness;
const Builder = Mir.Builder;
const CallableContract = types_mod.CallableContract;

const borrows_first: []const CallableContract = &.{.{ .kind = .borrows, .source = .{ .root = .{ .parameter = 0 } } }};
const carries_first: []const CallableContract = &.{.{ .kind = .carries, .source = .{ .root = .{ .parameter = 0 } } }};
const retains_borrow: []const CallableContract = &.{.{
    .kind = .retains,
    .source = .{ .root = .{ .parameter = 1 } },
    .destination = .{ .root = .{ .parameter = 0 } },
    .borrows_source = true,
}};

/// A callee taking one `Big` under the given convention and returning a
/// word, so a caller can lend, move or read through it.
fn takesBig(gpa: std.mem.Allocator, convention: Convention) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    b.param_count = 1;
    _ = try b.addLocal(Harness.big, if (convention == .sink) .value else .managed_address);
    const entry = try b.addBlock();
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });
    return b.finish(entry, .from(0));
}

/// A callee taking two `Big`s by address and returning a word.
fn takesTwoBig(gpa: std.mem.Allocator) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    b.param_count = 2;
    _ = try b.addLocal(Harness.big, .managed_address);
    _ = try b.addLocal(Harness.big, .managed_address);
    const entry = try b.addBlock();
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });
    return b.finish(entry, .from(0));
}

/// A callee lending out a borrow of the one `Big` it reads.
fn returnsBorrowOfBig(gpa: std.mem.Allocator) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = Harness.big_borrow;
    b.param_count = 1;
    const param = try b.addLocal(Harness.big, .managed_address);
    const entry = try b.addBlock();
    const a = try b.addInst(entry, .{ .tag = .load, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = param } });
    const pointer = try b.addInst(entry, .{ .tag = .borrow, .ty = Harness.big_borrow, .span = Span.empty, .data = .{ .unary = a } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = pointer } });
    return b.finish(entry, .from(0));
}

/// A callee taking one word by value.
fn takesWord(gpa: std.mem.Allocator) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    b.param_count = 1;
    _ = try b.addLocal(.u64, .value);
    const entry = try b.addBlock();
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });
    return b.finish(entry, .from(0));
}

const Shapes = struct {
    /// Function 0 is the subject; 1 lends `Big` for reading with `borrows`,
    /// 2 lends it for writing, 3 takes it by sink, 4 takes a word, 5 lends
    /// it for reading with `carries`, 6 returns a borrow of the `Big` it reads
    /// with `borrows`, 7 keeps a borrow of its second `Big` in its first with
    /// `retains`, and 8 returns a borrow of the `Big` it reads with `carries`.
    fn callees(gpa: std.mem.Allocator, subject: Mir) ![]Mir {
        const functions = try gpa.alloc(Mir, 9);
        functions[0] = subject;
        functions[1] = try takesBig(gpa, .read);
        functions[2] = try takesBig(gpa, .inout);
        functions[3] = try takesBig(gpa, .sink);
        functions[4] = try takesWord(gpa);
        functions[5] = try takesBig(gpa, .read);
        functions[6] = try returnsBorrowOfBig(gpa);
        functions[7] = try takesTwoBig(gpa);
        functions[8] = try returnsBorrowOfBig(gpa);
        return functions;
    }

    const shapes = [_]Harness.Shape{
        .{},
        .{ .conventions = &.{.read}, .contracts = borrows_first },
        .{ .conventions = &.{.inout} },
        .{ .conventions = &.{.sink} },
        .{ .conventions = &.{.read} },
        .{ .conventions = &.{.read}, .contracts = carries_first },
        .{ .conventions = &.{.read}, .contracts = borrows_first },
        .{ .conventions = &.{ .inout, .read }, .contracts = retains_borrow },
        .{ .conventions = &.{.read}, .contracts = carries_first },
    };

    const reads: FunctionId = .at(1);
    const lends: FunctionId = .at(2);
    const takes: FunctionId = .at(3);
    const word: FunctionId = .at(4);
    const carries: FunctionId = .at(5);
    const lends_borrow: FunctionId = .at(6);
    const retains: FunctionId = .at(7);
    const carries_borrow: FunctionId = .at(8);
};

fn ret(b: *Builder, block: BlockId, value: InstId) !void {
    _ = try b.setTerminator(block, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });
}

fn constant(b: *Builder, block: BlockId, value: i128) !InstId {
    return b.addInst(block, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = value } });
}

fn addrOf(b: *Builder, block: BlockId, slot: LocalId) !InstId {
    return b.addInst(block, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = slot } });
}

fn expectRefused(functions: []Mir, needle: []const u8) !void {
    var h = try Harness.initShaped(testing.allocator, functions, &Shapes.shapes);
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    for (got.said) |d| if (std.mem.indexOf(u8, d.message, needle) != null) return;
    std.debug.print("no diagnostic said {s}; said:\n", .{needle});
    for (got.said) |d| std.debug.print("  {s}\n", .{d.message});
    return error.TestUnexpectedResult;
}

fn expectAccepted(functions: []Mir) !void {
    var h = try Harness.initShaped(testing.allocator, functions, &Shapes.shapes);
    defer h.deinit();
    const got = try h.run();
    for (got.said) |d| std.debug.print("  {s}\n", .{d.message});
    try testing.expect(got.ok);
}

test "a value carried out of a slot is stale once the slot is lent for writing" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, big);
    const view = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{a});
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.lends, &.{a});
    try ret(&b, entry, view);
    try expectRefused(try Shapes.callees(gpa, try b.finish(entry, .from(0))), "uses %1 after %2 lent for writing or took the storage it observes");
}

test "a value carried out of a slot may be used before the slot is lent for writing" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, big);
    const view = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{a});
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.word, &.{view});
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.lends, &.{a});
    try ret(&b, entry, used);
    try expectAccepted(try Shapes.callees(gpa, try b.finish(entry, .from(0))));
}

test "an array view held in a slot is stale once the array is written" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const held = try b.addLocal(.u64, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, big);
    const bits = try b.addInst(entry, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = a } });
    _ = try b.addInst(entry, .{ .tag = .store, .ty = .u64, .span = Span.empty, .data = .{ .store = .{ .local = held, .value = bits } } });
    const eight = try constant(&b, entry, 8);
    const field = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = eight } } });
    const one = try b.addInst(entry, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = field, .rhs = one } } });
    const again = try b.addInst(entry, .{ .tag = .load, .ty = .u64, .span = Span.empty, .data = .{ .local = held } });
    try ret(&b, entry, again);
    try expectRefused(try Shapes.callees(gpa, try b.finish(entry, .from(0))), "uses %7 after %6 wrote the storage it observes");
}

test "an array view built into a slot from its address bits is stale once the array is written" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const array = try b.addLocal(Harness.big, .value);
    const view = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    // The view's first word is the array's address as an integer, as a
    // `Slice` built over an array holds it.
    const a = try addrOf(&b, entry, array);
    const bits = try b.addInst(entry, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = a } });
    const h = try addrOf(&b, entry, view);
    const zero = try constant(&b, entry, 0);
    const at = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = zero } } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = at, .rhs = bits } } });
    const eight = try constant(&b, entry, 8);
    const element = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = eight } } });
    const one = try b.addInst(entry, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = element, .rhs = one } } });
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{h});
    try ret(&b, entry, used);
    try expectRefused(try Shapes.callees(gpa, try b.finish(entry, .from(0))), "%10 uses slot $1 after %9 wrote the storage it observes");
}

/// Borrows `source`, copies the bytes the borrow points at into a slot of
/// their own, writes `source` through its first word, and reads the copy.
/// With `copy_after_write` the copy is made through the borrow after the
/// write instead.
fn copyThroughBorrow(gpa: std.mem.Allocator, copy_after_write: bool) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const source = try b.addLocal(Harness.big, .value);
    const copied = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, source);
    const pointer = try b.addInst(entry, .{ .tag = .borrow, .ty = Harness.big_borrow, .span = Span.empty, .data = .{ .unary = a } });
    const pointee = try b.addInst(entry, .{ .tag = .observe, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .unary = pointer } });
    const into = try addrOf(&b, entry, copied);
    if (!copy_after_write) _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = into, .rhs = pointee } } });
    const zero = try constant(&b, entry, 0);
    const first = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = zero } } });
    const one = try b.addInst(entry, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = first, .rhs = one } } });
    if (copy_after_write) _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = into, .rhs = pointee } } });
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{into});
    try ret(&b, entry, used);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a copy of the bytes a borrow points at does not observe the place they were copied from" {
    try expectAccepted(try copyThroughBorrow(testing.allocator, false));
}

test "a copy through a borrow after its place was written is refused" {
    try expectRefused(try copyThroughBorrow(testing.allocator, true), "uses");
}

/// Stores the address bits of `x` in the first word of a holder, borrows the
/// holder, copies the bytes the borrow points at into a slot of their own,
/// writes `x`, and reads the copy.
fn copyOfHolderThroughBorrow(gpa: std.mem.Allocator) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const x = try b.addLocal(Harness.big, .value);
    const holder = try b.addLocal(Harness.big, .value);
    const copied = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, x);
    const bits = try b.addInst(entry, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = a } });
    const h = try addrOf(&b, entry, holder);
    const zero = try constant(&b, entry, 0);
    const first = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = zero } } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = first, .rhs = bits } } });
    const pointer = try b.addInst(entry, .{ .tag = .borrow, .ty = Harness.big_borrow, .span = Span.empty, .data = .{ .unary = h } });
    const pointee = try b.addInst(entry, .{ .tag = .observe, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .unary = pointer } });
    const into = try addrOf(&b, entry, copied);
    _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = into, .rhs = pointee } } });
    const element = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = zero } } });
    const one = try b.addInst(entry, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = element, .rhs = one } } });
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{into});
    try ret(&b, entry, used);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a copy through a borrow still observes what the bytes it copied held" {
    try expectRefused(try copyOfHolderThroughBorrow(testing.allocator), "uses slot $2 after");
}

/// Writes the first word of the slot `a` addresses.
fn writeFirstWord(b: *Builder, block: BlockId, a: InstId) !void {
    const zero = try constant(b, block, 0);
    const first = try b.addInst(block, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = zero } } });
    const one = try b.addInst(block, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(block, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = first, .rhs = one } } });
}

/// Stores the address bits of the slot `a` addresses in the first word of the
/// slot `holder` addresses.
fn storeAddressBits(b: *Builder, block: BlockId, holder: InstId, a: InstId) !void {
    const bits = try b.addInst(block, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = a } });
    const zero = try constant(b, block, 0);
    const first = try b.addInst(block, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = holder, .rhs = zero } } });
    _ = try b.addInst(block, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = first, .rhs = bits } } });
}

/// Loads, through a borrow of `holder`, the borrow stored in the holder's
/// first word, writes the second word of the holder, and uses the loaded
/// borrow. The holder's first word views `x`.
fn borrowLoadedThroughBorrow(gpa: std.mem.Allocator) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const x = try b.addLocal(Harness.big, .value);
    const holder = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, x);
    const h = try addrOf(&b, entry, holder);
    try storeAddressBits(&b, entry, h, a);
    const pointer = try b.addInst(entry, .{ .tag = .borrow, .ty = Harness.big_borrow, .span = Span.empty, .data = .{ .unary = h } });
    const pointee = try b.addInst(entry, .{ .tag = .observe, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .unary = pointer } });
    const zero = try constant(&b, entry, 0);
    const cell = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = Harness.big_borrow, .span = Span.empty, .data = .{ .binary = .{ .lhs = pointee, .rhs = zero } } });
    const loaded = try b.addInst(entry, .{ .tag = .load_indirect, .ty = Harness.big_borrow, .span = Span.empty, .data = .{ .unary = cell } });
    const word_size = try constant(&b, entry, 8);
    const second = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = word_size } } });
    const one = try b.addInst(entry, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = second, .rhs = one } } });
    const reached = try b.addInst(entry, .{ .tag = .observe, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .unary = loaded } });
    const used = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .u64, .span = Span.empty, .data = .{ .unary = reached } });
    try ret(&b, entry, used);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a borrow loaded through a borrow of its holder does not observe the holder" {
    try expectAccepted(try borrowLoadedThroughBorrow(testing.allocator));
}

/// Borrows `x`, passes the bytes the borrow points at to a callee whose
/// result carries its argument, writes `x`, and uses the result.
fn carriedThroughBorrow(gpa: std.mem.Allocator) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const x = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, x);
    const pointer = try b.addInst(entry, .{ .tag = .borrow, .ty = Harness.big_borrow, .span = Span.empty, .data = .{ .unary = a } });
    const pointee = try b.addInst(entry, .{ .tag = .observe, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .unary = pointer } });
    const carried = try b.addCall(entry, .value, .u64, Span.empty, Shapes.carries, &.{pointee});
    try writeFirstWord(&b, entry, a);
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.word, &.{carried});
    try ret(&b, entry, used);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a result carried from the bytes a borrow points at does not observe the place they came from" {
    try expectAccepted(try carriedThroughBorrow(testing.allocator));
}

/// Gets a borrow of `x` from a `borrows` callee, copies the bytes it points
/// at into a slot of their own, writes `x`, and reads the copy.
fn copyThroughReturnedBorrow(gpa: std.mem.Allocator) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const x = try b.addLocal(Harness.big, .value);
    const copied = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, x);
    const returned = try b.addCall(entry, .value, Harness.big_borrow, Span.empty, Shapes.lends_borrow, &.{a});
    const pointee = try b.addInst(entry, .{ .tag = .observe, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .unary = returned } });
    const into = try addrOf(&b, entry, copied);
    _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = into, .rhs = pointee } } });
    try writeFirstWord(&b, entry, a);
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{into});
    try ret(&b, entry, used);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a copy through a borrow a callee returned does not observe the place it was copied from" {
    try expectAccepted(try copyThroughReturnedBorrow(testing.allocator));
}

/// Stores the address bits of `x` in a holder, gets a borrow of the holder
/// from a `borrows` callee, copies the bytes it points at into a slot of
/// their own, writes `x`, and reads the copy.
fn copyOfHolderThroughReturnedBorrow(gpa: std.mem.Allocator) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const x = try b.addLocal(Harness.big, .value);
    const holder = try b.addLocal(Harness.big, .value);
    const copied = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, x);
    const h = try addrOf(&b, entry, holder);
    try storeAddressBits(&b, entry, h, a);
    const returned = try b.addCall(entry, .value, Harness.big_borrow, Span.empty, Shapes.lends_borrow, &.{h});
    const pointee = try b.addInst(entry, .{ .tag = .observe, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .unary = returned } });
    const into = try addrOf(&b, entry, copied);
    _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = into, .rhs = pointee } } });
    try writeFirstWord(&b, entry, a);
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{into});
    try ret(&b, entry, used);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a copy through a borrow a callee returned still observes what the bytes it copied held" {
    try expectRefused(try copyOfHolderThroughReturnedBorrow(testing.allocator), "uses slot $2 after");
}

/// Keeps a borrow of `x` in a holder with a `retains` callee, gets a borrow
/// back out of the holder with a `carries` callee, copies the bytes it
/// points at into a slot of their own, writes `x`, and reads the copy.
fn copyThroughBorrowCarriedOutOfRetainer(gpa: std.mem.Allocator) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const x = try b.addLocal(Harness.big, .value);
    const holder = try b.addLocal(Harness.big, .value);
    const copied = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, x);
    const h = try addrOf(&b, entry, holder);
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.retains, &.{ h, a });
    const returned = try b.addCall(entry, .value, Harness.big_borrow, Span.empty, Shapes.carries_borrow, &.{h});
    const pointee = try b.addInst(entry, .{ .tag = .observe, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .unary = returned } });
    const into = try addrOf(&b, entry, copied);
    _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = into, .rhs = pointee } } });
    try writeFirstWord(&b, entry, a);
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{into});
    try ret(&b, entry, used);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a copy through a borrow kept by a retaining call still observes the place that borrow views" {
    try expectRefused(try copyThroughBorrowCarriedOutOfRetainer(testing.allocator), "uses slot $2 after");
}

/// Builds a slot `p` holding, in its first two words, the address bits of
/// two other slots, lends the first for writing, and reads the word at
/// `read_off`: the sibling's observation survives, the lent one's does not.
fn twoObservationsThenLend(gpa: std.mem.Allocator, read_off: i128) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const x = try b.addLocal(Harness.big, .value);
    const y = try b.addLocal(Harness.big, .value);
    const p = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, x);
    const bits_x = try b.addInst(entry, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = a } });
    const h = try addrOf(&b, entry, p);
    const zero = try constant(&b, entry, 0);
    const first = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = zero } } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = first, .rhs = bits_x } } });
    const c = try addrOf(&b, entry, y);
    const bits_y = try b.addInst(entry, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = c } });
    const eight = try constant(&b, entry, 8);
    const second = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = eight } } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = second, .rhs = bits_y } } });
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.lends, &.{a});
    const at = try constant(&b, entry, read_off);
    const part = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = at } } });
    const read = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .u64, .span = Span.empty, .data = .{ .unary = part } });
    try ret(&b, entry, read);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a part of a slot is read while another part's observation is stale" {
    try expectAccepted(try twoObservationsThenLend(testing.allocator, 8));
}

test "the part of a slot holding a stale observation is not read" {
    try expectRefused(try twoObservationsThenLend(testing.allocator, 0), "%14 uses slot $2 after %11 lent for writing or took the storage it observes");
}

/// Observes the first word of `t`, then writes through an address computed
/// from a run-time index inside `t` at `within_off` -- the whole of `t` at
/// zero, its second word at eight -- and uses the observation.
fn computedWriteBesideObservation(gpa: std.mem.Allocator, within_off: ?i128) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const t = try b.addLocal(Harness.big, .value);
    const index = try b.addLocal(.u64, .value);
    const held = try b.addLocal(.u64, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, t);
    const zero = try constant(&b, entry, 0);
    const first = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = zero } } });
    const bits = try b.addInst(entry, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = first } });
    _ = try b.addInst(entry, .{ .tag = .store, .ty = .u64, .span = Span.empty, .data = .{ .store = .{ .local = held, .value = bits } } });
    const k = try b.addInst(entry, .{ .tag = .load, .ty = .u64, .span = Span.empty, .data = .{ .local = index } });
    var within = a;
    if (within_off) |off| {
        const at = try constant(&b, entry, off);
        within = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = at } } });
    }
    const element = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = within, .rhs = k } } });
    const one = try b.addInst(entry, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = element, .rhs = one } } });
    const again = try b.addInst(entry, .{ .tag = .load, .ty = .u64, .span = Span.empty, .data = .{ .local = held } });
    const used = try b.addCall(entry, .value, .u64, Span.empty, Shapes.word, &.{again});
    try ret(&b, entry, used);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a write at a computed index inside one part leaves an observation of another part live" {
    try expectAccepted(try computedWriteBesideObservation(testing.allocator, 8));
}

test "a write at a computed index inside the whole slot ends an observation of its first part" {
    try expectRefused(try computedWriteBesideObservation(testing.allocator, null), "%10 uses %9 after %8 wrote the storage it observes");
}

test "a dominator tree as deep as the function has blocks is walked" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const depth: u32 = 60000;
    const blocks = try gpa.alloc(BlockId, depth);
    defer gpa.free(blocks);
    for (blocks) |*block| block.* = try b.addBlock();
    const exit = try b.addBlock();
    // Each block observes the slot and branches on to the next or out, so
    // every block's dominator is the one before it.
    for (blocks, 0..) |block, i| {
        const a = try addrOf(&b, block, big);
        const view = try b.addCall(block, .value, .u64, Span.empty, Shapes.reads, &.{a});
        const zero = try constant(&b, block, 0);
        const cond = try b.addInst(block, .{ .tag = .cmp_eq, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = view, .rhs = zero } } });
        const next = if (i + 1 < blocks.len) blocks[i + 1] else exit;
        _ = try b.setTerminator(block, .{ .tag = .branch, .ty = .unit, .span = Span.empty, .data = .{ .branch = .{ .cond = cond, .then_block = next, .else_block = exit } } });
    }
    const k = try constant(&b, exit, 0);
    try ret(&b, exit, k);
    try expectAccepted(try Shapes.callees(gpa, try b.finish(blocks[0], .from(0))));
}

test "an edge into a loop other than at its dominating block is reported" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const first = try b.addBlock();
    const second = try b.addBlock();
    const exit = try b.addBlock();
    // The entry reaches both blocks of the loop, so neither dominates the
    // other, and the edge from the second back to the first enters the loop
    // other than at a header.
    const a = try addrOf(&b, entry, big);
    const view = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{a});
    const zero = try constant(&b, entry, 0);
    const cond = try b.addInst(entry, .{ .tag = .cmp_eq, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = view, .rhs = zero } } });
    _ = try b.setTerminator(entry, .{ .tag = .branch, .ty = .unit, .span = Span.empty, .data = .{ .branch = .{ .cond = cond, .then_block = first, .else_block = second } } });
    _ = try b.addCall(first, .value, .u64, Span.empty, Shapes.word, &.{view});
    _ = try b.setTerminator(first, .{ .tag = .branch, .ty = .unit, .span = Span.empty, .data = .{ .branch = .{ .cond = cond, .then_block = second, .else_block = exit } } });
    _ = try b.addCall(second, .value, .u64, Span.empty, Shapes.lends, &.{a});
    _ = try b.setTerminator(second, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = first } });
    const k = try constant(&b, exit, 0);
    try ret(&b, exit, k);
    try expectRefused(try Shapes.callees(gpa, try b.finish(entry, .from(0))), "an edge enters a loop other than at the block that dominates it");
}

/// Builds a slot holding, in its first and second words, the address bits of
/// two other slots, lends the first for writing, then reads a word through
/// an address a run-time index chose: the word `inner` bytes into some
/// element of the slot read as an array of `elem`-byte elements.
fn twoObservationsThenStridedRead(gpa: std.mem.Allocator, elem: u32, inner: i128) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const x = try b.addLocal(Harness.big, .value);
    const y = try b.addLocal(Harness.big, .value);
    const p = try b.addLocal(Harness.big, .value);
    const index = try b.addLocal(.u64, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, x);
    const bits_x = try b.addInst(entry, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = a } });
    const h = try addrOf(&b, entry, p);
    const zero = try constant(&b, entry, 0);
    const first = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = zero } } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = first, .rhs = bits_x } } });
    const c = try addrOf(&b, entry, y);
    const bits_y = try b.addInst(entry, .{ .tag = .address_bits, .ty = .u64, .span = Span.empty, .data = .{ .unary = c } });
    const eight = try constant(&b, entry, 8);
    const second = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = eight } } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = second, .rhs = bits_y } } });
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.lends, &.{a});
    const k = try b.addInst(entry, .{ .tag = .load, .ty = .u64, .span = Span.empty, .data = .{ .local = index } });
    const element = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = if (elem == 8) TypeId.u64 else Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = k } } });
    const at = try constant(&b, entry, inner);
    const part = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = element, .rhs = at } } });
    const read = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .u64, .span = Span.empty, .data = .{ .unary = part } });
    try ret(&b, entry, read);
    return Shapes.callees(gpa, try b.finish(entry, .from(0)));
}

test "a read of one part of an element chosen at run time uses that part of every element" {
    // Elements as wide as the slot: the second word of the one element is
    // read, which does not hold the stale observation.
    try expectAccepted(try twoObservationsThenStridedRead(testing.allocator, 24, 8));
}

test "a read of an element chosen at run time uses the part that holds the stale observation" {
    // Elements of eight bytes: the word read may be the first, which holds
    // the lent slot's observation.
    try expectRefused(try twoObservationsThenStridedRead(testing.allocator, 8, 0), "%16 uses slot $2 after %11 lent for writing or took the storage it observes");
}

test "a slot is not read after it is moved out" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, big);
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.takes, &.{a});
    const again = try addrOf(&b, entry, big);
    const read = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .i64, .span = Span.empty, .data = .{ .unary = again } });
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = read;
    try ret(&b, entry, k);
    try expectRefused(try Shapes.callees(gpa, try b.finish(entry, .from(0))), "reads slot $0 after %1 moved it out");
}

test "a moved slot written part by part holds a value again" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const a = try addrOf(&b, entry, big);
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.takes, &.{a});
    const zero = try constant(&b, entry, 0);
    const field = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = zero } } });
    const one = try b.addInst(entry, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = field, .rhs = one } } });
    const again = try addrOf(&b, entry, big);
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.takes, &.{again});
    const k = try constant(&b, entry, 0);
    try ret(&b, entry, k);
    try expectAccepted(try Shapes.callees(gpa, try b.finish(entry, .from(0))));
}

test "a moved value is not read again, and a copied one is" {
    const gpa = testing.allocator;
    for ([_]mir_mod.Inst.Tag{ .move_value, .copy_value }) |tag| {
        var b = Builder.init(gpa);
        defer b.deinit();
        b.return_type = .u64;
        const from = try b.addLocal(Harness.big, .value);
        const to = try b.addLocal(Harness.big, .value);
        const entry = try b.addBlock();
        const src = try addrOf(&b, entry, from);
        const dst = try addrOf(&b, entry, to);
        _ = try b.addInst(entry, .{ .tag = tag, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = dst, .rhs = src } } });
        const read = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .i64, .span = Span.empty, .data = .{ .unary = src } });
        _ = read;
        const k = try constant(&b, entry, 0);
        try ret(&b, entry, k);
        const functions = try Shapes.callees(gpa, try b.finish(entry, .from(0)));
        if (tag == .move_value) {
            try expectRefused(functions, "reads slot $0 after %2 moved it out");
        } else {
            try expectAccepted(functions);
        }
    }
}

/// A loop over a slot: the header branches on a word, the body runs `body`
/// and jumps back, the exit returns. Blocks are entry, header, body, exit.
const Loop = struct { entry: BlockId, header: BlockId, body: BlockId, exit: BlockId };

fn loopShape(b: *Builder) !Loop {
    const entry = try b.addBlock();
    const header = try b.addBlock();
    const body = try b.addBlock();
    const exit = try b.addBlock();
    return .{ .entry = entry, .header = header, .body = body, .exit = exit };
}

fn closeLoop(b: *Builder, loop: Loop, cond: InstId) !void {
    _ = try b.setTerminator(loop.entry, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = loop.header } });
    _ = try b.setTerminator(loop.header, .{ .tag = .branch, .ty = .unit, .span = Span.empty, .data = .{ .branch = .{ .cond = cond, .then_block = loop.body, .else_block = loop.exit } } });
    _ = try b.setTerminator(loop.body, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = loop.header } });
    const k = try constant(b, loop.exit, 0);
    try ret(b, loop.exit, k);
}

test "a walk whose body lends the walked slot for writing is refused on the back edge" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const iter = try b.addLocal(.u64, .value);
    const loop = try loopShape(&b);
    // The view is taken once before the loop and walked from the header.
    const a = try addrOf(&b, loop.entry, big);
    const view = try b.addCall(loop.entry, .value, .u64, Span.empty, Shapes.reads, &.{a});
    _ = try b.addInst(loop.entry, .{ .tag = .store, .ty = .u64, .span = Span.empty, .data = .{ .store = .{ .local = iter, .value = view } } });
    const walked = try b.addInst(loop.header, .{ .tag = .load, .ty = .u64, .span = Span.empty, .data = .{ .local = iter } });
    const next = try b.addCall(loop.header, .value, .u64, Span.empty, Shapes.word, &.{walked});
    const zero = try constant(&b, loop.header, 0);
    const cond = try b.addInst(loop.header, .{ .tag = .cmp_eq, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = next, .rhs = zero } } });
    const again = try addrOf(&b, loop.body, big);
    _ = try b.addCall(loop.body, .value, .u64, Span.empty, Shapes.lends, &.{again});
    try closeLoop(&b, loop, cond);
    try expectRefused(try Shapes.callees(gpa, try b.finish(loop.entry, .from(0))), "uses %3 after %8 lent for writing or took the storage it observes");
}

test "a view re-created on every pass of a loop is fresh on every pass" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const loop = try loopShape(&b);
    const flag = try constant(&b, loop.entry, 1);
    const zero = try constant(&b, loop.header, 0);
    const cond = try b.addInst(loop.header, .{ .tag = .cmp_eq, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = flag, .rhs = zero } } });
    // Take the view, use it, then lend the slot for writing; the next pass
    // takes it again.
    const a = try addrOf(&b, loop.body, big);
    const view = try b.addCall(loop.body, .value, .u64, Span.empty, Shapes.reads, &.{a});
    _ = try b.addCall(loop.body, .value, .u64, Span.empty, Shapes.word, &.{view});
    _ = try b.addCall(loop.body, .value, .u64, Span.empty, Shapes.lends, &.{a});
    try closeLoop(&b, loop, cond);
    try expectAccepted(try Shapes.callees(gpa, try b.finish(loop.entry, .from(0))));
}

test "a slot built part by part and sunk on every pass of a loop is held on every pass" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const loop = try loopShape(&b);
    const flag = try constant(&b, loop.entry, 1);
    const zero = try constant(&b, loop.header, 0);
    const cond = try b.addInst(loop.header, .{ .tag = .cmp_eq, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = flag, .rhs = zero } } });
    const a = try addrOf(&b, loop.body, big);
    const at = try constant(&b, loop.body, 0);
    const field = try b.addInst(loop.body, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = at } } });
    const one = try b.addInst(loop.body, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(loop.body, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = field, .rhs = one } } });
    _ = try b.addCall(loop.body, .value, .u64, Span.empty, Shapes.takes, &.{a});
    try closeLoop(&b, loop, cond);
    try expectAccepted(try Shapes.callees(gpa, try b.finish(loop.entry, .from(0))));
}

test "a stale carrier on one arm of a branch is stale after the join" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const then = try b.addBlock();
    const other = try b.addBlock();
    const join = try b.addBlock();
    const a = try addrOf(&b, entry, big);
    const view = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{a});
    const zero = try constant(&b, entry, 0);
    const cond = try b.addInst(entry, .{ .tag = .cmp_eq, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = view, .rhs = zero } } });
    _ = try b.setTerminator(entry, .{ .tag = .branch, .ty = .unit, .span = Span.empty, .data = .{ .branch = .{ .cond = cond, .then_block = then, .else_block = other } } });
    _ = try b.addCall(then, .value, .u64, Span.empty, Shapes.lends, &.{a});
    _ = try b.setTerminator(then, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = join } });
    _ = try constant(&b, other, 0);
    _ = try b.setTerminator(other, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = join } });
    try ret(&b, join, view);
    try expectRefused(try Shapes.callees(gpa, try b.finish(entry, .from(0))), "uses %1 after %5 lent for writing or took the storage it observes");
}

test "a slot every arm rewrites before the join is held after it, on every pass of a loop" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const other = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const header = try b.addBlock();
    const body = try b.addBlock();
    const whole = try b.addBlock();
    const part = try b.addBlock();
    const join = try b.addBlock();
    const exit = try b.addBlock();

    const flag = try constant(&b, entry, 1);
    _ = try b.setTerminator(entry, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = header } });
    const zero = try constant(&b, header, 0);
    const cond = try b.addInst(header, .{ .tag = .cmp_eq, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = flag, .rhs = zero } } });
    _ = try b.setTerminator(header, .{ .tag = .branch, .ty = .unit, .span = Span.empty, .data = .{ .branch = .{ .cond = cond, .then_block = body, .else_block = exit } } });
    _ = try b.setTerminator(body, .{ .tag = .branch, .ty = .unit, .span = Span.empty, .data = .{ .branch = .{ .cond = cond, .then_block = whole, .else_block = part } } });

    // One arm rewrites the slot whole, the other writes a part of it.
    const dst = try addrOf(&b, whole, big);
    const src = try addrOf(&b, whole, other);
    _ = try b.addInst(whole, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = dst, .rhs = src } } });
    _ = try b.setTerminator(whole, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = join } });
    const a = try addrOf(&b, part, big);
    const at = try constant(&b, part, 0);
    const field = try b.addInst(part, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = a, .rhs = at } } });
    const one = try b.addInst(part, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(part, .{ .tag = .store_indirect, .ty = .i64, .span = Span.empty, .data = .{ .binary = .{ .lhs = field, .rhs = one } } });
    _ = try b.setTerminator(part, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = join } });

    // After the join the slot is moved out, and the loop goes round again.
    const moved_from = try addrOf(&b, join, big);
    _ = try b.addCall(join, .value, .u64, Span.empty, Shapes.takes, &.{moved_from});
    _ = try b.setTerminator(join, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = header } });
    const k = try constant(&b, exit, 0);
    try ret(&b, exit, k);
    try expectAccepted(try Shapes.callees(gpa, try b.finish(entry, .from(0))));
}

test "a stale slot rebuilt part by part is fresh again" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const big = try b.addLocal(Harness.big, .value);
    const holder = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    // The holder takes a view of the slot, the slot is lent for writing, and
    // then the holder is rebuilt field by field, as a `let` of a literal is.
    const a = try addrOf(&b, entry, big);
    const view = try b.addCall(entry, .value, .u64, Span.empty, Shapes.reads, &.{a});
    const h = try addrOf(&b, entry, holder);
    const at = try constant(&b, entry, 0);
    const field = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = h, .rhs = at } } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = field, .rhs = view } } });
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.lends, &.{a});
    const one = try constant(&b, entry, 1);
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = field, .rhs = one } } });
    _ = try b.addCall(entry, .value, .u64, Span.empty, Shapes.takes, &.{h});
    const k = try constant(&b, entry, 0);
    try ret(&b, entry, k);
    try expectAccepted(try Shapes.callees(gpa, try b.finish(entry, .from(0))));
}

// -- Cost --
//
// Reached by the allocation property below and by nothing else, for the
// reason the verifier's fuzz target keeps its own copies: the property is
// about what lowering hands this phase, so it has to run the passes that
// produce one.
const Source = @import("../support/source.zig").Source;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const resolveTree = @import("../sema/resolve.zig").resolveTree;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;
const checkOwnershipTree = @import("../ownership/check.zig").checkTree;
const lowerTree = @import("lower.zig").lowerTree;

/// One body taking `n` views of one place, reading each and lending the place
/// for writing: one dependency created and one marked stale per step. The
/// release sweep times the same program.
pub fn viewsProgram(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "struct Box { value: UInt64, other: UInt64 }\n" ++
            "fn view(b: Box) -> borrow UInt64 where borrows(b) { borrow b.value }\n" ++
            "fn bump(inout b: Box) -> () { b.other = b.other + 1 }\n" ++
            "fn main() -> UInt8 {\n    var box = Box { value = 1, other = 0 }\n    var total: UInt64 = 0\n",
    );
    for (0..n) |i| {
        try w.print("    let v{d} = view(box)\n    total = total + *v{d}\n    bump(&box)\n", .{ i, i });
    }
    try w.print("    if total == {d} {{ 0 }} else {{ 1 }}\n}}\n", .{n});
    return out.toOwnedSlice();
}

test "the phase does no more allocation work than views taken and lent in turn are worth" {
    try expectLinearWork(viewsProgram);
}

/// One holder retaining views of `n` places, then carried out `n` times: the
/// shape whose dependency sets grow, one root per retained view, and whose
/// carries share that whole set.
pub fn retainedViewsProgram(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "struct Box { value: UInt64 }\n" ++
            "struct Holder { kept: borrow UInt64 }\n" ++
            "fn view(b: Box) -> borrow UInt64 where borrows(b) { borrow b.value }\n" ++
            "fn keep(inout h: Holder, v: borrow UInt64) -> () where retains(h: v) { h.kept = copy(v) }\n" ++
            "fn first(h: Holder) -> borrow UInt64 where carries(h) { copy(h.kept) }\n" ++
            "fn main() -> UInt8 {\n",
    );
    for (0..n) |i| try w.print("    let box{d} = Box {{ value = 1 }}\n", .{i});
    try w.writeAll("    var holder = Holder { kept = view(box0) }\n");
    for (1..n) |i| try w.print("    keep(&holder, view(box{d}))\n", .{i});
    try w.writeAll("    var total: UInt64 = 0\n");
    for (0..n) |i| try w.print("    let c{d} = first(holder)\n    total = total + *c{d}\n", .{ i, i });
    try w.print("    if total == {d} {{ 0 }} else {{ 1 }}\n}}\n", .{n});
    return out.toOwnedSlice();
}

test "the phase does no more allocation work than views retained in one holder are worth" {
    try expectLinearWork(retainedViewsProgram);
}

/// One struct of `n` views of `n` places, then each place lent for
/// writing in turn: one carrier holding `n` observations, each invalidated
/// once, which is the shape a mark must cost one step on.
pub fn wideViewsProgram(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "struct Box { value: UInt64 }\n" ++
            "fn bump(inout b: Box) -> () { b.value = b.value + 1 }\n" ++
            "struct Wide {",
    );
    for (0..n) |i| try w.print(" f{d}: borrow UInt64,", .{i});
    try w.writeAll(" }\nfn main() -> UInt8 {\n");
    for (0..n) |i| try w.print("    var b{d} = Box {{ value = 1 }}\n", .{i});
    try w.writeAll("    let wide = Wide {");
    for (0..n) |i| try w.print(" f{d} = borrow b{d}.value,", .{ i, i });
    try w.writeAll(" }\n    let first = *wide.f0\n");
    for (0..n) |i| try w.print("    bump(&b{d})\n", .{i});
    try w.writeAll("    if first == 1 { 0 } else { 1 }\n}\n");
    return out.toOwnedSlice();
}

test "the phase does no more allocation work than views held in one struct are worth" {
    try expectLinearWork(wideViewsProgram);
}

/// `wideViewsProgram` with the owners lent in the order opposite to the one
/// the struct holds their views in.
pub fn wideViewsEndedLastFirstProgram(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "struct Box { value: UInt64 }\n" ++
            "fn bump(inout b: Box) -> () { b.value = b.value + 1 }\n" ++
            "struct Wide {",
    );
    for (0..n) |i| try w.print(" f{d}: borrow UInt64,", .{i});
    try w.writeAll(" }\nfn main() -> UInt8 {\n");
    for (0..n) |i| try w.print("    var b{d} = Box {{ value = 1 }}\n", .{i});
    try w.writeAll("    let wide = Wide {");
    for (0..n) |i| try w.print(" f{d} = borrow b{d}.value,", .{ i, i });
    try w.writeAll(" }\n    let first = *wide.f0\n");
    for (0..n) |k| try w.print("    bump(&b{d})\n", .{n - 1 - k});
    try w.writeAll("    if first == 1 { 0 } else { 1 }\n}\n");
    return out.toOwnedSlice();
}

test "the phase does no more allocation work than views ended last first are worth" {
    try expectLinearWork(wideViewsEndedLastFirstProgram);
}

test "marks made against the order of the set enter the index once per part" {
    // A mark in front of older ones rebuilds the chain, which costs nodes,
    // but it adds no entry: the index holds one per dependency however the
    // owners end.
    const small = try storageWork(testing.allocator, wideViewsEndedLastFirstProgram, 200);
    const large = try storageWork(testing.allocator, wideViewsEndedLastFirstProgram, 1600);
    try testing.expect(large.entries <= small.entries * 10);
}

/// `n` copies of one struct of `n` views, then every owner lent for writing
/// in turn: `n` carriers holding the same set, each marked once per owner.
pub fn copiedWideViewsProgram(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "struct Box { value: UInt64 }\n" ++
            "fn bump(inout b: Box) -> () { b.value = b.value + 1 }\n" ++
            "@copyable\n" ++
            "struct Wide {",
    );
    for (0..n) |i| try w.print(" f{d}: borrow UInt64,", .{i});
    try w.writeAll(" }\nfn main() -> UInt8 {\n");
    for (0..n) |i| try w.print("    var b{d} = Box {{ value = 1 }}\n", .{i});
    try w.writeAll("    let wide = Wide {");
    for (0..n) |i| try w.print(" f{d} = borrow b{d}.value,", .{ i, i });
    try w.writeAll(" }\n");
    for (0..n) |k| try w.print("    let _wide{d} = copy(wide)\n", .{k});
    try w.writeAll("    let first = *wide.f0\n");
    for (0..n) |i| try w.print("    bump(&b{d})\n", .{i});
    try w.writeAll("    if first == 1 { 0 } else { 1 }\n}\n");
    return out.toOwnedSlice();
}

test "the phase does no more allocation work than copies of a wide struct are worth" {
    try expectLinearWorkBetween(copiedWideViewsProgram, 100, 800);
}

/// A phase holding only the marks' treap, for tests of its operations.
fn markTestInit(p: *Phase) !void {
    p.gpa = testing.allocator;
    p.marks = .empty;
    p.marks_interned = .empty;
    p.prefix = .empty;
    p.last_added = null;
    try p.marks.append(testing.allocator, .{
        .dep = .{ .hoff = 0, .hlen = 0, .root = no_entity, .off = 0, .len = 0 },
        .left = 0,
        .right = 0,
        .count = 0,
        .all_whole = true,
        .priority = 0,
    });
}

fn markTestDeinit(p: *Phase) void {
    p.marks.deinit(testing.allocator);
    p.marks_interned.deinit(testing.allocator);
    p.prefix.deinit(testing.allocator);
}

/// `n` distinct dependencies, greatest first: parts held at different offsets of a carrier,
/// a few held whole, over several roots.
fn markTestDeps(comptime n: usize) [n]Dep {
    var out: [n]Dep = undefined;
    for (&out, 0..) |*d, i| {
        const whole = i % 4 == 3;
        d.* = .{
            .hoff = if (whole) 0 else @intCast((i % 5) * 8),
            .hlen = if (whole) held_whole else 8,
            .root = @intCast(i * 7 % 11),
            .off = @intCast(i * 3),
            .len = 8,
        };
    }
    std.mem.sort(Dep, &out, {}, struct {
        fn lessThan(_: void, a: Dep, b: Dep) bool {
            return a.greater(b);
        }
    }.lessThan);
    return out;
}

fn markTestWalk(p: *const Phase, t: MarkId, out: *std.ArrayList(Dep)) !void {
    if (t == empty_set) return;
    const n = p.marks.items[t];
    try markTestWalk(p, n.left, out);
    try out.append(testing.allocator, n.dep);
    try markTestWalk(p, n.right, out);
}

/// Counts the bytes every allocation and growth asks for.
const Counting = struct {
    under: std.mem.Allocator,
    took: usize = 0,

    fn allocator(self: *Counting) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn alloc(ctx: *anyopaque, n: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        const got = self.under.rawAlloc(n, a, ra) orelse return null;
        self.took += n;
        return got;
    }

    fn resize(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        if (!self.under.rawResize(buf, a, n, ra)) return false;
        if (n > buf.len) self.took += n;
        return true;
    }

    fn remap(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        const got = self.under.rawRemap(buf, a, n, ra) orelse return null;
        if (n > buf.len) self.took += n;
        return got;
    }

    fn free(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, ra: usize) void {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        self.under.rawFree(buf, a, ra);
    }
};

/// What this phase does over one generated program at size `n`: the bytes it
/// allocates, counted on its own allocator so nothing above it is in the
/// number, the index entries it makes, and the state records it keeps: the
/// trail's peak and the segments saved for joins.
const Work = struct { bytes: usize, entries: usize, records: usize };

fn storageWork(gpa: std.mem.Allocator, program: fn (std.mem.Allocator, u32) anyerror![]u8, n: u32) !Work {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try program(a, n);
    const source: Source = .{ .path = "views.lin", .text = text };
    var sink = Sink.init(a);
    var interner: Interner = .empty;
    const tokens = try tokenize(a, &source, .from(0), &sink, &interner);
    var ast = try parse(a, &source, .from(0), tokens, &sink);
    var res = try resolveTree(a, &ast, &sink);
    var typing = try typecheckTree(a, &res, &sink);
    var cancelled = try checkOwnershipTree(a, &res, &typing, &sink);
    if (sink.hasErrors()) return error.SourceRejected;
    const module = (try lowerTree(a, &res, &typing, &cancelled, &sink, .program)) orelse return error.SourceRejected;
    if (sink.hasErrors()) return error.SourceRejected;

    var counting: Counting = .{ .under = gpa };
    var entries: usize = 0;
    var records: usize = 0;
    for (module.functions, 0..) |*f, i| {
        if (module.isExternal(.at(@intCast(i)))) continue;
        const addresses = try counting.allocator().alloc(Address, f.insts.len);
        defer counting.allocator().free(addresses);
        verify_mod.attribute(&module, f, addresses);
        var phase = try Phase.init(counting.allocator(), &module, f, .at(@intCast(i)), &sink);
        defer phase.deinit();
        try phase.check(addresses);
        if (!phase.ok) return error.AWellFormedModuleWasRefused;
        entries += phase.entries.items.len;
        records += phase.trail.capacity + phase.saved.items.len;
    }
    return .{ .bytes = counting.took, .entries = entries, .records = records };
}

/// Eight times the views is about eight times the work. The count includes
/// every growth of a list, which doubles, so a linear phase reads anywhere
/// from four to sixteen; a set held per carrier but sized by every carrier, a
/// scan that never shrinks, or a set copied rather than shared when it grows,
/// reads sixty-four and more. The records the phase keeps are held to the
/// same ratio, so a change logged once per carrier and dependency is seen
/// even when a record is small.
fn expectLinearWork(program: fn (std.mem.Allocator, u32) anyerror![]u8) !void {
    try expectLinearWorkBetween(program, 200, 1600);
}

fn expectLinearWorkBetween(program: fn (std.mem.Allocator, u32) anyerror![]u8, small_n: u32, large_n: u32) !void {
    const small = try storageWork(testing.allocator, program, small_n);
    const large = try storageWork(testing.allocator, program, large_n);
    if (large.bytes >= small.bytes * 20 or large.bytes < small.bytes * 3 or large.records >= small.records * 20) {
        std.debug.print("{s}: {d} bytes and {d} records at {d}, {d} and {d} at {d}\n", .{ @typeName(@TypeOf(program)), small.bytes, small.records, small_n, large.bytes, large.records, large_n });
    }
    try testing.expect(large.bytes < small.bytes * 20);
    try testing.expect(large.bytes >= small.bytes * 3);
    try testing.expect(large.records < small.records * 20);
}
