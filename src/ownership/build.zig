const std = @import("std");
const testing = std.testing;

const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const ExprId = node.ExprId;
const StmtId = node.StmtId;
const DeclId = node.DeclId;
const program_mod = @import("../syntax/program.zig");
const types_mod = @import("../sema/types.zig");
const Typing = types_mod.Typing;
const CallIndex = types_mod.CallIndex;
const typecheck = @import("../sema/typecheck.zig").typecheck;
const isCatchAll = @import("../sema/typecheck.zig").isCatchAll;
const postfixSelection = @import("../sema/typecheck.zig").postfixSelection;
const isPostfixCallee = @import("../sema/typecheck.zig").isPostfixCallee;
const fieldBase = @import("../sema/typecheck.zig").fieldBase;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const resolve_mod = @import("../sema/resolve.zig");
const BindingId = resolve_mod.BindingId;
const Resolution = resolve_mod.Resolution;
const cfg_mod = @import("cfg.zig");
const StringId = @import("../support/interner.zig").StringId;
const Cfg = cfg_mod.Cfg;
const Block = cfg_mod.Block;
const BlockId = cfg_mod.BlockId;
const Op = cfg_mod.Op;
const OpId = cfg_mod.OpId;
const OpList = cfg_mod.OpList;
const OpRange = cfg_mod.OpRange;
const LoopDepth = cfg_mod.LoopDepth;
const Place = cfg_mod.Place;
const Position = cfg_mod.Position;
const Function = cfg_mod.Function;
const Scope = cfg_mod.Scope;
const ScopeId = cfg_mod.ScopeId;
const BindingBits = cfg_mod.BindingBits;
const BlockBits = cfg_mod.BlockBits;

/// Builds the graph the ownership rules are checked over.
///
/// Control flow is constructed here a second time, from the same tree MIR is
/// lowered from, by a second piece of code that must agree with it about what
/// a loop is. That cost is real and is the price of a pass that says *which
/// name* on *which path*: MIR knows the paths and has forgotten the names.
pub fn build(
    gpa: std.mem.Allocator,
    program: *const ExpandedProgram,
    res: *const Resolution,
    typing: *const Typing,
) std.mem.Allocator.Error!Cfg {
    return buildRemaining(gpa, program, res, typing, null);
}

/// Builds only bodies not already checked with these exact semantic answers.
/// Retained declaration IDs are in this program's expanded domain.
pub fn buildRemaining(
    gpa: std.mem.Allocator,
    program: *const ExpandedProgram,
    res: *const Resolution,
    typing: *const Typing,
    retained: ?*const std.AutoHashMapUnmanaged(DeclId, void),
) std.mem.Allocator.Error!Cfg {
    const depths = try gpa.alloc(LoopDepth, res.bindingCount());
    errdefer gpa.free(depths);
    @memset(depths, 0);

    var lends = try BindingBits.initEmpty(gpa, res.bindingCount());
    errdefer lends.deinit(gpa);
    var lasting_lends = try BindingBits.initEmpty(gpa, res.bindingCount());
    errdefer lasting_lends.deinit(gpa);

    const scope_of = try gpa.alloc(ScopeId, res.bindingCount());
    errdefer gpa.free(scope_of);
    @memset(scope_of, ScopeId.none);

    // The checker freezes the site index with the records it names.
    const calls = &typing.call_index;

    var scratch_written = if (std.debug.runtime_safety) try BindingBits.initEmpty(gpa, res.bindingCount()) else {};
    defer if (std.debug.runtime_safety) scratch_written.deinit(gpa);

    var b: Builder = .{
        .gpa = gpa,
        .ast = &program.ast,
        .res = res,
        .typing = typing,
        .calls = calls,
        .declared_in_loops = depths,
        .lends = &lends,
        .lasting_lends = &lasting_lends,
        .scope_of = scope_of,
        .scratch_written = if (std.debug.runtime_safety) &scratch_written else {},
    };
    defer b.deinit();

    // The declarations whose bodies the loop below walks. A closure is
    // decided with the body it is written in, so the closure loop reads this
    // rather than repeating why a body is skipped: a template member, a
    // generated body a failed requirement suppressed, a retained body, a
    // declaration with no body.
    var walked = try std.DynamicBitSetUnmanaged.initEmpty(gpa, program.ast.declCount());
    defer walked.deinit(gpa);

    var suppressed_at: usize = 0;
    for (program.modules, 0..) |_, module_index| {
        for (program.declsOf(program_mod.ModuleId.from(module_index))) |d| {
            if (suppressed_at < typing.suppressed_generated_bodies.len and
                typing.suppressed_generated_bodies[suppressed_at] == d)
            {
                std.debug.assert(program.ast.declTag(d) == .function);
                std.debug.assert(program.ast.declBody(d) != ExprId.none);
                std.debug.assert(program.originOf(d) != null);
                suppressed_at += 1;
                continue;
            }
            if (retained) |checked| if (checked.contains(d)) continue;
            const body = switch (program.ast.declTag(d)) {
                .function => program.ast.declBody(d),
                .traversal_ => program.ast.declInit(d),
                else => continue,
            };
            if (body == ExprId.none) continue;
            walked.set(d.index());
            try b.function(d, body);
        }
    }
    std.debug.assert(suppressed_at == typing.suppressed_generated_bodies.len);

    for (typing.closures, 0..) |closure, i| {
        // A closure the checker never reached records no declaration.
        if (closure.enclosing == .none or !walked.isSet(closure.enclosing.index())) continue;
        const id: resolve_mod.ClosureId = .at(@intCast(i));
        // A closure written inside a refused one is met by no walk, so its
        // uncaptured name is decided here.
        if (res.freeReferenceOf(id) != ExprId.none) _ = try b.uncapturedName(id);
        if (b.refused(res.closures.exprOf(id))) continue;
        try b.closure(id, closure);
    }

    if (std.debug.runtime_safety) {
        // A scratch walk writes `scope_of`, `declared_in_loops` and the lend
        // tables for the bindings its body declares, and what it wrote is
        // sound only while no operation kept in the graph is rooted in one of
        // them: every reader of those entries reaches them through such an
        // operation.
        for (b.ops.items(.place)) |place| {
            if (place.root != .none) std.debug.assert(!scratch_written.get(place.root));
        }
    }

    try b.flattenEdges();
    b.closeScopes();

    // Handed over one at a time rather than as struct fields, because a
    // failure part-way through leaves the ones already taken owned by nobody:
    // the builder has released them and the graph does not exist yet.
    const functions = try b.functions.toOwnedSlice(gpa);
    errdefer {
        for (functions) |*f| f.deinitOne(gpa);
        gpa.free(functions);
    }
    const blocks = try b.blocks.toOwnedSlice(gpa);
    errdefer gpa.free(blocks);
    var exits = try BlockBits.initEmpty(gpa, blocks.len);
    errdefer exits.deinit(gpa);
    for (b.exit_blocks.items) |block| exits.set(block, true);
    var ops = b.ops.toOwnedSlice();
    errdefer ops.deinit(gpa);
    const scopes = try b.scopes.toOwnedSlice(gpa);
    errdefer gpa.free(scopes);
    const edges = try b.edges.toOwnedSlice(gpa);
    errdefer gpa.free(edges);
    const placements = try b.placements.toOwnedSlice(gpa);
    errdefer gpa.free(placements);
    const uncaptured = try b.uncaptured.toOwnedSlice(gpa);
    errdefer gpa.free(uncaptured);

    return .{
        .functions = functions,
        .blocks = blocks,
        .ops = ops,
        .edges = edges,
        .exits = exits.freeze(),
        .declared_in_loops = depths,
        .lends = lends.freeze(),
        .lasting_lends = lasting_lends.freeze(),
        .scopes = scopes,
        .scope_of = scope_of,
        .placements = placements,
        .temporary_statements = b.temporary_statements.move(),
        .static_reads = b.static_reads.move(),
        .uncaptured = uncaptured,
    };
}

