const std = @import("std");
const tracy = @import("../support/tracy.zig");
const testing = std.testing;

const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const ExprId = node.ExprId;
const DeclId = node.DeclId;
const program_mod = @import("../syntax/program.zig");
const Program = program_mod.Program;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Label = @import("../diagnostics/diagnostic.zig").Label;
const Diagnostic = @import("../diagnostics/diagnostic.zig").Diagnostic;
const resolve_mod = @import("../sema/resolve.zig");
const BindingId = resolve_mod.BindingId;
const Resolution = resolve_mod.Resolution;
const Typing = @import("../sema/types.zig").Typing;
const TypeId = @import("../sema/types.zig").TypeId;
const TokenId = @import("../lexer/token.zig").TokenId;
const Loc = @import("../support/span.zig").Loc;
const Span = @import("../support/span.zig").Span;
const typecheck_mod = @import("../sema/typecheck.zig");
const isCatchAll = typecheck_mod.isCatchAll;
const Reach = typecheck_mod.Reach;
const reachIn = typecheck_mod.reachIn;
const NameReach = typecheck_mod.NameReach;
const Applicable = typecheck_mod.Applicable;
const writtenTypeName = typecheck_mod.writtenTypeName;
const ModuleId = program_mod.ModuleId;
const cfg_mod = @import("cfg.zig");
const Cfg = cfg_mod.Cfg;
const DisposalPlan = cfg_mod.DisposalPlan;
const BlockId = cfg_mod.BlockId;
const OpId = cfg_mod.OpId;
const Function = cfg_mod.Function;
const buildRemaining = @import("build.zig").buildRemaining;

/// What is known about a binding at a point in the graph.
const State = enum(u8) {
    uninit,
    /// Named by a refused construct that may or may not have taken it. A use
    /// is not reported, a scope ending does not leak it, and a path that
    /// disagrees with it is not a merge anyone can be asked to fix.
    unknown,
    init,
    moved,

    /// Discardable bindings merge pessimistically. An obligatory one has no safe answer --
    /// calling it moved makes one path leak and calling it init makes the
    /// other double-free -- so a disagreement is reported rather than merged.
    fn join(a: State, b: State) State {
        return if (@intFromEnum(a) >= @intFromEnum(b)) a else b;
    }
};

fn fixpointSweepBudget(blocks: usize) usize {
    const state_rises = @typeInfo(State).@"enum".fields.len - 1;
    return blocks * (1 + state_rises + 1) + 1;
}

/// A value given up whose receiver has not begun.
///
/// Keyed by the construct rather than counted, because closing one closes only
/// its own: `use2(d, join(e, return 7))` has two open at the `return`, and the
/// inner call completing must leave the outer one open.
const Pending = struct {
    place: cfg_mod.Place,
    /// The construct whose `committed` op closes this.
    for_: ExprId,
    /// Where the value was given up, for the label that says so.
    at: ExprId,

    /// Whether two entries are the same transfer.
    ///
    /// Where it was given up is not part of the answer: two paths into a join
    /// may have given the same value to the same construct in different words,
    /// and that is one transfer open, not two.
    fn same(a: Pending, b: Pending) bool {
        return a.for_ == b.for_ and
            a.place.root == b.place.root and
            a.place.depth == b.place.depth;
    }
};

/// Whether this operation begins a placement's run rather than continuing one.
///
/// The builder walks one deferred expression at a time, so a run is every
/// adjacent operation carrying the same pair.
fn startsARun(graph: *const Cfg, first: u32, at: OpId) bool {
    if (at.index() == first) return true;
    const before = OpId.at(@intCast(at.index() - 1));
    return graph.opSchedule(before) != graph.opSchedule(at) or graph.opExit(before) != graph.opExit(at);
}

/// Whether every place a placement takes is already gone on this path.
///
/// Asked of the state before the run applies, which is what makes the answer
/// about the path rather than about what the run itself does. A run that takes
/// one gone place and one live one is neither spent nor safe to skip: running
/// it takes the first twice and skipping it loses the second, so it is not
/// cancelled and [O-Move] refuses the program.
fn spentAt(c: *const Checker, at: OpId, end: u32, state: []const State) bool {
    const schedule = c.cfg.opSchedule(at);
    const exit = c.cfg.opExit(at);
    var i: u32 = @intCast(at.index());
    while (i < end) : (i += 1) {
        const op = OpId.at(i);
        if (c.cfg.opSchedule(op) != schedule or c.cfg.opExit(op) != exit) break;
        if (c.cfg.opTag(op) != .consume) continue;
        const place = c.cfg.opPlace(op);
        if (!place.isWhole()) return false;
        const slot = c.slotOf(place.root) orelse return false;
        if (state[slot] != .moved) return false;
    }
    return true;
}

fn holds(open: []const Pending, p: Pending) bool {
    for (open) |o| {
        if (o.same(p)) return true;
    }
    return false;
}

/// Proves that every linear value is consumed exactly once, and that no value
/// is used after it was taken.
///
/// Use-after-free and double-free are one check: the root is `moved` and
/// something reads it. That the two most feared bugs in systems programming
/// collapse into one rule is the argument for the design, and the diagnostics
/// do not obscure it by inventing a second code.
/// Checks a tree that is its own module. For a caller holding a tree and no
/// directory structure -- a mutation, the generator, the fuzzer.
pub fn checkTree(
    gpa: std.mem.Allocator,
    resolved: *const resolve_mod.ResolvedTree,
    typing: *const Typing,
    sink: *Sink,
) std.mem.Allocator.Error!DisposalPlan {
    var plan = try check(gpa, gpa, &resolved.expanded, &resolved.resolution, typing, sink);
    errdefer plan.deinit(gpa);
    try resolved.expanded.collapseGeneratedDiagnostics(sink);
    return plan;
}

/// Flow results used to diagnose schedules and freeze the disposal plan.
const Cancellations = struct {
    at: std.AutoHashMapUnmanaged(cfg_mod.Placement, void) = .empty,
    placed: std.AutoHashMapUnmanaged(cfg_mod.Placement, void) = .empty,

    const empty: Cancellations = .{};

    fn deinit(self: *Cancellations, gpa: std.mem.Allocator) void {
        self.at.deinit(gpa);
        self.placed.deinit(gpa);
        self.* = undefined;
    }
};

/// Temporary graphs and flow buffers use `scratch`; only the returned plan
/// uses `retained`. Diagnostic payloads belong to the supplied sink.
pub fn check(
    retained: std.mem.Allocator,
    scratch: std.mem.Allocator,
    program: *const ExpandedProgram,
    res: *const Resolution,
    typing: *const Typing,
    sink: *Sink,
) std.mem.Allocator.Error!DisposalPlan {
    return checkBodies(retained, scratch, program, res, typing, sink, null);
}

/// Continues a successful immutable ownership snapshot after its semantic
/// tables have been attached without changing any retained body's answers.
/// Only the exact declarations named by `checked` are omitted from analysis;
/// the resulting disposal plan owns both imported and newly checked schedules.
pub fn checkWithRetained(
    retained: std.mem.Allocator,
    scratch: std.mem.Allocator,
    program: *const ExpandedProgram,
    res: *const Resolution,
    typing: *const Typing,
    sink: *Sink,
    checked: cfg_mod.CheckedOwnership,
) (std.mem.Allocator.Error || error{InvalidDisposalImport})!DisposalPlan {
    var fresh = try checkBodies(retained, scratch, program, res, typing, sink, checked.declarations);
    defer fresh.deinit(retained);
    return DisposalPlan.imported(retained, checked.disposals, checked.expressions, &fresh);
}

fn checkBodies(
    retained: std.mem.Allocator,
    scratch: std.mem.Allocator,
    program: *const ExpandedProgram,
    res: *const Resolution,
    typing: *const Typing,
    sink: *Sink,
    checked: ?*const std.AutoHashMapUnmanaged(node.DeclId, void),
) std.mem.Allocator.Error!DisposalPlan {
    const gpa = scratch;
    const z_cfg = tracy.beginZone(@src(), "ow.graph");
    var cfg = try buildRemaining(gpa, program, res, typing, checked);
    z_cfg.end();
    defer cfg.deinit(gpa);

    const z_check = tracy.beginZone(@src(), "ow.check");
    defer z_check.end();

    // One entry per binding in the program, held across the whole pass and
    // left empty between functions. A function fills only the entries it
    // mentions and clears those again, so no function pays for the bindings
    // the rest of the program declared.
    const slot_of = try gpa.alloc(u32, res.bindingCount());
    defer gpa.free(slot_of);
    @memset(slot_of, Checker.no_slot);

    // One entry per scope in the program, filled once below.
    const tracked = try gpa.alloc(cfg_mod.ScopeId, cfg.scopes.len);
    defer gpa.free(tracked);

    var c: Checker = .{
        .gpa = gpa,
        .program = program,
        .ast = &program.ast,
        .res = res,
        .typing = typing,
        .sink = sink,
        .cfg = &cfg,
        .slot_of = slot_of,
        .tracked = tracked,
    };
    defer c.seen.deinit(gpa);
    defer c.reached.deinit(gpa);
    defer c.merge_origins.deinit(gpa);
    defer c.scheduled.deinit(gpa);
    defer c.emitted.deinit(gpa);
    defer c.leaks.deinit(gpa);

    defer c.cancelled.deinit(gpa);
    for (cfg.uncaptured) |u| try c.reportUncaptured(u);
    for (cfg.functions) |*f| try c.function(f);
    try c.reportDeadSchedules();
    try @import("dependencies.zig").check(gpa, program, res, typing, &cfg, &c.cancelled.at, sink);
    return DisposalPlan.init(retained, cfg.placements, &c.cancelled.at, cfg.ops, &cfg.static_reads);
}

