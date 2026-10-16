//! Observation dependencies carried by values on the ownership CFG.
//!
//! Paths and fact sets are interned within one function. Invalidation travels
//! with the affected observation, so a later use supplies the witness that an
//! owner was still needed. Replacing or abandoning that observation requires
//! no lifetime extension. Joins preserve every reachable origin.
const std = @import("std");
const Ast = @import("../syntax/ast.zig").Ast;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const node = @import("../syntax/node.zig");
const ExprId = node.ExprId;
const BindingId = @import("../sema/ids.zig").BindingId;
const Resolution = @import("../sema/resolve.zig").Resolution;
const types = @import("../sema/types.zig");
const Typing = types.Typing;
const Sink = @import("../diagnostics/sink.zig").Sink;
const diagnostics = @import("../diagnostics/diagnostic.zig");
const FileId = @import("../support/source.zig").FileId;
const Span = @import("../support/span.zig").Span;
const cfg_mod = @import("cfg.zig");
const Cfg = cfg_mod.Cfg;
const Function = cfg_mod.Function;
const OpId = cfg_mod.OpId;
const Allocator = std.mem.Allocator;

/// Returns the `Option` or `Result` that `e?` or `e else { … }` takes its
/// success out of.
fn unwrapped(ast: *const Ast, id: ExprId) ExprId {
    return if (ast.exprTag(id) == .try_) ast.unaryOperand(id) else ast.unwrapElse(id).operand;
}

const PathId = enum(u32) { root, _ };
const SetId = enum(u32) { empty, _ };
const ExclusionsId = enum(u32) { empty, _ };
const Exclusion = struct { path: PathId, next: ExclusionsId };
const CarriedSet = struct { set: SetId, ty: types.TypeId };
const Cell = enum(u64) {
    _,
    fn binding(b: BindingId) Cell {
        return @enumFromInt(@as(u64, @intFromEnum(b)) << 2);
    }
    fn expression(e: ExprId) Cell {
        return @enumFromInt((@as(u64, @intFromEnum(e)) << 2) | 1);
    }
    fn alias(b: BindingId) Cell {
        return @enumFromInt((@as(u64, @intFromEnum(b)) << 2) | 2);
    }
    fn capture(source: ExprId) Cell {
        return @enumFromInt((@as(u64, @intFromEnum(source)) << 2) | 3);
    }
};
const element: u96 = 1 << 64;
const observed: u96 = element + 1;
const opaque_projection: u96 = element + 2;
// Separate tags keep array ranges distinct from fields and enum payloads.
// The low 64 bits hold inclusive UInt32 start and end indices.
const indexed_element: u96 = 1 << 66;
fn elementRange(first: u32, last: u32) u96 {
    return indexed_element | (@as(u96, first) << 32) | last;
}
fn orderHeads(wanted: u96, head: u96) std.math.Order {
    return std.math.order(wanted, head);
}

fn elementHead(index: u64) u96 {
    return elementRange(@intCast(index), @intCast(index));
}
fn rangeFirst(head: u96) u32 {
    return @truncate(head >> 32);
}
fn rangeLast(head: u96) u32 {
    return @truncate(head);
}
fn headsOverlap(a: u96, b: u96) bool {
    if (a == b) return true;
    if (!isElement(a) or !isElement(b)) return false;
    return a == element or b == element or (rangeFirst(a) <= rangeLast(b) and rangeFirst(b) <= rangeLast(a));
}
fn isElement(head: u96) bool {
    return head == element or head >= indexed_element;
}
const KnownIndex = struct { value: u64, from_end: bool = false };
const IndexSubstitution = struct { binding: u32, index: ?KnownIndex };
const Path = struct { head: u96, tail: PathId };
fn payloadHead(variant: u32, index: u32) u96 {
    return (@as(u96, 1) << 65) | (@as(u96, variant) << 32) | index;
}
const Place = struct { root: BindingId, path: PathId = .root };
const Selection = struct { root: ExprId, path: PathId, carried_source: ExprId = .none };
const Origin = struct {
    place: Place,
    /// Carried parameter dependencies belong to caller storage, independently
    /// of the parameter descriptor's own location in this function.
    external: bool = false,
    /// A borrowed temporary, where the origin is one: the value evaluated
    /// into storage of its own, and the statement it ends with. Its place has
    /// no root.
    temporary: ExprId = .none,
    statement: ExprId = .none,
    /// The capture source that lends this place `inout`, where the
    /// observation is an exclusive lend: while a value carrying it is live, no
    /// other access may touch the place. `.none` for a read observation.
    lent: ExprId = .none,
};
const Fact = struct {
    path: PathId = .root,
    origin: Origin,
    invalid: ExprId = .none,
    /// A callable contract hides representation: every selected part may
    /// carry this dependency until an operation with a narrower contract.
    ambient: bool = false,
    symbolic: bool = false,
    /// Parts definitely replaced since this ambient dependency was introduced.
    exclusions: ExclusionsId = .empty,
};
const State = std.AutoHashMapUnmanaged(Cell, SetId);

/// What can end an origin: a binding whose scope, move or write ends it, or a
/// statement whose end ends the temporaries it made.
const Owner = enum(u64) {
    _,

    const statement_bit: u64 = 1 << 32;

    fn binding(b: BindingId) Owner {
        return @enumFromInt(@intFromEnum(b));
    }

    fn statement(anchor: ExprId) Owner {
        return @enumFromInt(statement_bit | @intFromEnum(anchor));
    }

    /// The binding this owner is, or null for a statement.
    fn asBinding(self: Owner) ?BindingId {
        const bits = @intFromEnum(self);
        if (bits & statement_bit != 0) return null;
        return @enumFromInt(@as(u32, @intCast(bits)));
    }
};

fn dependencyOwner(fact: Fact) ?Owner {
    if (fact.invalid != .none or fact.origin.external) return null;
    if (fact.origin.statement != .none) return Owner.statement(fact.origin.statement);
    return Owner.binding(fact.origin.place.root);
}

test "a statement owner is never a binding owner" {
    const b: BindingId = @enumFromInt(7);
    const e: ExprId = @enumFromInt(7);
    try std.testing.expect(Owner.binding(b) != Owner.statement(e));
    try std.testing.expectEqual(b, Owner.binding(b).asBinding().?);
    try std.testing.expectEqual(@as(?BindingId, null), Owner.statement(e).asBinding());
}

/// The live sets observing each owner, found by the first step of the
/// observed path as well as by owner, so an access to one field inspects the
/// observations of that field and of the whole owner rather than those of
/// every field. Element steps share one bucket, because an indexed element
/// may overlap any other; the whole owner has a bucket of its own.
const OwnerIndex = struct {
    const Sets = std.AutoHashMapUnmanaged(SetId, void);
    const Key = struct { owner: Owner, head: u96 };
    const whole_owner: u96 = std.math.maxInt(u96);

    by_owner: std.AutoHashMapUnmanaged(Owner, Sets) = .empty,
    by_head: std.AutoHashMapUnmanaged(Key, Sets) = .empty,

    fn bucketOf(store: *const Store, path: PathId) u96 {
        if (path == .root) return whole_owner;
        const head = store.path(path).head;
        return if (isElement(head)) element else head;
    }

    fn clear(self: *OwnerIndex, gpa: Allocator) void {
        var owners = self.by_owner.valueIterator();
        while (owners.next()) |bucket| bucket.deinit(gpa);
        self.by_owner.clearRetainingCapacity();
        var heads = self.by_head.valueIterator();
        while (heads.next()) |bucket| bucket.deinit(gpa);
        self.by_head.clearRetainingCapacity();
    }

    fn deinit(self: *OwnerIndex, gpa: Allocator) void {
        self.clear(gpa);
        self.by_owner.deinit(gpa);
        self.by_head.deinit(gpa);
    }

    fn put(self: *OwnerIndex, gpa: Allocator, store: *const Store, owner: Owner, path: PathId, set: SetId) !void {
        const all = try self.by_owner.getOrPut(gpa, owner);
        if (!all.found_existing) all.value_ptr.* = .empty;
        try all.value_ptr.put(gpa, set, {});
        const headed = try self.by_head.getOrPut(gpa, .{ .owner = owner, .head = bucketOf(store, path) });
        if (!headed.found_existing) headed.value_ptr.* = .empty;
        try headed.value_ptr.put(gpa, set, {});
    }

    fn remove(self: *OwnerIndex, gpa: Allocator, store: *const Store, owner: Owner, path: PathId, set: SetId) void {
        removeFrom(Owner, gpa, &self.by_owner, owner, set);
        removeFrom(Key, gpa, &self.by_head, .{ .owner = owner, .head = bucketOf(store, path) }, set);
    }

    fn removeFrom(comptime K: type, gpa: Allocator, index: *std.AutoHashMapUnmanaged(K, Sets), key: K, set: SetId) void {
        const bucket = index.getPtr(key) orelse return;
        _ = bucket.remove(set);
        if (bucket.count() == 0) {
            bucket.deinit(gpa);
            _ = index.remove(key);
        }
    }

    /// The sets that may observe a part of `owner` overlapping `path`: all of
    /// them for the whole owner, and otherwise those of the path's first
    /// step and those observing the whole owner.
    fn setsOverlapping(self: *const OwnerIndex, gpa: Allocator, store: *const Store, owner: Owner, path: PathId) ![]SetId {
        const head = bucketOf(store, path);
        if (head == whole_owner) return keysOf(gpa, &.{self.by_owner.getPtr(owner)});
        return keysOf(gpa, &.{ self.by_head.getPtr(.{ .owner = owner, .head = head }), self.by_head.getPtr(.{ .owner = owner, .head = whole_owner }) });
    }

    fn keysOf(gpa: Allocator, buckets: []const ?*Sets) ![]SetId {
        var total: usize = 0;
        for (buckets) |found| if (found) |bucket| {
            total += bucket.count();
        };
        const sets = try gpa.alloc(SetId, total);
        var i: usize = 0;
        for (buckets) |found| if (found) |bucket| {
            var keys = bucket.keyIterator();
            while (keys.next()) |key| : (i += 1) sets[i] = key.*;
        };
        // A set observing both the whole owner and one part of it sits in
        // two buckets; each is inspected once.
        std.mem.sortUnstable(SetId, sets, {}, struct {
            fn less(_: void, a: SetId, b: SetId) bool {
                return @intFromEnum(a) < @intFromEnum(b);
            }
        }.less);
        var unique: usize = 0;
        for (sets) |set| {
            if (unique != 0 and sets[unique - 1] == set) continue;
            sets[unique] = set;
            unique += 1;
        }
        return gpa.realloc(sets, unique);
    }
};

/// Active interned sets share their reverse edges across carrier aliases.
/// Moving an unchanged set adds/removes a cell; its facts are indexed only
/// when that set first becomes active in the block.
const Dependents = struct {
    owners: OwnerIndex = .{},
    /// The active sets holding an exclusive lend of each owner: a subset of
    /// `owners`, so a read of a place inspects only the lends of it rather
    /// than every observation of it.
    lenders: OwnerIndex = .{},
    active: std.AutoHashMapUnmanaged(SetId, std.AutoHashMapUnmanaged(Cell, void)) = .empty,

    fn clear(self: *Dependents, gpa: Allocator) void {
        self.owners.clear(gpa);
        self.lenders.clear(gpa);
        var sets = self.active.valueIterator();
        while (sets.next()) |bucket| bucket.deinit(gpa);
        self.active.clearRetainingCapacity();
    }

    fn deinit(self: *Dependents, gpa: Allocator) void {
        self.clear(gpa);
        self.owners.deinit(gpa);
        self.lenders.deinit(gpa);
        self.active.deinit(gpa);
    }

    fn add(self: *Dependents, gpa: Allocator, store: *const Store, cell: Cell, set: SetId) !void {
        if (!store.hasInvalidatableOrigin(set)) return;
        const entry = try self.active.getOrPut(gpa, set);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.put(gpa, cell, {});
        if (entry.found_existing) return;
        for (store.facts(set)) |fact| {
            const owner = dependencyOwner(fact) orelse continue;
            try self.owners.put(gpa, store, owner, fact.origin.place.path, set);
            if (fact.origin.lent != .none) try self.lenders.put(gpa, store, owner, fact.origin.place.path, set);
        }
    }

    fn remove(self: *Dependents, gpa: Allocator, store: *const Store, cell: Cell, set: SetId) void {
        const cells = self.active.getPtr(set) orelse return;
        _ = cells.remove(cell);
        if (cells.count() != 0) return;
        cells.deinit(gpa);
        _ = self.active.remove(set);
        for (store.facts(set)) |fact| {
            const owner = dependencyOwner(fact) orelse continue;
            self.owners.remove(gpa, store, owner, fact.origin.place.path, set);
            if (fact.origin.lent != .none) self.lenders.remove(gpa, store, owner, fact.origin.place.path, set);
        }
    }

    fn carriers(self: *const Dependents, gpa: Allocator, set: SetId) ![]Cell {
        const bucket = self.active.get(set) orelse return &.{};
        const cells = try gpa.alloc(Cell, bucket.count());
        var keys = bucket.keyIterator();
        var i: usize = 0;
        while (keys.next()) |key| : (i += 1) cells[i] = key.*;
        return cells;
    }
};
// Backwards traversal repeatedly replaces live cells. Dense removal avoids
// retaining tombstones across a long binding chain with few live values.
const Live = std.AutoArrayHashMapUnmanaged(Cell, void);
// Offsets remain valid while the function's shared cell buffer grows.
const Effect = struct {
    start: usize,
    uses_start: usize,
    end: usize,

    fn defines(self: Effect, cells: []const Cell) []const Cell {
        return cells[self.start..self.uses_start];
    }

    fn uses(self: Effect, cells: []const Cell) []const Cell {
        return cells[self.uses_start..self.end];
    }
};
const Liveness = struct {
    const Range = struct { start: usize, end: usize };
    const Drop = struct { op: OpId, cells: Range };

    entries: []Live,
    blocks: []Range = &.{},
    drops: std.ArrayList(Drop) = .empty,
    cells: std.ArrayList(Cell) = .empty,

    fn deinit(self: *Liveness, gpa: Allocator) void {
        for (self.entries) |*entry| entry.deinit(gpa);
        gpa.free(self.entries);
        gpa.free(self.blocks);
        self.drops.deinit(gpa);
        self.cells.deinit(gpa);
    }
};

/// A set of at most this many facts is walked directly where its distinct
/// owners are wanted; a larger one is summarised once.
const few_facts = 8;