const Builder = struct {
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    /// Read for one question: what a call takes. A postfix call's receiver is
    /// an argument the tree does not hold, and a pass that walked the written
    /// ones alone would never see the value the call is about -- so it could
    /// report neither a move through it nor a leak of it.
    typing: *const Typing,
    /// Where each call site's records sit in the checker's tables, which is
    /// how the question above is asked in one step rather than by a scan.
    calls: *const CallIndex,
    declared_in_loops: []LoopDepth,
    lends: *BindingBits,
    lasting_lends: *BindingBits,
    /// Which scope each binding holds, by `BindingId`. A binding is declared
    /// once, so it is pushed once and the node it is given is its own.
    scope_of: []ScopeId,

    functions: std.ArrayList(Function) = .empty,
    blocks: std.ArrayList(Block) = .empty,
    exit_blocks: std.ArrayList(BlockId) = .empty,
    ops: OpList = .empty,
    edges: std.ArrayList(BlockId) = .empty,

    /// Where operations are appended. Control flow moves it, so every emit
    /// site would otherwise have to thread it.
    at: BlockId = .none,
    /// The blocks a `break` and a `continue` jump to, innermost last.
    loops: std.ArrayList(LoopFrame) = .empty,
    /// The scopes that have not ended yet, innermost last, so a scope exit
    /// knows what dies there.
    ///
    /// Each entry is a node in `scopes`, so a mark into this stack and the top
    /// of it together name a stretch of the tree -- which is what a scope exit
    /// records instead of one operation per binding in the stretch.
    live: std.ArrayList(ScopeId) = .empty,
    /// Every stack the walk has stood on, as one tree.
    scopes: std.ArrayList(Scope) = .empty,
    /// Which schedule the walk is emitting, and at which exit, so the
    /// operations it produces carry both and the checker can tell a written
    /// consume from a placed one -- and say which placement it cancelled.
    placing: struct { schedule: ExprId = ExprId.none, exit: ExprId = ExprId.none } = .{},
    /// Expressions a `defer` scheduled, innermost scope last, so an exit knows
    /// what runs there. Carried the way `live` is and marked the same way: a
    /// scope records where its own run begins and walks back to it.
    scheduled: std.ArrayList(ExprId) = .empty,
    placements: std.ArrayList(cfg_mod.Placement) = .empty,
    /// Scratch for `pathOf`, which collects a path's indexes before emitting
    /// them in the order they run. On the builder rather than the stack
    /// because a path may nest and the walk is recursive.
    indexes: std.ArrayList(ExprId) = .empty,
    /// Edges as pairs, until every block has been built.
    pending: std.ArrayList(Edge) = .empty,
    /// How many loops still enclose what is being walked, where that is the
    /// operand of something that leaves one. Null while walking anything else.
    leaving: ?LoopDepth = null,
    /// The constructs being built, innermost last, so a consume inside one
    /// records what closes it and a jump out records what it left half-built.
    ///
    /// A stack rather than one construct, because they nest and a jump leaves
    /// as many of them as it was written inside.
    building: std.ArrayList(ExprId) = .empty,
    /// The statements being walked, innermost last. A borrowed temporary
    /// belongs to the innermost one and ends where that statement does.
    statements: std.ArrayList(Statement) = .empty,
    /// See `Cfg.temporary_statements`.
    temporary_statements: std.AutoHashMapUnmanaged(ExprId, ExprId) = .empty,
    /// See `Cfg.static_reads`.
    static_reads: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// The closures refused for an uncaptured name; see `Cfg.uncaptured`.
    uncaptured: std.ArrayList(cfg_mod.Uncaptured) = .empty,
    /// Whether each closure refused for an uncaptured name takes or changes
    /// it, keyed by the closures decided so far, so each is walked and
    /// reported once however many walks meet it.
    uncaptured_unsettles: std.AutoHashMapUnmanaged(resolve_mod.ClosureId, bool) = .empty,
    /// Set on the builder that walks a refused closure's body only to read
    /// what it takes. Such a walk decides nothing about the closures written
    /// inside that body, since its graph is discarded.
    scratch: bool = false,
    /// With runtime safety, the bindings whose entries in the shared tables a
    /// scratch walk wrote, which `buildRemaining` holds against the kept
    /// graph. Void where safety is off.
    scratch_written: if (std.debug.runtime_safety) *BindingBits else void,
    /// The declaration whose bounds say what the body being built may copy.
    owner: DeclId = .none,

    const Edge = struct { from: BlockId, to: BlockId };

    /// A statement and whether it has evaluated a borrowed temporary, which
    /// is what obliges it to end one.
    const Statement = struct { anchor: ExprId, made: bool = false };

    const LoopFrame = struct {
        result: ExprId,
        after: BlockId,
        again: BlockId,
        /// Where the loop itself sits, which is where what a `break` carries
        /// out ends up.
        yields: Position,
        /// How much was live when the loop began, so a `break` can end the
        /// scopes it is jumping out of.
        live: usize,
        /// And how much was scheduled, so it runs what those scopes owe on the
        /// way out. Carried beside `live` because they are marks into two
        /// stacks that a jump unwinds together.
        scheduled: usize,
        /// How much was being built when the loop began, so a `break` says
        /// which constructs it leaves. A loop written as an operand is inside
        /// the construct that takes it, and leaving the loop does not leave
        /// that -- the call begins the moment the loop yields.
        building: usize,
        /// How many statements were open when the loop began, so a `break`
        /// ends the statements it leaves and the temporaries they made.
        statements: usize,
    };

    fn deinit(self: *Builder) void {
        // Only reached when building failed: on success the list has been
        // handed to the graph and holds nothing.
        for (self.functions.items) |*f| f.deinitOne(self.gpa);
        self.functions.deinit(self.gpa);
        self.blocks.deinit(self.gpa);
        self.exit_blocks.deinit(self.gpa);
        self.ops.deinit(self.gpa);
        self.edges.deinit(self.gpa);
        self.loops.deinit(self.gpa);
        self.live.deinit(self.gpa);
        self.scopes.deinit(self.gpa);
        self.scheduled.deinit(self.gpa);
        self.placements.deinit(self.gpa);
        self.indexes.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.building.deinit(self.gpa);
        self.statements.deinit(self.gpa);
        self.temporary_statements.deinit(self.gpa);
        self.static_reads.deinit(self.gpa);
        self.uncaptured.deinit(self.gpa);
        self.uncaptured_unsettles.deinit(self.gpa);
    }

    fn newBlock(self: *Builder, at: ExprId) !BlockId {
        const id: BlockId = .at(self.blocks.items.len);
        try self.blocks.append(self.gpa, .{
            .ops = .{ .start = @intCast(self.ops.len), .end = @intCast(self.ops.len) },
            .edges = .{ .start = 0, .end = 0 },
            .at = at,
        });
        return id;
    }

    fn markExit(self: *Builder, block: BlockId) !void {
        try self.exit_blocks.append(self.gpa, block);
    }

    /// Appends to the block operations are currently going into.
    ///
    /// A block's operations are contiguous, so switching blocks closes the one
    /// being left. That is why `emit` finalises the range every time rather
    /// than once: the alternative is a per-block list and a flattening pass.
    fn emit(self: *Builder, tag: Op.Tag, place: Place, at: ExprId) !void {
        if (self.at == .none) return;
        try self.ops.append(self.gpa, .{
            .tag = tag,
            .place = place,
            .at = at,
            // Only a transfer is left open by the construct around it. A read
            // hands nothing over, so there is nothing waiting to be received.
            .pending_for = if (tag == .consume or tag == .transferred)
                self.constructAt(self.building.items.len)
            else
                ExprId.none,
            .loops = self.enclosingLoops(),
            .schedule = self.placing.schedule,
            .exit = self.placing.exit,
        });
        self.blocks.items[self.at.index()].ops.end = @intCast(self.ops.len);
    }

    fn value(self: *Builder, at: ExprId, source: ExprId) !void {
        if (self.at == .none) return;
        const ty = self.typing.exprType(at);
        if (!self.typing.mayCarryDependencies(ty)) return;
        try self.emit(.value, .{ .root = .none }, at);
        self.ops.items(.source)[self.ops.len - 1] = source;
    }

    fn returned(self: *Builder, at: ExprId, source: ExprId) !void {
        if (self.at == .none) return;
        try self.emit(.returned, .{ .root = .none }, at);
        self.ops.items(.source)[self.ops.len - 1] = source;
    }

    /// The construct open at a point in the stack of those being built.
    ///
    /// A mark of `len` is here, which is what a transfer emitted now hands its
    /// value to. A loop's mark is where the loop was written, which is what a
    /// `break`'s operand hands its value to -- the loop yields there, so the
    /// construct that takes the loop is the one waiting. One routine, because
    /// those are the same question asked at two points in one stack.
    fn constructAt(self: *const Builder, mark: usize) ExprId {
        return if (mark == 0) ExprId.none else self.building.items[mark - 1];
    }

    /// Walks something that takes the value where it is written.
    ///
    /// A `let`, an assignment, a `return`, a `break` and a `match`'s scrutinee
    /// each receive what they name at the point they are written, so a
    /// transfer into one closes there and nothing is left waiting. Only a
    /// construct's own operand is pending on that construct -- so a `return`
    /// inside a block argument crosses whatever the construct was given, and
    /// not what a statement of that block already handed over.
    fn received(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        return self.receivedBy(id, position, ExprId.none);
    }

    /// Walks an operand whose value is owed to a construct further out.
    ///
    /// What `received` is, with the receiver named: a `break` hands its value
    /// to the loop, and the loop sits inside whatever it was written as an
    /// operand of, so the value is owed to that construct until it begins.
    /// `ExprId.none` is a receiver that takes the value where it stands, which
    /// leaves nothing waiting.
    fn receivedBy(
        self: *Builder,
        id: ExprId,
        position: Position,
        construct: ExprId,
    ) std.mem.Allocator.Error!void {
        try self.building.append(self.gpa, construct);
        defer _ = self.building.pop();
        try self.expr(id, position);
    }

    /// Records that control leaves every construct opened since `mark`.
    ///
    /// Outermost first, which is the order the transfers were opened in and so
    /// the order a reader meets them. A barrier is not a construct and takes
    /// nothing, so there is nothing to leave half-built.
    fn escapeTo(self: *Builder, mark: usize, at: ExprId) !void {
        if (self.at == .none) return;
        for (self.building.items[mark..]) |construct| {
            if (construct == ExprId.none) continue;
            try self.ops.append(self.gpa, .{
                .tag = .escaped,
                // No place: what is left half-built is the construct, and
                // which values it was given is what the transfers say.
                .place = .{ .root = BindingId.none },
                .at = at,
                .pending_for = construct,
                .loops = self.enclosingLoops(),
                .schedule = self.placing.schedule,
                .exit = self.placing.exit,
            });
            self.blocks.items[self.at.index()].ops.end = @intCast(self.ops.len);
        }
    }

    /// How many loops an operation emitted here runs inside.
    ///
    /// The loop stack says how many enclose it syntactically; what a `break`
    /// or a `return` carries out leaves the ones it jumps past, so it runs
    /// once however many times they do. The single place that answers this,
    /// because it was written twice and one copy was later forgotten.
    fn loopDepth(n: usize) LoopDepth {
        // An exit retains its syntax path while one deferred sibling is walked.
        // Schedule placement cannot recurse, so at most two bounded paths add.
        const max_composed_depth = 2 * node.max_tree_height;
        comptime std.debug.assert(max_composed_depth <= std.math.maxInt(LoopDepth));
        std.debug.assert(n <= max_composed_depth);
        return @intCast(n);
    }

    fn enclosingLoops(self: *const Builder) LoopDepth {
        return self.leaving orelse loopDepth(self.loops.items.len);
    }

    /// Starts a block, and gives the one being left an edge to it.
    fn goTo(self: *Builder, next: BlockId) !void {
        try self.link(next);
        try self.resume_(next);
    }

    /// Starts a block without an edge from wherever operations were going.
    ///
    /// What a merge does: its edges came from the arms, which have each
    /// already been walked, so there is nothing here to link. Every block's
    /// operations are contiguous, so becoming one means saying where its run
    /// begins -- and a site that set `at` and forgot to say it appended to
    /// whichever block last happened to end there.
    fn resume_(self: *Builder, next: BlockId) !void {
        self.at = next;
        if (next != .none) {
            self.blocks.items[next.index()].ops.start = @intCast(self.ops.len);
            self.blocks.items[next.index()].ops.end = @intCast(self.ops.len);
        }
    }

    /// Records an edge. Kept as a pair while building and flattened at the
    /// end, because a block gains its second edge long after another block has
    /// gained its first -- an arm is walked between them -- and a range that
    /// assumed otherwise silently dropped the earlier one.
    fn link(self: *Builder, to: BlockId) !void {
        if (self.at == .none or to == .none) return;
        try self.pending.append(self.gpa, .{ .from = self.at, .to = to });
    }

    /// Turns the recorded pairs into one contiguous run per block.
    ///
    /// Counted rather than searched: the pairs are grouped by counting how
    /// many leave each block, turning those counts into where each run starts,
    /// and then placing each pair once. Rescanning every pair for every block
    /// read both lists in full for each block, and the two grow together over
    /// the whole program rather than per function -- so a program of many
    /// small functions paid for it as surely as one enormous function did.
    ///
    /// The placing pass walks the pairs in the order they were recorded, so
    /// each block's edges keep that order.
    fn flattenEdges(self: *Builder) !void {
        try self.edges.resize(self.gpa, self.pending.items.len);

        // `end` counts the run while it is being sized, then walks it while
        // the pairs are placed, and finishes where the run finishes.
        for (self.blocks.items) |*blk| blk.edges = .{ .start = 0, .end = 0 };
        for (self.pending.items) |e| self.blocks.items[e.from.index()].edges.end += 1;

        var next: u32 = 0;
        for (self.blocks.items) |*blk| {
            blk.edges.start = next;
            next += blk.edges.end;
            blk.edges.end = blk.edges.start;
        }

        for (self.pending.items) |e| {
            const blk = &self.blocks.items[e.from.index()];
            self.edges.items[blk.edges.end] = e.to;
            blk.edges.end += 1;
        }
    }

    fn function(self: *Builder, d: DeclId, expression: ExprId) !void {
        const first = self.blocks.items.len;
        const first_scope = self.scopes.items.len;
        self.at = try self.newBlock(expression);
        self.loops.clearRetainingCapacity();
        self.live.clearRetainingCapacity();
        self.building.clearRetainingCapacity();

        var inouts: std.ArrayList(BindingId) = .empty;
        errdefer inouts.deinit(self.gpa);

        // A parameter arrives initialised. An `inout` also carries a promise
        // to be initialised again at every exit, which is the only thing that
        // distinguishes it here.
        const params = self.ast.declParams(d);
        for (self.res.parametersOf(d)) |b| {
            try self.emit(.init, .{ .root = b }, expression);
            switch (params[self.res.paramIndexOf(b)].convention) {
                .inout => try inouts.append(self.gpa, b),
                // The callee took ownership, so the obligation is the
                // callee's: a `sink` parameter still held where the body ends
                // is a value nobody disposed of. Without this a function that
                // promises to release something can simply not.
                .sink => try self.beginScope(b),
                .read => {},
            }
        }

        // A function's value leaves through its return type, which takes it.
        self.owner = d;
        self.statements.clearRetainingCapacity();
        try self.beginStatement(expression);
        try self.expr(expression, .consuming);
        try self.endStatement();
        try self.returned(expression, expression);
        try self.endScopesTo(0, expression);

        if (self.at != .none) {
            try self.markExit(self.at);
        }

        try self.functions.append(self.gpa, .{
            .decl = d,
            .owner = d,
            .entry = .at(first),
            .signature = self.typing.declSignature(d),
            .parameters = self.res.parametersOf(d),
            .blocks = .{ .start = @intCast(first), .end = @intCast(self.blocks.items.len) },
            .scopes = .{ .start = @intCast(first_scope), .end = @intCast(self.scopes.items.len) },
            .inouts = try inouts.toOwnedSlice(self.gpa),
            .contract_declined = self.typing.declined_contracts.contains(d),
            .default_carrier = self.typing.defaulted_contracts.get(d),
        });
    }

    fn closure(self: *Builder, id: resolve_mod.ClosureId, descriptor: types_mod.ClosureDescriptor) !void {
        const first = self.blocks.items.len;
        const first_scope = self.scopes.items.len;
        self.at = try self.newBlock(descriptor.body);
        self.loops.clearRetainingCapacity();
        self.live.clearRetainingCapacity();
        self.building.clearRetainingCapacity();

        var inouts: std.ArrayList(BindingId) = .empty;
        errdefer inouts.deinit(self.gpa);
        const params = self.ast.lambda(descriptor.expr).params;
        for (self.res.closureParameters(id)) |b| {
            try self.emit(.init, .{ .root = b }, descriptor.body);
            switch (params[self.res.paramIndexOf(b)].convention) {
                .inout => try inouts.append(self.gpa, b),
                .sink => try self.beginScope(b),
                .read => {},
            }
        }

        // A parameter written as a tuple pattern is taken apart where the
        // body begins, as `let (a, b) = argument` takes a value and
        // `let read (a, b) = argument` lends from a place.
        for (self.res.closureParameters(id)) |b| {
            const param = params[self.res.paramIndexOf(b)];
            if (param.pattern == ExprId.none) continue;
            const owning = param.convention == .sink;
            try self.received(param.argument, if (owning) .consuming else .reading);
            const holding: Holding = switch (param.convention) {
                .sink => .owned,
                .read => .lent_until_last_use,
                .inout => .lent,
            };
            try self.bindPatternHolders(param.pattern, param.argument, param.argument, holding);
        }

        for (self.res.closureCaptures(id)) |capture| {
            try self.emit(.init, .{ .root = capture.binding }, descriptor.expr);
            // A place lent `inout` is the caller's, as an `inout` parameter's
            // is: the body may change it and must leave it initialized.
            if (capture.convention == .inout and descriptor.invocation != .read) {
                try inouts.append(self.gpa, capture.binding);
            } else if (capture.convention != .sink or descriptor.invocation == .read) {
                self.shareWrite(capture.binding);
                self.lends.set(capture.binding, true);
            } else switch (descriptor.invocation) {
                .read => unreachable,
                .sink => try self.beginScope(capture.binding),
                .inout => try inouts.append(self.gpa, capture.binding),
            }
        }

        self.owner = descriptor.enclosing;
        self.statements.clearRetainingCapacity();
        try self.beginStatement(descriptor.body);
        try self.expr(descriptor.body, .consuming);
        try self.endStatement();
        try self.returned(descriptor.body, descriptor.body);
        try self.endScopesTo(0, descriptor.body);
        if (self.at != .none) try self.markExit(self.at);
        try self.functions.append(self.gpa, .{
            .decl = .none,
            .owner = descriptor.enclosing,
            .entry = .at(first),
            .signature = descriptor.signature,
            .parameters = self.res.closureParameters(id),
            .blocks = .{ .start = @intCast(first), .end = @intCast(self.blocks.items.len) },
            .scopes = .{ .start = @intCast(first_scope), .end = @intCast(self.scopes.items.len) },
            .inouts = try inouts.toOwnedSlice(self.gpa),
            .contract_declined = descriptor.contract_declined,
            .default_carrier = descriptor.default_carrier,
        });
    }

    /// What a pattern binds, as somewhere to start and how far to step.
    ///
    /// A struct pattern names a field and then the binder it goes to; a
    /// variant pattern names its payload directly. Every rule about pattern
    /// binders reads this rather than restating which form puts them where --
    /// the lend rule was written twice and the two disagreed about the struct
    /// form, so a `Key` could be carried out of a value the match never took.
    const Binders = struct {
        args: []const ExprId,
        step: usize,

        fn first(self: Binders) usize {
            return self.step - 1;
        }
    };

    /// Whether a pattern is a bare `_`, which matches anything and binds none
    /// of it.
    fn isWildcard(self: *const Builder, pattern: ExprId) bool {
        return isCatchAll(self.ast, pattern);
    }

    /// Records each binder a pattern introduces as a binding that owns what
    /// it was given.
    fn bindersOf(self: *const Builder, pattern: ExprId) ?Binders {
        if (pattern == ExprId.none) return null;
        const step: usize = switch (self.ast.exprTag(pattern)) {
            .struct_pattern => 2,
            .tuple_pattern, .call => 1,
            // A bare variant name binds nothing, and `_` names nothing.
            else => return null,
        };
        return .{ .args = self.ast.call(pattern).args, .step = step };
    }

    /// The part a tuple pattern's binder takes: the field the checker's
    /// selection names, or the whole where the checker refused the binder.
    fn componentProjection(self: *const Builder, binder: ExprId) cfg_mod.Projection {
        const field = self.componentField(binder) orelse return .whole;
        return .{ .field = field };
    }

    /// The part a struct pattern's binder takes: the field its label names,
    /// where the checker accepted the label as a field of the value, and the
    /// whole where it refused it. The checker looked the field up by this
    /// spelling, so the spelling is the field's name.
    fn labelProjection(self: *const Builder, label: ExprId) cfg_mod.Projection {
        const token = self.ast.exprMain(label);
        if (self.typing.fieldSelection(token) == null) return .whole;
        return .{ .field = self.ast.tokenName(token) };
    }

    /// The field a tuple pattern's binder stands at, or null where the
    /// checker refused the binder.
    fn componentField(self: *const Builder, binder: ExprId) ?StringId {
        const selected = self.typing.fieldSelection(self.ast.exprMain(binder)) orelse return null;
        const decl = self.typing.declOfType(selected.receiver) orelse return null;
        return self.ast.declFieldName(decl, selected.field.index());
    }

    /// The part of its walk's element a loop binder takes: the element's
    /// place under a lending walk, whatever the pattern, and the element or
    /// its component under an owning one.
    fn walkedPart(self: *const Builder, walk: ExprId, binder: ExprId, lending: bool) cfg_mod.Projection {
        if (lending) return .{ .index = walk };
        if (self.ast.exprTag(self.ast.call(walk).args[0]) != .tuple_pattern) return .element;
        const field = self.componentField(binder) orelse return .element;
        return .{ .element_component = field };
    }

    /// How a pattern's binders hold what they name: owned by the binder, lent
    /// for the extent of the construct that bound them, or lent until their
    /// last use.
    const Holding = enum { owned, lent, lent_until_last_use };

    fn bindPatternHolders(self: *Builder, pattern: ExprId, at: ExprId, source: ExprId, holding: Holding) !void {
        const b = self.bindersOf(pattern) orelse return;
        var i = b.first();
        while (i < b.args.len) : (i += b.step) {
            const binder = self.res.targetOf(b.args[i]);
            if (binder == BindingId.none) continue;
            const projection: cfg_mod.Projection = switch (self.ast.exprTag(pattern)) {
                .struct_pattern => self.labelProjection(b.args[i - 1]),
                .tuple_pattern => self.componentProjection(b.args[i]),
                else => if (types_mod.variantOrdinalOf(&self.res.variant_ordinals, &self.typing.variant_uses, pattern)) |variant|
                    .{ .payload = .{ .variant = variant, .index = @intCast(i) } }
                else
                    .whole,
            };
            try self.bindHolder(binder, at, source, projection, holding);
        }
    }

    /// Records one binder taking the part `projection` selects of `source`,
    /// owned or lent as `holding` says. Every construct that binds a name to
    /// part of a value -- a pattern, a walk, an `else` -- binds it here.
    fn bindHolder(self: *Builder, binder: BindingId, at: ExprId, source: ExprId, projection: cfg_mod.Projection, holding: Holding) !void {
        const lending = holding != .owned;
        self.shareWrite(binder);
        self.declared_in_loops[binder.index()] = loopDepth(self.loops.items.len);
        if (lending) self.lends.set(binder, true);
        if (holding == .lent_until_last_use) self.lasting_lends.set(binder, true);
        try self.emit(if (lending) .lent else .init, .{ .root = binder }, at);
        if (self.at != .none) {
            self.ops.items(.source)[self.ops.len - 1] = source;
            self.ops.items(.projection)[self.ops.len - 1] = projection;
        }
        if (!lending) try self.beginScope(binder);
    }

    /// Puts a binding on the live stack, and records the node it holds.
    ///
    /// Minted in the order the walk meets declarations, which is depth-first
    /// over the tree: a node therefore sits after every node it is inside, so
    /// its subtree is the contiguous run of indices `closeScopes` gives it.
    fn beginScope(self: *Builder, b: BindingId) !void {
        const id: ScopeId = .at(self.scopes.items.len);
        try self.scopes.append(self.gpa, .{
            .binding = b,
            .outer = self.topScope(),
            .depth = @intCast(self.live.items.len + 1),
            .last = @intCast(id.index()),
        });
        try self.live.append(self.gpa, id);
        self.shareWrite(b);
        self.scope_of[b.index()] = id;
    }

    /// Notes that this walk writes `b`'s entries in the tables every walk
    /// shares, when this walk's graph is discarded; see `scratch_written`.
    fn shareWrite(self: *Builder, b: BindingId) void {
        if (std.debug.runtime_safety and self.scratch) self.scratch_written.set(b, true);
    }

    /// The innermost scope still open, and `.none` where nothing is.
    fn topScope(self: *const Builder) ScopeId {
        if (self.live.items.len == 0) return ScopeId.none;
        return self.live.items[self.live.items.len - 1];
    }

    /// Gives each scope the last index in its subtree.
    ///
    /// One backward pass over the whole tree: a scope is minted after every
    /// scope it holds, so by the time this reaches one, everything inside it
    /// has already pushed its own end up.
    fn closeScopes(self: *Builder) void {
        var i = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            const outer = self.scopes.items[i].outer;
            if (outer == ScopeId.none) continue;
            const last = self.scopes.items[i].last;
            const into = &self.scopes.items[outer.index()];
            if (into.last < last) into.last = last;
        }
    }

    /// Walks what a scope scheduled, last first, at an exit from it.
    ///
    /// Before the scope's `dies` operations, which is what makes a value the
    /// schedule discharged read as `moved` by the time [O-Leak] asks. Reversed
    /// because a later `defer` may name what an earlier one holds, and that is
    /// the only order that composes.
    fn runScheduledTo(self: *Builder, mark: usize, at: ExprId) std.mem.Allocator.Error!void {
        // A schedule cannot place itself. An expression that leaves from
        // inside a `defer` re-enters this walk over a stack the walk has not
        // popped, and follows itself forever. [S-Defer] refuses the program;
        // this is what keeps the frontend total while it does.
        if (self.placing.schedule != ExprId.none) return;

        const was = self.placing;
        defer self.placing = was;

        var i = self.scheduled.items.len;
        while (i > mark) {
            i -= 1;
            if (self.at == .none) break;
            self.placing = .{ .schedule = self.scheduled.items[i], .exit = at };
            if (self.placing.schedule != .none) try self.placements.append(self.gpa, .{
                .schedule = self.placing.schedule,
                .exit = at,
            });
            try self.beginStatement(self.scheduled.items[i]);
            try self.received(self.scheduled.items[i], .consuming);
            try self.endStatement();
        }
    }

    /// Opens a statement anchored at `anchor`. Every borrowed temporary
    /// evaluated until it closes belongs to it.
    fn beginStatement(self: *Builder, anchor: ExprId) !void {
        try self.statements.append(self.gpa, .{ .anchor = anchor });
    }

    /// Closes the innermost statement, ending the temporaries it made.
    fn endStatement(self: *Builder) !void {
        const closed = self.statements.pop().?;
        if (closed.made) try self.emit(.temporaries_end, .{ .root = BindingId.none }, closed.anchor);
    }

    /// Ends the temporaries of every statement above `mark`, which control
    /// leaves without reaching their ends. The statements stay open for the
    /// walk, since what follows a `break` in the tree is still written there.
    fn endStatementsTo(self: *Builder, mark: usize) !void {
        var i = self.statements.items.len;
        while (i > mark) {
            i -= 1;
            const open = self.statements.items[i];
            if (open.made) try self.emit(.temporaries_end, .{ .root = BindingId.none }, open.anchor);
        }
    }

    /// Records that a borrowed temporary is evaluated here, in the innermost
    /// open statement.
    fn noteTemporary(self: *Builder, id: ExprId) !void {
        const open = &self.statements.items[self.statements.items.len - 1];
        open.made = true;
        try self.temporary_statements.put(self.gpa, id, open.anchor);
    }

    /// Records that everything live above `mark` has reached the end of its
    /// scope.
    ///
    /// One operation for the whole stretch, naming the top of the live stack
    /// and how much of it survives, because the same stretch is ended by every
    /// early exit written inside it: an operation per binding makes a body of
    /// n exits over n live bindings a graph of n squared, which every pass
    /// that walks the graph then pays for again. Which bindings the stretch
    /// holds is a walk of the tree, and the readers that ask are the ones that
    /// have a reason to.
    ///
    /// Emitting only; the stack is left alone, because a `return` inside a
    /// block does not end the block for the statements after it.
    fn endScopesTo(self: *Builder, mark: usize, at: ExprId) !void {
        if (self.at == .none) return;
        if (self.live.items.len <= mark) return;
        try self.ops.append(self.gpa, .{
            .tag = .dies,
            // No place: what ends is a stretch of the stack, and `run` is
            // where the operation says which stretch.
            .place = .{ .root = BindingId.none },
            .at = at,
            .run = .{ .top = self.topScope(), .mark = @intCast(mark) },
            .loops = self.enclosingLoops(),
            .schedule = self.placing.schedule,
            .exit = self.placing.exit,
        });
        self.blocks.items[self.at.index()].ops.end = @intCast(self.ops.len);
    }

    /// A block, and what its trailing value is for.
    ///
    /// The tail is the block's value, so it inherits the position the block
    /// itself sits in: a body whose value is returned takes what it names, and
    /// one whose value is an operand of `+` observes it.
    fn body(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        const blk = self.ast.blockOf(id);
        const mark = self.live.items.len;
        const held = self.scheduled.items.len;

        for (self.ast.blockStmts(blk)) |s| try self.stmt(s);
        // The tail is the block's value, so it is the construct's own operand
        // wherever the block sits. Every other consuming position in a block
        // is `received` where it is written.
        if (blk.tail != ExprId.none) {
            try self.expr(blk.tail, position);
            try self.value(id, blk.tail);
        }

        try self.runScheduledTo(held, id);
        try self.endScopesTo(mark, id);
        self.live.shrinkRetainingCapacity(mark);
        self.scheduled.shrinkRetainingCapacity(held);
    }

    fn stmt(self: *Builder, s: StmtId) std.mem.Allocator.Error!void {
        // A `defer` is walked where it runs, as a statement of its own.
        const anchor = self.ast.stmtData(s).init;
        if (anchor == ExprId.none or self.ast.stmtTag(s) == .defer_stmt or self.ast.stmtTag(s) == .defer_release) return self.statementBody(s);
        try self.beginStatement(anchor);
        try self.statementBody(s);
        try self.endStatement();
    }

    fn statementBody(self: *Builder, s: StmtId) std.mem.Allocator.Error!void {
        switch (self.ast.stmtTag(s)) {
            // Already diagnosed. Whatever the parser could not read has no
            // places worth reasoning about.
            .err => {},
            .expr_stmt => try self.expr(self.ast.stmtData(s).init, .reading),
            // Recorded, not walked. Reaching a `defer` changes nothing about
            // what anything owns -- which is what makes `defer free(b)` legal
            // before `b` is read. The walk happens at each exit from the scope,
            // last scheduled first.
            .defer_stmt, .defer_release => try self.scheduled.append(self.gpa, self.ast.stmtData(s).init),
            // Taking a value apart takes it: the parts are what is left, and
            // each becomes a binding that must be disposed of in its own turn.
            .let_destructure => {
                const d = self.ast.stmtData(s);
                try self.received(d.init, .consuming);
                try self.bindPatternHolders(d.pattern, d.init, d.init, .owned);
            },
            // Observing a place leaves it where it is: each part becomes a
            // lend of the place, as a `match read` arm's binders are, and the
            // lend lasts as long as something still uses it.
            .let_read_destructure => {
                const d = self.ast.stmtData(s);
                try self.received(d.init, .reading);
                try self.bindPatternHolders(d.pattern, d.init, d.init, .lent_until_last_use);
            },
            .let_decl => {
                const d = self.ast.stmtData(s);
                // The initialiser occupies a consuming position.
                if (d.init != ExprId.none) try self.received(d.init, .consuming);

                const b = self.res.bindingOf(s);
                if (b != BindingId.none) {
                    self.shareWrite(b);
                    self.declared_in_loops[b.index()] = loopDepth(self.loops.items.len);
                    try self.emit(.init, .{ .root = b }, d.init);
                    if (self.at != .none) self.ops.items(.source)[self.ops.len - 1] = d.init;
                    // An initialiser the checker refused -- a construction of
                    // a type sealed here, a call it did not accept -- built no
                    // value, whatever type the binding was given, so what the
                    // binding holds is unknown rather than owed. A branching
                    // initialiser is not refused as a whole: its arms that
                    // built a value leave the binding owing it.
                    if (d.init != ExprId.none and self.refused(d.init)) try self.emit(.unsettled, .{ .root = b }, d.init);
                    try self.beginScope(b);
                }
            },
        }
    }

    /// Walks an expression, recording what happens to the places in it.
    ///
    /// `position` is the caller's: an argument's position is its parameter's
    /// convention, an operand's is reading, and a `let`'s initialiser is
    /// consuming. Nothing about the operator decides it.
    fn expr(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        if (id == ExprId.none) return;
        if (self.typing.borrowed_temporaries.contains(id)) try self.noteTemporary(id);

        const tag = self.ast.exprTag(id);
        switch (tag) {
            // A pattern names fields and binders rather than places: what it
            // does to the value is the destructure's business, recorded where
            // the destructure is.
            .err, .int_literal, .float_literal, .str_literal, .bool_literal, .unit_literal, .reflection_root, .variant_ref, .struct_pattern, .tuple_pattern => {},

            .lambda => {
                try self.building.append(self.gpa, id);
                defer _ = self.building.pop();
                const closure_id = self.res.closures.closureOf(id);
                if (closure_id != .none and !self.scratch) {
                    const free = self.res.freeReferenceOf(closure_id);
                    if (free != ExprId.none and try self.uncapturedName(closure_id)) try self.unsettle(free);
                    if (self.refused(id)) try self.unsettleNestedUncaptured(closure_id);
                }
                if (closure_id != .none) for (self.res.closureCaptures(closure_id)) |capture| {
                    try self.expr(capture.source, if (capture.convention == .sink) .consuming else .reading);
                    if (self.at != .none) {
                        try self.emit(.value, .{ .root = .none }, id);
                        const op = self.ops.len - 1;
                        self.ops.items(.source)[op] = capture.source;
                        self.ops.items(.projection)[op] = .{ .field = self.ast.tokenName(self.res.captureNameToken(capture.binding)) };
                        self.ops.items(.reading)[op] = capture.convention != .sink;
                        self.ops.items(.exclusive)[op] = capture.convention == .inout;
                    }
                };
                try self.commit(id);
            },

            .name_ref, .param_argument => {
                const b = self.res.targetOf(id);
                if (b == BindingId.none) return;
                switch (self.res.kindOf(b)) {
                    .local, .parameter, .binder, .capture => {},
                    // A selected function value is stateless. Constants and
                    // declarations carry no ownership-tracked source state.
                    // Exhaustive, with no `else`, so a kind of name added later
                    // says which side of this it falls on before the build
                    // succeeds.
                    .function, .declared_type, .builtin_type, .trait, .module, .associated_type, .type_parameter, .type_alias => return,
                    .constant => return self.staticRead(id),
                }
                try self.emit(
                    self.placeOperation(id, position),
                    .{ .root = b },
                    id,
                );
            },

            .field, .index, .dereference => try self.selection(id, position),

            // Parentheses are not an operation. What is inside sits exactly
            // where the whole expression sits, which is the same reason every
            // walk over places steps through them.
            .grouped => try self.expr(self.ast.unaryOperand(id), position),

            // An operator observes its operand and yields something else,
            // whatever position the operation as a whole sits in. Grouped with
            // parentheses, `let b = -a` moved `a` -- the position passed
            // straight through a node that produces a new value from one it
            // only looked at.
            .negate, .not => try self.expr(self.ast.unaryOperand(id), .reading),
            // Counting back from an end builds a value out of a number it
            // read, so what it counts by is observed wherever the count is
            // written.
            .from_end => try self.expr(self.ast.unaryOperand(id), .reading),
            // A copy reads its place and yields something else, so what it
            // names is observed rather than taken however the copy itself is
            // used. That is the whole of what `copy` is for.
            .copy_ => {
                const of = self.ast.unaryOperand(id);
                try self.expr(of, .reading);
                try self.emitCopy(id, of, position);
            },
            .borrow => try self.expr(self.ast.unaryOperand(id), .reading),
            .panic => try self.received(self.ast.unaryOperand(id), .reading),
            // The marker is not an operation. What it marks is written back
            // through, which is a read here: `inout` does not consume.
            .marked => try self.expr(self.ast.unaryOperand(id), .reading),

            .block => try self.body(id, position),

            // Both operands are read: the head is observed and the index is
            // a number. Which element is named is a question about places,
            // and a whole array is what a move takes.
            .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge => {
                const p = self.ast.binary(id);
                try self.expr(p.lhs, .reading);
                try self.expr(p.rhs, .reading);
            },

            .assign => {
                const p = self.ast.binary(id);
                // The value first, then the place it fills, so a self
                // assignment reads before it writes.
                try self.received(p.rhs, .consuming);
                try self.assigned(p.lhs, false, p.rhs);
            },

            // The same two in the same order, and the place read as well as
            // written -- which is the whole of what the graph has to know about
            // a compound assignment. The path itself is walked once, here, so
            // an effect in an index is one operation in the graph exactly as it
            // is one call in the program.
            //
            // The operand is *read*, where an assignment's value is taken. It
            // is an operand of the operator, and operands are read: `a += b`
            // leaves `b` where `a = a + b` leaves it, which is in one piece.
            .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => {
                const p = self.ast.binary(id);
                try self.received(p.rhs, .reading);
                try self.assigned(p.lhs, true, .none);
            },

            .try_ => try self.tryExpr(id),
            .unwrap_else => try self.unwrapElse(id, position),

            // A piece the literal borrows or copies is read, so naming a
            // binding inside a literal does not spend it. A value the literal
            // holds without copying is computed in its braces and given up
            // into it, as a structure literal's field is.
            .interp => {
                try self.building.append(self.gpa, id);
                defer _ = self.building.pop();
                for (self.ast.interpolation(id).pieces) |piece| {
                    // A refused piece has no recorded position and holds nothing.
                    const moved = (self.typing.interpolationPosition(piece) orelse .borrowed) == .moved;
                    try self.expr(piece, if (moved) .consuming else .reading);
                }
                try self.commit(id);
            },
            .call, .struct_literal, .array_literal, .tuple_literal => try self.call(id),

            // A construction, as a structure literal's fields are: each end
            // is given up into the value being built, whatever position the
            // range itself sits in.
            .range => {
                const ends = self.ast.rangeEnds(id);
                try self.expr(ends.lhs, .consuming);
                try self.expr(ends.rhs, .consuming);
            },
            .match_, .match_read => try self.matchExpr(id, position),
            .conditional => try self.conditional(id, position),
            .logical_and, .logical_or => try self.logical(id, position),
            .while_, .loop_ => try self.loopExpr(id, position),
            .for_, .for_read, .for_inout => try self.forExpr(id, position),

            .continue_ => {
                // A jump, not a value. Grouped with the literals it read as
                // falling through, so the graph believed the rest of the body
                // ran on the path that skips it -- and a value the body holds
                // was taken to be disposed of by code `continue` jumps over.
                if (self.loops.items.len > 0) {
                    const loop = self.loops.items[self.loops.items.len - 1];
                    // The constructs opened inside the loop are left half-built
                    // by going back to its head; the ones the loop itself sits
                    // inside are not, and receive their values when it yields.
                    try self.escapeTo(loop.building, id);
                    try self.runScheduledTo(loop.scheduled, id);
                    // The scopes between here and the loop head end here, for
                    // the same reason a `break`'s do, and so do the statements.
                    try self.endScopesTo(loop.live, id);
                    try self.endStatementsTo(loop.statements);
                    try self.link(loop.again);
                }
                // Nothing after this runs.
                self.at = .none;
            },

            .break_, .return_ => {
                // What a `break` or a `return` carries out is evaluated once
                // however many times the loop runs, because it is what leaves.
                // Counting it as inside the loop would refuse `break x`, which
                // is how a loop yields a value at all.
                const breaking = self.ast.exprTag(id) == .break_ and self.loops.items.len > 0;
                const was = self.leaving;
                self.leaving = if (self.ast.exprTag(id) == .break_)
                    loopDepth(self.loops.items.len -| 1)
                else
                    0;
                defer self.leaving = was;

                const operand = self.ast.unaryOperand(id);
                // A `return` hands its value to the caller, which takes it
                // where it stands; a `break` hands its value to the loop, and
                // the loop yields where it was written. So a value carried out
                // of a loop written as an operand is owed to the construct that
                // takes the loop, exactly as an argument written there is.
                if (breaking) {
                    const loop = self.loops.items[self.loops.items.len - 1];
                    try self.receivedBy(operand, loop.yields, self.constructAt(loop.building));
                } else {
                    try self.received(operand, .consuming);
                }

                if (breaking) {
                    const loop = self.loops.items[self.loops.items.len - 1];
                    try self.value(loop.result, operand);
                    // As for a `continue`: what the loop is written inside of
                    // is not left by leaving the loop.
                    try self.escapeTo(loop.building, id);
                    // What those scopes scheduled runs on the way out, before
                    // they end -- the same order a normal exit uses, and for
                    // the same reason.
                    try self.runScheduledTo(loop.scheduled, id);
                    // The scopes between here and the loop end here. Without
                    // this a `break` walks out past every `let` inside the
                    // body and nothing is ever asked about them.
                    try self.endScopesTo(loop.live, id);
                    try self.endStatementsTo(loop.statements);
                    try self.link(loop.after);
                } else if (self.ast.exprTag(id) == .return_ and self.at != .none) {
                    // Every construct is left half-built, because a `return`
                    // leaves everything the function was in the middle of.
                    try self.escapeTo(0, id);
                    // Everything scheduled anywhere in the function runs, so a
                    // `defer` reaches the path a `return` takes.
                    try self.runScheduledTo(0, id);
                    // Every scope ends, and so does the function -- so this is
                    // where a value still held is a value never disposed of.
                    try self.endScopesTo(0, id);
                    try self.returned(id, operand);
                    // Running the schedules can leave the block that is doing
                    // the running: an expression that leaves from inside a
                    // `defer` is [S-Defer], and the walk still has to finish
                    // over the tree that says so.
                    if (self.at != .none) try self.markExit(self.at);
                }
                // Nothing after this runs.
                self.at = .none;
            },
        }

        // A non-completing expression has no local successor. Transfers above
        // still record their destination before this common answer is read.
        if (self.typing.exprType(id) == .never) self.at = .none;

        // After the operands, so a construct has received what it was given
        // before its own result is owed to the construct outside it.
        switch (tag) {
            .block, .conditional, .match_, .match_read, .unwrap_else, .loop_, .while_, .for_, .for_read, .for_inout, .return_, .break_, .continue_ => {},
            else => try self.value(id, .none),
        }
        if (yieldsAnUnnamedValue(tag)) try self.yielded(id, position);
    }

    /// Records a value no place names.
    ///
    /// In a consuming position it is owed to the construct around it, which is
    /// what [O-Uncommitted] follows. In a reading position it is owed to
    /// nobody and nobody can take it: no place names it, so no position after
    /// this one can name it, and a Linear one is a leak where it is yielded.
    ///
    /// Built here rather than through `emit` because the position has to
    /// survive onto the operation, and `emit` takes a place instead.
    fn yielded(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        if (self.at == .none) return;
        try self.ops.append(self.gpa, .{
            .tag = .transferred,
            .place = .{ .root = BindingId.none },
            .at = id,
            .reading = position == .reading,
            .pending_for = if (position == .consuming)
                self.constructAt(self.building.items.len)
            else
                ExprId.none,
            .loops = self.enclosingLoops(),
            .schedule = self.placing.schedule,
            .exit = self.placing.exit,
        });
        self.blocks.items[self.at.index()].ops.end = @intCast(self.ops.len);
    }

    /// Whether an expression of this kind yields a value that no place names.
    ///
    /// Three kinds do not. A place names a value and emits its own transfer,
    /// keyed by that place. A pattern and an error region are not values. And
    /// a construct carrying the position to whatever it yields -- a block to
    /// its tail, a conditional to its arms, a loop to its breaks -- has
    /// already asked this of the expression that yields the value, so asking
    /// again would count one value twice.
    ///
    /// Everything else yields one. Whether it was made there or taken out of
    /// something that was is not the question: a call's result and the payload
    /// a `?` moves out of an enum are alike in owing what a named value owes
    /// and having no name to be asked for it by.
    /// Exhaustive on purpose. The dangerous default is `true`: a construct
    /// that carries the position to whatever it yields belongs in the `false`
    /// set, and every one added later -- a labelled block, another form of
    /// binding-and-branching -- is of that family. Falling through to `true`
    /// would count its value twice, with no compile error and a wrong
    /// ownership diagnostic on a shape nobody has written yet.
    fn yieldsAnUnnamedValue(tag: node.Expr.Tag) bool {
        return switch (tag) {
            .name_ref, .param_argument, .field, .dereference, .grouped, .marked => false,
            .err, .reflection_root, .struct_pattern, .tuple_pattern => false,
            .block, .conditional, .match_, .match_read, .loop_, .while_ => false,
            .for_, .for_read, .for_inout => false,
            // Its success path yields the payload itself; its failing path
            // carries the position to the block.
            .unwrap_else => false,
            .logical_and, .logical_or => false,
            // An assignment of either kind yields Unit, which is not a value
            // anything can be left holding.
            .break_, .continue_, .return_, .panic, .assign => false,
            .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => false,

            // A literal builds a value no place names, exactly as the other
            // constructors do.
            .interp => true,
            .call, .struct_literal, .array_literal, .tuple_literal, .variant_ref, .copy_, .borrow, .try_, .lambda => true,
            .range => true,
            .int_literal, .float_literal, .str_literal, .bool_literal, .unit_literal, .negate, .not => true,
            // A value built from the number after the caret, which no place
            // names.
            .from_end => true,
            // An index yields the element, which no place names until the
            // place machinery reaches it.
            // An index names a place rather than yielding a value: it is a
            // step in a path, so what it reaches is part of a binding.
            .index => false,
            .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge => true,
        };
    }

    /// Records a copy, so the rules about a pointless one can be asked.
    fn emitCopy(self: *Builder, id: ExprId, of: ExprId, position: Position) !void {
        // Rejected copies have no duplication to classify; their operands
        // have already been checked as reads.
        if (self.refused(id)) return;
        // No `walkIndexes` here: whatever reached the place already walked
        // them, and a second walk records every effect inside an index twice.
        const path = self.pathOf(of);
        const depth = path.depth;
        const at = path.root;
        if (!self.ast.refersToBinding(at)) return;

        const b = self.res.targetOf(at);
        if (b == BindingId.none) return;
        switch (self.res.kindOf(b)) {
            .local, .parameter, .binder, .capture => {},
            // A function or a type is not a value and has no state.
            // Exhaustive, with no `else`, so a kind of name added later says
            // which side of this it falls on before the build succeeds.
            .constant, .function, .declared_type, .builtin_type, .trait, .module, .associated_type, .type_parameter, .type_alias => return,
        }

        if (self.at == .none) return;
        try self.ops.append(self.gpa, .{
            .tag = .copied,
            .place = .{ .root = b, .depth = depth },
            .at = id,
            .source = of,
            .reading = position == .reading,
            .loops = self.enclosingLoops(),
            .schedule = self.placing.schedule,
            .exit = self.placing.exit,
        });
        self.blocks.items[self.at.index()].ops.end = @intCast(self.ops.len);
    }

    /// `a.x`, which reads `a` however deep the selection goes.
    ///
    /// Walking it also emits the index expressions, which are read wherever the
    /// path sits: `a[f()]` calls `f` whether the element is taken or observed.
    fn pathOf(self: *const Builder, id: ExprId) Ast.PlacePath {
        var steps = self.ast.placeSteps(id);
        var depth: u32 = 0;
        while (steps.next()) |step| depth += self.selectionDepth(step);
        return .{ .root = steps.at, .depth = depth };
    }

    fn selectionDepth(self: *const Builder, step: ExprId) u32 {
        if (self.typing.placeProjection(step)) |projection| {
            return projection.observations + @as(u32, @intFromBool(projection.field != null));
        }
        return 1;
    }

    /// Walks the index expressions of a path, in the order they run.
    ///
    /// Apart from `pathOf`, which answers where a path leads and must be
    /// askable twice: a `copy` asks it after the walk that reads the place
    /// already did, and a walk with effects run twice records every effect
    /// inside an index twice -- a value given away in one read as given away
    /// in two.
    ///
    /// Innermost-first, because that is the order the program evaluates them
    /// and the descent meets them in the other one. Emitted as they were met,
    /// `g[take(k)][look(k)]` recorded the read before the move, and the graph
    /// said a value was still held where it had been given away.
    fn walkIndexes(self: *Builder, id: ExprId) std.mem.Allocator.Error!void {
        const mark = self.indexes.items.len;
        defer self.indexes.shrinkRetainingCapacity(mark);

        var steps = self.ast.placeSteps(id);
        while (steps.next()) |step| {
            if (self.ast.exprTag(step) != .index) continue;
            try self.indexes.append(self.gpa, self.ast.binary(step).rhs);
        }

        var i = self.indexes.items.len;
        while (i > mark) {
            i -= 1;
            try self.indexExpr(self.indexes.items[i]);
        }
    }

    /// What a bracket holds, walked where it runs.
    ///
    /// A range written in a bracket forms a place rather than building a
    /// value: its bounds settle where the bracket is written and fold into an
    /// offset, so all the site does with one is read it. Everywhere else a
    /// range is a construction and each end is given up into it, which is what
    /// the walk over expressions says -- so the two are told apart here, at
    /// the one position where a range is not a value.
    fn indexExpr(self: *Builder, id: ExprId) std.mem.Allocator.Error!void {
        const at = self.ast.withoutGroups(id);
        if (self.ast.exprTag(at) == .range) {
            const ends = self.ast.rangeEnds(at);
            try self.expr(ends.lhs, .reading);
            try self.expr(ends.rhs, .reading);
            return;
        }
        try self.expr(id, .reading);
    }

    /// Records a use of a constant's static storage. A constant holds no state
    /// an operation could change, so the graph gets no operation; the plan
    /// still says the use reads a place rather than computing a value.
    fn staticRead(self: *Builder, id: ExprId) !void {
        if (self.at == .none) return;
        try self.static_reads.put(self.gpa, id, {});
    }

    fn placeOperation(self: *const Builder, id: ExprId, position: Position) Op.Tag {
        // A rejected place has no established value to consume. Its operands
        // are still evaluated before this operation is classified.
        if (self.rejectedPlace(id)) return .read;
        return if (position == .consuming and !self.typing.isScalarSnapshot(self.placeType(id))) .consume else .read;
    }

    /// The type the checker gave the place `id` names: a name's binding, or
    /// a selection's selected place.
    fn placeType(self: *const Builder, id: ExprId) types_mod.TypeId {
        if (self.ast.refersToBinding(id)) {
            const b = self.res.targetOf(id);
            return if (b == BindingId.none) .poison else self.typing.bindingType(b);
        }
        return self.typing.selected_places.get(id) orelse self.typing.exprType(id);
    }

    /// Whether the checker rejected the place `id` names -- a name naming
    /// nothing, a binding it could give no type, a field the type does not
    /// have -- so no value is established there. A name of a function, a
    /// type or a constant names no place, so none is rejected.
    fn rejectedPlace(self: *const Builder, id: ExprId) bool {
        if (self.ast.refersToBinding(id)) {
            const b = self.res.targetOf(id);
            if (b == BindingId.none) return true;
            switch (self.res.kindOf(b)) {
                .local, .parameter, .binder, .capture => {},
                .constant, .function, .declared_type, .builtin_type, .trait, .module, .associated_type, .type_parameter, .type_alias => return false,
            }
        }
        if (self.ast.refersToBinding(id)) return self.placeType(id) == .poison;
        if (self.typing.selected_places.get(id)) |selected| return selected == .poison;
        return self.typing.isRefused(id);
    }

    fn selection(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        try self.walkIndexes(id);
        var steps = self.ast.placeSteps(id);
        var depth: u32 = 0;
        var rejected = false;
        while (steps.next()) |step| {
            depth += self.selectionDepth(step);
            if (!self.typing.selected_places.contains(step)) rejected = true;
        }
        const at = steps.at;
        if (self.res.constantReached(self.ast, id)) try self.staticRead(id);

        // An invalid path transfers no field; an incompatible expected type
        // leaves a resolved selection's position intact. Every path step is
        // checked because deferred index validation can reject an inner bracket.
        //
        // The steps that were accepted still name part of the root, and a
        // consuming position still takes that part. No part is ever moved out
        // of a binding, so the consume below is refused as a partial move and
        // transfers nothing; a rejected step counts at least one level, which
        // keeps it partial.
        if (rejected) {
            try self.expr(at, .reading);
            if (!self.ast.refersToBinding(at) or self.placeOperation(id, position) != .consume) return;
            depth = @max(depth, 1);
        } else if (!self.ast.refersToBinding(at)) {
            try self.expr(at, .reading);
            try self.emit(self.placeOperation(id, position), .{ .root = .none }, id);
            return;
        }

        const b = self.res.targetOf(at);
        if (b == BindingId.none) return;
        switch (self.res.kindOf(b)) {
            .local, .parameter, .binder, .capture => {},
            // A function or a type is not a value and has no state.
            // Exhaustive, with no `else`, so a kind of name added later says
            // which side of this it falls on before the build succeeds.
            .constant, .function, .declared_type, .builtin_type, .trait, .module, .associated_type, .type_parameter, .type_alias => return,
        }

        try self.emit(
            self.placeOperation(id, position),
            .{ .root = b, .depth = depth },
            id,
        );
    }

    /// The left side of an assignment: the place that becomes initialised.
    /// A place written, and `updating` whether the write also reads what was
    /// there.
    fn assigned(self: *Builder, id: ExprId, updating: bool, source: ExprId) std.mem.Allocator.Error!void {
        try self.walkIndexes(id);
        // A rejected destination names no storage to read or replace. Its
        // index and right-hand-side expressions still contribute their effects.
        if (self.typing.exprType(id) == .poison) return;
        const path = self.pathOf(id);
        const depth = path.depth;
        const at = path.root;
        if (!self.ast.refersToBinding(at)) return;

        const b = self.res.targetOf(at);
        if (b == BindingId.none) return;
        // Writing a part reaches through the binding to find it, so it is a
        // use of that binding -- and using one that has been moved is [O-Move]
        // like any other use. Without this the write is unremarked and a value
        // moved into it is held by something that is not there.
        //
        // A compound assignment reads at every depth, including zero: it is
        // defined by what was in the place, where a plain assignment replaces a
        // whole binding without looking at it.
        if (depth > 0 or updating) try self.emit(.read, .{ .root = b, .depth = depth }, id);

        // Assigning a whole binding refills a hole a move left. Assigning a
        // part does not, which is why the depth is kept -- and it is counted
        // rather than flattened to one, so what the graph holds is the place
        // that was written and not a summary of it.
        try self.emit(.init, .{ .root = b, .depth = depth }, id);
        if (self.at != .none) {
            self.ops.items(.source)[self.ops.len - 1] = source;
            self.ops.items(.replaces)[self.ops.len - 1] = true;
        }
    }

    /// A call or a structure literal: the callee's conventions decide each
    /// argument's position, and a literal's fields are all consuming.
    fn call(self: *Builder, id: ExprId) std.mem.Allocator.Error!void {
        const c = self.ast.call(id);

        if (self.ast.exprTag(id) == .struct_literal) {
            // A struct literal holds names and values alternately; a field
            // initialiser takes the value. A base is written last and taken
            // last, whole, and the parts of it that a written field replaces
            // are dropped with nothing left holding them.
            try self.building.append(self.gpa, id);
            defer _ = self.building.pop();

            var i: usize = 1;
            while (i < c.args.len) : (i += 2) try self.expr(c.args[i], .consuming);
            if (self.ast.structLiteralBase(id)) |base| {
                try self.expr(base, .consuming);
                i = 0;
                while (i + 1 < c.args.len) : (i += 2) {
                    try self.emit(.replaced, .{ .root = .none }, c.args[i]);
                    if (self.at != .none) self.ops.items(.source)[self.ops.len - 1] = base;
                }
            }
            try self.commit(id);
            return;
        }

        // A conversion observes its operand and yields something else, exactly
        // as `-a` does. It is written as a call, so the position an argument
        // would sit in is not the one this sits in. The checker records which
        // calls are conversions, including ones with a symbolic integer target.
        if (self.typing.conversionTarget(id)) |_| {
            for (c.args) |a| try self.expr(a, .reading);
            return;
        }

        const normal = self.calls.callOf(self.typing, id);

        // A variant carries what it is given, and a literal with no callee is
        // built out of its operands: neither names a function, so there are no
        // conventions to read and every argument is given up -- which is a
        // consuming position. A refused call is the exception; see
        // `refusedCall`, and `refused` for what counts as one.
        if (self.refused(id)) {
            try self.building.append(self.gpa, id);
            defer _ = self.building.pop();
            try self.refusedCall(id, c.callee, c.args, self.calls.recoveredCallOf(self.typing, id));
            try self.commit(id);
            return;
        }

        if (normal == null) {
            try self.building.append(self.gpa, id);
            defer _ = self.building.pop();
            for (c.args) |a| try self.expr(a, .consuming);
            try self.commit(id);
            return;
        }

        try self.building.append(self.gpa, id);
        defer _ = self.building.pop();

        const normalized = normal.?;
        if (normalized.target.calleeIsValue()) try self.expr(c.callee, if (normalized.callee_convention == .sink) .consuming else .reading);
        for (normalized.args, 0..) |a, i| {
            // A parameter the call omitted receives a constant spliced at
            // lowering. It names no place, was moved from nowhere and belongs
            // to nobody, so there is nothing here for the graph to hold.
            if (a == ExprId.none) continue;

            const position: Position = if (normalized.argumentConvention(self.typing, i) == .sink)
                .consuming
            else
                .reading;
            try self.expr(a, position);
        }
        try self.commit(id);
    }

    /// A closure refused for naming a binding of the body around it without
    /// capturing it, reported once, and whether the enclosing walk marks that
    /// binding unsettled where the closure is written.
    ///
    /// Whether the body takes the binding is decided the way every position
    /// is: the body is walked by a builder of its own, whose graph is read
    /// and discarded, since a refused closure is never checked. A binding
    /// the body takes or changes needs a capture that moves it in, so on
    /// this path whether the closure took it is unknown; one it only reads
    /// needs `[name]`, which takes nothing.
    fn uncapturedName(self: *Builder, closure_id: resolve_mod.ClosureId) std.mem.Allocator.Error!bool {
        if (self.uncaptured_unsettles.get(closure_id)) |unsettles| return unsettles;
        const descriptor = self.typing.closures[closure_id.index()];
        const lambda = self.res.closures.exprOf(closure_id);
        const free = self.res.freeReferenceOf(closure_id);
        const binding = self.res.targetOf(free);
        var walk: Builder = .{
            .gpa = self.gpa,
            .ast = self.ast,
            .res = self.res,
            .typing = self.typing,
            .calls = self.calls,
            .declared_in_loops = self.declared_in_loops,
            .lends = self.lends,
            .lasting_lends = self.lasting_lends,
            .scope_of = self.scope_of,
            .scratch = true,
            .scratch_written = self.scratch_written,
        };
        defer walk.deinit();
        // A closure whose check never reached its body has none to walk.
        if (descriptor.expr == lambda) try walk.closure(closure_id, descriptor);
        const takes = binding != BindingId.none and for (walk.ops.items(.tag), walk.ops.items(.place)) |tag, place| {
            if (tag == .consume and place.root == binding) break true;
        } else false;
        const unsettles = takes or descriptor.uncaptured_changed;
        try self.uncaptured_unsettles.put(self.gpa, closure_id, unsettles);
        try self.uncaptured.append(self.gpa, .{ .lambda = lambda, .free = free, .takes = takes, .changes = descriptor.uncaptured_changed });
        return unsettles;
    }

    /// The names that closures nested in a refused closure take or change
    /// without capturing them, where they are declared outside it. No walk
    /// reaches the refused body, so the enclosing walk marks each such name
    /// unsettled where the refused closure is written: fixing the inner
    /// closure makes the refused one capture the name too, so on this path
    /// whether it was taken is unknown.
    ///
    /// The resolver numbers a closure before the closures in its body, so
    /// those are the ones after it whose tokens lie inside its own, and the
    /// scan stops at the first that is not. A walk meets a refused closure
    /// only in a body it walks, and never walks a refused body, so a nested
    /// closure is scanned once for each walked body that holds a refused
    /// closure around it: once, unless accepted and refused closures
    /// alternate around it.
    fn unsettleNestedUncaptured(self: *Builder, refused_id: resolve_mod.ClosureId) std.mem.Allocator.Error!void {
        const outer = self.ast.exprTokens(self.res.closures.exprOf(refused_id));
        var i = refused_id.index() + 1;
        while (i < self.res.closures.count()) : (i += 1) {
            const nested: resolve_mod.ClosureId = .at(@intCast(i));
            const at = self.ast.exprTokens(self.res.closures.exprOf(nested)).start.index();
            if (at < outer.start.index() or at >= outer.end.index()) break;
            const free = self.res.freeReferenceOf(nested);
            if (free == ExprId.none) continue;
            const binding = self.res.targetOf(free);
            if (binding == BindingId.none) continue;
            const declared = self.res.declaringToken(binding).index();
            if (declared >= outer.start.index() and declared < outer.end.index()) continue;
            if (try self.uncapturedName(nested)) try self.unsettle(free);
        }
    }

    /// Whether the checker refused the construct `id` builds, so it builds
    /// no value and does not run: a call with no accepted record whose callee
    /// is written, and either a recovery kept for its arguments or a refusal
    /// of its own; a structure literal, a `copy` or a closure the checker
    /// refused; a walk whose binder the checker refused, because what it walks
    /// is no sequence it may walk; a place the checker rejected. A construct
    /// whose value was built and only fails to fit its context is not
    /// refused. Every reader of "was this refused" asks here -- the call walk,
    /// a walk's head, a `copy`, a `let` whose initialiser this is, and the
    /// choice of which closure bodies are checked.
    fn refused(self: *const Builder, id: ExprId) bool {
        const at = self.ast.withoutGroups(id);
        return switch (self.ast.exprTag(at)) {
            .call => self.calls.callOf(self.typing, at) == null and
                self.ast.call(at).callee != ExprId.none and
                (self.calls.recoveredCallOf(self.typing, at) != null or self.typing.isRefused(at)),
            .struct_literal, .tuple_literal, .copy_, .lambda => self.typing.isRefused(at),
            .for_ => self.typing.isRefused(self.ast.call(at).args[0]),
            .name_ref, .param_argument, .field => self.rejectedPlace(at),
            else => false,
        };
    }

    /// A call the checker refused. It does not run, but what is written in it
    /// is still walked: a call inside an argument still runs, and naming a
    /// value already taken is still a use of it.
    ///
    /// Where the callee was resolved -- the call was refused for a bound, a
    /// mismatch or an argument that does not fit -- its conventions are known
    /// and the recovery the checker kept carries them: a `read` or `inout`
    /// argument is placed exactly as an accepted call places it. Only what the
    /// call would have taken is unknown: an argument at a `sink` position,
    /// and every argument and the callee of a call whose callee was never
    /// resolved. Such a place is read and then marked unsettled, since on
    /// this path whether the call took it is unknown; a value no place names
    /// is handed to the call, since nothing can name it afterwards.
    fn refusedCall(self: *Builder, id: ExprId, callee: ExprId, args: []const ExprId, recovery: ?types_mod.RecoveredCall) std.mem.Allocator.Error!void {
        var taken: std.ArrayList(ExprId) = .empty;
        defer taken.deinit(self.gpa);
        if (recovery) |kept| {
            if (kept.target.calleeIsValue()) try self.refusedOperand(callee, kept.callee_convention, &taken);
            for (self.calls.recoveredArgsOf(self.typing, id)) |argument| {
                try self.refusedOperand(argument.argument, argument.convention, &taken);
            }
        } else {
            // A postfix callee's operand is its receiver; any other callee
            // is itself the operand. A literal has no callee.
            if (callee != ExprId.none) {
                const selected = postfixSelection(self.ast, callee);
                if (isPostfixCallee(self.ast, self.res, selected))
                    try self.refusedOperand(fieldBase(self.ast, selected), .sink, &taken)
                else
                    try self.refusedOperand(callee, .sink, &taken);
            }
            for (args) |a| try self.refusedOperand(a, .sink, &taken);
        }
        for (taken.items) |place| try self.unsettle(place);
    }

    /// One operand of a refused call, at the convention it would have been
    /// received with: `sink` for one whose convention is unknown.
    ///
    /// A place the operand lends with `&`, or one a consuming position would
    /// only read -- a scalar snapshot such as `holder.row` -- cannot be given
    /// away, so it is read and nothing more; `placeOperation` is what says
    /// which positions take a place.
    fn refusedOperand(self: *Builder, id: ExprId, convention: node.Convention, taken: *std.ArrayList(ExprId)) std.mem.Allocator.Error!void {
        if (convention != .sink) return self.expr(id, .reading);
        if (!self.namesAPlace(id)) return self.expr(id, .consuming);
        try self.expr(id, .reading);
        const place = postfixSelection(self.ast, id);
        if (self.ast.exprTag(place) == .marked) return;
        if (self.placeOperation(place, .consuming) != .consume) return;
        try taken.append(self.gpa, place);
    }

    /// Whether an argument names a place rooted in a binding, through a `&`
    /// mark and every selection, rather than yielding a value no place names.
    fn namesAPlace(self: *const Builder, id: ExprId) bool {
        return self.res.pathBinding(self.ast, id) != BindingId.none;
    }

    /// Marks the binding a refused construct names whole as unsettled on this
    /// path: the construct had no signature or capture to say whether it
    /// would have taken it.
    fn unsettle(self: *Builder, id: ExprId) std.mem.Allocator.Error!void {
        const named = self.ast.pathRoot(id);
        if (!self.ast.refersToBinding(named)) return;
        const b = self.res.targetOf(named);
        if (b == BindingId.none) return;
        switch (self.res.kindOf(b)) {
            .local, .parameter, .binder, .capture => try self.emit(.unsettled, .{ .root = b }, named),
            .constant, .function, .declared_type, .builtin_type, .trait, .module, .associated_type, .type_parameter, .type_alias => {},
        }
    }

    /// `e?`: the operand is taken apart, and one of the two paths leaves.
    ///
    /// One exit edge and one continuation edge, which is the whole of what
    /// this adds to the graph. The failing path is what a `return`'s path
    /// already is -- every construct it was written inside is left half-built,
    /// and every scope between here and the function's end closes -- so
    /// [O-Leak] and [O-Uncommitted] are asked there without either rule
    /// knowing that `?` exists.
    fn tryExpr(self: *Builder, id: ExprId) std.mem.Allocator.Error!void {
        // Received where it is written, like a `let`'s initialiser: the `?`
        // takes the enum apart right here, so there is no interval in which
        // the construct around it has been given the enum and not received it.
        // Walked as an ordinary operand instead, `use2(get()?, …)` reports the
        // enum as pending on `use2`, which was never offered it.
        try self.received(self.ast.unaryOperand(id), .consuming);

        const from = self.at;
        if (from == .none) return;

        const leaves = try self.newBlock(id);
        try self.goTo(leaves);
        {
            // The failure exits the function, so its scheduled operations run
            // once even when the question mark is inside a repeating body.
            const was_leaving = self.leaving;
            self.leaving = 0;
            defer self.leaving = was_leaving;
            try self.escapeTo(0, id);
            try self.runScheduledTo(0, id);
            try self.endScopesTo(0, id);
            const operand = self.ast.unaryOperand(id);
            const operand_type = self.typing.exprType(operand);
            const failure = self.typing.failureVariantOf(operand_type);
            const has_payload = if (failure) |variant| self.typing.variantFieldCount(operand_type, variant) != 0 else false;
            try self.returned(id, if (has_payload) operand else .none);
            if (has_payload and self.at != .none) self.ops.items(.projection)[self.ops.len - 1] = .{ .payload = .{ .variant = failure.?, .index = 0 } };
            try self.markExit(self.at);
        }

        const continues = try self.newBlock(id);
        self.at = from;
        try self.goTo(continues);
    }

    /// Builds the graph of `e else |error| { … }`. The operand is taken apart,
    /// and the block runs on the failing path.
    ///
    /// Two paths from the operand, as a `match` with two arms has. The success
    /// path yields what the operand carried. The failing path binds what the
    /// failure carried and walks the block where the construct sits, so a
    /// block that leaves ends its path through the transfer it holds, and
    /// [O-Leak] asks there about everything still held.
    fn unwrapElse(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        const u = self.ast.unwrapElse(id);
        try self.received(u.operand, .consuming);

        const after = try self.newBlock(id);
        const from = self.at;

        if (self.at != .none) try self.goTo(try self.newBlock(u.body));
        // The binder's scope is the block, as an arm's binders' is its arm.
        const held = self.live.items.len;
        const binder = if (u.binder == ExprId.none) BindingId.none else self.res.targetOf(u.binder);
        if (binder != BindingId.none) {
            const failure = self.typing.failureVariantOf(self.typing.exprType(u.operand));
            const projection: cfg_mod.Projection = if (failure) |variant|
                .{ .payload = .{ .variant = variant, .index = 0 } }
            else
                .whole;
            try self.bindHolder(binder, id, u.operand, projection, .owned);
        }
        try self.expr(u.body, position);
        try self.value(id, u.body);
        try self.endScopesTo(held, u.body);
        self.live.shrinkRetainingCapacity(held);
        try self.link(after);

        self.at = from;
        if (self.at != .none) try self.goTo(try self.newBlock(id));
        try self.value(id, .none);
        try self.yielded(id, position);
        try self.link(after);

        try self.resume_(after);
    }

    /// Closes every transfer this construct's operands opened.
    fn commit(self: *Builder, id: ExprId) std.mem.Allocator.Error!void {
        // No place: what the construct received is a set of transfers rather
        // than one binding, and each is named by the consume that opened it.
        try self.emit(.committed, .{ .root = BindingId.none }, id);
    }

    /// A `match`: the scrutinee, then each arm from the state after it.
    ///
    /// The consuming form takes the scrutinee apart; the lending one observes
    /// it. That is the whole difference, and it is one word at the top.
    fn matchExpr(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        const m = self.ast.call(id);
        const lending = self.ast.exprTag(id) == .match_read;
        try self.received(m.callee, if (lending) .reading else .consuming);

        const after = try self.newBlock(id);
        const from = self.at;

        var i: usize = 0;
        while (i + 1 < m.args.len) : (i += 2) {
            self.at = from;
            if (self.at != .none) {
                const arm = try self.newBlock(m.args[i + 1]);
                try self.goTo(arm);
            }
            // A consuming match takes the value apart, and each binder owns
            // what it was given -- the same thing a destructuring `let` does.
            //
            // Bound inside the arm rather than before the branch. Only this
            // arm can reach its own binders, and binding them all up front put
            // every arm's on every path: each was moved on its own arm and
            // untouched on the others, so the join had no answer and a linear
            // enum carrying a payload in more than one variant was unwritable.
            const held = self.live.items.len;
            try self.bindPatternHolders(m.args[i], id, m.callee, if (lending) .lent else .owned);

            // An arm that names none of what the value held. `_` matches
            // every variant, payload and all; `Has` selects a variant and
            // takes none of what it carries. `Has(_)` binds the payload and is
            // already refused, and these two are the same claim spelled
            // differently -- §5.5 says naming nothing is a statement about not
            // using a value, not a licence to discard it.
            //
            // Whether the arm left a payload unnamed is the checker's: it
            // counted what the variant carries against what the arm bound, and
            // that count is the only thing that tells a bare `Has` over a
            // payload from a bare `Empty` over none. Asking the scrutinee's
            // type instead refuses both, because the type is linear either
            // way.
            if (!lending and (self.isWildcard(m.args[i]) or self.typing.dropsPayload(m.args[i]))) {
                // Keyed on the value, not on whether it was given a name. A
                // scrutinee is usually a temporary, and a rule that only saw
                // named ones would say `_` may drop a linear value provided
                // you did not bind it -- a rule about syntax, where ownership
                // is decided by position. The op is written at the arm, which
                // is what drops the value, and carries the scrutinee as its
                // source so the checker can ask what it is; the root may be
                // nothing at all.
                const scrutinee = self.ast.withoutGroups(m.callee);
                try self.emit(.discarded, .{ .root = self.res.targetOf(scrutinee) }, m.args[i]);
                if (self.at != .none) self.ops.items(.source)[self.ops.len - 1] = scrutinee;
            }
            // An arm is the match's value, so it sits where the match does.
            try self.expr(m.args[i + 1], position);
            try self.value(id, m.args[i + 1]);
            // A binder's scope is its arm, so this is where a value it still
            // holds is one nothing disposed of.
            try self.endScopesTo(held, m.args[i + 1]);
            try self.link(after);
        }

        try self.resume_(after);
    }

    /// `if c { a } else { b }`, whose branches are the expression's value.
    ///
    /// So a branch sits in the position the whole `if` does, and nothing about
    /// the `if` decides it: `take(if c { p.f } else { p.g })` observes what it
    /// names, exactly as `take(p.f)` would.
    fn conditional(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        const c = self.ast.conditional(id);
        try self.expr(c.cond, .reading);

        const after = try self.newBlock(id);
        const from = self.at;

        const then_block = try self.newBlock(c.then);
        self.at = from;
        try self.goTo(then_block);
        try self.expr(c.then, position);
        try self.value(id, c.then);
        try self.link(after);

        if (c.otherwise != ExprId.none) {
            const else_block = try self.newBlock(c.otherwise);
            self.at = from;
            try self.goTo(else_block);
            try self.expr(c.otherwise, position);
            try self.value(id, c.otherwise);
            try self.link(after);
        } else {
            // No `else` is a path through the `if` that does nothing, which is
            // exactly the path a merge has to consider.
            self.at = from;
            try self.link(after);
        }

        try self.resume_(after);
    }

    /// A value reached on one path only.
    ///
    /// `a && b` evaluates `b` when `a` holds and skips it otherwise, and the
    /// arm it supplies instead -- a `false` or a `true` -- consumes nothing. So
    /// this is the shape `conditional` builds when there is no `else`: one
    /// branch that does something and one that does not, merging after.
    fn logical(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        const b = self.ast.binary(id);
        try self.expr(b.lhs, .reading);

        const after = try self.newBlock(id);
        const from = self.at;

        const taken = try self.newBlock(b.rhs);
        self.at = from;
        try self.goTo(taken);
        try self.expr(b.rhs, position);
        try self.link(after);

        // The path that skips the right operand. A merge has to consider it,
        // which is what makes a move inside `b` a move on one path only.
        self.at = from;
        try self.link(after);

        try self.resume_(after);
    }

    /// `for x in xs { … }`: the sequence is taken once, then a loop whose
    /// body may not run at all.
    ///
    /// The sequence sits in a consuming position, so `xs` moves at the head
    /// and every later use of it is [O-Moved] against a consume this pass
    /// records where the loop is written. Nothing about the loop decides
    /// that -- a value written where a walk begins is a value the walk takes,
    /// which is the same rule a `let` initialiser and a `match` scrutinee
    /// already answer to.
    ///
    /// The binder is declared inside the head, so the loop stack already
    /// holds this loop when it is recorded: [O-Loop] then reads a linear
    /// element consumed on one iteration as consumed once per iteration,
    /// which is exactly what it is. Its scope ends where the body does, which
    /// is what makes each iteration's element a fresh value rather than the
    /// previous one moved again.
    fn forExpr(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        const f = self.ast.call(id);

        // `for read` and `for inout` observe the places rather than taking
        // them. That is the whole difference, and it is one word at the top --
        // the same word, and the same difference, a `match read` makes.
        const lending = self.ast.exprTag(id) != .for_;

        // Before the head, and once: the walk begins from a value it took,
        // and it takes it whether or not the body ever runs. A lending walk
        // takes nothing -- it names places inside a value that stays where it
        // is -- so what it does to the head is what reading one does.
        //
        // Taken while the exemption around it still stands. The head runs
        // once for each time the walk is reached, exactly as a call argument
        // does, so a walk written in a `break` or a `return` operand takes
        // its sequence as often as that operand is evaluated -- and reading
        // the syntactic loop depth here would refuse a program that consumes
        // its sequence once, while the same walk behind a call is accepted.
        //
        // A refused walk never runs, and whether it would have taken its head
        // is not something a later use can be held to, so the head is placed
        // as a refused call's `sink` operand is: read, then left unsettled.
        if (!lending and self.refused(id)) {
            var taken: std.ArrayList(ExprId) = .empty;
            defer taken.deinit(self.gpa);
            try self.refusedOperand(f.callee, .sink, &taken);
            for (taken.items) |place| try self.unsettle(place);
        } else try self.received(f.callee, if (lending) .reading else .consuming);

        // The body is what repeats, however few times the operand around the
        // walk is evaluated, so the exemption ends here and not above.
        const was_leaving = self.leaving;
        self.leaving = null;
        defer self.leaving = was_leaving;

        const head = try self.newBlock(id);
        try self.goTo(head);

        // `for x in &it` calls `next` on `it` at the head of every iteration,
        // which changes it as an `inout` argument does. Recorded against the
        // mark, where a marked call's change is recorded against the call.
        if (!lending and self.ast.exprTag(f.callee) == .marked) try self.commit(f.callee);

        // Where taking the sequence left control, which is the head only when
        // that expression had no control flow of its own.
        const from = self.at;

        const after = try self.newBlock(id);
        const inside = try self.newBlock(id);

        self.at = from;
        try self.link(inside);
        // A walk that has run out never enters the body.
        try self.link(after);

        try self.loops.append(self.gpa, .{
            .result = id,
            .after = after,
            .again = head,
            .yields = position,
            .live = self.live.items.len,
            .scheduled = self.scheduled.items.len,
            .building = self.building.items.len,
            .statements = self.statements.items.len,
        });
        defer _ = self.loops.pop();

        try self.resume_(inside);

        const held = self.live.items.len;
        // A tuple pattern takes each element apart into one binder per
        // component. A lending walk gives every component the whole element's
        // place, so a write through one is a write to the place the others
        // read.
        const holding: Holding = if (lending) .lent else .owned;
        if (self.ast.exprTag(f.args[0]) == .tuple_pattern) {
            for (self.ast.call(f.args[0]).args) |component| {
                const binder = self.res.targetOf(component);
                if (binder == BindingId.none) continue;
                try self.bindHolder(binder, component, f.callee, self.walkedPart(id, component, lending), holding);
            }
        } else {
            const binder = self.res.targetOf(f.args[0]);
            if (binder != BindingId.none) {
                try self.bindHolder(binder, f.args[0], f.callee, self.walkedPart(id, f.args[0], lending), holding);
            }
        }

        // The body runs once per iteration, so its temporaries end with each.
        try self.beginStatement(f.args[1]);
        try self.expr(f.args[1], .reading);
        try self.endStatement();

        // The binder's scope is one iteration, so what it still holds at the
        // bottom of the body is a value nothing disposed of.
        try self.endScopesTo(held, f.args[1]);

        // The back edge, which is the reason this is a graph and not a tree.
        try self.link(head);

        try self.resume_(after);
    }

    fn loopExpr(self: *Builder, id: ExprId, position: Position) std.mem.Allocator.Error!void {
        const is_while = self.ast.exprTag(id) == .while_;

        // A loop written inside a `break` or a `return` operand runs its own
        // body as many times as it says, however few times the operand around
        // it is evaluated. The exemption belongs to what leaves, and this loop
        // is not what leaves -- left standing, [O-Loop] stopped applying to
        // every body a `return` happened to enclose.
        const was_leaving = self.leaving;
        self.leaving = null;
        defer self.leaving = was_leaving;

        const head = try self.newBlock(id);
        try self.goTo(head);

        // A condition is evaluated once per iteration, so its temporaries end
        // with each evaluation.
        if (is_while) {
            try self.beginStatement(self.ast.binary(id).lhs);
            try self.expr(self.ast.binary(id).lhs, .reading);
            try self.endStatement();
        }

        // Where the condition's control flow ended, which is the head only
        // when the condition had none of its own. A condition holding an `if`,
        // a `match` or a `&&` finishes in that construct's merge, and the loop
        // branches from there -- read as the head, the merge kept no way out
        // and everything the condition did to a value stopped inside it.
        const from = self.at;

        const after = try self.newBlock(id);
        const inside = try self.newBlock(id);

        self.at = from;
        try self.link(inside);
        // A `while` may not run its body at all.
        if (is_while) try self.link(after);

        try self.loops.append(self.gpa, .{
            .result = id,
            .after = after,
            .again = head,
            .yields = position,
            .live = self.live.items.len,
            .scheduled = self.scheduled.items.len,
            .building = self.building.items.len,
            .statements = self.statements.items.len,
        });
        defer _ = self.loops.pop();

        try self.resume_(inside);

        // The body runs once per iteration, so its temporaries end with each.
        const b = if (is_while) self.ast.binary(id).rhs else self.ast.unaryOperand(id);
        try self.beginStatement(b);
        try self.expr(b, .reading);
        try self.endStatement();

        // The back edge, which is the reason this is a graph and not a tree.
        try self.link(head);

        try self.resume_(after);
    }
};