const Checker = struct {
    gpa: std.mem.Allocator,
    program: *const ExpandedProgram,
    ast: *const Ast,
    res: *const Resolution,
    typing: *const Typing,
    sink: *Sink,
    cfg: *const Cfg,
    /// Which slot of the current function's state vector each binding holds.
    /// `no_slot` for one the function never names, which is nearly all of them.
    slot_of: []u32,
    /// Which blocks a walk over the successors has already reached.
    ///
    /// One entry per block of the function and held across the pass rather
    /// than taken per walk. Asking whether a place is read again is asked once
    /// per `copy`, and a walk settles after a block or two -- so a buffer
    /// sized by the function and cleared for each of them cost the function's
    /// blocks per copy in it, to support two visits. What a walk reached it
    /// puts back, so the next one finds it as it was.
    seen: std.ArrayList(bool) = .empty,
    reached: std.ArrayList(u32) = .empty,
    /// For each scope, the innermost scope at or beneath it whose binding is
    /// tracked at some block (`isTracked` with no block), and `.none` where no
    /// scope beneath it has one.
    ///
    /// What a scope end does to any other binding cannot be observed, so this
    /// is the whole of what a scope exit has to visit. It is a chain rather
    /// than a scan because a scope exit ends every scope down to a mark, and
    /// an exit written inside n live bindings would otherwise read all n to
    /// find the none of them that could leak or disagree at a join.
    tracked: []cfg_mod.ScopeId,
    /// Binding-state changes whose pessimistic state reached a diagnosed merge.
    /// Safety still reads that state; diagnostics use this provenance to avoid
    /// restating the same disagreement as a later failure about that binding.
    merge_origins: std.AutoHashMapUnmanaged(MergeOrigin, void) = .empty,
    /// The bindings a `defer` of the function being walked consumes, each
    /// numbered by the bit it holds in a row of `awaiting`. Sized by the
    /// function's own operations.
    scheduled: std.AutoHashMapUnmanaged(BindingId, u32) = .empty,
    /// For each block of the function being walked, a row of bits over
    /// `scheduled`: bit `i` is set when a schedule consuming binding `i` can
    /// still run from the block's start before that binding's scope ends.
    /// Rows are `awaiting_words` long. Sized by the function's blocks times
    /// the bindings its `defer`s consume, and freed when the function is done.
    awaiting: []u64 = &.{},
    awaiting_words: usize = 0,
    /// The diagnostics already given, keyed by code, primary span and message.
    /// A `defer` body is walked once per exit that places it, so one mistake
    /// in it is met once per exit and is said once. Sized by the diagnostics
    /// this pass reports.
    emitted: std.StringHashMapUnmanaged(void) = .empty,
    /// Whether every place the placement being walked takes is already gone.
    /// Settled once at the run's start; see `runBlock`.
    run_is_spent: bool = false,
    /// Placements the walk found already discharged, removed before the
    /// disposal plan crosses the pass boundary.
    cancelled: Cancellations = .empty,
    /// The declaration whose generic promises are active for this graph.
    current_owner: DeclId = .none,
    /// Where this function's reporting walk found a Linear binding still held
    /// as its scope ended, gathered so that each binding is reported once,
    /// however many paths leave it held. Sized by the function's leaking
    /// exits, and emptied when the function has been reported.
    leaks: std.ArrayList(Leak) = .empty,

    /// A Linear binding still held where control leaves its scope at `exit`.
    const Leak = struct { binding: BindingId, exit: ExprId };

    /// A binding the function being checked does not name.
    const no_slot = std.math.maxInt(u32);
    /// Spoken for while the roots are being gathered, before they are ordered.
    const claimed = no_slot - 1;

    const MergeOrigin = struct {
        at: ExprId,
        binding: BindingId,
    };

    /// Where a binding sits in this function's state vector.
    fn slotOf(self: *const Checker, b: BindingId) ?usize {
        if (b.index() >= self.slot_of.len) return null;
        const slot = self.slot_of[b.index()];
        return if (slot == no_slot) null else slot;
    }

    /// The bindings this function's state vector holds, in binding order.
    ///
    /// A state vector used to hold one entry per binding in the *program*, so a
    /// program of many small functions paid, per function, for every binding
    /// every other function declared -- in memory as much as in time, since the
    /// vector is allocated per block.
    ///
    /// Ordered, so that a slot's position is the binding's: `checkMerges` walks
    /// the vector to report a disagreement, and which binding it names first
    /// may not depend on which operation happened to mention one first.
    fn rootsOf(self: *Checker, f: *const Function) std.mem.Allocator.Error![]BindingId {
        var roots: std.ArrayList(BindingId) = .empty;
        errdefer {
            for (roots.items) |b| self.slot_of[b.index()] = no_slot;
            roots.deinit(self.gpa);
        }

        // An `inout` is asked about at every exit whether or not the body
        // mentions it, so it holds a slot either way.
        for (f.inouts) |b| try self.claim(&roots, b);
        for (f.blocks.start..f.blocks.end) |j| {
            var ops = self.cfg.opsOf(self.cfg.blocks[j]);
            while (ops.next()) |op| {
                const root = self.cfg.opPlace(op).root;
                try self.claim(&roots, root);
                if (self.cfg.opTag(op) == .consume and self.cfg.opSchedule(op) != ExprId.none) {
                    const entry = try self.scheduled.getOrPut(self.gpa, root);
                    if (!entry.found_existing) entry.value_ptr.* = @intCast(self.scheduled.count() - 1);
                }
            }
        }

        std.mem.sortUnstable(BindingId, roots.items, {}, byBinding);
        for (roots.items, 0..) |b, slot| self.slot_of[b.index()] = @intCast(slot);
        return roots.toOwnedSlice(self.gpa);
    }

    fn claim(
        self: *Checker,
        roots: *std.ArrayList(BindingId),
        b: BindingId,
    ) std.mem.Allocator.Error!void {
        if (b.index() >= self.slot_of.len) return;
        if (self.slot_of[b.index()] != no_slot) return;
        // Listed before it is marked, so a failure to list it leaves nothing
        // spoken for: the errdefer hands back what `roots` holds, and a
        // binding marked but not held would be in neither.
        try roots.append(self.gpa, b);
        self.slot_of[b.index()] = claimed;
    }

    fn byBinding(_: void, a: BindingId, b: BindingId) bool {
        return a.index() < b.index();
    }

    /// Hands the slots back, so the next function starts from an empty table.
    fn releaseRoots(self: *Checker, roots: []const BindingId) void {
        for (roots) |b| self.slot_of[b.index()] = no_slot;
    }

    /// Which blocks reach each block, as one run per block.
    ///
    /// The graph records where a block goes and not where it came from, so a
    /// merge found its predecessors by asking every block in the function
    /// whether it went here -- a walk of the whole function per block, paid
    /// whether or not any merge existed. Counted and placed instead, the way
    /// `flattenEdges` already builds the forward direction.
    const Predecessors = struct {
        /// Where each block's run begins, and one past the last so that a run
        /// is a pair of neighbours.
        starts: []u32,
        blocks: []u32,

        fn of(self: *const Predecessors, i: usize) []const u32 {
            return self.blocks[self.starts[i]..self.starts[i + 1]];
        }

        fn deinit(self: *Predecessors, gpa: std.mem.Allocator) void {
            gpa.free(self.starts);
            gpa.free(self.blocks);
        }
    };

    /// Builds `Predecessors` for one function.
    ///
    /// The placing pass walks the blocks in order, so each run keeps that
    /// order: a merge compares every predecessor against the first it sees,
    /// and which one that is decides what the report says.
    fn predecessorsOf(
        self: *Checker,
        f: *const Function,
        count: usize,
    ) std.mem.Allocator.Error!Predecessors {
        const starts = try self.gpa.alloc(u32, count + 1);
        errdefer self.gpa.free(starts);
        @memset(starts, 0);

        // An edge leaving the function reaches no block a merge here could
        // name, exactly as it matched nothing when every block was asked.
        var total: u32 = 0;
        for (f.blocks.start..f.blocks.end) |j| {
            for (self.cfg.edgesOf(self.cfg.blocks[j])) |e| {
                const to = e.index() -% f.blocks.start;
                if (to >= count) continue;
                starts[to + 1] += 1;
                total += 1;
            }
        }
        for (1..count + 1) |i| starts[i] += starts[i - 1];

        const blocks = try self.gpa.alloc(u32, total);
        errdefer self.gpa.free(blocks);

        const cursor = try self.gpa.alloc(u32, count);
        defer self.gpa.free(cursor);
        @memcpy(cursor, starts[0..count]);

        for (f.blocks.start..f.blocks.end) |j| {
            const from: u32 = @intCast(j - f.blocks.start);
            for (self.cfg.edgesOf(self.cfg.blocks[j])) |e| {
                const to = e.index() -% f.blocks.start;
                if (to >= count) continue;
                blocks[cursor[to]] = from;
                cursor[to] += 1;
            }
        }

        return .{ .starts = starts, .blocks = blocks };
    }

    /// Whether a value of this type still owes something.
    ///
    /// The one question [O-Leak] asks. The scope end, the unnamed payload and
    /// the written place are three positions where it happens, not three
    /// failures, so all three read this and differ only in which type they
    /// hand it -- a binding's, a written place's, or a discarded value's.
    fn owes(self: *const Checker, t: TypeId) bool {
        return self.typing.mustConsumeWithin(self.current_owner, t);
    }

    fn isLinear(self: *const Checker, b: BindingId) bool {
        return self.owes(self.typing.bindingType(b));
    }

    /// Whether paths that meet at the start of block `join` must agree about
    /// this binding's state, or, with `join` null, whether they must at some
    /// block of the function.
    ///
    /// A Linear binding must everywhere, because it has to be consumed exactly
    /// once. A binding a `defer` consumes must where one of its schedules can
    /// still run, because a schedule runs or is cancelled by the state it
    /// finds, and a pessimistic merge would cancel it on the path that still
    /// holds the value. Past the last schedule that can run, a `defer` has
    /// consumed the value where it ran, exactly as a call written there
    /// would, and the binding merges like any other: pessimistically, with a
    /// use after the join reporting the move it reads.
    ///
    /// `checkMerges` compares exactly the bindings tracked at its join. A
    /// scope end resets every binding tracked anywhere, so a binding whose
    /// scope ended on one path and that was never declared on the other is
    /// `.uninit` on both.
    ///
    /// Reads `scheduled`, so it answers only once `rootsOf` has filled it,
    /// and with a block only once `findAwaiting` has filled `awaiting`.
    fn isTracked(self: *const Checker, b: BindingId, join: ?u32) bool {
        if (self.isLinear(b)) return true;
        const i = self.scheduled.get(b) orelse return false;
        const block = join orelse return true;
        const word = self.awaiting[block * self.awaiting_words + i / 64];
        return (word >> @intCast(i % 64)) & 1 != 0;
    }

    /// Fills `awaiting`: which schedules each block can still reach.
    ///
    /// A backward walk to a fixpoint. A block's row is what its successors'
    /// rows hold, with its operations applied last to first: a scheduled
    /// consume of a binding sets its bit, and a scope end clears the bits of
    /// the bindings it ends, so a back edge into the next iteration does not
    /// carry the schedule of a binding the body declares into the previous
    /// iteration. Rows only grow, so the sweeps settle. A sweep visits each
    /// operation once and each scope end's tracked bindings once, as
    /// `endScopes` does.
    fn findAwaiting(self: *Checker, f: *const Function, order: []const u32) std.mem.Allocator.Error!void {
        const count = f.blocks.end - f.blocks.start;
        const words = (self.scheduled.count() + 63) / 64;
        self.awaiting_words = words;
        self.awaiting = try self.gpa.alloc(u64, count * words);
        @memset(self.awaiting, 0);
        if (words == 0) return;

        const row = try self.gpa.alloc(u64, words);
        defer self.gpa.free(row);

        var changed = true;
        while (changed) {
            changed = false;
            var k = order.len;
            while (k > 0) {
                k -= 1;
                const b = order[k];
                const block = self.cfg.blocks[f.blocks.start + b];
                @memset(row, 0);
                for (self.cfg.edgesOf(block)) |e| {
                    const to = e.index() -% f.blocks.start;
                    if (to >= count) continue;
                    for (row, self.awaiting[to * words ..][0..words]) |*w, from| w.* |= from;
                }

                var at = block.ops.end;
                while (at > block.ops.start) {
                    at -= 1;
                    const op = OpId.at(at);
                    switch (self.cfg.opTag(op)) {
                        .dies => {
                            var each = self.dying(op);
                            while (each.next()) |d| {
                                const i = self.scheduled.get(d) orelse continue;
                                row[i / 64] &= ~(@as(u64, 1) << @intCast(i % 64));
                            }
                        },
                        .consume => if (self.cfg.opSchedule(op) != ExprId.none) {
                            const i = self.scheduled.get(self.cfg.opPlace(op).root).?;
                            row[i / 64] |= @as(u64, 1) << @intCast(i % 64);
                        },
                        else => {},
                    }
                }

                const mine = self.awaiting[b * words ..][0..words];
                if (!std.mem.eql(u64, mine, row)) {
                    @memcpy(mine, row);
                    changed = true;
                }
            }
        }
    }

    /// Threads the chain of scopes whose bindings are tracked at some block.
    ///
    /// One forward pass over the whole tree, because a scope is minted after
    /// the one it sits inside: by the time this reaches a scope, the answer
    /// for everything beneath it is already written.
    fn findTracked(self: *Checker, f: *const Function) void {
        for (self.cfg.scopes[f.scopes.start..f.scopes.end], f.scopes.start..) |s, i| {
            self.tracked[i] = if (self.isTracked(s.binding, null))
                cfg_mod.ScopeId.at(i)
            else if (s.outer == cfg_mod.ScopeId.none)
                cfg_mod.ScopeId.none
            else
                self.tracked[s.outer.index()];
        }
    }

    /// The tracked bindings a scope exit ends, innermost first -- the order a
    /// reader expects to be told.
    ///
    /// Every scope in the stretch that could leak or disagree at a join and
    /// no other, which is normally none of them: a body of `UInt8` locals has
    /// nothing here to visit however many of them the exit ends.
    const Dying = struct {
        c: *const Checker,
        at: cfg_mod.ScopeId,
        /// How many bindings the exit leaves live.
        mark: u32,

        fn next(self: *Dying) ?BindingId {
            if (self.at == cfg_mod.ScopeId.none) return null;
            const s = self.c.cfg.scopes[self.at.index()];
            if (s.depth <= self.mark) return null;
            self.at = if (s.outer == cfg_mod.ScopeId.none)
                cfg_mod.ScopeId.none
            else
                self.c.tracked[s.outer.index()];
            return s.binding;
        }
    };

    fn dying(self: *const Checker, op: OpId) Dying {
        const run = self.cfg.opRun(op);
        return .{
            .c = self,
            .at = if (run.top == cfg_mod.ScopeId.none)
                cfg_mod.ScopeId.none
            else
                self.tracked[run.top.index()],
            .mark = run.mark,
        };
    }

    /// Whether taking a value of this type apart discharges what it owes.
    ///
    /// It does when nothing it carries owes anything: every part either goes
    /// somewhere or owes nothing, so there is nothing left over to name and
    /// `_` abbreviates what it holds rather than discarding it.
    ///
    /// One level is enough: owned parts propagate mandatory consumption, so
    /// an obligation at any depth is also an obligation on its immediate owner.
    ///
    /// A parameter has no parts to look at, which is not the same as its
    /// having none, so nothing it holds is known to be discharged. One check
    /// of a body stands for every instantiation, which is why the pessimistic
    /// answer is the sound one.
    fn takingItApartDischarges(self: *const Checker, t: TypeId) bool {
        if (self.typing.get(t) == .parameter) return false;

        var i: u32 = 0;
        while (i < self.typing.fieldCount(t)) : (i += 1) {
            if (self.owes(self.typing.fieldType(t, i))) return false;
        }
        var v: u32 = 0;
        while (v < self.typing.variantCount(t)) : (v += 1) {
            var f: u32 = 0;
            while (f < self.typing.variantFieldCount(t, v)) : (f += 1) {
                if (self.owes(self.typing.variantFieldType(t, v, f))) return false;
            }
        }
        return true;
    }

    /// Whether a `_` arm over this value leaves an obligation unaccounted for.
    ///
    /// The discarded-value position of [O-Leak]: what it owes, less what
    /// taking it apart discharges.
    fn discardLeavesAnObligation(self: *const Checker, t: TypeId) bool {
        return self.owes(t) and !self.takingItApartDischarges(t);
    }

    /// Whether the place an `init` writes is itself Linear.
    ///
    /// A whole binding is asked of its binding's type, a part of the type of
    /// the selection that named it. State is kept per binding rather than per
    /// field, so for a part that type is the only thing that says a Linear
    /// value sat there. A discardable part does not inherit the obligations of
    /// its containing value.
    ///
    /// The root's type would answer the wrong question for a part, and a
    /// whole binding has no selection to read, so neither source alone spans
    /// both depths.
    fn writesALinearPlace(self: *const Checker, op: OpId) bool {
        const place = self.cfg.opPlace(op);
        if (place.isWhole()) return self.isLinear(place.root);
        return self.owes(self.typing.exprType(self.cfg.opAt(op)));
    }

    /// Reports a `defer` whose disposal is skipped everywhere it was placed.
    ///
    /// Said once per schedule rather than once per exit: what is wrong is the
    /// `defer`, not any one path out of the scope.
    ///
    /// In the order the schedules are written, which the placements are not in:
    /// a schedule is placed at each exit, and the exits are reached in whatever
    /// order the graph runs them. Sorted rather than accumulated in order,
    /// because a `defer` reaching two exits is seen twice and neither sighting
    /// is the one a reader would name.
    fn reportDeadSchedules(self: *Checker) std.mem.Allocator.Error!void {
        var dead: std.AutoHashMapUnmanaged(ExprId, bool) = .empty;
        defer dead.deinit(self.gpa);

        var it = self.cancelled.placed.keyIterator();
        while (it.next()) |p| {
            const gone = self.cancelled.at.contains(p.*);
            const seen = try dead.getOrPut(self.gpa, p.schedule);
            seen.value_ptr.* = if (seen.found_existing) seen.value_ptr.* and gone else gone;
        }

        var written: std.ArrayList(ExprId) = .empty;
        defer written.deinit(self.gpa);

        var each = dead.iterator();
        while (each.next()) |entry| {
            if (!entry.value_ptr.*) continue;
            try written.append(self.gpa, entry.key_ptr.*);
        }

        std.mem.sort(ExprId, written.items, self, isWrittenBefore);

        for (written.items) |at| {
            if (self.ast.callIsScheduledRelease(at)) {
                // The schedule is the binding's own, so the fix is the
                // binding, not a `defer` the program wrote.
                try self.report(
                    .o_defer_dead,
                    at,
                    "write `let` where the value is meant to move",
                    "`{s}` is moved on every path out, so the release `defer let` schedules never runs",
                    .{self.ast.tokenText(self.ast.exprMain(self.ast.call(at).args[0]))},
                );
                continue;
            }
            try self.report(
                .o_defer_dead,
                at,
                "delete the `defer`, or move what takes the value after it",
                "what this schedules never runs: the value is gone on every path out",
                .{},
            );
        }
    }

    /// Of two places a value may have been taken, the one written first.
    ///
    /// A total order over a pair either of which may be absent, so the merge
    /// has an answer that does not depend on which edge arrived first.
    fn writtenFirst(self: *const Checker, a: ExprId, b: ExprId) ExprId {
        if (a == ExprId.none) return b;
        if (b == ExprId.none) return a;
        return if (self.isWrittenBefore(a, b)) a else b;
    }

    /// Whether one expression is written before another across a whole program.
    ///
    /// By file first, because a span is an offset into the file that holds it
    /// and two files' offsets are not comparable.
    fn isWrittenBefore(self: *const Checker, a: ExprId, b: ExprId) bool {
        const fa = self.ast.fileOfExpr(a);
        const fb = self.ast.fileOfExpr(b);
        if (fa != fb) return @intFromEnum(fa) < @intFromEnum(fb);
        return self.ast.exprSpan(a).start < self.ast.exprSpan(b).start;
    }

    /// Names a binding as a message spells it: as written, or, for one a derive
    /// generated for a component, as the source field it holds.
    fn nameOf(self: *const Checker, b: BindingId) std.mem.Allocator.Error![]const u8 {
        const tok = self.res.declaringToken(b);
        const generated = try self.program.generatedComponentName(self.sink.arena, self.ast.fileOf(tok), self.ast.tokenSpan(tok));
        return generated orelse self.ast.tokenText(tok);
    }

    /// How a message spells the construct a value was given to.
    ///
    /// A call and a variant construction are written with a callee, which is
    /// what a reader would point at. A structure literal is written with none,
    /// so it is named by the type it builds, recorded even where a component
    /// left before the literal was built. An array literal and an interpolation
    /// are named by what they are.
    fn constructName(self: *const Checker, id: ExprId) []const u8 {
        return switch (self.ast.exprTag(id)) {
            .struct_literal, .tuple_literal => self.typing.nameOf(self.typing.constructionType(id)),
            .array_literal => "array literal",
            .interp => "interpolation",
            .lambda => "closure",
            else => self.ast.exprText(self.ast.call(id).callee),
        };
    }

    /// Reports control leaving before a construct received what it was given.
    ///
    /// Two labels because the fix is the order: what is wrong is not either
    /// place on its own but that one comes before the other, so a reader has
    /// to see both.
    /// Where an expression begins, which orders two mentions of one transfer.
    fn startOf(self: *const Checker, at: ExprId) u32 {
        return self.ast.exprSpan(at).start;
    }

    /// Opens `p` in `into`, or keeps whichever mention of the same transfer
    /// comes first in the source. Whether anything changed.
    ///
    /// A transfer is one thing however many paths reach it, and `Pending.same`
    /// says so by leaving `at` out of the answer. Which `at` survives would
    /// otherwise be whichever path a sweep walked first -- a fact about the
    /// order blocks were visited in, surfacing in the label that says where the
    /// value was given up. The earliest wins, so the fixpoint settles on the
    /// same answer whatever order it reaches it in.
    fn openTransfer(
        self: *Checker,
        into: *std.ArrayList(Pending),
        p: Pending,
    ) std.mem.Allocator.Error!bool {
        for (into.items) |*o| {
            if (!o.same(p)) continue;
            if (self.startOf(p.at) >= self.startOf(o.at)) return false;
            o.at = p.at;
            return true;
        }
        try into.append(self.gpa, p);
        return true;
    }

    /// Reports a place taken again, saying where it was taken before.
    ///
    /// Two labels where the earlier take is known, one where it is not: a
    /// binding may arrive at a block already moved on some path with no
    /// operation on this one to point at, and a label pointing nowhere is
    /// worse than the sentence it would decorate.
    fn reportMoved(
        self: *Checker,
        at: ExprId,
        root: BindingId,
        before: ExprId,
    ) std.mem.Allocator.Error!void {
        // Not where the earlier take is this very expression, which a loop
        // makes ordinary: the back edge carries the state round and the take a
        // second iteration finds is the one written here. A label pointing at
        // the line it annotates says nothing the caret has not.
        const known = before != ExprId.none and before != at;
        const count: usize = if (known) 2 else 1;
        const labels = try self.sink.arena.alloc(Label, count);
        labels[0] = .{
            .file = self.ast.fileOfExpr(at),
            .span = self.ast.exprSpan(at),
            .message = "it was already taken, and a value is taken once",
            .style = .primary,
        };
        if (known) labels[1] = .{
            .file = self.ast.fileOfExpr(before),
            .span = self.ast.exprSpan(before),
            .message = "it was taken here",
            .style = .secondary,
        };
        try self.emit(.{
            .severity = .err,
            .code = .o_move,
            .message = try std.fmt.allocPrint(
                self.sink.arena,
                "`{s}` has already been moved",
                .{try self.nameOf(root)},
            ),
            .labels = labels,
        });
    }

    fn reportUncommitted(self: *Checker, leaves: ExprId, p: Pending) std.mem.Allocator.Error!void {
        const labels = try self.sink.arena.alloc(Label, 2);
        labels[0] = .{
            .file = self.ast.fileOfExpr(leaves),
            .span = self.ast.exprSpan(leaves),
            .message = "give the value up after this, not before it",
            .style = .primary,
        };
        labels[1] = .{
            .file = self.ast.fileOfExpr(p.at),
            .span = self.ast.exprSpan(p.at),
            .message = "it was given up here",
            .style = .secondary,
        };
        try self.emit(.{
            .severity = .err,
            .code = .o_uncommitted,
            // A value made where it was given up has no name to quote, and
            // the label on the expression that made it says which one it is.
            .message = if (p.place.root == BindingId.none)
                try std.fmt.allocPrint(
                    self.sink.arena,
                    "`{s}` has not been given this value yet, and control leaves here",
                    .{self.constructName(p.for_)},
                )
            else
                try std.fmt.allocPrint(
                    self.sink.arena,
                    "`{s}` has not been given `{s}` yet, and control leaves here",
                    .{ self.constructName(p.for_), try self.nameOf(p.place.root) },
                ),
            .labels = labels,
        });
    }

    /// Records one diagnostic, or fails.
    ///
    /// The failure is passed to the caller rather than dropped. A dropped one
    /// turns a rejected program into an accepted one, and this pass is what
    /// stands between a program and a value used twice -- so of the two ways
    /// to be wrong when memory runs out, silently compiling is the one that
    /// cannot be allowed. The driver stops between passes; it can only do that
    /// if it is told.
    fn report(
        self: *Checker,
        code: @import("../diagnostics/diagnostic.zig").Code,
        at: ExprId,
        label: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) std.mem.Allocator.Error!void {
        const labels = try self.sink.arena.alloc(Label, 1);
        labels[0] = .{
            .file = self.ast.fileOfExpr(at),
            .span = self.ast.exprSpan(at),
            .message = label,
            .style = .primary,
        };
        try self.emit(.{
            .severity = .err,
            .code = code,
            .message = try std.fmt.allocPrint(self.sink.arena, fmt, args),
            .labels = labels,
        });
    }

    /// Gives one error to the sink unless an identical one was already given.
    fn emit(self: *Checker, d: Diagnostic) std.mem.Allocator.Error!void {
        const primary = d.primaryLabel() orelse return self.sink.add(d);
        const key = try std.fmt.allocPrint(self.sink.arena, "{d}:{d}:{d}:{d}:{s}", .{
            if (d.code) |c| @intFromEnum(c) else 0,
            @intFromEnum(primary.file),
            primary.span.start,
            primary.span.end,
            d.message,
        });
        if ((try self.emitted.getOrPut(self.gpa, key)).found_existing) return;
        try self.sink.add(d);
    }

    /// Reports every leak this function's reporting walk gathered: one
    /// diagnostic per binding, however many paths leave it held.
    ///
    /// Where it points is decided by how the value is left behind, because
    /// that is where a reader writes the fix. An explicit exit -- `return`,
    /// `?`, `break`, `continue` -- is where the path leaves while the value is
    /// held, so the first one written is primary and every other is named
    /// beside it. A path that only reaches the end of the scope has no exit to
    /// point at, and a brace is not a place to write a fix, so the binding is
    /// primary and the brace says where the scope ends. The binding is always
    /// shown, as where the value was acquired when it is not primary -- except
    /// in a derive's generated body, whose labels all land on the derive.
    fn reportLeaks(self: *Checker) std.mem.Allocator.Error!void {
        defer self.leaks.clearRetainingCapacity();
        const leaks = self.leaks.items;
        if (leaks.len == 0) return;
        std.mem.sort(Leak, leaks, self, leakBefore);
        var start: usize = 0;
        while (start < leaks.len) {
            var end = start + 1;
            while (end < leaks.len and leaks[end].binding == leaks[start].binding) end += 1;
            try self.reportLeak(leaks[start..end]);
            start = end;
        }
    }

    /// Orders leaks by the binding's declaration, then by where each exit is
    /// written, so that a binding's leaks are adjacent and the first explicit
    /// exit in the source is the first one met.
    fn leakBefore(self: *Checker, a: Leak, b: Leak) bool {
        if (a.binding != b.binding) {
            const ta = self.res.declaringToken(a.binding);
            const tb = self.res.declaringToken(b.binding);
            const fa = self.ast.fileOf(ta);
            const fb = self.ast.fileOf(tb);
            if (fa != fb) return @intFromEnum(fa) < @intFromEnum(fb);
            const sa = self.ast.tokenSpan(ta).start;
            const sb = self.ast.tokenSpan(tb).start;
            if (sa != sb) return sa < sb;
            return @intFromEnum(a.binding) < @intFromEnum(b.binding);
        }
        return self.isWrittenBefore(a.exit, b.exit);
    }

    /// Whether control leaves at `exit` by a jump written there, rather than
    /// by reaching the end of the scope.
    fn leavesExplicitly(self: *const Checker, exit: ExprId) bool {
        return cfg_mod.leavesExplicitly(self.ast, exit);
    }

    fn exitSpan(self: *const Checker, exit: ExprId) Span {
        return cfg_mod.exitSpan(self.ast, exit);
    }

    fn reportLeak(self: *Checker, group: []const Leak) std.mem.Allocator.Error!void {
        const arena = self.sink.arena;
        const b = group[0].binding;
        const tok = self.res.declaringToken(b);
        const discard = std.mem.eql(u8, try self.nameOf(b), "_");
        // A `_` in a tuple pattern stands at a component the tuple's
        // declaration names, and the label says which one it left unsettled.
        const component: ?[]const u8 = if (discard) blk: {
            const selected = self.typing.fieldSelection(tok) orelse break :blk null;
            break :blk self.typing.fieldName(selected.receiver, selected.field.index());
        } else null;
        // A derive's generated body is reported at the derive, so every label
        // in it lands on one span and only the primary says anything.
        const generated = self.program.originOf(self.current_owner) != null;

        var primary: ?ExprId = null;
        for (group) |l| {
            if (self.leavesExplicitly(l.exit)) {
                primary = l.exit;
                break;
            }
        }

        var ends_blocks = true;
        for (group) |l| {
            if (!self.leavesExplicitly(l.exit) and self.ast.exprTag(l.exit) != .block) ends_blocks = false;
        }

        var labels: std.ArrayList(Label) = .empty;
        const binding_label: Label = .{
            .file = self.ast.fileOf(tok),
            .span = self.ast.tokenSpan(tok),
            .message = if (component) |name|
                try std.fmt.allocPrint(arena, "`_` does not settle `{s}`", .{name})
            else if (discard)
                "`_` does not settle it"
            else if (primary != null)
                "acquired here"
            else if (ends_blocks)
                "never settled on the path that reaches the end of this block"
            else
                "never settled on the path that reaches the end of its scope",
            .style = if (primary == null) .primary else .secondary,
        };
        if (primary) |p| {
            try labels.append(arena, .{
                .file = self.ast.fileOfExpr(p),
                .span = self.exitSpan(p),
                .message = "still owned here",
            });
        }
        if (primary == null or !generated) try labels.append(arena, binding_label);
        if (!generated) {
            var previous = ExprId.none;
            for (group) |l| {
                if (l.exit == previous or (primary != null and l.exit == primary.?)) continue;
                previous = l.exit;
                const block = self.ast.exprTag(l.exit) == .block;
                try labels.append(arena, .{
                    .file = self.ast.fileOfExpr(l.exit),
                    .span = self.exitSpan(l.exit),
                    .message = if (self.leavesExplicitly(l.exit))
                        "also still owned here"
                    else if (primary != null)
                        (if (block) "also still owned where the block ends" else "also still owned where its scope ends")
                    else if (block)
                        "the block ends here"
                    else
                        "its scope ends here",
                    .style = .secondary,
                });
            }
        }

        const ty = self.typing.bindingType(b);
        const receiver = if (generated) null else try self.receiverOf(b);
        const notes = try arena.alloc([]const u8, 1);
        notes[0] = try self.settleHelp(ty, "settle it first with", receiver);
        // `let _ = badge` holds what `badge` held, and `badge` is the name the
        // reader wrote for it.
        const subject = if (discard and receiver != null)
            try std.fmt.allocPrint(arena, "`{s}`", .{receiver.?})
        else
            try self.subjectOf(b);
        try self.emit(.{
            .severity = .err,
            .code = .o_leak,
            .message = try std.fmt.allocPrint(arena, "{s} (a linear {s}) is still owned when this path leaves", .{
                subject,
                try self.typeText(ty),
            }),
            .labels = labels.items,
            .notes = notes,
        });
    }

    /// Names a binding for a message: by its name in backticks, or, for one a
    /// derive generated, by the source component it holds.
    fn subjectOf(self: *const Checker, b: BindingId) std.mem.Allocator.Error![]const u8 {
        return self.program.subjectAt(self.sink.arena, self.res.declaringToken(b));
    }

    /// What a help line writes an operation's receiver as: the binding's name,
    /// or for `let _ = e`, the expression `e` where it is short enough to
    /// quote. Null where there is nothing to write.
    fn receiverOf(self: *const Checker, b: BindingId) std.mem.Allocator.Error!?[]const u8 {
        const name = try self.nameOf(b);
        if (!std.mem.eql(u8, name, "_")) return name;
        const s = self.res.stmtOf(b);
        if (s == node.StmtId.none) return null;
        if (self.ast.stmtTag(s) != .let_decl) return null;
        const init = self.ast.stmtData(s).init;
        if (init == ExprId.none) return null;
        const text = self.ast.exprText(init);
        if (text.len > 40 or std.mem.indexOfScalar(u8, text, '\n') != null) return null;
        return text;
    }

    /// How a message writes the type of a value it names: in backticks, as
    /// the function's module writes it, arguments included. A closure has no
    /// name a reader could write, so it is called a closure.
    fn typeText(self: *const Checker, t: TypeId) std.mem.Allocator.Error![]const u8 {
        if (self.typing.get(t) == .closure) return "closure";
        const from = if (self.current_owner == .none) ModuleId.none else self.program.moduleOf(self.current_owner);
        const written = try writtenTypeName(self.sink.arena, self.ast, self.program, self.res, self.typing, from, t);
        return std.fmt.allocPrint(self.sink.arena, "`{s}`", .{written});
    }

    /// The help line saying how a value of type `t` can be settled: the
    /// operations the function's module can call on it that take it, then
    /// taking it apart where this module may and doing so settles what it
    /// holds.
    ///
    /// The operations are the type's own, through its per-type member index,
    /// and the ones the traits this module can name declare for it, through
    /// the implementations recorded under the type's head -- so the cost is
    /// what one type declares and implements, never the program. A trait's
    /// operation of a name the type's own operation already answers is not
    /// named, because a postfix call reaches the type's own first.
    fn settleHelp(self: *const Checker, t: TypeId, lead: []const u8, receiver: ?[]const u8) std.mem.Allocator.Error![]const u8 {
        const arena = self.sink.arena;
        var ops: std.ArrayList([]const u8) = .empty;
        var more = false;
        if (receiver) |r| {
            var names: [4]node.DeclId = undefined;
            const found = try self.settlingOperations(t, &names);
            more = found > 3;
            // `release` settles whatever state the value is in, so it leads.
            const shown = names[0..@min(found, 3)];
            for (shown, 0..) |op, i| {
                if (i == 0 or !std.mem.eql(u8, self.ast.tokenText(self.ast.declName(op)), "release")) continue;
                std.mem.copyBackwards(node.DeclId, shown[1 .. i + 1], shown[0..i]);
                shown[0] = op;
                break;
            }
            for (shown) |op| {
                const takes_more = self.ast.declParams(op).len > 1;
                try ops.append(arena, try std.fmt.allocPrint(arena, "`{s}.{s}({s})`", .{
                    r,
                    self.ast.tokenText(self.ast.declName(op)),
                    if (takes_more) "…" else "",
                }));
            }
        }
        const apart = if (receiver) |r| try self.takingApartHint(t, r) else null;
        const elsewhere: ?Applicable = if (receiver != null and ops.items.len == 0) try self.settlingElsewhere(t) else null;

        var out: std.Io.Writer.Allocating = .init(arena);
        const w = &out.writer;
        if (ops.items.len > 0) {
            w.print("{s} ", .{lead}) catch return error.OutOfMemory;
            for (ops.items, 0..) |text, i| {
                if (i > 0) w.writeAll(if (i + 1 == ops.items.len and !more) " or " else ", ") catch return error.OutOfMemory;
                w.writeAll(text) catch return error.OutOfMemory;
            }
            if (more) w.writeAll(" or …") catch return error.OutOfMemory;
            if (apart) |hint| w.print(", or take it apart with {s}", .{hint}) catch return error.OutOfMemory;
        } else if (elsewhere) |found| {
            const op = self.ast.tokenText(self.ast.declName(found.sig));
            w.print("{s} `{s}.{s}({s})` after `use {s}.{s}`", .{
                lead,
                receiver.?,
                op,
                if (self.ast.declParams(found.sig).len > 1) "…" else "",
                self.program.get(self.program.moduleOf(found.trait)).name,
                self.ast.tokenText(self.ast.declName(found.trait)),
            }) catch return error.OutOfMemory;
            if (apart) |hint| w.print(", or take it apart with {s}", .{hint}) catch return error.OutOfMemory;
        } else if (if (receiver != null) try self.handingBackOperation(t) else null) |op| {
            w.print("end it with `{s}.{s}({s})`, and settle what its `Err` hands back", .{
                receiver.?,
                self.ast.tokenText(self.ast.declName(op)),
                if (self.ast.declParams(op).len > 1) "…" else "",
            }) catch return error.OutOfMemory;
            if (apart) |hint| w.print(", or take it apart with {s}", .{hint}) catch return error.OutOfMemory;
        } else if (apart) |hint| {
            w.print("take it apart with {s}, or give it to something that takes it", .{hint}) catch return error.OutOfMemory;
        } else {
            w.writeAll("give it to something that takes it") catch return error.OutOfMemory;
        }
        return out.toOwnedSlice() catch return error.OutOfMemory;
    }

    /// Fills `out` with up to its length of the operations a postfix call
    /// written in this function's module runs on a value of `t` and that
    /// settle it, in the order `Reach.each` yields them: the type's own first,
    /// then the traits'. How many were found, up to `out.len`.
    ///
    /// Which operations a postfix call reaches is `Reach`'s answer -- the one
    /// the checker resolves a call by, with its reach, receiver and field
    /// rules -- and of those a name reaches, the one it runs is
    /// `NameReach.reaches`. What is added here is only what settling asks: the
    /// operation takes the value by `sink`, its result owes nothing, since one
    /// that hands back something to settle sends a reader round again, and it
    /// is not the operation the leak is inside. Whether an own operation's
    /// result owes is the answer the checker recorded for every type a binding
    /// must settle, which it gives only where the operation's block applies to
    /// the type, as the call would require; where it recorded none, nothing is
    /// named.
    ///
    /// Costs `Reach.each` over one type -- its own operations and the traits
    /// the module can see -- and a comparison of names among those.
    fn settlingOperations(self: *const Checker, t: TypeId, out: []node.DeclId) std.mem.Allocator.Error!usize {
        if (self.current_owner == .none) return 0;
        return self.settlers().operations(self.gpa, t, out);
    }

    /// The one routine that decides which operations settle a value, read
    /// from this function's module and under its declaration's promises.
    fn settlers(self: *const Checker) typecheck_mod.Settlers {
        return .{ .ast = self.ast, .res = self.res, .typing = self.typing, .reach = self.reach(), .owner = self.current_owner };
    }

    fn handingBackOperation(self: *const Checker, t: TypeId) std.mem.Allocator.Error!?node.DeclId {
        if (self.current_owner == .none) return null;
        return self.settlers().handingBack(self.gpa, t);
    }

    /// What `settlingOperations` reads postfix reach through: the checker's
    /// `Reach`, from this function's module and under its declaration's
    /// promises.
    fn reach(self: *const Checker) Reach {
        var r = reachIn(self.ast, self.program.source, self.res, self.typing, self.program.moduleOf(self.current_owner), self.current_owner);
        r.expanded_program = self.program;
        return r;
    }

    fn settles(self: *const Checker, t: TypeId, sig: node.DeclId) bool {
        return self.settlers().settles(t, sig);
    }

    /// An operation that settles a value of `t` through a trait this module
    /// cannot see, and that trait: what the help names, with the `use` that
    /// brings it in, when nothing in scope settles the value.
    ///
    /// The traits are read from the implementations under `t`'s head whose
    /// applicability the checker prepared, and each candidate is confirmed by
    /// `Reach.elsewhere`, the same answer a call of that name is refused with,
    /// so a field of that name or an unmet bound rules it out. Costs the rows
    /// under one head and the signatures of their traits.
    fn settlingElsewhere(self: *const Checker, t: TypeId) std.mem.Allocator.Error!?Applicable {
        if (self.current_owner == .none) return null;
        const module = self.program.moduleOf(self.current_owner);
        const head = self.typing.headOf(t);
        var rows = self.typing.impl_index.membersOfHead(head);
        while (rows.next()) |at| {
            const row = self.typing.implementations[at];
            if (!row.ofATrait() or !row.valid_key or !row.head.same(head)) continue;
            const trait: node.DeclId = @enumFromInt(row.trait);
            if (self.res.seesTrait(module, trait)) continue;
            var signatures = self.res.signatures.of(self.ast, trait);
            while (signatures.next()) |sig| {
                if (!self.settles(t, sig)) continue;
                const name = self.ast.tokenName(self.ast.declName(sig));
                if (try self.reach().elsewhere(self.gpa, t, name) != trait) continue;
                return .{ .sig = sig, .trait = trait };
            }
        }
        return null;
    }

    /// How a value of `t` is taken apart, where the function's module may take
    /// it apart and doing so settles everything it holds; null elsewhere.
    fn takingApartHint(self: *const Checker, t: TypeId, receiver: []const u8) std.mem.Allocator.Error!?[]const u8 {
        const d = self.typing.declOfType(t) orelse return null;
        if (!self.takingItApartDischarges(t)) return null;
        if (self.ast.declVisibility(d) == .opaque_ and
            (self.current_owner == .none or self.program.moduleOf(d) != self.program.moduleOf(self.current_owner))) return null;
        const arena = self.sink.arena;
        const name = self.ast.tokenText(self.ast.declName(d));
        switch (self.ast.declTag(d)) {
            .struct_ => {
                const fields = self.ast.declFields(d);
                if (fields.len > 3) return try std.fmt.allocPrint(arena, "`let {s} {{ … }} = {s}`", .{ name, receiver });
                var out: std.Io.Writer.Allocating = .init(arena);
                const w = &out.writer;
                w.print("`let {s} {{", .{name}) catch return error.OutOfMemory;
                for (fields, 0..) |field, i| {
                    w.print("{s} {s}: _", .{ if (i == 0) "" else ",", self.ast.tokenText(field.name) }) catch return error.OutOfMemory;
                }
                w.print("{s}}} = {s}`", .{ if (fields.len == 0) "" else " ", receiver }) catch return error.OutOfMemory;
                return out.toOwnedSlice() catch return error.OutOfMemory;
            },
            .newtype => return try std.fmt.allocPrint(arena, "`let {s}(_) = {s}`", .{ name, receiver }),
            .enum_ => return "a `match`",
            else => return null,
        }
    }

    /// Reports a write over a place that still holds a Linear value, at the
    /// write: that is what drops the value.
    fn reportOverwrite(self: *Checker, op: OpId) std.mem.Allocator.Error!void {
        const arena = self.sink.arena;
        const at = self.cfg.opAt(op);
        const place = self.cfg.opPlace(op);
        const ty = if (place.isWhole()) self.typing.bindingType(place.root) else self.typing.exprType(at);
        const written = self.ast.exprText(at);
        const labels = try arena.alloc(Label, 2);
        labels[0] = .{
            .file = self.ast.fileOfExpr(at),
            .span = self.ast.exprSpan(at),
            .message = "this write drops the old value",
        };
        const tok = self.res.declaringToken(place.root);
        labels[1] = .{
            .file = self.ast.fileOf(tok),
            .span = self.ast.tokenSpan(tok),
            .message = "acquired here",
            .style = .secondary,
        };
        const notes = try arena.alloc([]const u8, 1);
        // A part cannot be taken on its own, so neither an operation taking it
        // nor taking it apart is something to suggest for one.
        notes[0] = if (place.isWhole())
            try self.settleHelp(ty, "settle the old value first with", written)
        else
            "settle what this part holds before writing over it";
        try self.emit(.{
            .severity = .err,
            .code = .o_leak,
            .message = try std.fmt.allocPrint(arena, "`{s}` (a linear {s}) is still owned when this write replaces it", .{
                written,
                try self.typeText(ty),
            }),
            .labels = labels,
            .notes = notes,
        });
    }

    /// Reports a consuming `match` arm that names none of what the value held,
    /// at the arm: the arm is what drops it.
    fn reportDiscarded(self: *Checker, arm: ExprId, scrutinee: ExprId) std.mem.Allocator.Error!void {
        const arena = self.sink.arena;
        const ty = self.typing.exprType(scrutinee);
        const named = self.ast.exprTag(scrutinee) == .name_ref;
        const labels = try arena.alloc(Label, 2);
        labels[0] = .{
            .file = self.ast.fileOfExpr(arm),
            .span = self.ast.exprSpan(arm),
            .message = if (isCatchAll(self.ast, arm)) "`_` does not settle what it holds" else "this arm names none of what it holds",
        };
        labels[1] = .{
            .file = self.ast.fileOfExpr(scrutinee),
            .span = self.ast.exprSpan(scrutinee),
            .message = "taken apart here",
            .style = .secondary,
        };
        const notes = try arena.alloc([]const u8, 1);
        notes[0] = "name what it holds in the arm, so something can settle it";
        try self.emit(.{
            .severity = .err,
            .code = .o_leak,
            .message = if (named)
                try std.fmt.allocPrint(arena, "`{s}` (a linear {s}) is taken apart and what it holds is never settled", .{
                    self.ast.exprText(scrutinee),
                    try self.typeText(ty),
                })
            else
                try std.fmt.allocPrint(arena, "this linear {s} is taken apart and what it holds is never settled", .{try self.typeText(ty)}),
            .labels = labels,
            .notes = notes,
        });
    }

    /// Reports a field a structure literal writes over one its base holds
    /// that still owes settlement, at the written field: writing it is what
    /// drops the base's value.
    fn reportReplaced(self: *Checker, label: ExprId, base: ExprId, ty: TypeId) std.mem.Allocator.Error!void {
        const arena = self.sink.arena;
        const name = self.ast.exprText(label);
        const labels = try arena.alloc(Label, 2);
        labels[0] = .{
            .file = self.ast.fileOfExpr(label),
            .span = self.ast.exprSpan(label),
            .message = "this field replaces the base's value",
        };
        labels[1] = .{
            .file = self.ast.fileOfExpr(base),
            .span = self.ast.exprSpan(base),
            .message = "the base is taken here",
            .style = .secondary,
        };
        const notes = try arena.alloc([]const u8, 1);
        notes[0] = try std.fmt.allocPrint(arena, "settle the base's `{s}` before building from it, or let the base supply it", .{name});
        try self.emit(.{
            .severity = .err,
            .code = .o_leak,
            .message = try std.fmt.allocPrint(arena, "the base's `{s}` (a linear {s}) is replaced and never settled", .{
                name,
                try self.typeText(ty),
            }),
            .labels = labels,
            .notes = notes,
        });
    }

    /// Reports [O-Capture] for a closure body naming a binding of the body
    /// around it that it did not capture, and says which capture its uses
    /// need. A binding the body takes must be owned by a closure called
    /// once, `sink [sink name]`. One it changes is lent to it,
    /// `inout [inout name]`. Any other is read, `[name]`.
    fn reportUncaptured(self: *Checker, u: cfg_mod.Uncaptured) std.mem.Allocator.Error!void {
        const arena = self.sink.arena;
        const lambda = self.ast.lambda(u.lambda);
        const name = self.ast.tokenText(self.ast.exprMain(u.free));
        const listed = lambda.capture_open != .none;
        const note = if (u.takes) (if (!listed)
            try std.fmt.allocPrint(arena, "the closure gives `{s}` away, so it must own it: write `sink [sink {s}]` before the parameters, which makes a closure called once", .{ name, name })
        else if (lambda.invocation != .sink)
            try std.fmt.allocPrint(arena, "the closure gives `{s}` away, so it must own it: add `sink {s}` to the capture list and write `sink` before the list, which makes a closure called once", .{ name, name })
        else
            try std.fmt.allocPrint(arena, "the closure gives `{s}` away, so it must own it: add `sink {s}` to the capture list", .{ name, name })) else if (u.changes) (if (!listed)
            try std.fmt.allocPrint(arena, "the closure changes `{s}`, so lend it to the closure: `inout [inout {s}]` before the parameters lends `{s}` until the closure's last use", .{ name, name, name })
        else if (lambda.invocation == .read)
            try std.fmt.allocPrint(arena, "the closure changes `{s}`, so lend it to the closure: add `inout {s}` to the capture list and write `inout` before the list, which lends `{s}` until the closure's last use", .{ name, name, name })
        else
            try std.fmt.allocPrint(arena, "the closure changes `{s}`, so lend it to the closure: add `inout {s}` to the capture list, which lends `{s}` until the closure's last use", .{ name, name, name })) else if (!listed)
            try std.fmt.allocPrint(arena, "write `[{s}]` before the parameters to read it where it is, or `[sink {s}]` to move it into the closure", .{ name, name })
        else
            try std.fmt.allocPrint(arena, "add `{s}` to the capture list to read it where it is, or `sink {s}` to move it into the closure", .{ name, name });
        const labels = try arena.alloc(Label, 1);
        labels[0] = .{ .file = self.ast.fileOfExpr(u.free), .span = self.ast.exprSpan(u.free), .message = "this name belongs to an enclosing body", .style = .primary };
        const notes = try arena.alloc([]const u8, 1);
        notes[0] = note;
        try self.emit(.{
            .severity = .err,
            .code = .o_capture,
            .message = "this name is not declared in the closure capture list",
            .labels = labels,
            .notes = notes,
        });
    }

    /// Reports a Linear value no place names, yielded where it is only
    /// observed: nothing after this can name it to settle it.
    fn reportUnbound(self: *Checker, at: ExprId) std.mem.Allocator.Error!void {
        const arena = self.sink.arena;
        const labels = try arena.alloc(Label, 1);
        labels[0] = .{
            .file = self.ast.fileOfExpr(at),
            .span = self.ast.exprSpan(at),
            .message = "nothing can take what this yields",
        };
        const notes = try arena.alloc([]const u8, 1);
        notes[0] = "bind it with `let`, or give it to something that takes it";
        try self.emit(.{
            .severity = .err,
            .code = .o_leak,
            .message = try std.fmt.allocPrint(arena, "this linear {s} is never settled", .{try self.typeText(self.typing.exprType(at))}),
            .labels = labels,
            .notes = notes,
        });
    }

    /// Whether a place is lent rather than owned here.
    ///
    /// A lend may not be taken from, so a copy of one is never deletable --
    /// which is why `O-CopyDead` does not ask about it. Nor does it ask about
    /// a copy that names a part, since a part cannot be moved either. The rule
    /// is that a copy which could have been a move says nothing, and a copy
    /// that is the only legal way says everything.
    fn isLend(self: *const Checker, b: BindingId) bool {
        if (self.cfg.isLend(b)) return true;
        return self.res.parameterConvention(self.ast, b) == .read;
    }

    /// Whether a place is read again after this operation, on any path.
    ///
    /// The one thing in this pass that runs backwards, and the only reason it
    /// does. `O-CopyDead` asks whether a copy did anything, and that is a
    /// question about the future rather than the past -- a copy whose source
    /// nothing reads afterwards could have been the move it was hiding.
    fn liveAfter(
        self: *Checker,
        f: *const Function,
        i: usize,
        of: OpId,
    ) std.mem.Allocator.Error!bool {
        const blk = self.cfg.blocks[f.blocks.start + i];
        const root = self.cfg.opPlace(of).root;

        // The rest of this block first: a read after the copy settles it
        // without looking at any edge.
        //
        // Where the copy sits is the caller's -- it is walking these very
        // operations and knows the index. Searching the block for it instead
        // read the whole block once per copy in it, and a body of many copies
        // is the one shape that has.
        var ops: cfg_mod.OpIds = .{ .at = @intCast(of.index() + 1), .end = blk.ops.end };
        while (ops.next()) |op| {
            switch (self.cfg.opTag(op)) {
                .read, .consume, .copied => if (self.cfg.opPlace(op).root == root) return true,
                // Written again: what the copy holds is no longer what this
                // place holds, and nothing after can be reading it.
                .init, .discarded => if (self.cfg.opPlace(op).root == root) return false,
                // Or gone, which an exit says of a stretch of the live stack
                // rather than of one place, so it is asked of the stretch.
                .dies => if (self.cfg.endsScopeOf(self.cfg.opRun(op), root)) return false,
                // A construct receiving what it was given, being left before it
                // did, or handing on a value it made itself, touches no place
                // -- so none of them settles anything about what a copy still
                // holds. The end of a statement's temporaries touches no place
                // either, nor does a field a literal writes over its base's.
                .transferred, .committed, .escaped, .value, .returned, .lent, .temporaries_end, .replaced, .unsettled => {},
            }
        }

        return self.liveFrom(f, blk, root);
    }

    /// Whether a place is read on any path out of a block.
    ///
    /// A walk over the blocks reachable from here rather than a fixpoint over
    /// all of them: what is asked is reachability of a read, and a block seen
    /// twice answers the same both times.
    fn liveFrom(self: *Checker, f: *const Function, from: cfg_mod.Block, root: BindingId) std.mem.Allocator.Error!bool {
        const count = f.blocks.end - f.blocks.start;
        if (self.seen.items.len < count) {
            try self.seen.appendNTimes(self.gpa, false, count - self.seen.items.len);
        }
        self.reached.clearRetainingCapacity();
        defer for (self.reached.items) |at| {
            self.seen.items[at] = false;
        };

        var stack = std.ArrayList(BlockId).empty;
        defer stack.deinit(self.gpa);
        for (self.cfg.edgesOf(from)) |e| try stack.append(self.gpa, e);

        while (stack.pop()) |b| {
            if (b == .none) continue;
            const at = b.index() - f.blocks.start;
            if (at >= count or self.seen.items[at]) continue;
            self.seen.items[at] = true;
            try self.reached.append(self.gpa, @intCast(at));

            const blk = self.cfg.blocks[b.index()];
            var settled = false;
            var ops = self.cfg.opsOf(blk);
            while (ops.next()) |op| {
                switch (self.cfg.opTag(op)) {
                    .read, .consume, .copied => if (self.cfg.opPlace(op).root == root) return true,
                    .init, .discarded => if (self.cfg.opPlace(op).root == root) {
                        settled = true;
                    },
                    .dies => if (self.cfg.endsScopeOf(self.cfg.opRun(op), root)) {
                        settled = true;
                    },
                    .transferred, .committed, .escaped, .value, .returned, .lent, .temporaries_end, .replaced, .unsettled => {},
                }
                if (settled) break;
            }
            if (settled) continue;
            for (self.cfg.edgesOf(blk)) |e| try stack.append(self.gpa, e);
        }
        return false;
    }

    /// Which block every path to a block must pass through last.
    ///
    /// The immediate dominator, by the iterative algorithm over reverse
    /// postorder: a block's dominator is the one all its reached predecessors
    /// agree on, found by walking two of them up until they meet. It settles
    /// because reverse postorder puts a block after everything that can reach
    /// it except across a back edge.
    ///
    /// This is what makes a state a delta. A block's entry differs from its
    /// dominator's only where the operations between them wrote, and there is
    /// no other block whose state it can be stated against: a predecessor is
    /// not enough, because a join has several and they agree on nothing but
    /// what they inherited.
    const Dominators = struct {
        /// The immediate dominator of each block, itself for the entry, and
        /// `unreached` for a block no path reaches.
        idom: []u32,
        /// Where each block sits in reverse postorder, which is the order the
        /// walk up compares in.
        rank: []u32,

        const unreached = std.math.maxInt(u32);

        fn deinit(self: *Dominators, gpa: std.mem.Allocator) void {
            gpa.free(self.idom);
            gpa.free(self.rank);
        }

        /// The nearest block that dominates both, walking the two up until
        /// they meet. Reverse postorder ranks say which one is further down.
        fn meet(self: *const Dominators, a: u32, b: u32) u32 {
            var x = a;
            var y = b;
            while (x != y) {
                while (self.rank[x] > self.rank[y]) x = self.idom[x];
                while (self.rank[y] > self.rank[x]) y = self.idom[y];
            }
            return x;
        }
    };

    fn dominatorsOf(
        self: *Checker,
        order: []const u32,
        count: usize,
        preds: *const Predecessors,
    ) std.mem.Allocator.Error!Dominators {
        const idom = try self.gpa.alloc(u32, count);
        errdefer self.gpa.free(idom);
        @memset(idom, Dominators.unreached);

        const rank = try self.gpa.alloc(u32, count);
        errdefer self.gpa.free(rank);
        // A block the order left out is unreachable, and nothing asks about it.
        // Ranking it past every reached block keeps the walk up from following
        // one if a stale edge ever points at it.
        @memset(rank, Dominators.unreached);
        for (order, 0..) |b, at| rank[b] = @intCast(at);

        var doms: Dominators = .{ .idom = idom, .rank = rank };
        idom[0] = 0;

        var moved = true;
        while (moved) {
            moved = false;
            for (order) |b| {
                if (b == 0) continue;

                var settled: ?u32 = null;
                // Intersection is independent of order while this block's
                // parents stay fixed. Later blocks come first so a shared
                // loop exit walks back through neighbouring branches instead
                // of walking each branch back to the same early ancestor.
                // The predecessor order used for diagnostics stays intact.
                const previous = preds.of(b);
                var predecessor_index = previous.len;
                while (predecessor_index > 0) {
                    predecessor_index -= 1;
                    const p = previous[predecessor_index];
                    if (idom[p] == Dominators.unreached) continue;
                    settled = if (settled) |x| doms.meet(x, p) else p;
                }

                const found = settled orelse continue;
                if (idom[b] != found) {
                    idom[b] = found;
                    moved = true;
                }
            }
        }

        // What the answer means, checked rather than assumed: the immediate
        // dominator of a block is an ancestor of every predecessor that
        // reaches it. A wrong one would make a delta be stated against a block
        // some path never passes through, which is a wrong state rather than a
        // slow one.
        // Walking a chain per predecessor is quadratic in a function that is
        // one long chain, which is exactly the shape this work is about -- so
        // the check is bounded by a size every case in the corpus is under and
        // only a generated body exceeds. It covers what a person writes.
        if (std.debug.runtime_safety and count <= 512) {
            for (order) |b| {
                if (b == 0) continue;
                if (idom[b] == Dominators.unreached) continue;
                for (preds.of(b)) |p| {
                    if (idom[p] == Dominators.unreached) continue;
                    var up = p;
                    while (up != idom[b] and up != 0) up = idom[up];
                    std.debug.assert(up == idom[b]);
                }
            }
        }

        return doms;
    }

    /// One slot's value on both sides of a change.
    ///
    /// Both sides, because the trail is read in either direction: winding down
    /// to a block applies what its operations made of a slot, and unwinding
    /// puts back what they found.
    const Edit = struct {
        slot: u32,
        was: State,
        now: State,
        was_at: ExprId,
        now_at: ExprId,
    };

    const EditGeneration = enum(u1) { first, second };

    /// What a block changed, against the exit state of the block that
    /// dominates it.
    const EditRange = struct {
        start: usize = 0,
        len: usize = 0,
        /// How many leading edits its entry merge made, the rest being its
        /// operations'. The walk that reports needs the two apart: it runs the
        /// operations again, and has to start from what the merge settled.
        join: usize = 0,
        generation: EditGeneration = .first,
    };

    const EditArenas = struct {
        items: [2]std.ArrayList(Edit) = .{ .empty, .empty },
        read: EditGeneration = .first,
        write: EditGeneration = .second,
    };

    /// The state of every root at one position in the graph, and the edits
    /// that move it to any other.
    ///
    /// The state used to be a row per block: a matrix in the function's blocks
    /// times its bindings, allocated per function and copied per block per
    /// sweep, so a body of n statements cost n squared however little it
    /// learned. What it learns is nowhere near that large. At two thousand
    /// statements the matrix holds eight hundred times more cells than any
    /// operation writes, and the multiple doubles with the body, because the
    /// edits grow with the program while the matrix grows with its square.
    ///
    /// So there is one state, wound to a position rather than copied to one. A
    /// block's own edits are stated against the exit of the block that
    /// dominates it -- the only block they can be stated against, since a
    /// merge has several predecessors and they agree on nothing but what they
    /// inherited. Moving between two blocks undoes the edits back to what the
    /// two share and applies the edits down to where it is going.
    ///
    /// The price is that a reader asks rather than indexes. `state[slot]`
    /// answers for wherever the trail is wound and nowhere else, so every
    /// question is now about where the asker stands as much as about the slot.
    const Flow = struct {
        /// What every root holds at the position the trail is wound to.
        state: []State,
        /// Where each was taken, parallel to `state`.
        state_at: []ExprId,
        /// What each block changed, against its dominator's exit.
        delta: []EditRange,
        /// Complete previous- and current-sweep edit generations.
        arenas: EditArenas,
        /// The blocks whose edits are applied, outermost first. Always a path
        /// down the dominator tree.
        path: std.ArrayList(u32),
        on_path: []bool,
        /// Whether any sweep has computed this block's delta. Until one has,
        /// the block has no exit state, and a merge naming it as a predecessor
        /// is naming a block no path has reached yet.
        computed: []bool,
        idom: []const u32,
        /// Where winding collects the blocks between a target and the path.
        chain: std.ArrayList(u32),
        /// How much of `path` a merge in progress has already read.
        ///
        /// A merge asks every predecessor what it changed since the block they
        /// all share, and winding from one predecessor to the next replaces
        /// only the frames the two do not have in common. Without this the
        /// frames they do have in common are read once per predecessor, so a
        /// loop that n `break`s leave reads the whole body n times -- which is
        /// the difference between a merge costing the edits it reads and
        /// costing those edits times the number of paths in.
        harvested: usize = 0,

        /// No block on the path is an ancestor, so the walk goes to the root.
        const nowhere = std.math.maxInt(u32);

        fn init(
            gpa: std.mem.Allocator,
            n: usize,
            count: usize,
            idom: []const u32,
        ) std.mem.Allocator.Error!Flow {
            const state = try gpa.alloc(State, n);
            errdefer gpa.free(state);
            @memset(state, .uninit);

            const state_at = try gpa.alloc(ExprId, n);
            errdefer gpa.free(state_at);
            @memset(state_at, ExprId.none);

            const delta = try gpa.alloc(EditRange, count);
            errdefer gpa.free(delta);
            @memset(delta, .{});

            const on_path = try gpa.alloc(bool, count);
            errdefer gpa.free(on_path);
            @memset(on_path, false);

            const computed = try gpa.alloc(bool, count);
            errdefer gpa.free(computed);
            @memset(computed, false);

            return .{
                .state = state,
                .state_at = state_at,
                .delta = delta,
                .arenas = .{},
                .path = .empty,
                .on_path = on_path,
                .computed = computed,
                .idom = idom,
                .chain = .empty,
            };
        }

        fn deinit(self: *Flow, gpa: std.mem.Allocator) void {
            for (&self.arenas.items) |*items| items.deinit(gpa);
            gpa.free(self.delta);
            gpa.free(self.state);
            gpa.free(self.state_at);
            gpa.free(self.on_path);
            gpa.free(self.computed);
            self.path.deinit(gpa);
            self.chain.deinit(gpa);
            self.* = undefined;
        }

        fn arena(self: *Flow, generation: EditGeneration) *std.ArrayList(Edit) {
            return &self.arenas.items[@intFromEnum(generation)];
        }

        fn writeArena(self: *Flow) *std.ArrayList(Edit) {
            return self.arena(self.arenas.write);
        }

        fn editsOfRange(self: *Flow, range: EditRange) []Edit {
            const items = self.arena(range.generation).items;
            std.debug.assert(range.start <= items.len);
            std.debug.assert(range.len <= items.len - range.start);
            std.debug.assert(range.join <= range.len);
            return items[range.start..][0..range.len];
        }

        fn editsOf(self: *Flow, b: u32) []Edit {
            return self.editsOfRange(self.delta[b]);
        }

        /// Publishes a complete candidate after the caller has reserved the
        /// path slot and finished every fallible operation for the block.
        fn publish(self: *Flow, b: u32, candidate: EditRange) void {
            std.debug.assert(candidate.generation == self.arenas.write);
            std.debug.assert(self.path.items.len < self.path.capacity);
            self.delta[b] = candidate;
            self.computed[b] = true;
            self.path.appendAssumeCapacity(b);
            self.on_path[b] = true;
        }

        fn publishCandidate(
            self: *Flow,
            gpa: std.mem.Allocator,
            b: u32,
            candidate: EditRange,
        ) std.mem.Allocator.Error!void {
            try self.path.ensureUnusedCapacity(gpa, 1);
            self.publish(b, candidate);
        }

        /// Rotates only when no reached descriptor still needs the old read
        /// generation. A false result leaves both roles unchanged.
        fn rotateArenas(self: *Flow) bool {
            for (self.delta, self.computed) |range, computed| {
                if (computed and range.generation != self.arenas.write) return false;
            }
            std.mem.swap(EditGeneration, &self.arenas.read, &self.arenas.write);
            return true;
        }

        fn applyEdits(self: *Flow, edits: []const Edit) void {
            for (edits) |e| {
                self.state[e.slot] = e.now;
                self.state_at[e.slot] = e.now_at;
            }
        }

        /// Backwards, because two edits may name one slot and it is the first
        /// of them that holds what the slot was before either.
        fn undoEdits(self: *Flow, edits: []const Edit) void {
            var i = edits.len;
            while (i > 0) {
                i -= 1;
                self.state[edits[i].slot] = edits[i].was;
                self.state_at[edits[i].slot] = edits[i].was_at;
            }
        }

        /// Restates a block's edits against where the trail now stands.
        ///
        /// An edit says what a slot became and what it was before, and the
        /// second half is only ever true of the state the block's dominator
        /// hands it. That state rises while the sweeps settle, so a block
        /// whose dominator has moved since its own edits were recorded holds
        /// a "was" no block on the path still has -- and undoing the edits
        /// writes it back.
        ///
        /// It matters because a block's own edits are applied while winding
        /// to a predecessor it dominates, which is every loop head: the walk
        /// goes down through the head to the back edge and returns through
        /// the head again. Returning with a stale "was" leaves the base the
        /// merge is measured against holding a value nothing wrote, and the
        /// merge then records the difference as an edit -- which is the same
        /// stale one, so it never settles.
        ///
        /// Called where the trail stands at the block's base, so applying and
        /// undoing leaves the state exactly as it found it.
        fn restate(self: *Flow, b: u32) void {
            for (self.editsOf(b)) |*e| {
                e.was = self.state[e.slot];
                e.was_at = self.state_at[e.slot];
                self.state[e.slot] = e.now;
                self.state_at[e.slot] = e.now_at;
            }
            self.undoEdits(self.editsOf(b));
        }

        /// Records a block whose edits the caller has already applied.
        fn mark(self: *Flow, gpa: std.mem.Allocator, b: u32) std.mem.Allocator.Error!void {
            try self.path.append(gpa, b);
            self.on_path[b] = true;
        }

        fn pop(self: *Flow) void {
            const b = self.path.pop().?;
            self.on_path[b] = false;
            if (self.harvested > self.path.items.len) self.harvested = self.path.items.len;
            self.undoEdits(self.editsOf(b));
        }

        /// Begins a merge, which reads the path from here down.
        fn openMerge(self: *Flow) usize {
            self.harvested = self.path.items.len;
            return self.harvested;
        }

        /// The frames pushed since the last time a merge read the path, which
        /// is what this predecessor changed that no earlier one already said.
        fn freshFrames(self: *Flow) []const u32 {
            const from = self.harvested;
            self.harvested = self.path.items.len;
            return self.path.items[from..];
        }

        /// Back to the function's entry, where nothing has been written yet.
        fn unwind(self: *Flow) void {
            while (self.path.items.len > 0) self.pop();
        }

        /// Winds the state to a block's exit.
        ///
        /// Up to what the target and the current position share, then down. The
        /// walk up is the target's dominator chain, so what it costs is the
        /// distance between the two in the dominator tree and not the size of
        /// the function.
        fn wind(self: *Flow, gpa: std.mem.Allocator, to: u32) std.mem.Allocator.Error!void {
            self.chain.clearRetainingCapacity();
            var q = to;
            var meet: u32 = nowhere;
            while (true) {
                if (self.on_path[q]) {
                    meet = q;
                    break;
                }
                try self.chain.append(gpa, q);
                if (q == 0) break;
                q = self.idom[q];
            }

            while (self.path.items.len > 0 and
                self.path.items[self.path.items.len - 1] != meet) self.pop();

            var i = self.chain.items.len;
            while (i > 0) {
                i -= 1;
                const b = self.chain.items[i];
                self.applyEdits(self.editsOf(b));
                try self.mark(gpa, b);
            }
        }

        /// Winds to what a block's own edits are stated against: the exit of
        /// the block that dominates it, or the function's entry for the one
        /// block nothing dominates.
        fn windToBase(self: *Flow, gpa: std.mem.Allocator, b: u32) std.mem.Allocator.Error!void {
            if (b == 0) {
                self.unwind();
                return;
            }
            try self.wind(gpa, self.idom[b]);
        }
    };

    /// Whether two edit sets say the same about the lattice.
    ///
    /// Where a value was taken is deliberately left out. It is not part of the
    /// lattice, so it cannot settle the graph anywhere the states alone would
    /// not -- and letting it drive the sweeps would spend on a site that is
    /// still moving the bound the states are entitled to.
    fn sameStates(a: []const Edit, b: []const Edit) bool {
        if (a.len != b.len) return false;
        for (a, b) |x, y| {
            if (x.slot != y.slot or x.now != y.now) return false;
        }
        return true;
    }

    /// What a block's entry holds: everything every path into it agrees on,
    /// recorded as edits against the exit of the block that dominates it.
    ///
    /// That block dominates every predecessor too, so each predecessor differs
    /// from it -- and therefore from every other predecessor -- only in the
    /// edits since it. Those slots are the whole of what a merge has to ask
    /// about. Everywhere else each predecessor still holds what it inherited,
    /// which is one value, so the join is that value and there is nothing to
    /// record.
    fn joinInto(
        self: *Checker,
        flow: *Flow,
        preds: *const Predecessors,
        b: u32,
        slots: *std.ArrayList(u32),
        merged: *std.ArrayList(State),
        merged_at: *std.ArrayList(ExprId),
        into: *std.ArrayList(Edit),
    ) std.mem.Allocator.Error!void {
        try flow.windToBase(self.gpa, b);
        flow.restate(b);
        const base = flow.openMerge();

        // What the last sweep settled here, which this one starts from rather
        // than replaces. The states could be replaced: they only ever rise, so
        // a predecessor's exit today is at least what it pushed on any earlier
        // sweep and joining the old answer in would add nothing. A site is not
        // in the lattice and does not rise -- once a value arrives already
        // taken, the operation that took it stops saying where -- so the
        // earliest one seen is kept, and it is kept by carrying it forward.
        const settled = flow.editsOf(b)[0..flow.delta[b].join];

        slots.clearRetainingCapacity();
        for (settled) |e| try slots.append(self.gpa, e.slot);
        for (preds.of(b)) |p| {
            if (!flow.computed[p]) continue;
            try flow.wind(self.gpa, p);
            // Winding to a predecessor only ever extends the base path, which
            // is what it means for the block's dominator to dominate it.
            std.debug.assert(flow.path.items.len >= base);
            for (flow.freshFrames()) |q| {
                for (flow.editsOf(q)) |e| try slots.append(self.gpa, e.slot);
            }
        }
        if (slots.items.len == 0) {
            try flow.windToBase(self.gpa, b);
            return;
        }

        std.mem.sortUnstable(u32, slots.items, {}, std.sort.asc(u32));
        var kept: usize = 0;
        for (slots.items) |s| {
            if (kept > 0 and slots.items[kept - 1] == s) continue;
            slots.items[kept] = s;
            kept += 1;
        }
        slots.shrinkRetainingCapacity(kept);

        merged.clearRetainingCapacity();
        merged_at.clearRetainingCapacity();
        var first = true;
        for (preds.of(b)) |p| {
            if (!flow.computed[p]) continue;
            try flow.wind(self.gpa, p);
            if (first) {
                for (slots.items) |s| {
                    try merged.append(self.gpa, flow.state[s]);
                    try merged_at.append(self.gpa, flow.state_at[s]);
                }
                first = false;
                continue;
            }
            for (slots.items, 0..) |s, k| {
                merged.items[k] = State.join(merged.items[k], flow.state[s]);
                // The site does not drive the sweep, so which of two survives
                // is settled by where they are written rather than by the order
                // the blocks were walked in.
                merged_at.items[k] = self.writtenFirst(merged_at.items[k], flow.state_at[s]);
            }
        }

        // A slot is asked about because some predecessor's edits named it, or
        // because the last sweep settled it -- and the last sweep only settled
        // anything if a predecessor had already been computed. So there is
        // always one to have answered.
        std.debug.assert(merged.items.len == slots.items.len);

        // Both runs are in slot order, so carrying the earlier sites forward is
        // one walk rather than a lookup per slot.
        var k: usize = 0;
        for (settled) |e| {
            while (k < slots.items.len and slots.items[k] < e.slot) k += 1;
            if (k == slots.items.len) break;
            if (slots.items[k] != e.slot) continue;
            merged_at.items[k] = self.writtenFirst(merged_at.items[k], e.now_at);
        }

        try flow.windToBase(self.gpa, b);
        for (slots.items, merged.items, merged_at.items) |s, v, at| {
            if (flow.state[s] == v and flow.state_at[s] == at) continue;
            try writeState(self.gpa, flow.state, flow.state_at, into, @intCast(s), v, at);
        }
    }

    /// Runs the forward analysis over one function to a fixpoint.
    ///
    /// A fixpoint rather than a walk because of the back edge: a loop's body
    /// is reached both from the head and from itself, and what is true at its
    /// start is what is true on both.
    fn function(self: *Checker, f: *const Function) std.mem.Allocator.Error!void {
        const count = f.blocks.end - f.blocks.start;
        if (count == 0) return;
        self.current_owner = f.owner;
        defer self.current_owner = .none;
        self.merge_origins.clearRetainingCapacity();
        self.scheduled.clearRetainingCapacity();

        const roots = try self.rootsOf(f);
        defer {
            self.releaseRoots(roots);
            self.gpa.free(roots);
        }
        self.findTracked(f);
        const n = roots.len;

        // The transfers open at each block's entry.
        //
        // Carried alongside the lattice rather than inside it: from the
        // source's side the value is genuinely moved, and what is pending is
        // the receipt, which belongs to the construct and not to the binding.
        // It has to cross blocks because a construct's operands do. `use2(d,
        // if c { return 7 } else { k })` gives `d` up in one block and leaves
        // in another, so a set held only within a block sees nothing open
        // where control goes.
        const open = try self.gpa.alloc(std.ArrayList(Pending), count);
        defer {
            for (open) |*o| o.deinit(self.gpa);
            self.gpa.free(open);
        }
        @memset(open, .empty);

        var carried: std.ArrayList(Pending) = .empty;
        defer carried.deinit(self.gpa);

        // Bounded rather than "until nothing changes": a state can only rise
        // through five values, so the graph settles in at most that many
        // sweeps per block, and a bound turns a builder mistake into a wrong
        // answer rather than a hang.
        //
        // A sweep carries what is known at least one block further, so the
        // bound holds whatever order the blocks are taken in: `count` of them
        // for reachability to spread, four times that again for the four
        // rises a state can make along the way, and `count` more for an open
        // transfer, which is created once its block is reached and then spreads
        // a block per sweep like everything else. Exhausting the bound would mean
        // reading states that were still rising -- too low, so a `moved` that
        // had not yet arrived goes unreported and a use after a move is
        // accepted. That is the accepting direction, out of the pass that is
        // the whole memory guarantee, so the bound is asserted and not assumed.
        //
        // Reverse postorder makes it slack rather than tight: a chain of `if`s
        // settles in two sweeps where index order needed one per `if`.
        const order = try self.cfg.reversePostorder(self.gpa, f);
        defer self.gpa.free(order);

        try self.findAwaiting(f, order);
        defer {
            self.gpa.free(self.awaiting);
            self.awaiting = &.{};
        }

        var preds = try self.predecessorsOf(f, count);
        defer preds.deinit(self.gpa);

        var doms = try self.dominatorsOf(order, count, &preds);
        defer doms.deinit(self.gpa);

        var flow = try Flow.init(self.gpa, n, count, doms.idom);
        defer flow.deinit(self.gpa);

        // What a merge asks about, and what it settles on.
        var asked: std.ArrayList(u32) = .empty;
        defer asked.deinit(self.gpa);
        var merged: std.ArrayList(State) = .empty;
        defer merged.deinit(self.gpa);
        var merged_at: std.ArrayList(ExprId) = .empty;
        defer merged_at.deinit(self.gpa);

        var replayed: std.ArrayList(Edit) = .empty;
        defer replayed.deinit(self.gpa);

        var sweeps = fixpointSweepBudget(count);
        var changed = true;
        while (changed and sweeps > 0) : (sweeps -= 1) {
            changed = false;
            for (flow.delta, flow.computed) |range, computed| {
                std.debug.assert(!computed or range.generation == flow.arenas.read);
            }
            flow.writeArena().clearRetainingCapacity();
            for (order) |b| {
                const start = flow.writeArena().items.len;
                try self.joinInto(&flow, &preds, b, &asked, &merged, &merged_at, flow.writeArena());
                const join = flow.writeArena().items.len - start;

                carried.clearRetainingCapacity();
                try carried.appendSlice(self.gpa, open[b].items);

                // Nothing is reported here: a sweep may be working from a
                // state that later rises, and a message from one of those is
                // about a program that does not exist.
                try self.runBlock(f, b, flow.state, flow.state_at, &carried, flow.writeArena(), false);
                const len = flow.writeArena().items.len - start;
                const candidate: EditRange = .{
                    .start = start,
                    .len = len,
                    .join = join,
                    .generation = flow.arenas.write,
                };

                if (!flow.computed[b] or !sameStates(flow.editsOf(b), flow.editsOfRange(candidate))) {
                    changed = true;
                }

                // Open transfers join by union: a value pending on one path
                // into a block is pending there, whatever the other path did.
                // Pushed rather than pulled, because a union has no base to be
                // stated against and needs none -- it only ever grows.
                for (self.cfg.edgesOf(self.cfg.blocks[f.blocks.start + b])) |e| {
                    const to = e.index() - f.blocks.start;
                    for (carried.items) |p| {
                        if (try self.openTransfer(&open[to], p)) changed = true;
                    }
                }

                try flow.publishCandidate(self.gpa, b, candidate);
            }
            const rotated = flow.rotateArenas();
            std.debug.assert(rotated);
        }
        std.debug.assert(!changed);
        if (std.debug.runtime_safety) try self.agreesWithRows(f, count, n, order, &flow);

        for (0..count) |i| {
            const b: u32 = @intCast(i);
            if (!flow.computed[b]) continue;
            try self.checkMerges(f, b, roots, &preds, &flow, &asked, &merged, &merged_at, .mark_origins);
        }

        // The walk that reports. It runs each block's operations again over the
        // state the fixpoint settled on, in the order the blocks were minted so
        // that what it says comes out where a reader would look for it.
        for (0..count) |i| {
            const b: u32 = @intCast(i);
            if (!flow.computed[b]) continue;

            // Wound to the block's exit and then walked back over its own
            // operations, which leaves the state at its entry while the path
            // still says its exit. The two are made to agree again below,
            // before anything winds anywhere else.
            try flow.wind(self.gpa, b);
            const body = flow.editsOf(b)[flow.delta[b].join..];
            flow.undoEdits(body);

            carried.clearRetainingCapacity();
            try carried.appendSlice(self.gpa, open[b].items);
            replayed.clearRetainingCapacity();
            try self.runBlock(f, b, flow.state, flow.state_at, &carried, &replayed, true);

            if (std.debug.runtime_safety) {
                // What this walk reported is about the state the fixpoint
                // settled on only if running the block again lands where the
                // fixpoint recorded that it does.
                std.debug.assert(replayed.items.len == body.len);
                for (replayed.items, body) |seen, settled| {
                    std.debug.assert(seen.slot == settled.slot);
                    std.debug.assert(seen.was == settled.was);
                    std.debug.assert(seen.now == settled.now);
                    std.debug.assert(seen.was_at == settled.was_at);
                    std.debug.assert(seen.now_at == settled.now_at);
                }
            }

            flow.undoEdits(replayed.items);
            flow.applyEdits(body);
        }
        try self.reportLeaks();

        for (0..count) |i| {
            const b: u32 = @intCast(i);
            if (!flow.computed[b]) continue;
            try self.checkMerges(f, b, roots, &preds, &flow, &asked, &merged, &merged_at, .report);
        }
    }

    /// Walks one block's operations, updating `state` and the open transfers.
    fn runBlock(
        self: *Checker,
        f: *const Function,
        i: usize,
        state: []State,
        /// Where each moved place was taken, parallel to `state`. Carried
        /// beside it rather than inside it because it is not part of the
        /// lattice: it answers "where", and the join answers "whether".
        moved_at: []ExprId,
        open: *std.ArrayList(Pending),
        journal: ?*std.ArrayList(Edit),
        report_now: bool,
    ) std.mem.Allocator.Error!void {
        const block_id = BlockId.at(f.blocks.start + i);
        const blk = self.cfg.blocks[block_id.index()];

        var ops = self.cfg.opsOf(blk);
        while (ops.next()) |op| {
            const tag = self.cfg.opTag(op);
            const at = self.cfg.opAt(op);
            // A placement's operations are contiguous, so whether it is spent
            // is settled once, here, against the state before any of the run
            // has applied. Asking per operation instead lets the first consume
            // to find a moved place stand for the whole expression, while the
            // consumes beside it keep marking their own values taken -- and
            // lowering skips all of them, so those values are released by
            // nobody and the graph says they were.
            const schedule = self.cfg.opSchedule(op);
            if (schedule != ExprId.none) {
                if (startsARun(self.cfg, blk.ops.start, op)) {
                    self.run_is_spent = spentAt(self, op, blk.ops.end, state);
                }
            }

            // A construct receiving what its operands gave up. Only its own
            // close here: an inner call completing must leave the call around
            // it open, which is what makes them compose by union.
            if (tag == .committed) {
                var kept: usize = 0;
                for (open.items) |p| {
                    if (p.for_ == at) continue;
                    open.items[kept] = p;
                    kept += 1;
                }
                open.shrinkRetainingCapacity(kept);
                continue;
            }

            // Control leaving a construct that has not completed. What was
            // given to it, if anything, is owned by nobody in the state this
            // goes to.
            if (tag == .escaped) {
                if (report_now) {
                    // One is enough: a construct given two values and left is
                    // one mistake, and naming both would be the same sentence
                    // twice. The earliest in the source rather than whichever
                    // the sweeps left first in the list, so which one is named
                    // does not depend on the order the blocks were walked in.
                    var earliest: ?Pending = null;
                    for (open.items) |p| {
                        if (p.for_ != self.cfg.opPendingFor(op)) continue;
                        if (earliest == null or self.startOf(p.at) < self.startOf(earliest.?.at)) {
                            earliest = p;
                        }
                    }
                    if (earliest) |p| try self.reportUncommitted(at, p);
                }
                continue;
            }

            // A value no place names, yielded to the construct around it.
            // There is no place to key it by and no binding state to change:
            // what owes something is the value itself, and the only thing that
            // can say so is its type.
            if (schedule != ExprId.none and report_now) {
                try self.cancelled.placed.put(
                    self.gpa,
                    .{ .schedule = schedule, .exit = self.cfg.opExit(op) },
                    {},
                );
            }

            if (tag == .transferred) {
                // Yielded into a position that only observes it. Nothing will
                // ever consume it: no place names it, so no position after
                // this one can name it, and there is no scope end where it
                // would be asked for -- a binding's [O-Leak] is asked at
                // `dies`, and this value has no binding.
                if (self.cfg.opReading(op)) {
                    if (report_now and self.owes(self.typing.exprType(at))) try self.reportUnbound(at);
                    continue;
                }
                if (self.cfg.opPendingFor(op) != ExprId.none and
                    self.owes(self.typing.exprType(at)))
                {
                    const p: Pending = .{
                        .place = .{ .root = BindingId.none },
                        .for_ = self.cfg.opPendingFor(op),
                        .at = at,
                    };
                    if (!holds(open.items, p)) try open.append(self.gpa, p);
                }
                continue;
            }

            // Asked before the root is looked at, because this one need not
            // have a root: what a `_` arm discards is a value, named or not.
            if (tag == .discarded) {
                const scrutinee = self.cfg.ops.items(.source)[op.index()];
                if (report_now and self.discardLeavesAnObligation(self.typing.exprType(scrutinee))) {
                    try self.reportDiscarded(at, scrutinee);
                }
                continue;
            }

            // A field a structure literal writes over its base's, which names
            // no place: the base was taken whole, so what it held under that
            // field has no owner left. The field's declared type says whether
            // that loses a settlement.
            if (tag == .replaced) {
                if (report_now) {
                    if (self.typing.fieldSelection(self.ast.exprMain(at))) |field| {
                        const replaced = self.typing.fieldType(field.receiver, field.field.index());
                        if (self.owes(replaced)) try self.reportReplaced(at, self.cfg.ops.items(.source)[op.index()], replaced);
                    }
                }
                continue;
            }

            // A stretch of the live stack ending, which names no place either:
            // what ends is every scope down to a mark, and the bindings in it
            // are reached through the stack rather than through the operation.
            if (tag == .dies) {
                try self.endScopes(op, state, moved_at, journal, report_now);
                continue;
            }

            // An observed projection can start at a temporary descriptor and
            // have no binding slot. Its read-only authority still forbids a
            // consuming position from taking the referent. Scalar snapshots
            // and explicit copies read the place instead.
            if (tag == .consume and self.typing.readonly_places.contains(at)) {
                if (report_now) try self.report(
                    .o_move,
                    at,
                    "read the observation, or copy a copyable referent",
                    "this read-only observation cannot give away the value it observes",
                    .{},
                );
                continue;
            }

            const place = self.cfg.opPlace(op);
            const root = place.root;
            const slot = self.slotOf(root) orelse continue;

            switch (tag) {
                // Answered above, before the root was looked at, because these
                // name no place: what a `_` arm discards or a written field
                // replaces is a value named or not, what a construct makes has
                // no name at all, a construct
                // receiving or being left names none, and a scope exit names a
                // stretch of the stack.
                .discarded, .replaced, .transferred, .committed, .escaped, .dies, .value, .returned, .lent, .temporaries_end => {},

                // Writing is not moving, and that is why it leaks: a move
                // leaves the obligation with the value, a write leaves the
                // old value with nothing holding it. So a place written while
                // it still holds a Linear value loses it, and `init` is where
                // that is asked -- of the place written, whatever its depth,
                // because a whole binding and a Linear part of one differ in
                // how much is lost and not in whether anything is.
                //
                // Only a whole binding refills the hole a move left. Writing
                // one field of a moved-from value leaves the rest gone, so
                // reading a partial assignment as a refill lets what was
                // already taken be taken again. The depth is what the builder
                // kept in order to say which of the two this is.
                .init => {
                    if (report_now and
                        state[slot] == .init and
                        self.writesALinearPlace(op))
                    {
                        try self.reportOverwrite(op);
                    }
                    if (place.depth == 0) try writeState(
                        self.gpa,
                        state,
                        moved_at,
                        journal,
                        @intCast(slot),
                        .init,
                        moved_at[slot],
                    );
                },

                // Whether the refused construct took the value is unknown,
                // so an initialised place is neither held nor moved on this
                // path.
                .unsettled => if (state[slot] == .init) try writeState(self.gpa, state, moved_at, journal, @intCast(slot), .unknown, moved_at[slot]),

                .read => if (state[slot] == .moved and report_now) {
                    if (at == moved_at[slot]) _ = self.merge_origins.remove(.{ .at = at, .binding = root });
                    if (!self.fromMerge(moved_at[slot], root)) try self.reportMoved(at, root, moved_at[slot]);
                },

                .consume => {
                    try self.consume(op, slot, state, moved_at, journal, report_now);

                    // A construct that has been given a value and has not
                    // received it yet. Only a Linear one is worth following:
                    // the invariant is that every Linear value has exactly one
                    // owner, and a discardable value in flight is owed to nobody.
                    //
                    // Recorded from the operation alone rather than from
                    // whether the consume was accepted, so the set a block
                    // begins with only ever grows and the sweeps settle.
                    if (self.cfg.opPendingFor(op) != ExprId.none and
                        place.isWhole() and
                        self.isLinear(root))
                    {
                        const p: Pending = .{ .place = place, .for_ = self.cfg.opPendingFor(op), .at = at };
                        if (!holds(open.items, p)) try open.append(self.gpa, p);
                    }
                },

                // A copy changes no state: it reads its source and yields
                // something else. What is asked of it is whether it did
                // anything at all.
                .copied => if (report_now) {
                    if (self.cfg.opReading(op)) {
                        try self.report(
                            .o_copy_read,
                            at,
                            "delete the `copy`",
                            "nothing here takes `{s}`, so this copy has no effect",
                            .{try self.nameOf(root)},
                        );
                    } else if (place.isWhole() and
                        !self.isLend(root) and
                        !try self.liveAfter(f, i, op))
                    {
                        try self.report(
                            .o_copy_dead,
                            at,
                            "write the move instead",
                            "`{s}` is not read after this, so this copy has no effect",
                            .{try self.nameOf(root)},
                        );
                    }
                },
            }
        }

        if (report_now and self.cfg.isExit(block_id)) {
            for (f.inouts) |b| {
                const at = self.slotOf(b) orelse continue;
                if (state[at] == .init) continue;
                const tok = self.res.declaringToken(b);
                try self.sink.addErrorFmt(
                    .o_reinit,
                    self.ast.fileOf(tok),
                    self.ast.tokenSpan(tok),
                    "assign it before returning on every path",
                    "`{s}` is moved out and not put back",
                    .{try self.nameOf(b)},
                );
            }
        }
    }

    /// Ends every scope a stretch of the live stack holds.
    ///
    /// Only the bindings tracked at some block are visited, and what that
    /// leaves out cannot be seen. Three things could see it and none does. An
    /// untracked binding is named again only where a loop redeclares it, and
    /// the `let` that does writes the state before anything reads it -- and
    /// writing over a place that owes nothing loses nothing, so that write
    /// reports nothing either. A merge reports a disagreement about a tracked
    /// binding and about no other. And where a value was taken is quoted only
    /// for a place a consume moved, which writes its own.
    ///
    /// Whether a place is read after a `copy` is a fourth reader and asks
    /// something else: it asks the graph where a scope ends, not the lattice
    /// what a binding holds, so it sees every death whatever the binding owes.
    /// Dropping the deaths instead of the visits is what would move
    /// [O-CopyDead], by letting a back edge find a read on a later iteration.
    ///
    /// So a body of `UInt8` locals ends a hundred scopes in constant work,
    /// where visiting each of them would put the graph's quadratic straight
    /// back into every exit.
    fn endScopes(
        self: *Checker,
        op: OpId,
        state: []State,
        moved_at: []ExprId,
        journal: ?*std.ArrayList(Edit),
        report_now: bool,
    ) std.mem.Allocator.Error!void {
        var each = self.dying(op);
        while (each.next()) |b| {
            const slot = self.slotOf(b) orelse continue;
            // [O-Leak] asks what the binding owes. One a `defer` consumes
            // and that owes nothing is tracked for its merges alone.
            if (state[slot] == .init and report_now and self.isLinear(b)) {
                try self.leaks.append(self.gpa, .{ .binding = b, .exit = self.cfg.opAt(op) });
            }
            // Its scope has ended, so it no longer exists. Without this a
            // binding declared inside a loop reaches the head twice -- once
            // uninitialised and once moved -- and the two disagree about a
            // value neither can name.
            // And where it was taken goes with it. A site answers "where did
            // the value in this place go", and there is no longer a place.
            try writeState(
                self.gpa,
                state,
                moved_at,
                journal,
                @intCast(slot),
                .uninit,
                ExprId.none,
            );
        }
    }

    fn consume(
        self: *Checker,
        op: OpId,
        slot: usize,
        state: []State,
        moved_at: []ExprId,
        journal: ?*std.ArrayList(Edit),
        report_now: bool,
    ) std.mem.Allocator.Error!void {
        const place = self.cfg.opPlace(op);
        const at = self.cfg.opAt(op);
        const schedule = self.cfg.opSchedule(op);
        const root = place.root;

        // A `defer` placed this, and on this path the value is already gone.
        // The program wrote one disposal and it happened elsewhere, so the
        // placement is recorded as cancelled and nothing is reported. This is
        // what a runtime drop flag buys; here the lattice already knows, and
        // what it knows is written down for lowering to read.
        //
        // A value that is gone only because [O-Merge] already refused the
        // paths into this join is not cancelled: that disagreement is the one
        // mistake, and a dead schedule would be a second report of it.
        if (schedule != ExprId.none and self.run_is_spent and
            place.isWhole() and state[slot] == .moved)
        {
            if (report_now and !self.fromMerge(moved_at[slot], root)) try self.cancelled.at.put(
                self.gpa,
                .{ .schedule = schedule, .exit = self.cfg.opExit(op) },
                {},
            );
            return;
        }

        if (!place.isWhole()) {
            // There is no partial move: a partially-moved value is a state the
            // language would then have to describe everywhere else.
            if (report_now) try self.report(
                .o_move,
                at,
                "move the whole binding, or `copy` this part out of it",
                "only part of `{s}` is named here",
                .{try self.nameOf(root)},
            );
            return;
        }

        if (state[slot] == .moved) {
            if (report_now) {
                if (at == moved_at[slot]) _ = self.merge_origins.remove(.{ .at = at, .binding = root });
                if (!self.fromMerge(moved_at[slot], root)) try self.reportMoved(at, root, moved_at[slot]);
            }
            return;
        }

        // A lend may not be taken from: whoever lent it still owns it. A
        // `match read` arm's binders are lends for the same reason a `read`
        // parameter is -- the match did not take the scrutinee -- and a lending
        // walk's binder for the same reason again.
        if (self.cfg.isLend(root)) {
            if (report_now) try self.report(
                .o_move,
                at,
                "`copy` it, or use the plain form of the construct, which does take the value",
                "`{s}` is a lend, and this takes it",
                .{try self.nameOf(root)},
            );
            return;
        }

        if (self.res.kindOf(root) == .parameter) {
            if (self.res.parameterConvention(self.ast, root) == .read) {
                if (report_now) try self.report(
                    .o_move,
                    at,
                    "`copy` it, or declare the parameter `sink` to take it",
                    "`{s}` is lent, and this takes it",
                    .{try self.nameOf(root)},
                );
                return;
            }
        }

        // A move inside a loop would run more than once. Stated over the body
        // rather than over the graph: the back edge is not where anyone wrote
        // anything, and a rule whose answer depends on whether a `break` is
        // unconditional is one a reader cannot predict.
        //
        // A pattern's binder is declared where it is bound, like any other
        // name, so it is asked the same question. It was exempt while it was
        // declared nowhere and the exemption stood in for that.
        if (self.cfg.opLoops(op) > self.cfg.declared_in_loops[root.index()]) {
            if (report_now) try self.report(
                .o_loop,
                at,
                "consume it outside the loop, or restructure until it is consumed once",
                "`{s}` is moved inside a loop, so this would run more than once",
                .{try self.nameOf(root)},
            );
            return;
        }

        try writeState(self.gpa, state, moved_at, journal, @intCast(slot), .moved, at);
    }

    fn fromMerge(self: *const Checker, at: ExprId, binding: BindingId) bool {
        return at != .none and self.merge_origins.contains(.{ .at = at, .binding = binding });
    }

    /// Reports a binding tracked at the join whose state the arms of a branch
    /// disagree on.
    ///
    /// Reported at the join because there is nothing to answer there and
    /// because the fix goes there: consume it on the other path too.
    ///
    /// Two predecessors can only disagree where at least one of them differs
    /// from the block that dominates them both, so the slots those edits name
    /// are the whole of what is compared. Everywhere else both still hold what
    /// they inherited, which is one value. They are sorted, because a slot's
    /// position is its binding's and which binding a report names first may not
    /// depend on which operation happened to mention one.
    const MergeAction = enum { mark_origins, report };

    fn checkMerges(
        self: *Checker,
        f: *const Function,
        b: u32,
        roots: []const BindingId,
        preds: *const Predecessors,
        flow: *Flow,
        asked: *std.ArrayList(u32),
        first: *std.ArrayList(State),
        first_at: *std.ArrayList(ExprId),
        action: MergeAction,
    ) std.mem.Allocator.Error!void {
        try flow.windToBase(self.gpa, b);
        const base = flow.openMerge();

        asked.clearRetainingCapacity();
        for (preds.of(b)) |p| {
            if (!flow.computed[p]) continue;
            try flow.wind(self.gpa, p);
            std.debug.assert(flow.path.items.len >= base);
            for (flow.freshFrames()) |q| {
                for (flow.editsOf(q)) |e| try asked.append(self.gpa, e.slot);
            }
        }
        if (asked.items.len == 0) return;

        std.mem.sortUnstable(u32, asked.items, {}, std.sort.asc(u32));
        var kept: usize = 0;
        for (asked.items) |s| {
            if (kept > 0 and asked.items[kept - 1] == s) continue;
            asked.items[kept] = s;
            kept += 1;
        }
        asked.shrinkRetainingCapacity(kept);

        first.clearRetainingCapacity();
        first_at.clearRetainingCapacity();
        for (preds.of(b)) |p| {
            if (!flow.computed[p]) continue;
            try flow.wind(self.gpa, p);
            if (first.items.len == 0) {
                for (asked.items) |s| {
                    try first.append(self.gpa, flow.state[s]);
                    try first_at.append(self.gpa, flow.state_at[s]);
                }
                continue;
            }

            for (asked.items, first.items, first_at.items) |s, *was_slot, *was_at_slot| {
                // A path through a refused construct holds an unknown state,
                // which agrees and disagrees with nothing: it is left out, and
                // every other path is compared with the first known one.
                if (flow.state[s] == .unknown) continue;
                if (was_slot.* == .unknown) {
                    was_slot.* = flow.state[s];
                    was_at_slot.* = flow.state_at[s];
                    continue;
                }
                const was = was_slot.*;
                const was_at = was_at_slot.*;
                if (was == flow.state[s]) continue;
                const binding = roots[s];
                if (!self.isTracked(binding, b)) continue;

                switch (action) {
                    .mark_origins => {
                        if (was_at != .none) try self.merge_origins.put(self.gpa, .{ .at = was_at, .binding = binding }, {});
                        const at = flow.state_at[s];
                        if (at != .none) try self.merge_origins.put(self.gpa, .{ .at = at, .binding = binding }, {});
                    },
                    .report => try self.report(
                        .o_merge,
                        self.cfg.blocks[f.blocks.start + b].at,
                        "consume it on the other path too, or on neither",
                        "the paths here disagree about `{s}`",
                        .{try self.nameOf(binding)},
                    ),
                }
            }
        }
    }

    /// The same fixpoint over a row per block, run beside the trail and
    /// asserted to reach the same answer at every block.
    ///
    /// A corpus differential would only see the programs someone wrote. This
    /// runs on all of those, on their metamorphic rewrites and on every
    /// generated program, and it fails at the first block where the two
    /// disagree rather than at whichever diagnostic happened to move.
    ///
    /// Bounded by the matrix it allocates, which is the cost the trail exists
    /// to remove: past that size the check would spend exactly what the
    /// representation was changed to stop spending. Every case in the corpus is
    /// far below the bound and only a generated body is above it.
    fn agreesWithRows(
        self: *Checker,
        f: *const Function,
        count: usize,
        n: usize,
        order: []const u32,
        flow: *Flow,
    ) std.mem.Allocator.Error!void {
        if (n != 0 and count > (1 << 18) / n) return;

        const entry = try self.gpa.alloc(State, count * n);
        defer self.gpa.free(entry);
        @memset(entry[0..n], .uninit);

        const entry_at = try self.gpa.alloc(ExprId, count * n);
        defer self.gpa.free(entry_at);
        @memset(entry_at[0..n], ExprId.none);

        const reached = try self.gpa.alloc(bool, count);
        defer self.gpa.free(reached);
        @memset(reached, false);
        reached[0] = true;

        const working = try self.gpa.alloc(State, n);
        defer self.gpa.free(working);
        const working_at = try self.gpa.alloc(ExprId, n);
        defer self.gpa.free(working_at);

        const open = try self.gpa.alloc(std.ArrayList(Pending), count);
        defer {
            for (open) |*o| o.deinit(self.gpa);
            self.gpa.free(open);
        }
        @memset(open, .empty);

        var carried: std.ArrayList(Pending) = .empty;
        defer carried.deinit(self.gpa);

        // The independent row oracle has the same lattice and transfer facts
        // as the trail analysis, so the same proof bounds both fixpoints.
        var sweeps = fixpointSweepBudget(count);
        var changed = true;
        while (changed and sweeps > 0) : (sweeps -= 1) {
            changed = false;
            for (order) |b| {
                const i: usize = b;
                if (!reached[i]) continue;
                @memcpy(working, entry[i * n ..][0..n]);
                @memcpy(working_at, entry_at[i * n ..][0..n]);
                carried.clearRetainingCapacity();
                try carried.appendSlice(self.gpa, open[i].items);

                try self.runBlock(f, i, working, working_at, &carried, null, false);

                for (self.cfg.edgesOf(self.cfg.blocks[f.blocks.start + i])) |e| {
                    const to = e.index() - f.blocks.start;
                    const into = entry[to * n ..][0..n];
                    const into_at = entry_at[to * n ..][0..n];
                    if (!reached[to]) {
                        reached[to] = true;
                        @memcpy(into, working);
                        @memcpy(into_at, working_at);
                        changed = true;
                    } else {
                        for (into, working) |*was, now| {
                            const merged = State.join(was.*, now);
                            if (merged != was.*) {
                                was.* = merged;
                                changed = true;
                            }
                        }
                        for (into_at, working_at) |*was, now| {
                            was.* = self.writtenFirst(was.*, now);
                        }
                    }
                    for (carried.items) |p| {
                        if (try self.openTransfer(&open[to], p)) changed = true;
                    }
                }
            }
        }
        std.debug.assert(!changed);

        for (0..count) |i| {
            const b: u32 = @intCast(i);
            std.debug.assert(reached[i] == flow.computed[b]);
            if (!reached[i]) continue;

            try flow.wind(self.gpa, b);
            const body = flow.editsOf(b)[flow.delta[b].join..];
            flow.undoEdits(body);
            for (entry[i * n ..][0..n], entry_at[i * n ..][0..n], 0..) |was, was_at, s| {
                std.debug.assert(flow.state[s] == was);
                std.debug.assert(flow.state_at[s] == was_at);
            }
            flow.applyEdits(body);
        }
    }
};