const Store = struct {
    const FactSet = struct {
        facts: []const Fact,
        has_invalidatable_origin: bool,
        /// Whether any fact records an exclusive lend.
        has_lend: bool,
    };

    gpa: Allocator,
    paths: std.ArrayList(Path) = .empty,
    exclusions: std.ArrayList(Exclusion) = .empty,
    exclusion_index: std.AutoHashMapUnmanaged(u64, ExclusionsId) = .empty,
    path_index: std.AutoHashMapUnmanaged(u128, PathId) = .empty,
    sets: std.ArrayList(FactSet) = .empty,
    set_index: std.AutoHashMapUnmanaged(u64, std.ArrayList(SetId)) = .empty,
    local_origins: std.AutoHashMapUnmanaged(SetId, std.AutoHashMapUnmanaged(BindingId, void)) = .empty,
    owner_lists: std.AutoHashMapUnmanaged(SetId, OwnerList) = .empty,

    /// The distinct roots a set's facts observe, for the facts still valid
    /// and for all of them.
    const OwnerList = struct { valid: []const BindingId, all: []const BindingId };

    fn deinit(self: *Store) void {
        var lists = self.owner_lists.valueIterator();
        while (lists.next()) |list| {
            self.gpa.free(list.valid);
            self.gpa.free(list.all);
        }
        self.owner_lists.deinit(self.gpa);
        self.exclusions.deinit(self.gpa);
        self.exclusion_index.deinit(self.gpa);
        var origins = self.local_origins.valueIterator();
        while (origins.next()) |owners| owners.deinit(self.gpa);
        self.local_origins.deinit(self.gpa);
        for (self.sets.items) |set| self.gpa.free(set.facts);
        var buckets = self.set_index.valueIterator();
        while (buckets.next()) |bucket| bucket.deinit(self.gpa);
        self.set_index.deinit(self.gpa);
        self.sets.deinit(self.gpa);
        self.path_index.deinit(self.gpa);
        self.paths.deinit(self.gpa);
    }

    fn prepend(self: *Store, head: u96, tail: PathId) !PathId {
        const key = (@as(u128, head) << 32) | @intFromEnum(tail);
        const entry = try self.path_index.getOrPut(self.gpa, key);
        if (entry.found_existing) return entry.value_ptr.*;
        errdefer _ = self.path_index.remove(key);
        const id: PathId = @enumFromInt(self.paths.items.len + 1);
        try self.paths.append(self.gpa, .{ .head = head, .tail = tail });
        entry.value_ptr.* = id;
        return id;
    }

    fn path(self: *const Store, id: PathId) Path {
        return self.paths.items[@intFromEnum(id) - 1];
    }

    fn concat(self: *Store, prefix: PathId, suffix: PathId) !PathId {
        var heads: std.ArrayList(u96) = .empty;
        defer heads.deinit(self.gpa);
        var at = prefix;
        while (at != .root) {
            const step = self.path(at);
            try heads.append(self.gpa, step.head);
            at = step.tail;
        }
        var out = suffix;
        var i = heads.items.len;
        while (i > 0) {
            i -= 1;
            out = try self.prepend(heads.items[i], out);
        }
        return out;
    }

    fn boundary(self: *Store, path_id: PathId, stop_at_element: bool) !struct { prefix: PathId, remaining: PathId } {
        var heads: std.ArrayList(u96) = .empty;
        defer heads.deinit(self.gpa);
        var remaining = path_id;
        while (remaining != .root) {
            const step = self.path(remaining);
            if (step.head == observed or (stop_at_element and (isElement(step.head) or step.head == opaque_projection))) break;
            try heads.append(self.gpa, step.head);
            remaining = step.tail;
        }
        var prefix: PathId = .root;
        var i = heads.items.len;
        while (i > 0) {
            i -= 1;
            prefix = try self.prepend(heads.items[i], prefix);
        }
        return .{ .prefix = prefix, .remaining = remaining };
    }

    fn lastObservation(self: *Store, path_id: PathId) !?struct { prefix: PathId, suffix: PathId } {
        var heads: std.ArrayList(u96) = .empty;
        defer heads.deinit(self.gpa);
        var last: ?usize = null;
        var suffix: PathId = .root;
        var at = path_id;
        while (at != .root) {
            const step = self.path(at);
            if (step.head == observed) {
                last = heads.items.len;
                suffix = step.tail;
            }
            try heads.append(self.gpa, step.head);
            at = step.tail;
        }
        var i = last orelse return null;
        var prefix: PathId = .root;
        while (i > 0) {
            i -= 1;
            prefix = try self.prepend(heads.items[i], prefix);
        }
        return .{ .prefix = prefix, .suffix = suffix };
    }

    fn strip(self: *const Store, path_id: PathId, prefix: PathId) ?PathId {
        var at = path_id;
        var part = prefix;
        while (part != .root) {
            if (at == .root) return null;
            const a = self.path(at);
            const b = self.path(part);
            if (a.head != b.head) return null;
            at = a.tail;
            part = b.tail;
        }
        return at;
    }

    /// Selection and invalidation include every slot an unknown index may name.
    /// Definite replacement uses exact strip instead, so a wildcard never kills
    /// a dependency belonging to an untouched element.
    fn matchingStrip(self: *const Store, path_id: PathId, prefix: PathId) ?PathId {
        var at = path_id;
        var part = prefix;
        while (part != .root) {
            if (at == .root) return null;
            const a = self.path(at);
            const b = self.path(part);
            if (!headsOverlap(a.head, b.head)) return null;
            at = a.tail;
            part = b.tail;
        }
        return at;
    }

    fn internExclusion(self: *Store, path_id: PathId, next: ExclusionsId) !ExclusionsId {
        const key = (@as(u64, @intFromEnum(next)) << 32) | @intFromEnum(path_id);
        const entry = try self.exclusion_index.getOrPut(self.gpa, key);
        if (entry.found_existing) return entry.value_ptr.*;
        errdefer _ = self.exclusion_index.remove(key);
        const id: ExclusionsId = @enumFromInt(self.exclusions.items.len + 1);
        try self.exclusions.append(self.gpa, .{ .path = path_id, .next = next });
        entry.value_ptr.* = id;
        return id;
    }

    fn exclude(self: *Store, previous: ExclusionsId, path_id: PathId) !ExclusionsId {
        var at = previous;
        var paths: std.ArrayList(PathId) = .empty;
        defer paths.deinit(self.gpa);
        while (at != .empty) {
            const item = self.exclusions.items[@intFromEnum(at) - 1];
            if (self.strip(path_id, item.path) != null) return previous;
            if (self.strip(item.path, path_id) == null) try paths.append(self.gpa, item.path);
            at = item.next;
        }
        try paths.append(self.gpa, path_id);
        std.mem.sortUnstable(PathId, paths.items, {}, struct {
            fn less(_: void, a: PathId, b: PathId) bool {
                return @intFromEnum(a) < @intFromEnum(b);
            }
        }.less);
        var result: ExclusionsId = .empty;
        var i = paths.items.len;
        while (i != 0) {
            i -= 1;
            result = try self.internExclusion(paths.items[i], result);
        }
        return result;
    }

    /// A joined dependency is absent only where every predecessor replaced it.
    /// For A and B exclusions this costs O(A * B * path depth); empty or
    /// identical sets return immediately, including unchanged branch inputs.
    fn commonExclusions(self: *Store, a: ExclusionsId, b: ExclusionsId) !ExclusionsId {
        if (a == b) return a;
        if (a == .empty or b == .empty) return .empty;
        var result: ExclusionsId = .empty;
        var left = a;
        while (left != .empty) {
            const x = self.exclusions.items[@intFromEnum(left) - 1];
            var right = b;
            while (right != .empty) {
                const y = self.exclusions.items[@intFromEnum(right) - 1];
                if (self.strip(x.path, y.path) != null) {
                    result = try self.exclude(result, x.path);
                } else if (self.strip(y.path, x.path) != null) {
                    result = try self.exclude(result, y.path);
                }
                right = y.next;
            }
            left = x.next;
        }
        return result;
    }

    /// Rebase exceptions after selecting below an ambient fact. A null result
    /// means this entire selected part has already been replaced.
    fn selectExclusions(self: *Store, exclusions: ExclusionsId, selection: PathId) !?ExclusionsId {
        var at = exclusions;
        var result: ExclusionsId = .empty;
        while (at != .empty) {
            const item = self.exclusions.items[@intFromEnum(at) - 1];
            if (self.strip(selection, item.path) != null) return null;
            if (self.strip(item.path, selection)) |tail| result = try self.exclude(result, tail);
            at = item.next;
        }
        return result;
    }

    fn overlaps(self: *const Store, a: PathId, b: PathId) bool {
        return self.matchingStrip(a, b) != null or self.matchingStrip(b, a) != null;
    }

    fn facts(self: *const Store, id: SetId) []const Fact {
        if (id == .empty) return &.{};
        return self.sets.items[@intFromEnum(id) - 1].facts;
    }

    fn hasLend(self: *const Store, id: SetId) bool {
        return id != .empty and self.sets.items[@intFromEnum(id) - 1].has_lend;
    }

    fn hasInvalidatableOrigin(self: *const Store, id: SetId) bool {
        return id != .empty and self.sets.items[@intFromEnum(id) - 1].has_invalidatable_origin;
    }

    /// Self-containment depends on local origin identity even after that
    /// origin has been invalidated. Index each immutable set once, so moving
    /// a wide carrier through fresh bindings does not revisit its fields.
    fn containsLocalOrigin(self: *Store, set: SetId, owner: BindingId) !bool {
        const set_facts = self.facts(set);
        if (set_facts.len == 0) return false;
        if (set_facts.len == 1) return !set_facts[0].origin.external and set_facts[0].origin.place.root == owner;
        if (self.local_origins.get(set)) |owners| return owners.contains(owner);
        var owners: std.AutoHashMapUnmanaged(BindingId, void) = .empty;
        errdefer owners.deinit(self.gpa);
        for (set_facts) |fact| {
            if (!fact.origin.external) try owners.put(self.gpa, fact.origin.place.root, {});
        }
        try self.local_origins.put(self.gpa, set, owners);
        return owners.contains(owner);
    }

    /// The distinct roots the facts of a set observe: only the facts not yet
    /// invalidated unless `invalidated` is set. A set of many fields over
    /// one owner is one root, found once per immutable set, so a wide
    /// carrier moved through many bindings does not revisit its fields.
    fn ownersOf(self: *Store, set: SetId, invalidated: bool) ![]const BindingId {
        const set_facts = self.facts(set);
        const entry = try self.owner_lists.getOrPut(self.gpa, set);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .valid = &.{}, .all = &.{} };
            errdefer _ = self.owner_lists.remove(set);
            const all = try self.distinctRoots(set_facts, true);
            errdefer self.gpa.free(all);
            entry.value_ptr.* = .{ .valid = try self.distinctRoots(set_facts, false), .all = all };
        }
        return if (invalidated) entry.value_ptr.all else entry.value_ptr.valid;
    }

    fn distinctRoots(self: *Store, set_facts: []const Fact, invalidated: bool) ![]const BindingId {
        var roots: std.ArrayList(BindingId) = .empty;
        errdefer roots.deinit(self.gpa);
        for (set_facts) |fact| {
            if (fact.invalid != .none and !invalidated) continue;
            try roots.append(self.gpa, fact.origin.place.root);
        }
        std.mem.sortUnstable(BindingId, roots.items, {}, struct {
            fn less(_: void, a: BindingId, b: BindingId) bool {
                return @intFromEnum(a) < @intFromEnum(b);
            }
        }.less);
        var count: usize = 0;
        for (roots.items) |root| {
            if (count > 0 and roots.items[count - 1] == root) continue;
            roots.items[count] = root;
            count += 1;
        }
        roots.shrinkRetainingCapacity(count);
        return roots.toOwnedSlice(self.gpa);
    }

    fn comparePaths(self: *const Store, a: PathId, b: PathId) std.math.Order {
        var left = a;
        var right = b;
        while (left != right) {
            if (left == .root) return .lt;
            if (right == .root) return .gt;
            const x = self.path(left);
            const y = self.path(right);
            if (x.head != y.head) return std.math.order(x.head, y.head);
            left = x.tail;
            right = y.tail;
        }
        return .eq;
    }

    fn before(self: *const Store, a: Fact, b: Fact) bool {
        const aa = [_]u64{ @intFromEnum(a.origin.place.root), @intFromEnum(a.origin.place.path), @intFromBool(a.origin.external), @intFromEnum(a.origin.temporary), @intFromEnum(a.origin.statement), @intFromEnum(a.origin.lent), @intFromEnum(a.invalid), @intFromBool(a.ambient), @intFromBool(a.symbolic) };
        const bb = [_]u64{ @intFromEnum(b.origin.place.root), @intFromEnum(b.origin.place.path), @intFromBool(b.origin.external), @intFromEnum(b.origin.temporary), @intFromEnum(b.origin.statement), @intFromEnum(b.origin.lent), @intFromEnum(b.invalid), @intFromBool(b.ambient), @intFromBool(b.symbolic) };
        const order = std.mem.order(u64, &aa, &bb);
        if (order != .eq) return order == .lt;
        const paths = self.comparePaths(a.path, b.path);
        return if (paths != .eq) paths == .lt else @intFromEnum(a.exclusions) < @intFromEnum(b.exclusions);
    }

    /// Adjacent slots with the same dependency share a range, keeping repeated
    /// array initializers and sequential replacement proportional to their runs.
    fn mergePaths(self: *Store, a: PathId, b: PathId) Allocator.Error!?PathId {
        if (a == b) return a;
        if (a == .root or b == .root) return null;
        const x = self.path(a);
        const y = self.path(b);
        if (x.head == y.head) {
            const tail = (try self.mergePaths(x.tail, y.tail)) orelse return null;
            return try self.prepend(x.head, tail);
        }
        if (x.tail != y.tail or x.head < indexed_element or y.head < indexed_element) return null;
        if (@as(u64, rangeFirst(x.head)) > @as(u64, rangeLast(y.head)) + 1 or
            @as(u64, rangeFirst(y.head)) > @as(u64, rangeLast(x.head)) + 1) return null;
        return try self.prepend(elementRange(@min(rangeFirst(x.head), rangeFirst(y.head)), @max(rangeLast(x.head), rangeLast(y.head))), x.tail);
    }

    fn intern(self: *Store, input: []const Fact) !SetId {
        if (input.len == 0) return .empty;
        var scratch: []Fact = &.{};
        defer self.gpa.free(scratch);
        var canonical = input;
        if (input.len > 1) {
            scratch = try self.gpa.dupe(Fact, input);
            // The ordering includes every fact field, so ties are identical.
            std.mem.sortUnstable(Fact, scratch, self, before);
            var count: usize = 0;
            for (scratch) |fact| {
                if (count > 0) {
                    var previous = scratch[count - 1];
                    previous.exclusions = fact.exclusions;
                    if (std.meta.eql(previous, fact)) {
                        scratch[count - 1].exclusions = try self.commonExclusions(scratch[count - 1].exclusions, fact.exclusions);
                        continue;
                    }
                    previous = scratch[count - 1];
                    previous.path = fact.path;
                    if (std.meta.eql(previous, fact)) if (try self.mergePaths(scratch[count - 1].path, fact.path)) |merged| {
                        scratch[count - 1].path = merged;
                        continue;
                    };
                }
                scratch[count] = fact;
                count += 1;
            }
            canonical = scratch[0..count];
        }
        var hash = std.hash.Wyhash.init(0);
        var has_invalidatable_origin = false;
        var has_lend = false;
        for (canonical) |fact| {
            has_invalidatable_origin = has_invalidatable_origin or dependencyOwner(fact) != null;
            has_lend = has_lend or fact.origin.lent != .none;
            const words = [_]u64{ @intFromEnum(fact.path), @intFromEnum(fact.origin.place.root), @intFromEnum(fact.origin.place.path), @intFromBool(fact.origin.external), @intFromEnum(fact.origin.temporary), @intFromEnum(fact.origin.statement), @intFromEnum(fact.origin.lent), @intFromEnum(fact.invalid), @intFromBool(fact.ambient), @intFromBool(fact.symbolic), @intFromEnum(fact.exclusions) };
            hash.update(std.mem.sliceAsBytes(&words));
        }
        const entry = try self.set_index.getOrPut(self.gpa, hash.final());
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        for (entry.value_ptr.items) |candidate| {
            const old = self.facts(candidate);
            if (old.len != canonical.len) continue;
            var equal = true;
            for (old, canonical) |a, b| if (!std.meta.eql(a, b)) {
                equal = false;
                break;
            };
            if (equal) return candidate;
        }
        const owned = try self.gpa.dupe(Fact, canonical);
        errdefer self.gpa.free(owned);
        const id: SetId = @enumFromInt(self.sets.items.len + 1);
        try entry.value_ptr.ensureUnusedCapacity(self.gpa, 1);
        try self.sets.append(self.gpa, .{ .facts = owned, .has_invalidatable_origin = has_invalidatable_origin, .has_lend = has_lend });
        entry.value_ptr.appendAssumeCapacity(id);
        return id;
    }

    fn join(self: *Store, a: SetId, b: SetId) !SetId {
        if (a == b or b == .empty) return a;
        if (a == .empty) return b;
        var facts_out: std.ArrayList(Fact) = .empty;
        defer facts_out.deinit(self.gpa);
        try facts_out.appendSlice(self.gpa, self.facts(a));
        try facts_out.appendSlice(self.gpa, self.facts(b));
        return self.intern(facts_out.items);
    }

    fn opaqueBoundary(self: *Store, path_id: PathId) Allocator.Error!?struct { prefix: PathId, suffix: PathId } {
        var opaque_at = path_id;
        while (opaque_at != .root and self.path(opaque_at).head != opaque_projection) {
            opaque_at = self.path(opaque_at).tail;
        }
        if (opaque_at == .root) return null;
        var heads: std.ArrayList(u96) = .empty;
        defer heads.deinit(self.gpa);
        var at = path_id;
        while (at != opaque_at) {
            const step = self.path(at);
            try heads.append(self.gpa, step.head);
            at = step.tail;
        }
        var prefix: PathId = .root;
        var i = heads.items.len;
        while (i != 0) {
            i -= 1;
            prefix = try self.prepend(heads.items[i], prefix);
        }
        return .{ .prefix = prefix, .suffix = self.path(opaque_at).tail };
    }

    fn select(self: *Store, set: SetId, prefix: PathId) Allocator.Error!SetId {
        if (prefix == .root) return set;
        // A generic projection hides the selected container's representation.
        // Summarize only that container, then preserve its dependencies through
        // every subsequent result selection, as callable contracts do.
        if (try self.opaqueBoundary(prefix)) |cut| {
            const carried = try self.select(set, cut.prefix);
            return self.select(try self.summarize(carried), cut.suffix);
        }
        var out: std.ArrayList(Fact) = .empty;
        defer out.deinit(self.gpa);
        for (self.facts(set)) |fact| {
            var selected = fact;
            if (self.matchingStrip(fact.path, prefix)) |tail| {
                selected.path = tail;
            } else if (fact.ambient and self.matchingStrip(prefix, fact.path) != null) {
                selected.exclusions = (try self.selectExclusions(fact.exclusions, self.matchingStrip(prefix, fact.path).?)) orelse continue;
                if (fact.symbolic) selected.origin.place.path = try self.concat(fact.origin.place.path, self.matchingStrip(prefix, fact.path).?);
                selected.path = .root;
            } else continue;
            try out.append(self.gpa, selected);
        }
        return self.intern(out.items);
    }

    fn prefixed(self: *Store, set: SetId, prefix_path: PathId) !SetId {
        if (prefix_path == .root or set == .empty) return set;
        var out: std.ArrayList(Fact) = .empty;
        defer out.deinit(self.gpa);
        for (self.facts(set)) |fact| {
            var next_fact = fact;
            next_fact.path = try self.concat(prefix_path, fact.path);
            try out.append(self.gpa, next_fact);
        }
        return self.intern(out.items);
    }

    fn summarize(self: *Store, set: SetId) !SetId {
        var out: std.ArrayList(Fact) = .empty;
        defer out.deinit(self.gpa);
        for (self.facts(set)) |fact| {
            var carried = fact;
            carried.path = .root;
            carried.ambient = true;
            carried.exclusions = .empty;
            carried.symbolic = false;
            try out.append(self.gpa, carried);
        }
        return self.intern(out.items);
    }
};