const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const Source = @import("../support/source.zig").Source;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;

/// What one program's graph looks like, for a test to assert against.
const Built = struct {
    consumes: u32,
    reads: u32,
    inits: u32,
    /// Scopes ended, which is what the exits below name between them. Counted
    /// by walking the stack each exit holds, so a test that says how many
    /// bindings die also says the stack it walked was the right one.
    deaths: u32,
    /// Operations that end a scope, which is one per exit however many scopes
    /// the exit ends.
    exits: u32,
    /// Consumes that a construct has yet to receive, and the constructs that
    /// received them.
    pending: u32,
    /// Linear values made where they were given up, counted apart because a
    /// place and a value the program never named are what the two halves of
    /// this rule are about.
    transfers: u32,
    commits: u32,
    /// Constructs control left before they had received anything.
    escapes: u32,
    blocks: usize,
    exit_blocks: usize,
    zero_edge_blocks: usize,
    zero_edge_nonexit_blocks: usize,
    unreachable_blocks: usize,
    unreachable_exit_blocks: usize,
    unreachable_zero_edge_nonexit_blocks: usize,
    /// Whether any block has more than one way in, which is what makes a
    /// merge a merge.
    joins: bool,
    /// Whether any edge returns to an earlier block, which is what makes a
    /// loop a loop in the graph rather than only in the tree.
    back_edge: bool,
};