/// Applies one semantic flow mutation and, when requested, records both sides
/// so the dominator trail can wind through the block in either direction.
fn writeState(
    gpa: std.mem.Allocator,
    state: []State,
    moved_at: []ExprId,
    journal: ?*std.ArrayList(Checker.Edit),
    slot: u32,
    now: State,
    now_at: ExprId,
) std.mem.Allocator.Error!void {
    if (state[slot] == now and moved_at[slot] == now_at) return;
    if (journal) |edits| try edits.append(gpa, .{
        .slot = slot,
        .was = state[slot],
        .now = now,
        .was_at = moved_at[slot],
        .now_at = now_at,
    });
    state[slot] = now;
    moved_at[slot] = now_at;
}

const Interner = @import("../support/interner.zig").Interner;
const Source = @import("../support/source.zig").Source;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const resolveTree = resolve_mod.resolveTree;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;

test "a failed group entry does not suppress sibling generated ownership" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var interner: Interner = .empty;
    var sink = Sink.init(gpa);
    const source: Source = .{ .path = "case.lin", .text =
        \\trait Required {}
        \\trait Rejected { fn run(rejected: Self) -> UInt8 }
        \\trait Checked { fn run(checked: Self) -> UInt8 }
        \\template impl Rejected
        \\where reflect.components: Required
        \\{
        \\    fn run(rejected: Self) -> UInt8 { let _taken = rejected; 0 }
        \\}
        \\template impl Checked {
        \\    fn run(checked: Self) -> UInt8 { let _taken = checked; 0 }
        \\}
        \\@(linear, derive(Rejected, Checked))
        \\struct Box { value: UInt8 }
        \\fn main() -> UInt8 { 0 }
    };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &resolved, &sink);

    try testing.expectEqual(@as(usize, 1), typing.suppressed_generated_bodies.len);
    var cancellations = try checkTree(gpa, &resolved, &typing, &sink);
    defer cancellations.deinit(gpa);

    var derive_errors: usize = 0;
    var move_errors: usize = 0;
    for (sink.items()) |diagnostic| {
        if (diagnostic.code == .t_derive) derive_errors += 1;
        if (diagnostic.code != .o_move) continue;
        move_errors += 1;
        try testing.expect(std.mem.indexOf(u8, diagnostic.message, "`checked`") != null);
        try testing.expect(std.mem.indexOf(u8, diagnostic.message, "`rejected`") == null);
    }
    try testing.expectEqual(@as(usize, 1), derive_errors);
    try testing.expectEqual(@as(usize, 1), move_errors);
}