pub fn check(gpa: Allocator, program: *const ExpandedProgram, res: *const Resolution, typing: *const Typing, cfg: *const Cfg, cancelled: *const std.AutoHashMapUnmanaged(cfg_mod.Placement, void), sink: *Sink) !void {
    for (cfg.functions) |*function| {
        var needed = false;
        for (cfg.blocks[function.blocks.start..function.blocks.end]) |block| {
            var ops = cfg.opsOf(block);
            while (ops.next()) |op| {
                // A lasting lend's alias names the place it was lent from,
                // and a use through it after that place changed is stale
                // whatever the binder's type carries.
                if (cfg.opTag(op) == .value or
                    (cfg.opTag(op) == .lent and cfg.opPlace(op).root != .none and cfg.isLastingLend(cfg.opPlace(op).root)) or
                    (cfg.opTag(op) == .init and cfg.opPlace(op).root != .none and typing.mayCarryDependencies(typing.bindingType(cfg.opPlace(op).root))))
                {
                    needed = true;
                    break;
                }
            }
            if (needed) break;
        }
        if (!needed) continue;
        const initial: Analysis = .{ .gpa = gpa, .ast = &program.ast, .program = program, .res = res, .typing = typing, .cfg = cfg, .function = function, .cancelled = cancelled, .sink = sink, .store = .{ .gpa = gpa } };
        var analysis = initial;
        defer analysis.deinit();
        if (!try analysis.seedsDependencies()) continue;
        analysis.deinit();
        analysis = initial;
        try analysis.analyze();
    }
}