fn expectExitIsSink(cfg: *const Cfg) !void {
    for (cfg.blocks, 0..) |block, i| {
        if (cfg.isExit(BlockId.at(i))) {
            try testing.expectEqual(@as(usize, 0), cfg.edgesOf(block).len);
        }
    }
}

fn graphOf(gpa: std.mem.Allocator, text: []const u8) !Built {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;

    const source: Source = .{ .path = "case.lin", .text = text };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);

    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);

    var cfg = try build(gpa, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(gpa);
    try testing.expectEqual(cfg.blocks.len, cfg.exits.len());
    try expectExitIsSink(&cfg);

    var reachable = try gpa.alloc(bool, cfg.blocks.len);
    defer gpa.free(reachable);
    @memset(reachable, false);
    const pending = try gpa.alloc(BlockId, cfg.blocks.len);
    defer gpa.free(pending);
    var pending_end: usize = 0;
    for (cfg.functions) |function| {
        if (reachable[function.entry.index()]) continue;
        reachable[function.entry.index()] = true;
        pending[pending_end] = function.entry;
        pending_end += 1;
    }
    var pending_at: usize = 0;
    while (pending_at < pending_end) : (pending_at += 1) {
        for (cfg.edgesOf(cfg.blocks[pending[pending_at].index()])) |edge| {
            if (edge == .none or reachable[edge.index()]) continue;
            reachable[edge.index()] = true;
            pending[pending_end] = edge;
            pending_end += 1;
        }
    }

    var got: Built = .{
        .consumes = 0,
        .reads = 0,
        .inits = 0,
        .deaths = 0,
        .exits = 0,
        .pending = 0,
        .transfers = 0,
        .commits = 0,
        .escapes = 0,
        .blocks = cfg.blocks.len,
        .exit_blocks = 0,
        .zero_edge_blocks = 0,
        .zero_edge_nonexit_blocks = 0,
        .unreachable_blocks = 0,
        .unreachable_exit_blocks = 0,
        .unreachable_zero_edge_nonexit_blocks = 0,
        .joins = false,
        .back_edge = false,
    };
    for (0..cfg.ops.len) |i| {
        const op = OpId.at(@intCast(i));
        switch (cfg.opTag(op)) {
            .consume => {
                got.consumes += 1;
                if (cfg.opPendingFor(op) != ExprId.none) got.pending += 1;
            },
            // Counted by settlement obligation. The
            // builder records every transfer and the checker decides which ones
            // owe anything, so a tally of what this rule is about has to filter
            // where the checker does -- otherwise every integer written into a
            // literal shows up as a value in flight.
            .transferred => {
                if (cfg.opPendingFor(op) != ExprId.none and
                    typing.mustConsume(typing.exprType(cfg.opAt(op))))
                {
                    got.transfers += 1;
                }
            },
            .read => got.reads += 1,
            .init => got.inits += 1,
            .dies => {
                got.exits += 1;
                const run = cfg.opRun(op);
                var s = run.top;
                while (s != ScopeId.none and cfg.scopes[s.index()].depth > run.mark) {
                    got.deaths += 1;
                    s = cfg.scopes[s.index()].outer;
                }
            },
            .committed => got.commits += 1,
            .escaped => got.escapes += 1,
            .copied, .discarded, .replaced, .value, .returned, .lent, .temporaries_end, .unsettled => {},
        }
    }

    var incoming = try gpa.alloc(u32, cfg.blocks.len);
    defer gpa.free(incoming);
    @memset(incoming, 0);
    for (cfg.blocks, 0..) |block, i| {
        const id = BlockId.at(i);
        const is_exit = cfg.isExit(id);
        const has_no_edges = cfg.edgesOf(block).len == 0;
        if (is_exit) got.exit_blocks += 1;
        if (has_no_edges) got.zero_edge_blocks += 1;
        if (has_no_edges and !is_exit) got.zero_edge_nonexit_blocks += 1;
        if (!reachable[i]) {
            got.unreachable_blocks += 1;
            if (is_exit) got.unreachable_exit_blocks += 1;
            if (has_no_edges and !is_exit) got.unreachable_zero_edge_nonexit_blocks += 1;
        }
        for (cfg.edgesOf(block)) |edge| {
            if (edge != .none) {
                incoming[edge.index()] += 1;
                if (edge.index() <= i) got.back_edge = true;
            }
        }
    }
    for (incoming) |n| {
        if (n > 1) got.joins = true;
    }
    return got;
}

