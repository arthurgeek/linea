const array_initialization = @import("array_initialization.zig");
const std = @import("std");
const tracy = @import("../support/tracy.zig");
const testing = std.testing;

const Source = @import("../support/source.zig").Source;
const Span = @import("../support/span.zig").Span;
const generatedCall = instantiate_mod.generatedCall;
const LayoutDecls = instantiate_mod.LayoutDecls;
const FileId = @import("../support/source.zig").FileId;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Code = @import("../diagnostics/diagnostic.zig").Code;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const Ast = @import("../syntax/ast.zig").Ast;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const syntax_node = @import("../syntax/node.zig");
const ExprId = syntax_node.ExprId;
const DeclId = syntax_node.DeclId;
const StmtId = syntax_node.StmtId;
const resolve_mod = @import("../sema/resolve.zig");
const resolveTree = resolve_mod.resolveTree;
const Resolution = resolve_mod.Resolution;
const BindingId = resolve_mod.BindingId;
const types_mod = @import("../sema/types.zig");
const Typing = types_mod.Typing;
const TypeId = types_mod.TypeId;
const Layout = types_mod.Layout;
const typecheck = @import("../sema/typecheck.zig").typecheck;
const isCatchAll = @import("../sema/typecheck.zig").isCatchAll;
const lentReceiver = @import("../sema/typecheck.zig").lentReceiver;
const DisposalPlan = @import("../ownership/cfg.zig").DisposalPlan;
const checkOwnershipTree = @import("../ownership/check.zig").checkTree;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;
const rendersDisplayItself = @import("../sema/typecheck.zig").rendersDisplayItself;
const FormattingDecls = @import("../sema/typecheck.zig").FormattingDecls;
const FormattingTarget = @import("../sema/typecheck.zig").FormattingTarget;
const preludeDecl = @import("../sema/typecheck.zig").preludeDecl;
const equatableDecl = @import("../sema/typecheck.zig").equatableDecl;
const comparableDecl = @import("../sema/typecheck.zig").comparableDecl;
const steppableDecl = @import("../sema/typecheck.zig").steppableDecl;
const traitMemberNamed = @import("../sema/typecheck.zig").traitMemberNamed;
const bodyParametersOf = @import("../sema/typecheck.zig").bodyParametersOf;
const sequenceDecl = @import("../sema/typecheck.zig").sequenceDecl;
const iteratorDecl = @import("../sema/typecheck.zig").iteratorDecl;
const instantiate_mod = @import("../sema/instantiate.zig");
const instantiate = instantiate_mod.instantiate;
const InstanceTableBuilder = instantiate_mod.TableBuilder;
const InstanceTable = instantiate_mod.InstanceTable;
const RawAccesses = instantiate_mod.RawAccesses;
const mir_mod = @import("mir.zig");
const Mir = mir_mod.Mir;
const Module = mir_mod.Module;
const FunctionId = mir_mod.FunctionId;
const Inst = mir_mod.Inst;
const InstId = mir_mod.InstId;
const BlockId = mir_mod.BlockId;
const LocalId = mir_mod.LocalId;
const TrapKind = mir_mod.TrapKind;

/// Resolution owns whether the roots need an entry point and which purpose
/// that entry serves. Lowering reads the same choice.
pub const Purpose = @import("../sema/resolve.zig").Purpose;

/// Lowers a standalone resolved tree using ownership's complete disposal plan.
/// Discovery settles its instances before emission turns nesting into sequence,
/// bound names into locals, and explicit parentheses into their operands.
pub fn lowerTree(
    gpa: std.mem.Allocator,
    resolved: *const resolve_mod.ResolvedTree,
    typing: *const Typing,
    disposals: *const DisposalPlan,
    sink: *Sink,
    purpose: Purpose,
) !?Module {
    return lowerProgram(gpa, &resolved.expanded, &resolved.resolution, typing, disposals, sink, purpose);
}

/// Composes semantic instance discovery with emission for callers that need a
/// module and do not retain the pass result between the two.
pub fn lowerProgram(
    gpa: std.mem.Allocator,
    program: *const ExpandedProgram,
    resolution: *const Resolution,
    typing: *const Typing,
    disposals: *const DisposalPlan,
    sink: *Sink,
    purpose: Purpose,
) !?Module {
    if (sink.hasErrors()) return null;
    var instances = try instantiate(gpa, program, resolution, typing, disposals, sink, purpose);
    defer instances.deinit();
    try program.collapseGeneratedDiagnostics(sink);
    if (sink.hasErrors()) return null;
    return try lower(gpa, program, resolution, typing, &instances, disposals, sink, purpose);
}

/// Emits exactly the instances discovery supplied.
///
/// Checking and discovery must have accepted the program. Invalid semantic
/// states here are compiler defects, not another source-recovery path.
/// Consumes discovery's sealed type pool; its instance keys remain borrowed.
pub fn lower(
    gpa: std.mem.Allocator,
    program: *const ExpandedProgram,
    resolution: *const Resolution,
    typing: *const Typing,
    discovery: *instantiate_mod.Instantiation,
    disposals: *const DisposalPlan,
    sink: *const Sink,
    purpose: Purpose,
) !Module {
    const zone = tracy.beginZone(@src(), "lower");
    defer zone.end();

    const ast = &program.ast;

    std.debug.assert(!sink.hasErrors());
    std.debug.assert(discovery.pool.sealed);
    const table = discovery.table();
    const instances = &table;

    var mono: Mono = .{
        .gpa = gpa,
        .pool = discovery.pool,
        .instances = instances,
    };
    discovery.pool = .{ .gpa = gpa };
    defer mono.deinit();

    // Every body borrows the checker's frozen site index.
    const z_idx = tracy.beginZone(@src(), "lower.indexes");
    const calls = &typing.call_index;

    const library: LibraryDecls = .{
        .raw = typing.raw_accesses,
        .float_math = typing.float_math,
        .report = generatedCall(program, "report"),
        .ran = generatedCall(program, "ran"),
        .selected = generatedCall(program, "selected"),
        .no_such_test = generatedCall(program, "no_such_test"),
        .formatting = FormattingDecls.init(ast, resolution),
        .layouts = LayoutDecls.init(program),
        .equatable = equatableDecl(ast, resolution),
        .comparable = comparableDecl(ast, resolution),
        .equals = traitMemberNamed(ast, resolution, equatableDecl(ast, resolution), "equals"),
        .less = traitMemberNamed(ast, resolution, comparableDecl(ast, resolution), "less"),
        .forward = traitMemberNamed(ast, resolution, steppableDecl(ast, resolution), "forward"),
        .backward = traitMemberNamed(ast, resolution, steppableDecl(ast, resolution), "backward"),
        .sequence = sequenceDecl(ast, resolution),
        .iterate = traitMemberNamed(ast, resolution, sequenceDecl(ast, resolution), "iterate"),
        .iterator = iteratorDecl(ast, resolution),
        .next = traitMemberNamed(ast, resolution, iteratorDecl(ast, resolution), "next"),
    };

    z_idx.end();

    const local_of_binding = try gpa.alloc(LocalId, resolution.bindingCount());
    defer gpa.free(local_of_binding);
    @memset(local_of_binding, LocalId.at(0));

    // Which entries the function being lowered has written, so the next one
    // puts back what this one disturbed instead of clearing the whole table.
    // Cleared per function it cost the program's bindings for every function
    // lowered, and a body writes only its own.
    var touched: std.ArrayList(u32) = .empty;
    defer touched.deinit(gpa);

    // The entry is a lookup into the finished set, not the root of a second
    // reachability walk. `.none` names a library or a fragment with no runtime
    // entry, while a test binary receives its generated dispatcher below.
    var entry: FunctionId = .none;
    if (purpose == .program and resolution.entry != DeclId.none) {
        entry = mono.idFor(resolution.entry, &.{}, .poison, &.{});
    }

    // A test binary's entry point, which is written here because no source
    // declares one. Discovery has already included every test and generated
    // library call it makes. It is held rather than appended because its index
    // has to follow every source function.
    const dispatches = purpose == .tests;
    var dispatcher: ?Mir = if (!dispatches) null else try buildDispatcher(
        gpa,
        ast,
        resolution,
        typing,
        disposals,
        calls,
        local_of_binding,
        &touched,
        &mono,
        library,
    );
    errdefer if (dispatcher) |*d| d.deinit(gpa);

    var lowered: std.ArrayList(Mir) = .empty;
    // The functions in it as well as the list holding them: each one owns its
    // own instructions, and a later function failing does not make the earlier
    // ones anybody else's.
    errdefer {
        for (lowered.items) |*m| m.deinit(gpa);
        lowered.deinit(gpa);
    }

    // Which declaration each function came from, and what this instantiation
    // makes of the parameters its types hold. Built as each is lowered, so the
    // bindings a body was lowered through are the ones a reader rendering it
    // reads back rather than a second derivation of them.
    var origins: std.ArrayList(mir_mod.Origin) = .empty;
    errdefer {
        for (origins.items) |o| {
            gpa.free(o.args);
            gpa.free(o.impl_args);
        }
        origins.deinit(gpa);
    }

    // Discovery is complete: emission iterates the immutable answer once and
    // no body can append work behind this cursor.
    for (instances.instances) |instance| {
        const w = instance.key;
        const source_decl = switch (w.body) {
            .declaration => |decl| decl,
            .closure => |closure| typing.closureOf(closure).enclosing,
            .closure_release => typing.closure_release.?.member,
            .constructor => |constructor| constructor.enclosing,
            .erased_entry => typing.raw_accesses.closure_entry,
            .erased_settle => typing.raw_accesses.closure_settle,
            .built_in, .viewed => |at| at.member,
        };

        // What the receiver bound the enclosing implementation's parameters
        // to -- or, for a trait's provided operation, the trait's -- travels
        // as `impl_args`. A member of an implementation generic over its head
        // is checked in terms of those parameters and lowered in terms of what
        // one receiver made them, exactly as a generic function is in terms of
        // its own.
        //
        // Copied into the list, which owns both from the moment it takes them:
        // the instance table owns its arguments, and these bindings belong to
        // this emitted origin alone. Each is the caller's until the entry
        // holding it is in, so a failure between the two frees what the list
        // never took.
        {
            const parameters = bodyParametersOf(ast, resolution, typing, source_decl);
            var settled = try parameters.instantiation(gpa, w.body, source_decl, w.args, w.self_ty, w.impl_args);
            errdefer gpa.free(settled.args);
            settled.impl_args = try gpa.dupe(TypeId, w.impl_args);
            errdefer gpa.free(settled.impl_args);

            try origins.append(gpa, settled);
        }
        const origin = origins.items[origins.items.len - 1];

        // Named rather than nested, so a function that lowered has an owner
        // before the list is asked to take it. Passed straight to `append`, a
        // failure there dropped a whole function nobody could then free.
        const z_fn = tracy.beginZone(@src(), "lower.function");
        defer z_fn.end();
        var one = try lowerFunction(
            gpa,
            program,
            ast,
            resolution,
            typing,
            disposals,
            calls,
            local_of_binding,
            &touched,
            origin,
            &mono,
            library,
        );
        errdefer one.deinit(gpa);
        try lowered.append(gpa, one);
    }

    // A test binary's entry point, which is written here because no source
    // declares one. Appended after every function it calls has been lowered, so
    // the calls it makes name instantiations that exist.
    if (dispatcher) |one| {
        try lowered.append(gpa, one);
        dispatcher = null;

        // An origin beside it, because every table indexed by a function is
        // indexed by every function. The dispatcher came from no declaration,
        // which is what `.none` says here -- and a table one entry short is a
        // table whose length disagrees with the thing it describes, which the
        // reader of it finds out by reading past the end.
        try origins.append(gpa, .{
            .decl = DeclId.none,
            .args = &.{},
            .impl = DeclId.none,
            .impl_args = &.{},
        });

        entry = FunctionId.at(@intCast(lowered.items.len - 1));
    }

    const extra: usize = if (dispatches) 1 else 0;

    const names = try gpa.alloc([]const u8, instances.instances.len + extra);
    var named: usize = 0;
    errdefer {
        for (names[0..named]) |name| gpa.free(name);
        gpa.free(names);
    }
    for (instances.instances, 0..) |instance, i| {
        names[i] = try gpa.dupe(u8, instance.name);
        named += 1;
    }

    // Spelled where no program can reach: every declaration's symbol carries
    // the `;` that ends its route and a generated body's is `kind.N`, and this
    // name has neither, so it appears in no name a program spelled. That is
    // what keeps this from colliding with a test called `dispatch` written in
    // a program's root.
    //
    // Without the prefix every defined symbol carries, which the backend writes
    // and which a name held here has never included.
    if (dispatches) {
        names[names.len - 1] = try gpa.dupe(u8, "_h.dispatch");
        named += 1;
    }

    // Which of them are defined elsewhere. A call names one the way it names
    // any other function; what differs is that emitting a definition for it
    // would put a body of this compiler's invention under a name the runtime
    // already answers to.
    const external = try gpa.alloc(bool, instances.instances.len + extra);
    errdefer gpa.free(external);
    for (instances.instances, 0..) |instance, i| external[i] = switch (instance.key.body) {
        .declaration => |decl| ast.declIsExtern(decl),
        .closure_release, .closure, .constructor, .erased_entry, .erased_settle, .built_in, .viewed => false,
    };
    // Defined here, whatever else is not: this pass wrote its body.
    if (dispatches) external[external.len - 1] = false;

    // What something outside may reach, which only a library has any of. A
    // program's every caller is in this module, so nothing in one is marked and
    // the backend emits it exactly as before.
    //
    // The library's own root module, and `pub` within it. Not `pub` wherever it
    // is written: everything a program is compiled with is lowered into one
    // module, the standard library included, so marking every public
    // declaration would publish the whole of `std` out of a library that
    // called four functions of it -- and the object would hold every body
    // either of them ever defined.
    //
    // The same boundary [N-Unused] draws, and for the same reason: the root is
    // the surface something outside reaches, and nothing outside can name a
    // module below it. What this decides is only whether a body survives, not
    // what it is called -- the symbol is the one every defined function
    // carries.
    const exported = try gpa.alloc([]const u8, instances.instances.len + extra);
    errdefer gpa.free(exported);
    @memset(exported, "");
    errdefer for (exported) |n| if (n.len > 0) gpa.free(n);
    if (program.kind == .library) {
        for (instances.instances, 0..) |instance, i| {
            const decl = switch (instance.key.body) {
                .declaration => |decl| decl,
                .closure_release, .closure, .constructor, .erased_entry, .erased_settle, .built_in, .viewed => continue,
            };
            if (!program.publishesExport(decl)) continue;
            exported[i] = try gpa.dupe(u8, ast.tokenText(ast.declName(decl)));
        }
    }

    const z_lay = tracy.beginZone(@src(), "lower.layouts");
    const layouts = try gpa.alloc(Layout, mono.pool.pool.items.len);
    errdefer gpa.free(layouts);
    for (0..mono.pool.pool.items.len) |i| {
        layouts[i] = mono.pool.layoutOf(@enumFromInt(@as(u32, @intCast(i))));
    }

    const type_view = mono.pool.view();
    var representations = try mir_mod.deriveRepresentations(gpa, &type_view, layouts);
    errdefer representations.deinit(gpa);

    z_lay.end();

    // Transfer discovery's completed pool, including the names it owns.
    const z_fin = tracy.beginZone(@src(), "lower.finish");
    defer z_fin.end();
    var pool = try mono.pool.finish(.empty);
    var owned_pool = pool;
    errdefer owned_pool.deinit(gpa);

    // Carried across rather than left behind. `finish` creates a typing from
    // the pool alone, so a side table the checker built survives only by being
    // handed over -- and what a written type settled to is one nothing below
    // here can work out again. The sealed copy preserves every handle.
    pool.written_types = try gpa.dupe(TypeId, typing.written_types);
    owned_pool = pool;

    // Keep each transferred allocation owned until the final function handoff.
    const came_from = try origins.toOwnedSlice(gpa);
    errdefer {
        for (came_from) |o| {
            gpa.free(o.args);
            gpa.free(o.impl_args);
        }
        gpa.free(came_from);
    }

    const bytes = try mono.bytes.toOwnedSlice(gpa);
    errdefer {
        for (bytes) |blob| gpa.free(blob);
        gpa.free(bytes);
    }
    const statics = try mono.statics.toOwnedSlice(gpa);
    errdefer {
        for (statics) |held| gpa.free(held.parts);
        gpa.free(statics);
    }
    const functions = try lowered.toOwnedSlice(gpa);

    return .{
        .functions = functions,
        .zeroed_allocator = if (instances.zeroed_allocator == .none)
            .none
        else if (instances.lookup(instances.zeroed_allocator, &.{}, .poison, &.{})) |id|
            FunctionId.at(id.index())
        else
            .none,
        .bytes = bytes,
        .statics = statics,
        .names = names,
        .external = external,
        .exported_as = exported,
        .origins = came_from,
        .types = pool,
        .representations = representations,
        .layouts = layouts,
        .panic_message_type = if (preludeDecl(ast, resolution, "Str")) |d|
            typing.typeOfDecl(d) orelse .poison
        else
            .poison,
        .entry = entry,
    };
}

/// A constant at the erased type it is laid out at.
const StaticKey = struct {
    value: types_mod.ConstantValue,
    ty: TypeId,

    const Context = struct {
        pub fn hash(_: Context, key: StaticKey) u64 {
            var state = std.hash.Wyhash.init(@intFromEnum(key.ty));
            key.value.hash(&state);
            return state.final();
        }

        pub fn eql(_: Context, a: StaticKey, b: StaticKey) bool {
            return a.ty == b.ty and a.value.eql(b.value);
        }
    };
};

/// The immutable instance lookup and emission-local pools.
///
/// Function ids are positions in discovery's table. Recursive calls therefore
/// resolve before either body is emitted, without allowing lowering to create
/// another instance.
const Mono = struct {
    gpa: std.mem.Allocator,
    /// Every distinct blob of bytes the module names, and where each sits.
    ///
    /// Interned by content rather than by the expression that wrote it: a
    /// generic body is lowered once per instantiation, so a literal inside one
    /// would otherwise be emitted once per instantiation of a function nobody
    /// wrote twice.
    bytes: std.ArrayList([]const u8) = .empty,
    bytes_at: std.StringHashMapUnmanaged(u32) = .empty,
    /// The static holding each constant at each type a body reads it at, laid
    /// out the first time one is reached. Keyed by the checked value rather
    /// than the declaration, so two constants with one value share storage,
    /// which no program can observe: a borrow's address is not comparable.
    statics: std.ArrayList(mir_mod.Static) = .empty,
    statics_at: std.HashMapUnmanaged(StaticKey, u32, StaticKey.Context, std.hash_map.default_max_load_percentage) = .empty,
    /// Scratch for laying out a scalar constant, whose one part is its value
    /// and which needs no static.
    scratch_parts: std.ArrayList(mir_mod.StaticPart) = .empty,
    /// Discovery's completed pool, consumed without rebuilding its indexes or
    /// layouts. Substitution may read existing handles, never mint new ones.
    pool: Typing.Builder,
    instances: *const InstanceTable,

    fn callResultRole(self: *const Mono, ty: TypeId) mir_mod.ResultRole {
        return mir_mod.valueRole(self.pool.layoutOf(ty));
    }

    /// Where a run of bytes sits in the pool, adding it if it is new.
    ///
    /// Takes what the blob holds rather than how it was spelled, because not
    /// every blob was spelled: a test's name is bytes the compiler wrote, and it
    /// is interned here so that it shares the pool -- and the sharing rule --
    /// with every literal a program wrote.
    fn internBytes(self: *Mono, raw: []const u8) std.mem.Allocator.Error!u32 {
        const found = try self.bytes_at.getOrPut(self.gpa, raw);
        if (found.found_existing) return found.value_ptr.*;

        const owned = try self.gpa.dupe(u8, raw);
        errdefer self.gpa.free(owned);
        const at: u32 = @intCast(self.bytes.items.len);
        try self.bytes.append(self.gpa, owned);
        found.key_ptr.* = owned;
        found.value_ptr.* = at;
        return at;
    }

    fn internLiteral(self: *Mono, ast: *const Ast, id: ExprId) std.mem.Allocator.Error!u32 {
        var written: std.ArrayList(u8) = .empty;
        defer written.deinit(self.gpa);
        // The lexer reported anything unreadable, and lowering runs on a tree
        // the driver did not stop at, so what comes back here is bytes.
        _ = try ast.literalText(self.gpa, &written, id);

        // The pool outlives the source and the scratch above, so what it holds
        // is copied there rather than borrowed from here.
        return self.internBytes(written.items);
    }

    fn deinit(self: *Mono) void {
        for (self.bytes.items) |bytes| self.gpa.free(bytes);
        self.bytes.deinit(self.gpa);
        self.bytes_at.deinit(self.gpa);
        for (self.statics.items) |entry| self.gpa.free(entry.parts);
        self.statics.deinit(self.gpa);
        self.statics_at.deinit(self.gpa);
        self.scratch_parts.deinit(self.gpa);
        self.pool.deinit();
    }

    /// The handle a call reaches in the complete set. Emission has no growth
    /// path: absence means discovery and lowering disagree about the program.
    fn idFor(
        self: *const Mono,
        decl: DeclId,
        args: []const TypeId,
        self_ty: TypeId,
        impl_args: []const TypeId,
    ) FunctionId {
        const found = self.instances.lookup(decl, args, self_ty, impl_args) orelse
            @panic("compiler defect: lowering asked for an instance instantiation never discovered");
        return FunctionId.at(found.index());
    }

    fn idForClosure(self: *const Mono, closure: types_mod.ClosureType) FunctionId {
        const found = self.instances.lookupClosure(&self.pool, closure) orelse
            @panic("compiler defect: lowering asked for a closure instance discovery never found");
        return FunctionId.at(found.index());
    }

    fn idForConstructor(self: *const Mono, constructor: types_mod.ConstructorBody, args: []const TypeId, self_ty: TypeId, impl_args: []const TypeId) FunctionId {
        const found = self.instances.lookupConstructor(constructor, args, self_ty, impl_args) orelse
            @panic("compiler defect: lowering asked for a constructor instance discovery never found");
        return FunctionId.at(found.index());
    }
};

/// Materializes a stored value in its canonical MIR representation.
fn readStoredValue(b: *Mir.Builder, block: BlockId, typing: Typing, address: InstId, ty: TypeId, span: Span) !InstId {
    const layout = typing.layoutOf(ty);
    if (layout.isAggregate()) return address;
    if (layout.size == 0)
        return b.addInst(block, .{ .tag = .constant, .result_role = .value, .ty = ty, .span = span, .data = .{ .constant = 0 } });
    return b.addInst(block, .{ .tag = .load_indirect, .result_role = .value, .ty = ty, .span = span, .data = .{ .unary = address } });
}

fn lowerClosureRelease(gpa: std.mem.Allocator, ast: *const Ast, typing: *const Typing, mono: *Mono, closure_type: TypeId) !Mir {
    const instance = mono.instances.lookupBody(.{ .closure_release = closure_type }, &.{}, .poison, &.{}).?;
    const plan = mono.instances.release_plans.get(instance).?;
    // A structural function value has no source of its own; its release is
    // placed at the trait member it implements.
    const place: struct { span: Span, file: FileId } = switch (mono.pool.get(closure_type)) {
        .closure => |closure| blk: {
            const source = typing.closureOf(closure.closure).expr;
            break :blk .{ .span = ast.exprSpan(source), .file = ast.fileOfExpr(source) };
        },
        else => blk: {
            const member = typing.closure_release.?.member;
            break :blk .{ .span = ast.declSpan(member), .file = ast.fileOfDecl(member) };
        },
    };
    const span = place.span;
    var b = Mir.Builder.init(gpa);
    errdefer b.deinit();
    b.signature = plan.signature;
    b.return_type = .unit;
    b.param_count = 1;
    const block = try b.addBlock();
    const local = try b.addLocal(closure_type, .value);
    if (plan.calls.len != 0) {
        const base = try b.addInst(block, .{ .tag = .addr_of, .result_role = .managed_address, .ty = closure_type, .span = span, .data = .{ .local = local } });
        for (plan.calls) |call| {
            const environment = mono.pool.get(closure_type).closure.environment;
            const field_type = mono.pool.erased(mono.pool.view().fieldType(environment, call.field.index()));
            const offset = mono.pool.view().fieldOffset(environment, call.field.index());
            const displacement = try b.addInst(block, .{ .tag = .constant, .result_role = .value, .ty = .u64, .span = span, .data = .{ .constant = offset } });
            const address = try b.addInst(block, .{ .tag = .field_addr, .result_role = .managed_address, .ty = field_type, .span = span, .data = .{ .binary = .{ .lhs = base, .rhs = displacement } } });
            const argument = try readStoredValue(&b, block, mono.pool.view(), address, field_type, span);
            _ = try b.addCall(block, .value, .unit, span, FunctionId.at(call.callee.index()), &.{argument});
        }
    }
    const unit = try b.addInst(block, .{ .tag = .constant, .result_role = .value, .ty = .unit, .span = span, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(block, .{ .tag = .ret, .result_role = .none, .ty = .unit, .span = span, .data = .{ .unary = unit } });
    return b.finish(block, place.file);
}

/// The body a function value holds for an operation the compiler provides,
/// or one an array answers through its slice view. It takes the operation's
/// arguments as a direct call to the trait member passes them, and answers as
/// such a call is lowered: with the instruction the compiler provides, or by
/// viewing each array argument and calling the slice's member.
fn lowerBuiltInBody(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    resolution: *const Resolution,
    typing: *const Typing,
    disposals: *const DisposalPlan,
    calls: *const types_mod.CallIndex,
    local_of_binding: []LocalId,
    touched: *std.ArrayList(u32),
    instance: mir_mod.Origin,
    mono: *Mono,
    library: LibraryDecls,
) !Mir {
    const built_in = switch (instance.body) {
        .built_in, .viewed => |at| at,
        else => unreachable,
    };
    const span = ast.tokenSpan(ast.declName(built_in.member));
    var b = Mir.Builder.init(gpa);
    errdefer b.deinit();
    const entry_block = try b.addBlock();
    b.signature = try instantiate_mod.builtInSignature(ast, typing, &mono.pool, built_in);
    const params = mono.pool.callableParams(mono.pool.get(b.signature).callable);
    b.return_type = mono.pool.get(b.signature).callable.result;

    const slots = try gpa.alloc(LocalId, params.len);
    defer gpa.free(slots);
    for (params, slots) |param, *slot| {
        const slot_ty = mir_mod.parameterSlotType(mono.pool.erased(param.ty));
        slot.* = try b.addLocal(slot_ty, mir_mod.parameterSlotRole(param, mono.pool.layoutOf(slot_ty).isAggregate()));
    }
    b.param_count = @intCast(params.len);

    var l: Lowerer = .{
        .gpa = gpa,
        .ast = ast,
        .res = resolution,
        .typing = typing,
        .disposals = disposals,
        .b = &b,
        .block = entry_block,
        .local_of_binding = local_of_binding,
        .touched = touched,
        .mono = mono,
        .calls = calls,
        .instance = .{ .decl = DeclId.none },
        .library = library,
        .answers = b.return_type,
    };
    defer l.selected_callables.deinit(gpa);
    defer l.loops.deinit(gpa);
    defer l.unreached.deinit(gpa);

    var args: std.ArrayList(InstId) = .empty;
    defer args.deinit(gpa);
    for (params, slots) |param, slot| {
        const ty = mono.pool.erased(param.ty);
        try args.append(gpa, if (b.slotRoleOf(slot) == .managed_address)
            try l.emit(.load, ty, span, .{ .local = slot })
        else
            try l.loadLocal(slot, ty, span));
    }
    const result = if (instance.body == .built_in)
        try l.builtInOperation(built_in.member, b.return_type, span, span, args.items) orelse
            @panic("compiler defect: a built-in operation value names no operation the compiler provides")
    else viewed: {
        const choice = mono.instances.selectedChoice(built_in.trait, &.{}, built_in.receiver);
        const selected = instantiate_mod.selectedMember(ast, &mono.instances.typing, choice, built_in.member) orelse
            @panic("compiler defect: a viewed operation's slice supplies no member");
        for (params, args.items) |param, *argument| {
            if (param.ty == built_in.receiver) argument.* = try l.receiverArgument(argument.*, built_in.receiver, choice, span);
        }
        const callee = mono.idFor(selected.body.declaration, &.{}, selected.self_ty, selected.impl_args);
        break :viewed try l.directCall(b.return_type, span, callee, args.items);
    };
    try l.returnFrom(result, span);

    b.return_type = mono.pool.erased(b.return_type);
    for (b.locals.items) |*t| t.* = mono.pool.erased(t.*);
    for (b.insts.items(.ty)) |*t| t.* = mono.pool.erased(t.*);
    return b.finish(entry_block, ast.fileOfDecl(built_in.member));
}

/// The entry and the release an erased closure is called and settled through,
/// generated for one stored callable type.
///
/// Both take the address and length of the bytes the callable was moved into.
/// The stored callable is read through a checked storage address at offset
/// 0, so a length too short for it traps rather than reads past the bytes.
/// The address itself is aligned because the buffer's allocation is: the
/// check covers the offset, not the address. A callable of no size is never
/// read: it is produced, as every value of such a type is.
///
/// The entry takes the closure's arguments first and passes them on
/// unchanged. A capturing closure's body is called directly with its
/// environment's address; a function value is loaded and called through.
fn lowerErasedBody(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    resolution: *const Resolution,
    typing: *const Typing,
    disposals: *const DisposalPlan,
    calls: *const types_mod.CallIndex,
    local_of_binding: []LocalId,
    touched: *std.ArrayList(u32),
    instance: mir_mod.Origin,
    mono: *Mono,
    library: LibraryDecls,
) !Mir {
    const callable, const signature, const placed = switch (instance.body) {
        .erased_entry => |entry| .{ entry.callable, entry.signature, typing.raw_accesses.closure_entry },
        .erased_settle => |callable| .{ callable, TypeId.poison, typing.raw_accesses.closure_settle },
        else => unreachable,
    };
    const span = ast.tokenSpan(ast.declName(placed));
    var b = Mir.Builder.init(gpa);
    errdefer b.deinit();
    const entry_block = try b.addBlock();

    // The entry is `ClosureEntry`'s signature for the closure's `S`, and the
    // release the type the library's `settle` field declares. Both end with
    // the stored callable's address and length.
    b.signature = if (signature == .poison)
        typing.get(typing.declSignature(placed)).callable.result
    else
        (try mono.pool.closureEntrySignature(signature)).?;
    const params = mono.pool.callableParams(mono.pool.get(b.signature).callable);
    b.return_type = mono.pool.get(b.signature).callable.result;

    // Each parameter takes the slot a body of that signature gives it, so an
    // argument arrives exactly as a direct call passes it.
    const slots = try gpa.alloc(LocalId, params.len);
    defer gpa.free(slots);
    for (params, slots) |param, *slot| {
        const slot_ty = mir_mod.parameterSlotType(mono.pool.erased(param.ty));
        slot.* = try b.addLocal(slot_ty, mir_mod.parameterSlotRole(param, mono.pool.layoutOf(slot_ty).isAggregate()));
    }
    b.param_count = @intCast(params.len);
    const forwarded = slots[0 .. slots.len - 2];
    const at_slot = slots[slots.len - 2];
    const len_slot = slots[slots.len - 1];

    var l: Lowerer = .{
        .gpa = gpa,
        .ast = ast,
        .res = resolution,
        .typing = typing,
        .disposals = disposals,
        .b = &b,
        .block = entry_block,
        .local_of_binding = local_of_binding,
        .touched = touched,
        .mono = mono,
        .calls = calls,
        .instance = .{ .decl = DeclId.none },
        .library = library,
        .answers = b.return_type,
    };
    defer l.selected_callables.deinit(gpa);
    defer l.loops.deinit(gpa);
    defer l.unreached.deinit(gpa);

    // The stored callable's address: checked against the length it was given,
    // or a slot of no size where the callable has none.
    const stored = if (mono.pool.layoutOf(callable).size == 0)
        try l.emit(.addr_of, callable, span, .{ .local = try b.addLocal(callable, .value) })
    else blk: {
        const at = try l.emit(.load, .u64, span, .{ .local = at_slot });
        const len = try l.emit(.load, .u64, span, .{ .local = len_slot });
        const start = try l.emit(.constant, .u64, span, .{ .constant = 0 });
        break :blk try l.checkedStorageAddress(callable, .{ at, len, start }, span);
    };

    if (signature == .poison) {
        const release = mono.instances.lookupBody(.{ .closure_release = callable }, &.{}, .poison, &.{}) orelse
            @panic("compiler defect: an erased closure's release was never discovered");
        _ = try l.directCall(.unit, span, FunctionId.at(release.index()), &.{try l.readThrough(stored, callable, span)});
        try l.returnFrom(try l.nothing(.unit, span), span);
    } else {
        var args: std.ArrayList(InstId) = .empty;
        defer args.deinit(gpa);
        for (params[0..forwarded.len], forwarded) |param, slot| {
            const ty = mono.pool.erased(param.ty);
            try args.append(gpa, if (b.slotRoleOf(slot) == .managed_address)
                try l.emit(.load, ty, span, .{ .local = slot })
            else
                try l.loadLocal(slot, ty, span));
        }
        const result_ty = b.return_type;
        const result = switch (mono.pool.get(callable)) {
            .closure => |closure| blk: {
                if (closure.environment != .unit) try args.append(gpa, try l.fieldAddr(stored, closure.environment, 0, span));
                const callee = mono.idForClosure(closure);
                break :blk try l.directCall(result_ty, span, callee, args.items);
            },
            .callable => blk: {
                const code = try l.readThrough(stored, callable, span);
                if (result_ty == .never) {
                    _ = try b.setIndirectCallNoreturn(l.block, span, code, args.items);
                    break :blk try l.afterNoreturn(span);
                }
                break :blk try b.addIndirectCall(l.block, mono.callResultRole(result_ty), result_ty, span, code, args.items);
            },
            // Only a closure and a function value satisfy a callable bound.
            else => @panic("compiler defect: an erased closure stores a callable of no known kind"),
        };
        try l.returnFrom(result, span);
    }

    b.return_type = mono.pool.erased(b.return_type);
    for (b.locals.items) |*t| t.* = mono.pool.erased(t.*);
    for (b.insts.items(.ty)) |*t| t.* = mono.pool.erased(t.*);
    return b.finish(entry_block, ast.fileOfDecl(placed));
}

/// The width of every checked buffer access, which is also the alignment its
/// offsets are held to and the alignment the buffer's allocation asks for.
/// One number in three places -- here, the library's `Buffer.alignment`, and
/// the bound the runtime honours -- tied together by the test at the bottom
/// of this file, which reads the runtime's bound and the library's alignment
/// out of their sources.
pub const checked_access_width: u64 = 8;

/// The library declarations lowering must find by identity, answered once per
/// program: the four raw accesses the swap replaces, `report`, which the entry
/// point's failing edges call, and `Display`, which says whether a call is one
/// an interpolation renders itself. `none` where the library does not hold one
/// -- a build of the compiler's own tests compiles programs with no library at
/// all.
const LibraryDecls = struct {
    raw: RawAccesses,
    float_math: @import("../sema/intrinsics.zig").FloatMath,
    report: DeclId = DeclId.none,
    /// What a test binary's generated entry point reaches: whether a name was
    /// selected, what its answer becomes, and what an unusable command line
    /// says. Found by module and name exactly as `report` is, because they are
    /// the same kind of thing -- a declaration only generated code calls.
    ran: DeclId = DeclId.none,
    selected: DeclId = DeclId.none,
    no_such_test: DeclId = DeclId.none,
    /// Found through the prelude, which is what a program's own names resolve
    /// against, so these are the declarations the checker selected for each
    /// interpolation format.
    formatting: FormattingDecls,
    /// A laid-out interpolation value renders through these library
    /// functions, found by the routine discovery used to reach them.
    layouts: LayoutDecls,
    /// The two traits the six comparison operators are calls on, and the three
    /// signatures the compiler provides a body for. Found the same way
    /// `Display` is, so the row this pass emits from is the row the checker's
    /// demand admitted.
    equatable: ?DeclId = null,
    comparable: ?DeclId = null,
    equals: ?DeclId = null,
    less: ?DeclId = null,
    forward: ?DeclId = null,
    backward: ?DeclId = null,
    /// The two traits a `for` walks through, and the member of each the
    /// desugar calls. Found the same way `Display` is, so the implementation
    /// this pass calls is the one the checker's demand admitted.
    sequence: ?DeclId = null,
    iterate: ?DeclId = null,
    iterator: ?DeclId = null,
    next: ?DeclId = null,
};

/// The entry point of a test binary, which no source declares.
///
/// Built rather than parsed because lowering already holds what a call needs --
/// the declaration, its settled type arguments and its symbol -- so generating
/// text would mean parsing something back into what is already here, with
/// imports to alias, a qualifier to disambiguate and spans pointing at source
/// nobody wrote.
///
/// What it decides is only which name selects which call. Whether a command
/// line selects anything, what an unusable one answers, and what a test's
/// answer becomes are the library's, in functions a reader can open: a message
/// spelled here would be the compiler deciding what a program says.
///
/// It is also the one function in the artefact that no diagnostic can name. A
/// mistake here is not a rejected program; it is a binary that runs and answers
/// wrongly, which is why the cases covering it run it.
fn buildDispatcher(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    resolution: *const Resolution,
    typing: *const Typing,
    disposals: *const DisposalPlan,
    calls: *const types_mod.CallIndex,
    local_of_binding: []LocalId,
    touched: *std.ArrayList(u32),
    mono: *Mono,
    library: LibraryDecls,
) !Mir {
    var b = Mir.Builder.init(gpa);
    errdefer b.deinit();

    const entry_block = try b.addBlock();
    b.return_type = .u8;
    b.signature = try mono.pool.internCallable(&.{}, .u8, &.{}, .read);

    var l: Lowerer = .{
        .gpa = gpa,
        .ast = ast,
        .res = resolution,
        .typing = typing,
        .disposals = disposals,
        .b = &b,
        .block = entry_block,
        .local_of_binding = local_of_binding,
        .touched = touched,
        .mono = mono,
        .calls = calls,
        // No declaration, and so no type parameters for anything to stand for:
        // substitution through this is the identity, which is what a function
        // with no generics of its own asks of it.
        .instance = .{ .decl = DeclId.none },
        .library = library,
        .answers = .u8,
    };
    defer l.selected_callables.deinit(gpa);
    defer l.loops.deinit(gpa);
    defer l.unreached.deinit(gpa);

    // Every span here names the library declaration the generated call reaches.
    // Nothing in this function can trap, so no span is ever printed; what they
    // are for is the file table, which wants each instruction to belong
    // somewhere real.
    //
    // Defended, because a library that declares none of these is a compiler
    // built against a library it does not know: every call below already
    // degrades to poison for a declaration that is `.none`, and reading a span
    // off one would be the single place that crashed instead.
    const missing = library.no_such_test == DeclId.none;
    const span: Span = if (missing) .empty else ast.tokenSpan(ast.declName(library.no_such_test));

    // What a name is, read off the parameter that receives one rather than
    // built here: the type is the library's and asking it is one lookup, where
    // constructing it would be this pass deciding what `Str` is.
    const str_ty = blk: {
        const params = resolution.parametersOf(library.selected);
        if (params.len == 0) break :blk TypeId.poison;
        break :blk typing.bindingType(params[0]);
    };

    for (resolution.tests) |t| {
        // What this test answers, and what its failure carries, settled before
        // anything is emitted for it. A test whose answer is not a `Result` was
        // refused by [S-Test] and the program never reached lowering, so this
        // is the shape being read rather than a case being handled: skipping
        // leaves no half-written arm behind if it ever stops holding.
        const answers = typing.declReturn(t.decl);

        // [S-Test] admits `Result[(), E]` and nothing else, so a recorded test
        // whose answer carries no failure is a rule that has stopped holding
        // rather than a shape to handle. Skipping one would leave the runner
        // spawning a child for a name the binary answers nothing to, and the
        // transcript would blame the command line for a defect in the compiler.
        const bad = mono.pool.view().failureVariantOf(answers) orelse unreachable;
        const held = mono.pool.view().variantFieldType(answers, bad, 0);

        const name = try l.strValue(try mono.internBytes(t.qualified_name), str_ty, span, null);
        const hit = try l.callLibrary(library.selected, &.{}, &.{name}, .bool_, span);

        const runs = try b.addBlock();
        const next = try b.addBlock();
        _ = try b.setTerminator(l.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = hit, .then_block = runs, .else_block = next } },
        });

        // The test, and what its answer becomes. `ran` is generic over the
        // failure, so the type argument is this test's own -- two tests may
        // answer differently and each instantiates it for itself.
        l.block = runs;
        const answered = try l.callLibrary(t.decl, &.{}, &.{}, answers, span);
        const status = try l.callLibrary(library.ran, &.{held}, &.{answered}, .u8, span);
        _ = try b.setTerminator(l.block, .{
            .tag = .ret,
            .ty = .unit,
            .span = span,
            .data = .{ .unary = status },
        });

        l.block = next;
    }

    // Nothing matched, which includes a binary holding no tests at all.
    const usage = try l.callLibrary(library.no_such_test, &.{}, &.{}, .u8, span);
    _ = try b.setTerminator(l.block, .{
        .tag = .ret,
        .ty = .unit,
        .span = span,
        .data = .{ .unary = usage },
    });

    return b.finish(entry_block, if (missing) FileId.from(0) else ast.fileOfDecl(library.no_such_test));
}