/// Runs the pass over `text` once per allocation it makes, cutting that
/// allocation and every one after it, and requires each run to either refuse
/// or report.
///
/// `text` must be a program this pass rejects, so "reported nothing" is always
/// the wrong answer and never merely an uninteresting one.
fn everyCutRefusesOrReports(gpa: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const scratch = arena.allocator();

    var interner: Interner = .empty;

    // The program is prepared with an allocator that works: what is under test
    // is this pass, not the passes that hand it their answers.
    //
    // Parsed here rather than loaded, because loading is the driver's and a
    // pass reaching for it closes a cycle: the driver runs this pass. A case
    // is one file with no imports, so what the loader would add is a module
    // graph of one -- which is what the `Tree` entry points already stand for.
    var setup = Sink.init(scratch);
    const source: Source = .{ .path = "case.lin", .text = text };
    const tokens = try tokenize(scratch, &source, .from(0), &setup, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &setup);

    var res = try resolveTree(scratch, &ast, &setup);
    var typing = try typecheckTree(scratch, &res, &setup);

    var cut: usize = 0;
    var refused: usize = 0;
    while (cut < 4096) : (cut += 1) {
        var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = cut });
        var reports = std.heap.ArenaAllocator.init(failing.allocator());
        defer reports.deinit();
        var sink = Sink.init(reports.allocator());

        if (checkTree(failing.allocator(), &res, &typing, &sink)) |returned| {
            var plan = returned;
            plan.deinit(failing.allocator());
            // Returning normally is a claim that the program is safe, and this
            // program is not. Whether the cut fell past the last allocation or
            // on the one the diagnostic needed, the answer must be the same.
            try testing.expect(sink.hasErrors());
            if (cut > failing.alloc_index) break;
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            refused += 1;
        }
    }

    // A pass that allocated nothing would satisfy the loop vacuously.
    try testing.expect(refused > 0);
}