test "builder sink invariant covers every control-flow shape" {
    const fallthrough = try graphOf(testing.allocator,
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(usize, 1), fallthrough.exit_blocks);
    try testing.expectEqual(@as(usize, 1), fallthrough.zero_edge_blocks);

    const returning = try graphOf(testing.allocator,
        \\fn main() -> UInt8 { return 0 }
    );
    try testing.expectEqual(@as(usize, 1), returning.exit_blocks);
    try testing.expectEqual(@as(usize, 1), returning.zero_edge_blocks);

    const question = try graphOf(testing.allocator,
        \\enum Option[T] { None, Some(T) }
        \\fn pass(input: Option[UInt8]) -> Option[UInt8] {
        \\    let value = input?
        \\    Option.Some(value)
        \\}
    );
    try testing.expectEqual(@as(usize, 2), question.exit_blocks);
    try testing.expectEqual(@as(usize, 2), question.zero_edge_blocks);

    const rejoining = try graphOf(testing.allocator,
        \\fn main() -> UInt8 { if true { 1 } else { 2 } }
    );
    try testing.expectEqual(@as(usize, 1), rejoining.exit_blocks);
    try testing.expectEqual(@as(usize, 1), rejoining.zero_edge_blocks);
    try testing.expect(rejoining.joins);

    const looping = try graphOf(testing.allocator,
        \\fn main() -> UInt8 {
        \\    var n: UInt8 = 0
        \\    while n < 1 { n = n + 1 }
        \\    n
        \\}
    );
    try testing.expectEqual(@as(usize, 1), looping.exit_blocks);
    try testing.expectEqual(@as(usize, 1), looping.zero_edge_blocks);
    try testing.expect(looping.back_edge);

    const all_return = try graphOf(testing.allocator,
        \\fn main() -> UInt8 {
        \\    if true { return 1 } else { return 2 }
        \\}
    );
    try testing.expectEqual(@as(usize, 4), all_return.blocks);
    try testing.expectEqual(@as(usize, 2), all_return.exit_blocks);
    try testing.expectEqual(@as(usize, 3), all_return.zero_edge_blocks);
    try testing.expectEqual(@as(usize, 1), all_return.zero_edge_nonexit_blocks);
    try testing.expectEqual(@as(usize, 1), all_return.unreachable_blocks);
    try testing.expectEqual(@as(usize, 0), all_return.unreachable_exit_blocks);
    try testing.expectEqual(@as(usize, 1), all_return.unreachable_zero_edge_nonexit_blocks);
}