fn lowerFunction(
    gpa: std.mem.Allocator,
    program: *const ExpandedProgram,
    ast: *const Ast,
    resolution: *const Resolution,
    typing: *const Typing,
    disposals: *const DisposalPlan,
    calls: *const types_mod.CallIndex,
    /// Which slot holds each binding. Lent rather than taken: it is one entry
    /// per binding in the whole program, and a body reads and writes only its
    /// own -- so what it disturbs is put back rather than the whole of it
    /// being cleared, which cost the program's bindings per function lowered.
    local_of_binding: []LocalId,
    touched: *std.ArrayList(u32),
    /// The declaration to lower and what this instantiation makes of every
    /// parameter its types hold.
    instance: mir_mod.Origin,
    mono: *Mono,
    library: LibraryDecls,
) !Mir {
    if (instance.body == .closure_release) return lowerClosureRelease(gpa, ast, typing, mono, instance.body.closure_release);
    if (instance.body == .erased_entry or instance.body == .erased_settle)
        return lowerErasedBody(gpa, ast, resolution, typing, disposals, calls, local_of_binding, touched, instance, mono, library);
    if (instance.body == .built_in or instance.body == .viewed)
        return lowerBuiltInBody(gpa, ast, resolution, typing, disposals, calls, local_of_binding, touched, instance, mono, library);
    const d = instance.decl;
    const SourceBody = struct {
        body: ExprId,
        params: []const syntax_node.Param,
        bindings: []const BindingId,
        returns: TypeId,
        signature: TypeId,
        file: FileId,
    };
    const source: SourceBody = switch (instance.body) {
        .closure_release, .erased_entry, .erased_settle, .built_in, .viewed => unreachable,
        .declaration => |decl| .{
            .body = ast.declBody(decl),
            .params = ast.declParams(decl),
            .bindings = resolution.parametersOf(decl),
            .returns = typing.declReturn(decl),
            .signature = typing.declSignature(decl),
            .file = program.primaryFileOfDecl(decl),
        },
        .closure => |closure| blk: {
            const descriptor = typing.closureOf(closure);
            const signature = typing.get(descriptor.signature).callable;
            break :blk .{
                .body = descriptor.body,
                .params = ast.lambda(descriptor.expr).params,
                .bindings = resolution.closureParameters(closure),
                .returns = signature.result,
                .signature = descriptor.signature,
                .file = ast.fileOfExpr(descriptor.expr),
            };
        },
        .constructor => |constructor| blk: {
            const value = calls.functionValueOf(typing, constructor.expr).?;
            break :blk .{
                .body = .none,
                .params = &.{},
                .bindings = &.{},
                .returns = typing.get(value.signature).callable.result,
                .signature = value.signature,
                .file = ast.fileOfExpr(constructor.expr),
            };
        },
    };

    var b = Mir.Builder.init(gpa);
    errdefer b.deinit();
    b.signature = try instance.through(&mono.pool, source.signature);
    // An `extern` answering `ffi.Errno[R]` returns `R` from C. Each call to it
    // builds the `Errno` from that and the `errno` read after it.
    if (instance.body == .declaration and ast.declIsExtern(d)) {
        if (try typing.raw_accesses.errnoSignature(gpa, &mono.pool, b.signature)) |answered| b.signature = answered;
    }

    const entry_block = try b.addBlock();

    // Every entry this function writes goes back to where it started, so the
    // next one sees the table it would have seen after a clear.
    touched.clearRetainingCapacity();
    defer for (touched.items) |at| {
        local_of_binding[at] = LocalId.at(0);
    };

    // A parameter arrives in a slot, so the body reads one exactly as it reads
    // a binding and nothing below here knows the difference.
    const params = source.params;
    // A parameter's type comes from the checker rather than from its
    // annotation token: a declared type is named by an identifier, and which
    // type that names is a question this pass must not answer twice.
    const param_types = try gpa.alloc(TypeId, params.len);
    defer gpa.free(param_types);
    @memset(param_types, .poison);
    for (source.bindings) |sym| {
        const at = resolution.paramIndexOf(sym);
        local_of_binding[sym.index()] = LocalId.at(at);
        try touched.append(gpa, @intCast(sym.index()));
        param_types[at] = try instance.through(&mono.pool, typing.bindingType(sym));
    }

    // Which parameters are reached through an address rather than held.
    //
    // An `inout` must be, because writing back through it is the whole point.
    // A `read` aggregate may be, and that is what a lend buys here: the body
    // cannot write it, and moving out of one is [O-Move], so all it can do is
    // read -- while [N-Aliased] says no other argument mutates the same place
    // for the duration of the call. Copying it in would be copying a value
    // nothing can change, which is the copy ADR 0025 reserved the right not to
    // make. A `sink` still copies: the callee owns what it was given.
    for (0..params.len) |i| {
        const slot_ty = mir_mod.parameterSlotType(mono.pool.erased(param_types[i]));
        const param = typing.callableParams(typing.get(source.signature).callable)[i];
        _ = try b.addLocal(slot_ty, mir_mod.parameterSlotRole(param, mono.pool.layoutOf(slot_ty).isAggregate()));
    }

    b.param_count = @intCast(params.len);
    var environment: TypeId = .unit;
    var environment_slot: LocalId = .at(0);
    if (instance.body == .closure) {
        const closure = instance.body.closure;
        const descriptor = typing.closureOf(closure);
        if (descriptor.environment != .unit) {
            const concrete = try instance.through(&mono.pool, typing.exprType(descriptor.expr));
            environment = mono.pool.get(concrete).closure.environment;
            b.signature = mono.pool.get(concrete).closure.body_signature;
            std.debug.assert(b.signature != .poison);
            environment_slot = try b.addLocal(environment, if (descriptor.invocation == .sink) .value else .managed_address);
            b.param_count += 1;
        }
    }
    if (instance.body == .constructor) {
        const parameter = mono.pool.callableParams(mono.pool.get(b.signature).callable)[0];
        _ = try b.addLocal(mir_mod.parameterSlotType(mono.pool.erased(parameter.ty)), .value);
        b.param_count = 1;
    }
    // What the declaration was written to return, and not what its body block
    // came out as. The two agree only where the value leaves as the body's
    // tail: a body whose value leaves through `return` has a block yielding
    // nothing, and a function returning a value too wide for a register would
    // then be emitted as one returning a register -- handing the caller the
    // address of a frame that has ended instead of a copy of the value.
    b.return_type = if (source.body == ExprId.none and instance.body != .constructor)
        .poison
    else
        try instance.through(&mono.pool, source.returns);

    var array_elisions: array_initialization.Elisions = if (source.body == .none) .empty else try array_initialization.find(gpa, ast, resolution, typing, source.body);
    defer array_elisions.deinit(gpa);

    var l: Lowerer = .{
        .gpa = gpa,
        .ast = ast,
        .res = resolution,
        .typing = typing,
        .disposals = disposals,
        .b = &b,
        .block = entry_block,
        .local_of_binding = local_of_binding,
        .touched = touched,
        .mono = mono,
        .calls = calls,
        .instance = instance,
        .library = library,
        .answers = b.return_type,
        .array_elisions = &array_elisions,
    };

    // The entry point may answer `Result[UInt8, E]`, and the runtime reads a
    // byte. So what the declaration answers and what the function returns part
    // company here: the body still builds the `Result` -- `?` inside it has to
    // build the failing variant of the type that was written -- and the return
    // unwraps it, handing back the byte on success and what `report` answers on
    // failure.
    //
    // `answers` above keeps the written type for that reason. Overwriting
    // `return_type` alone would have made a `?` in `main` build its failure out
    // of `UInt8`.
    if (instance.body == .declaration and resolution.entry != DeclId.none and d == resolution.entry) {
        const view = mono.pool.view();
        if (view.successVariantOf(b.return_type) != null) {
            l.unwraps = b.return_type;
            b.return_type = .u8;
        }
    }
    defer l.selected_callables.deinit(gpa);
    defer l.loops.deinit(gpa);
    defer l.unreached.deinit(gpa);
    defer l.splices.deinit(gpa);
    defer l.lent.deinit(gpa);

    if (environment != .unit) {
        const span = ast.exprSpan(source.body);
        const base = if (b.slotRoleOf(environment_slot) == .managed_address)
            try l.emit(.load, environment, span, .{ .local = environment_slot })
        else
            try l.emit(.addr_of, environment, span, .{ .local = environment_slot });
        for (resolution.closureCaptures(instance.body.closure), 0..) |capture, index| {
            const field: u32 = @intCast(index);
            const field_ty = l.types().fieldType(environment, field);
            const address = try l.fieldAddr(base, field_ty, l.types().fieldOffset(environment, field), span);
            // A read or `inout` capture's field holds the address of the
            // place it observes; a sink capture's field is the place.
            const capture_address = if (capture.convention != .sink)
                try l.observeLayers(try l.readThrough(address, field_ty, span), field_ty, 1, span)
            else
                address;
            try l.lent.put(gpa, capture.binding, capture_address);
        }
    }

    // A parameter written as a tuple pattern is taken apart before the body
    // runs: a `sink` parameter's components are moved into slots of their own,
    // and any other convention lends the components in place.
    for (params) |param| {
        if (param.pattern == ExprId.none) continue;
        const pattern_span = ast.exprSpan(param.pattern);
        const of = try l.typeAt(param.argument);
        const value = try l.expr(param.argument);
        try l.bindPattern(param.pattern, l.matchedValueOf(of, value), param.convention != .sink, pattern_span);
    }

    const body = source.body;
    const span = if (instance.body == .constructor) ast.exprSpan(instance.body.constructor.expr) else if (body == ExprId.none) ast.tokenSpan(ast.declName(d)) else ast.exprSpan(body);
    const result = if (instance.body == .constructor) blk: {
        const parameter = mono.pool.callableParams(mono.pool.get(b.signature).callable)[0];
        const payload = try l.loadLocal(LocalId.at(0), parameter.ty, span);
        if (parameter.ty == .never) break :blk payload;
        break :blk try l.buildVariant(b.return_type, @intFromEnum(instance.body.constructor.ordinal), .{ .values = &.{payload} }, span, null);
    } else if (body == ExprId.none)
        try l.poison(span)
    else if (ast.exprTag(body) == .block)
        try l.blockExpr(body, null)
    else
        try l.expr(body);

    // A body's result is returned where its tail is written, so a debugger
    // stepping out of the function stops on the result line.
    const exit_span = if (body != ExprId.none and ast.exprTag(body) == .block) tail: {
        const tail = ast.blockOf(body).tail;
        break :tail if (tail == ExprId.none) span else ast.exprSpan(tail);
    } else span;
    if (b.return_type == .never) {
        try l.finishNever(span);
    } else {
        try l.returnFrom(try l.testSuccess(body, result, exit_span), exit_span);
    }

    // Every type this body names, erased to what it represents. The backend
    // reads a handle to decide a load's width and signedness, a division's
    // signedness and whether an overflow guard is needed, and a newtype is a
    // handle it cannot classify -- so one reaching it meant an unsigned load
    // for a signed base and a guard silently elided.
    //
    // Swept once, where the body is finished, rather than at each site that
    // carries a type: lowering reads the checker's own types while it walks --
    // which newtype a fallible construction is testing is one of them -- and
    // a rule applied per site is a rule a form added later can miss.
    b.return_type = mono.pool.erased(b.return_type);
    for (b.locals.items) |*t| t.* = mono.pool.erased(t.*);
    for (b.insts.items(.ty)) |*t| t.* = mono.pool.erased(t.*);

    const origin = program.originOf(d);
    var finished = try b.finish(
        entry_block,
        if (origin != null) program.primaryFileOfDecl(d) else source.file,
    );
    if (origin != null) @memset(finished.insts.items(.span), program.primarySpanOfDecl(d));
    return finished;
}

/// What an access to a tag is typed by.
///
/// A tag occupies a full word wherever it sits, so reading or writing one is
/// eight bytes wide whatever the enum around it holds. Typing the access by the
/// enum gave that width only because an enum is never narrower than its tag,
/// which makes the right answer an accident of the layout rather than a
/// consequence of it.
const tag_type: TypeId = Layout.tag_type;

/// Where an aggregate's bytes are wanted, offered to the expression that
/// produces them.
///
/// A literal that takes one writes its fields straight through `at`, so no slot
/// is minted for the value and no copy follows it. Every other form ignores the
/// offer and is copied into place as before, which is what `used` records.
///
/// Sound only for an address the expression cannot name: a field's initialiser
/// that could read the destination would observe it half built. So an offer is
/// made from exactly two places -- a slot lowering minted, which nothing in the
/// program names, and the local a `let` introduces, which is not in scope in
/// its own initialiser.
const Dest = struct {
    at: InstId,
    used: bool = false,
};

/// One slot of a projection's path, and the expression the site fills it with.
///
/// A projection's body is written in its own parameters; a bracket says what
/// stands in each of them. Held while the path is read and dropped after it,
/// because what a slot means is a fact about one site.
const Splice = struct {
    /// The parameter the path names.
    binding: BindingId,
    /// What the site wrote in its place, or `.none` where what fills the slot
    /// is a value rather than an expression: a lending walk fills both slots
    /// with values it has -- the head it evaluated once before the loop, and
    /// the position the traversal handed over -- and no line of the program
    /// spells either a second time. Such a slot arrives with its `value`
    /// already in it, which is also what keeps the head from being evaluated
    /// once per position.
    wrote: ExprId,
    /// Expressions belong to the site's instantiation, even while a generic
    /// projection's body is being read under its own instantiation.
    instance: mir_mod.Origin,
    /// What that lowered to, emitted the first time the path names the slot.
    value: InstId = .none,
    /// Whether reading the path asked for what the site wrote -- by lowering
    /// it, or by folding it into an offset, which reads the expression as
    /// surely and emits nothing.
    read: bool = false,
    /// How many slots were open at the site, before this bracket opened its
    /// own. What the site wrote reaches only those: a projection that
    /// forwards to itself through a generic layer (`self.next[i]` inside
    /// `Mw[H]`, instantiated at `Mw[Mw[R]]`) opens slots for the same
    /// parameters again, and the outer site's `self` names the outer slot,
    /// never the inner one its own expression fills.
    site: usize,
    /// How many expressions written outside this slot's bracket are being
    /// lowered; the slot is out of their reach while any is.
    hidden: u32 = 0,
};

/// What a variant carries, as whoever builds it has it.
///
/// A payload the program wrote is still an expression, so it is handed over
/// unlowered and each part is built at the offset it occupies. A payload
/// lowering worked out for itself -- what `?` moves from one enum to another --
/// is already a value and is written as one.
const Carried = union(enum) {
    values: []const InstId,
    written: []const ExprId,

    fn count(self: Carried) usize {
        return switch (self) {
            .values => |v| v.len,
            .written => |w| w.len,
        };
    }
};