const Analysis = struct {
    gpa: Allocator,
    ast: *const Ast,
    program: *const ExpandedProgram,
    res: *const Resolution,
    typing: *const Typing,
    cfg: *const Cfg,
    function: *const Function,
    cancelled: *const std.AutoHashMapUnmanaged(cfg_mod.Placement, void),
    sink: *Sink,
    store: Store,
    reported: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    liveness: ?*const Liveness = null,
    selections: std.AutoHashMapUnmanaged(ExprId, Selection) = .empty,
    dependents: Dependents = .{},
    coverage: types.DependencyCoverage = .{},
    carried_sets: std.AutoHashMapUnmanaged(CarriedSet, SetId) = .empty,
    inspected_sets: std.AutoHashMapUnmanaged(SetId, void) = .empty,
    contract_sources: std.AutoHashMapUnmanaged(BindingId, std.ArrayList(u32)) = .empty,
    contracts_indexed: bool = false,
    /// Where a dependency on `owner` first reached `cell`: the source of a
    /// control-flow join into an expression's value, or the write into a
    /// binding. [O-Escapes] and [O-Borrow] reports follow these back to the
    /// expression that carried the dependency. Sized by the function's joins
    /// and writes times the owners each carries.
    arrivals: std.AutoHashMapUnmanaged(Arrival, ExprId) = .empty,
    /// The piece or operand through which a literal, a `borrow` or a call
    /// first borrowed `owner` into its value. An [O-Borrow] report follows
    /// `arrivals` and then this one step further, to the borrow itself; an
    /// [O-Escapes] report stops at the value that escapes. Sized by the
    /// function's borrows times the owners each reaches.
    borrowed_through: std.AutoHashMapUnmanaged(Arrival, ExprId) = .empty,
    /// The scope exits that ended an owner, so an [O-Borrow] report names
    /// the exit rather than an operation. Sized by the function's exits.
    exits: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// Temporaries already reported, apart from `reported` because an
    /// expression can be both a temporary and an invalidating operation.
    reported_temporaries: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// Lends already reported as escaping, keyed by the capture that made
    /// them. Sized by the function's `inout` captures.
    escaped_lends: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// Sites already reported as escaping. A dependency written into an
    /// `inout` parameter is checked at every exit and reported where it was
    /// written, so each exit after that write would repeat one report. Sized
    /// by the function's escapes.
    escaped_sites: std.AutoHashMapUnmanaged(EscapeSite, void) = .empty,
    /// Exits that have reported an escape. Another escape at such an exit is
    /// an independent mistake and is still reported; an exit claimed by any
    /// other report suppresses escapes there as its consequences. Sized by
    /// the function's exits.
    escape_exits: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// Owners already reported as escaping through the result. Each exit
    /// names the value it returns, so one view returned at several exits
    /// would otherwise be reported once per exit; the missing clause is one.
    /// Sized by the function's parameters.
    escaped_owners: std.AutoHashMapUnmanaged(BindingId, void) = .empty,
    /// The capture sources that lent a place `inout`, each of which ended
    /// the earlier observations of that place. Sized likewise.
    lend_sites: std.AutoHashMapUnmanaged(ExprId, void) = .empty,

    const Arrival = struct { cell: Cell, owner: BindingId };

    fn deinit(self: *Analysis) void {
        self.store.deinit();
        self.arrivals.deinit(self.gpa);
        self.borrowed_through.deinit(self.gpa);
        self.exits.deinit(self.gpa);
        self.reported_temporaries.deinit(self.gpa);
        self.escaped_lends.deinit(self.gpa);
        self.escaped_sites.deinit(self.gpa);
        self.escape_exits.deinit(self.gpa);
        self.escaped_owners.deinit(self.gpa);
        self.lend_sites.deinit(self.gpa);
        self.reported.deinit(self.gpa);
        self.selections.deinit(self.gpa);
        self.dependents.deinit(self.gpa);
        self.coverage.deinit(self.gpa);
        self.carried_sets.deinit(self.gpa);
        self.inspected_sets.deinit(self.gpa);
        var contracts = self.contract_sources.valueIterator();
        while (contracts.next()) |run| run.deinit(self.gpa);
        self.contract_sources.deinit(self.gpa);
    }

    /// If every block maps empty state to empty state without creating any
    /// fact, joins remain empty and no dependency diagnostic has an origin.
    /// Probe every block, including unreachable ones, using the same transfer
    /// as the solver. A seeded function restarts with fresh analysis storage.
    fn seedsDependencies(self: *Analysis) !bool {
        var state: State = .empty;
        defer state.deinit(self.gpa);
        for (0..self.function.blocks.end - self.function.blocks.start) |index| {
            state.clearRetainingCapacity();
            try self.transfer(&state, index, .probe);
            if (self.store.sets.items.len != 0) return true;
        }
        return false;
    }

    fn isReadCapture(self: *const Analysis, binding: BindingId) bool {
        return self.res.captureConvention(binding) == .read;
    }

    /// Whether a use of this binding reads the place its alias cell names: a
    /// lend's binder, or a read capture, whose alias stands for the captured
    /// environment.
    fn readsThroughAlias(self: *const Analysis, binding: BindingId) bool {
        return self.cfg.isLend(binding) and (self.res.kindOf(binding) != .capture or self.isReadCapture(binding));
    }

    fn canCarry(self: *const Analysis, ty: types.TypeId) bool {
        return self.typing.mayCarryDependencies(ty);
    }

    fn expansionPath(self: *Analysis, expansion: types.Expansion, index: ?KnownIndex) Allocator.Error!PathId {
        if (expansion.delegation) |delegate| {
            const tail = if (delegate.backing) |backing|
                try self.expansionPath(self.typing.expansions[backing], index)
            else
                try self.store.prepend(if (delegate.deferred_trait != null) opaque_projection else self.arrayElementHead(delegate.field_type, index), .root);
            return if (delegate.field_name) |name| self.store.prepend(@intFromEnum(name), tail) else tail;
        }
        // An authored projection already has a checked canonical place path.
        // Private storage tails may select the receiver's carried contents as
        // a whole; they do not invent a field in the source expression.
        return (try self.selectedPathWithIndex(expansion.path, .{ .binding = expansion.index, .index = index })).path;
    }

    fn knownIndex(self: *const Analysis, expression: ExprId, substitution: ?IndexSubstitution) ?KnownIndex {
        const at = self.ast.withoutGroups(expression);
        if (substitution) |bound| {
            if (bound.binding != types.Expansion.no_binding and
                @intFromEnum(self.res.targetOf(at)) == bound.binding) return bound.index;
        }
        const from_end = self.ast.exprTag(at) == .from_end;
        const value_at = if (from_end) self.ast.withoutGroups(self.ast.unaryOperand(at)) else at;
        const integer = self.typing.foldedIndex(value_at) orelse return null;
        return .{ .value = integer, .from_end = from_end };
    }

    fn arrayElementHead(self: *const Analysis, ty: types.TypeId, index: ?KnownIndex) u96 {
        const shape = self.typing.get(ty);
        if (shape != .array) return element;
        if (index) |known| {
            if (Typing.elementSlot(shape.array.count, known.value, known.from_end)) |slot| return elementHead(slot);
            if (known.from_end) return element;
        }
        // Any successful access into a singleton selects its only slot.
        return if (shape.array.count == 1) elementHead(0) else element;
    }

    fn selectedPath(self: *Analysis, expression: ExprId) Allocator.Error!Selection {
        return self.selectedPathWithIndex(expression, null);
    }

    fn selectedPathWithIndex(self: *Analysis, expression: ExprId, substitution: ?IndexSubstitution) Allocator.Error!Selection {
        if (substitution == null) if (self.selections.get(expression)) |selected| return selected;
        var base = self.ast.withoutGroups(expression);
        while (self.ast.exprTag(base) == .marked) base = self.ast.withoutGroups(self.ast.unaryOperand(base));
        var steps = self.ast.placeSteps(base);
        var path: PathId = .root;
        var carried_source: ExprId = .none;
        while (steps.next()) |step| {
            // A constant reached through a module or a type roots the path:
            // what lies beyond it names no binding this function holds.
            if (self.res.constantNamed(step) != .none) {
                steps.at = step;
                break;
            }
            if (self.typing.carried_places.contains(step) and self.ast.exprTag(step) == .index) carried_source = self.ast.binary(step).lhs;
            if (self.typing.call_index.projectionOf(self.typing, step)) |expansion| {
                path = try self.store.concat(try self.expansionPath(expansion, if (self.ast.exprTag(step) == .index) self.knownIndex(self.ast.binary(step).rhs, substitution) else null), path);
                if (self.typing.placeProjection(step)) |projection| {
                    for (0..projection.observations) |_| path = try self.store.prepend(observed, path);
                }
            } else if (self.typing.placeProjection(step)) |projection| {
                if (projection.field != null) path = try self.store.prepend(@intFromEnum(self.ast.tokenName(self.ast.exprMain(step))), path);
                for (0..projection.observations) |_| path = try self.store.prepend(observed, path);
            } else {
                const head = if (self.ast.exprTag(step) == .index) self.arrayElementHead(self.typing.exprType(self.ast.binary(step).lhs), self.knownIndex(self.ast.binary(step).rhs, substitution)) else @as(u96, @intFromEnum(self.ast.tokenName(self.ast.exprMain(step))));
                path = try self.store.prepend(head, path);
            }
        }
        const selected: Selection = .{ .root = steps.at, .path = path, .carried_source = carried_source };
        if (substitution == null) try self.selections.put(self.gpa, expression, selected);
        return selected;
    }

    fn value(self: *Analysis, state: *const State, expr: ExprId) !SetId {
        if (expr == .none) return .empty;
        const id = self.ast.withoutGroups(expr);
        if (!self.canCarry(self.typing.exprType(id))) return .empty;
        if (state.get(Cell.expression(id))) |found| return found;
        if (self.ast.exprTag(id) == .marked) return self.value(state, self.ast.unaryOperand(id));
        const selected = try self.selectedPath(id);
        const base = if (self.ast.refersToBinding(selected.root))
            state.get(Cell.binding(self.res.targetOf(selected.root))) orelse .empty
        else
            state.get(Cell.expression(selected.root)) orelse .empty;
        return self.store.select(base, selected.path);
    }

    fn put(self: *Analysis, state: *State, cell: Cell, set: SetId) !void {
        const old = state.get(cell) orelse .empty;
        if (old == set) return;
        self.dependents.remove(self.gpa, &self.store, cell, old);
        if (set == .empty) {
            _ = state.remove(cell);
        } else {
            try state.put(self.gpa, cell, set);
            try self.dependents.add(self.gpa, &self.store, cell, set);
        }
    }

    fn actualPlace(self: *Analysis, state: *const State, expression: ExprId) !SetId {
        if (try self.temporaryPlace(expression)) |temporary| return temporary;
        return self.selectedPlace(state, try self.selectedPath(expression));
    }

    fn projectedOrigins(self: *Analysis, descriptors: SetId, suffix: PathId) !SetId {
        var origins: std.ArrayList(Fact) = .empty;
        defer origins.deinit(self.gpa);
        const selected = (try self.store.boundary(suffix, true)).prefix;
        for (self.store.facts(descriptors)) |fact| {
            if (fact.path != .root) continue;
            var target = fact;
            target.ambient = false;
            target.exclusions = .empty;
            target.origin.place.path = try self.store.concat(target.origin.place.path, selected);
            try origins.append(self.gpa, target);
        }
        return self.store.intern(origins.items);
    }

    fn selectedPlace(self: *Analysis, state: *const State, selected: Selection) !SetId {
        // A constant's storage is static: nothing owns it, and nothing ends or
        // replaces it, so an observation of it or of any part of it depends on
        // nothing and may be kept or returned anywhere.
        if (self.res.constantNamed(selected.root) != .none) return .empty;
        const root = if (self.ast.refersToBinding(selected.root)) self.res.targetOf(selected.root) else BindingId.none;
        if (try self.store.lastObservation(selected.path)) |cut| {
            const cell = if (root != .none) Cell.binding(root) else Cell.expression(selected.root);
            const descriptor = try self.store.select(state.get(cell) orelse .empty, cut.prefix);
            return self.projectedOrigins(descriptor, cut.suffix);
        }
        if (selected.carried_source != .none) {
            var out: std.ArrayList(Fact) = .empty;
            defer out.deinit(self.gpa);
            for (self.store.facts(try self.value(state, selected.carried_source))) |fact| {
                var target = fact;
                target.path = .root;
                target.ambient = false;
                target.exclusions = .empty;
                target.symbolic = false;
                try out.append(self.gpa, target);
            }
            return self.store.intern(out.items);
        }
        const cut = try self.store.boundary(selected.path, true);
        if (root != .none) if (state.get(Cell.alias(root))) |origins| {
            return self.projectedOrigins(origins, cut.prefix);
        };
        if (root == .none) return .empty;
        // An indexed observation depends on its containing storage; an unknown
        // element cannot establish disjointness from a later update.
        return self.store.intern(&.{.{ .origin = .{ .place = .{ .root = root, .path = cut.prefix } } }});
    }

    /// The storage a borrowed temporary is evaluated into, which its
    /// statement's end invalidates, or null where `expression` is not one.
    fn temporaryPlace(self: *Analysis, expression: ExprId) !?SetId {
        const temporary = self.ast.withoutGroups(expression);
        const statement = self.cfg.temporary_statements.get(temporary) orelse return null;
        return try self.store.intern(&.{.{ .origin = .{ .place = .{ .root = .none }, .temporary = temporary, .statement = statement } }});
    }

    fn borrowed(self: *Analysis, state: *const State, expression: ExprId) !SetId {
        const location = try self.actualPlace(state, expression);
        const contained = try self.store.prefixed(try self.value(state, expression), try self.store.prepend(observed, .root));
        return self.store.join(location, contained);
    }

    /// What an `inout` capture of `source` observes: the place, lent
    /// exclusively, and what the place's value carries. Lending a place
    /// `inout` ends every earlier observation of it, as a write does.
    fn lentInout(self: *Analysis, state: *State, source: ExprId) !SetId {
        try self.lend_sites.put(self.gpa, source, {});
        const location = try self.actualPlace(state, source);
        var lent: std.ArrayList(Fact) = .empty;
        defer lent.deinit(self.gpa);
        for (self.store.facts(location)) |fact| {
            if (!fact.origin.external) try self.invalidate(state, fact.origin.place, null, source);
            var exclusive = fact;
            exclusive.origin.lent = source;
            try lent.append(self.gpa, exclusive);
        }
        const contained = try self.store.prefixed(try self.value(state, source), try self.store.prepend(observed, .root));
        return self.store.join(try self.store.intern(lent.items), contained);
    }

    fn invalidate(self: *Analysis, state: *State, place: ?Place, run: ?cfg_mod.Op.Run, at: ExprId) !void {
        if (place) |owner| {
            var changed = owner;
            if (try self.store.opaqueBoundary(owner.path)) |cut| changed.path = cut.prefix;
            return self.invalidatePlace(state, changed, at);
        }
        // Scope exits inspect live owner identities, without revisiting each
        // unaffected carrier. Scope membership remains the CFG's answer.
        var ended: std.ArrayList(Place) = .empty;
        defer ended.deinit(self.gpa);
        var owners = self.dependents.owners.by_owner.keyIterator();
        while (owners.next()) |key| {
            const root = key.asBinding() orelse continue;
            if (self.cfg.endsScopeOf(run.?, root)) try ended.append(self.gpa, .{ .root = root });
        }
        if (ended.items.len != 0) try self.exits.put(self.gpa, at, {});
        for (ended.items) |owner| try self.invalidatePlace(state, owner, at);
    }

    fn invalidatePlace(self: *Analysis, state: *State, place: Place, at: ExprId) !void {
        return self.invalidateObservations(state, place, at, .every);
    }

    /// Which observations of a place an access ends: a write, a move or a
    /// scope exit ends every one, and a read ends only exclusive lends.
    const Ended = enum { every, lends };

    fn invalidateObservations(self: *Analysis, state: *State, place: Place, at: ExprId, ended: Ended) !void {
        const owner = Owner.binding(place.root);
        const sets = switch (ended) {
            .every => try self.dependents.owners.setsOverlapping(self.gpa, &self.store, owner, place.path),
            .lends => try self.dependents.lenders.setsOverlapping(self.gpa, &self.store, owner, place.path),
        };
        defer self.gpa.free(sets);
        for (sets) |set| {
            var out: std.ArrayList(Fact) = .empty;
            defer out.deinit(self.gpa);
            var changed = false;
            for (self.store.facts(set)) |fact| {
                var next = fact;
                if (!fact.origin.external and fact.invalid == .none and fact.origin.statement == .none and
                    (ended == .every or fact.origin.lent != .none) and
                    place.root == fact.origin.place.root and self.store.overlaps(place.path, fact.origin.place.path))
                {
                    next.invalid = at;
                    changed = true;
                }
                try out.append(self.gpa, next);
            }
            if (!changed) continue;
            try self.replaceSet(state, set, out.items);
        }
    }

    /// Ends every temporary the statement anchored at `statement` made. The
    /// invalid site is the temporary itself, which is what a later use of a
    /// value borrowing it is reported against.
    fn invalidateTemporaries(self: *Analysis, state: *State, statement: ExprId) !void {
        const sets = try self.dependents.owners.setsOverlapping(self.gpa, &self.store, Owner.statement(statement), .root);
        defer self.gpa.free(sets);
        for (sets) |set| {
            var out: std.ArrayList(Fact) = .empty;
            defer out.deinit(self.gpa);
            for (self.store.facts(set)) |fact| {
                var next = fact;
                if (fact.invalid == .none and fact.origin.statement == statement) next.invalid = fact.origin.temporary;
                try out.append(self.gpa, next);
            }
            try self.replaceSet(state, set, out.items);
        }
    }

    /// Moves every carrier of `set` to the set holding `facts` instead.
    fn replaceSet(self: *Analysis, state: *State, set: SetId, facts: []const Fact) !void {
        const updated = try self.store.intern(facts);
        const cells = try self.dependents.carriers(self.gpa, set);
        defer self.gpa.free(cells);
        for (cells) |cell| try self.put(state, cell, updated);
    }

    /// The later point that still needs an observation, which an [O-Borrow]
    /// report labels beside the operation that invalidated it.
    const Need = union(enum) {
        /// An expression reads the observation.
        used: ExprId,
        /// An owning `for` walks this value again: its next pass takes the
        /// next element from it, through `next` or from the array.
        walked: ExprId,
        /// The function returns this value, and the caller receives the
        /// observation with it.
        returned: ExprId,
        /// This inout parameter still holds the observation when the
        /// function returns.
        retained: BindingId,
    };

    fn needLabel(self: *const Analysis, need: Need, fact: Fact) diagnostics.Label {
        return switch (need) {
            .used => |at| .{ .file = self.ast.fileOfExpr(at), .span = self.ast.exprSpan(at), .message = "the observation is still used here", .style = .secondary },
            .walked => |at| .{ .file = self.ast.fileOfExpr(at), .span = self.ast.exprSpan(at), .message = "the loop's next pass still walks the observation here", .style = .secondary },
            // Recorded arrivals lead from a returned block to the expression
            // that carried the dependency into it.
            .returned => |result| blk: {
                const at = self.carriedFrom(result, fact.origin.place.root);
                break :blk .{ .file = self.ast.fileOfExpr(at), .span = self.ast.exprSpan(at), .message = "the observation is returned here", .style = .secondary };
            },
            .retained => |parameter| blk: {
                const token = self.res.declaringToken(parameter);
                break :blk .{ .file = self.ast.fileOf(token), .span = self.ast.tokenSpan(token), .message = "this inout parameter still holds the observation when the function returns", .style = .secondary };
            },
        };
    }

    /// Reports each invalidation `set` records, at the operation that
    /// invalidated the place, with `need` as the later point that requires it.
    fn stale(self: *Analysis, set: SetId, need: Need, report: bool) !void {
        if (!report or set == .empty or self.inspected_sets.contains(set)) return;
        for (self.store.facts(set)) |fact| {
            if (fact.invalid == .none) continue;
            if (fact.origin.temporary != .none) {
                switch (need) {
                    .used, .walked => |at| try self.temporaryOutlived(fact.origin.temporary, at, false),
                    .returned => |result| try self.temporaryOutlived(fact.origin.temporary, result, true),
                    // A value an inout parameter keeps leaves with it.
                    .retained => try self.temporaryOutlived(fact.origin.temporary, .none, true),
                }
                continue;
            }
            const site = fact.invalid;
            if (self.reported.contains(site)) continue;
            try self.reported.put(self.gpa, site, {});
            if (self.exits.contains(site)) {
                try self.ownerEnded(fact, site, need);
                continue;
            }
            if (fact.origin.lent != .none) {
                try self.usedWhileLent(fact, site, need);
                continue;
            }
            if (self.lend_sites.contains(site)) {
                const labels = try self.sink.arena.dupe(diagnostics.Label, &.{ .{ .file = self.ast.fileOfExpr(site), .span = self.ast.exprSpan(site), .message = "lending the place `inout` here ends its earlier observations" }, self.needLabel(need, fact) });
                try self.sink.add(.{ .severity = .err, .code = .o_borrow, .message = "this `inout` capture lends a place that an earlier observation still needs", .labels = labels, .notes = try self.sink.arena.dupe([]const u8, &.{"make the capture after the observation's last use"}) });
                continue;
            }
            const primary: diagnostics.Label = .{ .file = self.ast.fileOfExpr(site), .span = self.ast.exprSpan(site), .message = "keep this place available until the last use of its observation" };
            const labels = try self.sink.arena.dupe(diagnostics.Label, &.{ primary, self.needLabel(need, fact) });
            try self.sink.add(.{ .severity = .err, .code = .o_borrow, .message = "this operation invalidates a place that a later observation still needs", .labels = labels });
        }
        // Invalidation creates a different SetId. Reported sites only grow,
        // so revisiting this immutable set cannot add another diagnostic.
        try self.inspected_sets.put(self.gpa, set, {});
    }

    /// [O-Borrow] for a place lent `inout`: `site` reads, writes, moves or
    /// lends the place while `need` still requires the value holding the
    /// lend `fact` records.
    fn usedWhileLent(self: *Analysis, fact: Fact, site: ExprId, need: Need) !void {
        const arena = self.sink.arena;
        const lent = fact.origin.lent;
        const later: diagnostics.Label = switch (need) {
            .used => |at| .{ .file = self.ast.fileOfExpr(at), .span = self.ast.exprSpan(at), .message = "a value holding the lend is still used here", .style = .secondary },
            .walked => |at| .{ .file = self.ast.fileOfExpr(at), .span = self.ast.exprSpan(at), .message = "the loop's next pass takes its next element from this value, which holds the lend", .style = .secondary },
            else => self.needLabel(need, fact),
        };
        const here: diagnostics.Label = .{ .file = self.ast.fileOfExpr(site), .span = self.ast.exprSpan(site), .message = if (site == lent)
            "this lends the place again while its earlier lend is still used"
        else
            "this uses the place while it is lent" };
        // A capture that lends the place again, as one made in a loop does,
        // is both the use and the earlier lend.
        const labels = if (site == lent) try arena.dupe(diagnostics.Label, &.{ here, later }) else try arena.dupe(diagnostics.Label, &.{
            here,
            .{ .file = self.ast.fileOfExpr(lent), .span = self.ast.exprSpan(lent), .message = "lent `inout` here", .style = .secondary },
            later,
        });
        try self.sink.add(.{
            .severity = .err,
            .code = .o_borrow,
            .message = "this operation uses a place lent `inout` to a value that is still used",
            .labels = labels,
            .notes = try arena.dupe([]const u8, &.{"a place lent `inout` is reached only through what holds the lend until that value's last use; use it after that, or through the closure"}),
        });
    }

    /// [O-Borrow] at a scope exit: the owner of `fact` ends at `exit` while
    /// `need` still requires a value borrowing it.
    fn ownerEnded(self: *Analysis, fact: Fact, exit: ExprId, need: Need) !void {
        const owner = fact.origin.place.root;
        const arena = self.sink.arena;
        const subject = try self.program.subjectAt(arena, self.res.declaringToken(owner));
        var labels: std.ArrayList(diagnostics.Label) = .empty;
        try labels.append(arena, .{
            .file = self.ast.fileOfExpr(exit),
            .span = cfg_mod.exitSpan(self.ast, exit),
            .message = try std.fmt.allocPrint(arena, "{s} ends here", .{subject}),
        });
        const later: ?ExprId = switch (need) {
            .used, .walked => |at| at,
            .returned => |result| result,
            .retained => null,
        };
        if (later) |at| if (self.borrowSite(at, owner)) |site| try labels.append(arena, .{
            .file = self.ast.fileOfExpr(site),
            .span = self.ast.exprSpan(site),
            .message = "borrowed here",
            .style = .secondary,
        });
        try labels.append(arena, self.needLabel(need, fact));
        try self.sink.add(.{
            .severity = .err,
            .code = .o_borrow,
            .message = try std.fmt.allocPrint(arena, "{s} ends while a value borrowing it is still used", .{subject}),
            .labels = labels.items,
            .notes = try arena.dupe([]const u8, &.{"keep the borrowing value inside the scope, or declare what it borrows outside it"}),
        });
    }

    /// The expression that borrowed `owner` into the value `used` reads:
    /// back from a binding to the value written into it, then through the
    /// arrivals `escape` follows, to the piece or argument that borrowed it.
    fn borrowSite(self: *const Analysis, used: ExprId, owner: BindingId) ?ExprId {
        var start = self.ast.withoutGroups(used);
        if (self.ast.refersToBinding(start)) {
            const binding = self.res.targetOf(start);
            if (binding == .none) return null;
            start = self.arrivals.get(.{ .cell = Cell.binding(binding), .owner = owner }) orelse return null;
        }
        var site = self.carriedFrom(start, owner);
        // A borrow nested in a borrowed piece, `"{"x {name}"}"`, is followed
        // to the innermost one, each step to a distinct recorded borrow.
        var steps: usize = 0;
        while (self.borrowed_through.get(.{ .cell = Cell.expression(site), .owner = owner })) |inner| : (steps += 1) {
            if (inner == site or steps > self.borrowed_through.count()) break;
            site = self.carriedFrom(inner, owner);
        }
        return if (site == used) null else site;
    }

    /// [O-Temporary]: a value borrowing `temporary` is used at `used` after
    /// the temporary's statement ended, or `leaves` the function. Each
    /// temporary is reported once.
    fn temporaryOutlived(self: *Analysis, temporary: ExprId, used: ExprId, leaves: bool) !void {
        if ((try self.reported_temporaries.getOrPut(self.gpa, temporary)).found_existing) return;
        const primary: diagnostics.Label = .{
            .file = self.ast.fileOfExpr(temporary),
            .span = self.ast.exprSpan(temporary),
            .message = if (leaves)
                "this temporary ends with its statement, before the caller reads the result"
            else
                "this temporary ends with its statement",
        };
        // A value that leaves is shown by the primary label alone: the exit a
        // function's body falls off has no expression of its own to point at.
        const labels = if (leaves) try self.sink.arena.dupe(diagnostics.Label, &.{primary}) else try self.sink.arena.dupe(diagnostics.Label, &.{ primary, .{
            .file = self.ast.fileOfExpr(used),
            .span = self.ast.exprSpan(used),
            .message = "and a value borrowing it is used here",
            .style = .secondary,
        } });
        try self.sink.add(.{
            .severity = .err,
            .code = .o_temporary,
            .message = if (leaves)
                "a returned value cannot borrow a temporary"
            else
                "a value borrowing a temporary is used after the temporary's statement",
            .labels = labels,
            .notes = try self.sink.arena.dupe([]const u8, &.{if (leaves)
                "return a value that does not borrow it, or borrow a parameter instead"
            else
                "bind the value with `let` first, and borrow the binding"}),
        });
    }

    fn use(self: *Analysis, state: *const State, expr: ExprId, report: bool) !void {
        if (!report) return;
        const selected = try self.selectedPath(expr);
        if (selected.carried_source != .none) try self.stale(try self.value(state, selected.carried_source), .{ .used = expr }, report);
        // A lasting lend reads the place it was lent from, whatever its type
        // carries: a scalar read through one still observes that place, so a
        // write or a move of it before this use left the lend naming nothing.
        // A construct's own lends are guarded for the construct's extent by
        // [O-Lent] instead.
        if (self.ast.refersToBinding(selected.root)) {
            const root = self.res.targetOf(selected.root);
            if (root != .none and self.cfg.isLastingLend(root)) {
                if (state.get(Cell.alias(root))) |origins| try self.stale(origins, .{ .used = expr }, report);
            }
        }
        const cut = try self.store.boundary(selected.path, false);
        if (cut.remaining == .root and !self.canCarry(self.typing.exprType(expr))) return;
        if (self.ast.refersToBinding(selected.root)) {
            const binding = self.res.targetOf(selected.root);
            const carried = try self.carriedBy(state.get(Cell.binding(binding)) orelse .empty, self.typing.bindingType(binding));
            try self.stale(try self.store.select(carried, cut.prefix), .{ .used = expr }, report);
        } else {
            const carried = try self.carriedBy(state.get(Cell.expression(selected.root)) orelse .empty, self.typing.exprType(selected.root));
            try self.stale(try self.store.select(carried, cut.prefix), .{ .used = expr }, report);
        }
    }

    fn keepOutsideWrite(self: *Analysis, kept: *std.ArrayList(Fact), fact: Fact, existing: PathId, written: PathId, prefix: PathId) Allocator.Error!void {
        if (written == .root) return;
        if (existing == .root) {
            var remaining = fact;
            if (fact.ambient) remaining.exclusions = try self.store.exclude(fact.exclusions, written);
            try kept.append(self.gpa, remaining);
            return;
        }
        const old = self.store.path(existing);
        const target = self.store.path(written);
        if (old.head == target.head) {
            return self.keepOutsideWrite(kept, fact, old.tail, target.tail, try self.store.concat(prefix, try self.store.prepend(old.head, .root)));
        }
        if (old.head >= indexed_element and target.head >= indexed_element and headsOverlap(old.head, target.head)) {
            const first = rangeFirst(old.head);
            const last = rangeLast(old.head);
            const changed_first = @max(first, rangeFirst(target.head));
            const changed_last = @min(last, rangeLast(target.head));
            if (first < changed_first) {
                var left = fact;
                left.path = try self.store.concat(prefix, try self.store.prepend(elementRange(first, changed_first - 1), old.tail));
                try kept.append(self.gpa, left);
            }
            if (changed_last < last) {
                var right = fact;
                right.path = try self.store.concat(prefix, try self.store.prepend(elementRange(changed_last + 1, last), old.tail));
                try kept.append(self.gpa, right);
            }
            const middle = elementRange(changed_first, changed_last);
            var changed = fact;
            changed.path = try self.store.concat(prefix, try self.store.prepend(middle, old.tail));
            return self.keepOutsideWrite(kept, changed, old.tail, target.tail, try self.store.concat(prefix, try self.store.prepend(middle, .root)));
        }
        try kept.append(self.gpa, fact);
    }

    fn write(self: *Analysis, state: *State, root: BindingId, path: PathId, written: SetId, at: ExprId, report: bool) !void {
        const value_set = try self.heldAs(written, self.typing.bindingType(root));
        try self.noteArrivalsOf(Cell.binding(root), value_set, at, true);
        if (report and !self.reported.contains(at) and try self.store.containsLocalOrigin(value_set, root)) {
            try self.reported.put(self.gpa, at, {});
            try self.sink.addErrorFmt(.o_escapes, self.ast.fileOfExpr(at), self.ast.exprSpan(at), "keep an observation outside the owner it observes", "this write would make a value contain an observation of itself", .{});
        }
        if (path == .root) return self.put(state, Cell.binding(root), value_set);
        if (try self.store.opaqueBoundary(path)) |cut| {
            // An unresolved projection may update any part of its container.
            // Retain old contents and summarize the incoming owners there;
            // an opaque selection marker never becomes a stored fact path.
            const incoming = try self.store.prefixed(try self.store.summarize(value_set), cut.prefix);
            const old = state.get(Cell.binding(root)) orelse .empty;
            return self.put(state, Cell.binding(root), try self.store.join(old, incoming));
        }
        // Known slots are replaced exactly. An unknown index may leave any
        // previous slot untouched, so its write joins rather than removes facts.
        var precise = true;
        var step_at = path;
        while (step_at != .root) {
            const step = self.store.path(step_at);
            if (step.head == element) precise = false;
            step_at = step.tail;
        }
        var kept: std.ArrayList(Fact) = .empty;
        defer kept.deinit(self.gpa);
        for (self.store.facts(state.get(Cell.binding(root)) orelse .empty)) |fact| {
            if (precise) {
                try self.keepOutsideWrite(&kept, fact, fact.path, path, .root);
            } else try kept.append(self.gpa, fact);
        }
        const old = try self.store.intern(kept.items);
        try self.put(state, Cell.binding(root), try self.store.join(old, try self.store.prefixed(value_set, path)));
    }

    fn evaluate(self: *Analysis, state: *State, op: OpId) !void {
        const id = self.cfg.opAt(op);
        const source = self.cfg.ops.items(.source)[op.index()];
        const projection = self.cfg.ops.items(.projection)[op.index()];
        var result: SetId = .empty;
        if (self.ast.exprTag(id) == .lambda) {
            if (projection != .whole) {
                const captured = if (self.cfg.ops.items(.exclusive)[op.index()])
                    try self.lentInout(state, source)
                else if (self.cfg.ops.items(.reading)[op.index()])
                    try self.borrowed(state, source)
                else
                    try self.value(state, source);
                try self.put(state, Cell.capture(source), try self.store.prefixed(captured, try self.projectionPath(projection)));
                return;
            }
            // Each field becomes live before later initializers run. Joining
            // once after construction avoids copying every preceding field
            // for each new capture.
            var combined: std.ArrayList(Fact) = .empty;
            defer combined.deinit(self.gpa);
            const closure = self.res.closures.closureOf(id);
            if (closure != .none) for (self.res.closureCaptures(closure)) |capture| {
                try combined.appendSlice(self.gpa, self.store.facts(state.get(Cell.capture(capture.source)) orelse .empty));
            };
            result = try self.store.intern(combined.items);
        } else if (source != .none) {
            result = try self.value(state, source);
            try self.noteArrivals(Cell.expression(id), result, source);
        } else switch (self.ast.exprTag(id)) {
            .borrow => {
                result = try self.borrowed(state, self.ast.unaryOperand(id));
                try self.noteBorrowedThrough(Cell.expression(id), result, self.ast.unaryOperand(id));
            },
            .copy_ => result = try self.value(state, self.ast.unaryOperand(id)),
            .grouped, .marked => result = try self.value(state, self.ast.unaryOperand(id)),
            .name_ref, .param_argument, .field, .index, .dereference => {
                const selected = try self.selectedPath(id);
                const base = if (self.ast.refersToBinding(selected.root))
                    state.get(Cell.binding(self.res.targetOf(selected.root))) orelse .empty
                else
                    state.get(Cell.expression(selected.root)) orelse .empty;
                result = try self.store.select(base, selected.path);
            },
            .struct_literal, .array_literal, .tuple_literal => {
                const args = self.ast.call(id).args;
                const tag = self.ast.exprTag(id);
                const fields = tag == .struct_literal;
                // A tuple's declaration names its components as fields, and
                // `t._0` selects by that name, so a component's facts sit
                // under the field's head rather than an element's. A tuple
                // literal the checker refused has no declaration, and what
                // its components carry reaches nothing.
                const tuple_decl: ?node.DeclId = if (tag == .tuple_literal) self.typing.declOfType(self.typing.constructionType(id)) else null;
                var combined: std.ArrayList(Fact) = .empty;
                defer combined.deinit(self.gpa);
                var i: usize = if (fields) 1 else 0;
                while (i < args.len) : (i += if (fields) 2 else 1) {
                    const component = try self.value(state, args[i]);
                    const head: u96 = switch (tag) {
                        .struct_literal => @intFromEnum(self.ast.tokenName(self.ast.exprMain(args[i - 1]))),
                        .tuple_literal => @intFromEnum(self.ast.declFieldName(tuple_decl orelse continue, i)),
                        else => elementHead(i),
                    };
                    const prefix = try self.store.prepend(head, .root);
                    for (self.store.facts(component)) |fact| {
                        var part = fact;
                        part.path = try self.store.concat(prefix, fact.path);
                        try combined.append(self.gpa, part);
                    }
                }
                // A base supplies the fields the literal does not write, so
                // what it carries under a written field is replaced and what
                // it carries anywhere else arrives in the new value. A fact
                // about the base as a whole cannot be split by field and is
                // kept whole.
                //
                // **Bound:** the written heads are sorted once, and each of the
                // base's facts is one binary search over them: O(w log w +
                // f log w) for w written fields and f facts of the base.
                if (fields) if (self.ast.structLiteralBase(id)) |base| {
                    var written: std.ArrayList(u96) = .empty;
                    defer written.deinit(self.gpa);
                    var at: usize = 0;
                    while (at + 1 < args.len) : (at += 2) try written.append(self.gpa, @intFromEnum(self.ast.tokenName(self.ast.exprMain(args[at]))));
                    std.mem.sort(u96, written.items, {}, std.sort.asc(u96));
                    for (self.store.facts(try self.value(state, base))) |fact| {
                        if (fact.path != .root and std.sort.binarySearch(u96, written.items, self.store.path(fact.path).head, orderHeads) != null) continue;
                        try combined.append(self.gpa, fact);
                    }
                };
                result = try self.store.intern(combined.items);
            },
            .call => {
                const callee = self.ast.withoutGroups(self.ast.call(id).callee);
                const ordinal = types.variantOrdinalOf(&self.res.variant_ordinals, &self.typing.variant_uses, callee);
                if (ordinal) |variant| {
                    for (self.ast.call(id).args, 0..) |arg, index| {
                        const prefix = try self.store.prepend(payloadHead(variant, @intCast(index)), .root);
                        result = try self.store.join(result, try self.store.prefixed(try self.value(state, arg), prefix));
                    }
                } else result = try self.callResult(state, id);
            },
            // A literal observes each piece it borrows and carries what each
            // piece it holds carries.
            .interp => {
                const literal = self.typing.exprType(id);
                for (self.ast.interpolation(id).pieces, 0..) |piece, i| {
                    if (i % 2 == 0) continue;
                    const facts = if (self.typing.interpolationBorrows(literal, @intCast(i)))
                        try self.borrowed(state, piece)
                    else
                        try self.value(state, piece);
                    try self.noteBorrowedThrough(Cell.expression(id), facts, piece);
                    result = try self.store.join(result, facts);
                }
            },
            // The success path of `e else { … }` yields what `e` carried, as
            // `e?` does; its failing path records the block as its source.
            .try_, .unwrap_else => {
                const operand = unwrapped(self.ast, id);
                if (self.typing.successVariantOf(self.typing.exprType(operand))) |variant| {
                    result = try self.store.select(try self.value(state, operand), try self.store.prepend(payloadHead(variant, 0), .root));
                }
            },
            else => {},
        }
        try self.put(state, Cell.expression(id), try self.carriedBy(result, self.typing.exprType(id)));
    }

    fn projectionPath(self: *Analysis, projection: cfg_mod.Projection) !PathId {
        return switch (projection) {
            .whole => .root,
            .field => |field| self.store.prepend(@intFromEnum(field), .root),
            .payload => |payload| self.store.prepend(payloadHead(payload.variant, payload.index), .root),
            .element => self.store.prepend(element, .root),
            .element_component => |field| self.store.prepend(element, try self.store.prepend(@intFromEnum(field), .root)),
            .index => |at| if (self.typing.call_index.projectionOf(self.typing, at)) |expansion|
                self.expansionPath(expansion, null)
            else
                self.store.prepend(element, .root),
        };
    }

    fn contractPath(self: *Analysis, fields: []const types.PathSelector) !PathId {
        var path: PathId = .root;
        var i = fields.len;
        while (i > 0) {
            i -= 1;
            path = try self.store.prepend(switch (fields[i]) {
                .field => |field| @intFromEnum(field),
                .observed => observed,
            }, path);
        }
        return path;
    }

    fn resultPath(self: *Analysis, selectors: []const types.ResultSelector) !PathId {
        var path: PathId = .root;
        var i = selectors.len;
        while (i > 0) {
            i -= 1;
            path = try self.store.prepend(switch (selectors[i]) {
                .field => |field| @intFromEnum(field.name),
                .payload => |payload| payloadHead(@intFromEnum(payload.variant), payload.index),
            }, path);
        }
        return path;
    }

    const CallEndpoint = struct {
        expression: ExprId,
        relative: PathId,
        selected: Selection,
    };

    fn boundaryBinding(self: *const Analysis, root: types.ContractRoot) ?BindingId {
        return switch (root) {
            .parameter => |index| if (index < self.function.parameters.len) self.function.parameters[index] else null,
            .capture => |capture| self.res.closureCaptures(capture.closure)[capture.field.index()].binding,
            .callee => null,
        };
    }

    /// Map an endpoint to the caller's place, including the stored observation
    /// through which a read capture reaches its source.
    fn callEndpoint(self: *Analysis, call: types.NormalizedCall, endpoint: types.ContractPath) !?CallEndpoint {
        var prefix: PathId = .root;
        const expression = switch (endpoint.root) {
            .callee => return null,
            .parameter => |index| blk: {
                if (index >= call.args.len or call.args[index] == .none) return null;
                if (index < call.receiver_adjustments.len) {
                    if (call.receiver_adjustments[index]) |adjustment| {
                        for (0..adjustment.observations) |_| prefix = try self.store.prepend(observed, prefix);
                    }
                }
                break :blk call.args[index];
            },
            .capture => |capture| blk: {
                const binding = self.res.closureCaptures(capture.closure)[capture.field.index()].binding;
                if (self.isReadCapture(binding)) prefix = try self.store.prepend(observed, prefix);
                prefix = try self.store.prepend(@intFromEnum(self.ast.tokenName(self.res.captureNameToken(binding))), prefix);
                break :blk self.ast.call(call.at).callee;
            },
        };
        const relative = try self.store.concat(prefix, try self.contractPath(endpoint.fields));
        var selected = try self.selectedPath(expression);
        selected.path = try self.store.concat(selected.path, relative);
        return .{ .expression = expression, .relative = relative, .selected = selected };
    }

    fn sourceFacts(self: *Analysis, state: *const State, call: types.NormalizedCall, source: types.ContractPath, borrows: bool, direct_borrow: bool) !SetId {
        if (source.root == .callee) {
            std.debug.assert(!borrows and source.fields.len == 0);
            // A generic callback exposes carried dependencies without exposing
            // its environment's field layout or borrowing its storage.
            return self.store.summarize(try self.value(state, self.ast.call(call.at).callee));
        }
        const endpoint = try self.callEndpoint(call, source) orelse return .empty;
        const carried = try self.store.select(try self.value(state, endpoint.expression), endpoint.relative);
        if (!borrows) return if (direct_borrow) carried else self.store.summarize(carried);
        const places = if (try self.temporaryPlace(endpoint.expression)) |temporary|
            temporary
        else
            try self.selectedPlace(state, endpoint.selected);
        try self.noteBorrowedThrough(Cell.expression(call.at), places, endpoint.expression);
        var out: std.ArrayList(Fact) = .empty;
        defer out.deinit(self.gpa);
        for (self.store.facts(places)) |fact| {
            var selected = fact;
            selected.ambient = !direct_borrow;
            try out.append(self.gpa, selected);
        }
        const contents = if (direct_borrow)
            try self.store.prefixed(carried, try self.store.prepend(observed, .root))
        else
            try self.store.summarize(carried);
        return self.store.join(try self.store.intern(out.items), contents);
    }

    fn callResult(self: *Analysis, state: *const State, id: ExprId) !SetId {
        const call = self.typing.call_index.callOf(self.typing, id) orelse return .empty;
        // Recovery preserves the environment representation, including each
        // field's precise observation paths.
        if (call.target == .closure_recovery) return self.value(state, call.args[0]);
        const signature = switch (self.typing.get(call.signature)) {
            .callable => |s| s,
            else => return .empty,
        };
        var combined: std.ArrayList(Fact) = .empty;
        defer combined.deinit(self.gpa);
        for (signature.contracts) |contract| {
            if (contract.kind == .retains) continue;
            const target_type = self.typing.contractTargetType(signature.result, contract.target);
            const carried = try self.sourceFacts(state, call, contract.source, contract.kind == .borrows, self.typing.get(target_type) == .borrow);
            const selected = try self.store.prefixed(carried, try self.resultPath(contract.target));
            try combined.appendSlice(self.gpa, self.store.facts(selected));
        }
        return self.store.intern(combined.items);
    }

    /// One step of `for x in &it`: the walk calls `next` on `it` through the
    /// mark, which changes `it` as an `inout` argument does, so every local
    /// observation of it is invalidated here, once per iteration -- the same
    /// answer `&it.next()` gets from `applyCall`.
    fn applyLentStep(self: *Analysis, state: *State, mark: ExprId) !void {
        if (self.dependents.owners.by_owner.count() == 0) return;
        for (self.store.facts(try self.actualPlace(state, self.ast.unaryOperand(mark)))) |fact| {
            if (!fact.origin.external) try self.invalidate(state, fact.origin.place, null, mark);
        }
    }

    fn applyCall(self: *Analysis, state: *State, id: ExprId, report: bool) !void {
        const normalized = self.typing.call_index.callOf(self.typing, id) orelse return;
        const signature = switch (self.typing.get(normalized.signature)) {
            .callable => |s| s,
            else => return,
        };
        // Without a live local origin, an inout call cannot invalidate an
        // observation. Avoid constructing place facts solely for that check.
        if (self.dependents.owners.by_owner.count() != 0) {
            if (normalized.callee_convention == .inout) {
                for (self.store.facts(try self.actualPlace(state, self.ast.call(id).callee))) |fact| {
                    if (!fact.origin.external) try self.invalidate(state, fact.origin.place, null, id);
                }
            }
            for (self.typing.callableParams(signature), normalized.args) |param, arg| {
                if (arg == .none or param.convention != .inout) continue;
                for (self.store.facts(try self.actualPlace(state, arg))) |fact| {
                    if (!fact.origin.external) try self.invalidate(state, fact.origin.place, null, id);
                }
            }
        }
        // The callable is invoked after its arguments finish evaluating.
        // Its observations must survive their effects and inout writes too.
        if (normalized.target.calleeIsValue()) try self.stale(try self.value(state, self.ast.call(id).callee), .{ .used = self.ast.call(id).callee }, report);
        for (normalized.args) |arg| {
            if (arg != .none) try self.stale(try self.value(state, arg), .{ .used = arg }, report);
        }
        for (signature.contracts) |contract| {
            if (contract.kind != .retains) continue;
            const destination = contract.destination orelse continue;
            const endpoint = try self.callEndpoint(normalized, destination) orelse continue;
            if (!self.ast.refersToBinding(endpoint.selected.root)) continue;
            const root = self.res.targetOf(endpoint.selected.root);
            const path = endpoint.selected.path;
            const added = try self.sourceFacts(state, normalized, contract.source, contract.borrows_source, false);
            const previous = try self.store.select(state.get(Cell.binding(root)) orelse .empty, path);
            try self.write(state, root, path, try self.store.join(previous, added), id, report);
        }
    }

    fn originWithinPath(self: *Analysis, origin: Origin, path: PathId, borrows: bool) !bool {
        if (self.store.strip(origin.place.path, path) != null) return true;
        if (borrows and origin.external) if (try self.store.lastObservation(path)) |cut| {
            // Dereferencing selects the descriptor's stored address.
            return self.store.strip(origin.place.path, try self.store.concat(cut.prefix, cut.suffix)) != null;
        };
        return false;
    }

    fn sourceAllows(self: *Analysis, origin: Origin, source: types.ContractPath, borrows: bool) !bool {
        const binding = self.boundaryBinding(source.root) orelse return false;
        if (binding != origin.place.root) return false;
        // An exclusive lend never leaves the function that lends the place.
        if (origin.lent != .none) return false;
        // A closure-owned place cannot escape, even when a contract names it.
        // Observations already contained in a capture have external origins.
        if (!origin.external and (source.root == .capture or !borrows)) return false;
        var path = try self.contractPath(source.fields);
        if (source.root == .capture and self.isReadCapture(binding)) {
            if (borrows and try self.originWithinPath(origin, path, true)) return true;
            path = try self.store.prepend(observed, path);
        }
        return self.originWithinPath(origin, path, borrows);
    }

    fn noteBorrowedThrough(self: *Analysis, cell: Cell, set: SetId, at: ExprId) !void {
        for (self.store.facts(set)) |fact| {
            if (fact.invalid != .none) continue;
            const entry = try self.borrowed_through.getOrPut(self.gpa, .{ .cell = cell, .owner = fact.origin.place.root });
            if (!entry.found_existing) entry.value_ptr.* = at;
        }
    }

    fn noteArrivals(self: *Analysis, cell: Cell, set: SetId, at: ExprId) !void {
        return self.noteArrivalsOf(cell, set, at, false);
    }

    /// As `noteArrivals`, also for dependencies already invalidated where
    /// `invalidated` is set: a binding written from a value whose owner has
    /// just ended still came from that value, and a report about the ended
    /// owner follows the binding back to it.
    fn noteArrivalsOf(self: *Analysis, cell: Cell, set: SetId, at: ExprId, invalidated: bool) !void {
        const set_facts = self.store.facts(set);
        if (set_facts.len <= few_facts) {
            for (set_facts) |fact| {
                if (fact.invalid != .none and !invalidated) continue;
                const entry = try self.arrivals.getOrPut(self.gpa, .{ .cell = cell, .owner = fact.origin.place.root });
                if (!entry.found_existing) entry.value_ptr.* = at;
            }
            return;
        }
        for (try self.store.ownersOf(set, invalidated)) |owner| {
            const entry = try self.arrivals.getOrPut(self.gpa, .{ .cell = cell, .owner = owner });
            if (!entry.found_existing) entry.value_ptr.* = at;
        }
    }

    /// The expression whose value carried a dependency on `owner` into
    /// `start`'s value: back through each join recorded for a block, branch
    /// or loop, to the break operand or arm tail that supplied it. Each step
    /// moves to a distinct recorded join, so the walk ends within the
    /// function's own arrivals.
    fn carriedFrom(self: *const Analysis, start: ExprId, owner: BindingId) ExprId {
        var site = start;
        var steps: usize = 0;
        while (self.arrivals.get(.{ .cell = Cell.expression(site), .owner = owner })) |earlier| : (steps += 1) {
            if (earlier == site or steps > self.arrivals.count()) break;
            site = earlier;
        }
        return site;
    }

    /// Where a returned value that carries `owner` is reported: what
    /// `carriedFrom` finds, and past a block no join leads out of, its tail,
    /// which is the value a reader would change rather than the braces.
    /// Each step into a tail moves inside the block, so the walk ends within
    /// the block's nesting.
    fn returnedFrom(self: *const Analysis, start: ExprId, owner: BindingId) ExprId {
        var site = self.carriedFrom(start, owner);
        while (self.ast.exprTag(site) == .block) {
            const tail = self.ast.blockOf(site).tail;
            if (tail == .none) break;
            site = self.carriedFrom(self.ast.withoutGroups(tail), owner);
        }
        return site;
    }

    const EscapeSite = struct { file: FileId, span: Span };

    fn exprSite(self: *const Analysis, id: ExprId) EscapeSite {
        return .{ .file = self.ast.fileOfExpr(id), .span = self.ast.exprSpan(id) };
    }

    /// [O-Escapes] at `site`; `lent` is the capture that lends the escaping
    /// place `inout`, or `.none` for a read observation.
    /// What an [O-Escapes] report says escaped: an observation a contract
    /// does not permit, a lend made by the capture `lend`, or, inside a
    /// closure body, an observation of a place lent to it `inout` or one
    /// stored in that place.
    const Escaped = union(enum) { observation, lend: ExprId, from_lent_capture, into_lent_capture };

    fn isLentCapture(self: *const Analysis, binding: BindingId) bool {
        return self.res.captureConvention(binding) == .inout;
    }

    fn escape(self: *Analysis, at: ExprId, site: EscapeSite, escaped: Escaped, origin: ?Origin) !void {
        if (self.reported.contains(at) and !self.escape_exits.contains(at)) return;
        try self.reported.put(self.gpa, at, {});
        try self.escape_exits.put(self.gpa, at, {});
        if ((try self.escaped_sites.getOrPut(self.gpa, site)).found_existing) return;
        const arena = self.sink.arena;
        switch (escaped) {
            .observation => if (origin) |from| {
                if ((try self.escaped_owners.getOrPut(self.gpa, from.place.root)).found_existing) return;
            },
            // Every exit that carries one lend is the same mistake, so the
            // lend is reported once.
            .lend => |lent| {
                if ((try self.escaped_lends.getOrPut(self.gpa, lent)).found_existing) return;
                const labels = try arena.dupe(diagnostics.Label, &.{
                    .{ .file = site.file, .span = site.span, .message = "this value holds the lend" },
                    .{ .file = self.ast.fileOfExpr(lent), .span = self.ast.exprSpan(lent), .message = "lent `inout` here", .style = .secondary },
                });
                return self.sink.add(.{
                    .severity = .err,
                    .code = .o_escapes,
                    .message = "a value holding a place lent `inout` cannot leave the function that lends it",
                    .labels = labels,
                    .notes = try arena.dupe([]const u8, &.{"finish with the value inside this function, or give the closure its own state with a `sink` capture"}),
                });
            },
            .from_lent_capture => return self.sink.add(.{
                .severity = .err,
                .code = .o_escapes,
                .message = "a closure's result cannot observe a place lent to it `inout`",
                .labels = try arena.dupe(diagnostics.Label, &.{.{ .file = site.file, .span = site.span, .message = "this observes the lent place" }}),
                .notes = try arena.dupe([]const u8, &.{"the next call may change the place, so return a value of its own, such as a copy"}),
            }),
            .into_lent_capture => return self.sink.add(.{
                .severity = .err,
                .code = .o_escapes,
                .message = "a closure cannot store an observation in a place lent to it `inout`",
                .labels = try arena.dupe(diagnostics.Label, &.{.{ .file = site.file, .span = site.span, .message = "this stores an observation in the lent place" }}),
                .notes = try arena.dupe([]const u8, &.{"the observation could outlive what it observes; store a value that observes nothing"}),
            }),
        }
        const message = "this boundary carries an observation from an owner its signature does not permit";
        const primary: diagnostics.Label = .{ .file = site.file, .span = site.span, .message = "escape observations only from the signature's declared sources" };
        // A member without a clause is held to its trait signature's
        // contract, so the report names the signature that declared it.
        const sig = if (self.function.decl == .none) null else self.typing.adopted_contracts.get(self.function.decl);
        const promised = switch (self.typing.get(if (sig) |declared| self.typing.declSignature(declared) else .poison)) {
            .callable => |callable| callable,
            else => return self.escapeUnderCarrierDefault(primary, message, origin),
        };
        const written = self.ast.declParams(sig.?);
        const names = try self.sink.arena.alloc([]const u8, written.len);
        for (written, names) |param, *spelled| spelled.* = self.ast.tokenText(param.name);
        const clause = try types.contractClause(self.sink.arena, promised.contracts, names);
        const name = self.ast.declName(sig.?);
        const labels = try self.sink.arena.dupe(diagnostics.Label, &.{ primary, .{
            .file = self.ast.fileOf(name),
            .span = self.ast.tokenSpan(name),
            .message = try std.fmt.allocPrint(self.sink.arena, "this implementation adopts `{s}.{s}`'s `{s}`", .{ self.ast.tokenText(self.ast.declOwner(sig.?)), self.ast.tokenText(name), clause }),
            .style = .secondary,
        } });
        try self.sink.add(.{ .severity = .err, .code = .o_escapes, .message = message, .labels = labels });
    }

    /// An [O-Escapes] for a function whose contract may be its carrier
    /// parameter's default: the report names that parameter and, where the
    /// escaping value came from another parameter, the clause that says so.
    fn escapeUnderCarrierDefault(self: *Analysis, primary: diagnostics.Label, message: []const u8, origin: ?Origin) !void {
        const carrier_binding = if (self.function.default_carrier) |index| self.function.parameters[index] else return self.sink.addError(.o_escapes, primary.file, primary.span, message, primary.message);
        const arena = self.sink.arena;
        const carrier_name = self.ast.tokenText(self.res.declaringToken(carrier_binding));
        var notes: std.ArrayList([]const u8) = .empty;
        // The verb is the one the signature's computed contract carries.
        const verb: []const u8 = verb: {
            const signature = switch (self.typing.get(self.function.signature)) {
                .callable => |callable| callable,
                else => break :verb "carries",
            };
            for (signature.contracts) |contract| {
                switch (contract.source.root) {
                    .parameter => |index| if (index == self.function.default_carrier.?) break :verb @tagName(contract.kind),
                    else => {},
                }
            }
            break :verb "carries";
        };
        try notes.append(arena, try std.fmt.allocPrint(arena, "`{s}` is a carrier and this signature writes no clause, so its contract is `where {s}({s})`", .{ carrier_name, verb, carrier_name }));
        if (origin) |from| for (self.function.parameters) |parameter| {
            if (parameter != from.place.root) continue;
            const name = self.ast.tokenText(self.res.declaringToken(parameter));
            const kind = if (from.external) "carries" else "borrows";
            try notes.append(arena, try std.fmt.allocPrint(arena, "the value comes from `{s}`; write `where {s}({s})` to say so", .{ name, kind, name }));
            break;
        };
        try self.sink.add(.{
            .severity = .err,
            .code = .o_escapes,
            .message = message,
            .labels = try arena.dupe(diagnostics.Label, &.{primary}),
            .notes = try notes.toOwnedSlice(arena),
        });
    }

    fn childType(self: *const Analysis, ty: types.TypeId, head: u96) ?types.TypeId {
        const shape = self.typing.get(ty);
        if (head == observed) return if (shape == .borrow) shape.borrow.referent else null;
        if (isElement(head)) return if (shape == .array) shape.array.element else null;
        if (head >= (@as(u96, 1) << 65)) {
            const variant: u32 = @truncate(head >> 32);
            const index: u32 = @truncate(head);
            if (variant >= self.typing.variantCount(ty) or index >= self.typing.variantFieldCount(ty, variant)) return null;
            return self.typing.variantFieldType(ty, variant, index);
        }
        if (head > std.math.maxInt(u32)) return null;
        const index = self.typing.fieldIndexByName(ty, @enumFromInt(@as(u32, @intCast(head)))) orelse return null;
        return self.typing.fieldType(ty, index);
    }

    fn typeAtPath(self: *const Analysis, ty: types.TypeId, path: PathId) ?types.TypeId {
        var selected = ty;
        var remaining = path;
        while (remaining != .root) {
            const step = self.store.path(remaining);
            selected = self.childType(selected, step.head) orelse return null;
            remaining = step.tail;
        }
        return selected;
    }

    /// Contract upper bounds occupy only components capable of carrying an
    /// observation. Keep exact facts and opaque paths conservatively.
    fn ambientPossible(self: *Analysis, fact: Fact, ty: types.TypeId) !bool {
        const selected = self.typeAtPath(ty, fact.path) orelse return true;
        if (!self.canCarry(selected)) return false;
        if (fact.exclusions == .empty) return true;
        var paths: std.ArrayList(PathId) = .empty;
        defer paths.deinit(self.gpa);
        var at = fact.exclusions;
        while (at != .empty) {
            const exclusion = self.store.exclusions.items[@intFromEnum(at) - 1];
            try paths.append(self.gpa, exclusion.path);
            at = exclusion.next;
        }
        return !try self.coverage.covers(PathId, self.gpa, self.typing, selected, paths.items, CoveragePaths{ .analysis = self });
    }

    fn carriedBy(self: *Analysis, set: SetId, ty: types.TypeId) !SetId {
        if (set == .empty) return .empty;
        const key: CarriedSet = .{ .set = set, .ty = ty };
        if (self.carried_sets.get(key)) |answer| return answer;
        const facts = self.store.facts(set);
        var kept: std.ArrayList(Fact) = .empty;
        defer kept.deinit(self.gpa);
        var filtered = false;
        for (facts, 0..) |fact, index| {
            const possible = !fact.ambient or try self.ambientPossible(fact, ty);
            if (!possible) {
                if (!filtered) {
                    try kept.appendSlice(self.gpa, facts[0..index]);
                    filtered = true;
                }
            } else if (filtered) try kept.append(self.gpa, fact);
        }
        const answer = try self.heldAs(if (filtered) try self.store.intern(kept.items) else set, ty);
        try self.carried_sets.put(self.gpa, key, answer);
        return answer;
    }

    /// `set` as a value of `ty` holds it. Only a closure, a function value or
    /// a type parameter's value can write through a place lent `inout`, and a
    /// closure's result never observes a place it has lent, so a value whose
    /// type can hold none of them observes a lent place only for reading: its
    /// lends become read observations. Whatever still holds the writer keeps
    /// the lend, so the place stays unreadable until the writer's last use.
    fn heldAs(self: *Analysis, set: SetId, ty: types.TypeId) !SetId {
        if (!self.store.hasLend(set) or ty == .poison or self.typing.mayHoldWriter(ty)) return set;
        const read = try self.gpa.dupe(Fact, self.store.facts(set));
        defer self.gpa.free(read);
        for (read) |*fact| fact.origin.lent = .none;
        return self.store.intern(read);
    }

    const CoveragePaths = struct {
        analysis: *const Analysis,

        pub fn isRoot(_: CoveragePaths, path: PathId) bool {
            return path == .root;
        }

        pub fn head(self: CoveragePaths, path: PathId) u96 {
            return self.analysis.store.path(path).head;
        }

        pub fn tail(self: CoveragePaths, path: PathId) PathId {
            return self.analysis.store.path(path).tail;
        }

        pub fn arrayRange(_: CoveragePaths, step: u96, count: u32) ?types.ArrayCoverageRange {
            if (count == 0 or !isElement(step)) return null;
            return if (step == element) .{ .first = 0, .last = count - 1 } else .{ .first = rangeFirst(step), .last = rangeLast(step) };
        }

        pub fn childType(self: CoveragePaths, ty: types.TypeId, step: u96) ?types.TypeId {
            return self.analysis.childType(ty, step);
        }
    };

    fn coveredPath(self: *Analysis, ty: types.TypeId, upper: PathId, targets: []const PathId, ambient: bool) !bool {
        var suffixes: std.ArrayList(PathId) = .empty;
        defer suffixes.deinit(self.gpa);
        for (targets) |target| {
            if (self.store.strip(upper, target) != null) return true;
            if (ambient) if (self.store.strip(target, upper)) |suffix| try suffixes.append(self.gpa, suffix);
        }
        if (!ambient) return false;
        const selected = self.typeAtPath(ty, upper) orelse return false;
        return self.coverage.covers(PathId, self.gpa, self.typing, selected, suffixes.items, CoveragePaths{ .analysis = self });
    }

    fn coveredFact(self: *Analysis, ty: types.TypeId, fact: Fact, targets: *std.ArrayList(PathId)) !bool {
        // Replaced components impose no requirement on the result contract.
        if (fact.ambient) {
            var at = fact.exclusions;
            while (at != .empty) {
                const exclusion = self.store.exclusions.items[@intFromEnum(at) - 1];
                try targets.append(self.gpa, try self.store.concat(fact.path, exclusion.path));
                at = exclusion.next;
            }
        }
        return self.coveredPath(ty, fact.path, targets.items, fact.ambient);
    }

    /// A contract can permit only origins belonging to its source binding.
    /// Keep this index within the function, with one entry per source clause.
    fn contractsFrom(self: *Analysis, binding: BindingId, contracts: []const types.CallableContract) ![]const u32 {
        if (!self.contracts_indexed) {
            for (contracts, 0..) |contract, index| {
                const source = self.boundaryBinding(contract.source.root) orelse continue;
                const entry = try self.contract_sources.getOrPut(self.gpa, source);
                if (!entry.found_existing) entry.value_ptr.* = .empty;
                try entry.value_ptr.append(self.gpa, @intCast(index));
            }
            self.contracts_indexed = true;
        }
        return if (self.contract_sources.get(binding)) |run| run.items else &.{};
    }

    fn returned(self: *Analysis, state: *const State, op: OpId, report: bool) !void {
        if (!report) return;
        const at = self.cfg.opAt(op);
        const signature = switch (self.typing.get(self.function.signature)) {
            .callable => |s| s,
            else => return,
        };
        const projection = self.cfg.ops.items(.projection)[op.index()];
        const source = self.cfg.ops.items(.source)[op.index()];
        const returned_value = if (source != .none) self.ast.withoutGroups(source) else at;
        var result = try self.store.select(try self.value(state, source), try self.projectionPath(projection));
        // A `?` that converts its error returns the converted value, which
        // depends on the original only as far as its type can hold a
        // dependency at all.
        if (projection == .payload) if (self.typing.try_conversions.get(at)) |conversion| {
            if (!self.canCarry(conversion.target)) result = .empty;
        };
        if (projection == .payload) if (self.typing.failureVariantOf(signature.result)) |variant| {
            // A propagated error occupies the caller's failure payload, even
            // when the operand and returned enums have different payload types.
            result = try self.store.prefixed(result, try self.store.prepend(payloadHead(variant, 0), .root));
        };
        result = try self.carriedBy(result, signature.result);
        if (!self.function.contract_declined) for (self.store.facts(result)) |fact| {
            // A temporary ends with its statement, before the caller could
            // read what the function returns.
            if (fact.origin.temporary != .none) {
                try self.temporaryOutlived(fact.origin.temporary, returned_value, true);
                continue;
            }
            var targets: std.ArrayList(PathId) = .empty;
            defer targets.deinit(self.gpa);
            for (try self.contractsFrom(fact.origin.place.root, signature.contracts)) |index| {
                const contract = signature.contracts[index];
                if (contract.kind == .retains) continue;
                if (try self.sourceAllows(fact.origin, contract.source, contract.kind == .borrows)) {
                    try targets.append(self.gpa, try self.resultPath(contract.target));
                }
            }
            if (!try self.coveredFact(signature.result, fact, &targets))
                try self.escape(at, self.exprSite(self.returnedFrom(returned_value, fact.origin.place.root)), if (fact.origin.lent != .none)
                    .{ .lend = fact.origin.lent }
                else if (self.isLentCapture(fact.origin.place.root)) .from_lent_capture else .observation, fact.origin);
        };
        try self.stale(result, .{ .returned = returned_value }, report);
        for (self.function.inouts) |parameter| {
            const retained = try self.carriedBy(state.get(Cell.binding(parameter)) orelse .empty, self.typing.bindingType(parameter));
            for (self.store.facts(retained)) |fact| {
                if (fact.origin.temporary != .none) {
                    try self.temporaryOutlived(fact.origin.temporary, at, true);
                    continue;
                }
                // Existing dependencies may remain where the caller put them.
                // Moving them to a different field requires a retention clause.
                if (fact.origin.external and fact.origin.place.root == parameter and
                    try self.coveredPath(self.typing.bindingType(parameter), fact.origin.place.path, &.{fact.path}, true)) continue;
                var targets: std.ArrayList(PathId) = .empty;
                defer targets.deinit(self.gpa);
                for (try self.contractsFrom(fact.origin.place.root, signature.contracts)) |index| {
                    const contract = signature.contracts[index];
                    if (contract.kind != .retains) continue;
                    const destination = contract.destination orelse continue;
                    if ((self.boundaryBinding(destination.root) orelse continue) != parameter) continue;
                    if (try self.sourceAllows(fact.origin, contract.source, contract.borrows_source)) {
                        try targets.append(self.gpa, try self.contractPath(destination.fields));
                    }
                }
                if (!try self.coveredFact(self.typing.bindingType(parameter), fact, &targets)) {
                    // Reported where the dependency was written into the
                    // parameter, not where the body happens to end.
                    const site = if (self.arrivals.get(.{ .cell = Cell.binding(parameter), .owner = fact.origin.place.root })) |written|
                        self.exprSite(self.carriedFrom(written, fact.origin.place.root))
                    else
                        EscapeSite{ .file = self.ast.fileOf(self.res.declaringToken(parameter)), .span = self.ast.tokenSpan(self.res.declaringToken(parameter)) };
                    try self.escape(at, site, if (fact.origin.lent != .none)
                        .{ .lend = fact.origin.lent }
                    else if (self.isLentCapture(parameter)) .into_lent_capture else .observation, null);
                }
            }
            try self.stale(retained, .{ .retained = parameter }, report);
        }
    }

    const TransferMode = enum { probe, solve, report };

    fn transfer(self: *Analysis, state: *State, index: usize, comptime mode: TransferMode) !void {
        const block = self.cfg.blocks[self.function.blocks.start + index];
        const report = mode == .report;
        self.dependents.clear(self.gpa);
        var entries = state.iterator();
        while (entries.next()) |entry| try self.dependents.add(self.gpa, &self.store, entry.key_ptr.*, entry.value_ptr.*);
        const drops = if (self.liveness) |live| live.blocks[index] else Liveness.Range{ .start = 0, .end = 0 };
        var next_drop = drops.end;
        var ops = self.cfg.opsOf(block);
        while (ops.next()) |op| {
            if (mode == .probe and self.store.sets.items.len != 0) return;
            // Liveness records drops backwards. Consume that sequence forwards,
            // including skipped operations, without hashing every operation.
            const cells: []const Cell = if (next_drop > drops.start and self.liveness.?.drops.items[next_drop - 1].op == op) cells: {
                next_drop -= 1;
                const range = self.liveness.?.drops.items[next_drop].cells;
                break :cells self.liveness.?.cells.items[range.start..range.end];
            } else &.{};
            const schedule = self.cfg.opSchedule(op);
            if (schedule != .none and self.cancelled.contains(.{ .schedule = schedule, .exit = self.cfg.opExit(op) })) continue;
            const at = self.cfg.opAt(op);
            const place = self.cfg.opPlace(op);
            const source = self.cfg.ops.items(.source)[op.index()];
            switch (self.cfg.opTag(op)) {
                .value => try self.evaluate(state, op),
                .returned => try self.returned(state, op, report),
                .read, .copied => {
                    const read_at = self.readPlace(op);
                    try self.use(state, read_at, report);
                    // Reading a place lent `inout` ends the lend; a value
                    // still holding it is stale from here.
                    if (place.root != .none and self.dependents.lenders.by_owner.count() != 0) {
                        var read = Place{ .root = place.root, .path = (try self.selectedPath(read_at)).path };
                        if (try self.store.opaqueBoundary(read.path)) |cut| read.path = cut.prefix;
                        try self.invalidateObservations(state, read, at, .lends);
                    }
                },
                .consume => {
                    try self.use(state, at, report);
                    const selected = try self.selectedPath(at);
                    if (place.root != .none) try self.invalidate(state, .{ .root = place.root, .path = selected.path }, null, at);
                },
                .init, .lent => {
                    if (place.root == .none) continue;
                    if ((self.res.kindOf(place.root) == .parameter or self.res.kindOf(place.root) == .capture) and !self.cfg.ops.items(.replaces)[op.index()]) {
                        const ty = self.typing.bindingType(place.root);
                        const origin_path = if (self.isReadCapture(place.root)) try self.store.prepend(observed, .root) else PathId.root;
                        var facts: std.ArrayList(Fact) = .empty;
                        defer facts.deinit(self.gpa);
                        if (self.typing.mayCarryDependencies(ty)) {
                            const borrowed_type = self.typing.get(ty);
                            try facts.append(self.gpa, .{ .origin = .{ .place = .{ .root = place.root, .path = origin_path }, .external = true }, .ambient = borrowed_type != .borrow, .symbolic = true });
                            if (borrowed_type == .borrow and self.typing.mayCarryDependencies(borrowed_type.borrow.referent)) {
                                const path = try self.store.prepend(observed, .root);
                                try facts.append(self.gpa, .{ .path = path, .origin = .{ .place = .{ .root = place.root, .path = try self.store.concat(origin_path, path) }, .external = true }, .ambient = true, .symbolic = true });
                            }
                        }
                        try self.put(state, Cell.binding(place.root), try self.store.intern(facts.items));
                        if (self.isReadCapture(place.root)) {
                            const origins = try self.store.intern(&.{.{ .origin = .{ .place = .{ .root = place.root }, .external = true } }});
                            try self.put(state, Cell.alias(place.root), origins);
                        }
                        continue;
                    }
                    const assignment = self.cfg.ops.items(.replaces)[op.index()];
                    const path = if (assignment) (try self.selectedPath(at)).path else PathId.root;
                    var incoming = try self.value(state, if (source != .none) source else if (assignment) .none else at);
                    const projection = self.cfg.ops.items(.projection)[op.index()];
                    // Each pass of an owning `for` takes its element from the
                    // walked value, through `next` or from the array, so the
                    // walked value itself is what still needs an observation
                    // the body invalidated.
                    if (projection == .element or projection == .element_component) try self.stale(incoming, .{ .walked = source }, report);
                    const projected = try self.projectionPath(projection);
                    incoming = try self.store.select(incoming, projected);
                    if (self.cfg.opTag(op) == .lent) {
                        var aliases: std.ArrayList(Fact) = .empty;
                        defer aliases.deinit(self.gpa);
                        // The part a pattern selects refines its source only
                        // where the source's own path reached it exactly. A
                        // source cut at an element or an observation already
                        // names the whole storage it depends on, and appending
                        // the part to that cut would name a place no write
                        // to the element overlaps.
                        const source_path = (try self.selectedPath(source)).path;
                        const exact = (try self.store.boundary(source_path, true)).remaining == .root;
                        const alias_path = if (exact) (try self.store.boundary(projected, true)).prefix else PathId.root;
                        for (self.store.facts(try self.actualPlace(state, source))) |fact| {
                            var target = fact;
                            target.origin.place.path = try self.store.concat(target.origin.place.path, alias_path);
                            try aliases.append(self.gpa, target);
                        }
                        try self.put(state, Cell.alias(place.root), try self.store.intern(aliases.items));
                    }
                    if (assignment) try self.invalidate(state, .{ .root = place.root, .path = path }, null, at);
                    try self.write(state, place.root, path, incoming, at, report);
                },
                .dies => try self.invalidate(state, null, self.cfg.opRun(op), at),
                .temporaries_end => try self.invalidateTemporaries(state, at),
                .committed => switch (self.ast.exprTag(at)) {
                    .call => try self.applyCall(state, at, report),
                    .marked => try self.applyLentStep(state, at),
                    else => {},
                },
                .transferred, .discarded, .replaced, .escaped, .unsettled => {},
            }
            for (cells) |cell| try self.put(state, cell, .empty);
        }
    }

    /// The place an access reads. A copy is recorded at the `copy` expression,
    /// whose own value is defined only after the read, so what it reads is the
    /// place the operation records as its source; taking the expression
    /// instead would read the copy's result before it exists, and inside a
    /// loop that is the result of the pass before.
    fn readPlace(self: *const Analysis, op: OpId) ExprId {
        if (self.cfg.opTag(op) == .copied) return self.cfg.ops.items(.source)[op.index()];
        return self.cfg.opAt(op);
    }

    fn addUses(self: *Analysis, uses: *std.ArrayList(Cell), expr: ExprId) Allocator.Error!void {
        if (expr == .none) return;
        const at = self.ast.withoutGroups(expr);
        if (self.canCarry(self.typing.exprType(at))) try uses.append(self.gpa, Cell.expression(at));
        try self.addPlaceUses(uses, at);
    }

    // Place operations read their source before the expression's value is
    // produced. Demanding that future cache entry keeps unrelated reads live
    // across every preceding block instead of just retaining their source.
    fn addPlaceUses(self: *Analysis, uses: *std.ArrayList(Cell), expr: ExprId) !void {
        if (expr == .none) return;
        const at = self.ast.withoutGroups(expr);
        const selected = try self.selectedPath(at);
        if (selected.carried_source != .none) try self.addUses(uses, selected.carried_source);
        if (self.ast.refersToBinding(selected.root)) {
            const root = self.res.targetOf(selected.root);
            if (root != .none) {
                if (self.readsThroughAlias(root)) try uses.append(self.gpa, Cell.alias(root));
                if (self.canCarry(self.typing.bindingType(root))) try uses.append(self.gpa, Cell.binding(root));
            }
        }
        if (!self.ast.refersToBinding(selected.root)) {
            if (selected.root != at) {
                try self.addUses(uses, selected.root);
            } else if (self.canCarry(self.typing.exprType(selected.root))) {
                try uses.append(self.gpa, Cell.expression(selected.root));
            }
        }
        if (self.ast.exprTag(at) == .marked) try self.addUses(uses, self.ast.unaryOperand(at));
    }

    fn addCallUses(self: *Analysis, cells: *std.ArrayList(Cell), call: types.NormalizedCall) !void {
        if (call.target.calleeIsValue()) try self.addUses(cells, self.ast.call(call.at).callee);
        for (call.args) |arg| try self.addUses(cells, arg);
    }

    fn effect(self: *Analysis, op: OpId, cells: *std.ArrayList(Cell)) !Effect {
        const start = cells.items.len;
        var uses_start = start;
        const at = self.cfg.opAt(op);
        const place = self.cfg.opPlace(op);
        const source = self.cfg.ops.items(.source)[op.index()];
        switch (self.cfg.opTag(op)) {
            .value => {
                const capture_field = self.ast.exprTag(at) == .lambda and self.cfg.ops.items(.projection)[op.index()] != .whole;
                if (capture_field)
                    try cells.append(self.gpa, Cell.capture(source))
                else if (self.canCarry(self.typing.exprType(at)))
                    try cells.append(self.gpa, Cell.expression(at));
                uses_start = cells.items.len;
                if (self.ast.exprTag(at) == .lambda) {
                    if (capture_field) {
                        try self.addUses(cells, source);
                    } else {
                        const closure = self.res.closures.closureOf(at);
                        if (closure != .none) for (self.res.closureCaptures(closure)) |capture| try cells.append(self.gpa, Cell.capture(capture.source));
                    }
                } else if (source != .none) {
                    try self.addUses(cells, source);
                } else switch (self.ast.exprTag(at)) {
                    .copy_, .borrow, .grouped, .marked => try self.addUses(cells, self.ast.unaryOperand(at)),
                    .try_, .unwrap_else => try self.addUses(cells, unwrapped(self.ast, at)),
                    .name_ref, .param_argument, .field, .index, .dereference => {
                        const selected = try self.selectedPath(at);
                        if (self.ast.refersToBinding(selected.root)) {
                            const root = self.res.targetOf(selected.root);
                            if (self.canCarry(self.typing.bindingType(root))) try cells.append(self.gpa, Cell.binding(root));
                        } else try self.addUses(cells, selected.root);
                    },
                    .struct_literal => {
                        const args = self.ast.call(at).args;
                        var i: usize = 1;
                        while (i < args.len) : (i += 2) try self.addUses(cells, args[i]);
                        if (self.ast.structLiteralBase(at)) |base| try self.addUses(cells, base);
                    },
                    .array_literal, .tuple_literal => for (self.ast.call(at).args) |arg| try self.addUses(cells, arg),
                    .interp => {
                        for (self.ast.interpolation(at).pieces, 0..) |piece, i| {
                            if (i % 2 == 1) try self.addUses(cells, piece);
                        }
                    },
                    .call => if (self.typing.call_index.callOf(self.typing, at)) |normalized| {
                        try self.addCallUses(cells, normalized);
                    } else {
                        for (self.ast.call(at).args) |arg| try self.addUses(cells, arg);
                    },
                    else => {},
                }
            },
            .init, .lent => {
                if (place.root != .none) {
                    if (self.canCarry(self.typing.bindingType(place.root))) try cells.append(self.gpa, Cell.binding(place.root));
                    if (self.cfg.opTag(op) == .lent or self.isReadCapture(place.root)) try cells.append(self.gpa, Cell.alias(place.root));
                    uses_start = cells.items.len;
                    if ((self.res.kindOf(place.root) != .parameter and self.res.kindOf(place.root) != .capture) or self.cfg.ops.items(.replaces)[op.index()]) {
                        try self.addUses(cells, if (source != .none) source else at);
                        if (place.depth > 0 and self.canCarry(self.typing.bindingType(place.root))) try cells.append(self.gpa, Cell.binding(place.root));
                    }
                }
            },
            .read, .consume, .copied => try self.addPlaceUses(cells, self.readPlace(op)),
            .returned => {
                try self.addUses(cells, source);
                for (self.function.inouts) |parameter| {
                    if (self.canCarry(self.typing.bindingType(parameter))) try cells.append(self.gpa, Cell.binding(parameter));
                }
            },
            .committed => switch (self.ast.exprTag(at)) {
                .call => if (self.typing.call_index.callOf(self.typing, at)) |normalized| {
                    try self.addCallUses(cells, normalized);
                },
                .marked => try self.addUses(cells, self.ast.unaryOperand(at)),
                else => {},
            },
            .dies, .transferred, .discarded, .replaced, .escaped, .temporaries_end, .unsettled => {},
        }
        return .{ .start = start, .uses_start = uses_start, .end = cells.items.len };
    }

    fn liveUnion(self: *Analysis, into: *Live, from: *const Live) !bool {
        var changed = false;
        for (from.keys()) |cell| {
            const entry = try into.getOrPut(self.gpa, cell);
            changed = changed or !entry.found_existing;
        }
        return changed;
    }

    /// Sparse backwards demands discard temporaries at their last use. The
    /// worklist visits only predecessors whose input demand changed; tables
    /// contain this function's mentioned cells, never the program's ExprIds.
    fn computeLiveness(self: *Analysis) !Liveness {
        const start = self.function.blocks.start;
        const count = self.function.blocks.end - start;
        var result: Liveness = .{ .entries = try self.gpa.alloc(Live, count) };
        @memset(result.entries, .empty);
        errdefer result.deinit(self.gpa);
        result.blocks = try self.gpa.alloc(Liveness.Range, count);
        const predecessors = try self.gpa.alloc(std.ArrayList(u32), count);
        defer self.gpa.free(predecessors);
        @memset(predecessors, .empty);
        defer for (predecessors) |*preds| preds.deinit(self.gpa);
        // Block offsets pack only this function's operations, independently
        // of where their OpIds sit in the compilation's operation table.
        const effect_offsets = try self.gpa.alloc(usize, count);
        defer self.gpa.free(effect_offsets);
        var effect_count: usize = 0;
        for (effect_offsets, 0..) |*offset, index| {
            offset.* = effect_count;
            const block = self.cfg.blocks[start + index];
            effect_count += block.ops.end - block.ops.start;
        }
        const effects = try self.gpa.alloc(Effect, effect_count);
        defer self.gpa.free(effects);
        var effect_cells: std.ArrayList(Cell) = .empty;
        defer effect_cells.deinit(self.gpa);
        var initialized: usize = 0;
        for (0..count) |index| {
            const block = self.cfg.blocks[start + index];
            for (self.cfg.edgesOf(block)) |edge| {
                if (edge != .none) try predecessors[edge.index() - start].append(self.gpa, @intCast(index));
            }
            var ops = self.cfg.opsOf(block);
            while (ops.next()) |op| {
                effects[initialized] = try self.effect(op, &effect_cells);
                initialized += 1;
            }
        }
        const queued = try self.gpa.alloc(bool, count);
        defer self.gpa.free(queued);
        @memset(queued, true);
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(self.gpa);
        for (0..count) |index| try pending.append(self.gpa, @intCast(index));
        var live: Live = .empty;
        defer live.deinit(self.gpa);
        while (pending.pop()) |index| {
            queued[index] = false;
            live.clearRetainingCapacity();
            const block = self.cfg.blocks[start + index];
            for (self.cfg.edgesOf(block)) |edge| if (edge != .none) {
                _ = try self.liveUnion(&live, &result.entries[edge.index() - start]);
            };
            var op_index = block.ops.end;
            while (op_index > block.ops.start) {
                op_index -= 1;
                const item = effects[effect_offsets[index] + (op_index - block.ops.start)];
                for (item.defines(effect_cells.items)) |cell| _ = live.swapRemove(cell);
                for (item.uses(effect_cells.items)) |cell| try live.put(self.gpa, cell, {});
            }
            if (try self.liveUnion(&result.entries[index], &live)) {
                for (predecessors[index].items) |predecessor| if (!queued[predecessor]) {
                    queued[predecessor] = true;
                    try pending.append(self.gpa, predecessor);
                };
            }
        }
        for (0..count) |index| {
            live.clearRetainingCapacity();
            result.blocks[index].start = result.drops.items.len;
            const block = self.cfg.blocks[start + index];
            for (self.cfg.edgesOf(block)) |edge| if (edge != .none) {
                _ = try self.liveUnion(&live, &result.entries[edge.index() - start]);
            };
            var op_index = block.ops.end;
            while (op_index > block.ops.start) {
                op_index -= 1;
                const op = OpId.at(op_index);
                const item = effects[effect_offsets[index] + (op_index - block.ops.start)];
                const cells_start = result.cells.items.len;
                for (item.defines(effect_cells.items)) |cell| if (!live.contains(cell)) try result.cells.append(self.gpa, cell);
                for (item.uses(effect_cells.items)) |cell| if (!live.contains(cell)) try result.cells.append(self.gpa, cell);
                if (result.cells.items.len > cells_start) {
                    try result.drops.append(self.gpa, .{ .op = op, .cells = .{ .start = cells_start, .end = result.cells.items.len } });
                }
                for (item.defines(effect_cells.items)) |cell| _ = live.swapRemove(cell);
                for (item.uses(effect_cells.items)) |cell| try live.put(self.gpa, cell, {});
            }
            result.blocks[index].end = result.drops.items.len;
        }
        return result;
    }

    fn analyze(self: *Analysis) !void {
        var live = try self.computeLiveness();
        defer live.deinit(self.gpa);
        self.liveness = &live;
        const start = self.function.blocks.start;
        const count = self.function.blocks.end - start;
        const entries = try self.gpa.alloc(State, count);
        defer self.gpa.free(entries);
        @memset(entries, .empty);
        defer for (entries) |*entry| entry.deinit(self.gpa);
        const queued = try self.gpa.alloc(bool, count);
        defer self.gpa.free(queued);
        @memset(queued, false);
        const reached = try self.gpa.alloc(bool, count);
        defer self.gpa.free(reached);
        @memset(reached, false);
        const order = try self.cfg.reversePostorder(self.gpa, self.function);
        defer self.gpa.free(order);
        const ranks = try self.gpa.alloc(u32, count);
        defer self.gpa.free(ranks);
        for (order, 0..) |block, rank| ranks[block] = @intCast(rank);
        // Rank priority lets every acyclic predecessor contribute before a join.
        // Back edges may enqueue earlier ranks without replaying unrelated blocks.
        const Pending = std.PriorityQueue(u32, void, struct {
            fn compare(_: void, a: u32, b: u32) std.math.Order {
                return std.math.order(a, b);
            }
        }.compare);
        var pending: Pending = .empty;
        defer pending.deinit(self.gpa);
        const first: u32 = @intCast(self.function.entry.index() - start);
        try pending.push(self.gpa, ranks[first]);
        queued[first] = true;
        reached[first] = true;
        var state: State = .empty;
        defer state.deinit(self.gpa);
        while (pending.pop()) |rank| {
            const index = order[rank];
            queued[index] = false;
            state.clearRetainingCapacity();
            var input = entries[index].iterator();
            while (input.next()) |entry| try state.put(self.gpa, entry.key_ptr.*, entry.value_ptr.*);
            const block = self.cfg.blocks[start + index];
            try self.transfer(&state, index, .solve);
            for (self.cfg.edgesOf(block)) |edge| {
                if (edge == .none) continue;
                const successor: u32 = @intCast(edge.index() - start);
                var changed = !reached[successor];
                reached[successor] = true;
                var values = state.iterator();
                while (values.next()) |value_entry| {
                    if (!live.entries[successor].contains(value_entry.key_ptr.*)) continue;
                    const old = entries[successor].get(value_entry.key_ptr.*) orelse .empty;
                    const joined = try self.store.join(old, value_entry.value_ptr.*);
                    if (old == joined) continue;
                    try entries[successor].put(self.gpa, value_entry.key_ptr.*, joined);
                    changed = true;
                }
                if (changed and !queued[successor]) {
                    try pending.push(self.gpa, ranks[successor]);
                    queued[successor] = true;
                }
            }
        }
        for (0..count) |index| {
            if (!reached[index]) continue;
            state.clearRetainingCapacity();
            var input = entries[index].iterator();
            while (input.next()) |entry| try state.put(self.gpa, entry.key_ptr.*, entry.value_ptr.*);
            try self.transfer(&state, index, .report);
        }
    }
};