test "fixpoint budget covers reachability every state rise and open transfer" {
    const blocks = 3;
    const rises = [_]State{ .uninit, .unknown, .init, .moved };
    for (rises[0 .. rises.len - 1], rises[1..]) |before, after| {
        try testing.expectEqual(after, State.join(before, after));
        try testing.expectEqual(after, State.join(after, before));
    }
    const state_rises = rises.len - 1;
    var propagation_left: usize = blocks * (1 + state_rises + 1);

    // This is the production and row-oracle budget. The model spends one round
    // per block on reachability, one on each ordered state
    // rise, and one on the open-transfer fact that travels beside the state.
    var sweeps = fixpointSweepBudget(blocks);
    var changed = true;
    while (changed and sweeps > 0) : (sweeps -= 1) {
        propagation_left -= 1;
        changed = propagation_left != 0;
    }
    try testing.expect(!changed);
}

test "edit generation ranges resolve the descriptor arena" {
    try testing.expectEqual(@as(usize, 32), @sizeOf(Checker.EditRange));

    var flow = try Checker.Flow.init(testing.allocator, 1, 2, &.{ 0, 0 });
    defer flow.deinit(testing.allocator);
    try flow.arena(.first).append(testing.allocator, .{
        .slot = 0,
        .was = .uninit,
        .now = .init,
        .was_at = .none,
        .now_at = ExprId.at(1),
    });
    try flow.arena(.second).append(testing.allocator, .{
        .slot = 0,
        .was = .init,
        .now = .moved,
        .was_at = ExprId.at(1),
        .now_at = ExprId.at(2),
    });

    flow.delta[0] = .{ .start = 0, .len = 1, .join = 0, .generation = .first };
    flow.delta[1] = .{ .start = 0, .len = 1, .join = 0, .generation = .second };
    const old = flow.editsOf(0);
    const new = flow.editsOf(1);
    try testing.expectEqual(State.uninit, old[0].was);
    try testing.expectEqual(State.moved, new[0].now);
}

test "repeated edit undo restores the state before the first edit" {
    var flow = try Checker.Flow.init(testing.allocator, 1, 1, &.{0});
    defer flow.deinit(testing.allocator);
    try flow.arena(.first).appendSlice(testing.allocator, &.{
        .{
            .slot = 0,
            .was = .uninit,
            .now = .init,
            .was_at = .none,
            .now_at = ExprId.at(1),
        },
        .{
            .slot = 0,
            .was = .init,
            .now = .moved,
            .was_at = ExprId.at(1),
            .now_at = ExprId.at(2),
        },
    });
    const range: Checker.EditRange = .{ .start = 0, .len = 2, .generation = .first };
    flow.state[0] = .moved;
    flow.state_at[0] = ExprId.at(2);

    flow.undoEdits(flow.editsOfRange(range));

    try testing.expectEqual(State.uninit, flow.state[0]);
    try testing.expectEqual(ExprId.none, flow.state_at[0]);
}