const Lowerer = struct {
    array_elisions: ?*const array_initialization.Elisions = null,
    ast: *const Ast,
    res: *const Resolution,
    typing: *const Typing,
    b: *Mir.Builder,
    /// What the declaration was written to answer, which `?` builds its failing
    /// variant out of. The same as the builder's return type everywhere except
    /// an entry point whose answer is unwrapped on the way out, where the two
    /// deliberately differ.
    answers: TypeId = .poison,
    /// The `Result` an entry point answers, where its return is unwrapped, and
    /// `.poison` otherwise -- no function answers poison, so the absence has no
    /// spelling of its own to keep in step.
    unwraps: TypeId = .poison,
    /// Which slot holds each binding. Lowering allocates slots of its own, so
    /// the two are no longer numbered alike.
    local_of_binding: []LocalId,
    /// Which entries of it this function has written, so they can be put back.
    touched: *std.ArrayList(u32),
    /// Where instructions are appended. A separate field rather than a
    /// parameter because control flow will move it, and every emit site would
    /// otherwise have to thread it.
    block: BlockId,
    gpa: std.mem.Allocator,
    /// The loops enclosing the expression being lowered, innermost last, so a
    /// `break` or `continue` finds the blocks it jumps to.
    loops: std.ArrayList(LoopFrame) = .empty,
    /// Ordered schedules already placed and checked by ownership.
    disposals: *const DisposalPlan,
    /// Whether the passes above this one reported nothing about the program
    /// being lowered.
    /// Blocks nothing jumps to: what follows a `return`, a `break` or a
    /// `continue` in the source. Lowering is total, so the statements after
    /// one are still lowered, and this is where they go.
    ///
    /// Named so that a scope ending inside one runs no schedules. Control does
    /// not reach the end of a block it cannot reach at all, which is what the
    /// ownership pass already sees: it stops walking there and records no
    /// placement for that exit.
    unreached: std.AutoHashMapUnmanaged(mir_mod.BlockId, void) = .empty,
    /// Whether a deferred expression is being emitted. Nested exits in a
    /// rejected deferred body must not re-enter its enclosing placement.
    placing: bool = false,
    /// The slots a projection's path is being read through, innermost last.
    ///
    /// A bracket that routes is the implementation's path with its receiver
    /// and its index parameter standing for the two expressions the site wrote,
    /// so lowering the path meets those parameters by name and lowers what the
    /// site wrote instead. Keyed by binding, which is unique to the
    /// declaration, so a nested expansion adds slots rather than shadowing
    /// them.
    ///
    /// Each slot's value is emitted at most once. The path may name a slot
    /// twice, and the site's own expression is ordinary code that may call --
    /// so re-lowering it would run the call once per mention, in a position
    /// nobody wrote.
    splices: std.ArrayList(Splice) = .empty,
    /// The address each lending binder stands for: a lending walk's binder
    /// for the body it was bound over, a `match read` binder for its arm, a
    /// `let read` binder for the rest of the function, and a read capture.
    ///
    /// A lend names a place inside what it observes rather than storage of its
    /// own, so there is no slot to load and nothing to copy in: what the name
    /// reaches is the address computed where it was bound, and read by
    /// everything later done to the name.
    ///
    /// **Bound:** one entry per lending walk or `match read` binder enclosing
    /// the expression being lowered, plus one per `let read` binder and capture
    /// of the function, and nothing per program.
    lent: std.AutoHashMapUnmanaged(BindingId, InstId) = .empty,
    /// Immutable local selections keep the predicate value produced when the
    /// binding was initialized. Calls branch on that value after evaluating
    /// their arguments once. Storage follows eligible locals in this function.
    selected_callables: std.AutoHashMapUnmanaged(LocalId, SelectedCallable) = .empty,

    /// What discovery proved must exist, available here through lookup only.
    mono: *Mono,
    /// Where each call site's records sit in the checker's tables.
    calls: *const types_mod.CallIndex,
    /// The declaration being lowered and what it was instantiated with, so
    /// every type this body reads is read through them.
    instance: mir_mod.Origin,
    /// The extern declarations a call is replaced for, answered once for the
    /// program rather than asked per call site.
    library: LibraryDecls,

    const SelectedCallable = struct {
        condition: InstId,
        targets: [2]FunctionId,
    };

    /// A type this body carries, with the instantiation's arguments in it.
    ///
    /// Every type read goes through here. A body is checked once, in terms of
    /// its parameters; a body is *lowered* once per instantiation, in terms of
    /// what those parameters became.
    fn typeAt(self: *Lowerer, of: ExprId) !TypeId {
        return self.substituted(self.typing.exprType(of));
    }

    /// What a binding's storage holds, through the instantiation being
    /// lowered.
    ///
    /// The checker decided this and recorded it, so it is read rather than
    /// worked out again from the initialiser. The two differ wherever a
    /// binding is annotated and its initialiser is not of that type -- a `let`
    /// whose initialiser is a `return` has the annotation's width and the
    /// initialiser's is Unit, and a slot allocated from the initialiser is too
    /// small for what names it.
    fn bindingTypeAt(self: *Lowerer, b: BindingId) !TypeId {
        if (b == BindingId.none) return .poison;
        return self.substituted(self.typing.bindingType(b));
    }

    /// Discovery's sealed type pool.
    ///
    /// Every structural question goes through here; what the checker decided
    /// about an expression still comes from the checker.
    fn types(self: *const Lowerer) Typing {
        return self.mono.pool.view();
    }

    fn substituted(self: *Lowerer, t: TypeId) !TypeId {
        return self.instance.through(&self.mono.pool, t);
    }

    fn emit(self: *Lowerer, tag: Inst.Tag, ty: TypeId, span: Span, data: Inst.Data) !InstId {
        const role: mir_mod.ResultRole = switch (tag) {
            .store,
            .store_indirect,
            .store_raw,
            .copy_value,
            .move_value,
            .call_noreturn,
            .call_indirect_noreturn,
            .ret,
            .jump,
            .branch,
            .trap,
            => .none,
            .addr_of, .field_addr, .storage_addr, .observe, .static_addr => .managed_address,
            .load => if (self.b.slotRoleOf(data.local) == .managed_address) .managed_address else .value,
            .load_indirect => mir_mod.valueRole(self.mono.pool.layoutOf(ty)),
            .call, .call_indirect => self.mono.callResultRole(ty),
            .constant,
            .bytes_addr,
            .address_bits,
            .borrow,
            .load_raw,
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
            .float_extend,
            .float_truncate,
            .float_math,
            .check,
            .function_addr,
            .foreign_function_addr,
            => .value,
        };
        return self.b.addInst(self.block, .{ .tag = tag, .result_role = role, .ty = ty, .span = span, .data = data });
    }

    fn blockExpr(self: *Lowerer, id: ExprId, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const blk = self.ast.blockOf(id);

        // Exhaustive on purpose. A statement kind added later has to be given
        // an answer here rather than falling through a chain of tests and
        // reaching none -- which lowers to a block that quietly omits it.
        for (self.ast.blockStmts(blk)) |s| switch (self.ast.stmtTag(s)) {
            // Already diagnosed. The driver stops between passes, so nothing
            // lowered from a tree holding one reaches the backend.
            .err => {},
            .defer_stmt, .defer_release => {},
            .expr_stmt => _ = try self.expr(self.ast.stmtData(s).init),
            .let_destructure, .let_read_destructure => try self.destructure(s),
            .let_decl => try self.lowerLet(s),
        };

        // The tail is the block's value, computed before what the scope
        // scheduled runs -- so a `defer` observing a binding sees it as the
        // tail left it, not as the tail found it. It is also where the block's
        // value is produced, so a destination the block was given belongs to
        // it: an `if`'s arm is a block, and the arm is where the value is
        // written. Nothing a `defer` can name is a destination, so a tail that
        // writes to one before the schedules run is unobservable to them.
        const value = if (blk.tail == ExprId.none)
            try self.nothing(.unit, self.ast.exprSpan(id))
        else
            try self.exprInto(blk.tail, dest);

        try self.runScheduledAt(id);
        return value;
    }

    fn lowerLet(self: *Lowerer, s: StmtId) std.mem.Allocator.Error!void {
        const d = self.ast.stmtData(s);

        const binding = self.res.bindingOf(s);
        const ty = if (d.init == ExprId.none) TypeId.poison else try self.bindingTypeAt(binding);
        const span = self.ast.stmtSpan(s);

        // The initializer is the only part of a Never binding that can run.
        // It cannot complete, so no binding value reaches storage and no slot
        // exists for a later unreachable read to load.
        if (ty == .never) {
            _ = try self.expr(d.init);
            return;
        }

        // Lowering allocates slots of its own -- a conditional needs one to
        // carry a value between its arms -- so a local's handle is no
        // longer the binding's and the two are related by a table.
        //
        // Taken before the initialiser is lowered, so the initialiser can be
        // given the slot to build in. Nothing it evaluates can name the slot:
        // the binding it belongs to is not in scope until this statement ends.
        const local = try self.b.addLocal(ty, .value);
        const targets = if (binding != .none and !self.ast.stmtIsMutable(s) and d.init != .none)
            try self.callableSelection(d.init, ty)
        else
            null;
        if (targets) |selected| {
            var condition: InstId = .none;
            const value = try self.conditional(self.ast.withoutGroups(d.init), ty, span, &condition);
            try self.storeLocal(local, ty, span, value);
            try self.selected_callables.put(self.gpa, local, .{ .condition = condition, .targets = selected });
        } else if (d.init == ExprId.none) {
            try self.storeLocal(local, ty, span, try self.poison(span));
        } else {
            try self.storeExprIn(local, ty, span, d.init);
        }

        if (binding != BindingId.none) {
            self.local_of_binding[binding.index()] = local;
            try self.touched.append(self.gpa, @intCast(binding.index()));
        }
    }

    fn expr(self: *Lowerer, id: ExprId) std.mem.Allocator.Error!InstId {
        return self.exprInto(id, null);
    }

    /// As `expr`, where the caller already knows where the value is to end up.
    ///
    /// One switch rather than a second dispatch beside it: the forms that can
    /// take a destination are the ones that write their parts through an
    /// address, and every other arm ignores the offer, so nothing has to agree
    /// with this about which is which.
    fn exprInto(self: *Lowerer, id: ExprId, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        // Above everything, because a name reaching a slot of a projection's
        // path is not a name in this body at all: it stands for what the site
        // wrote, and its type and its span are that expression's.
        if (self.slotAt(id)) |at| return self.slotValue(at);

        const ty = try self.typeAt(id);
        const span = self.ast.exprSpan(id);

        // Lowering runs only on a program the checker accepted, so a node it
        // left untyped is one the checker refused without reporting. That is a
        // compiler bug, and the poison value lowered for it is what MIR
        // verification refuses as invalid compiler output.
        if (ty == TypeId.poison) return self.poison(span);

        if (self.typing.integerProperty(id)) |property| {
            const receiver = try self.substituted(property.receiver);
            const value = property.endpoint.value(receiver).?;
            return self.emit(.constant, ty, span, .{ .constant = value });
        }

        // Bare and qualified names read the same checked binding value. Its
        // concrete type and diagnostic span belong to this use, so nominal
        // identity survives without replaying the initializer's arithmetic.
        if (self.typing.constantValue(self.res.targetOf(id))) |value| return self.materializeConstant(value, ty, span);
        if (self.res.constantNamed(id) != BindingId.none) return self.poison(span);
        if (self.calls.functionValueOf(self.typing, id)) |value| return self.functionValue(value, span);

        return switch (self.ast.exprTag(id)) {
            // Patterns are read by whatever destructures them; none reaches
            // lowering as an expression of its own.
            .err, .reflection_root, .struct_pattern, .tuple_pattern => unreachable,

            .while_ => self.whileLoop(id, span),

            .assign => self.assign(id, span),
            .borrow => self.emit(.borrow, ty, span, .{ .unary = try self.addressOf(id, span) }),

            // A one-scalar string literal in a range end checks as its
            // scalar's number, not `Str` -- the checker's own recorded type
            // says which this is, so lowering asks it rather than the
            // node's tag alone.
            .str_literal => if (ty.integerInfo() != null)
                self.literal(id, ty)
            else
                self.strLiteral(id, ty, span, dest),
            .embed, .embed_bytes => self.embedded(id, ty, span, dest),

            .loop_ => self.loopExpr(id, ty, span),

            .for_, .for_read, .for_inout => self.forLoop(id, ty, span),

            .break_ => self.jump(id, span, .break_),

            .return_ => self.returnExpr(id, span),

            .continue_ => self.jump(id, span, .continue_),

            .call => self.callExpr(id, ty, span, dest),
            .panic => self.panicExpr(id, span),

            .lambda => self.closureValue(ty, span, dest),

            .interp => self.interpolation(id, ty, span, dest),
            .array_literal => self.arrayLiteral(id, ty, span, dest),

            .index => self.indexExpr(id, ty, span),

            .match_, .match_read => self.matchExpr(id, ty, span),
            .try_ => self.tryExpr(id, span),
            .unwrap_else => self.unwrapElse(id, ty, span),
            // A value independent of the place it names, owed here rather
            // than wherever the value is consumed. A scalar is already
            // independent: reading one takes the bits out of the slot, and
            // nothing written to the slot afterwards reaches them. An
            // aggregate's value is its address, so what comes back still
            // names the source -- and a consumer that blits later blits
            // whatever the source holds by then, which is the wrong value
            // whenever anything wrote to it in between.
            .copy_ => self.copyExpr(id, ty, span),

            .variant_ref => self.variantRef(id, ty, span, dest),

            .field, .dereference => self.selection(id, ty, span, dest),

            .struct_literal => self.structLiteral(id, ty, span, dest),
            .tuple_literal => self.tupleLiteral(id, ty, span, dest),

            .range => self.rangeExpr(id, ty, span, dest),

            .from_end => self.fromEndValue(id, ty, span, dest),

            .int_literal => self.literal(id, ty),

            .float_literal => self.literal(id, ty),

            .bool_literal => self.emit(.constant, ty, span, .{
                .constant = @intFromBool(self.ast.boolIsTrue(id)),
            }),

            .unit_literal => self.nothing(.unit, span),

            .name_ref, .param_argument => blk: {
                const target = self.res.targetOf(id);
                if (target == BindingId.none) break :blk self.poison(span);
                if (try self.uninhabitedRead(ty, span)) |unreachable_value| break :blk unreachable_value;
                if (self.mono.pool.get(ty) == .closure and self.mono.pool.get(ty).closure.environment == .unit)
                    break :blk self.nothing(ty, span);

                // A lend is an address rather than storage. For a value that
                // lives in memory that address *is* the value, so there is
                // nothing behind it to load.
                if (try self.addressBehind(target, ty, span)) |p| {
                    break :blk self.readThrough(p, ty, span);
                }
                break :blk self.loadLocal(self.local_of_binding[target.index()], ty, span);
            },

            .marked => self.addressOf(id, span),

            // Parentheses exist so a formatter can reproduce them. Nothing
            // below here reproduces source, so they end at this boundary.
            .grouped => self.exprInto(self.ast.unaryOperand(id), dest),

            // A negated literal is one constant, not a negation of another.
            // The type checker settles it that way because the minimum of a
            // signed type has no positive counterpart, and generated code has
            // to agree or a legal program traps on its own smallest value.
            // `!e` is `e == false`. There is no negation instruction because
            // there needs to be none: a comparison against the constant says
            // the same thing, and the backend already knows how to do it.
            .not => blk: {
                const operand = self.ast.unaryOperand(id);
                const v = try self.expr(operand);
                if (try self.typeAt(operand) == .never) break :blk v;
                const off = try self.emit(.constant, .bool_, span, .{ .constant = 0 });
                break :blk self.emit(.cmp_eq, .bool_, span, .{ .binary = .{ .lhs = v, .rhs = off } });
            },

            .negate => blk: {
                const operand = self.ast.unaryOperand(id);
                // The checker records one value for a negated integer literal,
                // parenthesized or not; its minimum has no positive operand to
                // negate at run time.
                if (self.typing.literalValue(id) != null) {
                    break :blk self.literal(id, ty);
                }
                const v = try self.expr(operand);
                if (try self.typeAt(operand) == .never) break :blk v;
                const r = try self.emit(.neg, ty, span, .{ .unary = v });
                // A float negation flips a sign bit and nothing can escape:
                // IEEE 754 defines the result for every input, so there is no
                // range to hold it to.
                if (ty.isFloat()) break :blk r;
                break :blk self.check(r, ty, self.opSpan(id), .overflow);
            },

            // A comparison yields `Bool`, so no range check follows it: its
            // result is one of two values and cannot leave them.
            .eq, .ne, .lt, .le, .gt, .ge => self.comparison(id, ty, span),

            .add, .sub, .mul, .div, .rem => blk: {
                const pair = self.ast.binary(id);
                const lhs = try self.expr(pair.lhs);
                if (try self.typeAt(pair.lhs) == .never) break :blk lhs;
                const rhs = try self.expr(pair.rhs);
                if (try self.typeAt(pair.rhs) == .never) break :blk rhs;
                break :blk self.arithmetic(self.ast.exprTag(id), self.opSpan(id), ty, span, lhs, rhs);
            },

            .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => self.compoundAssign(id, span),

            .conditional => self.conditional(id, ty, span, null),
            .logical_and, .logical_or => self.logical(id, ty, span),

            .block => self.blockExpr(id, dest),
        };
    }

    /// One of the two operations every comparison is made of.
    ///
    /// Two rather than six: `>` is `less` with its operands swapped and `<=`
    /// is `less` or `equals`, so a type says how it orders once and cannot
    /// disagree with itself.
    const Operation = enum { equals, less };

    /// Who supplies the operation a comparison runs.
    ///
    /// Discovery has selected either an intrinsic or a written implementation.
    const Supplier = union(enum) {
        /// The compiler's, or no library declaring the trait at all: the
        /// operator is the instruction it has always been.
        provided,
        /// A source wrote it, and this is the row a call goes through.
        written: types_mod.Implementation,
    };

    /// Which implementation discovery selected for this operand type.
    ///
    /// The checker's own lookup, so what a call runs here is what the
    /// operator's demand admitted there.
    ///
    /// **Bound:** one index lookup, asked once per trait a comparison names.
    /// That is one for the four operators made of a single operation and two
    /// for `<=` and `>=`, which are an order and an equality and so name two
    /// traits; the answer is carried from here into whichever operations it
    /// supplies rather than asked again per operation.
    fn supplierOf(
        self: *Lowerer,
        trait: ?DeclId,
        operand: TypeId,
    ) std.mem.Allocator.Error!Supplier {
        const declared = trait orelse return .provided;
        const row = self.mono.instances.selectedImplementation(declared, &.{}, operand) orelse
            @panic("compiler defect: comparison implementation was not settled");
        return if (row.isAmbient()) .provided else .{ .written = row };
    }

    /// The six comparison operators, as calls on the traits `std` declares.
    ///
    /// Intrinsic primitive operations can become direct instructions. An
    /// inclusive comparison combines into `cmp_le` or `cmp_ge` only when both
    /// selected operations are intrinsic and use the same receiver. Written
    /// equality remains a separate call even when ordering is intrinsic.
    ///
    /// Both operands are evaluated here and in the order they were written,
    /// whichever order the operation below takes them in.
    fn comparison(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const pair = self.ast.binary(id);
        const tag = self.ast.exprTag(id);
        const operand = try self.typeAt(pair.lhs);

        const orders = tag != .eq and tag != .ne;
        const trait = if (orders) self.library.comparable else self.library.equatable;

        const left = try self.expr(pair.lhs);
        if (try self.typeAt(pair.lhs) == .never) return left;
        const right = try self.expr(pair.rhs);
        if (try self.typeAt(pair.rhs) == .never) return right;
        const by = try self.supplierOf(trait, operand);
        const inclusive = tag == .le or tag == .ge;
        const equality: ?Supplier = if (inclusive) try self.supplierOf(self.library.equatable, operand) else null;
        switch (by) {
            .provided => {
                const receiver = if (trait) |declared| self.mono.instances.selectedReceiver(declared, &.{}, operand) else operand;
                if (equality) |equal_by| {
                    const equal_receiver = if (self.library.equatable) |declared| self.mono.instances.selectedReceiver(declared, &.{}, operand) else operand;
                    if (equal_by == .written or equal_receiver != receiver) {
                        return if (tag == .le)
                            self.orderOrEquality(by, equal_by, operand, left, right, left, right, ty, span)
                        else
                            self.orderOrEquality(by, equal_by, operand, right, left, left, right, ty, span);
                    }
                }
                const lhs = try self.observationArgument(left, operand, receiver, false, span);
                const rhs = try self.observationArgument(right, operand, receiver, false, span);
                const inst: Inst.Tag = switch (tag) {
                    .eq => .cmp_eq,
                    .ne => .cmp_ne,
                    .lt => .cmp_lt,
                    .le => .cmp_le,
                    .gt => .cmp_gt,
                    .ge => .cmp_ge,
                    else => unreachable,
                };
                return self.emit(inst, ty, span, .{ .binary = .{ .lhs = lhs, .rhs = rhs } });
            },
            // The six rows, and the one place the swap is written: `>` and
            // `>=` are the pair `less` takes the other way round, and the
            // equality beside an ordering keeps the order the operands were
            // written in.
            .written => return switch (tag) {
                .eq => self.operation(by, .equals, operand, left, right, span),
                .ne => self.negated(try self.operation(by, .equals, operand, left, right, span), span),
                .lt => self.operation(by, .less, operand, left, right, span),
                .gt => self.operation(by, .less, operand, right, left, span),
                .le => self.orderOrEquality(by, equality.?, operand, left, right, left, right, ty, span),
                .ge => self.orderOrEquality(by, equality.?, operand, right, left, left, right, ty, span),
                else => unreachable,
            },
        }
    }

    /// The trait an operation is declared by, or null where no library
    /// declares one.
    fn traitOf(self: *const Lowerer, op: Operation) ?DeclId {
        return switch (op) {
            .equals => self.library.equatable,
            .less => self.library.comparable,
        };
    }

    /// `equals(a, b)` or `less(a, b)`, at the operands in the order given.
    ///
    /// One place decides whether an operation is a call or an instruction, so
    /// a type whose ordering is written and whose equality is not still
    /// answers each the way its own implementation says.
    ///
    /// `by` is what the trait this operation is declared by reached, which the
    /// caller has already asked for: the operator names the trait before it
    /// knows how many operations it is made of, so asking again here would be
    /// the same lookup twice for every comparison written.
    fn operation(
        self: *Lowerer,
        by: Supplier,
        op: Operation,
        operand: TypeId,
        a: InstId,
        b: InstId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const trait = self.traitOf(op);
        const choice: types_mod.ImplementationChoice = if (trait) |declared|
            self.mono.instances.selectedChoice(declared, &.{}, operand)
        else
            .{ .supplier = .bound, .receiver = operand };
        const left = try self.receiverArgument(a, operand, choice, span);
        const right = try self.receiverArgument(b, operand, choice, span);
        switch (by) {
            .written => |row| {
                const sig = switch (op) {
                    .equals => self.library.equals,
                    .less => self.library.less,
                } orelse return self.poison(span);
                const member = (self.typing.supply_index.memberOf(row.decl, sig) orelse
                    return self.poison(span));
                const held = instantiate_mod.receiverKeying(self.ast, row.decl, choice.implementedFor());
                const impl_args = self.mono.instances.selectedArguments(trait.?, &.{}, operand);
                const callee = self.mono.idFor(member, &.{}, held, impl_args);
                return self.b.addCall(self.block, .value, .bool_, span, callee, &.{ left, right });
            },
            .provided => return self.emit(switch (op) {
                .equals => .cmp_eq,
                .less => .cmp_lt,
            }, .bool_, span, .{ .binary = .{ .lhs = left, .rhs = right } }),
        }
    }

    /// `!e`, which is `e == false`: the same shape the operator lowers to,
    /// because a comparison against the constant is what says it.
    fn negated(self: *Lowerer, value: InstId, span: Span) std.mem.Allocator.Error!InstId {
        const off = try self.emit(.constant, .bool_, span, .{ .constant = 0 });
        return self.emit(.cmp_eq, .bool_, span, .{ .binary = .{ .lhs = value, .rhs = off } });
    }

    /// A branch whose two arms each yield a value, as the branch, the slot and
    /// the join they become.
    ///
    /// The one encoding of a short-circuiting operator: `&&`, `||` and the
    /// `less(…) || equals(…)` that `<=` stands for differ only in what each arm
    /// runs, so what they share is written once and a change to how a value
    /// leaves a branch has one place to land. That is also how bindings already
    /// work, and it means neither MIR nor the backend needs a notion of SSA --
    /// the slot is a lowering device, not storage the program can reach.
    ///
    /// Each arm is entered with the lowerer positioned in its own block and
    /// answers with the value it yields. An arm that branches again leaves the
    /// lowerer in whatever block it ended in, which is the block that jumps to
    /// the join.
    fn branchToValue(
        self: *Lowerer,
        cond: InstId,
        ty: TypeId,
        span: Span,
        arms: anytype,
    ) std.mem.Allocator.Error!InstId {
        const then_block = try self.b.addBlock();
        const else_block = try self.b.addBlock();
        const join = try self.b.addBlock();
        const yields = ty != .unit and ty != .never;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        _ = try self.b.setTerminator(self.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = cond, .then_block = then_block, .else_block = else_block } },
        });

        self.block = then_block;
        const then_value = try arms.whenTrue(self);
        if (slot) |local| try self.storeLocal(local, ty, span, then_value);
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = join },
        });

        self.block = else_block;
        const else_value = try arms.whenFalse(self);
        if (slot) |local| try self.storeLocal(local, ty, span, else_value);
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = join },
        });

        self.block = join;
        if (slot) |local| return self.loadLocal(local, ty, span);
        if (ty == .never) {
            try self.finishNever(span);
            return self.afterNoreturn(span);
        }
        return self.unitOrPoison(ty, span);
    }

    /// `less(…) || equals(a, b)`, which is what `<=` and `>=` mean.
    ///
    /// The `||` the language already lowers, through the routine that lowers
    /// it: a branch, and an equality reached only where the order answered
    /// false. Not the negation of the swap -- `!less(b, a)` answers true for a
    /// pair a partial order relates neither way, and an order-or-equality
    /// answers false.
    fn orderOrEquality(
        self: *Lowerer,
        by: Supplier,
        equality: Supplier,
        operand: TypeId,
        first: InstId,
        second: InstId,
        a: InstId,
        b: InstId,
        ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const ordered = try self.operation(by, .less, operand, first, second, span);

        return self.branchToValue(ordered, ty, span, struct {
            by: Supplier,
            operand: TypeId,
            a: InstId,
            b: InstId,
            ty: TypeId,
            span: Span,

            fn whenTrue(arms: @This(), l: *Lowerer) std.mem.Allocator.Error!InstId {
                return l.emit(.constant, arms.ty, arms.span, .{ .constant = 1 });
            }

            fn whenFalse(arms: @This(), l: *Lowerer) std.mem.Allocator.Error!InstId {
                return l.operation(arms.by, .equals, arms.operand, arms.a, arms.b, arms.span);
            }
        }{
            .by = equality,
            .operand = operand,
            .a = a,
            .b = b,
            .ty = ty,
            .span = span,
        });
    }

    /// `a && b` and `a || b`, as the conditionals they are.
    ///
    /// `a && b` is `if a { b } else { false }` and `a || b` is
    /// `if a { true } else { b }`, so this is the same branch, the same join
    /// and the same slot the conditional uses -- one arm being a constant is
    /// the only difference. After this point nothing distinguishes the two:
    /// the MIR for `a && b` is the MIR for the `if` it stands for.
    fn logical(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const b = self.ast.binary(id);
        const short_circuits_on_false = self.ast.exprTag(id) == .logical_and;
        const cond = try self.expr(b.lhs);
        if (try self.typeAt(b.lhs) == .never) return cond;

        // The arm that runs the right operand, and the arm that supplies the
        // answer the operator already knows.
        return self.branchToValue(cond, ty, span, struct {
            rhs: ExprId,
            on_false: bool,
            ty: TypeId,
            span: Span,

            fn whenTrue(arms: @This(), l: *Lowerer) std.mem.Allocator.Error!InstId {
                if (arms.on_false) return l.expr(arms.rhs);
                return l.emit(.constant, arms.ty, arms.span, .{ .constant = 1 });
            }

            fn whenFalse(arms: @This(), l: *Lowerer) std.mem.Allocator.Error!InstId {
                if (arms.on_false) return l.emit(.constant, arms.ty, arms.span, .{ .constant = 0 });
                return l.expr(arms.rhs);
            }
        }{
            .rhs = b.rhs,
            .on_false = short_circuits_on_false,
            .ty = ty,
            .span = span,
        });
    }

    /// Lowers a conditional into a branch, two arms and a join.
    ///
    /// Where the conditional yields a value, each arm stores it to a slot and
    /// the join loads it. That is how bindings already work, and it means
    /// neither MIR nor the backend needs a notion of SSA -- the slot is a
    /// lowering device, not storage the program can reach.
    fn conditional(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, saved_condition: ?*InstId) std.mem.Allocator.Error!InstId {
        const c = self.ast.conditional(id);
        const cond = try self.expr(c.cond);
        if (try self.typeAt(c.cond) == .never) return cond;
        if (saved_condition) |saved| saved.* = cond;

        const then_block = try self.b.addBlock();
        const else_block = try self.b.addBlock();
        const join = try self.b.addBlock();

        // A slot only where there is a value to carry.
        const yields = ty != .unit and ty != .poison and ty != .never;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        _ = try self.b.setTerminator(self.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = cond, .then_block = then_block, .else_block = else_block } },
        });

        self.block = then_block;
        if (slot) |s| try self.storeExprIn(s, ty, span, c.then) else _ = try self.expr(c.then);
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = join },
        });

        self.block = else_block;
        if (c.otherwise != ExprId.none) {
            if (slot) |s| try self.storeExprIn(s, ty, span, c.otherwise) else _ = try self.expr(c.otherwise);
        }
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = join },
        });

        self.block = join;
        if (slot) |s| return self.loadLocal(s, ty, span);
        if (ty == .never) {
            try self.finishNever(span);
            return self.afterNoreturn(span);
        }
        return self.unitOrPoison(ty, span);
    }

    /// Where a jump inside a loop goes.
    ///
    /// `continue` returns to the block that decides whether to iterate again,
    /// which is a `while`'s header and a `loop`'s body; `break` leaves for the
    /// exit, storing to the slot first where the loop yields a value.
    const LoopFrame = struct {
        continue_to: BlockId,
        exit: BlockId,
        slot: ?LocalId,
        /// The option the slot holds, where the loop answers with one, and
        /// poison where the slot holds what a break site carries outright.
        ///
        /// A `for` yields `Option[E]` because it has two ways to end, so a
        /// `break e` stores `Some(e)` rather than `e`. Which it is belongs to
        /// the loop and not to the jump: a `break` is written the same way in
        /// every loop there is, and reading the enclosing construct's tag here
        /// would be a second answer to what the checker already settled.
        wraps: TypeId = TypeId.poison,
    };

    /// `loop { … }` becomes a body that jumps back to itself and an exit that
    /// only a `break` reaches.
    ///
    /// Where the loop yields a value, each break site stores it to a slot and
    /// the exit loads it -- the same device a conditional uses, for the same
    /// reason: neither MIR nor the backend needs a notion of SSA.
    fn loopExpr(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const body = try self.b.addBlock();
        const exit = try self.b.addBlock();

        const yields = ty != .unit and ty != .poison and ty != .never;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = body },
        });

        try self.loops.append(self.gpa, .{ .continue_to = body, .exit = exit, .slot = slot });
        self.block = body;
        _ = try self.expr(self.ast.unaryOperand(id));
        _ = self.loops.pop();

        // A body that ran to its end starts again. A `break` already left, and
        // setting a terminator on a block that has one is refused, so this is
        // reached only where control actually fell through.
        if (!self.b.hasTerminator(self.block)) {
            _ = try self.b.setTerminator(self.block, .{
                .tag = .jump,
                .ty = .unit,
                .span = span,
                .data = .{ .target = body },
            });
        }

        self.block = exit;
        if (slot) |s| return self.loadLocal(s, ty, span);
        if (ty == .never) {
            try self.finishNever(span);
            return self.afterNoreturn(span);
        }
        return self.unitOrPoison(ty, span);
    }

    /// Whether values of a type live in memory rather than in a register.
    ///
    /// Not the same question as `carriesBytes`, and deliberately two: all four
    /// answers to the pair name a type this pass sees. A scalar is a register
    /// with bytes and a structure is memory with bytes; `()` is a register with
    /// no bytes; and an aggregate whose every part is `()` is memory with no
    /// bytes. Answering one with the other would get one of the four wrong
    /// whichever way round it was folded.
    fn isAggregate(self: *const Lowerer, ty: TypeId) bool {
        return self.types().layoutOf(ty).isAggregate();
    }

    /// Whether a value of a type occupies any storage at all.
    ///
    /// The unit type does not, and a generic instantiated at it puts a part of
    /// width zero in a structure field or a variant payload. Nothing else in
    /// the language does, and nothing can annotate a binding with it, so the
    /// shape is reached by inference or not at all. A generic every part of
    /// which lands on `()` is the fourth case `isAggregate` names: a value that
    /// lives in memory and has nothing there.
    fn carriesBytes(self: *const Lowerer, ty: TypeId) bool {
        return self.types().layoutOf(ty).size > 0;
    }

    /// The value of a type that occupies no storage.
    ///
    /// Such a type has exactly one value, so it is produced rather than read.
    /// There are no bytes to read: a part of width zero sits at the offset the
    /// part after it begins at, which for a last part is the offset one past
    /// the whole.
    fn nothing(self: *Lowerer, ty: TypeId, span: Span) !InstId {
        return self.emit(.constant, ty, span, .{ .constant = 0 });
    }

    fn unitOrPoison(self: *Lowerer, ty: TypeId, span: Span) !InstId {
        return if (ty == .unit) self.nothing(.unit, span) else self.poison(span);
    }

    /// Reads a part through the address of the bytes it occupies.
    ///
    /// Three answers to one question, in the one place that asks it. A value
    /// that lives in memory *is* its address, so it is handed back rather than
    /// loaded. A value with no bytes is produced rather than loaded, because
    /// the machine has no zero-width load and every width the backend can pick
    /// for one would read bytes the object does not have. Everything else is a
    /// load at its own width.
    ///
    /// Where it lives is asked first, and `writeThrough` asks how many bytes
    /// first. The two part company only for a part that is memory with nothing
    /// in it, and the order is not arbitrary: this produces a value, and what a
    /// value *is* is settled by where it lives. An aggregate's value is the
    /// address of its bytes whether or not there are any, so the empty one is
    /// handed back as an address like every other. Asking about bytes first
    /// would hand back a constant, which every caller of this is entitled to
    /// treat as an address.
    fn readThrough(self: *Lowerer, at: InstId, ty: TypeId, span: Span) !InstId {
        if (try self.uninhabitedRead(ty, span)) |unreachable_value| return unreachable_value;
        return readStoredValue(self.b, self.block, self.types(), at, ty, span);
    }

    /// Writes a part through the address of the bytes it occupies.
    ///
    /// The reverse of `readThrough`, and the same three answers. A value that
    /// lives in memory is copied into place, because storing it would write its
    /// address into the part and leave the bytes in a frame that is about to
    /// end. A value with no bytes writes nothing: there is nowhere to put it,
    /// and a store emitted anyway is a store at some other width -- for a part
    /// at the end of its container, past the end of it.
    ///
    /// How many bytes is asked first, where `readThrough` asks where it lives.
    /// This moves bytes rather than producing a value, so the count is what
    /// decides whether there is anything to do, and it decides that for the
    /// empty aggregate as well: asking where it lives first would emit a copy
    /// of no bytes, an instruction with no effect whose operands the reader has
    /// to check anyway.
    fn writeThrough(self: *Lowerer, at: InstId, ty: TypeId, value: InstId, span: Span) !void {
        if (!self.carriesBytes(ty)) return;
        const tag: Inst.Tag = if (self.isAggregate(ty)) .move_value else .store_indirect;
        _ = try self.emit(tag, ty, span, .{ .binary = .{ .lhs = at, .rhs = value } });
    }

    /// Lowers an expression whose value belongs at an address it cannot name.
    ///
    /// The address goes to the expression first, so a literal builds its parts
    /// where they are wanted; what will not take it is evaluated and written
    /// through the address exactly as it was before.
    fn writeInto(self: *Lowerer, id: ExprId, ty: TypeId, at: InstId, span: Span) std.mem.Allocator.Error!void {
        var dest: Dest = .{ .at = at };
        const value = try self.exprInto(id, &dest);
        if (dest.used) return;
        if (!self.carriesBytes(ty)) return;
        if (self.isAggregate(ty)) {
            _ = try self.emit(self.blitOf(id), ty, span, .{ .binary = .{ .lhs = at, .rhs = value } });
        } else {
            try self.writeThrough(at, ty, value, span);
        }
    }

    /// Whether blitting the value of an expression moves it out of its place
    /// or copies it, as the program wrote it: a place ownership tracks that was
    /// written in a reading position stays held beneath the blit.
    fn blitOf(self: *const Lowerer, id: ExprId) Inst.Tag {
        return if (self.readsAPlace(id)) .copy_value else .move_value;
    }

    /// Where an aggregate writes its parts: the destination it was offered, or
    /// a slot of its own.
    ///
    /// Every builder asks this rather than allocating outright, so taking a
    /// destination is one decision and the builders differ only in what they
    /// then write. A value that lives in a register has no parts to write
    /// through an address, so it keeps its slot and leaves the offer alone.
    fn baseFor(self: *Lowerer, ty: TypeId, span: Span, dest: ?*Dest) !InstId {
        if (self.isAggregate(ty)) {
            if (dest) |d| {
                d.used = true;
                return d.at;
            }
        }
        const slot = try self.b.addLocal(ty, .value);
        return self.emit(.addr_of, ty, span, .{ .local = slot });
    }

    /// `copy(e)`: a value no later operation on `e` can reach.
    ///
    /// The independence is established here, at the copy, rather than left to
    /// whoever consumes the value. A consumer runs later -- for a call
    /// argument, after the whole argument list -- so a copy that only handed
    /// its source along would be read after anything else in that list had
    /// already written to it.
    fn copyExpr(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) !InstId {
        const operand = self.ast.unaryOperand(id);
        const value = try self.expr(operand);
        if (try self.typeAt(operand) == .never) return value;
        if (!self.isAggregate(ty)) return value;

        // The one blit that leaves its source owned: `copy_value` rather than
        // the `move_value` every other transfer of an aggregate is.
        const slot = try self.b.addLocal(ty, .value);
        const dst = try self.emit(.addr_of, ty, span, .{ .local = slot });
        _ = try self.emit(.copy_value, ty, span, .{ .binary = .{ .lhs = dst, .rhs = value } });
        return self.loadLocal(slot, ty, span);
    }

    /// The value of a slot.
    ///
    /// A value that lives in memory *is* its address, so reading the slot
    /// yields the address rather than what is at it. Every site that reads a
    /// binding goes through here, which is why none of them had to learn that
    /// some types are wider than a word.
    fn loadLocal(self: *Lowerer, local: LocalId, ty: TypeId, span: Span) !InstId {
        if (try self.uninhabitedRead(ty, span)) |unreachable_value| return unreachable_value;
        if (self.isAggregate(ty)) return self.emit(.addr_of, ty, span, .{ .local = local });
        return self.emit(.load, ty, span, .{ .local = local });
    }

    /// No value can be read from Never storage, through a slot or an address.
    fn uninhabitedRead(self: *Lowerer, ty: TypeId, span: Span) std.mem.Allocator.Error!?InstId {
        if (ty != .never) return null;
        try self.finishNever(span);
        return try self.afterNoreturn(span);
    }

    /// Writes a value into a slot.
    ///
    /// For a value that lives in memory this copies the bytes rather than the
    /// address: the slot is that value's storage, and storing the address
    /// would leave two names sharing one buffer.
    ///
    /// A scalar slot uses its recorded storage width; an aggregate slot owns
    /// its canonical layout extent. Empty aggregates still copy zero bytes,
    /// while zero-sized scalar values occupy the Unit storage convention.
    fn storeLocal(self: *Lowerer, local: LocalId, ty: TypeId, span: Span, value: InstId) !void {
        if (!self.isAggregate(ty)) {
            _ = try self.emit(.store, ty, span, .{ .store = .{ .local = local, .value = value } });
            return;
        }
        const dst = try self.emit(.addr_of, ty, span, .{ .local = local });
        _ = try self.emit(.move_value, ty, span, .{ .binary = .{ .lhs = dst, .rhs = value } });
    }

    /// As `storeLocal`, where what is stored is still an expression and the
    /// slot is one lowering minted for it.
    ///
    /// The slot's address is offered to the expression, so a literal fills the
    /// slot rather than filling a second one and copying. Sound because such a
    /// slot is unnameable: a `let`'s local is not in scope in its own
    /// initialiser, and a join's slot has no name at all.
    fn storeExprIn(self: *Lowerer, local: LocalId, ty: TypeId, span: Span, id: ExprId) !void {
        // A non-completing expression reaches no store. Lower it for its
        // control flow, but never materialize the value its type says cannot
        // exist.
        if (try self.typeAt(id) == .never) {
            _ = try self.expr(id);
            return;
        }
        if (!self.isAggregate(ty)) return self.storeLocal(local, ty, span, try self.expr(id));

        var dest: Dest = .{ .at = try self.emit(.addr_of, ty, span, .{ .local = local }) };
        const value = try self.exprInto(id, &dest);
        if (dest.used) return;
        // A slot is sized for its whole type, so an aggregate with no bytes is
        // copied rather than skipped -- the same reason `storeLocal` copies one.
        // A place the program did not take stays held beneath the blit.
        _ = try self.emit(self.blitOf(id), ty, span, .{ .binary = .{ .lhs = dest.at, .rhs = value } });
    }

    /// Whether the value an expression yields is a place the program wrote in
    /// a reading position, as ownership recorded it, so blitting the value
    /// leaves the place held. A block yields its tail, so it sits where the
    /// tail does; an arm of a conditional or a `match` sits where the
    /// construct sits, which is how a read argument's arm only reads.
    fn readsAPlace(self: *const Lowerer, id: ExprId) bool {
        var at = self.ast.withoutGroups(id);
        while (self.ast.exprTag(at) == .block) {
            const tail = self.ast.blockOf(at).tail;
            if (tail == ExprId.none) return false;
            at = self.ast.withoutGroups(tail);
        }
        return self.disposals.reads(at);
    }

    /// Where a part of a value a pattern takes apart is: its type, its address
    /// where it lives somewhere a lend can name, and its value where that is
    /// already in hand. An aggregate's value is its address, so it has both.
    const Matched = struct {
        ty: TypeId,
        address: InstId = .none,
        value: InstId = .none,
    };

    /// A value lowering produced, about to be taken apart.
    fn matchedValueOf(self: *const Lowerer, ty: TypeId, value: InstId) Matched {
        if (self.isAggregate(ty)) return .{ .ty = ty, .address = value, .value = value };
        return .{ .ty = ty, .value = value };
    }

    /// A place about to be lent apart. A newtype's base is lent from the
    /// newtype's own address, which `lendingPlace` finds even for a scalar.
    fn matchedPlaceOf(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) std.mem.Allocator.Error!Matched {
        const place = try self.lendingPlace(id, ty, span);
        if (self.isAggregate(ty)) return .{ .ty = ty, .address = place, .value = place };
        if (self.types().get(ty) == .newtype) return .{ .ty = ty, .address = place };
        return .{ .ty = ty, .value = place };
    }

    /// The value at `m`, read through its address where it is not in hand.
    fn matchedValue(self: *Lowerer, m: Matched, span: Span) std.mem.Allocator.Error!InstId {
        if (m.value != .none) return m.value;
        return self.readThrough(m.address, m.ty, span);
    }

    /// The part of `m` that the part at `index` of `pattern`'s arguments
    /// selects. Which part is the checker's selection -- a struct pattern's
    /// field, a tuple's position, a variant's payload position -- and the
    /// offset is this instance's layout of it. A newtype's base is the
    /// newtype's own representation.
    fn matchedPart(self: *Lowerer, pattern: ExprId, m: Matched, index: usize, span: Span) std.mem.Allocator.Error!Matched {
        const args = self.ast.call(pattern).args;
        const ty = try self.typeAt(args[index]);
        const view = self.types();
        const offset: u32 = switch (self.ast.exprTag(pattern)) {
            .struct_pattern => blk: {
                const selected = self.typing.fieldSelection(self.ast.exprMain(args[index - 1])) orelse
                    @panic("compiler defect: a struct pattern's field was not settled before emission");
                break :blk view.fieldOffset(m.ty, selected.field.index());
            },
            .tuple_pattern => view.fieldOffset(m.ty, @intCast(index)),
            else => if (view.get(m.ty) == .newtype) {
                if (m.address == .none) return .{ .ty = ty, .value = m.value };
                return .{ .ty = ty, .address = try self.fieldAddr(m.address, ty, 0, span) };
            } else view.variantFieldOffset(m.ty, self.variantIndex(pattern), @intCast(index)),
        };
        return .{ .ty = ty, .address = try self.fieldAddr(m.address, ty, offset, span) };
    }

    /// Where `pattern`'s parts sit among its arguments.
    fn partStride(self: *const Lowerer, pattern: ExprId) ?usize {
        return switch (self.ast.exprTag(pattern)) {
            .struct_pattern => 2,
            .tuple_pattern, .call => 1,
            else => null,
        };
    }

    /// Tests that `pattern` matches the value at `m`, its outer part first,
    /// and branches to `fail` at the first part that does not, leaving the
    /// lowerer where every test passed. A payload is read only once its
    /// variant's tag has been tested, because control reaches the read only
    /// through that test. Answers false after ending an arm whose variant
    /// carries a concrete `Never`, which no value can be.
    fn testPattern(self: *Lowerer, pattern: ExprId, m: Matched, fail: BlockId, span: Span) std.mem.Allocator.Error!bool {
        // The parts that bind are skipped before this is asked, so a bare
        // name here is the head of an arm: `_`, or a variant.
        if (isCatchAll(self.ast, pattern)) return true;
        switch (self.ast.exprTag(pattern)) {
            .int_literal, .negate => {
                const value = try self.matchedValue(m, span);
                const want = try self.expr(pattern);
                const eq = try self.emit(.cmp_eq, .bool_, span, .{ .binary = .{ .lhs = value, .rhs = want } });
                try self.branchOn(eq, fail, span);
                return true;
            },
            .range => {
                const value = try self.matchedValue(m, span);
                const pass = try self.b.addBlock();
                try self.rangeArmGuard(pattern, value, pass, fail, span);
                self.block = pass;
                return true;
            },
            .name_ref, .call => if (self.types().get(m.ty) != .newtype) {
                const k = self.variantIndex(pattern);
                const tag = if (self.isAggregate(m.ty))
                    try self.emit(.load_indirect, tag_type, span, .{ .unary = m.address })
                else
                    try self.matchedValue(m, span);
                const want_ty = if (self.isAggregate(m.ty)) tag_type else m.ty;
                const want = try self.emit(.constant, want_ty, span, .{ .constant = k });
                const eq = try self.emit(.cmp_eq, .bool_, span, .{ .binary = .{ .lhs = tag, .rhs = want } });
                try self.branchOn(eq, fail, span);
                // A concrete Never field makes this variant impossible. End
                // the arm before creating addresses for values that cannot
                // exist.
                const view = self.types();
                for (0..view.variantFieldCount(m.ty, k)) |j| {
                    if (view.variantFieldType(m.ty, k, @intCast(j)) != .never) continue;
                    try self.finishNever(span);
                    return false;
                }
            },
            else => {},
        }
        const stride = self.partStride(pattern) orelse return true;
        const args = self.ast.call(pattern).args;
        var i = stride - 1;
        while (i < args.len) : (i += stride) {
            const part = args[i];
            if (isCatchAll(self.ast, part) or self.ast.partBinds(part)) continue;
            if (!try self.testPattern(part, try self.matchedPart(pattern, m, i, span), fail, span)) return false;
        }
        return true;
    }

    /// Continues where `cond` holds and goes to `fail` where it does not.
    fn branchOn(self: *Lowerer, cond: InstId, fail: BlockId, span: Span) std.mem.Allocator.Error!void {
        const pass = try self.b.addBlock();
        _ = try self.b.setTerminator(self.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = cond, .then_block = pass, .else_block = fail } },
        });
        self.block = pass;
    }

    /// Binds every binder of `pattern`, at any depth, to its part of the
    /// value at `m`: lent as the address the part sits at, or owned as its
    /// value in a slot of its own. Emitted once every test passed, so only a
    /// value the pattern matched is taken apart.
    fn bindPattern(self: *Lowerer, pattern: ExprId, m: Matched, lending: bool, span: Span) std.mem.Allocator.Error!void {
        const stride = self.partStride(pattern) orelse return;
        const args = self.ast.call(pattern).args;
        var i = stride - 1;
        while (i < args.len) : (i += stride) {
            const part = args[i];
            if (!self.ast.partBinds(part)) {
                if (self.partStride(part) != null) try self.bindPattern(part, try self.matchedPart(pattern, m, i, span), lending, span);
                continue;
            }
            const target = self.res.targetOf(part);
            if (target == BindingId.none) continue;
            const at = try self.matchedPart(pattern, m, i, span);
            if (lending) {
                try self.lent.put(self.gpa, target, at.address);
                continue;
            }
            const value = try self.matchedValue(at, span);
            const local = try self.b.addLocal(at.ty, .value);
            self.local_of_binding[target.index()] = local;
            try self.storeLocal(local, at.ty, span, value);
        }
    }

    /// Ends the lends `bindPattern` made, at the end of the construct.
    fn endPatternLends(self: *Lowerer, pattern: ExprId) void {
        var parts = self.ast.patternParts(pattern);
        while (parts.next()) |part| {
            if (self.ast.partBinds(part)) {
                const target = self.res.targetOf(part);
                if (target != BindingId.none) _ = self.lent.remove(target);
            } else {
                self.endPatternLends(part);
            }
        }
    }

    /// `let S { f: b, .. } = e`: each binder gets a slot holding its part.
    ///
    /// The value is taken apart rather than kept: every part is named exactly
    /// once, so what the slot held is entirely accounted for by the slots the
    /// binders get.
    ///
    /// `let read` binds the same parts as lends of the place, which is what a
    /// `match read` arm's binders are: each name reads through the address
    /// its part sits at, and nothing is copied or stored. Checking proved the
    /// initialiser is a place, so the address is the place's own.
    fn destructure(self: *Lowerer, s: StmtId) std.mem.Allocator.Error!void {
        const d = self.ast.stmtData(s);
        if (d.init == ExprId.none or d.pattern == ExprId.none) return;

        const span = self.ast.stmtSpan(s);
        const lending = self.ast.stmtTag(s) == .let_read_destructure;
        const of = try self.typeAt(d.init);
        const m = if (lending) try self.matchedPlaceOf(d.init, of, span) else self.matchedValueOf(of, try self.expr(d.init));
        return self.bindPattern(d.pattern, m, lending, span);
    }

    /// The address of a field within a value held in memory.
    ///
    /// The projection is retained at offset zero because its result type says
    /// what the managed address denotes. The backend may erase the no-op
    /// offset, but MIR may not erase the type transition with it.
    fn fieldAddr(self: *Lowerer, base: InstId, result_ty: TypeId, offset: u32, span: Span) !InstId {
        const off = try self.emit(.constant, .u64, span, .{ .constant = offset });
        return self.emit(.field_addr, result_ty, span, .{ .binary = .{ .lhs = base, .rhs = off } });
    }

    fn isIndirect(self: *const Lowerer, local: LocalId) bool {
        return self.b.slotRoleOf(local) == .managed_address;
    }

    /// The address a name is reached through, or null where it names storage
    /// of its own.
    ///
    /// Indirect parameters hold an address in their slot. Match and traversal
    /// binders and captures use the address registered in `lent`. Reads, writes
    /// and borrows all resolve these names through the same source address.
    fn addressBehind(
        self: *Lowerer,
        target: BindingId,
        ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!?InstId {
        if (target != BindingId.none) {
            if (self.lent.get(target)) |at| return at;
        }
        const local = self.local_of_binding[target.index()];
        if (!self.isIndirect(local)) return null;
        return try self.emit(.load, ty, span, .{ .local = local });
    }

    /// `&p` becomes the address of `p`'s slot.
    ///
    /// Where `p` is itself an `inout` parameter its slot already holds an
    /// address, so passing it on is a load rather than another `addr_of`.
    fn addressOf(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        // Parentheses are a node and name the same place, so they are stepped
        // through here as everywhere else a place is walked. Without this
        // `&(o.inner)` matched neither shape below and lowered to poison,
        // which the callee then wrote through.
        return self.addressOfPlace(self.ast.unaryOperand(id), span);
    }

    fn addressOfPlace(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        const place = self.ast.withoutGroups(id);

        // A path's address is the field's, computed exactly as an assignment
        // through the same path computes it -- `bump(&o.inner.y)` and
        // `o.inner.y = ...` reach the same bytes, so they reach them the same
        // way. A constant is the root of a path, however it is named.
        if (self.ast.isSelection(place) or self.res.constantNamed(place) != BindingId.none) {
            const address = try self.placeAddress(place, span);
            if (address == InstId.none) return self.poison(span);
            return address;
        }

        const target = self.res.targetOf(place);
        if (target == BindingId.none) return self.poison(span);

        const ty = try self.typeAt(place);
        // A lend is already an address, so marking it hands that address on
        // rather than taking the address of whatever holds it.
        if (try self.addressBehind(target, ty, span)) |p| return p;

        return self.emit(.addr_of, ty, span, .{ .local = self.local_of_binding[target.index()] });
    }

    /// A variant is its tag: the position it was declared in.
    ///
    /// Constructs the variant selected by resolution or checking.
    fn variantRef(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        return self.buildVariant(ty, self.variantIndex(id), .{ .values = &.{} }, span, dest);
    }

    /// A value of enum type: its tag, then whatever the variant carries.
    ///
    /// Where the type fits a register the value is the tag and nothing more,
    /// which is what every fieldless enum was before payloads existed. Where
    /// it does not, the value is a slot filled in and handed on by address.
    fn buildVariant(
        self: *Lowerer,
        ty: TypeId,
        k: u32,
        carried: Carried,
        span: Span,
        dest: ?*Dest,
    ) std.mem.Allocator.Error!InstId {
        if (!self.isAggregate(ty)) return self.emit(.constant, ty, span, .{ .constant = k });
        const tag = try self.emit(.constant, tag_type, span, .{ .constant = k });

        const base = try self.baseFor(ty, span, dest);
        try self.writeThrough(base, tag_type, tag, span);

        // Each store carries what it writes, not what it writes into: the
        // backend picks a width from the instruction's type, and the enum's
        // width is the whole value rather than this part of it.
        for (0..carried.count()) |j| {
            const field = self.types().variantFieldType(ty, @intCast(k), @intCast(j));
            const offset = self.types().variantFieldOffset(ty, @intCast(k), @intCast(j));
            const at = try self.fieldAddr(base, field, offset, span);
            switch (carried) {
                .values => |v| try self.writeThrough(at, field, v[j], span),
                .written => |a| try self.writeInto(a[j], field, at, span),
            }
        }
        return base;
    }

    /// `Shape.Circle(3)`. Builds the variant rather than calling anything.
    fn construct(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const c = self.ast.call(id);
        if (ty == .never) {
            for (c.args) |arg| {
                const value = try self.expr(arg);
                if (try self.typeAt(arg) == .never) return value;
            }
            return self.poison(span);
        }
        return self.buildVariant(ty, self.variantIndex(self.ast.withoutGroups(c.callee)), .{ .written = c.args }, span, dest);
    }

    /// What a variant carries at one position, read out of the value.
    ///
    /// Consuming binders and `?` read through the same payload address that
    /// read-match binders lend. The concrete layout supplies its offset.
    fn carriedAt(
        self: *Lowerer,
        of: TypeId,
        value: InstId,
        k: u32,
        j: u32,
        ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        return self.readThrough(try self.carriedAddress(of, value, k, j, ty, span), ty, span);
    }

    fn carriedAddress(
        self: *Lowerer,
        of: TypeId,
        value: InstId,
        k: u32,
        j: u32,
        ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        return self.fieldAddr(value, ty, self.types().variantFieldOffset(of, k, j), span);
    }

    /// `p.x`, or `Colour.Red`.
    ///
    /// A type on the left is a variant, which is its tag. A value on the left
    /// is a field, which is an address and a load -- the same two instructions
    /// a binder already emits, at a different offset.
    fn selection(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        if (self.res.targetOf(id) != BindingId.none) return self.variantRef(id, ty, span, dest);

        const address = try self.selectedAddress(id, span);
        if (ty == .never) return address;
        return self.readThrough(address, ty, span);
    }

    /// `.{ x = 1 }`. A slot, filled in, handed on by address.
    /// `[a, b, c]` becomes a slot and one write per element.
    ///
    /// The same shape a braced literal lowers to, with the offset a product of
    /// the stride rather than a field's recorded place -- which is the whole of
    /// what an array adds to the arrangement.
    /// `"a{x}b"` becomes the value holding its pieces.
    ///
    /// Built exactly as a structure literal is, which is what it is: the
    /// evaluation happens here, in written order, once each -- so an
    /// interpolation rendered twice does not compute its pieces twice, and one
    /// that is never rendered still computes them where it was written.
    fn interpolation(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const pieces = self.ast.interpolation(id).pieces;

        if (ty == .never) {
            for (pieces) |piece| {
                const value = try self.expr(piece);
                if (try self.typeAt(piece) == .never) return value;
            }
            return self.poison(span);
        }

        const base = try self.baseFor(ty, span, dest);

        for (pieces, 0..) |piece, i| {
            const held = self.types().fieldType(ty, @intCast(i));
            const at = try self.fieldAddr(base, held, self.types().fieldOffset(ty, @intCast(i)), span);
            const borrowed = self.types().interpolationBorrows(ty, @intCast(i));
            if (self.typing.interpolationPosition(piece)) |position| std.debug.assert((position == .borrowed) == borrowed);
            if (borrowed) {
                const observed = try self.emit(.borrow, held, span, .{ .unary = try self.borrowedAddress(piece, span) });
                try self.writeThrough(at, held, observed, span);
            } else {
                // A copied piece names a place ownership recorded as read, so
                // the blit copies it and the place stays the program's; a
                // moved piece is a computed value, built into the literal.
                try self.writeInto(piece, held, at, span);
            }
        }
        return base;
    }

    /// The address a borrow of `id` observes. A place is borrowed where it
    /// lives. Any other value is evaluated into a slot of its own, which is
    /// the temporary its statement keeps alive.
    fn borrowedAddress(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        if (!self.typing.borrowed_temporaries.contains(self.ast.withoutGroups(id))) return self.addressOfPlace(id, span);
        const ty = try self.typeAt(id);
        const slot = try self.b.addLocal(ty, .value);
        try self.storeExprIn(slot, ty, span, id);
        return self.emit(.addr_of, ty, span, .{ .local = slot });
    }

    fn arrayLiteral(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const c = self.ast.call(id);

        if (ty == .never) {
            for (c.args) |arg| {
                const value = try self.expr(arg);
                if (try self.typeAt(arg) == .never) return value;
            }
            return self.poison(span);
        }

        const base = try self.baseFor(ty, span, dest);
        if (self.array_elisions) |elisions| if (elisions.contains(id)) return base;

        const element = switch (self.types().get(ty)) {
            .array => |a| a.element,
            else => return base,
        };
        const stride = self.types().strideOf(element);

        for (c.args, 0..) |a, i| {
            const at = try self.fieldAddr(base, element, @intCast(stride * i), span);
            try self.writeInto(a, element, at, span);
        }
        return base;
    }

    /// `a[i]` becomes a bounds check and an address.
    ///
    /// The check folds away where the index is a constant the array's length
    /// holds: the comparison's answer is written in the program. A constant no
    /// element sits at -- reachable only through a generic body checked before
    /// the array's length was known -- keeps the check, which traps.
    fn foldedIndex(self: *Lowerer, id: ExprId) ?u64 {
        return self.typing.foldedIndex(self.ast.withoutGroups(self.spliced(id)));
    }

    fn indexExpr(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const b = self.ast.binary(id);
        const head_ty = try self.typeAt(b.lhs);

        if (ty == .never) {
            const head = try self.expr(b.lhs);
            if (head_ty == .never) return head;
            const index = try self.expr(b.rhs);
            if (try self.typeAt(b.rhs) == .never) return index;
            return self.poison(span);
        }

        const addr = try self.elementAddress(id, span);
        if (addr == InstId.none) return self.poison(span);
        return self.readThrough(addr, ty, span);
    }

    /// `"hello"` becomes the `Str` the library declares: the address of a blob
    /// the module carries, and how many bytes it holds.
    ///
    /// Built exactly as a structure literal is, because that is what it is --
    /// a slot, and a write through each field's address. What the compiler
    /// supplies is the two values; what they mean is `std/text/`'s to say.
    fn strLiteral(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        // What the literal means, not how it was spelled: the same routine the
        // lexer already ran to decide the escapes could be read. A literal that
        // reaches here has been through that, so it cannot fail differently.
        return self.strValue(try self.mono.internLiteral(self.ast, id), ty, span, dest);
    }

    /// The `Str` or byte slice over a file the loader read. Its bytes join the
    /// pool every literal is interned in, so a file and a literal holding the
    /// same bytes are one blob, and every embedded byte reaches the emitted
    /// code.
    fn embedded(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const bytes = self.res.embeds.bytesOf(id) orelse return self.poison(span);
        return self.strValue(try self.mono.internBytes(bytes), ty, span, dest);
    }

    /// A `Str` over a blob already in the pool.
    ///
    /// Apart from the literal that spelled it, because a blob the compiler wrote
    /// has no literal: a test's name reaches a generated call this way, and
    /// building the value a second way there would be a second answer to what a
    /// `Str` is made of.
    fn strValue(self: *Lowerer, blob: u32, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const fields = self.types().textFields(ty) orelse return self.poison(span);
        const at = fields.at;
        const len = fields.len;
        const base = try self.baseFor(ty, span, dest);

        const address = try self.emit(.bytes_addr, at.ty, span, .{ .bytes = blob });
        try self.writeThrough(try self.fieldAddr(base, at.ty, at.offset, span), at.ty, address, span);

        // Read back from the pool, so the length is the decoded blob's and not
        // the spelling's: `"\u{e1}"` is six characters and two bytes.
        const held: i128 = @intCast(self.mono.bytes.items[blob].len);
        const count = try self.emit(.constant, len.ty, span, .{ .constant = held });
        try self.writeThrough(try self.fieldAddr(base, len.ty, len.offset, span), len.ty, count, span);

        return base;
    }

    fn structLiteral(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const c = self.ast.call(id);
        const update = self.ast.structLiteralBase(id);

        if (ty == .never) {
            var at: usize = 1;
            while (at < c.args.len) : (at += 2) {
                const value = try self.expr(c.args[at]);
                if (try self.typeAt(c.args[at]) == .never) return value;
            }
            if (update) |written| {
                const value = try self.expr(written);
                if (try self.typeAt(written) == .never) return value;
            }
            return self.poison(span);
        }

        const base = try self.baseFor(ty, span, dest);

        // Which fields the literal writes, kept only where a base supplies the
        // rest. Sized by the literal's own type.
        const given: []bool = if (update != null) try self.gpa.alloc(bool, self.types().fieldCount(ty)) else &.{};
        defer if (update != null) self.gpa.free(given);
        @memset(given, false);

        var i: usize = 0;
        while (i + 1 < c.args.len) : (i += 2) {
            const name = self.ast.tokenText(self.ast.exprMain(c.args[i]));

            // A field the type does not have was reported; what was written
            // for it is still lowered, because its effect is in the program.
            const found = self.types().lookupField(ty, name) orelse {
                _ = try self.expr(c.args[i + 1]);
                continue;
            };
            if (update != null) given[found.index] = true;
            const at = try self.fieldAddr(base, found.ty, found.offset, span);
            try self.writeInto(c.args[i + 1], found.ty, at, span);
        }

        // `..written` runs after the written fields, then each field the
        // literal did not write is copied out of it. The destination is one
        // the program cannot name, so the base cannot observe the fields
        // already written into it.
        if (update) |written| {
            const from = try self.expr(written);
            for (given, 0..) |had, f| {
                if (had) continue;
                const field: u32 = @intCast(f);
                const field_ty = self.types().fieldType(ty, field);
                const offset = self.types().fieldOffset(ty, field);
                const value = try self.readThrough(try self.fieldAddr(from, field_ty, offset, span), field_ty, span);
                try self.writeThrough(try self.fieldAddr(base, field_ty, offset, span), field_ty, value, span);
            }
        }
        return base;
    }

    /// `(a, b)`: a structure literal whose fields are the components in
    /// order. The tuple's declaration names its fields by position, so each
    /// component is written through the field at its own index and no name
    /// is looked up.
    fn tupleLiteral(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const c = self.ast.call(id);

        if (ty == .never) {
            for (c.args) |arg| {
                const value = try self.expr(arg);
                if (try self.typeAt(arg) == .never) return value;
            }
            return self.poison(span);
        }

        const base = try self.baseFor(ty, span, dest);
        for (c.args, 0..) |arg, i| {
            const field: u32 = @intCast(i);
            const field_ty = self.types().fieldType(ty, field);
            const at = try self.fieldAddr(base, field_ty, self.types().fieldOffset(ty, field), span);
            try self.writeInto(arg, field_ty, at, span);
        }
        return base;
    }

    /// `^k`: lowers exactly as the structure literal `{ .k = k }` would,
    /// because that is what the checker typed it as.
    ///
    /// Reached where the value itself is wanted -- a bracket over a container
    /// whose implementation takes one and hands it on. A bracket over an array
    /// never builds one: the array interprets the count, so what it needs is
    /// the number and not a value holding it.
    fn fromEndValue(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const operand = self.ast.unaryOperand(id);
        if (ty == .never) return self.expr(operand);
        const base = try self.baseFor(ty, span, dest);
        const k = self.types().lookupField(ty, "k").?;
        try self.writeInto(operand, k.ty, try self.fieldAddr(base, k.ty, k.offset, span), span);
        return base;
    }

    /// `lo..hi` or `lo..=hi`: lowers exactly as the struct literal
    /// `{ .lo = lo, .hi = hi, .inclusive = k }` would, because that is what
    /// the checker typed it as. The flag is written from the node rather than
    /// from an operand -- it has no expression of its own, only what the
    /// spelling settled.
    fn rangeExpr(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const ends = self.ast.rangeEnds(id);

        if (ty == .never) {
            const lo = try self.expr(ends.lhs);
            if (try self.typeAt(ends.lhs) == .never) return lo;
            const hi = try self.expr(ends.rhs);
            if (try self.typeAt(ends.rhs) == .never) return hi;
            return self.poison(span);
        }
        const base = try self.baseFor(ty, span, dest);

        const lo = self.types().lookupField(ty, "lo").?;
        try self.writeInto(ends.lhs, lo.ty, try self.fieldAddr(base, lo.ty, lo.offset, span), span);

        const hi = self.types().lookupField(ty, "hi").?;
        try self.writeInto(ends.rhs, hi.ty, try self.fieldAddr(base, hi.ty, hi.offset, span), span);

        const inclusive = self.types().lookupField(ty, "inclusive").?;
        const flag_at = try self.fieldAddr(base, inclusive.ty, inclusive.offset, span);
        const flag = try self.emit(.constant, inclusive.ty, span, .{
            .constant = @intFromBool(self.ast.rangeInclusive(id)),
        });
        try self.writeThrough(flag_at, inclusive.ty, flag, span);

        return base;
    }

    /// `lo <= v` and, by `hi_tag`, `v <= hi` or `v < hi`, tested in sequence
    /// so `body_block` is reached only where both hold -- the pair beside the
    /// single `cmp_eq` a literal match arm emits.
    ///
    /// Shared by a range arm's guard and a refined newtype's fallible
    /// construction: both ask "is this value in bounds" as two comparisons
    /// and a pair of branches, and asking it twice is how the two could come
    /// to disagree about what "in bounds" lowers to.
    fn boundsGuard(
        self: *Lowerer,
        value: InstId,
        lo: InstId,
        hi: InstId,
        hi_tag: Inst.Tag,
        body_block: BlockId,
        next: BlockId,
        span: Span,
    ) std.mem.Allocator.Error!void {
        const ge = try self.emit(.cmp_ge, .bool_, span, .{ .binary = .{ .lhs = value, .rhs = lo } });

        const mid = try self.b.addBlock();
        _ = try self.b.setTerminator(self.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = ge, .then_block = mid, .else_block = next } },
        });

        self.block = mid;
        const le = try self.emit(hi_tag, .bool_, span, .{ .binary = .{ .lhs = value, .rhs = hi } });
        _ = try self.b.setTerminator(self.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = le, .then_block = body_block, .else_block = next } },
        });
    }

    /// A range arm's guard: `lo <= v` and, by the spelling, `v <= hi` or
    /// `v < hi`.
    ///
    /// Each bound lowers as any expression does: a literal reads its own
    /// text, and a name reaching a constant reads through to what it is
    /// bound to -- nothing here re-derives a value the checker
    /// already settled.
    fn rangeArmGuard(
        self: *Lowerer,
        pattern: ExprId,
        tag: InstId,
        body_block: BlockId,
        next: BlockId,
        span: Span,
    ) std.mem.Allocator.Error!void {
        const ends = self.ast.rangeEnds(pattern);
        const lo = try self.expr(ends.lhs);
        const hi = try self.expr(ends.rhs);
        const hi_tag: Inst.Tag = if (self.ast.rangeInclusive(pattern)) .cmp_le else .cmp_lt;
        try self.boundsGuard(tag, lo, hi, hi_tag, body_block, next, span);
    }

    /// What a lending pattern binds through: an aggregate's value is already
    /// its address, and a newtype's base is lent from the newtype's own
    /// address, which `matchPlace` finds.
    fn lendingPlace(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) !InstId {
        if (self.types().get(ty) == .newtype) return self.matchPlace(id, ty, span);
        return self.expr(id);
    }

    // A scalar newtype needs its original address when its base is lent.
    // An unnamed temporary gets one slot for the duration of the match.
    fn matchPlace(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) !InstId {
        if (self.isAggregate(ty)) return self.expr(id);
        const source = self.ast.withoutGroups(id);
        const target = self.res.targetOf(source);
        if (self.ast.isSelection(source) or self.res.constantNamed(source) != BindingId.none or
            (self.ast.exprTag(source) == .name_ref and target != BindingId.none))
            return self.addressOfPlace(source, span);
        const value = try self.expr(id);
        const local = try self.b.addLocal(ty, .value);
        try self.storeLocal(local, ty, span, value);
        return self.emit(.addr_of, ty, span, .{ .local = local });
    }

    /// `match e { … }` becomes a chain of arms, each testing its pattern and
    /// then binding what it names.
    ///
    /// A test is a comparison and a branch, which is what a conditional
    /// already lowers to, so nothing new reaches MIR and the edge table gains
    /// nothing. Where the match yields a value each arm stores to a slot and
    /// the join loads it, exactly as a conditional's arms do.
    fn matchExpr(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const m = self.ast.call(id);
        const scrutinee_ty = try self.typeAt(m.callee);
        const lending = self.ast.exprTag(id) == .match_read;
        const matched = if (lending)
            try self.matchedPlaceOf(m.callee, scrutinee_ty, span)
        else
            self.matchedValueOf(scrutinee_ty, try self.expr(m.callee));
        if (scrutinee_ty == .never) return if (matched.value != .none) matched.value else matched.address;

        const exit = try self.b.addBlock();
        const yields = ty != .unit and ty != .poison and ty != .never;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        var i: usize = 0;
        while (i + 1 < m.args.len) : (i += 2) {
            const pattern = m.args[i];
            const next = try self.b.addBlock();

            if (try self.testPattern(pattern, matched, next, span)) {
                try self.bindPattern(pattern, matched, lending, span);
                defer if (lending) self.endPatternLends(pattern);
                if (slot) |s|
                    try self.storeExprIn(s, ty, span, m.args[i + 1])
                else
                    _ = try self.expr(m.args[i + 1]);
                if (!self.b.hasTerminator(self.block)) {
                    _ = try self.b.setTerminator(self.block, .{
                        .tag = .jump,
                        .ty = .unit,
                        .span = span,
                        .data = .{ .target = exit },
                    });
                }
            }

            self.block = next;
        }

        // Checking proved exhaustive coverage; the failed final test cannot
        // enter the result join without initializing its slot.
        _ = try self.b.setTerminator(self.block, .{
            .tag = .trap,
            .ty = .unit,
            .span = span,
            .data = .{ .trap = .{ .kind = .unreachable_reached } },
        });

        self.block = exit;
        if (slot) |s| return self.loadLocal(s, ty, span);
        if (ty == .never) {
            try self.finishNever(span);
            return self.afterNoreturn(span);
        }
        return self.unitOrPoison(ty, span);
    }

    /// Split control on whether a carrier holds its success.
    ///
    /// One question -- did this `Result` or `Option` succeed -- and one place
    /// that answers it, for the three that ask: a return unwrapping the entry
    /// point's answer, a `?`, and each piece of an interpolation.
    ///
    /// Which variant counts as success is the caller's, because each of the
    /// three needs it afterwards as well -- to read what a success carries, or
    /// to build one. Asking here too would be the same lookup made twice.
    ///
    /// The block the lowerer sits in is terminated and neither arm is entered.
    /// The caller fills both, because a block nothing terminates is a broken
    /// function rather than a rejected program.
    fn branchOnSuccess(
        self: *Lowerer,
        carrier: TypeId,
        value: InstId,
        ok: u32,
        span: Span,
    ) std.mem.Allocator.Error!struct { continues: BlockId, leaves: BlockId } {
        // The tag is read through the value's address, because every carrier
        // reaching here lives in memory. Each of `Option` and `Result` has a
        // variant carrying a field whatever its arguments settle to -- `()`
        // included, which is a field of width zero rather than no field -- and
        // a variant with a field is what puts a value in memory. Nothing else
        // is a carrier: [T-Try] admits those two types and no others, [S-Entry]
        // admits `UInt8` or `Result[UInt8, E]`, and what an interpolation
        // renders through answers the prelude's `Display`. Stated rather than
        // branched on, because a branch for the case that cannot happen is a
        // second lowering nothing exercises.
        std.debug.assert(self.isAggregate(carrier));
        const tag = try self.emit(.load_indirect, tag_type, span, .{ .unary = value });
        const want = try self.emit(.constant, tag_type, span, .{ .constant = ok });
        const eq = try self.emit(.cmp_eq, .bool_, span, .{ .binary = .{ .lhs = tag, .rhs = want } });

        const continues = try self.b.addBlock();
        const leaves = try self.b.addBlock();
        _ = try self.b.setTerminator(self.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = eq, .then_block = continues, .else_block = leaves } },
        });
        return .{ .continues = continues, .leaves = leaves };
    }

    /// Leave the function, unwrapping the entry point's answer where it has one.
    ///
    /// One place, because there are three ways out -- a body's tail, a `?`, and
    /// a written `return` -- and each of them was building the terminator
    /// itself. What a return *does* is one question, and three answers to it is
    /// three chances for the entry point to keep only two of them.
    ///
    /// For every other function this is the terminator and nothing else.
    fn returnFrom(self: *Lowerer, value: InstId, span: Span) std.mem.Allocator.Error!void {
        if (self.b.return_type == .never) return self.finishNever(span);

        const carrier = self.unwraps;
        if (carrier == TypeId.poison) {
            _ = try self.b.setTerminator(self.block, .{
                .tag = .ret,
                .ty = .unit,
                .span = span,
                .data = .{ .unary = value },
            });
            return;
        }

        const view = self.types();
        const ok = view.successVariantOf(carrier) orelse return;
        const bad = view.failureVariantOf(carrier) orelse return;

        const arms = try self.branchOnSuccess(carrier, value, ok, span);

        // The exit status the program said, handed straight back.
        self.block = arms.continues;
        const status = try self.carriedAt(carrier, value, ok, 0, .u8, span);
        _ = try self.b.setTerminator(self.block, .{
            .tag = .ret,
            .ty = .unit,
            .span = span,
            .data = .{ .unary = status },
        });

        // The failure the program did not deal with, handed to the library.
        // Rendering it is what `Display` is for, and a compiler spelling a
        // message would be a second place that decides what a program says.
        self.block = arms.leaves;
        const held = self.types().variantFieldType(carrier, bad, 0);
        const carried = try self.carriedAt(carrier, value, bad, 0, held, span);
        const answered = try self.callLibrary(self.library.report, &.{held}, &.{carried}, .u8, span);
        _ = try self.b.setTerminator(self.block, .{
            .tag = .ret,
            .ty = .unit,
            .span = span,
            .data = .{ .unary = answered },
        });
    }

    fn finishNever(self: *Lowerer, span: Span) std.mem.Allocator.Error!void {
        if (self.b.hasTerminator(self.block)) return;
        _ = try self.b.setTerminator(self.block, .{
            .tag = .trap,
            .ty = .unit,
            .span = span,
            .data = .{ .trap = .{ .kind = .unreachable_reached } },
        });
    }

    fn panicExpr(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        const message_expr = self.ast.unaryOperand(id);
        const message = try self.expr(message_expr);
        if (try self.typeAt(message_expr) == .never) return message;

        _ = try self.b.setTerminator(self.block, .{
            .tag = .trap,
            .ty = .unit,
            .span = span,
            .data = .{ .trap = .{ .kind = .panic, .message = message } },
        });
        return self.afterNoreturn(span);
    }

    /// A call to a library declaration generated code needs. Discovery has
    /// already included its instance; the declaration arrives resolved rather
    /// than by name, so no generated call site pays a walk of the library.
    fn callLibrary(
        self: *Lowerer,
        d: DeclId,
        settled: []const TypeId,
        args: []const InstId,
        ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        if (d == DeclId.none) return self.poison(span);
        const callee = self.mono.idFor(d, settled, .poison, &.{});
        return self.b.addCall(self.block, self.mono.callResultRole(ty), ty, span, callee, args);
    }

    /// `e?`: test the tag, yield what a success carries or return a failure.
    ///
    /// The failing path **builds** the function's own failing variant. It does
    /// not pass the operand through: the operand's type and the function's are
    /// two instantiations, and each one's layout is the backend's to choose --
    /// so an offset in one says nothing about the offset in the other.
    ///
    /// Takes no expected type. Every width and every offset here is read from
    /// the enum the value is in, so the type recorded for the expression is
    /// not a second source that could disagree with it.
    fn tryExpr(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        const operand = self.ast.unaryOperand(id);
        const carrier = try self.typeAt(operand);
        const value = try self.expr(operand);
        if (carrier == .never) return value;

        const view = self.types();
        const ok = view.successVariantOf(carrier) orelse return self.poison(span);
        const bad = view.failureVariantOf(carrier) orelse return self.poison(span);

        const arms = try self.branchOnSuccess(carrier, value, ok, span);

        // The answer's own failing variant, built here. An `Option`'s carries
        // nothing; a `Result`'s carries the error moved out of the operand,
        // converted where the checker recorded a conversion and otherwise of
        // the same error type, because [T-TryAnswer] says so.
        // Resolved before the block is switched. Returning from here after
        // `self.block = arms.leaves` would leave that block without a
        // terminator, which is a broken function rather than a rejected
        // program.
        const answers = self.answers;
        const answers_bad = view.failureVariantOf(answers) orelse return self.poison(span);

        // Both counts, because the payload is read out of one enum and written
        // into the other. [T-TryAnswer] makes them agree; asking only the one
        // not being indexed is how a loosened rule turns into an out-of-bounds
        // read rather than into a diagnostic.
        const carries = self.types().variantFieldCount(carrier, bad) > 0 and
            self.types().variantFieldCount(answers, answers_bad) > 0;

        self.block = arms.leaves;
        // A failure carrying `Never` holds no value, so the failing edge is
        // never taken: `Result[T, Never]` is how a writer that cannot fail
        // says so, and there is no payload to read or return.
        if (carries and self.types().variantFieldType(carrier, bad, 0) == .never) {
            try self.finishNever(span);
            self.block = arms.continues;
            return self.carriedAt(carrier, value, ok, 0, self.types().variantFieldType(carrier, ok, 0), span);
        }
        // A different error type is converted through the `From`
        // implementation the checker found, before the scheduled operations
        // run, as the operand of a `return` is evaluated before them.
        var converted: [1]InstId = undefined;
        const conversion = self.typing.try_conversions.get(id);
        if (conversion) |found| if (carries) {
            const failure = try self.carriedAt(carrier, value, bad, 0, self.types().variantFieldType(carrier, bad, 0), span);
            converted[0] = try self.convertedError(found, failure, span);
        };
        // The least visible exit in the language: nothing is written where
        // control leaves. Everything scheduled anywhere in the function runs
        // here, which is the reason `defer` is worth having beside `?`.
        try self.runScheduledAt(id);
        const carried: []const InstId = if (!carries)
            &.{}
        else if (conversion != null)
            &converted
        else
            &.{try self.carriedAt(carrier, value, bad, 0, self.types().variantFieldType(carrier, bad, 0), span)};

        try self.returnFrom(try self.buildVariant(answers, answers_bad, .{ .values = carried }, span, null), span);

        // The width comes from the same variant the offset does. Read from
        // `ty` instead, an expression whose recorded type disagreed with the
        // enum it was read out of produced an access of the wrong width with
        // nothing to notice -- a load of one byte blitted as twenty-four.
        self.block = arms.continues;
        return self.carriedAt(carrier, value, ok, 0, self.types().variantFieldType(carrier, ok, 0), span);
    }

    /// `From.from(failure)` for a converting `?`, through the implementation
    /// discovery selected for this instance's error types.
    fn convertedError(self: *Lowerer, conversion: types_mod.TryConversion, failure: InstId, span: Span) std.mem.Allocator.Error!InstId {
        const target = try self.substituted(conversion.target);
        const found = try self.implementedMember(conversion.trait, conversion.member, &.{try self.substituted(conversion.source)}, target) orelse
            return self.poison(span);
        return self.callImplemented(found, target, span, &.{failure});
    }

    /// Lowers `e else |error| { … }`. It tests the tag, yields what a success
    /// carries, or binds what a failure carries and runs the block.
    ///
    /// The block either leaves, ending its own path, or yields the success
    /// type -- so both paths store into one slot and the join loads it, as a
    /// conditional's arms do. Widths and offsets are read from the enum the
    /// value is in, as `?` reads them.
    fn unwrapElse(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const u = self.ast.unwrapElse(id);
        const carrier = try self.typeAt(u.operand);
        const value = try self.expr(u.operand);
        if (carrier == .never) return value;

        const view = self.types();
        const ok = view.successVariantOf(carrier) orelse return self.poison(span);
        const bad = view.failureVariantOf(carrier) orelse return self.poison(span);

        const arms = try self.branchOnSuccess(carrier, value, ok, span);
        const exit = try self.b.addBlock();
        const yields = ty != .unit and ty != .poison and ty != .never;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        self.block = arms.leaves;
        const target = if (u.binder == ExprId.none) BindingId.none else self.res.targetOf(u.binder);
        if (target != BindingId.none) {
            const held = view.variantFieldType(carrier, bad, 0);
            // An error of type Never cannot exist, so neither can this path.
            if (held == .never) {
                try self.finishNever(span);
            } else {
                const local = try self.b.addLocal(held, .value);
                try self.storeLocal(local, held, span, try self.carriedAt(carrier, value, bad, 0, held, span));
                self.local_of_binding[target.index()] = local;
                try self.touched.append(self.gpa, @intCast(target.index()));
            }
        }
        if (!self.b.hasTerminator(self.block)) {
            if (slot) |s| try self.storeExprIn(s, ty, span, u.body) else _ = try self.expr(u.body);
            try self.jumpTo(exit, span);
        }

        self.block = arms.continues;
        const success = view.variantFieldType(carrier, ok, 0);
        if (success == .never) {
            try self.finishNever(span);
        } else {
            const carried = try self.carriedAt(carrier, value, ok, 0, success, span);
            if (slot) |s| try self.storeLocal(s, ty, span, carried);
            try self.jumpTo(exit, span);
        }

        self.block = exit;
        if (slot) |s| return self.loadLocal(s, ty, span);
        if (ty == .never) {
            try self.finishNever(span);
            return self.afterNoreturn(span);
        }
        return self.unitOrPoison(ty, span);
    }

    /// Ends the current block with a jump, unless something already ended it.
    fn jumpTo(self: *Lowerer, target: BlockId, span: Span) std.mem.Allocator.Error!void {
        if (self.b.hasTerminator(self.block)) return;
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = target },
        });
    }

    fn variantOrdinal(self: *const Lowerer, id: ExprId) ?u32 {
        return types_mod.variantOrdinalOf(&self.res.variant_ordinals, &self.typing.variant_uses, id);
    }

    fn variantIndex(self: *const Lowerer, id: ExprId) u32 {
        return self.variantOrdinal(id) orelse
            @panic("compiler defect: variant was not settled before emission");
    }

    /// Emits the ordered schedule ownership recorded for this exit.
    fn runScheduledAt(self: *Lowerer, exit: ExprId) std.mem.Allocator.Error!void {
        if (self.placing or self.unreached.contains(self.block)) return;
        self.placing = true;
        defer self.placing = false;
        for (self.disposals.schedulesAt(exit)) |scheduled| {
            _ = try self.expr(scheduled);
        }
    }

    fn testSuccess(self: *Lowerer, id: ExprId, value: InstId, span: Span) std.mem.Allocator.Error!InstId {
        const result = self.typing.implicit_test_successes.get(id) orelse return value;
        const ty = try self.substituted(result);
        const ok = self.types().successVariantOf(ty).?;
        return self.buildVariant(ty, ok, .{ .values = &.{value} }, span, null);
    }

    /// `return` ends the block it sits in.
    ///
    /// No exit block is needed: `ret` is a terminator, so any block may end in
    /// one, and a function with several returns simply has several.
    fn returnExpr(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        const value = self.ast.unaryOperand(id);
        const result = if (value == ExprId.none)
            try self.nothing(.unit, span)
        else
            try self.expr(value);

        // After the operand, which the caller takes, and before the return
        // itself: everything the function scheduled runs on the way out.
        try self.runScheduledAt(id);

        try self.returnFrom(try self.testSuccess(id, result, span), span);

        // Whatever follows in the source is unreachable, and lowering is
        // total, so it goes into a block nothing jumps to.
        self.block = try self.b.addBlock();
        try self.unreached.put(self.gpa, self.block, {});
        return self.nothing(.unit, span);
    }

    /// `break` and `continue` are jumps to blocks the enclosing loop named.
    fn jump(self: *Lowerer, id: ExprId, span: Span, kind: enum { break_, continue_ }) std.mem.Allocator.Error!InstId {
        std.debug.assert(self.loops.items.len != 0);
        const frame = self.loops.items[self.loops.items.len - 1];

        if (kind == .break_) {
            const value = self.ast.unaryOperand(id);
            if (frame.slot) |s| {
                if (value != ExprId.none and frame.wraps != TypeId.poison) {
                    const ok = self.types().successVariantOf(frame.wraps) orelse return self.poison(span);
                    const built = try self.buildVariant(frame.wraps, ok, .{ .written = &.{value} }, span, null);
                    try self.storeLocal(s, frame.wraps, span, built);
                } else if (value != ExprId.none) {
                    try self.storeExprIn(s, try self.typeAt(value), span, value);
                }
            } else if (value != ExprId.none) {
                _ = try self.expr(value);
            }
        }

        // What the scopes between here and the loop scheduled runs on the way
        // out, after a `break`'s own value -- which the loop takes -- and
        // before the jump. The same order the ownership graph walks them in.
        try self.runScheduledAt(id);

        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = if (kind == .break_) frame.exit else frame.continue_to },
        });

        // Whatever follows in the source is unreachable, and lowering is total:
        // it goes into a block nothing jumps to rather than being dropped.
        self.block = try self.b.addBlock();
        try self.unreached.put(self.gpa, self.block, {});
        return self.nothing(.unit, span);
    }

    /// An implementation and the member of it supplying one signature.
    ///
    /// What `calleeOf` answers for a call the program wrote, for the calls a
    /// desugar makes instead. A `for` names no callee, so there is no call
    /// expression whose settled `Self` the checker recorded -- but the lookup
    /// is the same one, keyed by the trait, its arguments and the receiver,
    /// and a missing row is reported through the sentence `calleeOf` reports.
    const Implemented = struct {
        /// The row itself, so what the member returns is read off it rather
        /// than worked out again from the trait's declaration.
        row: types_mod.Implementation,
        member: DeclId,
        /// The receiver an instantiation of the member is keyed by.
        held: TypeId,
        impl_args: []const TypeId,
    };

    /// The body a trait's member runs for one receiver, found without a call.
    ///
    /// **Bound:** one chain walk over the implementations of one trait for one
    /// type, and one lookup.
    fn implementedMember(
        self: *Lowerer,
        trait: ?DeclId,
        member: ?DeclId,
        args: []const TypeId,
        held: TypeId,
    ) std.mem.Allocator.Error!?Implemented {
        const declared = trait orelse return null;
        const sig = member orelse return null;

        const row = self.mono.instances.selectedImplementation(declared, args, held) orelse return null;
        if (row.isAmbient()) return null;

        const impl = row.decl;
        const supplied = self.typing.supply_index.memberOf(impl, sig) orelse return null;
        return .{
            .row = row,
            .member = supplied,
            .held = instantiate_mod.receiverKeying(self.ast, impl, self.mono.instances.selectedChoice(declared, args, held).implementedFor()),
            .impl_args = self.mono.instances.selectedArguments(declared, args, held),
        };
    }

    /// Calls what `implementedMember` found. The members reached this way --
    /// a `for`'s `iterate` and `next`, and the `from` a converting `?`
    /// calls -- declare no type parameters of their own.
    fn callImplemented(
        self: *Lowerer,
        found: Implemented,
        answers: TypeId,
        span: Span,
        args: []const InstId,
    ) std.mem.Allocator.Error!InstId {
        const callee = self.mono.idFor(found.member, &.{}, found.held, found.impl_args);
        return self.directCall(answers, span, callee, args);
    }

    /// `for x in xs { … }`, which elaborates two ways under one syntax.
    ///
    /// Whose places these are is answered here and nowhere below: an array
    /// carries its own, and everything else names a `Sequence` that says how
    /// to walk it. One switch on the head rather than a question each branch
    /// asks again -- a second reading of it is a second answer, and the two
    /// would disagree on the type that is both.
    fn forLoop(self: *Lowerer, id: ExprId, ty: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const callee = self.ast.call(id).callee;
        const walked = try self.typeAt(callee);
        if (walked == .never) return self.expr(callee);
        // A lending walk takes nothing, so neither branch below is what it
        // needs: it names each place where it lives rather than building a
        // value or moving one out. Asked before the head is, because what the
        // head *is* decides only how the positions are found.
        if (self.ast.exprTag(id) != .for_) return self.lendingWalk(id, ty, span, walked);
        return switch (self.types().get(walked)) {
            .array => |a| self.arrayWalk(id, ty, span, a.count),
            else => self.sequenceWalk(id, ty, span, walked),
        };
    }

    /// `for read x in xs { … }` and `for inout x in xs { … }`: a position at a
    /// time, and the place it names bound to the binder.
    ///
    /// The two halves the checker held the type to, emitted. Where the
    /// positions come from is the one thing an array differs in: its length is
    /// part of its type, so a counter bounded by that length is the traversal,
    /// and every position is an offset the compiler already addresses. Anything
    /// else runs the iterator its `trav` names and splices its `proj at` at each
    /// position, which is the same splice a bracket over it makes.
    ///
    /// The binder is the address rather than a copy of what is there, for both
    /// conventions. `read` reads through it and `inout` writes through it, and
    /// which of the two a site does is decided where the site is -- the same
    /// rule a lend into a call answers to, and the reason there is nothing here
    /// that switches on the word.
    fn lendingWalk(
        self: *Lowerer,
        id: ExprId,
        ty: TypeId,
        span: Span,
        walked: TypeId,
    ) std.mem.Allocator.Error!InstId {
        const f = self.ast.call(id);

        // An aggregate is its address, and a place inside one is reached
        // through the place walk rather than by evaluating it as a value.
        //
        // Evaluated here and read by both branches, never by the path: a walk
        // that lowered the head again per position would lend places of a
        // different value each time, so a write through one would be lost with
        // the value it was made in and a head with effects would run once per
        // position. It is what fills the projection's receiver slot below, for
        // that reason.
        const base = if (self.ast.isSelection(f.callee))
            try self.placeAddress(self.ast.withoutGroups(f.callee), span)
        else
            try self.expr(f.callee);
        if (base == InstId.none) return self.poison(span);

        // Where the positions come from, settled here and read below.
        const counted: ?u32 = switch (self.types().get(walked)) {
            .array => |a| a.count,
            else => null,
        };

        // The traversal the checker found and the projection it recorded
        // against this loop, read rather than searched for again: a second
        // search would be free to reach another implementation than the one
        // whose element the binder was checked against.
        const declared: ?Traversed = if (counted != null) null else try self.traversed(id);
        if (counted == null and declared == null) return self.poison(span);

        const yields = ty != .unit and ty != .poison;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        // The counter an array's positions run through, and the iterator a
        // declared traversal's do. One of the two, decided above.
        const counter = if (counted != null) try self.b.addLocal(.u64, .value) else null;
        if (counter) |c| {
            try self.storeLocal(c, .u64, span, try self.emit(.constant, .u64, span, .{ .constant = 0 }));
        }
        const positions = if (declared) |d| try self.b.addLocal(d.positions, .value) else null;
        if (positions) |p| {
            if (declared) |d| try self.storeLocal(p, d.positions, span, try self.traversalValue(d, walked, base, span));
        }

        const header = try self.b.addBlock();
        const step = try self.b.addBlock();
        const ran_out = try self.b.addBlock();
        const exit = try self.b.addBlock();

        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = header },
        });

        self.block = header;
        // What this position is, and whether there is one. An array answers
        // both from its counter; a traversal answers both from one `next`.
        var at: InstId = InstId.none;
        var body: mir_mod.BlockId = undefined;
        if (counter) |c| {
            at = try self.loadLocal(c, .u64, span);
            const length = try self.emit(.constant, .u64, span, .{ .constant = counted.? });
            const more = try self.emit(.cmp_lt, .bool_, span, .{ .binary = .{ .lhs = at, .rhs = length } });
            body = try self.b.addBlock();
            _ = try self.b.setTerminator(self.block, .{
                .tag = .branch,
                .ty = .unit,
                .span = span,
                .data = .{ .branch = .{ .cond = more, .then_block = body, .else_block = ran_out } },
            });
        } else {
            const d = declared.?;
            const holds = try self.emit(.addr_of, d.positions, span, .{ .local = positions.? });
            const asked = try self.callImplemented(d.steps, d.answer, span, &.{holds});
            const ok = self.types().successVariantOf(d.answer) orelse return self.poison(span);
            const arms = try self.branchOnSuccess(d.answer, asked, ok, span);
            body = arms.continues;
            self.block = arms.leaves;
            _ = try self.b.setTerminator(self.block, .{
                .tag = .jump,
                .ty = .unit,
                .span = span,
                .data = .{ .target = ran_out },
            });
            self.block = body;
            at = try self.carriedAt(d.answer, asked, ok, 0, d.item, span);
        }

        // The walk has run out. Nothing was found, which is what the loop
        // answers with where it answers with anything.
        self.block = ran_out;
        if (slot) |s| {
            const none = self.types().failureVariantOf(ty) orelse return self.poison(span);
            const empty = try self.buildVariant(ty, none, .{ .values = &.{} }, span, null);
            try self.storeLocal(s, ty, span, empty);
        }
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = exit },
        });

        // The place this position names, bound to the binder for the extent of
        // the body. Its type is the one the checker settled and recorded, read
        // here as a payload binder's already is.
        self.block = body;
        const item = try self.typeAt(f.args[0]);
        const place = if (counted) |_| at: {
            const stride = try self.emit(.constant, .u64, span, .{ .constant = self.types().strideOf(item) });
            const offset = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = at, .rhs = stride } });
            break :at try self.emit(.field_addr, item, span, .{ .binary = .{ .lhs = base, .rhs = offset } });
        } else try self.splicedPath(
            declared.?.expansion,
            .{ .held = .{ .value = base, .ty = walked } },
            .{ .held = .{ .value = at, .ty = declared.?.item } },
            span,
        );
        if (place == InstId.none) return self.poison(span);

        try self.lendWalked(f.args[0], item, place, span);
        defer self.unlendWalked(f.args[0]);

        try self.loops.append(self.gpa, .{
            .continue_to = step,
            .exit = exit,
            .slot = slot,
            .wraps = if (yields) ty else TypeId.poison,
        });
        _ = try self.expr(f.args[1]);
        _ = self.loops.pop();

        // A body that ran to its end asks for the next position. A `break`
        // already left, and setting a terminator on a block that has one is
        // refused, so this is reached only where control fell through.
        if (!self.b.hasTerminator(self.block)) {
            _ = try self.b.setTerminator(self.block, .{
                .tag = .jump,
                .ty = .unit,
                .span = span,
                .data = .{ .target = step },
            });
        }

        // One place advances to the next position, and it is where `continue`
        // lands as well. A traversal advances by being asked again, which the
        // header does; an array's counter is advanced here.
        self.block = step;
        if (counter) |c| {
            const reached = try self.loadLocal(c, .u64, span);
            const one = try self.emit(.constant, .u64, span, .{ .constant = 1 });
            const next = try self.emit(.add, .u64, span, .{ .binary = .{ .lhs = reached, .rhs = one } });
            try self.storeLocal(c, .u64, span, next);
        }
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = header },
        });

        self.block = exit;
        if (slot) |s| return self.loadLocal(s, ty, span);
        return self.unitOrPoison(ty, span);
    }

    /// Binds a lending walk's binder to the place the position names. A tuple
    /// pattern's binders each name their component of that place.
    fn lendWalked(self: *Lowerer, binder: ExprId, item: TypeId, place: InstId, span: Span) std.mem.Allocator.Error!void {
        if (self.ast.exprTag(binder) == .tuple_pattern)
            return self.bindPattern(binder, self.matchedValueOf(item, place), true, span);
        const target = self.res.targetOf(binder);
        if (target != BindingId.none) try self.lent.put(self.gpa, target, place);
    }

    /// Ends what `lendWalked` bound, at the end of the body.
    fn unlendWalked(self: *Lowerer, binder: ExprId) void {
        if (self.ast.exprTag(binder) == .tuple_pattern) return self.endPatternLends(binder);
        const target = self.res.targetOf(binder);
        if (target != BindingId.none) _ = self.lent.remove(target);
    }

    /// Binds an owning walk's binder to the element taken this iteration,
    /// which is `carried`. A tuple pattern's binders each take their component
    /// of it.
    fn takeWalked(self: *Lowerer, binder: ExprId, item: TypeId, carried: InstId, span: Span) std.mem.Allocator.Error!void {
        if (self.ast.exprTag(binder) == .tuple_pattern)
            return self.bindPattern(binder, self.matchedValueOf(item, carried), false, span);
        const local = try self.b.addLocal(item, .value);
        const target = self.res.targetOf(binder);
        if (target != BindingId.none) self.local_of_binding[target.index()] = local;
        try self.storeLocal(local, item, span, carried);
    }

    /// What a walk over a declared traversal needs: the positions, the `next`
    /// that hands them over one at a time, and the path each names a place
    /// through.
    const Traversed = struct {
        source: types_mod.TraversalPositions,
        /// The traversal's own declaration, for the expression it is bound to.
        decl: DeclId,
        /// The type that expression has, which is the iterator being run.
        positions: TypeId,
        /// The `next` supplying `Iterator` for it, and what it answers with.
        steps: Implemented,
        answer: TypeId,
        /// What one answer carries, which is a position.
        item: TypeId,
        /// The projection's path, as the checker recorded it against this loop.
        expansion: types_mod.Expansion,
        impl_args: []const TypeId,
    };

    /// The traversal and the projection the checker settled for this walk.
    ///
    /// Both are read off the checker's tables rather than looked for here. A
    /// walk indexed by positions this pass found for itself could be indexed by
    /// a traversal the checker never held to the projection.
    fn traversed(self: *Lowerer, id: ExprId) std.mem.Allocator.Error!?Traversed {
        const plan = self.calls.traversalPlan(self.typing, id) orelse return null;
        const decl = plan.decl;
        const expansion = self.calls.projectionOf(self.typing, id) orelse return null;
        const recorded = plan.impl_args;
        const bound = try self.gpa.alloc(TypeId, recorded.len);
        defer self.gpa.free(bound);
        for (recorded, bound) |written, *settled| settled.* = try self.substituted(written);
        const written_positions = switch (plan.positions) {
            .expression => |expression| self.typing.exprType(expression),
            .array => |array| array.iterator,
        };
        const positions = if (self.typing.implementationOf(decl)) |implementation|
            try self.mono.pool.substitute(written_positions, implementation.decl.index(), bound)
        else
            try self.substituted(written_positions);
        if (positions == .poison) return null;

        const steps = try self.implementedMember(self.library.iterator, self.library.next, &.{}, positions) orelse
            return null;
        const answer = try self.mono.pool.settledBy(steps.row, (self.library.next orelse
            return null), steps.impl_args) orelse return null;
        const ok = self.types().successVariantOf(answer) orelse return null;
        if (self.types().variantFieldCount(answer, @intCast(ok)) == 0) return null;
        const item = self.types().variantFieldType(answer, @intCast(ok), 0);

        return .{
            .decl = decl,
            .source = plan.positions,
            .positions = positions,
            .steps = steps,
            .answer = answer,
            .item = item,
            .expansion = expansion,
            .impl_args = recorded,
        };
    }

    /// The iterator a traversal's expression builds, lowered where the walk is.
    ///
    /// The expression belongs to the implementation that declares it, so it is
    /// lowered under that implementation's instantiation rather than under the
    /// body's -- the same swap a projection's path is read under, and for the
    /// same reason.
    fn traversalValue(self: *Lowerer, d: Traversed, walked: TypeId, base: InstId, site: Span) std.mem.Allocator.Error!InstId {
        // The receiver is what the walk names, because that is what the
        // implementation was matched against: a traversal declared by
        // `impl[T] Pair[T]` and reached at `Pair[UInt8]` binds `T` to
        // `UInt8`. Handing the positions type here instead binds the
        // implementation's parameters to whatever the iterator applies --
        // one argument for a `Range`, none for an iterator of its own -- so
        // an implementation of any other arity reaches an assertion that
        // the receiver and the head agree, and one that happens to match
        // lowers the expression under a substitution nobody chose.
        const bound = try self.gpa.alloc(TypeId, d.impl_args.len);
        defer self.gpa.free(bound);
        for (d.impl_args, bound) |written, *settled| settled.* = try self.substituted(written);
        const member_instance = try bodyParametersOf(self.ast, self.res, self.typing, d.decl).splicedAt(self.gpa, d.decl, walked, bound);
        defer self.gpa.free(member_instance.args);

        const saved = self.instance;
        self.instance = member_instance;
        defer self.instance = saved;
        const mark = self.splices.items.len;
        defer self.splices.shrinkRetainingCapacity(mark);
        for (self.res.parametersOf(d.decl)) |receiver| {
            std.debug.assert(self.res.paramIndexOf(receiver) == 0);
            try self.splices.append(self.gpa, .{ .binding = receiver, .wrote = .none, .value = base, .instance = self.instance, .site = mark });
        }
        return switch (d.source) {
            .expression => |expression| self.splicedExpr(expression, site),
            .array => |array| self.constantTraversalRange(d.positions, array.count, site),
        };
    }

    /// Lowers an expression another declaration wrote in place of the site
    /// that reaches it. It may sit in another file, and a function's
    /// instructions all carry locations in the function's own file, so every
    /// instruction it becomes is located at the site.
    fn splicedExpr(self: *Lowerer, expression: ExprId, site: Span) std.mem.Allocator.Error!InstId {
        const outer = self.b.located_at;
        if (outer == null) self.b.located_at = site;
        defer self.b.located_at = outer;
        return self.expr(expression);
    }

    fn constantTraversalRange(self: *Lowerer, ty: TypeId, count: u32, span: Span) std.mem.Allocator.Error!InstId {
        const base = try self.baseFor(ty, span, null);
        for ([_][]const u8{ "lo", "hi", "inclusive" }, [_]u32{ 0, count, 0 }) |name, value| {
            const field = self.types().lookupField(ty, name).?;
            const at = try self.fieldAddr(base, field.ty, field.offset, span);
            const constant = try self.emit(.constant, field.ty, span, .{ .constant = value });
            try self.writeThrough(at, field.ty, constant, span);
        }
        return base;
    }

    /// The walk an array's own places make: a counter from zero to the length,
    /// and the element at that position moved out.
    ///
    /// The length is part of the type, so the counter is bounded by the same
    /// number the offsets are computed from and no index is checked -- there is
    /// no index a program wrote for one to be about.
    ///
    /// The positions are counted rather than written out. An array's length is
    /// whatever a program spelled, so a step per position would make what
    /// lowering emits the product of that length and the body: a buffer of a
    /// few thousand elements is a few thousand copies of a loop one counter
    /// expresses, and the traversal is the same traversal either way.
    ///
    /// Moving out rather than reading is what the loop taking the array buys:
    /// nothing else names the array afterwards, so each element leaves its
    /// place once and the binder holds a value of its own -- which is what lets
    /// a body consume a Linear element.
    fn arrayWalk(
        self: *Lowerer,
        id: ExprId,
        ty: TypeId,
        span: Span,
        count: u32,
    ) std.mem.Allocator.Error!InstId {
        const f = self.ast.call(id);

        // An aggregate is its address, and a place inside one is reached
        // through the place walk rather than by evaluating it as a value.
        const base = if (self.ast.isSelection(f.callee))
            try self.placeAddress(self.ast.withoutGroups(f.callee), span)
        else
            try self.expr(f.callee);
        if (base == InstId.none) return self.poison(span);

        const yields = ty != .unit and ty != .poison;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        const counter = try self.b.addLocal(.u64, .value);
        try self.storeLocal(counter, .u64, span, try self.emit(.constant, .u64, span, .{ .constant = 0 }));

        const header = try self.b.addBlock();
        const body = try self.b.addBlock();
        const step = try self.b.addBlock();
        const ran_out = try self.b.addBlock();
        const exit = try self.b.addBlock();

        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = header },
        });

        self.block = header;
        const position = try self.loadLocal(counter, .u64, span);
        const length = try self.emit(.constant, .u64, span, .{ .constant = count });
        const more = try self.emit(.cmp_lt, .bool_, span, .{ .binary = .{ .lhs = position, .rhs = length } });
        _ = try self.b.setTerminator(self.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = more, .then_block = body, .else_block = ran_out } },
        });

        // The walk has run out. Nothing was found, which is what the loop
        // answers with where it answers with anything.
        self.block = ran_out;
        if (slot) |s| {
            const none = self.types().failureVariantOf(ty) orelse return self.poison(span);
            const empty = try self.buildVariant(ty, none, .{ .values = &.{} }, span, null);
            try self.storeLocal(s, ty, span, empty);
        }
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = exit },
        });

        // The element at this position, bound to the binder for this
        // iteration. Its type is the one the checker settled for the binder
        // from the array and recorded, read here as a payload binder's already
        // is -- and read for the distance between places as well as for the
        // width of the load, so the address the walk steps to and the bytes it
        // reads there cannot come apart.
        self.block = body;
        const item = try self.typeAt(f.args[0]);
        const stride = try self.emit(.constant, .u64, span, .{ .constant = self.types().strideOf(item) });
        const offset = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = position, .rhs = stride } });
        const place = try self.emit(.field_addr, item, span, .{ .binary = .{ .lhs = base, .rhs = offset } });
        try self.takeWalked(f.args[0], item, try self.readThrough(place, item, span), span);

        try self.loops.append(self.gpa, .{
            .continue_to = step,
            .exit = exit,
            .slot = slot,
            .wraps = if (yields) ty else TypeId.poison,
        });
        _ = try self.expr(f.args[1]);
        _ = self.loops.pop();

        // A body that ran to its end asks for the next position. A `break`
        // already left, and setting a terminator on a block that has one is
        // refused, so this is reached only where control fell through.
        if (!self.b.hasTerminator(self.block)) {
            _ = try self.b.setTerminator(self.block, .{
                .tag = .jump,
                .ty = .unit,
                .span = span,
                .data = .{ .target = step },
            });
        }

        // One place advances the counter, and it is where `continue` lands as
        // well -- an iteration ending early and an iteration running out are
        // the same next position, so there is one site that decides it.
        self.block = step;
        const reached = try self.loadLocal(counter, .u64, span);
        const one = try self.emit(.constant, .u64, span, .{ .constant = 1 });
        const next = try self.emit(.add, .u64, span, .{ .binary = .{ .lhs = reached, .rhs = one } });
        try self.storeLocal(counter, .u64, span, next);
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = header },
        });

        self.block = exit;
        if (slot) |s| return self.loadLocal(s, ty, span);
        return self.unitOrPoison(ty, span);
    }

    /// The walk a `Sequence` says how to make: the iterator `xs` vends, a
    /// header that asks it for the next element, a body bound to that element,
    /// and an exit.
    ///
    /// The sequence is evaluated once, before the header: what the walk holds
    /// is built from it, and rebuilding it per iteration would walk the first
    /// element forever. The iterator lives in a slot of its own because `next`
    /// takes it `inout` -- where the walk has got to is the iterator's own,
    /// and a value passed by address is a value with an address.
    ///
    /// Where the loop answers with a value, the slot holds `Option[E]`: the
    /// exhausted path stores `None` and each break site stores `Some`, which
    /// is the pair of exits a walk has. The type is the checker's, read off
    /// the expression rather than assembled here.
    fn sequenceWalk(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, walked: TypeId) std.mem.Allocator.Error!InstId {
        const f = self.ast.call(id);

        // `for x in &it` advances the iterator `it` names, where it lives:
        // its address is taken once, before the header, and `next` is called
        // through it. Otherwise the walk takes what it names, asks it for an
        // iterator and keeps that in a local of its own.
        const lent = self.ast.exprTag(f.callee) == .marked;
        var iter_ty = walked;
        var holds: ?mir_mod.LocalId = null;
        var lent_at: InstId = InstId.none;
        if (lent) {
            lent_at = try self.addressOf(f.callee, span);
            if (lent_at == InstId.none) return self.poison(span);
        } else {
            const begins = try self.implementedMember(self.library.sequence, self.library.iterate, &.{}, walked) orelse
                return self.poison(span);
            // What the implementation's own `iterate` answers with, substituted
            // for this receiver. Read off the row rather than settled a second
            // time: the type a member returns is one question.
            iter_ty = try self.mono.pool.settledBy(begins.row, (self.library.iterate orelse
                return self.poison(span)), begins.impl_args) orelse return self.poison(span);

            const from = try self.expr(f.callee);
            const walking = try self.callImplemented(begins, iter_ty, span, &.{from});

            holds = try self.b.addLocal(iter_ty, .value);
            try self.storeLocal(holds.?, iter_ty, span, walking);
        }

        const steps = try self.implementedMember(self.library.iterator, self.library.next, &.{}, iter_ty) orelse
            return self.poison(span);
        const answer = try self.mono.pool.settledBy(steps.row, (self.library.next orelse
            return self.poison(span)), steps.impl_args) orelse return self.poison(span);

        const yields = ty != .unit and ty != .poison;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        const header = try self.b.addBlock();
        const exit = try self.b.addBlock();
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = header },
        });

        self.block = header;
        const at = if (holds) |h| try self.emit(.addr_of, iter_ty, span, .{ .local = h }) else lent_at;
        const asked = try self.callImplemented(steps, answer, span, &.{at});

        const view = self.types();
        const ok = view.successVariantOf(answer) orelse return self.poison(span);
        const arms = try self.branchOnSuccess(answer, asked, ok, span);

        // The walk has run out. Nothing was found, which is what the loop
        // answers with where it answers with anything.
        self.block = arms.leaves;
        if (slot) |s| {
            const none = self.types().failureVariantOf(ty) orelse return self.poison(span);
            const empty = try self.buildVariant(ty, none, .{ .values = &.{} }, span, null);
            try self.storeLocal(s, ty, span, empty);
        }
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = exit },
        });

        // An element, bound to the binder for this iteration. Its type is the
        // one the checker settled for the binder and recorded, read here as a
        // payload binder's already is -- worked out again from what `next`
        // answers, the slot would be allocated at one width and every read of
        // the binding would use the other.
        self.block = arms.continues;
        const item = try self.typeAt(f.args[0]);
        try self.takeWalked(f.args[0], item, try self.carriedAt(answer, asked, ok, 0, item, span), span);

        try self.loops.append(self.gpa, .{
            .continue_to = header,
            .exit = exit,
            .slot = slot,
            .wraps = if (yields) ty else TypeId.poison,
        });
        _ = try self.expr(f.args[1]);
        _ = self.loops.pop();

        // A body that ran to its end asks for the next element. A `break`
        // already left, and setting a terminator on a block that has one is
        // refused, so this is reached only where control fell through.
        if (!self.b.hasTerminator(self.block)) {
            _ = try self.b.setTerminator(self.block, .{
                .tag = .jump,
                .ty = .unit,
                .span = span,
                .data = .{ .target = header },
            });
        }

        self.block = exit;
        if (slot) |s| return self.loadLocal(s, ty, span);
        return self.unitOrPoison(ty, span);
    }

    /// `while c { … }` becomes a header that tests, a body that jumps back to
    /// it, and an exit that carries on.
    ///
    /// The condition is lowered once, into the header, rather than copied
    /// ahead of the loop as well: a condition may trap, and a copy would give
    /// that trap two sites reporting one line. Moving the test to the bottom
    /// is a transformation over this shape and belongs to the pass that does
    /// those, not to lowering.
    ///
    /// The terminator is set on whatever block is current rather than on the
    /// one just made, because lowering the condition or the body may itself
    /// open blocks and leave control somewhere else.
    fn whileLoop(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        const w = self.ast.binary(id);

        const header = try self.b.addBlock();

        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = header },
        });

        self.block = header;
        const cond = try self.expr(w.lhs);
        if (try self.typeAt(w.lhs) == .never) return cond;

        const body = try self.b.addBlock();
        const exit = try self.b.addBlock();
        _ = try self.b.setTerminator(self.block, .{
            .tag = .branch,
            .ty = .unit,
            .span = span,
            .data = .{ .branch = .{ .cond = cond, .then_block = body, .else_block = exit } },
        });

        // A `while` is a loop a `break` can leave, so it pushes a frame like
        // any other. It never yields a value, so there is no slot to carry
        // one, and `continue` returns to the header to test again.
        try self.loops.append(self.gpa, .{ .continue_to = header, .exit = exit, .slot = null });
        self.block = body;
        _ = try self.expr(w.rhs);
        _ = self.loops.pop();

        if (!self.b.hasTerminator(self.block)) {
            _ = try self.b.setTerminator(self.block, .{
                .tag = .jump,
                .ty = .unit,
                .span = span,
                .data = .{ .target = header },
            });
        }

        self.block = exit;
        return self.nothing(.unit, span);
    }

    /// The arithmetic an operator names, with the checks it carries.
    ///
    /// One routine, so `a + b` and `a += b` cannot come to disagree about where
    /// an overflow traps or what a division by zero does. Which operator it is
    /// arrives as `op`, which for a compound assignment is the one its tag
    /// compounds; `at` is the expression whose operator token a trap points at.
    fn arithmetic(
        self: *Lowerer,
        op: syntax_node.Expr.Tag,
        /// Where a failed check is reported.
        checked_at: Span,
        ty: TypeId,
        span: Span,
        lhs: InstId,
        operand: InstId,
    ) std.mem.Allocator.Error!InstId {
        var rhs = operand;

        // The divisor is tested before the division rather than after, because
        // there is no result to inspect when it is zero. A remainder divides to
        // find what is left, so it fails on a zero divisor for the same reason
        // and is checked by the same code rather than by a copy of it.
        //
        // Not over floats: IEEE 754 defines a result for every input, a zero
        // divisor included, so a float operation carries no check at all and
        // there is no range for its result to escape.
        if ((op == .div or op == .rem) and !ty.isFloat()) {
            rhs = try self.check(rhs, ty, checked_at, .division_by_zero);
        }

        const tag: Inst.Tag = switch (op) {
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div => .div,
            .rem => .rem,
            else => unreachable,
        };
        const r = try self.emit(tag, ty, span, .{ .binary = .{ .lhs = lhs, .rhs = rhs } });
        if (ty.isFloat()) return r;
        return self.check(r, ty, checked_at, .overflow);
    }

    /// `p += e`, and the three like it.
    ///
    /// The place is evaluated to an address once, and the read, the arithmetic
    /// and the write all go through that one address. That is the whole of what
    /// the construct exists for: `xs[step(&i)] += 1` steps once, and the
    /// element it writes is the element it read.
    fn compoundAssign(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        const a = self.ast.binary(id);
        const op = self.ast.exprTag(id).compounds().?;
        const lhs = self.ast.withoutGroups(a.lhs);
        const ty = try self.typeAt(lhs);
        if (ty == TypeId.poison) return self.poison(span);

        // The operand first, as an assignment evaluates its value first.
        const operand = try self.expr(a.rhs);
        if (try self.typeAt(a.rhs) == .never) return operand;

        // A path is an address, and one address serves the read and the write.
        if (self.ast.isSelection(lhs)) {
            const at = try self.placeAddress(lhs, span);
            if (at == InstId.none) return self.poison(span);
            if (ty == .never) return at;
            const was = try self.readThrough(at, ty, span);
            try self.writeThrough(at, ty, try self.arithmetic(op, self.opSpan(id), ty, span, was, operand), span);
            return self.nothing(.unit, span);
        }

        const target = self.res.targetOf(lhs);
        if (target == BindingId.none) return self.poison(span);

        // A lend is an address, so the value is behind it and both the read
        // and the write go through it -- exactly as they do for a plain
        // assignment to the same binding.
        if (try self.addressBehind(target, ty, span)) |p| {
            const was = try self.readThrough(p, ty, span);
            try self.writeThrough(p, ty, try self.arithmetic(op, self.opSpan(id), ty, span, was, operand), span);
            return self.nothing(.unit, span);
        }

        const local = self.local_of_binding[target.index()];
        const was = try self.loadLocal(local, ty, span);
        try self.storeLocal(local, ty, span, try self.arithmetic(op, self.opSpan(id), ty, span, was, operand));
        return self.nothing(.unit, span);
    }

    /// `x = e` writes to the slot the binding already has. Nothing new is
    /// allocated: assignment names an existing binding rather than introducing
    /// one, which is also why it needs no scope of its own.
    fn assign(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        const a = self.ast.binary(id);
        // The target names the same place however it is parenthesised. Without
        // this `(n) = 7` matched neither shape below and emitted no store at
        // all -- a program that ran and answered the wrong number.
        const lhs = self.ast.withoutGroups(a.lhs);

        // A path is an address and a store through it. Reading `o.inner.y` and
        // writing it compute the same address, so the chain is walked by the
        // code that reads one and only the last step differs. An index is such
        // a step: `xs[0] = 9` writes where `xs[0]` reads.
        if (self.ast.isSelection(lhs)) {
            const ty = try self.typeAt(lhs);
            const value = try self.expr(a.rhs);
            if (try self.typeAt(a.rhs) == .never) return value;
            const at = try self.placeAddress(lhs, span);
            if (at == InstId.none) return self.poison(span);
            if (ty == .never) return at;

            try self.writeThrough(at, ty, value, span);
            return self.nothing(.unit, span);
        }

        const target = self.res.targetOf(lhs);
        if (target == BindingId.none) return self.poison(span);

        // How much is written comes from the place written, as it does on the
        // path above. Taking it from the right-hand side is safe only while the
        // checker guarantees the two types are equal, and it fails in the
        // direction that overruns rather than the one that under-fills: a wider
        // source writes past the end of a narrower destination.
        const ty = try self.typeAt(lhs);
        const value = try self.expr(a.rhs);
        if (try self.typeAt(a.rhs) == .never) return value;

        // A lend is an address, so what is written goes through it. Storing
        // the value into the slot would overwrite the address that was lent,
        // and for a value that lives in memory it would store that value's
        // address rather than its bytes.
        if (try self.addressBehind(target, ty, span)) |p| {
            try self.writeThrough(p, ty, value, span);
            return self.nothing(.unit, span);
        }

        try self.storeLocal(self.local_of_binding[target.index()], ty, span, value);
        return self.nothing(.unit, span);
    }

    /// The address a path names.
    ///
    /// The base is an expression, and a value that lives in memory *is* its
    /// address -- so this is the same walk `selection` makes, stopping one
    /// step short of the load.
    fn placeAddress(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        // A constant, bare or reached through a module or a type, is the
        // static holding it. Asked before the steps, because `Limits.TABLE`
        // is written as a field and names no field, and every walk reaching a
        // base, an element's included, comes through here.
        const constant = self.res.constantNamed(id);
        if (constant != BindingId.none) {
            const value = self.typing.constantValue(constant) orelse return self.poison(span);
            return self.staticAddress(value, try self.typeAt(id), span);
        }

        // An index is a step like a field is, so the address of one is found
        // the same way: what it steps into, then how far in. The offset is a
        // product rather than a recorded place, which is the whole of what an
        // array adds here.
        if (self.ast.exprTag(id) == .index) return self.elementAddress(id, span);

        return self.selectedAddress(id, span);
    }

    fn selectedAddress(self: *Lowerer, id: ExprId, span: Span) !InstId {
        const projection = self.typing.placeProjection(id) orelse return self.poison(span);
        const held = try self.typeAt(projection.base);
        const value = try self.expr(projection.base);
        if (held == .never) return value;
        const address = try self.observeLayers(value, held, projection.observations, span);
        if (projection.field) |field| {
            const receiver = try self.substituted(projection.receiver);
            const member = self.types().fieldType(receiver, field.index());
            return self.fieldAddr(address, member, self.types().fieldOffset(receiver, field.index()), span);
        }
        return address;
    }

    /// Which slot of a projection's path a name reaches, or null where it
    /// reaches none.
    ///
    /// **Bound:** the slots the expansions being read through opened, which is
    /// two per bracket nested at this point and nothing per program.
    fn slotAt(self: *const Lowerer, id: ExprId) ?usize {
        if (self.splices.items.len == 0) return null;
        const at = self.ast.withoutGroups(id);
        if (self.ast.exprTag(at) != .name_ref) return null;
        const target = self.res.targetOf(at);
        if (target == BindingId.none) return null;

        var i = self.splices.items.len;
        while (i > 0) {
            i -= 1;
            const slot = self.splices.items[i];
            if (slot.hidden == 0 and slot.binding == target) return i;
        }
        return null;
    }

    /// What a slot holds, lowering the site's expression the first time it is
    /// asked for.
    fn slotValue(self: *Lowerer, at: usize) std.mem.Allocator.Error!InstId {
        self.splices.items[at].read = true;
        if (self.splices.items[at].value != InstId.none) return self.splices.items[at].value;
        const saved = self.instance;
        self.instance = self.splices.items[at].instance;
        defer self.instance = saved;
        // The expression was written where only the slots open before its
        // bracket were in reach, so those opened since are hidden while it is
        // lowered; slots its own brackets open stay visible. The slots touched
        // are the ones open at this point: two per bracket nested here.
        // Indices, not a slice: lowering may open slots and move the list.
        const from = self.splices.items[at].site;
        const until = self.splices.items.len;
        for (self.splices.items[from..until]) |*slot| slot.hidden += 1;
        defer for (self.splices.items[from..until]) |*slot| {
            slot.hidden -= 1;
        };
        const v = try self.expr(self.splices.items[at].wrote);
        self.splices.items[at].value = v;
        return v;
    }

    /// The expression a name stands for: what the site wrote where the name
    /// reaches a slot, and the name itself where it does not.
    ///
    /// What reads a path without emitting from it goes through here, so what is
    /// folded and what is emitted are the same expression -- `g[2]` folds
    /// because the slot the path names is filled by a literal, exactly as the
    /// path written out by hand does.
    fn spliced(self: *Lowerer, id: ExprId) ExprId {
        const at = self.slotAt(id) orelse return id;
        // A slot filled with a value has no expression to fold, and the name
        // itself is the only thing left to read -- which folds to nothing, as
        // a position settled at run time should.
        if (self.splices.items[at].wrote == ExprId.none) return id;
        // Folding is reading. The value reached the path and became an offset,
        // so emitting the expression afterwards would be a second reading of
        // one expression rather than the first reading of an unread one.
        self.splices.items[at].read = true;
        return self.splices.items[at].wrote;
    }

    /// The address a routed bracket names: the implementation's own path, read
    /// with the site's two expressions in its slots.
    ///
    /// This is the whole of what a projection costs. No call is emitted and
    /// nothing stands for the projection below here -- what reaches the rest of
    /// lowering is the field arithmetic and the bounds check the same path
    /// written out by hand reaches.
    ///
    /// The span is the site's throughout, so a check that fails names the
    /// bracket a reader wrote rather than a line inside a library.
    fn projectedAddress(
        self: *Lowerer,
        id: ExprId,
        found: types_mod.Expansion,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const b = self.ast.binary(id);
        return self.splicedPath(found, .{ .wrote = b.lhs }, .{ .wrote = b.rhs }, span);
    }

    /// What fills one of a projection's two slots at one site.
    ///
    /// Two shapes and one splice. A bracket fills both with expressions a
    /// reader wrote, lowered when the path first names the slot. A lending walk
    /// fills both with values it already has: the head it evaluated once before
    /// the loop, and the position the traversal handed over -- neither of which
    /// any line of the program spells a second time, and the head of which must
    /// not be evaluated again, because a walk rebuilding it per position would
    /// lend places of a different value each time. Everything below the slot is
    /// the same path, so the difference stops at what goes into one.
    const Fills = union(enum) {
        wrote: ExprId,
        /// The value, and the type it is at: with no expression to read a type
        /// off, the slot carries its own.
        held: struct { value: InstId, ty: TypeId },

        fn expression(self: Fills) ExprId {
            return switch (self) {
                .wrote => |e| e,
                .held => ExprId.none,
            };
        }

        fn value(self: Fills) InstId {
            return switch (self) {
                .wrote => InstId.none,
                .held => |h| h.value,
            };
        }
    };

    /// The address an implementation's path names, with the receiver and the
    /// position in its two slots.
    fn splicedPath(
        self: *Lowerer,
        found: types_mod.Expansion,
        receiver: Fills,
        position: Fills,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        if (found.delegation) |delegation| return self.delegatedAddress(found, delegation, receiver, position, span);
        const mark = self.splices.items.len;
        defer self.splices.shrinkRetainingCapacity(mark);

        const base = self.splices.items.len;
        try self.splices.append(self.gpa, .{
            .binding = BindingId.at(found.receiver),
            .wrote = receiver.expression(),
            .value = receiver.value(),
            .instance = self.instance,
            .site = mark,
        });
        // A projection declaring only a receiver names no index parameter, so
        // there is no slot for the site's position to fill.
        const index: ?usize = if (found.index == types_mod.Expansion.no_binding) null else at: {
            const slot = self.splices.items.len;
            try self.splices.append(self.gpa, .{
                .binding = BindingId.at(found.index),
                .wrote = position.expression(),
                .value = position.value(),
                .instance = self.instance,
                .site = mark,
            });
            break :at slot;
        };

        // The path is the implementation's own text, checked once in terms of
        // the implementation's own parameters -- so a type it names, read
        // through the instantiation this body is being lowered under, is read
        // through the wrong one unless that instantiation is swapped first. A
        // member of an implementation generic over its head is bound by its
        // receiver, exactly as an ordinary call to one is (`lowerFunction`
        // binds it from `w.self_ty` the same way): the receiver here is the
        // site's own, read under the instantiation still in force outside this
        // bracket, which is what settles it before anything is swapped.
        const receiver_ty = switch (receiver) {
            .wrote => |e| try self.typeAt(e),
            .held => |h| h.ty,
        };
        const bound = try self.gpa.alloc(TypeId, found.impl_args.len);
        defer self.gpa.free(bound);
        for (found.impl_args, bound) |written, *settled| settled.* = try self.substituted(written);
        const member_instance = try bodyParametersOf(self.ast, self.res, self.typing, found.member).splicedAt(self.gpa, found.member, receiver_ty, bound);
        defer self.gpa.free(member_instance.args);

        const path = self.ast.withoutGroups(found.path);
        // A path that is the receiver itself names the base's own place, and
        // the base is a value in memory, which is its address.
        const saved = self.instance;
        self.instance = member_instance;
        const address = addr: {
            defer self.instance = saved;
            break :addr if (self.ast.isSelection(path))
                try self.placeAddress(path, span)
            else
                try self.splicedExpr(path, span);
        };

        // Both of a bracket's operands are expressions the site wrote, and an
        // expression runs where it is written whatever reads its value -- under
        // the instantiation the site itself is lowered through, restored above
        // before either runs. A path that names neither slot -- `self.a` over
        // an index the implementation ignores -- still leaves a call in the
        // brackets to make, and ownership has already recorded what that call
        // does. A slot the path did name was run by the walk above, once, so
        // this runs the rest and nothing twice.
        try self.runUnread(base);
        if (index) |slot| try self.runUnread(slot);
        return address;
    }

    /// Emits a slot's expression where reading the path never asked for it.
    fn runUnread(self: *Lowerer, slot: usize) std.mem.Allocator.Error!void {
        if (self.splices.items[slot].read) return;
        _ = try self.slotValue(slot);
    }

    /// The address of `a[i]`, checked.
    ///
    /// Shared by reading one, writing through one, and marking one into a
    /// callee: all three reach the same bytes, so they reach them by the same
    /// arithmetic and the same check.
    fn elementAddress(self: *Lowerer, id: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        const b = self.ast.binary(id);
        const head_ty = try self.typeAt(b.lhs);
        if (head_ty == .never) return self.expr(b.lhs);
        const index_ty = try self.typeAt(b.rhs);
        if (index_ty == .never) {
            _ = if (self.ast.isSelection(b.lhs))
                try self.placeAddress(self.ast.withoutGroups(b.lhs), span)
            else
                try self.expr(b.lhs);
            return self.expr(b.rhs);
        }

        // A bracket the checker routed through an implementation is that
        // implementation's path. Operand divergence is handled first because
        // no implementation lookup or path runs after control stops.
        if (self.calls.projectionOf(self.typing, id)) |found| {
            return self.projectedAddress(id, found, span);
        }

        const result_ty = try self.typeAt(id);

        const arr = switch (self.types().get(head_ty)) {
            .array => |a| a,
            else => return InstId.none,
        };

        // An aggregate is its address, and a place inside one is reached
        // through the place walk rather than by evaluating it as a value.
        const base = if (self.ast.isSelection(b.lhs))
            try self.placeAddress(self.ast.withoutGroups(b.lhs), span)
        else
            try self.expr(b.lhs);
        if (base == InstId.none) return InstId.none;

        const stride = self.types().strideOf(arr.element);

        // A range names a run of elements, which is one place beginning where
        // its lower bound does: how wide it is is the place's own type, and
        // belongs to whatever reads or writes through this address, so there is
        // nothing here but the offset. Both bounds settled where the place was
        // formed, and this is what they settled to -- so no check is emitted,
        // which is the same nothing a settled index costs.
        if (self.calls.rangePlaceOf(self.typing, id)) |place| {
            return self.fieldAddr(base, result_ty, @intCast(stride * place.first), span);
        }

        return self.arrayElementAddress(base, head_ty, .{ .wrote = b.rhs }, index_ty, span);
    }

    /// Both authored and delegated projections use the same array bounds checks.
    fn arrayElementAddress(
        self: *Lowerer,
        base: InstId,
        array_type: TypeId,
        position: Fills,
        index_ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const arr = self.types().get(array_type).array;
        const result_ty = arr.element;
        const stride = self.types().strideOf(result_ty);
        const wrote = position.expression();
        if (self.typing.from_end != .poison and index_ty == self.typing.from_end) {
            if (wrote != .none) if (self.foldedCountBack(wrote)) |k| {
                if (Typing.elementSlot(arr.count, k, true)) |slot|
                    return self.fieldAddr(base, result_ty, @intCast(stride * slot), span);
            };
            const k = switch (position) {
                .wrote => |expression| try self.fromEndCount(expression, span),
                .held => |held| try self.countIn(held.value, held.ty, span),
            };
            return self.fromEndValueAddress(k, base, result_ty, arr.count, stride, span);
        }
        if (wrote != .none) if (self.foldedIndex(wrote)) |at| {
            if (Typing.elementSlot(arr.count, at, false)) |slot|
                return self.fieldAddr(base, result_ty, @intCast(stride * slot), span);
        };
        const idx = switch (position) {
            .wrote => |expression| try self.expr(expression),
            .held => |held| held.value,
        };
        var address_index = idx;
        const signed = switch (self.types().get(index_ty)) {
            .integer => |i| i.signed,
            else => false,
        };
        if (signed) {
            const zero = try self.emit(.constant, index_ty, span, .{ .constant = 0 });
            const low = try self.emit(.cmp_ge, .bool_, span, .{ .binary = .{ .lhs = idx, .rhs = zero } });
            _ = try self.check(low, .bool_, span, .index_out_of_bounds);
            address_index = try self.check(idx, .u64, span, .conversion_out_of_range);
        }
        const count = try self.emit(.constant, .u64, span, .{ .constant = arr.count });
        const ok = try self.emit(.cmp_lt, .bool_, span, .{ .binary = .{ .lhs = address_index, .rhs = count } });
        _ = try self.check(ok, .bool_, span, .index_out_of_bounds);
        const by = try self.emit(.constant, .u64, span, .{ .constant = stride });
        const off = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = address_index, .rhs = by } });
        return self.emit(.field_addr, result_ty, span, .{ .binary = .{ .lhs = base, .rhs = off } });
    }

    fn delegatedAddress(
        self: *Lowerer,
        found: types_mod.Expansion,
        delegation: types_mod.DelegatedProjection,
        receiver: Fills,
        position: Fills,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const receiver_ty = switch (receiver) {
            .wrote => |expression| try self.typeAt(expression),
            .held => |held| held.ty,
        };
        const base = switch (receiver) {
            .wrote => |expression| if (self.ast.isSelection(expression))
                try self.placeAddress(self.ast.withoutGroups(expression), span)
            else
                try self.expr(expression),
            .held => |held| held.value,
        };
        const field_ty = if (delegation.field) |field| self.types().fieldType(receiver_ty, field) else receiver_ty;
        const address = if (delegation.field) |field| try self.fieldAddr(base, field_ty, self.types().fieldOffset(receiver_ty, field), span) else base;
        if (delegation.deferred_trait) |trait| {
            const bound = try self.gpa.alloc(TypeId, found.impl_args.len);
            defer self.gpa.free(bound);
            for (found.impl_args, bound) |written, *settled| settled.* = try self.substituted(written);
            const key = if (delegation.field == null) try self.substituted(delegation.key_type) else try self.mono.pool.substitute(delegation.key_type, found.member.index(), bound);
            if (try self.mono.pool.projectionFor(self.typing, trait, key, field_ty)) |backing|
                return self.splicedPath(backing, .{ .held = .{ .value = address, .ty = field_ty } }, position, span);
            return self.arrayElementAddress(address, field_ty, position, key, span);
        }
        if (delegation.backing) |row| {
            const bound = try self.gpa.alloc(TypeId, found.impl_args.len);
            defer self.gpa.free(bound);
            for (found.impl_args, bound) |written, *settled| settled.* = try self.substituted(written);
            const args = try self.gpa.alloc(TypeId, delegation.backing_args.len);
            defer self.gpa.free(args);
            for (delegation.backing_args, args) |written, *settled|
                settled.* = try self.mono.pool.substitute(written, found.member.index(), bound);
            var backing = self.typing.expansions[row];
            backing.impl_args = args;
            return self.splicedPath(backing, .{ .held = .{ .value = address, .ty = field_ty } }, position, span);
        }
        const key = switch (position) {
            .wrote => |expression| try self.typeAt(expression),
            .held => |held| held.ty,
        };
        return self.arrayElementAddress(address, field_ty, position, key, span);
    }

    /// The address `a[^k]` names: the length, less the count, guarded.
    ///
    /// Both ends before the subtraction, and that is the whole point of the
    /// order. A count of nothing names the place past the last element and a
    /// count past the length names one before the first -- and an unsigned
    /// subtraction run first would land the second back inside the array, at a
    /// place nobody named, with nothing left for a check to notice. So the
    /// count is held against one and against the length while it is still the
    /// number that was written, and the subtraction happens only where the
    /// difference is a place the array has.
    ///
    /// Reached by a count the compiler does not settle. A settled one folded to
    /// an offset above, which is what makes a settled index cost nothing at run
    /// time whichever end it counts from.
    fn fromEndValueAddress(
        self: *Lowerer,
        k: InstId,
        base: InstId,
        result_ty: TypeId,
        length: u32,
        stride: u64,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        if (k == InstId.none) return InstId.none;

        const one = try self.emit(.constant, .u64, span, .{ .constant = 1 });
        const counts = try self.emit(.cmp_ge, .bool_, span, .{ .binary = .{ .lhs = k, .rhs = one } });
        _ = try self.check(counts, .bool_, span, .index_out_of_bounds);

        const count = try self.emit(.constant, .u64, span, .{ .constant = length });
        const within = try self.emit(.cmp_le, .bool_, span, .{ .binary = .{ .lhs = k, .rhs = count } });
        _ = try self.check(within, .bool_, span, .index_out_of_bounds);

        const at = try self.emit(.sub, .u64, span, .{ .binary = .{ .lhs = count, .rhs = k } });
        const by = try self.emit(.constant, .u64, span, .{ .constant = stride });
        const off = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = at, .rhs = by } });
        return self.emit(.field_addr, result_ty, span, .{ .binary = .{ .lhs = base, .rhs = off } });
    }

    /// What a count back from the end counts by.
    ///
    /// The caret is the short spelling of a value, so a site that wrote one
    /// yields the number under it and a site that wrote a value of its own
    /// yields the number that value holds. One routine, because the guard above
    /// compares the count however the site spelled it.
    ///
    /// A name filling a projection's slot goes through the slot rather than
    /// through the expression it stands for: the slot lowers what the site
    /// wrote once however many times the path names it, and the count is then
    /// read off that one value. Reaching past it to the site's expression is
    /// how a path naming its parameter twice ran the site's brackets twice --
    /// the number a bracket produced is read as many times as the path asks
    /// for it, and the expression that produced it runs where it is written.
    fn fromEndCount(self: *Lowerer, index: ExprId, span: Span) std.mem.Allocator.Error!InstId {
        if (self.slotAt(index)) |slot| {
            // A slot filled with a value has no site expression to read a type
            // off, so the parameter's own is what it is at -- which is the type
            // the position arrived as.
            const wrote = self.splices.items[slot].wrote;
            const at = if (wrote == ExprId.none) index else wrote;
            return self.countIn(try self.slotValue(slot), try self.typeAt(at), span);
        }

        const at = self.ast.withoutGroups(index);
        if (self.ast.exprTag(at) == .from_end) return self.expr(self.ast.unaryOperand(at));

        return self.countIn(try self.expr(at), try self.typeAt(at), span);
    }

    /// The count a value of the library's `FromEnd` holds, read out of it by
    /// the name that structure gives it.
    fn countIn(self: *Lowerer, value: InstId, of: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        if (value == InstId.none) return InstId.none;
        const k = self.types().lookupField(of, "k") orelse return InstId.none;
        return self.readThrough(try self.fieldAddr(value, k.ty, k.offset, span), k.ty, span);
    }

    /// What a count back from an end counts by, where the compiler settles it.
    ///
    /// Read the way an index written as a number is read, and through the
    /// splice for the same reason: folding is reading, so a slot whose value
    /// became an offset is not read a second time.
    fn foldedCountBack(self: *Lowerer, id: ExprId) ?u64 {
        const at = self.ast.withoutGroups(self.spliced(id));
        if (self.ast.exprTag(at) != .from_end) return null;
        return self.foldedIndex(self.ast.unaryOperand(at));
    }

    fn afterNoreturn(self: *Lowerer, span: Span) std.mem.Allocator.Error!InstId {
        self.block = try self.b.addBlock();
        try self.unreached.put(self.gpa, self.block, {});
        return self.poison(span);
    }

    fn directCall(
        self: *Lowerer,
        ty: TypeId,
        span: Span,
        callee: FunctionId,
        args: []const InstId,
    ) std.mem.Allocator.Error!InstId {
        if (ty != .never) return self.b.addCall(self.block, self.mono.callResultRole(ty), ty, span, callee, args);
        _ = try self.b.setCallNoreturn(self.block, span, callee, args);
        return self.afterNoreturn(span);
    }

    /// A call the program wrote, recorded against its expression so a reader
    /// finds the callee of that expression rather than of whatever else was
    /// lowered at its span.
    fn sourceCall(
        self: *Lowerer,
        written: ExprId,
        ty: TypeId,
        span: Span,
        callee: FunctionId,
        args: []const InstId,
    ) std.mem.Allocator.Error!InstId {
        const call = try self.directCall(ty, span, callee, args);
        if (ty != .never) try self.b.recordCallSite(written, call);
        return call;
    }

    /// Lowers one written call argument and says whether it ended evaluation.
    /// Every call form uses this so a divergent argument prevents the call
    /// instruction regardless of how the callee is represented.
    fn appendCallArgument(self: *Lowerer, args: *std.ArrayList(InstId), arg: ExprId, param: types_mod.CallableParam) !?InstId {
        const value = if (mir_mod.parameterBorrowsPlace(param) and try self.typeAt(arg) != .never)
            try self.borrowedAddress(arg, self.ast.exprSpan(arg))
        else
            try self.expr(arg);
        try args.append(self.gpa, value);
        return if (try self.typeAt(arg) == .never) value else null;
    }

    /// `f(a, b)`. A call returning Never ends its block; every other call
    /// returns control to the following instruction.
    fn callExpr(self: *Lowerer, id: ExprId, ty: TypeId, span: Span, dest: ?*Dest) std.mem.Allocator.Error!InstId {
        const c = self.ast.call(id);
        // A recorded variant selection names a constructor rather than a call.
        if (self.variantOrdinal(self.ast.withoutGroups(c.callee)) != null) return self.construct(id, ty, span, dest);

        // The checker records conversions before instantiation. The result
        // type above supplies the concrete target for this instance.
        if (self.typing.conversionTarget(id)) |_| {
            // A conversion the checker rejected reaches here with no argument
            // to take; nothing below it runs, because the program is rejected.
            if (c.args.len != 1) return self.poison(span);
            const v = try self.expr(c.args[0]);
            if (try self.typeAt(c.args[0]) == .never) return v;

            // A change of register class is an instruction, not a re-test:
            // the bits move between encodings, where an integer conversion is
            // one value held to a narrower range. The guards a float-to-int
            // carries travel with the instruction, because they are what the
            // conversion means and not a separate verification of its input.
            const source = try self.typeAt(c.args[0]);
            if (ty.isFloat() or source.isFloat()) {
                if (source == ty) return v;
                if (ty.isFloat() and source.isFloat()) {
                    return self.emit(if (ty == .f64) .float_extend else .float_truncate, ty, span, .{ .unary = v });
                }
                return self.emit(if (ty.isFloat()) .int_to_float else .float_to_int, ty, span, .{ .unary = v });
            }

            return self.check(v, ty, span, .conversion_out_of_range);
        }

        // And one whose callee names a newtype constructs. The checker
        // proved this program before it reached lowering, so nothing here
        // re-derives whether the value is in range -- only the fallible form
        // still asks that at run time, because it is the one form whose
        // answer the checker could not settle.
        if (resolve_mod.constructionOf(self.ast, self.res, id)) |_| {
            return self.newtypeConstruct(id, ty, span, dest);
        }

        const normal = self.calls.callOf(self.typing, id) orelse return self.poison(span);

        switch (normal.target) {
            .array_view => {
                const source = normal.args[0];
                const adjustment = normal.receiver_adjustments[0].?;
                const source_type = try self.substituted(adjustment.receiver);
                const address = if (adjustment.observations > 0)
                    try self.observeLayers(try self.expr(source), try self.typeAt(source), adjustment.observations, span)
                else
                    try self.borrowedAddress(source, span);
                const bits = try self.emit(.address_bits, .u64, span, .{ .unary = address });
                const count = try self.emit(.constant, .u64, span, .{ .constant = self.types().get(source_type).array.count });
                return self.buildSpan(ty, bits, count, span);
            },
            .array_length => {
                // The receiver still runs for its effects; the count is the
                // one its array type holds.
                const source = normal.args[0];
                const value = try self.expr(source);
                if (try self.typeAt(source) == .never) return value;
                const array_type = try self.substituted(normal.receiver_adjustments[0].?.receiver);
                return self.emit(.constant, .u64, span, .{ .constant = self.types().get(array_type).array.count });
            },
            .closure_recovery => {
                const receiver = normal.args[0];
                const value = try self.expr(receiver);
                const receiver_type = try self.typeAt(receiver);
                if (self.mono.pool.get(receiver_type).closure.environment == .unit)
                    return self.baseFor(ty, span, dest);
                return self.fieldAddr(value, ty, 0, span);
            },
            .closure => return self.directClosureCall(id, normal, c.callee, ty, span),
            .generic_callable => |parameter| {
                const concrete = try self.instance.through(&self.mono.pool, parameter);
                return switch (self.mono.pool.get(concrete)) {
                    .closure => self.directClosureCall(id, normal, c.callee, ty, span),
                    .callable => self.indirectCall(normal, c.callee, ty, span),
                    else => self.poison(span),
                };
            },
            .indirect => |callee| return self.indirectCall(normal, callee, ty, span),
            .erased => |callee| return self.erasedCall(normal, callee, ty, span),
            else => {},
        }

        // A call through a trait names a signature, which has no body: the
        // callee is not the declaration the call reaches. The checker settled
        // what `Self` is; this instantiation is what makes it concrete, and the
        // implementation follows from it with nothing consulted at run time.
        const named = switch (normal.target) {
            .declared => |decl| decl,
            .closure => unreachable,
            .closure_recovery, .array_view, .array_length, .indirect, .generic_callable, .erased => unreachable,
        };

        // An interpolation renders itself, and no implementation is written
        // anywhere for it to reach. Intercepted here rather than given a body
        // to call, because the body would be one function per literal and each
        // would be used exactly once.
        //
        // Before the arguments, because rendering lowers the literal itself and
        // this call takes nothing else: lowering them first built the fragments
        // a second time and then dropped them.
        if (try self.rendersInterpolation(id, named)) |rendered| return rendered;

        var args: std.ArrayList(InstId) = .empty;
        defer args.deinit(self.gpa);
        const lent = lentReceiver(self.ast, self.res, id, normal.written_type_arguments);
        for (normal.args, 0..) |a, at| {
            // `&x.op()` lends its receiver, so what is passed is the place's
            // address, exactly as for an argument written `&x`.
            if (a != ExprId.none and a == lent) {
                try args.append(self.gpa, try self.addressOfPlace(a, self.ast.exprSpan(a)));
                continue;
            }
            // A hole is a parameter the call omitted, and what fills it is the
            // constant its declaration writes. Spliced here rather than
            // evaluated: the checker worked the expression out where the
            // parameter is declared, so what arrives is a value and the call
            // below sees a list every parameter of which was given something.
            if (a == ExprId.none) {
                try args.append(self.gpa, try self.splicedCallableDefault(normal.signature, at, span));
                continue;
            }
            const param = self.typing.callableParams(self.typing.get(normal.signature).callable)[at];
            if (at < normal.receiver_adjustments.len) {
                if (normal.receiver_adjustments[at]) |adjustment| {
                    var observations = adjustment.observations;
                    var receiver = try self.substituted(adjustment.receiver);
                    if (adjustment.selection == .implementation) {
                        const rec = normal.selection.implementation orelse
                            @panic("compiler defect: receiver adjustment has no implementation selection");
                        const trait_args = try self.gpa.alloc(TypeId, rec.args.len);
                        defer self.gpa.free(trait_args);
                        for (rec.args, 0..) |argument, i| trait_args[i] = try self.substituted(argument);
                        const choice = self.mono.instances.selectedChoice(DeclId.at(rec.trait), trait_args, try self.substituted(rec.self_ty));
                        if (choice.view != .poison and try self.typeAt(a) != .never) {
                            const value = try self.expr(a);
                            const layered = try self.observationArgument(value, try self.typeAt(a), receiver, false, span);
                            try args.append(self.gpa, try self.receiverArgument(layered, receiver, choice, span));
                            continue;
                        }
                        observations += choice.observations;
                        receiver = choice.receiver;
                    }
                    const argument_type = try self.typeAt(a);
                    if (observations > 0 and argument_type != .never) {
                        const address = try self.observeLayers(try self.expr(a), argument_type, observations, span);
                        const value = if (param.stable_address) address else try self.readThrough(address, receiver, span);
                        try args.append(self.gpa, value);
                        continue;
                    }
                }
            }
            // C calls a callback through an entry in its own convention, so an
            // `extern`'s callback argument is that entry's address. The checker
            // gave every such argument a fixed target ([T-ExternCallback]).
            if (self.ast.declIsExtern(named) and self.typing.get(param.ty) == .callable) {
                const value = self.calls.functionValueOf(self.typing, self.ast.withoutGroups(a)) orelse
                    @panic("compiler defect: a callback passed to C has no fixed target");
                const target = try self.functionTarget(value);
                try args.append(self.gpa, try self.b.addForeignFunctionAddr(self.block, try self.substituted(value.signature), self.ast.exprSpan(a), target));
                continue;
            }
            if (try self.appendCallArgument(&args, a, param)) |stopped| return stopped;
        }

        // A call on an implementation the compiler provides names no body to
        // run, so it becomes the instruction that implementation is. After the
        // arguments, because it takes exactly the ones every other call takes.
        if (try self.ambientOperation(id, named, ty, span, args.items)) |v| return v;

        // The body, and the type it runs for: a member of an implementation
        // generic over its head is one declaration per family, and which member
        // of the family this call reaches is the receiver it settled.
        const d, const held, const impl_args = switch (try self.calleeOf(id, named)) {
            .named => .{ named, TypeId.poison, @as([]const TypeId, &.{}) },
            .implemented => |body| .{ body.member, body.held, body.impl_args },
            .generated => |body| {
                const target = self.mono.instances.lookupBody(body, &.{}, .poison, &.{}).?;
                return self.sourceCall(id, ty, span, FunctionId.at(target.index()), args.items);
            },
        };

        std.debug.assert(self.ast.declBody(d) != ExprId.none or self.ast.declIsExtern(d));

        if (self.library.float_math.operationOf(d)) |math_operation| {
            std.debug.assert(args.items.len == math_operation.arity());
            return self.emit(.float_math, .f64, span, .{ .float_math = .{
                .operation = math_operation,
                .lhs = args.items[0],
                .rhs = if (math_operation.arity() == 2) args.items[1] else .none,
            } });
        }

        // Except the raw accesses, which no runtime provides: the call
        // is replaced by the checks and the access itself, so one that
        // survives to the linker is a lowering that missed this swap -- and it
        // fails the build there rather than running a second implementation.
        if (d == self.library.raw.store)
            return self.checkedAccess(.wide, args.items[0..3].*, args.items[3], span);
        if (d == self.library.raw.load)
            return self.checkedAccess(.wide, args.items[0..3].*, null, span);
        if (d == self.library.raw.store8)
            return self.checkedAccess(.byte, args.items[0..3].*, args.items[3], span);
        if (d == self.library.raw.load8)
            return self.checkedAccess(.byte, args.items[0..3].*, null, span);

        // Which instantiation this call reaches. The checker recorded what it
        // settled the callee's parameters to; those arguments are themselves
        // read through this body's own, so a generic function calling another
        // passes on what it was given rather than what it was written with.
        const settled = try self.argsOfCall(id);
        defer self.gpa.free(settled);

        if (d == self.library.raw.stride) {
            return self.emit(.constant, .u64, span, .{ .constant = @max(self.types().layoutOf(settled[0]).size, 1) });
        }
        if (d == self.library.raw.closure_size)
            return self.emit(.constant, .u64, span, .{ .constant = self.types().layoutOf(settled[0]).size });
        if (self.library.raw.erasedBody(d, settled)) |body| {
            const generated = self.mono.instances.lookupBody(body, &.{}, .poison, &.{}) orelse
                @panic("compiler defect: an erased closure's generated body was never discovered");
            return self.b.addFunctionAddr(self.block, ty, span, FunctionId.at(generated.index()));
        }
        if (d == self.library.raw.span or d == self.library.raw.buffer_span or d == self.library.raw.subspan or d == self.library.raw.slice_place or self.library.raw.processText(d) != null)
            return self.spanIntrinsic(d, ty, settled, args.items, span);
        if (d == self.library.raw.take or d == self.library.raw.put or d == self.library.raw.place) {
            const element = settled[0];
            const storage = if (d == self.library.raw.place) blk: {
                const fits = try self.emit(.cmp_lt, .bool_, span, .{ .binary = .{ .lhs = args.items[4], .rhs = args.items[3] } });
                _ = try self.check(fits, .bool_, span, .index_out_of_bounds);
                const stride = try self.emit(.constant, .u64, span, .{ .constant = self.types().layoutOf(element).size });
                const offset = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = args.items[4], .rhs = stride } });
                _ = try self.check(offset, .u64, span, .overflow);
                break :blk try self.checkedStorageAddress(element, .{ args.items[1], args.items[2], offset }, span);
            } else try self.checkedStorageAddress(element, args.items[1..4].*, span);
            if (d == self.library.raw.place) return storage;
            if (d == self.library.raw.put) {
                try self.writeThrough(storage, element, args.items[4], span);
                return self.nothing(.unit, span);
            }
            const value = try self.readThrough(storage, element, span);
            if (!self.isAggregate(element)) return value;
            const local = try self.b.addLocal(element, .value);
            try self.storeLocal(local, element, span, value);
            return self.loadLocal(local, element, span);
        }
        const callee = self.mono.idFor(d, settled, held, impl_args);
        if (self.ast.declIsExtern(d)) {
            if (self.library.raw.errnoValue(&self.mono.pool, ty)) |value| return self.errnoCall(id, ty, value, span, callee, args.items);
        }
        return self.sourceCall(id, ty, span, callee, args.items);
    }

    /// A call to an `extern` answering `ffi.Errno[R]`: C's `R`, then the
    /// runtime's read of `errno`, emitted next so no code between the two can
    /// change it, and the `Errno` built from both.
    fn errnoCall(self: *Lowerer, written: ExprId, ty: TypeId, value_ty: TypeId, span: Span, callee: FunctionId, args: []const InstId) !InstId {
        const value = try self.sourceCall(written, value_ty, span, callee, args);
        const read = self.mono.idFor(self.library.raw.errno_read, &.{}, .poison, &.{});
        const code = try self.directCall(.i32, span, read, &.{});
        const base = try self.baseFor(ty, span, null);
        const value_field = self.types().lookupField(ty, "value") orelse return self.poison(span);
        const code_field = self.types().lookupField(ty, "code") orelse return self.poison(span);
        try self.writeThrough(try self.fieldAddr(base, value_field.ty, value_field.offset, span), value_field.ty, value, span);
        try self.writeThrough(try self.fieldAddr(base, code_field.ty, code_field.offset, span), code_field.ty, code, span);
        return base;
    }

    fn fieldValue(self: *Lowerer, base: InstId, ty: TypeId, name: []const u8, span: Span) !InstId {
        const field = self.types().lookupField(ty, name) orelse return self.poison(span);
        return self.readThrough(try self.fieldAddr(base, field.ty, field.offset, span), field.ty, span);
    }

    fn buildSpan(self: *Lowerer, ty: TypeId, address: InstId, count: InstId, span: Span) !InstId {
        const base = try self.baseFor(ty, span, null);
        const at = self.types().lookupField(ty, "at") orelse return self.poison(span);
        const len = self.types().lookupField(ty, "len") orelse return self.poison(span);
        try self.writeThrough(try self.fieldAddr(base, at.ty, at.offset, span), at.ty, address, span);
        try self.writeThrough(try self.fieldAddr(base, len.ty, len.offset, span), len.ty, count, span);
        return base;
    }

    fn spanIntrinsic(self: *Lowerer, d: DeclId, ty: TypeId, type_args: []const TypeId, args: []const InstId, span: Span) !InstId {
        const raw = self.library.raw;
        if (raw.processText(d)) |source| {
            const count = try self.directCall(.u64, span, self.mono.idFor(source.count, &.{}, .poison, &.{}), &.{});
            const fits = try self.emit(.cmp_lt, .bool_, span, .{ .binary = .{ .lhs = args[0], .rhs = count } });
            _ = try self.check(fits, .bool_, span, .index_out_of_bounds);
            const address = try self.directCall(.u64, span, self.mono.idFor(source.at, &.{}, .poison, &.{}), args);
            const len = try self.directCall(.u64, span, self.mono.idFor(source.len, &.{}, .poison, &.{}), args);
            return self.buildSpan(ty, address, len, span);
        }
        const element = if (d == raw.buffer_span) TypeId.u8 else type_args[0];
        const stride = try self.emit(.constant, .u64, span, .{ .constant = self.types().layoutOf(element).size });
        const owner = args[0];
        const owner_ty = self.b.insts.items(.ty)[owner.index()];
        const address = try self.fieldValue(owner, owner_ty, "at", span);
        const physical_len = try self.fieldValue(owner, owner_ty, "len", span);
        const live = if (d == raw.span) args[1] else physical_len;
        const start = if (d == raw.span) args[2] else args[1];
        if (d == raw.slice_place) {
            const fits = try self.emit(.cmp_lt, .bool_, span, .{ .binary = .{ .lhs = start, .rhs = live } });
            _ = try self.check(fits, .bool_, span, .index_out_of_bounds);
            const extent = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = live, .rhs = stride } });
            _ = try self.check(extent, .u64, span, .overflow);
            const offset = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = start, .rhs = stride } });
            _ = try self.check(offset, .u64, span, .overflow);
            return self.checkedStorageAddress(element, .{ address, extent, offset }, span);
        }
        const count = if (d == raw.span) args[3] else args[2];
        const start_fits = try self.emit(.cmp_le, .bool_, span, .{ .binary = .{ .lhs = start, .rhs = live } });
        _ = try self.check(start_fits, .bool_, span, .index_out_of_bounds);
        const remaining = try self.emit(.sub, .u64, span, .{ .binary = .{ .lhs = live, .rhs = start } });
        const count_fits = try self.emit(.cmp_le, .bool_, span, .{ .binary = .{ .lhs = count, .rhs = remaining } });
        _ = try self.check(count_fits, .bool_, span, .index_out_of_bounds);
        const offset = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = start, .rhs = stride } });
        _ = try self.check(offset, .u64, span, .overflow);
        if (d == raw.span) {
            const initialized = try self.emit(.mul, .u64, span, .{ .binary = .{ .lhs = live, .rhs = stride } });
            _ = try self.check(initialized, .u64, span, .overflow);
            const fits = try self.emit(.cmp_le, .bool_, span, .{ .binary = .{ .lhs = initialized, .rhs = physical_len } });
            _ = try self.check(fits, .bool_, span, .index_out_of_bounds);
        }
        const at = try self.emit(.add, .u64, span, .{ .binary = .{ .lhs = address, .rhs = offset } });
        _ = try self.check(at, .u64, span, .overflow);
        return self.buildSpan(ty, at, count, span);
    }

    fn closureValue(self: *Lowerer, ty: TypeId, span: Span, dest: ?*Dest) !InstId {
        const closure = self.mono.pool.get(ty).closure;
        if (closure.environment == .unit) return self.nothing(ty, span);
        const base = try self.baseFor(ty, span, dest);
        for (self.res.closureCaptures(closure.closure), 0..) |capture, index| {
            const field: u32 = @intCast(index);
            const field_ty = self.types().fieldType(closure.environment, field);
            const at = try self.fieldAddr(base, field_ty, self.types().fieldOffset(closure.environment, field), span);
            if (capture.convention != .sink) {
                const source = try self.addressOfPlace(capture.source, self.ast.exprSpan(capture.source));
                const observation = try self.emit(.borrow, field_ty, span, .{ .unary = source });
                try self.writeThrough(at, field_ty, observation, span);
            } else {
                try self.writeInto(capture.source, field_ty, at, span);
            }
        }
        return base;
    }

    fn directClosureCall(
        self: *Lowerer,
        written: ExprId,
        normal: types_mod.NormalizedCall,
        callee_expr: ExprId,
        ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        // The callee is evaluated once before explicit arguments, including
        // factory calls whose result has an empty environment.
        const value = try self.expr(callee_expr);
        const closure_type = try self.typeAt(callee_expr);
        if (closure_type == .never) return value;
        const environment = self.mono.pool.get(closure_type).closure.environment;
        var args: std.ArrayList(InstId) = .empty;
        defer args.deinit(self.gpa);
        for (normal.args, 0..) |arg, at| {
            if (arg == ExprId.none) {
                try args.append(self.gpa, try self.splicedCallableDefault(normal.signature, at, span));
                continue;
            }
            if (try self.appendCallArgument(&args, arg, self.typing.callableParams(self.typing.get(normal.signature).callable)[at])) |stopped| return stopped;
        }
        if (environment != .unit)
            try args.append(self.gpa, try self.fieldAddr(value, environment, 0, span));
        const callee = self.mono.idForClosure(self.mono.pool.get(closure_type).closure);
        return self.sourceCall(written, ty, span, callee, args.items);
    }

    fn indirectCall(
        self: *Lowerer,
        normal: types_mod.NormalizedCall,
        callee_expr: ExprId,
        ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const callee_at = self.ast.withoutGroups(callee_expr);
        const binding = if (self.ast.exprTag(callee_at) == .name_ref) self.res.targetOf(callee_at) else BindingId.none;
        const selected = if (binding != .none)
            self.selected_callables.get(self.local_of_binding[binding.index()])
        else
            null;
        const callee = if (selected == null) try self.expr(callee_expr) else InstId.none;
        var args: std.ArrayList(InstId) = .empty;
        defer args.deinit(self.gpa);
        for (normal.args, 0..) |arg, at| {
            if (arg == ExprId.none) {
                try args.append(self.gpa, try self.splicedCallableDefault(normal.signature, at, span));
                continue;
            }
            if (try self.appendCallArgument(&args, arg, self.typing.callableParams(self.typing.get(normal.signature).callable)[at])) |stopped| return stopped;
        }
        if (selected) |choice| return self.branchToValue(choice.condition, ty, span, struct {
            targets: [2]FunctionId,
            args: []const InstId,
            ty: TypeId,
            span: Span,

            fn whenTrue(arms: @This(), l: *Lowerer) std.mem.Allocator.Error!InstId {
                return l.directCall(arms.ty, arms.span, arms.targets[0], arms.args);
            }

            fn whenFalse(arms: @This(), l: *Lowerer) std.mem.Allocator.Error!InstId {
                return l.directCall(arms.ty, arms.span, arms.targets[1], arms.args);
            }
        }{ .targets = choice.targets, .args = args.items, .ty = ty, .span = span });
        if (ty != .never) {
            return self.b.addIndirectCall(
                self.block,
                self.mono.callResultRole(ty),
                ty,
                span,
                callee,
                args.items,
            );
        }
        _ = try self.b.setIndirectCallNoreturn(self.block, span, callee, args.items);
        return self.afterNoreturn(span);
    }

    /// A call through a `mem.Closure`: its entry, given the arguments and then
    /// the address and length of the stored callable's bytes. The closure is
    /// read in place and evaluated before the arguments, as any callee is.
    fn erasedCall(
        self: *Lowerer,
        normal: types_mod.NormalizedCall,
        callee_expr: ExprId,
        ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const closure = try self.expr(callee_expr);
        const closure_type = try self.typeAt(callee_expr);
        if (closure_type == .never) return closure;
        const entry = try self.fieldValue(closure, closure_type, "entry", span);
        const at = try self.fieldValue(closure, closure_type, "at", span);
        const len = try self.fieldValue(closure, closure_type, "len", span);
        var args: std.ArrayList(InstId) = .empty;
        defer args.deinit(self.gpa);
        for (normal.args, 0..) |arg, position| {
            if (arg == ExprId.none) {
                try args.append(self.gpa, try self.splicedCallableDefault(normal.signature, position, span));
                continue;
            }
            if (try self.appendCallArgument(&args, arg, self.typing.callableParams(self.typing.get(normal.signature).callable)[position])) |stopped| return stopped;
        }
        try args.append(self.gpa, at);
        try args.append(self.gpa, len);
        if (ty != .never) return self.b.addIndirectCall(self.block, self.mono.callResultRole(ty), ty, span, entry, args.items);
        _ = try self.b.setIndirectCallNoreturn(self.block, span, entry, args.items);
        return self.afterNoreturn(span);
    }

    fn functionValue(
        self: *Lowerer,
        value: types_mod.FunctionValue,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const target = try self.functionTarget(value);
        const signature = try self.substituted(value.signature);
        return self.b.addFunctionAddr(self.block, signature, span, target);
    }

    fn functionTarget(self: *Lowerer, value: types_mod.FunctionValue) std.mem.Allocator.Error!FunctionId {
        return switch (value.target) {
            .constructor => |constructor| self.mono.idForConstructor(constructor, self.instance.args, self.instance.self_ty, self.instance.impl_args),
            .closure => self.mono.idForClosure(self.mono.pool.get(try self.substituted(value.closure_type)).closure),
            .declared => |decl| blk: {
                const args = try self.gpa.alloc(TypeId, value.type_args.len);
                defer self.gpa.free(args);
                for (value.type_args, 0..) |arg, i| args[i] = try self.substituted(arg);
                break :blk switch (try self.calleeThrough(value.implementation, decl, true)) {
                    .named => self.mono.idFor(decl, args, .poison, &.{}),
                    .implemented => |body| self.mono.idFor(body.member, args, body.held, body.impl_args),
                    .generated => |body| FunctionId.at(self.mono.instances.lookupBody(body, &.{}, .poison, &.{}).?.index()),
                };
            },
        };
    }

    /// The two leaves must already be checked function values. Empty block
    /// wrappers and parentheses carry no effects; every other branch body
    /// keeps the ordinary indirect call. Target resolution is shared with
    /// function-address emission, including concrete generic arguments.
    fn callableSelection(self: *Lowerer, init: ExprId, signature: TypeId) std.mem.Allocator.Error!?[2]FunctionId {
        const at = self.ast.withoutGroups(init);
        if (self.mono.pool.get(signature) != .callable or self.ast.exprTag(at) != .conditional) return null;
        const choice = self.ast.conditional(at);
        if (choice.otherwise == .none or try self.typeAt(choice.cond) == .never) return null;
        var targets: [2]FunctionId = undefined;
        for ([_]ExprId{ choice.then, choice.otherwise }, 0..) |arm, i| {
            var leaf = self.ast.withoutGroups(arm);
            while (self.ast.exprTag(leaf) == .block) {
                const block = self.ast.blockOf(leaf);
                if (self.ast.blockStmts(block).len != 0 or block.tail == .none) return null;
                leaf = self.ast.withoutGroups(block.tail);
            }
            const value = self.calls.functionValueOf(self.typing, leaf) orelse return null;
            if (try self.substituted(value.signature) != signature) return null;
            const declared = switch (value.target) {
                .declared => |decl| decl,
                .closure, .constructor => return null,
            };
            if (self.ast.declIsExtern(declared) or self.ast.declBody(declared) == .none) return null;
            targets[i] = try self.functionTarget(value);
        }
        return targets;
    }

    /// A call reaching an implementation the compiler provides, as the
    /// instruction that implementation is, or null where it reaches a written
    /// one.
    ///
    /// `Comparable.less(a, b)` spelled out over a primitive is the comparison
    /// `a < b` lowers to, and `Steppable.forward(x)` is the checked `x + 1`
    /// that `+` lowers to, `backward` the checked `x - 1` -- so an edge of a
    /// type traps rather than wrapping, under the check the arithmetic already
    /// carries. Such a row
    /// names no declaration, because no Linea body could write one: a `less`
    /// written with `<` would be `Comparable.less` calling itself.
    fn ambientOperation(
        self: *Lowerer,
        id: ExprId,
        sig: DeclId,
        ty: TypeId,
        span: Span,
        args: []const InstId,
    ) std.mem.Allocator.Error!?InstId {
        const rec = self.implOf(id) orelse return null;
        if (!rec.ofATrait()) return null;

        const held = try self.substituted(rec.self_ty);
        const settled = try self.gpa.alloc(TypeId, rec.args.len);
        defer self.gpa.free(settled);
        for (rec.args, 0..) |a, i| settled[i] = try self.substituted(a);

        const row = self.mono.instances.selectedImplementation(DeclId.at(rec.trait), settled, held) orelse return null;
        if (!row.isAmbient()) return null;
        return self.builtInOperation(sig, ty, span, self.opSpan(id), args);
    }

    /// The instruction an operation the compiler provides is: a comparison,
    /// or a step by one checked for overflow at `checked_at`. A direct call
    /// and the body a function value holds are both this.
    fn builtInOperation(
        self: *Lowerer,
        sig: DeclId,
        ty: TypeId,
        span: Span,
        checked_at: Span,
        args: []const InstId,
    ) std.mem.Allocator.Error!?InstId {
        const binary: Inst.Tag = if (sig == (self.library.equals orelse DeclId.none))
            .cmp_eq
        else if (sig == (self.library.less orelse DeclId.none))
            .cmp_lt
        else {
            if (args.len != 1) return null;
            const step: syntax_node.Expr.Tag = if (sig == (self.library.forward orelse DeclId.none))
                .add
            else if (sig == (self.library.backward orelse DeclId.none))
                .sub
            else
                return null;
            const one = try self.emit(.constant, ty, span, .{ .constant = 1 });
            return try self.arithmetic(step, checked_at, ty, span, args[0], one);
        };
        if (args.len != 2) return null;
        return try self.emit(binary, .bool_, span, .{ .binary = .{ .lhs = args[0], .rhs = args[1] } });
    }

    /// A checked constant read by value, at its reference or at a call that
    /// omits the argument it defaults.
    ///
    /// A scalar is its one part, emitted as a value. An aggregate is the
    /// address of its static, which a position taking the value copies out of
    /// as it copies out of any other place.
    fn materializeConstant(self: *Lowerer, value: types_mod.ConstantValue, written: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const ty = self.types().erased(written);
        if (self.isAggregate(ty)) return self.staticAddress(value, ty, span);
        const parts = &self.mono.scratch_parts;
        parts.clearRetainingCapacity();
        try self.layOutConstant(parts, value, ty, 0);
        if (parts.items.len == 0) return self.nothing(ty, span);
        return self.emit(.constant, ty, span, .{ .constant = parts.items[0].value.constant });
    }

    /// The address of a constant's static: the storage every borrow of the
    /// constant, or of a part of it, observes.
    fn staticAddress(self: *Lowerer, value: types_mod.ConstantValue, written: TypeId, span: Span) std.mem.Allocator.Error!InstId {
        const ty = self.types().erased(written);
        return self.emit(.static_addr, ty, span, .{ .static = try self.staticOf(value, ty) });
    }

    /// Where a constant is held at one type, laying it out the first time.
    ///
    /// **Bound:** a constant is laid out once per type it is read at; later
    /// reads find it by hashing the checked value, which for an aggregate is
    /// a handle and for text is its bytes.
    fn staticOf(self: *Lowerer, value: types_mod.ConstantValue, ty: TypeId) std.mem.Allocator.Error!u32 {
        const gpa = self.mono.gpa;
        const key: StaticKey = .{ .value = value, .ty = ty };
        if (self.mono.statics_at.get(key)) |at| return at;

        var parts: std.ArrayList(mir_mod.StaticPart) = .empty;
        defer parts.deinit(gpa);
        try self.layOutConstant(&parts, value, ty, 0);
        // A record's fields arrive in the order its initializer wrote them.
        std.mem.sort(mir_mod.StaticPart, parts.items, {}, struct {
            fn before(_: void, a: mir_mod.StaticPart, b: mir_mod.StaticPart) bool {
                return a.offset < b.offset;
            }
        }.before);

        const at: u32 = @intCast(self.mono.statics.items.len);
        const owned = try parts.toOwnedSlice(gpa);
        errdefer gpa.free(owned);
        try self.mono.statics.append(gpa, .{ .ty = ty, .parts = owned });
        errdefer _ = self.mono.statics.pop();
        try self.mono.statics_at.put(gpa, key, at);
        return at;
    }

    /// The scalar parts of a constant laid out at `offset` within its
    /// containing value: the one layout of a constant's bytes. Each part is
    /// what a store of its type at that offset writes, and a part of no width
    /// is left out.
    fn layOutConstant(
        self: *Lowerer,
        parts: *std.ArrayList(mir_mod.StaticPart),
        value: types_mod.ConstantValue,
        written: TypeId,
        offset: u32,
    ) std.mem.Allocator.Error!void {
        const gpa = self.mono.gpa;
        // A newtype's constant was planned against its representation.
        const ty = self.types().erased(written);
        if (!self.carriesBytes(ty)) return;
        switch (value) {
            .integer => |integer| try parts.append(gpa, .{ .offset = offset, .ty = ty, .value = .{ .constant = integer } }),
            .truth => |truth| try parts.append(gpa, .{ .offset = offset, .ty = ty, .value = .{ .constant = @intFromBool(truth) } }),
            .string => |bytes| {
                const fields = self.types().textFields(ty).?;
                const blob = try self.mono.internBytes(bytes);
                try parts.append(gpa, .{ .offset = offset + fields.at.offset, .ty = fields.at.ty, .value = .{ .bytes = blob } });
                // The decoded length, which is the blob's and not the spelling's.
                try parts.append(gpa, .{ .offset = offset + fields.len.offset, .ty = fields.len.ty, .value = .{ .constant = @intCast(bytes.len) } });
            },
            .aggregate => |id| try self.layOutNode(parts, id, ty, offset),
        }
    }

    fn layOutNode(
        self: *Lowerer,
        parts: *std.ArrayList(mir_mod.StaticPart),
        id: types_mod.constants.ConstantId,
        ty: TypeId,
        offset: u32,
    ) std.mem.Allocator.Error!void {
        const gpa = self.mono.gpa;
        const node_value = self.typing.constant_pool.get(id);
        switch (node_value) {
            .integer => |value| return self.layOutConstant(parts, .{ .integer = value }, ty, offset),
            .truth => |value| return self.layOutConstant(parts, .{ .truth = value }, ty, offset),
            .string => |value| return self.layOutConstant(parts, .{ .string = value }, ty, offset),
            .unit => return,
            else => {},
        }
        const plan = self.typing.constant_materializations.get(.{ .value = id, .ty = ty }).?;
        switch (node_value) {
            .record => |fields| for (fields, plan.fields) |field, ordinal| {
                const index = @intFromEnum(ordinal);
                const at = offset + self.types().fieldOffset(ty, index);
                try self.layOutNode(parts, field.value, self.types().erased(self.types().fieldType(ty, index)), at);
            },
            .array => |values| {
                const element = self.types().erased(self.types().get(ty).array.element);
                const stride = self.types().strideOf(element);
                for (values, 0..) |child, i| try self.layOutNode(parts, child, element, offset + @as(u32, @intCast(stride * i)));
            },
            .variant => |variant| {
                const ordinal = @intFromEnum(plan.variant.?);
                // An enum that fits a register is its tag; a wider one holds
                // its tag in the first word and its payload behind it.
                if (!self.isAggregate(ty)) {
                    try parts.append(gpa, .{ .offset = offset, .ty = ty, .value = .{ .constant = ordinal } });
                    return;
                }
                try parts.append(gpa, .{ .offset = offset, .ty = tag_type, .value = .{ .constant = ordinal } });
                for (variant.payloads, 0..) |child, i| {
                    const field = self.types().erased(self.types().variantFieldType(ty, ordinal, @intCast(i)));
                    try self.layOutNode(parts, child, field, offset + self.types().variantFieldOffset(ty, ordinal, @intCast(i)));
                }
            },
            .integer, .truth, .string, .unit => unreachable,
        }
    }

    fn splicedCallableDefault(self: *Lowerer, signature_type: TypeId, at: usize, span: Span) !InstId {
        const signature = self.typing.get(signature_type).callable;
        const params = self.typing.callableParams(signature);
        if (at >= params.len) return self.poison(span);
        const value = switch (params[at].default) {
            .absent => return self.poison(span),
            .value => |value| value,
        };
        return self.materializeConstant(value, try self.substituted(params[at].ty), span);
    }

    /// `Name(e)` or `Name?(e)`, a newtype's construction.
    ///
    /// The checker already proved this program, so `Name(e)` erases to the
    /// operand -- no wrapper, no instruction where the representation is
    /// already the same. `Name?(e)` is the one form whose proof waits for the
    /// value the program supplies, so it is the one form still tested here:
    /// the same two comparisons `boundsGuard` gives a range arm's guard,
    /// feeding a branch into `Some` or `None` instead of into a match arm.
    fn newtypeConstruct(
        self: *Lowerer,
        id: ExprId,
        ty: TypeId,
        span: Span,
        dest: ?*Dest,
    ) std.mem.Allocator.Error!InstId {
        const c = self.ast.call(id);
        if (c.args.len != 1) return self.poison(span);
        const operand = c.args[0];

        if (!self.ast.callFallible(id)) return self.exprInto(operand, dest);

        // The callee's own recorded type, read back rather than re-derived
        // from the declaration: the checker already settled which newtype
        // this is, through the same lookup a conversion's callee answers.
        const newtype = try self.typeAt(c.callee);
        const bounds = self.types().refinementOf(newtype);
        const value = try self.expr(operand);
        if (try self.typeAt(operand) == .never) return value;
        const lo = try self.emit(.constant, newtype, span, .{ .constant = bounds.lo });
        const hi = try self.emit(.constant, newtype, span, .{ .constant = bounds.hi });

        const some_block = try self.b.addBlock();
        const none_block = try self.b.addBlock();
        const exit = try self.b.addBlock();
        const yields = ty != .unit and ty != .poison;
        const slot = if (yields) try self.b.addLocal(ty, .value) else null;

        // Both ends are inclusive whichever way the refinement was spelled,
        // the same folding the declaration already settled.
        try self.boundsGuard(value, lo, hi, .cmp_le, some_block, none_block, span);

        self.block = some_block;
        const some_v = try self.buildVariant(ty, self.types().successVariantOf(ty).?, .{ .values = &.{value} }, span, null);
        if (slot) |s| try self.storeLocal(s, ty, span, some_v);
        _ = try self.b.setTerminator(self.block, .{ .tag = .jump, .ty = .unit, .span = span, .data = .{ .target = exit } });

        self.block = none_block;
        const none_v = try self.buildVariant(ty, self.types().failureVariantOf(ty).?, .{ .values = &.{} }, span, null);
        if (slot) |s| try self.storeLocal(s, ty, span, none_v);
        _ = try self.b.setTerminator(self.block, .{ .tag = .jump, .ty = .unit, .span = span, .data = .{ .target = exit } });

        self.block = exit;
        if (slot) |s| return self.loadLocal(s, ty, span);
        return self.poison(span);
    }

    /// `Display.fmt(s, &w)` where `s` is an interpolation: render its pieces.
    ///
    /// Null where this call is anything else, so the ordinary path is the one
    /// every other call takes and this reads as the exception it is.
    ///
    /// The pieces alternate text and value, and each is rendered by the same
    /// `Display` the program would have reached had it written the calls out --
    /// so a value inside a literal renders exactly as it does outside one, and
    /// there is no second answer to what a type looks like.
    fn rendersInterpolation(self: *Lowerer, id: ExprId, sig: DeclId) std.mem.Allocator.Error!?InstId {
        const rec = self.implOf(id) orelse return null;
        // A call naming an inherent member goes through no trait, so it is not
        // the rendering call this intercepts.
        if (!rec.ofATrait()) return null;
        const held = try self.substituted(rec.self_ty);
        const trait = DeclId.at(rec.trait);
        // The checker's own predicate: it admits a literal spliced into a
        // rendering call, and this intercepts the calls it admitted. Asking
        // only about the type would intercept a call through some other trait
        // an interpolation was never blessed for.
        {
            const view = self.types();
            if (!rendersDisplayItself(&view, self.library.formatting.display.trait, held, trait)) return null;
            if (sig != (self.library.formatting.display.member orelse return null)) return null;
        }

        const span = self.ast.exprSpan(id);
        const normal = self.calls.callOf(self.typing, id) orelse return null;
        const written = normal.args;
        if (written.len != 2) return try self.poison(span);

        // Rendering takes the value and the writer from the call itself, so
        // neither may be a parameter the call omitted: there is no expression
        // to lower where a hole sits, and this path has no splice to make one.
        // The signature it intercepts declares no default, which is what keeps
        // that from happening rather than an assumption about what a call
        // looks like.
        if (written[0] == ExprId.none or written[1] == ExprId.none) return try self.poison(span);

        // Both evaluated once and before any piece is written: a writer named
        // by an expression with an effect must not have it once per piece.
        const value = try self.expr(written[0]);
        const writer = try self.expr(written[1]);

        // What the intercepted call settled the rendering signature's own type
        // parameters to, read from the checker rather than assembled here: it
        // decided them, and a second reckoning of how many there are and which
        // is the writer is a mangled symbol that agrees only by luck.
        //
        // Every piece's call settles the same ones. `Self` is what differs
        // between them, and `Self` is not among these.
        const settled = try self.argsOfCall(id);
        defer self.gpa.free(settled);

        // What the intercepted call answers, which is what each piece answers:
        // the signature's return is written in terms of the arguments above,
        // and they are the same at every piece and at the literal.
        const answer = try self.typeAt(id);
        return try self.renderPieces(value, held, writer, settled, answer, span);
    }

    /// Write each piece of the interpolation `value`, of type `held`, to
    /// `writer`, stopping at the first failure, and answer what the rendering
    /// call answers. A piece that is itself an interpolation rendered through
    /// `Display` has no implementation to call, so its pieces are written in
    /// its place; the recursion is as deep as the literals are nested.
    fn renderPieces(
        self: *Lowerer,
        value: InstId,
        held: TypeId,
        writer: InstId,
        settled: []const TypeId,
        answer: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const view = self.types();
        const ok = view.successVariantOf(answer) orelse return try self.poison(span);

        const slot = try self.b.addLocal(answer, .value);
        const merge = try self.b.addBlock();

        const pieces = self.types().fieldCount(held);
        const formats = self.types().interpolationFormats(held);
        var i: u32 = 0;
        while (i < pieces) : (i += 1) {
            const field = self.types().fieldType(held, i);
            const piece = self.types().interpolationValue(held, i);
            var at = try self.fieldAddr(value, field, self.types().fieldOffset(held, i), span);
            // A borrowed piece renders the value it observes.
            if (self.types().interpolationBorrows(held, i)) at = try self.observeLayers(try self.readThrough(at, field, span), field, 1, span);
            // A part wider than a register is reached through its address, and
            // a scalar is loaded -- the same choice every other argument makes,
            // and made here for the same reason.
            const arg = if (self.isAggregate(piece)) at else try self.readThrough(at, piece, span);
            const target = if (i % 2 == 0) self.library.formatting.display else self.library.formatting.target(formats[i / 2]);
            const r = if (i % 2 == 1 and formats[i / 2].laysOut())
                try self.layOutOne(formats[i / 2], piece, arg, writer, settled, answer, self.types().fieldType(held, 0), span)
            else if (self.rendersNested(piece, target))
                try self.renderPieces(arg, piece, writer, settled, answer, span)
            else
                try self.renderOne(target, piece, arg, writer, settled, answer, span);

            const arms = try self.branchOnSuccess(answer, r, ok, span);

            // The piece's answer and the literal's are one type, so a failure
            // is stored as it stands rather than taken apart and rebuilt.
            self.block = arms.leaves;
            try self.storeLocal(slot, answer, span, r);
            _ = try self.b.setTerminator(self.block, .{
                .tag = .jump,
                .ty = .unit,
                .span = span,
                .data = .{ .target = merge },
            });

            self.block = arms.continues;
        }

        // Every piece written, so the literal answers with the success the
        // trait declares.
        const done = try self.buildVariant(answer, ok, .{ .values = &.{} }, span, null);
        try self.storeLocal(slot, answer, span, done);
        _ = try self.b.setTerminator(self.block, .{
            .tag = .jump,
            .ty = .unit,
            .span = span,
            .data = .{ .target = merge },
        });

        self.block = merge;
        return try self.loadLocal(slot, answer, span);
    }

    /// Answer true when a piece is an interpolation rendered through
    /// `Display`, which the checker admits without an implementation.
    fn rendersNested(self: *Lowerer, piece: TypeId, target: FormattingTarget) bool {
        const trait = target.trait orelse return false;
        const view = self.types();
        return rendersDisplayItself(&view, self.library.formatting.display.trait, piece, trait);
    }

    fn observeLayers(self: *Lowerer, argument: InstId, from: TypeId, observations: u32, span: Span) !InstId {
        var value = argument;
        var held = from;
        for (0..observations) |step| {
            held = self.types().get(held).borrow.referent;
            const address = try self.emit(.observe, held, span, .{ .unary = value });
            if (step + 1 == observations) return address;
            value = try self.readThrough(address, held, span);
        }
        return value;
    }

    fn observationArgument(self: *Lowerer, argument: InstId, from: TypeId, receiver: TypeId, stable_address: bool, span: Span) !InstId {
        var held = from;
        var observations: u32 = 0;
        while (held != receiver) {
            held = self.types().get(held).borrow.referent;
            observations += 1;
        }
        if (observations == 0) return argument;
        const address = try self.observeLayers(argument, from, observations, span);
        return if (stable_address) address else self.readThrough(address, receiver, span);
    }

    /// Converts a whole-`Self` argument to what a selected implementation
    /// takes: it reads through the choice's observations, then, where the
    /// array those reach answers through its `Slice` view, builds that view of
    /// the same elements.
    fn receiverArgument(self: *Lowerer, argument: InstId, from: TypeId, choice: types_mod.ImplementationChoice, span: Span) !InstId {
        if (choice.view == .poison) return self.observationArgument(argument, from, choice.receiver, false, span);
        const address = if (choice.observations > 0)
            try self.observeLayers(argument, from, choice.observations, span)
        else
            try self.valueAddress(argument, choice.receiver, span);
        return self.arrayView(address, choice.receiver, choice.view, span);
    }

    /// Returns where a value of `ty` is held. An aggregate already is its
    /// address, and a register value is stored in a slot of its own first.
    fn valueAddress(self: *Lowerer, value: InstId, ty: TypeId, span: Span) !InstId {
        if (self.isAggregate(ty)) return value;
        const local = try self.b.addLocal(ty, .value);
        try self.storeLocal(local, ty, span, value);
        return self.emit(.addr_of, ty, span, .{ .local = local });
    }

    /// Builds the `Slice` that observes every element of the array at `address`.
    fn arrayView(self: *Lowerer, address: InstId, array: TypeId, view: TypeId, span: Span) !InstId {
        const bits = try self.emit(.address_bits, .u64, span, .{ .unary = address });
        const count = try self.emit(.constant, .u64, span, .{ .constant = self.types().get(array).array.count });
        return self.buildSpan(view, bits, count, span);
    }

    /// Lay out one value through the library function discovery chose for its
    /// type, passing the parts its spec wrote. The spec is a fact about the
    /// literal, so each part is a constant here; what the parts do to the
    /// value is the library's alone.
    fn layOutOne(
        self: *Lowerer,
        format: syntax_node.InterpolationFormat,
        piece: TypeId,
        value: InstId,
        writer: InstId,
        settled: []const TypeId,
        answer: TypeId,
        str_ty: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const layout = self.library.layouts.of(format, self.types().layoutShape(DeclId.none, piece), piece);
        if (layout.decl == DeclId.none) return self.poison(span);
        const args = try layout.arguments(self.gpa, piece, settled);
        defer self.gpa.free(args);

        var fill: [4]u8 = undefined;
        const fill_len = std.unicode.utf8Encode(format.fill, &fill) catch unreachable;
        // The alignment's ordinal is none, left, right, center, which is the
        // order the library's `spec_of` reads 0 through 3 in.
        const alignment: u8 = @intFromEnum(format.alignment);
        const parts = [_]InstId{
            value,
            try self.strValue(try self.mono.internBytes(fill[0..fill_len]), str_ty, span, null),
            try self.emit(.constant, .u8, span, .{ .constant = alignment }),
            try self.emit(.constant, .bool_, span, .{ .constant = @intFromBool(format.plus) }),
            try self.emit(.constant, .bool_, span, .{ .constant = @intFromBool(format.zero) }),
            try self.emit(.constant, .u64, span, .{ .constant = format.width }),
            try self.emit(.constant, .bool_, span, .{ .constant = @intFromBool(format.has_precision) }),
            try self.emit(.constant, .u64, span, .{ .constant = format.precision }),
            // The hexadecimal choice's ordinal is none, lower, upper, which is
            // the order `spec_of` reads 0 through 2 in.
            try self.emit(.constant, .u8, span, .{ .constant = @intFromEnum(format.hex) }),
            writer,
        };
        return self.callLibrary(layout.decl, args, &parts, answer, span);
    }

    /// One piece of an interpolation, through the implementation its own type
    /// answers with -- so a value inside a literal renders exactly as it does
    /// outside one, and there is no second answer to what a type looks like.
    ///
    /// The implementation is found by the lookup the checker admitted the piece
    /// with. A piece with none is reported rather than emitted as poison: the
    /// call's result is read and copied out, so a poisoned one is a program the
    /// compiler accepted reading a value nothing computed.
    fn renderOne(
        self: *Lowerer,
        target: FormattingTarget,
        piece: TypeId,
        value: InstId,
        writer: InstId,
        settled: []const TypeId,
        answer: TypeId,
        span: Span,
    ) std.mem.Allocator.Error!InstId {
        const trait = target.trait orelse return self.poison(span);
        const signature = target.member orelse return self.poison(span);
        const selected = self.mono.instances.selectedImplementation(trait, &.{}, piece) orelse return self.poison(span);
        const impl = selected.decl;
        const member = (self.typing.supply_index.memberOf(impl, signature) orelse
            return self.poison(span));

        const choice = self.mono.instances.selectedChoice(trait, &.{}, piece);
        const held = instantiate_mod.receiverKeying(self.ast, impl, choice.implementedFor());
        const callee = self.mono.idFor(member, settled, held, choice.impl_args);
        const argument = try self.receiverArgument(value, piece, choice, span);
        return self.directCall(answer, span, callee, &.{ argument, writer });
    }

    /// Which declaration a call runs.
    ///
    /// A call that names a function runs that function. A call through a trait
    /// names a signature, which supplies no body, and runs the member of the
    /// implementation `Self` settled to -- so what a call names and what it
    /// runs are two questions. One optional answer confused them: absent stood
    /// both for a call that goes nowhere near a trait and for a trait call
    /// whose implementation was not found, and the caller had no way to treat
    /// the second as the mistake it is.
    const Callee = union(enum) {
        /// Not a call through a trait. The declaration named carries the body.
        named,
        /// A call through a trait: the implementation's member it runs, and
        /// the receiver that member runs for.
        implemented: struct { member: DeclId, held: TypeId, impl_args: []const TypeId },
        generated: types_mod.BodyOrigin,
    };

    /// The receiver keying and implementation arguments discovery recorded for
    /// a member of an inherent implementation at a concrete receiver. A member
    /// discovery found no head for was never interned, so reaching one here is
    /// a defect rather than a plain call.
    fn inherentHead(self: *Lowerer, member: DeclId, held: TypeId) instantiate_mod.InherentHead {
        const recorded: instantiate_mod.RecordedArguments = .{ .typing = &self.mono.instances.typing };
        return instantiate_mod.inherentHead(self.ast, self.typing, member, held, recorded) catch unreachable orelse
            @panic("compiler defect: an inherent member has no implementation, or its arguments were not discovered");
    }

    /// The body a call through a trait runs, at this instantiation.
    ///
    /// Concrete types identify the selection discovery recorded. This lookup
    /// reads that answer without searching or rechecking implementations.
    fn calleeOf(self: *Lowerer, id: ExprId, sig: DeclId) !Callee {
        return self.calleeThrough(self.implOf(id), sig, false);
    }

    /// The body `sig` names through what the checker recorded for its head,
    /// at this instantiation. A call and a function value naming one
    /// declaration read their body here; a `value` holds a generated body for
    /// an operation the compiler provides, where a call is that operation.
    fn calleeThrough(self: *Lowerer, record: ?types_mod.CallImpl, sig: DeclId, value: bool) !Callee {
        const rec = record orelse return .named;

        const held = try self.substituted(rec.self_ty);

        // A call naming a member of an inherent implementation names the body
        // outright: there is no trait to look one up through, and what the
        // record carries is which member of the family the receiver settled.
        if (!rec.ofATrait()) {
            const head = self.inherentHead(sig, held);
            return .{ .implemented = .{ .member = sig, .held = head.held, .impl_args = head.impl_args } };
        }

        // The arguments the call settled, read through this instantiation for
        // the reason `Self` is: a body generic on its own account settles a
        // trait's argument to one of its own parameters, and which type that
        // is is not known until the body is instantiated.
        const args = try self.gpa.alloc(TypeId, rec.args.len);
        defer self.gpa.free(args);
        for (rec.args, 0..) |a, i| args[i] = try self.substituted(a);

        const trait = DeclId.at(rec.trait);
        const choice = self.mono.instances.selectedChoice(trait, args, held);
        const found = if (value)
            instantiate_mod.valueMember(self.ast, &self.mono.instances.typing, choice, trait, sig)
        else
            instantiate_mod.selectedMember(self.ast, &self.mono.instances.typing, choice, sig);
        const selected = found orelse
            @panic("compiler defect: selected implementation has no member body");
        return switch (selected.body) {
            .declaration => |member| .{ .implemented = .{ .member = member, .held = selected.self_ty, .impl_args = selected.impl_args } },
            .closure_release, .built_in, .viewed => .{ .generated = selected.body },
            .closure, .constructor, .erased_entry, .erased_settle => unreachable,
        };
    }

    /// What the checker settled a call's `Self` to, or nothing where the call
    /// does not go through a trait.
    fn implOf(self: *const Lowerer, id: ExprId) ?types_mod.CallImpl {
        return (self.calls.callOf(self.typing, id) orelse return null).selection.implementation;
    }

    /// The type arguments a call was settled with, read through the
    /// instantiation this body is being lowered as.
    fn argsOfCall(self: *Lowerer, id: ExprId) ![]const TypeId {
        const args = (self.calls.callOf(self.typing, id) orelse
            return self.gpa.alloc(TypeId, 0)).selection.own_args;

        const out = try self.gpa.alloc(TypeId, args.len);
        errdefer self.gpa.free(out);
        for (args, 0..) |a, i| out[i] = try self.substituted(a);
        return out;
    }

    fn check(self: *Lowerer, value: InstId, ty: TypeId, span: Span, kind: TrapKind) !InstId {
        return self.emit(.check, ty, span, .{ .check = .{ .value = value, .kind = kind } });
    }

    /// How wide one raw access is, and what that decides.
    ///
    /// Two widths and not a number, because the width decides three things at
    /// once -- how far the bound reaches, what the value's type is, and whether
    /// there is an alignment to check -- and a caller passing 8 could not be
    /// stopped from passing 3.
    const Access = enum {
        /// Eight bytes at an eight-aligned offset, which is what a buffer holds
        /// a machine word in.
        wide,
        /// One byte at any offset. Every offset is aligned for a byte, so the
        /// alignment check is not merely trivially true here -- it is absent,
        /// and a byte store cannot report a misalignment that has no meaning.
        byte,

        fn width(self: Access) u64 {
            return switch (self) {
                .wide => checked_access_width,
                .byte => 1,
            };
        }

        fn valueType(self: Access) TypeId {
            return switch (self) {
                .wide => .u64,
                .byte => .u8,
            };
        }
    };

    /// A raw access of one width: the checks, then the store where a
    /// value arrives and the load where none does.
    ///
    /// The bound compares `i + 8` against the length, never the offset against
    /// `len - 8`: the subtraction underflows on a buffer shorter than the
    /// width, and would need a third check to say so. The sum's own overflow
    /// is the check every add gets. The final add is not checked, because the
    /// offset was just proved to land inside the region the view describes,
    /// and an address inside valid storage does not wrap. Bounds established
    /// by the caller may make the generated checks redundant for the optimiser.
    ///
    /// The bound is asked before the alignment, so an offset that is both
    /// past the end and off its width reports out of bounds -- one order,
    /// stated here because either would be defensible and a reader deserves
    /// to know which was chosen.
    fn checkedAccess(self: *Lowerer, how: Access, args: [3]InstId, value: ?InstId, span: Span) !InstId {
        var access = try self.checkedAddress(how.width(), how.width(), args, span);
        const ty = how.valueType();
        if (value) |v| {
            access.value = v;
            _ = try self.b.addRawAccess(self.block, .store_raw, ty, span, access);
            return self.nothing(.unit, span);
        }
        return self.b.addRawAccess(self.block, .load_raw, ty, span, access);
    }

    fn checkedStorageAddress(self: *Lowerer, ty: TypeId, args: [3]InstId, span: Span) !InstId {
        const layout = self.types().layoutOf(ty);
        const access = try self.checkedAddress(layout.size, layout.alignment, args, span);
        return self.b.addRawAccess(self.block, .storage_addr, ty, span, access);
    }

    /// The byte extent and alignment of an access share one checked address.
    /// Dimensions come from a scalar operation or the settled element layout.
    fn checkedAddress(self: *Lowerer, width: u64, alignment: u64, args: [3]InstId, span: Span) !Inst.RawAccess {
        const at, const len, const offset = args;
        const wide = try self.emit(.constant, .u64, span, .{ .constant = width });
        const end = try self.emit(.add, .u64, span, .{ .binary = .{ .lhs = offset, .rhs = wide } });
        const overflow = try self.check(end, .u64, span, .overflow);
        const fits = try self.emit(.cmp_le, .bool_, span, .{ .binary = .{ .lhs = end, .rhs = len } });
        const bounds = try self.check(fits, .bool_, span, .index_out_of_bounds);
        var alignment_check = InstId.none;
        if (alignment > 1) {
            const align_value = if (alignment == width) wide else try self.emit(.constant, .u64, span, .{ .constant = alignment });
            const remainder = try self.emit(.rem, .u64, span, .{ .binary = .{ .lhs = offset, .rhs = align_value } });
            const zero = try self.emit(.constant, .u64, span, .{ .constant = 0 });
            const aligned = try self.emit(.cmp_eq, .bool_, span, .{ .binary = .{ .lhs = remainder, .rhs = zero } });
            alignment_check = try self.check(aligned, .bool_, span, .misaligned_access);
        }
        const address = try self.emit(.add, .u64, span, .{ .binary = .{ .lhs = at, .rhs = offset } });
        return .{
            .address = address,
            .length = len,
            .overflow_check = overflow,
            .bounds_check = bounds,
            .alignment_check = alignment_check,
        };
    }

    fn literal(self: *Lowerer, id: ExprId, ty: TypeId) !InstId {
        const value = self.typing.literalValue(id) orelse
            @panic("compiler defect: checked literal has no value");
        const bits: i128 = switch (value) {
            .integer => |integer| integer,
            .float => |float| @as(u64, @bitCast(float)),
        };
        return self.emit(.constant, ty, self.ast.exprSpan(id), .{ .constant = bits });
    }

    fn poison(self: *Lowerer, span: Span) !InstId {
        return self.emit(.constant, .poison, span, .{ .constant = 0 });
    }

    /// A trap names the operator rather than the whole expression, so a failure
    /// deep in a nested expression points at the operation that failed.
    fn opSpan(self: *Lowerer, id: ExprId) Span {
        return self.ast.tokenSpan(self.ast.exprMain(id));
    }
};