test "scalar snapshots read local field and indexed places" {
    const got = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\fn snapshots(held: Held, numbers: [UInt8; 1], number: UInt8) -> UInt8 {
        \\    let local = number
        \\    let field = held.number
        \\    let indexed = numbers[0]
        \\    local + field + indexed
        \\}
    );
    try testing.expectEqual(@as(u32, 0), got.consumes);
    try testing.expectEqual(@as(u32, 6), got.reads);
}

test "scalar snapshots retain place types after contextual errors" {
    const sources = [_][]const u8{
        \\struct Held { number: UInt8 }
        \\fn main() -> UInt8 { let held: Held = .{ number = 7 }; let _wrong: Bool = held.number; held.number }
        ,
        \\fn main() -> UInt8 { let numbers: [UInt8; 1] = [7]; let _wrong: Bool = numbers[0]; numbers[0] }
        ,
        \\fn main() -> UInt8 { let number: UInt8 = 7; let _wrong: Bool = number; number }
        ,
    };
    for (sources) |source| {
        const got = try graphOf(testing.allocator, source);
        try testing.expectEqual(@as(u32, 0), got.consumes);
    }
}

test "a `let` consumes its initialiser and initialises its binding" {
    // The initializer and function result occupy consuming positions.
    const got = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\fn main() -> Held {
        \\    let a: Held = .{ number = 1 };
        \\    let b = a;
        \\    b
        \\}
    );
    // `a` in `let b = a`, and `b` as the body's trailing value -- a function's
    // result is a consuming position exactly as a `return` operand is.
    try testing.expectEqual(@as(u32, 2), got.consumes);
    try testing.expectEqual(@as(u32, 2), got.inits);
    try testing.expectEqual(@as(u32, 2), got.deaths);
}