fn checkLocalDependencyOrigins(gpa: Allocator) !void {
    var store: Store = .{ .gpa = gpa };
    defer store.deinit();
    const local: BindingId = @enumFromInt(1);
    const external: BindingId = @enumFromInt(2);
    const invalid: ExprId = @enumFromInt(3);
    const original = try store.intern(&.{
        .{ .origin = .{ .place = .{ .root = local } } },
        .{ .origin = .{ .place = .{ .root = external }, .external = true } },
    });
    try std.testing.expect(try store.containsLocalOrigin(original, local));
    try std.testing.expect(!try store.containsLocalOrigin(original, external));
    try std.testing.expect(!try store.containsLocalOrigin(.empty, local));
    const single = try store.intern(&.{.{ .origin = .{ .place = .{ .root = local } } }});
    try std.testing.expect(try store.containsLocalOrigin(single, local));
    try std.testing.expect(!try store.containsLocalOrigin(single, external));
    const caller = try store.intern(&.{.{ .origin = .{ .place = .{ .root = external }, .external = true } }});
    try std.testing.expect(!try store.containsLocalOrigin(caller, external));
    const changed = try store.intern(&.{.{ .origin = .{ .place = .{ .root = local } }, .invalid = invalid }});
    try std.testing.expect(original != changed);
    try std.testing.expect(try store.containsLocalOrigin(changed, local));
    try std.testing.expectEqual(invalid, store.facts(changed)[0].invalid);
    try std.testing.expectEqual(ExprId.none, store.facts(original)[0].invalid);

    var dependents: Dependents = .{};
    defer dependents.deinit(gpa);
    const first = Cell.binding(local);
    const second = Cell.binding(external);
    try dependents.add(gpa, &store, first, caller);
    try dependents.add(gpa, &store, second, changed);
    try std.testing.expectEqual(@as(usize, 0), dependents.active.count());
    try std.testing.expectEqual(@as(usize, 0), dependents.owners.by_owner.count());
    dependents.remove(gpa, &store, first, caller);
    dependents.remove(gpa, &store, second, changed);
    try dependents.add(gpa, &store, first, original);
    try dependents.add(gpa, &store, second, original);
    try std.testing.expectEqual(@as(usize, 1), dependents.active.count());
    try std.testing.expectEqual(@as(usize, 1), dependents.owners.by_owner.count());
    try std.testing.expect(dependents.owners.by_owner.get(Owner.binding(local)).?.contains(original));
    dependents.remove(gpa, &store, first, original);
    try std.testing.expect(dependents.active.get(original).?.contains(second));
    dependents.remove(gpa, &store, second, original);
    try std.testing.expectEqual(@as(usize, 0), dependents.active.count());
    try std.testing.expectEqual(@as(usize, 0), dependents.owners.by_owner.count());
    for (4..36) |index| {
        try std.testing.expect(!try store.containsLocalOrigin(original, @enumFromInt(index)));
    }
    try std.testing.expect(try store.containsLocalOrigin(original, local));
}