/// Lowers `text` as a program checked against no library.
fn lowerSource(gpa: std.mem.Allocator, text: []const u8) !Module {
    return lowerSourceAs(gpa, text, .no_prelude);
}

/// Lowers `text` as a program whose prelude is its own module, so a program
/// declaring `Tuple2` itself is one whose tuple syntax names that declaration.
fn lowerSourceAsPrelude(gpa: std.mem.Allocator, text: []const u8) !Module {
    return lowerSourceAs(gpa, text, .own_prelude);
}

fn lowerSourceAs(gpa: std.mem.Allocator, text: []const u8, prelude: enum { no_prelude, own_prelude }) !Module {
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    defer resolved.deinit(gpa);
    if (prelude == .own_prelude) {
        resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
        resolved.resolution.tuple_decls = resolve_mod.tupleDeclsIn(&resolved.expanded.ast, resolved.resolution.prelude);
    }
    var typing = try typecheckTree(gpa, &resolved, &sink);
    var disposals = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
    defer disposals.deinit(gpa);
    return (try lowerTree(gpa, &resolved, &typing, &disposals, &sink, .program)) orelse error.SourceRejected;
}

test "a tuple literal writes each component through its field address" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var module = try lowerSourceAsPrelude(gpa,
        \\@copyable
        \\pub struct Tuple2[A, B] { _0: A, _1: B }
        \\fn main() -> UInt8 {
        \\    let pair: (UInt8, UInt8) = (1, 2)
        \\    let (a, b) = pair
        \\    a + b - 3
        \\}
    );
    defer module.deinit(gpa);
    // The literal writes `_0` and `_1` through one field address each, the
    // pattern reads them back through two more, and nothing is poisoned.
    var field_addresses: usize = 0;
    for (module.functions) |function| {
        for (function.insts.items(.tag), function.insts.items(.ty)) |tag, ty| {
            try testing.expect(!(tag == .constant and ty == .poison));
            if (tag == .field_addr) field_addresses += 1;
        }
    }
    try testing.expectEqual(@as(usize, 4), field_addresses);
}