test "an operand is read and an argument follows its convention" {
    const got = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\fn lend(n: Held) -> UInt8 { n.number }
        \\fn take(sink n: Held) -> Held { n }
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1;
        \\    let b: Held = .{ number = a + 1 };
        \\    let saved = lend(b); let Held { number } = take(b); saved + number
        \\}
    );
    // The scalar arithmetic and field are read. The sink argument and the
    // aggregate returned from `take` transfer their source places.
    try testing.expectEqual(@as(u32, 2), got.consumes);
    try testing.expectEqual(@as(u32, 5), got.reads);
}

test "a rejected selection reads its source without transferring a field" {
    const got = try graphOf(testing.allocator,
        \\struct Pair { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let pair: Pair = .{ value = 1 }
        \\    pair.missing
        \\}
    );
    try testing.expectEqual(@as(u32, 0), got.consumes);
    try testing.expectEqual(@as(u32, 1), got.reads);
}

test "a contextual mismatch preserves a selected field's consuming position" {
    const got = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\struct Pair { value: Held }
        \\fn main() -> UInt8 {
        \\    let pair: Pair = .{ value = .{ number = 1 } }
        \\    let _wrong: Bool = pair.value
        \\    0
        \\}
    );
    try testing.expectEqual(@as(u32, 1), got.consumes);
    try testing.expectEqual(@as(u32, 0), got.reads);
}

test "a contextual mismatch preserves an indexed element's consuming position" {
    const got = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\fn main() -> UInt8 {
        \\    let values: [Held; 1] = [.{ number = 1 }]
        \\    let _wrong: Bool = values[0]
        \\    0
        \\}
    );
    try testing.expectEqual(@as(u32, 1), got.consumes);
    try testing.expectEqual(@as(u32, 0), got.reads);
}

test "a call refused for a generic mismatch reads the places it names" {
    const got = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\struct Flag {}
        \\struct Pair { value: Held }
        \\fn same[T: Discardable](sink _a: T, sink _b: T) -> () {}
        \\fn main() -> UInt8 {
        \\    let pair: Pair = .{ value = .{ number = 1 } }
        \\    let flag: Flag = .{}
        \\    same(flag, pair.value)
        \\    0
        \\}
    );
    try testing.expectEqual(@as(u32, 0), got.consumes);
    try testing.expectEqual(@as(u32, 2), got.reads);
}

test "a rejected call reads its arguments" {
    const got = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\fn take(sink _n: Held) -> () {}
        \\fn main() -> Held {
        \\    let a: Held = .{ number = 1 }
        \\    let b: Held = .{ number = 2 }
        \\    take(a, b)
        \\    b
        \\}
    );
    // The refused call reads `a` and `b` and takes neither, and the trailing
    // `b` is the function result.
    try testing.expectEqual(@as(u32, 1), got.consumes);
    try testing.expectEqual(@as(u32, 2), got.reads);
}

test "a refused tuple literal reads its components and takes none of them" {
    // The undefined component poisons the literal, which is then walked as a
    // refused call is: `a` is read and left unsettled, and nothing is
    // consumed.
    const got = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\fn main() -> UInt8 {
        \\    let a: Held = .{ number = 1 }
        \\    let _pair = (a, nope)
        \\    0
        \\}
    );
    try testing.expectEqual(@as(u32, 0), got.consumes);
    try testing.expectEqual(@as(u32, 1), got.reads);
}

test "rejected callable recovery evaluates the callee before its arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "case.lin", .text =
        \\@linear enum Key { Held(UInt8) }
        \\fn identity(value: UInt8) -> UInt8 { value }
        \\fn choose(sink key: Key) -> fn(read value: UInt8) -> UInt8 {
        \\    match key { Held(_) => {} }
        \\    identity
        \\}
        \\fn main() -> UInt8 {
        \\    let key = Key.Held(1)
        \\    let first: UInt8 = 2
        \\    let second: UInt8 = 3
        \\    choose(key)(first, second)
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);
    var cfg = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(testing.allocator);

    const expected = [_][]const u8{ "key", "first", "second" };
    var found: usize = 0;
    for (cfg.functions) |function| {
        if (function.decl == .none or !std.mem.eql(u8, ast.tokenText(ast.declName(function.decl)), "main")) continue;
        for (function.blocks.start..function.blocks.end) |block| {
            var ops = cfg.opsOf(cfg.blocks[block]);
            while (ops.next()) |op| {
                if (cfg.opTag(op) != .consume and cfg.opTag(op) != .read) continue;
                const text = ast.exprText(cfg.opAt(op));
                if (found < expected.len and std.mem.eql(u8, text, expected[found])) found += 1;
            }
        }
    }
    try testing.expectEqual(expected.len, found);
}

test "a construct that takes several values says where it took them" {
    // Two arguments given up into one call, and one operation saying the call
    // received them. Without the second, the graph records a value leaving its
    // owner and nothing about it arriving.
    const got = try graphOf(testing.allocator,
        \\@linear struct Key {
        \\    n: UInt8,
        \\}
        \\
        \\fn use2(sink a: Key, sink b: Key) -> UInt8 {
        \\    let Key { n: x } = a
        \\    let Key { n: y } = b
        \\    x + y
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let one: Key = .{ n = 1 }
        \\    let two: Key = .{ n = 2 }
        \\    use2(one, two)
        \\}
    );
    // Only the call's two arguments are transfers a construct has yet to
    // receive: a field initialiser here is a literal, which opens none.
    try testing.expectEqual(@as(u32, 2), got.pending);
    // Three constructs take a value and say so: each `.{ … }` and the call.
    try testing.expectEqual(@as(u32, 3), got.commits);
    // Nothing leaves, so nothing is left half-built.
    try testing.expectEqual(@as(u32, 0), got.escapes);
}

test "a jump says which constructs it left half-built" {
    const key =
        \\@linear struct Key {
        \\    n: UInt8,
        \\}
        \\
        \\fn use2(sink a: Key, sink b: Key) -> UInt8 {
        \\    let Key { n: x } = a
        \\    let Key { n: y } = b
        \\    x + y
        \\}
        \\
        \\fn key() -> Key {
        \\    .{ n = 2 }
        \\}
        \\
    ;

    // A `return` leaves everything the function was in the middle of, and
    // nothing receives what was given up on the way there.
    const returning = try graphOf(testing.allocator, key ++
        \\fn go(sink d: Key) -> UInt8 {
        \\    use2(d, return 7)
        \\}
    );
    try testing.expectEqual(@as(u32, 1), returning.escapes);

    // A loop written as an operand is inside the call that takes it, so
    // leaving the loop leaves nothing: the call begins where the loop yields.
    const breaking = try graphOf(testing.allocator, key ++
        \\fn go(sink d: Key) -> UInt8 {
        \\    use2(d, loop { break key() })
        \\}
    );
    try testing.expectEqual(@as(u32, 0), breaking.escapes);
    // The call still receives them, which is what makes the two answers
    // different questions rather than the same one twice.
    try testing.expectEqual(@as(u32, 1), breaking.pending);
}

test "what a break carries out is owed to whatever takes the loop" {
    // A `break` hands its value to the loop, and the loop yields where it was
    // written -- so the value is owed to the construct that takes the loop,
    // from the `break` onwards. Reading the operand as received at the `break`
    // closes the transfer at a point that owns nothing afterwards, and a jump
    // in the next operand then crosses a transfer the graph says is shut.
    const got = try graphOf(testing.allocator,
        \\@linear struct Key {
        \\    n: UInt8,
        \\}
        \\
        \\fn use2(sink a: Key, sink b: Key) -> UInt8 {
        \\    let Key { n: x } = a
        \\    let Key { n: y } = b
        \\    x + y
        \\}
        \\
        \\fn go(sink d: Key, sink e: Key) -> UInt8 {
        \\    use2(loop { break e }, d)
        \\}
    );
    // `e` carried out of the loop and `d` written beside it: both owed to
    // `use2`, and neither received before it begins.
    try testing.expectEqual(@as(u32, 2), got.pending);
    // The loop is not a construct anything waits on, so the only thing that
    // receives here is the call.
    try testing.expectEqual(@as(u32, 1), got.commits);
}

test "a value made where it is given up is owed to the construct around it" {
    // `key()` names no place, so nothing keyed by a place could follow it. The
    // transfer is recorded against the expression that made the value, which
    // is the only name a message could give it.
    const got = try graphOf(testing.allocator,
        \\@linear struct Key {
        \\    n: UInt8,
        \\}
        \\
        \\fn use2(sink a: Key, sink b: Key) -> UInt8 {
        \\    let Key { n: x } = a
        \\    let Key { n: y } = b
        \\    x + y
        \\}
        \\
        \\fn key() -> Key {
        \\    .{ n = 2 }
        \\}
        \\
        \\fn go(sink d: Key) -> UInt8 {
        \\    use2(key(), d)
        \\}
    );
    // `d` is a place and opens a transfer keyed by one.
    try testing.expectEqual(@as(u32, 1), got.pending);
    // `key()` in `go` is the only Linear value made where it was given up:
    // the literal in `key`'s own body is the function's result and waits on
    // no construct, and the `2` inside it owes nothing.
    try testing.expectEqual(@as(u32, 1), got.transfers);
}

test "a statement inside a block argument is received where it is written" {
    // A block argument's statements complete on their own: `let held = e`
    // hands the value to `held`, not to the call the block sits in. Only the
    // block's tail is the construct's own operand.
    const got = try graphOf(testing.allocator,
        \\@linear struct Key {
        \\    n: UInt8,
        \\}
        \\
        \\fn use2(sink a: Key, sink b: Key) -> UInt8 {
        \\    let Key { n: x } = a
        \\    let Key { n: y } = b
        \\    x + y
        \\}
        \\
        \\fn go(sink d: Key, sink e: Key) -> UInt8 {
        \\    use2(
        \\        {
        \\            let held = e
        \\            held
        \\        },
        \\        d,
        \\    )
        \\}
    );
    // `use2`'s own two operands in `go`, and `use2`'s own body destructures
    // rather than moving. `let held = e` is not among them.
    try testing.expectEqual(@as(u32, 2), got.pending);
}

test "a branch is the expression's value, so it sits where the expression does" {
    // The branches of an `if` are what it evaluates to, so each sits in the
    // position the whole `if` does. Written as always-consuming, an `if` in a
    // reading position took what its branches named -- and a program that
    // observes a value through one was refused for moving it.
    const reading = try graphOf(testing.allocator,
        \\fn lend(n: Held) -> Held { n }
        \\struct Held { number: UInt8 }
        \\fn main() -> Held {
        \\    let a: Held = .{ number = 1 };
        \\    let b: Held = .{ number = 2 };
        \\    lend(if true { a } else { b })
        \\}
    );
    // `a` and `b` are read, and `n` leaving `lend` is the only move.
    try testing.expectEqual(@as(u32, 2), reading.reads);
    try testing.expectEqual(@as(u32, 1), reading.consumes);

    // The same `if` where the value is taken.
    const consuming = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\fn main() -> Held {
        \\    let a: Held = .{ number = 1 };
        \\    let b: Held = .{ number = 2 };
        \\    let c: Held = if true { a } else { b };
        \\    c
        \\}
    );
    try testing.expectEqual(@as(u32, 0), consuming.reads);
    try testing.expectEqual(@as(u32, 3), consuming.consumes);
}

test "an arm is the match's value, so it sits where the match does" {
    const got = try graphOf(testing.allocator,
        \\enum Colour { Red, Green }
        \\fn lend(n: Held) -> Held { n }
        \\struct Held { number: UInt8 }
        \\fn main() -> Held {
        \\    let a: Held = .{ number = 1 };
        \\    let b: Held = .{ number = 2 };
        \\    lend(match Colour.Red { Red => a, Green => b })
        \\}
    );
    try testing.expectEqual(@as(u32, 2), got.reads);
    try testing.expectEqual(@as(u32, 1), got.consumes);
}

test "an operator observes its operand, and parentheses do not" {
    // `-` and a conversion produce a new value from one they only looked at,
    // so the operand is read whatever position the operation sits in. Grouped
    // with parentheses -- which *are* transparent -- the position passed
    // straight through and `let b = -a` moved `a`.
    const operators = try graphOf(testing.allocator,
        \\fn main() -> UInt8 {
        \\    let a: Int64 = 5;
        \\    let b: Int64 = -a;
        \\    let c: UInt8 = UInt8(a);
        \\    UInt8(a + b) + c
        \\}
    );
    // Five reads: `a` under `-`, under the conversion and inside the sum,
    // then `b` and `c` as operands of `+`. Nothing is taken -- every `let`
    // here is initialised by an operator, which yields a value of its own.
    try testing.expectEqual(@as(u32, 5), operators.reads);
    try testing.expectEqual(@as(u32, 0), operators.consumes);

    // Parentheses preserve the consuming position of an aggregate.
    const grouped = try graphOf(testing.allocator,
        \\struct Held { number: UInt8 }
        \\fn main() -> Held {
        \\    let a: Held = .{ number = 5 };
        \\    let b: Held = (a);
        \\    b
        \\}
    );
    try testing.expectEqual(@as(u32, 0), grouped.reads);
    try testing.expectEqual(@as(u32, 2), grouped.consumes);
}

test "parentheses do not hide a place" {
    // Parentheses are a node so a formatter can put them back, which means a
    // walk that asks what an expression names has to step through them.
    // Stopping at one left `(o).z` naming nothing: a move out of a part went
    // unrecorded, and the rule that would have refused it never ran.
    const got = try graphOf(testing.allocator,
        \\struct Outer { z: UInt8 }
        \\fn main() -> UInt8 {
        \\    let o: Outer = .{ z = 2 };
        \\    let n: UInt8 = (o).z;
        \\    n
        \\}
    );
    // `(o).z` reads the selected scalar while preserving the owner.
    try testing.expect(got.reads > 0);
}

test "a scope exit says what dies there" {
    // The only operation that says where "still live" stops being true, which
    // is the whole of the leak check. One operation names the whole stretch of
    // the stack that ends, so the count of bindings is what the stack says and
    // not what the graph holds.
    const got = try graphOf(testing.allocator,
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1;
        \\    let b: UInt8 = 2;
        \\    a + b
        \\}
    );
    try testing.expectEqual(@as(u32, 2), got.deaths);
    try testing.expectEqual(@as(u32, 1), got.exits);
}

test "an early exit ends every scope it is written inside, in one operation" {
    // A `return` and a `?` each leave every scope between where they are
    // written and the function's end. One operation names the whole stretch,
    // so a body of n early exits over n live bindings is a graph of n and not
    // of n squared -- and the stretch still says which bindings die.
    const got = try graphOf(testing.allocator,
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1;
        \\    { let b: UInt8 = 2; return a + b }
        \\}
    );
    try testing.expectEqual(@as(u32, 2), got.deaths);
    try testing.expectEqual(@as(u32, 1), got.exits);
}

test "an `if` makes a block two ways can reach" {
    // A merge is a block with more than one way in. Without one there is
    // no incoming ownership states to disagree, and O-Merge could not fire.
    const got = try graphOf(testing.allocator,
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1;
        \\    if a == 1 { 2 } else { 3 }
        \\}
    );
    try testing.expect(got.joins);
    try testing.expect(got.blocks >= 4);
}