test "carrier origin indexes preserve external and invalidated facts" {
    try checkLocalDependencyOrigins(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkLocalDependencyOrigins, .{});
}

test "dependency sets ignore insertion order and duplicate facts" {
    const gpa = std.testing.allocator;
    var store: Store = .{ .gpa = gpa };
    defer store.deinit();
    const base: Fact = .{ .origin = .{ .place = .{ .root = @enumFromInt(1) } } };
    var facts = [_]Fact{base} ** 8;
    facts[1].path = try store.prepend(1, .root);
    facts[2].origin.place.root = @enumFromInt(2);
    facts[3].origin.place.path = @enumFromInt(1);
    facts[4].origin.external = true;
    facts[5].invalid = @enumFromInt(1);
    facts[6].ambient = true;
    facts[7].symbolic = true;
    const expected = try store.intern(&facts);
    try std.testing.expectEqual(facts.len, store.facts(expected).len);
    var repeated: [facts.len * 2]Fact = undefined;
    for (0..facts.len) |index| {
        repeated[index * 2] = facts[facts.len - 1 - index];
        repeated[index * 2 + 1] = facts[facts.len - 1 - index];
    }
    try std.testing.expectEqual(expected, try store.intern(&repeated));
    try std.testing.expectEqual(try store.intern(&.{base}), try store.intern(&.{ base, base }));
    try std.testing.expectEqual(SetId.empty, try store.intern(&.{}));
}