test "a tuple pattern binds each component by position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var module = try lowerSourceAsPrelude(gpa,
        \\@copyable
        \\pub struct Tuple2[A, B] { _0: A, _1: B }
        \\fn pair() -> (UInt8, UInt8) { Tuple2[UInt8, UInt8] { _0 = 1, _1 = 2 } }
        \\fn main() -> UInt8 {
        \\    let (a, b) = pair()
        \\    a + b
        \\}
    );
    defer module.deinit(gpa);
    // Each binder reads its own field through the tuple's address: two field
    // addresses to take the pair apart, beside the two that built it, and
    // nothing is left to poison.
    var field_addresses: usize = 0;
    for (module.functions) |function| {
        for (function.insts.items(.tag), function.insts.items(.ty)) |tag, ty| {
            try testing.expect(!(tag == .constant and ty == .poison));
            if (tag == .field_addr) field_addresses += 1;
        }
    }
    try testing.expectEqual(@as(usize, 4), field_addresses);
}

test "a lambda parameter's tuple pattern is taken apart where the closure begins" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var module = try lowerSourceAsPrelude(gpa,
        \\@copyable
        \\pub struct Tuple2[A, B] { _0: A, _1: B }
        \\fn apply[F: fn(read pair: (UInt8, UInt8)) -> UInt8](pair: (UInt8, UInt8), take: F) -> UInt8 {
        \\    take(pair)
        \\}
        \\fn main() -> UInt8 {
        \\    apply((1, 2), |(a, b)| a + b)
        \\}
    );
    defer module.deinit(gpa);
    // `main` writes the literal's two components and the closure reads its
    // parameter's two back through field addresses of their own, so exactly
    // two functions hold two and nothing is poisoned.
    var holding_two: usize = 0;
    for (module.functions) |function| {
        var field_addresses: usize = 0;
        for (function.insts.items(.tag), function.insts.items(.ty)) |tag, ty| {
            try testing.expect(!(tag == .constant and ty == .poison));
            if (tag == .field_addr) field_addresses += 1;
        }
        if (field_addresses == 2) holding_two += 1;
    }
    try testing.expectEqual(@as(usize, 2), holding_two);
}