test "an `if` with no `else` still has a path that does nothing" {
    // The path a merge has to consider: one arm moved something and the other
    // arm is not written down.
    const got = try graphOf(testing.allocator,
        \\fn main() -> UInt8 {
        \\    var a: UInt8 = 1;
        \\    if a == 1 { a = 2; }
        \\    a
        \\}
    );
    try testing.expect(got.joins);
}

test "an `inout` parameter's binding list belongs to the graph" {
    // The only allocation a function owns beyond the arrays the graph itself
    // holds, so it is the only one a caller freeing the graph can miss. The
    // driver hands this pass an arena and would never notice; a checked
    // allocator here is what says the graph frees what it allocated.
    const got = try graphOf(testing.allocator,
        \\fn refill(inout n: UInt8) -> UInt8 {
        \\    n = 2
        \\    0
        \\}
        \\fn main() -> UInt8 {
        \\    var a: UInt8 = 1;
        \\    let r = refill(&a);
        \\    a + r
        \\}
    );
    try testing.expect(got.blocks > 0);
}

test "lend bits classify lending binders and borrowed let binders last until their last use" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "case.lin", .text =
        \\struct Pair {
        \\    a: UInt8,
        \\    b: UInt8,
        \\}
        \\fn classify(
        \\    read_parameter: UInt8,
        \\    pair: Pair,
        \\    inout items: [UInt8; 1],
        \\    sink taken: Pair,
        \\) -> UInt8 {
        \\    var total = read_parameter
        \\    let read Pair { a: let_lend, b: _ } = pair
        \\    total += let_lend
        \\    total += match read pair {
        \\        Pair { a: match_lend, b: _ } => match_lend,
        \\    }
        \\    for read for_read in items {
        \\        total += for_read
        \\    }
        \\    for inout for_inout in items {
        \\        for_inout = for_inout
        \\    }
        \\    total + match taken {
        \\        Pair { a: consuming, b: _ } => consuming,
        \\    }
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);
    var cfg = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, res.resolution.bindingCount()), cfg.lends.len());
    try testing.expectEqual(@as(usize, res.resolution.bindingCount()), cfg.lasting_lends.len());
    const expected = [_]struct { name: []const u8, lend: bool, lasting: bool = false }{
        .{ .name = "let_lend", .lend = true, .lasting = true },
        .{ .name = "match_lend", .lend = true },
        .{ .name = "for_read", .lend = true },
        .{ .name = "for_inout", .lend = true },
        .{ .name = "consuming", .lend = false },
        .{ .name = "read_parameter", .lend = false },
    };
    for (expected) |want| {
        var found = BindingId.none;
        for (0..res.resolution.bindingCount()) |i| {
            const binding = BindingId.at(@intCast(i));
            const token = res.resolution.declaringToken(binding);
            if (token == .none) continue;
            const name = ast.tokenText(token);
            if (std.mem.eql(u8, name, want.name)) {
                found = binding;
                break;
            }
        }
        try testing.expect(found != .none);
        try testing.expectEqual(want.lend, cfg.isLend(found));
        try testing.expectEqual(want.lasting, cfg.isLastingLend(found));
    }
}

test "a refused postfix call marks its receiver and arguments unsettled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "case.lin", .text =
        \\@linear
        \\struct Ticket { seat: UInt8 }
        \\fn main() -> UInt8 {
        \\    let ticket = Ticket { seat = 3 }
        \\    let voucher = Ticket { seat = 4 }
        \\    let kept = Ticket { seat = 5 }
        \\    ticket.exchange(voucher)
        \\    let Ticket { seat } = kept
        \\    seat
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);
    var cfg = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(testing.allocator);

    const expected = [_]struct { name: []const u8, unsettled: bool }{
        .{ .name = "ticket", .unsettled = true },
        .{ .name = "voucher", .unsettled = true },
        .{ .name = "kept", .unsettled = false },
    };
    for (expected) |want| {
        var found = BindingId.none;
        for (0..res.resolution.bindingCount()) |i| {
            const binding = BindingId.at(@intCast(i));
            const token = res.resolution.declaringToken(binding);
            if (token == .none) continue;
            if (std.mem.eql(u8, ast.tokenText(token), want.name)) {
                found = binding;
                break;
            }
        }
        try testing.expect(found != .none);
        var marked = false;
        for (cfg.ops.items(.tag), cfg.ops.items(.place)) |tag, place| {
            if (tag == .unsettled and place.root == found) marked = true;
        }
        try testing.expectEqual(want.unsettled, marked);
    }
}

test "a loop has a back edge" {
    // The reason this is a graph and not a tree: a fixpoint needs the edge
    // that returns, and a subtree has no such thing.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;

    const source: Source = .{ .path = "case.lin", .text =
        \\fn main() -> UInt8 {
        \\    var a: UInt8 = 1;
        \\    while a == 1 { a = 2; }
        \\    a
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);
    var cfg = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(testing.allocator);

    // Some edge goes to a block that is not after the one it leaves.
    var backward = false;
    for (cfg.blocks, 0..) |blk, i| {
        for (cfg.edgesOf(blk)) |e| {
            if (e != .none and e.index() <= i) backward = true;
        }
    }
    try testing.expect(backward);
}

test "a walk's tuple pattern binds each component, owned or lent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    // The program is its own prelude, so the tuple syntax names the pair
    // declared here.
    const source: Source = .{ .path = "case.lin", .text =
        \\@copyable
        \\pub struct Tuple2[A, B] { _0: A, _1: B }
        \\
        \\fn main() -> UInt8 {
        \\    let pairs = [(UInt8(1), UInt8(2))]
        \\    var total: UInt8 = 0
        \\    for (taken, other) in pairs {
        \\        total += taken + other
        \\    }
        \\    for read (seen, also) in pairs {
        \\        total += seen + also
        \\    }
        \\    total
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    res.resolution.prelude = res.expanded.declsOf(.from(0));
    res.resolution.tuple_decls = resolve_mod.tupleDeclsIn(&res.expanded.ast, res.resolution.prelude);
    var typing = try typecheckTree(scratch, &res, &sink);
    var cfg = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(testing.allocator);

    const expected = [_]struct { name: []const u8, tag: cfg_mod.Op.Tag, field: ?[]const u8 }{
        .{ .name = "taken", .tag = .init, .field = "_0" },
        .{ .name = "other", .tag = .init, .field = "_1" },
        .{ .name = "seen", .tag = .lent, .field = null },
        .{ .name = "also", .tag = .lent, .field = null },
    };
    for (expected) |want| {
        var found = BindingId.none;
        for (0..res.resolution.bindingCount()) |i| {
            const binding = BindingId.at(@intCast(i));
            const token = res.resolution.declaringToken(binding);
            if (token == .none) continue;
            if (std.mem.eql(u8, ast.tokenText(token), want.name)) found = binding;
        }
        try testing.expect(found != .none);

        var bound = false;
        for (cfg.ops.items(.tag), cfg.ops.items(.place), cfg.ops.items(.projection)) |tag, place, projection| {
            if (place.root != found or tag != want.tag) continue;
            bound = true;
            if (want.field) |field| {
                try testing.expect(projection == .element_component);
                try testing.expectEqualStrings(field, interner.textOf(projection.element_component).?);
            } else {
                try testing.expect(projection == .index);
            }
        }
        try testing.expect(bound);
    }
}

test "a lambda parameter's tuple pattern binds each component under the parameter's convention" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "case.lin", .text =
        \\@copyable
        \\pub struct Tuple2[A, B] { _0: A, _1: B }
        \\
        \\fn owned[F: fn(sink pair: (UInt8, UInt8)) -> UInt8](sink pair: (UInt8, UInt8), take: F) -> UInt8 {
        \\    take(pair)
        \\}
        \\
        \\fn lent[F: fn(read pair: (UInt8, UInt8)) -> UInt8](pair: (UInt8, UInt8), take: F) -> UInt8 {
        \\    take(pair)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    owned((1, 2), |sink (taken, other)| taken + other) + lent((3, 4), |(seen, also)| seen + also)
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    res.resolution.prelude = res.expanded.declsOf(.from(0));
    res.resolution.tuple_decls = resolve_mod.tupleDeclsIn(&res.expanded.ast, res.resolution.prelude);
    var typing = try typecheckTree(scratch, &res, &sink);
    var cfg = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(testing.allocator);

    const expected = [_]struct { name: []const u8, tag: cfg_mod.Op.Tag, field: []const u8 }{
        .{ .name = "taken", .tag = .init, .field = "_0" },
        .{ .name = "other", .tag = .init, .field = "_1" },
        .{ .name = "seen", .tag = .lent, .field = "_0" },
        .{ .name = "also", .tag = .lent, .field = "_1" },
    };
    for (expected) |want| {
        var found = BindingId.none;
        for (0..res.resolution.bindingCount()) |i| {
            const binding = BindingId.at(@intCast(i));
            const token = res.resolution.declaringToken(binding);
            if (token == .none) continue;
            if (std.mem.eql(u8, ast.tokenText(token), want.name)) found = binding;
        }
        try testing.expect(found != .none);

        var bound = false;
        for (cfg.ops.items(.tag), cfg.ops.items(.place), cfg.ops.items(.projection)) |tag, place, projection| {
            if (place.root != found or tag != want.tag) continue;
            bound = true;
            try testing.expect(projection == .field);
            try testing.expectEqualStrings(want.field, interner.textOf(projection.field).?);
        }
        try testing.expect(bound);
    }
}

test "nested loops record bounded operation and declaration depths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "case.lin", .text =
        \\fn main() -> UInt8 {
        \\    var _outer: UInt8 = 0
        \\    while _outer < 1 {
        \\        let _first: UInt8 = 1
        \\        while _outer < 1 {
        \\            let _second: UInt8 = 2
        \\            _outer = _outer + 1
        \\        }
        \\    }
        \\    _outer
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);
    var cfg = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(testing.allocator);

    var outer = BindingId.none;
    var first = BindingId.none;
    var second = BindingId.none;
    for (0..res.resolution.bindingCount()) |i| {
        const binding = BindingId.at(@intCast(i));
        const token = res.resolution.declaringToken(binding);
        if (token == .none) continue;
        const spelling = ast.tokenText(token);
        if (std.mem.eql(u8, spelling, "_outer")) outer = binding;
        if (std.mem.eql(u8, spelling, "_first")) first = binding;
        if (std.mem.eql(u8, spelling, "_second")) second = binding;
    }
    try testing.expect(outer != .none and first != .none and second != .none);
    try testing.expectEqual(@as(LoopDepth, 0), cfg.declared_in_loops[outer.index()]);
    try testing.expectEqual(@as(LoopDepth, 1), cfg.declared_in_loops[first.index()]);
    try testing.expectEqual(@as(LoopDepth, 2), cfg.declared_in_loops[second.index()]);

    var inner_op: ?OpId = null;
    for (cfg.blocks) |block| {
        var ops = cfg.opsOf(block);
        while (ops.next()) |op| {
            if (cfg.opTag(op) == .init and cfg.opPlace(op).root == outer) inner_op = op;
        }
    }
    try testing.expect(inner_op != null);
    try testing.expectEqual(@as(LoopDepth, 2), cfg.opLoops(inner_op.?));
}

test "deferred and exit loop depths compose within the bounded domain" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const nesting = node.max_tree_height / 2 + 1;
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(scratch, "fn main() -> UInt8 {\n    defer ");
    for (0..nesting) |_| try text.appendSlice(scratch, "while false {\n");
    try text.appendSlice(scratch, "let _ignored: UInt8 = 0\n");
    for (0..nesting) |_| try text.appendSlice(scratch, "}\n");
    for (0..nesting) |_| try text.appendSlice(scratch, "while true {\n");
    try text.appendSlice(scratch, "return 0\n");
    for (0..nesting) |_| try text.appendSlice(scratch, "}\n");
    try text.appendSlice(scratch, "0\n}\n");

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "case.lin", .text = text.items };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);
    try testing.expect(!sink.hasErrors());
    var cfg = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(testing.allocator);

    var deepest: LoopDepth = 0;
    for (0..cfg.ops.len) |i| deepest = @max(deepest, cfg.opLoops(OpId.at(@intCast(i))));
    try testing.expectEqual(@as(LoopDepth, @intCast(2 * nesting)), deepest);
}

test "ownership skips suppressed generated bodies but builds unrelated bodies" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "case.lin", .text =
        \\trait Measured {}
        \\trait Inspect { fn inspect(self: Self) -> UInt8 }
        \\template impl Inspect
        \\where reflect.components: Measured
        \\{
        \\    fn inspect(_self: Self) -> UInt8 { 0 }
        \\}
        \\struct Box[T] { value: T }
        \\derive[T] Inspect for Box[T]
        \\fn _unrelated() -> UInt8 { 1 }
        \\fn main() -> UInt8 { 0 }
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var resolved = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &resolved, &sink);
    try testing.expectEqual(@as(usize, 1), typing.suppressed_generated_bodies.len);

    var cfg = try build(testing.allocator, &resolved.expanded, &resolved.resolution, &typing);
    defer cfg.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), cfg.functions.len);
    for (cfg.functions) |function| {
        try testing.expect(function.decl != typing.suppressed_generated_bodies[0]);
        try testing.expect(resolved.expanded.originOf(function.decl) == null);
    }
}

test "every block's edges are one contiguous run and the runs tile the array" {
    // What grouping the pairs by block has to produce, stated directly: each
    // block's run begins where the previous one ended, and together they cover
    // the edge array exactly. A block whose edges were scattered, counted
    // twice or dropped breaks this whatever the program was.
    const gpa = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const scratch = arena.allocator();

    var sink = Sink.init(scratch);
    var interner: Interner = .empty;

    // Branches inside branches inside a loop, so blocks gain their edges well
    // out of block order -- which is the whole reason the pairs are kept and
    // grouped rather than appended as they are found.
    const source: Source = .{ .path = "case.lin", .text =
        \\fn main() -> UInt8 {
        \\    var n: UInt8 = 0;
        \\    while n < 9 {
        \\        if n < 3 { n = n + 1 } else { if n < 5 { n = n + 2 } else { n = n + 3 } }
        \\    }
        \\    n
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);
    var cfg = try build(gpa, &res.expanded, &res.resolution, &typing);
    defer cfg.deinit(gpa);

    var next: u32 = 0;
    var with_two: usize = 0;
    for (cfg.blocks) |blk| {
        try testing.expectEqual(next, blk.edges.start);
        try testing.expect(blk.edges.end >= blk.edges.start);
        if (blk.edges.end - blk.edges.start == 2) with_two += 1;
        next = blk.edges.end;
    }
    try testing.expectEqual(@as(u32, @intCast(cfg.edges.len)), next);

    // The loop head and the two `if`s each leave two ways, so a grouping that
    // tiled the array while losing an edge would still have to answer this.
    try testing.expectEqual(@as(usize, 3), with_two);
}

test "ownership continuation omits exact retained bodies and their closures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "case.lin", .text =
        \\fn saved() -> UInt8 {
        \\    let f: fn(read n: UInt8) -> UInt8 = |n| n
        \\    f(1)
        \\}
        \\fn main() -> UInt8 {
        \\    let g: fn(read n: UInt8) -> UInt8 = |n| n
        \\    saved() + g(2)
        \\}
    };
    const tokens = try tokenize(scratch, &source, .from(0), &sink, &interner);
    var ast = try parse(scratch, &source, .from(0), tokens, &sink);
    var res = try resolve_mod.resolveTree(scratch, &ast, &sink);
    var typing = try typecheckTree(scratch, &res, &sink);
    try testing.expect(!sink.hasErrors());
    var declarations: std.AutoHashMapUnmanaged(DeclId, void) = .empty;
    defer declarations.deinit(testing.allocator);
    for (0..ast.declCount()) |i| {
        const d: DeclId = .at(@intCast(i));
        if (ast.declTag(d) == .function and std.mem.eql(u8, ast.tokenText(ast.declName(d)), "saved")) {
            try declarations.put(testing.allocator, d, {});
        }
    }
    try testing.expectEqual(@as(u32, 1), declarations.count());
    var whole = try build(testing.allocator, &res.expanded, &res.resolution, &typing);
    defer whole.deinit(testing.allocator);
    var remainder = try buildRemaining(testing.allocator, &res.expanded, &res.resolution, &typing, &declarations);
    defer remainder.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 4), whole.functions.len);
    try testing.expectEqual(@as(usize, 2), remainder.functions.len);
    for (remainder.functions) |function| try testing.expect(!declarations.contains(function.owner));
}