test "edit generation ranges preserve boundary joins and computed empties" {
    var flow = try Checker.Flow.init(testing.allocator, 1, 3, &.{ 0, 0, 0 });
    defer flow.deinit(testing.allocator);
    try flow.arena(.first).append(testing.allocator, .{
        .slot = 0,
        .was = .uninit,
        .now = .init,
        .was_at = .none,
        .now_at = ExprId.at(1),
    });

    flow.delta[0] = .{ .start = 0, .len = 1, .join = 0, .generation = .first };
    flow.delta[1] = .{ .start = 0, .len = 1, .join = 1, .generation = .first };
    flow.delta[2] = .{ .start = 1, .len = 0, .join = 0, .generation = .first };
    flow.computed[0] = true;
    flow.computed[1] = true;
    flow.computed[2] = true;

    const all_body = flow.editsOf(0)[flow.delta[0].join..];
    const no_body = flow.editsOf(1)[flow.delta[1].join..];
    try testing.expectEqual(@as(usize, 1), all_body.len);
    try testing.expectEqual(@as(usize, 0), no_body.len);
    try testing.expect(flow.computed[2]);
    try testing.expectEqual(@as(usize, 0), flow.editsOf(2).len);
}

test "edit generation restatement mutates only the old range" {
    var flow = try Checker.Flow.init(testing.allocator, 1, 1, &.{0});
    defer flow.deinit(testing.allocator);
    try flow.arena(.first).appendSlice(testing.allocator, &.{
        .{
            .slot = 0,
            .was = .uninit,
            .now = .init,
            .was_at = .none,
            .now_at = ExprId.at(1),
        },
        .{
            .slot = 0,
            .was = .init,
            .now = .moved,
            .was_at = ExprId.at(1),
            .now_at = ExprId.at(2),
        },
    });
    try flow.arena(.second).append(testing.allocator, .{
        .slot = 0,
        .was = .uninit,
        .now = .moved,
        .was_at = .none,
        .now_at = ExprId.at(3),
    });
    flow.delta[0] = .{ .start = 0, .len = 2, .generation = .first };
    flow.state[0] = .moved;
    flow.state_at[0] = ExprId.at(4);

    flow.restate(0);

    const old = flow.editsOf(0);
    const candidate = flow.editsOfRange(.{ .start = 0, .len = 1, .generation = .second });
    try testing.expectEqual(State.moved, old[0].was);
    try testing.expectEqual(ExprId.at(4), old[0].was_at);
    try testing.expectEqual(State.init, old[1].was);
    try testing.expectEqual(State.uninit, candidate[0].was);
    try testing.expectEqual(State.moved, flow.state[0]);
    try testing.expectEqual(ExprId.at(4), flow.state_at[0]);
}

test "edit generation offsets survive write arena growth" {
    var flow = try Checker.Flow.init(testing.allocator, 1, 1, &.{0});
    defer flow.deinit(testing.allocator);
    try flow.writeArena().append(testing.allocator, .{
        .slot = 0,
        .was = .uninit,
        .now = .init,
        .was_at = .none,
        .now_at = ExprId.at(1),
    });
    flow.delta[0] = .{ .start = 0, .len = 1, .generation = flow.arenas.write };
    const before = flow.writeArena().capacity;
    for (0..64) |i| try flow.writeArena().append(testing.allocator, .{
        .slot = 0,
        .was = .init,
        .now = .moved,
        .was_at = ExprId.at(1),
        .now_at = ExprId.at(@intCast(i + 2)),
    });

    try testing.expect(flow.writeArena().capacity > before);
    const first = flow.editsOf(0)[0];
    try testing.expectEqual(State.uninit, first.was);
    try testing.expectEqual(State.init, first.now);
    try testing.expectEqual(ExprId.at(1), first.now_at);
}

const EditGenerationFailureObservation = struct {
    candidate_failures: usize = 0,
    descriptor_unchanged: bool = true,
};

fn appendGrowingEditGeneration(
    gpa: std.mem.Allocator,
    flow: *Checker.Flow,
) std.mem.Allocator.Error!Checker.EditRange {
    const start = flow.writeArena().items.len;
    for (0..64) |i| try flow.writeArena().append(gpa, .{
        .slot = 0,
        .was = if (i == 0) .uninit else .init,
        .now = .init,
        .was_at = if (i == 0) .none else ExprId.at(@intCast(i)),
        .now_at = ExprId.at(@intCast(i + 1)),
    });
    return .{
        .start = start,
        .len = flow.writeArena().items.len - start,
        .generation = flow.arenas.write,
    };
}

fn exerciseEditGenerationAllocationFailures(
    gpa: std.mem.Allocator,
    observation: *EditGenerationFailureObservation,
) !void {
    var flow = try Checker.Flow.init(gpa, 1, 1, &.{0});
    defer flow.deinit(gpa);
    try flow.arena(flow.arenas.read).append(gpa, .{
        .slot = 0,
        .was = .uninit,
        .now = .init,
        .was_at = .none,
        .now_at = ExprId.at(1),
    });
    flow.delta[0] = .{ .start = 0, .len = 1, .generation = flow.arenas.read };
    flow.computed[0] = true;
    const old = flow.delta[0];

    const candidate = appendGrowingEditGeneration(gpa, &flow) catch |err| {
        observation.candidate_failures += 1;
        observation.descriptor_unchanged = observation.descriptor_unchanged and
            std.meta.eql(old, flow.delta[0]);
        return err;
    };
    try flow.publishCandidate(gpa, 0, candidate);
    try testing.expectEqual(flow.arenas.write, flow.delta[0].generation);
    try testing.expectEqual(@as(usize, 64), flow.delta[0].len);
}

test "allocation failure leaves an edit generation descriptor unpublished" {
    var observation: EditGenerationFailureObservation = .{};
    try testing.checkAllAllocationFailures(
        testing.allocator,
        exerciseEditGenerationAllocationFailures,
        .{&observation},
    );
    try testing.expect(observation.candidate_failures > 0);
    try testing.expect(observation.descriptor_unchanged);
}

const DeltaPublicationFailureObservation = struct {
    reservation_failures: usize = 0,
    successful_publications: usize = 0,
    old_answer_unchanged: bool = true,
};

fn exerciseLateDeltaPublicationReservation(
    gpa: std.mem.Allocator,
    observation: *DeltaPublicationFailureObservation,
) !void {
    var flow = try Checker.Flow.init(gpa, 1, 2, &.{ 0, 0 });
    defer flow.deinit(gpa);
    flow.computed[0] = true;
    try flow.wind(gpa, 0);

    const start = flow.writeArena().items.len;
    try flow.writeArena().append(gpa, .{
        .slot = 0,
        .was = .uninit,
        .now = .init,
        .was_at = .none,
        .now_at = ExprId.at(1),
    });
    const candidate: Checker.EditRange = .{
        .start = start,
        .len = flow.writeArena().items.len - start,
        .generation = flow.arenas.write,
    };

    // Force the post-winding boundary this regression targets: no path slot
    // remains when publication performs its own reservation.
    try flow.path.shrinkToLen(gpa);
    try testing.expectEqual(flow.path.items.len, flow.path.capacity);
    const old = flow.delta[1];
    const old_computed = flow.computed[1];

    flow.publishCandidate(gpa, 1, candidate) catch |err| {
        observation.reservation_failures += 1;
        observation.old_answer_unchanged = observation.old_answer_unchanged and
            std.meta.eql(old, flow.delta[1]) and
            old_computed == flow.computed[1] and
            !flow.on_path[1] and
            std.mem.eql(u32, &.{0}, flow.path.items);
        return err;
    };

    observation.successful_publications += 1;
    try testing.expectEqualSlices(u32, &.{ 0, 1 }, flow.path.items);
    try testing.expect(flow.on_path[1]);
    try testing.expect(flow.computed[1]);
    try testing.expect(std.meta.eql(candidate, flow.delta[1]));
}

test "late delta publication allocation protects the old answer" {
    var observation: DeltaPublicationFailureObservation = .{};
    try testing.checkAllAllocationFailures(
        testing.allocator,
        exerciseLateDeltaPublicationReservation,
        .{&observation},
    );
    try testing.expect(observation.reservation_failures > 0);
    try testing.expectEqual(@as(usize, 1), observation.successful_publications);
    try testing.expect(observation.old_answer_unchanged);
}

test "edit generation winding reads a mixed-generation back edge" {
    var flow = try Checker.Flow.init(testing.allocator, 2, 3, &.{ 0, 0, 0 });
    defer flow.deinit(testing.allocator);
    try flow.writeArena().append(testing.allocator, .{
        .slot = 0,
        .was = .uninit,
        .now = .init,
        .was_at = .none,
        .now_at = ExprId.at(1),
    });
    try flow.arena(flow.arenas.read).append(testing.allocator, .{
        .slot = 1,
        .was = .uninit,
        .now = .moved,
        .was_at = .none,
        .now_at = ExprId.at(2),
    });
    flow.delta[0] = .{ .start = 0, .len = 1, .generation = flow.arenas.write };
    flow.delta[1] = .{ .start = 0, .len = 0, .generation = flow.arenas.read };
    flow.delta[2] = .{ .start = 0, .len = 1, .generation = flow.arenas.read };
    @memset(flow.computed, true);

    try flow.wind(testing.allocator, 2);

    try testing.expectEqual(State.init, flow.state[0]);
    try testing.expectEqual(State.moved, flow.state[1]);
    try testing.expectEqualSlices(u32, &.{ 0, 2 }, flow.path.items);
}

test "edit generation rotation waits for every computed descriptor" {
    var flow = try Checker.Flow.init(testing.allocator, 0, 2, &.{ 0, 0 });
    defer flow.deinit(testing.allocator);
    flow.computed[0] = true;
    flow.computed[1] = true;
    flow.delta[0].generation = flow.arenas.write;
    flow.delta[1].generation = flow.arenas.read;
    const read = flow.arenas.read;
    const write = flow.arenas.write;

    try testing.expect(!flow.rotateArenas());
    try testing.expectEqual(read, flow.arenas.read);
    try testing.expectEqual(write, flow.arenas.write);

    flow.delta[1].generation = flow.arenas.write;
    try testing.expect(flow.rotateArenas());
    try testing.expectEqual(write, flow.arenas.read);
    try testing.expectEqual(read, flow.arenas.write);
    try testing.expectEqual(write, flow.delta[0].generation);
    try testing.expectEqual(write, flow.delta[1].generation);
}

test "a rejected callable call still accounts for a consuming callee" {
    const prefix =
        \\@linear enum Key { Held(UInt8) }
        \\fn release(sink key: Key) { match key { Held(_) => {} } }
        \\fn identity(value: UInt8) -> UInt8 { value }
        \\fn choose(sink key: Key) -> fn(read value: UInt8) -> UInt8 {
        \\    release(key)
        \\    identity
        \\}
        \\fn probe() -> UInt8 {
        \\    let key = Key.Held(1)
        \\    let first: UInt8 = 2
        \\    let second: UInt8 = 3
        \\    choose(key)(first, second)
        \\}
    ;
    const suffixes = [_][]const u8{
        \\fn main() -> UInt8 { probe() }
        ,
        \\fn main() -> UInt8 {
        \\    let key = Key.Held(1)
        \\    let _ = choose(key)(2, 3)
        \\    release(key)
        \\    0
        \\}
        ,
    };

    for (suffixes, 0..) |suffix, case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try std.mem.concat(gpa, u8, &.{ prefix, suffix });
        var interner: Interner = .empty;
        var sink = Sink.init(gpa);
        const source: Source = .{ .path = "case.lin", .text = text };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var res = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &res, &sink);
        _ = try checkTree(gpa, &res, &typing, &sink);

        var move_count: usize = 0;
        var leak_count: usize = 0;
        for (sink.items()) |diagnostic| {
            if (diagnostic.code == .o_move) move_count += 1;
            if (diagnostic.code == .o_leak) leak_count += 1;
        }
        try testing.expectEqual(@as(usize, if (case == 0) 0 else 1), move_count);
        try testing.expectEqual(@as(usize, 0), leak_count);
    }
}

test "an allocation failure cannot turn a rejected program into an accepted one" {
    // Reporting means allocating, so a sink that cannot allocate used to mean
    // reporting nothing -- and reporting nothing is exactly how this pass says
    // a program is safe. The two ways to be wrong when memory runs out are not
    // equal: refusing to compile is recoverable, and compiling a program that
    // frees a value twice is not.
    const key =
        \\@linear enum Key { Forged(UInt8) }
        \\
        \\fn release(sink k: Key) { match k { Forged(_) => {} } }
        \\
    ;

    // A leak at a scope end, which is gathered during the walk and reported
    // once the function has been walked, rather than through the expression
    // it reached.
    try everyCutRefusesOrReports(testing.allocator, key ++
        \\fn main() -> UInt8 {
        \\    let k = Key.Forged(1);
        \\    0
        \\}
    );

    // A leak at a write, which is reported where the walk meets it. The two
    // routes to the sink are separate code, so one being safe says nothing
    // about the other.
    try everyCutRefusesOrReports(testing.allocator, key ++
        \\fn main() -> UInt8 {
        \\    var k = Key.Forged(1);
        \\    k = Key.Forged(2);
        \\    release(k);
        \\    0
        \\}
    );
}

test "ownership borrow protects its owner until the last observation use" {
    try checkDependencyCases(.observations);
}

test "ownership allocation failure cannot accept an invalidated observation" {
    try everyCutRefusesOrReports(testing.allocator,
        \\fn main() -> UInt8 {
        \\    var owner: UInt8 = 1
        \\    let view = borrow owner
        \\    owner = 2
        \\    *view
        \\}
    );
}

test "ownership result targets isolate borrowed payloads" {
    try checkDependencyCases(.targets);
}

const DependencyGroup = enum { observations, targets };