test "tree pipeline retains generated derive members" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var module = try lowerSource(gpa,
        \\@derive(Structural)
        \\struct Mark {}
        \\
        \\trait Structural {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let m: Mark = .{}
        \\    m.value()
        \\}
    );
    defer module.deinit(gpa);

    var generated = false;
    for (0..module.functions.len) |i| {
        if (std.mem.indexOf(u8, module.nameOf(.at(@intCast(i))), "value") != null) generated = true;
    }
    try testing.expect(generated);
}

test "type representations separate computation from storage and cover the sealed pool" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\type Meters = UInt64
        \\
        \\fn main() -> UInt8 {
        \\    let m = Meters(7)
        \\    let Meters(n) = m
        \\    UInt8(n)
        \\}
    );
    defer module.deinit(gpa);

    try testing.expectEqual(module.types.pool.len, module.representations.len());
    try testing.expectEqual(
        mir_mod.TypeRepresentation{
            .computation = .{ .integer = .unsigned },
            .storage = .{ .integer = .{ .signedness = .unsigned, .bits = 8 } },
        },
        module.representationOf(.u8),
    );
    try testing.expectEqual(
        mir_mod.TypeRepresentation{ .computation = .boolean, .storage = .boolean },
        module.representationOf(.bool_),
    );
    try testing.expectEqual(
        mir_mod.TypeRepresentation{ .computation = .{ .float = 64 }, .storage = .{ .float = 64 } },
        module.representationOf(.f64),
    );
    try testing.expectEqual(
        mir_mod.TypeRepresentation{ .computation = .{ .float = 32 }, .storage = .{ .float = 32 } },
        module.representationOf(.f32),
    );

    var meters = TypeId.poison;
    for (0..module.types.pool.len) |i| {
        const ty = TypeId.at(@intCast(i));
        if (std.mem.eql(u8, module.types.nameOf(ty), "Meters")) {
            meters = ty;
            break;
        }
    }
    try testing.expect(meters != .poison);
    try testing.expectEqual(module.representationOf(.u64), module.representationOf(meters));
}