test "a set of many fields over one owner has one owner, and the invalidated ones are its own list" {
    const gpa = std.testing.allocator;
    var store: Store = .{ .gpa = gpa };
    defer store.deinit();
    var facts: [few_facts * 4]Fact = undefined;
    for (&facts, 0..) |*fact, i| {
        fact.* = .{ .origin = .{ .place = .{ .root = @enumFromInt(1), .path = try store.prepend(i, .root) } } };
    }
    const one_owner = try store.intern(&facts);
    try std.testing.expectEqualSlices(BindingId, &.{@enumFromInt(1)}, try store.ownersOf(one_owner, false));
    facts[0].origin.place.root = @enumFromInt(2);
    facts[1].origin.place.root = @enumFromInt(3);
    facts[1].invalid = @enumFromInt(1);
    const mixed = try store.intern(&facts);
    try std.testing.expectEqualSlices(BindingId, &.{ @enumFromInt(1), @enumFromInt(2) }, try store.ownersOf(mixed, false));
    try std.testing.expectEqualSlices(BindingId, &.{ @enumFromInt(1), @enumFromInt(2), @enumFromInt(3) }, try store.ownersOf(mixed, true));
}

test "dependency joins retain only replacements shared by all predecessors" {
    const gpa = std.testing.allocator;
    var store: Store = .{ .gpa = gpa };
    defer store.deinit();
    const zero = try store.prepend(elementHead(0), .root);
    const one = try store.prepend(elementHead(1), .root);
    const killed_zero = try store.exclude(.empty, zero);
    const killed_one = try store.exclude(.empty, one);
    const both = try store.exclude(killed_zero, one);
    try std.testing.expectEqual(both, try store.exclude(killed_one, zero));
    const original: Fact = .{ .origin = .{ .place = .{ .root = @enumFromInt(1) } }, .ambient = true };
    var left = original;
    left.exclusions = killed_zero;
    var right = original;
    right.exclusions = both;
    const joined = try store.join(try store.intern(&.{left}), try store.intern(&.{right}));
    try std.testing.expectEqual(@as(usize, 1), store.facts(joined).len);
    try std.testing.expectEqual(killed_zero, store.facts(joined)[0].exclusions);
    try std.testing.expectEqual(SetId.empty, try store.select(joined, zero));
    try std.testing.expect(try store.select(joined, one) != .empty);
    try std.testing.expectEqual(try store.intern(&.{original}), try store.join(joined, try store.intern(&.{original})));
}