fn checkDependencyCases(group: DependencyGroup) !void {
    const cases = [_]struct { source: []const u8, refused: bool, certified: bool = false, raw_carrier: bool = false, prelude: bool = false, owner_conflict: bool = false, group: DependencyGroup = .observations, readonly_take: bool = false }{
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\fn make(owner: Owner) -> [borrow Owner; 2] where borrows(owner) {
        \\    [borrow owner, borrow owner]
        \\}
        \\fn main() -> UInt8 {
        \\    var old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    var slots = make(old)
        \\    slots[0] = borrow fresh
        \\    slots[1] = borrow fresh
        \\    old = .{ value = 2 }
        \\    let result = slots
        \\    result[0].value + old.value
        \\}
        , .refused = false, .owner_conflict = false },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\fn make(owner: Owner) -> [borrow Owner; 2] where borrows(owner) {
        \\    [borrow owner, borrow owner]
        \\}
        \\fn main() -> UInt8 {
        \\    var old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    var slots = make(old)
        \\    slots[0] = borrow fresh
        \\    old = .{ value = 2 }
        \\    let result = slots
        \\    result[0].value + old.value
        \\}
        , .refused = true, .owner_conflict = true },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\@copyable struct Pair { left: borrow Owner, right: borrow Owner }
        \\fn replaced(old: Pair, owner: Owner) -> Pair where borrows(.left: owner), carries(.right: old) {
        \\    var result = copy(old)
        \\    result.left = borrow owner
        \\    result
        \\}
        \\fn main() -> UInt8 {
        \\    let old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    let pair: Pair = .{ left = borrow old, right = borrow old }
        \\    let result = replaced(pair, fresh)
        \\    result.left.value
        \\}
        , .refused = false },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\@copyable struct Pair { left: borrow Owner, right: borrow Owner }
        \\fn replaced(old: Pair, owner: Owner) -> Pair where borrows(.left: owner), carries(.right: old) {
        \\    var result = copy(old)
        \\    let _replacement = borrow owner
        \\    result
        \\}
        \\fn main() -> UInt8 {
        \\    let old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    let pair: Pair = .{ left = borrow old, right = borrow old }
        \\    let result = replaced(pair, fresh)
        \\    result.left.value
        \\}
        , .refused = true },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\fn replaced(old: [borrow Owner; 2], owner: Owner) -> [borrow Owner; 2] where borrows(owner) {
        \\    var slots = copy(old)
        \\    slots[0] = borrow owner
        \\    slots
        \\}
        \\fn main() -> UInt8 {
        \\    let old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    let slots = [borrow old, borrow old]
        \\    let result = replaced(slots, fresh)
        \\    result[0].value
        \\}
        , .refused = true },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\fn replaced(old: [borrow Owner; 2], owner: Owner) -> [borrow Owner; 2] where borrows(owner) {
        \\    var slots = copy(old)
        \\    slots[0] = borrow owner
        \\    slots[1] = borrow owner
        \\    slots
        \\}
        \\fn main() -> UInt8 {
        \\    let old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    let slots = [borrow old, borrow old]
        \\    let result = replaced(slots, fresh)
        \\    result[0].value
        \\}
        , .refused = false },
        .{ .source =
        \\let slot: UInt64 = 0
        \\fn replaced(owner: UInt8) -> borrow UInt8 where borrows(owner) {
        \\    let local: UInt8 = 1
        \\    var slots = [borrow local, borrow local]
        \\    slots[slot] = borrow owner
        \\    copy(slots[slot])
        \\}
        \\fn main() -> UInt8 { let owner: UInt8 = 0; let result = replaced(owner); *result }
        , .refused = false, .prelude = false },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\fn replaced(old: [borrow Owner; 2], owner: Owner, choose: Bool) -> borrow Owner where borrows(owner) {
        \\    var slots = copy(old)
        \\    if choose { slots[0] = borrow owner } else { slots[0] = borrow owner }
        \\    copy(slots[0])
        \\}
        \\fn main() -> UInt8 {
        \\    let old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    let slots = [borrow old, borrow old]
        \\    let result = replaced(slots, fresh, true)
        \\    result.value
        \\}
        , .refused = false },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\fn replaced(old: [borrow Owner; 2], owner: Owner, choose: Bool) -> borrow Owner where borrows(owner) {
        \\    var slots = copy(old)
        \\    if choose { slots[0] = borrow owner }
        \\    copy(slots[0])
        \\}
        \\fn main() -> UInt8 {
        \\    let old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    let slots = [borrow old, borrow old]
        \\    let result = replaced(slots, fresh, true)
        \\    result.value
        \\}
        , .refused = true },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\fn replaced(old: [borrow Owner; 2], owner: Owner, index: UInt64) -> borrow Owner where borrows(owner) {
        \\    var slots = copy(old)
        \\    slots[0] = borrow owner; slots[index] = copy(old[0])
        \\    copy(slots[0])
        \\}
        \\fn main() -> UInt8 {
        \\    let old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    let slots = [borrow old, borrow old]
        \\    let result = replaced(slots, fresh, 0)
        \\    result.value
        \\}
        , .refused = true },
        .{ .source =
        \\struct Owner { value: UInt8 }
        \\fn replaced(old: [borrow Owner; 2], owner: Owner) -> borrow Owner where borrows(owner) {
        \\    var slots = copy(old)
        \\    slots[0] = borrow owner
        \\    copy(slots[0])
        \\}
        \\fn main() -> UInt8 {
        \\    let old: Owner = .{ value = 1 }
        \\    let fresh: Owner = .{ value = 0 }
        \\    let slots = [borrow old, borrow old]
        \\    let result = replaced(slots, fresh)
        \\    result.value
        \\}
        , .refused = false },
        .{ .source =
        \\fn keep(owner: UInt8, index: UInt64) -> borrow UInt8 where borrows(owner) {
        \\    let local: UInt8 = 7
        \\    var xs = [borrow local, borrow owner]
        \\    xs[index] = borrow owner
        \\    copy(xs[0])
        \\}
        \\fn main() -> UInt8 { let owner: UInt8 = 8; let view = keep(owner, 0); *view }
        , .refused = true },
        .{ .source =
        \\fn keep(owner: UInt8, index: UInt64) -> borrow UInt8 where borrows(owner) {
        \\    let local: UInt8 = 7
        \\    var xs = [borrow local, borrow local]
        \\    xs[0] = borrow owner
        \\    copy(xs[index])
        \\}
        \\fn main() -> UInt8 { let owner: UInt8 = 8; let view = keep(owner, 0); *view }
        , .refused = true },
        .{ .source =
        \\fn keep(owner: UInt8) -> borrow UInt8 where borrows(owner) {
        \\    let local: UInt8 = 7
        \\    var xs = [[borrow local, borrow local], [borrow local, borrow local]]
        \\    xs[1][0] = borrow owner
        \\    copy(xs[1][0])
        \\}
        \\fn main() -> UInt8 { let owner: UInt8 = 8; let view = keep(owner); *view }
        , .refused = false },
        .{ .source =
        \\@copyable struct Pair { left: borrow UInt8, right: borrow UInt8 }
        \\fn keep(owner: UInt8) -> borrow UInt8 where borrows(owner) {
        \\    let local: UInt8 = 7
        \\    var xs: [Pair; 2] = [.{ left = borrow local, right = borrow local }, .{ left = borrow local, right = borrow local }]
        \\    xs[0].left = borrow owner
        \\    copy(xs[0].left)
        \\}
        \\fn main() -> UInt8 { let owner: UInt8 = 8; let view = keep(owner); *view }
        , .refused = false },
        .{ .source =
        \\fn keep(owner: UInt8, choose: Bool) -> borrow UInt8 where borrows(owner) {
        \\    let local: UInt8 = 7
        \\    var xs = [borrow local, borrow local]
        \\    if choose { xs[0] = borrow owner } else { xs[0] = borrow owner }
        \\    copy(xs[0])
        \\}
        \\fn main() -> UInt8 { let owner: UInt8 = 8; let view = keep(owner, true); *view }
        , .refused = false },
        .{ .source =
        \\fn keep(owner: UInt8, choose: Bool) -> borrow UInt8 where borrows(owner) {
        \\    let local: UInt8 = 7
        \\    var xs = [borrow local, borrow owner]
        \\    if choose { xs[0] = borrow owner }
        \\    copy(xs[0])
        \\}
        \\fn main() -> UInt8 { let owner: UInt8 = 8; let view = keep(owner, true); *view }
        , .refused = true },
        .{ .source =
        \\@copyable struct Entry { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let entry: Entry = .{ value = 7 }
        \\    let saved = *(borrow entry)
        \\    saved.value + entry.value
        \\}
        , .refused = true, .readonly_take = true },
        .{ .source =
        \\@copyable struct Entry { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let entry: Entry = .{ value = 7 }
        \\    let saved = copy(*(borrow entry))
        \\    saved.value + entry.value
        \\}
        , .refused = false },
        .{ .source =
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 7
        \\    let view = borrow number
        \\    let saved = *(borrow view)
        \\    return *saved + *view
        \\}
        , .refused = true, .readonly_take = true },
        .{ .source =
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 7
        \\    let view = borrow number
        \\    let saved = copy(*(borrow view))
        \\    return *saved + *view
        \\}
        , .refused = false },
        .{ .source =
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 7
        \\    let saved = *(borrow number)
        \\    saved + number
        \\}
        , .refused = false },
        .{ .source =
        \\struct Pair[T] { left: T, right: T }
        \\fn fill[T: Copyable](inout pair: Pair[T], value: T) where retains(pair: value) {
        \\    pair = .{ left = copy(value), right = copy(value) }
        \\}
        \\fn fill_fields[T: Copyable](inout pair: Pair[T], value: T) where retains(pair.left: value), retains(pair.right: value) {
        \\    fill(&pair, value)
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    var pair: Pair[borrow UInt8] = .{ left = borrow number, right = borrow number }
        \\    fill_fields(&pair, borrow number)
        \\    return *pair.left + *pair.right
        \\}
        , .refused = false, .group = .targets },
        .{ .source =
        \\struct Pair[T] { left: T, right: T }
        \\fn fill[T: Copyable](inout pair: Pair[T], value: T) where retains(pair: value) {
        \\    pair = .{ left = copy(value), right = copy(value) }
        \\}
        \\fn fill_fields[T: Copyable](inout pair: Pair[T], value: T) where retains(pair.left: value) {
        \\    fill(&pair, value)
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    var pair: Pair[borrow UInt8] = .{ left = borrow number, right = borrow number }
        \\    fill_fields(&pair, borrow number)
        \\    return *pair.left + *pair.right
        \\}
        , .refused = true, .group = .targets },
        .{ .source =
        \\enum Maybe[T] { Some(T), None }
        \\fn wrap[T](sink value: T) -> Maybe[T] where carries(value) { .Some(value) }
        \\fn forward[T](sink value: T) -> Maybe[T] where carries(.Some: value) { wrap(value) }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    match forward(borrow number) { Some(view) => *view, None => 0 }
        \\}
        , .refused = false, .group = .targets },
        .{ .source =
        \\enum Choice[T] { Left(T), Right(T) }
        \\fn wrap[T](sink value: T) -> Choice[T] where carries(value) { .Left(value) }
        \\fn forward[T](sink value: T) -> Choice[T] where carries(.Left: value), carries(.Right: value) { wrap(value) }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    match forward(borrow number) { Left(view) => *view, Right(view) => *view }
        \\}
        , .refused = false, .group = .targets },
        .{ .source =
        \\enum Choice[T] { Left(T), Right(T) }
        \\fn wrap[T](sink value: T) -> Choice[T] where carries(value) { .Left(value) }
        \\fn forward[T](sink value: T) -> Choice[T] where carries(.Left: value) { wrap(value) }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    match forward(borrow number) { Left(view) => *view, Right(view) => *view }
        \\}
        , .refused = true, .group = .targets },
        .{ .source =
        \\enum Maybe[T] { Some(T), None }
        \\fn unwrap[T](sink value: Maybe[T]) -> T where carries(value) {
        \\    match value { Some(value) => value, None => loop {} }
        \\}
        \\fn restore[T](inout storage: Maybe[T]) {
        \\    let value = unwrap(storage)
        \\    storage = .Some(value)
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    var storage = Maybe.Some(borrow number)
        \\    restore(&storage)
        \\    match storage { Some(view) => *view, None => 0 }
        \\}
        , .refused = false, .group = .targets },
        .{ .source =
        \\struct Pair { left: borrow UInt8, right: borrow UInt8 }
        \\fn forward(sink value: Pair) -> Pair where carries(value) { value }
        \\fn swap(inout value: Pair) {
        \\    let saved = forward(value)
        \\    value = .{ left = copy(saved.right), right = copy(saved.left) }
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    var pair: Pair = .{ left = borrow number, right = borrow number }
        \\    swap(&pair)
        \\    return *pair.left + *pair.right
        \\}
        , .refused = true, .group = .targets },
        .{ .source =
        \\@linear struct Item { number: UInt8 }
        \\fn observe(item: Item) -> borrow Item where borrows(item) { borrow item }
        \\fn take(sink item: Item) -> UInt8 { let Item { number } = item; number }
        \\fn main() -> UInt8 {
        \\    let item: Item = .{ number = 1 }
        \\    let first = take(*observe(item))
        \\    first + take(item)
        \\}
        , .refused = true, .readonly_take = true },
        .{ .source =
        \\@linear struct Pool { at: UInt8 }
        \\struct Handle { owner: borrow Pool }
        \\impl Pool {
        \\    fn handle(self: Pool) -> Handle where borrows(self) { .{ owner = borrow self } }
        \\    fn close(sink self: Pool) { let Pool { at: _at } = self }
        \\}
        \\fn close_then_use(handle: Handle, sink pool: Pool) -> UInt8 {
        \\    pool.close()
        \\    handle.owner.at
        \\}
        \\fn main() -> UInt8 {
        \\    let pool: Pool = .{ at = 1 }
        \\    let handle = pool.handle()
        \\    close_then_use(handle, pool)
        \\}
        , .refused = true, .owner_conflict = true },
        .{ .source =
        \\@linear struct Pool { at: UInt8 }
        \\struct Handle { owner: borrow Pool }
        \\impl Pool {
        \\    fn handle(self: Pool) -> Handle where borrows(self) { .{ owner = borrow self } }
        \\    fn close(sink self: Pool) { let Pool { at: _at } = self }
        \\}
        \\fn close_then_use(sink pool: Pool) -> UInt8 {
        \\    let handle = pool.handle()
        \\    pool.close()
        \\    handle.owner.at
        \\}
        \\fn main() -> UInt8 { close_then_use(.{ at = 1 }) }
        , .refused = true, .owner_conflict = true },
        .{ .source =
        \\@linear struct Pool { at: UInt8 }
        \\struct Handle { owner: borrow Pool }
        \\impl Pool {
        \\    fn handle(self: Pool) -> Handle where borrows(self) { .{ owner = borrow self } }
        \\    fn close(sink self: Pool) { let Pool { at: _at } = self }
        \\}
        \\fn relay(sink pool: Pool) -> Pool { pool }
        \\fn main() -> UInt8 {
        \\    let pool: Pool = .{ at = 1 }
        \\    let handle = pool.handle()
        \\    let moved = relay(pool)
        \\    let value = handle.owner.at
        \\    moved.close()
        \\    value
        \\}
        , .refused = true, .owner_conflict = true },
        .{ .source =
        \\@linear struct Pool { at: UInt8 }
        \\struct Handle { owner: borrow Pool }
        \\impl Pool {
        \\    fn handle(self: Pool) -> Handle where borrows(self) { .{ owner = borrow self } }
        \\    fn close(sink self: Pool) { let Pool { at: _at } = self }
        \\}
        \\fn relay(sink pool: Pool) -> Pool { pool }
        \\fn identity(sink handle: Handle) -> Handle where carries(handle) { handle }
        \\fn forward(sink handle: Handle) -> Handle where carries(handle) { identity(handle) }
        \\fn main() -> UInt8 {
        \\    let pool = relay(.{ at = 1 })
        \\    let handle = forward(pool.handle())
        \\    let value = handle.owner.at
        \\    pool.close()
        \\    value
        \\}
        , .refused = false },
        .{ .source =
        \\enum Result[T, E] { Ok(T), Err(E) }
        \\struct Failure { code: UInt8 }
        \\fn observe(number: UInt8) -> Result[borrow UInt8, Failure] where borrows(.Ok: number) {
        \\    .Ok(borrow number)
        \\}
        \\fn outer() -> Result[UInt8, Failure] {
        \\    let number: UInt8 = 1
        \\    let observation = observe(number)?;
        \\    .Ok(*observation)
        \\}
        \\fn main() -> UInt8 { match outer() { Ok(value) => value, Err(error) => error.code } }
        , .refused = false, .group = .targets, .prelude = true },
        .{ .source =
        \\enum Result[T, E] { Ok(T), Err(E) }
        \\fn observe(number: UInt8) -> Result[borrow UInt8, borrow UInt8] where borrows(.Ok: number) {
        \\    .Err(borrow number)
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    match observe(number) { Ok(value) => *value, Err(error) => *error }
        \\}
        , .refused = true, .group = .targets },
        .{ .source =
        \\fn observe(view: borrow UInt8) -> borrow UInt8 where borrows(*view) {
        \\    borrow *view
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    let observation = observe(borrow number)
        \\    return *observation
        \\}
        , .refused = false },
        .{ .source =
        \\fn observe(view: borrow UInt8) -> borrow UInt8 where borrows(*view) {
        \\    borrow *view
        \\}
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let observation = observe(borrow number)
        \\    number = 2
        \\    return *observation
        \\}
        , .refused = true, .owner_conflict = true },
        .{ .source =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let observation = borrow number
        \\    number = 2
        \\    return *observation
        \\}
        , .refused = true },
        .{ .source =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let observation = borrow number
        \\    let first = *observation
        \\    number = 2
        \\    first + number
        \\}
        , .refused = false },
        .{ .source =
        \\struct Pair { left: UInt8, right: UInt8 }
        \\fn main() -> UInt8 {
        \\    var pair: Pair = .{ left = 1, right = 2 }
        \\    let observation = borrow pair.left
        \\    pair.right = 3
        \\    return *observation + pair.right
        \\}
        , .refused = false },
        .{ .source =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let observation = loop { break borrow number }
        \\    number = 2
        \\    return *observation
        \\}
        , .refused = true },
        .{ .source =
        \\struct Views { left: borrow UInt8, right: borrow UInt8 }
        \\fn main() -> UInt8 {
        \\    var left: UInt8 = 1
        \\    let right: UInt8 = 2
        \\    let views: Views = .{ left = borrow left, right = borrow right }
        \\    left = 3
        \\    return *views.right + left
        \\}
        , .refused = false },
        .{ .source =
        \\@copyable struct Holder { view: borrow UInt8 }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    let other: UInt8 = 2
        \\    var owner: Holder = .{ view = borrow number }
        \\    let observation = borrow owner
        \\    let snapshot = copy(*observation)
        \\    owner = .{ view = borrow other }
        \\    return *snapshot.view + *owner.view
        \\}
        , .refused = false },
        .{ .source =
        \\@copyable struct Holder { view: borrow UInt8 }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let owner: Holder = .{ view = borrow number }
        \\    let observation = borrow owner
        \\    let snapshot = copy(*observation)
        \\    number = 2
        \\    return *snapshot.view
        \\}
        , .refused = true },
        .{ .source =
        \\struct Holder { number: UInt8, view: borrow UInt8 }
        \\fn main() -> UInt8 {
        \\    let other: UInt8 = 1
        \\    var owner: Holder = .{ number = 2, view = borrow other }
        \\    owner.view = borrow owner.number
        \\    return *owner.view
        \\}
        , .refused = true },
        .{ .source =
        \\enum Wrapped { Value(borrow UInt8) }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let held = Wrapped.Value(borrow number)
        \\    let observation = match held { Value(v) => v }
        \\    number = 2
        \\    return *observation
        \\}
        , .refused = true },
        .{ .source =
        \\struct Holder { view: borrow UInt8 }
        \\fn replace(inout holder: Holder, source: UInt8) where retains(holder: borrow source) {
        \\    let local = source + 1
        \\    holder.view = borrow local
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    var holder: Holder = .{ view = borrow number }
        \\    replace(&holder, number)
        \\    return *holder.view
        \\}
        , .refused = true },
        .{ .source =
        \\struct Holder { view: borrow UInt8 }
        \\fn replace(inout holder: Holder, source: UInt8) where retains(holder: borrow source) {
        \\    holder.view = borrow source
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    var holder: Holder = .{ view = borrow number }
        \\    replace(&holder, number)
        \\    return *holder.view
        \\}
        , .refused = false },
        .{ .source =
        \\@(opaque, copyable) struct Slice[phantom T] { at: UInt64, len: UInt64 }
        \\extern fn slice_place[T](owner: Slice[T], i: UInt64) -> T where carries(owner)
        \\extern fn argument_span(i: UInt64) -> Slice[UInt8]
        \\extern fn linea_arg_count() -> UInt64
        \\extern fn linea_arg_at(i: UInt64) -> UInt64
        \\extern fn linea_arg_len(i: UInt64) -> UInt64
        \\trait Index[I] { type Elem; proj at(self: Self, i: I) -> Elem where carries(self) }
        \\impl[T] Index[UInt64] for Slice[T] {
        \\    type Elem = T
        \\    proj at(self: Self, i: UInt64) -> T where carries(self) { slice_place(self, i) }
        \\}
        \\fn first(owner: Slice[UInt8]) -> borrow UInt8 where carries(owner) { borrow owner[0] }
        \\fn main() -> UInt8 {
        \\    let _count = linea_arg_count()
        \\    let _at = linea_arg_at(0)
        \\    let _len = linea_arg_len(0)
        \\    let owner = argument_span(0)
        \\    let item = first(owner)
        \\    return *item
        \\}
        , .refused = false, .certified = true },
        .{ .source =
        \\@copyable enum Option[T] { None, Some(T) }
        \\@(opaque, linear) struct Buffer[A] { at: UInt64, len: UInt64, allocated: UInt64, allocator: A }
        \\struct Storage[phantom T, A] { buffer: Option[Buffer[A]], allocator: A, at: UInt64, len: UInt64 }
        \\extern fn slot_put[T,A](inout owner: Storage[T,A], at: UInt64, len: UInt64, i: UInt64, sink v: T) where retains(owner: v)
        \\extern fn slot_take[T,A](inout owner: Storage[T,A], at: UInt64, len: UInt64, i: UInt64) -> T where carries(owner)
        \\fn extract[T,A: Copyable](sink owner: Storage[T,A]) -> Option[Buffer[A]] where carries(.Some: owner) {
        \\    let Storage { buffer: raw, allocator: _, at: _, len: _ } = owner
        \\    raw
        \\}
        \\fn restore[T,A: Copyable](sink raw: Buffer[A]) -> Storage[T,A] where carries(raw) {
        \\    let allocator = copy(raw.allocator)
        \\    let at = raw.at
        \\    let len = raw.len
        \\    return .{ buffer = .Some(raw), allocator, at, len }
        \\}
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    var owner: Storage[borrow UInt8,UInt8] = .{ buffer = .Some(.{ at = 0, len = 8, allocated = 8, allocator = 0 }), allocator = 0, at = 0, len = 8 }
        \\    slot_put(&owner, 0, 8, 0, borrow number)
        \\    let raw = extract(owner)
        \\    var restored: Storage[borrow UInt8,UInt8] = match raw { Some(buffer) => restore(buffer), None => return 0 }
        \\    number = 2
        \\    let item = slot_take(&restored, 0, 8, 0)
        \\    let value = *item
        \\    let Storage { buffer: disposed, allocator: _, at: _, len: _ } = restored
        \\    match disposed {
        \\        Some(buffer) => { let Buffer { at: _, len: _, allocated: _, allocator: _ } = buffer },
        \\        None => {},
        \\    }
        \\    value
        \\}
        , .refused = true, .raw_carrier = true, .owner_conflict = true },
        .{ .source =
        \\@copyable struct Data { view: borrow UInt8 }
        \\trait Duplicate { fn duplicate(self: Self) -> Data where carries(self) }
        \\impl Duplicate for Data {
        \\    fn duplicate(self: Self) -> Data where carries(self) { copy(self) }
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    let other: UInt8 = 2
        \\    var owner: Data = .{ view = borrow number }
        \\    let duplicate = Duplicate.duplicate(borrow owner)
        \\    owner = .{ view = borrow other }
        \\    return *duplicate.view + *owner.view
        \\}
        , .refused = false },
        .{ .source =
        \\trait Observe { fn byte(self: Self) -> borrow UInt8 where borrows(self) }
        \\impl Observe for UInt8 { fn byte(self: Self) -> borrow UInt8 where borrows(self) { borrow self } }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let view = Observe.byte(borrow number)
        \\    number = 2
        \\    return *view
        \\}
        , .refused = true },
        .{ .source =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let items = [borrow number]
        \\    for item in items {
        \\        number = 2
        \\        return *item
        \\    }
        \\    0
        \\}
        , .refused = true },
        .{ .source =
        \\enum Wrapped { Value(UInt8) }
        \\fn first(owner: Wrapped) -> borrow UInt8 where borrows(owner) {
        \\    match read owner { Value(value) => borrow value }
        \\}
        \\fn main() -> UInt8 {
        \\    let owner = Wrapped.Value(1)
        \\    let observation = first(owner)
        \\    return *observation
        \\}
        , .refused = false },
        .{ .source =
        \\enum Result[T, E] { Ok(T), Err(E) }
        \\fn leaked(source: UInt8) -> Result[UInt8, borrow UInt8] where borrows(source) {
        \\    let local = source
        \\    let failed: Result[UInt8, borrow UInt8] = .Err(borrow local)
        \\    let value = failed?;
        \\    .Ok(value)
        \\}
        \\fn main() -> UInt8 {
        \\    let source: UInt8 = 2
        \\    match leaked(source) { Ok(value) => value, Err(view) => *view }
        \\}
        , .refused = true, .prelude = true },
        .{ .source =
        \\@copyable struct Holder { view: borrow UInt8 }
        \\fn observe(owner: Holder) -> borrow Holder where borrows(owner) { borrow owner }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let owner: Holder = .{ view = borrow number }
        \\    let copied = copy(*observe(owner))
        \\    number = 2
        \\    return *copied.view
        \\}
        , .refused = true },
        .{ .source =
        \\@copyable struct Holder { view: borrow UInt8 }
        \\fn observe(owner: Holder) -> borrow Holder where borrows(owner) { borrow owner }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    let other: UInt8 = 2
        \\    var owner: Holder = .{ view = borrow number }
        \\    let copied = copy(*observe(owner))
        \\    owner = .{ view = borrow other }
        \\    return *copied.view + *owner.view
        \\}
        , .refused = false },
        .{ .source =
        \\fn observe(inout owner: UInt8) -> borrow UInt8 where borrows(owner) {
        \\    defer { owner = 2 }
        \\    return borrow owner
        \\}
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let observation = observe(&number)
        \\    return *observation
        \\}
        , .refused = true },
        .{ .source =
        \\struct Holder { number: UInt8 }
        \\fn observe(owner: Holder) -> borrow Holder where borrows(owner) { borrow owner }
        \\fn main() -> UInt8 {
        \\    var owner: Holder = .{ number = 1 }
        \\    let view = borrow observe(owner).number
        \\    owner.number = 2
        \\    return *view
        \\}
        , .refused = true },
    };
    var mismatches: usize = 0;
    for (cases) |case| {
        if (case.group != group) continue;
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "borrow.lin", .text = case.source };
        var interner: Interner = .empty;
        var sink = Sink.init(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        if (case.certified or case.raw_carrier) {
            resolved.modules[0].name = "mem";
            resolved.modules[0].library = true;
            resolved.modules[0].externs = true;
            resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
        }
        if (case.prelude) resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
        var typing = try typecheckTree(gpa, &resolved, &sink);
        if (sink.hasErrors()) {
            std.debug.print("\nFRONTEND {s}\n", .{case.source});
            for (sink.items()) |diagnostic| std.debug.print("{s}\n", .{diagnostic.message});
        }
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        if (case.certified) try testing.expect(typing.carried_places.count() > 0);
        var plan = try checkTree(gpa, &resolved, &typing, &sink);
        defer plan.deinit(gpa);
        if (case.refused != sink.hasErrors()) {
            mismatches += 1;
            std.debug.print("\nSOURCE {s}\n", .{case.source});
            for (sink.items()) |diagnostic| std.debug.print("{s} {s}\n", .{ if (diagnostic.code) |code| @tagName(code) else "none", diagnostic.message });
        }
        if (case.readonly_take) {
            var found = false;
            for (sink.items()) |diagnostic| if (diagnostic.code == .o_move) {
                found = true;
            };
            try testing.expect(found);
        }
        if (case.owner_conflict) {
            var found = false;
            for (sink.items()) |diagnostic| if (diagnostic.code == .o_borrow) {
                found = true;
            };
            try testing.expect(found);
        }
        for (sink.items()) |diagnostic| {
            const expected_code = diagnostic.code == .o_borrow or diagnostic.code == .o_escapes or (case.readonly_take and diagnostic.code == .o_move);
            if (!expected_code) std.debug.print("\nUNEXPECTED {s}\n{s}: {s}\n", .{ case.source, if (diagnostic.code) |code| @tagName(code) else "none", diagnostic.message });
            try testing.expect(expected_code);
        }
    }
    try testing.expectEqual(@as(usize, 0), mismatches);
}

test "ownership hands off ordered schedules including expressions with no tracked operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "schedules.lin", .text =
        \\fn first() {}
        \\fn second() {}
        \\fn main() -> UInt8 {
        \\    defer first()
        \\    {
        \\        defer second()
        \\        defer {}
        \\        return 0
        \\    }
        \\}
    };
    var interner: Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &resolved, &sink);
    var plan = try checkTree(gpa, &resolved, &typing, &sink);
    defer plan.deinit(gpa);
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    var checked_return = false;
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .return_) continue;
        const scheduled = plan.schedulesAt(id);
        try testing.expectEqual(@as(usize, 3), scheduled.len);
        for (scheduled, [_][]const u8{ "{}", "second()", "first()" }) |expression, expected| {
            const span = ast.exprSpan(expression);
            try testing.expectEqualStrings(expected, source.text[span.start..span.end]);
        }
        checked_return = true;
    }
    try testing.expect(checked_return);
    try testing.expectEqual(@as(usize, 0), plan.schedulesAt(ast.declBody(resolved.resolution.entry)).len);
}

test "ownership scratch does not allocate an empty retained plan" {
    var frontend = std.heap.ArenaAllocator.init(testing.allocator);
    defer frontend.deinit();
    const a = frontend.allocator();
    const source: Source = .{ .path = "scratch.lin", .text = "fn main() -> UInt8 { 0 }" };
    var interner: Interner = .empty;
    var sink = Sink.init(a);
    const tokens = try tokenize(a, &source, .from(0), &sink, &interner);
    var ast = try parse(a, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(a, &ast, &sink);
    var typing = try typecheckTree(a, &resolved, &sink);
    try testing.expect(!sink.hasErrors());

    var retained = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var plan = try check(retained.allocator(), testing.allocator, &resolved.expanded, &resolved.resolution, &typing, &sink);
    defer plan.deinit(retained.allocator());
    try testing.expect(!sink.hasErrors());
    try testing.expectEqual(@as(usize, 0), retained.allocated_bytes);
    try testing.expectEqual(@as(usize, 0), plan.expressions.len);
    try testing.expectEqual(@as(usize, 0), plan.by_exit.count());

    for (0..2) |cut| {
        var scratch = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = cut });
        try testing.expectError(error.OutOfMemory, check(retained.allocator(), scratch.allocator(), &resolved.expanded, &resolved.resolution, &typing, &sink));
        try testing.expectEqual(scratch.allocated_bytes, scratch.freed_bytes);
        try testing.expectEqual(@as(usize, 0), retained.allocated_bytes);
    }
}

test "ownership scratch can be released before plans and diagnostics are read" {
    var frontend = std.heap.ArenaAllocator.init(testing.allocator);
    defer frontend.deinit();
    const a = frontend.allocator();
    const source: Source = .{ .path = "scratch.lin", .text =
        \\struct Value { number: UInt8 }
        \\fn main() -> UInt8 {
        \\    defer {}
        \\    let value: Value = .{ number = 1 };
        \\    let _moved = value;
        \\    return value.number
        \\}
    };
    var interner: Interner = .empty;
    var sink = Sink.init(a);
    const tokens = try tokenize(a, &source, .from(0), &sink, &interner);
    var ast = try parse(a, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(a, &ast, &sink);
    var typing = try typecheckTree(a, &resolved, &sink);
    try testing.expect(!sink.hasErrors());

    for (0..2) |cut| {
        var retained = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = cut });
        var scratch = testing.FailingAllocator.init(testing.allocator, .{});
        var failure_sink = Sink.init(a);
        try testing.expectError(error.OutOfMemory, check(retained.allocator(), scratch.allocator(), &resolved.expanded, &resolved.resolution, &typing, &failure_sink));
        try testing.expectEqual(retained.allocated_bytes, retained.freed_bytes);
        try testing.expectEqual(scratch.allocated_bytes, scratch.freed_bytes);
    }

    var plan = blk: {
        var scratch = std.heap.ArenaAllocator.init(testing.allocator);
        defer scratch.deinit();
        break :blk try check(testing.allocator, scratch.allocator(), &resolved.expanded, &resolved.resolution, &typing, &sink);
    };
    defer plan.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), plan.expressions.len);
    try testing.expectEqual(@as(usize, 1), plan.by_exit.count());
    const schedule_span = ast.exprSpan(plan.expressions[0]);
    try testing.expectEqualStrings("{}", source.text[schedule_span.start..schedule_span.end]);
    var found_return = false;
    for (0..ast.exprCount()) |i| {
        const expression = ExprId.at(@intCast(i));
        if (ast.exprTag(expression) != .return_) continue;
        try testing.expectEqualSlices(ExprId, plan.expressions, plan.schedulesAt(expression));
        found_return = true;
    }
    try testing.expect(found_return);
    try testing.expectEqual(@as(u32, 1), sink.error_count);
    const diagnostic = sink.items()[0];
    try testing.expectEqual(.o_move, diagnostic.code);
    try testing.expectEqualStrings("`value` has already been moved", diagnostic.message);
    try testing.expectEqual(@as(usize, 2), diagnostic.labels.len);
    try testing.expectEqualStrings("it was already taken, and a value is taken once", diagnostic.labels[0].message);
    try testing.expectEqualStrings("it was taken here", diagnostic.labels[1].message);
}