test "result and slot roles survive lowering" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\struct Cell { value: UInt8 }
        \\fn make() -> Cell { .{ value = 9 } }
        \\
        \\fn replace(inout x: UInt8) {
        \\    x = 7
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    var x: UInt8 = 1
        \\    let _ = make()
        \\    replace(&x)
        \\    x
        \\}
    );
    defer module.deinit(gpa);

    var saw_address = false;
    var saw_field_address = false;
    var saw_unit_value = false;
    for (module.functions) |*f| {
        try testing.expectEqual(f.locals.len, f.slot_roles.len);
        for (f.slot_roles) |role| {
            if (role == .managed_address) saw_address = true;
        }
        for (0..f.insts.len) |i| {
            const id = InstId.at(@intCast(i));
            switch (f.tagOf(id)) {
                .addr_of, .field_addr => {
                    try testing.expectEqual(mir_mod.ResultRole.managed_address, f.resultRoleOf(id));
                    saw_address = true;
                    if (f.tagOf(id) == .field_addr) {
                        try testing.expectEqual(TypeId.u8, f.typeOf(id));
                        saw_field_address = true;
                    }
                },
                .store, .store_indirect, .store_raw, .copy_value, .move_value, .ret, .jump, .branch, .trap => try testing.expectEqual(mir_mod.ResultRole.none, f.resultRoleOf(id)),
                .call => {
                    const want: mir_mod.ResultRole = if (module.returnsIndirectly(f.callOf(id).func)) .managed_address else .value;
                    try testing.expectEqual(want, f.resultRoleOf(id));
                    if (want == .managed_address) saw_address = true;
                },
                else => {},
            }
            if (f.resultRoleOf(id) == .value and f.typeOf(id) == .unit) saw_unit_value = true;
        }
    }
    try testing.expect(saw_address);
    try testing.expect(saw_field_address);
    try testing.expect(saw_unit_value);
}

test "a width only a concrete instantiation reaches is held to the limit" {
    // The checker sees `P[T]` once, in terms of a parameter; discovery reaches
    // one concrete type per level. Its completed pool is where all their
    // widths can be checked before a layout table is projected for emission.
    const gpa = testing.allocator;

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try text.appendSlice(gpa, "enum P[T] { Deep(T, T, T, T, T, T, T, T), Nothing }\n");
    // Each level is eight times the last, so ten of them cross what a layout
    // records and nine do not.
    for (1..11) |i| {
        try text.print(gpa, "fn l{d}[T: Discardable](sink _v: T) -> UInt8 {{ let w: P[T] = .Nothing; ", .{i});
        if (i == 10) {
            try text.appendSlice(gpa, "let _x = w; 0 }\n");
        } else {
            try text.print(gpa, "l{d}(w) }}\n", .{i + 1});
        }
    }
    try text.appendSlice(gpa, "fn main() -> UInt8 { let n: UInt64 = 1; l1(n) }\n");

    const source: Source = .{ .path = "t.lin", .text = text.items };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var res = try resolveTree(gpa, &ast, &sink);
    defer res.deinit(gpa);
    var typing = try typecheckTree(gpa, &res, &sink);
    defer typing.deinit(gpa);

    // Nothing the checker was asked about crosses: the widths that do are the
    // ones the program reached without writing.
    try testing.expect(!sink.hasErrors());

    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer disposals.deinit(gpa);
    var module: ?Module = try lowerTree(gpa, &res, &typing, &disposals, &sink, .program);
    defer if (module) |*m| m.deinit(gpa);
    try testing.expect(module == null);

    // One mistake, one diagnostic: the level the width crosses at, not the
    // chain that carried it there.
    try testing.expectEqual(@as(usize, 1), sink.list.items.len);
    try testing.expectEqual(@as(?Code, .l_size), sink.list.items[0].code);
}

fn countTag(mir: *const Mir, tag: Inst.Tag) usize {
    var n: usize = 0;
    for (mir.insts.items(.tag)) |t| {
        if (t == tag) n += 1;
    }
    return n;
}

fn lowerOnly(gpa: std.mem.Allocator, ctx: struct {
    disposals: *const DisposalPlan,
    resolved: *const resolve_mod.ResolvedTree,
    typing: *const Typing,
    /// On the caller's arena rather than the failing allocator: what this test
    /// varies is what lowering owns when an allocation fails, and a sink that
    /// failed to grow would be a different failure.
    sink: *Sink,
}) !void {
    var m = (try lowerTree(gpa, ctx.resolved, ctx.typing, ctx.disposals, ctx.sink, .program)) orelse return error.SourceRejected;
    m.deinit(gpa);
}

test "the composed instance and lowering path gives back partial work" {
    // Every other test here asks what the composed path owns when it succeeds.
    // This varies every allocation so names, instance keys, types, and emitted
    // functions are each checked on their partial-failure paths.
    const gpa = testing.allocator;
    const source: Source = .{ .path = "t.lin", .text =
        \\struct Cell[T] {
        \\    v: T,
        \\}
        \\
        \\fn wrap[T: Copyable](x: T) -> Cell[T] {
        \\    .{ v = copy(x) }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1
        \\    let c = wrap(a)
        \\    c.v
        \\}
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var res = try resolveTree(gpa, &ast, &sink);
    defer res.deinit(gpa);
    var typing = try typecheckTree(gpa, &res, &sink);
    defer typing.deinit(gpa);

    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer disposals.deinit(gpa);
    try testing.checkAllAllocationFailures(gpa, lowerOnly, .{.{
        .disposals = &disposals,
        .resolved = &res,
        .typing = &typing,
        .sink = &sink,
    }});
}

test "an instantiated type's name is owned by whoever keeps it" {
    // The concrete Cell is local to a generic body: discovery creates its
    // name, and the returned module must retain it after discovery is gone.
    const gpa = testing.allocator;
    const source: Source = .{ .path = "t.lin", .text =
        \\struct Cell[T] {
        \\    v: T,
        \\}
        \\
        \\fn wrap[T: Copyable](x: T) -> UInt8 {
        \\    let c: Cell[T] = .{ v = copy(x) }
        \\    let _ = c
        \\    0
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1
        \\    wrap(a)
        \\}
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var res = try resolveTree(gpa, &ast, &sink);
    defer res.deinit(gpa);
    var typing = try typecheckTree(gpa, &res, &sink);
    defer typing.deinit(gpa);

    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer disposals.deinit(gpa);
    var module = (try lowerTree(gpa, &res, &typing, &disposals, &sink, .program)) orelse return error.SourceRejected;
    defer module.deinit(gpa);

    var found = false;
    for (module.types.pool, 0..) |_, at| {
        const ty: TypeId = @enumFromInt(at);
        if (std.mem.eql(u8, module.types.nameOf(ty), "Cell[UInt8]")) found = true;
    }
    try testing.expect(found);
}

test "the module owns copied instance symbols" {
    // Discovery interns two same-typed calls as one instance. Emission copies
    // the retained symbols into the module, so the pass owner and the module
    // can both be destroyed without sharing an allocation.
    const gpa = testing.allocator;
    const source: Source = .{ .path = "t.lin", .text =
        \\fn ident[T: Copyable](v: T) -> T {
        \\    copy(v)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1
        \\    let b: UInt8 = 2
        \\    ident(a) + ident(b)
        \\}
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var res = try resolveTree(gpa, &ast, &sink);
    defer res.deinit(gpa);
    var typing = try typecheckTree(gpa, &res, &sink);
    defer typing.deinit(gpa);

    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer disposals.deinit(gpa);
    var module = (try lowerTree(gpa, &res, &typing, &disposals, &sink, .program)) orelse return error.SourceRejected;
    defer module.deinit(gpa);

    // Two calls at one type are one function.
    try testing.expectEqual(@as(usize, 2), module.functions.len);
}

test "lowering emits the discovered instance set and order" {
    const source: Source = .{ .path = "t.lin", .text =
        \\trait Echo {
        \\    fn echo(x: Self) -> Self
        \\}
        \\
        \\impl Echo for UInt8 {
        \\    fn echo(x: Self) -> Self { x }
        \\}
        \\
        \\struct Box[T: Copyable] { value: T }
        \\
        \\impl[T: Copyable] Box[T] {
        \\    fn take(box: Box[T]) -> T { copy(box.value) }
        \\}
        \\
        \\fn ident[T: Copyable](x: T) -> T { copy(x) }
        \\fn bounded[T: Echo](x: T) -> T { Echo.echo(x) }
        \\fn recurse[T: Copyable](x: T, n: UInt8) -> T {
        \\    if n == 0 { copy(x) } else { recurse(x, n - 1) }
        \\}
        \\fn later[T: Copyable](_x: T) {}
        \\
        \\fn main() -> UInt8 {
        \\    defer later(true)
        \\    defer later(UInt64(1))
        \\    let one: UInt8 = 1
        \\    let two: UInt8 = 2
        \\    let a: UInt8 = ident(one)
        \\    let b: UInt8 = ident(two)
        \\    let _different: Bool = ident(true)
        \\    let box: Box[UInt8] = .{ value = a + b }
        \\    let member: UInt8 = box.take()
        \\    recurse(bounded(member), 1)
        \\}
    };

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var resolution = try resolveTree(gpa, &ast, &sink);
    defer resolution.deinit(gpa);
    var typing = try typecheckTree(gpa, &resolution, &sink);
    defer typing.deinit(gpa);
    try testing.expect(!sink.hasErrors());

    var disposals = try checkOwnershipTree(gpa, &resolution, &typing, &sink);
    defer disposals.deinit(gpa);
    var complete = try instantiate(gpa, &resolution.expanded, &resolution.resolution, &typing, &disposals, &sink, .program);
    defer complete.deinit();
    const table = complete.table();
    var module = try lower(gpa, &resolution.expanded, &resolution.resolution, &typing, &complete, &disposals, &sink, .program);
    defer module.deinit(gpa);
    try testing.expectEqual(@as(usize, table.count()), module.names.len);
    for (module.names, 0..) |name, i| {
        try testing.expectEqualStrings(name, table.get(.at(@intCast(i))).name);
    }
}

test "a strict instance-table prefix withholds the omitted callee" {
    const source: Source = .{ .path = "t.lin", .text =
        \\fn called() -> UInt8 { 7 }
        \\fn main() -> UInt8 { called() }
    };

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var resolution = try resolveTree(gpa, &ast, &sink);
    defer resolution.deinit(gpa);
    var typing = try typecheckTree(gpa, &resolution, &sink);
    defer typing.deinit(gpa);
    try testing.expect(!sink.hasErrors());

    var disposals = try checkOwnershipTree(gpa, &resolution, &typing, &sink);
    defer disposals.deinit(gpa);
    var complete = try instantiate(gpa, &resolution.expanded, &resolution.resolution, &typing, &disposals, &sink, .program);
    defer complete.deinit();
    const full = complete.table();
    try testing.expectEqual(@as(u32, 2), full.count());

    var prefix = InstanceTableBuilder.init(gpa);
    defer prefix.deinit();
    const root = full.get(.at(0));
    var prefix_pool = try Typing.Builder.reopen(gpa, &full.typing);
    defer prefix_pool.deinit();
    _ = try prefix.intern(root.key, &resolution.expanded, &prefix_pool);
    var prefix_table = prefix.table();
    prefix_table.typing = full.typing;

    const withheld = full.get(.at(1)).key;
    try testing.expect(prefix_table.lookup(root.key.body.declaration, root.key.args, root.key.self_ty, root.key.impl_args) != null);
    try testing.expectEqual(
        @as(?instantiate_mod.InstanceId, null),
        prefix_table.lookup(withheld.body.declaration, withheld.args, withheld.self_ty, withheld.impl_args),
    );
}

test "lowerTree emits materialized generic returns in discovery order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(),
        \\struct Cell[T] { value: T }
        \\fn wrap[T: Copyable](x: T) -> Cell[T] { .{ value = copy(x) } }
        \\fn main() -> UInt8 {
        \\    let _ = wrap(true)
        \\    let _ = wrap(UInt8(1))
        \\    0
        \\}
    );

    try testing.expectEqual(@as(usize, 3), module.functions.len);
    try testing.expectEqual(@as(usize, 0), module.origins[0].args.len);
    try testing.expectEqual(TypeId.bool_, module.origins[1].args[0]);
    try testing.expectEqual(TypeId.u8, module.origins[2].args[0]);
}

test "named constant DAGs lower their checked value without repeated arithmetic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(),
        \\let c0: UInt8 = 1
        \\let c1: UInt8 = c0 + c0
        \\let c2: UInt8 = c1 + c1
        \\let c3: UInt8 = c2 + c2
        \\let c4: UInt8 = c3 + c3
        \\fn main() -> UInt8 { c4 }
    );
    const function = &module.functions[0];
    try testing.expectEqual(@as(usize, 0), countTag(function, .add));
    try testing.expectEqual(@as(usize, 0), countTag(function, .check));
    const returned = function.unaryOf(function.terminatorOf(function.entry));
    try testing.expectEqual(mir_mod.Inst.Tag.constant, function.tagOf(returned));
    try testing.expectEqual(TypeId.u8, function.typeOf(returned));
    try testing.expectEqual(@as(i128, 16), function.constantOf(returned));
}

test "named constants retain scalar values and nominal types at their uses" {
    const cases = [_]struct { text: []const u8, ty: []const u8, value: i128 }{
        .{ .text = "let value: UInt8 = later\nlet later: UInt8 = UInt8((9 * 3 - 1) / 2 % 8)\nfn held() -> UInt8 { value }", .ty = "UInt8", .value = 5 },
        .{ .text = "let value: Int8 = -128\nfn held() -> Int8 { value }", .ty = "Int8", .value = -128 },
        .{ .text = "let value: UInt64 = 18446744073709551615\nfn held() -> UInt64 { value }", .ty = "UInt64", .value = 18446744073709551615 },
        .{ .text = "let value: Bool = true\nfn held() -> Bool { value }", .ty = "Bool", .value = 1 },
        .{ .text = "let value: Bool = false\nfn held() -> Bool { value }", .ty = "Bool", .value = 0 },
        .{ .text = "type Meters = UInt8\nimpl Meters { pub let value: UInt8 = 3 + 4 }\nfn held() -> Meters { Meters(Meters.value) }", .ty = "Meters", .value = 7 },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source = try std.fmt.allocPrint(gpa, "{s}\nfn main() -> UInt8 {{ let _ = held(); 0 }}", .{case.text});
        const module = try lowerSource(gpa, source);
        try testing.expectEqual(@as(usize, 2), module.functions.len);
        const function = &module.functions[1];
        const returned = function.unaryOf(function.terminatorOf(function.entry));
        try testing.expectEqual(Inst.Tag.constant, function.tagOf(returned));
        try testing.expectEqualStrings(case.ty, module.types.nameOf(module.types.get(function.signature).callable.result));
        try testing.expectEqual(function.return_type, function.typeOf(returned));
        try testing.expectEqual(@as(i128, case.value), function.constantOf(returned));
        try testing.expectEqual(@as(usize, 0), countTag(function, .check));
    }
}

test "arithmetic lowers to an operation and a check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(), "fn main() -> UInt8 { 1 + 2 }");
    const mir = &module.functions[0];
    try testing.expectEqual(@as(usize, 1), countTag(mir, .add));
    try testing.expectEqual(@as(usize, 2), countTag(mir, .constant));
    try testing.expectEqual(@as(usize, 1), countTag(mir, .check));
}

test "division checks its divisor before dividing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(), "fn main() -> UInt8 { 6 / 2 }");
    const mir = &module.functions[0];
    try testing.expectEqual(@as(usize, 2), countTag(mir, .check));

    // The divisor's check precedes the division, because a zero divisor
    // produces no result to inspect afterwards.
    const insts = mir.instsOf(mir.entry);
    var saw_divisor_check = false;
    for (insts) |i| {
        switch (mir.tagOf(i)) {
            .check => if (mir.checkOf(i).kind == .division_by_zero) {
                saw_divisor_check = true;
            },
            .div => try testing.expect(saw_divisor_check),
            else => {},
        }
    }
    try testing.expect(saw_divisor_check);
}

test "a binding becomes a store and a use becomes a load" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(), "fn main() -> UInt8 { let x: UInt8 = 4; x }");
    const mir = &module.functions[0];
    try testing.expectEqual(@as(usize, 1), countTag(mir, .store));
    try testing.expectEqual(@as(usize, 1), countTag(mir, .load));
    try testing.expectEqual(@as(usize, 1), mir.locals.len);
    try testing.expectEqual(TypeId.u8, mir.locals[0]);
}

test "a shadowed binding gets its own local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(), "fn main() -> UInt8 { let _x: UInt8 = 1; let _x: UInt8 = 2; _x }");
    const mir = &module.functions[0];
    try testing.expectEqual(@as(usize, 2), mir.locals.len);
    try testing.expectEqual(@as(usize, 2), countTag(mir, .store));

    // The use reads the second, which is what shadowing means.
    try testing.expectEqual(@as(usize, 1), countTag(mir, .load));
    for (mir.insts.items(.tag), 0..) |t, i| {
        if (t != .load) continue;
        try testing.expectEqual(@as(u32, 1), mir.localOf(InstId.at(@intCast(i))).index());
    }
}

test "parentheses do not survive lowering" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const plain = try lowerSource(arena.allocator(), "fn main() -> UInt8 { 1 + 2 }");
    const parens = try lowerSource(arena.allocator(), "fn main() -> UInt8 { ((1) + (2)) }");
    try testing.expectEqual(plain.functions[0].insts.len, parens.functions[0].insts.len);
}

test "a conversion becomes a check against the target type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(), "fn main() -> UInt8 { let x: Int64 = 4; UInt8(x) }");
    const mir = &module.functions[0];
    var saw = false;
    for (mir.insts.items(.tag), 0..) |t, i| {
        if (t != .check) continue;
        const id = InstId.at(@intCast(i));
        if (mir.checkOf(id).kind == .conversion_out_of_range) {
            try testing.expectEqual(TypeId.u8, mir.typeOf(id));
            saw = true;
        }
    }
    try testing.expect(saw);
}

test "symbolic integer conversions retain instantiated runtime checks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(),
        \\fn converted[T: Integer](_witness: T) -> T { T(256) }
        \\fn main() -> UInt8 {
        \\    let _wide = converted(UInt16(0))
        \\    converted(UInt8(0))
        \\}
    );
    var narrow = false;
    var wide = false;
    for (module.functions, 0..) |function, f| {
        if (std.mem.indexOf(u8, module.nameOf(.at(@intCast(f))), "converted") == null) continue;
        for (function.insts.items(.tag), 0..) |tag, i| {
            if (tag != .check) continue;
            const id = InstId.at(@intCast(i));
            if (function.checkOf(id).kind != .conversion_out_of_range) continue;
            switch (function.typeOf(id)) {
                .u8 => narrow = true,
                .u16 => wide = true,
                else => {},
            }
        }
    }
    try testing.expect(narrow and wide);
}

test "integer range properties lower after type substitution" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(),
        \\fn minimum[T: Integer](_witness: T) -> T { T.min }
        \\fn maximum[T: Integer](_witness: T) -> T { T.max }
        \\fn main() -> UInt8 {
        \\    let _least = minimum(Int64(0))
        \\    let _greatest = maximum(UInt64(0))
        \\    0
        \\}
    );
    var limits: usize = 0;
    for (module.functions, 0..) |function, i| {
        const name = module.nameOf(.at(@intCast(i)));
        const expected: i128 = if (std.mem.indexOf(u8, name, "minimum") != null)
            -9223372036854775808
        else if (std.mem.indexOf(u8, name, "maximum") != null)
            18446744073709551615
        else
            continue;
        const returned = function.unaryOf(function.terminatorOf(function.entry));
        try testing.expectEqual(Inst.Tag.constant, function.tagOf(returned));
        try testing.expectEqual(expected, function.constantOf(returned));
        try testing.expectEqual(function.return_type, function.typeOf(returned));
        limits += 1;
    }
    try testing.expectEqual(@as(usize, 2), limits);
}

test "every block ends in a terminator" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(), "fn main() -> UInt8 { let x: UInt8 = 4; x * 2 + 1 }");
    const mir = &module.functions[0];
    for (0..mir.blockCount()) |i| {
        const t = mir.terminatorOf(BlockId.at(@intCast(i)));
        try testing.expect(t != InstId.none);
        try testing.expect(mir.tagOf(t).isTerminator());
    }
}

test "rejected source produces no MIR" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    for ([_][]const u8{
        "fn main() -> UInt8 { 1 + }",
        "fn main() -> UInt8 { }",
        "fn main() -> UInt8 { unknown }",
        "fn main() -> UInt8 { 1 / 0 }",
    }) |text| {
        try testing.expectError(error.SourceRejected, lowerSource(arena.allocator(), text));
    }
}

test "a type declaration lowers to no function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A handle is a position among the functions, not among the declarations,
    // so an enum between two functions must not shift the second one's calls.
    const module = try lowerSource(arena.allocator(),
        \\fn first() -> UInt8 { 1 }
        \\enum Colour { Red }
        \\fn second() -> UInt8 { 2 }
        \\fn main() -> UInt8 { let _ = Colour.Red; first() + second() }
    );
    try testing.expectEqual(@as(usize, 3), module.functions.len);
    for (module.names) |n| try testing.expect(!std.mem.eql(u8, n, "Colour"));
}

test "a variant lowers to its declared position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(),
        \\enum Colour { Red, Green, Blue }
        \\fn main() -> UInt8 { let _ = Colour.Blue; 0 }
    );
    // Blue is the third variant, so its tag is 2 -- a wrong tag here is a
    // program that runs and answers wrongly, which nothing downstream checks.
    var saw = false;
    for (module.functions[0].insts.items(.data), module.functions[0].insts.items(.tag)) |d, tag| {
        if (tag == .constant and d.constant == 2) saw = true;
    }
    try testing.expect(saw);
}

test "an exhaustive match tests each tag and cannot fall through" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The index comes from the type, not from the scrutinee's symbol: a
    // scrutinee is usually a binding, whose declaration is the function it
    // sits in. Reading it from there compares every arm against zero, which
    // type-checks and runs and answers wrongly.
    const module = try lowerSource(arena.allocator(),
        \\enum Shape { Circle, Square, Point }
        \\fn pick(s: Shape) -> UInt8 { match read s { Circle => 0, Square => 4, Point => 1 } }
        \\fn main() -> UInt8 { pick(Shape.Square) }
    );

    var matched = false;
    for (module.functions) |f| {
        if (f.tagOf(f.terminatorOf(f.entry)) != .branch) continue;
        matched = true;
        var block = f.entry;
        for (0..3) |ordinal| {
            const terminator = f.terminatorOf(block);
            try testing.expectEqual(mir_mod.Inst.Tag.branch, f.tagOf(terminator));
            const branch = f.branchOf(terminator);
            try testing.expectEqual(mir_mod.Inst.Tag.cmp_eq, f.tagOf(branch.cond));
            const comparison = f.binaryOf(branch.cond);
            try testing.expectEqual(@as(i128, @intCast(ordinal)), f.constantOf(comparison.rhs));
            block = branch.else_block;
        }
        const fallthrough = f.terminatorOf(block);
        try testing.expectEqual(mir_mod.Inst.Tag.trap, f.tagOf(fallthrough));
        try testing.expectEqual(mir_mod.TrapKind.unreachable_reached, f.trapOf(fallthrough).kind);
    }
    try testing.expect(matched);
}

test "a signature is not lowered as a function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const module = try lowerSource(arena.allocator(),
        \\struct Account {
        \\    balance: UInt8,
        \\}
        \\
        \\trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\
        \\impl Measure for Account {
        \\    fn of(x: Self) -> UInt8 {
        \\        x.balance
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ balance = 4 }
        \\    Measure.of(a)
        \\}
    );

    // The implementation's member and `main`, and nothing standing for the
    // signature.
    try testing.expectEqual(@as(usize, 2), module.functions.len);
    for (module.names) |n| try testing.expect(!std.mem.eql(u8, n, "Measure.of"));
}

test "a call without a concrete implementation produces no MIR" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.SourceRejected, lowerSource(arena.allocator(),
        \\struct Account {
        \\    balance: UInt8,
        \\}
        \\
        \\trait Measure {
        \\    fn zero() -> UInt8
        \\}
        \\
        \\impl Measure for Account {
        \\    fn zero() -> UInt8 {
        \\        5
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ balance = 1 }
        \\    let _ = a.balance
        \\    Measure.zero()
        \\}
    ));
}

test "the composed trait-call path gives back partial work" {
    // A trait call exercises implementation bindings and call-site side
    // tables, so it allocates on paths a program with no trait leaves
    // untouched.
    const gpa = testing.allocator;
    const source: Source = .{ .path = "t.lin", .text =
        \\struct Account {
        \\    balance: UInt8,
        \\}
        \\
        \\trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\
        \\impl Measure for Account {
        \\    fn of(x: Self) -> UInt8 {
        \\        x.balance
        \\    }
        \\}
        \\
        \\fn twice[T: Measure](v: T) -> UInt8 {
        \\    Measure.of(v) + Measure.of(v)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ balance = 3 }
        \\    twice(a)
        \\}
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var res = try resolveTree(gpa, &ast, &sink);
    defer res.deinit(gpa);
    var typing = try typecheckTree(gpa, &res, &sink);
    defer typing.deinit(gpa);

    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer disposals.deinit(gpa);
    try testing.checkAllAllocationFailures(gpa, lowerOnly, .{.{
        .disposals = &disposals,
        .resolved = &res,
        .typing = &typing,
        .sink = &sink,
    }});
}

test "an index the compiler settles emits no bounds check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Both directions in one test, because either alone is satisfied by a
    // compiler that never checks or by one that always does. The absence is
    // what the folding is for and nothing else can see it: a folded index and
    // a checked one compute the same answer, so no exit status moves when the
    // fold stops happening.
    const folded = try lowerSource(gpa, "fn main() -> UInt8 { let xs: [UInt8; 3] = [1, 2, 3]\n xs[1] }");
    try testing.expectEqual(@as(usize, 0), boundsChecksIn(&folded));

    const computed = try lowerSource(gpa,
        \\fn at(xs: [UInt8; 3], i: UInt8) -> UInt8 { xs[i] }
        \\fn main() -> UInt8 { let xs: [UInt8; 3] = [1, 2, 3]
        \\ at(xs, 1) }
    );
    try testing.expect(boundsChecksIn(&computed) > 0);
}

fn boundsChecksIn(m: *const Module) usize {
    var n: usize = 0;
    for (m.functions) |f| {
        for (f.insts.items(.tag), 0..) |t, i| {
            if (t != .check) continue;
            if (f.checkOf(@enumFromInt(@as(u32, @intCast(i)))).kind == .index_out_of_bounds) n += 1;
        }
    }
    return n;
}

test "a buffer access, the buffer's alignment and the runtime's bound are one number" {
    // The runtime refuses an alignment past what `malloc` guarantees, the
    // library asks for one number for every buffer, and lowering holds every
    // offset to the width it stores. Three texts, one number: a change to any
    // alone leaves an allocator refusing everything or an access misaligned
    // for its own buffer, reported far from the edit. Read out of the sources,
    // so the tie cannot go stale.
    const runtime_source = @embedFile("runtime_source");
    const bound_key = "if (align > ";
    const at = std.mem.indexOf(u8, runtime_source, bound_key).?;
    const from = at + bound_key.len;
    const to = std.mem.indexOfScalarPos(u8, runtime_source, from, ')').?;
    const honoured = try std.fmt.parseInt(u64, runtime_source[from..to], 10);
    try testing.expectEqual(checked_access_width, honoured);

    for (@import("library_manifest").files) |f| {
        if (!std.mem.endsWith(u8, f.path, "mem/buffer.lin")) continue;
        const align_key = "let alignment: UInt64 = ";
        const a = std.mem.indexOf(u8, f.text, align_key).?;
        const v = a + align_key.len;
        const end = std.mem.indexOfScalarPos(u8, f.text, v, '\n').?;
        const declared = try std.fmt.parseInt(u64, std.mem.trim(u8, f.text[v..end], " \r"), 10);
        try testing.expectEqual(checked_access_width, declared);
        return;
    }
    return error.TestUnexpectedResult;
}

test "lowering reads checked literal values without reparsing source" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text = try gpa.dupe(u8,
        \\fn main() -> UInt8 {
        \\    let _fraction: Float64 = 0.1
        \\    let negative: Int8 = -128
        \\    if negative < 0 { 7 } else { 0 }
        \\}
    );
    const source: Source = .{ .path = "literals.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &resolved, &sink);
    var disposals = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
    defer disposals.deinit(gpa);
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    // The token extents stay valid, but their spellings no longer describe
    // the checked constants. Emission consumes the semantic values.
    text[(std.mem.indexOf(u8, text, "0.1") orelse unreachable) + 2] = '2';
    text[(std.mem.indexOf(u8, text, "-128") orelse unreachable) + 3] = '9';
    text[std.mem.indexOf(u8, text, "7") orelse unreachable] = '9';
    var module = (try lowerTree(gpa, &resolved, &typing, &disposals, &sink, .program)) orelse return error.SourceRejected;
    defer module.deinit(gpa);
    var saw_float = false;
    var saw_negative = false;
    var saw_seven = false;
    for (module.functions) |function| {
        for (function.insts.items(.tag), function.insts.items(.ty), function.insts.items(.data)) |tag, ty, data| {
            if (tag != .constant) continue;
            if (ty == .f64) {
                try testing.expectEqual(@as(i128, 0x3fb999999999999a), data.constant);
                saw_float = true;
            }
            if (ty == .i8 and data.constant < 0) {
                try testing.expectEqual(@as(i128, -128), data.constant);
                saw_negative = true;
            }
            if (ty == .u8) {
                try testing.expect(data.constant != 9);
                saw_seven = saw_seven or data.constant == 7;
            }
        }
    }
    try testing.expect(saw_float and saw_negative and saw_seven);
}

test "enum lowering reads settled variant ordinals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text = try gpa.dupe(u8,
        \\enum Flag { First, Other }
        \\enum Box[T] { First(UInt8, T), Other(UInt64, T) }
        \\fn flag(sink x: Flag) -> UInt8 { match x { First => 3, Other => 4 } }
        \\fn unbox[T: Discardable](sink x: Box[T]) -> T { match x { First(_ignored, v) => v, Other(_ignored, v) => v } }
        \\fn main() -> UInt8 { let _flag: Flag = .First; flag(Flag.First) + unbox(Box.First(UInt8(0), UInt8(7))) }
    );
    const source: Source = .{ .path = "variants.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &resolved, &sink);
    var disposals = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    var before = (try lowerTree(gpa, &resolved, &typing, &disposals, &sink, .program)) orelse return error.SourceRejected;
    var expected: std.Io.Writer.Allocating = .init(gpa);
    try @import("dump.zig").dumpModule(&expected.writer, &before);

    // Qualified selections remain the resolver's answers even when checking
    // sees different source spellings. Their payload types still come from
    // the selected variant, including during generic argument inference.
    for ([_][]const u8{ "Flag.First", "Box.First" }) |qualified| {
        const start = std.mem.indexOf(u8, text, qualified) orelse unreachable;
        const from = start + qualified.len - 5;
        @memcpy(text[from..][0..5], "Other");
    }
    var rechecked = try typecheckTree(gpa, &resolved, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    var from_resolution = (try lowerTree(gpa, &resolved, &rechecked, &disposals, &sink, .program)) orelse return error.SourceRejected;
    var resolved_output: std.Io.Writer.Allocating = .init(gpa);
    try @import("dump.zig").dumpModule(&resolved_output.writer, &from_resolution);
    try testing.expectEqualStrings(expected.written(), resolved_output.written());

    // Use-site spellings change while declarations retain their names. Tag
    // construction, arm tests, and payload loads read settled ordinals.
    for ([_][]const u8{ "First =>", "First(_ignored, v) =>", "First;" }) |pattern| {
        const at = std.mem.indexOf(u8, text, pattern) orelse unreachable;
        @memcpy(text[at..][0..5], "Other");
    }
    var after = (try lowerTree(gpa, &resolved, &typing, &disposals, &sink, .program)) orelse return error.SourceRejected;
    var actual: std.Io.Writer.Allocating = .init(gpa);
    try @import("dump.zig").dumpModule(&actual.writer, &after);
    try testing.expectEqualStrings(expected.written(), actual.written());
}

test "storage byte access lowers to a checked load only for its exact library declaration" {
    const program_mod = @import("../syntax/program.zig");
    const cases = [_]struct { library: bool = true, module: []const u8 = "mem", declaration: []const u8, intrinsic: bool = false, expected_error: ?@import("../diagnostics/diagnostic.zig").Code = null, runtime_refused: bool = false }{
        .{ .declaration = "extern fn linea_raw_load8(at: UInt64, len: UInt64, i: UInt64) -> UInt8", .intrinsic = true },
        // Outside the standard library the primitive is neither granted nor
        // defined by the runtime, and both rules say so.
        .{ .library = false, .declaration = "extern fn linea_raw_load8(at: UInt64, len: UInt64, i: UInt64) -> UInt8", .expected_error = .m_extern, .runtime_refused = true },
        .{ .library = false, .declaration = "fn linea_raw_load8(at: UInt64, len: UInt64, i: UInt64) -> UInt8 { UInt8(at + len + i) }" },
        .{ .module = "text", .declaration = "extern fn linea_raw_load8(at: UInt64, len: UInt64, i: UInt64) -> UInt8", .expected_error = .t_extern_runtime },
        // A parameter's name is a label, so a renamed one is still the primitive.
        .{ .declaration = "extern fn linea_raw_load8(at: UInt64, extent: UInt64, i: UInt64) -> UInt8", .intrinsic = true },
        .{ .declaration = "extern fn linea_raw_load8(at: UInt32, len: UInt64, i: UInt64) -> UInt8", .expected_error = .t_extern_runtime },
        .{ .declaration = "extern fn linea_raw_load8(at: UInt64, len: UInt64, i: UInt64) -> UInt64", .expected_error = .t_extern_runtime },
        .{ .declaration = "extern fn linea_raw_load8(sink at: UInt64, len: UInt64, i: UInt64) -> UInt8", .expected_error = .t_extern_runtime },
        .{ .declaration = "extern fn linea_raw_load8(at: UInt64, len: UInt64, i: UInt64 = 0) -> UInt8" },
        .{ .declaration = "fn linea_raw_load8(at: UInt64, len: UInt64, i: UInt64) -> UInt8 { UInt8(at + len + i) }" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try std.fmt.allocPrint(gpa, "{s}\nfn main() -> UInt8 {{ UInt8(linea_raw_load8(1, 1, 0)) }}", .{case.declaration});
        const source: Source = .{ .path = "byte.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var modules = [_]program_mod.Module{.{
            .name = case.module,
            .dir = "std/mem",
            .files = &.{.from(0)},
            .decls = .{ .start = 0, .end = ast.declCount() },
            .imports = &.{},
            .library = case.library,
            .externs = case.library,
        }};
        const program: program_mod.Program = .{ .modules = &modules, .ast = ast };
        var resolved = try resolve_mod.resolve(gpa, &program, &interner, &sink, .program);
        var typing = try @import("../sema/typecheck.zig").typecheck(gpa, &resolved.expanded, &resolved.resolution, &sink);
        if (case.expected_error) |expected| {
            try testing.expectEqual(@as(u32, 1) + @intFromBool(case.runtime_refused), sink.error_count);
            try testing.expectEqual(expected, sink.list.items[0].code);
            if (case.runtime_refused) try testing.expectEqual(@import("../diagnostics/diagnostic.zig").Code.t_extern_runtime, sink.list.items[1].code);
            continue;
        }
        var disposals = try @import("../ownership/check.zig").check(gpa, gpa, &resolved.expanded, &resolved.resolution, &typing, &sink);
        if (sink.hasErrors()) {
            std.debug.print("\nraw-access fixture: {s}\n", .{case.declaration});
            for (sink.list.items) |diagnostic| std.debug.print("{s}\n", .{diagnostic.message});
        }
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        const module = (try lowerProgram(gpa, &resolved.expanded, &resolved.resolution, &typing, &disposals, &sink, .program)).?;
        const entry = &module.functions[module.entry.index()];
        try testing.expectEqual(@as(usize, if (case.intrinsic) 1 else 0), countTag(entry, .load_raw));
        try testing.expectEqual(@as(usize, if (case.intrinsic) 0 else 1), countTag(entry, .call));
        if (case.intrinsic) for (0..entry.insts.len) |i| {
            const id = InstId.at(@intCast(i));
            if (entry.tagOf(id) != .load_raw) continue;
            const raw = entry.rawAccessOf(id);
            try testing.expectEqual(TrapKind.overflow, entry.checkOf(raw.overflow_check).kind);
            try testing.expectEqual(TrapKind.index_out_of_bounds, entry.checkOf(raw.bounds_check).kind);
            try testing.expectEqual(InstId.none, raw.alignment_check);
        };
    }
}

test "immutable two-target callable selections lower to direct branches" {
    const cases = [_]struct { text: []const u8, indirect: usize, direct: usize, noreturn: usize = 0 }{
        .{
            .text =
            \\fn first(value: UInt8) -> UInt8 { value }
            \\fn second(value: UInt8) -> UInt8 { value }
            \\fn main() -> UInt8 {
            \\    let selected: fn(read value: UInt8) -> UInt8 = if true { first } else { second }
            \\    selected(7)
            \\}
            ,
            .indirect = 0,
            .direct = 2,
        },
        .{
            .text =
            \\fn first(value: UInt8) -> UInt8 { value }
            \\fn second(value: UInt8) -> UInt8 { value }
            \\fn main() -> UInt8 {
            \\    var selected: fn(read value: UInt8) -> UInt8 = if true { first } else { second }
            \\    selected = second
            \\    selected(7)
            \\}
            ,
            .indirect = 1,
            .direct = 0,
        },
        .{
            .text =
            \\fn first[T](sink value: T) -> T { value }
            \\fn second[T](sink value: T) -> T { value }
            \\fn main() -> UInt8 {
            \\    let selected: fn(sink value: UInt8) -> UInt8 = if false { first } else { second }
            \\    selected(7)
            \\}
            ,
            .indirect = 0,
            .direct = 2,
        },
        .{
            .text =
            \\fn first() {}
            \\fn second() {}
            \\fn main() -> UInt8 {
            \\    let selected: fn() = if true { first } else { second }
            \\    selected()
            \\    7
            \\}
            ,
            .indirect = 0,
            .direct = 2,
        },
        .{
            .text =
            \\fn first() -> Never { loop {} }
            \\fn second() -> Never { loop {} }
            \\fn main() -> UInt8 {
            \\    let selected: fn() -> Never = if true { first } else { second }
            \\    selected()
            \\}
            ,
            .indirect = 0,
            .direct = 0,
            .noreturn = 2,
        },
        .{
            .text =
            \\fn first(value: UInt8) -> UInt8 { value }
            \\fn second(value: UInt8) -> UInt8 { value }
            \\fn main() -> UInt8 {
            \\    let selected: fn(read value: UInt8) -> UInt8 = if true { let _marker = 1; first } else { second }
            \\    selected(7)
            \\}
            ,
            .indirect = 1,
            .direct = 0,
        },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var module = try lowerSource(arena.allocator(), case.text);
        var sink = Sink.init(arena.allocator());
        try testing.expect(try @import("verify.zig").verify(arena.allocator(), &module, &sink));
        const entry = &module.functions[module.entry.index()];
        try testing.expectEqual(case.indirect, countTag(entry, .call_indirect));
        try testing.expectEqual(case.direct, countTag(entry, .call));
        try testing.expectEqual(case.noreturn, countTag(entry, .call_noreturn));
        try testing.expectEqual(@as(usize, 0), countTag(entry, .call_indirect_noreturn));
    }
}

test "callable selection lowering releases partial provenance" {
    const gpa = testing.allocator;
    const source: Source = .{ .path = "selection.lin", .text =
        \\fn first[T](sink value: T) -> T { value }
        \\fn second[T](sink value: T) -> T { value }
        \\fn main() -> UInt8 {
        \\    let selected: fn(sink value: UInt8) -> UInt8 = if true { first } else { second }
        \\    selected(7)
        \\}
    };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var resolved = try resolveTree(gpa, &ast, &sink);
    defer resolved.deinit(gpa);
    var typing = try typecheckTree(gpa, &resolved, &sink);
    defer typing.deinit(gpa);
    var disposals = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
    defer disposals.deinit(gpa);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try testing.checkAllAllocationFailures(gpa, lowerOnly, .{.{
        .disposals = &disposals,
        .resolved = &resolved,
        .typing = &typing,
        .sink = &sink,
    }});
}

test "array initializers disappear only before complete matching prefix writes" {
    const Case = struct {
        helper: []const u8 = "",
        initializer: []const u8 = "[0, 0, 0, 0]",
        before: []const u8 = "",
        write: []const u8 = "slots[i] = i + 1;",
        step: []const u8 = "i = i + 1;",
        after: []const u8 = "",
        bound: []const u8 = "count",
        result: []const u8 = "total",
        stores: usize = 5,
    };
    const cases = [_]Case{
        .{ .stores = 1 },
        .{ .write = "slots[i] = slots[i] + 1;" },
        .{ .write = "slots[i] += 1;" },
        .{ .write = "if i != 1 { slots[i] = i + 1 }" },
        .{ .write = "if i == 2 { break }; slots[i] = i + 1;" },
        .{ .step = "i = i + 2;" },
        .{ .before = "let first = slots[0];", .result = "total + first" },
        .{ .after = "let last = slots[3];", .result = "total + last" },
        .{ .before = "let other = (count + 1) % 5;", .bound = "other" },
        .{ .helper = "fn touch(values: [UInt64; 4]) -> UInt64 { values[0] }", .after = "let first = touch(slots);", .result = "total + first" },
        .{ .helper = "fn seed(n: UInt64) -> UInt64 { 4 / n }", .initializer = "[seed(n), 0, 0, 0]" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try std.fmt.allocPrint(gpa, "{s}\nfn work(n: UInt64) -> UInt64 {{\n" ++
            "var slots: [UInt64; 4] = {s};\nlet count = n % 5;\n{s}\nvar i: UInt64 = 0;\n" ++
            "while i < count {{\n{s}\n{s}\n}}\n{s}\ni = 0;\nvar total: UInt64 = 0;\n" ++
            "while i < {s} {{ total += slots[i]; i += 1; }}\n{s}\n}}\n" ++
            "fn main() -> UInt8 {{ UInt8(work(4)) }}\n", .{ case.helper, case.initializer, case.before, case.write, case.step, case.after, case.bound, case.result });
        var module = try lowerSource(gpa, text);
        defer module.deinit(gpa);
        var stores: usize = 0;
        for (module.functions) |*function| stores += countTag(function, .store_indirect);
        try testing.expectEqual(case.stores, stores);
    }
}

test "array initialization lowering releases partial proof storage" {
    const gpa = testing.allocator;
    const source: Source = .{ .path = "array.lin", .text =
        \\fn main() -> UInt8 {
        \\    var first: [UInt64; 4] = [0, 0, 0, 0]
        \\    var second: [UInt64; 4] = [1, 1, 1, 1]
        \\    let count: UInt64 = 3
        \\    var i: UInt64 = 0
        \\    while i < count {
        \\        first[i] = i
        \\        second[i] = i + 1
        \\        i += 1
        \\    }
        \\    i = 0
        \\    var total: UInt64 = 0
        \\    while i < count {
        \\        total += first[i] + second[i]
        \\        i += 1
        \\    }
        \\    UInt8(total)
        \\}
    };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);
    var resolved = try resolveTree(gpa, &ast, &sink);
    defer resolved.deinit(gpa);
    var typing = try typecheckTree(gpa, &resolved, &sink);
    defer typing.deinit(gpa);
    var disposals = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
    defer disposals.deinit(gpa);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try testing.checkAllAllocationFailures(gpa, lowerOnly, .{.{
        .disposals = &disposals,
        .resolved = &resolved,
        .typing = &typing,
        .sink = &sink,
    }});
}

test "a match arm with a Never payload has no value to bind" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\enum Box[T] { None, Some(T) }
        \\trait Discard { fn discard(sink self: Self) }
        \\impl[T: Discardable] Discard for Box[T] {
        \\    fn discard(sink self: Self) {
        \\        match self { None => {}, Some(value) => { let _ = value } }
        \\    }
        \\}
        \\fn main() -> UInt8 {
        \\    let empty: Box[Never] = .None
        \\    Discard.discard(empty)
        \\    0
        \\}
    );
    defer module.deinit(gpa);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow of a read scalar returns a stable caller address" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\fn observe(value: UInt8) -> borrow UInt8 where borrows(value) {
        \\    borrow value
        \\}
        \\fn main() -> UInt8 {
        \\    let value: UInt8 = 17
        \\    let observation = observe(value)
        \\    return *observation
        \\}
    );
    defer module.deinit(gpa);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow generic referents infer through the observation type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\fn forward[T](sink view: borrow T) -> borrow T where carries(view) { view }
        \\fn main() -> UInt8 { let n: UInt8 = 19; let b = forward(borrow n); *b }
    );
    defer module.deinit(gpa);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow forwards a readonly trait through generic inference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\trait Measure { fn value(self: Self) -> UInt8 }
        \\impl Measure for UInt8 { fn value(self: Self) -> UInt8 { self } }
        \\fn measure[T: Measure](x: T) -> UInt8 { Measure.value(x) }
        \\fn main() -> UInt8 { let n: UInt8 = 23; let b = borrow n; measure(b) }
    );
    defer module.deinit(gpa);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow observational traits return the underlying place" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\trait Observe { fn byte(self: Self) -> borrow UInt8 where borrows(self) }
        \\impl Observe for UInt8 { fn byte(self: Self) -> borrow UInt8 where borrows(self) { borrow self } }
        \\fn main() -> UInt8 {
        \\    let n: UInt8 = 23
        \\    let view = Observe.byte(borrow n)
        \\    return *view
        \\}
    );
    defer module.deinit(gpa);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow comparisons use the underlying observational trait ABI" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "comparison.lin", .text =
        \\trait Equatable { fn equals(self: Self, other: Self) -> Bool }
        \\struct Number { value: UInt8 }
        \\impl Equatable for Number { fn equals(_self: Self, _other: Self) -> Bool { true } }
        \\fn main() -> UInt8 {
        \\    let left: Number = .{ value = 3 }
        \\    let right: Number = .{ value = 3 }
        \\    let a = borrow left
        \\    let b = borrow right
        \\    if a == b { 0 } else { 1 }
        \\}
    };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
    var typing = try typecheckTree(gpa, &resolved, &sink);
    var disposals = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
    const lowered = try lowerTree(gpa, &resolved, &typing, &disposals, &sink, .program);
    for (sink.list.items) |diagnostic| std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code.?), diagnostic.message });
    var module = lowered orelse return error.SourceRejected;
    try testing.expect(!sink.hasErrors());
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow values implement their own consuming traits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\trait Release { fn release(sink self: Self) }
        \\impl[T] Release for borrow T { fn release(sink _self: Self) {} }
        \\@linear struct Owner { value: UInt8 }
        \\fn drop[T: Release](sink value: T) { Release.release(value) }
        \\fn main() -> UInt8 {
        \\    let owner: Owner = .{ value = 7 }
        \\    drop(borrow owner)
        \\    let Owner { value: n } = owner
        \\    n
        \\}
    );
    defer module.deinit(gpa);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow explicit observational implementations preserve nested receiver ABI" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\trait Number { fn number(self: Self) -> UInt8 }
        \\impl Number for UInt8 { fn number(self: Self) -> UInt8 { self } }
        \\impl Number for borrow UInt8 { fn number(_self: Self) -> UInt8 { 9 } }
        \\fn observed[T: Number](value: T) -> UInt8 { Number.number(borrow value) }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 3
        \\    let view = borrow number
        \\    observed(view) + Number.number(borrow view) + Number.number(view)
        \\}
    );
    defer module.deinit(gpa);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow call arguments stop at divergence before observation adaptation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\trait Number { fn number(self: Self, other: Self) -> UInt8 }
        \\impl Number for UInt8 { fn number(self: Self, _other: Self) -> UInt8 { self } }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 3
        \\    let view = borrow number
        \\    Number.number(view, { return 7 })
        \\}
    );
    defer module.deinit(gpa);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "borrow comparisons adapt each selected operation independently" {
    const declarations =
        \\trait Equatable { fn equals(self: Self, other: Self) -> Bool }
        \\trait Comparable { fn less(self: Self, other: Self) -> Bool }
        \\
    ;
    const cases = [_]struct { source: []const u8, calls: usize, ambient_order: bool = false }{
        .{ .source = declarations ++
            \\struct Number { value: UInt8 }
            \\impl Comparable for Number { fn less(_self: Self, _other: Self) -> Bool { false } }
            \\impl Equatable for borrow Number { fn equals(_self: Self, _other: Self) -> Bool { true } }
            \\fn main() -> UInt8 {
            \\    let number: Number = .{ value = 3 }
            \\    let view = borrow number
            \\    if view <= view { 0 } else { 1 }
            \\}
        , .calls = 2 },
        .{ .source = declarations ++
            \\impl Equatable for borrow UInt8 { fn equals(_self: Self, _other: Self) -> Bool { false } }
            \\fn main() -> UInt8 {
            \\    let number: UInt8 = 3
            \\    let view = borrow number
            \\    if Comparable.less(number, number) || view >= view { 1 } else { 0 }
            \\}
        , .calls = 1, .ambient_order = true },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "comparison.lin", .text = case.source };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        resolved.resolution.prelude = resolved.expanded.declsOf(.from(0));
        if (case.ambient_order) {
            // Primitive rows are the resolver input for mixed intrinsic and
            // source implementations; this tree has no loaded cmp module.
            resolved.resolution.ambient_impls = try gpa.dupe(resolve_mod.AmbientImpl, &.{
                .{ .trait = comparableDecl(&resolved.expanded.ast, &resolved.resolution).?, .over = .{ .primitive = .u8 } },
                .{ .trait = equatableDecl(&resolved.expanded.ast, &resolved.resolution).?, .over = .{ .primitive = .u8 } },
            });
        }
        var typing = try typecheckTree(gpa, &resolved, &sink);
        var disposals = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
        var module = (try lowerTree(gpa, &resolved, &typing, &disposals, &sink, .program)) orelse {
            for (sink.list.items) |diagnostic| std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code.?), diagnostic.message });
            return error.SourceRejected;
        };
        try testing.expect(!sink.hasErrors());
        try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
        var calls: usize = 0;
        for (module.functions[@intFromEnum(module.entry)].insts.items(.tag)) |tag| if (tag == .call) {
            calls += 1;
        };
        try testing.expectEqual(case.calls, calls);
    }
}

test "read match observations alias their source fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var module = try lowerSource(gpa,
        \\struct Pair { number: UInt8 }
        \\enum Payload { Full(Pair) }
        \\type Count = UInt8
        \\fn pair(value: Payload) -> borrow Pair where borrows(value) {
        \\    match read value { Full(item) => borrow item }
        \\}
        \\fn field(value: Pair) -> borrow UInt8 where borrows(value) {
        \\    match read value { Pair { number } => borrow number }
        \\}
        \\fn base(value: Count) -> borrow UInt8 where borrows(value) {
        \\    match read value { Count(number) => borrow number }
        \\}
        \\fn main() -> UInt8 {
        \\    let payload: Payload = .Full(.{ number = 7 })
        \\    let value: Pair = .{ number = 11 }
        \\    let count = Count(13)
        \\    pair(payload).number + *field(value) + *base(count)
        \\}
    );
    defer module.deinit(gpa);
    var observations: usize = 0;
    for (module.functions) |*function| {
        const count = countTag(function, .borrow);
        if (count == 0) continue;
        observations += count;
        // A returned observation must not address a copied local payload.
        try testing.expectEqual(@as(usize, 0), countTag(function, .addr_of));
        try testing.expectEqual(@as(usize, 0), countTag(function, .copy_value));
        try testing.expectEqual(@as(usize, 0), countTag(function, .move_value));
    }
    try testing.expectEqual(@as(usize, 3), observations);
    var sink = Sink.init(gpa);
    try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
}

test "float math lowers every trusted operation with its checked arity" {
    const names = [_][]const u8{ "sqrt", "floor", "ceil", "trunc", "round", "pow", "sin", "cos", "ln", "exp" };
    for (names) |name| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        const binary = std.mem.eql(u8, name, "pow");
        const text = try std.fmt.allocPrint(
            gpa,
            "extern fn linea_math_{s}(value: Float64{s}) -> Float64\nfn main() -> UInt8 {{ let _answer = linea_math_{s}(4.0{s}); 0 }}",
            .{ name, if (binary) ", exponent: Float64" else "", name, if (binary) ", 2.0" else "" },
        );
        const source: Source = .{ .path = "float.lin", .text = text };
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        resolved.modules[0].name = "scalar";
        resolved.modules[0].library = true;
        resolved.modules[0].externs = true;
        var typing = try typecheckTree(gpa, &resolved, &sink);
        var disposals = try @import("../ownership/check.zig").checkTree(gpa, &resolved, &typing, &sink);
        try testing.expect(!sink.hasErrors());
        const module = (try lowerTree(gpa, &resolved, &typing, &disposals, &sink, .program)).?;
        const entry = &module.functions[module.entry.index()];
        try testing.expectEqual(@as(usize, 1), countTag(entry, .float_math));
        try testing.expectEqual(@as(usize, 0), countTag(entry, .call));
        for (entry.insts.items(.tag), entry.insts.items(.data)) |tag, data| {
            if (tag != .float_math) continue;
            try testing.expectEqualStrings(name, @tagName(data.float_math.operation));
            try testing.expectEqual(!binary, data.float_math.rhs == .none);
        }
        try testing.expect(try @import("verify.zig").verify(gpa, &module, &sink));
    }
}