test "scalar snapshots report rejected copies without ownership cascades" {
    const Code = @import("../diagnostics/diagnostic.zig").Code;
    const cases = [_]struct { text: []const u8, typed_errors: u32, codes: []const Code }{
        .{ .text =
        \\fn main() -> UInt8 { let number: UInt8 = 7; copy(number) }
        , .typed_errors = 1, .codes = &.{.o_scalar_copy} },
        .{ .text =
        \\fn inspect(number: UInt8) -> UInt8 { number }
        \\fn main() -> UInt8 { let number: UInt8 = 7; inspect(copy(number)) }
        , .typed_errors = 1, .codes = &.{.o_scalar_copy} },
        .{ .text =
        \\struct Held { number: UInt8 }
        \\fn main() -> UInt8 { let held: Held = .{ number = 7 }; let moved = held; let _invalid = copy(held); moved.number }
        , .typed_errors = 1, .codes = &.{ .o_copy, .o_move } },
        .{ .text =
        \\@copyable struct Held { number: UInt8 }
        \\fn main() -> UInt8 { let held: Held = .{ number = 7 }; let copied = copy(held); copied.number }
        , .typed_errors = 0, .codes = &.{.o_copy_dead} },
        .{ .text =
        \\@copyable struct Held { number: UInt8 }
        \\fn inspect(held: Held) -> UInt8 { held.number }
        \\fn main() -> UInt8 { let held: Held = .{ number = 7 }; inspect(copy(held)) }
        , .typed_errors = 0, .codes = &.{.o_copy_read} },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "scalar-copy.lin", .text = case.text };
        var interner: Interner = .empty;
        var sink = Sink.init(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &resolved, &sink);
        try testing.expectEqual(case.typed_errors, sink.error_count);
        var plan = try checkTree(gpa, &resolved, &typing, &sink);
        defer plan.deinit(gpa);
        try testing.expectEqual(case.codes.len, sink.error_count);
        for (case.codes, sink.items()) |code, diagnostic| try testing.expectEqual(code, diagnostic.code.?);
    }
}

test "ownership borrow ignores an invalid assignment destination" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "invalid-field.lin", .text =
        \\struct Holder { view: borrow UInt8 }
        \\fn retain(inout holder: Holder, value: UInt8) where retains(holder.view: borrow value) {
        \\    holder.missing = borrow value
        \\}
        \\fn main() -> UInt8 {
        \\    let original: UInt8 = 1
        \\    let replacement: UInt8 = 2
        \\    var holder: Holder = .{ view = borrow original }
        \\    retain(&holder, replacement)
        \\    return *holder.view
        \\}
    };
    var interner: Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &resolved, &sink);
    try testing.expectEqual(@as(u32, 1), sink.error_count);
    try testing.expectEqual(.t_unknown_field, sink.items()[0].code.?);
    var plan = try checkTree(gpa, &resolved, &typing, &sink);
    defer plan.deinit(gpa);
    if (sink.error_count != 1) for (sink.items()) |diagnostic| {
        std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code.?), diagnostic.message });
    };
    try testing.expectEqual(@as(u32, 1), sink.error_count);
}

test "ownership read captures retain observation dependencies and lend aliases" {
    const Code = @import("../diagnostics/diagnostic.zig").Code;
    const cases = [_]struct { text: []const u8, code: ?Code }{
        .{ .text =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let saved = read [read number] || number
        \\    let result = saved()
        \\    number = 4
        \\    result + number
        \\}
        , .code = null },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let saved = read [read number] || number
        \\    number = 4
        \\    saved()
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let saved = read [read number] || number
        \\    let moved = saved
        \\    number = 4
        \\    moved()
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\fn forward[T](sink value: T) -> T where carries(value) { value }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let saved = read [read number] || number
        \\    let moved = forward(saved)
        \\    number = 4
        \\    moved()
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 3
        \\    let outer = read [read number] || {
        \\        let inner = read [read number] || number
        \\        inner() + inner()
        \\    }
        \\    outer()
        \\}
        , .code = null },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 3 }
        \\    let saved = read [read key] || key.id
        \\    let { id: _ } = key
        \\    saved()
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 3 }
        \\    let saved = read [read key] || {
        \\        let { id } = key
        \\        id
        \\    }
        \\    let result = saved()
        \\    let { id: _ } = key
        \\    result
        \\}
        , .code = .o_move },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let saved = read [read number] || borrow number
        \\    *saved()
        \\}
        , .code = .o_escapes },

        .{ .text =
        \\fn change(inout number: UInt8) -> UInt64 { number = 4; 0 }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let values: [UInt8; 1] = [7]
        \\    let saved = read [read number, read item = values[change(&number)]] || number + item
        \\    saved()
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    let saved = {
        \\        let number: UInt8 = 3
        \\        read [read number] || number
        \\    }
        \\    saved()
        \\}
        , .code = .o_borrow },

        .{ .text =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let saved = read [read number] || number
        \\    let duplicate = copy(saved)
        \\    let result = saved()
        \\    number = 4
        \\    duplicate() + result
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\struct Holder[T] { value: T }
        \\fn hold[T](sink value: T) -> Holder[T] where carries(value) { .{ value = value } }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let saved = read [read number] || number
        \\    let holder = hold(saved)
        \\    let { value: moved } = holder
        \\    number = 4
        \\    moved()
        \\}
        , .code = .o_borrow },

        .{ .text =
        \\fn change(inout number: UInt8) -> UInt8 { number = 4; 0 }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let get = read [read number] |_input: UInt8| number
        \\    get(change(&number))
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\fn change(inout number: UInt8) -> UInt8 { number = 4; 0 }
        \\fn apply[F: fn(read _input: UInt8) -> UInt8](callback: F, input: UInt8) -> UInt8 { callback(input) }
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 3
        \\    let get = read [read number] |_input: UInt8| number
        \\    apply(get, change(&number))
        \\}
        , .code = .o_borrow },
    };
    for (cases, 0..) |case, index| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "read-captures.lin", .text = case.text };
        var interner: Interner = .empty;
        var sink = Sink.init(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &resolved, &sink);
        if (sink.hasErrors()) {
            std.debug.print("read capture case {d} typing failed\n", .{index});
            for (sink.items()) |diagnostic| std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code.?), diagnostic.message });
        }
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        var plan = try checkTree(gpa, &resolved, &typing, &sink);
        defer plan.deinit(gpa);
        var found = false;
        for (sink.items()) |diagnostic| {
            if (diagnostic.code == case.code) found = true;
        }
        if (case.code) |_| {
            if (!found) std.debug.print("read capture case {d} lacked expected diagnostic\n", .{index});
            try testing.expect(found);
        } else try testing.expectEqual(@as(u32, 0), sink.error_count);
    }
}

test "ownership owned captures follow invocation and construction obligations" {
    const Code = @import("../diagnostics/diagnostic.zig").Code;
    const cases = [_]struct { text: []const u8, code: ?Code }{
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 7 }
        \\    let finish = sink [sink key] || { let { id } = key; id }
        \\    finish()
        \\}
        , .code = null },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 7 }
        \\    let finish = [sink key] || { let { id } = key; id }
        \\    finish()
        \\}
        , .code = .o_move },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 7 }
        \\    let inspect = sink [sink key] || key.id
        \\    inspect()
        \\}
        , .code = .o_leak },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    let get = [sink number = UInt8(3)] || number
        \\    get() + get()
        \\}
        , .code = null },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    let finish = sink [sink number = UInt8(3)] || number
        \\    let result = finish()
        \\    result + finish()
        \\}
        , .code = .o_move },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 7 }
        \\    let inspect = [sink key] || key.id
        \\    inspect()
        \\}
        , .code = .o_leak },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn perform(abort: Bool) -> UInt8 {
        \\    let key: Key = .{ id = 7 }
        \\    let finish = sink [sink key, sink extra = { if abort { return 0 }; UInt8(1) }] || {
        \\        let { id } = key
        \\        id + extra
        \\    }
        \\    finish()
        \\}
        \\fn main() -> UInt8 { perform(true) }
        , .code = .o_uncommitted },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 7 }
        \\    let finish = sink [sink key] || { let { id } = key; id }
        \\    let previous = key.id
        \\    finish() + previous
        \\}
        , .code = .o_move },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    let get = [sink number = UInt8(3)] || borrow number
        \\    *get()
        \\}
        , .code = .o_escapes },

        .{ .text =
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 3
        \\    var next = inout [number, sink count = UInt8(0)] || { count += 1; number + count }
        \\    let first = &next()
        \\    first + &next()
        \\}
        , .code = null },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 7 }
        \\    var take = inout [sink key] || { let { id } = key; id }
        \\    &take()
        \\}
        , .code = .o_reinit },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    var next = inout [sink count = UInt8(0)] || { count += 1; count }
        \\    let view = borrow next
        \\    let first = &next()
        \\    var snapshot = copy(*view)
        \\    first + &snapshot()
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    let first: UInt8 = 1
        \\    var store = inout [sink held = borrow first] |replacement: borrow UInt8| { held = copy(replacement) }
        \\    let second: UInt8 = 2
        \\    &store(borrow second)
        \\    0
        \\}
        , .code = .o_escapes },

        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    var make = inout [sink count = UInt8(0)] || { count += 1; let result: Key = .{ id = count }; result }
        \\    let { id } = &make()
        \\    id
        \\}
        , .code = null },
        .{ .text =
        \\@linear struct Key { id: UInt8 }
        \\fn main() -> UInt8 {
        \\    let key: Key = .{ id = 7 }
        \\    let inspect = [sink key] || key.id
        \\    let { key: recovered } = inspect.into_captures()
        \\    let { id } = recovered
        \\    id
        \\}
        , .code = null },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    var left: UInt8 = 1
        \\    let right: UInt8 = 2
        \\    let sum = [left, right] || left + right
        \\    let { left: before, right: after } = sum.into_captures()
        \\    let first = *before
        \\    left = 3
        \\    first + *after + left
        \\}
        , .code = null },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    var number: UInt8 = 1
        \\    let read_number = [number] || number
        \\    let { number: observation } = read_number.into_captures()
        \\    number = 2
        \\    *observation + number
        \\}
        , .code = .o_borrow },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 1
        \\    let read_number = [number] || number
        \\    let { number: observation } = read_number.into_captures()
        \\    *observation + read_number()
        \\}
        , .code = .o_move },
        .{ .text =
        \\fn main() -> UInt8 {
        \\    let get = || UInt8(1)
        \\    let {} = get.into_captures()
        \\    0
        \\}
        , .code = null },
    };
    for (cases, 0..) |case, index| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "owned-captures.lin", .text = case.text };
        var interner: Interner = .empty;
        var sink = Sink.init(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &resolved, &sink);
        if (sink.hasErrors()) {
            std.debug.print("owned capture case {d} typing failed\n", .{index});
            for (sink.items()) |diagnostic| std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code.?), diagnostic.message });
        }
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        var plan = try checkTree(gpa, &resolved, &typing, &sink);
        defer plan.deinit(gpa);
        var found = false;
        for (sink.items()) |diagnostic| {
            if (diagnostic.code == case.code) found = true;
        }
        if (case.code) |_| {
            if (!found) std.debug.print("owned capture case {d} lacked expected diagnostic\n", .{index});
            try testing.expect(found);
        } else try testing.expectEqual(@as(u32, 0), sink.error_count);
    }
}

fn checkIndexedObservationEscape(comptime spelling: enum { direct, handwritten, delegated }, comptime local: bool, comptime overwrite: enum { none, other, sole, same }) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const declaration = switch (spelling) {
        .direct => "",
        .handwritten => "impl Index[UInt64] for Board { type Elem = borrow UInt8; proj at(inout self: Self, i: UInt64) -> borrow UInt8 where carries(self) { self.values[i] } }\n",
        .delegated => "impl Index[UInt64] for Board via values\n",
    };
    const selected = if (spelling == .direct) "board.values[0]" else "board[0]";
    const trait = if (spelling == .direct) "" else "trait Index[I] { type Elem; proj at(inout self: Self, i: I) -> Elem where carries(self) }\n";
    const replaced = if (spelling == .direct) "board.values[1]" else "board[1]";
    const text = trait ++ (if (overwrite == .sole or overwrite == .same)
        "struct Board { values: [borrow UInt8; " ++ (if (overwrite == .sole) "1" else "2") ++ "] }\n" ++ declaration ++
            "fn escaped(owner: UInt8) -> borrow UInt8 where borrows(owner) { " ++
            "let local: UInt8 = 7; var board: Board = .{ values = [borrow local" ++ (if (overwrite == .sole) "" else ", borrow local") ++ "] }; " ++ selected ++ " = borrow owner; copy(" ++ selected ++ ") }\n" ++
            "fn main() -> UInt8 { let first: UInt8 = 8; let saved = escaped(first); *saved }"
    else if (overwrite == .other)
        "struct Board { values: [borrow UInt8; 2] }\n" ++ declaration ++
            "fn escaped(owner: UInt8) -> borrow UInt8 where borrows(owner) { " ++
            (if (local) "let local: UInt8 = 7; " else "") ++
            "var board: Board = .{ values = [borrow " ++ (if (local) "local" else "owner") ++ ", borrow owner] }; " ++ replaced ++ " = borrow owner; copy(" ++ selected ++ ") }\n" ++
            "fn main() -> UInt8 { let first: UInt8 = 8; let saved = escaped(first); *saved }"
    else if (local)
        "struct Board { values: [borrow UInt8; 1] }\n" ++ declaration ++
            "fn escaped() -> borrow UInt8 { let local: UInt8 = 7; let board: Board = .{ values = [borrow local] }; copy(" ++ selected ++ ") }\n" ++
            "fn main() -> UInt8 { let saved = escaped(); *saved }"
    else
        "struct Board { values: [borrow UInt8; 1], spare: borrow UInt8 }\n" ++ declaration ++
            "fn escaped(owner: UInt8, other: UInt8) -> borrow UInt8 where borrows(owner) { let board: Board = .{ values = [borrow owner], spare = borrow other }; copy(" ++ selected ++ ") }\n" ++
            "fn main() -> UInt8 { let first: UInt8 = 7; let second: UInt8 = 8; let saved = escaped(first, second); *saved }");
    const source: Source = .{ .path = "escape.lin", .text = text };
    var names: Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
    var typing = try typecheckTree(gpa, &resolved, &sink);
    try testing.expect(!sink.hasErrors());
    var plan = try checkTree(gpa, &resolved, &typing, &sink);
    defer plan.deinit(gpa);
    var escapes = false;
    for (sink.items()) |diagnostic| {
        if (diagnostic.code == .o_escapes) escapes = true;
    }
    try testing.expectEqual(local and overwrite != .sole and overwrite != .same, escapes);
    if (!local or overwrite == .sole or overwrite == .same) try testing.expect(!sink.hasErrors());
}

test "indexed observation escape through a direct field is rejected" {
    try checkIndexedObservationEscape(.direct, true, .none);
}

test "indexed observation escape through a handwritten projection is rejected" {
    try checkIndexedObservationEscape(.handwritten, true, .none);
}

test "indexed observation escape through a delegated projection is rejected" {
    try checkIndexedObservationEscape(.delegated, true, .none);
}

test "indexed observation escape preserves disjoint external owner contracts" {
    try checkIndexedObservationEscape(.direct, false, .none);
    try checkIndexedObservationEscape(.handwritten, false, .none);
    try checkIndexedObservationEscape(.delegated, false, .none);
}

test "call result contracts preserve every distinct source and duplicate clauses" {
    for ([_]bool{ false, true }) |omit_second| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try std.mem.concat(gpa, u8, &.{
            "struct Pair { first: borrow UInt8, second: borrow UInt8 }\n",
            "fn pair(a: borrow UInt8, b: borrow UInt8) -> Pair where carries(a, b, a) { .{ first = copy(a), second = copy(b) } }\n",
            "fn forward(a: borrow UInt8, b: borrow UInt8) -> Pair where carries(",
            if (omit_second) "a" else "a, b",
            ") { pair(a, b) }\n",
            "fn main() -> UInt8 { let a: UInt8 = 3; let b: UInt8 = 4; let result = forward(borrow a, borrow b); *result.first + *result.second }\n",
        });
        const source: Source = .{ .path = "contract-sources.lin", .text = text };
        var names: Interner = .empty;
        var sink = Sink.init(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
        var typing = try typecheckTree(gpa, &resolved, &sink);
        try testing.expect(!sink.hasErrors());
        var plan = try checkTree(gpa, &resolved, &typing, &sink);
        defer plan.deinit(gpa);
        try testing.expectEqual(omit_second, sink.hasErrors());
        if (omit_second) for (sink.items()) |diagnostic| {
            try testing.expectEqual(.o_escapes, diagnostic.code.?);
        };
    }
}

fn checkDeferredIndexedObservationEscape(comptime local: bool, comptime generic_call: enum { none, delegated, bound }, comptime assignment: bool) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const header =
        \\trait Index[I] { type Elem; proj at(inout self: Self, i: I) -> Elem where carries(self) }
        \\struct Inner { values: [borrow UInt8; 1] }
        \\impl Index[UInt64] for Inner {
        \\    type Elem = borrow UInt8
        \\    proj at(inout self: Self, i: UInt64) -> borrow UInt8 where carries(self) { self.values[i] }
        \\}
        \\struct Wrapper[C: Index[UInt64]] { inner: C, spare: borrow UInt8 }
        \\impl[C: Index[UInt64]] Index[UInt64] for Wrapper[C] via inner
        \\
    ;
    const helper = switch (generic_call) {
        .delegated => "fn selected[C: Index[UInt64]](wrapper: Wrapper[C]) -> C.Elem where C.Elem: Copyable, carries(wrapper.inner) { copy(wrapper[0]) }\n",
        .bound => "fn selected[C: Index[UInt64]](container: C) -> C.Elem where C.Elem: Copyable, carries(container) { copy(container[0]) }\n",
        .none => "",
    };
    const selection = switch (generic_call) {
        .delegated => "selected(wrapper)",
        .bound => "selected(wrapper.inner)",
        .none => "copy(wrapper[0])",
    };
    const body = if (assignment)
        "fn escaped(owner: UInt8, other: UInt8) -> borrow UInt8 where borrows(owner) { " ++
            (if (local) "let local: UInt8 = 7; " else "") ++
            "var wrapper: Wrapper[Inner] = .{ inner = .{ values = [borrow owner] }, spare = borrow other }; wrapper[0] = borrow " ++
            (if (local) "local" else "owner") ++ "; copy(wrapper.inner.values[0]) }\n" ++
            "fn main() -> UInt8 { let first: UInt8 = 7; let second: UInt8 = 8; let saved = escaped(first, second); *saved }"
    else if (local)
        "fn escaped() -> borrow UInt8 { let local: UInt8 = 7; let wrapper: Wrapper[Inner] = .{ inner = .{ values = [borrow local] }, spare = borrow local }; " ++ selection ++ " }\n" ++
            "fn main() -> UInt8 { let saved = escaped(); *saved }"
    else
        "fn escaped(owner: UInt8, other: UInt8) -> borrow UInt8 where borrows(owner) { let wrapper: Wrapper[Inner] = .{ inner = .{ values = [borrow owner] }, spare = borrow other }; " ++ selection ++ " }\n" ++
            "fn main() -> UInt8 { let first: UInt8 = 7; let second: UInt8 = 8; let saved = escaped(first, second); *saved }";
    const source: Source = .{ .path = "deferred-escape.lin", .text = header ++ helper ++ body };
    var names: Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
    var typing = try typecheckTree(gpa, &resolved, &sink);
    try testing.expect(!sink.hasErrors());
    var plan = try checkTree(gpa, &resolved, &typing, &sink);
    defer plan.deinit(gpa);
    var escapes = false;
    for (sink.items()) |diagnostic| if (diagnostic.code == .o_escapes) {
        escapes = true;
    };
    try testing.expectEqual(local, escapes);
    if (!local) try testing.expect(!sink.hasErrors());
}

test "indexed observation escape through deferred delegation is rejected" {
    try checkDeferredIndexedObservationEscape(true, .none, false);
}

test "indexed observation escape through deferred delegation keeps disjoint owners" {
    try checkDeferredIndexedObservationEscape(false, .none, false);
}

test "indexed observation escape follows a generic delegated field contract" {
    try checkDeferredIndexedObservationEscape(true, .delegated, false);
    try checkDeferredIndexedObservationEscape(false, .delegated, false);
}

test "indexed observation escape follows writes through deferred delegation" {
    try checkDeferredIndexedObservationEscape(true, .none, true);
}

test "indexed observation escape permits external writes through deferred delegation" {
    try checkDeferredIndexedObservationEscape(false, .none, true);
}

test "indexed observation escape retains other elements after a direct write" {
    try checkIndexedObservationEscape(.direct, true, .other);
}

test "indexed observation escape retains other elements after a handwritten write" {
    try checkIndexedObservationEscape(.handwritten, true, .other);
}

test "indexed observation escape retains other elements after a delegated write" {
    try checkIndexedObservationEscape(.delegated, true, .other);
}

test "indexed observation escape permits external owners after element writes" {
    try checkIndexedObservationEscape(.direct, false, .other);
    try checkIndexedObservationEscape(.handwritten, false, .other);
    try checkIndexedObservationEscape(.delegated, false, .other);
}

test "indexed observation escape follows a direct bound indexing contract" {
    try checkDeferredIndexedObservationEscape(true, .bound, false);
    try checkDeferredIndexedObservationEscape(false, .bound, false);
}

fn checkTraversalObservationEscape(comptime spelling: enum { direct, handwritten, delegated }, comptime local: bool) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const protocol = if (spelling == .direct) "" else "trait Index[I] { type Elem; proj at(inout self: Self, i: I) -> Elem where carries(self) }\n" ++
        "trait Iterator { type Item }\n" ++
        "pub struct Range[T] { lo: T, hi: T, inclusive: Bool }\n" ++
        "impl[T] Iterator for Range[T] { type Item = T }\n";
    const implementation = switch (spelling) {
        .direct => "",
        .handwritten => "impl Index[UInt64] for Board { type Elem = borrow UInt8; proj at(inout self: Self, i: UInt64) -> borrow UInt8 where carries(self) { self.values[i] } }\nimpl Board { trav positions = UInt64(0)..UInt64(1) }\n",
        .delegated => "impl Index[UInt64] for Board via values\nimpl Board { trav positions via values }\n",
    };
    const walked = if (spelling == .direct) "board.values" else "board";
    const source: Source = .{ .path = "traversal-escape.lin", .text = protocol ++
        "enum Option[T] { None, Some(T) }\nstruct Board { values: [borrow UInt8; 1] }\n" ++ implementation ++
        (if (local)
            "fn escaped() -> Option[borrow UInt8] { let owner: UInt8 = 7; "
        else
            "fn escaped(owner: UInt8) -> Option[borrow UInt8] where borrows(owner) { ") ++
        "let board: Board = .{ values = [borrow owner] }; for read item in " ++ walked ++ " { break copy(item) } }\n" ++
        (if (local)
            "fn main() -> UInt8 { match escaped() { None => 0, Some(item) => *item } }"
        else
            "fn main() -> UInt8 { let owner: UInt8 = 7; match escaped(owner) { None => 0, Some(item) => *item } }") };
    var names: Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
    var typing = try typecheckTree(gpa, &resolved, &sink);
    if (sink.hasErrors()) for (sink.items()) |diagnostic| std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code.?), diagnostic.message });
    try testing.expect(!sink.hasErrors());
    var plan = try checkTree(gpa, &resolved, &typing, &sink);
    defer plan.deinit(gpa);
    var escapes = false;
    for (sink.items()) |diagnostic| {
        if (diagnostic.code == .o_escapes) escapes = true;
    }
    try testing.expectEqual(local, escapes);
    if (!local) try testing.expect(!sink.hasErrors());
}

test "traversal observation escape follows a direct array" {
    try checkTraversalObservationEscape(.direct, true);
    try checkTraversalObservationEscape(.direct, false);
}

test "traversal observation escape follows a handwritten projection" {
    try checkTraversalObservationEscape(.handwritten, true);
    try checkTraversalObservationEscape(.handwritten, false);
}

test "traversal observation escape follows a delegated projection" {
    try checkTraversalObservationEscape(.delegated, true);
    try checkTraversalObservationEscape(.delegated, false);
}

test "indexed observation escape forgets a replaced sole element" {
    try checkIndexedObservationEscape(.direct, true, .sole);
    try checkIndexedObservationEscape(.handwritten, true, .sole);
    try checkIndexedObservationEscape(.delegated, true, .sole);
}

test "indexed observation escape forgets only the replaced known element" {
    try checkIndexedObservationEscape(.direct, true, .same);
    try checkIndexedObservationEscape(.handwritten, true, .same);
    try checkIndexedObservationEscape(.delegated, true, .same);
}
