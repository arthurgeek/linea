const std = @import("std");
const testing = std.testing;

const tracy = @import("../support/tracy.zig");
const Source = @import("../support/source.zig").Source;
const FileId = @import("../support/source.zig").FileId;
const Span = @import("../support/span.zig").Span;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Diagnostic = @import("../diagnostics/diagnostic.zig").Diagnostic;
const Chain = @import("../support/chain.zig").Chain;
const name_case = @import("../support/name_case.zig");
const article = @import("../support/article.zig");
const Stamped = @import("../support/stamp.zig").Stamped;
const interner_mod = @import("../support/interner.zig");
const Interner = interner_mod.Interner;
const StringId = interner_mod.StringId;
const Label = @import("../diagnostics/diagnostic.zig").Label;
const Code = @import("../diagnostics/diagnostic.zig").Code;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const Modules = @import("../parser/parser.zig").Modules;
const token = @import("../lexer/token.zig");
const TokenId = token.TokenId;
const Ast = @import("../syntax/ast.zig").Ast;
const DeclIndex = @import("../syntax/ast.zig").DeclIndex;
const expanded_mod = @import("../syntax/expanded_program.zig");
const ExpandedProgram = expanded_mod.ExpandedProgram;
const Relocation = @import("../syntax/relocation.zig").Relocation;
const GeneratedDecl = expanded_mod.GeneratedDecl;
const GeneratedImport = expanded_mod.GeneratedImport;
const GeneratedImplementation = expanded_mod.GeneratedImplementation;
const GeneratedImplementationId = expanded_mod.GeneratedImplementationId;
const ComponentRequirement = expanded_mod.ComponentRequirement;
const ComponentRequirementRange = expanded_mod.ComponentRequirementRange;
const GeneratedOriginSegment = expanded_mod.GeneratedOriginSegment;
const GeneratedSources = expanded_mod.GeneratedSources;
const TemplateMemberPlan = expanded_mod.TemplateMemberPlan;
const program_mod = @import("../syntax/program.zig");
const Program = program_mod.Program;
const generated_calls = @import("../support/generated_calls.zig");
const ModuleId = program_mod.ModuleId;
const node = @import("../syntax/node.zig");
const constfold = @import("constfold.zig");
const Constraints = @import("constraints.zig").Constraints;
const reflection = @import("reflection.zig");
const ComponentLoopPlan = reflection.ComponentLoopPlan;
const ComponentPlacePlan = reflection.ComponentPlacePlan;
const MetadataPlan = reflection.MetadataPlan;
const OrdinalPlan = reflection.OrdinalPlan;
const ReflectedCasePlan = reflection.ReflectedCasePlan;
const SameCasePlan = reflection.SameCasePlan;
const ReflectionMemberPlan = reflection.ReflectionMemberPlan;
const ParameterPlan = reflection.ParameterPlan;
const TypeId = @import("types.zig").TypeId;
const IntegerEndpoint = @import("types.zig").IntegerEndpoint;

pub const IntegerSelection = struct { receiver: BindingId, endpoint: IntegerEndpoint };
const VariantOrdinal = @import("types.zig").VariantOrdinal;
const ids = @import("ids.zig");
const Table = @import("../support/table.zig").Table;
const BitTable = @import("../support/table.zig").BitTable;
const ExprId = node.ExprId;
const StmtId = node.StmtId;
const DeclId = node.DeclId;

pub const ResolveResult = struct {
    expanded: ExpandedProgram,
    resolution: Resolution,
};

/// A resolved library and the private rows needed to continue its name walk.
/// The source program and its source buffers must outlive this value.
pub const LibraryPrefix = struct {
    arena: std.heap.ArenaAllocator,
    result: ResolveResult,
    interner: Interner,
    seed: Seed,

    /// Reuse requires the same closed source prefix and stable interned names.
    /// Application expansion uses the complete resolver until its generated
    /// source can be appended to an existing expansion.
    pub fn canResume(self: *const LibraryPrefix, program: *const Program, interner: *const Interner) bool {
        const cached = self.result.expanded.source;
        if (program.modules.len <= cached.modules.len or program.primary.index() < cached.modules.len) return false;
        if (program.prelude != cached.prelude) return false;
        if (program.ast.parts.len < cached.ast.parts.len or program.ast.tokenCount() < cached.ast.tokenCount()) return false;
        if (interner.count() < self.interner.count()) return false;
        for (self.interner.texts.items, 0..) |name, i| {
            if (!std.mem.eql(u8, name, interner.texts.items[i])) return false;
        }
        for (cached.ast.parts, program.ast.parts[0..cached.ast.parts.len]) |before, after| {
            if (before.file != after.file or before.decl_start != after.decl_start or before.decl_end != after.decl_end or
                !std.mem.eql(u8, before.path, after.path) or !std.mem.eql(u8, before.source, after.source)) return false;
        }
        for (cached.modules, program.modules[0..cached.modules.len]) |before, after| {
            if (!after.library or before.root != after.root or before.decls.start != after.decls.start or before.decls.end != after.decls.end or
                !std.mem.eql(u8, before.name, after.name) or !std.mem.eql(u8, before.dir, after.dir) or
                before.imports.len != after.imports.len or !std.mem.eql(FileId, before.files, after.files)) return false;
            for (before.imports, after.imports) |a, b| if (a.decl != b.decl or a.module != b.module) return false;
        }
        for (program.modules[cached.modules.len..]) |module| {
            if (module.library) return false;
            for (module.decls.start..module.decls.end) |i| {
                const d = DeclId.at(@intCast(i));
                switch (program.ast.declTag(d)) {
                    .template_impl, .derive_impl => return false,
                    else => {},
                }
                if (program.ast.deriveRequestTraitRange(d).len() != 0) return false;
            }
        }
        // Closure symbols and capture environment names encode allocation
        // identities, so application closures require the ordinary load order.
        for (cached.ast.exprCount()..program.ast.exprCount()) |i| {
            if (program.ast.exprTag(ExprId.at(@intCast(i))) == .lambda) return false;
        }
        for (cached.ast.tokenCount()..program.ast.tokenCount()) |i| {
            const tok = TokenId.at(@intCast(i));
            if (program.ast.tokenTag(tok) == .identifier and
                std.mem.startsWith(u8, program.ast.tokenText(tok), "_linea_trait_")) return false;
        }
        for (program.ast.parts[cached.ast.parts.len..]) |part| {
            for (self.result.expanded.ast.parts[cached.ast.parts.len..]) |generated| {
                if (std.mem.eql(u8, std.fs.path.basename(part.path), std.fs.path.basename(generated.path))) return false;
            }
        }
        return true;
    }

    pub fn deinit(self: *LibraryPrefix) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Resolve a closed library through the ordinary pass, retaining its builder
/// rows before finalization groups scopes and consumes the mutable tables.
pub fn resolveLibraryPrefix(
    gpa: std.mem.Allocator,
    program: *const Program,
    interner: *const Interner,
    sink: *Sink,
) !LibraryPrefix {
    if (sink.hasErrors() or program.modules.len == 0) return error.InvalidLibraryPrefix;
    for (program.modules) |module| {
        if (!module.library) return error.InvalidLibraryPrefix;
        for (module.imports) |import| {
            if (import.module == .none or import.module.index() >= program.modules.len)
                return error.InvalidLibraryPrefix;
        }
    }
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    var seed: ?Seed = null;
    const result = try resolveInternal(arena.allocator(), program, interner, sink, .program, &seed, null);
    if (sink.hasErrors()) return error.InvalidLibraryPrefix;
    const names = if (result.expanded.borrowed_source) interner else &result.expanded.interner;
    return .{ .arena = arena, .result = result, .interner = try Interner.initPrefix(arena.allocator(), names), .seed = seed.? };
}

/// Continue a clean library resolution, or run the complete pass when the
/// application cannot preserve the cached source and expansion identities.
pub fn resolveWithPrefix(
    gpa: std.mem.Allocator,
    program: *const Program,
    interner: *const Interner,
    sink: *Sink,
    purpose: Purpose,
    prefix: *const LibraryPrefix,
) !ResolveResult {
    if (!prefix.canResume(program, interner)) return resolve(gpa, program, interner, sink, purpose);
    var names = try Interner.initPrefix(gpa, interner);
    defer names.deinit(gpa);
    var parser = try Modules.initPrefix(gpa, sink, &names, &program.ast);
    defer parser.deinit();
    const relocation = try parser.appendGenerated(&prefix.result.expanded.source.ast, &prefix.result.expanded.ast);
    var joined = try parser.finish();
    const expanded = try ExpandedProgram.attachLibraryPrefix(gpa, program, &joined, &names, &prefix.result.expanded, relocation);
    const input: Resumed = .{ .prefix = prefix, .expanded = expanded, .relocation = relocation };
    return resolveInternal(gpa, program, interner, sink, purpose, null, &input);
}

/// Authoritative rows discarded by Resolution finalization. Lookup indexes
/// are rebuilt from these rows and the complete Resolution when continuing.
const Seed = struct {
    bindings: []const Binding,
    top: []const BindingId,
    module_runs: []const ModuleRun,
    members: []const Member,
    implementations: []const Implementation,
    builtins: []const BindingId,
    prelude: []const BindingId,
    scope_bindings: []const BindingId,
    binding_scopes: []const ScopeId,
    pattern_heads: []const PatternHead,
    inherent_heads: []const InherentHead,
    inherent_selections: []const StringId,

    fn capture(gpa: std.mem.Allocator, r: *const Resolver, prelude: []const BindingId) !Seed {
        return .{
            .bindings = try gpa.dupe(Binding, r.bindings.items),
            .top = try gpa.dupe(BindingId, r.top.items),
            .module_runs = try gpa.dupe(ModuleRun, r.module_runs.items),
            .members = try gpa.dupe(Member, r.members.items),
            .implementations = try gpa.dupe(Implementation, r.impls.items),
            .builtins = try gpa.dupe(BindingId, r.builtins.items),
            .prelude = try gpa.dupe(BindingId, prelude),
            .scope_bindings = try gpa.dupe(BindingId, r.scope_bindings.items),
            .binding_scopes = try gpa.dupe(ScopeId, r.binding_scopes.items),
            .pattern_heads = try gpa.dupe(PatternHead, r.pattern_heads.items),
            .inherent_heads = try gpa.dupe(InherentHead, r.inherent_heads.items),
            .inherent_selections = try gpa.dupe(StringId, r.inherent_selections.items),
        };
    }
};

/// Whether a written type is `Self`.
///
/// One test rather than a comparison at each site that cares: `Self` is an
/// ordinary identifier to the lexer, so what tells it from a declared type is
/// this spelling and only this spelling. Here rather than where types are,
/// because deciding what a head names is this pass's job and the passes after
/// it read the answer.
pub fn namesSelf(ast: *const Ast, tok: TokenId) bool {
    if (tok == TokenId.none) return false;
    if (ast.tokenTag(tok) != .identifier) return false;
    return std.mem.eql(u8, ast.tokenText(tok), "Self");
}

/// What resolution mints. Declared below this pass so the checker can hold a
/// table keyed by one without importing the pass that hands them out.
pub const BindingId = ids.BindingId;
pub const ScopeId = ids.ScopeId;
pub const ClosureId = ids.ClosureId;
const BindingBits = BitTable(BindingId);
const FinishedBindingBits = BindingBits.Frozen;

/// How far from its declaring module a binding's name may travel.
pub const Reach = enum(u8) {
    module,
    root,
    public,
};

/// Reports why a name written at `at`, held by the module `holding`, does
/// not reach where it is written: a private name reaches its own module and
/// an internal one its root. One wording for a written path and for a
/// postfix call, since both are held to the same rule.
pub fn reportUnreachableName(sink: *Sink, ast: *const Ast, at: TokenId, holding: []const u8, reach: Reach) !void {
    switch (reach) {
        .module => try sink.addErrorFmt(
            .m_vis,
            ast.fileOf(at),
            ast.tokenSpan(at),
            "declare it `pub` in its own module, or do not name it here",
            "`{s}` is private to `{s}`",
            .{ ast.tokenText(at), holding },
        ),
        .root => try sink.addErrorFmt(
            .m_vis,
            ast.fileOf(at),
            ast.tokenSpan(at),
            "only modules in the same root may name it",
            "`{s}` is internal to another root",
            .{ast.tokenText(at)},
        ),
        .public => unreachable,
    }
}

test "an unreachable name is reported by the reach it has" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "t.lin", .text = "fn close() -> UInt8 { 0 }" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    const at = ast.declName(DeclId.at(0));

    try reportUnreachableName(&sink, &ast, at, "door", .module);
    try reportUnreachableName(&sink, &ast, at, "door", .root);
    try testing.expectEqual(@as(u32, 2), sink.error_count);
    const reported = sink.items();
    try testing.expectEqual(Code.m_vis, reported[0].code);
    try testing.expectEqualStrings("`close` is private to `door`", reported[0].message);
    try testing.expectEqual(Code.m_vis, reported[1].code);
    try testing.expectEqualStrings("`close` is internal to another root", reported[1].message);
}

/// The naming reach a source visibility declares.
pub fn reachForVisibility(visibility: node.Visibility) Reach {
    return switch (visibility) {
        .private => .module,
        .internal_ => .root,
        .pub_, .opaque_ => .public,
    };
}

/// Whether `writing` may name a binding held by `holding` at this reach.
pub fn reachableFrom(program: *const Program, reach: Reach, holding: ModuleId, writing: ModuleId) bool {
    return switch (reach) {
        .module => holding == writing,
        .root => program.get(holding).root == program.get(writing).root,
        .public => true,
    };
}

/// Who owns the type side of an implementation's head.
pub const ImplTypeSide = union(enum) {
    /// A type a module declares, owned by that module.
    declared: ModuleId,
    /// A primitive. No module declares one, so the library, which is what
    /// the language ships, owns its type side.
    primitive,
    /// Unit, a callable type, a parameter or an observation constructor: no
    /// module owns its type side, so only the trait's module may implement
    /// for it.
    unowned,
    /// A type no `impl` head can name: a closure, whose type is its own, or
    /// an array. No module may write an implementation for it.
    unnameable,
};

/// Whether `writer` may write an implementation of the trait declared in
/// `trait_module` (`.none` for an inherent `impl`) for a head whose type side
/// is `side`. A module owning one side of what the `impl` declares may write
/// it. The resolver asks this of every `impl` it admits, and the checker asks
/// it when a refused bound decides whether to offer an implementation.
pub fn ownsAnImplSide(writer: ModuleId, writer_is_library: bool, side: ImplTypeSide, trait_module: ModuleId) bool {
    if (side == .unnameable) return false;
    if (trait_module != .none and trait_module == writer) return true;
    return switch (side) {
        .declared => |declaring| declaring == writer,
        .primitive => writer_is_library,
        .unowned, .unnameable => false,
    };
}

/// Why no module of a program may implement a trait for a type, and the
/// edit it can make instead, where there is one.
pub const ImplRefusal = struct {
    reason: []const u8,
    instead: ?[]const u8,
};

/// The one wording of why a program may not write an implementation of
/// `trait_name` for `type_name`, whose type side is `side` and whose trait no
/// module of the program declares. The resolver says it where such an `impl`
/// is written, and the checker where a refused bound would need one.
pub fn implRefusal(arena: std.mem.Allocator, side: ImplTypeSide, type_name: []const u8, trait_name: []const u8) std.mem.Allocator.Error!ImplRefusal {
    return switch (side) {
        .unnameable => .{
            .reason = try std.fmt.allocPrint(arena, "no `impl` can name `{s}`", .{type_name}),
            .instead = null,
        },
        .unowned => .{
            .reason = try std.fmt.allocPrint(arena, "only the library, which declares `{s}`, may implement it for `{s}`", .{ trait_name, type_name }),
            .instead = null,
        },
        .declared, .primitive => .{
            .reason = try std.fmt.allocPrint(arena, "the library declares both `{s}` and `{s}`", .{ type_name, trait_name }),
            .instead = try std.fmt.allocPrint(arena, "wrap it in a type this program declares that implements `{s}`", .{trait_name}),
        },
    };
}

test "a module owning either side of an implementation may write it" {
    const trait_home = ModuleId.from(1);
    const type_home = ModuleId.from(2);
    const other = ModuleId.from(3);
    try testing.expect(ownsAnImplSide(trait_home, false, .{ .declared = type_home }, trait_home));
    try testing.expect(ownsAnImplSide(type_home, false, .{ .declared = type_home }, trait_home));
    try testing.expect(!ownsAnImplSide(other, false, .{ .declared = type_home }, trait_home));
    try testing.expect(ownsAnImplSide(other, true, .primitive, trait_home));
    try testing.expect(!ownsAnImplSide(other, false, .primitive, trait_home));
    try testing.expect(!ownsAnImplSide(other, true, .unowned, trait_home));
    try testing.expect(!ownsAnImplSide(other, false, .{ .declared = type_home }, .none));
    try testing.expect(!ownsAnImplSide(trait_home, true, .unnameable, trait_home));
}

/// Whether a closure body may change a capture binding: an owned capture
/// under `inout` invocation, and a place lent `inout`. A closure called for
/// reading cannot hold an `inout` capture at all, which the checker reports
/// at the capture rather than at each write.
pub fn captureIsMutable(capture: node.Convention, invocation: node.Convention) bool {
    return switch (capture) {
        .sink => invocation == .inout,
        .inout => true,
        .read => false,
    };
}

pub const ResolvedCapture = struct {
    binding: BindingId,
    source: ExprId,
    convention: node.Convention,
};

pub const CaptureLocation = struct {
    closure: ClosureId,
    index: u32,
};

const CaptureRange = struct { start: u32, end: u32 };

pub const ParameterOwner = union(enum) {
    declaration: DeclId,
    closure: ClosureId,
};

/// Both directions between a lambda expression and its source identity.
pub const ClosureMap = struct {
    of_expr: []const ClosureId = &.{},
    exprs: []const ExprId = &.{},

    pub fn deinit(self: *ClosureMap, gpa: std.mem.Allocator) void {
        gpa.free(self.of_expr);
        gpa.free(self.exprs);
        self.* = .{};
    }

    pub fn closureOf(self: *const ClosureMap, expr: ExprId) ClosureId {
        if (expr == .none or expr.index() >= self.of_expr.len) return .none;
        return self.of_expr[expr.index()];
    }

    pub fn exprOf(self: *const ClosureMap, closure: ClosureId) ExprId {
        return self.exprs[closure.index()];
    }

    pub fn count(self: *const ClosureMap) u32 {
        return @intCast(self.exprs.len);
    }

    pub fn table(
        self: *const ClosureMap,
        gpa: std.mem.Allocator,
        comptime T: type,
        fill: T,
    ) !Table(ClosureId, T) {
        return Table(ClosureId, T).of(gpa, self.count(), fill);
    }

    pub const Builder = struct {
        gpa: std.mem.Allocator,
        of_expr: []ClosureId,
        exprs: std.ArrayList(ExprId) = .empty,

        pub fn init(gpa: std.mem.Allocator, expr_count: u32) !Builder {
            const of_expr = try gpa.alloc(ClosureId, expr_count);
            @memset(of_expr, .none);
            return .{ .gpa = gpa, .of_expr = of_expr };
        }

        pub fn deinit(self: *Builder) void {
            self.gpa.free(self.of_expr);
            self.exprs.deinit(self.gpa);
            self.* = undefined;
        }

        pub fn add(self: *Builder, expr: ExprId) !ClosureId {
            std.debug.assert(expr != .none and expr.index() < self.of_expr.len);
            std.debug.assert(self.of_expr[expr.index()] == .none);
            const closure = ClosureId.at(@intCast(self.exprs.items.len));
            try self.exprs.append(self.gpa, expr);
            self.of_expr[expr.index()] = closure;
            return closure;
        }

        pub fn grow(self: *Builder, expr_count: u32) !void {
            if (expr_count <= self.of_expr.len) return;
            const before = self.of_expr.len;
            self.of_expr = try self.gpa.realloc(self.of_expr, expr_count);
            @memset(self.of_expr[before..], .none);
        }

        pub fn finish(self: *Builder) !ClosureMap {
            const exprs = try self.exprs.toOwnedSlice(self.gpa);
            const of_expr = self.of_expr;
            self.of_expr = &.{};
            return .{ .of_expr = of_expr, .exprs = exprs };
        }
    };
};

/// A scope's parent and the run of `scope_bindings` it declared.
pub const Scope = struct {
    /// The scope this one sits in; `.none` for a module's own, which is the
    /// root of every chain inside that module.
    parent: ScopeId,
    from: u32,
    to: u32,
};

/// Which binding each name reference names.
pub const Resolution = struct {
    /// Qualified variant selections, in declaration order. Generic
    /// substitution preserves these ordinals. Storage follows selections,
    /// with expected O(1) lookup by expanded expression ID.
    variant_ordinals: std.AutoHashMapUnmanaged(ExprId, VariantOrdinal) = .empty,
    /// The type name each alias's written type is headed by, followed
    /// through aliases: `Point` for `alias Spot = Point`, `Option` for
    /// `alias Maybe = Option[UInt8]`. An alias of a function, array or
    /// parameter type is headed by no declaration and has no row. What a
    /// path, a call or a bound through an alias reaches is read here.
    alias_heads: std.AutoHashMapUnmanaged(DeclId, BindingId) = .empty,
    /// The names of the operations implementations refused for an alias
    /// head declare. The refusal is the report, so a call reaching none of
    /// its operations is not reported missing a second time.
    refused_operations: std.AutoHashMapUnmanaged(StringId, void) = .empty,
    /// Generic-list bounds and trailing predicates normalized once while
    /// resolution has the complete written declaration environment.
    constraints: Constraints = .{},
    closures: ClosureMap = .{},
    capture_ranges: []const CaptureRange = &.{},
    captures: []const ResolvedCapture = &.{},
    capture_bindings: std.AutoHashMapUnmanaged(BindingId, CaptureLocation) = .empty,
    /// The first undeclared enclosing-body reference in each closure body.
    free_references: []const ExprId = &.{},
    /// Indexed by `ExprId`; `.none` for a name that resolved to nothing, and
    /// for every expression that is not a name.
    targets: []const BindingId,
    integer_selections: std.AutoHashMapUnmanaged(ExprId, IntegerSelection) = .empty,
    /// Selections written after a type's name, `Limits.default`, whose name
    /// some trait declares and the type's namespace holds as nothing but an
    /// operation, if it holds it at all, and every name selected after a type
    /// parameter, `T.default`. Which trait's
    /// operation such a name reaches depends on what the type implements or
    /// the parameter's bounds promise, so the checker settles it.
    trait_selections: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// Selections in an expression, `text.find`, whose head is a lexical
    /// binding that shadows an import of the same name in that file. A
    /// diagnostic about the selection says so, since the writer may have meant
    /// the module.
    shadowed_heads: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// The token spelling the binding each expression reaches, indexed by
    /// `ExprId`; `.none` wherever `targets` is.
    ///
    /// Recorded beside the target because the two are one decision, and because
    /// the tree does not always answer the second: `Shade.Dim` is a selection
    /// whose own main token is `Dim` and which settles on the enum, so a reader
    /// taking the expression's main token points at a name the expression does
    /// not reach. Where a use is written is this pass's answer, kept at the
    /// moment it is made rather than worked out again from the shape of a node.
    spelled: []const TokenId,
    /// The binding each name written outside an expression reaches, indexed by
    /// `TokenId`; `.none` for every token that is not one.
    ///
    /// An annotation, a type argument, a bound, an `impl` head and a `use` path
    /// are tokens rather than expressions, so `targets` holds none of them --
    /// and every consumer asking where a name is written would have had to
    /// re-resolve one, which is a second rule for what a name means. This pass
    /// already resolves each of them to mark what it reaches used; it records
    /// the answer at the same moment rather than throwing it away.
    ///
    /// One entry per token of the program, filled at the places that resolve
    /// one: a written type once per annotation, argument, field, parameter and
    /// return; a bound once per bound; an `impl` head and its trait once each;
    /// a `use` path's two elements once each. So the fill is bounded by what is
    /// written, and the table by what was lexed.
    written: []const BindingId,
    /// What each symbol is, so a caller of a local or an operand that is a
    /// function is a diagnosed mistake rather than a wrong answer.
    kinds: []const Kind,
    /// The statement that declared each local; `.none` for other kinds.
    stmts: []const StmtId,
    /// The declaration each symbol belongs to: itself for a function, the
    /// enclosing one for a parameter or a local.
    decls: []const DeclId,
    /// A parameter's position in its function's list.
    param_indices: []const u32,
    parameter_owners: []const ParameterOwner,
    /// The primitive each symbol names, and `.poison` for every symbol that
    /// names something else. Read through `builtinOf`, never directly.
    builtins: []const TypeId,
    /// Every type name a module can write, and the declaration it means.
    ///
    /// A written type is a name, and which declaration a name means is this
    /// pass's question -- so it answers it once, here, rather than leaving a
    /// later pass to rescan declarations and get a different answer for a
    /// re-export, an alias, or an ambient name.
    type_names: []const TypeName = &.{},
    /// Which rows of `type_names` carry each `(module, name)` pair.
    ///
    /// Both `declNamed` and `namedIn` read the flat list, so every written type
    /// name in the program cost its whole length -- and the list and the
    /// annotations both grow with the program, so checking a module of n
    /// declarations cost n squared. The chain is built from those same rows and
    /// walked in the order they were recorded, so the row each question settles
    /// on is the one the walk would have stopped at.
    named: Chain(.newest_first) = .empty,
    /// Which rows of `type_names` name a trait, chained under the module, in
    /// the order the module's scope records them.
    ///
    /// **Bound:** one position per trait row, so the traits a module can see
    /// cost that module's rows and no other module's.
    traits_seen: Chain(.oldest_first) = .empty,
    /// Every trait some module can name, once each, in the order of the first
    /// `type_names` row naming it. Read where an editor lists every trait the
    /// module cannot see, which is a question about the program's traits
    /// rather than about one module's rows.
    traits: []const DeclId = &.{},
    /// Which `(module, trait)` pairs have a trait row, so whether one module
    /// can name one trait is a lookup rather than a walk of its rows.
    ///
    /// **Bound:** one entry per trait row.
    sees: std.AutoHashMapUnmanaged(u64, void) = .empty,
    /// The members of every trait each module can name, one row per
    /// `(module, trait, member)`, in the order of the trait rows and then of
    /// the trait's declarations.
    ///
    /// **Bound:** the members of the traits each module can see, summed over
    /// modules -- the same product `type_names` already holds one row of per
    /// trait, times the members a trait declares. It holds because a row is
    /// made from a trait row and that trait's own member chain, never from
    /// the program's declarations.
    trait_members: []const TraitMember = &.{},
    /// Which rows of `trait_members` carry each `(module, name)`, so a call
    /// written in a module reads the traits it can see that declare its name
    /// and nothing else.
    members_named: Chain(.oldest_first) = .empty,
    /// Which rows of `trait_members` carry each name whatever the module,
    /// noting each member once under the first row that names its trait, so
    /// a report about a trait out of scope prepares each trait once.
    members_anywhere: Chain(.oldest_first) = .empty,
    /// What the prelude makes nameable everywhere, as the declarations it
    /// names rather than as the names.
    ///
    /// The same in every module, so one list rather than one per module. A
    /// pass below here resolves a written type by looking at the module that
    /// wrote it, and an ambient name is in no module's declarations -- this is
    /// what tells it the rest.
    prelude: []const DeclId = &.{},
    /// The prelude's `Tuple2` through `Tuple8`, indexed by arity less two,
    /// and `.none` for an arity the prelude does not publish. Tuple syntax
    /// names these by identity, so a module declaring its own `Tuple2`
    /// shadows the name and not the syntax. Read through `tupleDecl`.
    tuple_decls: TupleDecls = no_tuple_decls,
    /// The token that declares each binding: the `let`'s name, the parameter's
    /// name, the declaration's name, the binder in its pattern.
    ///
    /// Stored rather than reconstructed. Every consumer that wants a
    /// binding's spelling had to switch over the kind and reach into whichever
    /// table that kind lives in, and each new kind broke every one of them --
    /// the resolver had the token in hand and threw it away.
    tokens: []const TokenId,
    /// Which bindings a `use` made: a name bound to a declaration another
    /// module owns.
    ///
    /// Recorded where a re-export is settled, which is the one place the alias
    /// is made. A consumer that told one apart by comparing the token it was
    /// declared at against the name of the declaration it holds would be
    /// deciding again what this pass decided, and would answer differently the
    /// first time a second form of alias existed.
    reexported: FinishedBindingBits,
    /// Whether each binder was written as a field's own name, indexed by
    /// `BindingId`. A struct pattern's shorthand puts the field and the binder
    /// at one token, so the token that declares the binder is also the one
    /// naming the field.
    field_shorthand: FinishedBindingBits,
    /// How far each binding's own module passes the name on, indexed by
    /// `BindingId`. This is the alias declaration's reach for a re-export,
    /// rather than the visibility of the declaration it holds.
    reach: []const Reach,
    /// Whether each binding is in a module's scope because the prelude puts it
    /// in every one, indexed by `BindingId`.
    ///
    /// Kept beside `reach` because the two together decide whether a name may
    /// travel through a module -- asked once while a qualified name is settled
    /// and once by a caller listing what an import brings within reach.
    ambient: FinishedBindingBits,
    /// Whether each binding is read anywhere, indexed by `BindingId`.
    ///
    /// The unused check is what computes this, and a rule needing the same
    /// answer reads it here rather than walking for it again: a name a body
    /// never mentions is one question, and `[N-Unused]` already asks it.
    referenced: FinishedBindingBits,
    /// The reverse: which symbol a statement declared, indexed by StmtId, and
    /// `.none` for a statement that declares nothing. Stored rather than
    /// searched, because every consumer needs it once per statement and a scan
    /// would make that quadratic.
    binding_of_stmt: []const BindingId,
    /// The declaration the runtime calls, or `.none` where the program does
    /// not declare exactly one. Decided once, where the rule that there is
    /// exactly one is enforced.
    entry: DeclId = DeclId.none,
    /// Every `test fn` the program itself declares, in the order the walk
    /// reached them.
    ///
    /// Not in the order anything presents them. What a reader sees is ordered
    /// where it is written, and an order decided here as well would be one rule
    /// with two implementations. The library's own tests are absent: they
    /// belong to the library, which is tested as a program of its own.
    tests: []const Test = &.{},
    /// Where each declaration's parameter bindings begin, and the bindings
    /// themselves. Two passes want this and both used to work it out again --
    /// one by scanning every binding in the program per function, which is the
    /// program squared over a file of many small ones.
    param_starts: []const u32,
    params_of: []const BindingId,
    closure_param_starts: []const u32 = &.{},
    closure_params: []const BindingId = &.{},
    /// Every lexical scope the program writes, in the order the walk opened
    /// them.
    ///
    /// A module's own scope has no parent, so a program of several modules has
    /// one root per module -- which is what makes a body see its own module's
    /// declarations and no other's.
    scopes: []const Scope,
    /// The bindings every scope declared, concatenated, with each scope's
    /// `from` and `to` giving its own run. One array rather than a list per
    /// scope, because scopes close in the order they opened and a run is
    /// therefore contiguous.
    scope_bindings: []const BindingId,
    /// The scope each statement sits in, indexed by `StmtId`; `.none` for a
    /// statement no walk reached.
    scope_of_stmt: []const ScopeId,
    /// The scope each module's own run is, indexed by `ModuleId`.
    ///
    /// The bottom of every chain inside that module, written down so a caller
    /// standing nowhere in particular -- a cursor above the first declaration,
    /// a lookup of what an import brings within reach -- reaches the same run a
    /// body reaches by walking out of itself.
    module_scopes: []const ScopeId,
    /// The innermost scope open while each expression was resolved, indexed by
    /// `ExprId`; `.none` for an expression no walk reached.
    ///
    /// For a name that is the scope its target was found in, recorded where the
    /// target is so a name and the scope it was found from are one decision: a
    /// consumer that took the enclosing statement's scope instead would answer
    /// differently for a name in a match arm, whose scope no statement carries.
    ///
    /// For a block it is the scope the block opens rather than the one it sits
    /// in, because that is where its contents were resolved -- and a caller
    /// asking what is visible somewhere inside an expression is asking about
    /// exactly that.
    scope_of_expr: []const ScopeId,
    /// Every declaration written in a type's or a trait's own namespace, in
    /// the order they were written.
    ///
    /// The rows a name written after a type's name searches, kept so that
    /// listing what a namespace holds and looking one name up in it read the
    /// same recording. What is written in the braces and what every inherent
    /// `impl` writes are one namespace, and a trait implementation's members
    /// are in none: those are the rules `declareMember` recorded, and this is
    /// that record rather than a second reading of the declarations.
    namespaced: []const Namespaced = &.{},
    /// Which rows of `namespaced` each namespace holds.
    under: Chain(.newest_first) = .empty,
    /// Which rows of `namespaced` an inherent `impl` on each declared type
    /// wrote, keyed by the declaration's index.
    ///
    /// The same rows `under` chains, keyed by the type the block's head names
    /// rather than by the name it was written under. The two answer different
    /// questions: `under` is what a name written after a qualifier searches,
    /// which is a question about one module's namespace; this is what a value
    /// of a declared type answers to, which its type's declaration identifies
    /// however the block spelled it -- an alias or a re-export resolves to the
    /// same declaration. Which declaration a head names is settled where the
    /// block is resolved, so a reader of this chain does not decide ownership
    /// a second time.
    under_decl: Chain(.newest_first) = .empty,
    /// Which namespace each primitive's name opens.
    ///
    /// A primitive is declared by no module, so the namespace its name opens is
    /// whichever module wrote an inherent `impl` on it -- and the ownership
    /// rule leaves those to the standard library. One row per primitive, module
    /// and spelling, however many blocks that module writes, so a reader meets
    /// each member once; the list is the library's own and nothing a program
    /// writes lengthens it.
    builtin_namespaces: []const BuiltinNamespace = &.{},
    /// The implementations the compiler provides, in the order the prelude
    /// declares their traits.
    ///
    /// Decided here, where which declaration each prelude name is, is settled,
    /// and where coherence holds a written header against them. The checker
    /// turns each into a row of its own table rather than deciding a second
    /// time which pairs these are -- two answers to that would let a row the
    /// checker seeded be one no header was ever held against.
    ambient_impls: []const AmbientImpl = &.{},
    /// Which trait declares each signature, and which signatures each trait
    /// declares. One relation, so the checker reads the resolver's answer
    /// rather than working the same one out from the declarations again.
    signatures: Signatures = .{},
    /// The implementation each declaration is a member of, by declaration, and
    /// `.none` for every declaration none encloses.
    ///
    /// One relation, for the same reason: this pass walks the members to put
    /// an implementation's parameters in scope in them, and the checker asks
    /// the same question to say what `Self` is. Worked out twice they answered
    /// differently -- a member of an implementation the checker recorded
    /// nothing for was a member of nothing, and `Self` there became the bare
    /// constructor.
    impl_of_decl: []const DeclId = &.{},
    /// Which module holds each file, keyed by `FileId`.
    module_of_file: std.AutoHashMapUnmanaged(FileId, ModuleId) = .empty,
    /// Every pair of implementations already reported as one written twice,
    /// as the later declaration and the earlier one it repeats.
    ///
    /// Read by the overlap check, which would otherwise report the same pair
    /// again under its own rule: two implementations written identically
    /// overlap trivially, and a reader shown both diagnostics is shown one
    /// mistake twice. Recorded where the report is made rather than decided
    /// again there, because whether two implementations are the same one is
    /// this pass's question and the answer it gives is what the report stands
    /// on.
    duplicate_impls: std.AutoHashMapUnmanaged(u64, void) = .empty,
    /// The implementations resolution refused and reported. Overlapping
    /// another is the same mistake, so a later pass does not report it again.
    refused_impls: std.AutoHashMapUnmanaged(DeclId, void) = .empty,
    /// The one structural template each resolved trait declares.
    templates: std.AutoHashMapUnmanaged(DeclId, DeclId) = .empty,

    /// Erased source closures whose labels may escape the recorded lexical uses.
    unpaired_template_closures: std.AutoHashMapUnmanaged(ClosureId, void) = .empty,

    /// For a postfix call written on a value, `n.double()`, whose name reaches
    /// a free function from the call's module: that function, and the import
    /// it is reached through where it is not the module's own. Keyed by the
    /// callee. Read where the call reaches no operation, to show the call that
    /// does run the function; nothing is marked used by being recorded.
    postfix_functions: std.AutoHashMapUnmanaged(ExprId, PostfixFunction) = .empty,

    /// Marked calls whose callee starts from a function, a type, a trait or a
    /// module, `&make().change()` or `&Type.make()`: the `&` marks a call that
    /// lends no place. Decided here, where the callee's root is resolved, and
    /// read by the checker to word its refusal.
    unlent_marks: std.AutoHashMapUnmanaged(ExprId, void) = .empty,

    /// What a bracket holds, for each bracket whose contents also read as
    /// types: one directly before a call, or one after a path. Keyed by the
    /// index node. A bracket with no entry is an index.
    bracket_readings: std.AutoHashMapUnmanaged(ExprId, BracketReading) = .empty,

    /// What kind of name each source token declaring one was checked as under
    /// [N-Case], keyed by that token. A rename reads it to hold a new name to
    /// the same case. Library names a resumed run did not check are absent.
    name_kinds: std.AutoHashMapUnmanaged(TokenId, name_case.Kind) = .empty,

    /// Functions and imports nothing uses apart from postfix calls whose names
    /// reach them. Whether such a call used one depends on what it reached,
    /// which the checker decides; it reports the ones every such call left
    /// unused.
    deferred_unused: []const BindingId = &.{},

    /// Immutable bindings a `&` lends as a receiver, `&x.op()`, or as an
    /// argument, `f(&x)`. Whether the `&` belongs there depends on the
    /// parameter it meets, which the checker decides: where the parameter is
    /// not `inout` the `&` itself is refused, and the binding being `let` is
    /// not a second mistake. The checker reports the rest.
    deferred_immutable: []const DeferredImmutable = &.{},

    /// A `&` whose immutable root the checker reports.
    pub const DeferredImmutable = struct {
        /// The marked call for a receiver, or the `&` expression for an
        /// argument: what the checker holds when it meets the parameter.
        mark: ExprId,
        /// The name at the root of the lent place.
        name: ExprId,
        binding: BindingId,
    };

    /// A free function a postfix call's name reaches, and how to name it.
    pub const PostfixFunction = struct {
        function: BindingId,
        /// The import binding it is reached through, or `.none` where the
        /// call's own module declares it.
        through: BindingId = .none,
        /// Whether a lexical binding at the call shadows `through`, so the
        /// call cannot be written through that name there.
        shadowed: bool = false,
    };

    /// Whether the brackets before a call hold type arguments or an index.
    pub const BracketReading = union(enum) {
        /// The head names a function, or a trait's operation through a type,
        /// so the brackets hold its type arguments.
        type_arguments,
        /// The head names anything else, so the bracket indexes it.
        index,
        /// The head reaches nothing, which is the one mistake to report: the
        /// brackets are read as neither an index nor types.
        unresolved,
        /// The head selects a name from a value. A method of the value's type
        /// takes the brackets as type arguments, and a field is indexed; the
        /// checker decides which. What resolving each reading would report
        /// waits here until then.
        member: Deferred,

        pub const Deferred = struct {
            index_reports: []const Diagnostic,
            type_reports: []const Diagnostic,
        };
    };

    /// What the brackets before a call hold, or null where they have only
    /// the index reading.
    pub fn bracketReading(self: *const Resolution, bracket: ExprId) ?BracketReading {
        return self.bracket_readings.get(bracket);
    }

    test "a bracket before a call reads by what its head names" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\struct Box { items: [UInt8; 2] }
            \\fn pick[T](value: T) -> T { value }
            \\fn main() -> UInt8 {
            \\    let box = Box { items = [1, 2] }
            \\    let steps = [main, main]
            \\    let i = 1
            \\    pick[UInt8](box.items[0]) + box.first[UInt8]() + steps[i]()
            \\}
            \\
        );
        const ast = &result.ast;
        var readings: [3]?Resolution.BracketReading = .{ null, null, null };
        var found: usize = 0;
        for (0..ast.exprCount()) |i| {
            const id = ExprId.at(@intCast(i));
            if (ast.exprTag(id) != .index or ast.bracketTypes(id) == null) continue;
            if (found < readings.len) readings[found] = result.res.bracketReading(id);
            found += 1;
        }
        try testing.expectEqual(@as(usize, 3), found);
        try testing.expectEqual(Resolution.BracketReading.type_arguments, std.meta.activeTag(readings[0].?));
        try testing.expectEqual(Resolution.BracketReading.member, std.meta.activeTag(readings[1].?));
        try testing.expectEqual(Resolution.BracketReading.index, std.meta.activeTag(readings[2].?));
    }

    /// The free function a postfix call's name reaches, where it reaches one.
    pub fn postfixFunction(self: *const Resolution, callee: ExprId) ?PostfixFunction {
        return self.postfix_functions.get(callee);
    }

    /// Whether a marked call's callee lends no place.
    pub fn marksNoPlace(self: *const Resolution, call: ExprId) bool {
        return self.unlent_marks.contains(call);
    }

    test "a postfix call's name reaches the free function of that name" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\fn double(value: UInt8) -> UInt8 { value * 2 }
            \\fn main() -> UInt8 {
            \\    let n: UInt8 = 4
            \\    n.double() + n.triple()
            \\}
            \\
        );
        // Whether `double` is used depends on what the call reaches, so the
        // resolver leaves it to the checker rather than reporting it.
        try testing.expectEqual(@as(u32, 0), result.errors);
        try testing.expectEqual(@as(usize, 1), result.res.deferred_unused.len);
        try testing.expectEqualStrings("double", result.ast.tokenText(result.res.declaringToken(result.res.deferred_unused[0])));
        const ast = &result.ast;
        var found: u32 = 0;
        for (0..ast.exprCount()) |i| {
            const e = ExprId.at(@intCast(i));
            if (ast.exprTag(e) != .field) continue;
            const named = result.res.postfixFunction(e);
            if (std.mem.eql(u8, ast.tokenText(ast.exprMain(e)), "double")) {
                try testing.expect(named != null);
                try testing.expectEqualStrings("double", ast.tokenText(result.res.declaringToken(named.?.function)));
                try testing.expectEqual(BindingId.none, named.?.through);
                found += 1;
            } else try testing.expect(named == null);
        }
        try testing.expectEqual(@as(u32, 1), found);
    }

    /// One `test fn`, and the name everything outside the compiler calls it.
    pub const Test = struct {
        decl: DeclId,
        expects_trap: bool,
        /// Owned by the resolution, and freed with it.
        qualified_name: []const u8,
    };

    /// The kind of name `at` declares, or null where it declares none that
    /// [N-Case] checked.
    pub fn nameKindAt(self: *const Resolution, at: TokenId) ?name_case.Kind {
        return self.name_kinds.get(at);
    }

    pub fn deinit(self: *Resolution, gpa: std.mem.Allocator) void {
        self.variant_ordinals.deinit(gpa);
        self.alias_heads.deinit(gpa);
        self.refused_operations.deinit(gpa);
        self.integer_selections.deinit(gpa);
        self.trait_selections.deinit(gpa);
        self.shadowed_heads.deinit(gpa);
        self.constraints.deinit(gpa);
        for (self.tests) |t| gpa.free(t.qualified_name);
        gpa.free(self.tests);
        gpa.free(self.targets);
        gpa.free(self.spelled);
        gpa.free(self.written);
        gpa.free(self.kinds);
        gpa.free(self.stmts);
        gpa.free(self.decls);
        gpa.free(self.param_indices);
        gpa.free(self.parameter_owners);
        gpa.free(self.builtins);
        gpa.free(self.prelude);
        gpa.free(self.type_names);
        self.named.deinit(gpa);
        self.traits_seen.deinit(gpa);
        gpa.free(self.traits);
        self.sees.deinit(gpa);
        gpa.free(self.trait_members);
        self.members_named.deinit(gpa);
        self.members_anywhere.deinit(gpa);
        gpa.free(self.namespaced);
        self.under.deinit(gpa);
        self.under_decl.deinit(gpa);
        gpa.free(self.builtin_namespaces);
        gpa.free(self.ambient_impls);
        gpa.free(self.tokens);
        self.reexported.deinit(gpa);
        self.field_shorthand.deinit(gpa);
        gpa.free(self.reach);
        self.referenced.deinit(gpa);
        self.ambient.deinit(gpa);
        gpa.free(self.binding_of_stmt);
        gpa.free(self.param_starts);
        gpa.free(self.params_of);
        gpa.free(self.closure_param_starts);
        gpa.free(self.closure_params);
        gpa.free(self.free_references);
        gpa.free(self.capture_ranges);
        gpa.free(self.captures);
        self.capture_bindings.deinit(gpa);
        self.closures.deinit(gpa);
        gpa.free(self.scopes);
        gpa.free(self.scope_bindings);
        gpa.free(self.module_scopes);
        gpa.free(self.scope_of_stmt);
        gpa.free(self.scope_of_expr);
        self.signatures.deinit(gpa);
        gpa.free(self.impl_of_decl);
        self.module_of_file.deinit(gpa);
        self.duplicate_impls.deinit(gpa);
        self.refused_impls.deinit(gpa);
        self.templates.deinit(gpa);
        self.unpaired_template_closures.deinit(gpa);
        self.postfix_functions.deinit(gpa);
        self.unlent_marks.deinit(gpa);
        self.bracket_readings.deinit(gpa);
        self.name_kinds.deinit(gpa);
        gpa.free(self.deferred_unused);
        gpa.free(self.deferred_immutable);
        self.* = undefined;
    }

    /// Whether resolution refused this `impl`.
    pub fn isRefusedImpl(self: *const Resolution, impl: DeclId) bool {
        return self.refused_impls.contains(impl);
    }

    test "an implementation resolution refused is the one isRefusedImpl names" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const result = try resolveSource(arena.allocator(),
            \\struct Box { v: UInt8 }
            \\impl Box { fn get(self: Self) -> UInt8 { self.v } }
            \\impl UInt8 { fn twice(self: Self) -> UInt8 { self } }
            \\fn main() -> UInt8 { let b: Box = .{ v = 1 }
            \\b.get() }
        );
        var refused: u32 = 0;
        var kept: u32 = 0;
        for (0..result.ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (result.ast.declTag(d) != .impl_) continue;
            if (result.res.isRefusedImpl(d)) refused += 1 else kept += 1;
        }
        try testing.expectEqual(@as(u32, 1), refused);
        try testing.expectEqual(@as(u32, 1), kept);
    }

    /// Whether the pair was already reported as one implementation written
    /// twice.
    pub fn reportedDuplicate(self: *const Resolution, earlier: DeclId, later: DeclId) bool {
        return self.duplicate_impls.contains(duplicateKey(earlier, later));
    }

    fn duplicateKey(earlier: DeclId, later: DeclId) u64 {
        return (@as(u64, @intFromEnum(earlier)) << 32) | @intFromEnum(later);
    }

    /// The implementation `d` is a member of, or `.none` where none is.
    ///
    /// The relation this pass built while it put each implementation's
    /// parameters in scope in its members. Read rather than worked out again:
    /// a second derivation is a second population, and the one a walk over
    /// what the checker recorded produced was missing every implementation
    /// whose trait names nothing.
    pub fn implEnclosing(self: *const Resolution, d: DeclId) DeclId {
        if (d == DeclId.none or d.index() >= self.impl_of_decl.len) return DeclId.none;
        return self.impl_of_decl[d.index()];
    }

    fn scopeCount(self: *const Resolution) u32 {
        return @intCast(self.scopes.len);
    }

    fn parentScope(self: *const Resolution, sc: ScopeId) ScopeId {
        if (sc == .none) return .none;
        return self.scopes[sc.index()].parent;
    }

    fn visibleAt(
        self: *const Resolution,
        gpa: std.mem.Allocator,
        s: StmtId,
        out: *std.ArrayList(BindingId),
    ) !void {
        return self.visibleIn(gpa, self.scopeOfStmt(s), out);
    }

    /// The scope a statement sits in.
    pub fn scopeOfStmt(self: *const Resolution, s: StmtId) ScopeId {
        if (s == StmtId.none or s.index() >= self.scope_of_stmt.len) return .none;
        return self.scope_of_stmt[s.index()];
    }

    /// The innermost scope open while an expression was resolved, or `.none`
    /// where no walk reached it.
    pub fn scopeOfExpr(self: *const Resolution, e: ExprId) ScopeId {
        if (e == ExprId.none or e.index() >= self.scope_of_expr.len) return .none;
        return self.scope_of_expr[e.index()];
    }

    /// The scope holding one module's own run: its declarations, its imports,
    /// what was re-exported to it and what the prelude gave it.
    pub fn moduleScope(self: *const Resolution, m: ModuleId) ScopeId {
        if (m == .none or m.index() >= self.module_scopes.len) return .none;
        return self.module_scopes[m.index()];
    }

    /// The bindings one scope declared, in the order they were declared.
    pub fn declaredIn(self: *const Resolution, sc: ScopeId) []const BindingId {
        if (sc == .none) return &.{};
        const s = self.scopes[sc.index()];
        return self.scope_bindings[s.from..s.to];
    }

    /// Every binding visible in a scope: its own run and every run above it,
    /// innermost scope first and, within a scope, latest declaration first.
    ///
    /// That order is the chain searched from the inside out, so between scopes
    /// it is what a lookup found: an inner scope's binding of a name comes
    /// before an outer scope's of that name, which is the shadowing a nested
    /// block does.
    ///
    /// Within one scope it is declaration order reversed, which is a weaker
    /// claim. A scope records what it declared and not where, so where one
    /// scope declares a name twice both entries are here and the later one
    /// leads at every point in that scope, including the points above the
    /// second declaration -- where the name reaches the first. Which binding a
    /// written name reached is `targetOf`, recorded where the resolver settled
    /// it; this answers what is in scope, which is the wider question.
    ///
    /// It costs the size of the answer and the depth of the nesting, and
    /// nothing about the program: a scope's run is a slice, and each is
    /// appended whole. `out` is emptied first, so one list serves a caller
    /// asking about many points.
    pub fn visibleIn(
        self: *const Resolution,
        gpa: std.mem.Allocator,
        sc: ScopeId,
        out: *std.ArrayList(BindingId),
    ) !void {
        out.clearRetainingCapacity();
        var at = sc;
        while (at != .none) : (at = self.scopes[at.index()].parent) {
            const run = self.declaredIn(at);
            const written = try out.addManyAsSlice(gpa, run.len);
            for (written, 0..) |*binding, i| binding.* = run[run.len - 1 - i];
        }
    }

    /// Every binding `writing` may reach through `holding`, in the order the
    /// holding module's scope keeps them.
    ///
    /// The rule `member` settles a qualified name by, read off the finished
    /// tables: a name in the module's own run that is not a module of its own,
    /// is not there because the prelude puts it everywhere, and whose
    /// declaration passes it on. Written here rather than beside each caller,
    /// because what crosses a module boundary is one question and a second
    /// answer would offer a name the compiler refuses.
    ///
    /// Costs the module's own run, which is a slice, and nothing about the
    /// program. `out` is emptied first, so one list serves many modules.
    pub fn reachableThrough(
        self: *const Resolution,
        gpa: std.mem.Allocator,
        program: *const Program,
        holding: ModuleId,
        writing: ModuleId,
        out: *std.ArrayList(BindingId),
    ) !void {
        out.clearRetainingCapacity();
        for (self.declaredIn(self.moduleScope(holding))) |b| {
            if (!nameableFromOutside(self.kindOf(b), self.isAmbient(b))) continue;
            if (!reachableFrom(program, self.namingReachOf(b), holding, writing)) continue;
            try out.append(gpa, b);
        }
    }

    /// The `import` that bound a module name, or `.none` where the binding is
    /// not a module's.
    pub fn importOf(self: *const Resolution, b: BindingId) DeclId {
        if (b == BindingId.none or self.kinds[b.index()] != .module) return DeclId.none;
        return self.decls[b.index()];
    }

    /// The alias a written name token reached when it was resolved, or null
    /// where it reached anything else. The one test of whether a written name
    /// is an alias, for a bare name, a name after a module's and a bound's.
    pub fn aliasReachedBy(self: *const Resolution, tok: TokenId) ?DeclId {
        const b = self.writtenAt(tok);
        if (b == BindingId.none or self.kindOf(b) != .type_alias) return null;
        return self.declaredBy(b);
    }

    test "aliasReachedBy answers for a name that reached an alias and for no other" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const result = try resolveSource(arena.allocator(),
            \\struct Cell { v: UInt8 }
            \\alias Spot = Cell
            \\fn _read(_a: Spot, _b: Cell) {}
            \\fn main() -> UInt8 { 0 }
        );
        const ast = &result.ast;
        const read = declSpelledIn(ast, .{ .start = 0, .end = ast.declCount() }, "_read");
        const params = ast.declParams(read);
        const alias = declSpelledIn(ast, .{ .start = 0, .end = ast.declCount() }, "Spot");
        try testing.expectEqual(alias, result.res.aliasReachedBy(params[0].written.name).?);
        try testing.expect(result.res.aliasReachedBy(params[1].written.name) == null);
        try testing.expect(result.res.aliasReachedBy(TokenId.none) == null);
    }

    /// The declaration a type name means in a module, or null where the
    /// module cannot write that name.
    pub fn typeNamed(self: *const Resolution, m: ModuleId, name: StringId) ?DeclId {
        return self.declNamed(m, name, .declared_type);
    }

    /// The binding a type name stands for as a path's head, a callee or a
    /// bound: an alias answers with the type name its written type is headed
    /// by, or `.none` where none heads it, and every other binding with itself.
    pub fn throughAlias(self: *const Resolution, b: BindingId) BindingId {
        if (b == BindingId.none or self.kindOf(b) != .type_alias) return b;
        return self.alias_heads.get(self.decls[b.index()]) orelse .none;
    }

    /// The declaration a trait name means in a module, or null where the
    /// module cannot write that name.
    ///
    /// Asked for the same reason a type name is: a name is unique only within
    /// a module, so what a bound admits and what a call reaches are decided by
    /// which declaration the name reaches from where it is written. Answered
    /// from the same table, because "what does this name reach here" is one
    /// question however the answer is used.
    /// The module a file belongs to, or `.none` where no module holds it.
    pub fn moduleOfFile(self: *const Resolution, f: FileId) ModuleId {
        return self.module_of_file.get(f) orelse .none;
    }

    pub fn traitNamed(self: *const Resolution, m: ModuleId, name: StringId) ?DeclId {
        return self.declNamed(m, name, .trait);
    }

    /// How a file writes the `use` that brings `trait` into scope.
    pub const UseRoute = struct {
        /// The module name written before the trait's name.
        module: []const u8,
        /// The import the file must write first, or null where it already
        /// imports that module.
        import: ?[]const u8,
    };

    /// The `use` a file writes to bring `trait` into scope, answered for the
    /// diagnostic that asks for it and for the editor's fix that writes it.
    ///
    /// A module the file imports that declares the trait or passes it on is
    /// written as the import binds it, alias included. Otherwise the module
    /// enclosing a nested library module is named, or else the declaring
    /// module, with the import that reaches it. The answer depends on where
    /// the trait is declared, not on what else the program loads. Costs the
    /// file's module's imports, and nothing about the program.
    pub fn useRoute(
        self: *const Resolution,
        program: *const Program,
        ast: *const Ast,
        file: FileId,
        trait: DeclId,
    ) UseRoute {
        const writing = self.moduleOfFile(file);
        const declaring = program.moduleOf(trait);
        const name = ast.tokenName(ast.declName(trait));
        if (writing != .none) for (program.get(writing).imports) |imported| {
            if (imported.module == .none) continue;
            const binds = ast.declName(imported.decl);
            if (ast.fileOf(binds) != file) continue;
            if (imported.module == declaring or self.passesOn(program, imported.module, writing, name, trait))
                return .{ .module = ast.tokenText(binds), .import = null };
        };
        // A trait a nested library module declares, as `std.io.core` declares
        // `Writer`, is named through the module enclosing it, `std.io`. The
        // library passes every public trait of a nested module on through the
        // module enclosing it, which a test of the library's layout holds, so
        // the answer is the same whether or not this program loads that
        // module. Anything else is named by the module that declares it.
        const path = program.modulePath(declaring);
        if (program.get(declaring).library) if (std.mem.lastIndexOfScalar(u8, path, '.')) |dot| {
            const enclosing = path[0..dot];
            if (std.mem.lastIndexOfScalar(u8, enclosing, '.')) |named| {
                return .{ .module = enclosing[named + 1 ..], .import = enclosing };
            }
        };
        return .{ .module = program.get(declaring).name, .import = if (path.len == 0) null else path };
    }

    /// Whether `writing` can name `decl` as `name` through `holding`: the
    /// rule `use holding.name` is settled by, read off the finished tables.
    fn passesOn(self: *const Resolution, program: *const Program, holding: ModuleId, writing: ModuleId, name: StringId, decl: DeclId) bool {
        var rows = self.rowsNamed(holding, name);
        while (rows.next()) |at| {
            const row = self.type_names[at];
            if (row.decl != decl) continue;
            if (!nameableFromOutside(self.kindOf(row.binding), self.isAmbient(row.binding))) continue;
            if (reachableFrom(program, self.namingReachOf(row.binding), holding, writing)) return true;
        }
        return false;
    }

    /// The key the rows of `type_names` are chained on.
    fn namedKey(m: ModuleId, name: StringId) u64 {
        return (@as(u64, @intFromEnum(m)) << 32) | @intFromEnum(name);
    }

    /// The rows for `(module, name)`, in the order they were recorded.
    fn rowsNamed(self: *const Resolution, m: ModuleId, name: StringId) Chain(.newest_first).Walk {
        return self.named.walk(namedKey(m, name));
    }

    fn declNamed(self: *const Resolution, m: ModuleId, name: StringId, kind: Kind) ?DeclId {
        var rows = self.rowsNamed(m, name);
        while (rows.next()) |at| {
            const t = self.type_names[at];
            if (t.kind == kind) return t.decl;
        }
        return null;
    }

    /// The binding a type name reaches in a module, or null where the module
    /// cannot write that name.
    ///
    /// The same table `typeNamed` reads, answering with the binding rather than
    /// what it declares -- which is what a primitive needs, because it declares
    /// nothing.
    pub fn namedIn(self: *const Resolution, m: ModuleId, name: StringId) ?BindingId {
        // A token that is not an identifier carries no name, and `()` is such a
        // token. Nothing is asking about a name in that case, so nothing may be
        // found -- a primitive the program never spells carries `.none` too.
        if (name == .none) return null;
        var rows = self.rowsNamed(m, name);
        if (rows.next()) |at| return self.type_names[at].binding;
        return null;
    }

    /// The traits `m` can name, in the order its scope records them.
    pub fn traitsSeenBy(self: *const Resolution, m: ModuleId) TraitsSeen {
        return .{ .of = self, .rows = self.traits_seen.walk(@intFromEnum(m)) };
    }

    test "the traits a module sees are its trait names, in scope order" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\struct Door { width: UInt8 }
            \\trait Shut { fn close(x: Self) -> UInt8 }
            \\trait Latch { fn close(x: Self) -> UInt8 }
            \\impl Shut for Door { fn close(x: Self) -> UInt8 { x.width } }
            \\impl Latch for Door { fn close(x: Self) -> UInt8 { x.width } }
            \\fn main() -> UInt8 {
            \\    let door: Door = .{ width = 1 }
            \\    Shut.close(door)
            \\}
            \\
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;

        var seen = result.res.traitsSeenBy(.from(0));
        try testing.expectEqualStrings("Shut", ast.tokenText(ast.declName(seen.next().?)));
        try testing.expectEqualStrings("Latch", ast.tokenText(ast.declName(seen.next().?)));
        try testing.expect(seen.next() == null);
        try testing.expectEqual(@as(usize, 2), result.res.traits.len);
    }

    pub const TraitsSeen = struct {
        of: *const Resolution,
        rows: Chain(.oldest_first).Walk,

        pub fn next(self: *TraitsSeen) ?DeclId {
            return self.of.type_names[self.rows.next() orelse return null].decl;
        }
    };

    /// Whether `m` can name `trait`: the same rows `traitsSeenBy` walks,
    /// asked of one trait.
    pub fn seesTrait(self: *const Resolution, m: ModuleId, trait: DeclId) bool {
        return self.sees.contains(seesKey(m, trait));
    }

    /// The key the entries of `sees` are kept under.
    fn seesKey(m: ModuleId, trait: DeclId) u64 {
        return (@as(u64, @intFromEnum(m)) << 32) | @intFromEnum(trait);
    }

    test "a module sees the traits its rows name and no other" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\struct Door { width: UInt8 }
            \\trait Shut { fn close(x: Self) -> UInt8 }
            \\impl Shut for Door { fn close(x: Self) -> UInt8 { x.width } }
            \\fn main() -> UInt8 {
            \\    let door: Door = .{ width = 1 }
            \\    Shut.close(door)
            \\}
            \\
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        const all: node.DeclRange = .{ .start = 0, .end = ast.declCount() };
        try testing.expect(result.res.seesTrait(.from(0), declSpelledIn(ast, all, "Shut")));
        try testing.expect(!result.res.seesTrait(.from(0), declSpelledIn(ast, all, "Door")));
        try testing.expect(!result.res.seesTrait(.from(1), declSpelledIn(ast, all, "Shut")));
    }

    /// The members named `name` that the traits `m` can name declare, in the
    /// order of `traitsSeenBy` and then of each trait's declarations.
    ///
    /// **Bound:** the rows under one `(module, name)` key, which is what the
    /// module's traits declare under that name and nothing about the rest of
    /// the program.
    pub fn traitMembersNamed(self: *const Resolution, m: ModuleId, name: StringId) TraitMembers {
        return .{ .of = self, .rows = self.members_named.walk(namedKey(m, name)) };
    }

    test "a name's trait members are read from the traits the module sees, in order" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\struct Door { width: UInt8 }
            \\trait Shut { fn close(x: Self) -> UInt8
            \\    fn open(x: Self) -> UInt8 }
            \\trait Latch { fn close(x: Self) -> UInt8
            \\    type Key }
            \\impl Shut for Door {
            \\    fn close(x: Self) -> UInt8 { x.width }
            \\    fn open(x: Self) -> UInt8 { x.width }
            \\}
            \\impl Latch for Door { fn close(x: Self) -> UInt8 { x.width }
            \\    type Key = UInt8 }
            \\fn main() -> UInt8 {
            \\    let door: Door = .{ width = 1 }
            \\    Shut.close(door)
            \\}
            \\
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        const all: node.DeclRange = .{ .start = 0, .end = ast.declCount() };
        const shut = declSpelledIn(ast, all, "Shut");
        const latch = declSpelledIn(ast, all, "Latch");

        var closes = result.res.traitMembersNamed(.from(0), ast.tokenName(ast.declName(declSpelledIn(ast, all, "close"))));
        const first = closes.next().?;
        try testing.expectEqual(shut, first.trait);
        try testing.expectEqualStrings("close", ast.tokenText(ast.declName(first.member)));
        const second = closes.next().?;
        try testing.expectEqual(latch, second.trait);
        try testing.expectEqualStrings("close", ast.tokenText(ast.declName(second.member)));
        try testing.expect(closes.next() == null);

        var keys = result.res.traitMembersNamed(.from(0), ast.tokenName(ast.declName(declSpelledIn(ast, all, "Key"))));
        const key = keys.next().?;
        try testing.expectEqual(latch, key.trait);
        try testing.expectEqual(node.Decl.Tag.associated_type, ast.declTag(key.member));
        try testing.expect(keys.next() == null);

        var widths = result.res.traitMembersNamed(.from(0), ast.tokenName(ast.declName(declSpelledIn(ast, all, "Door"))));
        try testing.expect(widths.next() == null);
    }

    /// The members named `name` of every trait some module can name, each
    /// member once, in the order the traits were first named.
    ///
    /// **Bound:** the rows under one name, which is what the program's traits
    /// declare under it.
    pub fn traitMembersNamedAnywhere(self: *const Resolution, name: StringId) TraitMembers {
        return .{ .of = self, .rows = self.members_anywhere.walk(@intFromEnum(name)) };
    }

    test "a trait two modules name declares each member once anywhere" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        var trees = Modules.init(gpa, &sink, &interner);
        defer trees.deinit();

        const app_decls = try trees.add(&.{.{
            .file = .from(0),
            .source = .{ .path = "app/main.lin", .text =
            \\import support
            \\use support.Shut
            \\struct Door { width: UInt8 }
            \\impl Shut for Door { fn close(x: Self) -> UInt8 { x.width } }
            \\fn main() -> UInt8 {
            \\    let door: Door = .{ width = 1 }
            \\    Shut.close(door)
            \\}
            },
        }});
        const support_decls = try trees.add(&.{.{
            .file = .from(1),
            .source = .{ .path = "support/main.lin", .text =
            \\pub trait Shut { fn close(x: Self) -> UInt8 }
            },
        }});
        const ast = try trees.finish();
        var imports = [_]program_mod.Import{.{
            .decl = DeclId.at(app_decls.start),
            .module = .from(1),
        }};
        var modules = [_]program_mod.Module{
            .{ .name = "app", .dir = "app", .files = &.{.from(0)}, .decls = app_decls, .imports = &imports },
            .{ .name = "support", .dir = "support", .files = &.{.from(1)}, .decls = support_decls, .imports = &.{}, .root = .from(1) },
        };
        const program: Program = .{ .modules = &modules, .ast = ast };
        var result = try resolve(gpa, &program, &interner, &sink, .program);
        defer result.expanded.deinit(gpa);
        defer result.resolution.deinit(gpa);
        try testing.expectEqual(@as(u32, 0), sink.error_count);

        const shut = declSpelledIn(&ast, support_decls, "Shut");
        const close = ast.tokenName(ast.declName(declSpelledIn(&ast, support_decls, "close")));

        // Both modules name the trait, so each sees its member under the name.
        for ([_]ModuleId{ .from(0), .from(1) }) |m| {
            var seen = result.resolution.traitsSeenBy(m);
            try testing.expectEqual(shut, seen.next().?);
            try testing.expect(seen.next() == null);
            var named = result.resolution.traitMembersNamed(m, close);
            try testing.expectEqual(shut, named.next().?.trait);
            try testing.expect(named.next() == null);
        }

        // The member is one declaration, so it is offered once whatever names it.
        var anywhere = result.resolution.traitMembersNamedAnywhere(close);
        try testing.expectEqual(shut, anywhere.next().?.trait);
        try testing.expect(anywhere.next() == null);
        try testing.expectEqual(@as(usize, 1), result.resolution.traits.len);
        try testing.expectEqual(shut, result.resolution.traits[0]);
    }

    pub const TraitMembers = struct {
        of: *const Resolution,
        rows: Chain(.oldest_first).Walk,

        pub fn next(self: *TraitMembers) ?TraitMember {
            return self.of.trait_members[self.rows.next() orelse return null];
        }
    };

    /// The key the rows of `namespaced` are chained on.
    fn underKey(m: ModuleId, owner: StringId) u64 {
        return (@as(u64, @intFromEnum(m)) << 32) | @intFromEnum(owner);
    }

    /// The bindings one namespace holds, in the order they were written.
    ///
    /// The plural of the lookup a written name makes: same rows, same key, so
    /// a caller listing what may follow a dot and the pass deciding what a
    /// name after one reaches cannot come to disagree about what a namespace
    /// holds.
    ///
    /// Costs one lookup and the length of the answer, which is what that
    /// namespace holds and never what the program holds.
    pub fn membersUnder(self: *const Resolution, m: ModuleId, owner: StringId) Members {
        return .{ .of = self, .rows = self.under.walk(underKey(m, owner)) };
    }

    /// The bindings every inherent `impl` on a declared type wrote, in the
    /// order they were written.
    ///
    /// What a caller holding a value asks, where `membersUnder` is what a
    /// caller holding a qualifier asks: a value carries no module and no
    /// spelling, only the declaration its type came from, and that is the key.
    ///
    /// Costs one lookup and the length of the answer, which is what that type
    /// declares and never what the program holds.
    pub fn membersOfType(self: *const Resolution, d: DeclId) Members {
        return .{ .of = self, .rows = self.under_decl.walk(@intFromEnum(d)) };
    }

    test "a type's members are the ones its inherent blocks wrote, in order" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\struct Door { width: UInt8 }
            \\struct Wall { height: UInt8 }
            \\trait Shut { fn close(x: Self) -> UInt8 }
            \\impl Door { fn open(self: Door) -> UInt8 { self.width } }
            \\impl Shut for Door { fn close(x: Self) -> UInt8 { x.width } }
            \\impl Wall { fn paint(self: Wall) -> UInt8 { self.height } }
            \\impl Door { fn lock(self: Door) -> UInt8 { self.width } }
            \\fn main() -> UInt8 {
            \\    let door: Door = .{ width = 1 }
            \\    let wall: Wall = .{ height = 2 }
            \\    door.open() + door.lock() + wall.paint() + Shut.close(door)
            \\}
            \\
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        const all: node.DeclRange = .{ .start = 0, .end = ast.declCount() };

        var doors = result.res.membersOfType(declSpelledIn(ast, all, "Door"));
        try testing.expectEqualStrings("open", ast.tokenText(ast.declName(result.res.declaredBy(doors.next().?))));
        try testing.expectEqualStrings("lock", ast.tokenText(ast.declName(result.res.declaredBy(doors.next().?))));
        try testing.expect(doors.next() == null);

        var walls = result.res.membersOfType(declSpelledIn(ast, all, "Wall"));
        try testing.expectEqualStrings("paint", ast.tokenText(ast.declName(result.res.declaredBy(walls.next().?))));
        try testing.expect(walls.next() == null);

        var traits = result.res.membersOfType(declSpelledIn(ast, all, "Shut"));
        try testing.expect(traits.next() == null);
    }

    pub const Members = struct {
        of: *const Resolution,
        rows: Chain(.newest_first).Walk,

        pub fn next(self: *Members) ?BindingId {
            return self.of.namespaced[self.rows.next() orelse return null].binding;
        }
    };

    /// The primitive a name reaches, or null where it reaches something else.
    ///
    /// The one place that answers "is this a builtin". It was a token-tag test
    /// in four passes, which is one question with four answers that could come
    /// to disagree once a tenth primitive or an alias existed.
    pub fn builtinNamed(self: *const Resolution, m: ModuleId, name: StringId) ?TypeId {
        return self.builtinOf(self.namedIn(m, name) orelse return null);
    }

    /// The primitive a binding names, or null where it names something else.
    pub fn builtinOf(self: *const Resolution, b: BindingId) ?TypeId {
        if (b == BindingId.none) return null;
        return builtinNames(self.kindOf(b), self.builtins[b.index()]);
    }

    pub fn kindOf(self: *const Resolution, b: BindingId) Kind {
        return self.kinds[b.index()];
    }

    /// The declaration a symbol *is* — a function, a type, a trait, a constant
    /// or a type a trait declares.
    ///
    /// Split from `enclosingDecl` deliberately. One accessor meaning "itself"
    /// for a declaration and "the one it sits in" for a parameter is always
    /// valid and usually wrong: it returns a good `DeclId` from the wrong
    /// place, which no type can catch. Asking for the wrong one now fails
    /// where it is asked rather than several passes later.
    ///
    /// A primitive is the one kind of type name this refuses: nothing in
    /// source declares one, so there is no declaration for it to be.
    pub fn declaredBy(self: *const Resolution, b: BindingId) DeclId {
        const kind = self.kinds[b.index()];
        std.debug.assert(kind == .function or kind == .declared_type or
            kind == .trait or kind == .constant or kind == .associated_type or
            kind == .type_alias);
        return self.decls[b.index()];
    }

    pub fn typeParameterOwner(self: *const Resolution, b: BindingId) DeclId {
        std.debug.assert(self.kinds[b.index()] == .type_parameter);
        return self.decls[b.index()];
    }

    pub fn parameterOwner(self: *const Resolution, b: BindingId) ParameterOwner {
        std.debug.assert(self.kinds[b.index()] == .parameter);
        return self.parameter_owners[b.index()];
    }

    /// The declaration a symbol is, or `.none` where it is neither a function
    /// nor a type. For a caller that is asking *whether* it is one.
    ///
    /// A type a trait declares is one of them: it is written in source and the
    /// walk that pairs an implementation with its trait keys the pair by this
    /// declaration, so a caller reaching for the pair reaches it from here.
    pub fn declIfDeclared(self: *const Resolution, b: BindingId) DeclId {
        return switch (self.kinds[b.index()]) {
            .function, .declared_type, .associated_type => self.decls[b.index()],
            else => DeclId.none,
        };
    }

    pub fn paramIndexOf(self: *const Resolution, b: BindingId) u32 {
        return self.param_indices[b.index()];
    }

    /// The convention a parameter binding is taken by, from the declaration
    /// or the lambda that lists it. Null where the binding is not a parameter,
    /// or where recovery bound more parameters than the list holds.
    pub fn parameterConvention(self: *const Resolution, ast: *const Ast, b: BindingId) ?node.Convention {
        if (b == BindingId.none or self.kindOf(b) != .parameter) return null;
        const params = switch (self.parameterOwner(b)) {
            .declaration => |owner| ast.declParams(owner),
            .closure => |owner| ast.lambda(self.closures.exprOf(owner)).params,
        };
        const at = self.paramIndexOf(b);
        if (at >= params.len) return null;
        return params[at].convention;
    }

    test "a parameter is taken by the convention its list writes" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\fn weigh(crate: UInt8, inout total: UInt8, sink spare: UInt8) -> UInt8 {
            \\    let scale = |sink item: UInt8| item
            \\    total = scale(spare) + crate
            \\    total
            \\}
            \\fn main() -> UInt8 {
            \\    var sum: UInt8 = 0
            \\    weigh(1, &sum, 2)
            \\}
            \\
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        const expected = [_]struct { name: []const u8, convention: ?node.Convention }{
            .{ .name = "crate", .convention = .read },
            .{ .name = "total", .convention = .inout },
            .{ .name = "spare", .convention = .sink },
            .{ .name = "item", .convention = .sink },
            .{ .name = "scale", .convention = null },
            .{ .name = "sum", .convention = null },
        };
        for (expected) |want| {
            var found = false;
            for (0..result.res.bindingCount()) |i| {
                const b = BindingId.at(@intCast(i));
                const declaring = result.res.declaringToken(b);
                if (declaring == .none or !std.mem.eql(u8, ast.tokenText(declaring), want.name)) continue;
                try testing.expectEqual(want.convention, result.res.parameterConvention(ast, b));
                found = true;
            }
            try testing.expect(found);
        }
    }

    test "a lambda's tuple pattern binds locals and leaves one parameter binding per parameter" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\fn main() -> UInt8 {
            \\    let f = |sink (a, b), c: UInt8| a + b + c
            \\    f((1, 2), 3)
            \\}
            \\
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const parameters = result.res.closureParameters(ClosureId.at(0));
        try testing.expectEqual(@as(usize, 2), parameters.len);
        try testing.expectEqual(node.Convention.sink, result.res.parameterConvention(&result.ast, parameters[0]));
        try testing.expectEqual(node.Convention.read, result.res.parameterConvention(&result.ast, parameters[1]));
        var binders: usize = 0;
        for (0..result.res.bindingCount()) |i| {
            const b = BindingId.at(@intCast(i));
            if (result.res.kindOf(b) == .binder) binders += 1;
        }
        try testing.expectEqual(@as(usize, 2), binders);

        // A name is declared once across the whole parameter list.
        for ([_][]const u8{ "|(a, a)| a", "|(a, b), a: UInt8| a + b", "|a: UInt8, (a, b)| a + b" }) |lambda| {
            const text = try std.fmt.allocPrint(arena.allocator(), "fn main() -> UInt8 {{\n    let f = {s}\n    f(0, 0)\n}}\n", .{lambda});
            const refused = try resolveSource(arena.allocator(), text);
            try testing.expectEqual(@as(u32, 1), refused.errors);
        }
    }

    /// The token a binding is declared at, whatever kind it is.
    pub fn declaringToken(self: *const Resolution, b: BindingId) TokenId {
        return self.tokens[b.index()];
    }

    /// Whether a `use` made this binding, which is a name another module's
    /// declaration answers to here.
    /// Whether a body reads this binding anywhere.
    ///
    /// A binder nothing reads lends nothing: `[N-Unused]` refuses one that is
    /// not written `_`, so what reaches here unread is a part a pattern had to
    /// name and the arm goes on to ignore.
    pub fn isReferenced(self: *const Resolution, b: BindingId) bool {
        if (b == BindingId.none or b.index() >= self.referenced.len()) return false;
        return self.referenced.get(b);
    }

    pub fn isReExport(self: *const Resolution, b: BindingId) bool {
        if (b == BindingId.none or b.index() >= self.reexported.len()) return false;
        return self.reexported.get(b);
    }

    /// The prelude's declaration of a tuple with `arity` components, or null
    /// where the prelude publishes none. Null too for an arity the parser
    /// refused, whose node reaches later passes all the same: such a node is
    /// typed as nothing, since the parser reported it where it was written.
    pub fn tupleDecl(self: *const Resolution, arity: usize) ?DeclId {
        return tupleDeclIn(self.tuple_decls, arity);
    }

    test tupleDecl {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var r = try resolveSource(arena.allocator(), "fn main() -> UInt8 { 0 }\n");
        try testing.expectEqual(@as(?DeclId, null), r.res.tupleDecl(2));
        r.res.tuple_decls[0] = DeclId.at(5);
        r.res.tuple_decls[node.max_tuple_arity - 2] = DeclId.at(11);
        try testing.expectEqual(@as(?DeclId, DeclId.at(5)), r.res.tupleDecl(2));
        try testing.expectEqual(@as(?DeclId, DeclId.at(11)), r.res.tupleDecl(node.max_tuple_arity));
        try testing.expectEqual(@as(?DeclId, null), r.res.tupleDecl(3));
        try testing.expectEqual(@as(?DeclId, null), r.res.tupleDecl(1));
        try testing.expectEqual(@as(?DeclId, null), r.res.tupleDecl(node.max_tuple_arity + 1));
    }

    /// Whether the token declaring this binding also names a field, which a
    /// struct pattern's shorthand is the whole of.
    pub fn bindsAFieldByItsOwnName(self: *const Resolution, b: BindingId) bool {
        if (b == BindingId.none or b.index() >= self.field_shorthand.len()) return false;
        return self.field_shorthand.get(b);
    }

    pub fn namingReachOf(self: *const Resolution, b: BindingId) Reach {
        return self.reach[b.index()];
    }

    pub fn isAmbient(self: *const Resolution, b: BindingId) bool {
        if (b == BindingId.none or b.index() >= self.ambient.len()) return false;
        return self.ambient.get(b);
    }

    /// The bindings a declaration's parameters are, in the order written.
    pub fn parametersOf(self: *const Resolution, d: DeclId) []const BindingId {
        const i = d.index();
        if (i + 1 >= self.param_starts.len) return &.{};
        return self.params_of[self.param_starts[i]..self.param_starts[i + 1]];
    }

    pub fn closureParameters(self: *const Resolution, closure: ClosureId) []const BindingId {
        const i = closure.index();
        return self.closure_params[self.closure_param_starts[i]..self.closure_param_starts[i + 1]];
    }

    pub fn closureCaptures(self: *const Resolution, closure: ClosureId) []const ResolvedCapture {
        const range = self.capture_ranges[closure.index()];
        return self.captures[range.start..range.end];
    }

    pub fn captureOfBinding(self: *const Resolution, binding: BindingId) ?CaptureLocation {
        return self.capture_bindings.get(binding);
    }

    /// How the closure holds the place a capture binding stands for, or null
    /// where the binding is no capture.
    pub fn captureConvention(self: *const Resolution, binding: BindingId) ?node.Convention {
        const location = self.capture_bindings.get(binding) orelse return null;
        return self.closureCaptures(location.closure)[location.index].convention;
    }

    /// The token that names a capture's environment field: the alias the
    /// closure declares for the captured place. The resolver declares the
    /// capture binding there, and every pass naming the field reads it here.
    pub fn captureNameToken(self: *const Resolution, binding: BindingId) TokenId {
        return self.tokens[binding.index()];
    }

    pub fn freeReferenceOf(self: *const Resolution, closure: ClosureId) ExprId {
        return self.free_references[closure.index()];
    }

    pub fn targetOf(self: *const Resolution, id: ExprId) BindingId {
        return self.targets[id.index()];
    }

    /// The constant an expression names, written bare or reached through a
    /// module or a type, or `.none` where it names none. A constant is held
    /// in static storage, so a place path reaching one is rooted there.
    pub fn constantNamed(self: *const Resolution, id: ExprId) BindingId {
        const b = self.targetOf(id);
        return if (b != .none and self.kindOf(b) == .constant) b else .none;
    }

    /// Whether a place path is held in a constant's static storage: the path's
    /// root or any step of it names a constant, bare or reached through a
    /// module or a type.
    pub fn constantReached(self: *const Resolution, ast: *const Ast, id: ExprId) bool {
        var steps = ast.placeSteps(id);
        while (steps.next()) |step| if (self.constantNamed(step) != .none) return true;
        return self.constantNamed(steps.at) != .none;
    }

    test constantReached {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const result = try resolveSource(arena.allocator(),
            \\struct Box { n: UInt8 }
            \\let shared = Box{ n = 1 }
            \\fn make() -> Box { Box{ n = 3 } }
            \\fn main() -> UInt8 {
            \\    let local = Box{ n = 2 }
            \\    let a = shared.n
            \\    let b = local.n
            \\    let c = make().n
            \\    a + b + c
            \\}
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        var constant_paths: u32 = 0;
        var other_paths: u32 = 0;
        for (0..ast.exprCount()) |i| {
            const e = ExprId.at(@intCast(i));
            if (ast.exprTag(e) != .field) continue;
            const base = ast.stepBase(e).?;
            const reached = result.res.constantReached(ast, e);
            if (ast.exprTag(base) == .name_ref and std.mem.eql(u8, ast.tokenText(ast.exprMain(base)), "shared")) {
                try testing.expect(reached);
                try testing.expect(result.res.constantReached(ast, base));
                constant_paths += 1;
            } else {
                try testing.expect(!reached);
                other_paths += 1;
            }
        }
        try testing.expectEqual(@as(u32, 1), constant_paths);
        try testing.expectEqual(@as(u32, 2), other_paths);
    }

    test constantNamed {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const result = try resolveSource(arena.allocator(),
            \\let limit = 3
            \\struct Limits { low: UInt8 }
            \\impl Limits {
            \\    let max = 9
            \\}
            \\fn main() -> UInt8 {
            \\    let local = limit
            \\    let _limits = Limits{ low = 1 }
            \\    UInt8(local + Limits.max)
            \\}
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        var constants: u32 = 0;
        var locals: u32 = 0;
        for (0..ast.exprCount()) |i| {
            const e = ExprId.at(@intCast(i));
            const tag = ast.exprTag(e);
            if (tag != .name_ref and tag != .field) continue;
            const text = ast.tokenText(ast.exprMain(e));
            if (std.mem.eql(u8, text, "limit") or std.mem.eql(u8, text, "max")) {
                try testing.expect(result.res.constantNamed(e) != .none);
                constants += 1;
            } else if (std.mem.eql(u8, text, "local")) {
                try testing.expectEqual(BindingId.none, result.res.constantNamed(e));
                locals += 1;
            }
        }
        try testing.expectEqual(@as(u32, 2), constants);
        try testing.expectEqual(@as(u32, 1), locals);
    }

    pub fn selectsAVariant(self: *const Resolution, id: ExprId) bool {
        return self.variant_ordinals.contains(id);
    }

    /// What a fold reads about the names written in a constant expression, for
    /// a pass reading a finished resolution.
    pub fn integerSelection(self: *const Resolution, id: ExprId) ?IntegerSelection {
        return self.integer_selections.get(id);
    }

    /// Whether `id`, a name selected after a type's name, is left to reach an
    /// operation of a trait the type implements.
    pub fn selectsThroughTrait(self: *const Resolution, id: ExprId) bool {
        return self.trait_selections.contains(id);
    }

    /// Whether `id` selects from a lexical binding that shadows an imported
    /// module of the same name.
    pub fn headShadowsAnImport(self: *const Resolution, id: ExprId) bool {
        return self.shadowed_heads.contains(id);
    }

    test "a name after a type that only a trait declares is left to the traits" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        const result = try resolveSource(arena.allocator(),
            \\trait Blank { fn blank() -> Self }
            \\struct Meal { courses: UInt8 }
            \\impl Meal { fn served(courses: UInt8) -> Meal { .{ courses = courses } } }
            \\impl Blank for Meal { fn blank() -> Meal { .{ courses = 0 } } }
            \\fn fresh[T: Blank]() -> T { T.blank() }
            \\fn main() -> UInt8 {
            \\    let empty: Meal = fresh()
            \\    Meal.blank().courses + Meal.served(2).courses + empty.courses
            \\}
            \\
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        var left: u32 = 0;
        for (0..ast.exprCount()) |i| {
            const e = ExprId.at(@intCast(i));
            if (ast.exprTag(e) != .field) continue;
            const name = ast.tokenText(ast.exprMain(e));
            // `Meal.blank` and `T.blank` are left to the checker; `Meal.served`
            // is the type's own and a field of a value is neither.
            try testing.expectEqual(std.mem.eql(u8, name, "blank"), result.res.selectsThroughTrait(e));
            if (result.res.selectsThroughTrait(e)) left += 1;
        }
        try testing.expectEqual(@as(u32, 2), left);
    }

    pub fn nameSites(self: *const Resolution) constfold.Names {
        return .{ .ctx = self, .reaches = reachedFrom, .constant_call = constantCallFrom, .integer_property = integerPropertyFrom, .variant = variantFrom, .tuple_component = tupleComponentFrom };
    }

    fn tupleComponentFrom(ctx: *const anyopaque, ast: *const Ast, arity: usize, position: usize) ?[]const u8 {
        const self: *const Resolution = @ptrCast(@alignCast(ctx));
        return tupleComponentIn(ast, self.tuple_decls, arity, position);
    }

    fn variantFrom(ctx: *const anyopaque, id: ExprId) bool {
        const self: *const Resolution = @ptrCast(@alignCast(ctx));
        return self.variant_ordinals.contains(id);
    }

    fn integerPropertyFrom(ctx: *const anyopaque, id: ExprId) ?i128 {
        const self: *const Resolution = @ptrCast(@alignCast(ctx));
        const selected = self.integerSelection(id) orelse return null;
        const receiver = self.builtinOf(selected.receiver) orelse return null;
        return selected.endpoint.value(receiver);
    }

    fn reachedFrom(ctx: *const anyopaque, id: ExprId) constfold.Reach {
        const self: *const Resolution = @ptrCast(@alignCast(ctx));
        if (id == ExprId.none or id.index() >= self.targets.len) return .nothing;
        const b = self.targetOf(id);
        if (b == BindingId.none) return .nothing;
        return reachOf(self.kindOf(b), self.decls[b.index()], self.stmts[b.index()]);
    }

    fn constantCallFrom(ctx: *const anyopaque, ast: *const Ast, callee: ExprId) ?constfold.ConstantCall {
        const self: *const Resolution = @ptrCast(@alignCast(ctx));
        if (callee == ExprId.none or callee.index() >= self.targets.len) return null;
        const b = self.throughAlias(self.targetOf(callee));
        if (b == BindingId.none) return null;
        return callOn(ast, callee, self.kindOf(b), self.builtins[b.index()], self.decls[b.index()]);
    }

    /// The token spelling the binding an expression reaches, or `.none` where
    /// it reaches nothing.
    pub fn spelledAt(self: *const Resolution, id: ExprId) TokenId {
        if (id == ExprId.none or id.index() >= self.spelled.len) return .none;
        return self.spelled[id.index()];
    }

    /// The binding a name written outside an expression reaches, or `.none`
    /// where the token is not one.
    pub fn writtenAt(self: *const Resolution, t: TokenId) BindingId {
        if (t == TokenId.none or t.index() >= self.written.len) return .none;
        return self.written[t.index()];
    }

    pub fn stmtOf(self: *const Resolution, b: BindingId) StmtId {
        return self.stmts[b.index()];
    }

    /// Whether writing through this binding is accepted at all: a local's
    /// own `var` (never a `let`), a parameter's own `inout`, or a capture
    /// taken `sink` into a closure whose own invocation is `inout` -- the one
    /// shape the resolver lets write back through a captured name. Every
    /// other kind, including a binder, answers `false`: a binder's writable
    /// cases depend on the construct that bound it (a `for inout` walk, and
    /// no other), which is decided at bind time and kept nowhere a later
    /// question can read it back, so this asks only what it can answer for
    /// certain rather than assume the answer is yes.
    ///
    /// Read from what each kind's own declaration already settled -- the
    /// statement's keyword, the parameter list's convention, the capture
    /// list's convention and the lambda's own invocation -- so a
    /// semantic-tokens modifier and a completion offer answer from the same
    /// rule instead of each keeping its own copy of "can this be written".
    pub fn bindingIsMutable(self: *const Resolution, ast: *const Ast, b: BindingId) bool {
        return switch (self.kindOf(b)) {
            .local => local: {
                const s = self.stmtOf(b);
                break :local s == StmtId.none or ast.stmtTag(s) != .let_decl or ast.stmtIsMutable(s);
            },
            .parameter => (self.parameterConvention(ast, b) orelse .read) == .inout,
            .capture => capture: {
                const loc = self.captureOfBinding(b) orelse break :capture false;
                const taken = self.closureCaptures(loc.closure)[loc.index];
                const lambda = ast.lambda(self.closures.exprOf(loc.closure));
                break :capture captureIsMutable(taken.convention, lambda.invocation);
            },
            else => false,
        };
    }

    /// The binding at a place's root, after walking `.field` and `.index`
    /// projections down to it exactly as `Resolver.place` walks one when it
    /// resolves an assignment or a `&` mark -- so a receiver reached through
    /// a projection is judged by the same rule the checker settles the write
    /// against, not a second, narrower reading of "is this a place" invented
    /// beside it. `.none` where the walk does not end at a `name_ref`: a
    /// call's result, a dereferenced observation, anything that is not
    /// itself a place.
    pub fn placeRoot(self: *const Resolution, ast: *const Ast, receiver: ExprId) BindingId {
        var steps = ast.placeSteps(receiver);
        while (steps.next()) |step| if (ast.exprTag(step) == .dereference) return .none;
        if (ast.exprTag(steps.at) != .name_ref) return .none;
        return self.targetOf(steps.at);
    }

    /// The binding a path written as an argument or a target is rooted in,
    /// through a `&` mark, parentheses and every selection including a
    /// dereference; `.none` where it is rooted at no name.
    ///
    /// Unlike `placeRoot`, which stops at a dereferenced observation because
    /// nothing through one may be written, this asks only which name was
    /// written: what a pass that follows a place for its state or its
    /// dependencies needs.
    pub fn pathBinding(self: *const Resolution, ast: *const Ast, id: ExprId) BindingId {
        const root = ast.pathRoot(id);
        if (!ast.refersToBinding(root)) return .none;
        return self.targetOf(root);
    }

    test pathBinding {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const result = try resolveSource(arena.allocator(),
            \\struct Box { n: UInt8 }
            \\let shared = Box{ n = 1 }
            \\fn make() -> Box { Box{ n = 3 } }
            \\fn main() -> UInt8 {
            \\    let local = Box{ n = 2 }
            \\    let a = shared.n
            \\    let b = local.n
            \\    let c = make().n
            \\    a + b + c
            \\}
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        var seen: u32 = 0;
        for (0..ast.exprCount()) |i| {
            const e = ExprId.at(@intCast(i));
            if (ast.exprTag(e) != .field) continue;
            const base = ast.stepBase(e).?;
            if (ast.exprTag(base) == .name_ref) {
                try testing.expect(result.res.targetOf(base) != .none);
                try testing.expectEqual(result.res.targetOf(base), result.res.pathBinding(ast, e));
            } else {
                try testing.expectEqual(BindingId.none, result.res.pathBinding(ast, e));
            }
            seen += 1;
        }
        try testing.expectEqual(@as(u32, 3), seen);
    }

    /// Whether the place a receiver expression names may be written through
    /// at all -- what `&` and an assignment both ask of a place before
    /// either reaches the binding underneath it.
    ///
    /// `false` wherever `placeRoot` finds no binding: nothing about a value
    /// that is not a place can be marked, so it is never a candidate for a
    /// caller to make writable, marked or not.
    pub fn placeIsMutable(self: *const Resolution, ast: *const Ast, receiver: ExprId) bool {
        const b = self.placeRoot(ast, receiver);
        if (b == BindingId.none) return false;
        return self.bindingIsMutable(ast, b);
    }

    test "a capture binding answers its convention and the name of its environment field" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "t.lin", .text =
            \\fn main() -> UInt8 {
            \\    var total = 0
            \\    let number = 4
            \\    let get = read [read held = number] || held
            \\    let add = inout [inout sum = total] |step: UInt8| { sum += step }
            \\    get()
            \\}
        };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        const resolved = try resolveTree(gpa, &ast, &sink);

        var held: ?BindingId = null;
        var sum: ?BindingId = null;
        var number: ?BindingId = null;
        for (0..resolved.resolution.bindingCount()) |i| {
            const b = BindingId.at(@intCast(i));
            const at = resolved.resolution.declaringToken(b);
            if (at == TokenId.none) continue;
            const name = ast.tokenText(at);
            if (resolved.resolution.kindOf(b) == .capture and std.mem.eql(u8, name, "held")) held = b;
            if (resolved.resolution.kindOf(b) == .capture and std.mem.eql(u8, name, "sum")) sum = b;
            if (std.mem.eql(u8, name, "number")) number = b;
        }
        try testing.expectEqual(@as(?node.Convention, .read), resolved.resolution.captureConvention(held.?));
        try testing.expectEqual(@as(?node.Convention, .inout), resolved.resolution.captureConvention(sum.?));
        try testing.expectEqual(@as(?node.Convention, null), resolved.resolution.captureConvention(number.?));
        try testing.expectEqualStrings("held", ast.tokenText(resolved.resolution.captureNameToken(held.?)));
        try testing.expectEqualStrings("sum", ast.tokenText(resolved.resolution.captureNameToken(sum.?)));
    }

    test "bindingIsMutable reads a local's let or var and a parameter's own convention" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "t.lin", .text =
            \\fn tally(fixed: UInt8, inout counted: UInt8) -> UInt8 {
            \\    let held = fixed
            \\    var kept = counted
            \\    kept + held
            \\}
            \\fn main() -> UInt8 {
            \\    var total = 0
            \\    tally(1, &total)
            \\}
        };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        const resolved = try resolveTree(gpa, &ast, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);

        var held: ?BindingId = null;
        var kept: ?BindingId = null;
        var fixed: ?BindingId = null;
        var counted: ?BindingId = null;
        for (0..resolved.resolution.bindingCount()) |i| {
            const b = BindingId.at(@intCast(i));
            const at = resolved.resolution.declaringToken(b);
            if (at == TokenId.none) continue;
            const name = ast.tokenText(at);
            if (std.mem.eql(u8, name, "held")) held = b;
            if (std.mem.eql(u8, name, "kept")) kept = b;
            if (std.mem.eql(u8, name, "fixed")) fixed = b;
            if (std.mem.eql(u8, name, "counted")) counted = b;
        }
        try testing.expect(!resolved.resolution.bindingIsMutable(&ast, held.?));
        try testing.expect(resolved.resolution.bindingIsMutable(&ast, kept.?));
        try testing.expect(!resolved.resolution.bindingIsMutable(&ast, fixed.?));
        try testing.expect(resolved.resolution.bindingIsMutable(&ast, counted.?));
    }

    test "placeIsMutable requires a place rooted in a name, never a call result" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const result = try resolveSource(gpa,
            \\struct Holder { list: UInt8 }
            \\fn made() -> Holder { .{ list = 0 } }
            \\fn tryIt(self: Holder) -> UInt8 {
            \\    self.list
            \\}
            \\fn main() -> UInt8 {
            \\    var owned: Holder = .{ list = 0 }
            \\    tryIt(made()) + tryIt(owned)
            \\}
        );
        try testing.expectEqual(@as(u32, 0), result.errors);
        const ast = &result.ast;
        const res = &result.res;

        var owned_receiver: ExprId = .none;
        var self_field: ExprId = .none;
        var call_result: ExprId = .none;
        for (0..ast.exprCount()) |i| {
            const e = ExprId.at(@intCast(i));
            switch (ast.exprTag(e)) {
                .field => if (std.mem.eql(u8, ast.tokenText(ast.exprMain(e)), "list") and
                    ast.exprTag(ast.withoutGroups(ast.unaryOperand(e))) == .name_ref and
                    std.mem.eql(u8, ast.tokenText(ast.exprMain(ast.withoutGroups(ast.unaryOperand(e)))), "self"))
                {
                    self_field = e;
                },
                .call => {
                    const c = ast.call(e);
                    if (ast.exprTag(c.callee) == .name_ref and std.mem.eql(u8, ast.tokenText(ast.exprMain(c.callee)), "made")) call_result = e;
                    if (ast.exprTag(c.callee) == .name_ref and std.mem.eql(u8, ast.tokenText(ast.exprMain(c.callee)), "tryIt") and
                        c.args.len == 1 and ast.exprTag(c.args[0]) == .name_ref and
                        std.mem.eql(u8, ast.tokenText(ast.exprMain(c.args[0])), "owned"))
                    {
                        owned_receiver = c.args[0];
                    }
                },
                else => {},
            }
        }
        try testing.expect(owned_receiver != .none);
        try testing.expect(self_field != .none);
        try testing.expect(call_result != .none);

        // A plain local is a place; a field reached through a `read`
        // parameter is a place but not a writable one; a call's result is no
        // place at all.
        try testing.expect(res.placeIsMutable(ast, owned_receiver));
        try testing.expect(!res.placeIsMutable(ast, self_field));
        try testing.expect(!res.placeIsMutable(ast, call_result));
    }

    /// Which binding a statement declared, or `.none`.
    pub fn bindingOf(self: *const Resolution, s: StmtId) BindingId {
        return self.binding_of_stmt[s.index()];
    }

    pub fn bindingCount(self: *const Resolution) u32 {
        return @intCast(self.kinds.len);
    }

    /// A table with one entry per binding this resolution minted.
    ///
    /// Built here for the reason `Ast.declTable` is built there: this is what
    /// owns the count, and a table keyed by `BindingId` and sized by anything
    /// else answers for the wrong elements.
    ///
    /// The caller owns the result.
    pub fn bindingTable(
        self: *const Resolution,
        gpa: std.mem.Allocator,
        comptime T: type,
        fill: T,
    ) !Table(ids.BindingId, T) {
        return Table(ids.BindingId, T).of(gpa, self.bindingCount(), fill);
    }
};

// Makes every test build compile the tests `Resolution` holds, including a build
// filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Resolution;
}

/// What a name refers to.
///
/// One space rather than two. A scope chain has to hold locals and functions
/// alike, and a lookup should not have to know which kind it is seeking before
/// it knows what it found -- so the kind is a property of what was found, and
/// using one where the other belongs is a diagnosed mistake rather than an
/// unrepresentable state.
pub const Kind = enum {
    local,
    capture,
    parameter,
    function,
    /// A name a module or an `impl` bound to a value. A value like a local is,
    /// and its own kind rather than one: a diagnostic reads the kind to say
    /// what it found, and "this is a constant, not a function" is a sentence a
    /// call to one has to be able to produce.
    constant,
    /// A type the program declared -- an enum or a structure. One kind for
    /// both, because what a name refers to is the question, and "a type" is
    /// the answer either way.
    declared_type,
    /// A primitive the compiler provides. A name in every scope, bound to no
    /// declaration: nothing in source declares one, which is why `decl` is
    /// `.none` here and nowhere else among the type kinds.
    builtin_type,
    /// A trait the program declared. A namespace rather than a type: a bound
    /// may name one and a call may be reached through one, but no value has a
    /// trait for its type, so it is neither a `declared_type` nor a value.
    trait,
    /// A module an `import` bound to a name in this file. What it names is a
    /// namespace rather than a value, so a use of one is always qualified and
    /// an unqualified reference to it is a diagnosed mistake.
    module,
    /// A name a match arm's pattern binds to what its variant carries. A
    /// binding declared by neither a statement nor a parameter list, which is
    /// why it is its own kind rather than a local with nothing to point at.
    binder,
    /// A type a trait declares and its implementations settle. A name
    /// standing for a type rather than naming one, so it is neither a
    /// `declared_type` -- nothing here says what it is -- nor a value.
    associated_type,
    /// A type parameter declared by a structural derive. It names source for
    /// tooling but is neither a value nor a declaration semantic passes select.
    type_parameter,
    /// An `alias`: another name for the type written after its `=`. A type
    /// name wherever a type is written, and nothing else -- it declares no
    /// representation, so there is no declaration of its own to construct,
    /// destructure, select through or implement.
    type_alias,
};

/// Whether a binding of this kind holds a value, rather than naming a
/// namespace, a function, or a type standing for another.
pub fn kindIsAValue(kind: Kind) bool {
    return switch (kind) {
        .local, .parameter, .capture, .binder, .constant => true,
        .function, .declared_type, .builtin_type, .associated_type, .type_parameter, .type_alias, .trait, .module => false,
    };
}

/// Whether a binding of this kind, while in scope, shadows an import of its
/// name at the head of a dotted expression: the kinds `lexicalName` finds.
/// Tooling that reads a finished scope asks this; the resolver asks
/// `lexicalName` while the scope is still being built.
pub fn kindShadowsAnImport(kind: Kind) bool {
    return switch (kind) {
        .local, .parameter, .capture, .binder, .type_parameter => true,
        .function, .constant, .declared_type, .builtin_type, .associated_type, .type_alias, .trait, .module => false,
    };
}

/// The prelude declaration with this name, or null where it publishes none.
///
/// The prelude's own declarations are what every ambient name in every module
/// resolves against, so asking them is asking the one thing that decides which
/// declaration `Option` is -- whatever a module that shadows the name declares.
pub fn preludeDeclIn(ast: *const Ast, prelude: []const DeclId, name: []const u8) ?DeclId {
    for (prelude) |d| {
        if (d == DeclId.none) continue;
        if (std.mem.eql(u8, ast.tokenText(ast.declName(d)), name)) return d;
    }
    return null;
}

test "a prelude declaration is found by its name among the prelude's" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "t.lin", .text = "struct Str {}\nenum Option { None }\n" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    const prelude = [_]DeclId{ DeclId.none, DeclId.at(0), DeclId.at(1) };

    try testing.expectEqual(@as(?DeclId, DeclId.at(1)), preludeDeclIn(&ast, &prelude, "Option"));
    try testing.expectEqual(@as(?DeclId, DeclId.at(0)), preludeDeclIn(&ast, &prelude, "Str"));
    try testing.expectEqual(@as(?DeclId, null), preludeDeclIn(&ast, &prelude, "Result"));
}

/// The prelude declarations tuple syntax constructs, by arity: a tuple of `n`
/// components is the `n - 2`th, written out one name per line so the prelude
/// gate reads from this table what the compiler asks the prelude for.
const tuple_names = [node.max_tuple_arity - 1][]const u8{
    "Tuple2",
    "Tuple3",
    "Tuple4",
    "Tuple5",
    "Tuple6",
    "Tuple7",
    "Tuple8",
};

/// The prelude's tuple declarations by arity less two; `.none` where the
/// prelude publishes none of that arity.
pub const TupleDecls = [node.max_tuple_arity - 1]DeclId;
pub const no_tuple_decls: TupleDecls = [_]DeclId{DeclId.none} ** (node.max_tuple_arity - 1);

/// The tuple declarations the prelude `decls` publish, found by name.
pub fn tupleDeclsIn(ast: *const Ast, decls: []const DeclId) TupleDecls {
    var found = no_tuple_decls;
    for (&found, tuple_names) |*slot, name| {
        slot.* = preludeDeclIn(ast, decls, name) orelse DeclId.none;
    }
    return found;
}

/// The declaration a tuple of `arity` components names in `decls`, or null:
/// for an arity the parser refuses, and for one the prelude did not publish.
fn tupleDeclIn(decls: TupleDecls, arity: usize) ?DeclId {
    if (!node.isTupleArity(arity)) return null;
    const decl = decls[arity - 2];
    return if (decl == DeclId.none) null else decl;
}

/// The field the declaration of a tuple of `arity` components names its
/// component at `position`, or null where no declaration of that arity is
/// published or it has no such component.
fn tupleComponentIn(ast: *const Ast, decls: TupleDecls, arity: usize, position: usize) ?[]const u8 {
    const decl = tupleDeclIn(decls, arity) orelse return null;
    const fields = ast.declFields(decl);
    return if (position < fields.len) ast.tokenText(fields[position].name) else null;
}

test "a tuple's component is the field its declaration names at that position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source: Source = .{ .path = "t.lin", .text = "struct Pair[A, B] { left: A, right: B }\n" };
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    const tokens = try tokenize(arena.allocator(), &source, .from(0), &sink, &interner);
    const ast = try parse(arena.allocator(), &source, .from(0), tokens, &sink);
    var decls = no_tuple_decls;
    decls[0] = DeclId.at(0);
    try testing.expectEqualStrings("left", tupleComponentIn(&ast, decls, 2, 0).?);
    try testing.expectEqualStrings("right", tupleComponentIn(&ast, decls, 2, 1).?);
    try testing.expectEqual(@as(?[]const u8, null), tupleComponentIn(&ast, decls, 2, 2));
    try testing.expectEqual(@as(?[]const u8, null), tupleComponentIn(&ast, decls, 3, 0));
}

test "the tuple declarations are found by arity among the prelude's" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "t.lin", .text = "struct Tuple3 {}\nstruct Str {}\nstruct Tuple2 {}\n" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    const prelude = [_]DeclId{ DeclId.at(0), DeclId.at(1), DeclId.at(2) };

    const found = tupleDeclsIn(&ast, &prelude);
    try testing.expectEqual(@as(?DeclId, DeclId.at(2)), tupleDeclIn(found, 2));
    try testing.expectEqual(@as(?DeclId, DeclId.at(0)), tupleDeclIn(found, 3));
    try testing.expectEqual(@as(?DeclId, null), tupleDeclIn(found, 4));
    try testing.expectEqual(@as(?DeclId, null), tupleDeclIn(found, 1));
    try testing.expectEqual(@as(?DeclId, null), tupleDeclIn(found, node.max_tuple_arity + 1));
}

/// Whether an expression names a variant: a leading-dot variant, or a
/// qualified one, whose selection settles on its enum's binding. `names` is
/// the resolver while it walks or the finished resolution.
pub fn namesAVariant(names: anytype, ast: *const Ast, id: ExprId) bool {
    return ast.exprTag(id) == .variant_ref or names.selectsAVariant(id);
}

/// Whether what stands left of a selection names a value rather than a
/// namespace -- the one answer the resolver and the checker both read.
///
/// A variant is a value of its enum even though its selection settles on the
/// enum's binding, so it answers before the binding's kind does. A left side
/// that reaches nothing is not a value when it is a bare name: only a bare
/// name can be unresolved, and one reaching nothing is a namespace the tree
/// cannot see, such as a prelude name read without the library beside it.
/// Any other expression has a value.
pub fn baseNamesAValue(names: anytype, ast: *const Ast, base: ExprId) bool {
    if (namesAVariant(names, ast, base)) return true;
    const t = names.targetOf(base);
    if (t == BindingId.none) return ast.exprTag(base) != .name_ref;
    return kindIsAValue(names.kindOf(t));
}

/// The primitive a binding names, or null where it names something else.
///
/// A free function over the two fields the answer reads, because it is asked
/// at two times: by the resolver from the bindings it is still building, and
/// by everything below it from the finished table. Those are two storages for
/// one column, so the rule that reads it is written here and nowhere else.
fn builtinNames(kind: Kind, held: TypeId) ?TypeId {
    if (kind != .builtin_type) return null;
    return held;
}

/// Whether the parser could not read a written type argument. It has already
/// reported one, so later passes neither report it again nor copy its source.
fn unreadable(ref: node.TypeRef) bool {
    return ref.kind == .named and ref.name == TokenId.none;
}

/// Where the binding a name reaches was written, for the fold that reads what
/// it was initialised with.
///
/// The two kinds a value was written into, which are the two holding an
/// initialiser to read. A free function over the three fields the answer
/// reads, for the same reason `builtinNames` is one: it is asked by the
/// resolver from the bindings it is still building, and from the finished
/// tables by the checker.
fn reachOf(kind: Kind, d: DeclId, s: StmtId) constfold.Reach {
    return switch (kind) {
        .constant => .{ .decl = d },
        .local => .{ .stmt = s },
        .parameter,
        .capture,
        .function,
        .declared_type,
        .builtin_type,
        .trait,
        .module,
        .binder,
        .associated_type,
        .type_parameter,
        .type_alias,
        => .nothing,
    };
}

/// The values a conversion written on a name admits, or null where the name
/// heads no conversion.
///
/// A conversion is written on a primitive, so the answer is that primitive's
/// range, read from the one table that says what a type holds. A free function
/// over the two fields the answer reads, for the same reason `builtinNames` is
/// one: the resolver asks it of the bindings it is still building and the
/// checker asks it of the finished tables.
fn conversionInto(kind: Kind, held: TypeId) ?constfold.Range {
    const t = builtinNames(kind, held) orelse return null;
    const b = t.bounds() orelse return null;
    return .{ .min = b.min, .max = b.max };
}

/// What a call on a callee reaching a binding does to its operand, for the
/// constant folder: a primitive's conversion or a newtype's construction.
///
/// A free function over the binding's columns for the same reason
/// `conversionInto` is one: the resolver asks it of the bindings it is still
/// building and the checker asks it of the finished tables.
fn callOn(ast: *const Ast, callee: ExprId, kind: Kind, held: TypeId, decl: DeclId) ?constfold.ConstantCall {
    if (conversionInto(kind, held)) |range| return .{ .into = range };
    if (headsConstruction(ast, callee, kind, decl)) return .construction;
    return null;
}

/// Whether a callee written this way, reaching a binding of `kind` declared by
/// `decl`, names a newtype, so a call on it constructs one.
///
/// A name or a path to one, because a type is named either way and which of
/// the two was written decides nothing: a head reaching a newtype through the
/// module declaring it constructs exactly what a bare name does.
fn headsConstruction(ast: *const Ast, callee: ExprId, kind: Kind, decl: DeclId) bool {
    switch (ast.exprTag(callee)) {
        .name_ref, .field => {},
        else => return false,
    }
    return kind == .declared_type and ast.declTag(decl) == .newtype;
}

/// Whether a name in a module's scope is one another module could name at all,
/// before its visibility is consulted.
///
/// A free function over the two fields the answer reads, because it is asked at
/// two times: by the resolver as it settles a qualified name, and from the
/// finished tables by a caller listing what an import brings within reach.
///
/// An `import` binds a module inside the file that wrote it and carries nothing
/// onward, so `m.other` reaches nothing. A name the prelude put in every
/// module's scope is not that module's to give either -- otherwise adding a
/// name to the prelude would widen the public surface of every module in every
/// program.
pub fn nameableFromOutside(kind: Kind, ambient: bool) bool {
    return kind != .module and !ambient;
}

/// What a bound written on a type parameter names.
pub const Bound = union(enum) {
    /// A capability the compiler defines. Closed: nothing implements one.
    capability: node.CapabilityRequirement,
    /// The closed family of built-in integer types.
    integer,
    /// A trait the program declares.
    trait: DeclId,
    /// Neither. A capability that does not exist is not something a program can
    /// be trying to name, so a name reaching nothing is an unknown trait.
    unknown,
};

/// What a bound names, decided in the order the language decides it.
///
/// What is declared decides, and is asked first. `Copyable` and `Linear` are
/// spelled like traits and are not ones, but a program declaring a trait of
/// that name has declared a trait -- and reading the spelling first made that
/// bound mean the capability as well, so it refused every type that owed
/// anything and skipped the rule that asks whether a declaration may hold one.
///
/// `declared` is whatever the caller's own lookup reached, because this is
/// asked at two times: by the resolver while the scope chain is still being
/// built, and by the checker from the finished table. Those two lookups cannot
/// disagree -- the table is built from that scope -- but the order they are
/// consulted in is the rule, and it is written here and nowhere else.
pub fn boundNames(ast: *const Ast, tok: TokenId, declared: ?DeclId) Bound {
    if (declared) |d| return .{ .trait = d };

    const text = ast.tokenText(tok);
    if (std.mem.eql(u8, text, "Integer")) return .integer;
    if (std.mem.eql(u8, text, "Copyable")) return .{ .capability = .copyable };
    if (std.mem.eql(u8, text, "Discardable")) return .{ .capability = .discardable };
    if (std.mem.eql(u8, text, "Linear")) return .{ .capability = .unrestricted };
    return .unknown;
}

/// What the bounds on one type parameter say about a name written after it.
pub const Declaring = struct {
    /// How many of the bounds name a trait at all. A capability declares
    /// nothing, so a parameter carrying only those carries no trait here.
    traits: u32 = 0,
    /// How many of those traits declare a member of that name.
    declaring: u32 = 0,
    /// The bound the name is read through: the one trait declaring it, or --
    /// where none does and one trait is bounded -- that one, so a message
    /// about a name nothing declares has a trait to name.
    bound: TokenId = .none,
    /// The arguments that bound was written at, which are the other half of
    /// what settles a declared type read through it: one type may implement
    /// one trait once per argument list, so the trait alone names no
    /// implementation.
    args: node.TypeRefRange = node.TypeRefRange.empty,
    /// Its trait.
    trait: DeclId = DeclId.none,
    /// The second bound declaring the name, which is the other half of what an
    /// ambiguity is between.
    also: TokenId = .none,
};

/// Which of a type parameter's bounds declares the name a settled reference
/// writes after the dot.
///
/// The bound names the trait, so nothing is searched for -- but a parameter
/// carries as many bounds as the program wrote, and the one the name is read
/// through is the one whose trait declares it. Two *traits* that do is the
/// ambiguity `Declaring.declaring` reports as two: the reference names two
/// declarations and nothing written can say which, so it names neither.
///
/// Traits and not bounds, because a trait named twice is one trait: the second
/// bound admits exactly what the first admits and declares exactly what it
/// declares, so there is nothing to choose between and no advice to give. A
/// repetition is a no-op everywhere else a bound is read -- `fn f[W: M + M]`
/// checks and runs -- and a settled reference is not the place that starts
/// reading it as saying something.
///
/// A member of that name whatever it is declared as, because a settled
/// reference reaches one declaration and two of that name is what nothing here
/// can choose between -- what the one it reaches must be is asked of that one
/// afterwards, where a trait declaring an operation of the name is told apart
/// from a trait declaring nothing.
///
/// `lookup` is the caller's own, for the reason `boundNames` takes the
/// declaration a caller reached: the resolver asks while the scope chain is
/// still being built and the checker reads the table that chain became. The
/// rule -- which bounds count, which one is read through, and when there is no
/// answer -- is here and in neither of them.
/// **Bound:** the bounds written on the one parameter, and per bound whatever
/// the lookup costs. A repetition is found through a table keyed by the trait
/// and the hash of the written arguments, so a bound is compared only with
/// the earlier bounds that hash alike and the pairing is linear in the bounds.
pub fn boundDeclaring(
    bounds: []const node.TraitBound,
    name: StringId,
    lookup: anytype,
) @TypeOf(lookup).Error!Declaring {
    const Lookup = @TypeOf(lookup);
    var found: Declaring = .{};
    var sole: node.TraitBound = .{};
    var sole_trait: DeclId = DeclId.none;

    var repeats: Repeats(Lookup) = .{ .bounds = bounds, .lookup = lookup };
    defer repeats.deinit();

    for (bounds, 0..) |b, at| {
        if (b.kind == .callable) continue;
        const trait = lookup.traitBoundAt(b.named.name) orelse continue;
        if (try repeats.repeatsEarlier(@intCast(at), trait)) continue;
        found.traits += 1;
        if (found.traits == 1) {
            sole = b;
            sole_trait = trait;
        }
        if (!lookup.declaresMember(trait, name)) continue;
        found.declaring += 1;
        switch (found.declaring) {
            1 => {
                found.bound = b.named.name;
                found.args = b.named.args;
                found.trait = trait;
            },
            2 => found.also = b.named.name,
            else => {},
        }
    }

    if (found.declaring == 0 and found.traits == 1) {
        found.bound = sole.named.name;
        found.args = sole.named.args;
        found.trait = sole_trait;
    }
    return found;
}

/// The bounds of one parameter that are not repetitions of an earlier one.
///
/// The pair, because one type may implement a trait once per argument:
/// `Lookup[UInt64]` and `Lookup[Tail]` are two bounds on the reading this
/// counts, however alike their trait, and only `Lookup[UInt64]` written twice
/// is the repetition a program means as one declaration to reach.
///
/// A bound is entered under its trait and the hash of its written arguments,
/// and compared with the bounds already entered under the same pair. The hash
/// reads a written type as the comparison does, so two bounds the comparison
/// calls one always meet; two it calls different meet only by collision.
fn Repeats(comptime Lookup: type) type {
    return struct {
        const Self = @This();
        const Key = struct { trait: DeclId, hash: u64 };
        const Entered = std.HashMapUnmanaged(u32, void, Context, 80);
        const Context = struct {
            bounds: []const node.TraitBound,
            keys: []const Key,
            lookup: Lookup,
            failure: *?Lookup.Error,

            pub fn hash(self: Context, at: u32) u64 {
                return self.keys[at].hash;
            }

            pub fn eql(self: Context, a: u32, b: u32) bool {
                if (self.keys[a].trait != self.keys[b].trait or self.keys[a].hash != self.keys[b].hash) return false;
                return self.lookup.sameArgs(self.bounds[a].named.args, self.bounds[b].named.args) catch |err| {
                    self.failure.* = err;
                    return false;
                };
            }
        };

        bounds: []const node.TraitBound,
        lookup: Lookup,
        keys: []Key = &.{},
        table: Entered = .empty,
        failure: ?Lookup.Error = null,

        fn deinit(self: *Self) void {
            const gpa = self.lookup.allocator();
            self.table.deinit(gpa);
            if (self.keys.len != 0) gpa.free(self.keys);
        }

        /// Whether the bound at `at`, which names `trait`, repeats one entered
        /// before it; a bound that does not is entered.
        fn repeatsEarlier(self: *Self, at: u32, trait: DeclId) Lookup.Error!bool {
            // One bound repeats nothing, and most parameters carry one.
            if (self.bounds.len < 2) return false;
            const gpa = self.lookup.allocator();
            if (self.keys.len == 0) self.keys = try gpa.alloc(Key, self.bounds.len);
            self.keys[at] = .{ .trait = trait, .hash = try self.lookup.hashArgs(self.bounds[at].named.args) };
            const context: Context = .{
                .bounds = self.bounds,
                .keys = self.keys,
                .lookup = self.lookup,
                .failure = &self.failure,
            };
            const entry = try self.table.getOrPutContext(gpa, at, context);
            if (self.failure) |err| return err;
            return entry.found_existing;
        }
    };
}

/// What a written name reached when it was resolved.
pub const Reached = union(enum) {
    /// A type parameter, an associated type, a name nothing declares, or a
    /// name not resolved yet: only its spelling says what it is.
    nothing,
    /// An alias, which stands for the type it names.
    alias: DeclId,
    /// A type, by the declaration or primitive that declares it, so two
    /// bindings of one declaration and two modules' declarations of one
    /// spelling are told apart as they should be.
    type_: u32,

    /// What a binding of this kind, declaration and primitive is reached as.
    pub fn of(kind: Kind, decl: DeclId, builtin: TypeId) Reached {
        return switch (kind) {
            .type_alias => if (decl == DeclId.none) .nothing else .{ .alias = decl },
            .declared_type => if (decl == DeclId.none) .nothing else .{ .type_ = @intFromEnum(decl) },
            .builtin_type => .{ .type_ = primitive_identity | @intFromEnum(builtin) },
            else => .nothing,
        };
    }

    /// Set on the identity of a primitive, which no declaration index reaches.
    const primitive_identity: u32 = 1 << 31;
};

/// How the names of one side of a comparison are read as another text.
///
/// A family's own parameters stand for what the implementation it is read at
/// applies in the same positions, and an alias's parameters stand for the
/// arguments written where it is used. In both the text substituted is
/// written in another place, so what it is read as is `after`: the reading
/// that was current where it was written.
pub const Reading = struct {
    family: DeclId = DeclId.none,
    applied: []const node.TypeRef = &.{},
    outer: ?*const Reading = null,

    /// The reading a text substituted for one of this one's parameters has.
    fn after(self: Reading) Reading {
        return if (self.outer) |outer| outer.* else .{};
    }

    /// Whether `alias` is being expanded by this reading or one around it,
    /// which is how an alias that names itself is told from one used twice.
    fn expands(self: *const Reading, alias: DeclId) bool {
        var at: ?*const Reading = self;
        while (at) |reading| : (at = reading.outer) {
            if (reading.family == alias) return true;
        }
        return false;
    }
};

/// What a written type stands for where it names one of the reading's
/// parameters and the text being read applies something there: the argument
/// written in that position, with the reading it was written under, or the
/// default its declaration gives an argument that was omitted.
///
/// A bare name and nothing else: a parameter with arguments of its own, an
/// array or a settled reference names a type built from a parameter rather
/// than the parameter itself. Walked over the family's own parameters, which
/// is what a head applies and so what bounds this.
const ParameterReading = struct { written: node.TypeRef, reading: Reading };

fn parameterReading(ast: *const Ast, read: Reading, x: node.TypeRef) ?ParameterReading {
    if (read.family == DeclId.none) return null;
    if (x.kind != .named or x.args.len() != 0) return null;
    if (x.name == TokenId.none or ast.tokenTag(x.name) != .identifier) return null;
    const name = ast.tokenName(x.name);
    for (ast.declTypeParams(read.family), 0..) |p, i| {
        if (ast.tokenName(p.name) != name) continue;
        if (i < read.applied.len) return .{ .written = read.applied[i], .reading = read.after() };
        // An omitted trailing argument reads as the default the declaration
        // gives it, which names no parameter and so reads under no reading.
        // A head the parser refused is recorded all the same, so a parameter
        // can name a position no argument and no default fills.
        return if (p.default.wasWritten()) .{ .written = p.default, .reading = .{} } else null;
    }
    return null;
}

/// The alias a written type is a use of, where it is one that can be read as
/// the type it names: not one already being expanded, which is an alias that
/// names itself and was refused where it is declared.
fn aliasUsed(ast: *const Ast, ctx: anytype, read: *const Reading, x: node.TypeRef) ?DeclId {
    if (x.kind != .named and x.kind != .selection) return null;
    if (x.name == TokenId.none) return null;
    const alias = switch (ctx.reaches(x.name)) {
        .alias => |d| d,
        .nothing, .type_ => return null,
    };
    if (ast.declTag(alias) != .alias or read.expands(alias)) return null;
    return alias;
}

/// What an alias's use reads as: the type it names, with its parameters
/// standing for the arguments written at the use.
fn throughAlias(ast: *const Ast, alias: DeclId, use: node.TypeRef, outer: *const Reading) Reading {
    return .{ .family = alias, .applied = ast.typeArgs(use.args), .outer = outer };
}

/// Whether two written type-argument lists name the same types.
///
/// The one answer to "do these two written types name one type", read by
/// coherence for the arguments of two implementations and by the bounds of one
/// parameter for the arguments of two bounds. It is the structure of what was
/// written and never unification: `Lookup[I]` and `Lookup[J]` are two keys
/// even where `I` and `J` later settle to one type, because asking otherwise
/// would put the unifier underneath name resolution -- a name's meaning would
/// depend on whether two types *could* be made equal.
///
/// What is read is the type a name reached and not its spelling, because two
/// modules may each declare an `Id`; an alias is the type it names, with its
/// parameters standing for what was written at the use, so `Swap[UInt8, Bool]`
/// is `Pair[Bool, UInt8]` when `Swap[A, B]` names `Pair[B, A]`; and what a type
/// spells as an expression is the value it folds to, so `[UInt8; 4]` and
/// `[UInt8; 2 + 2]` are one array.
///
/// `ra` and `rb` say how each side's own parameters are read. A name that
/// reached no type -- a parameter written in each header -- is compared as
/// spelled, since nothing declares it.
///
/// `ctx` answers `reaches(tok) Reached` for a written name,
/// `sameValue(a, b) !bool` for two constant expressions and names its `Error`.
///
/// **Bound:** `written_node_budget` nodes of the types the lists stand for, and
/// no more. An alias used twice stands for a tree of its expansion, so a type
/// written in a few lines can stand for one larger than anything written; two
/// uses of one alias with the same arguments are one type without expanding
/// either, which keeps what a module writes alike linear, and what the budget
/// leaves unread is answered as not provably the same type.
pub fn sameWrittenArgs(
    ast: *const Ast,
    ctx: anytype,
    a: node.TypeRefRange,
    ra: Reading,
    b: node.TypeRefRange,
    rb: Reading,
) @TypeOf(ctx).Error!bool {
    var left: usize = written_node_budget;
    return sameArgs(ast, ctx, a, ra, b, rb, &left);
}

/// How many nodes of the types a list stands for one comparison reads. Nodes
/// are counted once an alias and a parameter have been read as what they stand
/// for, so two spellings of one type spend the same.
const written_node_budget: usize = 1 << 16;

/// How many nodes of the types a list stands for one hash reads: the first of
/// them in the order the comparison reads them, so two lists it calls the same
/// stop at the same node and hash alike. A hash is only the cheap half of
/// telling two lists apart, so one that stops early is a coarser key that
/// costs a comparison and never an answer.
const hashed_node_budget: usize = 1 << 8;

fn sameArgs(
    ast: *const Ast,
    ctx: anytype,
    a: node.TypeRefRange,
    ra: Reading,
    b: node.TypeRefRange,
    rb: Reading,
    left: *usize,
) @TypeOf(ctx).Error!bool {
    if (a.len() != b.len()) return false;
    for (ast.typeArgs(a), ast.typeArgs(b)) |x, y| {
        if (!try sameType(ast, ctx, x, ra, y, rb, left)) return false;
    }
    return true;
}

/// One written type against another, by the rule `sameWrittenArgs` states.
///
/// A switch over what was written, with nothing to fall through to: what makes
/// two written types one is a property of the form, so a form added later says
/// here what its identity is or does not compile.
fn sameWrittenType(
    ast: *const Ast,
    ctx: anytype,
    lhs: node.TypeRef,
    ra: Reading,
    rhs: node.TypeRef,
    rb: Reading,
) @TypeOf(ctx).Error!bool {
    var left: usize = written_node_budget;
    return sameType(ast, ctx, lhs, ra, rhs, rb, &left);
}

fn sameType(
    ast: *const Ast,
    ctx: anytype,
    lhs: node.TypeRef,
    ra: Reading,
    rhs: node.TypeRef,
    rb: Reading,
    left: *usize,
) @TypeOf(ctx).Error!bool {
    const x = ast.withoutTypeGroups(lhs);
    const y = ast.withoutTypeGroups(rhs);
    // What stands in a parameter is the text of another place, so it is read
    // as that place read it and nothing under it is read a second time.
    if (parameterReading(ast, ra, x)) |held| return sameType(ast, ctx, held.written, held.reading, y, rb, left);
    if (parameterReading(ast, rb, y)) |held| return sameType(ast, ctx, x, ra, held.written, held.reading, left);
    const use_x = aliasUsed(ast, ctx, &ra, x);
    const use_y = aliasUsed(ast, ctx, &rb, y);
    // One alias applied to arguments that are the same types stands for one
    // type, which is what keeps nested aliases from being read leaf by leaf.
    // Arguments that differ may still stand for one type -- an alias need not
    // use a parameter -- so that answer is not final.
    if (use_x != null and use_x == use_y and try sameArgs(ast, ctx, x.args, ra, y.args, rb, left)) return true;
    if (use_x) |alias| {
        return sameType(ast, ctx, ast.declReturnRef(alias), throughAlias(ast, alias, x, &ra), y, rb, left);
    }
    if (use_y) |alias| {
        return sameType(ast, ctx, x, ra, ast.declReturnRef(alias), throughAlias(ast, alias, y, &rb), left);
    }
    if (left.* == 0) return false;
    left.* -= 1;
    // A type is the declaration its name reached, however it was written:
    // bare, qualified by the module that declares it, or qualified by one
    // that re-exports it. Only a selection that reached no type -- a member of
    // another type -- is told apart by what it selects from.
    if (headType(ctx, x)) |a| {
        if (headType(ctx, y)) |b| return a == b and try sameHeadArgs(ast, ctx, a, x.args, ra, y.args, rb, left);
    }
    if (x.kind != y.kind) return false;
    return switch (x.kind) {
        // A name and its arguments.
        .named => sameWrittenNames(ast, ctx, x.name, y.name) and
            try sameArgs(ast, ctx, x.args, ra, y.args, rb, left),
        .selection => try sameType(ast, ctx, ast.selectionBase(x), ra, ast.selectionBase(y), rb, left) and
            sameWrittenNames(ast, ctx, x.name, y.name) and
            try sameArgs(ast, ctx, x.args, ra, y.args, rb, left),
        // The element and how many of them, because both are the type.
        .array => try sameArgs(ast, ctx, x.args, ra, y.args, rb, left) and try sameArrayLength(ctx, x, y),
        .callable => try sameWrittenCallable(ast, ctx, ast.callableType(x), ra, ast.callableType(y), rb, left),
        // The components in order, which is what makes two tuples one.
        .borrow, .grouped, .tuple => try sameArgs(ast, ctx, x.args, ra, y.args, rb, left),
    };
}

/// The arguments two applications of one declaration write, with the defaults
/// the declaration gives the arguments either omitted: `Vec[T]` and
/// `Vec[T, SystemAllocator]` apply one declaration to one list.
fn sameHeadArgs(
    ast: *const Ast,
    ctx: anytype,
    identity: u32,
    a: node.TypeRefRange,
    ra: Reading,
    b: node.TypeRefRange,
    rb: Reading,
    left: *usize,
) @TypeOf(ctx).Error!bool {
    if (a.len() == b.len()) return sameArgs(ast, ctx, a, ra, b, rb, left);
    const parameters = declaredParameters(ast, identity);
    if (a.len() > parameters.len or b.len() > parameters.len) return false;
    const xs = ast.typeArgs(a);
    const ys = ast.typeArgs(b);
    for (parameters, 0..) |parameter, i| {
        const x = if (i < xs.len) xs[i] else parameter.default;
        const y = if (i < ys.len) ys[i] else parameter.default;
        if (!x.wasWritten() or !y.wasWritten()) return false;
        if (!try sameType(ast, ctx, x, if (i < xs.len) ra else .{}, y, if (i < ys.len) rb else .{}, left)) return false;
    }
    return true;
}

/// The parameters of the declaration a head identity names, none for a
/// primitive.
fn declaredParameters(ast: *const Ast, identity: u32) []const node.TypeParam {
    if (identity & Reached.primitive_identity != 0) return &.{};
    return ast.declTypeParams(DeclId.at(identity));
}

/// Hashes the arguments an application of a declaration writes as
/// `sameHeadArgs` compares them: completed with the defaults of the arguments
/// omitted, so spellings it calls one hash alike.
fn hashHeadArgs(
    ast: *const Ast,
    ctx: anytype,
    h: *std.hash.Wyhash,
    identity: u32,
    args: node.TypeRefRange,
    read: Reading,
    left: *usize,
) @TypeOf(ctx).Error!void {
    const parameters = declaredParameters(ast, identity);
    const written = ast.typeArgs(args);
    if (written.len >= parameters.len or !parameters[written.len].default.wasWritten()) return hashArgs(ast, ctx, h, args, read, left);
    // The width `hashArgs` hashes, so a completed list and a written one agree.
    const count: u32 = @intCast(parameters.len);
    h.update(std.mem.asBytes(&count));
    for (parameters, 0..) |parameter, i| {
        if (i < written.len) {
            try hashType(ast, ctx, h, written[i], read, left);
        } else {
            try hashType(ast, ctx, h, parameter.default, .{}, left);
        }
    }
}

/// The type a written type is headed by: the declaration or primitive a name
/// reached, bare or qualified, or the prelude's declaration of a tuple's
/// arity, which no name in scope need reach. A module declaring its own
/// `Tuple2` shadows the name and not the syntax, so a tuple and the prelude's
/// name for it are one type and the module's own is another. Null for every
/// other form and for a name that reached no type.
fn headType(ctx: anytype, x: node.TypeRef) ?u32 {
    switch (x.kind) {
        .named, .selection => {
            if (x.name == TokenId.none) return null;
            return reachedType(ctx.reaches(x.name));
        },
        .tuple => {
            const decl = ctx.tuple(x.args.len()) orelse return null;
            return @intFromEnum(decl);
        },
        else => return null,
    }
}

/// Whether two written names are headed by the same type, by the declaration
/// each reached. A name that reached no type is compared as spelled, on the
/// tag as well as the name: only an identifier carries a name, so every builtin
/// shares the same absent one and comparing names alone would make `Holds[u8]`
/// and `Holds[bool]` one key.
fn sameWrittenNames(ast: *const Ast, ctx: anytype, x: TokenId, y: TokenId) bool {
    const a = reachedType(ctx.reaches(x));
    const b = reachedType(ctx.reaches(y));
    if (a != null or b != null) return a != null and b != null and a.? == b.?;
    return sameWrittenName(ast, x, y);
}

fn reachedType(reached: Reached) ?u32 {
    return switch (reached) {
        .type_ => |t| t,
        .nothing, .alias => null,
    };
}

/// Two arrays' written lengths: both inferred, or both counts of the same value.
fn sameArrayLength(ctx: anytype, x: node.TypeRef, y: node.TypeRef) @TypeOf(ctx).Error!bool {
    if (x.inferred_length != TokenId.none or y.inferred_length != TokenId.none) {
        return x.inferred_length != TokenId.none and y.inferred_length != TokenId.none;
    }
    return ctx.sameValue(x.length, y.length);
}

fn sameWrittenCallable(
    ast: *const Ast,
    ctx: anytype,
    x: node.CallableType,
    ra: Reading,
    y: node.CallableType,
    rb: Reading,
    left: *usize,
) @TypeOf(ctx).Error!bool {
    if (x.invocation != y.invocation) return false;
    const a = ast.params[x.params.start..x.params.end];
    const b = ast.params[y.params.start..y.params.end];
    if (a.len != b.len) return false;
    for (a, b) |p, q| {
        if (p.convention != q.convention) return false;
        if (ast.tokenName(p.name) != ast.tokenName(q.name)) return false;
        if (!try sameType(ast, ctx, p.written, ra, q.written, rb, left)) return false;
        if ((p.default == ExprId.none) != (q.default == ExprId.none)) return false;
        if (p.default != ExprId.none and !try ctx.sameValue(p.default, q.default)) return false;
    }
    // A result written by neither is `()` in both; one written by only one is
    // a different result, as `()` is never written.
    if (x.result.wasWritten() != y.result.wasWritten()) return false;
    if (x.result.wasWritten() and !try sameType(ast, ctx, x.result, ra, y.result, rb, left)) return false;
    return sameWrittenContracts(ast, x.contracts, y.contracts);
}

/// Hashes what `sameWrittenArgs` compares, reading the text as it does: two
/// lists it calls the same hash alike, so an index keyed by this one cannot
/// disagree with which repeated requirement is one requirement. An expression
/// is hashed as the value it folds to, and as its spelling where it folds to
/// none, which is when the comparison reads its spelling.
///
/// `ctx` answers what the comparison asks and `valueKey(expr) !u64` for the
/// hash of a constant expression.
///
/// Reads the first `hashed_node_budget` nodes of the types the list stands
/// for and no more.
pub fn hashWrittenArgs(
    ast: *const Ast,
    ctx: anytype,
    h: *std.hash.Wyhash,
    args: node.TypeRefRange,
    read: Reading,
) @TypeOf(ctx).Error!void {
    var left: usize = hashed_node_budget;
    return hashArgs(ast, ctx, h, args, read, &left);
}

fn hashArgs(
    ast: *const Ast,
    ctx: anytype,
    h: *std.hash.Wyhash,
    args: node.TypeRefRange,
    read: Reading,
    left: *usize,
) @TypeOf(ctx).Error!void {
    const count = args.len();
    h.update(std.mem.asBytes(&count));
    for (ast.typeArgs(args)) |argument| try hashType(ast, ctx, h, argument, read, left);
}

fn hashType(
    ast: *const Ast,
    ctx: anytype,
    h: *std.hash.Wyhash,
    grouped: node.TypeRef,
    read: Reading,
    left: *usize,
) @TypeOf(ctx).Error!void {
    const written = ast.withoutTypeGroups(grouped);
    if (parameterReading(ast, read, written)) |held| return hashType(ast, ctx, h, held.written, held.reading, left);
    if (aliasUsed(ast, ctx, &read, written)) |alias| {
        return hashType(ast, ctx, h, ast.declReturnRef(alias), throughAlias(ast, alias, written, &read), left);
    }
    if (left.* == 0) return;
    left.* -= 1;
    const head = headType(ctx, written);
    const kind: u8 = @intFromEnum(if (head != null) @TypeOf(written.kind).named else written.kind);
    h.update(std.mem.asBytes(&kind));
    if (head) |identity| {
        h.update("type");
        h.update(std.mem.asBytes(&identity));
        return hashHeadArgs(ast, ctx, h, identity, written.args, read, left);
    }
    switch (written.kind) {
        .borrow, .grouped, .tuple => try hashArgs(ast, ctx, h, written.args, read, left),
        .named => {
            hashWrittenName(ast, ctx, h, written.name);
            try hashArgs(ast, ctx, h, written.args, read, left);
        },
        .selection => {
            try hashType(ast, ctx, h, ast.selectionBase(written), read, left);
            hashWrittenName(ast, ctx, h, written.name);
            try hashArgs(ast, ctx, h, written.args, read, left);
        },
        .array => {
            try hashArgs(ast, ctx, h, written.args, read, left);
            const inferred = written.inferred_length != TokenId.none;
            h.update(std.mem.asBytes(&inferred));
            if (!inferred) {
                const key = try ctx.valueKey(written.length);
                h.update(std.mem.asBytes(&key));
            }
        },
        .callable => {
            const callable = ast.callableType(written);
            const params = ast.params[callable.params.start..callable.params.end];
            for (params) |param| {
                const convention: u8 = @intFromEnum(param.convention);
                h.update(std.mem.asBytes(&convention));
                const name = ast.tokenName(param.name);
                h.update(std.mem.asBytes(&name));
                try hashType(ast, ctx, h, param.written, read, left);
                const has_default = param.default != ExprId.none;
                h.update(std.mem.asBytes(&has_default));
                if (has_default) {
                    const key = try ctx.valueKey(param.default);
                    h.update(std.mem.asBytes(&key));
                }
            }
            // As `sameWrittenCallable` reads it: an omitted result is `()`.
            if (callable.result.wasWritten()) try hashType(ast, ctx, h, callable.result, read, left) else h.update("()");
            hashWrittenContracts(ast, h, callable.contracts);
        },
    }
}

/// Hashes a written name as `sameWrittenNames` compares it: by the type it
/// reached, and as spelled where it reached none.
fn hashWrittenName(ast: *const Ast, ctx: anytype, h: *std.hash.Wyhash, tok: TokenId) void {
    if (reachedType(ctx.reaches(tok))) |t| {
        h.update("type");
        h.update(std.mem.asBytes(&t));
        return;
    }
    const tag: u8 = @intFromEnum(ast.tokenTag(tok));
    const name = ast.tokenName(tok);
    h.update(std.mem.asBytes(&tag));
    h.update(std.mem.asBytes(&name));
}

/// Whether two constant expressions a bound writes are one value: spelled
/// alike, or folding to one. Where a pair does not fold, the spelling is all
/// there is to read, and a bound is one scope's text, so the same spelling is
/// the same constant.
fn sameBoundConstant(ast: *const Ast, a: ExprId, b: ExprId, folded: ?constfold.CheckedValue, other: ?constfold.CheckedValue) bool {
    if (std.mem.eql(u8, ast.exprText(a), ast.exprText(b))) return true;
    const x = folded orelse return false;
    const y = other orelse return false;
    return x.eql(y);
}

/// The key a constant expression is hashed by: its value where it folds, so two
/// spellings of one value meet, and its spelling where it does not.
fn constantKey(ast: *const Ast, id: ExprId, folded: ?constfold.CheckedValue) u64 {
    var h: std.hash.Wyhash = .init(0);
    if (folded) |value| {
        h.update("value");
        value.hash(&h);
    } else {
        h.update("text");
        h.update(ast.exprText(id));
    }
    return h.final();
}

/// What `memo` holds for a constant expression, where it folded to a value.
fn checkedWorth(memo: *const constfold.Memo, id: ExprId) ?constfold.CheckedValue {
    return (memo.worthOf(id) orelse return null).checked();
}

/// What the passes after name resolution read of the names and constants a
/// bound writes: the tables resolution left and the memo the checker folded
/// into.
pub const SettledWritten = struct {
    ast: *const Ast,
    res: *const Resolution,
    memo: *const constfold.Memo,

    /// Reading tables already filled cannot fail.
    pub const Error = error{};

    pub fn reaches(self: SettledWritten, tok: TokenId) Reached {
        const b = self.res.writtenAt(tok);
        if (b == BindingId.none) return .nothing;
        return .of(self.res.kindOf(b), self.res.decls[b.index()], self.res.builtins[b.index()]);
    }

    fn folded(self: SettledWritten, id: ExprId) ?constfold.CheckedValue {
        return checkedWorth(self.memo, id);
    }

    /// The prelude's declaration of the tuple with `arity` components.
    pub fn tuple(self: SettledWritten, arity: usize) ?DeclId {
        return self.res.tupleDecl(arity);
    }

    pub fn sameValue(self: SettledWritten, a: ExprId, b: ExprId) Error!bool {
        return sameBoundConstant(self.ast, a, b, self.folded(a), self.folded(b));
    }

    pub fn valueKey(self: SettledWritten, id: ExprId) Error!u64 {
        return constantKey(self.ast, id, self.folded(id));
    }
};

/// Whether two bounds' written argument lists are the same bound's, by the
/// comparison coherence reads for two implementations' arguments.
pub fn sameBoundArgs(ast: *const Ast, ctx: anytype, a: node.TypeRefRange, b: node.TypeRefRange) @TypeOf(ctx).Error!bool {
    return sameWrittenArgs(ast, ctx, a, .{}, b, .{});
}

/// Hashes a bound's written arguments as `sameBoundArgs` compares them.
pub fn hashBoundArgs(ast: *const Ast, ctx: anytype, args: node.TypeRefRange) @TypeOf(ctx).Error!u64 {
    var h: std.hash.Wyhash = .init(0);
    try hashWrittenArgs(ast, ctx, &h, args, .{});
    return h.final();
}

test "bound arguments through an alias with parameters compare as the type it stands for" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\struct Pair[A, B] { first: A, second: B }
        \\alias Swap[A, B] = Pair[B, A]
        \\alias Twice[T] = Pair[T, T]
        \\trait Give[phantom T] {}
        \\fn _probe[
        \\    A: Give[Swap[UInt8, Bool]],
        \\    B: Give[Pair[Bool, UInt8]],
        \\    C: Give[Pair[UInt8, Bool]],
        \\    D: Give[Twice[UInt8]],
        \\    E: Give[Pair[UInt8, UInt8]],
        \\    F: Give[Twice[Bool]],
        \\](_a: A, _b: B, _c: C, _d: D, _e: E, _f: F) {}
        \\fn main() -> UInt8 { 0 }
    );
    const ast = &result.ast;
    try testing.expectEqual(@as(u32, 0), result.errors);
    const probe = declSpelledIn(ast, .{ .start = 0, .end = ast.declCount() }, "_probe");
    const params = ast.declTypeParams(probe);
    var args: [6]node.TypeRefRange = undefined;
    for (params, 0..) |param, i| args[i] = ast.boundsOf(param)[0].named.args;
    const unfolded: constfold.Memo = .empty;
    const settled: SettledWritten = .{ .ast = ast, .res = &result.res, .memo = &unfolded };
    const expected = [_][2]usize{ .{ 0, 1 }, .{ 0, 2 }, .{ 3, 4 }, .{ 3, 5 }, .{ 1, 2 } };
    const same = [_]bool{ true, false, true, false, false };
    for (expected, same) |pair, want| {
        try testing.expectEqual(want, try sameBoundArgs(ast, settled, args[pair[0]], args[pair[1]]));
        // Whatever the comparison calls one hashes alike.
        if (want) try testing.expectEqual(
            try hashBoundArgs(ast, settled, args[pair[0]]),
            try hashBoundArgs(ast, settled, args[pair[1]]),
        );
    }
}

test "an alias that names itself is read as spelled and never expanded forever" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\struct Vec[T] { v: T }
        \\alias Loop = Vec[Loop]
        \\trait Give[phantom T] {}
        \\fn _probe[A: Give[Loop], B: Give[Loop]](_a: A, _b: B) {}
        \\fn main() -> UInt8 { 0 }
    );
    const ast = &result.ast;
    const probe = declSpelledIn(ast, .{ .start = 0, .end = ast.declCount() }, "_probe");
    const params = ast.declTypeParams(probe);
    const unfolded: constfold.Memo = .empty;
    const settled: SettledWritten = .{ .ast = ast, .res = &result.res, .memo = &unfolded };
    try testing.expect(try sameBoundArgs(ast, settled, ast.boundsOf(params[0])[0].named.args, ast.boundsOf(params[1])[0].named.args));
}

test "aliases nested deep and used twice at each level are read without expanding every leaf" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const depth = 40;
    var text: std.Io.Writer.Allocating = .init(gpa);
    const w = &text.writer;
    try w.writeAll("struct Pair[A, B] { first: A, second: B }\nalias A0[T] = Pair[T, T]\n");
    for (1..depth + 1) |i| try w.print("alias A{d}[T] = Pair[A{d}[T], A{d}[T]]\n", .{ i, i - 1, i - 1 });
    try w.writeAll("trait Give[phantom T] {}\nstruct _Holder {}\n");
    try w.print("impl Give[A{d}[UInt8]] for _Holder {{}}\nimpl Give[A{d}[UInt8]] for _Holder {{}}\n", .{ depth, depth });
    try w.print("fn _probe[A: Give[A{d}[UInt8]], B: Give[A{d}[UInt8]], C: Give[A{d}[Bool]]](_a: A, _b: B, _c: C) {{}}\n", .{ depth, depth, depth });
    try w.writeAll("fn main() -> UInt8 { 0 }\n");
    const result = try resolveSource(gpa, text.written());
    const ast = &result.ast;
    // The two equal implementations are the one duplicate.
    try testing.expectEqual(@as(u32, 1), result.errors);
    const probe = declSpelledIn(ast, .{ .start = 0, .end = ast.declCount() }, "_probe");
    const params = ast.declTypeParams(probe);
    const unfolded: constfold.Memo = .empty;
    const settled: SettledWritten = .{ .ast = ast, .res = &result.res, .memo = &unfolded };
    const first = ast.boundsOf(params[0])[0].named.args;
    const second = ast.boundsOf(params[1])[0].named.args;
    const third = ast.boundsOf(params[2])[0].named.args;
    try testing.expect(try sameBoundArgs(ast, settled, first, second));
    try testing.expect(!try sameBoundArgs(ast, settled, first, third));
    try testing.expectEqual(try hashBoundArgs(ast, settled, first), try hashBoundArgs(ast, settled, second));
}

fn sameContractNames(ast: *const Ast, a: node.ContractPath, b: node.ContractPath) bool {
    if ((a.root == .none) != (b.root == .none)) return false;
    if (a.root != .none and ast.tokenName(a.root) != ast.tokenName(b.root)) return false;
    const x = ast.contractSteps(a);
    const y = ast.contractSteps(b);
    if (x.len != y.len) return false;
    for (x, y) |first, second| {
        if (std.meta.activeTag(first) != std.meta.activeTag(second)) return false;
        switch (first) {
            .field => |name| if (ast.tokenName(name) != ast.tokenName(second.field)) return false,
            .dereference => {},
        }
    }
    return true;
}

fn sameWrittenContracts(ast: *const Ast, a: node.ContractRange, b: node.ContractRange) bool {
    const x = ast.contracts[a.start..a.end];
    const y = ast.contracts[b.start..b.end];
    if (x.len != y.len) return false;
    for (x, y) |first, second| {
        if (first.kind != second.kind or first.borrows_source != second.borrows_source or
            !sameContractNames(ast, first.source, second.source) or
            !sameContractNames(ast, first.destination, second.destination) or
            !sameContractNames(ast, first.target, second.target)) return false;
    }
    return true;
}

fn hashWrittenContracts(ast: *const Ast, hash: *std.hash.Wyhash, range: node.ContractRange) void {
    for (ast.contracts[range.start..range.end]) |contract| {
        const kind: u8 = @intFromEnum(contract.kind);
        hash.update(std.mem.asBytes(&kind));
        hash.update(std.mem.asBytes(&contract.borrows_source));
        for ([_]node.ContractPath{ contract.source, contract.destination, contract.target }) |path| {
            const present = path.root != .none;
            hash.update(std.mem.asBytes(&present));
            if (present) {
                const root = ast.tokenName(path.root);
                hash.update(std.mem.asBytes(&root));
            }
            const steps = ast.contractSteps(path);
            hash.update(std.mem.asBytes(&steps.len));
            for (steps) |step| {
                const tag: u8 = @intFromEnum(std.meta.activeTag(step));
                hash.update(std.mem.asBytes(&tag));
                switch (step) {
                    .field => |at| {
                        const name = ast.tokenName(at);
                        hash.update(std.mem.asBytes(&name));
                    },
                    .dereference => {},
                }
            }
        }
    }
}

/// Whether two written types are headed by the same name.
fn sameWrittenName(ast: *const Ast, x: TokenId, y: TokenId) bool {
    // A callable's parameter type may be headed by no name token.
    if (x == TokenId.none or y == TokenId.none) return x == y;
    if (ast.tokenTag(x) != ast.tokenTag(y)) return false;
    return ast.tokenName(x) == ast.tokenName(y);
}

const Binding = struct {
    /// The interned name, so a lookup compares integers rather than bytes.
    /// The text is not kept: a diagnostic reads it from the token it
    /// underlines, which it has to hand anyway.
    name: StringId,
    kind: Kind,
    /// The statement that declared it, for a local; `.none` otherwise.
    stmt: StmtId,
    /// The declaration this belongs to: itself for a function, the enclosing
    /// one for a parameter or a local.
    decl: DeclId,
    /// Its position in the parameter list, for a parameter.
    param_index: u32,
    parameter_owner: ParameterOwner = .{ .declaration = .none },
    /// The token to underline when reporting it.
    at: TokenId,
    used: bool,
    /// Whether the name may be assigned again. A property of the binding
    /// rather than of its type, which is why assigning to a `let` is reported
    /// with the rules about what a name may do.
    mutable: bool,
    /// Exempt from the unused check: named with a leading underscore, or part
    /// of a statement that was already reported.
    exempt: bool,
    /// How far another module may reach this name through this one.
    ///
    /// A re-export binds the declaration it names, so reading the visibility
    /// off that declaration answers about the source. Whether this module
    /// passes it on is what its own visibility says, and that is what this
    /// records.
    reach: Reach = .module,
    /// Whether this name is here because the prelude offers it everywhere.
    ///
    /// It is in the module's scope so that writing it works and declaring it
    /// again is an ordinary duplicate -- but the module does not declare it,
    /// so nothing reaches it *through* the module.
    ambient: bool = false,
    /// Whether a `use` made this binding. It holds another module's
    /// declaration, and the path that named it is the only spelling it has.
    reexported: bool = false,
    /// Whether this is a `use` that reached nothing. Its path was reported
    /// where the `use` is written, so a name reaching it resolves to nothing
    /// and reports nothing more.
    unresolved: bool = false,
    /// Whether a struct pattern wrote this binder as the field's own name.
    ///
    /// `S { f }` binds the field to its own name, and the field and the binder
    /// are one token. So the token declaring this binding also names a field
    /// of the type, and rewriting it in place renames the field with it.
    names_a_field: bool = false,
    /// The primitive a `builtin_type` binding names. `.poison` for every other
    /// kind, which never reads it.
    builtin: TypeId = .poison,
};

/// A standalone tree and every resolver product keyed by it.
///
/// The source program is allocated so `ExpandedProgram.source` remains stable
/// when this value moves. Its AST is borrowed from the caller; the expanded AST
/// and resolution are owned here and share one lifetime.
pub const ResolvedTree = struct {
    source: *Program,
    modules: []program_mod.Module,
    expanded: ExpandedProgram,
    resolution: Resolution,

    pub fn deinit(self: *ResolvedTree, gpa: std.mem.Allocator) void {
        self.resolution.deinit(gpa);
        self.expanded.deinit(gpa);
        gpa.destroy(self.source);
        for (self.modules) |module| gpa.free(module.files);
        gpa.free(self.modules);
        self.* = undefined;
    }
};

/// Resolves a tree that is its own module, whole.
///
/// For a caller holding a tree and no directory structure: a test, the
/// generator, the fuzzer, the conformance runner's single-file cases. The
/// module has no name and no directory, so nothing it contains can be imported
/// and nothing in it can import.
pub fn resolveTree(gpa: std.mem.Allocator, ast: *const Ast, sink: *Sink) !ResolvedTree {
    const modules = try gpa.alloc(program_mod.Module, 1);
    errdefer gpa.free(modules);
    const files = try gpa.alloc(FileId, ast.parts.len);
    errdefer gpa.free(files);
    for (ast.parts, files) |part, *file| file.* = part.file;
    modules[0] = .{
        .name = "",
        .dir = "",
        .files = files,
        .decls = .{ .start = 0, .end = ast.declCount() },
        .imports = &.{},
    };
    const source = try gpa.create(Program);
    errdefer gpa.destroy(source);
    source.* = .{ .modules = modules, .ast = ast.* };
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    for (0..ast.tokenCount()) |i| {
        const tok = TokenId.at(@intCast(i));
        if (ast.tokenTag(tok) != .identifier) continue;
        const id = try interner.intern(gpa, ast.tokenText(tok));
        std.debug.assert(id == ast.tokenName(tok));
    }
    var result = try resolve(gpa, source, &interner, sink, .program);
    errdefer result.expanded.deinit(gpa);
    errdefer result.resolution.deinit(gpa);
    try result.expanded.collapseGeneratedDiagnostics(sink);
    return .{
        .source = source,
        .modules = modules,
        .expanded = result.expanded,
        .resolution = result.resolution,
    };
}

/// Resolves names to the bindings they refer to, reporting undefined references
/// and unused bindings.
///
/// The type checker reads the result to find a name's type, and code generation
/// will read it to find a name's storage.
pub fn resolve(
    gpa: std.mem.Allocator,
    program: *const Program,
    source_interner: *const Interner,
    sink: *Sink,
    purpose: Purpose,
) !ResolveResult {
    return resolveInternal(gpa, program, source_interner, sink, purpose, null, null);
}

fn resolveInternal(
    gpa: std.mem.Allocator,
    program: *const Program,
    source_interner: *const Interner,
    sink: *Sink,
    purpose: Purpose,
    captured_seed: ?*?Seed,
    resumed: ?*const Resumed,
) !ResolveResult {
    var expanded: ExpandedProgram = if (resumed) |input| input.expanded else undefined;
    var expanded_ready = resumed != null;
    errdefer if (expanded_ready) expanded.deinit(gpa);
    var ast = if (resumed) |input| &input.expanded.ast else &program.ast;
    var constraints: Constraints = .{};
    var r: Resolver = .{
        .gpa = gpa,
        .program = program,
        .current = program.primary,
        .ast = ast,
        .sink = sink,
        .purpose = purpose,
        .constraints = &constraints,
        .record_prefix = captured_seed != null,
    };
    defer r.free_references.deinit(gpa);
    defer r.capture_ranges.deinit(gpa);
    defer r.captures.deinit(gpa);
    defer r.capture_bindings.deinit(gpa);
    // Copyabled with every other list the resolver builds. Its contents are handed
    // to the resolution at the end, and until then a failure anywhere between
    // the first test recorded and that hand-over would otherwise leak every
    // name spelled so far.
    defer r.tests.deinit(gpa);
    defer r.bindings.deinit(gpa);
    defer r.visible.deinit(gpa);
    defer r.here_named.deinit(gpa);
    defer r.reachable_at.deinit(gpa);
    defer r.inherent.deinit(gpa);
    defer r.inherently_marked.deinit(gpa);
    defer r.inherent_selections.deinit(gpa);
    defer r.in_module.deinit(gpa);
    defer r.type_in_module.deinit(gpa);
    defer r.local_of.deinit(gpa);
    defer r.pattern_names.deinit(gpa);
    defer r.shadowed.deinit(gpa);
    defer r.import_at.deinit(gpa);
    defer r.top_named.deinit(gpa);
    defer r.exported_types.deinit(gpa);
    defer r.pattern_heads.deinit(gpa);
    defer r.internal_types.deinit(gpa);
    defer r.module_runs.deinit(gpa);
    defer r.top.deinit(gpa);
    defer r.members.deinit(gpa);
    defer r.member_at.deinit(gpa);
    defer r.impls.deinit(gpa);
    defer r.builtin_namespaces.deinit(gpa);
    defer r.folded.deinit(gpa);
    defer r.settled_aliases.deinit(gpa);
    defer r.used_type_params.deinit(gpa);
    defer r.type_param_slots.deinit(gpa);
    defer r.type_parameter_bindings.deinit(gpa);
    defer r.impl_of_head.deinit(gpa);
    defer r.inherent_heads.deinit(gpa);
    errdefer gpa.free(r.impl_of_decl);
    errdefer r.duplicate_impls.deinit(gpa);
    errdefer r.templates.deinit(gpa);
    errdefer r.unpaired_template_closures.deinit(gpa);
    errdefer r.postfix_functions.deinit(gpa);
    errdefer r.unlent_marks.deinit(gpa);
    errdefer r.bracket_readings.deinit(gpa);
    errdefer r.name_kinds.deinit(gpa);
    errdefer r.deferred_immutable.deinit(gpa);
    defer r.builtins.deinit(gpa);
    errdefer r.module_scopes.deinit(gpa);
    errdefer r.targets.deinit(gpa);
    errdefer r.integer_selections.deinit(gpa);
    errdefer r.trait_selections.deinit(gpa);
    errdefer r.shadowed_heads.deinit(gpa);
    errdefer r.variant_ordinals.deinit(gpa);
    errdefer r.alias_heads.deinit(gpa);
    errdefer r.refused_operations.deinit(gpa);
    errdefer r.refused_impls.deinit(gpa);
    errdefer r.spelled.deinit(gpa);
    errdefer r.written.deinit(gpa);
    errdefer r.scopes.deinit(gpa);
    errdefer r.scope_bindings.deinit(gpa);
    defer r.binding_scopes.deinit(gpa);
    errdefer r.scope_of_stmt.deinit(gpa);
    errdefer r.scope_of_expr.deinit(gpa);

    var module_of_file: std.AutoHashMapUnmanaged(FileId, ModuleId) = .empty;
    errdefer module_of_file.deinit(gpa);
    var prelude: std.ArrayList(BindingId) = .empty;
    defer prelude.deinit(gpa);
    var ambient: std.ArrayList(DeclId) = .empty;
    errdefer ambient.deinit(gpa);
    r.closures = try ClosureMap.Builder.init(gpa, ast.exprCount());
    defer r.closures.deinit();
    var early_bounds_checked = try program.ast.declTable(gpa, bool, false);
    defer early_bounds_checked.deinit(gpa);
    const early_type_parameter_uses = try gpa.alloc(bool, program.ast.type_params.len);
    defer gpa.free(early_type_parameter_uses);
    @memset(early_type_parameter_uses, false);

    if (resumed) |input| {
        expanded = input.expanded;
        r.expanded = &expanded;
        try r.importPrefix(input.prefix, input.relocation, source_interner);
        try prelude.appendSlice(gpa, input.prefix.seed.prelude);
        try appendRelocated(DeclId, gpa, &ambient, input.prefix.result.resolution.prelude, input.relocation);
        try r.indexTypeParams(0, ast.declCount());
        for (program.modules, 0..) |module, i| {
            if (module.library) continue;
            try r.declareModule(.from(i), prelude.items);
        }
        for (program.modules, 0..) |module, i| {
            if (module.library) continue;
            try r.reexportsOf(.from(i));
        }
        try r.noteScopeNames();
        r.ast = &program.ast;
        r.publishPrelude(ambient.items);
        try r.checkModifiers();
        try r.checkEntryPoint();
        try r.checkTests();
        r.ast = &expanded.ast;
        try r.declareModuleScopes();
        for (ast.parts) |part| {
            if (part.decl_start == part.decl_end) continue;
            try module_of_file.put(gpa, part.file, expanded.moduleOf(DeclId.at(part.decl_start)));
        }
    } else {
        try r.targets.appendNTimes(gpa, .none, ast.exprCount());
        try r.spelled.appendNTimes(gpa, .none, ast.exprCount());
        try r.written.appendNTimes(gpa, .none, ast.tokenCount());
        try r.scope_of_stmt.appendNTimes(gpa, .none, ast.stmtCount());
        try r.scope_of_expr.appendNTimes(gpa, .none, ast.exprCount());
        try r.indexTypeParams(0, ast.declCount());

        // Which module holds each file. A module holds one when it holds something
        // written in it, which is what reading the declarations answers -- so it
        // is read once here rather than per name that wants the module a token was
        // written in, which walked the program to answer about one token.
        //
        // The first module holding the file wins, which is the answer a walk from
        // the first module gave.
        for (program.modules, 0..) |*m, i| {
            for (m.decls.start..m.decls.end) |j| {
                const f = ast.fileOfDecl(DeclId.at(@intCast(j)));
                if (module_of_file.contains(f)) continue;
                try module_of_file.put(gpa, f, .from(i));
            }
        }

        // Before any module, because every module gets them: a primitive is a name
        // the compiler puts in scope, and it is in the module's own scope so that
        // declaring one again is the ordinary duplicate rather than a rule of its
        // own.
        try r.declareBuiltins();

        // Phase one, across every module before phase two begins anywhere. Every
        // declaration enters its module's scope before any body is walked, which
        // is what lets a call name a function declared further down -- and, across
        // modules, what lets one module's body name another's declaration without
        // the two being ordered.
        // A scope per module, filled in an order of this pass's choosing rather
        // than in the order the modules sit: the library binds before anything
        // that can see it.
        try r.module_runs.appendNTimes(gpa, .{ .from = 0, .to = 0 }, program.modules.len);

        // The library first, and completely -- its own re-exports resolved -- so
        // that what the prelude offers is settled before a module that sees it is
        // looked at.
        //
        // The prelude is the manifest's public `use` bindings, which exist once
        // the manifest is declared and are resolved in place by `reexportsOf`
        // below. Every module holds the binding rather than a copy of what it
        // names, so every library module sees the whole prelude whatever order
        // the manifest names them in.
        //
        // The manifest is the library's root module, which the loader recorded
        // as the prelude: every other sits in a directory below it, and every
        // name it offers comes from one of those. Read from that record rather
        // than from how a directory is spelled, which varies with where the
        // library was loaded from.
        const manifest: ModuleId = if (program.prelude != .none and program.modules[program.prelude.index()].library)
            program.prelude
        else
            .none;
        if (manifest != .none) try r.declareModule(manifest, &.{});

        // What every module can name without asking for it. These are bindings
        // in each module's own scope rather than a chain behind it, entered
        // after the module's own declarations and only for names it does not
        // declare, which is what lets a module shadow one.
        if (program.prelude != .none) {
            for (r.scopeOf(program.prelude)) |b| {
                // The reach the binding carries, not the visibility of what it
                // binds. A re-export binds the declaration it names, so reading
                // that declaration answers about the source rather than whether
                // this manifest publishes the alias. The alias's stored reach is
                // the answer member lookup already asks.
                if (r.bindings.items[b.index()].reach != .public) continue;
                try prelude.append(gpa, b);
            }
        }

        // Marked where they are collected, because a module's copy is the same
        // binding: nothing reaches these through a module that merely sees
        // them, and a re-export skips them for that reason.
        for (prelude.items) |b| r.bindings.items[b.index()].ambient = true;

        for (program.modules, 0..) |*m, i| {
            if (!m.library or ModuleId.from(i) == manifest) continue;
            try r.declareModule(.from(i), prelude.items);
        }
        for (program.modules, 0..) |*m, i| {
            if (!m.library) continue;
            try r.reexportsOf(.from(i));
        }

        // What those bindings name, kept for the passes below: an ambient name is
        // in no module's declarations, so nothing further down could find it.
        for (prelude.items) |b| try ambient.append(gpa, r.bindings.items[b.index()].decl);

        r.publishPrelude(ambient.items);

        // Before any written header is read, so an `impl` that duplicates one of
        // these is the second of the two and is what gets reported.
        try r.seedProvidedImplementations(ambient.items);

        {
            const z = tracy.beginZone(@src(), "rs.declare");
            defer z.end();
            for (program.modules, 0..) |*m, i| {
                if (m.library) continue;
                try r.declareModule(.from(i), prelude.items);
            }
            for (program.modules, 0..) |*m, i| {
                if (m.library) continue;
                try r.reexportsOf(.from(i));
            }

            // Here, because every module's run is filled by now and nothing below
            // adds to one.
            try r.noteScopeNames();
        }

        {
            const z = tracy.beginZone(@src(), "rs.modifiers");
            defer z.end();
            try r.checkModifiers();
            try r.checkEntryPoint();
            try r.checkTests();
        }

        // Every module's run is settled by here -- its own declarations, its
        // imports, what was re-exported to it and what the prelude gave it -- so
        // this is where the run a chain ends at can be written down.
        {
            const z = tracy.beginZone(@src(), "rs.scopes");
            defer z.end();
            try r.declareModuleScopes();
        }

        // Template planning resolves source member annotations and bodies before
        // expansion. Grow the same builder afterwards so generated expressions
        // retain source IDs as an exact prefix.

        var source_constraints = try Constraints.init(gpa, ast);
        defer source_constraints.deinit(gpa);
        r.constraints = &source_constraints;
        var derive_shared_valid = try ast.declTable(gpa, bool, true);
        defer derive_shared_valid.deinit(gpa);
        // Template identity and derive targets use the source module scopes. No
        // body or exact-domain table is read until expansion has frozen the tree.
        for (program.modules, 0..) |*m, i| {
            try r.enter(.from(i));
            for (m.decls.start..m.decls.end) |j| {
                const d = DeclId.at(@intCast(j));
                switch (ast.declTag(d)) {
                    .struct_, .enum_, .newtype => {
                        const attached = ast.attachedDeriveTraitRange(d).len() != 0;
                        if (ast.declTag(d) == .newtype and !attached) continue;
                        r.generic = d;
                        const errors_before = sink.error_count;
                        try r.refuseTypeParametersOfOneName(d);
                        try r.checkBounds(d);
                        // A derive header is valid when the type's own header
                        // is: field errors belong to the representation.
                        const header_valid = sink.error_count == errors_before;
                        if (attached) {
                            const params = ast.declTypeParamRange(d);
                            for (params.start..params.end, 0..) |parameter_index, local_index| {
                                early_type_parameter_uses[parameter_index] = r.used_type_params.items[local_index];
                            }
                            early_bounds_checked.set(d, true);
                        }
                        if (ast.declTag(d) != .newtype) {
                            for (ast.declFields(d)) |field| try r.useRef(field.written);
                            for (ast.declVariants(d)) |variant| {
                                for (ast.variantFields(variant)) |field| try r.useRef(field.written);
                            }
                            try r.reportUnusedTypeParams(d);
                        }
                        if (attached) {
                            // A type the parser could not name has already been
                            // reported. Its name slot holds whatever token stood
                            // there, and a header copied from it names nothing.
                            const named = ast.declName(d) != .none and ast.tokenTag(ast.declName(d)) == .identifier;
                            derive_shared_valid.set(d, named and header_valid and r.boundArityHolds(d));
                            // The type declaration is the shared attached header;
                            // each trait reference owns its own validity, so one
                            // unresolved entry cannot suppress a resolved sibling.
                            for (ast.derive_traits[ast.attachedDeriveTraitRange(d).start..ast.attachedDeriveTraitRange(d).end]) |trait| {
                                _ = try r.implTraitRef(trait.ref);
                                for (ast.typeArgs(trait.ref.args)) |arg| try r.useRef(arg);
                            }
                        }
                        r.generic = .none;
                    },
                    // What an alias names is read here, so a derive that compares
                    // written types reads through it.
                    .alias => {
                        r.generic = d;
                        try r.refuseTypeParametersOfOneName(d);
                        try r.checkBounds(d);
                        try r.useRef(ast.declReturnRef(d));
                        try r.reportUnusedTypeParams(d);
                        r.generic = .none;
                    },
                    .template_impl => {
                        r.generic = d;
                        try r.refuseTypeParametersOfOneName(d);
                        try r.checkBounds(d);
                        _ = try r.implTrait(d);
                        for (ast.typeArgs(ast.declTraitArgs(d))) |arg| try r.useRef(arg);
                        r.generic = .none;
                    },
                    .derive_impl => {
                        r.generic = d;
                        const errors_before = sink.error_count;
                        try r.refuseTypeParametersOfOneName(d);
                        try r.checkBounds(d);
                        for (ast.typeArgs(ast.declHead(d).args)) |arg| try r.useRef(arg);
                        try r.implTarget(d);
                        derive_shared_valid.set(d, ast.deriveHeadIsValid(d) and sink.error_count == errors_before);
                        for (ast.deriveTraits(d)) |trait| {
                            _ = try r.implTraitRef(trait.ref);
                            for (ast.typeArgs(trait.ref.args)) |arg| try r.useRef(arg);
                        }
                        r.generic = .none;
                    },
                    else => {},
                }
            }
        }
        try r.checkDeriveTemplates();

        expanded = try r.expand(source_interner, &derive_shared_valid);
        expanded_ready = true;
    }
    r.expanded = &expanded;
    ast = &expanded.ast;
    r.ast = ast;

    const source_ast = &program.ast;
    if (resumed == null) {
        try r.indexTypeParams(source_ast.declCount(), ast.declCount());
        try r.targets.appendNTimes(gpa, .none, ast.exprCount() - source_ast.exprCount());
        try r.spelled.appendNTimes(gpa, .none, ast.exprCount() - source_ast.exprCount());
        try r.written.appendNTimes(gpa, .none, ast.tokenCount() - source_ast.tokenCount());
        try r.scope_of_stmt.appendNTimes(gpa, .none, ast.stmtCount() - source_ast.stmtCount());
        try r.scope_of_expr.appendNTimes(gpa, .none, ast.exprCount() - source_ast.exprCount());
    }

    constraints = try Constraints.init(gpa, ast);
    errdefer constraints.deinit(gpa);
    r.constraints = &constraints;
    try r.closures.grow(ast.exprCount());

    // Read after expansion so both tables cover every generated declaration.
    var signatures = try Signatures.build(gpa, ast);
    errdefer signatures.deinit(gpa);
    r.signatures = &signatures;

    for (source_ast.parts.len..ast.parts.len) |part_index| {
        const part = &ast.parts[part_index];
        if (part.decl_start == part.decl_end) continue;
        const module = expanded.moduleOf(DeclId.at(part.decl_start));
        try module_of_file.put(gpa, part.file, module);
    }
    if (resumed == null) try r.registerGeneratedDeclarations();

    // Which implementation each member belongs to, before any annotation is
    // read: an `impl` is written after the members it holds, so a walk in
    // declaration order reaches a member before the parameters it may name.
    try r.noteImplementations();

    // An annotation names a type without referring to it as a value, so it is
    // not a `name_ref` and the walk over expressions never reaches one. A type
    // used only in annotations would otherwise be reported unused, which would
    // make the form that takes its type from context unwritable: `.Green` names
    // no enum, so something else has to.
    const z_ann = tracy.beginZone(@src(), "rs.annotations");
    for (program.modules, 0..) |module, i| {
        if (resumed != null and module.library) continue;
        try r.enter(.from(i));
        for (expanded.declsOf(.from(i))) |d| {
            // Source representations were resolved before expansion so copied
            // component types retain their bindings and import identities.
            if (resumed == null and d.index() < source_ast.declCount() and
                (ast.declTag(d) == .struct_ or ast.declTag(d) == .enum_ or ast.declTag(d) == .alias)) continue;
            if (ast.declTag(d) == .impl_) {
                try r.implTarget(d);
            }

            // A declaration's own type parameters answer before the module's
            // types while its annotations are read, so `T` in one declaration
            // is never the `T` of another.
            r.generic = d;
            r.impl_scope = r.implEnclosing(d);
            defer r.impl_scope = DeclId.none;
            r.trait_scope = if (ast.declTag(d) == .trait_)
                d
            else
                signatures.traitOf(ast, d) orelse DeclId.none;
            defer r.trait_scope = DeclId.none;
            // Before anything reads the list. A name written in an annotation
            // reaches the first parameter spelled that way, so a second of one
            // spelling decides nothing that follows it.
            if (d.index() < early_bounds_checked.len() and early_bounds_checked.get(d)) {
                const params = ast.declTypeParamRange(d);
                r.marks_for = d;
                r.used_type_params.clearRetainingCapacity();
                try r.used_type_params.ensureTotalCapacity(gpa, params.len());
                for (params.start..params.end) |parameter_index| {
                    r.used_type_params.appendAssumeCapacity(early_type_parameter_uses[parameter_index]);
                }
            } else {
                try r.refuseTypeParametersOfOneName(d);
                try r.checkBounds(d);
            }
            try r.refuseParametersOfOneName(d);

            // The arguments an `impl` supplies its trait are written types, so
            // they are read where every other written type is. Asked of the
            // `impl` rather than of the members carrying the same range: each
            // member records its header's arguments, and reading them per
            // member would report one mistake once per member. Read only where
            // a trait was named, because arguments are supplied to one -- and
            // brackets on a header naming none are what the parser reports.
            if (ast.declTag(d) == .impl_ and ast.declTrait(d) != TokenId.none) {
                for (ast.typeArgs(ast.declTraitArgs(d))) |a| try r.useRef(a);
                const head = ast.declHead(d);
                if (ast.declHasParameterHead(d) or head.kind == .callable) try r.useRef(head);
            }

            // A trait's parameters are in scope in the signatures it declares,
            // so the trait reads them: with `generic` the trait, a written `T`
            // is the trait's and is marked used by being written. A signature
            // read on its own would find neither -- its own list is empty, and
            // nothing else holds what its trait declared.
            if (ast.declTag(d) == .trait_) {
                r.trait_scope = d;
                var written = signatures.of(ast, d);
                while (written.next()) |sig| {
                    if (expanded.moduleOf(sig) != ModuleId.from(i)) continue;
                    // The signature is what `generic` names, so its own
                    // parameters answer first; the trait's answer through
                    // `trait_scope`. A signature may be generic on its own
                    // account, and both lists stand in the same place.
                    r.generic = sig;
                    for (ast.declParams(sig)) |p| try r.useRef(p.written);
                    try r.useRef(ast.declReturnRef(sig));
                }
                r.generic = d;
                r.trait_scope = DeclId.none;
            }

            // Read where the trait reads them, or twice over -- and the second
            // reading has no parameters to resolve against. A signature is a
            // function header, so what a function may not declare it may not
            // either -- and it skips the unused walk below, so the refusal is
            // asked here.
            if (ast.declIsSignature(d)) {
                for (ast.declTypeParams(d)) |p| try r.refuseCallablePhantom(p);
                r.generic = DeclId.none;
                continue;
            }

            for (ast.declParams(d)) |p| try r.useRef(p.written);
            for (ast.declVariants(d)) |v| for (ast.variantFields(v)) |f| {
                try r.useRef(f.written);
            };
            for (ast.declFields(d)) |f| try r.useRef(f.written);
            try r.useRef(ast.declReturnRef(d));
            // What an implementation applied its head to. The arguments and
            // not the head itself: an implementation's parameters are written
            // there and nowhere else, so a head left unread leaves every one
            // of them naming nothing -- while the constructor is what the
            // implementation is *for*, and naming it here would keep a type
            // alive that nothing else mentions.
            for (ast.typeArgs(ast.declHead(d).args)) |a| try r.useRef(a);
            try r.reportUnusedTypeParams(d);
            r.generic = DeclId.none;
        }
    }

    z_ann.end();

    // Every alias's written type is resolved by here, so what each one names
    // is known before anything asks what an alias stands for.
    try r.checkAliases(resumed != null);
    try r.recordAliasHeads();
    try r.recordRefusedOperations();

    // Every inherent `impl` header is resolved by here, and the first reader of
    // a primitive's namespace is the constant initialiser below.
    try r.collectBuiltinNamespaces();
    if (resumed == null) try r.refuseRepeatedPrimitiveMembers();

    // What a pattern's head reaches from a module declaring no type of its
    // spelling. Every module is declared by here, and nothing that could ask
    // has been read: a pattern is written inside an expression, and the first
    // expression this walk reads is the constant initialiser below.
    try r.noteExportedTypes();
    if (resumed) |input| {
        for (r.pattern_heads.items) |head| {
            r.written.items[head.token.index()] = .none;
            r.settlePatternHead(head);
        }
        for (input.prefix.seed.inherent_selections) |name| try r.markInherentlyNamed(name);
    }

    // A constant's initialiser, before anything compares the types written
    // around it. An array's length may name a constant and an implementation's
    // identity holds the length's value, so what a constant is worth has to be
    // readable where implementations are compared -- and what a constant is
    // worth is read through the names its initialiser reaches.
    //
    // It resolves against the module's scope, which is complete already: a
    // constant declares no parameters and has nowhere for a local to come
    // from, so there is nothing here that a body would have had to supply.
    {
        const z = tracy.beginZone(@src(), "rs.constants");
        defer z.end();
        for (program.modules, 0..) |module, i| {
            if (resumed != null and module.library) continue;
            try r.enter(.from(i));
            for (expanded.declsOf(.from(i))) |d| {
                // Traversal initializers share expression resolution with
                // constants, with their receiver in a declaration-local scope.
                switch (ast.declTag(d)) {
                    .constant, .traversal_ => try r.constantInitialiser(d),
                    else => {},
                }
            }
        }
    }

    // Every header is resolved by now, and either module owning a side may
    // have written one, so this is the first point where the whole set of
    // implementations exists in one place.
    {
        const z = tracy.beginZone(@src(), "rs.coherence");
        defer z.end();
        try r.checkCoherence();
    }

    // Phase two. Each body is resolved against a chain that holds its own
    // module's scope and this function's own names -- and nothing else, so a
    // module's declarations are invisible to another module except through the
    // import that names it.
    {
        const z = tracy.beginZone(@src(), "rs.bodies");
        defer z.end();
        for (program.modules, 0..) |module, i| {
            if (resumed != null and module.library) continue;
            try r.enter(.from(i));
            const module_scope = r.visible.items.len;
            for (expanded.declsOf(.from(i))) |d| try r.function(d, module_scope);
        }
    }

    // After the bodies, because what a body binds is known only once it has
    // been walked. A resumed run holds the library's bindings as a prefix it
    // imported, and those were checked when the prefix was resolved.
    {
        const z = tracy.beginZone(@src(), "rs.case");
        defer z.end();
        try r.checkNameCases(resumed != null, if (resumed) |input| input.prefix.seed.bindings.len else 0, source_interner);
    }

    // A function or import a postfix call named is used or not according to
    // what the call reached, which the checker decides. One unused apart from
    // such calls is deferred to it rather than reported here.
    var candidates: std.AutoHashMapUnmanaged(BindingId, void) = .empty;
    defer candidates.deinit(gpa);
    {
        var named = r.postfix_functions.valueIterator();
        while (named.next()) |n| {
            try candidates.put(gpa, n.function, {});
            if (n.through != BindingId.none and !n.shadowed) try candidates.put(gpa, n.through, {});
        }
    }
    var deferred_unused: std.ArrayList(BindingId) = .empty;
    errdefer deferred_unused.deinit(gpa);

    for (r.bindings.items, 0..) |b, index| {
        if (b.used or b.exempt) continue;

        // A `use` that binds a trait is reached by the methods resolving
        // through it and not by its name -- `a.acquire(n)` needs `Allocator`
        // in scope and never writes the word. Which methods resolved that way
        // is the checker's answer and it is not settled until after this pass,
        // so this rule cannot see the use and says nothing rather than
        // refusing a program that is correct. What it still catches is the
        // alias of a type or a function nothing names, which is the shape a
        // `use` is usually left behind in.
        if (b.reexported and b.kind == .trait) continue;

        // A keyword the parser took in a name's place was reported there,
        // and no reference can name it.
        if (b.at != TokenId.none and ast.tokenTag(b.at) != .identifier) continue;

        const id = BindingId.at(@intCast(index));
        if (candidates.contains(id)) {
            try deferred_unused.append(gpa, id);
            continue;
        }
        try reportUnused(sink, ast, b.at, b.kind, b.reexported);
    }
    const finished_deferred_unused = try deferred_unused.toOwnedSlice(gpa);
    errdefer gpa.free(finished_deferred_unused);
    const finished_deferred_immutable = try r.deferred_immutable.toOwnedSlice(gpa);
    errdefer gpa.free(finished_deferred_immutable);

    // After the bodies, because what an expression reaches is what this reads
    // and none of it is settled until they are walked.
    {
        const z = tracy.beginZone(@src(), "rs.tests");
        defer z.end();
        try r.refuseNamesThatReachATest();
    }

    if (captured_seed) |out| out.* = try Seed.capture(gpa, &r, prelude.items);

    // Each owned from the moment it exists: a later allocation failing left
    // every earlier one belonging to a resolution that was never returned.
    const kinds = try gpa.alloc(Kind, r.bindings.items.len);
    errdefer gpa.free(kinds);
    const stmts = try gpa.alloc(StmtId, r.bindings.items.len);
    errdefer gpa.free(stmts);
    const decls = try gpa.alloc(DeclId, r.bindings.items.len);
    errdefer gpa.free(decls);
    const param_indices = try gpa.alloc(u32, r.bindings.items.len);
    errdefer gpa.free(param_indices);
    const parameter_owners = try gpa.alloc(ParameterOwner, r.bindings.items.len);
    errdefer gpa.free(parameter_owners);
    const builtins = try gpa.alloc(TypeId, r.bindings.items.len);
    errdefer gpa.free(builtins);
    const tokens = try gpa.alloc(TokenId, r.bindings.items.len);
    errdefer gpa.free(tokens);
    var reexported = try BindingBits.initEmpty(gpa, r.bindings.items.len);
    errdefer reexported.deinit(gpa);
    var field_shorthand = try BindingBits.initEmpty(gpa, r.bindings.items.len);
    errdefer field_shorthand.deinit(gpa);
    const reaches = try gpa.alloc(Reach, r.bindings.items.len);
    errdefer gpa.free(reaches);
    var ambient_names = try BindingBits.initEmpty(gpa, r.bindings.items.len);
    errdefer ambient_names.deinit(gpa);
    var referenced = try BindingBits.initEmpty(gpa, r.bindings.items.len);
    errdefer referenced.deinit(gpa);
    const by_stmt = try gpa.alloc(BindingId, ast.stmtCount());
    errdefer gpa.free(by_stmt);
    // Where each declaration's parameters begin, counted one to the right so
    // the running total below turns counts into starts in place.
    const param_starts = try gpa.alloc(u32, ast.declCount() + 1);
    errdefer gpa.free(param_starts);
    @memset(by_stmt, .none);
    @memset(param_starts, 0);
    var param_total: u32 = 0;
    for (r.bindings.items, 0..) |b, i| {
        const id = BindingId.at(@intCast(i));
        kinds[i] = b.kind;
        stmts[i] = b.stmt;
        decls[i] = b.decl;
        param_indices[i] = b.param_index;
        parameter_owners[i] = b.parameter_owner;
        builtins[i] = b.builtin;
        tokens[i] = b.at;
        reexported.set(id, b.reexported);
        field_shorthand.set(id, b.names_a_field);
        reaches[i] = b.reach;
        ambient_names.set(id, b.ambient);
        referenced.set(id, b.used);
        if (b.stmt != StmtId.none) by_stmt[b.stmt.index()] = id;
        if (b.kind == .parameter and b.decl != DeclId.none and b.decl.index() < ast.declCount()) {
            param_starts[b.decl.index() + 1] += 1;
            param_total += 1;
        }
    }
    for (1..param_starts.len) |i| param_starts[i] += param_starts[i - 1];

    const params_of = try gpa.alloc(BindingId, param_total);
    errdefer gpa.free(params_of);
    {
        const filled = try gpa.alloc(u32, ast.declCount());
        defer gpa.free(filled);
        @memset(filled, 0);
        for (r.bindings.items, 0..) |b, i| {
            if (b.kind != .parameter) continue;
            if (b.decl == DeclId.none or b.decl.index() >= ast.declCount()) continue;
            const at = param_starts[b.decl.index()] + filled[b.decl.index()];
            params_of[at] = BindingId.at(@intCast(i));
            filled[b.decl.index()] += 1;
        }
    }

    const closure_count = r.closures.exprs.items.len;
    const closure_param_starts = try gpa.alloc(u32, closure_count + 1);
    errdefer gpa.free(closure_param_starts);
    @memset(closure_param_starts, 0);
    var closure_param_total: u32 = 0;
    for (r.bindings.items) |b| {
        if (b.kind != .parameter) continue;
        switch (b.parameter_owner) {
            .closure => |closure| {
                closure_param_starts[closure.index() + 1] += 1;
                closure_param_total += 1;
            },
            .declaration => {},
        }
    }
    for (1..closure_param_starts.len) |i| closure_param_starts[i] += closure_param_starts[i - 1];
    const closure_params = try gpa.alloc(BindingId, closure_param_total);
    errdefer gpa.free(closure_params);
    if (closure_count > 0) {
        const filled = try gpa.alloc(u32, closure_count);
        defer gpa.free(filled);
        @memset(filled, 0);
        for (r.bindings.items, 0..) |b, i| switch (b.parameter_owner) {
            .closure => |closure| {
                if (b.kind != .parameter) continue;
                const at = closure_param_starts[closure.index()] + filled[closure.index()];
                closure_params[at] = BindingId.at(@intCast(i));
                filled[closure.index()] += 1;
            },
            .declaration => {},
        };
    }

    var closures = try r.closures.finish();
    errdefer closures.deinit(gpa);
    const capture_ranges = try r.capture_ranges.toOwnedSlice(gpa);
    errdefer gpa.free(capture_ranges);
    const captures = try r.captures.toOwnedSlice(gpa);
    errdefer gpa.free(captures);
    const free_references = try r.free_references.toOwnedSlice(gpa);
    errdefer gpa.free(free_references);

    // One handover at a time, each owned from the moment it is taken. Written
    // as one struct literal, a field that fails leaves every field before it
    // moved out of the resolver and into nothing.
    const targets = try r.targets.toOwnedSlice(gpa);
    errdefer gpa.free(targets);
    const spelled = try r.spelled.toOwnedSlice(gpa);
    errdefer gpa.free(spelled);
    const written = try r.written.toOwnedSlice(gpa);
    errdefer gpa.free(written);
    const ambient_decls = try ambient.toOwnedSlice(gpa);
    errdefer gpa.free(ambient_decls);

    // The scopes are complete, so what each declared can be put in a run of
    // its own.
    try r.groupScopeRuns();
    const scopes = try r.scopes.toOwnedSlice(gpa);
    errdefer gpa.free(scopes);
    const scope_bindings = try r.scope_bindings.toOwnedSlice(gpa);
    errdefer gpa.free(scope_bindings);
    const module_scopes = try r.module_scopes.toOwnedSlice(gpa);
    errdefer gpa.free(module_scopes);
    const scope_of_stmt = try r.scope_of_stmt.toOwnedSlice(gpa);
    errdefer gpa.free(scope_of_stmt);
    const scope_of_expr = try r.scope_of_expr.toOwnedSlice(gpa);
    errdefer gpa.free(scope_of_expr);

    const type_names = try r.typeNames(gpa);
    errdefer gpa.free(type_names);

    // Chained where the rows are made, so the two questions asked of them --
    // which declaration a name reaches, and which binding -- read an index
    // rather than the whole list.
    var named: Chain(.newest_first) = .empty;
    errdefer named.deinit(gpa);

    // Backwards, so that the row left at the head of each chain is the first
    // one recorded and a walk of the chain runs in the order of the list.
    var at: usize = type_names.len;
    while (at > 0) {
        at -= 1;
        const key = Resolution.namedKey(type_names[at].module, type_names[at].name);
        try named.note(gpa, key, @intCast(at));
    }

    // The trait rows, indexed where they are made so that a call reads the
    // traits its module sees under the call's name rather than every row.
    var trait_index = try indexTraitMembers(gpa, ast, type_names, &signatures);
    errdefer {
        trait_index.traits_seen.deinit(gpa);
        gpa.free(trait_index.traits);
        trait_index.sees.deinit(gpa);
        gpa.free(trait_index.trait_members);
        trait_index.members_named.deinit(gpa);
        trait_index.members_anywhere.deinit(gpa);
    }

    // The rows a name written after a type's name searches, kept past the walk
    // that made them so that listing a namespace and looking one name up in it
    // read one recording.
    var namespaced: std.ArrayList(Namespaced) = .empty;
    errdefer namespaced.deinit(gpa);
    for (r.members.items) |m| {
        if (m.trait != TokenId.none) continue;
        try namespaced.append(gpa, .{ .module = m.module, .owner = m.owner, .binding = m.binding });
    }
    const namespace_rows = try namespaced.toOwnedSlice(gpa);
    errdefer gpa.free(namespace_rows);

    var under: Chain(.newest_first) = .empty;
    errdefer under.deinit(gpa);
    var under_decl: Chain(.newest_first) = .empty;
    errdefer under_decl.deinit(gpa);

    // The declaration each inherent `impl` names, as the head walk settled
    // it. Sized by the inherent blocks and read once per member below, so
    // chaining the members by type costs the blocks plus the members and
    // never their product.
    var names_of_impl: std.AutoHashMapUnmanaged(DeclId, DeclId) = .empty;
    defer names_of_impl.deinit(gpa);
    try names_of_impl.ensureTotalCapacity(gpa, @intCast(r.inherent_heads.items.len));
    for (r.inherent_heads.items) |head| names_of_impl.putAssumeCapacity(head.impl, head.names);

    // Backwards, so the row left at the head of each chain is the first one
    // recorded and a walk runs in the order the declarations were written.
    // One entry per member in each, laid down in the one pass that reads the
    // rows.
    var row: usize = namespace_rows.len;
    while (row > 0) {
        row -= 1;
        const key = Resolution.underKey(namespace_rows[row].module, namespace_rows[row].owner);
        try under.note(gpa, key, @intCast(row));
        const member = r.bindings.items[namespace_rows[row].binding.index()].decl;
        if (names_of_impl.get(r.implEnclosing(member))) |d| {
            try under_decl.note(gpa, @intFromEnum(d), @intCast(row));
        }
    }

    const builtin_rows = try gpa.dupe(BuiltinNamespace, r.builtin_namespaces.items);
    errdefer gpa.free(builtin_rows);

    // The rows no header recorded, handed on as what they are. Read off the
    // one list rather than seeded a second time, so what the checker turns
    // into a row of its own table is exactly what coherence compared against.
    var provided: std.ArrayList(AmbientImpl) = .empty;
    errdefer provided.deinit(gpa);
    for (r.impls.items) |i| {
        if (i.decl != DeclId.none) continue;
        try provided.append(gpa, .{
            .trait = i.trait,
            .over = switch (i.head) {
                // Seeded for what no module declares: a type a module does
                // declare can be implemented for in Linea, so nothing
                // provides one.
                .declared, .borrow_, .callable_, .parameter, .default_ => continue,
                .builtin => |t| .{ .primitive = t },
                .array => .array,
            },
            .args = i.supplied,
            .viewed = i.viewed,
        });
    }
    const provided_rows = try provided.toOwnedSlice(gpa);
    errdefer gpa.free(provided_rows);

    // In the order the walk reached them, and not sorted here. What order the
    // tests are presented in is the transcript's rule and is stated there; a
    // sort here as well would be that rule written twice, and either copy could
    // be deleted with nothing to notice.
    //
    // The dispatcher's arms follow this order and nothing can observe it: a
    // name selects an arm, so which arm was written first is not a question a
    // program or a transcript can ask.
    const tests = try r.tests.toOwnedSlice(gpa);
    errdefer {
        for (tests) |t| gpa.free(t.qualified_name);
        gpa.free(tests);
    }

    var finished_reexported = reexported.freeze();
    errdefer finished_reexported.deinit(gpa);
    var finished_field_shorthand = field_shorthand.freeze();
    errdefer finished_field_shorthand.deinit(gpa);
    var finished_ambient = ambient_names.freeze();
    errdefer finished_ambient.deinit(gpa);
    var finished_referenced = referenced.freeze();
    errdefer finished_referenced.deinit(gpa);

    const normalized_constraints = constraints;
    constraints = .{};
    const resolution: Resolution = .{
        .variant_ordinals = r.variant_ordinals,
        .alias_heads = r.alias_heads,
        .refused_operations = r.refused_operations,
        .constraints = normalized_constraints,
        .closures = closures,
        .capture_ranges = capture_ranges,
        .captures = captures,
        .capture_bindings = r.capture_bindings,
        .free_references = free_references,
        .targets = targets,
        .integer_selections = r.integer_selections,
        .trait_selections = r.trait_selections,
        .shadowed_heads = r.shadowed_heads,
        .spelled = spelled,
        .written = written,
        .kinds = kinds,
        .stmts = stmts,
        .decls = decls,
        .param_indices = param_indices,
        .parameter_owners = parameter_owners,
        .builtins = builtins,
        .prelude = ambient_decls,
        .tuple_decls = r.tuple_decls,
        .type_names = type_names,
        .named = named,
        .traits_seen = trait_index.traits_seen,
        .traits = trait_index.traits,
        .sees = trait_index.sees,
        .trait_members = trait_index.trait_members,
        .members_named = trait_index.members_named,
        .members_anywhere = trait_index.members_anywhere,
        .namespaced = namespace_rows,
        .under = under,
        .under_decl = under_decl,
        .builtin_namespaces = builtin_rows,
        .ambient_impls = provided_rows,
        .tokens = tokens,
        .reexported = finished_reexported,
        .field_shorthand = finished_field_shorthand,
        .reach = reaches,
        .ambient = finished_ambient,
        .referenced = finished_referenced,
        .binding_of_stmt = by_stmt,
        .entry = r.entry,
        .tests = tests,
        .param_starts = param_starts,
        .params_of = params_of,
        .closure_param_starts = closure_param_starts,
        .closure_params = closure_params,
        .scopes = scopes,
        .scope_bindings = scope_bindings,
        .module_scopes = module_scopes,
        .scope_of_stmt = scope_of_stmt,
        .scope_of_expr = scope_of_expr,
        .signatures = signatures,
        .impl_of_decl = r.impl_of_decl,
        .module_of_file = module_of_file,
        .duplicate_impls = r.duplicate_impls,
        .refused_impls = r.refused_impls,
        .templates = r.templates,
        .unpaired_template_closures = r.unpaired_template_closures,
        .postfix_functions = r.postfix_functions,
        .unlent_marks = r.unlent_marks,
        .bracket_readings = r.bracket_readings,
        .name_kinds = r.name_kinds,
        .deferred_unused = finished_deferred_unused,
        .deferred_immutable = finished_deferred_immutable,
    };
    r.capture_bindings = .empty;
    return .{ .expanded = expanded, .resolution = resolution };
}

/// Reports assigning to, or lending with `&`, a binding that cannot change.
/// One routine for the resolver, which reports an assignment, and the
/// checker, which reports a `&` that meets an `inout` parameter.
pub fn reportImmutableBinding(sink: *Sink, ast: *const Ast, id: ExprId, kind: Kind, declared_at: TokenId) std.mem.Allocator.Error!void {
    if (kind == .builtin_type or kind == .type_parameter) {
        const labels = try sink.arena.alloc(Label, 1);
        labels[0] = .{
            .file = ast.fileOfExpr(id),
            .span = ast.exprSpan(id),
            .message = "type namespaces are immutable",
            .style = .primary,
        };
        try sink.add(.{
            .severity = .err,
            .code = .n_immutable,
            .message = try std.fmt.allocPrint(
                sink.arena,
                "type namespace `{s}` cannot be mutated",
                .{ast.tokenText(ast.exprMain(id))},
            ),
            .labels = labels,
        });
        return;
    }
    // What the binding is, for the sentence and the label under its
    // declaration. Only a value binding is declared with `let`.
    const what: []const u8 = switch (kind) {
        .parameter => "a read-only parameter",
        .function => "a function",
        .declared_type => "a type",
        .trait => "a trait",
        .module => "a module",
        .constant => "a constant",
        .associated_type => "a type a trait declares",
        .capture => "captured by a closure that cannot change it",
        else => "declared with `let`",
    };
    const declared_label: []const u8 = switch (kind) {
        .parameter => "read-only parameter declared here",
        .capture => "captured here; a capture changes only in an `inout` closure that owns it",
        .local, .binder => "declared with `let` here",
        else => "declared here",
    };
    // A binding the parser could not read a declaration for has no token
    // to point at, and the frontend never fails -- so the sentence loses
    // its second half rather than the walk losing its footing. `let a
    // UInt8 = 9` makes one: the missing `:` turns the initialiser into an
    // assignment to a name nothing declared.
    const known = declared_at != TokenId.none;
    const labels = try sink.arena.alloc(Label, if (known) 2 else 1);
    // Rendered in the order given, and a reader follows the source
    // downwards, so the declaration comes first.
    if (known) labels[0] = .{
        .file = ast.fileOf(declared_at),
        .span = ast.tokenSpan(declared_at),
        .message = declared_label,
        .style = .secondary,
    };
    labels[labels.len - 1] = .{
        .file = ast.fileOfExpr(id),
        .span = ast.exprSpan(id),
        .message = "this binding cannot be assigned",
        .style = .primary,
    };
    try sink.add(.{
        .severity = .err,
        .code = .n_immutable,
        .message = try std.fmt.allocPrint(
            sink.arena,
            "`{s}` is {s}",
            .{ ast.tokenText(ast.exprMain(id)), what },
        ),
        .labels = labels,
    });
}

test "a `&` lending a `let` is left to the checker, and an assignment is reported by what it names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\struct Counter { count: UInt8 }
        \\fn add(inout counter: Counter) { counter.count += 1 }
        \\fn fresh() -> Counter { Counter { count = 0 } }
        \\fn main() -> UInt8 {
        \\    let fixed = Counter { count = 1 }
        \\    add(&fixed)
        \\    fresh = fresh
        \\    fixed.count
        \\}
        \\
    );
    // The assignment to `fresh` is the resolver's one report; the `&` waits
    // for the parameter it meets.
    try testing.expectEqual(@as(u32, 1), result.errors);
    try testing.expectEqual(@as(usize, 1), result.res.deferred_immutable.len);
    const lent = result.res.deferred_immutable[0];
    try testing.expectEqualStrings("fixed", result.ast.tokenText(result.ast.exprMain(lent.name)));
    try testing.expectEqual(node.Expr.Tag.marked, result.ast.exprTag(lent.mark));

    var sink = Sink.init(arena.allocator());
    try reportImmutableBinding(&sink, &result.ast, lent.name, result.res.kindOf(lent.binding), result.res.declaringToken(lent.binding));
    try testing.expectEqualStrings("`fixed` is declared with `let`", sink.items()[0].message);
}

/// The kind of name a declaration's own name is, for [N-Case], or null where
/// it declares no name of its own there.
///
/// A trait implementation's members and settled types restate the trait's
/// names, so they are checked where the trait declares them; an `impl`, a
/// derive, a template and a `use` name what they are about rather than
/// declaring a name.
pub fn declaredNameKind(ast: *const Ast, d: DeclId) ?name_case.Kind {
    const restated = ast.declTrait(d) != TokenId.none and ast.declOwner(d) != TokenId.none;
    return switch (ast.declTag(d)) {
        .struct_, .enum_, .newtype, .alias => .declared_type,
        .trait_ => .trait,
        .associated_type => if (restated) null else .associated_type,
        .function => if (restated) null else .function,
        .projection => if (restated) null else .projection,
        .constant => if (restated) null else .constant,
        .traversal_ => .traversal,
        .import_ => .module,
        .use_, .impl_, .template_impl, .derive_impl, .err => null,
    };
}

/// The name [N-Case] offers in place of a miscased one: the name respelled
/// in its kind's case, or that respelling marked unusable where no program
/// can declare it -- a reserved word, `Self`, or a spelling with no letter to
/// carry the case.
pub const Respelling = union(enum) {
    offered: []const u8,
    unusable: []const u8,
};

/// Respells `name` for a name of `kind`. One routine for the diagnostic and
/// for a rename refusing a new name, so both suggest the same spelling.
pub fn respelling(gpa: std.mem.Allocator, name: []const u8, kind: name_case.Kind) std.mem.Allocator.Error!Respelling {
    const respelled = try name_case.recased(gpa, name, kind.case());
    const usable = token.Tag.keywordFromLexeme(respelled) == null and
        !std.mem.eql(u8, respelled, "Self") and
        name_case.of(respelled) == kind.case();
    return if (usable) .{ .offered = respelled } else .{ .unusable = respelled };
}

test "a respelling a program cannot declare is not offered" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    try testing.expectEqualStrings("Light", (try respelling(gpa, "light", .variant)).offered);
    try testing.expectEqualStrings("for", (try respelling(gpa, "For", .function)).unusable);
    try testing.expectEqualStrings("Self", (try respelling(gpa, "self", .type_parameter)).unusable);
}

/// Reports a binding nothing uses, under [M-Unused] for an import or a `use`
/// and [N-Unused] for anything else. One routine for the resolver, which
/// reports what nothing names, and the checker, which reports what only a
/// postfix call that reached an operation named.
pub fn reportUnused(sink: *Sink, ast: *const Ast, at: TokenId, kind: Kind, reexported: bool) std.mem.Allocator.Error!void {
    // A `use` is an import of one name where an import is of one module,
    // so it carries the same rule: there is nothing to suggest but
    // removal, and a leading `_` would still bind what it names.
    const rule: Code = if (kind == .module or reexported)
        .m_unused
    else
        .n_unused;

    try sink.addErrorFmt(
        rule,
        ast.fileOf(at),
        ast.tokenSpan(at),
        if (reexported) "remove the `use`" else switch (kind) {
            .function => "call it, or name it with a leading `_`",
            .declared_type, .type_alias => "name it in an annotation, or remove it",
            // No `_` form: an import that names nothing is removed, and a
            // name beginning with `_` would still bind a module.
            .module => "remove the import",
            // A leading `_` is what every parameter accepts: a trait
            // implementation's parameter keeps its signature's name, so
            // naming it `_` alone is refused there.
            .parameter => "name it with a leading `_` if the value is not wanted",
            else => "bind it as `_` if the value is not wanted",
        },
        "`{s}` is never used",
        .{ast.tokenText(at)},
    );
}

test "an unused binding is reported under the rule its kind names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\fn helper() -> UInt8 { 1 }
        \\fn main() -> UInt8 { 0 }
        \\
    );
    var sink = Sink.init(arena.allocator());
    const ast = &result.ast;
    const all: node.DeclRange = .{ .start = 0, .end = ast.declCount() };
    const helper = ast.declName(declSpelledIn(ast, all, "helper"));
    try reportUnused(&sink, ast, helper, .function, false);
    try reportUnused(&sink, ast, helper, .module, false);
    try testing.expectEqual(Code.n_unused, sink.items()[0].code.?);
    try testing.expectEqualStrings("`helper` is never used", sink.items()[0].message);
    try testing.expectEqual(Code.m_unused, sink.items()[1].code.?);
}

/// Whether a module may name a member reached through a type's or a trait's
/// name.
///
/// `governing` is the declaration whose visibility answers, which is the member
/// itself except where a trait answers for its signature; `holding` is the
/// module the member was written in and `writing` the one naming it. One rule,
/// so what a written name reaches and what a caller is told it could write are
/// the same set.
pub fn memberIsReachable(
    ast: *const Ast,
    program: *const Program,
    governing: DeclId,
    holding: ModuleId,
    writing: ModuleId,
) bool {
    return reachableFrom(program, reachForVisibility(ast.declVisibility(governing)), holding, writing);
}

/// What a name written after a dot on a type's or a trait's name reaches.
pub const Selectable = union(enum) {
    /// A declaration the namespace holds.
    member: BindingId,
    /// A variant, as the token naming it: a variant declares no binding of its
    /// own. `Shade.Dim` settles on the enum and records its variant ordinal
    /// separately from the binding.
    variant: TokenId,
};

/// Whether a name of this kind opens a namespace rather than standing for a
/// value -- which is what says which side of a dot it may be written on.
///
/// Exhaustive, with no `else`: a kind of name added to the language answers
/// this before the build succeeds. One predicate, because `selectableUnder`
/// deciding what a namespace holds and a server deciding whether to ask are
/// the same question asked at two moments.
pub fn namesANamespace(kind: Kind) bool {
    return switch (kind) {
        // An alias opens the namespace of the type it names.
        .declared_type, .builtin_type, .trait, .type_parameter, .type_alias => true,
        // A type a trait declares holds nothing of its own: what it stands
        // for is settled by an implementation, and a dot is written on that.
        .local, .parameter, .capture, .binder, .constant, .function, .module, .associated_type => false,
    };
}

/// Whether a name of this kind stands for no value at all.
///
/// A module and a trait are reached through, never read: no value has a trait
/// for its type, and a module is a place names live rather than a thing an
/// expression can be. The checker records unit for a qualifier of either so a
/// walk looking for a type it failed to settle does not stop there, and a
/// server declines to hover them for the same reason -- two readers of one
/// fact, which is why it is a predicate rather than an arm each.
///
/// Exhaustive, with no `else`: a kind of name added to the language answers
/// this before the build succeeds.
pub fn carriesNoValue(kind: Kind) bool {
    return switch (kind) {
        .module, .trait => true,
        .declared_type, .builtin_type, .type_alias, .local, .parameter, .capture, .binder, .constant, .function, .associated_type, .type_parameter => false,
    };
}

/// Whether a name a namespace holds may stand where a value belongs.
///
/// A type a trait declares may not, wherever it is reached from: it names what
/// an implementation settled, and [N-NotAValue] refuses it in an expression
/// however it is spelled. The rest may -- a function is written as the call it
/// takes, and a type, a trait or a module written after a dot is the head of
/// something further rather than the end of the expression.
///
/// One predicate, because a server deciding what to offer after a dot and a
/// property holding it to exactly what a namespace holds are the same question
/// asked at two moments. Asked twice it was answered twice, and the two
/// answers were an editor offering text the compiler refuses.
///
/// Exhaustive, with no `else`, so a kind of name added to the language says
/// which side of this it falls on before the build succeeds.
pub fn standsWhereAValueBelongs(kind: Kind) bool {
    return switch (kind) {
        .associated_type, .type_parameter, .type_alias => false,
        .local, .parameter, .capture, .binder, .constant => true,
        .function, .declared_type, .builtin_type, .trait, .module => true,
    };
}

/// Every name a dot written on a type's, a trait's or a primitive's name could
/// be followed by, in the order `selection` looks for one.
///
/// The plural of what a written selection settles: the namespace's own
/// declarations that the writing module may reach, then -- for an enum, and
/// after them, because a declaration answers first -- its variants. A caller
/// listing what may be written reads this rather than the declarations, or an
/// editor would offer the names the compiler refuses and none of the ones it
/// accepts.
///
/// A trait's namespace holds its signatures, and the trait's own visibility
/// answers for each: a signature carries none, and asking it would make every
/// operation of every foreign trait unreachable.
///
/// **Bound:** one lookup and the length of the namespace, plus the enum's own
/// variants -- both sized by the declaration rather than by the program. For a
/// primitive it is one pass over the inherent implementations written on
/// primitives, which the ownership rule leaves to the standard library.
pub fn selectableUnder(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    program: *const Program,
    res: *const Resolution,
    writing: ModuleId,
    written: BindingId,
    out: *std.ArrayList(Selectable),
) !void {
    out.clearRetainingCapacity();
    // A path through an alias selects from the type it names.
    const b = res.throughAlias(written);
    if (b == BindingId.none) return;

    if (res.builtinOf(b)) |primitive| {
        for (res.builtin_namespaces) |ns| {
            if (ns.of != primitive) continue;
            try appendMembers(gpa, ast, program, res, writing, ns.module, ns.owner, DeclId.none, out);
        }
        return;
    }

    // A parameter's properties come from checked constraints, not from
    // declarations inside the function or type that binds the parameter.
    if (res.kindOf(b) == .type_parameter) return;
    if (!namesANamespace(res.kindOf(b))) return;

    const decl = res.declaredBy(b);
    if (decl == DeclId.none) return;

    try appendMembers(
        gpa,
        ast,
        program,
        res,
        writing,
        program.moduleOf(decl),
        ast.tokenName(ast.declName(decl)),
        if (res.kindOf(b) == .trait) decl else DeclId.none,
        out,
    );

    if (ast.declTag(decl) != .enum_) return;
    for (ast.declVariants(decl)) |v| try out.append(gpa, .{ .variant = v.name });
}

/// The members of one namespace the writing module may name. `governs` is the
/// declaration answering for every one of them, or `.none` where each answers
/// for itself.
fn appendMembers(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    program: *const Program,
    res: *const Resolution,
    writing: ModuleId,
    module: ModuleId,
    owner: StringId,
    governs: DeclId,
    out: *std.ArrayList(Selectable),
) !void {
    var held = res.membersUnder(module, owner);
    while (held.next()) |m| {
        const written = res.declaredBy(m);
        if (written == DeclId.none) continue;
        const governing = if (governs == DeclId.none) written else governs;
        if (!memberIsReachable(ast, program, governing, program.moduleOf(written), writing)) continue;
        try out.append(gpa, .{ .member = m });
    }
}

/// Whether a declaration is the one the runtime calls, given that it sits in
/// the root module.
///
/// The module test is the caller's: one walks the root's declarations, one is
/// already inside a module and knows which, and one has the module index in
/// hand. What the declaration itself has to be is this, and it was written
/// three times with a different subset of the tests each time -- the exemption
/// from [N-Unused] asked only for the name, so a `struct main` or a `main`
/// inside an `impl` was exempted from a rule it was never entitled to escape.
pub fn namesTheEntryPoint(ast: *const Ast, d: DeclId) bool {
    if (ast.declTag(d) != .function) return false;
    if (ast.declOwner(d) != TokenId.none) return false;
    const name = ast.declName(d);
    if (ast.tokenTag(name) != .identifier) return false;
    return std.mem.eql(u8, ast.tokenText(name), "main");
}

/// Whether this declaration is reached by something that writes no call to it.
///
/// The entry point, which the runtime reaches; every test, which the compiler
/// calls where it runs one; and every `export`, which something outside the
/// module links against. None of the three is named by anything a program
/// writes, so none of them is what [N-Unused] is for -- and whatever any of
/// them calls is reached through it.
///
/// One question with one answer, because the exemption above was three
/// answers once and let a `struct main` out of a rule it was never entitled to
/// escape. A second declaration reached without a call is added here or
/// nowhere.
pub fn reachedWithoutACall(ast: *const Ast, d: DeclId, in_root: bool) bool {
    // The entry point is the root module's and a test is any module's. That
    // asymmetry is the whole of why this takes the module: a program is tested
    // module by module, so a test below the root is an ordinary test and not a
    // declaration nothing reaches.
    if (in_root and namesTheEntryPoint(ast, d)) return true;

    // An export is reached from outside the module that declares it: what
    // links against it is not this compilation, so no module's own boundary
    // decides whether something names it.
    //
    // Held to being a function for the reason a test is. Only a function is an
    // entry point something can call, and an `export` written on anything else
    // is refused -- so exempting one would let a declaration nothing reaches
    // out of a rule it was never entitled to escape, which is the mistake this
    // routine exists to have made once.
    if (ast.declIsExport(d) and ast.declTag(d) == .function) return true;

    if (!ast.declIsTest(d)) return false;

    // The same two conditions the entry point is held to. A test the parser
    // refused -- inside an `impl`, or on something that is not a function --
    // is not a body anything runs, so it is not exempt from being unused
    // either.
    return ast.declTag(d) == .function and ast.declOwner(d) == TokenId.none;
}

/// What a compilation is for.
///
/// A program's artefact holds what its entry point reaches; a test binary holds
/// what its tests reach and its entry point is one the compiler writes. Two
/// different questions about one source, and neither is the other's default --
/// so the caller says which it is asking rather than a pass inferring it from
/// whether a `main` happened to be found.
///
/// Declared here rather than beside lowering because this is the earliest pass
/// that has to know: whether a root must declare `main` is a rule, and a rule
/// answered in two places is answered twice.
pub const Purpose = enum { program, tests };

/// The name a test is known by outside the compiler.
///
/// A module is a directory, so a test's identity is that directory's path
/// beneath the program root, dot-separated, with the declaration's own name
/// last. The root module contributes nothing, which is what makes a test in a
/// program of one file known by its bare name.
///
/// A `.` inside a directory's name is written `\.`, and a `\` is written
/// `\\`, so the one directory `a.b` names its tests `a\.b.name` and the two
/// directories `a/b` name theirs `a.b.name`. Every other byte is the path as
/// written, so a reader still recognises the directory.
///
/// Not the emitted symbol. That one is mangled and carries type arguments,
/// because it identifies an instantiation to a linker; this one identifies a
/// test to a reader, who copies it out of a transcript and back onto a command
/// line. Spelled here alone, because the dispatcher, the runner and the
/// transcript each read it and three spellings would be three rules.
pub fn qualifiedTestName(
    gpa: std.mem.Allocator,
    root_dir: []const u8,
    module_dir: []const u8,
    name: []const u8,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    // Only what sits beneath the root contributes. A directory that does not
    // is not a module of this program, and reaching upwards to spell one would
    // put a path from outside the program into a name a reader is meant to
    // type back.
    const root = std.mem.trimEnd(u8, root_dir, "/");
    // A prefix at a component boundary, not a prefix of bytes: `/p` is not an
    // ancestor of `/paranoid`. A name built from a byte prefix would carry the
    // tail of a directory that is not a module of this program, and identify
    // nothing.
    const beneath = module_dir.len > root.len and
        std.mem.startsWith(u8, module_dir, root) and
        (root.len == 0 or module_dir[root.len] == '/');
    if (beneath) {
        var rest = module_dir[root.len..];
        while (rest.len > 0 and rest[0] == '/') rest = rest[1..];
        for (rest) |c| switch (c) {
            '/' => try out.append(gpa, '.'),
            '.', '\\' => try out.appendSlice(gpa, &.{ '\\', c }),
            else => try out.append(gpa, c),
        };
        if (rest.len > 0) try out.append(gpa, '.');
    }

    try out.appendSlice(gpa, name);
    return out.toOwnedSlice(gpa);
}

/// The builtin type named by a conversion callee, or null for another callee.
/// The checker combines this name resolution with symbolic type-parameter
/// evidence and records the authoritative target in Typing.conversionTarget.
/// Ownership and lowering consume that checked answer.
///
/// A bare name and nothing else, where `constructionOf` beside it takes a path
/// too. That is the language and not an omission: no module declares a
/// primitive, so no primitive is reachable through one and `a.UInt8` names
/// nothing in any module. A newtype is a declaration, and a declaration is
/// named through the module holding it as readily as by a word in scope.
pub fn conversionTo(ast: *const Ast, res: *const Resolution, call: ExprId) ?TypeId {
    const callee = ast.call(call).callee;
    // An array literal has no callee: nothing is being called, so nothing is
    // being converted.
    if (callee == ExprId.none) return null;
    if (ast.exprTag(callee) != .name_ref) return null;
    return res.builtinOf(res.throughAlias(res.targetOf(callee)));
}

/// The newtype a call constructs, or null where the callee does not name one.
///
/// Construction is a call whose callee names a newtype -- the same shape
/// `conversionTo` reads for a primitive, kept as a routine of its own because
/// a newtype is reached through a declaration rather than through a builtin
/// binding, so the two cannot answer through one lookup. The checker types
/// the construction and lowering erases it; a rule each worked out on its own
/// would be two rules that could disagree about which calls those are.
pub fn constructionOf(ast: *const Ast, res: *const Resolution, call: ExprId) ?DeclId {
    const callee = ast.call(call).callee;
    if (callee == ExprId.none) return null;
    const target = res.throughAlias(res.targetOf(callee));
    if (target == BindingId.none) return null;
    const decl = res.decls[target.index()];
    if (!headsConstruction(ast, callee, res.kindOf(target), decl)) return null;
    return decl;
}

/// Indexes trait-owned signatures and associated declarations by owner token.
/// Separate member chains preserve source order and avoid program-wide scans.
pub const Signatures = struct {
    /// The trait each owner token names.
    trait_of: std.AutoHashMapUnmanaged(TokenId, DeclId) = .empty,
    /// Which declarations are the signatures recording each owner token.
    declared: Chain(.newest_first) = .empty,
    /// Associated type declarations indexed by their trait owner.
    declared_types: Chain(.newest_first) = .empty,
    /// The name of every operation some trait declares, so the resolver can
    /// tell a name no trait holds from one a trait may supply to a type.
    operation_names: std.AutoHashMapUnmanaged(StringId, void) = .empty,

    pub fn build(gpa: std.mem.Allocator, ast: *const Ast) !Signatures {
        var trait_of: std.AutoHashMapUnmanaged(TokenId, DeclId) = .empty;
        errdefer trait_of.deinit(gpa);
        var declared: Chain(.newest_first) = .empty;
        errdefer declared.deinit(gpa);
        var declared_types: Chain(.newest_first) = .empty;
        errdefer declared_types.deinit(gpa);
        var operation_names: std.AutoHashMapUnmanaged(StringId, void) = .empty;
        errdefer operation_names.deinit(gpa);

        for (0..ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (ast.declTag(d) != .trait_) continue;
            try trait_of.put(gpa, ast.declName(d), d);
        }

        // Backwards, so the entry left at the head of each chain is the first
        // signature written and a walk of the chain runs in that order.
        var k: usize = ast.declCount();
        while (k > 0) {
            k -= 1;
            const sig = DeclId.at(@intCast(k));
            const owner = ast.declOwner(sig);
            if (owner == TokenId.none) continue;
            if (ast.declIsSignature(sig)) {
                try declared.note(gpa, @intFromEnum(owner), @intCast(k));
                if (ast.declTag(sig) == .function and trait_of.contains(owner))
                    try operation_names.put(gpa, ast.tokenName(ast.declName(sig)), {});
            } else if (ast.declTag(sig) == .associated_type and trait_of.contains(owner)) {
                try declared_types.note(gpa, @intFromEnum(owner), @intCast(k));
            }
        }

        return .{ .trait_of = trait_of, .declared = declared, .declared_types = declared_types, .operation_names = operation_names };
    }

    pub fn deinit(self: *Signatures, gpa: std.mem.Allocator) void {
        self.trait_of.deinit(gpa);
        self.declared.deinit(gpa);
        self.declared_types.deinit(gpa);
        self.operation_names.deinit(gpa);
    }

    /// Whether any trait in the program declares an operation named `name`.
    pub fn declaresOperation(self: *const Signatures, name: StringId) bool {
        return self.operation_names.contains(name);
    }

    test "declaresOperation knows every trait operation's name and nothing else" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        const source: Source = .{ .path = "t.lin", .text =
            \\trait Shape {
            \\    type Unit
            \\    fn area(x: Self) -> UInt8
            \\}
            \\struct Square { side: UInt8 }
            \\impl Square {
            \\    fn side(x: Square) -> UInt8 { x.side }
            \\}
            \\
        };
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var signatures = try Signatures.build(gpa, &ast);
        defer signatures.deinit(gpa);
        try testing.expect(signatures.declaresOperation(interner.ids.get("area").?));
        try testing.expect(!signatures.declaresOperation(interner.ids.get("side").?));
        try testing.expect(!signatures.declaresOperation(interner.ids.get("Unit").?));
    }

    /// The trait that declares `d`, or null where none does.
    pub fn traitOf(self: *const Signatures, ast: *const Ast, d: DeclId) ?DeclId {
        const owner = ast.declOwner(d);
        if (owner == TokenId.none) return null;
        return self.trait_of.get(owner);
    }

    /// The signatures `trait` declares, in the order they were written.
    pub fn of(self: *const Signatures, ast: *const Ast, trait: DeclId) Iter {
        return .{ .run = self.declared.walk(@intFromEnum(ast.declName(trait))) };
    }

    /// Associated types declared by the trait, in source order.
    pub fn typesOf(self: *const Signatures, ast: *const Ast, trait: DeclId) Iter {
        return .{ .run = self.declared_types.walk(@intFromEnum(ast.declName(trait))) };
    }

    pub const Iter = struct {
        run: Chain(.newest_first).Walk,

        pub fn next(self: *Iter) ?DeclId {
            return DeclId.at(self.run.next() orelse return null);
        }
    };
};

// Makes every test build compile the tests `Signatures` holds, including a
// build filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Signatures;
}

/// Where one module's declarations sit in the visible chain.
///
/// Not a lexical scope: this is the run of top-level bindings `enter` puts at
/// the bottom of the chain, one per module, and it says nothing about nesting.
const ModuleRun = struct { from: u32, to: u32 };

/// One type name a module can write, and what it means there.
pub const TypeName = struct {
    module: ModuleId,
    name: StringId,
    /// What the name declares, and `.none` for a primitive: nothing in source
    /// declares one, so the binding is the whole of its identity.
    decl: DeclId,
    binding: BindingId,
    /// Whether the name reaches a declared type, a trait, or a primitive. All
    /// three are recorded, because all three are reached by what the module can
    /// see rather than by their spelling, and a second table would be a second
    /// answer.
    kind: Kind,
};

/// One member a trait declares, recorded for a module that can name the trait.
///
/// A postfix call asks which traits its module can see declare the call's
/// name, and asks it once per call. These rows are that question's index: a
/// row per member of each trait a module can name, chained under the module
/// and the member's name, so a call reads the rows under its own key rather
/// than every type name in the program.
pub const TraitMember = struct {
    module: ModuleId,
    trait: DeclId,
    /// A signature or an associated type the trait declares.
    member: DeclId,
};

/// The trait rows of `type_names`, indexed for the questions a call and a
/// report ask of them: which traits a module sees, which of their members
/// carry a name there, and which members carry a name anywhere.
const TraitIndex = struct {
    traits_seen: Chain(.oldest_first),
    traits: []const DeclId,
    sees: std.AutoHashMapUnmanaged(u64, void),
    trait_members: []const TraitMember,
    members_named: Chain(.oldest_first),
    members_anywhere: Chain(.oldest_first),
};

/// Indexes the trait rows of `type_names` once, in their order.
///
/// **Bound:** one visit per trait row plus one per member of that row's
/// trait, read off the trait's own member chains -- so the whole index costs
/// what it holds, and never the program's declarations per row.
fn indexTraitMembers(gpa: std.mem.Allocator, ast: *const Ast, type_names: []const TypeName, signatures: *const Signatures) !TraitIndex {
    var traits_seen: Chain(.oldest_first) = .empty;
    errdefer traits_seen.deinit(gpa);
    var traits: std.ArrayList(DeclId) = .empty;
    errdefer traits.deinit(gpa);
    var sees: std.AutoHashMapUnmanaged(u64, void) = .empty;
    errdefer sees.deinit(gpa);
    var rows: std.ArrayList(TraitMember) = .empty;
    errdefer rows.deinit(gpa);
    var members_named: Chain(.oldest_first) = .empty;
    errdefer members_named.deinit(gpa);
    var members_anywhere: Chain(.oldest_first) = .empty;
    errdefer members_anywhere.deinit(gpa);

    // A trait is named by as many rows as modules that can name it, and its
    // declaration is what says two rows are one trait. Sized by the traits
    // named, which is at most the trait rows.
    var noted: std.AutoHashMapUnmanaged(DeclId, void) = .empty;
    defer noted.deinit(gpa);

    for (type_names, 0..) |t, at| {
        if (t.kind != .trait) continue;
        try traits_seen.note(gpa, @intFromEnum(t.module), @intCast(at));
        try sees.put(gpa, Resolution.seesKey(t.module, t.decl), {});
        const first_row = !noted.contains(t.decl);
        if (first_row) {
            try noted.put(gpa, t.decl, {});
            try traits.append(gpa, t.decl);
        }
        for ([_]Signatures.Iter{ signatures.of(ast, t.decl), signatures.typesOf(ast, t.decl) }) |declared| {
            var members = declared;
            while (members.next()) |member| {
                const row: u32 = @intCast(rows.items.len);
                try rows.append(gpa, .{ .module = t.module, .trait = t.decl, .member = member });
                const name = ast.tokenName(ast.declName(member));
                try members_named.note(gpa, Resolution.namedKey(t.module, name), row);
                if (first_row) try members_anywhere.note(gpa, @intFromEnum(name), row);
            }
        }
    }

    const traits_named = try traits.toOwnedSlice(gpa);
    errdefer gpa.free(traits_named);
    return .{
        .traits_seen = traits_seen,
        .traits = traits_named,
        .sees = sees,
        .trait_members = try rows.toOwnedSlice(gpa),
        .members_named = members_named,
        .members_anywhere = members_anywhere,
    };
}

/// One declaration a namespace holds, under the key a name written after a dot
/// searches it by.
///
/// The rows of `Member` whose header named no trait, kept past the walk that
/// made them: those are the ones a name reaches, and the rest belong to an
/// implementation and are reached through the trait instead.
pub const Namespaced = struct {
    module: ModuleId,
    owner: StringId,
    binding: BindingId,
};

/// One namespace a primitive's name opens: the module that wrote an inherent
/// `impl` on it, under the name that block wrote.
pub const BuiltinNamespace = struct {
    /// The primitive the block was written for.
    of: TypeId,
    module: ModuleId,
    owner: StringId,
};

/// One declaration written inside a type or a trait, and which one.
///
/// By name rather than by handle: an `impl` may sit in a different file from
/// the type, so which declaration it belongs to is settled when the type's own
/// name is, and every module resolves its own names.
///
/// The module joins that name because a name is only unique within one: two
/// modules may each declare a `Thing`, which is most of what a module is for,
/// and keying on the name alone made their members one namespace.
/// What identifies a member: everything `memberOf` matched on, as one value.
///
/// A member was found by walking every member the program declares, so
/// declaring one cost the members already declared and a name reaching one
/// cost all of them -- the product, for a question about a single name. The
/// fields are the scan's conditions unchanged, so the key means what the walk
/// meant.
const MemberKey = struct {
    module: ModuleId,
    owner: StringId,
    trait: TokenId,
    name: StringId,
};

const Member = struct {
    module: ModuleId,
    owner: StringId,
    /// The token an implementation's header wrote the trait at, or `.none`
    /// where it named none.
    ///
    /// Part of the key rather than a flag beside it. A trait implementation's
    /// members belong to the trait, so they neither collide with the type's own
    /// members nor answer a selection written on the type.
    ///
    /// The token rather than the name it spells, because one token is one
    /// implementation: two modules may each declare a `Measure`, and members
    /// written against one of them are not written against the other. The
    /// type's own namespace is the one key several headers share -- `.none` is
    /// what the braces and every inherent `impl` all write.
    trait: TokenId,
    binding: BindingId,
};

/// One implementation of a trait for a type, as the two declarations it names.
///
/// By declaration rather than by spelling: a re-exported name is the type it
/// aliases, and two modules may each declare a trait called `Measure`, so
/// neither side of an implementation is identified by the text that reached it.
/// What an implementation is written for.
///
/// A declaration where a module declares the type, because an implementation
/// written against a re-exported name is written against the type it aliases
/// and the declaration is what both reach. A handle where it is a builtin: no
/// module declares one, so there is no declaration to name it by, and the type
/// itself is its identity because nothing can alias it.
///
/// The array constructor where it is one: `[UInt8; 3]` and `[Key; 9]` are two
/// types of one family, and what the compiler implements for arrays it
/// implements for the family. No module declares that family and no one type
/// is it, so neither of the other two spellings names it.
pub const Head = union(enum) {
    parameter,
    default_,
    declared: DeclId,
    builtin: TypeId,
    array,
    borrow_,
    /// A callable type, by its shape: every callable of one shape is one family.
    callable_: node.CallableShape,
};

const Implementation = struct {
    trait: DeclId,
    /// What the implementation supplied for the trait's parameters, as
    /// written. Part of the key: `TryFrom[Int64] for UInt8` and `TryFrom[UInt8] for
    /// UInt8` are two implementations of one trait for one type, and neither is
    /// the other.
    args: node.TypeRefRange,
    head: Head,
    /// The `impl` itself. What a second implementation is reported at and what
    /// names both sides is written in its header, so it is read from there
    /// rather than copied out beside it.
    ///
    /// `.none` for one the compiler provides, which no source declares. Every
    /// row a header records carries the `impl` that was written, so nothing
    /// else is spelled that way.
    decl: DeclId,
    /// What a row the compiler provides supplies for its trait's parameters.
    /// Empty for every written row, which supplies its arguments as the
    /// written references `args` holds -- there is no spelling to hold here
    /// for a row no source wrote, and no written reference to read for one it
    /// did.
    supplied: []const ProvidedArg = &.{},
    /// Is true when a row the compiler provides for arrays answers through the
    /// array's `Slice` view.
    viewed: bool = false,
};

/// Which traits the compiler implements for the primitives, in the order
/// `std/cmp` declares them.
///
/// A module and a name rather than declarations, because this list is written
/// before any declaration is in hand -- and the module rather than the prelude,
/// because what the prelude publishes is a decision about what a *program* need
/// not import, and which types equal each other is not that decision. Two of
/// these five are not published: nothing a programmer types names `Equivalent`
/// or `Ordered`, and every integer carries both regardless.
///
/// A library that holds no such module seeds nothing, which is what a program
/// compiled without one gets.
const ambient_traits = [_]struct {
    module: []const u8,
    name: []const u8,
    over: []const TypeId,
}{
    // `Bool` has two values and no order, so it equals and is an equivalence
    // and stops there. `Float64` equals and orders partially and stops there:
    // a NaN is not equal to itself, so it can promise neither the reflexivity
    // `Equivalent` names nor the totality `Ordered` does. Every integer
    // carries all five.
    .{ .module = "cmp", .name = "Equatable", .over = &TypeId.primitives },
    .{ .module = "cmp", .name = "Equivalent", .over = &equivalence_primitives },
    .{ .module = "cmp", .name = "Comparable", .over = &comparable_primitives },
    .{ .module = "cmp", .name = "Ordered", .over = &integer_primitives },
    .{ .module = "cmp", .name = "Steppable", .over = &integer_primitives },
};

/// The primitives an order runs totally over: exactly the integers, read off
/// their descriptors rather than sliced from the shared list by position.
/// The positional cut meant `Bool` when it was written and stopped meaning it
/// when the list grew a float on the end -- which seeded `Bool` with an order
/// and left `Float64` without one, the second answer this file's own rules
/// warn about.
const integer_primitives = blk: {
    var out: [TypeId.primitives.len]TypeId = undefined;
    var n: usize = 0;
    for (TypeId.primitives) |p| {
        if (p.integerInfo() != null) {
            out[n] = p;
            n += 1;
        }
    }
    var cut: [n]TypeId = undefined;
    for (0..n) |i| cut[i] = out[i];
    break :blk cut;
};

/// What promises a reflexive equality: the integers and `Bool`, and not
/// `Float64`, whose NaN is the counterexample.
const equivalence_primitives = integer_primitives ++ [_]TypeId{.bool_};

/// What compares at all: the integers totally, and `Float64` partially.
const comparable_primitives = integer_primitives ++ [_]TypeId{.f64};

/// Which traits the compiler implements for the array constructor, and what
/// each supplies for the trait's own parameters.
///
/// An array holds elements a bracket reaches, and no module can write that
/// implementation: an array is written as a form rather than as a name, so
/// there is no head to write it under. One row per key -- a trait taking
/// arguments is implemented once per argument tuple -- so a further key is an
/// entry here and not a mechanism of its own.
///
/// An argument is a primitive, which is its own type wherever it is named, or
/// a type the prelude declares, which is a name here and a type once the
/// checker has interned the declaration it reaches, or one of those applied to
/// arguments of its own. Nothing wrote any of them, so there is no written
/// reference to read them off.
const ambient_array_traits = [_]struct { name: []const u8, args: []const ProvidedArg }{
    .{ .name = "Index", .args = &.{.{ .primitive = .u64 }} },
    .{ .name = "Index", .args = &.{.{ .prelude = "FromEnd" }} },
    .{ .name = "Index", .args = &.{.{ .applied = .{
        .name = "Range",
        .args = &.{.{ .primitive = .u64 }},
    } }} },
};

/// Lists the traits every array implements through its `Slice` view, each by
/// the module declaring it and its name.
///
/// Each takes its receiver only as whole `read` parameters, so the view reads
/// exactly the elements the array holds: an array answers where its view's
/// implementation applies, and its operations are the view's. `Release` is
/// not among them, because releasing a view settles none of its elements.
const viewed_array_traits = [_]struct { module: []const u8, name: []const u8 }{
    .{ .module = "cmp", .name = "Equatable" },
    .{ .module = "cmp", .name = "Equivalent" },
    .{ .module = "cmp", .name = "Comparable" },
    .{ .module = "cmp", .name = "Ordered" },
    .{ .module = "hash", .name = "Hash" },
    .{ .module = "fmt", .name = "Debug" },
};

/// What a row the compiler provides supplies for one of its trait's
/// parameters.
///
/// Three spellings because the resolver has one and not the others: a
/// primitive is a type before any declaration is read, a type the library
/// declares is a name until the checker interns it, and a generic one is a
/// name and its arguments until the checker instantiates it. Whichever it is,
/// it is written once here and read wherever the row is -- so the rows of one
/// trait for one head are told apart by what this says and not by where each
/// was seeded.
pub const ProvidedArg = union(enum) {
    primitive: TypeId,
    prelude: []const u8,
    applied: Applied,

    /// A prelude name with arguments supplied to it, which is what a row keyed
    /// on an instantiation supplies: `Range[UInt64]` is a name this pass has
    /// and a type it does not, and the arguments are themselves supplied the
    /// same three ways.
    pub const Applied = struct {
        name: []const u8,
        args: []const ProvidedArg,
    };

    /// Whether two rows supply the same thing. The prelude publishes one
    /// declaration per name, so a name is as good as the declaration it
    /// reaches for telling one row from another -- and an application is the
    /// same question asked of its name and of each argument in turn.
    pub fn same(self: ProvidedArg, other: ProvidedArg) bool {
        return switch (self) {
            .primitive => |t| other == .primitive and other.primitive == t,
            .prelude => |n| other == .prelude and std.mem.eql(u8, other.prelude, n),
            .applied => |a| {
                if (other != .applied) return false;
                if (!std.mem.eql(u8, other.applied.name, a.name)) return false;
                if (other.applied.args.len != a.args.len) return false;
                for (a.args, other.applied.args) |x, y| {
                    if (!x.same(y)) return false;
                }
                return true;
            },
        };
    }
};

/// One implementation the compiler provides: a trait the prelude publishes,
/// for a primitive.
///
/// Which pairs those are is decided here, where the prelude's declarations are
/// settled, and read by the checker off this record. A second reader deciding
/// it from the spellings again would be free to seed a row coherence never
/// saw, which is the shape of a written implementation losing silently to one
/// the compiler provides.
pub const AmbientImpl = struct {
    trait: DeclId,
    /// What it is implemented for: one primitive, or every array there is.
    over: Over,
    /// What it supplies for the trait's own parameters. `Index[UInt64]` and
    /// `Index[FromEnd]` are two implementations of one trait for one head, so
    /// the arguments are part of which row this is.
    args: []const ProvidedArg = &.{},
    /// Is true when an array row answers through the array's `Slice` view.
    viewed: bool = false,

    /// The two things the compiler implements for, which are the two a source
    /// cannot: a primitive, which no module declares, and the array
    /// constructor, which is not a name at all.
    pub const Over = union(enum) {
        primitive: TypeId,
        array,
    };
};

const TemplateValidation = struct {
    binding_floor: usize,
    token_start: u32,
    references: []BindingId,
    reflection: *ReflectionContext,
};

const ReflectionContext = struct {
    const ClosureParameter = struct { closure: ClosureId, name: StringId };

    template: DeclId,
    member: DeclId,
    cases: std.ArrayList(ReflectedCasePlan) = .empty,
    same_cases: std.ArrayList(SameCasePlan) = .empty,
    loops: std.ArrayList(ComponentLoopPlan) = .empty,
    places: std.ArrayList(ComponentPlacePlan) = .empty,
    metadata: std.ArrayList(MetadataPlan) = .empty,
    ordinals: std.ArrayList(OrdinalPlan) = .empty,
    wraps: std.ArrayList(reflection.WrapPlan) = .empty,
    constructions: std.ArrayList(reflection.ConstructionPlan) = .empty,
    component_types: std.ArrayList(reflection.ComponentTypePlan) = .empty,
    locals: std.ArrayList(reflection.LocalRename) = .empty,
    local_tokens: std.AutoHashMapUnmanaged(TokenId, u32) = .empty,
    shorthand_values: std.AutoHashMapUnmanaged(TokenId, void) = .empty,
    selection_bases: std.AutoHashMapUnmanaged(TokenId, void) = .empty,
    closure_bindings: std.AutoHashMapUnmanaged(BindingId, ClosureId) = .empty,
    closure_parameters: std.AutoHashMapUnmanaged(ClosureParameter, BindingId) = .empty,
    closure_values: std.AutoHashMapUnmanaged(ExprId, ClosureId) = .empty,
    closure_uses: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    captured_closures: std.AutoHashMapUnmanaged(ClosureId, std.ArrayList(ClosureId)) = .empty,
    recipe_floor: ?usize = null,
    active_subjects: std.ArrayList(BindingId) = .empty,
    active_case_depth: u32 = 0,
    active_loop: ?ComponentLoopPlan = null,
    runtime_loop_depth: u32 = 0,
    component_receiver: bool = false,
    valid: bool = true,

    fn deinit(self: *ReflectionContext, gpa: std.mem.Allocator) void {
        self.cases.deinit(gpa);
        self.same_cases.deinit(gpa);
        self.loops.deinit(gpa);
        self.places.deinit(gpa);
        self.metadata.deinit(gpa);
        self.ordinals.deinit(gpa);
        self.wraps.deinit(gpa);
        self.constructions.deinit(gpa);
        self.component_types.deinit(gpa);
        self.locals.deinit(gpa);
        self.local_tokens.deinit(gpa);
        self.shorthand_values.deinit(gpa);
        self.selection_bases.deinit(gpa);
        self.closure_bindings.deinit(gpa);
        self.closure_parameters.deinit(gpa);
        self.closure_values.deinit(gpa);
        self.closure_uses.deinit(gpa);
        var captures = self.captured_closures.valueIterator();
        while (captures.next()) |run| run.deinit(gpa);
        self.captured_closures.deinit(gpa);
        self.active_subjects.deinit(gpa);
    }

    fn finish(self: *ReflectionContext, gpa: std.mem.Allocator, parameters: []const ParameterPlan) !ReflectionMemberPlan {
        std.mem.sortUnstable(ReflectedCasePlan, self.cases.items, {}, struct {
            fn before(_: void, lhs: ReflectedCasePlan, rhs: ReflectedCasePlan) bool {
                return lhs.match.index() < rhs.match.index();
            }
        }.before);
        std.mem.sortUnstable(ComponentLoopPlan, self.loops.items, {}, struct {
            fn before(_: void, lhs: ComponentLoopPlan, rhs: ComponentLoopPlan) bool {
                return lhs.loop.index() < rhs.loop.index();
            }
        }.before);
        std.mem.sortUnstable(ComponentPlacePlan, self.places.items, {}, struct {
            fn before(_: void, lhs: ComponentPlacePlan, rhs: ComponentPlacePlan) bool {
                return lhs.call.index() < rhs.call.index();
            }
        }.before);

        const cases = try self.cases.toOwnedSlice(gpa);
        errdefer gpa.free(cases);
        const same_cases = try self.same_cases.toOwnedSlice(gpa);
        errdefer gpa.free(same_cases);
        const loops = try self.loops.toOwnedSlice(gpa);
        errdefer gpa.free(loops);
        const places = try self.places.toOwnedSlice(gpa);
        errdefer gpa.free(places);
        const metadata = try self.metadata.toOwnedSlice(gpa);
        errdefer gpa.free(metadata);
        const ordinals = try self.ordinals.toOwnedSlice(gpa);
        errdefer gpa.free(ordinals);
        const wraps = try self.wraps.toOwnedSlice(gpa);
        errdefer gpa.free(wraps);
        const constructions = try self.constructions.toOwnedSlice(gpa);
        errdefer gpa.free(constructions);
        const component_types = try self.component_types.toOwnedSlice(gpa);
        errdefer gpa.free(component_types);
        const locals = try self.locals.toOwnedSlice(gpa);
        return .{
            .member = self.member,
            .cases = cases,
            .same_cases = same_cases,
            .loops = loops,
            .places = places,
            .metadata = metadata,
            .ordinals = ordinals,
            .wraps = wraps,
            .parameters = parameters,
            .constructions = constructions,
            .component_types = component_types,
            .locals = locals,
        };
    }
};

const Resumed = struct {
    prefix: *const LibraryPrefix,
    expanded: ExpandedProgram,
    relocation: Relocation,
};

fn appendRelocated(comptime T: type, gpa: std.mem.Allocator, out: *std.ArrayList(T), rows: []const T, relocation: Relocation) !void {
    try out.ensureUnusedCapacity(gpa, rows.len);
    for (rows) |row| out.appendAssumeCapacity(relocation.value(row));
}

fn importDomain(comptime Id: type, comptime T: type, gpa: std.mem.Allocator, out: *std.ArrayList(T), rows: []const T, count: usize, empty: T, relocation: Relocation) !void {
    try out.appendNTimes(gpa, empty, count);
    for (rows, 0..) |row, i| out.items[relocation.id(Id, @enumFromInt(i)).index()] = relocation.value(row);
}

const PatternHead = struct { token: TokenId, name: StringId, root: program_mod.RootId };

/// One admitted inherent `impl` and the declaration its head names.
const InherentHead = struct { impl: DeclId, names: DeclId };

const Resolver = struct {
    gpa: std.mem.Allocator,
    program: *const Program,
    expanded: ?*const ExpandedProgram = null,
    ast: *const Ast,
    sink: *Sink,
    constraints: *const Constraints,
    closures: ClosureMap.Builder = undefined,
    free_references: std.ArrayList(ExprId) = .empty,
    capture_ranges: std.ArrayList(CaptureRange) = .empty,
    captures: std.ArrayList(ResolvedCapture) = .empty,
    capture_bindings: std.AutoHashMapUnmanaged(BindingId, CaptureLocation) = .empty,
    current_closure: ClosureId = .none,
    closure_binding_start: usize = 0,
    /// Every module's top-level bindings, concatenated, with `module_runs`
    /// giving each module's run. Kept apart from the working chain so a body
    /// can be resolved against its own module's declarations and a qualified
    /// name can be looked up in another's, without either seeing the other's.
    top: std.ArrayList(BindingId) = .empty,
    module_runs: std.ArrayList(ModuleRun) = .empty,
    /// Which module the walk is inside.
    current: ModuleId = .none,
    /// What this compilation is for, which decides whether a root must declare
    /// an entry point at all.
    purpose: Purpose = .program,
    /// The declaration the runtime calls, or `.none` where the program does
    /// not declare exactly one.
    entry: DeclId = DeclId.none,
    /// Every test the program declares, filled as the walk enters each
    /// declaration and sorted once at the end.
    tests: std.ArrayList(Resolution.Test) = .empty,

    /// The declaration whose type parameters are in scope, while its
    /// annotations are being read. `.none` everywhere else.
    generic: DeclId = DeclId.none,
    /// Which of the current declaration's type parameters an annotation has
    /// named, by index. Cleared when the declaration changes.
    used_type_params: std.ArrayList(bool) = .empty,
    /// The first type parameter of each name in each declaration, keyed by
    /// declaration and interned name. Built once per source or generated row,
    /// so each annotation lookup is constant rather than a scan of its list.
    type_param_slots: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    /// Which declaration `used_type_params` counts for.
    marks_for: DeclId = DeclId.none,
    /// The trait whose signatures are being read, whose parameters are in scope
    /// in every one of them.
    trait_scope: DeclId = DeclId.none,
    /// The implementation whose member is being read, whose parameters are in
    /// scope in every one of them. `.none` outside one.
    ///
    /// An implementation generic over its head declares the parameters its head
    /// applies, and a member writing that head out longhand writes them: `Self`
    /// and `Holder[T]` are one type, so the name in the second has to reach
    /// what the first stands for.
    impl_scope: DeclId = DeclId.none,
    /// Which implementation each head name token belongs to, for the ones
    /// declaring parameters.
    ///
    /// A member records the token its `impl` wrote the head with, which is the
    /// token that implementation is named by -- so the pair the parser recorded
    /// is what this reads back, rather than a second relation worked out from
    /// where the declarations sit.
    impl_of_head: std.AutoHashMapUnmanaged(TokenId, DeclId) = .empty,
    /// The implementation each declaration is a member of, which the
    /// resolution carries away: one relation, read here to put an
    /// implementation's parameters in scope in its members and by the checker
    /// to say what `Self` is in one.
    impl_of_decl: []DeclId = &.{},
    /// The declarations written inside types, with the type each belongs to.
    /// What a namespace holds is read off `member_at` while the walk runs and
    /// off the chains built from these rows afterwards, so nothing searches
    /// the list.
    members: std.ArrayList(Member) = .empty,
    /// Which binding each member key reaches. Kept beside `members` rather
    /// than replacing it: a diagnostic still reads the list to say which trait
    /// holds a name, and that runs only where a name was already not found.
    member_at: std.AutoHashMapUnmanaged(MemberKey, BindingId) = .empty,
    /// Every pair reported as one implementation written twice, handed to the
    /// resolution so the overlap check does not report the same pair again.
    duplicate_impls: std.AutoHashMapUnmanaged(u64, void) = .empty,
    /// See `Resolution.postfix_functions`.
    postfix_functions: std.AutoHashMapUnmanaged(ExprId, Resolution.PostfixFunction) = .empty,
    /// See `Resolution.unlent_marks`.
    unlent_marks: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// See `Resolution.bracket_readings`.
    bracket_readings: std.AutoHashMapUnmanaged(ExprId, Resolution.BracketReading) = .empty,
    /// See `Resolution.name_kinds`.
    name_kinds: std.AutoHashMapUnmanaged(TokenId, name_case.Kind) = .empty,
    /// The bracket a call is about to resolve as its callee, while it is
    /// one; `.none` elsewhere. Only a called bracket can reach a method.
    called_bracket: ExprId = .none,
    /// See `Resolution.deferred_immutable`.
    deferred_immutable: std.ArrayList(Resolution.DeferredImmutable) = .empty,
    /// The `&` whose place is being resolved, while it is one the checker
    /// holds against a parameter; `.none` elsewhere.
    lending_mark: ExprId = .none,
    /// Resolved once before derive requests are admitted.
    templates: std.AutoHashMapUnmanaged(DeclId, DeclId) = .empty,
    unpaired_template_closures: std.AutoHashMapUnmanaged(ClosureId, void) = .empty,
    /// Set only while a source template member is planned. Every reached
    /// binding is classified at the lookup that already settled its identity,
    /// so planning does not rediscover references by scanning syntax.
    template_validation: ?TemplateValidation = null,
    record_written_expr: bool = false,
    /// Every trait implementation the program writes, resolved to the pair of
    /// declarations it names. Collected as the headers are resolved, so that
    /// coherence is asked of the whole program at once.
    impls: std.ArrayList(Implementation) = .empty,
    /// The namespaces a primitive's name opens: one row per primitive, module
    /// and spelling, however many inherent blocks that module writes. Built
    /// once from `impls` after every header is resolved, and handed on as
    /// the resolution's own table, so member lookup, completion and the
    /// checker read one answer.
    builtin_namespaces: std.ArrayList(BuiltinNamespace) = .empty,
    /// The declaration each admitted inherent `impl` names in its head.
    /// Written where the head is resolved and read once per member when the
    /// members are chained under their type, so a member reaches its type's
    /// chain without resolving the head a second time. Rows rather than a
    /// map, so a library's rows are carried into the program that resumes
    /// from it the way its members and implementations are.
    inherent_heads: std.ArrayList(InherentHead) = .empty,
    /// What this run has folded, and what it is still working out.
    ///
    /// One per run, so a constant naming another is folded once however many
    /// lengths read it and however many comparisons a length joins. Coherence
    /// compares each implementation against the others carrying its key, so a
    /// length worked out per comparison would cost the square of what a module
    /// implements times the square of how far its constants chain.
    folded: constfold.Memo = .empty,
    /// The aliases whose written text has been walked and holds only settled
    /// lengths, so an alias used again is not walked again. One per run, so the
    /// walk reads each alias's text once however many uses and implementations
    /// reach it, and its size is the aliases the program declares.
    settled_aliases: std.AutoHashMapUnmanaged(DeclId, void) = .empty,
    /// Every binding the program declares, in declaration order. Append-only:
    /// a `BindingId` indexes it, and every later pass keys side tables by one.
    bindings: std.ArrayList(Binding) = .empty,
    /// The nine primitives, as the bindings that name them. Every module's
    /// scope opens with these, so a written `UInt8` reaches one wherever it is
    /// written and a declaration of that name collides with it.
    builtins: std.ArrayList(BindingId) = .empty,
    /// The bindings a name can currently see, innermost last. A block pops
    /// back to its entry mark, which is what ends a scope -- the binding
    /// itself stays, because the unused check still has to report it.
    visible: std.ArrayList(BindingId) = .empty,
    /// How much of `visible` is the module's own run, which `enter` fills and
    /// no scope below it touches.
    module_run: usize = 0,
    /// Which entries of `top` carry each name within the module being
    /// declared.
    ///
    /// `declareTop` reports the second declaration of a name and found it by
    /// reading every binding the module had entered so far, so a module of D
    /// declarations cost D squared before a body was read. The chain covers
    /// the same run and is walked in the same order, so the binding it stops
    /// at is the binding the scan stopped at.
    ///
    /// A chain and not a set, because a name already held is not always a
    /// duplicate: an import another file of the module wrote is exempt, and
    /// deciding that needs the binding rather than its presence.
    top_named: Chain(.oldest_first) = .empty,
    /// The declarations the prelude publishes, once the library is resolved.
    /// Syntax that needs a prelude declaration finds it here by identity.
    prelude_decls: []const DeclId = &.{},
    /// `Resolution.tuple_decls`, filled once the prelude is published.
    tuple_decls: TupleDecls = no_tuple_decls,
    /// Which binding each name reaches in each module's own run, keyed by the
    /// module and the name.
    ///
    /// The run was walked for one name, so a module of D declarations cost D
    /// for every `impl` head, every bound and every trait name written in it
    /// -- and both grow together. Filled forwards and only where a name is
    /// absent, so the binding it answers with is the one the walk stopped at.
    ///
    /// Keyed by the module rather than rebuilt per module: the walk read
    /// whichever module is current, and two of them are read with another
    /// current while a re-export is followed.
    here_named: std.AutoHashMapUnmanaged(u64, BindingId) = .empty,
    /// Every exported type the program declares, keyed by the name it is
    /// written under, and `.none` under a name two modules both export.
    ///
    /// What a pattern's head reaches where the module writing it declares no
    /// type of that spelling: a head cannot be qualified, so the only types it
    /// can be naming from outside are the ones another module exports.
    exported_types: std.AutoHashMapUnmanaged(StringId, BindingId) = .empty,
    pattern_heads: std.ArrayList(PatternHead) = .empty,
    pattern_index_ready: bool = false,
    record_prefix: bool = false,
    /// Every internal type under the root and name from which it is reachable.
    /// Kept separately from public types so storage remains linear in
    /// declarations rather than roots multiplied by public declarations.
    internal_types: std.AutoHashMapUnmanaged(u64, BindingId) = .empty,
    /// Which binding a name written after a dot reaches in each module, under
    /// the same key. A narrower set than `here_named`, because what a module
    /// can write and what it declares are different questions.
    reachable_at: std.AutoHashMapUnmanaged(u64, BindingId) = .empty,
    /// Which bindings an inherent member of each name reaches, and how much of
    /// `bindings` the chain covers.
    inherent: Chain(.newest_first) = .empty,
    inherent_upto: usize = 0,
    /// The names `markInherentlyNamed` has walked, so each is walked once.
    inherently_marked: std.AutoHashMapUnmanaged(StringId, void) = .empty,
    inherent_selections: std.ArrayList(StringId) = .empty,
    /// Which binding each name reaches within that run.
    in_module: Stamped(StringId, BindingId) = .empty,
    /// Which binding each name reaches as a *type* within that run, which is a
    /// different question: a written type name skips whatever is not one, so
    /// the first type of a name answers where the last binding of it would not.
    type_in_module: Stamped(StringId, BindingId) = .empty,
    /// Which local each name reaches, as an index into `visible` above the
    /// module's run.
    ///
    /// The locals were searched backwards for every reference, so a body of L
    /// locals and R references cost L times R -- and a body that threads a
    /// value through a long run of `let`s is exactly that shape. The map holds
    /// the innermost, which is what searching backwards found.
    local_of: Stamped(StringId, u32) = .empty,
    /// The names the pattern being bound has declared so far, and where. A
    /// pattern restarts it before its first binder, so what it holds is one
    /// pattern's -- sized by that pattern's binders, never by the body's.
    pattern_names: Stamped(StringId, TokenId) = .empty,
    /// What each local shadowed when it was declared, so the scope that ends
    /// puts back what its names meant before it.
    shadowed: std.ArrayList(Shadowed) = .empty,
    /// The scopes, the bindings each declared, and where each statement and
    /// each resolved name sit. The chain above, written down.
    ///
    /// A binding is recorded against the scope that was open when the walk
    /// declared it, in declaration order, and the two lists are parallel. They
    /// are grouped into a run per scope once the walk is done: a scope opened
    /// inside another declares its own bindings between that one's, so a run is
    /// contiguous only after the entries are ordered by the scope that made
    /// them.
    scopes: std.ArrayList(Scope) = .empty,
    scope_bindings: std.ArrayList(BindingId) = .empty,
    binding_scopes: std.ArrayList(ScopeId) = .empty,
    scope_of_stmt: std.ArrayList(ScopeId) = .empty,
    scope_of_expr: std.ArrayList(ScopeId) = .empty,
    /// The scope each module's own declarations are, made once each and
    /// entered again for every phase and every body.
    module_scopes: std.ArrayList(ScopeId) = .empty,
    /// The scope the walk is inside.
    scope: ScopeId = .none,
    /// The first binding each `(module, name, file)` import reaches.
    import_at: std.AutoHashMapUnmanaged(u64, BindingId) = .empty,

    targets: std.ArrayList(BindingId) = .empty,
    integer_selections: std.AutoHashMapUnmanaged(ExprId, IntegerSelection) = .empty,
    trait_selections: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    shadowed_heads: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// Which traits declare which signatures, read while bodies are walked to
    /// tell whether a name after a type's name may be a trait's operation.
    signatures: ?*const Signatures = null,
    variant_ordinals: std.AutoHashMapUnmanaged(ExprId, VariantOrdinal) = .empty,
    /// The type name each alias's written type is headed by, followed
    /// through aliases: `Point` for `alias Spot = Point`, `Option` for
    /// `alias Maybe = Option[UInt8]`. An alias of a function, array or
    /// parameter type is headed by no declaration and has no row. What a
    /// path, a call or a bound through an alias reaches is read here.
    alias_heads: std.AutoHashMapUnmanaged(DeclId, BindingId) = .empty,
    /// The names of the operations implementations refused for an alias
    /// head declare. The refusal is the report, so a call reaching none of
    /// its operations is not reported missing a second time.
    refused_operations: std.AutoHashMapUnmanaged(StringId, void) = .empty,
    /// The implementations this pass refused: reported as written where no
    /// module may write them, or for a head that names an alias or no type.
    /// Published as `Resolution.refused_impls`.
    refused_impls: std.AutoHashMapUnmanaged(DeclId, void) = .empty,
    spelled: std.ArrayList(TokenId) = .empty,
    written: std.ArrayList(BindingId) = .empty,
    /// Type parameter bindings keyed by their unique declaration token.
    /// They enter no value or module scope.
    type_parameter_bindings: std.AutoHashMapUnmanaged(TokenId, BindingId) = .empty,

    fn importPrefix(self: *Resolver, prefix: *const LibraryPrefix, relocation: Relocation, interner: *const Interner) !void {
        const gpa = self.gpa;
        const seed = &prefix.seed;
        const res = &prefix.result.resolution;
        try appendRelocated(Binding, gpa, &self.bindings, seed.bindings, relocation);
        try self.top.appendSlice(gpa, seed.top);
        try self.module_runs.appendSlice(gpa, seed.module_runs);
        try self.module_runs.appendNTimes(gpa, .{ .from = 0, .to = 0 }, self.program.modules.len - seed.module_runs.len);
        try appendRelocated(Member, gpa, &self.members, seed.members, relocation);
        try appendRelocated(Implementation, gpa, &self.impls, seed.implementations, relocation);
        try self.builtins.appendSlice(gpa, seed.builtins);
        for (self.builtins.items) |id| {
            const binding = &self.bindings.items[id.index()];
            binding.name = interner.ids.get(binding.builtin.nameOf()) orelse .none;
        }
        try self.scopes.appendSlice(gpa, res.scopes);
        try self.scope_bindings.appendSlice(gpa, seed.scope_bindings);
        try self.binding_scopes.appendSlice(gpa, seed.binding_scopes);
        try self.module_scopes.appendSlice(gpa, res.module_scopes);
        try appendRelocated(PatternHead, gpa, &self.pattern_heads, seed.pattern_heads, relocation);
        try appendRelocated(InherentHead, gpa, &self.inherent_heads, seed.inherent_heads, relocation);
        try importDomain(ExprId, BindingId, gpa, &self.targets, res.targets, self.ast.exprCount(), .none, relocation);
        try importDomain(ExprId, TokenId, gpa, &self.spelled, res.spelled, self.ast.exprCount(), .none, relocation);
        try importDomain(TokenId, BindingId, gpa, &self.written, res.written, self.ast.tokenCount(), .none, relocation);
        try importDomain(StmtId, ScopeId, gpa, &self.scope_of_stmt, res.scope_of_stmt, self.ast.stmtCount(), .none, relocation);
        try importDomain(ExprId, ScopeId, gpa, &self.scope_of_expr, res.scope_of_expr, self.ast.exprCount(), .none, relocation);
        for (res.closures.of_expr, 0..) |closure, i| self.closures.of_expr[relocation.id(ExprId, @enumFromInt(i)).index()] = closure;
        try appendRelocated(ExprId, gpa, &self.closures.exprs, res.closures.exprs, relocation);
        try self.capture_ranges.appendSlice(gpa, res.capture_ranges);
        try appendRelocated(ResolvedCapture, gpa, &self.captures, res.captures, relocation);
        try appendRelocated(ExprId, gpa, &self.free_references, res.free_references, relocation);
        var captured_bindings = res.capture_bindings.iterator();
        while (captured_bindings.next()) |row| try self.capture_bindings.put(gpa, row.key_ptr.*, row.value_ptr.*);
        var integers = res.integer_selections.iterator();
        while (integers.next()) |row| try self.integer_selections.put(gpa, relocation.id(ExprId, row.key_ptr.*), row.value_ptr.*);
        var through_traits = res.trait_selections.keyIterator();
        while (through_traits.next()) |id| try self.trait_selections.put(gpa, relocation.id(ExprId, id.*), {});
        var shadowed = res.shadowed_heads.keyIterator();
        while (shadowed.next()) |id| try self.shadowed_heads.put(gpa, relocation.id(ExprId, id.*), {});
        var variants = res.variant_ordinals.iterator();
        while (variants.next()) |row| try self.variant_ordinals.put(gpa, relocation.id(ExprId, row.key_ptr.*), row.value_ptr.*);
        // The library's bodies are not walked again, and what their brackets
        // hold is read after checking: which receiver a marked call lends.
        var brackets = res.bracket_readings.iterator();
        while (brackets.next()) |row| try self.bracket_readings.put(gpa, relocation.id(ExprId, row.key_ptr.*), row.value_ptr.*);
        var templates = res.templates.iterator();
        while (templates.next()) |row| try self.templates.put(gpa, relocation.id(DeclId, row.key_ptr.*), relocation.id(DeclId, row.value_ptr.*));
        var unpaired = res.unpaired_template_closures.keyIterator();
        while (unpaired.next()) |closure| try self.unpaired_template_closures.put(gpa, closure.*, {});
        var duplicates = res.duplicate_impls.iterator();
        while (duplicates.next()) |row| {
            const first: DeclId = @enumFromInt(@as(u32, @truncate(row.key_ptr.* >> 32)));
            const second: DeclId = @enumFromInt(@as(u32, @truncate(row.key_ptr.*)));
            try self.duplicate_impls.put(gpa, Resolution.duplicateKey(relocation.id(DeclId, first), relocation.id(DeclId, second)), {});
        }
        for (self.members.items) |held_member| try self.member_at.put(gpa, .{
            .module = held_member.module,
            .owner = held_member.owner,
            .trait = held_member.trait,
            .name = self.bindings.items[held_member.binding.index()].name,
        }, held_member.binding);
        for (self.bindings.items, 0..) |binding, i| {
            const id = BindingId.at(@intCast(i));
            if (binding.kind == .module) {
                self.current = self.moduleOf(binding.decl);
                try self.noteModule(id);
            }
            if (binding.kind == .type_parameter) try self.type_parameter_bindings.put(gpa, binding.at, id);
        }
        try self.noteScopeNames();
    }

    /// Records that an expression reaches a binding, and the token that spells
    /// it.
    ///
    /// One call rather than two assignments, because the two are one decision
    /// and they do not always agree: a qualified variant settles on the enum
    /// while its own main token spells the variant, so a consumer taking the
    /// main token would point at a name the expression does not reach. The one
    /// place an expression's target is written down, so a form added later has
    /// to say where its name is written instead of inheriting an answer from
    /// the shape of its node.
    fn settle(self: *Resolver, id: ExprId, b: BindingId, at: TokenId) void {
        self.targets.items[id.index()] = b;
        self.spelled.items[id.index()] = at;
        if (self.record_written_expr and at != .none and at.index() < self.written.items.len) self.written.items[at.index()] = b;
        // Where the chain stood when this name was settled. Recorded with the
        // target rather than worked out from the node's position, because the
        // scope is what the lookup used.
        self.scope_of_expr.items[id.index()] = self.scope;
    }

    /// Records that a name written outside an expression reached a binding.
    ///
    /// Called from the places that resolve one, with what they resolved. It
    /// decides nothing: a caller that looked a name up and then called this
    /// with a different binding would be the second answer this table exists to
    /// prevent.
    fn reached(self: *Resolver, tok: TokenId, b: BindingId) void {
        if (tok == TokenId.none or tok.index() >= self.written.items.len) return;
        if (b == BindingId.none) return;
        self.noteTemplateBinding(tok, b);
        self.written.items[tok.index()] = b;
    }

    fn noteTemplateBinding(self: *Resolver, at: TokenId, b: BindingId) void {
        if (self.template_validation) |*validation| {
            const held = self.bindings.items[b.index()];
            if ((held.kind == .parameter and held.decl == validation.reflection.member) or
                (held.kind == .type_parameter and held.decl == validation.reflection.template))
            {
                if (at == .none or at.index() < validation.token_start) return;
                const offset = at.index() - validation.token_start;
                if (offset >= validation.references.len) return;
                validation.references[offset] = b;
                return;
            }
            if (b.index() >= validation.binding_floor) {
                if (validation.reflection.recipe_floor) |floor| {
                    if (b.index() >= floor and at != .none and at.index() >= validation.token_start) {
                        const offset = at.index() - validation.token_start;
                        if (offset < validation.references.len) validation.references[offset] = b;
                    }
                }
                return;
            }
            // Type parameters belong to the copied declaration, rather than
            // naming a module declaration a generated member must import. A
            // prelude name is recorded: the target's module may shadow it, so
            // the generated member has to reach the prelude's declaration by
            // identity rather than by the name.
            if (held.kind == .builtin_type or held.kind == .associated_type or held.kind == .type_parameter) return;
            if (at == .none or at.index() < validation.token_start) return;
            const offset = at.index() - validation.token_start;
            if (offset >= validation.references.len) return;
            validation.references[offset] = b;
        }
    }

    /// Puts `top[at]` at the end of its name's chain.
    fn noteTop(self: *Resolver, at: u32) !void {
        const name = self.bindings.items[self.top.items[at].index()].name;
        try self.top_named.note(self.gpa, @intFromEnum(name), at);
    }

    /// Records a binding that names a module, wherever one comes to.
    fn noteModule(self: *Resolver, b: BindingId) !void {
        const held = self.bindings.items[b.index()];
        const key = importKey(self.current, held.name, self.declaringFile(held.decl));
        if (!self.import_at.contains(key)) try self.import_at.put(self.gpa, key, b);
    }

    /// The key the rows of `import_at` are held under.
    fn importKey(m: ModuleId, name: StringId, in: FileId) u64 {
        var h: std.hash.Wyhash = .init(0);
        const parts = [_]u32{ @intFromEnum(m), @intFromEnum(name), @intFromEnum(in) };
        h.update(std.mem.asBytes(&parts));
        return h.final();
    }

    const Shadowed = struct { name: StringId, was: ?u32 };

    /// Declares a local, shadowing whatever its name reached.
    ///
    /// The name is passed rather than read off the binding, because a caller
    /// makes the binding visible before it appends it -- which is what stops a
    /// name's own initialiser from reaching it.
    fn pushLocal(self: *Resolver, b: BindingId, name: StringId) !void {
        const at: u32 = @intCast(self.visible.items.len);

        try self.visible.append(self.gpa, b);
        errdefer _ = self.visible.pop();
        try self.shadowed.append(self.gpa, .{ .name = name, .was = self.local_of.get(name) });
        try self.local_of.put(self.gpa, name, at);

        // The scope currently open is the one this name belongs to, which is
        // the whole of what makes the record the chain's own answer.
        try self.declaredHere(b);
    }

    /// Records that the open scope declares a binding.
    fn declaredHere(self: *Resolver, b: BindingId) !void {
        // Every binding is declared somewhere: a module's own in its module
        // scope, and every other inside a function, whose parameters are a
        // scope opened before any of them.
        std.debug.assert(self.scope != .none);

        try self.scope_bindings.append(self.gpa, b);
        errdefer _ = self.scope_bindings.pop();
        try self.binding_scopes.append(self.gpa, self.scope);
    }

    /// Opens a scope below the one the walk is in, and enters it.
    fn openScope(self: *Resolver) !ScopeId {
        try self.scopes.append(self.gpa, .{ .parent = self.scope, .from = 0, .to = 0 });
        self.scope = .at(@intCast(self.scopes.items.len - 1));
        return self.scope;
    }

    /// Ends a scope, leaving the walk in the scope above.
    ///
    /// Where `popLocalsTo` puts back what the scope shadowed. The two are the
    /// same moment: what the chain drops here is exactly this scope's run.
    fn closeScope(self: *Resolver, sc: ScopeId) void {
        self.scope = self.scopes.items[sc.index()].parent;
    }

    /// A scope per module, holding the run `enter` puts at the bottom of the
    /// chain.
    ///
    /// Made once every module's run is settled, and entered rather than rebuilt
    /// -- a module is entered again for each phase and the run is the same one
    /// each time. Costs the sum of the runs, which is every top-level binding
    /// the program has.
    fn declareModuleScopes(self: *Resolver) !void {
        for (self.module_scopes.items.len..self.program.modules.len) |i| {
            const sc = try self.openScope();
            for (self.scopeOf(.from(i))) |b| try self.declaredHere(b);
            self.closeScope(sc);
            try self.module_scopes.append(self.gpa, sc);
        }
    }

    /// Groups what each scope declared into a run of its own.
    ///
    /// The walk records a binding against the scope open at the time, and a
    /// scope opened inside another puts its bindings between that one's -- so
    /// the entries are ordered by scope here, which makes each run contiguous
    /// and leaves it in declaration order. One pass over the bindings and one
    /// over the scopes; it decides nothing, and a binding sits under the scope
    /// the walk already put it under.
    fn groupScopeRuns(self: *Resolver) !void {
        const n = self.scopes.items.len;
        const starts = try self.gpa.alloc(u32, n + 1);
        defer self.gpa.free(starts);
        @memset(starts, 0);

        // Counted one to the right, so the running total below turns counts
        // into starts in place.
        for (self.binding_scopes.items) |sc| starts[sc.index() + 1] += 1;
        for (1..n + 1) |i| starts[i] += starts[i - 1];

        const at = try self.gpa.alloc(u32, n);
        defer self.gpa.free(at);
        @memcpy(at, starts[0..n]);

        const grouped = try self.gpa.alloc(BindingId, self.scope_bindings.items.len);
        errdefer self.gpa.free(grouped);
        for (self.scope_bindings.items, self.binding_scopes.items) |b, sc| {
            grouped[at[sc.index()]] = b;
            at[sc.index()] += 1;
        }

        for (self.scopes.items, 0..) |*s, i| {
            s.from = starts[i];
            s.to = at[i];
        }

        self.scope_bindings.clearAndFree(self.gpa);
        self.scope_bindings = .fromOwnedSlice(grouped);
    }

    /// Ends every scope down to `mark`, putting back what each name meant.
    ///
    /// The entry restored was already in the map, so putting it back allocates
    /// nothing -- which is what lets a scope end where it ends rather than
    /// where it could fail.
    fn popLocalsTo(self: *Resolver, mark: usize) void {
        while (self.visible.items.len > mark) {
            _ = self.visible.pop();
            const was = self.shadowed.pop().?;
            if (was.was) |at| {
                self.local_of.putAssumeCapacity(was.name, at);
            } else {
                self.local_of.forget(was.name);
            }
        }
    }

    fn enter(self: *Resolver, m: ModuleId) !void {
        const s = self.module_runs.items[m.index()];
        self.scope = self.module_scopes.items[m.index()];
        self.visible.clearRetainingCapacity();
        try self.visible.appendSlice(self.gpa, self.top.items[s.from..s.to]);

        // The run a reference falls back to once no local carries the name.
        // Searching it backwards for every reference cost the module's own
        // size per name written, and both grow together.
        //
        // Filled forwards so the last binding a name reaches wins, which is
        // where a backwards walk of the same run would have stopped. It is
        // rebuilt here and nowhere else: a scope pushes and pops above this
        // run and never into it.
        self.module_run = self.visible.items.len;
        self.local_of.restart();
        self.shadowed.clearRetainingCapacity();
        self.in_module.restart();
        self.type_in_module.restart();
        for (self.visible.items) |b| {
            const held = self.bindings.items[b.index()];
            if (held.kind != .module) try self.in_module.put(self.gpa, held.name, b);

            // The first, not the last: a written type name walked this run
            // forwards and stopped at the first type it found. A primitive
            // answers here like a declared type does, because it is a name in
            // this scope and one walk settled both.
            switch (held.kind) {
                .declared_type, .builtin_type, .type_alias => {
                    const gop = try self.type_in_module.getOrPut(self.gpa, held.name);
                    if (!gop.found_existing) gop.value.* = b;
                },
                else => {},
            }
        }

        self.current = m;
    }

    fn moduleOf(self: *const Resolver, d: DeclId) ModuleId {
        if (self.expanded) |expanded| return expanded.moduleOf(d);
        return self.program.moduleOf(d);
    }

    /// Every type name each module can write, read off each module's run.
    ///
    /// A module's own declarations, what it re-exported, and what the prelude
    /// gave it are all bindings in its scope by now, so this is one filter
    /// rather than three lookups that could disagree.
    fn typeNames(self: *Resolver, gpa: std.mem.Allocator) ![]const TypeName {
        var out: std.ArrayList(TypeName) = .empty;
        errdefer out.deinit(gpa);

        for (0..self.program.modules.len) |i| {
            const m: ModuleId = .from(i);
            for (self.scopeOf(m)) |b| {
                const held = self.bindings.items[b.index()];
                // A type, a trait and a primitive are all things a type name
                // reaches, and all three are reached through what the module
                // can see -- its own, what it imported, what was re-exported to
                // it, the prelude, and the names the compiler seeds. One walk
                // records them, so none can be resolved by a rule the others do
                // not have.
                switch (held.kind) {
                    .declared_type, .trait, .builtin_type, .type_alias => {},
                    else => continue,
                }
                try out.append(gpa, .{
                    .module = m,
                    .name = held.name,
                    .decl = held.decl,
                    .binding = b,
                    .kind = held.kind,
                });
            }
        }
        return out.toOwnedSlice(gpa);
    }

    /// The top-level bindings of one module, whatever the walk is inside.
    fn scopeOf(self: *const Resolver, m: ModuleId) []const BindingId {
        const s = self.module_runs.items[m.index()];
        return self.top.items[s.from..s.to];
    }

    /// One binding per primitive, made once and shared by every module's scope.
    ///
    /// The spelling comes from the type itself, so the nine names and the nine
    /// handles cannot come apart -- there is no second list to keep in step.
    ///
    /// Each name is the handle the program's own tokens carry for that word.
    /// Two tokens spelling one word carry one handle, so any of them will do;
    /// a primitive no token spells keeps `.none`, which no lookup can ask for
    /// because every lookup starts from a token that spelled something.
    fn declareBuiltins(self: *Resolver) std.mem.Allocator.Error!void {
        var names = [_]StringId{.none} ** TypeId.primitives.len;
        for (0..self.ast.tokenCount()) |i| {
            const tok = TokenId.at(@intCast(i));
            if (self.ast.tokenTag(tok) != .identifier) continue;
            const text = self.ast.tokenText(tok);
            for (TypeId.primitives, &names) |t, *held| {
                if (held.* == .none and std.mem.eql(u8, text, t.nameOf())) {
                    held.* = self.ast.tokenName(tok);
                }
            }
        }

        for (TypeId.primitives, names) |t, name| {
            try self.builtins.append(self.gpa, BindingId.at(@intCast(self.bindings.items.len)));
            try self.bindings.append(self.gpa, .{
                .name = name,
                .kind = .builtin_type,
                .stmt = StmtId.none,
                .decl = DeclId.none,
                .param_index = 0,
                .at = TokenId.none,
                .used = false,
                .mutable = false,
                // Nothing declared it, so no program is at fault for not using
                // it and no source location could carry the report.
                .exempt = true,
                // Nothing reaches a primitive *through* a module: it is in
                // every scope already, so there is nothing for an import to
                // add and nothing for a re-export to pass on.
                .ambient = true,
                .builtin = t,
            });
        }
    }

    /// Every top-level declaration of one module, and whatever it sees for
    /// free.
    fn declareModule(
        self: *Resolver,
        m: ModuleId,
        ambient: []const BindingId,
    ) std.mem.Allocator.Error!void {
        const from: u32 = @intCast(self.top.items.len);
        self.current = m;
        // The chain covers one module's run, which is what `from` bounds and
        // what `declareTop` compares against.
        //
        // **Bound:** forgetting it is `O(1)`. A head carries the run it was
        // written in and a restart is an increment, so a module pays for the
        // names it declares and not for the widest module the program holds.
        // Emptying a hash table costs what it has room for, so a source tree
        // of many modules would pay that width at every one of them: 2.1 GB of
        // clearing at 32000 modules, four times that for twice the modules,
        // and priced in memory bandwidth rather than in work -- so how dear it
        // is says more about the machine than about the program. The tables
        // `enter` empties are stamped for the same reason and would come to as
        // much again.
        //
        // What the table holds instead is a slot per distinct name the whole
        // walk wrote, taken again by the next module writing that name, which
        // 32000 modules pay 2% more resident for. Keying the chain per module
        // so that nothing needs forgetting costs more than it saves, because
        // every note then carries the module it was written in.
        self.top_named.restart();

        // The primitives first, so a declaration of one of those names is the
        // second of its name and is reported where every duplicate is.
        try self.top.appendSlice(self.gpa, self.builtins.items);
        for (from..self.top.items.len) |at| try self.noteTop(@intCast(at));

        const decls = self.program.get(m).decls;
        for (decls.start..decls.end) |j| {
            const d = DeclId.at(@intCast(j));
            if (self.ast.tokenTag(self.ast.declName(d)) != .identifier) continue;
            // An `impl` declares no name of its own. It names the type it
            // belongs to so that its extent is recorded, and the members
            // inside it are what enter that type's namespace.
            if (self.ast.declTag(d) == .impl_ or
                self.ast.declTag(d) == .template_impl or
                self.ast.declTag(d) == .derive_impl)
            {
                continue;
            }
            // A declaration inside a type is reached through the type's name,
            // so it is not a name in the module. Its binding is made all the
            // same: the unused rule applies to it like any other.
            if (self.ast.declOwner(d) != TokenId.none) {
                try self.declareMember(d);
                continue;
            }
            try self.declareTop(d);
        }

        // The prelude last, and only where the module declares no name of its
        // own: a module's declaration or `use` of a prelude name shadows the
        // prelude's. The syntax that needs a prelude declaration finds it by
        // identity rather than by name, so shadowing cannot change what `?`,
        // a literal or an operator means.
        //
        // **Bound:** one chain lookup per prelude name, so a module pays for
        // its own declarations and the prelude's size, not the program's.
        for (ambient) |b| {
            const name = self.bindings.items[b.index()].name;
            if (self.top_named.contains(@intFromEnum(name))) continue;
            const at: u32 = @intCast(self.top.items.len);
            try self.top.append(self.gpa, b);
            try self.noteTop(at);
        }
        self.module_runs.items[m.index()] = .{ .from = from, .to = @intCast(self.top.items.len) };
    }

    /// The re-exports of one module, which read another module's scope and are
    /// read by every body -- so they sit between the two phases.
    fn reexportsOf(self: *Resolver, m: ModuleId) std.mem.Allocator.Error!void {
        self.current = m;
        const decls = self.program.get(m).decls;
        for (decls.start..decls.end) |j| {
            const d = DeclId.at(@intCast(j));
            if (self.ast.declTag(d) != .use_) continue;
            try self.reexport(d);
        }
    }

    /// Binds what a `pub use` names, as the declaration itself.
    ///
    /// An alias rather than a fresh identity: the binding holds the source
    /// declaration, so a value built through either spelling is the same
    /// nominal type and no later pass can tell which spelling reached it. The
    /// indirection is one step for the same reason -- a re-exported name is
    /// already bound to a real declaration, so following it once is following
    /// it all the way.
    fn reexport(self: *Resolver, d: DeclId) std.mem.Allocator.Error!void {
        return self.reexportFollowing(d, 0);
    }

    /// The module and the name a re-export's path spells, or null where it
    /// spells some other number of elements.
    fn pathOf(self: *const Resolver, d: DeclId) ?[2]TokenId {
        var elements: [2]TokenId = .{ TokenId.none, TokenId.none };
        var count: usize = 0;
        var walk = self.ast.pathElements(d);
        while (walk.next()) |id| {
            if (count < elements.len) elements[count] = id;
            count += 1;
        }
        return if (count == 2) elements else null;
    }

    /// Resolves a re-export, resolving what it names first where that is
    /// itself one.
    ///
    /// The indirection is one step only because this makes it so. Resolving
    /// modules in the order they are numbered bound an outer `use` to an inner
    /// one that had not been resolved yet -- a `use_` declaration, which has
    /// no parameters and no type, so every call through the chain was an
    /// arity error. Following the chain here needs no ordering to be true.
    ///
    /// The depth bound is what a cycle of re-exports runs into; each is
    /// reported where it is written by the ordinary path below.
    fn reexportFollowing(
        self: *Resolver,
        d: DeclId,
        depth: u32,
    ) std.mem.Allocator.Error!void {
        if (depth > 64) return;
        var here: ?*Binding = null;
        for (self.scopeOf(self.current)) |b| {
            if (self.bindings.items[b.index()].decl == d) here = &self.bindings.items[b.index()];
        }
        // A re-export exists for another module to reach rather than for use
        // where it is written, so nothing here is a use of it.
        //
        // A private `use` is not that. It binds a name for this module to
        // reach, which makes it an alias rather than an export, and one
        // nothing reaches is the mistake [M-Unused] is for -- the same
        // mistake, and the same rule, as an import naming a module nothing
        // names through.
        if (here) |h| {
            h.reexported = true;
            if (reachForVisibility(self.ast.declVisibility(d)) == .public) h.exempt = true;
        }

        const elements = self.pathOf(d) orelse {
            return self.sink.addErrorFmt(
                .m_import,
                self.ast.fileOf(self.ast.declName(d)),
                self.ast.tokenSpan(self.ast.declName(d)),
                "a re-export names a module and a declaration in it",
                "`use` takes a path of two elements",
                .{},
            );
        };

        // Resolved in the file that wrote it, like every other use of an
        // imported name. Scanning the whole module found a binding another
        // file wrote -- a different module under the same name -- and
        // re-exported from that one instead, which asked the visibility check
        // about a module this file never imported. It also marked every
        // binding of the name used, so an import nothing named in its own file
        // was silenced by a `use` in another.
        const module_name = self.ast.tokenName(elements[0]);
        var holding: ModuleId = .none;
        const imported = self.moduleNamed(module_name, self.ast.fileOf(elements[0]));
        if (imported) |b| {
            const held = &self.bindings.items[b.index()];
            held.used = true;
            self.reached(elements[0], b);
            holding = self.importedBy(held.decl);
        }

        if (holding == .none) {
            if (here) |h| h.unresolved = true;
            // An import that loaded nothing was reported where it is written,
            // and naming it here again would ask for the import that is there.
            if (imported != null) return;
            return self.sink.addErrorFmt(
                .m_import,
                self.ast.fileOf(elements[0]),
                self.ast.tokenSpan(elements[0]),
                try std.fmt.allocPrint(self.sink.arena, "add `import {s}` before this `use`", .{self.ast.tokenText(elements[0])}),
                "no module named `{s}` is imported here",
                .{self.ast.tokenText(elements[0])},
            );
        }

        const wanted = self.ast.tokenName(elements[1]);
        for (self.scopeOf(holding)) |b| {
            const held = &self.bindings.items[b.index()];
            if (held.name != wanted or held.kind == .module) continue;
            if (held.ambient) continue;

            if (!reachableFrom(self.program, held.reach, holding, self.current)) {
                held.used = true;
                try self.reportUnreachable(elements[1], holding, held.reach);
                return;
            }

            // What this names may itself be a re-export that nothing has
            // resolved yet, and binding it now would bind the alias rather
            // than what it aliases.
            if (self.ast.declTag(held.decl) == .use_) {
                const was = self.current;
                self.current = holding;
                try self.reexportFollowing(held.decl, depth + 1);
                self.current = was;
            }

            const settled = &self.bindings.items[b.index()];
            settled.used = true;
            self.reached(elements[1], b);
            if (here) |h| {
                const alias_reach = reachForVisibility(self.ast.declVisibility(d));
                if (@intFromEnum(alias_reach) > @intFromEnum(settled.reach)) {
                    try self.sink.addError(
                        .m_vis,
                        self.ast.fileOf(elements[1]),
                        self.ast.tokenSpan(elements[1]),
                        "write `internal use`, or make the original declaration `pub`",
                        "an internal declaration cannot be re-exported `pub`",
                    );
                }
                h.decl = settled.decl;
                h.kind = settled.kind;
                // A re-export can name a module, which makes this binding one
                // after the run it sits in was built.
                if (h.kind == .module) try self.noteModule(b);
                // The alias's own spelling decides how far this module passes
                // the canonical declaration on.
                h.reach = alias_reach;
            }
            return;
        }

        if (here) |h| h.unresolved = true;
        try self.sink.addErrorFmt(
            .m_import,
            self.ast.fileOf(elements[1]),
            self.ast.tokenSpan(elements[1]),
            "no declaration of that name is in that module",
            "`{s}` is not declared in `{s}`",
            .{ self.ast.tokenText(elements[1]), self.program.get(holding).name },
        );
    }

    /// Enters a declaration into the module scope. Phase one: nothing inside
    /// it is looked at yet, so a name's position among the declarations stops
    /// mattering for types exactly as it does for functions.
    /// Records a test under the name everything outside the compiler uses.
    ///
    /// The library's tests are not the program's. A program is compiled with
    /// the library beside it, so both are walked here, and running the
    /// library's tests as part of a program's would report failures nobody
    /// asked for and nobody in that program can fix. The library is tested as
    /// a program of its own, which is the only place its tests are its.
    fn recordTest(self: *Resolver, d: DeclId, spelled: []const u8) !void {
        const m = self.program.get(self.current);

        // Somebody else's library, and not when it is the root. A program is
        // compiled with the library beside it, so both are walked here, and
        // running the library's tests as part of a program's would report
        // failures nobody in that program asked for or can fix. Tested on its
        // own terms it is not a dependency at all -- it is what was named --
        // and its tests are the ones to run.
        if (m.library and !self.program.root().library) return;

        const qualified = try qualifiedTestName(
            self.gpa,
            self.program.root().dir,
            m.dir,
            spelled,
        );
        errdefer self.gpa.free(qualified);
        try self.tests.append(self.gpa, .{
            .decl = d,
            .expects_trap = self.ast.declExpectsTrap(d),
            .qualified_name = qualified,
        });
    }

    fn declareTop(self: *Resolver, d: DeclId) !void {
        const name_token = self.ast.declName(d);
        const name = self.ast.tokenName(name_token);

        // A second declaration of one name is reported at the second, and the
        // first keeps the name: later references mean something rather than
        // compounding one mistake into many. Only this module's own
        // declarations are considered: two modules may declare one name, which
        // is most of what a module is for.
        var held_here = self.top_named.walk(@intFromEnum(name));
        while (held_here.next()) |at| {
            const held = self.bindings.items[self.top.items[at].index()];
            // An import binds in the file that wrote it, so two files of one
            // module may each import the same dependency -- neither can see
            // the other's. Both must be imports: everything else a module
            // declares is shared by every file, so a module binding beside a
            // function or a type of the same name is one name meaning two
            // things in whichever file sees both.
            const both_imports = held.kind == .module and
                self.ast.declTag(d) == .import_;
            const exempt = both_imports and
                self.declaringFile(held.decl) != self.ast.fileOf(name_token);

            if (!exempt) {
                try self.sink.addErrorFmt(
                    .n_duplicate,
                    self.ast.fileOf(name_token),
                    self.ast.tokenSpan(name_token),
                    "a name is declared once",
                    "`{s}` is already declared",
                    .{self.ast.tokenText(name_token)},
                );
                return;
            }
        }

        const text = self.ast.tokenText(name_token);
        // Whether this is a declaration nothing here writes a call to, which
        // both exempts it from the unused rule and decides whether it is one of
        // the tests recorded below. Asked once: two calls could disagree only
        // by one of them being given a different module, and that is exactly
        // the mistake the argument exists to make visible.
        const reached_without_a_call = reachedWithoutACall(self.ast, d, self.current == self.program.primary);

        const at: u32 = @intCast(self.top.items.len);
        try self.top.append(self.gpa, BindingId.at(@intCast(self.bindings.items.len)));
        errdefer _ = self.top.pop();
        try self.bindings.append(self.gpa, .{
            .name = name,
            // Named rather than defaulted: a declaration kind added later
            // would otherwise be bound as a function, which is a wrong answer
            // rather than a missing one.
            .kind = switch (self.ast.declTag(d)) {
                .enum_, .struct_, .newtype => .declared_type,
                .alias => .type_alias,
                .trait_ => .trait,
                .import_ => .module,
                .constant, .traversal_ => .constant,
                .associated_type => .associated_type,
                // A projection is a member and is read in no other position,
                // so nothing reaches this with one. Classified with the
                // signature it is shaped as regardless, because what a
                // top-level scope holds is the parser's to say and this may
                // not be the reader that disagrees with it.
                .function, .projection, .use_, .impl_, .template_impl, .derive_impl, .err => .function,
            },
            .stmt = StmtId.none,
            .decl = d,
            .param_index = 0,
            .at = name_token,
            .used = false,
            .mutable = false,
            // The runtime calls the root module's `main`, so nothing in the
            // program has to. A `main` anywhere else is an ordinary private
            // function and is held to the same rule as any other.
            //
            // A declaration reachable from outside is used by being reachable:
            // without the exemption, exporting something would be a mistake.
            //
            // The prelude's imports are the manifest of what the library
            // ships. Nothing above the library can import a module of it, so
            // these are the only imports that name a module for being part of
            // the program rather than for a name it holds -- a module writing
            // implementations and exporting nothing has no name to reach for,
            // and dropping the import would drop the implementations.
            //
            // The prelude and not the library: an import a library module
            // writes is reached for a name like any other, and one nothing
            // names there is the mistake this rule is for.
            //
            // A leading `_` says a value is deliberately unused, and an import
            // binds no value: it names a module so something can be reached
            // through it, and an import nothing reaches through is removed
            // rather than renamed. There is no `_` form for one, which is what
            // the diagnostic says to a reader who tries.
            .exempt = reached_without_a_call or
                generated_calls.holds(self.program.get(self.current).name, text) or
                (self.ast.declTag(d) != .import_ and std.mem.startsWith(u8, text, "_")) or
                (self.ast.declTag(d) == .import_ and self.current == self.program.prelude) or
                reachForVisibility(self.ast.declVisibility(d)) == .public,
            .reach = reachForVisibility(self.ast.declVisibility(d)),
        });

        // Chained once the binding it names exists, because the chain is
        // keyed by the name that binding carries.
        try self.noteTop(at);
        if (reached_without_a_call and self.ast.declIsTest(d)) try self.recordTest(d, text);
        if (self.ast.declTag(d) == .import_) {
            try self.noteModule(BindingId.at(@intCast(self.bindings.items.len - 1)));
        }
    }

    /// Enters a declaration written inside a type or a trait into its
    /// namespace.
    ///
    /// Not into any scope: a namespace is not a scope that nests, so the body
    /// of one of these sees exactly what a top-level declaration's body sees.
    /// There is no receiver and nothing to bind one to.
    ///
    /// A trait implementation's members enter no namespace that a name reaches.
    /// The trait's own signatures are what a call resolves to, and which body
    /// runs is decided from the argument's type; entering them under the type
    /// would put them in the type's namespace, where adding an implementation
    /// would change what `Account.` means.
    fn declareMember(self: *Resolver, d: DeclId) !void {
        const name_token = self.ast.declName(d);
        const owner = self.ast.tokenName(self.ast.declOwner(d));
        const trait = self.ast.declTrait(d);

        const in = self.moduleOf(d);
        var intrinsic = false;
        if (trait == .none and IntegerEndpoint.fromName(self.ast.tokenText(name_token)) != null) {
            var candidates = self.top_named.walk(@intFromEnum(owner));
            while (candidates.next()) |at| {
                if (self.builtinOf(self.top.items[at])) |primitive| {
                    intrinsic = primitive.integerInfo() != null;
                    break;
                }
            }
        }
        if (intrinsic or self.memberOf(in, owner, trait, self.ast.tokenName(name_token)) != null) {
            return self.sink.addErrorFmt(
                .n_duplicate,
                self.ast.fileOf(name_token),
                self.ast.tokenSpan(name_token),
                "a name is declared once",
                "`{s}` is already declared in this type",
                .{self.ast.tokenText(name_token)},
            );
        }

        const text = self.ast.tokenText(name_token);
        const binding: BindingId = .at(@intCast(self.bindings.items.len));
        try self.members.append(self.gpa, .{
            .module = in,
            .owner = owner,
            .trait = trait,
            .binding = binding,
        });
        try self.member_at.put(self.gpa, .{
            .module = in,
            .owner = owner,
            .trait = trait,
            .name = self.ast.tokenName(name_token),
        }, binding);
        try self.bindings.append(self.gpa, .{
            .name = self.ast.tokenName(name_token),
            .kind = switch (self.ast.declTag(d)) {
                .enum_, .struct_, .newtype => .declared_type,
                .alias => .type_alias,
                .trait_ => .trait,
                // A traversal binds a name to an expression, which is what a
                // constant is. What tells them apart is that nothing names a
                // traversal, and that is read off the declaration.
                .constant, .traversal_ => .constant,
                .associated_type => .associated_type,
                // A projection is a member declared and supplied exactly as a
                // signature is, so it is entered under the kind a signature is:
                // what tells the two apart is what its body means, and that is
                // read off the declaration rather than off the binding.
                .function, .projection, .import_, .use_, .impl_, .template_impl, .derive_impl, .err => .function,
            },
            .stmt = StmtId.none,
            .decl = d,
            .param_index = 0,
            .at = name_token,
            .used = false,
            .mutable = false,
            // A trait's member is named for whatever answers it rather than
            // for anything that calls it, on both sides of the relation: a
            // signature for the bodies that supply it, a declared type for the
            // implementations that settle it, and a member of an
            // implementation for the trait it is reachable through.
            // A traversal is among them for a reason of its own: a walk finds
            // it through the type it is declared on, so no expression ever
            // spells its name and the unused rule would make it unwritable.
            .exempt = std.mem.startsWith(u8, text, "_") or
                reachForVisibility(self.ast.declVisibility(d)) == .public or
                self.ast.declTag(d) == .traversal_ or
                self.ast.declIsTraitMember(d),
            .reach = reachForVisibility(self.ast.declVisibility(d)),
        });
    }

    /// `let S { f: b, .. } = e`, `let N(n) = e` or `let (a, b) = e`: the value
    /// is resolved, then each binder becomes a binding that owns what it was
    /// given.
    ///
    /// The type's name and the field names are not names in scope -- one is a
    /// type and the others belong to it -- so the checker resolves those, and
    /// this resolves only what the pattern binds.
    fn destructure(self: *Resolver, s: StmtId) std.mem.Allocator.Error!void {
        const d = self.ast.stmtData(s);
        if (d.init != ExprId.none) try self.expr(d.init);
        if (d.pattern == ExprId.none) return;
        switch (self.ast.exprTag(d.pattern)) {
            .struct_pattern, .tuple_pattern, .call => {},
            else => return,
        }

        // The type's name is used by naming it here, exactly as an annotation
        // uses one.
        if (self.ast.exprTag(d.pattern) == .call)
            try self.usePatternHead(self.ast.exprMain(self.ast.call(d.pattern).callee));

        return self.bindPattern(d.pattern);
    }

    /// The binding of a member of `owner` with that name, in the namespace one
    /// header opened.
    ///
    /// `trait` is the token an implementation's header wrote the trait at, and
    /// `.none` is the type's own namespace -- the braces and every inherent
    /// `impl` write it, so a type's members are one namespace however many
    /// blocks they sit in. Every other value is one implementation's own.
    ///
    /// The one place the members table is asked which declarations a namespace
    /// holds, so declaring a second member and selecting one cannot come to
    /// disagree about what the first namespace holds.
    fn memberOf(
        self: *const Resolver,
        module: ModuleId,
        owner: StringId,
        trait: TokenId,
        name: StringId,
    ) ?BindingId {
        return self.member_at.get(.{
            .module = module,
            .owner = owner,
            .trait = trait,
            .name = name,
        });
    }

    /// The binding of a member a name reaches under `owner`.
    ///
    /// A trait implementation's members are skipped: they belong to the trait,
    /// so no name reaches them. What a call names is the trait's signature, and
    /// the body that runs is found from the argument's type rather than from a
    /// namespace.
    fn memberNamed(
        self: *const Resolver,
        module: ModuleId,
        owner: StringId,
        name: StringId,
    ) ?BindingId {
        return self.memberOf(module, owner, TokenId.none, name);
    }

    /// The binding of a member a name reaches under a primitive.
    ///
    /// The members table is keyed by the module that wrote the header, and no
    /// module declares a primitive -- so the namespace its name opens is
    /// whichever module wrote an inherent `impl` on it, which the ownership
    /// rule leaves to the standard library alone. Found through the same table
    /// a declared type's members are found in, so a namespace has one meaning
    /// however the type it hangs off came to exist.
    fn builtinMemberNamed(self: *const Resolver, primitive: TypeId, name: StringId) ?BindingId {
        for (self.builtin_namespaces.items) |ns| {
            if (ns.of != primitive) continue;
            if (self.memberNamed(ns.module, ns.owner, name)) |b| return b;
        }
        return null;
    }

    /// The namespaces primitives open, one row per primitive, module and
    /// spelling.
    ///
    /// Every inherent `impl` on a primitive is a row of `impls`, and a module
    /// may write several for one primitive. Their members share one namespace
    /// keyed by that module and spelling, so a row per block would hand every
    /// reader the same members once per block.
    ///
    /// **Bound:** one pass over `impls` with a set sized by its result; the
    /// rows are the library's inherent blocks on primitives, which the
    /// ownership rule keeps any program from lengthening.
    fn collectBuiltinNamespaces(self: *Resolver) !void {
        var seen: std.AutoHashMapUnmanaged(BuiltinNamespace, void) = .empty;
        defer seen.deinit(self.gpa);
        for (self.impls.items) |i| {
            if (i.trait != DeclId.none) continue;
            const of = switch (i.head) {
                // A namespace is opened by an inherent `impl`, whose head is a
                // written name -- so a head no header can write opens none.
                .declared, .array, .borrow_, .callable_, .parameter, .default_ => continue,
                .builtin => |t| t,
            };
            const row: BuiltinNamespace = .{
                .of = of,
                .module = self.moduleOf(i.decl),
                .owner = self.ast.tokenName(self.ast.declName(i.decl)),
            };
            if ((try seen.getOrPut(self.gpa, row)).found_existing) continue;
            try self.builtin_namespaces.append(self.gpa, row);
        }
    }

    /// Reports a primitive's inherent member named in a second module.
    ///
    /// [N-Duplicate] holds across all of a type's `impl` blocks. Declaring a
    /// member refuses a name its own module already holds for the type, and
    /// that is every block of a declared type. A primitive is declared by no
    /// module, so several library modules may each write blocks for it, and
    /// only this pass sees them together. The first module's member keeps
    /// the name, so lookup answers with it, and the report stands at the
    /// later declaration.
    ///
    /// **Bound:** one pass over the members, with tables sized by the
    /// primitives' namespaces; nothing runs unless some primitive has blocks
    /// in two modules.
    fn refuseRepeatedPrimitiveMembers(self: *Resolver) !void {
        const Opened = struct { module: ModuleId, owner: StringId };
        const Named = struct { of: TypeId, name: StringId };
        var namespace_of: std.AutoHashMapUnmanaged(Opened, TypeId) = .empty;
        defer namespace_of.deinit(self.gpa);
        var module_of: std.AutoHashMapUnmanaged(TypeId, ModuleId) = .empty;
        defer module_of.deinit(self.gpa);
        var shared = false;
        for (self.builtin_namespaces.items) |ns| {
            try namespace_of.put(self.gpa, .{ .module = ns.module, .owner = ns.owner }, ns.of);
            const first = try module_of.getOrPut(self.gpa, ns.of);
            if (!first.found_existing) first.value_ptr.* = ns.module else if (first.value_ptr.* != ns.module) shared = true;
        }
        if (!shared) return;

        var first_module: std.AutoHashMapUnmanaged(Named, ModuleId) = .empty;
        defer first_module.deinit(self.gpa);
        for (self.members.items) |m| {
            if (m.trait != TokenId.none) continue;
            const of = namespace_of.get(.{ .module = m.module, .owner = m.owner }) orelse continue;
            const binding = self.bindings.items[m.binding.index()];
            const entry = try first_module.getOrPut(self.gpa, .{ .of = of, .name = binding.name });
            if (!entry.found_existing) {
                entry.value_ptr.* = m.module;
                continue;
            }
            // One module's second declaration was refused where it was
            // declared, and never became a member.
            if (entry.value_ptr.* == m.module) continue;
            const name_token = self.ast.declName(binding.decl);
            try self.sink.addErrorFmt(
                .n_duplicate,
                self.ast.fileOf(name_token),
                self.ast.tokenSpan(name_token),
                "a name is declared once",
                "`{s}` is already declared in this type",
                .{self.ast.tokenText(name_token)},
            );
        }
    }

    /// Reports why a binding held by another module does not reach here.
    /// A name refused here was still written, so each caller marks what it
    /// reached used: the one mistake is its visibility, not that nothing
    /// names it.
    fn reportUnreachable(self: *Resolver, at: TokenId, holding: ModuleId, reach: Reach) !void {
        try reportUnreachableName(self.sink, self.ast, at, self.program.get(holding).name, reach);
    }

    /// Reaching a member: naming one uses it, and one outside its own module
    /// must be `pub` where it was written.
    ///
    /// `governing` is the declaration whose visibility answers, which is the
    /// member itself except where a trait answers for its signature.
    fn reachMember(self: *Resolver, id: ExprId, b: BindingId, governing: DeclId) !void {
        const from = self.moduleOf(self.bindings.items[b.index()].decl);
        const reach = reachForVisibility(self.ast.declVisibility(governing));
        if (!memberIsReachable(self.ast, self.program, governing, from, self.current)) {
            self.bindings.items[b.index()].used = true;
            return self.reportUnreachable(self.ast.exprMain(id), from, reach);
        }
        self.bindings.items[b.index()].used = true;
        self.settle(id, b, self.ast.exprMain(id));
    }

    /// Imports accept no visibility or export modifiers. Declaration
    /// attributes and their target shapes are validated by the parser, which
    /// retains their complete written groups for tooling.
    fn checkModifiers(self: *Resolver) !void {
        for (self.program.modules) |*m| {
            for (m.decls.start..m.decls.end) |i| {
                const d = DeclId.at(@intCast(i));
                for (self.ast.declParams(d)) |param| try self.refuseRedundantRead(param);
                // A member carries only `pub`, and a signature carries
                // nothing: the parser accepts no other word inside either
                // pair of braces, so there is nothing here that it let past.
                if (self.ast.declOwner(d) != TokenId.none) continue;
                try self.checkModifiersOf(d);
            }
        }
    }

    fn refuseRedundantRead(self: *Resolver, param: node.Param) !void {
        if (param.convention != .read) return;
        const convention_token = self.ast.paramConventionToken(param);
        if (convention_token == .none) return;
        try self.sink.addError(
            .s_entry,
            self.ast.fileOf(convention_token),
            self.ast.tokenSpan(convention_token),
            "`read` is redundant on a parameter",
            "omit `read`; parameters are read by default",
        );
    }

    fn checkModifiersOf(self: *Resolver, d: DeclId) !void {
        const tag = self.ast.declTag(d);
        if (tag != .import_) return;

        // Attributes are diagnosed by the parser at their own group. Imports
        // reject only their ordinary visibility and export prefixes here.
        if (self.ast.declVisibility(d) == .private and !self.ast.declIsExport(d)) return;
        const at = self.explicitModifierToken(d);
        std.debug.assert(at != TokenId.none);
        return self.sink.addError(
            .s_entry,
            self.ast.fileOfDecl(d),
            self.ast.tokenSpan(at),
            "an import takes no modifier",
            "an import binds a module here, and `pub use` carries a name onward",
        );
    }

    /// The written visibility or export word before a declaration's main
    /// token. Attribute groups occupy the same prefix but are not modifiers.
    fn explicitModifierToken(self: *const Resolver, d: DeclId) TokenId {
        const tokens = self.ast.declTokens(d);
        for (tokens.start.index()..self.ast.declMain(d).index()) |i| {
            const at = TokenId.at(@intCast(i));
            switch (self.ast.tokenTag(at)) {
                .keyword_pub, .keyword_internal, .keyword_export => return at,
                else => {},
            }
        }
        return .none;
    }

    /// The root module declares exactly one `main`, and it is `main() -> u8`.
    ///
    /// Asked of the root alone: a module that is imported declares no entry
    /// point, and holding every module to the rule would make a library
    /// uncompilable on its own terms.
    fn checkEntryPoint(self: *Resolver) !void {
        // The entry point is the root module's, so the names its signature
        // writes are read from there. Whichever module the loops above ended
        // in is not it.
        self.current = self.program.primary;
        const root = self.program.root();
        var found: u32 = 0;
        var entry: DeclId = DeclId.at(0);
        for (root.decls.start..root.decls.end) |i| {
            const d = DeclId.at(@intCast(i));
            if (!namesTheEntryPoint(self.ast, d)) continue;
            found += 1;
            entry = d;
        }
        // Recorded whatever the count, so lowering reads the selection rather
        // than making it: a program with no entry point or with two is
        // rejected here, and nothing downstream has to agree about which of
        // two it would have picked.
        // A library has nothing to run, so an entry point written in one is a
        // declaration the output cannot hold. Reported at the `main` rather
        // than at the root, because that is the line to delete or the manifest
        // to correct, and `namesTheEntryPoint` is what decides -- so `pub fn
        // main` is this and not an export.
        if (found >= 1 and self.program.kind == .library) {
            try self.sink.addError(
                .m_entry,
                self.ast.fileOfDecl(entry),
                self.ast.declNameSpan(entry),
                "a library declares no entry point",
                "a library has nothing to run: drop it, or name this root a program",
            );
            return;
        }

        if (found == 1) {
            self.entry = entry;
            return self.checkEntrySignature(entry);
        }

        // A test binary's entry point is one the compiler writes, so a root
        // that declares none is a program with nothing to run rather than a
        // program that is wrong. Two are still refused: which of them the
        // dispatcher would not call is not a question anybody should have to
        // ask.
        //
        // This is the whole of what test mode changes about the rule. A `main`
        // that is present is still held to its signature, and is still absent
        // from what a test binary emits.
        //
        // A library declares none for a different reason -- there is nothing to
        // run at all -- and the two are separate axes rather than one: a
        // library has tests, and running them is a test binary built from a
        // root that is still a library.
        // A module a named file selected is checked for what it declares; it
        // needs a `main` only to be run, which the driver asks.
        if (found == 0 and (self.purpose == .tests or self.program.kind == .library or self.program.named_module)) return;

        const label = try std.fmt.allocPrint(self.sink.arena, "found {d}", .{found});

        // The program's own source, never the tree's first file: the library
        // is loaded before an entry directory and after a single entry file,
        // so the tree's first file is whichever of the two happened to be
        // read first -- and blaming the standard library for a `main` the
        // program does not declare points at source the programmer cannot fix.
        if (root.decls.len() != 0) {
            const first = DeclId.at(root.decls.start);
            try self.sink.addError(
                .s_entry,
                self.ast.fileOfDecl(first),
                self.ast.declNameSpan(first),
                "a program declares exactly one `main`",
                label,
            );
            return;
        }
        if (root.files.len != 0) {
            try self.sink.addError(
                .s_entry,
                root.files[0],
                Span.empty,
                "a program declares exactly one `main`",
                label,
            );
            return;
        }

        // Nothing was read, so there is no place to point at. A label would
        // have to name a file, and every file there is belongs to the library.
        try self.sink.add(.{
            .severity = .err,
            .code = .s_entry,
            .message = "a program declares exactly one `main`, and this one holds no source",
        });
    }

    /// The entry point is `main() -> u8` and not merely something called
    /// `main`.
    ///
    /// The rule names a signature, so every part of that spelling is checked
    /// and not just the name. Nothing downstream can recover from a wrong one:
    /// the runtime calls the entry point with no arguments and reads its result
    /// as a byte, and the emitter writes that convention out unconditionally.
    /// A `main` returning a structure was accepted, and the exit status the
    /// operating system then observed was the low byte of a stack address.
    ///
    /// Checked against what was written rather than against a resolved type,
    /// because `UInt8` is a word the grammar reserves and so has exactly one
    /// spelling -- there is no annotation, alias or import that reaches this
    /// type under another name, and nothing to resolve.
    ///
    /// Each clause reports on its own: a `main` that is generic *and* takes a
    /// parameter is wrong twice, and being told once per edit is what makes the
    /// second one findable.
    /// Refuses every name that reaches a test.
    ///
    /// The compiler writes the only call to a test, and that is a claim about
    /// what a program may contain rather than a description of what it happens
    /// to. A test something calls is a test something ships: it is reached from
    /// the entry point like any other function, lowered like any other, and the
    /// artefact then holds a body that exists to be run by the runner and not
    /// by the program.
    ///
    /// So no expression names one, and that includes another test. A test
    /// calling a test was admitted while nothing was injured by it, and this is
    /// the injury: the rule cannot be "no ordinary code names a test" without
    /// deciding, per call, which code is ordinary -- and a rule that reads the
    /// caller is a rule with two answers the day a test is lowered.
    ///
    /// One walk over the table an expression's target is written into, which is
    /// the one place any of them is recorded.
    fn refuseNamesThatReachATest(self: *Resolver) !void {
        for (self.targets.items, 0..) |b, i| {
            if (b == BindingId.none) continue;
            const d = self.declIfDeclaredHere(b);
            if (d == DeclId.none) continue;
            if (!self.ast.declIsTest(d)) continue;

            const at = self.spelled.items[i];
            if (at == TokenId.none) continue;

            try self.sink.addError(
                .s_test,
                self.ast.fileOfExpr(ExprId.at(@intCast(i))),
                self.ast.tokenSpan(at),
                "a test is not called by name",
                "the compiler writes the only call to a test, so a program naming one would ship it",
            );
        }
    }

    /// The declaration a binding names, while the resolver is still building
    /// the tables `Resolution.declIfDeclared` reads.
    fn declIfDeclaredHere(self: *const Resolver, b: BindingId) DeclId {
        return switch (self.bindings.items[b.index()].kind) {
            .function, .declared_type, .associated_type => self.bindings.items[b.index()].decl,
            else => DeclId.none,
        };
    }

    /// Every test's shape, over every declaration the compilation holds.
    ///
    /// Not the root's alone: a test sits in any module, so the rules about what
    /// one may declare have to reach any module. The library is walked with
    /// everything else, which costs one pass over declarations that hold no
    /// test and answers for the ones that will.
    fn checkTests(self: *Resolver) !void {
        for (0..self.ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (!self.ast.declIsTest(d)) continue;
            // A modifier the parser already refused on this form reports there.
            // Asking a type about its parameters would report a second time
            // for one mistake -- and an `extern` is a function by tag, so the
            // tag alone does not settle it.
            if (self.ast.declTag(d) != .function) continue;
            if (self.ast.declIsExtern(d)) continue;
            try self.checkTestSignature(d);
        }
    }

    /// What a test may declare.
    ///
    /// The entry point's questions asked of a different declaration, and for
    /// the entry point's reason: the compiler writes the only call, so there is
    /// nothing to pass and nothing to settle. Asked of every test rather than
    /// of one declaration, which is the only way the two differ.
    fn checkTestSignature(self: *Resolver, d: DeclId) !void {
        const file = self.ast.fileOfDecl(d);

        for (self.ast.declTypeParams(d)) |p| {
            try self.sink.addError(
                .s_test,
                file,
                self.ast.tokenSpan(p.name),
                "a test is not generic",
                "the compiler writes the only call to a test, so nothing settles this",
            );
        }

        for (self.ast.declParams(d)) |p| {
            try self.sink.addError(
                .s_test,
                file,
                self.ast.tokenSpan(p.name),
                "a test takes no parameters",
                "the compiler writes the only call to a test, and has nothing to pass",
            );
        }
    }

    fn checkEntrySignature(self: *Resolver, d: DeclId) !void {
        const file = self.ast.fileOfDecl(d);

        // `pub` first, because it is written first. Only `pub`: `opaque` and
        // `linear` say nothing on any function, and the rule that refuses them
        // there does not stop being the reason when the function is `main`.
        //
        // A module reaches only the modules beneath it, so nothing imports the
        // program and no `pub` written in its root widens anything. A `main`
        // an imported module declares is an ordinary function and may be
        // exported like any other.
        if (self.ast.declVisibility(d) == .pub_) {
            try self.sink.addError(
                .s_entry,
                file,
                self.ast.tokenSpan(self.explicitModifierToken(d)),
                "a program's `main` is not exported",
                "nothing imports the program, so this reaches nobody",
            );
        }

        // A type parameter has no argument to take, because nothing calls the
        // entry point. Lowering instantiates it at no arguments whatever it
        // declares, so a body written against `T` is emitted against nothing.
        for (self.ast.declTypeParams(d)) |p| {
            try self.sink.addError(
                .s_entry,
                file,
                self.ast.tokenSpan(p.name),
                "a program's `main` is not generic",
                "nothing calls the entry point, so nothing supplies this",
            );
        }

        // Nothing calls the written entry with arguments. What the process
        // was started with reaches the runtime through the wrapper the backend
        // writes, and a program reads it from there -- so a parameter here
        // names something no caller supplies.
        for (self.ast.declParams(d)) |p| {
            try self.sink.addError(
                .s_entry,
                file,
                self.ast.tokenSpan(p.name),
                "a program's `main` takes no parameters",
                "the runtime calls the entry point with none",
            );
        }

        // A `main` that writes no result returns `()`, which has no exit
        // status to give. A type with no name is still a type: an array
        // `main` returns is not a `main` with no return type, and reading it
        // as one let [S-Entry] be bypassed by writing `-> [UInt8; 3]`.
        const written = self.ast.declReturnRef(d);
        if (written.isOmitted()) return self.sink.addError(
            .s_entry,
            self.ast.fileOfDecl(d),
            self.ast.declNameSpan(d),
            "the entry point answers with `UInt8`, which is the exit status",
            "this returns nothing; write `-> UInt8`",
        );
        // A result the parser refused was reported there.
        if (!written.wasWritten()) return;
        const tok = written.name;
        if (tok == TokenId.none) return self.sink.addError(
            .s_entry,
            if (written.length != .none) self.ast.fileOfExpr(written.length) else self.ast.fileOf(written.at),
            if (written.length != .none) self.ast.exprSpan(written.length) else self.ast.tokenSpan(written.at),
            "the entry point answers with `UInt8`, which is the exit status",
            "this is not `UInt8`",
        );

        // The same question every other written type is read through: which
        // type does this name reach here. A `UInt8` a module shadowed is not
        // the exit status, and only the name lookup knows that.
        if (self.builtinOf(self.namedHere(tok))) |t| {
            if (t == .u8) return;
        }

        // The other spelling: `Result[UInt8, E]`, where a failure the program
        // did not deal with leaves through the entry point and the runtime
        // reports it. Only that the name reaches the prelude's `Result` is
        // settled here -- that its success is the exit status and its failure
        // renders is a question about types, and the checker answers it.
        //
        // This is the one part of the signature not decided by the spelling.
        // `UInt8` is a word the grammar reserves, so a name lookup is
        // unnecessary for it; `Result` is an ordinary declaration the prelude
        // publishes, and a module is free to shadow the name. So it is compared
        // against the declaration rather than against the text, which is the
        // same question every other written type is read through.
        // A qualified spelling crosses its module through the one lookup
        // every qualified name does. Nothing is reported here: the written
        // type is resolved again with the rest of the signature, and that is
        // where a wrong path is reported, once.
        const named: BindingId = switch (written.kind) {
            .selection => selected: {
                const base = self.ast.selectionBase(written);
                if (base.kind != .named or self.ast.tokenTag(base.name) != .identifier) break :selected .none;
                const module = self.moduleNamed(self.ast.tokenName(base.name), self.ast.fileOf(base.name)) orelse break :selected .none;
                break :selected switch (self.crossModule(module, written.name)) {
                    .reached => |found| found,
                    else => .none,
                };
            },
            else => self.namedHere(tok),
        };
        if (named == .none and written.kind == .selection) return;
        if (named != .none) {
            // A local shadowing the name reaches a binding with no declaration
            // behind it, which is not the prelude's `Result` either.
            const declared = self.bindings.items[named.index()].decl;
            if (declared != DeclId.none and declared == preludeDeclIn(self.ast, self.prelude_decls, "Result")) return;
        }

        // Named by the text written rather than by what it reached: a name
        // reaching nothing still has a spelling, and the spelling is what the
        // programmer has to change.
        const label = try std.fmt.allocPrint(
            self.sink.arena,
            "returns `{s}`",
            .{self.ast.tokenText(tok)},
        );
        try self.sink.addError(
            .s_entry,
            file,
            self.ast.tokenSpan(tok),
            "a program's `main` answers `UInt8`, or `Result[UInt8, E]` to let a failure leave",
            label,
        );
    }

    /// The type an `impl` belongs to.
    ///
    /// An `impl` declares no name of its own, so nothing resolved its header:
    /// `impl Missing { .. }` attached functions to nothing and said nothing
    /// about it. The members inside are reached through the type's name, so a
    /// header naming no type leaves every one of them unreachable -- and a
    /// `pub fn` among them is silent, because the unused rule exempts what
    /// another module could have called.
    ///
    /// Naming it is not using it. A type whose only mention is an `impl` is
    /// still a type nothing needs, and [N-Unused] is what says so.
    fn implTarget(self: *Resolver, d: DeclId) !void {
        const is_derive = self.ast.declTag(d) == .derive_impl;
        const trait_decl = if (is_derive) DeclId.none else try self.implTrait(d);

        const written_head = self.ast.declHead(d);
        const tok = written_head.at;
        // A head the parser refused names no type, and was reported where it
        // was written. Nothing is recorded for it, so its members are the
        // members of nothing rather than of unit or of a tuple nobody wrote.
        if (headRefusedByTheParser(written_head)) return self.refused_impls.put(self.gpa, d, {});
        if (self.ast.declIsDefault(d)) {
            // A head the default names is still a written type name, and
            // what it reaches is recorded as any other one's is.
            if (self.ast.tokenTag(tok) == .identifier and !self.ast.declHasParameterHead(d)) {
                self.reached(tok, self.namedHere(tok));
            }
            if (trait_decl == .none) {
                try self.refused_impls.put(self.gpa, d, {});
                try self.sink.addErrorFmt(.t_impl, self.ast.fileOfDecl(d), self.ast.writtenSpan(written_head), "name a trait before `for`", "a default implementation must implement a trait", .{});
                return;
            }
            if (self.moduleOf(trait_decl) != self.current) {
                try self.refused_impls.put(self.gpa, d, {});
                try self.sink.addErrorFmt(.m_impl, self.ast.fileOf(tok), self.ast.writtenSpan(written_head), "write the default where the trait is declared", "a default implementation belongs to the trait's declaring module", .{});
                return;
            }
            return self.impls.append(self.gpa, .{ .trait = trait_decl, .args = self.ast.declTraitArgs(d), .head = .default_, .decl = d });
        }
        if (written_head.kind == .borrow) {
            if (!self.mayImplement(.unowned, trait_decl)) {
                try self.refused_impls.put(self.gpa, d, {});
                try self.sink.addErrorFmt(.m_impl, self.ast.fileOf(tok), self.ast.writtenSpan(written_head), "write the implementation where the trait is declared", "an observation constructor has no declaring module", .{});
                return;
            }
            return self.impls.append(self.gpa, .{ .trait = trait_decl, .args = self.ast.declTraitArgs(d), .head = .borrow_, .decl = d });
        }
        if (written_head.kind == .callable) {
            if (!self.mayImplement(.unowned, trait_decl)) {
                try self.refused_impls.put(self.gpa, d, {});
                try self.sink.addErrorFmt(.m_impl, self.ast.fileOf(tok), self.ast.writtenSpan(written_head), "write the implementation where the trait is declared", "a callable type has no declaring module", .{});
                return;
            }
            const shape = self.ast.callableShape(written_head) orelse {
                try self.refused_impls.put(self.gpa, d, {});
                return self.sink.addErrorFmt(.t_impl, self.ast.fileOf(tok), self.ast.writtenSpan(written_head), "name a callable type with fewer parameters", "a callable head names at most {d} parameters", .{node.CallableShape.max_shape_parameters});
            };
            return self.impls.append(self.gpa, .{ .trait = trait_decl, .args = self.ast.declTraitArgs(d), .head = .{ .callable_ = shape }, .decl = d });
        }
        if (self.ast.declHasParameterHead(d)) {
            if (!self.mayImplement(.unowned, trait_decl)) {
                try self.refused_impls.put(self.gpa, d, {});
                return self.sink.addErrorFmt(.m_impl, self.ast.fileOf(tok), self.ast.writtenSpan(written_head), "write the implementation where the trait is declared", "a parameter head has no declaring module", .{});
            }
            return self.impls.append(self.gpa, .{ .trait = trait_decl, .args = self.ast.declTraitArgs(d), .head = .parameter, .decl = d });
        }
        // A tuple head starts at `(` as unit does, and is told apart by its
        // kind: it names the prelude's tuple declaration by identity, so no
        // name in scope is looked up for it.
        const tuple_head = written_head.kind == .tuple;
        const unit_head = !tuple_head and self.ast.tokenTag(tok) == .l_paren;
        if (!unit_head and !tuple_head and self.ast.tokenTag(tok) != .identifier) return;

        const named = if (unit_head or tuple_head) BindingId.none else self.namedHere(tok);
        self.reached(tok, named);

        // No module declares a primitive, so its type side belongs to the
        // standard library: the library is what the language ships, and the
        // language is what provides them. Which module that is, is a property
        // of how it was loaded rather than of what it is called -- a directory
        // named `std` beside a program is not the library. Everyone else has
        // only the trait side to name, which is the ownership rule asked of a
        // type nobody wrote rather than a rule of its own.
        const builtin: ?TypeId = if (unit_head) .unit else if (tuple_head) null else self.builtinOf(named);
        if (builtin) |primitive| {
            if (is_derive) return;
            // Unit has no declaring module and grants no standard-library type
            // side. A trait implementation therefore belongs only with the
            // trait, while named primitives retain library ownership.
            if (!self.mayImplement(if (unit_head) .unowned else .primitive, trait_decl)) {
                try self.refused_impls.put(self.gpa, d, {});
                return self.sink.addErrorFmt(
                    .m_impl,
                    self.ast.fileOf(tok),
                    self.ast.writtenSpan(written_head),
                    if (self.ast.declTrait(d) == TokenId.none)
                        "an inherent `impl` goes in the module that declares the type"
                    else if (trait_decl != DeclId.none and self.program.get(self.moduleOf(trait_decl)).library)
                        try self.refusalHelp(if (unit_head) .unowned else .primitive, if (unit_head) "()" else self.ast.tokenText(tok), trait_decl)
                    else
                        "write it where the trait is declared",
                    "no module declares `{s}`",
                    .{if (unit_head) "()" else self.ast.tokenText(tok)},
                );
            }
            return self.impls.append(self.gpa, .{
                .trait = trait_decl,
                .args = self.ast.declTraitArgs(d),
                .head = .{ .builtin = primitive },
                .decl = d,
            });
        }

        // The declaration the head names. A tuple's is the prelude's, which
        // no name in scope need reach: a module declaring its own `Tuple2`
        // shadows the name and not the syntax. A written name's is whatever
        // the name reached, where that is a type's own declaration.
        const declared: DeclId = if (tuple_head) tuple: {
            break :tuple self.tupleDecl(written_head) orelse {
                try self.refused_impls.put(self.gpa, d, {});
                return self.sink.addErrorFmt(
                    .n_undefined,
                    self.ast.fileOf(tok),
                    self.ast.writtenSpan(written_head),
                    "the prelude publishes no tuple of this many components",
                    "undefined name `Tuple{d}`",
                    .{written_head.args.len()},
                );
            };
        } else name: {
            if (named == BindingId.none) {
                try self.refused_impls.put(self.gpa, d, {});
                return self.sink.addErrorFmt(
                    .n_undefined,
                    self.ast.fileOf(tok),
                    self.ast.tokenSpan(tok),
                    "no type with this name is declared here",
                    "undefined name `{s}`",
                    .{self.ast.tokenText(tok)},
                );
            }

            const b = self.bindings.items[named.index()];
            if (b.kind == .type_alias) {
                // Named by being written; the refusal is about where.
                self.bindings.items[named.index()].used = true;
                try self.refused_impls.put(self.gpa, d, {});
                return self.sink.addErrorFmt(
                    .n_type_alias,
                    self.ast.fileOf(tok),
                    self.ast.tokenSpan(tok),
                    try std.fmt.allocPrint(self.sink.arena, "write it for the type the alias names, `{s}`", .{self.ast.writtenText(self.ast.declReturnRef(b.decl))}),
                    "`{s}` is an alias, and an implementation names a type's own declaration",
                    .{self.ast.tokenText(tok)},
                );
            }
            if (b.kind != .declared_type) {
                try self.refused_impls.put(self.gpa, d, {});
                return self.sink.addErrorFmt(
                    .n_not_a_type,
                    self.ast.fileOf(tok),
                    self.ast.tokenSpan(tok),
                    "only a type has an `impl`",
                    "`{s}` is not a type",
                    .{self.ast.tokenText(tok)},
                );
            }
            break :name b.decl;
        };

        // A module owning one side of what the `impl` declares may write it.
        // An inherent `impl` names only a type, so the module declaring that
        // type is the only one owning a side.
        const from = self.moduleOf(declared);
        if (!is_derive and !self.mayImplement(.{ .declared = from }, trait_decl)) {
            try self.refused_impls.put(self.gpa, d, {});
            // What the writer can do differs by what was written. An inherent
            // `impl` has one side, so there is one place it can go; naming the
            // trait to someone who wrote none is advice about a construct that
            // is not on the line. A tuple head is underlined whole and named
            // by its declaration, which is what the module is told to find.
            return self.sink.addErrorFmt(
                .m_impl,
                self.ast.fileOf(tok),
                if (tuple_head) self.ast.writtenSpan(written_head) else self.ast.tokenSpan(tok),
                if (self.ast.declTrait(d) == TokenId.none)
                    "write the `impl` in the module that declares the type"
                else if (trait_decl != DeclId.none and self.program.get(from).library and self.program.get(self.moduleOf(trait_decl)).library)
                    try self.refusalHelp(.{ .declared = from }, self.ast.tokenText(if (tuple_head) self.ast.declName(declared) else tok), trait_decl)
                else
                    "write it where the trait is declared, or where the type is",
                "`{s}` is declared in `{s}`",
                .{ self.ast.tokenText(if (tuple_head) self.ast.declName(declared) else tok), self.program.get(from).name },
            );
        }

        // Recorded by the declarations both sides name rather than by the text
        // that reached them, which is what coherence has to compare: an
        // implementation written against a re-exported name is written against
        // the type it aliases, and one written on a tuple against the tuple's
        // declaration. Only an admitted one is recorded -- an `impl` already
        // reported as belonging elsewhere is one mistake, and counting it here
        // would report it a second time as a conflict.
        if (trait_decl != DeclId.none and !is_derive) {
            try self.impls.append(self.gpa, .{
                .trait = trait_decl,
                .args = self.ast.declTraitArgs(d),
                .head = .{ .declared = declared },
                .decl = d,
            });
        }
        // An inherent block is what a value of the type answers to, so the
        // declaration its head names is kept for chaining its members under
        // that declaration: settled here, once, where the head was resolved.
        if (trait_decl == DeclId.none and !is_derive) try self.inherent_heads.append(self.gpa, .{ .impl = d, .names = declared });
    }

    /// The help for an `impl` this program may not write because the library
    /// declares its trait and owns its type side.
    fn refusalHelp(self: *Resolver, side: ImplTypeSide, type_name: []const u8, trait_decl: DeclId) std.mem.Allocator.Error![]const u8 {
        const refusal = try implRefusal(self.sink.arena, side, type_name, self.ast.tokenText(self.ast.declName(trait_decl)));
        const instead = refusal.instead orelse return refusal.reason;
        return std.fmt.allocPrint(self.sink.arena, "{s}; {s}", .{ refusal.reason, instead });
    }

    /// Whether the module being resolved may write an implementation of
    /// `trait_decl` (`.none` for an inherent one) for a head whose type side
    /// is `side`.
    fn mayImplement(self: *const Resolver, side: ImplTypeSide, trait_decl: DeclId) bool {
        const trait_module: ModuleId = if (trait_decl == DeclId.none) .none else self.moduleOf(trait_decl);
        return ownsAnImplSide(self.current, self.program.get(self.current).library, side, trait_module);
    }

    /// How a report quotes an implementation's head: a tuple by the
    /// declaration its arity names, since every tuple of one arity shares that
    /// head, unit as `()`, and a name by its text.
    fn headText(self: *const Resolver, d: DeclId) []const u8 {
        const head = self.ast.declHead(d);
        if (self.isTupleHead(d)) return tuple_names[head.args.len() - node.min_tuple_arity];
        if (head.kind == .tuple or head.kind == .callable) return self.ast.writtenText(head);
        if (self.ast.tokenTag(head.at) == .l_paren) return "()";
        return self.ast.tokenText(head.at);
    }

    /// Whether an implementation's head is a tuple of an admitted arity,
    /// which coherence reads as the tuple declaration of that arity.
    fn isTupleHead(self: *const Resolver, d: DeclId) bool {
        const head = self.ast.declHead(d);
        return head.kind == .tuple and node.isTupleArity(head.args.len());
    }

    /// Records what the prelude publishes, once the library is resolved: the
    /// declarations syntax finds by identity, and among them the tuple
    /// declarations by arity, so a tuple head or argument is answered by an
    /// index rather than by a walk of the prelude.
    fn publishPrelude(self: *Resolver, decls: []const DeclId) void {
        self.prelude_decls = decls;
        self.tuple_decls = tupleDeclsIn(self.ast, decls);
    }

    /// `Resolution.tupleDecl` for a written tuple, asked while the walk runs.
    fn tupleDecl(self: *const Resolver, written: node.TypeRef) ?DeclId {
        return tupleDeclIn(self.tuple_decls, written.args.len());
    }

    /// Whether an implementation or derive head is one the parser refused and
    /// reported where it was written: a grouped type, which names nothing, or
    /// a tuple of an arity a tuple cannot have. Such a head registers nothing,
    /// so no second report names unit or a `Tuple1` nobody wrote.
    fn headRefusedByTheParser(head: node.TypeRef) bool {
        return switch (head.kind) {
            .grouped => true,
            .tuple => !node.isTupleArity(head.args.len()),
            else => false,
        };
    }

    test "a grouped head and a tuple head of a refused arity register nothing" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        for ([_][]const u8{ "(UInt8)", "(UInt8,)", "(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)" }) |head| {
            const text = try std.fmt.allocPrint(gpa, "trait Show {{}}\nimpl Show for {s} {{}}\nfn main() -> UInt8 {{ 0 }}\n", .{head});
            const result = try resolveWithPrelude(gpa, text, "pub struct Tuple2[A, B] { _0: A, _1: B }\n");
            try testing.expectEqual(@as(u32, 1), result.errors);
            try testing.expectEqual(@as(u32, 0), result.undefined);
        }
        // An arity the parser admits and the prelude does not publish is a
        // head naming nothing, which is reported.
        const unpublished = try resolveWithPrelude(gpa,
            \\trait Show {}
            \\impl Show for (UInt8, Bool, UInt16) {}
            \\fn main() -> UInt8 { 0 }
            \\
        , "pub struct Tuple2[A, B] { _0: A, _1: B }\n");
        try testing.expectEqual(@as(u32, 1), unpublished.undefined);
    }

    test "a callable head is one implementation per shape and invocation" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const header = "trait Show {}\n";
        const footer = "fn main() -> UInt8 { 0 }\n";
        const shapes = [_][]const u8{
            "impl Show for fn(a: UInt8) -> UInt8 {}\n",
            "impl Show for fn(inout a: UInt8) -> UInt8 {}\n",
            "impl Show for fn(a: UInt8, b: UInt8) -> UInt8 {}\n",
            "impl Show for inout fn(a: UInt8) -> UInt8 {}\n",
        };
        const together = try std.mem.concat(gpa, u8, &.{ header, shapes[0], shapes[1], shapes[2], shapes[3], footer });
        const distinct = try resolveWithPrelude(gpa, together, "");
        try testing.expectEqual(@as(u32, 0), distinct.duplicates);

        const repeated = try std.mem.concat(gpa, u8, &.{ header, shapes[0], "impl Show for fn(b: Bool) -> Bool {}\n", footer });
        try testing.expectEqual(@as(u32, 1), (try resolveWithPrelude(gpa, repeated, "")).duplicates);
    }

    /// The implementations the compiler provides, recorded as implementations.
    ///
    /// A primitive cannot implement these in Linea: a body written with `<` is
    /// `Comparable.less` and calls itself. An array cannot implement anything
    /// at all, being a form rather than a name and so having no head a header
    /// could write. They are rows in the list every written implementation is
    /// a row of, so coherence holds a header against them the way it holds one
    /// header against another -- a trait's own module may name a primitive in
    /// a head, and what it would write there is already implemented.
    ///
    /// **Bound:** the traits named above times the primitives each runs over,
    /// plus one row per trait the array constructor carries, and one lookup per
    /// trait -- a walk of `std/cmp` for the first group and of the prelude for
    /// the second. The first two are constants of the language; the walks are
    /// over what the library holds, and none of them grows with the program
    /// being compiled.
    fn seedProvidedImplementations(self: *Resolver, prelude: []const DeclId) !void {
        for (ambient_traits) |t| {
            const trait = self.libraryTrait(t.module, t.name) orelse continue;
            for (t.over) |held| {
                try self.impls.append(self.gpa, .{
                    .trait = trait,
                    // These traits take no parameters, so there is nothing to
                    // supply for them -- and nothing wrote a head here, so
                    // there would be no spelling to supply it with.
                    .args = .empty,
                    .head = .{ .builtin = held },
                    .decl = DeclId.none,
                });
            }
        }

        for (ambient_array_traits) |t| {
            const trait = self.preludeTrait(prelude, t.name) orelse continue;
            try self.impls.append(self.gpa, .{
                .trait = trait,
                // `Index` does take a parameter, and no head wrote the
                // argument for it: what this row supplies is a type, so it
                // sits in the field that holds one.
                .args = .empty,
                .head = .array,
                .decl = DeclId.none,
                .supplied = t.args,
            });
        }

        for (viewed_array_traits) |t| {
            const trait = self.libraryTrait(t.module, t.name) orelse continue;
            try self.impls.append(self.gpa, .{
                .trait = trait,
                .args = .empty,
                .head = .array,
                .decl = DeclId.none,
                .viewed = true,
            });
        }
    }

    /// The trait the prelude publishes under a name, or `null` where the name
    /// reaches something else or nothing.
    /// The trait a library module declares under this name.
    ///
    /// For a trait the compiler implements itself but no program need import.
    /// Found the way every library declaration the compiler must name is found
    /// -- by its module and its name -- rather than through the prelude, which
    /// answers a different question: what a program may write without importing
    /// anything.
    fn libraryTrait(self: *const Resolver, module: []const u8, name: []const u8) ?DeclId {
        const d = self.program.libraryDeclIn(module, name) orelse return null;
        return if (self.ast.declTag(d) == .trait_) d else null;
    }

    fn preludeTrait(self: *const Resolver, prelude: []const DeclId, name: []const u8) ?DeclId {
        const d = preludeDeclIn(self.ast, prelude, name) orelse return null;
        return if (self.ast.declTag(d) == .trait_) d else null;
    }

    /// At most one implementation of a trait for a type, across the program.
    ///
    /// What licenses every consumer to take the first implementation it finds
    /// rather than search among candidates: a bound is discharged by one and a
    /// call runs one, and two would let those two answers differ. Asked of the
    /// whole program at once because either module owning a side may write it,
    /// so neither sees both on its own.
    fn checkCoherence(self: *Resolver) !void {
        // One argument position per trait/head chain separates distinct written
        // constructors. Choosing it scans the represented arguments once; a
        // bare parameter or structural form remains in every candidate set.
        const Columns = struct {
            roots: std.ArrayList(?u64) = .empty,
            position: ?usize = null,
        };
        var columns: std.AutoHashMapUnmanaged(u64, Columns) = .empty;
        defer {
            var values = columns.valueIterator();
            while (values.next()) |value| value.roots.deinit(self.gpa);
            columns.deinit(self.gpa);
        }
        for (self.impls.items) |it| {
            if (it.decl == DeclId.none or it.trait == DeclId.none) continue;
            const entry = try columns.getOrPut(self.gpa, self.coherenceKey(it));
            if (!entry.found_existing) entry.value_ptr.* = .{};
            const choice = entry.value_ptr;
            const args = self.ast.typeArgs(it.args);
            if (args.len > choice.roots.items.len) {
                const old_len = choice.roots.items.len;
                try choice.roots.resize(self.gpa, args.len);
                @memset(choice.roots.items[old_len..], null);
            }
            for (args, 0..) |arg, position| {
                const root = self.coherenceArgumentRoot(arg) orelse continue;
                if (choice.roots.items[position]) |prior| {
                    if (prior != root) choice.position = @min(choice.position orelse position, position);
                } else choice.roots.items[position] = root;
            }
        }

        const RootKey = struct { group: u64, root: u64 };
        var first: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        defer first.deinit(self.gpa);
        var named: std.AutoHashMapUnmanaged(RootKey, u32) = .empty;
        defer named.deinit(self.gpa);
        var wildcards: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        defer wildcards.deinit(self.gpa);
        const next = try self.gpa.alloc(u32, self.impls.items.len);
        defer self.gpa.free(next);
        const filtered_next = try self.gpa.alloc(u32, self.impls.items.len);
        defer self.gpa.free(filtered_next);

        for (self.impls.items, 0..) |it, i| {
            // An implementation written with a length nothing settles is not
            // keyed at all, because neither answer a comparison could give for
            // one is sound: two lengths with no value called equal make one
            // key for what may be two types, and the one symbol that key
            // spells then stands for both; called unequal they admit two
            // implementations of what may be one type, and which of them a
            // call reaches is then decided by which was written first. Such a
            // length is not a type either, so it is refused where the type is
            // written and no program keeps it.
            if (!try self.lengthsAreSettled(it)) continue;

            // An inherent block implements no trait, so no other block is the
            // same implementation as it. A primitive's inherent blocks are rows
            // only so the namespace its name opens can be found, and the
            // library may split one primitive's methods across several.
            if (it.trait == DeclId.none) continue;

            const key = self.coherenceKey(it);
            const position = if (columns.get(key)) |choice| choice.position orelse 0 else 0;
            const args = self.ast.typeArgs(it.args);
            const root = if (it.decl != DeclId.none and position < args.len)
                self.coherenceArgumentRoot(args[position])
            else
                null;
            var chain = if (root) |r| named.get(.{ .group = key, .root = r }) else first.get(key);
            var wildcard = if (root != null) wildcards.get(key) else null;
            var found: ?Implementation = null;
            // Merge the two descending chains, retaining the latest matching
            // declaration as the diagnostic's earlier implementation.
            while (chain != null or wildcard != null) {
                const from_chain = if (chain) |j| wildcard == null or j > wildcard.? else false;
                const j = if (from_chain) chain.? else wildcard.?;
                const candidate = self.impls.items[j];
                if (self.sameImplementation(candidate, it)) {
                    found = candidate;
                    break;
                }
                const links = if (root == null) next else filtered_next;
                const following: ?u32 = if (links[j] == j) null else links[j];
                if (from_chain) chain = following else wildcard = following;
            }

            const earlier = found orelse {
                // Keep the full chain for a later wildcard as well as the
                // filtered chain for a later explicitly applied name.
                next[i] = first.get(key) orelse @intCast(i);
                try first.put(self.gpa, key, @intCast(i));
                if (root) |r| {
                    const root_key: RootKey = .{ .group = key, .root = r };
                    filtered_next[i] = named.get(root_key) orelse @intCast(i);
                    try named.put(self.gpa, root_key, @intCast(i));
                } else {
                    filtered_next[i] = wildcards.get(key) orelse @intCast(i);
                    try wildcards.put(self.gpa, key, @intCast(i));
                }
                continue;
            };

            {
                // What the compiler provides has no header to point at, so
                // there is nothing to report a pair of them at, and reading a
                // header off one reads the declaration table at no
                // declaration. Nothing is lost by passing over such a pair:
                // the rows the compiler provides differ from each other in
                // what they supply, so no two of them are one implementation.
                if (it.decl == DeclId.none) continue;

                const at = self.ast.declTrait(it.decl);

                // The report stands on whichever side was written, which is
                // this one. A row the compiler provides is the earlier of the
                // two wherever it takes part, because those rows are recorded
                // before any header is read.
                if (earlier.decl == DeclId.none) {
                    try self.sink.addErrorFmt(
                        .n_duplicate,
                        self.ast.fileOf(at),
                        self.ast.tokenSpan(at),
                        "the compiler implements it for this type",
                        "`{s}` is already implemented for `{s}`",
                        .{
                            self.ast.tokenText(at),
                            self.headText(it.decl),
                        },
                    );
                    continue;
                }

                const before = self.ast.declTrait(earlier.decl);
                try self.duplicate_impls.put(
                    self.gpa,
                    Resolution.duplicateKey(earlier.decl, it.decl),
                    {},
                );

                const labels = try self.sink.arena.alloc(Label, 2);
                labels[0] = .{
                    .file = self.ast.fileOf(before),
                    .span = self.ast.tokenSpan(before),
                    .message = "already implemented here",
                    .style = .secondary,
                };
                // What the two share is the whole key, so the message names
                // the whole key. A trait taking arguments has several
                // implementations for one type that are not duplicates, and a
                // message stopping at the type would state a rule this does
                // not enforce.
                const generic = it.args.len() > 0;
                labels[1] = .{
                    .file = self.ast.fileOf(at),
                    .span = self.ast.tokenSpan(at),
                    .message = if (it.head == .default_)
                        "a trait has at most one default implementation"
                    else if (generic)
                        "a trait is implemented once per arguments and type"
                    else if (self.isTupleHead(it.decl))
                        "a trait is implemented once for all tuples of one arity"
                    else if (it.head == .callable_)
                        "a trait is implemented once for each callable shape"
                    else
                        "a trait is implemented once for a type",
                    .style = .primary,
                };
                try self.sink.add(.{
                    .severity = .err,
                    .code = .n_duplicate,
                    .message = if (it.head == .default_) try std.fmt.allocPrint(
                        self.sink.arena,
                        "`{s}` already has a default implementation",
                        .{self.ast.tokenText(at)},
                    ) else if (generic) try std.fmt.allocPrint(
                        self.sink.arena,
                        "`{s}` is already implemented for `{s}` with the same arguments",
                        .{
                            self.ast.tokenText(at),
                            self.headText(it.decl),
                        },
                    ) else try std.fmt.allocPrint(
                        self.sink.arena,
                        "`{s}` is already implemented for `{s}`",
                        .{
                            self.ast.tokenText(at),
                            self.headText(it.decl),
                        },
                    ),
                    .labels = labels,
                });
            }
        }
    }

    /// An explicitly applied name cannot be replaced by one of a family's
    /// parameters, and a name that reaches a type fails `sameWrittenArgs`
    /// against one that reaches another, whatever the reading. Hash collisions
    /// retain extra candidates; equality remains that routine's decision.
    ///
    /// An alias with arguments is the type it names, so its root is the head
    /// of that type; an alias that is not headed by a name -- one naming a
    /// parameter, an array or a function type -- can stand for any type and
    /// has no root. Other forms carry no root this filter can safely separate.
    fn coherenceArgumentRoot(self: *const Resolver, arg: node.TypeRef) ?u64 {
        var h: std.hash.Wyhash = .init(0);
        switch (arg.kind) {
            .named => if (arg.args.len() == 0) return null,
            // A tuple is rooted where its long form is, so the two spellings
            // of one argument sit in one chain and are compared.
            .tuple => {
                const decl = self.tupleDecl(arg) orelse return null;
                const identity: u32 = @intFromEnum(decl);
                h.update(std.mem.asBytes(&identity));
                return h.final();
            },
            else => return null,
        }
        if (self.reachedType(arg.name)) |identity| {
            h.update(std.mem.asBytes(&identity));
            return h.final();
        }
        if (self.aliasReached(arg.name) != null) return null;
        const tag = self.ast.tokenTag(arg.name);
        const name = self.ast.tokenName(arg.name);
        h.update(std.mem.asBytes(&tag));
        h.update(std.mem.asBytes(&name));
        return h.final();
    }

    /// Whether two implementations are the same one: the trait, the head
    /// constructor, and the arguments supplied to the trait once a family's
    /// own parameters are read at the other's head.
    ///
    /// A family supplies the trait whatever its head was applied to, so
    /// `Give[T] for Holder[T]` supplies `Give[UInt8]` at `Holder[UInt8]` and
    /// is the same implementation as one that writes those arguments out.
    /// Comparing what was written made those two keys, which let a settled
    /// head sit under a family that already answers for it and never be
    /// reached by anything.
    ///
    /// One side is read at the other's head and never both: two families read
    /// at each other would each be renamed into the other's parameters, and a
    /// family read at a settled head is already the whole comparison.
    fn sameImplementation(self: *const Resolver, a: Implementation, b: Implementation) bool {
        if (a.trait != b.trait) return false;
        if (a.head == .default_ or b.head == .default_) return a.head == .default_ and b.head == .default_;
        if (a.head == .parameter or b.head == .parameter) return false;
        if (!std.meta.eql(a.head, b.head)) return false;
        // What the compiler provides has no header, so there are no parameters
        // to read one side at -- and what it supplies is not written anywhere,
        // so it is not in the written list this comparison otherwise reads.
        if (a.decl == DeclId.none or b.decl == DeclId.none) {
            return self.sameArgumentsProvided(a, b);
        }
        const ctx: Coherence = .{ .res = self };
        if (self.ast.declTypeParams(a.decl).len != 0) return sameWrittenArgs(self.ast, ctx, a.args, self.reading(a.decl, b), b.args, .{}) catch unreachable;
        if (self.ast.declTypeParams(b.decl).len != 0) return sameWrittenArgs(self.ast, ctx, b.args, self.reading(b.decl, a), a.args, .{}) catch unreachable;
        return sameWrittenArgs(self.ast, ctx, a.args, .{}, b.args, .{}) catch unreachable;
    }

    /// What `sameWrittenArgs` reads while implementations are keyed: the
    /// declaration each written name reached, and the value each length and
    /// callable default was worth when its implementation was keyed.
    const Coherence = struct {
        res: *const Resolver,

        pub const Error = error{};

        pub fn reaches(self: Coherence, tok: TokenId) Reached {
            const b = self.res.writtenBinding(tok);
            if (b == BindingId.none) return .nothing;
            const held = self.res.bindings.items[b.index()];
            return .of(held.kind, held.decl, held.builtin);
        }

        /// The prelude's declaration of the tuple with `arity` components.
        pub fn tuple(self: Coherence, arity: usize) ?DeclId {
            return tupleDeclIn(self.res.tuple_decls, arity);
        }

        /// Both expressions were folded before either implementation was
        /// keyed, so both are answers this run already holds. One that does
        /// not settle to a value never reaches a key: the walk skipped the
        /// implementation holding one before comparing anything. A miss here
        /// is that coupling broken -- `lengthsWithin` descending less far than
        /// the comparison reads -- and not a case to decide: answering
        /// "different" would hand the winner to declaration order, and "same"
        /// would put one symbol over what may be two types.
        pub fn sameValue(self: Coherence, a: ExprId, b: ExprId) Error!bool {
            const x = (self.res.folded.worthOf(a) orelse
                std.debug.panic("compiler defect: an unsettled constant reached a coherence key", .{})).checked() orelse
                std.debug.panic("compiler defect: an unsettled constant reached a coherence key", .{});
            const y = (self.res.folded.worthOf(b) orelse
                std.debug.panic("compiler defect: an unsettled constant reached a coherence key", .{})).checked() orelse
                std.debug.panic("compiler defect: an unsettled constant reached a coherence key", .{});
            return x.eql(y);
        }
    };

    /// Whether two implementations supply the trait the same arguments, where
    /// at least one of them is a row the compiler provides.
    ///
    /// Such a row supplies types, in `supplied`, because nothing wrote a
    /// spelling for it to supply -- so that is the one place its arguments
    /// live and this is the one comparison that reads them. Reading the
    /// written list for a provided row reads an empty one whatever the row
    /// supplies, which makes every row of one trait and one head the same
    /// implementation: two the compiler provides for one constructor would be
    /// reported as a duplicate of each other, at a header neither of them has.
    ///
    /// A header on the other side supplies written references, and this pass
    /// holds no type for a written name. The count is what both sides state
    /// in the same terms, and it decides every pair that can arise: a trait
    /// the compiler implements for a primitive takes no parameters, so a
    /// header supplying one is a header for something else, and the row that
    /// does supply one is for the array constructor, which no header can name.
    fn sameArgumentsProvided(self: *const Resolver, a: Implementation, b: Implementation) bool {
        if (self.argumentCount(a) != self.argumentCount(b)) return false;
        // The walk below reads both lists, so it is the lists that have to
        // agree in length and not the counts read out of whichever list each
        // side keeps. A pair supplying as many arguments as each other while
        // holding them in different lists passes the count above and would be
        // walked past the end of the shorter.
        if (a.supplied.len != b.supplied.len) return false;
        for (a.supplied, b.supplied) |x, y| {
            if (!x.same(y)) return false;
        }
        return true;
    }

    /// How many arguments an implementation supplies its trait, read from
    /// whichever list holds them: written references for a header, types for a
    /// row the compiler provides.
    fn argumentCount(self: *const Resolver, it: Implementation) usize {
        if (it.decl == DeclId.none) return it.supplied.len;
        return self.ast.typeArgs(it.args).len;
    }

    /// What `sameImplementation` can compare before it has both sides.
    ///
    /// The trait and the head constructor and nothing else. What a family
    /// supplies the trait is settled by the head it is read at, so the
    /// arguments are not a property of one implementation and cannot be part
    /// of a key. A shared hash is verified before anything is reported, so a
    /// coarse one costs a comparison and never an answer.
    fn coherenceKey(_: *const Resolver, it: Implementation) u64 {
        var h: std.hash.Wyhash = .init(0);
        const trait: u32 = @intFromEnum(it.trait);
        h.update(std.mem.asBytes(&trait));
        switch (it.head) {
            .declared => |d| {
                h.update("declared");
                const at: u32 = @intFromEnum(d);
                h.update(std.mem.asBytes(&at));
            },
            .builtin => |t| {
                h.update("builtin");
                const at: u32 = @intFromEnum(t);
                h.update(std.mem.asBytes(&at));
            },
            .array => h.update("array"),
            .borrow_ => h.update("borrow"),
            .callable_ => |shape| {
                h.update("callable");
                h.update(std.mem.asBytes(&shape));
            },
            .parameter => h.update("parameter"),
            .default_ => h.update("default"),
        }
        return h.final();
    }

    /// A family's parameters read at what `at`'s head applies.
    fn reading(self: *const Resolver, family: DeclId, at: Implementation) Reading {
        return .{
            .family = family,
            .applied = self.ast.typeArgs(self.ast.declHead(at.decl).args),
        };
    }

    /// The type a written name reached, through an alias to the name that heads
    /// what it stands for, or null where it reached none: a type parameter,
    /// an associated type, or a name nothing declares.
    fn reachedType(self: *const Resolver, tok: TokenId) ?u32 {
        const type_binding = self.throughAlias(self.writtenBinding(tok));
        if (type_binding == BindingId.none) return null;
        const held = self.bindings.items[type_binding.index()];
        return switch (Reached.of(held.kind, held.decl, held.builtin)) {
            .type_ => |identity| identity,
            .nothing, .alias => null,
        };
    }

    /// The binding a written name reached, or `.none` where it has not reached
    /// one yet.
    fn writtenBinding(self: *const Resolver, tok: TokenId) BindingId {
        if (tok == TokenId.none or tok.index() >= self.written.items.len) return .none;
        return self.written.items[tok.index()];
    }

    /// The alias a written name reached, or null where it reached anything
    /// else.
    fn aliasReached(self: *const Resolver, tok: TokenId) ?DeclId {
        const b = self.writtenBinding(tok);
        if (b == BindingId.none or self.bindings.items[b.index()].kind != .type_alias) return null;
        return self.bindings.items[b.index()].decl;
    }

    test "a name and the same name qualified by its module key one implementation" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const app_source: Source = .{ .path = "app/main.lin", .text =
            \\import geo
            \\use geo.Pair
            \\struct P {}
            \\trait Takes[T] {}
            \\impl Takes[Pair[UInt8]] for P {}
            \\impl Takes[geo.Pair[UInt8]] for P {}
            \\impl Takes[geo.Pair[Bool]] for P {}
            \\fn main() -> UInt8 { 0 }
            \\
        };
        const geo_source: Source = .{ .path = "geo/main.lin", .text =
            \\pub struct Pair[T] { first: T, second: T }
            \\
        };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        var trees = Modules.init(gpa, &sink, &interner);
        const app_decls = try trees.add(&.{.{ .file = .from(0), .source = app_source }});
        const geo_decls = try trees.add(&.{.{ .file = .from(1), .source = geo_source }});
        const ast = try trees.finish();
        var app_imports = [_]program_mod.Import{.{ .decl = DeclId.at(app_decls.start), .module = .from(1) }};
        var modules = [_]program_mod.Module{
            .{ .name = "app", .dir = "app", .files = &.{.from(0)}, .decls = app_decls, .imports = &app_imports },
            .{ .name = "geo", .dir = "geo", .files = &.{.from(1)}, .decls = geo_decls, .imports = &.{} },
        };
        const program: Program = .{ .modules = &modules, .ast = ast, .prelude = .none };
        _ = try resolve(gpa, &program, &interner, &sink, .program);
        var duplicates: u32 = 0;
        for (sink.items()) |d| {
            if (d.code == .n_duplicate) duplicates += 1;
        }
        try testing.expectEqual(@as(u32, 1), duplicates);
    }

    test "a tuple argument and its long form key one implementation, and a module's own Tuple2 is another" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const prelude = "pub struct Tuple2[A, B] { _0: A, _1: B }\n";

        // The two spellings of one trait argument.
        const argument = try resolveWithPrelude(gpa,
            \\struct P {}
            \\trait From[T] {}
            \\impl From[(UInt8, Bool)] for P {}
            \\impl From[Tuple2[UInt8, Bool]] for P {}
            \\fn main() -> UInt8 { 0 }
            \\
        , prelude);
        try testing.expectEqual(@as(u32, 1), argument.duplicates);

        // The two spellings of one head, each a family over its components.
        const head = try resolveWithPrelude(gpa,
            \\trait Show {}
            \\impl[A, B] Show for (A, B) {}
            \\impl[A, B] Show for Tuple2[A, B] {}
            \\fn main() -> UInt8 { 0 }
            \\
        , prelude);
        try testing.expectEqual(@as(u32, 1), head.duplicates);

        // A module's own `Tuple2` shadows the name and not the syntax.
        const own = try resolveWithPrelude(gpa,
            \\struct Tuple2[A, B] { l: A, r: B }
            \\trait Show {}
            \\impl[A, B] Show for (A, B) {}
            \\impl[A, B] Show for Tuple2[A, B] {}
            \\fn main() -> UInt8 { 0 }
            \\
        , prelude);
        try testing.expectEqual(@as(u32, 0), own.duplicates);
        try testing.expectEqual(@as(u32, 0), own.undefined);

        // A tuple the prelude does not publish is a head naming nothing.
        const unpublished = try resolveWithPrelude(gpa,
            \\trait Show {}
            \\impl Show for (UInt8, Bool, UInt16) {}
            \\fn main() -> UInt8 { 0 }
            \\
        , prelude);
        try testing.expectEqual(@as(u32, 1), unpublished.undefined);
    }

    /// What an array's length is worth, by the routine that folds a constant
    /// expression wherever one is read, remembered for the rest of the run.
    fn foldedLength(self: *Resolver, x: node.TypeRef) !constfold.Value {
        return constfold.foldConstant(self.gpa, self.ast, self.nameSites(), &self.folded, x.length);
    }

    /// Whether every length written into what decides an implementation's
    /// identity counts something.
    ///
    /// The trait's arguments and the head's: a family supplies the trait
    /// whatever its head was applied to, so a head argument is compared as a
    /// trait argument is and its lengths are read the same way.
    ///
    /// **The guard.** This is what lets every comparison below assume a length
    /// counts something: an implementation failing it is left out of the
    /// keying entirely, and the checker refuses the type where it is written.
    /// Another consumer that compares written array types calls this before it
    /// compares anything, or it decides for itself what two lengths with no
    /// count mean -- and neither answer to that is sound.
    fn lengthsAreSettled(self: *Resolver, it: Implementation) !bool {
        var walking: std.AutoHashMapUnmanaged(DeclId, void) = .empty;
        defer walking.deinit(self.gpa);
        var finished: std.ArrayList(DeclId) = .empty;
        defer finished.deinit(self.gpa);
        const settled = try self.implementationLengthsWithin(it, &walking, &finished);
        // An alias finished inside a walk that failed was read under an
        // answer the failure may have decided, so none of them is kept.
        if (!settled) {
            for (finished.items) |alias| _ = self.settled_aliases.remove(alias);
        }
        return settled;
    }

    fn implementationLengthsWithin(
        self: *Resolver,
        it: Implementation,
        walking: *std.AutoHashMapUnmanaged(DeclId, void),
        finished: *std.ArrayList(DeclId),
    ) !bool {
        if (!try self.lengthsWithin(self.ast.typeArgs(it.args), walking, finished)) return false;
        // What the compiler provides has no header, so there is no written head
        // to read a length out of. Its head is a primitive or the array
        // constructor, and neither holds a written argument to carry a length:
        // nothing to settle is settled, and the row is keyed like any other.
        if (it.decl == DeclId.none) return true;
        return self.lengthsWithin(self.ast.typeArgs(self.ast.declHead(it.decl).args), walking, finished);
    }

    /// The same question of a run of written types and everything under them.
    ///
    /// It descends exactly where `sameWrittenType` does, because what it settles
    /// is what that comparison reads: a form it walked past is a length the
    /// comparison would find no value for, and that is the panic there. An
    /// alias is read as the type it names, so its text is walked too, once for
    /// the run: a type naming an alias twice stands for a tree of the alias's
    /// expansion, but the lengths in it are the lengths in the alias's text.
    /// `walking` holds the aliases being walked, so one that names itself is
    /// not walked again, and `finished` the ones this walk settled. `walking`
    /// is a set because a chain of aliases n deep holds n entries and each
    /// step asks whether its alias is among them.
    ///
    /// Bounded by the text of the run and of each alias it reaches, once.
    fn lengthsWithin(
        self: *Resolver,
        refs: []const node.TypeRef,
        walking: *std.AutoHashMapUnmanaged(DeclId, void),
        finished: *std.ArrayList(DeclId),
    ) !bool {
        for (refs) |r| {
            switch (r.kind) {
                .named, .borrow, .grouped, .tuple => {},
                .selection => if (!try self.lengthsWithin(&.{self.ast.selectionBase(r)}, walking, finished)) return false,
                // A count, and not merely a constant expression: a truth value
                // is one and says nothing about how many elements a type holds,
                // so an implementation written with one is left unkeyed exactly
                // as one whose length has no value at all is. The type is
                // refused where it is written, which is what reports it.
                .array => if ((try self.foldedLength(r)).number() == null) return false,
                .callable => {
                    const callable = self.ast.callableType(r);
                    for (self.ast.params[callable.params.start..callable.params.end]) |param| {
                        if (!try self.lengthsWithin(&.{param.written}, walking, finished)) return false;
                        if (param.default != ExprId.none and
                            (try constfold.foldConstant(
                                self.gpa,
                                self.ast,
                                self.nameSites(),
                                &self.folded,
                                param.default,
                            )).checked() == null)
                        {
                            return false;
                        }
                    }
                    if (!try self.lengthsWithin(&.{callable.result}, walking, finished)) return false;
                },
            }
            if (!try self.lengthsWithin(self.ast.typeArgs(r.args), walking, finished)) return false;
            if ((r.kind == .named or r.kind == .selection) and r.name != TokenId.none) {
                if (self.aliasReached(r.name)) |alias| {
                    if (!self.settled_aliases.contains(alias) and !walking.contains(alias)) {
                        try walking.put(self.gpa, alias, {});
                        defer _ = walking.remove(alias);
                        if (!try self.lengthsWithin(&.{self.ast.declReturnRef(alias)}, walking, finished)) return false;
                        try self.settled_aliases.put(self.gpa, alias, {});
                        try finished.append(self.gpa, alias);
                    }
                }
            }
        }
        return true;
    }

    /// What a fold reads about the names written in a constant expression, from
    /// what the walk has settled so far.
    fn nameSites(self: *const Resolver) constfold.Names {
        return .{ .ctx = self, .reaches = reachedBy, .constant_call = constantCallBy, .integer_property = integerPropertyBy, .variant = variantBy, .tuple_component = tupleComponentBy };
    }

    fn tupleComponentBy(ctx: *const anyopaque, ast: *const Ast, arity: usize, position: usize) ?[]const u8 {
        const self: *const Resolver = @ptrCast(@alignCast(ctx));
        return tupleComponentIn(ast, self.tuple_decls, arity, position);
    }

    fn variantBy(ctx: *const anyopaque, id: ExprId) bool {
        const self: *const Resolver = @ptrCast(@alignCast(ctx));
        return self.variant_ordinals.contains(id);
    }

    /// The position of the variant `name` in an enum declaration, or `null`
    /// where it declares none by that name. The one lookup of a variant by its
    /// name that resolution performs. Bounded by the enum's variants.
    fn variantNamed(self: *const Resolver, decl: DeclId, name: StringId) ?u32 {
        for (self.ast.declVariants(decl), 0..) |v, ordinal| {
            if (self.ast.tokenName(v.name) == name) return @intCast(ordinal);
        }
        return null;
    }

    fn integerPropertyBy(ctx: *const anyopaque, id: ExprId) ?i128 {
        const self: *const Resolver = @ptrCast(@alignCast(ctx));
        const selected = self.integer_selections.get(id) orelse return null;
        const receiver = self.builtinOf(selected.receiver) orelse return null;
        return selected.endpoint.value(receiver);
    }

    fn reachedBy(ctx: *const anyopaque, id: ExprId) constfold.Reach {
        const self: *const Resolver = @ptrCast(@alignCast(ctx));
        if (id == ExprId.none or id.index() >= self.targets.items.len) return .nothing;
        const b = self.targets.items[id.index()];
        if (b == BindingId.none) return .nothing;
        const held = self.bindings.items[b.index()];
        return reachOf(held.kind, held.decl, held.stmt);
    }

    fn constantCallBy(ctx: *const anyopaque, ast: *const Ast, callee: ExprId) ?constfold.ConstantCall {
        const self: *const Resolver = @ptrCast(@alignCast(ctx));
        if (callee == ExprId.none or callee.index() >= self.targets.items.len) return null;
        const b = self.throughAlias(self.targets.items[callee.index()]);
        if (b == BindingId.none) return null;
        const held = self.bindings.items[b.index()];
        return callOn(ast, callee, held.kind, held.builtin, held.decl);
    }

    /// The binding a name reaches in the current module's own scope.
    ///
    /// It answers with whatever the name found, kind and all: a caller wanting
    /// a type or a trait says so about what came back, which is what keeps
    /// "this name is not one" a diagnosable answer rather than a missing one.
    /// A module declares each name once -- a second is [N-Duplicate] and never
    /// enters -- so the first match is the only one.
    fn namedHere(self: *const Resolver, tok: TokenId) BindingId {
        if (self.ast.tokenTag(tok) != .identifier) return .none;
        return self.here_named.get(hereKey(self.current, self.ast.tokenName(tok))) orelse .none;
    }

    /// The key the rows of `here_named` are held under.
    fn hereKey(m: ModuleId, name: StringId) u64 {
        return (@as(u64, @intFromEnum(m)) << 32) | @intFromEnum(name);
    }

    fn rootNameKey(root: program_mod.RootId, name: StringId) u64 {
        return (@as(u64, @intFromEnum(root)) << 32) | @intFromEnum(name);
    }

    /// Records what every module's own run names, once every run is filled.
    ///
    /// Nothing enters a run after the declaration phase, so this is where the
    /// answer stops changing and the walk it replaces stops being needed.
    fn noteScopeNames(self: *Resolver) !void {
        for (0..self.program.modules.len) |i| {
            const m: ModuleId = .from(i);
            for (self.scopeOf(m)) |b| {
                const held = self.bindings.items[b.index()];
                const key = hereKey(m, held.name);
                if (!self.here_named.contains(key)) try self.here_named.put(self.gpa, key, b);

                // What a name written after a dot can reach, which is a
                // different question and needs its own row: a module binding
                // is not reachable through one, and neither is a name the
                // prelude put in every module's scope -- a module that can
                // write a name does not thereby declare it. `here_named`
                // answers with exactly those, since they are entered first.
                //
                // Whether it is `pub` is left to the caller: a private name is
                // reached and refused, and reaching nothing is a different
                // diagnostic.
                if (!nameableFromOutside(held.kind, held.ambient)) continue;
                if (!self.reachable_at.contains(key)) try self.reachable_at.put(self.gpa, key, b);
            }
        }
    }

    /// The primitive a binding names, or null where it names something else.
    ///
    /// The answer `Resolution.builtinOf` gives, read from the bindings while
    /// they are still being built rather than from the finished table the
    /// resolver has not returned yet. One body decides it for both.
    fn builtinOf(self: *const Resolver, b: BindingId) ?TypeId {
        if (b == BindingId.none) return null;
        const held = self.bindings.items[b.index()];
        return builtinNames(held.kind, held.builtin);
    }

    /// The trait a name reaches here, or `.none` where it reaches something
    /// else or nothing.
    ///
    /// The one place the resolver decides which trait a written name means. A
    /// bound, an `impl` header and the rule about who may write that header
    /// all ask it, so none of them can settle on a different trait -- and what
    /// a name reaches is a declaration, never the text, which is what lets two
    /// modules each declare a `Measure`.
    fn traitNamed(self: *const Resolver, tok: TokenId) BindingId {
        const b = self.namedHere(tok);
        if (b == BindingId.none) return .none;
        if (self.bindings.items[b.index()].kind != .trait) return .none;
        return b;
    }

    /// The trait a bound names, marking it used.
    ///
    /// Naming a trait in a bound is using it, as implementing it is: the bound
    /// is what a generic body may assume, which is what a trait is for.
    ///
    /// The declaration rather than a yes: `boundNames` decides what a bound
    /// means from what its name reached, and a bool would leave the caller to
    /// re-derive which trait that was.
    fn traitBound(self: *Resolver, tok: TokenId) ?DeclId {
        const b = self.traitNamed(tok);
        if (b == BindingId.none) return null;
        self.bindings.items[b.index()].used = true;
        self.reached(tok, b);
        return self.bindings.items[b.index()].decl;
    }

    /// The trait an implementation names, where it names one.
    ///
    /// Naming it is using it, exactly as an annotation naming a type is a use:
    /// an implementation exists to say this type satisfies that trait, so a
    /// trait nothing implements is the unused one and a trait implemented here
    /// is not.
    fn implTrait(self: *Resolver, d: DeclId) !DeclId {
        return self.implTraitRef(self.ast.declTraitRef(d));
    }

    /// Resolves one bare or module-qualified trait reference and records every
    /// name in the qualified run at the binding it reaches.
    fn implTraitRef(self: *Resolver, ref: node.TraitRef) !DeclId {
        return self.traitRefReaching(ref, false);
    }

    /// A qualified name at the end of a trait reference: a trait, or in a
    /// bound, where `aliases` is set, an alias -- which bounds by the function
    /// type it names and is no trait, so it answers `.none` once marked.
    fn traitRefReaching(self: *Resolver, ref: node.TraitRef, aliases: bool) !DeclId {
        if (ref.path.len() == 0) return self.implTraitToken(ref.name);

        var names = self.ast.namesOf(ref.path);
        const first = names.next() orelse return .none;
        var module = self.moduleNamed(self.ast.tokenName(first), self.ast.fileOf(first)) orelse {
            try self.sink.addErrorFmt(
                .n_undefined,
                self.ast.fileOf(first),
                self.ast.tokenSpan(first),
                "import the module before qualifying the trait through it",
                "undefined module `{s}`",
                .{self.ast.tokenText(first)},
            );
            return .none;
        };
        self.bindings.items[module.index()].used = true;
        self.reached(first, module);

        var at = names.next() orelse return .none;
        while (true) {
            const b = (try self.throughModule(module, at)) orelse return .none;
            const next = names.next();
            if (next == null) {
                if (aliases and self.bindings.items[b.index()].kind == .type_alias) {
                    self.bindings.items[b.index()].used = true;
                    self.reached(at, b);
                    return .none;
                }
                if (self.bindings.items[b.index()].kind != .trait) {
                    try self.sink.addErrorFmt(
                        .n_not_a_type,
                        self.ast.fileOf(at),
                        self.ast.tokenSpan(at),
                        "only a trait may stand at the end of a trait reference",
                        "`{s}` is not a trait",
                        .{self.ast.tokenText(at)},
                    );
                    return .none;
                }
                self.reached(at, b);
                return self.bindings.items[b.index()].decl;
            }

            if (self.bindings.items[b.index()].kind != .module) {
                try self.sink.addErrorFmt(
                    .n_undefined,
                    self.ast.fileOf(at),
                    self.ast.tokenSpan(at),
                    "only a module namespace may precede the final trait name",
                    "`{s}` does not name a module",
                    .{self.ast.tokenText(at)},
                );
                return .none;
            }
            self.reached(at, b);
            module = b;
            at = next.?;
        }
    }

    fn implTraitToken(self: *Resolver, tok: TokenId) !DeclId {
        if (tok == TokenId.none) return DeclId.none;
        if (self.ast.tokenTag(tok) != .identifier) return DeclId.none;

        const b = self.traitNamed(tok);
        if (b != BindingId.none) {
            self.bindings.items[b.index()].used = true;
            self.reached(tok, b);
            return self.bindings.items[b.index()].decl;
        }

        if (self.namedHere(tok) != BindingId.none) {
            try self.sink.addErrorFmt(
                .n_not_a_type,
                self.ast.fileOf(tok),
                self.ast.tokenSpan(tok),
                "only a trait is implemented for a type",
                "`{s}` is not a trait",
                .{self.ast.tokenText(tok)},
            );
            return DeclId.none;
        }

        try self.sink.addErrorFmt(
            .n_undefined,
            self.ast.fileOf(tok),
            self.ast.tokenSpan(tok),
            "no trait with this name is declared here",
            "undefined name `{s}`",
            .{self.ast.tokenText(tok)},
        );
        return DeclId.none;
    }

    fn checkDeriveTemplates(self: *Resolver) !void {
        for (0..self.ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (self.ast.declTag(d) != .template_impl) continue;
            const trait = self.declReachedBy(self.ast.declTrait(d));
            if (trait == DeclId.none) continue;

            const gop = try self.templates.getOrPut(self.gpa, trait);
            if (gop.found_existing) {
                try self.sink.addError(
                    .t_template,
                    self.ast.fileOfDecl(d),
                    self.ast.tokenSpan(self.ast.declTrait(d)),
                    "a trait declares one structural template",
                    "another template already targets this trait",
                );
                continue;
            }
            gop.value_ptr.* = d;
        }

        for (0..self.ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            const request = self.ast.deriveRequestTraitRange(d);
            if (request.len() == 0) continue;
            for (self.ast.derive_traits[request.start..request.end]) |entry| {
                const trait = self.declReachedBy(entry.ref.name);
                if (trait == DeclId.none or self.templates.contains(trait)) continue;
                try self.sink.addError(
                    .t_derive,
                    self.ast.fileOf(entry.ref.name),
                    self.ast.tokenSpan(entry.ref.name),
                    "declare `template impl` in the trait's module, or write the implementation by hand",
                    "this trait has no structural template",
                );
            }
        }
    }

    const ExpansionPlan = struct {
        derive: DeclId,
        derive_trait: node.DeriveTraitId,
        trait_token: TokenId,
        target: DeclId,
        template: DeclId,
        module: ModuleId,
        import_targets: []const ModuleId,
        implementation: GeneratedImplementationId,
        requirements_range: ComponentRequirementRange,
        requirements: []const PendingComponentRequirement,
        generated_file: u32,
        members: []const TemplateMemberPlan,
        reflection_members: []const ReflectionMemberPlan,
    };

    const GeneratedImportPlan = struct {
        target: ModuleId,
        syntax: []const u8,
        alias: []const u8,
    };

    const SourceReplacements = std.AutoHashMapUnmanaged(BindingId, []const u8);
    const SourceAliasOrdinals = std.AutoHashMapUnmanaged(u64, void);
    const SourceAliasSuccessors = std.AutoHashMapUnmanaged(u64, u64);

    const PendingComponentRequirement = struct {
        requirement: node.TemplateRequirementId,
        bound: expanded_mod.RequirementBoundOrdinal,
        case: expanded_mod.CaseOrdinal,
        component: expanded_mod.ComponentOrdinal,
    };

    const PendingRequirements = struct {
        rows: []const PendingComponentRequirement,
        component_count: u32,
        bound_count: u32,
    };

    const ExpansionReservation = struct {
        implementation: GeneratedImplementationId,
        requirements: ComponentRequirementRange,
        generated_file: u32,
    };

    const ExpansionCapacity = struct {
        source_domain_end: u32,
        generated_file_end: u32,
        implementation_count: u32 = 0,
        requirement_count: u32 = 0,

        fn reserve(
            self: *ExpansionCapacity,
            source_bytes: usize,
            component_count: u32,
            bound_count: u32,
        ) ?ExpansionReservation {
            if (self.implementation_count == std.math.maxInt(u32)) return null;
            const bytes = std.math.cast(u32, source_bytes) orelse return null;
            const source_reserve = std.math.add(u32, bytes, 1) catch return null;
            const source_domain_end = std.math.add(u32, self.source_domain_end, source_reserve) catch return null;
            const generated_file_end = std.math.add(u32, self.generated_file_end, 1) catch return null;
            const requirement_count = std.math.mul(u32, component_count, bound_count) catch return null;
            const requirement_end = std.math.add(u32, self.requirement_count, requirement_count) catch return null;
            const implementation_count = std.math.add(u32, self.implementation_count, 1) catch return null;

            const reservation = ExpansionReservation{
                .implementation = .at(self.implementation_count),
                .requirements = .{ .start = self.requirement_count, .end = requirement_end },
                .generated_file = self.generated_file_end,
            };
            self.* = .{
                .source_domain_end = source_domain_end,
                .generated_file_end = generated_file_end,
                .implementation_count = implementation_count,
                .requirement_count = requirement_end,
            };
            return reservation;
        }
    };

    const PendingOriginSegment = struct {
        generated_file: u32,
        span: Span,
        derive_trait: node.DeriveTraitId,
        origin: expanded_mod.Origin,
    };

    const TemplatePlan = struct {
        template: DeclId,
        members: []const TemplateMemberPlan,
        free_references: []const []const TemplateFreeReference,
        reflection_members: []const ReflectionMemberPlan,
        valid: bool,
    };

    const TemplateFreeReference = struct {
        at: TokenId,
        declaration: DeclId,
        member: BindingId,
        /// Reached through the prelude rather than declared or imported by
        /// the template's module.
        prelude: bool,
    };

    const TemplatePlans = struct {
        items: std.ArrayList(TemplatePlan) = .empty,
        by_trait: std.AutoHashMapUnmanaged(DeclId, u32) = .empty,

        fn deinit(self: *TemplatePlans, gpa: std.mem.Allocator) void {
            for (self.items.items) |plan| {
                gpa.free(plan.members);
                for (plan.free_references) |references| gpa.free(references);
                gpa.free(plan.free_references);
                for (plan.reflection_members) |*reflection_member| reflection_member.deinit(gpa);
                gpa.free(plan.reflection_members);
            }
            self.items.deinit(gpa);
            self.by_trait.deinit(gpa);
        }

        fn get(self: *const TemplatePlans, trait: DeclId) ?*const TemplatePlan {
            const at = self.by_trait.get(trait) orelse return null;
            return &self.items.items[at];
        }
    };

    fn largestAstDomainEnd(ast: *const Ast) ?u32 {
        var largest = ast.parts.len;
        largest = @max(largest, ast.tokens.len);
        largest = @max(largest, ast.exprs.len);
        largest = @max(largest, ast.stmts.len);
        largest = @max(largest, ast.blocks.len);
        largest = @max(largest, ast.block_stmts.len);
        largest = @max(largest, ast.decls.len);
        largest = @max(largest, ast.params.len);
        largest = @max(largest, ast.type_params.len);
        largest = @max(largest, ast.bounds.len);
        largest = @max(largest, ast.where_predicates.len);
        largest = @max(largest, ast.derive_traits.len);
        largest = @max(largest, ast.template_requirements.len);
        largest = @max(largest, ast.type_refs.len);
        largest = @max(largest, ast.callable_types.len);
        largest = @max(largest, ast.variants.len);
        largest = @max(largest, ast.fields.len);
        largest = @max(largest, ast.extra.len);
        largest = @max(largest, ast.call_names.len);
        return std.math.cast(u32, largest);
    }

    fn nextGeneratedFile(ast: *const Ast) ?u32 {
        var next: u32 = 0;
        for (ast.parts) |part| {
            next = @max(next, std.math.add(u32, @intFromEnum(part.file), 1) catch return null);
        }
        return next;
    }

    fn caseCount(ast: *const Ast, target: DeclId) ?u32 {
        return switch (ast.declTag(target)) {
            .struct_, .newtype => 1,
            .enum_ => std.math.cast(u32, ast.declVariants(target).len),
            else => null,
        };
    }

    fn componentsInCase(ast: *const Ast, target: DeclId, case_index: u32) ?u32 {
        return switch (ast.declTag(target)) {
            .struct_ => std.math.cast(u32, ast.declFields(target).len),
            .newtype => 1,
            .enum_ => std.math.cast(u32, ast.variantFields(ast.declVariants(target)[case_index]).len),
            else => null,
        };
    }

    fn componentCount(ast: *const Ast, target: DeclId) ?u32 {
        const cases = caseCount(ast, target) orelse return null;
        var total: u32 = 0;
        for (0..cases) |case_index| {
            total = std.math.add(
                u32,
                total,
                componentsInCase(ast, target, @intCast(case_index)) orelse return null,
            ) catch return null;
        }
        return total;
    }

    fn buildPendingRequirements(self: *Resolver, target: DeclId, template: DeclId) !PendingRequirements {
        const requirement_range = self.program.ast.templateRequirementRange(template);
        if (requirement_range.end < requirement_range.start or
            requirement_range.end > self.program.ast.template_requirements.len)
        {
            return error.Overflow;
        }
        const requirements = self.program.ast.templateRequirements(template);
        const component_count = componentCount(&self.program.ast, target) orelse return error.Overflow;
        var bound_count: u32 = 0;
        for (requirements) |requirement| {
            bound_count = try std.math.add(u32, bound_count, requirement.bounds.len());
        }
        const row_count = try std.math.mul(u32, component_count, bound_count);

        var rows: std.ArrayList(PendingComponentRequirement) = .empty;
        defer rows.deinit(self.gpa);
        try rows.ensureTotalCapacity(self.gpa, row_count);
        const case_count = caseCount(&self.program.ast, target) orelse return error.Overflow;
        for (0..case_count) |case_index| {
            const case: expanded_mod.CaseOrdinal = @enumFromInt(
                std.math.cast(u32, case_index) orelse return error.Overflow,
            );
            const components = componentsInCase(&self.program.ast, target, @intCast(case_index)) orelse
                return error.Overflow;
            for (0..components) |component_index| {
                const component: expanded_mod.ComponentOrdinal = @enumFromInt(
                    std.math.cast(u32, component_index) orelse return error.Overflow,
                );
                for (requirements, 0..) |requirement, requirement_offset| {
                    const requirement_index = try std.math.add(
                        u32,
                        requirement_range.start,
                        std.math.cast(u32, requirement_offset) orelse return error.Overflow,
                    );
                    for (self.program.ast.boundsIn(requirement.bounds), 0..) |_, bound_index| {
                        try rows.append(self.gpa, .{
                            .requirement = .at(requirement_index),
                            .bound = @enumFromInt(std.math.cast(u32, bound_index) orelse return error.Overflow),
                            .case = case,
                            .component = component,
                        });
                    }
                }
            }
        }
        std.debug.assert(rows.items.len == row_count);
        return .{
            .rows = try rows.toOwnedSlice(self.gpa),
            .component_count = component_count,
            .bound_count = bound_count,
        };
    }

    fn planTemplateRequirements(self: *Resolver, template: DeclId) !void {
        const previous_generic = self.generic;
        defer self.generic = previous_generic;
        self.generic = template;

        var has_target_shape = false;
        for (self.program.ast.templateRequirements(template)) |requirement| {
            if (requirement.kind == .target) {
                if (has_target_shape) try self.sink.addError(.t_template, self.program.ast.fileOf(requirement.selector), self.program.ast.tokenSpan(requirement.selector), "state one target shape", "a template declares its target shape once");
                has_target_shape = true;
            }
            var invalid_shape = false;
            for (self.program.ast.boundsIn(requirement.bounds)) |bound| {
                if (bound.kind == .callable) {
                    invalid_shape = true;
                    try self.useCallableTypeIn(
                        self.program.ast.callableTypeById(bound.callable),
                        .template_requirement,
                    );
                    continue;
                }

                if (bound.named.path.len() != 0) {
                    if (try self.implTraitRef(bound.named) == .none) invalid_shape = true;
                    for (self.program.ast.typeArgs(bound.named.args)) |argument| {
                        if (!self.templateRequirementTypeIsSupported(argument)) invalid_shape = true;
                        try self.useRefIn(argument, .template_requirement);
                    }
                    continue;
                }

                const named = self.traitNamed(bound.named.name);
                const declared: ?DeclId = if (named == .none) null else self.bindings.items[named.index()].decl;
                switch (boundNames(&self.program.ast, bound.named.name, declared)) {
                    .trait => {
                        self.bindings.items[named.index()].used = true;
                        self.reached(bound.named.name, named);
                    },
                    .capability, .integer => invalid_shape = true,
                    .unknown => _ = try self.implTraitToken(bound.named.name),
                }

                for (self.program.ast.typeArgs(bound.named.args)) |argument| {
                    if (!self.templateRequirementTypeIsSupported(argument)) invalid_shape = true;
                    try self.useRefIn(argument, .template_requirement);
                }
            }
            if (invalid_shape) {
                try self.sink.addError(
                    .t_template,
                    self.program.ast.fileOf(requirement.reflect),
                    self.program.ast.tokenSpan(requirement.reflect),
                    "a component requirement names traits using closed types or template parameters",
                    "this requirement contains a capability bound, callable, reflection descriptor or unsupported parameter",
                );
            }
        }
    }

    fn templateRequirementTypeIsSupported(self: *Resolver, ref: node.TypeRef) bool {
        if (ref.kind == .callable) {
            const callable = self.program.ast.callableType(ref);
            for (self.program.ast.params[callable.params.start..callable.params.end]) |param| {
                if (!self.templateRequirementTypeIsSupported(param.written)) return false;
            }
            return self.templateRequirementTypeIsSupported(callable.result);
        }
        if (ref.kind == .named and ref.name != .none) {
            if (namesSelf(&self.program.ast, ref.name)) return false;
            if (self.program.ast.tokenTag(ref.name) == .keyword_reflect) return false;
            if (self.typeParamInScope(ref.name) != null and self.ast.declTag(self.generic) != .template_impl) return false;
        }
        if (ref.kind == .selection and !self.templateRequirementTypeIsSupported(self.ast.selectionBase(ref))) return false;
        for (self.program.ast.typeArgs(ref.args)) |argument| {
            if (!self.templateRequirementTypeIsSupported(argument)) return false;
        }
        return true;
    }

    /// Records every value-parameter reference in one template member once.
    /// Rendering later uses these typed references to distinguish a parameter
    /// whose uses survived expansion from one whose reflected region vanished;
    /// it never searches generated text for a spelling.
    fn templateParameterPlans(
        self: *Resolver,
        member_decl: DeclId,
        references: []const BindingId,
        token_start: u32,
    ) ![]ParameterPlan {
        const params = self.program.ast.declParams(member_decl);
        const counts = try self.gpa.alloc(usize, params.len);
        defer self.gpa.free(counts);
        @memset(counts, 0);

        for (references) |binding| {
            if (binding == .none) continue;
            const held = self.bindings.items[binding.index()];
            if (held.kind != .parameter or held.decl != member_decl) continue;
            if (held.param_index >= params.len) return error.InvalidGeneratedDeclarationCount;
            counts[held.param_index] = try std.math.add(usize, counts[held.param_index], 1);
        }

        var names = try self.program.ast.parameterNames(self.gpa, params);
        defer names.deinit(self.gpa);
        var contract_roots: std.ArrayList(struct { parameter: u32, at: TokenId }) = .empty;
        defer contract_roots.deinit(self.gpa);
        for (self.program.ast.declContracts(member_decl)) |contract| {
            const paths = [_]node.ContractPath{ contract.source, if (contract.kind == .retains) contract.destination else .empty };
            for (paths) |path| {
                const head = path.root;
                if (head == .none) continue;
                const parameter = names.get(self.program.ast.tokenName(head)) orelse continue;
                try contract_roots.append(self.gpa, .{ .parameter = parameter, .at = head });
                counts[parameter] = try std.math.add(usize, counts[parameter], 1);
            }
        }

        const plans = try self.gpa.alloc(ParameterPlan, params.len);
        var initialized: usize = 0;
        errdefer {
            for (plans[0..initialized]) |plan| self.gpa.free(plan.references);
            self.gpa.free(plans);
        }
        for (params, counts, 0..) |param, count, i| {
            plans[i] = .{
                .declaration = param.name,
                .references = try self.gpa.alloc(reflection.ParameterReference, count),
            };
            initialized += 1;
        }

        @memset(counts, 0);
        for (references, token_start..) |binding, token_index| {
            if (binding == .none) continue;
            const held = self.bindings.items[binding.index()];
            if (held.kind != .parameter or held.decl != member_decl) continue;
            const parameter_index = held.param_index;
            const at = counts[parameter_index];
            plans[parameter_index].references[at] = .{ .at = TokenId.at(@intCast(token_index)) };
            counts[parameter_index] += 1;
        }
        for (contract_roots.items) |root| {
            plans[root.parameter].references[counts[root.parameter]] = .{ .at = root.at, .contract = true };
            counts[root.parameter] += 1;
        }
        return plans;
    }

    /// Resolves and validates every template once, before any derive copies it.
    /// Member and signature maps are bounded by the one template and trait, and
    /// reference classification happens at ordinary lexical lookup sites.
    fn planTemplates(self: *Resolver, index: *const DeclIndex) !TemplatePlans {
        var out: TemplatePlans = .{};
        errdefer out.deinit(self.gpa);
        var entered_module: ?ModuleId = null;

        for (0..self.program.ast.declCount()) |i| {
            const template = DeclId.at(@intCast(i));
            if (self.program.ast.declTag(template) != .template_impl) continue;
            const trait = self.declReachedBy(self.program.ast.declTrait(template));
            if (trait == .none or self.templates.get(trait) != template) continue;

            const module = self.program.moduleOf(template);
            if (entered_module == null or entered_module.? != module) {
                try self.enter(module);
                entered_module = module;
            }
            const requirement_errors = self.sink.error_count;
            try self.planTemplateRequirements(template);
            const requirements_valid = self.sink.error_count == requirement_errors;
            const module_scope = self.visible.items.len;
            const members = index.ownedBy(self.program.ast.declName(template));
            const signatures = index.ownedBy(self.program.ast.declName(trait));
            const template_parameters = self.program.ast.declTypeParams(template);
            const template_arguments = self.program.ast.typeArgs(self.program.ast.declTraitArgs(template));
            var valid = self.program.moduleOf(trait) == module and
                self.program.ast.declTypeParams(trait).len == template_parameters.len and
                self.program.ast.declWherePredicates(template).len == 0 and
                template_arguments.len == template_parameters.len;
            if (valid) {
                for (template_arguments, template_parameters) |argument, parameter| {
                    if (argument.kind != .named or argument.args.len() != 0 or
                        argument.name == .none or self.program.ast.tokenName(argument.name) != self.program.ast.tokenName(parameter.name)) valid = false;
                }
            }
            if (!valid) {
                try self.refuseUnsupportedTemplate(template, "a template applies every parameter once in declaration order to its trait, with no trailing constraints");
            }

            var signatures_by_name: std.AutoHashMapUnmanaged(StringId, DeclId) = .empty;
            defer signatures_by_name.deinit(self.gpa);
            var signatures_valid = true;
            for (signatures) |signature| {
                if (self.program.ast.declTag(signature) != .function) {
                    signatures_valid = false;
                    continue;
                }
                const name = self.program.ast.tokenName(self.program.ast.declName(signature));
                const slot = try signatures_by_name.getOrPut(self.gpa, name);
                if (slot.found_existing) {
                    signatures_valid = false;
                } else {
                    slot.value_ptr.* = signature;
                }
            }

            var member_plans: std.ArrayList(TemplateMemberPlan) = .empty;
            defer member_plans.deinit(self.gpa);
            var matched: std.AutoHashMapUnmanaged(StringId, void) = .empty;
            defer matched.deinit(self.gpa);
            var members_valid = true;
            for (members) |template_member| {
                if (self.program.ast.declTag(template_member) != .function or
                    self.program.ast.declWherePredicates(template_member).len != 0)
                {
                    members_valid = false;
                    continue;
                }
                const name = self.program.ast.tokenName(self.program.ast.declName(template_member));
                const signature = signatures_by_name.get(name) orelse {
                    members_valid = false;
                    continue;
                };
                const match = try matched.getOrPut(self.gpa, name);
                if (match.found_existing) {
                    members_valid = false;
                    continue;
                }
                try member_plans.append(self.gpa, .{
                    .template = template,
                    .trait = trait,
                    .member = template_member,
                    .signature = signature,
                });
            }
            if (!signatures_valid or !members_valid or member_plans.items.len != signatures.len) {
                valid = false;
                try self.refuseUnsupportedTemplate(template, "the template supplies each function the trait declares exactly once");
            }

            var references_valid = true;
            var reference_plans: std.ArrayList([]const TemplateFreeReference) = .empty;
            defer reference_plans.deinit(self.gpa);
            errdefer for (reference_plans.items) |references| self.gpa.free(references);
            var reflection_plans: std.ArrayList(ReflectionMemberPlan) = .empty;
            defer reflection_plans.deinit(self.gpa);
            errdefer for (reflection_plans.items) |*plan| plan.deinit(self.gpa);
            for (member_plans.items) |member_plan| {
                const member_tokens = self.program.ast.declTokens(member_plan.member);
                const reference_bindings = try self.gpa.alloc(BindingId, member_tokens.len());
                defer self.gpa.free(reference_bindings);
                @memset(reference_bindings, .none);
                var reflection_context: ReflectionContext = .{
                    .template = template,
                    .member = member_plan.member,
                };
                defer reflection_context.deinit(self.gpa);
                self.template_validation = .{
                    .binding_floor = self.bindings.items.len,
                    .token_start = member_tokens.start.index(),
                    .references = reference_bindings,
                    .reflection = &reflection_context,
                };
                self.generic = member_plan.member;
                self.impl_scope = template;
                self.trait_scope = trait;
                try self.refuseTypeParametersOfOneName(member_plan.member);
                try self.checkBounds(member_plan.member);
                for (self.program.ast.declTypeParams(member_plan.member)) |param| try self.refuseCallablePhantom(param);
                for (self.program.ast.declParams(member_plan.member)) |param| try self.useRef(param.written);
                try self.useRef(self.program.ast.declReturnRef(member_plan.member));
                try self.reportUnusedTypeParams(member_plan.member);
                self.generic = .none;
                try self.function(member_plan.member, module_scope);
                try self.finishTemplateClosureUses(&reflection_context);
                const validation = self.template_validation.?;
                self.template_validation = null;
                self.impl_scope = .none;
                self.trait_scope = .none;
                if (!validation.reflection.valid) references_valid = false;

                const parameter_plans = try self.templateParameterPlans(
                    member_plan.member,
                    validation.references,
                    validation.token_start,
                );
                var parameters_handed_off = false;
                defer if (!parameters_handed_off) {
                    for (parameter_plans) |plan| self.gpa.free(plan.references);
                    self.gpa.free(parameter_plans);
                };

                var type_references: std.ArrayList(reflection.TypeParameterReference) = .empty;
                defer type_references.deinit(self.gpa);
                var member_references: std.ArrayList(TemplateFreeReference) = .empty;
                defer member_references.deinit(self.gpa);
                for (validation.references, validation.token_start..) |binding, token_index| {
                    if (binding == .none) continue;
                    const held = self.bindings.items[binding.index()];
                    if (binding.index() >= validation.binding_floor) continue;
                    if (held.kind == .parameter and held.decl == member_plan.member) continue;
                    if (held.kind == .type_parameter and held.decl == template) {
                        try type_references.append(self.gpa, .{ .at = TokenId.at(@intCast(token_index)), .parameter = held.param_index, .selection_base = reflection_context.selection_bases.contains(TokenId.at(@intCast(token_index))) });
                        continue;
                    }
                    const reproducible = held.kind != .module and held.decl != .none;
                    const broad_enough = @intFromEnum(held.reach) >= @intFromEnum(reachForVisibility(
                        self.program.ast.declVisibility(trait),
                    ));
                    if (!reproducible or !broad_enough) {
                        references_valid = false;
                        const at = TokenId.at(@intCast(token_index));
                        try self.sink.addError(
                            .t_template,
                            self.program.ast.fileOf(at),
                            self.program.ast.tokenSpan(at),
                            "re-export this name from the trait's module with at least the trait's visibility",
                            "a template free reference must be reproducible wherever the trait can be named",
                        );
                        continue;
                    }
                    try member_references.append(self.gpa, .{
                        .at = TokenId.at(@intCast(token_index)),
                        .declaration = held.decl,
                        .member = binding,
                        .prelude = held.ambient,
                    });
                }
                const owned_references = try member_references.toOwnedSlice(self.gpa);
                reference_plans.append(self.gpa, owned_references) catch |err| {
                    self.gpa.free(owned_references);
                    return err;
                };
                const owned_type_references = try type_references.toOwnedSlice(self.gpa);
                var reflection_plan = reflection_context.finish(self.gpa, parameter_plans) catch |err| {
                    self.gpa.free(owned_type_references);
                    return err;
                };
                reflection_plan.type_parameters = owned_type_references;
                parameters_handed_off = true;
                reflection_plans.append(self.gpa, reflection_plan) catch |err| {
                    reflection_plan.deinit(self.gpa);
                    return err;
                };
            }
            valid = valid and references_valid and requirements_valid;

            const owned_members = try member_plans.toOwnedSlice(self.gpa);
            var members_handed_off = false;
            errdefer if (!members_handed_off) self.gpa.free(owned_members);
            const owned_references = try reference_plans.toOwnedSlice(self.gpa);
            var references_handed_off = false;
            errdefer if (!references_handed_off) {
                for (owned_references) |references| self.gpa.free(references);
                self.gpa.free(owned_references);
            };
            const owned_reflection = try reflection_plans.toOwnedSlice(self.gpa);
            var reflection_handed_off = false;
            errdefer if (!reflection_handed_off) {
                for (owned_reflection) |*plan| plan.deinit(self.gpa);
                self.gpa.free(owned_reflection);
            };
            const at: u32 = @intCast(out.items.items.len);
            try out.items.append(self.gpa, .{
                .template = template,
                .members = owned_members,
                .free_references = owned_references,
                .reflection_members = owned_reflection,
                .valid = valid,
            });
            members_handed_off = true;
            references_handed_off = true;
            reflection_handed_off = true;
            try out.by_trait.put(self.gpa, trait, at);
        }
        return out;
    }

    /// Copy source while substituting resolved module aliases and target type
    /// parameters. Binding identity preserves shadowing across source files.
    fn appendSourceReplacingBindings(
        self: *const Resolver,
        out: *std.ArrayList(u8),
        source: []const u8,
        start: u32,
        end: u32,
        first_token: u32,
        token_end: u32,
        replacements: *const SourceReplacements,
    ) !void {
        const ast = &self.program.ast;
        if (end < start or end > source.len) return error.InvalidGeneratedSourceBounds;

        var cursor = start;
        for (first_token..token_end) |i| {
            if (i >= self.written.items.len) continue;
            const replacement = replacements.get(self.written.items[i]) orelse continue;
            const span = ast.tokenSpan(TokenId.at(@intCast(i)));
            if (span.start < cursor or span.end > end) return error.InvalidGeneratedSourceBounds;
            try out.appendSlice(self.gpa, source[cursor..span.start]);
            try out.appendSlice(self.gpa, replacement);
            cursor = span.end;
        }
        try out.appendSlice(self.gpa, source[cursor..end]);
    }

    fn appendSourceBetweenReplacingBindings(
        self: *const Resolver,
        out: *std.ArrayList(u8),
        after: TokenId,
        before: TokenId,
        replacements: *const SourceReplacements,
    ) !void {
        const ast = &self.program.ast;
        const from = ast.partOf(after);
        const to = ast.partOf(before);
        if (from.file != to.file) return error.InvalidGeneratedSourceBounds;
        return self.appendSourceReplacingBindings(
            out,
            from.source,
            ast.tokenSpan(after).end,
            ast.tokenSpan(before).start,
            after.index() + 1,
            before.index(),
            replacements,
        );
    }

    fn appendSourceRangeReplacingBindings(
        self: *const Resolver,
        out: *std.ArrayList(u8),
        range: token.TokenRange,
        replacements: *const SourceReplacements,
    ) !void {
        if (range.len() == 0) return error.InvalidGeneratedSourceBounds;
        const ast = &self.program.ast;
        const first = ast.partOf(range.start);
        const last = ast.partOf(TokenId.at(range.end.index() - 1));
        if (first.file != last.file) return error.InvalidGeneratedSourceBounds;
        const span = ast.rangeSpan(range);
        if (span.end > first.source.len) return error.InvalidGeneratedSourceBounds;
        return self.appendSourceReplacingBindings(
            out,
            first.source,
            span.start,
            span.end,
            range.start.index(),
            range.end.index(),
            replacements,
        );
    }

    /// A parsed trait argument ends before the following separator. Preserve
    /// its source spelling while omitting list punctuation and trailing trivia.
    fn traitArgumentRange(self: *const Resolver, entry: node.DeriveTrait, index: usize) token.TokenRange {
        const ast = &self.program.ast;
        const arguments = ast.typeArgs(entry.ref.args);
        const start = arguments[index].at;
        var end = if (index + 1 < arguments.len) arguments[index + 1].at.index() else entry.tokens.end.index();
        while (end > start.index() and ast.tokenTag(TokenId.at(end - 1)).isTrivia()) end -= 1;
        if (end > start.index()) end -= 1;
        while (end > start.index() and ast.tokenTag(TokenId.at(end - 1)).isTrivia()) end -= 1;
        if (index + 1 == arguments.len and end > start.index() and ast.tokenTag(TokenId.at(end - 1)) == .comma) end -= 1;
        while (end > start.index() and ast.tokenTag(TokenId.at(end - 1)).isTrivia()) end -= 1;
        return .{ .start = start, .end = TokenId.at(end) };
    }

    /// Finds the next ordinal no source identifier reserves. The first query
    /// crossing a consecutive reserved run records every ordinal's free
    /// successor; later modules cross that run in one hash lookup. Across an
    /// expansion, each source-owned ordinal is therefore scanned once.
    fn sourceFreeAliasOrdinal(
        self: *Resolver,
        start: u64,
        source_alias_ordinals: *const SourceAliasOrdinals,
        source_alias_successors: *SourceAliasSuccessors,
        skipped: *std.ArrayList(u64),
    ) !u64 {
        skipped.clearRetainingCapacity();
        var ordinal = start;
        while (source_alias_ordinals.contains(ordinal)) {
            if (source_alias_successors.get(ordinal)) |successor| {
                ordinal = successor;
                break;
            }
            try skipped.append(self.gpa, ordinal);
            ordinal +%= 1;
            if (ordinal == start) return error.Overflow;
        }
        for (skipped.items) |blocked| {
            try source_alias_successors.put(self.gpa, blocked, ordinal);
        }
        return ordinal;
    }

    /// Chooses an alias absent from both source and the target module. Source
    /// runs have the amortised bound above, and a module-local collision moves
    /// that module's cursor forward, so each local candidate is probed once.
    fn generatedAlias(
        self: *Resolver,
        source_alias_ordinals: *const SourceAliasOrdinals,
        source_alias_successors: *SourceAliasSuccessors,
        source_alias_skip_path: *std.ArrayList(u64),
        occupied: *std.StringHashMapUnmanaged(void),
        generated_aliases: *std.ArrayList([]u8),
        next_ordinal: *u64,
    ) ![]const u8 {
        var first_candidate: ?u64 = null;
        while (true) {
            const ordinal = try self.sourceFreeAliasOrdinal(
                next_ordinal.*,
                source_alias_ordinals,
                source_alias_successors,
                source_alias_skip_path,
            );
            if (first_candidate) |first| {
                if (ordinal == first) return error.Overflow;
            } else {
                first_candidate = ordinal;
            }
            next_ordinal.* = ordinal +% 1;
            const candidate = try std.fmt.allocPrint(self.gpa, "_linea_trait_{d}", .{ordinal});
            if (occupied.contains(candidate)) {
                self.gpa.free(candidate);
                continue;
            }
            generated_aliases.append(self.gpa, candidate) catch |err| {
                self.gpa.free(candidate);
                return err;
            };
            try occupied.put(self.gpa, candidate, {});
            return candidate;
        }
    }

    fn ensureGeneratedImport(
        self: *Resolver,
        module: ModuleId,
        target: ModuleId,
        source_alias_ordinals: *const SourceAliasOrdinals,
        source_alias_successors: *SourceAliasSuccessors,
        source_alias_skip_path: *std.ArrayList(u64),
        occupied: *std.StringHashMapUnmanaged(void),
        generated_aliases: *std.ArrayList([]u8),
        next_alias_ordinal: *u64,
        imports: *std.ArrayList(GeneratedImportPlan),
        imports_by_target: *std.AutoHashMapUnmanaged(ModuleId, u32),
    ) !?[]const u8 {
        if (imports_by_target.get(target)) |at| return imports.items[at].alias;
        const route = self.program.importRoute(module, target) orelse return null;
        const alias = try self.generatedAlias(
            source_alias_ordinals,
            source_alias_successors,
            source_alias_skip_path,
            occupied,
            generated_aliases,
            next_alias_ordinal,
        );
        const at = std.math.cast(u32, imports.items.len) orelse return error.Overflow;
        try imports.append(self.gpa, .{
            .target = route.target,
            .syntax = route.syntax,
            .alias = alias,
        });
        try imports_by_target.put(self.gpa, target, at);
        return alias;
    }

    /// The module declaring a prelude name a template writes, where the
    /// target's module shadows that name; null where the name is not a
    /// prelude one or the target's module reaches the same binding by it.
    fn preludeReferenceShadowed(self: *const Resolver, module: ModuleId, reference: TemplateFreeReference) ?ModuleId {
        if (!reference.prelude) return null;
        const declaring = self.program.moduleOf(reference.declaration);
        if (declaring == module) return null;
        const name = self.bindings.items[reference.member.index()].name;
        if (self.here_named.get(hereKey(module, name)) == reference.member) return null;
        return declaring;
    }

    /// The declaration a standalone derive request targets: the prelude's
    /// tuple declaration for a tuple head, and otherwise the declared type
    /// its name reached. Null where the head reached nothing, which
    /// `implTarget` reported, or where it names no declaration, which is
    /// reported here.
    fn deriveTarget(self: *Resolver, derive: DeclId) !?DeclId {
        const ast = &self.program.ast;
        const head = ast.declHead(derive);
        // Reported where it was written, as an implementation's refused head
        // is; it targets nothing, and nothing more is said about it.
        if (headRefusedByTheParser(head)) return null;
        if (head.kind == .tuple) return self.tupleDecl(head);
        const binding = self.writtenBindingAt(ast.declName(derive));
        const not_a_declaration = "derive targets a concrete declaration, not a primitive or another kind of name";
        if (binding == BindingId.none) {
            // Unit reaches no binding, and is no declaration either.
            if (ast.tokenTag(head.at) == .l_paren) try self.refuseUnsupportedDerive(derive, not_a_declaration);
            return null;
        }
        const held = self.bindings.items[binding.index()];
        if (held.kind != .declared_type or held.decl == DeclId.none) {
            try self.refuseUnsupportedDerive(derive, not_a_declaration);
            return null;
        }
        return held.decl;
    }

    test "a derive request whose head the parser refused is reported once" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        for ([_][]const u8{ "(A)", "(A,)", "(A, B, C, D, E, F, G, H, I)" }) |target| {
            const text = try std.fmt.allocPrint(gpa, "trait Marker {{}}\ntemplate impl Marker {{}}\nderive[A, B, C, D, E, F, G, H, I] Marker for {s}\nfn main() -> UInt8 {{ 0 }}\n", .{target});
            const result = try resolveWithPrelude(gpa, text, "pub struct Tuple2[A, B] { _0: A, _1: B }\n");
            try testing.expectEqual(@as(u32, 1), result.errors);
            try testing.expectEqual(@as(u32, 0), result.unsupported_derives);
            try testing.expectEqual(@as(u32, 0), result.undefined);
        }
    }

    test "a derive request for unit or a primitive targets no declaration" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        for ([_][]const u8{ "()", "UInt8" }) |target| {
            const text = try std.fmt.allocPrint(gpa, "trait Marker {{}}\ntemplate impl Marker {{}}\nderive Marker for {s}\nfn main() -> UInt8 {{ 0 }}\n", .{target});
            const result = try resolveWithPrelude(gpa, text, "");
            try testing.expectEqual(@as(u32, 1), result.unsupported_derives);
        }
    }

    fn deriveTargetRange(self: *const Resolver, derive: DeclId) token.TokenRange {
        const ast = &self.program.ast;
        const range = ast.declTokens(derive);
        var end = range.end.index();
        while (end > range.start.index() and ast.tokenTag(TokenId.at(end - 1)).isTrivia()) end -= 1;
        if (end > range.start.index() and ast.tokenTag(TokenId.at(end - 1)) == .semicolon) end -= 1;
        return .{ .start = ast.declName(derive), .end = TokenId.at(end) };
    }

    fn attachedHeaderEnd(self: *const Resolver, target: DeclId) TokenId {
        const ast = &self.program.ast;
        const range = ast.declTokens(target);
        for (ast.declName(target).index() + 1..range.end.index()) |i| {
            const at = TokenId.at(@intCast(i));
            if (ast.tokenTag(at) == .l_brace) return at;
        }
        return range.end;
    }

    fn attachedHeaderRange(self: *const Resolver, target: DeclId) token.TokenRange {
        return .{ .start = TokenId.at(self.program.ast.declName(target).index() + 1), .end = self.attachedHeaderEnd(target) };
    }

    fn attachedTypeParameterRange(self: *const Resolver, target: DeclId) token.TokenRange {
        const ast = &self.program.ast;
        var start = ast.declName(target).index() + 1;
        const limit = ast.declTokens(target).end.index();
        while (start < limit and ast.tokenTag(TokenId.at(start)).isTrivia()) start += 1;
        if (start >= limit or ast.tokenTag(TokenId.at(start)) != .l_bracket) return .empty;
        var end = start + 1;
        var depth: u32 = 1;
        while (end < limit and depth != 0) : (end += 1) {
            switch (ast.tokenTag(TokenId.at(end))) {
                .l_bracket => depth += 1,
                .r_bracket => depth -= 1,
                else => {},
            }
        }
        return .{ .start = TokenId.at(start), .end = TokenId.at(end) };
    }

    /// The tokens of each default `= Type` in a target's parameter list, which
    /// an implementation header cannot carry: it names the type's parameters,
    /// and an omitted argument is no parameter.
    ///
    /// **Bound:** the tokens of the target's parameter list.
    fn attachedDefaultRanges(self: *Resolver, target: DeclId, out: *std.ArrayList(token.TokenRange)) !void {
        const range = self.attachedTypeParameterRange(target);
        if (range.len() == 0) return;
        const ast = &self.program.ast;
        var depth: i32 = 0;
        var started: ?u32 = null;
        for (range.start.index()..range.end.index()) |i| {
            const tag = ast.tokenTag(TokenId.at(@intCast(i)));
            if (started) |from| {
                if (depth == 1 and (tag == .comma or tag == .r_bracket)) {
                    try out.append(self.gpa, .{ .start = TokenId.at(from), .end = TokenId.at(@intCast(i)) });
                    started = null;
                }
            } else if (tag == .equal and depth == 1) {
                started = @intCast(i);
            }
            depth += tag.nesting();
        }
    }

    /// The token ranges of a target's header that an implementation of it
    /// copies: the header less its parameters' defaults.
    fn attachedHeaderCopies(self: *Resolver, target: DeclId, out: *std.ArrayList(token.TokenRange)) !void {
        var defaults: std.ArrayList(token.TokenRange) = .empty;
        defer defaults.deinit(self.gpa);
        try self.attachedDefaultRanges(target, &defaults);
        const header = self.attachedHeaderRange(target);
        var from = header.start;
        for (defaults.items) |dropped| {
            try out.append(self.gpa, .{ .start = from, .end = dropped.start });
            from = dropped.end;
        }
        try out.append(self.gpa, .{ .start = from, .end = header.end });
    }

    /// The type's parameter list as an implementation header declares it.
    /// `phantom` describes the type's representation and a default belongs to
    /// the type's declaration, so an implementation cannot write either; each
    /// run between them is copied as written.
    fn appendAttachedParameters(self: *Resolver, text: *std.ArrayList(u8), target: DeclId, replacements: *const SourceReplacements) !void {
        const range = self.attachedTypeParameterRange(target);
        if (range.len() == 0) return;
        const ast = &self.program.ast;
        var defaults: std.ArrayList(token.TokenRange) = .empty;
        defer defaults.deinit(self.gpa);
        try self.attachedDefaultRanges(target, &defaults);
        var next_default: usize = 0;
        var run_start = range.start.index();
        var i = range.start.index();
        while (i < range.end.index()) : (i += 1) {
            const dropped_default = next_default < defaults.items.len and i == defaults.items[next_default].start.index();
            const dropped = dropped_default or ast.tokenTag(TokenId.at(@intCast(i))) == .keyword_phantom;
            if (!dropped) continue;
            if (i > run_start) try self.appendSourceRangeReplacingBindings(text, .{ .start = TokenId.at(run_start), .end = TokenId.at(@intCast(i)) }, replacements);
            if (dropped_default) {
                i = defaults.items[next_default].end.index() - 1;
                next_default += 1;
            }
            run_start = @intCast(i + 1);
        }
        if (range.end.index() > run_start) try self.appendSourceRangeReplacingBindings(text, .{ .start = TokenId.at(run_start), .end = range.end }, replacements);
    }

    /// Writes the target applied to its own parameters, then its written
    /// constraints followed by the predicates the derive adds for its field
    /// types.
    fn appendAttachedTarget(
        self: *Resolver,
        text: *std.ArrayList(u8),
        target: DeclId,
        replacements: *const SourceReplacements,
        derived_predicates: []const u8,
    ) !void {
        const ast = &self.program.ast;
        try text.appendSlice(self.gpa, ast.tokenText(ast.declName(target)));
        const params = ast.declTypeParams(target);
        if (params.len != 0) {
            try text.append(self.gpa, '[');
            for (params, 0..) |parameter, i| {
                if (i != 0) try text.appendSlice(self.gpa, ", ");
                try text.appendSlice(self.gpa, ast.tokenText(parameter.name));
            }
            try text.append(self.gpa, ']');
        }
        const written = ast.declWhereToken(target) != .none;
        if (written) {
            try text.append(self.gpa, ' ');
            try self.appendSourceRangeReplacingBindings(text, .{ .start = ast.declWhereToken(target), .end = self.attachedHeaderEnd(target) }, replacements);
            while (text.items.len > 0 and std.ascii.isWhitespace(text.items[text.items.len - 1])) text.items.len -= 1;
        }
        if (derived_predicates.len == 0) return;
        if (!written) {
            try text.appendSlice(self.gpa, " where ");
        } else if (text.items[text.items.len - 1] == ',') {
            try text.append(self.gpa, ' ');
        } else {
            try text.appendSlice(self.gpa, ", ");
        }
        try text.appendSlice(self.gpa, derived_predicates);
    }

    /// Says whether a template requires anything of its target's components.
    fn templateBoundsComponents(ast: *const Ast, template: DeclId) bool {
        for (ast.templateRequirements(template)) |requirement| {
            if (requirement.kind == .components and requirement.bounds.len() != 0) return true;
        }
        return false;
    }

    /// Says whether a component's written type names one of the target's own
    /// type parameters.
    ///
    /// **Bound:** the type references one written component type holds.
    fn namesTargetParameter(self: *const Resolver, target: DeclId, ref: node.TypeRef) bool {
        const ast = &self.program.ast;
        switch (ref.kind) {
            .callable => {
                const callable = ast.callableType(ref);
                for (ast.params[callable.params.start..callable.params.end]) |param| {
                    if (self.namesTargetParameter(target, param.written)) return true;
                }
                return self.namesTargetParameter(target, callable.result);
            },
            .selection => if (self.namesTargetParameter(target, ast.selectionBase(ref))) return true,
            .named => if (ref.name != .none and ref.name.index() < self.written.items.len) {
                const binding = self.written.items[ref.name.index()];
                if (binding != .none) {
                    const held = self.bindings.items[binding.index()];
                    if (held.kind == .type_parameter and held.decl == target) return true;
                }
            },
            .array, .borrow, .grouped, .tuple => {},
        }
        for (ast.typeArgs(ref.args)) |argument| {
            if (self.namesTargetParameter(target, argument)) return true;
        }
        return false;
    }

    /// Returns the bracketed argument list written after a bound's trait name,
    /// or an empty range where the bound writes none.
    fn boundArgumentRange(self: *const Resolver, name: TokenId) token.TokenRange {
        const ast = &self.program.ast;
        const limit = ast.tokenCount();
        var start = name.index() + 1;
        while (start < limit and ast.tokenTag(TokenId.at(start)).isTrivia()) start += 1;
        if (start >= limit or ast.tokenTag(TokenId.at(start)) != .l_bracket) return .empty;
        var end = start + 1;
        var depth: u32 = 1;
        while (end < limit and depth != 0) : (end += 1) {
            switch (ast.tokenTag(TokenId.at(end))) {
                .l_bracket => depth += 1,
                .r_bracket => depth -= 1,
                else => {},
            }
        }
        return .{ .start = TokenId.at(start), .end = TokenId.at(end) };
    }

    fn expand(
        self: *Resolver,
        source_interner: *const Interner,
        derive_shared_valid: *const Table(DeclId, bool),
    ) !ExpandedProgram {
        for (0..self.program.ast.declCount()) |i| {
            switch (self.program.ast.declTag(DeclId.at(@intCast(i)))) {
                .template_impl, .derive_impl => break,
                .struct_, .enum_, .newtype => if (self.program.ast.attachedDeriveTraitRange(DeclId.at(@intCast(i))).len() != 0) break,
                else => {},
            }
        } else return ExpandedProgram.borrowSource(self.gpa, self.program);

        var index = try DeclIndex.build(self.gpa, &self.program.ast);
        defer index.deinit(self.gpa);
        var template_plans = try self.planTemplates(&index);
        defer template_plans.deinit(self.gpa);
        var template_members: std.ArrayList(TemplateMemberPlan) = .empty;
        defer template_members.deinit(self.gpa);
        for (template_plans.items.items) |plan| {
            try template_members.appendSlice(self.gpa, plan.members);
        }

        var texts: std.ArrayList([]const u8) = .empty;
        defer {
            for (texts.items) |text| self.gpa.free(text);
            texts.deinit(self.gpa);
        }
        var plans: std.ArrayList(ExpansionPlan) = .empty;
        defer {
            for (plans.items) |plan| {
                self.gpa.free(plan.import_targets);
                self.gpa.free(plan.requirements);
            }
            plans.deinit(self.gpa);
        }
        var pending_origins: std.ArrayList(PendingOriginSegment) = .empty;
        defer pending_origins.deinit(self.gpa);
        const occupied_names = try self.gpa.alloc(std.StringHashMapUnmanaged(void), self.program.modules.len);
        defer self.gpa.free(occupied_names);
        for (occupied_names) |*occupied| occupied.* = .empty;
        defer for (occupied_names) |*occupied| occupied.deinit(self.gpa);
        var generated_aliases: std.ArrayList([]u8) = .empty;
        defer {
            for (generated_aliases.items) |alias| self.gpa.free(alias);
            generated_aliases.deinit(self.gpa);
        }
        const generated_alias_prefix = "_linea_trait_";
        var source_alias_ordinals: SourceAliasOrdinals = .empty;
        defer source_alias_ordinals.deinit(self.gpa);
        for (0..self.program.ast.tokenCount()) |i| {
            const id = TokenId.at(@intCast(i));
            if (self.program.ast.tokenTag(id) != .identifier) continue;
            const identifier = self.program.ast.tokenText(id);
            if (!std.mem.startsWith(u8, identifier, generated_alias_prefix)) continue;
            const ordinal = std.fmt.parseInt(u64, identifier[generated_alias_prefix.len..], 10) catch continue;
            try source_alias_ordinals.put(self.gpa, ordinal, {});
        }
        var source_alias_successors: SourceAliasSuccessors = .empty;
        defer source_alias_successors.deinit(self.gpa);
        // The first request of each argument-free trait per target. A trait
        // taking arguments is derived once per argument list, and whether two
        // lists name one implementation is coherence's question.
        var requested_traits: std.AutoHashMapUnmanaged(u64, TokenId) = .empty;
        defer requested_traits.deinit(self.gpa);
        var source_alias_skip_path: std.ArrayList(u64) = .empty;
        defer source_alias_skip_path.deinit(self.gpa);
        const next_generated_alias_ordinals = try self.gpa.alloc(u64, self.program.modules.len);
        defer self.gpa.free(next_generated_alias_ordinals);
        @memset(next_generated_alias_ordinals, 0);
        for (self.program.modules, 0..) |source_module, module_index| {
            for (source_module.decls.start..source_module.decls.end) |decl_index| {
                const source_decl = DeclId.at(@intCast(decl_index));
                const name = self.program.ast.declName(source_decl);
                if (name == .none) continue;
                try occupied_names[module_index].put(self.gpa, self.program.ast.tokenText(name), {});
            }
        }
        var capacity = ExpansionCapacity{
            .source_domain_end = largestAstDomainEnd(&self.program.ast) orelse std.math.maxInt(u32),
            .generated_file_end = nextGeneratedFile(&self.program.ast) orelse std.math.maxInt(u32),
        };

        for (0..self.program.ast.declCount()) |i| {
            const derive = DeclId.at(@intCast(i));
            const attached = self.program.ast.declTag(derive) != .derive_impl;
            const trait_range = self.program.ast.deriveRequestTraitRange(derive);
            if (trait_range.len() == 0) continue;
            if (!derive_shared_valid.get(derive)) continue;
            // Expansion consumes resolved bindings; module-dependent rendering
            // and import routing receive this module explicitly.
            const module = self.program.moduleOf(derive);
            const target = if (attached) derive else (try self.deriveTarget(derive)) orelse continue;
            const target_tag = self.program.ast.declTag(target);
            if (target_tag != .struct_ and target_tag != .enum_ and target_tag != .newtype) {
                try self.refuseUnsupportedDerive(derive, "structural reflection requires a struct, enum, or newtype target");
                continue;
            }
            // An attached request has no written head, so there is nothing to
            // apply: the declaration it sits on is the target.
            if (!attached and self.program.ast.declHead(derive).args.len() != self.program.ast.declTypeParams(target).len) {
                try self.refuseUnsupportedDerive(
                    derive,
                    "apply the target to exactly the number of parameters its declaration requires",
                );
                continue;
            }

            for (trait_range.start..trait_range.end) |trait_index| {
                const derive_trait = node.DeriveTraitId.at(@intCast(trait_index));
                const entry = self.program.ast.deriveTrait(derive_trait);
                const trait = self.declReachedBy(entry.ref.name);
                if (trait == .none) continue;
                // A trait with no valid template is refused where templates
                // are planned, so its written arguments add no second error.
                const template_plan = template_plans.get(trait) orelse continue;
                if (!template_plan.valid) continue;
                if (entry.ref.args.len() != self.program.ast.declTypeParams(trait).len) {
                    try self.refuseUnsupportedDeriveEntry(entry.ref.name, "supply exactly the type arguments the trait declares");
                    continue;
                }
                // The parser reported an argument it could not read, and that
                // argument has no source to copy into the implementation.
                var readable = true;
                for (self.program.ast.typeArgs(entry.ref.args)) |argument| {
                    if (unreadable(argument)) readable = false;
                }
                // An argument list the parser found unclosed ends the entry
                // before its bracket, so there is no complete entry to copy.
                if (self.program.ast.tokenTag(TokenId.at(entry.ref.name.index() + 1)) == .l_bracket and
                    self.program.ast.tokenTag(TokenId.at(entry.tokens.end.index() - 1)) != .r_bracket) readable = false;
                if (!readable) continue;
                const trait_module = self.program.moduleOf(trait);
                const supported = self.program.moduleOf(template_plan.template) == trait_module and
                    self.program.moduleOf(target) == module;
                if (!supported) {
                    try self.refuseUnsupportedDeriveEntry(entry.ref.name, "this derivation requires a target declared in the same module");
                    continue;
                }

                var shape_matches = true;
                for (self.program.ast.templateRequirements(template_plan.template)) |requirement| {
                    if (requirement.kind != .target or requirement.target_shape.declaration() == target_tag) continue;
                    try self.sink.addErrorFmt(.t_derive, self.program.ast.fileOf(entry.ref.name), self.program.ast.tokenSpan(entry.ref.name), "derive this trait for the declaration kind required by its template", "this template requires {s} `{s}` target", .{ article.before(requirement.target_shape.spelling()), requirement.target_shape.spelling() });
                    shape_matches = false;
                }
                // A target the template's own requirement already refused is
                // reported there; its constructions would be the same mistake
                // said a second time.
                if (shape_matches) {
                    for (template_plan.reflection_members) |reflected_member| {
                        for (reflected_member.constructions) |construction| {
                            if (target_tag == .newtype or (construction.product and target_tag != .struct_)) {
                                try self.sink.addError(.t_reflection, self.program.ast.fileOf(entry.ref.name), self.program.ast.tokenSpan(entry.ref.name), "construct structs or an active enum case", "this target does not provide the selected product");
                                shape_matches = false;
                                break;
                            }
                        }
                    }
                }
                if (!shape_matches) continue;

                const request_key = (@as(u64, target.index()) << 32) | trait.index();
                const requested = if (entry.ref.args.len() == 0)
                    try requested_traits.getOrPut(self.gpa, request_key)
                else
                    null;
                if (requested != null and requested.?.found_existing) {
                    const earlier = requested.?.value_ptr.*;
                    const labels = try self.sink.arena.alloc(Label, 2);
                    labels[0] = .{
                        .file = self.program.ast.fileOf(earlier),
                        .span = self.program.ast.tokenSpan(earlier),
                        .message = "this trait was already requested here",
                        .style = .secondary,
                    };
                    labels[1] = .{
                        .file = self.program.ast.fileOf(entry.ref.name),
                        .span = self.program.ast.tokenSpan(entry.ref.name),
                        .message = "a type derives each trait once",
                        .style = .primary,
                    };
                    try self.sink.add(.{
                        .severity = .err,
                        .code = .t_derive,
                        .message = "this derive trait is repeated",
                        .labels = labels,
                    });
                    continue;
                }
                if (requested) |first| first.value_ptr.* = entry.ref.name;

                const form_start = if (!attached and self.program.ast.deriveIsGrouped(derive))
                    self.program.ast.deriveGroupOpen(derive)
                else
                    entry.tokens.start;
                var imports: std.ArrayList(GeneratedImportPlan) = .empty;
                defer imports.deinit(self.gpa);
                var imports_by_target: std.AutoHashMapUnmanaged(ModuleId, u32) = .empty;
                defer imports_by_target.deinit(self.gpa);
                var replacements: SourceReplacements = .empty;
                defer replacements.deinit(self.gpa);

                const alias = if (trait_module == module)
                    null
                else
                    try self.ensureGeneratedImport(
                        module,
                        trait_module,
                        &source_alias_ordinals,
                        &source_alias_successors,
                        &source_alias_skip_path,
                        &occupied_names[module.index()],
                        &generated_aliases,
                        &next_generated_alias_ordinals[module.index()],
                        &imports,
                        &imports_by_target,
                    ) orelse {
                        try self.refuseUnsupportedDeriveEntry(entry.ref.name, "the trait module has no canonical import route from the target module");
                        continue;
                    };

                var imports_valid = true;
                var component_fields: std.ArrayList(node.Field) = .empty;
                defer component_fields.deinit(self.gpa);
                var component_offsets: std.ArrayList(u32) = .empty;
                defer component_offsets.deinit(self.gpa);
                var needs_component_types = false;
                for (template_plan.reflection_members) |reflected_member| {
                    if (reflected_member.component_types.len != 0) needs_component_types = true;
                }
                if (needs_component_types) switch (target_tag) {
                    .struct_ => {
                        try component_offsets.append(self.gpa, 0);
                        try component_fields.appendSlice(self.gpa, self.program.ast.declFields(target));
                    },
                    .enum_ => for (self.program.ast.declVariants(target)) |variant| {
                        try component_offsets.append(self.gpa, @intCast(component_fields.items.len));
                        try component_fields.appendSlice(self.gpa, self.program.ast.variantFields(variant));
                    },
                    else => {},
                };
                var copied_ranges: std.ArrayList(token.TokenRange) = .empty;
                defer copied_ranges.deinit(self.gpa);
                if (attached) {
                    try self.attachedHeaderCopies(target, &copied_ranges);
                    try copied_ranges.append(self.gpa, entry.tokens);
                } else try copied_ranges.appendSlice(self.gpa, &.{
                    .{
                        .start = TokenId.at(self.program.ast.declMain(derive).index() + 1),
                        .end = form_start,
                    },
                    self.deriveTargetRange(derive),
                    entry.tokens,
                });
                // An attached request's implementation applies where each
                // component naming a parameter of the target meets the
                // template's component bounds. Components naming none are
                // checked once, at the derive.
                var predicate_fields: std.ArrayList(node.Field) = .empty;
                defer predicate_fields.deinit(self.gpa);
                if (attached and templateBoundsComponents(&self.program.ast, template_plan.template)) {
                    const variants = if (target_tag == .enum_) self.program.ast.declVariants(target) else &.{};
                    for (0..if (target_tag == .enum_) variants.len else 1) |case_index| {
                        const fields = if (target_tag == .enum_)
                            self.program.ast.variantFields(variants[case_index])
                        else
                            self.program.ast.declFields(target);
                        for (fields) |field| {
                            if (self.namesTargetParameter(target, field.written)) try predicate_fields.append(self.gpa, field);
                        }
                    }
                }
                for (component_fields.items) |field| try copied_ranges.append(self.gpa, .{
                    .start = field.written.at,
                    .end = TokenId.at(field.type_end.index() + 1),
                });
                for (predicate_fields.items) |field| try copied_ranges.append(self.gpa, .{
                    .start = field.written.at,
                    .end = TokenId.at(field.type_end.index() + 1),
                });
                copied: for (copied_ranges.items) |copied_range| {
                    for (copied_range.start.index()..copied_range.end.index()) |token_index| {
                        if (token_index >= self.written.items.len) continue;
                        const binding = self.written.items[token_index];
                        if (binding == .none) continue;
                        const held = self.bindings.items[binding.index()];
                        if (held.kind != .module) continue;
                        const target_module = self.importedBy(held.decl);
                        if (target_module == .none) continue;
                        const replacement = try self.ensureGeneratedImport(
                            module,
                            target_module,
                            &source_alias_ordinals,
                            &source_alias_successors,
                            &source_alias_skip_path,
                            &occupied_names[module.index()],
                            &generated_aliases,
                            &next_generated_alias_ordinals[module.index()],
                            &imports,
                            &imports_by_target,
                        ) orelse {
                            try self.refuseUnsupportedDeriveEntry(entry.ref.name, "a referenced module has no canonical import route from the target module");
                            imports_valid = false;
                            break :copied;
                        };
                        try replacements.put(self.gpa, binding, replacement);
                    }
                }
                if (!imports_valid) continue;
                // An attached request writes the target's own parameters, so
                // only a written head renames them.
                if (!attached) {
                    const target_arguments = self.program.ast.typeArgs(self.program.ast.declHead(derive).args);
                    for (self.program.ast.declTypeParams(target), target_arguments) |parameter, argument| {
                        const binding = self.type_parameter_bindings.get(parameter.name) orelse continue;
                        try replacements.put(self.gpa, binding, self.program.ast.tokenText(argument.name));
                    }
                }
                var component_type_text: std.ArrayList([]const u8) = .empty;
                defer {
                    for (component_type_text.items) |field_text| self.gpa.free(field_text);
                    component_type_text.deinit(self.gpa);
                }
                for (component_fields.items) |field| {
                    var field_text: std.ArrayList(u8) = .empty;
                    defer field_text.deinit(self.gpa);
                    try self.appendSourceRangeReplacingBindings(&field_text, .{
                        .start = field.written.at,
                        .end = TokenId.at(field.type_end.index() + 1),
                    }, &replacements);
                    const owned = try field_text.toOwnedSlice(self.gpa);
                    component_type_text.append(self.gpa, owned) catch |err| {
                        self.gpa.free(owned);
                        return err;
                    };
                }

                const pending_requirements = self.buildPendingRequirements(target, template_plan.template) catch |err| switch (err) {
                    error.Overflow => {
                        try self.refuseUnsupportedDeriveEntry(entry.ref.name, "the generated implementation exceeds compiler representation limits");
                        continue;
                    },
                    else => return err,
                };
                var requirements_handed_off = false;
                defer if (!requirements_handed_off) self.gpa.free(pending_requirements.rows);

                const template_arguments = try self.gpa.alloc([]const u8, entry.ref.args.len());
                var argument_count: usize = 0;
                defer {
                    for (template_arguments[0..argument_count]) |argument| self.gpa.free(argument);
                    self.gpa.free(template_arguments);
                }
                for (template_arguments, 0..) |*argument, argument_index| {
                    var argument_text: std.ArrayList(u8) = .empty;
                    defer argument_text.deinit(self.gpa);
                    try self.appendSourceRangeReplacingBindings(&argument_text, self.traitArgumentRange(entry, argument_index), &replacements);
                    argument.* = try argument_text.toOwnedSlice(self.gpa);
                    argument_count += 1;
                }

                var derived_predicates: std.ArrayList(u8) = .empty;
                defer derived_predicates.deinit(self.gpa);
                if (predicate_fields.items.len != 0) {
                    var bounds_text: std.ArrayList(u8) = .empty;
                    defer bounds_text.deinit(self.gpa);
                    var qualified_names: std.ArrayList([]u8) = .empty;
                    defer {
                        for (qualified_names.items) |qualified| self.gpa.free(qualified);
                        qualified_names.deinit(self.gpa);
                    }
                    var bound_replacements = try replacements.clone(self.gpa);
                    defer bound_replacements.deinit(self.gpa);
                    for (self.program.ast.declTypeParams(template_plan.template), template_arguments) |parameter, argument| {
                        const binding = self.type_parameter_bindings.get(parameter.name) orelse continue;
                        try bound_replacements.put(self.gpa, binding, argument);
                    }
                    var routed = true;
                    requirements: for (self.program.ast.templateRequirements(template_plan.template)) |requirement| {
                        if (requirement.kind != .components) continue;
                        for (self.program.ast.boundsIn(requirement.bounds)) |bound| {
                            const bound_trait = self.declReachedBy(bound.named.name);
                            if (bound.kind != .named or bound_trait == .none) continue;
                            if (bounds_text.items.len != 0) try bounds_text.appendSlice(self.gpa, " + ");
                            const bound_module = self.program.moduleOf(bound_trait);
                            if (bound_module != module) {
                                const qualifier = try self.ensureGeneratedImport(
                                    module,
                                    bound_module,
                                    &source_alias_ordinals,
                                    &source_alias_successors,
                                    &source_alias_skip_path,
                                    &occupied_names[module.index()],
                                    &generated_aliases,
                                    &next_generated_alias_ordinals[module.index()],
                                    &imports,
                                    &imports_by_target,
                                ) orelse {
                                    routed = false;
                                    break :requirements;
                                };
                                try bounds_text.appendSlice(self.gpa, qualifier);
                                try bounds_text.append(self.gpa, '.');
                            }
                            try bounds_text.appendSlice(self.gpa, self.program.ast.tokenText(self.program.ast.declName(bound_trait)));
                            const arguments = self.boundArgumentRange(bound.named.name);
                            if (arguments.len() == 0) continue;
                            // Names the template module reaches are spelled
                            // through an import of the module declaring them.
                            for (arguments.start.index()..arguments.end.index()) |token_index| {
                                if (token_index >= self.written.items.len) continue;
                                const binding = self.written.items[token_index];
                                if (binding == .none or bound_replacements.contains(binding)) continue;
                                const held = self.bindings.items[binding.index()];
                                const declaring = switch (held.kind) {
                                    .module => self.importedBy(held.decl),
                                    .declared_type, .trait => self.program.moduleOf(held.decl),
                                    else => continue,
                                };
                                if (declaring == .none or (held.kind != .module and declaring == module)) continue;
                                if (held.kind != .module and self.program.ast.tokenTag(TokenId.at(@intCast(token_index - 1))) == .dot) continue;
                                const qualifier = try self.ensureGeneratedImport(
                                    module,
                                    declaring,
                                    &source_alias_ordinals,
                                    &source_alias_successors,
                                    &source_alias_skip_path,
                                    &occupied_names[module.index()],
                                    &generated_aliases,
                                    &next_generated_alias_ordinals[module.index()],
                                    &imports,
                                    &imports_by_target,
                                ) orelse {
                                    routed = false;
                                    break :requirements;
                                };
                                const spelled = if (held.kind == .module)
                                    try self.gpa.dupe(u8, qualifier)
                                else
                                    try std.fmt.allocPrint(self.gpa, "{s}.{s}", .{ qualifier, self.program.ast.tokenText(self.program.ast.declName(held.decl)) });
                                qualified_names.append(self.gpa, spelled) catch |err| {
                                    self.gpa.free(spelled);
                                    return err;
                                };
                                try bound_replacements.put(self.gpa, binding, spelled);
                            }
                            try self.appendSourceRangeReplacingBindings(&bounds_text, arguments, &bound_replacements);
                        }
                    }
                    if (!routed) {
                        try self.refuseUnsupportedDeriveEntry(entry.ref.name, "a component requirement's trait has no canonical import route from the target module");
                        continue;
                    }
                    var subjects: std.StringHashMapUnmanaged(void) = .empty;
                    defer {
                        var keys = subjects.keyIterator();
                        while (keys.next()) |key| self.gpa.free(key.*);
                        subjects.deinit(self.gpa);
                    }
                    var subject_text: std.ArrayList(u8) = .empty;
                    defer subject_text.deinit(self.gpa);
                    for (predicate_fields.items) |field| {
                        const start = derived_predicates.items.len;
                        if (start != 0) try derived_predicates.appendSlice(self.gpa, ", ");
                        const subject_start = derived_predicates.items.len;
                        try self.appendSourceRangeReplacingBindings(&derived_predicates, .{
                            .start = field.written.at,
                            .end = TokenId.at(field.type_end.index() + 1),
                        }, &replacements);
                        subject_text.clearRetainingCapacity();
                        try subject_text.appendSlice(self.gpa, derived_predicates.items[subject_start..]);
                        if (subjects.contains(subject_text.items)) {
                            derived_predicates.items.len = start;
                            continue;
                        }
                        const owned_subject = try self.gpa.dupe(u8, subject_text.items);
                        subjects.put(self.gpa, owned_subject, {}) catch |err| {
                            self.gpa.free(owned_subject);
                            return err;
                        };
                        try derived_predicates.appendSlice(self.gpa, ": ");
                        try derived_predicates.appendSlice(self.gpa, bounds_text.items);
                    }
                }

                // A prelude name the target's module shadows is reached
                // through an import of its declaring module, planned here so
                // the import is written with the others.
                var prelude_routed = true;
                prelude: for (template_plan.free_references) |free_references| {
                    for (free_references) |reference| {
                        const declaring = self.preludeReferenceShadowed(module, reference) orelse continue;
                        _ = try self.ensureGeneratedImport(
                            module,
                            declaring,
                            &source_alias_ordinals,
                            &source_alias_successors,
                            &source_alias_skip_path,
                            &occupied_names[module.index()],
                            &generated_aliases,
                            &next_generated_alias_ordinals[module.index()],
                            &imports,
                            &imports_by_target,
                        ) orelse {
                            prelude_routed = false;
                            break :prelude;
                        };
                    }
                }
                if (!prelude_routed) {
                    try self.refuseUnsupportedDeriveEntry(entry.ref.name, "a prelude name the template writes has no canonical import route from the target module");
                    continue;
                }

                var wrapped_cases: std.ArrayList(expanded_mod.CaseOrdinal) = .empty;
                defer wrapped_cases.deinit(self.gpa);
                if (!try self.selectWrappedVariants(&wrapped_cases, template_plan.reflection_members, template_plan.template, derive, attached, target, entry)) continue;

                var text: std.ArrayList(u8) = .empty;
                defer text.deinit(self.gpa);
                var entry_origins: std.ArrayList(PendingOriginSegment) = .empty;
                defer entry_origins.deinit(self.gpa);
                var representable = true;
                for (imports.items) |import_plan| {
                    try text.appendSlice(self.gpa, "import ");
                    try text.appendSlice(self.gpa, import_plan.syntax);
                    try text.appendSlice(self.gpa, " as ");
                    try text.appendSlice(self.gpa, import_plan.alias);
                    try text.append(self.gpa, '\n');
                }
                if (imports.items.len > 0) try text.append(self.gpa, '\n');
                try text.appendSlice(self.gpa, "impl");
                if (attached) {
                    try self.appendAttachedParameters(&text, target, &replacements);
                } else {
                    try self.appendSourceBetweenReplacingBindings(
                        &text,
                        self.program.ast.declMain(derive),
                        form_start,
                        &replacements,
                    );
                }
                if (text.items.len == 0 or !std.ascii.isWhitespace(text.items[text.items.len - 1])) {
                    try text.append(self.gpa, ' ');
                }
                if (alias) |qualifier| {
                    try text.appendSlice(self.gpa, qualifier);
                    try text.append(self.gpa, '.');
                }
                try text.appendSlice(self.gpa, self.program.ast.tokenText(self.program.ast.declName(trait)));
                try self.appendSourceBetweenReplacingBindings(&text, entry.ref.name, entry.tokens.end, &replacements);
                try text.appendSlice(self.gpa, " for ");
                if (attached)
                    try self.appendAttachedTarget(&text, target, &replacements, derived_predicates.items)
                else
                    try self.appendSourceRangeReplacingBindings(&text, self.deriveTargetRange(derive), &replacements);
                try text.appendSlice(self.gpa, " {\n");
                var wrapped_at: usize = 0;
                for (template_plan.members, template_plan.free_references, template_plan.reflection_members) |member_plan, free_references, *reflection_plan| {
                    const template_member = member_plan.member;
                    const member_wrapped = wrapped_cases.items[wrapped_at..][0..reflection_plan.wraps.len];
                    wrapped_at += reflection_plan.wraps.len;
                    const rendered_references = try self.gpa.alloc(reflection.FreeReference, free_references.len);
                    defer self.gpa.free(rendered_references);
                    for (free_references, rendered_references) |reference, *rendered_reference| {
                        rendered_reference.* = .{
                            .at = reference.at,
                            .member = self.bindings.items[reference.member.index()].at,
                        };
                        if (!reference.prelude) continue;
                        // A prelude name is written as the template wrote it
                        // where the target's module reaches the same binding
                        // by it, and through an import of its declaring
                        // module where the target's module shadows it.
                        rendered_reference.route = if (self.preludeReferenceShadowed(module, reference)) |declaring|
                            .{ .through = imports.items[imports_by_target.get(declaring).?].alias }
                        else
                            .as_written;
                    }
                    const member_base = std.math.cast(u32, text.items.len) orelse {
                        representable = false;
                        break;
                    };
                    var rendered = reflection.renderMember(
                        self.gpa,
                        &self.program.ast,
                        derive,
                        target,
                        reflection_plan,
                        rendered_references,
                        alias,
                        template_arguments,
                        member_wrapped,
                        .{ .offsets = component_offsets.items, .text = component_type_text.items },
                    ) catch |err| switch (err) {
                        error.Overflow, error.GeneratedSourceTooLarge => {
                            representable = false;
                            break;
                        },
                        else => return err,
                    };
                    defer rendered.deinit(self.gpa);
                    try text.appendSlice(self.gpa, rendered.text);
                    for (rendered.origins) |origin| {
                        const start = std.math.add(u32, member_base, origin.start) catch {
                            representable = false;
                            break;
                        };
                        const end = std.math.add(u32, member_base, origin.end) catch {
                            representable = false;
                            break;
                        };
                        try entry_origins.append(self.gpa, .{
                            .generated_file = 0,
                            .derive_trait = derive_trait,
                            .span = .{ .start = start, .end = end },
                            .origin = .{
                                .derive = derive,
                                .derive_trait = entry.ref.name,
                                .target = target,
                                .template_member = template_member,
                                .template_expr = origin.template_expr,
                                .case_ordinal = origin.case_ordinal,
                                .component_ordinal = origin.component_ordinal,
                            },
                        });
                    }
                    if (!representable) break;
                    try text.append(self.gpa, '\n');
                }
                if (!representable) {
                    try self.refuseUnsupportedDeriveEntry(entry.ref.name, "the generated implementation exceeds compiler representation limits");
                    continue;
                }
                try text.appendSlice(self.gpa, "}\n");
                const owned_text = try text.toOwnedSlice(self.gpa);
                var text_handed_off = false;
                defer if (!text_handed_off) self.gpa.free(owned_text);
                const import_targets = try self.gpa.alloc(ModuleId, imports.items.len);
                var import_targets_handed_off = false;
                defer if (!import_targets_handed_off) self.gpa.free(import_targets);
                for (imports.items, import_targets) |import_plan, *target_slot| {
                    target_slot.* = import_plan.target;
                }

                try plans.ensureUnusedCapacity(self.gpa, 1);
                try texts.ensureUnusedCapacity(self.gpa, 1);
                try pending_origins.ensureUnusedCapacity(self.gpa, entry_origins.items.len);
                const reservation = capacity.reserve(
                    owned_text.len,
                    pending_requirements.component_count,
                    pending_requirements.bound_count,
                ) orelse {
                    try self.refuseUnsupportedDeriveEntry(entry.ref.name, "the generated implementation exceeds compiler representation limits");
                    continue;
                };

                plans.appendAssumeCapacity(.{
                    .derive = derive,
                    .derive_trait = derive_trait,
                    .trait_token = entry.ref.name,
                    .target = target,
                    .template = template_plan.template,
                    .module = module,
                    .import_targets = import_targets,
                    .implementation = reservation.implementation,
                    .requirements_range = reservation.requirements,
                    .requirements = pending_requirements.rows,
                    .generated_file = reservation.generated_file,
                    .members = template_plan.members,
                    .reflection_members = template_plan.reflection_members,
                });
                import_targets_handed_off = true;
                requirements_handed_off = true;
                for (entry_origins.items) |origin| {
                    var committed = origin;
                    committed.generated_file = reservation.generated_file;
                    pending_origins.appendAssumeCapacity(committed);
                }
                texts.appendAssumeCapacity(owned_text);
                text_handed_off = true;
            }
        }

        var paths: std.ArrayList([]const u8) = .empty;
        defer {
            for (paths.items) |path| self.gpa.free(path);
            paths.deinit(self.gpa);
        }
        var used_paths: std.StringHashMapUnmanaged(void) = .empty;
        defer used_paths.deinit(self.gpa);
        for (self.program.ast.parts) |part| {
            try used_paths.put(self.gpa, std.fs.path.basename(part.path), {});
        }
        var path_ordinal: u32 = 0;
        for (plans.items) |_| {
            while (true) : (path_ordinal += 1) {
                const path = try std.fmt.allocPrint(self.gpa, "linea-derive-{d}.lin", .{path_ordinal});
                if (used_paths.contains(path)) {
                    self.gpa.free(path);
                    continue;
                }
                paths.append(self.gpa, path) catch |err| {
                    self.gpa.free(path);
                    return err;
                };
                try used_paths.put(self.gpa, path, {});
                path_ordinal += 1;
                break;
            }
        }

        var generated_sources: GeneratedSources = .empty;
        defer generated_sources.deinit(self.gpa);
        generated_sources.paths = try paths.toOwnedSlice(self.gpa);
        generated_sources.buffers = try texts.toOwnedSlice(self.gpa);
        var expanded_interner = try Interner.initPrefix(self.gpa, source_interner);
        defer expanded_interner.deinit(self.gpa);
        var parser = try Modules.initPrefix(
            self.gpa,
            self.sink,
            &expanded_interner,
            &self.program.ast,
        );
        defer parser.deinit();

        var generated: std.ArrayList(GeneratedDecl) = .empty;
        defer generated.deinit(self.gpa);
        var generated_imports: std.ArrayList(GeneratedImport) = .empty;
        defer generated_imports.deinit(self.gpa);
        var generated_origins: std.ArrayList(GeneratedOriginSegment) = .empty;
        defer generated_origins.deinit(self.gpa);
        for (pending_origins.items) |origin| {
            try generated_origins.append(self.gpa, .{
                .file = .from(origin.generated_file),
                .span = origin.span,
                .derive_trait = origin.derive_trait,
                .origin = origin.origin,
            });
        }
        var generated_implementations: std.ArrayList(GeneratedImplementation) = .empty;
        defer generated_implementations.deinit(self.gpa);
        var component_requirements: std.ArrayList(ComponentRequirement) = .empty;
        defer component_requirements.deinit(self.gpa);
        for (plans.items, 0..) |plan, ordinal| {
            try generated_implementations.ensureUnusedCapacity(self.gpa, 1);
            try component_requirements.ensureUnusedCapacity(self.gpa, plan.requirements.len);
            const range = try parser.add(&.{.{
                .file = .from(plan.generated_file),
                .source = .{
                    .path = generated_sources.path(ordinal),
                    .text = generated_sources.get(ordinal),
                },
            }});
            const view = parser.view();
            var member_at: usize = 0;
            var generated_impl = DeclId.none;
            var generated_import_count: usize = 0;
            for (range.start..range.end) |decl_index| {
                const decl = DeclId.at(@intCast(decl_index));
                const template_member = switch (view.declTag(decl)) {
                    .function => blk: {
                        const template_member = plan.members[member_at].member;
                        member_at += 1;
                        break :blk template_member;
                    },
                    .impl_ => blk: {
                        if (generated_impl != .none) return error.InvalidGeneratedDeclarationCount;
                        generated_impl = decl;
                        break :blk DeclId.none;
                    },
                    .import_ => blk: {
                        if (generated_import_count >= plan.import_targets.len) return error.InvalidGeneratedDeclarationCount;
                        try generated_imports.append(self.gpa, .{
                            .decl = decl,
                            .target = plan.import_targets[generated_import_count],
                        });
                        generated_import_count += 1;
                        break :blk DeclId.none;
                    },
                    else => return error.InvalidGeneratedDeclarationCount,
                };
                try generated.append(self.gpa, .{
                    .module = plan.module,
                    .derive_trait = plan.derive_trait,
                    .origin = .{
                        .derive = plan.derive,
                        .derive_trait = plan.trait_token,
                        .target = plan.target,
                        .template_member = template_member,
                    },
                });
            }
            if (member_at != plan.members.len or generated_impl == .none or
                generated_import_count != plan.import_targets.len or
                generated_implementations.items.len != plan.implementation.index() or
                component_requirements.items.len != plan.requirements_range.start)
            {
                return error.InvalidGeneratedDeclarationCount;
            }
            generated_implementations.appendAssumeCapacity(.{
                .generated_impl = generated_impl,
                .derive = plan.derive,
                .derive_trait = plan.derive_trait,
                .target = plan.target,
                .template = plan.template,
                .requirements = plan.requirements_range,
            });
            for (plan.requirements) |requirement| {
                component_requirements.appendAssumeCapacity(.{
                    .implementation = plan.implementation,
                    .requirement = requirement.requirement,
                    .bound = requirement.bound,
                    .case = requirement.case,
                    .component = requirement.component,
                });
            }
        }

        var owned_generated_implementations = try generated_implementations.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(owned_generated_implementations);
        var owned_component_requirements = try component_requirements.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(owned_component_requirements);
        var expanded_ast = try parser.finish();
        return ExpandedProgram.init(
            self.gpa,
            self.program,
            &expanded_ast,
            &expanded_interner,
            &generated_sources,
            template_members.items,
            &owned_generated_implementations,
            &owned_component_requirements,
            generated.items,
            generated_imports.items,
            generated_origins.items,
        );
    }

    fn refuseUnsupportedDerive(self: *Resolver, derive: DeclId, label: []const u8) !void {
        try self.sink.addError(
            .t_derive,
            self.program.ast.fileOfDecl(derive),
            self.program.ast.declSpan(derive),
            "this derive form is not supported yet",
            label,
        );
    }

    fn refuseUnsupportedDeriveEntry(self: *Resolver, trait: TokenId, label: []const u8) !void {
        try self.sink.addError(
            .t_derive,
            self.program.ast.fileOf(trait),
            self.program.ast.tokenSpan(trait),
            "this derive entry is not supported",
            label,
        );
    }

    /// How `selectWrappedVariants` reads written names: coherence's reading,
    /// with array lengths compared as a bound's constants are. A payload's
    /// length has not been folded the way an implementation's arguments are,
    /// so two lengths match when they are spelled alike.
    const WrapIdentity = struct {
        res: *const Resolver,

        pub const Error = error{};

        pub fn reaches(self: WrapIdentity, tok: TokenId) Reached {
            return (Coherence{ .res = self.res }).reaches(tok);
        }

        pub fn tuple(self: WrapIdentity, arity: usize) ?DeclId {
            return tupleDeclIn(self.res.tuple_decls, arity);
        }

        pub fn sameValue(self: WrapIdentity, a: ExprId, b: ExprId) Error!bool {
            return sameBoundConstant(self.res.ast, a, b, checkedWorth(&self.res.folded, a), checkedWorth(&self.res.folded, b));
        }
    };

    /// Whether every name a written type reaches settled: a name nothing
    /// declares, an alias whose own type fails, and an alias that reaches itself
    /// have each been reported where they are written.
    ///
    /// **Bound:** the written type's own nodes, and each alias it names once
    /// per level up to `alias_depth`.
    fn writtenSettled(self: *const Resolver, ref: node.TypeRef, depth: u32) bool {
        const alias_depth = 32;
        if (depth > alias_depth) return false;
        const ast = &self.program.ast;
        const x = ast.withoutTypeGroups(ref);
        switch (x.kind) {
            .named => if (x.name != TokenId.none) {
                const binding = self.writtenBinding(x.name);
                if (binding == BindingId.none) return false;
                const held = self.bindings.items[binding.index()];
                if (held.kind == .type_alias and !self.writtenSettled(ast.declReturnRef(held.decl), depth + 1)) return false;
            },
            .selection => if (!self.writtenSettled(ast.selectionBase(x), depth)) return false,
            .callable, .array, .tuple, .borrow, .grouped => {},
        }
        for (ast.typeArgs(x.args)) |argument| {
            if (!self.writtenSettled(argument, depth)) return false;
        }
        return true;
    }

    /// Selects the variant each `reflect.wrap` of a template's members
    /// constructs: the one variant of `target` with exactly one field whose
    /// written type is the wrapped parameter's, once the entry's trait
    /// arguments stand for the template's parameters. Appends one case per
    /// wrap to `out`, in member order. Reports [T-Derive] and returns false
    /// where no variant qualifies or two do.
    ///
    /// Types are compared by `sameWrittenType`, the one answer to whether two
    /// written types name one type, so an alias and the type it names select
    /// the same variant.
    fn selectWrappedVariants(
        self: *Resolver,
        out: *std.ArrayList(expanded_mod.CaseOrdinal),
        members: []const ReflectionMemberPlan,
        template: DeclId,
        derive: DeclId,
        attached: bool,
        target: DeclId,
        entry: node.DeriveTrait,
    ) !bool {
        const ast = &self.program.ast;
        const identity: WrapIdentity = .{ .res = self };
        const variants = ast.declVariants(target);
        for (members) |reflected| {
            for (reflected.wraps) |wrap| {
                const wrapped = ast.declParams(reflected.member)[wrap.parameter].written;
                const template_reading: Reading = .{
                    .family = template,
                    .applied = ast.typeArgs(entry.ref.args),
                };
                // An attached request spells the target's own parameters; a
                // written head applies the target's parameters to its own.
                const target_reading: Reading = if (attached) .{} else .{
                    .family = target,
                    .applied = ast.typeArgs(ast.declHead(derive).args),
                };
                var selected: ?usize = null;
                var second: ?usize = null;
                for (variants, 0..) |variant, index| {
                    const fields = ast.variantFields(variant);
                    if (fields.len != 1) continue;
                    if (!try sameWrittenType(ast, identity, wrapped, template_reading, fields[0].written, target_reading)) continue;
                    if (selected == null) selected = index else {
                        second = index;
                        break;
                    }
                }
                if (selected != null and second == null) {
                    try out.append(self.gpa, @enumFromInt(selected.?));
                    continue;
                }
                const written_arguments = ast.typeArgs(entry.ref.args);
                // A source or a payload that failed to resolve has its own
                // report; a missing variant would say the same mistake twice.
                var settled = true;
                for (written_arguments) |argument| settled = settled and self.writtenSettled(argument, 0);
                for (variants) |variant| {
                    const fields = ast.variantFields(variant);
                    if (fields.len == 1) settled = settled and self.writtenSettled(fields[0].written, 0);
                }
                if (!settled) return false;
                const source_text = ast.writtenText(if (written_arguments.len == 1) written_arguments[0] else wrapped);
                const target_name = ast.tokenText(ast.declName(target));
                const file = ast.fileOf(entry.ref.name);
                const labels = try self.sink.arena.alloc(Label, if (second != null) 3 else 1);
                labels[0] = .{
                    .file = file,
                    .span = ast.rangeSpan(entry.tokens),
                    .message = if (second != null) "the conversion would wrap the source in either variant" else "no variant wraps this source",
                    .style = .primary,
                };
                if (second) |later| {
                    for ([_]usize{ selected.?, later }, 1..) |index, slot| {
                        labels[slot] = .{
                            .file = ast.fileOf(variants[index].name),
                            .span = ast.tokenSpan(variants[index].name),
                            .message = "this variant holds the source's type",
                            .style = .secondary,
                        };
                    }
                    try self.sink.add(.{
                        .severity = .err,
                        .code = .t_derive,
                        .message = try std.fmt.allocPrint(self.sink.arena, "`{s}` has two variants wrapping `{s}`", .{ target_name, source_text }),
                        .labels = labels,
                        .notes = try self.sink.arena.dupe([]const u8, &.{"write the conversion by hand, or give each variant its own type"}),
                    });
                    return false;
                }
                var shapes: std.ArrayList(u8) = .empty;
                defer shapes.deinit(self.gpa);
                if (variants.len == 0) try shapes.appendSlice(self.gpa, "no variants");
                for (variants, 0..) |variant, index| {
                    if (index != 0) try shapes.appendSlice(self.gpa, ", ");
                    try shapes.appendSlice(self.gpa, "`");
                    try shapes.appendSlice(self.gpa, ast.tokenText(variant.name));
                    const fields = ast.variantFields(variant);
                    if (fields.len != 0) try shapes.append(self.gpa, '(');
                    for (fields, 0..) |field, field_index| {
                        if (field_index != 0) try shapes.appendSlice(self.gpa, ", ");
                        try shapes.appendSlice(self.gpa, ast.writtenText(field.written));
                    }
                    if (fields.len != 0) try shapes.append(self.gpa, ')');
                    try shapes.appendSlice(self.gpa, "`");
                }
                try self.sink.add(.{
                    .severity = .err,
                    .code = .t_derive,
                    .message = try std.fmt.allocPrint(self.sink.arena, "no variant of `{s}` wraps exactly `{s}`", .{ target_name, source_text }),
                    .labels = labels,
                    .notes = try self.sink.arena.dupe([]const u8, &.{
                        try std.fmt.allocPrint(self.sink.arena, "a variant wraps a source when its only field has the source's type{s}; `{s}` has {s}", .{
                            if (std.mem.indexOfScalar(u8, source_text, ';') != null) " (array lengths match only when spelled alike)" else "",
                            target_name,
                            shapes.items,
                        }),
                    }),
                });
                return false;
            }
        }
        return true;
    }

    fn refuseUnsupportedTemplate(self: *Resolver, template: DeclId, label: []const u8) !void {
        try self.sink.addError(
            .t_template,
            self.program.ast.fileOfDecl(template),
            self.program.ast.declSpan(template),
            "this structural template is not supported",
            label,
        );
    }

    fn registerGeneratedDeclarations(self: *Resolver) !void {
        const expanded = self.expanded.?;
        for (self.program.ast.declCount()..expanded.ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (expanded.ast.declTag(d) == .import_) {
                self.current = expanded.moduleOf(d);
                const name = expanded.ast.declName(d);
                const binding = BindingId.at(@intCast(self.bindings.items.len));
                try self.bindings.append(self.gpa, .{
                    .name = expanded.ast.tokenName(name),
                    .kind = .module,
                    .stmt = .none,
                    .decl = d,
                    .param_index = 0,
                    .at = name,
                    .used = false,
                    .mutable = false,
                    .exempt = false,
                });
                try self.noteModule(binding);
                continue;
            }
            if (expanded.ast.declOwner(d) == TokenId.none) continue;
            try self.declareMember(d);
        }
    }

    fn importedBy(self: *const Resolver, decl: DeclId) ModuleId {
        if (self.expanded) |expanded| return expanded.importedBy(decl);
        const module = self.program.moduleOf(decl);
        if (module == .none) return .none;
        return self.program.get(module).importedBy(decl);
    }

    fn declReachedBy(self: *const Resolver, tok: TokenId) DeclId {
        const binding = self.writtenBindingAt(tok);
        if (binding == BindingId.none) return .none;
        return self.bindings.items[binding.index()].decl;
    }

    /// The binding a name written outside an expression reached, or `.none`
    /// for a token that is not one or that reached nothing.
    fn writtenBindingAt(self: *const Resolver, tok: TokenId) BindingId {
        if (tok == TokenId.none or tok.index() >= self.written.items.len) return .none;
        return self.written.items[tok.index()];
    }

    /// Classifies each bound a declaration writes -- on its type parameters,
    /// and on the declaration itself where it declares a type a trait's
    /// implementations settle.
    ///
    /// A bound is a name and the parser recorded nothing more. Universes are a
    /// closed set the compiler defines; traits are open and contributed by
    /// libraries. A name that is neither is an unknown trait, because a
    /// capability that does not exist is not something a program can be trying
    /// to name.
    ///
    /// **Bound:** the bounds this one declaration wrote.
    fn checkBounds(self: *Resolver, d: DeclId) !void {
        self.marks_for = d;
        const params = self.ast.declTypeParams(d);
        self.used_type_params.clearRetainingCapacity();
        try self.used_type_params.appendNTimes(self.gpa, false, params.len);

        for (self.constraints.ofDeclaration(d)) |constraint| {
            try self.classifyBounds(self.constraints.requirementsOf(constraint));
        }
        try self.classifyBounds(self.ast.declBounds(d));
        for (self.ast.declWherePredicates(d)) |predicate| {
            try self.useRef(predicate.subject);
        }
        // A default is a written type like any other, read where the
        // declaration is.
        for (params) |parameter| {
            if (parameter.default.wasWritten()) try self.useRef(parameter.default);
        }
    }

    /// Whether every trait bound `d` writes supplies as many arguments as its
    /// trait declares. The type checker reports a mismatch at the bound; a
    /// derive attached to `d` copies its header, so the resolver withholds
    /// that expansion instead of letting the same bound be reported again.
    fn boundArityHolds(self: *const Resolver, d: DeclId) bool {
        for (self.constraints.ofDeclaration(d)) |constraint| {
            if (!self.boundsArityHolds(self.constraints.requirementsOf(constraint))) return false;
        }
        return self.boundsArityHolds(self.ast.declBounds(d));
    }

    fn boundsArityHolds(self: *const Resolver, bounds: []const node.TraitBound) bool {
        for (bounds) |b| {
            if (b.kind == .callable) continue;
            const trait = self.declReachedBy(b.named.name);
            if (trait == .none or self.program.ast.declTag(trait) != .trait_) continue;
            if (self.program.ast.declTypeParams(trait).len != b.named.args.len()) return false;
        }
        return true;
    }

    /// Says which of a run of bounds names nothing, refuses a capability bound
    /// that carries arguments, and marks the traits the rest reach as used --
    /// along with every name written inside what a bound applies, which is
    /// read like any other written type.
    ///
    /// A capability is closed and admits nothing to apply an argument to, so
    /// `Copyable[UInt8]` is refused here rather than left to whatever would later
    /// have tried to line the argument up against a parameter that does not
    /// exist.
    fn classifyBounds(self: *Resolver, bounds: []const node.TraitBound) !void {
        for (bounds) |b| {
            if (b.kind == .callable) {
                try self.useCallableType(self.ast.callableTypeById(b.callable));
                continue;
            }
            if (b.named.path.len() != 0) {
                _ = try self.traitRefReaching(b.named, true);
                for (self.ast.typeArgs(b.named.args)) |a| try self.useRef(a);
                continue;
            }
            switch (boundNames(self.ast, b.named.name, self.traitBound(b.named.name))) {
                .capability => if (b.named.args.len() != 0) try self.sink.addErrorFmt(
                    .t_bound,
                    self.ast.fileOf(b.named.name),
                    self.ast.tokenSpan(b.named.name),
                    "drop the arguments, or bound it by a trait instead",
                    "`{s}` is a capability, and capabilities take no type arguments",
                    .{self.ast.tokenText(b.named.name)},
                ),
                .integer => if (b.named.args.len() != 0) try self.sink.addErrorFmt(
                    .t_bound,
                    self.ast.fileOf(b.named.name),
                    self.ast.tokenSpan(b.named.name),
                    "drop the type arguments",
                    "`Integer` is a closed constraint and takes no type arguments",
                    .{},
                ),
                .trait => {},
                // An alias bounds by the type it names, which the checker
                // holds to be a function type.
                .unknown => if (self.aliasHere(b.named.name)) |alias| {
                    self.bindings.items[alias.index()].used = true;
                    self.reached(b.named.name, alias);
                } else try self.sink.addErrorFmt(
                    .n_undefined,
                    self.ast.fileOf(b.named.name),
                    self.ast.tokenSpan(b.named.name),
                    "no trait with this name is declared",
                    "unknown trait `{s}`",
                    .{self.ast.tokenText(b.named.name)},
                ),
            }
            // What a bound applies is a written type like any other, so a
            // name inside it is used by being written -- a parameter named
            // only inside a bound's argument is still a parameter the
            // declaration that names it uses.
            for (self.ast.typeArgs(b.named.args)) |a| try self.useRef(a);
        }
    }

    /// A declaration declares each of its type parameters once.
    ///
    /// A name reaches the first parameter spelled that way, so a second of one
    /// spelling stands for nothing a program can write and for no position an
    /// argument can settle. On a head it is worse than unreachable: both
    /// positions hold one parameter, so a receiver applying two types binds it
    /// twice and the member is lowered at whichever one the last position
    /// supplied, reading its own fields at another type's offsets and widths.
    ///
    /// Asked of every declaration that carries a list, because one list is what
    /// they all declare their parameters in -- and everywhere else the second
    /// one is caught by a consequence rather than by the name: unused where
    /// nothing mentions it, uninferable where a call must settle it, and
    /// waived outright wherever an underscore says disuse was meant.
    ///
    /// **Bound:** the parameters this one declaration declares, each entered
    /// once into a table sized by that list.
    fn refuseTypeParametersOfOneName(self: *Resolver, d: DeclId) !void {
        const params = self.ast.declTypeParams(d);
        if (params.len < 2) return;
        var names: std.ArrayList(TokenId) = .empty;
        defer names.deinit(self.gpa);
        try names.ensureTotalCapacity(self.gpa, params.len);
        for (params) |p| names.appendAssumeCapacity(p.name);
        try self.refuseNamesDeclaredTwice(names.items, "a declaration declares each parameter once");
    }

    /// [N-Duplicate] for a declaration's value parameters, a function's or a
    /// signature's: a list names each parameter once.
    fn refuseParametersOfOneName(self: *Resolver, d: DeclId) !void {
        const params = self.ast.declParams(d);
        if (params.len < 2) return;
        var names: std.ArrayList(TokenId) = .empty;
        defer names.deinit(self.gpa);
        try names.ensureTotalCapacity(self.gpa, params.len);
        // A name the parser read only to recover from a malformed parameter
        // declares nothing, so it is not a second of anything.
        for (params) |p| if (!p.recovered) names.appendAssumeCapacity(p.name);
        try self.refuseNamesDeclaredTwice(names.items, "a declaration declares each parameter once");
    }

    /// [N-Duplicate] for one list of names written together -- a type
    /// parameter list, a value parameter list, or a closure's captures and
    /// parameters: each is declared once. Reported at the second, and the
    /// first keeps the name, which is what every other duplicate does: what
    /// was already read resolves to the first, and moving the name would
    /// report each of those as well. Sized by the list.
    fn refuseNamesDeclaredTwice(self: *Resolver, names: []const TokenId, label: []const u8) !void {
        if (names.len < 2) return;
        var declared: std.AutoHashMapUnmanaged(StringId, TokenId) = .empty;
        defer declared.deinit(self.gpa);
        try declared.ensureTotalCapacity(self.gpa, @intCast(names.len));

        for (names) |name| {
            if (self.ast.tokenTag(name) != .identifier) continue;
            // `_` declares no name, so a list may hold it any number of times.
            if (std.mem.eql(u8, self.ast.tokenText(name), "_")) continue;
            const at = declared.getOrPutAssumeCapacity(self.ast.tokenName(name));
            if (!at.found_existing) {
                at.value_ptr.* = name;
                continue;
            }
            try self.reportNameDeclaredTwice(at.value_ptr.*, name, "declaration", label);
        }
    }

    /// [N-Duplicate] at `name`, the second spelling of what `first` declared
    /// in the same `owner`, a declaration or a pattern.
    fn reportNameDeclaredTwice(self: *Resolver, first: TokenId, name: TokenId, owner: []const u8, label: []const u8) !void {
        const labels = try self.sink.arena.alloc(Label, 2);
        labels[0] = .{
            .file = self.ast.fileOf(first),
            .span = self.ast.tokenSpan(first),
            .message = "already declared here",
            .style = .secondary,
        };
        labels[1] = .{
            .file = self.ast.fileOf(name),
            .span = self.ast.tokenSpan(name),
            .message = label,
            .style = .primary,
        };
        try self.sink.add(.{
            .severity = .err,
            .code = .n_duplicate,
            .message = try std.fmt.allocPrint(
                self.sink.arena,
                "`{s}` is already declared by this {s}",
                .{ self.ast.tokenText(name), owner },
            ),
            .labels = labels,
        });
    }

    /// [N-Case]: every name a declaration writes starts in the case its kind
    /// requires.
    ///
    /// What declarations write is read from the source tree's own tables, each
    /// row once: declaration names, every element of an import's path, type
    /// parameters, fields, variants, parameters -- of functions, signatures,
    /// closures and callable types alike -- and capture aliases. What a body
    /// binds by a statement or a pattern is read from the bindings resolution
    /// made from `own_bindings`, because which arguments of a pattern bind
    /// names is resolution's answer and the check reads it rather than
    /// deciding it again. The kind each name was checked as is recorded in
    /// `name_kinds`, which is what a rename checks a new name against.
    ///
    /// A name restated from elsewhere is not a declaration of it and is not
    /// checked: a trait implementation's members spell the trait's, a struct
    /// pattern's shorthand spells a field, and a capture without `=` spells
    /// the binding it captures. Generated declarations spell template source,
    /// which is checked where it is written. A resumed run checked its
    /// library when the prefix was resolved, so it skips the library's files.
    ///
    /// A structural template's body is walked once for validation and again
    /// as a member, so a body's bindings can repeat a token; `Checks` keeps
    /// one mistake one diagnostic.
    fn checkNameCases(self: *Resolver, resumed: bool, own_bindings: usize, interner: *const Interner) !void {
        const source = &self.program.ast;

        // Which files a resumed run skips, sized by the program's files.
        var library_files: std.DynamicBitSetUnmanaged = .{};
        defer library_files.deinit(self.gpa);
        if (resumed) {
            try library_files.resize(self.gpa, source.parts.len, false);
            for (self.program.modules) |module| {
                if (!module.library) continue;
                for (module.files) |file| {
                    if (file.index() >= library_files.bit_length) try library_files.resize(self.gpa, file.index() + 1, false);
                    library_files.set(file.index());
                }
            }
        }
        var checks: Checks = .{ .resolver = self, .source = source, .skipped = &library_files };
        defer checks.deinit();

        for (0..source.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (declaredNameKind(source, d)) |kind| {
                // A member is a duplicate of another member of its type, and a
                // top-level name, an import's included, of another in its
                // module's run -- the two places [N-Duplicate] asks.
                const module = self.program.moduleOf(d);
                const namespace: Namespace = if (source.declOwner(d) == TokenId.none)
                    .{ .module_run = module }
                else
                    .{ .members = .{ .module = module, .owner = source.tokenName(source.declOwner(d)) } };
                try checks.name(source.declName(d), kind, namespace);
            }
            switch (source.declTag(d)) {
                .import_ => {
                    // A path element names a directory, which nothing here
                    // declares, so it clashes with nothing.
                    var elements = source.pathElements(d);
                    while (elements.next()) |element| try checks.name(element, .module, .none);
                },
                .struct_ => for (source.declFields(d)) |f| try checks.name(f.name, .field, .{ .list = .{ .decl = d, .of = .fields } }),
                .enum_ => for (source.declVariants(d)) |v| try checks.name(v.name, .variant, .{ .list = .{ .decl = d, .of = .variants } }),
                else => {},
            }
            for (source.declTypeParams(d)) |p| try checks.name(p.name, .type_parameter, .{ .list = .{ .decl = d, .of = .type_parameters } });
        }
        // A body's names may shadow what encloses them, so a respelling is
        // compared against nothing there.
        for (source.params) |p| if (!p.recovered and p.pattern == ExprId.none) try checks.name(p.name, .parameter, .none);
        for (source.captures) |c| if (c.equals != TokenId.none) try checks.name(c.name, .capture, .none);

        for (self.bindings.items[own_bindings..]) |b| {
            if (b.at == TokenId.none or b.at.index() >= source.tokenCount()) continue;
            switch (b.kind) {
                .local => {},
                .binder => if (b.names_a_field) continue,
                .capture, .parameter, .function, .constant, .declared_type, .builtin_type, .trait, .module, .associated_type, .type_parameter, .type_alias => continue,
            }
            try checks.name(b.at, .binding, .none);
        }
        try checks.report(interner);
    }

    /// Where a declared name is a duplicate of another spelled alike: its
    /// module's run, its type's members, or one list a declaration writes --
    /// a structure's fields, an enum's variants, a type parameter list. A
    /// name a body declares may shadow what encloses it, so it has none.
    const Namespace = union(enum) {
        none,
        module_run: ModuleId,
        members: struct { module: ModuleId, owner: StringId },
        list: struct { decl: DeclId, of: enum { fields, variants, type_parameters } },
    };

    /// The names [N-Case] refuses, gathered from every table before any is
    /// reported so the diagnostics follow the source rather than the tables.
    const Checks = struct {
        resolver: *Resolver,
        source: *const Ast,
        skipped: *const std.DynamicBitSetUnmanaged,
        refused: std.ArrayList(Refusal) = .empty,

        const Refusal = struct {
            at: TokenId,
            kind: name_case.Kind,
            namespace: Namespace,

            fn before(_: void, a: Refusal, b: Refusal) bool {
                return a.at.index() < b.at.index();
            }
        };

        fn deinit(self: *Checks) void {
            self.refused.deinit(self.resolver.gpa);
        }

        /// Records the kind `at` declares, and refuses it when its name starts
        /// in the wrong case. The case is read first because it is what
        /// nearly every name passes on; the file a name is in is asked only
        /// where a resumed run skips some.
        fn name(self: *Checks, at: TokenId, kind: name_case.Kind, namespace: Namespace) !void {
            if (at == TokenId.none or self.source.tokenTag(at) != .identifier) return;
            if (self.skipped.bit_length != 0) {
                const file = self.source.fileOf(at);
                if (file.index() < self.skipped.bit_length and self.skipped.isSet(file.index())) return;
            }
            const r = self.resolver;
            const recorded = try r.name_kinds.getOrPut(r.gpa, at);
            if (recorded.found_existing) return;
            recorded.value_ptr.* = kind;
            const case = name_case.of(self.source.tokenText(at)) orelse return;
            if (case == kind.case()) return;
            try self.refused.append(r.gpa, .{ .at = at, .kind = kind, .namespace = namespace });
        }

        /// Reports every refused name in source order, each with the
        /// respelling a reader can write in its place.
        ///
        /// A respelling that would be a duplicate where the refused name is
        /// declared is named but not offered: accepting it would trade this
        /// error for [N-Duplicate]. Whether it would be is asked of the tables
        /// that rule is decided by.
        fn report(self: *Checks, interner: *const Interner) !void {
            std.mem.sortUnstable(Refusal, self.refused.items, {}, Refusal.before);
            const r = self.resolver;
            const sink = r.sink;
            // The names of the list the last refusal was declared in. A
            // list's names sit together in the source, so its refusals sort
            // together and each list is gathered once.
            var list_names: std.AutoHashMapUnmanaged(StringId, void) = .empty;
            defer list_names.deinit(r.gpa);
            var gathered: ?Namespace = null;
            for (self.refused.items) |refusal| {
                if (refusal.namespace == .list and !std.meta.eql(gathered, @as(?Namespace, refusal.namespace))) {
                    list_names.clearRetainingCapacity();
                    const l = refusal.namespace.list;
                    switch (l.of) {
                        .fields => for (self.source.declFields(l.decl)) |f| try self.gather(&list_names, f.name),
                        .variants => for (self.source.declVariants(l.decl)) |v| try self.gather(&list_names, v.name),
                        .type_parameters => for (self.source.declTypeParams(l.decl)) |p| try self.gather(&list_names, p.name),
                    }
                    gathered = refusal.namespace;
                }
                const text = self.source.tokenText(refusal.at);
                const label = switch (try respelling(sink.arena, text, refusal.kind)) {
                    .offered => |respelled| if (self.clashes(interner, refusal.namespace, &list_names, respelled))
                        try std.fmt.allocPrint(sink.arena, "rename it: `{s}` would be declared twice", .{respelled})
                    else
                        try std.fmt.allocPrint(sink.arena, "rename it `{s}`", .{respelled}),
                    .unusable => |respelled| try std.fmt.allocPrint(sink.arena, "rename it: `{s}` is not a name a program declares", .{respelled}),
                };
                try sink.addErrorFmt(
                    .n_case,
                    self.source.fileOf(refusal.at),
                    self.source.tokenSpan(refusal.at),
                    label,
                    "{s} start with {s}",
                    .{ refusal.kind.plural(), refusal.kind.case().describe() },
                );
            }
        }

        fn gather(self: *const Checks, names: *std.AutoHashMapUnmanaged(StringId, void), at: TokenId) !void {
            if (at == TokenId.none or self.source.tokenTag(at) != .identifier) return;
            try names.put(self.resolver.gpa, self.source.tokenName(at), {});
        }

        /// Whether `respelled` would be [N-Duplicate] where the refused name
        /// is declared: in its module's run or among its type's members, as
        /// declaring either asks, or in the list it was written in.
        fn clashes(
            self: *const Checks,
            interner: *const Interner,
            namespace: Namespace,
            list_names: *const std.AutoHashMapUnmanaged(StringId, void),
            respelled: []const u8,
        ) bool {
            const id = interner.ids.get(respelled) orelse return false;
            const r = self.resolver;
            return switch (namespace) {
                .none => false,
                .module_run => |module| r.here_named.contains(hereKey(module, id)),
                .members => |m| r.memberOf(m.module, m.owner, TokenId.none, id) != null,
                .list => list_names.contains(id),
            };
        }
    };

    /// A type parameter is a declaration, and its declaration says what it is
    /// for. One nothing names is an error like any other; one read for
    /// identity alone says so with `phantom`; and the spellings may not
    /// cross. `phantom` where a field carries the parameter is false, an
    /// underscore where the type system reads it is false the other way
    /// round, and a bound on a phantom parameter constrains an argument
    /// nothing ever inspects.
    fn reportUnusedTypeParams(self: *Resolver, d: DeclId) !void {
        for (self.ast.declTypeParams(d), 0..) |p, i| {
            const used = i < self.used_type_params.items.len and self.used_type_params.items[i];
            const text = self.ast.tokenText(p.name);

            if (p.phantom) {
                switch (self.ast.declTag(d)) {
                    // The declarations with parts a parameter could appear
                    // in. Everything else is refused by default, so a
                    // declaration kind added later cannot accept a modifier
                    // it silently ignores.
                    .struct_, .enum_, .trait_ => {},
                    // An alias is the type it names, so no identity of its
                    // own is there for a parameter to be read for.
                    .alias => {
                        try self.sink.addErrorFmt(
                            .t_phantom,
                            self.ast.fileOf(p.name),
                            self.ast.tokenSpan(p.name),
                            "an alias is the type it names, and has no identity of its own to brand",
                            "`phantom` is not an alias's to declare",
                            .{},
                        );
                        continue;
                    },
                    else => {
                        try self.refuseCallablePhantom(p);
                        continue;
                    },
                }
                if (std.mem.startsWith(u8, text, "_")) {
                    try self.sink.addErrorFmt(
                        .t_phantom,
                        self.ast.fileOf(p.name),
                        self.ast.tokenSpan(p.name),
                        "drop the underscore: one claim per parameter",
                        "`{s}` is declared `phantom`, read for identity, and the underscore says it is not read at all",
                        .{text},
                    );
                } else if (used) {
                    try self.sink.addErrorFmt(
                        .t_phantom,
                        self.ast.fileOf(p.name),
                        self.ast.tokenSpan(p.name),
                        if (self.ast.declTag(d) == .trait_)
                            "remove `phantom`: a signature reads the parameter"
                        else
                            "remove `phantom`: the parameter carries bytes",
                        "`{s}` appears in this declaration, and `phantom` says it appears nowhere",
                        .{text},
                    );
                }

                // A bound is not refused here. `phantom` says the parameter
                // reaches no field, no variant and no signature, which is a
                // statement about the representation; a bound says which types
                // may stand as the argument, which is a statement about the
                // instantiation. Reading the first as settling the second is
                // what refused them together, and it does not follow: nothing
                // inspects the argument *in a value* because there is no value
                // holding it, while the argument itself is a type, and a type
                // is what a bound constrains.
                //
                // Nothing here has to enforce it. `[T-Bound]` already reports
                // an argument that fails the bound of a phantom parameter --
                // it did so beside this refusal, which is what showed the
                // refusal was the only thing in the way.
                continue;
            }

            if (used) continue;
            const on_type = switch (self.ast.declTag(d)) {
                .struct_, .enum_, .trait_ => true,
                else => false,
            };
            if (std.mem.startsWith(u8, text, "_")) {
                // Deliberate disuse is the wrong claim here: the parameter is
                // read, by the type system, for identity -- delete it and two
                // brands become one type. A function's parameters keep the
                // escape, because `phantom` is not theirs to declare.
                if (!on_type) continue;
                try self.sink.addErrorFmt(
                    .t_phantom,
                    self.ast.fileOf(p.name),
                    self.ast.tokenSpan(p.name),
                    "declare it `phantom`: the type system reads it for identity",
                    "`{s}` is not unused, and an underscore does not stand for `phantom`",
                    .{text},
                );
                continue;
            }
            // The hint offers only spellings this declaration may write:
            // `phantom` is a type's, and a function told to declare it would
            // trade one error for another.
            try self.sink.addErrorFmt(
                .n_unused,
                self.ast.fileOf(p.name),
                self.ast.tokenSpan(p.name),
                if (on_type)
                    "name it in this declaration, declare it `phantom`, or remove it"
                else
                    "name it in this declaration, or remove it",
                "`{s}` is never used",
                .{text},
            );
        }
    }

    /// The refusal a callable's parameter gets: `phantom` is a type's to
    /// declare. One routine, because a signature and a function are one shape
    /// and the message must not drift between them.
    fn refuseCallablePhantom(self: *Resolver, p: node.TypeParam) !void {
        if (!p.phantom) return;
        try self.sink.addErrorFmt(
            .t_phantom,
            self.ast.fileOf(p.name),
            self.ast.tokenSpan(p.name),
            "a body can read no parameter for identity alone",
            "`phantom` is not a function's to declare",
            .{},
        );
    }

    const TypeUseContext = enum {
        ordinary,
        template_requirement,
        /// The head of a named literal. The parser reads `name { ... }` as a
        /// literal without asking what the name is, so a local, a function, a
        /// trait or a module may stand where the type belongs.
        literal_head,
        /// A type argument written in brackets before a call. The parser
        /// reads the brackets as types without asking what the names are, so
        /// a value may stand where a type belongs.
        type_argument,

        /// The context a written type's own arguments are read in.
        fn ofArguments(self: TypeUseContext) TypeUseContext {
            return if (self == .literal_head or self == .type_argument) .ordinary else self;
        }

        /// Whether a value written as the type is refused as no type rather
        /// than as an undefined type name.
        fn refusesValues(self: TypeUseContext) bool {
            return self == .literal_head or self == .type_argument;
        }
    };

    /// A written type and everything it was given.
    ///
    /// An argument names a type as much as a head does: `Inner[T]` uses `T`,
    /// and a rule that looked only at the head would report a parameter unused
    /// for appearing exactly where a generic type is meant to appear.
    ///
    /// Whole, rather than a head and a range beside it. An array names nothing
    /// and holds its element in the same range a named type's arguments use,
    /// so walking it by its head alone reaches neither the element nor the
    /// length -- and a name written as a length is then a name nobody
    /// resolved.
    ///
    /// A dotted head decides which of two things was written, and deciding it
    /// is this pass's job: a module qualifies a type name, and everything else
    /// is a settled reference. A settled reference's head is marked like any
    /// other name -- `Self` written where no implementation encloses it
    /// reaches nothing, and saying so is this pass's job too. A component
    /// requirement is the exception: its template rule owns prohibited
    /// `Self`, while names nested beneath it still take this ordinary walk.
    /// What follows the dot in a settled reference is a member of whatever the
    /// head names, which no scope in this module holds, so which type it is is
    /// settled by an implementation and answered where types are.
    fn useRef(self: *Resolver, ref: node.TypeRef) std.mem.Allocator.Error!void {
        return self.useRefIn(ref, .ordinary);
    }

    fn useRefIn(self: *Resolver, ref: node.TypeRef, context: TypeUseContext) std.mem.Allocator.Error!void {
        if (try self.reflectionComponentType(ref)) return;
        if (ref.kind == .callable) return self.useCallableTypeIn(self.ast.callableType(ref), context.ofArguments());
        if (ref.kind == .selection) {
            if (self.moduleHeading(ref)) |module| {
                try self.useQualifiedType(ref, module);
            } else {
                if (context.refusesValues() and try self.refuseValueSelection(ref, context)) return;
                const base = self.ast.selectionBase(ref);
                if (self.template_validation) |validation| {
                    try validation.reflection.selection_bases.put(self.gpa, base.at, {});
                }
                try self.useRefIn(base, context);
                try self.useSelectedType(ref);
            }
        } else if (context != .template_requirement or !namesSelf(self.ast, ref.name)) {
            // A head qualified by a module is read through the module, so
            // a name reaching nothing here names nothing at all, and saying
            // so is this pass's job alone: the checker answers such a
            // token with poison and reports nothing.
            switch (self.markTypeHere(ref.name)) {
                .settled => {},
                .unreached => {
                    if (context.refusesValues()) {
                        if (self.valueNamed(ref.name)) |value| return self.refuseValueHead(ref, value, context);
                    }
                    if (try self.refuseAliasedTrait(ref.name)) return;
                    self.reportUnknownType(ref.name);
                },
            }
        }
        // A length is an expression, so a name written in one is a name like
        // any other: it is read against the scope standing here, the binding
        // it reaches is used by being written, and reaching nothing is
        // [N-Undefined] rather than something to say about the form.
        if (ref.length != ExprId.none) try self.useTypeExpression(ref.length);
        for (self.ast.typeArgs(ref.args)) |a| try self.useRefIn(a, context.ofArguments());
    }

    /// The binding a name reaches from here when it reaches no type, without
    /// reporting a miss: the locals innermost first, then the module's run,
    /// in the order an expression's name is read.
    fn valueNamed(self: *const Resolver, tok: TokenId) ?BindingId {
        if (tok == TokenId.none or self.ast.tokenTag(tok) != .identifier) return null;
        const name = self.ast.tokenName(tok);
        if (self.local_of.get(name)) |at| return self.visible.items[at];
        return self.in_module.get(name);
    }

    /// A named literal whose head reaches a declaration that is not a type.
    ///
    /// Reported once, at the head. The declaration is marked used, as is
    /// whatever its written arguments name: each is declared, and calling one
    /// undefined or unused would describe a different mistake. An argument the
    /// parser could not read has already been reported, and the head is then
    /// part of that one mistake.
    fn refuseValueHead(self: *Resolver, head: node.TypeRef, value: BindingId, context: TypeUseContext) std.mem.Allocator.Error!void {
        return self.refuseValueHeadNamed(head, head.name, value, context);
    }

    /// A head written as a selection from a value, `wrap.inner { .. }`: the
    /// root names the value and the whole written head is underlined.
    fn refuseValueSelection(self: *Resolver, head: node.TypeRef, context: TypeUseContext) std.mem.Allocator.Error!bool {
        var root = self.ast.selectionBase(head);
        while (root.kind == .selection) root = self.ast.selectionBase(root);
        if (root.kind != .named or root.name == TokenId.none) return false;
        if (self.markTypeHere(root.name) == .settled) return false;
        const value = self.valueNamed(root.name) orelse return false;
        try self.refuseValueHeadNamed(head, root.name, value, context);
        return true;
    }

    fn refuseValueHeadNamed(self: *Resolver, head: node.TypeRef, name: TokenId, value: BindingId, context: TypeUseContext) std.mem.Allocator.Error!void {
        self.bindings.items[value.index()].used = true;
        var unreadable_head = false;
        for (self.ast.typeArgs(head.args)) |arg| {
            if (unreadable(arg)) unreadable_head = true;
            self.markHeadArgument(arg);
        }
        if (unreadable_head) return;
        try self.sink.addErrorFmt(
            .n_not_a_type,
            self.ast.fileOf(name),
            self.ast.writtenSpan(head),
            if (context == .type_argument) "the brackets before a call hold types" else "a named literal's head is a type",
            "`{s}` is not a type",
            .{self.ast.tokenText(name)},
        );
    }

    fn markHeadArgument(self: *Resolver, arg: node.TypeRef) void {
        switch (self.markTypeHere(arg.name)) {
            .settled => {},
            .unreached => if (self.valueNamed(arg.name)) |b| {
                self.bindings.items[b.index()].used = true;
            },
        }
        for (self.ast.typeArgs(arg.args)) |nested| self.markHeadArgument(nested);
    }

    fn useTypeExpression(self: *Resolver, expression: ExprId) std.mem.Allocator.Error!void {
        const previous = self.record_written_expr;
        self.record_written_expr = true;
        defer self.record_written_expr = previous;
        try self.expr(expression);
    }

    fn useCallableType(self: *Resolver, callable: node.CallableType) std.mem.Allocator.Error!void {
        return self.useCallableTypeIn(callable, .ordinary);
    }

    fn useCallableTypeIn(
        self: *Resolver,
        callable: node.CallableType,
        context: TypeUseContext,
    ) std.mem.Allocator.Error!void {
        for (self.ast.params[callable.params.start..callable.params.end]) |param| {
            try self.useRefIn(param.written, context);
            if (param.default != ExprId.none) try self.useTypeExpression(param.default);
        }
        try self.useRefIn(callable.result, context);
    }

    /// A namespace selection begins with the visible module binding.
    fn moduleHeading(self: *Resolver, ref: node.TypeRef) ?BindingId {
        if (ref.kind != .selection) return null;
        const base = self.ast.withoutTypeGroups(self.ast.selectionBase(ref));
        if (base.kind != .named or base.args.len() != 0 or base.name == .none) return null;
        if (self.ast.tokenTag(base.name) != .identifier) return null;
        if (namesSelf(self.ast, base.name) or self.typeParamInScope(base.name) != null) return null;
        return self.moduleNamed(self.ast.tokenName(base.name), self.ast.fileOf(base.name));
    }

    fn useQualifiedType(self: *Resolver, ref: node.TypeRef, module: BindingId) std.mem.Allocator.Error!void {
        const base = self.ast.withoutTypeGroups(self.ast.selectionBase(ref));
        self.bindings.items[module.index()].used = true;
        self.reached(base.name, module);
        if (ref.name == .none) return;
        const reached_type = (try self.throughModule(module, ref.name)) orelse return;
        const reached_kind = self.bindings.items[reached_type.index()].kind;
        if (reached_kind != .declared_type and reached_kind != .type_alias) {
            return self.sink.addErrorFmt(
                .n_undefined,
                self.ast.fileOf(ref.name),
                self.ast.tokenSpan(ref.name),
                "no type of that name is declared in that module",
                "`{s}` names no type in `{s}`",
                .{ self.ast.tokenText(ref.name), self.ast.tokenText(base.name) },
            );
        }
        self.reached(ref.name, reached_type);
    }

    /// Bound-based selections have a lexical declaration identity. A known
    /// structural base leaves applicability to canonical checked selection.
    fn useSelectedType(self: *Resolver, ref: node.TypeRef) std.mem.Allocator.Error!void {
        if (ref.name == .none) return;
        const base = self.ast.withoutTypeGroups(self.ast.selectionBase(ref));
        const wanted = self.ast.tokenName(ref.name);
        const trait = if (base.kind == .named and
            (namesSelf(self.ast, base.name) or self.typeParamInScope(base.name) != null))
            (try self.traitReadThrough(base.name, wanted)) orelse return
        else blk: {
            if (base.name == .none or base.name.index() >= self.written.items.len) return;
            const binding = self.written.items[base.name.index()];
            if (binding == .none or self.bindings.items[binding.index()].kind != .associated_type) return;
            const declared = self.bindings.items[binding.index()].decl;
            if (declared == .none) return;
            break :blk (try self.traitBounding(self.ast.declBounds(declared), wanted)) orelse return;
        };
        const declared = self.memberOf(self.moduleOf(trait), self.ast.tokenName(self.ast.declName(trait)), .none, wanted) orelse return;
        self.bindings.items[declared.index()].used = true;
        self.reached(ref.name, declared);
    }

    /// The one bound whose trait declares the name, as its declaration.
    fn traitBounding(self: *const Resolver, bounds: []const node.TraitBound, name: StringId) std.mem.Allocator.Error!?DeclId {
        const found = try boundDeclaring(bounds, name, BoundsHere{ .res = self });
        return if (found.declaring == 1) found.trait else null;
    }

    /// The trait that declares the name a settled reference writes after the
    /// dot, as its declaration.
    ///
    /// Two heads and one question. A head that is a type parameter carries its
    /// traits in its bounds, which is what a body checked once has instead of
    /// an implementation, and the one it is read through is the one declaring
    /// the name -- so a parameter answers from its own bounds and from nothing
    /// around it. Every other head is `Self`, which has the implementation:
    /// the trait an `impl` header names, or the trait a signature is written
    /// inside. Neither is searched for: a bound, a header and a signature each
    /// record the token their trait's name is.
    ///
    /// Null where no bound declares the name and where two do, which are the
    /// two the checker refuses -- so a name that reaches nothing is marked used
    /// by nothing. Null too where no declaration is being read, which is what
    /// both readings below are read off: a written type outside every
    /// declaration has no parameters to name and no implementation to give
    /// `Self` a meaning.
    ///
    /// **Bound:** the type parameters in scope, the bounds on one of them, and
    /// per bound one keyed lookup.
    fn traitReadThrough(self: *const Resolver, head: TokenId, name: StringId) std.mem.Allocator.Error!?DeclId {
        if (self.generic == DeclId.none) return null;

        if (head != TokenId.none and self.ast.tokenTag(head) == .identifier) {
            if (self.typeParamNamedInScope(self.ast.tokenName(head))) |found| {
                return try self.traitBounding(
                    self.constraints.parameterBounds(self.ast, found.of, found.at),
                    name,
                );
            }
        }

        const of = if (self.ast.declTrait(self.generic) != TokenId.none)
            self.ast.declTrait(self.generic)
        else
            self.ast.declOwner(self.generic);
        if (self.ast.declTag(self.generic) == .trait_) return self.generic;
        if (of == TokenId.none and self.trait_scope != DeclId.none) return self.trait_scope;
        if (of == TokenId.none) return null;

        const named = self.traitNamed(of);
        if (named == BindingId.none) return null;
        const trait = self.bindings.items[named.index()].decl;
        return if (trait == DeclId.none) null else trait;
    }

    /// The type parameter a head names, or null where it names none.
    fn typeParamInScope(self: *const Resolver, head: TokenId) ?node.TypeParam {
        if (head == TokenId.none) return null;
        if (self.ast.tokenTag(head) != .identifier) return null;

        const found = self.typeParamNamedInScope(self.ast.tokenName(head)) orelse return null;
        return found.written;
    }

    /// A type parameter in scope: what was written, which declaration declared
    /// it, and where in that declaration's list it stands.
    const ParamInScope = struct {
        written: node.TypeParam,
        of: DeclId,
        at: usize,
    };

    fn typeParamSlotKey(d: DeclId, name: StringId) u64 {
        return (@as(u64, d.index()) << 32) | @intFromEnum(name);
    }

    /// Adds the type-parameter rows of declarations in `[from, to)`. Source
    /// declarations are indexed before expansion and generated declarations
    /// afterwards; source IDs are an exact prefix and are never inserted twice.
    fn indexTypeParams(self: *Resolver, from: u32, to: u32) !void {
        for (from..to) |i| {
            const d = DeclId.at(@intCast(i));
            for (self.ast.declTypeParams(d), 0..) |parameter, position| {
                const entry = try self.type_param_slots.getOrPut(
                    self.gpa,
                    typeParamSlotKey(d, self.ast.tokenName(parameter.name)),
                );
                if (!entry.found_existing) entry.value_ptr.* = @intCast(position);
                const binding_entry = try self.type_parameter_bindings.getOrPut(self.gpa, parameter.name);
                if (!binding_entry.found_existing) {
                    binding_entry.value_ptr.* = BindingId.at(@intCast(self.bindings.items.len));
                    try self.bindings.append(self.gpa, .{
                        .name = self.ast.tokenName(parameter.name),
                        .kind = .type_parameter,
                        .stmt = .none,
                        .decl = d,
                        .param_index = @intCast(position),
                        .at = parameter.name,
                        .used = true,
                        .mutable = false,
                        .exempt = true,
                    });
                }
            }
        }
    }

    /// The type parameter a name reaches, searched through every scope that
    /// holds one, nearest first: the declaration being read, then the
    /// implementation whose member that is, then the trait whose signatures
    /// are being read.
    ///
    /// One chain, because which parameter a name reaches is one question. A
    /// reader with a chain of its own answers a name the others resolve with
    /// nothing, and a settled reference read off a parameter that reader could
    /// not see is a reference to a member of the wrong type.
    ///
    /// A member may be generic on its own account and its implementation may
    /// be too, and both lists stand in the same place -- so the nearer answers
    /// first, exactly as a local shadows a parameter.
    ///
    /// **Bound:** the type parameters written on the three declarations in
    /// scope, which is what a declaration was written with.
    fn typeParamNamedInScope(self: *const Resolver, wanted: StringId) ?ParamInScope {
        for ([_]DeclId{ self.generic, self.impl_scope, self.trait_scope }) |d| {
            if (d == DeclId.none) continue;
            const i = self.type_param_slots.get(typeParamSlotKey(d, wanted)) orelse continue;
            const params = self.ast.declTypeParams(d);
            if (i < params.len) return .{ .written = params[i], .of = d, .at = i };
        }
        return null;
    }

    /// What a bound names while the scope chain is still being built.
    const BoundsHere = struct {
        res: *const Resolver,

        /// Through the classifier both passes read, so what counts as a trait
        /// bound here and what counts as one where a settled reference is
        /// refused cannot come apart.
        pub fn traitBoundAt(self: BoundsHere, tok: TokenId) ?DeclId {
            // A qualified bound's final name is not in this module's bare
            // namespace. Resolution already recorded the declaration it
            // reached; the fallback serves bounds whose scope is still being
            // classified and therefore has no recorded target yet.
            const target = self.res.declReachedBy(tok);
            const named = if (target == DeclId.none) self.res.traitNamed(tok) else BindingId.none;
            const declared = if (target != DeclId.none)
                target
            else if (named != BindingId.none)
                self.res.bindings.items[named.index()].decl
            else
                null;
            return switch (boundNames(self.res.ast, tok, declared)) {
                .trait => |d| d,
                .capability, .integer, .unknown => null,
            };
        }

        pub const Error = std.mem.Allocator.Error;

        pub fn sameArgs(self: BoundsHere, a: node.TypeRefRange, b: node.TypeRefRange) Error!bool {
            return sameBoundArgs(self.res.ast, self, a, b);
        }

        pub fn hashArgs(self: BoundsHere, args: node.TypeRefRange) Error!u64 {
            return hashBoundArgs(self.res.ast, self, args);
        }

        pub fn allocator(self: BoundsHere) std.mem.Allocator {
            return self.res.gpa;
        }

        /// The declaration a written name reached, as far as resolution has
        /// got: a name it has not reached yet is read as spelled.
        pub fn reaches(self: BoundsHere, tok: TokenId) Reached {
            return (Coherence{ .res = self.res }).reaches(tok);
        }

        /// The prelude's declaration of the tuple with `arity` components.
        /// The prelude is published before any bound is read, so this answers
        /// as `Coherence` and `SettledWritten` do.
        pub fn tuple(self: BoundsHere, arity: usize) ?DeclId {
            return (Coherence{ .res = self.res }).tuple(arity);
        }

        /// What two constant expressions a bound writes are worth, folded into
        /// a memo of their own.
        ///
        /// Bounds are read while the scope chain is still being built, before
        /// the names a constant mentions are settled. Folding into the run's
        /// memo there would remember an expression as worth nothing for the
        /// rest of the run, and coherence reads that memo. A pair is folded
        /// only where the two are spelled differently, once per expression.
        pub fn sameValue(self: BoundsHere, a: ExprId, b: ExprId) Error!bool {
            if (std.mem.eql(u8, self.res.ast.exprText(a), self.res.ast.exprText(b))) return true;
            var scratch: constfold.Memo = .empty;
            defer scratch.deinit(self.res.gpa);
            const x = (try self.fold(&scratch, a)) orelse return false;
            const y = (try self.fold(&scratch, b)) orelse return false;
            return x.eql(y);
        }

        pub fn valueKey(self: BoundsHere, id: ExprId) Error!u64 {
            var scratch: constfold.Memo = .empty;
            defer scratch.deinit(self.res.gpa);
            return constantKey(self.res.ast, id, try self.fold(&scratch, id));
        }

        fn fold(self: BoundsHere, scratch: *constfold.Memo, id: ExprId) Error!?constfold.CheckedValue {
            return (try constfold.foldConstant(self.res.gpa, self.res.ast, self.res.nameSites(), scratch, id)).checked();
        }

        /// Through the members table, which is the one place this pass asks
        /// what a namespace holds.
        pub fn declaresMember(self: BoundsHere, trait: DeclId, name: StringId) bool {
            return self.res.memberOf(
                self.res.moduleOf(trait),
                self.res.ast.tokenName(self.res.ast.declName(trait)),
                TokenId.none,
                name,
            ) != null;
        }
    };

    /// What marking a written type name reached.
    const TypeUse = union(enum) {
        /// Marked used, or a token with nothing to mark.
        settled,
        /// Reached no type this module can write, and the name it wanted.
        unreached: StringId,
    };

    /// Marks the type a pattern's head names as used.
    ///
    /// The same question, with the opposite answer where the name reaches
    /// nothing. A pattern cannot qualify its head, so a module holding no type
    /// of that name is still entitled to take apart what another module's
    /// function returns -- and whether the head names the value's own
    /// type is checked against that value rather than against what is in
    /// scope. So a name reaching nothing here is not a mistake about names.
    ///
    /// The binding is recorded but not marked used here. A public type is
    /// already exempt from the unused rule; an internal type had to be named by
    /// a reachable signature before a value of it could arrive here. Taking the
    /// first binding of that spelling anywhere in the program instead gave one
    /// module's type the uses of another's: an unused private type escaped
    /// [N-Unused] because an unrelated enum's variant was spelled the same in a
    /// module that could not see it, and the walk cost the program for every
    /// call-shaped pattern written.
    ///
    /// What is recorded is where the name is *written*: this token spells
    /// that type's name, so it is where a reader would change it, and a
    /// rename that missed it would leave the head naming a type no longer
    /// there. From the indexes of public types and types internal to this root,
    /// each one lookup and each answering with nothing where the spelling is
    /// ambiguous. Which type a pattern takes apart is settled by the value it
    /// is given, and the checker settles it there.
    fn usePatternHead(self: *Resolver, tok: TokenId) std.mem.Allocator.Error!void {
        const wanted = switch (self.markTypeHere(tok)) {
            .settled => return,
            .unreached => |name| name,
        };
        const head: PatternHead = .{ .token = tok, .name = wanted, .root = self.program.get(self.current).root };
        if (self.record_prefix and self.pattern_index_ready) try self.pattern_heads.append(self.gpa, head);
        self.settlePatternHead(head);
    }

    fn settlePatternHead(self: *Resolver, head: PatternHead) void {
        const root_candidate = self.internal_types.get(rootNameKey(head.root, head.name));
        const public_candidate = self.exported_types.get(head.name);
        const target = if (root_candidate) |root_type|
            if (public_candidate) |public_type|
                if (root_type == public_type) root_type else BindingId.none
            else
                root_type
        else
            public_candidate orelse BindingId.none;
        self.reached(head.token, target);
    }

    /// Records every exported type under the name it is written with, and
    /// `.none` under a name two modules both export.
    ///
    /// Built once, after every module is declared and before any expression is
    /// resolved -- a constant's initialiser as much as a body, since either may
    /// write a pattern. A pattern head asks it, and asking it of the bindings
    /// directly is a walk of the program per pattern.
    ///
    /// An ambient name is the prelude's, offered to every module and declared
    /// by none of them, so counting one per module would make every prelude
    /// type ambiguous with itself. A re-export is another module's
    /// declaration under this module's name, and the declaration it names is
    /// already here.
    fn noteExportedTypes(self: *Resolver) std.mem.Allocator.Error!void {
        self.pattern_index_ready = true;
        for (self.bindings.items, 0..) |*b, i| {
            if (b.kind != .declared_type or b.reach == .module) continue;
            if (b.ambient or b.reexported) continue;
            switch (b.reach) {
                .module => unreachable,
                .root => {
                    const gop = try self.internal_types.getOrPut(
                        self.gpa,
                        rootNameKey(self.program.get(self.moduleOf(b.decl)).root, b.name),
                    );
                    gop.value_ptr.* = if (gop.found_existing) BindingId.none else BindingId.at(@intCast(i));
                },
                .public => {
                    const gop = try self.exported_types.getOrPut(self.gpa, b.name);
                    gop.value_ptr.* = if (gop.found_existing) BindingId.none else BindingId.at(@intCast(i));
                },
            }
        }
    }

    /// Records which implementation encloses each declaration.
    ///
    /// Every implementation naming a head, and not only the ones declaring
    /// type parameters: the relation is handed to the checker, which asks it
    /// to say what `Self` is inside a member, and a member of a
    /// non-generic implementation has one too.
    ///
    /// A member is owned by the token its implementation's head was written
    /// with, and a token is a position, so no two implementations share one and
    /// no other declaration's owner is one.
    ///
    /// **Bound:** two passes over the declarations, one entry per
    /// implementation and one per declaration.
    fn noteImplementations(self: *Resolver) std.mem.Allocator.Error!void {
        for (0..self.ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (self.ast.declTag(d) != .impl_ and self.ast.declTag(d) != .template_impl) continue;
            if (self.ast.declName(d) == TokenId.none) continue;
            try self.impl_of_head.put(
                self.gpa,
                self.ast.declName(d),
                d,
            );
        }

        const of_decl = try self.gpa.alloc(DeclId, self.ast.declCount());
        @memset(of_decl, DeclId.none);
        for (0..self.ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            const of = self.ast.declOwner(d);
            if (of == TokenId.none) continue;
            of_decl[i] = self.impl_of_head.get(of) orelse DeclId.none;
        }
        self.impl_of_decl = of_decl;
    }

    /// The implementation whose parameters `d` reads, or `.none` where it
    /// reads none.
    fn implEnclosing(self: *const Resolver, d: DeclId) DeclId {
        if (d.index() >= self.impl_of_decl.len) return DeclId.none;
        return self.impl_of_decl[d.index()];
    }

    /// Marks the type a name reaches from the module writing it.
    ///
    /// Searches the bindings rather than the visible chain: a type is entered
    /// in module scope and an annotation means the type whatever a local of
    /// that name might be.
    fn markTypeHere(self: *Resolver, tok: TokenId) TypeUse {
        if (tok == .none) return .settled;
        if (self.ast.tokenTag(tok) != .identifier) return .settled;

        var wanted = self.ast.tokenName(tok);

        // Whether this token spells the name it reaches. `Self` reaches the
        // type its `impl` names without spelling it, and what is recorded below
        // is where a name is *written*: a capability that reported `Self` as a
        // place `Coins` appears would offer to rewrite a word that does not say
        // `Coins` and never has to.
        var spells_it = true;

        // `Self` is the type the enclosing implementation names. Inside a
        // trait's signature it stands for whatever implements the trait, which
        // is nothing here -- nothing is checked against a signature, so there
        // is nothing to resolve it to. Asked of the tree rather than read off
        // the absent body, because a constant carries no body either and is an
        // ordinary member: written on one, `Self` names the type its `impl`
        // names and names nothing at all outside one.
        if (namesSelf(self.ast, tok)) {
            if (self.template_validation != null) return .settled;
            if (self.generic == DeclId.none) return .{ .unreached = wanted };
            if (self.ast.declIsSignature(self.generic) or self.ast.declTag(self.generic) == .trait_) return .settled;

            // The implementation whose head `Self` names: the declaration
            // being read where it is one, otherwise the one enclosing the
            // member being read. Under a tuple head, `Self` is the prelude's
            // tuple declaration, which `implTarget` found by identity and
            // reported where the prelude publishes none; a grouped head was
            // refused where it was written. Under a callable head, `Self` is
            // the callable type. None of them leaves `Self` anything further
            // to report.
            const impl = if (self.ast.declTag(self.generic) == .impl_) self.generic else self.implEnclosing(self.generic);
            if (impl != DeclId.none) {
                switch (self.ast.declHead(impl).kind) {
                    .tuple, .grouped, .callable => return .settled,
                    else => {},
                }
            }

            const owner = if (self.ast.declTag(self.generic) == .impl_)
                self.ast.declHead(self.generic).name
            else
                self.ast.declOwner(self.generic);
            if (owner == TokenId.none) return .{ .unreached = wanted };
            if (self.ast.tokenTag(owner) == .keyword_borrow) return .settled;
            wanted = self.ast.tokenName(owner);
            spells_it = false;
        }

        // A type parameter answers before any module-level type: it is the
        // nearest thing of that name, and a module-level type of the same name
        // is not what an annotation inside a generic declaration means.
        if (self.typeParamNamedInScope(wanted)) |found| {
            // Marked only where the marks are the declaration the parameter
            // belongs to. Reading a signature while its trait is being
            // accounted for leaves them the trait's, and an index into the
            // wrong list is a use recorded against a parameter nobody wrote.
            if (self.marks_for == found.of and found.at < self.used_type_params.items.len) {
                self.used_type_params.items[found.at] = true;
            }
            if (spells_it) self.reached(tok, self.type_parameter_bindings.get(found.written.name) orelse .none);
            return .settled;
        }

        // A type the trait declares answers next. Inside the braces that
        // declare it the name stands alone -- `type Item` is what a signature
        // writing `-> Item` beside it means, the way `Self` is the type an
        // implementation is for -- and it is the nearest declaration of that
        // name, so a module-level type spelled the same is not what a
        // signature inside those braces means.
        if (self.declaredTypeHere(wanted)) |declared| {
            self.bindings.items[declared.index()].used = true;
            if (spells_it) self.reached(tok, declared);
            return .settled;
        }

        // The module doing the naming answers first. Walking every binding in
        // the program and taking the first of that name gave one module's type
        // the uses of another's -- so a type named only in its own module was
        // reported unused, and one genuinely unused was exempted by a use that
        // was not of it.
        if (self.type_in_module.get(wanted)) |id| {
            self.bindings.items[id.index()].used = true;
            if (spells_it) self.reached(tok, id);
            return .settled;
        }

        if (self.reachesUnresolvedUse(wanted)) return .settled;
        return .{ .unreached = wanted };
    }

    /// The type the trait whose signatures are being read declares under this
    /// name, and null anywhere else.
    ///
    /// A trait's braces are the one place a member of it stands without a
    /// head, so the question is asked only while they are read: everywhere
    /// else a member is reached through what names the implementation that
    /// settles it.
    ///
    /// Through the members table, which is one lookup per name written and the
    /// same table a settled reference selects through -- what a trait holds is
    /// answered in one place, so a bare name and a dotted one cannot come to
    /// disagree about which declaration they reach.
    ///
    /// A member that is not a type answers nothing here. A signature's name in
    /// type position names no type, so it falls through to whatever else the
    /// name reaches and to the undefined name it is where nothing does.
    fn declaredTypeHere(self: *const Resolver, wanted: StringId) ?BindingId {
        if (self.trait_scope == DeclId.none) return null;
        const found = self.memberOf(
            self.moduleOf(self.trait_scope),
            self.ast.tokenName(self.ast.declName(self.trait_scope)),
            TokenId.none,
            wanted,
        ) orelse return null;
        if (self.bindings.items[found.index()].kind != .associated_type) return null;
        return found;
    }

    /// Refuses every alias that reaches itself through the type it names, and
    /// every alias that reaches further than a type it is written with.
    ///
    /// An alias is replaced by what it names wherever it is written, so one
    /// that names itself -- directly, inside an argument, or through another
    /// alias -- names no type at all: the replacement never ends. Each cycle
    /// is reported once, at the alias the walk found closing it.
    ///
    /// **Bound:** each alias is entered once and each token of what it wrote
    /// is read once, so the walk is linear in the aliases' text. The stack is
    /// explicit, because a generated chain of aliases may be longer than a
    /// thread's stack is deep.
    fn checkAliases(self: *Resolver, skip_libraries: bool) std.mem.Allocator.Error!void {
        const Mark = enum { walking, done };
        var marks: std.AutoHashMapUnmanaged(DeclId, Mark) = .empty;
        defer marks.deinit(self.gpa);
        const Frame = struct { alias: DeclId, next: u32 };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(self.gpa);

        for (self.program.modules, 0..) |module, i| {
            if (skip_libraries and module.library) continue;
            for (self.expanded.?.declsOf(.from(i))) |root| {
                if (self.ast.declTag(root) != .alias or marks.contains(root)) continue;
                try marks.put(self.gpa, root, .walking);
                try stack.append(self.gpa, .{ .alias = root, .next = self.ast.declName(root).index() + 1 });
                while (stack.items.len > 0) {
                    const top = &stack.items[stack.items.len - 1];
                    const end = self.ast.declTokens(top.alias).end.index();
                    const reached_alias: ?DeclId = found: while (top.next < end) {
                        const tok = TokenId.at(top.next);
                        top.next += 1;
                        if (tok.index() >= self.written.items.len) continue;
                        const b = self.written.items[tok.index()];
                        if (b == BindingId.none) continue;
                        const held = self.bindings.items[b.index()];
                        if (held.kind != .declared_type and held.kind != .type_alias) continue;
                        // The declaration's own reach, not the binding's: a
                        // `use` binding a published type privately still
                        // names a type every module may reach.
                        if (held.decl != DeclId.none) try self.refuseWiderAlias(top.alias, tok, reachForVisibility(self.ast.declVisibility(held.decl)));
                        if (held.kind != .type_alias) continue;
                        break :found held.decl;
                    } else null;
                    const next = reached_alias orelse {
                        try marks.put(self.gpa, top.alias, .done);
                        _ = stack.pop();
                        continue;
                    };
                    if (marks.get(next)) |mark| {
                        if (mark == .walking) try self.reportAliasCycle(next);
                        continue;
                    }
                    try marks.put(self.gpa, next, .walking);
                    try stack.append(self.gpa, .{ .alias = next, .next = self.ast.declName(next).index() + 1 });
                }
            }
        }
    }

    /// Refuses an alias that reaches further than a type it is written with.
    ///
    /// An alias is the type it names, so a wider alias would publish a
    /// declaration its own module kept: another module could build, take apart
    /// or name a structure its declaration never let it reach. The rule a
    /// re-export follows, that a second name narrows or preserves and never
    /// widens, holds for this second name too.
    fn refuseWiderAlias(self: *Resolver, alias: DeclId, at: TokenId, reach: Reach) std.mem.Allocator.Error!void {
        const own = reachForVisibility(self.ast.declVisibility(alias));
        if (@intFromEnum(reach) >= @intFromEnum(own)) return;
        const name = self.ast.declName(alias);
        try self.sink.addErrorFmt(
            .m_vis,
            self.ast.fileOf(at),
            self.ast.tokenSpan(at),
            try std.fmt.allocPrint(self.sink.arena, "declare `{s}` as widely as `{s}`, or narrow `{s}`", .{ self.ast.tokenText(at), self.ast.tokenText(name), self.ast.tokenText(name) }),
            "`{s}` reaches further than `{s}`, which it names",
            .{ self.ast.tokenText(name), self.ast.tokenText(at) },
        );
    }

    /// Records the type name each alias's written type is headed by, in every
    /// module a program reads, so a library's alias is read through as the
    /// program's own is. Each alias is followed once: a chain is walked to
    /// its end and every alias on it answered from there.
    ///
    /// **Bound:** one step per alias on each chain, with every alias answered
    /// once, so linear in the aliases.
    fn recordAliasHeads(self: *Resolver) std.mem.Allocator.Error!void {
        var chain: std.ArrayList(DeclId) = .empty;
        defer chain.deinit(self.gpa);
        for (self.program.modules, 0..) |_, i| {
            for (self.expanded.?.declsOf(.from(i))) |root| {
                if (self.ast.declTag(root) != .alias or self.alias_heads.contains(root)) continue;
                chain.clearRetainingCapacity();
                var at = root;
                const head: BindingId = while (true) {
                    try chain.append(self.gpa, at);
                    const b = self.writtenHead(at);
                    if (b == BindingId.none or self.bindings.items[b.index()].kind != .type_alias) break b;
                    const next = self.bindings.items[b.index()].decl;
                    if (self.alias_heads.get(next)) |known| break known;
                    // A cycle was refused where it was found, and heads nothing.
                    if (std.mem.indexOfScalar(DeclId, chain.items, next) != null) break .none;
                    at = next;
                };
                for (chain.items) |alias| {
                    if (head != BindingId.none) try self.alias_heads.put(self.gpa, alias, head);
                }
            }
        }
    }

    /// The binding the name heading an alias's written type reached, where a
    /// name heads it -- `Option` in `Option[UInt8]`, `Secret` in
    /// `m.Secret` -- and `.none` for a function, array, borrow or unit type.
    fn writtenHead(self: *const Resolver, alias: DeclId) BindingId {
        const written = self.ast.withoutTypeGroups(self.ast.declReturnRef(alias));
        const tok = switch (written.kind) {
            .named => written.name,
            .selection => if (self.moduleHeadingOf(written)) written.name else return .none,
            else => return .none,
        };
        if (tok == TokenId.none or tok.index() >= self.written.items.len) return .none;
        const b = self.written.items[tok.index()];
        if (b == BindingId.none) return .none;
        return switch (self.bindings.items[b.index()].kind) {
            .declared_type, .builtin_type, .type_alias => b,
            else => .none,
        };
    }

    /// Whether a dotted written type's head is a module, read from what the
    /// resolver recorded at that head.
    fn moduleHeadingOf(self: *const Resolver, ref: node.TypeRef) bool {
        const base = self.ast.withoutTypeGroups(self.ast.selectionBase(ref));
        if (base.kind != .named or base.name == .none or base.name.index() >= self.written.items.len) return false;
        const b = self.written.items[base.name.index()];
        return b != BindingId.none and self.bindings.items[b.index()].kind == .module;
    }

    /// The type name a path written through an alias reaches, or null where
    /// the path is refused: an alias of a function, array or parameter type
    /// holds nothing to select. A generic alias reaches the declaration its
    /// target is headed by, and the checker settles its parameters from the
    /// call.
    fn pathThroughAlias(self: *Resolver, id: ExprId, base: ExprId, alias_binding: BindingId) std.mem.Allocator.Error!?BindingId {
        const alias = self.bindings.items[alias_binding.index()].decl;
        const name = self.ast.exprMain(base);
        const head = self.throughAlias(alias_binding);
        if (head == BindingId.none) {
            try self.sink.addErrorFmt(
                .n_type_alias,
                self.ast.fileOfExpr(id),
                self.ast.exprSpan(id),
                "only a type a declaration names holds members",
                "`{s}` is an alias of `{s}`, which holds nothing to select",
                .{ self.ast.tokenText(name), self.ast.writtenText(self.ast.declReturnRef(alias)) },
            );
            return null;
        }
        return head;
    }

    /// The alias a name written in this module reaches, or null where it
    /// reaches anything else.
    fn aliasHere(self: *const Resolver, tok: TokenId) ?BindingId {
        if (tok == TokenId.none or self.ast.tokenTag(tok) != .identifier) return null;
        const b = self.type_in_module.get(self.ast.tokenName(tok)) orelse return null;
        return if (self.bindings.items[b.index()].kind == .type_alias) b else null;
    }

    /// Records the operations every implementation refused for an alias head
    /// declares, in one pass over the declarations and only where one was
    /// refused.
    fn recordRefusedOperations(self: *Resolver) std.mem.Allocator.Error!void {
        if (self.refused_impls.count() == 0) return;
        for (0..self.ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            const impl = self.implEnclosing(d);
            if (impl == DeclId.none or !self.refused_impls.contains(impl)) continue;
            try self.refused_operations.put(self.gpa, self.ast.tokenName(self.ast.declName(d)), {});
        }
    }

    /// See `Resolution.throughAlias`, read while the tables are being built.
    fn throughAlias(self: *const Resolver, b: BindingId) BindingId {
        if (b == BindingId.none or self.bindings.items[b.index()].kind != .type_alias) return b;
        return self.alias_heads.get(self.bindings.items[b.index()].decl) orelse .none;
    }

    fn reportAliasCycle(self: *Resolver, alias: DeclId) std.mem.Allocator.Error!void {
        const name = self.ast.declName(alias);
        try self.sink.addErrorFmt(
            .n_type_alias,
            self.ast.fileOf(name),
            self.ast.tokenSpan(name),
            "an alias names a type that already exists; a type holding itself is a `struct` or an `enum`",
            "`{s}` reaches itself through the type it names",
            .{self.ast.tokenText(name)},
        );
    }

    /// Refuses a trait written as the type an alias names, and says whether
    /// it did. An alias names a type, and a trait names none: said as that,
    /// rather than as a name nothing declares.
    fn refuseAliasedTrait(self: *Resolver, tok: TokenId) std.mem.Allocator.Error!bool {
        if (self.generic == DeclId.none or self.ast.declTag(self.generic) != .alias) return false;
        if (tok == TokenId.none or self.ast.tokenTag(tok) != .identifier) return false;
        const trait = self.traitNamed(tok);
        if (trait == BindingId.none) return false;
        self.bindings.items[trait.index()].used = true;
        self.reached(tok, trait);
        try self.sink.addErrorFmt(
            .n_type_alias,
            self.ast.fileOf(tok),
            self.ast.tokenSpan(tok),
            "an alias names a type; bound a type parameter by the trait instead",
            "`{s}` names `{s}`, which is a trait rather than a type",
            .{ self.ast.tokenText(self.ast.declName(self.generic)), self.ast.tokenText(tok) },
        );
        return true;
    }

    /// A written type naming nothing.
    ///
    /// Reported rather than left, because an annotation naming nothing poisons
    /// what it annotates, and a poisoned value nobody diagnosed is every rule
    /// about it silently skipped.
    fn reportUnknownType(self: *Resolver, tok: TokenId) void {
        // `Self` names the type of an implementation for a named type or a
        // tuple; an implementation for `()` has no name to stand for.
        const label = if (namesSelf(self.ast, tok))
            "`Self` is declared in an implementation for a named type or a tuple; write the type, as `()` for unit"
        else
            "no type with this name is declared here";
        self.sink.addErrorFmt(
            .n_undefined,
            self.ast.fileOf(tok),
            self.ast.tokenSpan(tok),
            label,
            "undefined name `{s}`",
            .{self.ast.tokenText(tok)},
        ) catch {};
    }

    /// Resolves one constant's initialiser.
    ///
    /// An initializer against the module's scope and its own parameters.
    /// Constants declare none; a traversal may bind the value being walked.
    ///
    /// It is cut back afterwards all the same. An initialiser is an expression
    /// like any other and a block, an `if` or a `match` written in one declares
    /// locals, so leaving them visible would let the next constant's
    /// initialiser reach a name the one before it wrote.
    fn constantInitialiser(self: *Resolver, d: DeclId) !void {
        const init_expr = self.ast.declInit(d);
        if (init_expr == ExprId.none) return;
        const mark = self.visible.items.len;
        defer self.popLocalsTo(mark);
        const scope = try self.openScope();
        defer self.closeScope(scope);
        self.generic = d;
        defer self.generic = DeclId.none;
        self.impl_scope = self.implEnclosing(d);
        defer self.impl_scope = DeclId.none;
        try self.declareParameters(d);
        try self.expr(init_expr);
    }

    fn declareParameters(self: *Resolver, d: DeclId) !void {
        // The namespace chain is searched nearest first; scope enumeration
        // walks each recorded run backwards, so record the outer owners first.
        const owners = [_]DeclId{ self.trait_scope, self.impl_scope, d };
        for (owners, 0..) |owner, i| {
            if (owner == .none) continue;
            if (std.mem.indexOfScalar(DeclId, owners[0..i], owner) != null) continue;
            for (self.ast.declTypeParams(owner)) |parameter| {
                try self.declaredHere(self.type_parameter_bindings.get(parameter.name).?);
            }
        }
        // A second parameter of one spelling was refused where the list was
        // read; the first keeps the name, and the second is neither visible
        // nor reported unused.
        var names: std.AutoHashMapUnmanaged(StringId, void) = .empty;
        defer names.deinit(self.gpa);
        for (self.ast.declParams(d), 0..) |p, i| {
            if (self.ast.tokenTag(p.name) != .identifier) continue;
            const text = self.ast.tokenText(p.name);
            const repeated = (try names.getOrPut(self.gpa, self.ast.tokenName(p.name))).found_existing;
            if (!repeated) try self.pushLocal(
                BindingId.at(@intCast(self.bindings.items.len)),
                self.ast.tokenName(p.name),
            );
            try self.bindings.append(self.gpa, .{
                .name = self.ast.tokenName(p.name),
                .kind = .parameter,
                .stmt = StmtId.none,
                .decl = d,
                .param_index = @intCast(i),
                .parameter_owner = .{ .declaration = d },
                .at = p.name,
                .used = false,
                // Only an `inout` parameter permits writes to the caller's value.
                .mutable = p.convention == .inout,
                // Bodyless signatures declare parameter names for callers and
                // implementations; they cannot use those parameters themselves.
                .exempt = repeated or p.recovered or std.mem.startsWith(u8, text, "_") or
                    (self.ast.declBody(d) == ExprId.none and self.ast.declInit(d) == ExprId.none),
            });
        }
    }

    /// Resolves one function's or projection's body. Phase two.
    ///
    /// The chain is cut back to the module scope first, so a body sees its own
    /// parameters, its own blocks and the declarations -- and never the locals
    /// of the function resolved before it. Functions do not nest, so the floor
    /// a body needs is exactly this truncation.
    ///
    /// A projection's body is a path rather than code, and a path is written
    /// out of the same names: `self` is its parameter and an index names
    /// whatever is in scope. Resolved by this walk rather than by one of its
    /// own, so what a name in a projection reaches is what a name anywhere
    /// reaches.
    fn function(self: *Resolver, d: DeclId, module_scope: usize) !void {
        // A type declares no body and no names of its own, and a constant's
        // initialiser is read where implementations are compared, which is
        // earlier than this.
        if (self.ast.declTag(d) != .function and self.ast.declTag(d) != .projection) return;
        self.popLocalsTo(module_scope);

        // The parameters are a scope of their own, which the body's own scope
        // sits below: a local of a parameter's name shadows it, exactly as one
        // block's local shadows an outer block's.
        const params = try self.openScope();
        defer self.closeScope(params);

        // Its own type parameters answer for the whole body, as they do for
        // the signature: `T` in an annotation inside this function is this
        // function's `T`, and a body walked without them would find a
        // module-level type of that name or nothing at all.
        self.generic = d;
        defer self.generic = DeclId.none;

        // And the implementation's, for the same reason: an annotation inside
        // a member of one names its parameters exactly as its signature does.
        self.impl_scope = if (self.template_validation) |validation| validation.reflection.template else self.implEnclosing(d);
        defer self.impl_scope = DeclId.none;
        // And a provided operation's trait's, for the same reason again: its
        // body names the trait's parameters as its signature does.
        self.trait_scope = if (self.ast.declIsProvided(d)) self.signatures.?.traitOf(self.ast, d) orelse DeclId.none else DeclId.none;
        defer self.trait_scope = DeclId.none;

        try self.declareParameters(d);

        // A default is an expression like any other the declaration writes,
        // so a name in it is a use like any other -- resolved here, in the
        // scope every parameter has already been pushed into, rather than
        // left for whichever pass eventually reads the default's value. A
        // signature has no body and so never reaches the walk below; its
        // defaults would go unresolved without this.
        for (self.ast.declParams(d)) |p| {
            if (p.default != ExprId.none) try self.expr(p.default);
        }

        const body = self.ast.declBody(d);
        if (body != ExprId.none) try self.expr(body);
    }

    /// Exhaustive on purpose. A statement kind added later has to be given an
    /// answer here rather than falling through a chain of tests and reaching
    /// none -- which is what a `defer` did, leaving every name a scheduled
    /// expression used reported as declared and never referenced.
    fn declare(self: *Resolver, s: StmtId) !void {
        self.scope_of_stmt.items[s.index()] = self.scope;
        switch (self.ast.stmtTag(s)) {
            // Already diagnosed. Whatever the parser could not read has no
            // names worth resolving.
            .err => {},
            .expr_stmt => try self.expr(self.ast.stmtData(s).init),
            // Resolved where it is written. Where it *runs* is the ownership
            // graph's answer, and a name a deferred expression uses is used.
            //
            // A `defer` the parser read no expression for carries none, and
            // every pass below still runs over the tree it produced.
            .defer_stmt => {
                const scheduled = self.ast.stmtData(s).init;
                if (scheduled != ExprId.none) try self.expr(scheduled);
            },
            // The release a `defer let` schedules names only the binding just
            // declared. Its callee is the operation the checker finds for the
            // type, so the one name to resolve is the receiver.
            .defer_release => try self.expr(self.ast.call(self.ast.stmtData(s).init).args[0]),
            .let_destructure, .let_read_destructure => try self.destructure(s),
            .let_decl => try self.declareLocal(s),
        }
    }

    fn declareLocal(self: *Resolver, s: StmtId) !void {
        const d = self.ast.stmtData(s);

        // Every type the annotation names, not just its head: `Cell[Opt]` names
        // `Opt`, and a type reachable only as an argument was otherwise
        // reported unused with no way to write the program differently.
        try self.useRef(d.annotation);

        // The initialiser is resolved before the binding becomes visible, so a
        // reference to the name being bound is undefined rather than circular.
        if (d.init != ExprId.none) try self.expr(d.init);

        const named = self.ast.tokenTag(d.name) == .identifier;
        const name = if (named) self.ast.tokenName(d.name) else StringId.none;

        const binding = BindingId.at(@intCast(self.bindings.items.len));
        try self.pushLocal(binding, name);
        try self.bindings.append(self.gpa, .{
            .name = name,
            .kind = .local,
            .stmt = s,
            .decl = DeclId.none,
            .param_index = 0,
            .at = d.name,
            .used = false,
            .mutable = self.ast.stmtIsMutable(s),
            .exempt = !named or
                std.mem.startsWith(u8, self.ast.tokenText(d.name), "_") or
                self.containsErr(d.init),
        });
        if (self.template_validation) |validation| {
            if (!self.ast.stmtIsMutable(s) and !d.annotation.wasWritten()) {
                if (self.templateClosureOf(d.init)) |closure| {
                    try validation.reflection.closure_bindings.put(self.gpa, binding, closure);
                    try self.noteTemplateClosureUse(d.init);
                }
            } else if (self.ast.withoutTypeGroups(d.annotation).kind == .callable) {
                // A structural conversion owns its labels independently of the body.
                try self.noteTemplateClosureUse(d.init);
            }
        }
    }

    /// Source templates are erased before checking. An unconverted immutable
    /// closure binding preserves its authored callable identity without typing.
    fn templateClosureOf(self: *const Resolver, expression: ExprId) ?ClosureId {
        const validation = self.template_validation orelse return null;
        return validation.reflection.closure_values.get(expression);
    }

    fn noteTemplateClosureValue(self: *Resolver, expression: ExprId) !void {
        const validation = self.template_validation orelse return;
        const closure = switch (self.ast.exprTag(expression)) {
            .lambda => self.closures.of_expr[expression.index()],
            .name_ref => validation.reflection.closure_bindings.get(self.targets.items[expression.index()]) orelse return,
            .grouped, .copy_, .borrow, .dereference => blk: {
                const operand = self.ast.unaryOperand(expression);
                const source = self.templateClosureOf(operand) orelse return;
                try self.noteTemplateClosureUse(operand);
                break :blk source;
            },
            else => return,
        };
        if (closure != .none) try validation.reflection.closure_values.put(self.gpa, expression, closure);
    }

    fn noteTemplateClosureUse(self: *Resolver, expression: ExprId) !void {
        const validation = self.template_validation orelse return;
        if (self.templateClosureOf(expression) != null)
            try validation.reflection.closure_uses.put(self.gpa, expression, {});
    }

    fn noteTemplateClosureCapture(self: *Resolver, owner: ClosureId, binding: BindingId, source: ExprId) !void {
        const validation = self.template_validation orelse return;
        const closure = self.templateClosureOf(source) orelse return;
        try validation.reflection.closure_bindings.put(self.gpa, binding, closure);
        try self.noteTemplateClosureUse(source);
        const captured = try validation.reflection.captured_closures.getOrPut(self.gpa, owner);
        if (!captured.found_existing) captured.value_ptr.* = .empty;
        try captured.value_ptr.append(self.gpa, closure);
    }

    /// Every known closure value must have a recorded identity-preserving use or
    /// a structural conversion. Other escapes make source parameter rename unsafe.
    /// Captured callable dependencies propagate refusal once per reached closure.
    fn finishTemplateClosureUses(self: *Resolver, context: *const ReflectionContext) !void {
        var pending: std.ArrayList(ClosureId) = .empty;
        defer pending.deinit(self.gpa);
        var values = context.closure_values.iterator();
        while (values.next()) |entry| {
            if (context.closure_uses.contains(entry.key_ptr.*)) continue;
            const held = try self.unpaired_template_closures.getOrPut(self.gpa, entry.value_ptr.*);
            if (!held.found_existing) try pending.append(self.gpa, entry.value_ptr.*);
        }
        while (pending.pop()) |closure| {
            const captured = context.captured_closures.get(closure) orelse continue;
            for (captured.items) |source| {
                const held = try self.unpaired_template_closures.getOrPut(self.gpa, source);
                if (!held.found_existing) try pending.append(self.gpa, source);
            }
        }
    }

    fn noteTemplateClosureCall(self: *Resolver, call: ExprId) !void {
        const validation = self.template_validation orelse return;
        const closure = self.templateClosureOf(self.ast.call(call).callee) orelse return;
        try self.noteTemplateClosureUse(self.ast.call(call).callee);
        for (self.ast.callNames(call)) |name| {
            if (name == .none) continue;
            const binding = validation.reflection.closure_parameters.get(.{ .closure = closure, .name = self.ast.tokenName(name) }) orelse continue;
            self.reached(name, binding);
        }
    }

    fn noteTemplateClosureContracts(self: *Resolver, closure: ClosureId, contracts: node.ContractRange) void {
        if (self.template_validation == null) return;
        for (self.ast.contracts[contracts.start..contracts.end]) |contract| {
            for ([_]node.ContractPath{ contract.source, if (contract.kind == .retains) contract.destination else .empty }) |path| {
                if (path.root == .none) continue;
                const local = self.local_of.get(self.ast.tokenName(path.root)) orelse continue;
                const binding = self.visible.items[local];
                const held = self.bindings.items[binding.index()];
                const owned = switch (held.kind) {
                    .parameter => held.parameter_owner == .closure and held.parameter_owner.closure == closure,
                    .capture => self.capture_bindings.get(binding).?.closure == closure,
                    else => false,
                };
                if (owned) self.reached(path.root, binding);
            }
        }
    }

    /// Why a name appears.
    const Use = enum {
        read,
        /// Written to. A local only ever assigned is still unused, because
        /// nothing observes what was written; an `inout` parameter only ever
        /// assigned is used, because the caller does.
        assigned,
        /// Handed to something that will mutate it. Both a use and a write:
        /// the callee may read it, and it must be a binding that may change.
        mutated,
    };

    fn reportImmutable(self: *Resolver, id: ExprId, binding: BindingId) std.mem.Allocator.Error!void {
        const held = self.bindings.items[binding.index()];
        try reportImmutableBinding(self.sink, self.ast, id, held.kind, held.at);
    }

    fn reportReflection(self: *Resolver, id: ExprId, hint: []const u8, label: []const u8) !void {
        if (self.template_validation) |validation| validation.reflection.valid = false;
        try self.sink.addError(
            .t_reflection,
            self.ast.fileOfExpr(id),
            self.ast.exprSpan(id),
            hint,
            label,
        );
    }

    fn fieldOver(self: *const Resolver, id: ExprId, name: []const u8) ?ExprId {
        if (id == .none or self.ast.exprTag(id) != .field) return null;
        if (!std.mem.eql(u8, self.ast.tokenText(self.ast.exprMain(id)), name)) return null;
        return self.ast.unaryOperand(id);
    }

    fn isReflectedCase(self: *const Resolver, id: ExprId) bool {
        const root = self.fieldOver(id, "case") orelse return false;
        return self.ast.exprTag(root) == .reflection_root;
    }

    fn isReflectionField(self: *const Resolver, id: ExprId, name: []const u8) bool {
        const root = self.fieldOver(id, name) orelse return false;
        return self.ast.exprTag(root) == .reflection_root;
    }

    fn reflectionMetadata(self: *Resolver, id: ExprId) !bool {
        const validation = self.template_validation orelse return false;
        const context = validation.reflection;
        const name = self.ast.tokenText(self.ast.exprMain(id));

        if (self.ast.exprTag(id) == .field) {
            const receiver = self.ast.unaryOperand(id);
            if (self.isReflectedCase(receiver)) {
                const kind: MetadataPlan.Kind = if (std.mem.eql(u8, name, "name"))
                    .case_name
                else if (std.mem.eql(u8, name, "ordinal"))
                    .case_ordinal
                else if (std.mem.eql(u8, name, "components_named"))
                    .components_named
                else
                    return false;
                if (context.active_case_depth == 0) {
                    try self.reportReflection(id, "use case metadata inside an active `reflect.case`", "this case metadata has no active case");
                    return true;
                }
                try context.metadata.append(self.gpa, .{ .expression = id, .kind = kind });
                return true;
            }

            const active_loop = context.active_loop orelse return false;
            if (self.ast.exprTag(receiver) != .name_ref) return false;
            if (self.ast.tokenName(self.ast.exprMain(receiver)) != self.bindings.items[active_loop.binder.index()].name) return false;
            const kind: MetadataPlan.Kind = if (std.mem.eql(u8, name, "name"))
                .component_name
            else if (std.mem.eql(u8, name, "ordinal"))
                .component_ordinal
            else
                return false;
            context.component_receiver = true;
            try self.expr(receiver);
            context.component_receiver = false;
            if (self.targets.items[receiver.index()] != active_loop.binder) return false;
            try context.metadata.append(self.gpa, .{ .expression = id, .kind = kind });
            return true;
        }
        return false;
    }

    fn reflectionComponentType(self: *Resolver, ref: node.TypeRef) std.mem.Allocator.Error!bool {
        const validation = self.template_validation orelse return false;
        const context = validation.reflection;
        if (context.recipe_floor == null or ref.kind != .selection) return false;
        const descriptor = context.active_loop orelse return false;
        const base = self.ast.withoutTypeGroups(self.ast.selectionBase(ref));
        if (base.kind != .named or base.name == .none) return false;
        const local = self.local_of.get(self.ast.tokenName(base.name)) orelse return false;
        if (self.visible.items[local] != descriptor.binder) return false;
        if (base.args.len() != 0 or ref.name == .none or !std.mem.eql(u8, self.ast.tokenText(ref.name), "Type") or ref.args.len() != 0) {
            context.valid = false;
            try self.sink.addError(.t_reflection, self.ast.fileOf(base.name), self.ast.tokenSpan(base.name), "write `component.Type` without arguments", "this is not a construction component type");
            return true;
        }
        self.bindings.items[descriptor.binder.index()].used = true;
        self.reached(base.name, descriptor.binder);
        try context.component_types.append(self.gpa, .{ .tokens = .{ .start = ref.at, .end = TokenId.at(ref.name.index() + 1) }, .selection_base = context.selection_bases.contains(ref.at) });
        return true;
    }

    fn recordRecipeLocal(self: *Resolver, context: *ReflectionContext, rename: reflection.LocalRename) !void {
        const entry = try context.local_tokens.getOrPut(self.gpa, rename.at);
        if (entry.found_existing) {
            context.locals.items[entry.value_ptr.*] = rename;
        } else {
            entry.value_ptr.* = @intCast(context.locals.items.len);
            try context.locals.append(self.gpa, rename);
        }
    }

    fn recipeRenamesBinding(self: *const Resolver, binding: BindingId) bool {
        const held = self.bindings.items[binding.index()];
        // Lambda parameter labels and capture names belong to the callable's
        // own scope and contracts, even when its enclosing recipe is copied.
        return held.kind != .capture and
            !(held.kind == .parameter and held.parameter_owner == .closure);
    }

    fn reflectionConstruction(self: *Resolver, id: ExprId) !bool {
        const call = self.ast.call(id);
        if (!self.isReflectionField(call.callee, "construct")) return false;
        const validation = self.template_validation;
        if (validation == null or call.args.len != 3) {
            try self.reportReflection(id, "construct a product with a descriptor recipe and finalization block", "`reflect.construct` takes three arguments inside a template member");
            return true;
        }
        const context = validation.?.reflection;
        const product = self.isReflectionField(call.args[0], "product");
        const active_case = self.isReflectedCase(call.args[0]) and context.active_case_depth != 0;
        if (context.active_loop != null) {
            try self.reportReflection(id, "finish the enclosing component recipe or reflected loop before constructing", "construction cannot nest inside a component recipe or reflected loop");
            return true;
        }
        if (!product and !active_case) {
            try self.reportReflection(call.args[0], "select `reflect.product` or the active `reflect.case`", "this expression does not select a construction target");
            return true;
        }
        if (self.ast.exprTag(call.args[1]) != .lambda or self.ast.exprTag(call.args[2]) != .block) {
            try self.reportReflection(id, "supply a descriptor recipe and a finalization block", "construction requires `|component| { ...; local }` followed by a block");
            return true;
        }
        const lambda = self.ast.lambda(call.args[1]);
        if (lambda.params.len != 1 or lambda.captures.len != 0 or lambda.capture_open != .none or
            lambda.invocation_token != .none or lambda.result_arrow != .none or lambda.contracts.start != lambda.contracts.end or
            self.ast.exprTag(lambda.body) != .block)
        {
            try self.reportReflection(call.args[1], "write `|component| { ...; local }`", "a construction recipe has one descriptor, no captures, convention or return annotation");
            return true;
        }
        const parameter = lambda.params[0];
        if (parameter.written.wasWritten() or parameter.default != .none or parameter.convention != .read or parameter.pattern != .none) {
            try self.reportReflection(call.args[1], "leave the recipe descriptor unannotated", "a component descriptor is not a callable parameter");
            return true;
        }
        for (lambda.open.index() + 1..parameter.name.index()) |index| {
            if (!self.ast.tokenTag(TokenId.at(@intCast(index))).isTrivia()) {
                try self.reportReflection(call.args[1], "write only the descriptor name between pipes", "a construction descriptor has no passing convention");
                return true;
            }
        }
        const block = self.ast.blockOf(lambda.body);
        if (block.tail == .none) {
            try self.reportReflection(lambda.body, "finish the recipe with a directly declared local", "a construction recipe must yield its completed field binding");
            return true;
        }
        var result = block.tail;
        while (self.ast.exprTag(result) == .grouped) result = self.ast.unaryOperand(result);
        if (self.ast.exprTag(result) != .name_ref) {
            try self.reportReflection(block.tail, "name a local `let` or `var` from this recipe", "an arbitrary expression cannot be a construction recipe result");
            return true;
        }
        const mark = self.visible.items.len;
        const scope = try self.openScope();
        const descriptor = BindingId.at(@intCast(self.bindings.items.len));
        try self.pushLocal(descriptor, self.ast.tokenName(parameter.name));
        try self.bindings.append(self.gpa, .{
            .name = self.ast.tokenName(parameter.name),
            .kind = .binder,
            .stmt = .none,
            .decl = .none,
            .param_index = 0,
            .at = parameter.name,
            .used = true,
            .mutable = false,
            .exempt = true,
        });
        const floor = self.bindings.items.len;
        const previous_loop = context.active_loop;
        context.active_loop = .{ .loop = id, .binder = descriptor, .body = lambda.body, .reversed = false };
        context.recipe_floor = floor;
        self.expr(lambda.body) catch |err| {
            context.recipe_floor = null;
            context.active_loop = previous_loop;
            self.popLocalsTo(mark);
            self.closeScope(scope);
            return err;
        };
        context.recipe_floor = null;
        context.active_loop = previous_loop;
        self.popLocalsTo(mark);
        self.closeScope(scope);
        const result_binding = self.targets.items[result.index()];
        var direct = false;
        if (result_binding != .none and result_binding.index() >= floor) {
            const held = self.bindings.items[result_binding.index()];
            for (self.ast.blockStmts(block)) |statement| {
                if (self.ast.stmtTag(statement) != .let_decl and self.ast.stmtTag(statement) != .let_destructure) continue;
                const span = self.ast.stmtSpan(statement);
                const name = self.ast.tokenSpan(held.at);
                if (span.start <= name.start and name.end <= span.end) direct = true;
            }
        }
        if (!direct) {
            try self.reportReflection(result, "yield a binding declared directly by this recipe", "the result cannot be the descriptor, an outer binding or a nested-scope local");
            return true;
        }
        const recipe_tokens = self.ast.exprTokens(lambda.body);
        for (recipe_tokens.start.index()..recipe_tokens.end.index()) |index| {
            const binding = validation.?.references[index - validation.?.token_start];
            if (binding == .none or binding.index() < floor) continue;
            if (!self.recipeRenamesBinding(binding)) continue;
            const at = TokenId.at(@intCast(index));
            try self.recordRecipeLocal(context, .{ .at = at, .binding = binding, .kind = if (context.shorthand_values.contains(at)) .field_value else .plain });
        }
        for (self.bindings.items[floor..], floor..) |held, index| {
            if (held.at == .none) continue;
            var rename: reflection.LocalRename = .{ .at = held.at, .binding = BindingId.at(@intCast(index)), .kind = if (held.names_a_field) .field_binder else .plain };
            if (held.kind == .capture) {
                const captured = self.capture_bindings.get(rename.binding).?;
                const range = self.capture_ranges.items[captured.closure.index()];
                const capture = self.captures.items[range.start + captured.index];
                if (self.ast.exprTag(capture.source) == .name_ref and self.ast.exprMain(capture.source) == held.at) {
                    rename.kind = .capture;
                    const source = self.targets.items[capture.source.index()];
                    if (source != .none and source.index() >= floor and self.recipeRenamesBinding(source)) rename.source = source;
                } else continue;
            } else if (!self.recipeRenamesBinding(rename.binding)) continue;
            try self.recordRecipeLocal(context, rename);
        }
        try context.constructions.append(self.gpa, .{ .call = id, .recipe = lambda.body, .finalization = call.args[2], .result = result_binding, .product = product });
        try self.expr(call.args[2]);
        return true;
    }

    fn reflectionOrdinal(self: *Resolver, id: ExprId) !bool {
        const call = self.ast.call(id);
        const root = self.fieldOver(call.callee, "ordinal_of") orelse return false;
        if (self.ast.exprTag(root) != .reflection_root) return false;
        const validation = self.template_validation;
        if (validation == null or
            validation.?.reflection.active_case_depth != 0 or
            validation.?.reflection.active_loop != null or
            call.args.len != 1)
        {
            try self.reportReflection(id, "call `reflect.ordinal_of(value)` outside reflected cases and component loops", "this ordinal operation cannot expand at one source point");
            for (call.args) |arg| try self.expr(arg);
            return true;
        }
        try self.expr(call.args[0]);
        try validation.?.reflection.ordinals.append(self.gpa, .{ .call = id, .operand = call.args[0] });
        return true;
    }

    /// `reflect.wrap(value)` constructs the variant whose only field has the
    /// type its argument, a parameter of the member, is written with. It needs
    /// an enum target, and the derive entry selects the variant.
    fn reflectionWrap(self: *Resolver, id: ExprId) !bool {
        const call = self.ast.call(id);
        const root = self.fieldOver(call.callee, "wrap") orelse return false;
        if (self.ast.exprTag(root) != .reflection_root) return false;
        const validation = self.template_validation;
        if (validation == null or
            validation.?.reflection.active_case_depth != 0 or
            validation.?.reflection.active_loop != null or
            call.args.len != 1)
        {
            try self.reportReflection(id, "call `reflect.wrap(parameter)` with one parameter, outside reflected cases and component loops", "this wrap cannot expand at one source point");
            for (call.args) |arg| try self.expr(arg);
            return true;
        }
        const context = validation.?.reflection;
        try self.expr(call.args[0]);
        var enum_target = false;
        for (self.ast.templateRequirements(context.template)) |requirement| {
            if (requirement.kind == .target and requirement.target_shape == .enum_) enum_target = true;
        }
        if (!enum_target) {
            try self.reportReflection(id, "state `reflect.target: enum` in the template", "`reflect.wrap` constructs an enum variant");
            return true;
        }
        const binding = if (self.ast.exprTag(call.args[0]) == .name_ref) self.targets.items[call.args[0].index()] else BindingId.none;
        if (binding == .none or self.bindings.items[binding.index()].kind != .parameter or self.bindings.items[binding.index()].decl != context.member) {
            try self.reportReflection(call.args[0], "wrap a parameter of this member", "the variant is selected by the written type of a parameter");
            return true;
        }
        try context.wraps.append(self.gpa, .{ .call = id, .callee = call.callee, .parameter = self.bindings.items[binding.index()].param_index });
        return true;
    }

    fn rootedInReflection(self: *const Resolver, id: ExprId) bool {
        var at = id;
        while (true) switch (self.ast.exprTag(at)) {
            .field, .grouped => at = self.ast.unaryOperand(at),
            .call => at = self.ast.call(at).callee,
            .index => at = self.ast.binary(at).lhs,
            .reflection_root => return true,
            else => return false,
        };
    }

    fn reflectedComponents(self: *const Resolver, id: ExprId) ?bool {
        if (self.fieldOver(id, "components")) |root| {
            if (self.ast.exprTag(root) == .reflection_root) return false;
        }
        const components = self.fieldOver(id, "reversed") orelse return null;
        const root = self.fieldOver(components, "components") orelse return null;
        if (self.ast.exprTag(root) != .reflection_root) return null;
        return true;
    }

    /// Resolves a component descriptor call when the receiver is the active
    /// reflected loop binder.
    fn componentPlace(self: *Resolver, id: ExprId) !bool {
        const validation = self.template_validation orelse return false;
        const active_loop = validation.reflection.active_loop orelse return false;
        const call = self.ast.call(id);
        const receiver = self.fieldOver(call.callee, "of") orelse return false;
        if (self.ast.exprTag(receiver) != .name_ref) return false;
        if (self.ast.tokenName(self.ast.exprMain(receiver)) != self.bindings.items[active_loop.binder.index()].name) return false;

        validation.reflection.component_receiver = true;
        try self.expr(receiver);
        validation.reflection.component_receiver = false;
        if (self.targets.items[receiver.index()] != active_loop.binder) {
            for (call.args) |arg| try self.expr(arg);
            return true;
        }
        if (validation.reflection.recipe_floor != null) {
            try self.reportReflection(id, "use recipe metadata `name`, `ordinal` or written `Type`", "a construction descriptor has no observed subject");
            return true;
        }

        for (call.args) |arg| try self.expr(arg);
        if (call.args.len != 1) {
            try self.reportReflection(id, "pass exactly the active reflected subject", "a component's `of` operation takes one subject");
            return true;
        }
        const subject = call.args[0];
        const subject_binding = self.targets.items[subject.index()];
        var active = false;
        for (validation.reflection.active_subjects.items) |candidate| {
            if (candidate == subject_binding) active = true;
        }
        if (!active) {
            try self.reportReflection(subject, "name the subject matched by the active `reflect.case`", "this is not the active reflected subject");
            return true;
        }
        try validation.reflection.places.append(self.gpa, .{
            .call = id,
            .loop = active_loop.loop,
            .subject_binding = subject_binding,
        });
        return true;
    }

    fn ordinaryLoopBody(self: *Resolver, body: ExprId) !void {
        if (self.template_validation) |validation| {
            if (validation.reflection.active_loop != null) {
                validation.reflection.runtime_loop_depth += 1;
                defer validation.reflection.runtime_loop_depth -= 1;
                return self.expr(body);
            }
        }
        try self.expr(body);
    }

    fn transferTargetsReflectedLoop(self: *const Resolver) bool {
        const validation = self.template_validation orelse return false;
        return validation.reflection.active_loop != null and validation.reflection.runtime_loop_depth == 0;
    }

    /// Records what a reference reached, and what reaching it means for the
    /// binding. One statement of it, for both halves of the search.
    fn bindTo(self: *Resolver, id: ExprId, use: Use, b: BindingId) std.mem.Allocator.Error!void {
        const i = b.index();
        self.noteTemplateBinding(self.ast.exprMain(id), b);
        if (self.current_closure != .none and i < self.closure_binding_start) {
            switch (self.bindings.items[i].kind) {
                .local, .parameter, .capture, .binder => {
                    const at = self.current_closure.index();
                    if (self.free_references.items[at] == .none) self.free_references.items[at] = id;
                },
                else => {},
            }
        }
        switch (use) {
            .read => self.bindings.items[i].used = true,
            .assigned => if (self.bindings.items[i].mutable) {
                // Writes through parameters, lending binders, and mutable
                // captures remain visible to their callers or owners. A local
                // only assigned has no observer and remains unused.
                switch (self.bindings.items[i].kind) {
                    .parameter, .binder, .capture => self.bindings.items[i].used = true,
                    else => {},
                }
            } else {
                try self.reportImmutable(id, b);
            },
            .mutated => {
                self.bindings.items[i].used = true;
                if (!self.bindings.items[i].mutable) {
                    if (self.lending_mark != .none) {
                        try self.deferred_immutable.append(self.gpa, .{ .mark = self.lending_mark, .name = id, .binding = b });
                    } else try self.reportImmutable(id, b);
                }
            },
        }
        self.settle(id, b, self.ast.exprMain(id));
        try self.noteTemplateClosureValue(id);
        if (self.template_validation) |validation| {
            if (validation.reflection.active_loop) |active_loop| {
                if (b == active_loop.binder and !validation.reflection.component_receiver) {
                    try self.reportReflection(id, "use the descriptor as `component.of(subject)`", "a component descriptor is not a runtime value");
                }
            }
        }
    }

    /// Resolves a name to the binding it refers to.
    ///
    /// Assignment resolves by this same rule rather than one of its own, which
    /// is what makes an assignment inside a block reach a binding declared
    /// outside it.
    fn nameRef(self: *Resolver, id: ExprId, use: Use) std.mem.Allocator.Error!void {
        if (self.ast.exprTag(id) != .name_ref) {
            // Already diagnosed as a region the parser gave up on.
            if (self.ast.exprTag(id) == .err) return;
            return self.sink.addError(
                .s_name,
                self.ast.fileOfExpr(id),
                self.ast.exprSpan(id),
                "expected a name",
                switch (use) {
                    .mutated => "`&` marks a binding the call writes to",
                    else => "an assignment names the binding it writes to",
                },
            );
        }

        const name = self.ast.tokenName(self.ast.exprMain(id));

        // What the index stands for: `enter` fills the module's run and every
        // scope below it pushes and pops above. A cut into the run would leave
        // the index answering for bindings no longer in the chain.
        std.debug.assert(self.visible.items.len >= self.module_run);

        if (self.lookupName(name)) |found| switch (found) {
            .binding => |b| return self.bindTo(id, use, b),
            .type_parameter => |param| {
                if (self.marks_for == param.of and param.at < self.used_type_params.items.len) self.used_type_params.items[param.at] = true;
                return self.bindTo(id, use, self.type_parameter_bindings.get(param.written.name).?);
            },
            .unresolved_use => |b| {
                self.bindings.items[b.index()].used = true;
                return;
            },
        };

        try self.sink.addErrorFmt(
            .n_undefined,
            self.ast.fileOfExpr(id),
            self.ast.exprSpan(id),
            "no binding with this name is in scope",
            "undefined name `{s}`",
            .{self.ast.tokenText(self.ast.exprMain(id))},
        );
    }

    /// A place that will be written: a name, or a name followed by fields.
    ///
    /// Permission belongs to the name at the root, so the chain is walked down
    /// to it and reported there. A field carrying its own permission is a
    /// separate rule, and the one deciding which of the two wins does not
    /// exist yet.
    ///
    /// An assignment target and the operand of `&` are the same thing asked in
    /// two places, which is why one routine answers both: `o.inner.y = 1` and
    /// `bump(&o.inner.y)` write the same bytes through the same permission.
    fn place(self: *Resolver, id: ExprId, use: Use) std.mem.Allocator.Error!void {
        // Parentheses are a node, and a place written inside them is the same
        // place: `(o).inner.y = 1` writes what `o.inner.y = 1` writes.
        var at = self.ast.withoutGroups(id);

        // Only the name at the root is written to. The steps along the way are
        // neither read nor written here -- a field belongs to a type rather
        // than to a scope, so there is no binding for it to reach -- but an
        // index is an ordinary expression and resolves in the scope the whole
        // place sits in.
        while (true) {
            switch (self.ast.exprTag(at)) {
                // The observation is read; typing checks the referent's write permission.
                .dereference => return self.expr(self.ast.unaryOperand(at)),
                .field => at = self.ast.withoutGroups(self.ast.unaryOperand(at)),
                .index => {
                    try self.expr(self.ast.binary(at).rhs);
                    at = self.ast.withoutGroups(self.ast.binary(at).lhs);
                },
                else => break,
            }
        }
        // A root that is no name is no place, and `nameRef` says so. It is
        // still an expression, so the names inside it are resolved and used:
        // `bump(&(fresh()))` calls `fresh` however the mark is refused.
        switch (self.ast.exprTag(at)) {
            .name_ref, .err => {},
            else => try self.expr(at),
        }
        try self.nameRef(at, use);
    }

    /// Whether an expression is a path `place` could walk: the chain above,
    /// ending at a binding or an observation dereference.
    ///
    /// Asked where a construct treats a place and a value differently and has
    /// to decide before it walks -- a `for inout` marks what it walks the way
    /// `&` marks one, and a head that is not a place is an ordinary expression
    /// rather than a mistake about names. The chain it steps through is the one
    /// above, and what it leaves out is the resolving: this decides whether the
    /// chain is one to walk, and `place` walks it.
    fn namesAPlace(self: *const Resolver, id: ExprId) bool {
        var steps = self.ast.placeSteps(id);
        while (steps.next()) |step| if (self.ast.exprTag(step) == .dereference) return true;
        return self.ast.exprTag(steps.at) == .name_ref;
    }

    /// Whether a module-level name is a `use` that reached nothing, marking it
    /// used: the name was written, and the `use` was already reported.
    fn reachesUnresolvedUse(self: *Resolver, name: StringId) bool {
        const b = self.in_module.get(name) orelse return false;
        const held = &self.bindings.items[b.index()];
        if (!held.unresolved) return false;
        held.used = true;
        return true;
    }

    /// Resolves the place a `&` lends to a parameter, leaving a `let` root
    /// for the checker to report where that parameter is `inout`.
    fn lend(self: *Resolver, mark: ExprId, at: ExprId) std.mem.Allocator.Error!void {
        const outer = self.lending_mark;
        self.lending_mark = mark;
        defer self.lending_mark = outer;
        try self.place(at, .mutated);
    }

    /// Whether the name a place-shaped path starts from is in scope as a
    /// binding that holds a value. A path from a function, a type, a trait or
    /// a module names no place. An unresolved name answers true, so `place`
    /// reports it as undefined. Looks the name up in the order `nameRef` does,
    /// without recording a reference.
    fn rootHoldsAValue(self: *const Resolver, id: ExprId) bool {
        var at = self.ast.withoutGroups(id);
        while (true) switch (self.ast.exprTag(at)) {
            .field => at = self.ast.withoutGroups(self.ast.unaryOperand(at)),
            .index => at = self.ast.withoutGroups(self.ast.binary(at).lhs),
            .name_ref => break,
            else => return true,
        };
        const found = self.lookupName(self.ast.tokenName(self.ast.exprMain(at))) orelse return true;
        return switch (found) {
            .binding => |b| kindIsAValue(self.kindOf(b)),
            .type_parameter, .unresolved_use => false,
        };
    }

    /// What a name written in an expression reaches, searched in scope order.
    const NameLookup = union(enum) {
        binding: BindingId,
        type_parameter: ParamInScope,
        /// A `use` that reached nothing, already reported.
        unresolved_use: BindingId,
    };

    /// The one search a name in an expression takes: the lexical names first,
    /// then the module's own run, which `enter` indexed with the last binding
    /// each name reaches there. Records nothing; `nameRef` binds what it
    /// finds.
    fn lookupName(self: *const Resolver, name: StringId) ?NameLookup {
        if (self.lexicalName(name)) |found| return found;
        const b = self.in_module.get(name) orelse return null;
        if (self.bindings.items[b.index()].unresolved) return .{ .unresolved_use = b };
        return .{ .binding = b };
    }

    /// The binding a name reaches inside the declaration being resolved: the
    /// locals innermost first, then the type parameters in scope. Anything
    /// found here is nearer than every file-level name, a module's included.
    fn lexicalName(self: *const Resolver, name: StringId) ?NameLookup {
        if (self.local_of.get(name)) |at| return .{ .binding = self.visible.items[at] };
        if (self.typeParamNamedInScope(name)) |found| return .{ .type_parameter = found };
        return null;
    }

    fn targetOf(self: *const Resolver, id: ExprId) BindingId {
        return self.targets.items[id.index()];
    }

    fn kindOf(self: *const Resolver, b: BindingId) Kind {
        return self.bindings.items[b.index()].kind;
    }

    fn selectsAVariant(self: *const Resolver, id: ExprId) bool {
        return self.variant_ordinals.contains(id);
    }

    /// Marks every inherent member of that name reached, whatever type holds
    /// it.
    ///
    /// Which type the receiver is belongs to the checker, so this marks by
    /// name and is loose in one direction: a member nobody calls goes
    /// unreported when another type has one of the same name. The alternative
    /// was telling a programmer to delete a function they were calling.
    ///
    /// Off a chain rather than a walk of every binding the program has made.
    /// A walk cost the program's bindings for every selection written, and a
    /// module that calls its own operations grows both together.
    ///
    /// The chain is caught up here rather than filled at every place a binding
    /// is made: bodies make bindings while they are walked, so the set is
    /// still growing when this is asked. What decides membership is fixed when
    /// a binding is made, so a binding enters once and never leaves.
    ///
    /// Each name's chain is walked once. A name once selected stays marked,
    /// so a later selection of it walks nothing, and a member bound after
    /// that selection is marked as it is noted rather than found by a walk.
    /// So the whole of what this costs is one visit per inherent member and
    /// one lookup per selection, whatever the members share a name.
    fn markInherentlyNamed(self: *Resolver, selected: StringId) !void {
        if (self.record_prefix) try self.inherent_selections.append(self.gpa, selected);
        while (self.inherent_upto < self.bindings.items.len) : (self.inherent_upto += 1) {
            const at: u32 = @intCast(self.inherent_upto);
            const b = self.bindings.items[at];
            if (b.decl == DeclId.none) continue;
            if (self.ast.declOwner(b.decl) == TokenId.none) continue;
            if (self.ast.declTrait(b.decl) != TokenId.none) continue;
            if (self.inherently_marked.contains(b.name)) {
                self.bindings.items[at].used = true;
                continue;
            }
            try self.inherent.note(self.gpa, @intFromEnum(b.name), at);
        }

        const marked = try self.inherently_marked.getOrPut(self.gpa, selected);
        if (marked.found_existing) return;
        var run = self.inherent.walk(@intFromEnum(selected));
        while (run.next()) |i| self.bindings.items[i].used = true;
    }

    /// Whether a selection wrote the name it selects.
    ///
    /// A `.` with nothing after it is still a selection: the tree records one
    /// so that what it selects from is resolved and typed, which is what a
    /// reader typing there is pointing at. Nothing was written for a name to
    /// reach, though, and the parser reported that where the name belongs --
    /// so every lookup below is skipped rather than made to report a name
    /// nobody wrote as one nobody declared.
    fn selectsAName(self: *const Resolver, id: ExprId) bool {
        return self.ast.tokenTag(self.ast.exprMain(id)) == .identifier;
    }

    /// Whether `Type.name`, whose namespace holds the operation `b`, is left
    /// to the checker because a trait also declares an operation of that
    /// name. Which of the two the name reaches is the question `Reach` answers
    /// for the postfix form too: the type's own where this module may name it,
    /// and otherwise a trait's. `b` is marked used as a selection reaching it
    /// marks it, so a call refused for its privacy is not also reported as
    /// leaving it unused.
    fn leavesOwnToTraits(self: *Resolver, id: ExprId, b: BindingId) std.mem.Allocator.Error!bool {
        const binding = self.bindings.items[b.index()];
        if (binding.kind != .function) return false;
        // A selection resolved before the program's signatures are indexed
        // keeps the namespace's answer.
        const signatures = self.signatures orelse return false;
        if (!signatures.declaresOperation(binding.name)) return false;
        self.bindings.items[b.index()].used = true;
        try self.leaveToTraits(id);
        return true;
    }

    /// Records that a name after a type's name is left to reach an operation
    /// of a trait the type implements. Which trait answers depends on the
    /// implementations and the bounds in scope, which the checker holds.
    fn leaveToTraits(self: *Resolver, id: ExprId) std.mem.Allocator.Error!void {
        try self.trait_selections.put(self.gpa, id, {});
    }

    /// Marks the name a selection from a value writes as reached, so an
    /// operation called in the postfix form, `x.op()` or `&x.op()`, is not
    /// reported unused. Which type's operation it reaches is the checker's to
    /// know; see `markInherentlyNamed` for why marking by name is enough.
    ///
    /// A left side that reached nothing is marked from too. It was already
    /// reported as undefined, and the name selected from it was written:
    /// reporting that name unused as well would describe a second mistake.
    fn notePostfixName(self: *Resolver, id: ExprId) std.mem.Allocator.Error!void {
        if (!self.selectsAName(id)) return;
        const base = self.ast.unaryOperand(id);
        if (baseNamesAValue(self, self.ast, base) or self.targets.items[base.index()] == BindingId.none) {
            try self.markInherentlyNamed(self.ast.tokenName(self.ast.exprMain(id)));
        }
    }

    /// `p.x`, or `Colour.Red`.
    ///
    /// What is selected from resolves like any other expression. Whether it
    /// names a type or a value is what decides which of the two this is, and
    /// the checker asks that question -- except where the answer is an enum,
    /// because a variant that names no variant is a mistake about names.
    fn selection(self: *Resolver, id: ExprId) std.mem.Allocator.Error!void {
        const base = self.ast.unaryOperand(id);

        // A qualified name is decided here, because this is the pass that
        // knows the head names a module rather than a value.
        if (self.ast.exprTag(base) == .name_ref) {
            if (try self.moduleHeadingExpression(id, self.ast.exprMain(base))) |b| {
                return self.member(id, base, b);
            }
        }

        try self.expr(base);
        if (!self.selectsAName(id)) return;

        // A postfix call reaches a type's own operation, and which type the
        // receiver is is the checker's to know rather than this pass's. What
        // this pass can do is stop reporting one as unused for want of a
        // mention: the name is written right here.
        //
        // Only where the left of the dot is a *value*. A qualified call names
        // its type, so this pass resolves it and marks what it reached -- and
        // marking there as well would keep an unreachable member from being
        // reported, which is a case the corpus already holds.
        //
        // By name, across every inherent member that has it, because the
        // receiver's type is not known yet. Loose in one direction only: a
        // member nobody calls goes unreported when another type has one of the
        // same name. The alternative was telling a programmer to delete a
        // function they were calling.
        try self.notePostfixName(id);
        const from_value = baseNamesAValue(self, self.ast, base);

        // What was selected from is a type or a trait, whatever shape named it:
        // a bare name here, or a qualified one where it came from another
        // module. Anything else selects a field, and there is nothing here to
        // check -- a variant included, whose selection settles on the enum's
        // binding while naming a value of it.
        if (from_value) return;
        const written_target = self.targets.items[base.index()];
        if (written_target == BindingId.none) return;
        // A path through an alias is a path through the type it names.
        const target = if (self.bindings.items[written_target.index()].kind == .type_alias)
            (try self.pathThroughAlias(id, base, written_target)) orelse return
        else
            written_target;
        const kind = self.bindings.items[target.index()].kind;
        if (kind == .type_parameter or
            (kind == .builtin_type and self.builtinOf(target).?.integerInfo() != null))
        {
            if (IntegerEndpoint.fromName(self.ast.tokenText(self.ast.exprMain(id)))) |endpoint| {
                try self.integer_selections.put(self.gpa, id, .{ .receiver = target, .endpoint = endpoint });
                return;
            }
        }

        // A type parameter holds no declarations of its own, so a name after
        // it can only be an operation its bounds declare, which the checker
        // reads from the bounds.
        if (kind == .type_parameter) return self.leaveToTraits(id);

        // A primitive is a namespace like any other type. Nobody declares one,
        // so what its name opens is the namespace the standard library wrote:
        // the members table is keyed by the module the `impl` sits in, and the
        // ownership rule leaves that module to the library alone.
        if (kind == .builtin_type) {
            const from = self.ast.tokenName(self.ast.exprMain(id));
            if (self.builtinMemberNamed(self.builtinOf(target).?, from)) |b| {
                if (try self.leavesOwnToTraits(id, b)) return;
                return self.reachMember(id, b, self.bindings.items[b.index()].decl);
            }
            if (self.signatures.?.declaresOperation(from)) return self.leaveToTraits(id);
            return self.sink.addErrorFmt(
                .n_undefined,
                self.ast.fileOfExpr(id),
                self.ast.tokenSpan(self.ast.exprMain(id)),
                "a primitive holds what the standard library writes for it",
                "`{s}` declares no `{s}`",
                .{
                    self.ast.tokenText(self.ast.exprMain(base)),
                    self.ast.tokenText(self.ast.exprMain(id)),
                },
            );
        }

        if (kind != .declared_type and kind != .trait) return;

        const decl = self.bindings.items[target.index()].decl;

        // A type is a namespace, so a name under it is a declaration written
        // inside it before it is anything else. A variant is looked for only
        // where no declaration answers.
        const wanted = self.ast.tokenName(self.ast.exprMain(id));
        if (self.memberNamed(self.moduleOf(decl), self.ast.tokenName(self.ast.declName(decl)), wanted)) |b| {
            // Asked of the member, not of the type it hangs off. A `pub use`
            // carries a type into a module that did not declare it, and an
            // `impl` may sit in either, so the two answer differently -- and
            // reading the type's answer made a private function reachable
            // wherever its type was.
            //
            // A trait's signature is the exception, and the trait answers for
            // it: a signature carries no visibility of its own, so asking it
            // would make every operation of every foreign trait unreachable --
            // which is the whole of what a trait is for.
            const written = self.bindings.items[b.index()].decl;
            if (kind != .trait and try self.leavesOwnToTraits(id, b)) return;
            return self.reachMember(id, b, if (kind == .trait) decl else written);
        }

        // A trait holds signatures and nothing else -- no representation to
        // select from and no variants -- so a name it does not declare is
        // undefined there and that is the whole of it. The type's own member
        // of that name is not what was written: an implementation associates
        // the two namespaces without merging them.
        if (kind == .trait) {
            return self.sink.addErrorFmt(
                .n_undefined,
                self.ast.fileOfExpr(id),
                self.ast.tokenSpan(self.ast.exprMain(id)),
                "only what the trait declares is reached through it",
                "`{s}` declares no `{s}`",
                .{ self.ast.tokenText(self.ast.declName(decl)), self.ast.tokenText(self.ast.exprMain(id)) },
            );
        }

        // A variant is part of what an enum's name reaches, so it answers
        // before any advice about a namespace that does not hold the name.
        // Adding an implementation cannot change what `Colour.` means, and a
        // trait member sharing a variant's spelling is the case that says so.
        if (self.variantNamed(decl, wanted)) |ordinal| {
            // The selection reaches the enum's binding and retains the
            // variant's ordinal for checking and emission.
            self.settle(id, target, self.ast.exprMain(base));
            try self.variant_ordinals.put(self.gpa, id, @enumFromInt(ordinal));
            return;
        }

        // A name the type's namespace does not hold may be an operation of a
        // trait the type implements, which the checker settles.
        if (self.signatures.?.declaresOperation(wanted)) return self.leaveToTraits(id);

        if (self.ast.declTag(decl) != .enum_) {
            return self.sink.addError(
                .n_variant,
                self.ast.fileOfExpr(base),
                self.ast.exprSpan(base),
                "this name refers to a type, and a type has no parts to select",
                "only an enum has variants",
            );
        }

        try self.sink.addErrorFmt(
            .n_variant,
            self.ast.fileOfExpr(id),
            self.ast.exprSpan(id),
            "the enum has no such variant",
            "`{s}` is not a variant of `{s}`",
            .{ self.ast.tokenText(self.ast.exprMain(id)), self.ast.tokenText(self.ast.declName(decl)) },
        );
    }

    /// The module a name refers to, in the file the use was written in.
    ///
    /// An import binds a name in that file and nowhere else, so a file that
    /// wrote no import cannot use one another file wrote -- otherwise which
    /// names a file has would depend on what its neighbours happened to
    /// import.
    /// Looked up, not walked. This is asked of every selection written whose
    /// base is a name -- every `p.x`, not only a qualified one -- and the list
    /// holds every import in the program, so a walk was the two multiplied.
    fn moduleNamed(self: *Resolver, name: StringId, in: FileId) ?BindingId {
        return self.import_at.get(importKey(self.current, name, in));
    }

    /// The module the name before a dot in an expression reaches, or null
    /// where a nearer binding holds that name.
    ///
    /// An import is a file-level name, so whatever `lexicalName` finds -- a
    /// local, a parameter, a loop or pattern binder, or a type parameter --
    /// shadows it for as long as that binding is in scope: `text.find(":")`
    /// inside `fn parse(text: Str)` searches the parameter. A type position
    /// asks `moduleHeading` instead, where only a type parameter shadows,
    /// because a local is a value and never names a type. A shadowed head is
    /// recorded against the selection `id` for the diagnostics about it.
    fn moduleHeadingExpression(self: *Resolver, id: ExprId, head: TokenId) std.mem.Allocator.Error!?BindingId {
        const name = self.ast.tokenName(head);
        const module = self.moduleNamed(name, self.ast.fileOf(head)) orelse return null;
        if (!self.shadowsAnImport(name)) return module;
        try self.shadowed_heads.put(self.gpa, id, {});
        return null;
    }

    /// Whether an import of this name is shadowed in an expression here:
    /// whatever `lexicalName` finds is nearer than every file-level name.
    /// The one answer a dotted head and a suggested qualifier both read.
    fn shadowsAnImport(self: *const Resolver, name: StringId) bool {
        return self.lexicalName(name) != null;
    }

    /// The file a declaration was written in.
    fn declaringFile(self: *const Resolver, d: DeclId) FileId {
        return self.ast.fileOf(self.ast.declName(d));
    }

    /// Records the free function a postfix call written on a value names, if
    /// its name reaches one from the call's module: the module's own function
    /// of that name, or else a public one of a module the call's file imports.
    ///
    /// A free function is not an operation, so the call will not run it. Where
    /// the call reaches no operation the checker says so and shows the call
    /// that does; where it reaches one, the function was not named at all.
    /// Which of the two is the checker's to know, so nothing is marked used
    /// here: a function or import unused apart from such calls is left for
    /// the checker to report, in `deferred_unused`.
    ///
    /// Costs one lookup in the module's own names and, where that finds no
    /// function, one per import the call's file writes.
    fn notePostfixFunction(self: *Resolver, callee: ExprId) std.mem.Allocator.Error!void {
        const at = self.ast.withoutGroups(callee);
        if (self.ast.exprTag(at) != .field or !self.selectsAName(at)) return;
        const base = self.ast.unaryOperand(at);
        if (!baseNamesAValue(self, self.ast, base)) return;
        const name = self.ast.tokenName(self.ast.exprMain(at));

        if (self.in_module.get(name)) |b| {
            const held = self.bindings.items[b.index()];
            if (held.kind != .function or held.decl == DeclId.none or self.ast.declOwner(held.decl) != TokenId.none) return;
            return self.postfix_functions.put(self.gpa, at, .{ .function = b });
        }

        // An import a lexical binding shadows at the call is kept only as a
        // last resort, so an alias no binding shadows names the call instead.
        const file = self.ast.fileOfExpr(at);
        var shadowed: ?Resolution.PostfixFunction = null;
        for (self.program.get(self.current).imports) |import| {
            if (self.declaringFile(import.decl) != file) continue;
            const imported = self.ast.tokenName(self.ast.declName(import.decl));
            const through = self.moduleNamed(imported, file) orelse continue;
            const b = self.reachable_at.get(hereKey(import.module, name)) orelse continue;
            const held = self.bindings.items[b.index()];
            if (held.kind != .function or held.decl == DeclId.none or self.ast.declOwner(held.decl) != TokenId.none) continue;
            if (!reachableFrom(self.program, held.reach, import.module, self.current)) continue;
            if (self.shadowsAnImport(imported)) {
                if (shadowed == null) shadowed = .{ .function = b, .through = through, .shadowed = true };
                continue;
            }
            return self.postfix_functions.put(self.gpa, at, .{ .function = b, .through = through });
        }
        if (shadowed) |named| try self.postfix_functions.put(self.gpa, at, named);
    }

    /// `a.f`, where `a` names an imported module.
    fn member(
        self: *Resolver,
        id: ExprId,
        base: ExprId,
        module_binding: BindingId,
    ) std.mem.Allocator.Error!void {
        self.bindings.items[module_binding.index()].used = true;
        self.settle(base, module_binding, self.ast.exprMain(base));

        if (!self.selectsAName(id)) return;

        const at = self.ast.exprMain(id);
        const b = (try self.throughModule(module_binding, at)) orelse return;
        self.settle(id, b, at);
    }

    /// What a name written after a module's name reaches, or null where it
    /// reaches nothing and that has been said.
    ///
    /// The one place a name crosses a module boundary, and so the one place
    /// visibility is checked. Sealing hooks in here for the same reason: what
    /// may be reached from outside is one question, asked once. A name in a
    /// type position crosses on the same terms as one in an expression, so it
    /// crosses here too rather than through a second reading of what a module
    /// holds.
    fn throughModule(
        self: *Resolver,
        module_binding: BindingId,
        at: TokenId,
    ) std.mem.Allocator.Error!?BindingId {
        switch (self.crossModule(module_binding, at)) {
            // The import was already reported as naming nothing. Reporting
            // every name reached through it would bury that under its
            // consequences.
            .unimported => return null,
            .reached => |b| {
                self.bindings.items[b.index()].used = true;
                return b;
            },
            .unreachable_from_here => |refused| {
                const held = &self.bindings.items[refused.binding.index()];
                held.used = true;
                try self.reportUnreachable(at, refused.target, held.reach);
                return null;
            },
            .undeclared => |target| {
                try self.sink.addErrorFmt(
                    .n_undefined,
                    self.ast.fileOf(at),
                    self.ast.tokenSpan(at),
                    "no declaration of that name is in that module",
                    "`{s}` is not declared in `{s}`",
                    .{ self.ast.tokenText(at), self.program.get(target).name },
                );
                return null;
            },
        }
    }

    /// What a name written after a module's name reaches from here, decided
    /// and not reported. `throughModule` reports and marks what this answers;
    /// a check that reads a written path before its signature is resolved
    /// asks this and leaves the report to the resolution that follows.
    const Crossing = union(enum) {
        unimported,
        reached: BindingId,
        unreachable_from_here: struct { binding: BindingId, target: ModuleId },
        undeclared: ModuleId,
    };

    fn crossModule(self: *const Resolver, module_binding: BindingId, at: TokenId) Crossing {
        const import_decl = self.bindings.items[module_binding.index()].decl;
        const target = self.importedBy(import_decl);
        if (target == .none) return .unimported;

        // Looked up rather than walked: this is asked once per qualified
        // reference written, and the run it read holds everything the target
        // module declares -- so a walk was the two multiplied.
        const b = self.reachable_at.get(hereKey(target, self.ast.tokenName(at))) orelse return .{ .undeclared = target };
        if (!reachableFrom(self.program, self.bindings.items[b.index()].reach, target, self.current)) {
            return .{ .unreachable_from_here = .{ .binding = b, .target = target } };
        }
        return .{ .reached = b };
    }

    /// Declares the names a match arm's pattern binds.
    ///
    /// A bare pattern binds nothing; a call-shaped one binds its arguments,
    /// which is the shape the parser gives `Circle(n)`. The binder's own
    /// `name_ref` is pointed at the binding it declares rather than left
    /// unresolved, so a consumer reaching a pattern finds the binding through
    /// the map it already uses for every other name.
    fn bindPattern(self: *Resolver, pattern: ExprId) std.mem.Allocator.Error!void {
        self.pattern_names.restart();
        // A struct pattern names the type it takes apart, then alternates
        // field and binder. Only the binders are names this introduces; which
        // fields a type has is the checker's question.
        if (self.ast.exprTag(pattern) == .struct_pattern) {
            const p = self.ast.call(pattern);
            if (p.callee != ExprId.none) try self.usePatternHead(self.ast.exprMain(p.callee));

            var i: usize = 1;
            while (i < p.args.len) : (i += 2) {
                // The shorthand puts the field and the binder at one token,
                // which the parser records by building two nodes there. What
                // was written is the tree's answer and nobody else's.
                const shared = self.ast.exprMain(p.args[i - 1]) == self.ast.exprMain(p.args[i]);
                try self.bindOne(p.args[i], shared, false);
            }
            return;
        }

        // A tuple pattern names no type and binds each component by position.
        if (self.ast.exprTag(pattern) == .tuple_pattern) {
            for (self.ast.call(pattern).args) |a| try self.bindOne(a, false, false);
            return;
        }

        // A range or a literal pattern's bounds are ordinary expressions -- a
        // name a bound reaches is a name in scope, not a part this pattern
        // binds -- so they resolve the way any expression does, through the
        // same case a range or a literal in expression position already
        // reaches.
        if (self.ast.exprTag(pattern) == .range or self.ast.exprTag(pattern) == .int_literal) {
            try self.expr(pattern);
            return;
        }

        if (self.ast.exprTag(pattern) != .call) return;
        // Most spellings here are a variant, which is not a type and marks
        // nothing. A newtype's pattern spells the type itself, indistinguishable
        // from a variant's at this point in the pipeline -- so the head is
        // offered to the same lookup a struct pattern's is, which finds a
        // declared type only where the spelling actually is one.
        try self.usePatternHead(self.ast.exprMain(self.ast.call(pattern).callee));
        for (self.ast.call(pattern).args) |a| try self.bindOne(a, false, false);
    }

    /// One name a pattern binds to part of what it took apart.
    ///
    /// The one place a binder is made, so a variant's payload and a struct's
    /// field are bound alike -- both name a part of a value the pattern is
    /// taking apart, and neither is a name that was already in scope.
    fn bindOne(
        self: *Resolver,
        a: ExprId,
        /// Whether the pattern wrote this binder as the field's own name.
        names_a_field: bool,
        /// Whether the construct that binds it said it may be written. A
        /// pattern's binders never are -- a part is read where it is wanted --
        /// and a walk lending its places writably is what the exception is for.
        mutable: bool,
    ) std.mem.Allocator.Error!void {
        if (self.ast.exprTag(a) != .name_ref) return;

        const tok = self.ast.exprMain(a);
        const b = BindingId.at(@intCast(self.bindings.items.len));

        // A pattern declares each name once, and `_` declares none. The first
        // spelling keeps the name, as it does in a parameter list: the second
        // is bound so the checker finds a binding at it, but no name reaches
        // it and nothing reports it unused.
        const spelled = self.ast.tokenName(tok);
        const first = if (std.mem.eql(u8, self.ast.tokenText(tok), "_")) null else self.pattern_names.get(spelled);
        if (first) |earlier| {
            try self.reportNameDeclaredTwice(earlier, tok, "pattern", "a pattern declares each name once");
            try self.declaredHere(b);
        } else {
            try self.pattern_names.put(self.gpa, spelled, tok);
            try self.pushLocal(b, spelled);
        }
        try self.bindings.append(self.gpa, .{
            .name = self.ast.tokenName(tok),
            .kind = .binder,
            .stmt = StmtId.none,
            .decl = DeclId.none,
            .param_index = 0,
            .at = tok,
            .used = false,
            // A binding cannot be assigned unless the construct that bound it
            // said it may be.
            .mutable = mutable,
            .exempt = first != null or std.mem.startsWith(u8, self.ast.tokenText(tok), "_"),
            .names_a_field = names_a_field,
        });
        self.settle(a, b, tok);
    }

    fn expr(self: *Resolver, id: ExprId) std.mem.Allocator.Error!void {
        // Where the chain stands as this expression is read. Written for every
        // expression rather than for the names alone, because what is visible
        // somewhere inside an expression is a question about a point and not
        // about a name -- and a point in a half-written construct is usually
        // inside something that names nothing.
        self.scope_of_expr.items[id.index()] = self.scope;

        switch (self.ast.exprTag(id)) {
            // Already diagnosed; anything inside it would report the same
            // mistake a second time.
            .err => {},

            .int_literal, .float_literal, .str_literal, .bool_literal, .unit_literal => {},

            .reflection_root => try self.reportReflection(
                id,
                "use a supported reflection operation inside a structural-template member",
                "a reflection descriptor is not a runtime value",
            ),

            // The text pieces resolve to nothing; the values between them are
            // ordinary expressions and resolve as any argument does.
            .interp => for (self.ast.interpolation(id).pieces) |piece| try self.expr(piece),

            .conditional => {
                const c = self.ast.conditional(id);
                try self.expr(c.cond);
                try self.expr(c.then);
                if (c.otherwise != ExprId.none) try self.expr(c.otherwise);
            },

            .name_ref => try self.nameRef(id, .read),

            // Pointed at its parameter's binding where the lambda binds its
            // parameters, and reached by no walk of the tree.
            .param_argument => {},

            .lambda => {
                const lambda = self.ast.lambda(id);
                try self.useRef(lambda.result);
                for (lambda.params) |param| {
                    try self.refuseRedundantRead(param);
                    try self.useRef(param.written);
                }
                // Defaults are evaluated where the lambda is created, before
                // its parameters exist, and therefore cannot capture them.
                // An `inout` capture lends its source to be changed, as `&`
                // does, so the source must be a binding that may change.
                for (lambda.captures) |capture| {
                    if (capture.convention == .inout and self.namesAPlace(capture.source))
                        try self.place(capture.source, .mutated)
                    else
                        try self.expr(capture.source);
                }
                for (lambda.params) |p| if (p.default != ExprId.none) try self.expr(p.default);

                const closure = try self.closures.add(id);
                try self.free_references.append(self.gpa, .none);
                const capture_start: u32 = @intCast(self.captures.items.len);
                try self.capture_ranges.append(self.gpa, .{ .start = capture_start, .end = capture_start + @as(u32, @intCast(lambda.captures.len)) });
                const previous_closure = self.current_closure;
                const previous_start = self.closure_binding_start;
                self.current_closure = closure;
                self.closure_binding_start = self.bindings.items.len;
                defer {
                    self.current_closure = previous_closure;
                    self.closure_binding_start = previous_start;
                }

                const mark = self.visible.items.len;
                defer self.popLocalsTo(mark);
                const parameter_scope = try self.openScope();
                defer self.closeScope(parameter_scope);
                self.scope_of_expr.items[id.index()] = parameter_scope;
                // Capture aliases and parameters are one list of names. A second
                // of one spelling is refused there; the first keeps the name,
                // and the second is neither visible nor reported unused.
                {
                    var listed: std.ArrayList(TokenId) = .empty;
                    defer listed.deinit(self.gpa);
                    for (lambda.captures) |capture| try listed.append(self.gpa, capture.name);
                    for (lambda.params) |p| try listed.append(self.gpa, p.name);
                    try self.refuseNamesDeclaredTwice(listed.items, "a closure's captures and parameters are declared once");
                }
                var names: std.AutoHashMapUnmanaged(StringId, void) = .empty;
                defer names.deinit(self.gpa);
                // The names a tuple-pattern parameter's binders meet: each
                // capture and named parameter, and the binders before them.
                self.pattern_names.restart();
                for (lambda.captures, 0..) |capture, i| {
                    const named = try names.getOrPut(self.gpa, self.ast.tokenName(capture.name));
                    if (!named.found_existing and !std.mem.eql(u8, self.ast.tokenText(capture.name), "_"))
                        try self.pattern_names.put(self.gpa, self.ast.tokenName(capture.name), capture.name);
                    const binding = BindingId.at(@intCast(self.bindings.items.len));
                    if (!named.found_existing) try self.pushLocal(binding, self.ast.tokenName(capture.name));
                    try self.bindings.append(self.gpa, .{
                        .name = self.ast.tokenName(capture.name),
                        .kind = .capture,
                        .stmt = .none,
                        .decl = .none,
                        .param_index = 0,
                        .at = capture.name,
                        .used = false,
                        .mutable = captureIsMutable(capture.convention, lambda.invocation),
                        .exempt = named.found_existing or std.mem.startsWith(u8, self.ast.tokenText(capture.name), "_"),
                    });
                    try self.captures.append(self.gpa, .{ .binding = binding, .source = capture.source, .convention = capture.convention });
                    try self.capture_bindings.put(self.gpa, binding, .{ .closure = closure, .index = @intCast(i) });
                    try self.noteTemplateClosureCapture(closure, binding, capture.source);
                }
                for (lambda.params, 0..) |p, i| {
                    // A tuple pattern's argument is still a parameter, so the
                    // closure's parameter bindings stay one per parameter. No
                    // name reaches it; the pattern's binders are locals of
                    // the lambda, bound as a pattern's are.
                    if (p.pattern != ExprId.none) {
                        const argument = BindingId.at(@intCast(self.bindings.items.len));
                        try self.bindings.append(self.gpa, .{
                            .name = self.ast.tokenName(p.name),
                            .kind = .parameter,
                            .stmt = .none,
                            .decl = .none,
                            .param_index = @intCast(i),
                            .parameter_owner = .{ .closure = closure },
                            .at = p.name,
                            .used = true,
                            .mutable = p.convention == .inout,
                            .exempt = true,
                        });
                        // Settled at no token: nothing written names it.
                        self.settle(p.argument, argument, .none);
                        for (self.ast.call(p.pattern).args) |binder| try self.bindOne(binder, false, p.convention == .inout);
                        continue;
                    }
                    if (self.ast.tokenTag(p.name) != .identifier) continue;
                    const named = try names.getOrPut(self.gpa, self.ast.tokenName(p.name));
                    const text = self.ast.tokenText(p.name);
                    // A parameter named after a pattern's binder is a second
                    // declaration of it, which the list check above cannot
                    // see, since a pattern's binders are not in that list.
                    const earlier = if (named.found_existing or std.mem.eql(u8, text, "_")) null else self.pattern_names.get(self.ast.tokenName(p.name));
                    if (earlier) |first| {
                        try self.reportNameDeclaredTwice(first, p.name, "declaration", "a closure's captures and parameters are declared once");
                    } else if (!named.found_existing and !std.mem.eql(u8, text, "_")) {
                        try self.pattern_names.put(self.gpa, self.ast.tokenName(p.name), p.name);
                    }
                    const repeated = named.found_existing or earlier != null;
                    const binding = BindingId.at(@intCast(self.bindings.items.len));
                    if (!repeated) try self.pushLocal(binding, self.ast.tokenName(p.name));
                    try self.bindings.append(self.gpa, .{
                        .name = self.ast.tokenName(p.name),
                        .kind = .parameter,
                        .stmt = .none,
                        .decl = .none,
                        .param_index = @intCast(i),
                        .parameter_owner = .{ .closure = closure },
                        .at = p.name,
                        .used = false,
                        .mutable = p.convention == .inout,
                        .exempt = repeated or std.mem.startsWith(u8, text, "_"),
                    });
                    if (self.template_validation) |validation| {
                        if (!repeated)
                            try validation.reflection.closure_parameters.put(self.gpa, .{ .closure = closure, .name = self.ast.tokenName(p.name) }, binding);
                    }
                }
                self.noteTemplateClosureContracts(closure, lambda.contracts);
                try self.expr(lambda.body);
            },

            .while_ => {
                const b = self.ast.binary(id);
                try self.expr(b.lhs);
                try self.ordinaryLoopBody(b.rhs);
            },

            .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => {
                const b = self.ast.binary(id);
                // The value first, so a name is not yet resolvable through the
                // target it is being assigned to.
                try self.expr(b.rhs);
                // A compound assignment reads its place as well as writing it,
                // and is still `assigned` rather than `mutated`: the read feeds
                // only the write back to the same place, so nothing observes
                // it, and a binding only ever updated this way is as unused as
                // one only ever assigned. Permission is the same question too,
                // so `[N-Immutable]` answers here through the routine that
                // answers it for `=`.
                try self.place(b.lhs, .assigned);
            },

            .grouped, .negate, .not, .borrow, .dereference, .copy_, .panic, .try_, .from_end => try self.expr(self.ast.unaryOperand(id)),
            .loop_ => try self.ordinaryLoopBody(self.ast.unaryOperand(id)),

            // A pattern's names are fields and binders, neither of which is a
            // name in scope. Which fields a type has is the checker's
            // question; what the binders bind is settled where the pattern is.
            .struct_pattern, .tuple_pattern => {},

            // A bare `break` carries nothing to resolve, and `continue` never
            // does. Whether either sits inside a loop is a question about the
            // grammar, answered by the checker.
            .break_ => {
                if (self.transferTargetsReflectedLoop()) {
                    try self.reportReflection(id, "remove the transfer or target an ordinary nested loop", "`break` cannot target a reflected loop");
                }
                const value = self.ast.unaryOperand(id);
                if (value != ExprId.none) try self.expr(value);
            },

            .return_ => {
                const value = self.ast.unaryOperand(id);
                if (value != ExprId.none) try self.expr(value);
            },

            .continue_ => if (self.transferTargetsReflectedLoop()) {
                try self.reportReflection(id, "remove the transfer or target an ordinary nested loop", "`continue` cannot target a reflected loop");
            },

            // `.Red` waits for the type the context expects, which the
            // checker supplies.
            .variant_ref => {},

            // `p.x` and `Colour.Red` are one shape. What is selected is a
            // name and not a binding either way -- a field belongs to a type
            // and a variant to an enum, and neither is in scope -- so only
            // what it is selected from resolves here.
            .field => if (!try self.reflectionMetadata(id)) try self.selection(id),

            // The names are the fields being given, which belong to a type
            // rather than to a scope. The values resolve.
            .struct_literal => {
                const c = self.ast.call(id);
                if (self.ast.structLiteralHead(id)) |head| try self.useRefIn(head, .literal_head);
                var i: usize = 1;
                while (i < c.args.len) : (i += 2) {
                    try self.expr(c.args[i]);
                    if (self.template_validation) |validation| {
                        if (validation.reflection.recipe_floor != null and self.ast.fieldIsShorthand(c.args[i - 1], c.args[i])) {
                            try validation.reflection.shorthand_values.put(self.gpa, self.ast.exprMain(c.args[i]), {});
                        }
                    }
                }
                if (self.ast.structLiteralBase(id)) |base| try self.expr(base);
            },

            // The marker names a place that will be written, so it resolves
            // like an assignment target and reports a `let` the same way.
            .marked => try self.lend(id, self.ast.unaryOperand(id)),

            // The callee resolves like any other name; whether it names
            // something callable is a question about the symbol it found, and
            // the checker asks it.
            .call => {
                if (try self.reflectionConstruction(id)) return;
                if (try self.reflectionOrdinal(id)) return;
                if (try self.reflectionWrap(id)) return;
                if (try self.componentPlace(id)) return;
                const c = self.ast.call(id);
                const lends = self.ast.callMarked(id) and self.rootHoldsAValue(c.callee);
                if (self.ast.callMarked(id) and !lends) try self.unlent_marks.put(self.gpa, id, {});
                if (lends) {
                    // `&` lends a place the call writes through: the receiver
                    // of a postfix call, `&x.op()`, or the callable place
                    // itself, `&callback()`. Either is a path rooted at the
                    // binding being lent, so the whole callee resolves like an
                    // assignment target, and the operation a postfix call
                    // names is still marked as reached. A callee rooted at a
                    // function, a type or a module lends nothing: it resolves
                    // as the path it is, and the checker refuses the `&`.
                    if (self.ast.exprTag(c.callee) == .field) {
                        try self.lend(id, c.callee);
                        try self.notePostfixName(c.callee);
                    } else if (self.ast.exprTag(c.callee) == .index and self.ast.bracketTypes(c.callee) != null and
                        self.ast.exprTag(self.ast.binary(c.callee).lhs) == .field)
                    {
                        // `&x.name[T](...)` lends the receiver of a method, or
                        // the place a field's element is, which the checker
                        // decides; both are rooted at `x`.
                        const head = self.ast.binary(c.callee).lhs;
                        try self.lend(id, head);
                        try self.notePostfixName(head);
                        try self.bracketReadings(c.callee, true);
                    } else try self.place(c.callee, .mutated);
                } else {
                    self.called_bracket = c.callee;
                    try self.expr(c.callee);
                    self.called_bracket = .none;
                }
                try self.notePostfixFunction(c.callee);
                for (c.args) |a| try self.expr(a);
                try self.noteTemplateClosureCall(id);
            },

            // No callee, so only the elements name anything.
            .array_literal, .tuple_literal => {
                for (self.ast.call(id).args) |a| try self.expr(a);
            },

            // A pattern is not a name in scope: it names a variant under the
            // scrutinee's enum, which only the checker knows. So the scrutinee
            // resolves and the bodies resolve, and which variant a pattern
            // names is left to the pass that knows what it is a pattern of.
            //
            // What a pattern binds is not that question. Those are bindings
            // whatever the variant turns out to be, so the arm is a scope and
            // it is built here, where every other scope is built.
            // The sequence is named where the loop is written, so it reaches
            // whatever `for` sits in and never the binder: `for x in x` walks
            // the `x` that was already in scope.
            //
            // The binder is a name the loop introduces, and its scope is the
            // body -- the same arrangement a `match` arm's binders have, built
            // through the same routine so that one kind of name is made in one
            // place.
            .for_, .for_read, .for_inout => {
                const f = self.ast.call(id);
                const reflected = self.reflectedComponents(f.callee);

                // A walk lending its places writably writes through what it
                // walks, so the value after `in` is marked the way `&p` marks
                // one and a `let` here is the mistake a `let` behind an `&`
                // is. Only where a place was written: a walk over something
                // else writes into a value nothing outside can see, which is
                // useless rather than a mistake about names.
                const writes = self.ast.exprTag(id) == .for_inout;
                if (reflected == null and writes and self.namesAPlace(f.callee))
                    try self.place(f.callee, .mutated)
                else if (reflected == null)
                    try self.expr(f.callee);

                const mark = self.visible.items.len;
                defer self.popLocalsTo(mark);
                const scope = try self.openScope();
                defer self.closeScope(scope);

                // The binder of a writable lend is assignable: writing through
                // it is what the walk was written for.
                self.pattern_names.restart();
                if (self.ast.exprTag(f.args[0]) == .tuple_pattern) {
                    for (self.ast.call(f.args[0]).args) |component| try self.bindOne(component, false, writes);
                } else {
                    try self.bindOne(f.args[0], false, writes);
                }
                if (reflected) |reversed| {
                    // A component is not a tuple, so a pattern has nothing to
                    // take apart and no binding to plan the loop around.
                    if (self.ast.exprTag(f.args[0]) == .tuple_pattern) {
                        try self.reportReflection(
                            f.args[0],
                            "a reflected component loop binds one name",
                            "a component is not a tuple to take apart",
                        );
                        try self.expr(f.args[1]);
                        return;
                    }
                    const validation = self.template_validation;
                    const valid_context = validation != null and
                        validation.?.reflection.active_case_depth != 0 and
                        validation.?.reflection.active_loop == null and
                        self.ast.exprTag(id) == .for_;
                    if (!valid_context) {
                        try self.reportReflection(
                            f.callee,
                            "walk components once inside an active `reflect.case`",
                            "this reflected component loop has no valid lexical case",
                        );
                        try self.expr(f.args[1]);
                        return;
                    }

                    const context = validation.?.reflection;
                    const plan: ComponentLoopPlan = .{
                        .loop = id,
                        .binder = self.targets.items[f.args[0].index()],
                        .body = f.args[1],
                        .reversed = reversed,
                    };
                    try context.loops.append(self.gpa, plan);
                    const previous = context.active_loop;
                    context.active_loop = plan;
                    defer context.active_loop = previous;
                    try self.expr(f.args[1]);
                } else {
                    try self.ordinaryLoopBody(f.args[1]);
                }
            },

            .match_, .match_read => {
                const m = self.ast.call(id);
                try self.expr(m.callee);

                if (m.args.len >= 2 and self.isReflectionField(m.args[0], "same_case")) {
                    const validation = self.template_validation;
                    const subject_binding = self.targets.items[m.callee.index()];
                    const has_other = m.args.len == 4 and self.isReflectionField(m.args[2], "other_case");
                    if (validation == null or
                        validation.?.reflection.active_case_depth == 0 or
                        validation.?.reflection.active_loop != null or
                        subject_binding == .none or
                        (m.args.len != 2 and !has_other))
                    {
                        try self.reportReflection(
                            m.args[0],
                            "match one named subject with `reflect.same_case` and an optional final `reflect.other_case`",
                            "this same-case match has no active reflected case or has unsupported arms",
                        );
                        var bad_i: usize = 1;
                        while (bad_i < m.args.len) : (bad_i += 2) try self.expr(m.args[bad_i]);
                        return;
                    }

                    const context = validation.?.reflection;
                    try context.same_cases.append(self.gpa, .{
                        .match = id,
                        .subject = m.callee,
                        .subject_binding = subject_binding,
                        .same_body = m.args[1],
                        .other_body = if (has_other) m.args[3] else null,
                    });
                    const subject_mark = context.active_subjects.items.len;
                    defer context.active_subjects.shrinkRetainingCapacity(subject_mark);
                    const previous_depth = context.active_case_depth;
                    defer context.active_case_depth = previous_depth;
                    try context.active_subjects.append(self.gpa, subject_binding);
                    context.active_case_depth = previous_depth + 1;
                    try self.expr(m.args[1]);
                    if (has_other) {
                        context.active_subjects.shrinkRetainingCapacity(subject_mark);
                        context.active_case_depth = previous_depth;
                        try self.expr(m.args[3]);
                    }
                    return;
                }

                var reflected_pattern = ExprId.none;
                var pattern_index: usize = 0;
                while (pattern_index + 1 < m.args.len) : (pattern_index += 2) {
                    if (self.rootedInReflection(m.args[pattern_index])) {
                        reflected_pattern = m.args[pattern_index];
                        break;
                    }
                }
                if (reflected_pattern != .none and m.args.len != 2) {
                    try self.reportReflection(
                        reflected_pattern,
                        "give a reflected match exactly its one generic case arm",
                        "ordinary sibling arms cannot be expanded uniformly",
                    );
                }

                var i: usize = 0;
                while (i + 1 < m.args.len) : (i += 2) {
                    const mark = self.visible.items.len;
                    defer self.popLocalsTo(mark);
                    const arm = try self.openScope();
                    defer self.closeScope(arm);

                    const pattern = m.args[i];
                    const body = m.args[i + 1];
                    if (self.isReflectedCase(pattern)) {
                        const validation = self.template_validation;
                        const subject_binding = self.targets.items[m.callee.index()];
                        if (validation == null or
                            validation.?.reflection.active_case_depth != 0 or
                            validation.?.reflection.active_loop != null or
                            subject_binding == .none)
                        {
                            try self.reportReflection(
                                pattern,
                                "match one named subject in a structural-template member",
                                "this reflected case has no independent named subject",
                            );
                            try self.expr(body);
                            continue;
                        }

                        const context = validation.?.reflection;
                        const plan: ReflectedCasePlan = .{
                            .match = id,
                            .pattern = pattern,
                            .subject = m.callee,
                            .subject_binding = subject_binding,
                            .body = body,
                        };
                        try context.cases.append(self.gpa, plan);
                        try context.active_subjects.append(self.gpa, subject_binding);
                        defer _ = context.active_subjects.pop();
                        context.active_case_depth += 1;
                        defer context.active_case_depth -= 1;
                        try self.expr(body);
                    } else if (self.rootedInReflection(pattern)) {
                        try self.reportReflection(
                            pattern,
                            "use `reflect.case` as the reflected match pattern",
                            "this reflection selection is not a supported pattern",
                        );
                        try self.expr(body);
                    } else {
                        try self.bindPattern(pattern);
                        try self.expr(body);
                    }
                }
            },

            // The binder is a name the failure introduces, and its scope is
            // the block -- the arrangement a `match` arm's binders have, built
            // through the same routine.
            .unwrap_else => {
                const u = self.ast.unwrapElse(id);
                try self.expr(u.operand);

                const mark = self.visible.items.len;
                defer self.popLocalsTo(mark);
                const scope = try self.openScope();
                defer self.closeScope(scope);

                self.pattern_names.restart();
                if (u.binder != ExprId.none) try self.bindOne(u.binder, false, false);
                // A block the parser gave up on cannot show whether the binder
                // is used, so it is not reported as unused.
                if (u.binder != ExprId.none and self.ast.exprTag(u.binder) == .name_ref and self.containsErr(u.body)) {
                    self.bindings.items[self.bindings.items.len - 1].exempt = true;
                }
                try self.expr(u.body);
            },

            // The head and the index are both ordinary expressions, except
            // for a bracket whose contents also read as types: what it holds
            // is settled by what the head names.
            .index => {
                const called = self.called_bracket == id;
                self.called_bracket = .none;
                const b = self.ast.binary(id);
                try self.expr(b.lhs);
                if (self.ast.bracketTypes(id) != null) {
                    try self.bracketReadings(id, called);
                } else {
                    try self.expr(b.rhs);
                }
            },

            .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge, .logical_and, .logical_or => {
                const b = self.ast.binary(id);
                try self.expr(b.lhs);
                try self.expr(b.rhs);
            },

            // `lo..hi`: both ends are ordinary expressions, whatever the
            // checker later makes of the node that holds them.
            .range => {
                const ends = self.ast.rangeEnds(id);
                try self.expr(ends.lhs);
                try self.expr(ends.rhs);
            },

            // A block is a scope. Its bindings stop being visible where it
            // ends, or a name after the block would find one declared inside
            // it -- which reads the wrong storage rather than failing.
            .block => {
                const mark = self.visible.items.len;
                defer self.popLocalsTo(mark);
                const sc = try self.openScope();
                defer self.closeScope(sc);

                // The scope it opens rather than the one it sits in: a point
                // inside the braces sees what the block declares.
                self.scope_of_expr.items[id.index()] = sc;

                const inner = self.ast.blockOf(id);
                for (self.ast.blockStmts(inner)) |s| try self.declare(s);
                if (inner.tail != ExprId.none) try self.expr(inner.tail);
            },
        }
        if (self.ast.exprTag(id) != .name_ref) try self.noteTemplateClosureValue(id);
    }

    /// Resolves what a bracket holds, once its head is resolved.
    ///
    /// A head naming a function takes the brackets as its type arguments, and
    /// only that reading is resolved, called or not: `create[UInt8]` is the
    /// function's instance as a value. A called head selecting a name from a
    /// value reaches a method or a field, which the checker decides once it
    /// knows the value's type, so both readings are resolved here and what
    /// each would report is kept for that decision; uncalled, it is a field,
    /// and indexed. A head that reaches nothing is the mistake, and the
    /// brackets add no report of their own. Any other head is indexed.
    fn bracketReadings(self: *Resolver, id: ExprId, called: bool) std.mem.Allocator.Error!void {
        const b = self.ast.binary(id);
        const types = self.ast.typeArgs(self.ast.bracketTypes(id).?);
        const head = b.lhs;
        const target = self.targetOf(head);
        const selects_from_a_value = self.ast.exprTag(head) == .field and baseNamesAValue(self, self.ast, self.ast.unaryOperand(head));
        const held: Resolution.BracketReading = if (selects_from_a_value and !called)
            .index
        else if (selects_from_a_value)
            .{ .member = .{
                .index_reports = try self.quietly(.index, b.rhs, types),
                .type_reports = try self.quietly(.type_arguments, b.rhs, types),
            } }
        else if (target != BindingId.none and self.kindOf(target) == .function)
            .type_arguments
        else if (self.trait_selections.contains(head))
            .type_arguments
        else if (target == BindingId.none and self.integer_selections.get(head) == null)
            .unresolved
        else
            .index;
        switch (held) {
            .type_arguments => for (types) |ref| try self.useRefIn(ref, .type_argument),
            // Contents that read only as a list form no index, which the
            // checker reports once; the names in the list are still uses, so
            // none is reported unused as well.
            .index => if (self.ast.exprTag(b.rhs) == .err) {
                _ = try self.quietly(.type_arguments, b.rhs, types);
            } else try self.expr(b.rhs),
            // The names written in the brackets are still uses, so a type
            // named only there is not reported unused as well.
            .unresolved => _ = try self.quietly(.type_arguments, b.rhs, types),
            .member => {},
        }
        try self.bracket_readings.put(self.gpa, id, held);
    }

    /// Resolves one reading of a bracket and returns what it would report
    /// rather than reporting it.
    fn quietly(
        self: *Resolver,
        comptime which: enum { index, type_arguments },
        index: ExprId,
        types: []const node.TypeRef,
    ) std.mem.Allocator.Error![]const Diagnostic {
        var quiet = Sink.init(self.sink.arena);
        const loud = self.sink;
        self.sink = &quiet;
        defer self.sink = loud;
        switch (which) {
            .index => try self.expr(index),
            .type_arguments => for (types) |ref| try self.useRefIn(ref, .type_argument),
        }
        return quiet.list.items;
    }

    /// Whether an expression subtree contains a region the parser gave up on.
    fn containsErr(self: *const Resolver, id: ExprId) bool {
        if (id == ExprId.none) return true;
        return switch (self.ast.exprTag(id)) {
            .err => true,
            .int_literal, .float_literal, .str_literal, .bool_literal, .unit_literal, .name_ref, .param_argument, .reflection_root, .struct_pattern, .tuple_pattern => false,
            .lambda => blk: {
                const lambda = self.ast.lambda(id);
                for (lambda.captures) |capture| if (self.containsErr(capture.source)) break :blk true;
                for (lambda.params) |p| {
                    if (p.default != ExprId.none and self.containsErr(p.default)) break :blk true;
                }
                break :blk self.containsErr(lambda.body);
            },
            .interp => blk: {
                for (self.ast.interpolation(id).pieces) |a| {
                    if (self.containsErr(a)) break :blk true;
                }
                break :blk false;
            },
            .conditional => blk: {
                const c = self.ast.conditional(id);
                break :blk self.containsErr(c.cond) or self.containsErr(c.then) or
                    (c.otherwise != ExprId.none and self.containsErr(c.otherwise));
            },
            .grouped, .negate, .not, .loop_, .borrow, .dereference, .copy_, .panic, .try_, .from_end => self.containsErr(self.ast.unaryOperand(id)),
            .break_, .return_ => blk: {
                const value = self.ast.unaryOperand(id);
                break :blk value != ExprId.none and self.containsErr(value);
            },
            .continue_ => false,
            .variant_ref => blk: {
                const q = self.ast.unaryOperand(id);
                break :blk q != ExprId.none and self.containsErr(q);
            },
            .field => self.containsErr(self.ast.unaryOperand(id)),
            .struct_literal => blk: {
                const c = self.ast.call(id);
                for (c.args) |a| {
                    if (self.containsErr(a)) break :blk true;
                }
                break :blk c.callee != ExprId.none and self.containsErr(c.callee);
            },
            .marked => self.containsErr(self.ast.unaryOperand(id)),
            .array_literal, .tuple_literal => blk: {
                for (self.ast.call(id).args) |a| {
                    if (self.containsErr(a)) break :blk true;
                }
                break :blk false;
            },
            .match_, .match_read, .for_, .for_read, .for_inout, .call, .unwrap_else => blk: {
                const c = self.ast.call(id);
                if (self.containsErr(c.callee)) break :blk true;
                for (c.args) |a| {
                    if (self.containsErr(a)) break :blk true;
                }
                break :blk false;
            },
            .index, .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge, .while_, .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign, .logical_and, .logical_or => blk: {
                const b = self.ast.binary(id);
                break :blk self.containsErr(b.lhs) or self.containsErr(b.rhs);
            },
            .range => blk: {
                const ends = self.ast.rangeEnds(id);
                break :blk self.containsErr(ends.lhs) or self.containsErr(ends.rhs);
            },
            .block => blk: {
                const inner = self.ast.blockOf(id);
                for (self.ast.blockStmts(inner)) |s| {
                    if (self.containsErr(self.ast.stmtData(s).init)) break :blk true;
                }
                break :blk inner.tail != ExprId.none and self.containsErr(inner.tail);
            },
        };
    }
};

// Makes every test build compile the tests `Resolver` holds, including a
// build filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Resolver;
}

fn resolveSource(gpa: std.mem.Allocator, text: []const u8) !struct {
    tree: ResolvedTree,
    res: Resolution,
    errors: u32,
    ast: Ast,
} {
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    const before = sink.error_count;
    const tree = try resolveTree(gpa, &ast, &sink);
    return .{
        .tree = tree,
        .res = tree.resolution,
        .errors = sink.error_count - before,
        .ast = ast,
    };
}

fn declSpelledIn(ast: *const Ast, range: node.DeclRange, name: []const u8) DeclId {
    for (range.start..range.end) |i| {
        const decl = DeclId.at(@intCast(i));
        if (std.mem.eql(u8, ast.tokenText(ast.declName(decl)), name)) return decl;
    }
    return .none;
}

fn diagnosticCodeCount(sink: *const Sink, code: Code) usize {
    var count: usize = 0;
    for (sink.items()) |diagnostic| {
        if (diagnostic.code == code) count += 1;
    }
    return count;
}

test "resolution borrows source syntax without expansion declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try resolveSource(arena.allocator(), "fn main() -> UInt8 { 0 }");
    try testing.expect(result.tree.expanded.ast.parts.ptr == result.ast.parts.ptr);
}

test "derive expands ordinary members" {
    const gpa = testing.allocator;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const source: Source = .{ .path = "linea-derive-0.lin", .text =
        \\trait Structural {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\struct Mark { value: UInt8 }
        \\derive Structural for Mark
        \\fn main() -> UInt8 {
        \\    let mark: Mark = .{ value = 1 }
        \\    Structural.value(mark)
        \\}
        \\
    };
    var trees = Modules.init(gpa, &sink, &interner);
    defer trees.deinit();
    const decls = try trees.add(&.{.{ .file = .from(0), .source = source }});
    const ast = try trees.finish();
    var modules = [_]program_mod.Module{.{
        .name = "",
        .dir = "",
        .files = &.{.from(0)},
        .decls = decls,
        .imports = &.{},
    }};
    var program: Program = .{ .modules = &modules, .ast = ast };
    defer program.ast.deinit(gpa);

    var result = try resolve(gpa, &program, &interner, &sink, .program);
    defer result.resolution.deinit(gpa);
    defer result.expanded.deinit(gpa);

    const source_ast = &program.ast;
    var source_trait = DeclId.none;
    var source_target = DeclId.none;
    var source_template = DeclId.none;
    var source_signature = DeclId.none;
    var source_derive = DeclId.none;
    for (0..source_ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        switch (source_ast.declTag(d)) {
            .trait_ => source_trait = d,
            .struct_ => source_target = d,
            .template_impl => source_template = d,
            .derive_impl => source_derive = d,
            .function => if (source_ast.declIsSignature(d)) {
                source_signature = d;
            },
            else => {},
        }
    }

    const expanded = &result.expanded;
    const source_trait_token = source_ast.deriveTraits(source_derive)[0].ref.name;
    var generated_impl = DeclId.none;
    var generated_member = DeclId.none;
    for (expanded.declsOf(.from(0))) |d| {
        const origin = expanded.originOf(d) orelse continue;
        try testing.expectEqual(source_derive, origin.derive);
        try testing.expectEqual(source_trait_token, origin.derive_trait);
        switch (expanded.ast.declTag(d)) {
            .impl_ => generated_impl = d,
            .function => generated_member = d,
            else => return error.TestUnexpectedResult,
        }
    }

    try testing.expect(!expanded.isActive(source_template));
    try testing.expect(!expanded.isActive(source_derive));
    try testing.expect(generated_impl != .none);
    try testing.expect(generated_member != .none);
    try testing.expect(expanded.isActive(generated_impl));
    try testing.expect(expanded.isActive(generated_member));
    try testing.expectEqual(ModuleId.from(0), expanded.moduleOf(generated_impl));
    try testing.expectEqual(ModuleId.from(0), expanded.moduleOf(generated_member));
    try testing.expectEqual(generated_impl, result.resolution.implEnclosing(generated_member));

    const resolved_trait = result.resolution.writtenAt(expanded.ast.declTrait(generated_impl));
    const resolved_target = result.resolution.writtenAt(expanded.ast.declName(generated_impl));
    try testing.expectEqual(source_trait, result.resolution.declaredBy(resolved_trait));
    try testing.expectEqual(source_target, result.resolution.declaredBy(resolved_target));
    try testing.expectEqual(@as(usize, 1), expanded.template_members.len);
    try testing.expectEqual(source_template, expanded.template_members[0].template);
    try testing.expectEqual(source_trait, expanded.template_members[0].trait);
    try testing.expectEqual(source_signature, expanded.template_members[0].signature);
    try testing.expectEqual(
        expanded.originOf(generated_member).?.template_member,
        expanded.template_members[0].member,
    );
    try testing.expectEqualStrings("linea-derive-1.lin", expanded.ast.parts[source_ast.parts.len].path);
    try testing.expectEqual(source_ast.tokenSpan(source_trait_token), expanded.primarySpanOfDecl(generated_impl));
}

test "grouped generic derive expands entries and preserves constraints" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait First {}
        \\template impl First {}
        \\trait Second {}
        \\template impl Second {}
        \\struct Pair[T] { left: T, right: T }
        \\derive[T: Copyable] (First, Second) for Pair[T] where
        \\    T: Copyable,
        \\fn main() -> UInt8 {
        \\    let _pair: Pair[UInt8] = .{ left = 1, right = 2 }
        \\    0
        \\}
    );
    try testing.expectEqual(@as(u32, 0), result.errors);

    const source_ast = &result.ast;
    const expanded = &result.tree.expanded;
    try testing.expectEqual(@as(usize, 2), expanded.generated_sources.buffers.len);
    try testing.expectEqualDeep(
        source_ast.derive_traits,
        expanded.ast.derive_traits[0..source_ast.derive_traits.len],
    );
    try testing.expectEqualDeep(
        source_ast.template_requirements,
        expanded.ast.template_requirements[0..source_ast.template_requirements.len],
    );

    var derive = DeclId.none;
    for (0..source_ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (source_ast.declTag(d) == .derive_impl) derive = d;
    }
    try testing.expect(derive != .none);
    const entries = source_ast.deriveTraits(derive);
    try testing.expectEqual(@as(usize, 2), entries.len);

    var generated_at: usize = 0;
    for (expanded.declsOf(.from(0))) |d| {
        if (expanded.ast.declTag(d) != .impl_) continue;
        const origin = expanded.originOf(d) orelse continue;
        try testing.expect(generated_at < entries.len);
        try testing.expectEqual(derive, origin.derive);
        try testing.expectEqual(entries[generated_at].ref.name, origin.derive_trait);
        try testing.expectEqual(@as(usize, 1), expanded.ast.declTypeParams(d).len);
        try testing.expectEqual(@as(u32, 1), expanded.ast.declHead(d).args.len());
        try testing.expectEqual(@as(usize, 1), expanded.ast.declWherePredicates(d).len);
        try testing.expectEqual(source_ast.tokenSpan(entries[generated_at].ref.name), expanded.primarySpanOfDecl(d));
        generated_at += 1;
    }
    try testing.expectEqual(@as(usize, 2), generated_at);
    try testing.expect(std.mem.indexOf(u8, expanded.generated_sources.get(0), "impl[T: Copyable] First for Pair[T]") != null);
    try testing.expect(std.mem.indexOf(u8, expanded.generated_sources.get(1), "impl[T: Copyable] Second for Pair[T]") != null);
}

test "grouped generic derive keeps a valid sibling expansion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Missing {}
        \\trait Good {}
        \\template impl Good {}
        \\struct Mark {}
        \\derive (Missing, Good) for Mark
        \\fn main() -> UInt8 { let _mark: Mark = .{}; 0 }
    );
    try testing.expectEqual(@as(u32, 1), result.errors);
    try testing.expectEqual(@as(usize, 1), result.tree.expanded.generated_sources.buffers.len);
    try testing.expect(std.mem.indexOf(u8, result.tree.expanded.generated_sources.get(0), "impl Good for Mark") != null);
}

test "attached derive keeps a valid sibling after an unresolved trait" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Good {}
        \\template impl Good {}
        \\@derive(Missing, Good)
        \\struct Mark {}
        \\fn main() -> UInt8 { let _mark = Mark {}; 0 }
    );
    try testing.expectEqual(@as(u32, 1), result.errors);
    try testing.expectEqual(@as(usize, 1), result.tree.expanded.generated_sources.buffers.len);
    try testing.expect(std.mem.indexOf(u8, result.tree.expanded.generated_sources.get(0), "impl Good for Mark") != null);
}

test "attached derive validates its shared header once before expansion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const baseline = try resolveSource(arena.allocator(),
        \\struct Mark[T, T] { value: T }
        \\fn main() -> UInt8 { 0 }
    );
    const result = try resolveSource(arena.allocator(),
        \\trait Good {}
        \\template impl Good {}
        \\@derive(Good)
        \\struct Mark[T, T] { value: T }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(baseline.errors, result.errors);
    try testing.expectEqual(@as(usize, 0), result.tree.expanded.generated_sources.buffers.len);
}

test "an attached trait argument does not make a parameter part of representation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Good {}
        \\template impl Good {}
        \\@derive(Good[T])
        \\struct Mark[T] {}
        \\fn main() -> UInt8 { let _mark = Mark[UInt8] {}; 0 }
    );
    // The unsupported trait argument, and `T` remaining unused by the
    // representation.
    try testing.expectEqual(@as(u32, 2), result.errors);
    try testing.expectEqual(@as(usize, 0), result.tree.expanded.generated_sources.buffers.len);
}

test "grouped generic derive rejects trait arguments without dropping a sibling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Good {}
        \\template impl Good {}
        \\struct Mark {}
        \\derive (Good[UInt8], Good) for Mark
        \\fn main() -> UInt8 { let _mark: Mark = .{}; 0 }
    );
    try testing.expectEqual(@as(u32, 1), result.errors);
    try testing.expectEqual(@as(usize, 1), result.tree.expanded.generated_sources.buffers.len);
    try testing.expect(std.mem.indexOf(u8, result.tree.expanded.generated_sources.get(0), "impl Good for Mark") != null);
}

test "grouped generic derive separates impl from a delimiter-adjacent trait" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait First {}
        \\template impl First {}
        \\struct Mark {}
        \\derive(First) for Mark
        \\fn main() -> UInt8 { let _mark: Mark = .{}; 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);
    try testing.expectEqual(@as(usize, 1), result.tree.expanded.generated_sources.buffers.len);
    try testing.expect(std.mem.indexOf(u8, result.tree.expanded.generated_sources.get(0), "impl First for Mark") != null);
}

test "grouped generic derive does not expand an invalid shared environment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait First {}
        \\template impl First {}
        \\trait Second {}
        \\template impl Second {}
        \\struct Pair[T] { value: T }
        \\derive[T: Missing] (First, Second) for Pair[T]
        \\fn main() -> UInt8 { let _pair: Pair[UInt8] = .{ value = 1 }; 0 }
    );
    try testing.expectEqual(@as(u32, 1), result.errors);
    try testing.expectEqual(@as(usize, 0), result.tree.expanded.generated_sources.buffers.len);
}

test "component requirement rows preserve component and bound order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait First {}
        \\trait Second {}
        \\trait Structural {}
        \\template impl Structural where reflect.components: First + Second {}
        \\struct Pair { left: UInt8, right: UInt16 }
        \\derive Structural for Pair
        \\fn main() -> UInt8 { let _pair: Pair = .{ left = 1, right = 2 }; 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);

    const source_ast = &result.ast;
    var derive = DeclId.none;
    var target = DeclId.none;
    var template = DeclId.none;
    for (0..source_ast.declCount()) |i| {
        const decl = DeclId.at(@intCast(i));
        switch (source_ast.declTag(decl)) {
            .derive_impl => derive = decl,
            .struct_ => target = decl,
            .template_impl => template = decl,
            else => {},
        }
    }

    const expanded = &result.tree.expanded;
    try testing.expectEqual(@as(u32, 1), expanded.generatedImplementationCount());
    const implementation_id = expanded_mod.GeneratedImplementationId.at(0);
    const implementation = expanded.generatedImplementation(implementation_id);
    try testing.expectEqual(derive, implementation.derive);
    try testing.expectEqual(source_ast.deriveTraitRange(derive).start, implementation.derive_trait.index());
    try testing.expectEqual(target, implementation.target);
    try testing.expectEqual(template, implementation.template);
    try testing.expectEqual(node.Decl.Tag.impl_, expanded.ast.declTag(implementation.generated_impl));

    const rows = expanded.componentRequirements(implementation_id);
    try testing.expectEqual(@as(usize, 4), rows.len);
    const expected = [_]expanded_mod.ComponentRequirement{
        .{ .implementation = implementation_id, .requirement = .at(0), .bound = @enumFromInt(0), .component = @enumFromInt(0) },
        .{ .implementation = implementation_id, .requirement = .at(0), .bound = @enumFromInt(1), .component = @enumFromInt(0) },
        .{ .implementation = implementation_id, .requirement = .at(0), .bound = @enumFromInt(0), .component = @enumFromInt(1) },
        .{ .implementation = implementation_id, .requirement = .at(0), .bound = @enumFromInt(1), .component = @enumFromInt(1) },
    };
    try testing.expectEqualSlices(expanded_mod.ComponentRequirement, &expected, rows);
}

test "enum component requirement rows follow case and payload order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Required {}
        \\trait Structural {}
        \\template impl Structural where reflect.components: Required {}
        \\enum Value { Empty, One(UInt8), Pair(UInt16, UInt32) }
        \\derive Structural for Value
        \\fn main() -> UInt8 { let _value: Value = .Empty; 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);

    const implementation_id = expanded_mod.GeneratedImplementationId.at(0);
    const rows = result.tree.expanded.componentRequirements(implementation_id);
    try testing.expectEqual(@as(usize, 3), rows.len);
    try testing.expectEqual(@as(u32, 1), @intFromEnum(rows[0].case));
    try testing.expectEqual(@as(u32, 0), @intFromEnum(rows[0].component));
    try testing.expectEqual(@as(u32, 2), @intFromEnum(rows[1].case));
    try testing.expectEqual(@as(u32, 0), @intFromEnum(rows[1].component));
    try testing.expectEqual(@as(u32, 2), @intFromEnum(rows[2].case));
    try testing.expectEqual(@as(u32, 1), @intFromEnum(rows[2].component));
}

test "component requirement resolution accepts closed nested trait arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Required[phantom T] {}
        \\trait Structural {}
        \\struct Inner {}
        \\struct Outer[T] { value: T }
        \\template impl Structural where reflect.components: Required[Outer[Inner]] {}
        \\struct Target {}
        \\derive Structural for Target
        \\fn main() -> UInt8 { let _target: Target = .{}; 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);

    const ast = &result.ast;
    const all_decls = node.DeclRange{ .start = 0, .end = ast.declCount() };
    var template_impl = DeclId.none;
    for (0..ast.declCount()) |i| {
        const decl = DeclId.at(@intCast(i));
        if (ast.declTag(decl) == .template_impl) template_impl = decl;
    }
    try testing.expect(template_impl != .none);
    const requirement = ast.templateRequirements(template_impl)[0];
    const bound = ast.boundsIn(requirement.bounds)[0];
    const outer = ast.typeArgs(bound.named.args)[0];
    const inner = ast.typeArgs(outer.args)[0];
    try testing.expectEqual(
        declSpelledIn(ast, all_decls, "Required"),
        result.res.declaredBy(result.res.writtenAt(bound.named.name)),
    );
    try testing.expectEqual(
        declSpelledIn(ast, all_decls, "Outer"),
        result.res.declaredBy(result.res.writtenAt(outer.name)),
    );
    try testing.expectEqual(
        declSpelledIn(ast, all_decls, "Inner"),
        result.res.declaredBy(result.res.writtenAt(inner.name)),
    );
}

test "component requirement resolution uses the template lexical module" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    var trees = Modules.init(gpa, &sink, &interner);
    defer trees.deinit();
    const app_decls = try trees.add(&.{.{
        .file = .from(0),
        .source = .{ .path = "app/main.lin", .text =
        \\trait Required[phantom T] {}
        \\trait Structural {}
        \\struct Choice {}
        \\template impl Structural where reflect.components: Required[Choice] {}
        \\struct Target {}
        \\derive Structural for Target
        \\fn main() -> UInt8 { let _target: Target = .{}; 0 }
        },
    }});
    const other_decls = try trees.add(&.{.{
        .file = .from(1),
        .source = .{ .path = "other/main.lin", .text = "pub struct Choice {}\n" },
    }});
    const ast = try trees.finish();
    var modules = [_]program_mod.Module{
        .{ .name = "app", .dir = "app", .files = &.{.from(0)}, .decls = app_decls, .imports = &.{} },
        .{ .name = "other", .dir = "other", .files = &.{.from(1)}, .decls = other_decls, .imports = &.{}, .library = true },
    };
    var program: Program = .{ .modules = &modules, .ast = ast };
    defer program.ast.deinit(gpa);
    var result = try resolve(gpa, &program, &interner, &sink, .program);
    defer result.expanded.deinit(gpa);
    defer result.resolution.deinit(gpa);
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    var template = DeclId.none;
    for (app_decls.start..app_decls.end) |i| {
        const decl = DeclId.at(@intCast(i));
        if (program.ast.declTag(decl) == .template_impl) template = decl;
    }
    try testing.expect(template != .none);
    const requirement = program.ast.templateRequirements(template)[0];
    const bound = program.ast.boundsIn(requirement.bounds)[0];
    const argument = program.ast.typeArgs(bound.named.args)[0];
    const local = declSpelledIn(&program.ast, app_decls, "Choice");
    const other = declSpelledIn(&program.ast, other_decls, "Choice");
    const reached = result.resolution.declaredBy(result.resolution.writtenAt(argument.name));
    try testing.expectEqual(local, reached);
    try testing.expect(reached != other);
}

test "component requirement resolution rejects capability and callable bounds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\trait Structural {}
        \\template impl Structural where
        \\    reflect.components: Copyable,
        \\    reflect.components: fn(read value: UInt8) -> UInt8,
        \\{}
        \\struct Target {}
        \\derive Structural for Target
        \\fn main() -> UInt8 { let _target: Target = .{}; 0 }
    , &sink);
    try testing.expectEqual(@as(u32, 2), sink.error_count);
    try testing.expectEqual(@as(usize, 2), diagnosticCodeCount(&sink, .t_template));
}

test "component requirement resolution rejects Self arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Required[phantom T] {}
        \\trait Structural {}
        \\struct Closed {}
        \\struct Wrapper[A, B] { left: A, right: B }
        \\template impl Structural where reflect.components: Required[Wrapper[Self, Closed]] {}
        \\struct Target {}
        \\derive Structural for Target
        \\fn main() -> UInt8 { let _target: Target = .{}; 0 }
    );
    try testing.expectEqual(@as(u32, 1), result.errors);

    const ast = &result.ast;
    const all_decls = node.DeclRange{ .start = 0, .end = ast.declCount() };
    var template_impl = DeclId.none;
    for (0..ast.declCount()) |i| {
        const declaration = DeclId.at(@intCast(i));
        if (ast.declTag(declaration) == .template_impl) template_impl = declaration;
    }
    try testing.expect(template_impl != .none);
    const requirement = ast.templateRequirements(template_impl)[0];
    const bound = ast.boundsIn(requirement.bounds)[0];
    const wrapper = ast.typeArgs(bound.named.args)[0];
    const arguments = ast.typeArgs(wrapper.args);
    try testing.expectEqual(
        declSpelledIn(ast, all_decls, "Wrapper"),
        result.res.declaredBy(result.res.writtenAt(wrapper.name)),
    );
    try testing.expectEqual(
        declSpelledIn(ast, all_decls, "Closed"),
        result.res.declaredBy(result.res.writtenAt(arguments[1].name)),
    );
}

test "component requirement resolution rejects reflection descriptor arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\trait Required[phantom T] {}
        \\trait Structural {}
        \\template impl Structural where reflect.components: Required[reflect.components] {}
        \\fn main() -> UInt8 { 0 }
    , &sink);
    try testing.expect(sink.error_count > 0);
    try testing.expect(diagnosticCodeCount(&sink, .s_type) > 0);
}

test "component requirement resolution preserves undefined and non-trait diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\pub fn not_trait() -> UInt8 { 0 }
        \\trait Structural {}
        \\template impl Structural where reflect.components: Missing + not_trait {}
        \\struct Target {}
        \\derive Structural for Target
        \\fn main() -> UInt8 { let _target: Target = .{}; 0 }
    , &sink);
    try testing.expectEqual(@as(u32, 2), sink.error_count);
    try testing.expectEqual(@as(usize, 1), diagnosticCodeCount(&sink, .n_undefined));
    try testing.expectEqual(@as(usize, 1), diagnosticCodeCount(&sink, .n_not_a_type));
}

test "component requirement rows retain an empty target descriptor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Required {}
        \\trait Structural {}
        \\template impl Structural where reflect.components: Required {}
        \\struct Empty {}
        \\derive Structural for Empty
        \\fn main() -> UInt8 { let _empty: Empty = .{}; 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);

    const expanded = &result.tree.expanded;
    try testing.expectEqual(@as(u32, 1), expanded.generatedImplementationCount());
    const implementation_id = expanded_mod.GeneratedImplementationId.at(0);
    const implementation = expanded.generatedImplementation(implementation_id);
    try testing.expectEqual(@as(u32, 0), implementation.requirements.len());
    try testing.expectEqual(@as(usize, 0), expanded.componentRequirements(implementation_id).len);
}

test "component requirement rows preflight near-limit entries transactionally" {
    const almost_full = Resolver.ExpansionCapacity{
        .source_domain_end = 10,
        .generated_file_end = 20,
        .implementation_count = std.math.maxInt(u32),
        .requirement_count = 30,
    };
    var capacity = almost_full;
    try testing.expectEqual(@as(?Resolver.ExpansionReservation, null), capacity.reserve(12, 2, 2));
    try testing.expectEqual(almost_full, capacity);

    capacity = .{
        .source_domain_end = 10,
        .generated_file_end = 20,
        .implementation_count = 30,
        .requirement_count = std.math.maxInt(u32) - 1,
    };
    const before_rows = capacity;
    try testing.expectEqual(@as(?Resolver.ExpansionReservation, null), capacity.reserve(12, 1, 2));
    try testing.expectEqual(before_rows, capacity);

    capacity = .{
        .source_domain_end = std.math.maxInt(u32),
        .generated_file_end = 20,
        .implementation_count = 30,
        .requirement_count = 40,
    };
    const before_source = capacity;
    try testing.expectEqual(@as(?Resolver.ExpansionReservation, null), capacity.reserve(1, 1, 1));
    try testing.expectEqual(before_source, capacity);

    capacity = .{
        .source_domain_end = 10,
        .generated_file_end = std.math.maxInt(u32),
        .implementation_count = 30,
        .requirement_count = 40,
    };
    const before_file = capacity;
    try testing.expectEqual(@as(?Resolver.ExpansionReservation, null), capacity.reserve(1, 1, 1));
    try testing.expectEqual(before_file, capacity);

    capacity = .{
        .source_domain_end = 10,
        .generated_file_end = 20,
        .implementation_count = 30,
        .requirement_count = 40,
    };
    const before_product = capacity;
    try testing.expectEqual(@as(?Resolver.ExpansionReservation, null), capacity.reserve(1, std.math.maxInt(u32), 2));
    try testing.expectEqual(before_product, capacity);

    capacity = .{
        .source_domain_end = 10,
        .generated_file_end = 20,
        .implementation_count = 30,
        .requirement_count = 40,
    };
    const reserved = capacity.reserve(12, 2, 3) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(expanded_mod.GeneratedImplementationId.at(30), reserved.implementation);
    try testing.expectEqual(expanded_mod.ComponentRequirementRange{ .start = 40, .end = 46 }, reserved.requirements);
    try testing.expectEqual(@as(u32, 20), reserved.generated_file);
    try testing.expectEqual(@as(u32, 23), capacity.source_domain_end);
    try testing.expectEqual(@as(u32, 21), capacity.generated_file_end);
    try testing.expectEqual(@as(u32, 31), capacity.implementation_count);
    try testing.expectEqual(@as(u32, 46), capacity.requirement_count);
}

fn resolveTestText(gpa: std.mem.Allocator, path: []const u8, text: []const u8, sink: *Sink) !void {
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const source: Source = .{ .path = path, .text = text };
    const tokens = try tokenize(gpa, &source, .from(0), sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, sink);
    defer ast.deinit(gpa);
    var modules = [_]program_mod.Module{.{
        .name = "",
        .dir = "",
        .files = &.{.from(0)},
        .decls = .{ .start = 0, .end = ast.declCount() },
        .imports = &.{},
    }};
    const program: Program = .{ .modules = &modules, .ast = ast };
    var result = try resolve(gpa, &program, &interner, sink, .program);
    defer result.expanded.deinit(gpa);
    defer result.resolution.deinit(gpa);
}

fn diagnosticContains(sink: *const Sink, needle: []const u8) bool {
    for (sink.items()) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.message, needle) != null) return true;
        for (diagnostic.labels) |label| {
            if (std.mem.indexOf(u8, label.message, needle) != null) return true;
        }
    }
    return false;
}

test "an import takes no internal visibility" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\internal import support
        \\fn main() -> UInt8 { 0 }
    , &sink);
    try testing.expectEqual(@as(usize, 1), diagnosticCodeCount(&sink, .s_entry));
    try testing.expect(diagnosticContains(&sink, "an import takes no modifier"));
}

test "an internal name does not cross loaded roots" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    var trees = Modules.init(gpa, &sink, &interner);
    defer trees.deinit();

    const app_decls = try trees.add(&.{.{
        .file = .from(0),
        .source = .{ .path = "app/main.lin", .text =
        \\import support
        \\fn main() -> UInt8 { support.value() }
        },
    }});
    const support_decls = try trees.add(&.{.{
        .file = .from(1),
        .source = .{ .path = "support/main.lin", .text =
        \\internal fn value() -> UInt8 { 7 }
        },
    }});
    const ast = try trees.finish();
    var imports = [_]program_mod.Import{.{
        .decl = DeclId.at(app_decls.start),
        .module = .from(1),
    }};
    var modules = [_]program_mod.Module{
        .{ .name = "app", .dir = "app", .files = &.{.from(0)}, .decls = app_decls, .imports = &imports },
        .{ .name = "support", .dir = "support", .files = &.{.from(1)}, .decls = support_decls, .imports = &.{}, .root = .from(1) },
    };
    const program: Program = .{ .modules = &modules, .ast = ast };
    var result = try resolve(gpa, &program, &interner, &sink, .program);
    defer result.expanded.deinit(gpa);
    defer result.resolution.deinit(gpa);

    try testing.expectEqual(@as(usize, 1), diagnosticCodeCount(&sink, .m_vis));

    var reachable: std.ArrayList(BindingId) = .empty;
    defer reachable.deinit(gpa);
    try result.resolution.reachableThrough(gpa, &program, .from(1), .from(0), &reachable);
    try testing.expectEqual(@as(usize, 0), reachable.items.len);
    try result.resolution.reachableThrough(gpa, &program, .from(1), .from(1), &reachable);
    try testing.expectEqual(@as(usize, 1), reachable.items.len);
    try testing.expectEqual(Reach.root, result.resolution.namingReachOf(reachable.items[0]));
}

test "unused function templates reach symbolic type checking" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\trait Structural {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\fn main() -> UInt8 { 0 }
    , &sink);
    try testing.expect(!diagnosticContains(&sink, "unused function template"));
}

test "unused templates accept module free references with matching reach" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\fn _helper() -> UInt8 { 7 }
        \\trait Structural {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { _helper() }
        \\}
        \\fn main() -> UInt8 { 0 }
    , &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
}

fn expectReflectionError(text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin", text, &sink);
    try testing.expectEqual(@as(u32, 1), sink.error_count);
    try testing.expectEqual(Code.t_reflection, sink.items()[0].code.?);
}

test "structural reflection plans template operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\trait Structural {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self {
        \\            reflect.case => {
        \\                var total: UInt8 = 0
        \\                for component in reflect.components.reversed {
        \\                    total = total + component.of(_self)
        \\                }
        \\                total
        \\            }
        \\        }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    , &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
}

test "construction hygiene reserves deriving type parameter names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Build { fn build() -> Self }
        \\template impl Build where reflect.target: struct, reflect.components: Build {
        \\    fn build() -> Self {
        \\        reflect.construct(reflect.product, |component| {
        \\            let field: component.Type = Build.build()
        \\            field
        \\        }, {})
        \\    }
        \\}
        \\struct Item[T] { field: T }
        \\derive[_linea_derive_5_0_0_0: Build] Build for Item[_linea_derive_5_0_0_0]
        \\fn main() -> UInt8 { 0 }
    );
    // The lowercase type parameter is refused under [N-Case] and is the only
    // error: the generated local is still renamed away from it.
    try testing.expectEqual(@as(u32, 1), result.errors);
    const generated = result.tree.expanded.generated_sources.get(0);
    try testing.expect(std.mem.indexOf(u8, generated, "let _linea_derive_5_0_0_0:") == null);
}

test "structural reflection renders ordinary members" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const struct_result = try resolveSource(gpa,
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self { reflect.case => {
        \\            var total: UInt8 = 0
        \\            for component in reflect.components.reversed {
        \\                total = total * 10 + component.of(_self)
        \\            }
        \\            total
        \\        } }
        \\    }
        \\}
        \\struct Digits { tens: UInt8, ones: UInt8 }
        \\derive Structural for Digits
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), struct_result.errors);
    const struct_text = struct_result.tree.expanded.generated_sources.get(0);
    try testing.expect(std.mem.indexOf(u8, struct_text, "reflect") == null);
    try testing.expect(std.mem.indexOf(
        u8,
        struct_text,
        "Digits { tens: _linea_derive_5_0_0_0, ones: _linea_derive_5_0_1_0, }",
    ) != null);
    const ones = std.mem.indexOf(u8, struct_text, "total = total * 10 + _linea_derive_5_0_1_0") orelse return error.TestUnexpectedResult;
    const tens = std.mem.indexOfPos(u8, struct_text, ones + 1, "total = total * 10 + _linea_derive_5_0_0_0") orelse return error.TestUnexpectedResult;
    try testing.expect(ones < tens);

    const newtype_result = try resolveSource(gpa,
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self { reflect.case => for component in reflect.components {
        \\            component.of(_self)
        \\        } }
        \\    }
        \\}
        \\type Meters = UInt8
        \\derive Structural for Meters
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), newtype_result.errors);
    const newtype_text = newtype_result.tree.expanded.generated_sources.get(0);
    try testing.expect(std.mem.indexOf(u8, newtype_text, "reflect") == null);
    try testing.expect(std.mem.indexOf(u8, newtype_text, "Meters(_linea_derive_5_0_0_0)") != null);

    const empty_result = try resolveSource(gpa,
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { match _self { reflect.case => 7 } }
        \\}
        \\struct Empty {}
        \\derive Structural for Empty
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), empty_result.errors);
    const empty_text = empty_result.tree.expanded.generated_sources.get(0);
    try testing.expect(std.mem.indexOf(u8, empty_text, "reflect") == null);
    try testing.expect(std.mem.indexOf(u8, empty_text, "match _self {\nEmpty { } => 7,") != null);
}

test "structural reflection renames erased parameters in source contracts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Structural {
        \\    fn view(self: Self, input: UInt8) -> borrow UInt8 where borrows(input)
        \\}
        \\template impl Structural {
        \\    fn view(self: Self, input: UInt8) -> borrow UInt8 where borrows(input) {
        \\        match read self { reflect.case => borrow input }
        \\    }
        \\}
        \\@copyable
        \\enum Empty {}
        \\derive Structural for Empty
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);
    const generated = result.tree.expanded.generated_sources.get(0);
    try testing.expect(std.mem.indexOf(u8, generated, "_input: UInt8") != null);
    try testing.expect(std.mem.indexOf(u8, generated, "borrows(_input)") != null);
}

test "structural reflection keeps erased parameter names distinct" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\trait Structural {
        \\    fn view(self: Self, input: UInt8, _input: UInt8) -> borrow UInt8 where borrows(input)
        \\}
        \\template impl Structural {
        \\    fn view(self: Self, input: UInt8, _input: UInt8) -> borrow UInt8 where borrows(input) {
        \\        let _probe = _input
        \\        match read self { reflect.case => borrow input }
        \\    }
        \\}
        \\@copyable
        \\enum Empty {}
        \\derive Structural for Empty
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);
    const generated = result.tree.expanded.generated_sources.get(0);
    try testing.expect(std.mem.indexOf(u8, generated, "__input: UInt8, _input: UInt8") != null);
    try testing.expect(std.mem.indexOf(u8, generated, "borrows(__input)") != null);
}

test "structural reflection plans T-Reflection requires a template" {
    try expectReflectionError(
        \\fn main() -> UInt8 { reflect.case; 0 }
    );
}

test "structural reflection plans T-Reflection enforces lexical nesting" {
    try expectReflectionError(
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        for _component in reflect.components { 0 }
        \\        0
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );

    try expectReflectionError(
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self {
        \\            reflect.case => match read _self { reflect.case => 0 }
        \\        }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );

    try expectReflectionError(
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self {
        \\            reflect.case => for _outer in reflect.components {
        \\                for _inner in reflect.components { 0 }
        \\            }
        \\        }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );

    try expectReflectionError(
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self { _ => 1, reflect.case => 0 }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );

    try expectReflectionError(
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self { reflect.case() => 0 }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );
}

test "structural reflection renders a component loop as one expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try resolveSource(arena.allocator(),
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self { reflect.case => for component in reflect.components {
        \\            let _value = component.of(_self)
        \\        } }
        \\        0
        \\    }
        \\}
        \\struct Pair { left: UInt8, right: UInt8 }
        \\derive Structural for Pair
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);
    const generated = result.tree.expanded.generated_sources.get(0);
    try testing.expect(std.mem.indexOf(u8, generated, "reflect") == null);

    const empty = try resolveSource(arena.allocator(),
        \\trait Structural { fn visit(sink self: Self) }
        \\template impl Structural {
        \\    fn visit(sink _self: Self) {
        \\        match _self { reflect.case => for component in reflect.components {
        \\            let _ = component.of(_self)
        \\        } }
        \\    }
        \\}
        \\struct Empty {}
        \\derive Structural for Empty
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), empty.errors);
    const empty_generated = empty.tree.expanded.generated_sources.get(0);
    try testing.expect(std.mem.indexOf(u8, empty_generated, "Empty { } => {\n}") != null);
    try testing.expect(std.mem.indexOf(u8, empty_generated, "_linea_derive_") == null);
}

test "structural reflection plans T-Reflection validates descriptor uses" {
    try expectReflectionError(
        \\trait Structural {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { reflect.components; 0 }
        \\}
        \\fn main() -> UInt8 { 0 }
    );

    try expectReflectionError(
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self { reflect.case => for component in reflect.components {
        \\            component.of(_self, _self)
        \\        } }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );

    try expectReflectionError(
        \\trait Structural { fn value(self: Self, other: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self, _other: Self) -> UInt8 {
        \\        match read _self { reflect.case => for component in reflect.components {
        \\            component.of(_other)
        \\        } }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );
}

test "structural reflection plans T-Reflection rejects reflected loop transfers" {
    try expectReflectionError(
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self { reflect.case => for _component in reflect.components { break } }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );

    try expectReflectionError(
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        match read _self { reflect.case => for _component in reflect.components { continue } }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    );
}

test "derive rejects omitted generic target arguments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\struct Box[phantom T] {}
        \\trait Structural {}
        \\template impl Structural {}
        \\derive Structural for Box
        \\fn main() -> UInt8 { 0 }
    , &sink);
    try testing.expect(diagnosticContains(&sink, "apply the target to exactly the number of parameters"));
}

test "derive diagnoses a primitive target" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\trait Structural {}
        \\template impl Structural {}
        \\derive Structural for UInt8
        \\fn main() -> UInt8 { 0 }
    , &sink);
    try testing.expect(diagnosticContains(&sink, "concrete declaration"));
}

/// Resolves a program of two modules, the second of them a module of the
/// library, named.
///
/// The compiler's own implementations are seeded against the traits a named
/// library module declares, so a program with no library reaches none of them
/// and a test about one has to say which module declares what. The name is what
/// the lookup keys on, so a test passing the wrong one seeds nothing — which is
/// the same answer a missing library gives, and is why it is a parameter rather
/// than a constant here.
fn resolveWithLibraryModule(
    gpa: std.mem.Allocator,
    app: []const u8,
    module: []const u8,
    library: []const u8,
) !struct { errors: u32, duplicates: u32 } {
    const app_source: Source = .{ .path = "app/main.lin", .text = app };
    const std_source: Source = .{ .path = "std/lib.lin", .text = library };

    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var trees = Modules.init(gpa, &sink, &interner);
    // The program before the library, which is the order they are loaded in:
    // a module owns a run of the tree, and the runs ascend.
    const app_decls = try trees.add(&.{.{ .file = .from(0), .source = app_source }});
    const std_decls = try trees.add(&.{.{ .file = .from(1), .source = std_source }});
    const ast = try trees.finish();

    var modules = [_]program_mod.Module{
        .{ .name = "app", .dir = "app", .files = &.{}, .decls = app_decls, .imports = &.{} },
        .{
            .name = module,
            .dir = "std",
            .files = &.{},
            .decls = std_decls,
            .imports = &.{},
            .library = true,
        },
    };
    // No prelude: what these seed is found by module and name, and nothing here
    // is a name a program writes without importing it.
    const program: Program = .{ .modules = &modules, .ast = ast };
    _ = try resolve(gpa, &program, &interner, &sink, .program);

    var duplicates: u32 = 0;
    for (sink.items()) |d| {
        if (d.code == .n_duplicate) duplicates += 1;
    }
    return .{ .errors = sink.error_count, .duplicates = duplicates };
}

/// Resolves `app` as a program whose prelude is a library manifest holding
/// `prelude`, so a test can publish a prelude declaration such as `Tuple2`
/// and ask what syntax naming it by identity resolved to.
fn resolveWithPrelude(
    gpa: std.mem.Allocator,
    app: []const u8,
    prelude: []const u8,
) !struct { errors: u32, duplicates: u32, undefined: u32, unsupported_derives: u32 } {
    const app_source: Source = .{ .path = "app/main.lin", .text = app };
    const std_source: Source = .{ .path = "std/std.lin", .text = prelude };

    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var trees = Modules.init(gpa, &sink, &interner);
    const app_decls = try trees.add(&.{.{ .file = .from(0), .source = app_source }});
    const std_decls = try trees.add(&.{.{ .file = .from(1), .source = std_source }});
    const ast = try trees.finish();

    var modules = [_]program_mod.Module{
        .{ .name = "app", .dir = "app", .files = &.{.from(0)}, .decls = app_decls, .imports = &.{} },
        .{ .name = "std", .dir = "std", .files = &.{.from(1)}, .decls = std_decls, .imports = &.{}, .library = true },
    };
    const program: Program = .{ .modules = &modules, .ast = ast, .prelude = .from(1) };
    _ = try resolve(gpa, &program, &interner, &sink, .program);

    var duplicates: u32 = 0;
    var undefined_names: u32 = 0;
    var unsupported_derives: u32 = 0;
    for (sink.items()) |d| {
        switch (d.code orelse continue) {
            .n_duplicate => duplicates += 1,
            .n_undefined => undefined_names += 1,
            .t_derive => unsupported_derives += 1,
            else => {},
        }
    }
    return .{ .errors = sink.error_count, .duplicates = duplicates, .undefined = undefined_names, .unsupported_derives = unsupported_derives };
}

/// The `nth` binding whose declaring token spells `name`, in declaration
/// order. Named from the source rather than from the tree, so a test asking
/// what the tree recorded does not find its subject through the tree.
fn bindingSpelled(ast: *const Ast, res: *const Resolution, name: []const u8, nth: usize) BindingId {
    var seen: usize = 0;
    for (0..res.bindingCount()) |i| {
        const b: BindingId = .at(@intCast(i));
        const tok = res.declaringToken(b);
        if (tok == TokenId.none) continue;
        if (!std.mem.eql(u8, ast.tokenText(tok), name)) continue;
        if (seen == nth) return b;
        seen += 1;
    }
    return BindingId.none;
}

test "resolution flags and reach are typed by bindings and preserve public answers" {
    inline for (.{ "reexported", "field_shorthand", "ambient", "referenced" }) |field| {
        const Field = @FieldType(Resolution, field);
        try testing.expect(Field == FinishedBindingBits);
        try testing.expect(!@hasDecl(Field, "set"));
        try testing.expect(@FieldType(Field, "words") == []const usize);
    }

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try resolveSource(arena.allocator(),
        \\struct Point { x: UInt8 }
        \\pub fn spare() -> UInt8 { 0 }
        \\fn main() -> UInt8 {
        \\    let local: UInt8 = 4
        \\    let p: Point = .{ x = local }
        \\    let Point { x } = p
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    inline for (.{ "reexported", "field_shorthand", "ambient", "referenced" }) |field| {
        try testing.expectEqual(@as(usize, r.res.bindingCount()), @field(r.res, field).len());
    }
    try testing.expectEqual(@as(usize, r.res.bindingCount()), r.res.reach.len);

    const local = bindingSpelled(&r.ast, &r.res, "local", 0);
    const field_binder = bindingSpelled(&r.ast, &r.res, "x", 0);
    const spare = bindingSpelled(&r.ast, &r.res, "spare", 0);
    try testing.expect(r.res.isReferenced(local));
    try testing.expect(!r.res.isReExport(local));
    try testing.expect(!r.res.bindsAFieldByItsOwnName(local));
    try testing.expectEqual(Reach.module, r.res.namingReachOf(local));
    try testing.expect(!r.res.isAmbient(local));

    try testing.expect(r.res.bindsAFieldByItsOwnName(field_binder));
    try testing.expect(!r.res.isReExport(field_binder));
    try testing.expectEqual(Reach.module, r.res.namingReachOf(field_binder));
    try testing.expect(!r.res.isAmbient(field_binder));
    try testing.expect(r.res.isReferenced(field_binder));

    try testing.expectEqual(Reach.public, r.res.namingReachOf(spare));
    try testing.expect(!r.res.isReExport(spare));
    try testing.expect(!r.res.bindsAFieldByItsOwnName(spare));
    try testing.expect(!r.res.isAmbient(spare));
    try testing.expect(!r.res.isReferenced(spare));

    const app_source: Source = .{ .path = "app/main.lin", .text =
        \\fn main() -> UInt8 { offered() + gift() }
    };
    const prelude_source: Source = .{ .path = "std/main.lin", .text =
        \\import inner
        \\pub use inner.gift
        \\pub fn offered() -> UInt8 { 1 }
    };
    const inner_source: Source = .{ .path = "std/inner/main.lin", .text =
        \\pub fn gift() -> UInt8 { 2 }
    };
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    var trees = Modules.init(arena.allocator(), &sink, &interner);
    const app_decls = try trees.add(&.{.{ .file = .from(0), .source = app_source }});
    const prelude_decls = try trees.add(&.{.{ .file = .from(1), .source = prelude_source }});
    const inner_decls = try trees.add(&.{.{ .file = .from(2), .source = inner_source }});
    const ast = try trees.finish();
    var prelude_imports = [_]program_mod.Import{.{
        .decl = DeclId.at(prelude_decls.start),
        .module = .from(2),
    }};
    var modules = [_]program_mod.Module{
        .{ .name = "app", .dir = "app", .files = &.{}, .decls = app_decls, .imports = &.{} },
        .{
            .name = "std",
            .dir = "std",
            .files = &.{},
            .decls = prelude_decls,
            .imports = &prelude_imports,
            .library = true,
        },
        .{
            .name = "inner",
            .dir = "std/inner",
            .files = &.{},
            .decls = inner_decls,
            .imports = &.{},
            .library = true,
        },
    };
    const program: Program = .{ .modules = &modules, .prelude = .from(1), .ast = ast };
    const before = sink.error_count;
    const module_result = try resolve(arena.allocator(), &program, &interner, &sink, .program);
    const module_res = module_result.resolution;
    try testing.expectEqual(@as(u32, 0), sink.error_count - before);
    inline for (.{ "reexported", "field_shorthand", "ambient", "referenced" }) |field| {
        try testing.expectEqual(@as(usize, module_res.bindingCount()), @field(module_res, field).len());
    }
    try testing.expectEqual(@as(usize, module_res.bindingCount()), module_res.reach.len);

    const offered = bindingSpelled(&ast, &module_res, "offered", 0);
    const gift = bindingSpelled(&ast, &module_res, "gift", 0);
    try testing.expect(!module_res.isReExport(offered));
    try testing.expect(!module_res.bindsAFieldByItsOwnName(offered));
    try testing.expectEqual(Reach.public, module_res.namingReachOf(offered));
    try testing.expect(module_res.isAmbient(offered));
    try testing.expect(module_res.isReferenced(offered));

    try testing.expect(module_res.isReExport(gift));
    try testing.expect(!module_res.bindsAFieldByItsOwnName(gift));
    try testing.expectEqual(Reach.public, module_res.namingReachOf(gift));
    try testing.expect(module_res.isAmbient(gift));
    try testing.expect(module_res.isReferenced(gift));

    const past_end = BindingId.at(r.res.bindingCount());
    try testing.expect(!r.res.isReferenced(.none));
    try testing.expect(!r.res.isReferenced(past_end));
    try testing.expect(!r.res.isReExport(.none));
    try testing.expect(!r.res.isReExport(past_end));
    try testing.expect(!r.res.bindsAFieldByItsOwnName(.none));
    try testing.expect(!r.res.bindsAFieldByItsOwnName(past_end));
    try testing.expect(!r.res.isAmbient(.none));
    try testing.expect(!r.res.isAmbient(past_end));
}

/// The first expression that reaches a binding.
fn firstNameReaching(ast: *const Ast, res: *const Resolution, b: BindingId) ExprId {
    for (0..ast.exprCount()) |i| {
        const e: ExprId = .at(@intCast(i));
        if (res.targetOf(e) == b) return e;
    }
    return ExprId.none;
}

fn holdsBinding(run: []const BindingId, b: BindingId) bool {
    return std.mem.indexOfScalar(BindingId, run, b) != null;
}

/// Where a binding sits in a run, or null where it is absent.
fn positionOf(run: []const BindingId, b: BindingId) ?usize {
    return std.mem.indexOfScalar(BindingId, run, b);
}

/// Whether a run holds the binding that names a primitive. A primitive is
/// declared by no token, so it is found by what it names.
fn holdsPrimitive(res: *const Resolution, run: []const BindingId, name: []const u8) bool {
    for (run) |b| {
        const t = res.builtinOf(b) orelse continue;
        if (std.mem.eql(u8, t.nameOf(), name)) return true;
    }
    return false;
}

/// The first binding in a run whose declaring token spells `name`, which is
/// where a walk of the run for that name would stop.
fn firstSpelled(ast: *const Ast, res: *const Resolution, run: []const BindingId, name: []const u8) ?BindingId {
    for (run) |b| {
        const tok = res.declaringToken(b);
        if (tok == TokenId.none) continue;
        if (std.mem.eql(u8, ast.tokenText(tok), name)) return b;
    }
    return null;
}

test "a name reaches an initialiser only where one was written" {
    // What folding reads about a name, over every kind a name can reach. A
    // parameter is the one a length is most likely to be written against, and
    // it holds no initialiser at all: what the caller passed is not something
    // the type it is written into can be settled by.
    const d = DeclId.at(3);
    const s = StmtId.at(5);
    for (std.enums.values(Kind)) |kind| {
        const site = reachOf(kind, d, s);
        switch (kind) {
            .constant => try testing.expectEqual(constfold.Reach{ .decl = d }, site),
            .local => try testing.expectEqual(constfold.Reach{ .stmt = s }, site),
            .parameter,
            .capture,
            .type_parameter,
            .function,
            .declared_type,
            .builtin_type,
            .trait,
            .module,
            .binder,
            .associated_type,
            .type_alias,
            => try testing.expectEqual(constfold.Reach.nothing, site),
        }
    }
}

test "a conversion is written on a primitive, and admits what it holds" {
    // The range a fold checks a conversion against, read from the one table
    // that says what a type holds -- so a width added there is admitted here
    // without the fold knowing what a type is.
    try testing.expectEqual(
        constfold.Range{ .min = 0, .max = 255 },
        conversionInto(.builtin_type, .u8).?,
    );
    try testing.expectEqual(
        constfold.Range{ .min = -128, .max = 127 },
        conversionInto(.builtin_type, .i8).?,
    );
    // `Bool` is a pair of names rather than a range, and a declared type is
    // not a conversion at all: neither heads one.
    try testing.expectEqual(@as(?constfold.Range, null), conversionInto(.builtin_type, .bool_));
    try testing.expectEqual(@as(?constfold.Range, null), conversionInto(.declared_type, .u8));
}

test "a reference resolves to its binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x = 4;
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    // The function is a symbol too, so one binding makes two -- after the nine
    // primitives, which are bindings in every program whether it names them or
    // not.
    try testing.expectEqual(@as(u32, TypeId.primitives.len + 2), r.res.bindingCount());
}

test "the later of two bindings wins" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // The first x is unused, so one diagnostic; the reference resolves to the
    // second, which is binding 1.
    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x = 1;
        \\    let x = 2;
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 1), r.errors);
    // Two bindings and the function they sit in, after the nine primitives.
    try testing.expectEqual(@as(u32, TypeId.primitives.len + 3), r.res.bindingCount());
}

test "an undefined name is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try resolveSource(arena.allocator(), "fn main() -> UInt8 { y }");
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "an unused binding is reported, and an underscore is not" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    try testing.expectEqual(@as(u32, 1), (try resolveSource(gpa, "fn main() -> UInt8 { let x = 1; 2 }")).errors);
    try testing.expectEqual(@as(u32, 0), (try resolveSource(gpa, "fn main() -> UInt8 { let _x = 1; 2 }")).errors);
    try testing.expectEqual(@as(u32, 0), (try resolveSource(gpa, "fn main() -> UInt8 { let _ = 1; 2 }")).errors);
}

test "a binding whose statement is already diagnosed is not reported unused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    try testing.expectEqual(@as(u32, 0), (try resolveSource(gpa, "fn main() -> UInt8 { let x = ; 2 }")).errors);
    try testing.expectEqual(@as(u32, 0), (try resolveSource(gpa, "fn main() -> UInt8 { let = 1; 2 }")).errors);
}

test "a name used before its binding is undefined" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Two errors: y is undefined at its use, and x is never used.
    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x = y;
        \\    let y = 1;
        \\    y
        \\}
    );
    try testing.expectEqual(@as(u32, 2), r.errors);
}

test "a resolved reference names the binding, not the statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "t.lin", .text = "fn main() -> UInt8 { let x = 4; x }" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    const res = try resolveTree(gpa, &ast, &sink);

    const tail = ast.blockOf(ast.declBody(DeclId.at(0))).tail;
    const target = res.resolution.targetOf(tail);
    try testing.expect(target != BindingId.none);
    // And the statement it came from is reachable.
    try testing.expect(res.resolution.stmtOf(target) != StmtId.none);
}

test "a block's bindings stop being visible where it ends" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Without a scope the trailing `x` finds the one declared inside the arm,
    // which reads the wrong storage rather than failing -- so the outer
    // binding is reported unused and the program answers 2 instead of 1.
    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1;
        \\    let _ = x;
        \\    if true {
        \\        let x: UInt8 = 2;
        \\        let _ = x;
        \\    }
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "a name after a block does not reach a binding declared inside it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `y` exists only within the arm, so the reference after it is undefined
    // and the binding itself is unused: two diagnostics.
    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    if true {
        \\        let y: UInt8 = 2;
        \\    }
        \\    y
        \\}
    );
    try testing.expectEqual(@as(u32, 2), r.errors);
}

test "assigning to a binding is not reading it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Written and never read, so [N-Unused] still applies.
    const assigned = try resolveSource(gpa,
        \\fn main() -> UInt8 {
        \\    var x: UInt8 = 1;
        \\    x = 2;
        \\    0
        \\}
    );
    try testing.expectEqual(@as(u32, 1), assigned.errors);

    // Read as well, so it is used.
    const read = try resolveSource(gpa,
        \\fn main() -> UInt8 {
        \\    var x: UInt8 = 1;
        \\    x = 2;
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), read.errors);
}

test "a type parameter is a declaration, and an unused one is an error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Named by a field, so used.
    const used = try resolveSource(gpa,
        \\struct Held[T] { x: T }
        \\fn main() -> UInt8 { let h: Held = .{ x = 1 }; h.x }
    );
    try testing.expectEqual(@as(u32, 0), used.errors);

    // Named by nothing.
    const unused = try resolveSource(gpa,
        \\struct Held[T] { x: UInt8 }
        \\fn main() -> UInt8 { let h: Held = .{ x = 1 }; h.x }
    );
    try testing.expect(unused.errors > 0);

    // Read for identity, and declared so. The underscore spelling asserted
    // deliberate disuse of a parameter the type system reads, and is refused
    // toward the truthful one.
    const declared = try resolveSource(gpa,
        \\struct Held[phantom T] { x: UInt8 }
        \\fn main() -> UInt8 { let h: Held = .{ x = 1 }; h.x }
    );
    try testing.expectEqual(@as(u32, 0), declared.errors);

    const underscored = try resolveSource(gpa,
        \\struct Held[_T] { x: UInt8 }
        \\fn main() -> UInt8 { let h: Held = .{ x = 1 }; h.x }
    );
    try testing.expect(underscored.errors > 0);

    // One declaration's `T` is not another's: naming it here does not answer
    // for the one next door.
    const separate = try resolveSource(gpa,
        \\struct A[T] { x: T }
        \\struct B[T] { y: UInt8 }
        \\fn main() -> UInt8 { let a: A = .{ x = 1 }; let b: B = .{ y = 2 }; a.x + b.y }
    );
    try testing.expect(separate.errors > 0);
}

test "a bound names a capability, or a trait that does not exist yet" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const known = try resolveSource(gpa,
        \\struct Held[T: Copyable] { x: T }
        \\fn main() -> UInt8 { let h: Held = .{ x = 1 }; h.x }
    );
    try testing.expectEqual(@as(u32, 0), known.errors);

    // Traits are a later stage, so every name that is not a capability is one
    // that does not exist -- which is exactly what it will be.
    const unknown = try resolveSource(gpa,
        \\struct Held[T: Weigh] { x: T }
        \\fn main() -> UInt8 { let h: Held = .{ x = 1 }; h.x }
    );
    try testing.expect(unknown.errors > 0);
}

test "an impl names a type the module declares" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Nothing resolved the header, so an `impl` on a name the module does not
    // declare attached its functions to nothing and said nothing about it. A
    // `pub` member among them is silent twice over: the unused rule exempts
    // what another module could have called, and no other module can reach
    // this one.
    const missing = try resolveSource(gpa,
        \\impl Missing { pub fn a() -> UInt8 { 1 } }
        \\fn main() -> UInt8 { 1 }
    );
    try testing.expect(missing.errors > 0);

    // Defined, but not a type. Its own rule: "undefined" would send a reader
    // looking for a declaration that is right there.
    const not_a_type = try resolveSource(gpa,
        \\fn helper() -> UInt8 { 1 }
        \\impl helper { pub fn a() -> UInt8 { 1 } }
        \\fn main() -> UInt8 { helper() }
    );
    try testing.expect(not_a_type.errors > 0);

    // And a type may have as many `impl` blocks as it likes.
    const several = try resolveSource(gpa,
        \\struct P { x: UInt8 }
        \\impl P { fn a(p: P) -> UInt8 { p.x } }
        \\impl P { fn b(p: P) -> UInt8 { p.x } }
        \\fn main() -> UInt8 { let p: P = .{ x = 1 }; P.a(p) + P.b(p) }
    );
    try testing.expectEqual(@as(u32, 0), several.errors);
}

test "an implementation does not take a variant's name away" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A variant is part of what an enum's name reaches, and an implementation
    // enters neither namespace. Looking for the implementation first made
    // adding one turn every reference to the variant it shadowed into an
    // undefined name.
    const r = try resolveSource(arena.allocator(),
        \\enum Colour { Red, Green }
        \\trait Measure { fn Red(c: Self) -> UInt8 }
        \\impl Measure for Colour {
        \\    fn Red(c: Self) -> UInt8 { match read c { Red => 4, Green => 3 } }
        \\}
        \\fn main() -> UInt8 { Measure.Red(Colour.Red) }
    );
    // The operation spelled like a variant is refused under [N-Case], and
    // that is the only error: the variant is still reached.
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "a trait is implemented once for a type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // What lets a bound and a call each take the first implementation they
    // find rather than search among candidates.
    const twice = try resolveSource(gpa,
        \\struct Account { balance: UInt8 }
        \\trait Measure { fn of(x: Self) -> UInt8 }
        \\impl Measure for Account { fn of(x: Account) -> UInt8 { x.balance } }
        \\impl Measure for Account { fn of(x: Account) -> UInt8 { x.balance } }
        \\fn main() -> UInt8 { let a: Account = .{ balance = 1 }; Measure.of(a) }
    );
    try testing.expect(twice.errors > 0);

    // Two traits are two implementations, however many names they share.
    const distinct = try resolveSource(gpa,
        \\struct Account { balance: UInt8 }
        \\trait Measure { fn of(x: Self) -> UInt8 }
        \\trait Weigh { fn of(x: Self) -> UInt8 }
        \\impl Measure for Account { fn of(x: Account) -> UInt8 { x.balance } }
        \\impl Weigh for Account { fn of(x: Account) -> UInt8 { x.balance } }
        \\fn main() -> UInt8 { let a: Account = .{ balance = 1 }; Measure.of(a) + Weigh.of(a) }
    );
    try testing.expectEqual(@as(u32, 0), distinct.errors);

    // And a type still takes as many inherent blocks as it likes, which is a
    // different question with the same shape.
    const inherent = try resolveSource(gpa,
        \\struct P { x: UInt8 }
        \\impl P { fn a(p: P) -> UInt8 { p.x } }
        \\impl P { fn b(p: P) -> UInt8 { p.x } }
        \\fn main() -> UInt8 { let p: P = .{ x = 1 }; P.a(p) + P.b(p) }
    );
    try testing.expectEqual(@as(u32, 0), inherent.errors);
}

test "an implementation the compiler provides is implemented once too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A primitive belongs to no module, so the module declaring the trait is
    // the one that may write the head -- and the compiler already implements
    // the comparison traits for every primitive. What is written there is a
    // second answer for one relationship, which is what coherence refuses.
    const again = try resolveWithLibraryModule(gpa,
        \\fn main() -> UInt8 { 1 }
    , "cmp",
        \\pub trait Equatable { fn equals(self: Self, other: Self) -> Bool }
        \\impl Equatable for Int64 {
        \\    fn equals(_a: Int64, _b: Int64) -> Bool { true }
        \\}
    );
    try testing.expectEqual(@as(u32, 1), again.duplicates);

    // A trait the compiler implements for nothing takes a primitive head from
    // its own module freely: the written implementation is the only answer.
    const alone = try resolveWithLibraryModule(gpa,
        \\fn main() -> UInt8 { 1 }
    , "cmp",
        \\pub trait Measure { fn of(self: Self) -> UInt8 }
        \\impl Measure for Int64 {
        \\    fn of(_a: Int64) -> UInt8 { 1 }
        \\}
    );
    try testing.expectEqual(@as(u32, 0), alone.errors);

    // The module is what finds it, not the spelling alone. The same trait under
    // the same name in a module the compiler does not look in seeds nothing, so
    // the written implementation is the only answer and coherence has nothing to
    // refuse -- which is also what a compilation with no library at all gets.
    const elsewhere = try resolveWithLibraryModule(gpa,
        \\fn main() -> UInt8 { 1 }
    , "elsewhere",
        \\pub trait Equatable { fn equals(self: Self, other: Self) -> Bool }
        \\impl Equatable for Int64 {
        \\    fn equals(_a: Int64, _b: Int64) -> Bool { true }
        \\}
    );
    try testing.expectEqual(@as(u32, 0), elsewhere.duplicates);
    try testing.expectEqual(@as(u32, 0), elsewhere.errors);
}

test "writing to an inout parameter uses it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A setter: the function's whole effect is the write, and the caller is
    // what observes it. Every corpus case for `inout` read the parameter as
    // well, so this shape was unwritable and nothing said so.
    const setter = try resolveSource(gpa,
        \\fn set(inout n: UInt8) {
        \\    n = 1;
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    var x: UInt8 = 0;
        \\    set(&x);
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), setter.errors);

    // Through a field, which is the same question: the binding is named to
    // reach a part of it, and the part is what the caller reads back.
    const field = try resolveSource(gpa,
        \\struct Point { x: UInt8, y: UInt8 }
        \\
        \\fn set(inout p: Point) {
        \\    p.x = 1;
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    var p: Point = .{ x = 0, y = 2 };
        \\    set(&p);
        \\    p.x + p.y
        \\}
    );
    try testing.expectEqual(@as(u32, 0), field.errors);

    // And a local is not a parameter: nothing outside the function can see
    // what was written, so the rule that made it unused still holds.
    const local = try resolveSource(gpa,
        \\struct Point { x: UInt8, y: UInt8 }
        \\
        \\fn main() -> UInt8 {
        \\    var p: Point = .{ x = 0, y = 2 };
        \\    p.x = 1;
        \\    3
        \\}
    );
    try testing.expectEqual(@as(u32, 1), local.errors);
}

test "only a var may be assigned" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const immutable = try resolveSource(gpa,
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1;
        \\    x = 2;
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 1), immutable.errors);

    const mutable = try resolveSource(gpa,
        \\fn main() -> UInt8 {
        \\    var x: UInt8 = 1;
        \\    x = 2;
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), mutable.errors);
}

test "an assignment reaches a binding declared outside the block" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Assignment resolves by the ordinary rule, so nothing special is needed
    // for it to name a binding from an enclosing scope.
    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    var x: UInt8 = 1;
        \\    if true {
        \\        x = 9;
        \\    }
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "a call resolves to a function declared later" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Phase one enters every declaration before any body is walked, so the
    // order of declarations does not matter.
    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 { later() }
        \\fn later() -> UInt8 { 1 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "mutual recursion resolves" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\fn ping(n: UInt8) -> UInt8 { pong(n) }
        \\fn pong(n: UInt8) -> UInt8 { ping(n) }
        \\fn main() -> UInt8 { ping(1) }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "a body cannot see another function's locals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Without cutting the chain back between functions, the backward search
    // runs past this function's own names into the previous one's.
    const r = try resolveSource(arena.allocator(),
        \\fn a() -> UInt8 { let hidden: UInt8 = 1; hidden }
        \\fn b() -> UInt8 { hidden }
        \\fn main() -> UInt8 { a() }
    );
    try testing.expect(r.errors > 0);
}

test "a parameter is visible in its body and nowhere else" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const visible = try resolveSource(gpa,
        \\fn f(a: UInt8) -> UInt8 { a }
        \\fn main() -> UInt8 { f(1) }
    );
    try testing.expectEqual(@as(u32, 0), visible.errors);

    const elsewhere = try resolveSource(gpa,
        \\fn f(_a: UInt8) -> UInt8 { 1 }
        \\fn main() -> UInt8 { a }
    );
    try testing.expect(elsewhere.errors > 0);
}

test "two declarations of one name are reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\fn f() -> UInt8 { 1 }
        \\fn f() -> UInt8 { 2 }
        \\fn main() -> UInt8 { f() }
    );
    try testing.expect(r.errors > 0);
}

test "a function nothing calls is unused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // ADR 0014 reaches declarations: a function is one.
    const spare = try resolveSource(gpa,
        \\fn spare() -> UInt8 { 1 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 1), spare.errors);

    // `main` is exempt because the runtime calls it, and a leading underscore
    // is exempt as it is everywhere else.
    const exempt = try resolveSource(gpa,
        \\fn _spare() -> UInt8 { 1 }
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), exempt.errors);
}

test "a program declares exactly one main" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const none = try resolveSource(gpa, "fn f() -> UInt8 { 1 }");
    try testing.expect(none.errors > 0);

    const two = try resolveSource(gpa,
        \\fn main() -> UInt8 { 1 }
        \\fn main() -> UInt8 { 2 }
    );
    try testing.expect(two.errors > 0);
}

test "a variant resolves through its enum" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\enum Colour { Red, Green }
        \\fn main() -> UInt8 { let _ = Colour.Red; 0 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "an enum declared later is still usable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Phase one enters types beside functions, so declaration order does not
    // matter for either.
    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 { let _ = Colour.Red; 0 }
        \\enum Colour { Red }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "a bare variant name does not resolve" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The enum is what gives the name meaning.
    const r = try resolveSource(arena.allocator(),
        \\enum Colour { Red }
        \\fn main() -> UInt8 { let _ = Red; 0 }
    );
    try testing.expect(r.errors > 0);
}

test "a name that is not a variant of that enum is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\enum Colour { Red }
        \\fn main() -> UInt8 { let _ = Colour.Blue; 0 }
    );
    try testing.expect(r.errors > 0);
}

test "an enum nothing uses is unused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(), "enum Spare { A }\nfn main() -> UInt8 { 0 }");
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "a binder is visible in its arm" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\fn main() -> UInt8 { match Shape.Square { Circle(n) => n, Square => 0 } }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "a binder is not visible in another arm" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The arm is the scope. A binder reaching the arm beside it would read a
    // payload the value it matched does not carry.
    const r = try resolveSource(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\fn main() -> UInt8 { match Shape.Square { Circle(n) => 0, Square => n } }
    );
    try testing.expect(r.errors > 0);
}

test "a binder is not visible after the match" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\fn main() -> UInt8 {
        \\    let _ = match Shape.Square { Circle(n) => n, Square => 0 };
        \\    n
        \\}
    );
    try testing.expect(r.errors > 0);
}

test "a binder nothing uses is unused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\fn main() -> UInt8 { match Shape.Square { Circle(n) => 1, Square => 0 } }
    );
    try testing.expectEqual(@as(u32, 1), r.errors);

    // A leading underscore says the payload is deliberately not wanted.
    const ok = try resolveSource(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\fn main() -> UInt8 { match Shape.Square { Circle(_n) => 1, Square => 0 } }
    );
    try testing.expectEqual(@as(u32, 0), ok.errors);
}

test "a binder shadows an outer name only inside its arm" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\fn main() -> UInt8 {
        \\    let n: UInt8 = 7;
        \\    let _ = match Shape.Square { Circle(n) => n, Square => 0 };
        \\    n
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "a type named only by an annotation is used" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Naming a type in an annotation is naming it. Without this the inferred
    // form is unreachable in practice: a program could not write `.Green`
    // without also writing `Colour.Green` somewhere to keep the enum used.
    const bound = try resolveSource(arena.allocator(),
        \\enum Colour { Red, Green }
        \\fn main() -> UInt8 { let c: Colour = .Green; match c { Red => 1, Green => 7 } }
    );
    try testing.expectEqual(@as(u32, 0), bound.errors);

    const param = try resolveSource(arena.allocator(),
        \\enum Colour { Red }
        \\fn look(c: Colour) -> UInt8 { match c { Red => 0 } }
        \\fn main() -> UInt8 { look(.Red) }
    );
    try testing.expectEqual(@as(u32, 0), param.errors);

    const returned = try resolveSource(arena.allocator(),
        \\enum Colour { Red }
        \\fn pick() -> Colour { .Red }
        \\fn main() -> UInt8 { match pick() { Red => 0 } }
    );
    try testing.expectEqual(@as(u32, 0), returned.errors);

    const carried = try resolveSource(arena.allocator(),
        \\enum Colour { Red }
        \\enum Shape { Circle(Colour) }
        \\fn main() -> UInt8 { match Shape.Circle(.Red) { Circle(c) => match c { Red => 0 } } }
    );
    try testing.expectEqual(@as(u32, 0), carried.errors);
}

test "a type no annotation and no expression names is unused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The rule still bites; an annotation is a use and there is none here.
    const r = try resolveSource(arena.allocator(), "enum Spare { A }\nfn main() -> UInt8 { 0 }");
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "a struct named only by an annotation is used" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Nothing can build one yet, so the only thing naming `Point` is what a
    // variant declares it carries. A third declaring form must not miss the
    // rule enums exposed.
    const r = try resolveSource(arena.allocator(),
        \\struct Point { x: UInt8 }
        \\enum Wrapper { Has(Point), None }
        \\fn main() -> UInt8 { match Wrapper.None { Has(_p) => 0, None => 1 } }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
}

test "a struct nothing names is unused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(), "struct Spare { x: UInt8 }\nfn main() -> UInt8 { 0 }");
    try testing.expectEqual(@as(u32, 1), r.errors);
}

test "a struct is not an enum, and has no variants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\struct Point { x: UInt8 }
        \\fn main() -> UInt8 { let _p = Point.x; 0 }
    );
    try testing.expect(r.errors > 0);
}

test "mutability is the binding's, whatever the path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Permission belongs to the name at the root, so a `let` refuses at any
    // depth. A field carrying its own permission is not a rule this language
    // has, so there is no second answer for this one to be weighed against.
    const refused = try resolveSource(arena.allocator(),
        \\struct Inner { y: UInt8 }
        \\struct Outer { inner: Inner }
        \\fn main() -> UInt8 {
        \\    let o: Outer = .{ inner = .{ y = 1 } };
        \\    o.inner.y = 7;
        \\    o.inner.y
        \\}
    );
    try testing.expectEqual(@as(u32, 1), refused.errors);

    const allowed = try resolveSource(arena.allocator(),
        \\struct Inner { y: UInt8 }
        \\struct Outer { inner: Inner }
        \\fn main() -> UInt8 {
        \\    var o: Outer = .{ inner = .{ y = 1 } };
        \\    o.inner.y = 7;
        \\    o.inner.y
        \\}
    );
    try testing.expectEqual(@as(u32, 0), allowed.errors);
}

fn resolveOnly(gpa: std.mem.Allocator, ctx: struct { ast: *const Ast, generated_count: ?usize = null }) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var res = try resolveTree(gpa, ctx.ast, &sink);
    defer res.deinit(gpa);
    if (ctx.generated_count) |expected| {
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        try testing.expectEqual(expected, res.expanded.generated_sources.buffers.len);
        for (res.expanded.generated_sources.buffers, 0..) |text, i| {
            const part = res.expanded.ast.parts[ctx.ast.parts.len + i];
            try testing.expectEqualStrings(text, part.source);
            try testing.expect(text.ptr == part.source.ptr);
            try testing.expect(res.expanded.generated_sources.path(i).ptr == part.path.ptr);
        }
    }
}

test "generated sources survive resolution and release partial expansion on allocation failure" {
    const gpa = testing.allocator;
    const source: Source = .{ .path = "linea-derive-0.lin", .text =
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\struct Mark { value: UInt8 }
        \\derive Structural for Mark
        \\fn main() -> UInt8 {
        \\    let mark: Mark = .{ value = 1 }
        \\    Structural.value(mark)
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
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    try testing.checkAllAllocationFailures(gpa, resolveOnly, .{.{ .ast = &ast, .generated_count = 1 }});
}

test "resolving that fails part-way gives back what it took" {
    // Every other test here asks what resolution owns when it succeeds. The
    // six tables it hands the caller are taken one at a time, and a failure at
    // any one of them left the ones before it holding memory nobody owns --
    // invisible to a test that never fails an allocation.
    const gpa = testing.allocator;
    const source: Source = .{ .path = "t.lin", .text =
        \\struct Cell[T] {
        \\    v: T,
        \\}
        \\
        \\enum Side {
        \\    left(UInt8),
        \\    right,
        \\}
        \\
        \\fn wrap[T: Copyable](x: T) -> Cell[T] {
        \\    .{ v = copy(x) }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1
        \\    let c = wrap(a)
        \\    var total: UInt8 = 0
        \\    var i: UInt8 = 0
        \\    while i < 4 {
        \\        total = total + c.v
        \\        i = i + 1
        \\    }
        \\    let s: Side = Side.left(2)
        \\    match s {
        \\        left(n) => total + n,
        \\        right => total,
        \\    }
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
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    try testing.checkAllAllocationFailures(gpa, resolveOnly, .{.{ .ast = &ast }});
}

test "a local is declared in the scope its statement sits in" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 4;
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const x = bindingSpelled(&r.ast, &r.res, "x", 0);
    const sc = r.res.scopeOfStmt(r.res.stmtOf(x));
    try testing.expect(sc != .none);
    try testing.expect(holdsBinding(r.res.declaredIn(sc), x));

    // The name and the declaration are in one scope, which is what a lookup
    // walking outwards from the name starts at.
    try testing.expectEqual(sc, r.res.scopeOfExpr(firstNameReaching(&r.ast, &r.res, x)));
}

test "a local declared in a nested block is in that block's scope and not the one outside it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    var i: UInt8 = 0;
        \\    while i < 4 {
        \\        let b: UInt8 = i;
        \\        i = i + b;
        \\    }
        \\    i
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const i = bindingSpelled(&r.ast, &r.res, "i", 0);
    const b = bindingSpelled(&r.ast, &r.res, "b", 0);
    const outer = r.res.scopeOfStmt(r.res.stmtOf(i));
    const inner = r.res.scopeOfStmt(r.res.stmtOf(b));

    try testing.expect(inner != outer);
    try testing.expectEqual(outer, r.res.parentScope(inner));
    try testing.expect(holdsBinding(r.res.declaredIn(inner), b));
    try testing.expect(!holdsBinding(r.res.declaredIn(inner), i));
    try testing.expect(holdsBinding(r.res.declaredIn(outer), i));

    // The block's own bindings and no others: a scope holds what was declared
    // in it, not what was declared inside it.
    try testing.expect(!holdsBinding(r.res.declaredIn(outer), b));
}

test "a shadowing local and the one it displaced sit in different scopes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1;
        \\    var i: UInt8 = 0;
        \\    while i < 1 {
        \\        let x: UInt8 = 2;
        \\        i = i + x;
        \\    }
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    // In declaration order, so which is which comes from the source and not
    // from the tree being asked about.
    const outer_x = bindingSpelled(&r.ast, &r.res, "x", 0);
    const inner_x = bindingSpelled(&r.ast, &r.res, "x", 1);

    const outer = r.res.scopeOfStmt(r.res.stmtOf(outer_x));
    const inner = r.res.scopeOfStmt(r.res.stmtOf(inner_x));
    try testing.expect(inner != outer);
    try testing.expect(holdsBinding(r.res.declaredIn(inner), inner_x));
    try testing.expect(!holdsBinding(r.res.declaredIn(inner), outer_x));
    try testing.expect(holdsBinding(r.res.declaredIn(outer), outer_x));

    // Each name is recorded where it was written, which is the scope that
    // decides which of the two it reaches.
    try testing.expectEqual(inner, r.res.scopeOfExpr(firstNameReaching(&r.ast, &r.res, inner_x)));
}

test "a parameter is declared in the scope the body's own scope sits below" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\fn f(p: UInt8) -> UInt8 {
        \\    p
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    f(1)
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const p = bindingSpelled(&r.ast, &r.res, "p", 0);
    const body = r.res.scopeOfExpr(firstNameReaching(&r.ast, &r.res, p));
    const params = r.res.parentScope(body);

    // The parameters are a scope of their own, so a local of the body's own
    // name shadows a parameter rather than colliding with it.
    try testing.expect(!holdsBinding(r.res.declaredIn(body), p));
    try testing.expect(holdsBinding(r.res.declaredIn(params), p));

    // And a scope of this function's own: the module's is above it, which is
    // what stops the parameter being one every function in the module sees.
    try testing.expect(r.res.parentScope(params) != .none);
}

test "a lambda expression names its parameter scope while its default stays outside" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let base: UInt8 = 3
        \\    let apply = |value: UInt8 = base| value
        \\    apply()
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    var lambda = ExprId.none;
    for (0..r.ast.exprCount()) |i| {
        const e: ExprId = .at(@intCast(i));
        if (r.ast.exprTag(e) == .lambda) {
            lambda = e;
            break;
        }
    }
    try testing.expect(lambda != .none);

    const parameter = bindingSpelled(&r.ast, &r.res, "value", 0);
    const parameter_scope = r.res.scopeOfExpr(lambda);
    try testing.expect(holdsBinding(r.res.declaredIn(parameter_scope), parameter));

    const outer = r.res.scopeOfExpr(firstNameReaching(
        &r.ast,
        &r.res,
        bindingSpelled(&r.ast, &r.res, "base", 0),
    ));
    try testing.expectEqual(outer, r.res.parentScope(parameter_scope));
}

test "a parameter of one function is not visible in another" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const r = try resolveSource(gpa,
        \\fn f(p: UInt8) -> UInt8 {
        \\    p
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let q: UInt8 = f(1);
        \\    q
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const p = bindingSpelled(&r.ast, &r.res, "p", 0);
    const q = bindingSpelled(&r.ast, &r.res, "q", 0);

    var out: std.ArrayList(BindingId) = .empty;
    try r.res.visibleAt(gpa, r.res.stmtOf(q), &out);

    // What the module declares is shared; what a body declares is not. A
    // parameter placed above the scope that declared it would be visible
    // here, and every name would still reach what it reached.
    try testing.expect(holdsBinding(out.items, bindingSpelled(&r.ast, &r.res, "f", 0)));
    try testing.expect(!holdsBinding(out.items, p));
}

test "a binder is declared in its arm's scope and not in the arm beside it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square(UInt8) }
        \\
        \\fn main() -> UInt8 {
        \\    match Shape.Square(1) { Circle(n) => n, Square(m) => m }
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const n = bindingSpelled(&r.ast, &r.res, "n", 0);
    const m = bindingSpelled(&r.ast, &r.res, "m", 0);
    const first = r.res.scopeOfExpr(firstNameReaching(&r.ast, &r.res, n));
    const second = r.res.scopeOfExpr(firstNameReaching(&r.ast, &r.res, m));

    try testing.expect(first != second);
    try testing.expectEqual(r.res.parentScope(first), r.res.parentScope(second));
    try testing.expect(holdsBinding(r.res.declaredIn(first), n));
    try testing.expect(!holdsBinding(r.res.declaredIn(first), m));
    try testing.expect(holdsBinding(r.res.declaredIn(second), m));
}

test "the scope a name sits in is reached from the module's own declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const r = try resolveSource(arena.allocator(),
        \\fn f(p: UInt8) -> UInt8 {
        \\    p
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    f(1)
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const p = bindingSpelled(&r.ast, &r.res, "p", 0);
    var sc = r.res.scopeOfExpr(firstNameReaching(&r.ast, &r.res, p));
    var depth: usize = 0;
    while (r.res.parentScope(sc) != .none) : (depth += 1) {
        sc = r.res.parentScope(sc);
        try testing.expect(depth < r.res.scopeCount());
    }

    // The root of every chain is what the module declares, which is where a
    // name no scope below carries is found.
    try testing.expect(holdsBinding(r.res.declaredIn(sc), bindingSpelled(&r.ast, &r.res, "f", 0)));
    try testing.expect(holdsBinding(r.res.declaredIn(sc), bindingSpelled(&r.ast, &r.res, "main", 0)));
}

test "what is visible at a statement holds the innermost binding of a shadowed name first" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const r = try resolveSource(gpa,
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1;
        \\    var i: UInt8 = 0;
        \\    while i < 1 {
        \\        let x: UInt8 = 2;
        \\        i = i + x;
        \\    }
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const outer_x = bindingSpelled(&r.ast, &r.res, "x", 0);
    const inner_x = bindingSpelled(&r.ast, &r.res, "x", 1);

    var out: std.ArrayList(BindingId) = .empty;
    try r.res.visibleAt(gpa, r.res.stmtOf(inner_x), &out);

    // Both are visible inside the block, and the block's own is the first of
    // them: between scopes the answer is innermost first, so a walk that stops
    // at the first entry carrying a name stops where the chain did.
    try testing.expectEqual(inner_x, firstSpelled(&r.ast, &r.res, out.items, "x").?);
    try testing.expect(positionOf(out.items, inner_x).? < positionOf(out.items, outer_x).?);
}

test "a scope declaring one name twice makes both visible, the later one first" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const r = try resolveSource(gpa,
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1
        \\    let x: UInt8 = x + 1
        \\    x
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const first_x = bindingSpelled(&r.ast, &r.res, "x", 0);
    const second_x = bindingSpelled(&r.ast, &r.res, "x", 1);

    // One scope, because a redeclaration opens none: both runs are the same
    // run, and the tree records that a scope declared them and not where.
    const sc = r.res.scopeOfStmt(r.res.stmtOf(second_x));
    try testing.expectEqual(sc, r.res.scopeOfStmt(r.res.stmtOf(first_x)));
    try testing.expect(holdsBinding(r.res.declaredIn(sc), first_x));
    try testing.expect(holdsBinding(r.res.declaredIn(sc), second_x));

    // The `x` the second statement reads is the first, which is what the
    // program computes and what the resolver settled.
    const reads = firstNameReaching(&r.ast, &r.res, first_x);
    try testing.expectEqual(sc, r.res.scopeOfExpr(reads));
    try testing.expectEqual(first_x, r.res.targetOf(reads));

    var out: std.ArrayList(BindingId) = .empty;
    try r.res.visibleAt(gpa, r.res.stmtOf(second_x), &out);

    // Both are in scope there, later first -- so within one scope the leading
    // entry for a name is the last declaration of it and not what a name
    // written before that declaration reached. What a written name reached is
    // `targetOf`; this says what is in scope.
    try testing.expect(positionOf(out.items, second_x).? < positionOf(out.items, first_x).?);
    try testing.expectEqual(second_x, firstSpelled(&r.ast, &r.res, out.items, "x").?);
}

test "resolution retains both closure identity directions" {
    var builder = try ClosureMap.Builder.init(testing.allocator, 8);
    defer builder.deinit();

    const first = try builder.add(ExprId.at(7));
    const second = try builder.add(ExprId.at(3));
    var closures = try builder.finish();
    defer closures.deinit(testing.allocator);

    try testing.expectEqual(ClosureId.at(0), first);
    try testing.expectEqual(ClosureId.at(1), second);
    try testing.expectEqual(first, closures.closureOf(ExprId.at(7)));
    try testing.expectEqual(second, closures.closureOf(ExprId.at(3)));
    try testing.expectEqual(ExprId.at(7), closures.exprOf(first));
    try testing.expectEqual(ExprId.at(3), closures.exprOf(second));
    try testing.expectEqual(ClosureId.none, closures.closureOf(ExprId.at(6)));
}

test "what is visible in one arm does not hold the binder of the arm beside it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const r = try resolveSource(gpa,
        \\enum Shape { Circle(UInt8), Square(UInt8) }
        \\
        \\fn main() -> UInt8 {
        \\    match Shape.Square(1) {
        \\        Circle(n) => { let a: UInt8 = n; a },
        \\        Square(m) => { let b: UInt8 = m; b },
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const a = bindingSpelled(&r.ast, &r.res, "a", 0);
    const n = bindingSpelled(&r.ast, &r.res, "n", 0);
    const m = bindingSpelled(&r.ast, &r.res, "m", 0);

    var out: std.ArrayList(BindingId) = .empty;
    try r.res.visibleAt(gpa, r.res.stmtOf(a), &out);

    try testing.expect(holdsBinding(out.items, n));
    try testing.expect(!holdsBinding(out.items, m));
}

test "what is visible at a statement holds its own locals, then the parameter, then what the module declares" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const r = try resolveSource(gpa,
        \\fn f(p: UInt8) -> UInt8 {
        \\    let q: UInt8 = p;
        \\    q
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    f(1)
        \\}
    );
    try testing.expectEqual(@as(u32, 0), r.errors);

    const p = bindingSpelled(&r.ast, &r.res, "p", 0);
    const q = bindingSpelled(&r.ast, &r.res, "q", 0);
    const f = bindingSpelled(&r.ast, &r.res, "f", 0);

    var out: std.ArrayList(BindingId) = .empty;
    try r.res.visibleAt(gpa, r.res.stmtOf(q), &out);

    // Outwards: the block, the parameters, then the module's own run -- which
    // holds what it declares and the primitives every module opens with.
    try testing.expect(positionOf(out.items, q).? < positionOf(out.items, p).?);
    try testing.expect(positionOf(out.items, p).? < positionOf(out.items, f).?);
    try testing.expect(holdsBinding(out.items, bindingSpelled(&r.ast, &r.res, "main", 0)));
    try testing.expect(holdsPrimitive(&r.res, out.items, "UInt8"));
}

test "a test is named by the module it sits in, beneath the root" {
    // A module is a directory, so a test's identity is that directory's path
    // beneath the program root, dot-separated, with its own name last. The root
    // contributes nothing: a test written there is known by its bare name,
    // which is what a program of one file has.
    //
    // Not the emitted symbol, which is mangled and carries type arguments. This
    // is the name a reader copies out of a transcript and back onto a command
    // line, so it is spelled once and read by the dispatcher, the runner and
    // the transcript alike.
    const gpa = testing.allocator;

    const bare = try qualifiedTestName(gpa, "/p", "/p", "a_thing_holds");
    defer gpa.free(bare);
    try testing.expectEqualStrings("a_thing_holds", bare);

    const under = try qualifiedTestName(gpa, "/p", "/p/deep", "a_thing_holds");
    defer gpa.free(under);
    try testing.expectEqualStrings("deep.a_thing_holds", under);

    const nested = try qualifiedTestName(gpa, "/p", "/p/text/str", "a_thing_holds");
    defer gpa.free(nested);
    try testing.expectEqualStrings("text.str.a_thing_holds", nested);

    // A `.` in one directory's name is not the separator between two.
    const dotted = try qualifiedTestName(gpa, "/p", "/p/a.b", "a_thing_holds");
    defer gpa.free(dotted);
    try testing.expectEqualStrings("a\\.b.a_thing_holds", dotted);

    const slashed = try qualifiedTestName(gpa, "/p", "/p/a\\b", "a_thing_holds");
    defer gpa.free(slashed);
    try testing.expectEqualStrings("a\\\\b.a_thing_holds", slashed);

    // A root written with a trailing separator names the same module as one
    // without, so neither may leave an empty component in front of the name.
    const trailing = try qualifiedTestName(gpa, "/p/", "/p/deep", "a_thing_holds");
    defer gpa.free(trailing);
    try testing.expectEqualStrings("deep.a_thing_holds", trailing);

    // A sibling whose name merely begins with the root's is not beneath it, so
    // it contributes no component at all.
    const sibling = try qualifiedTestName(gpa, "/p", "/paranoid", "a_thing_holds");
    defer gpa.free(sibling);
    try testing.expectEqualStrings("a_thing_holds", sibling);
}

test "a traversal receiver is bound only in its initializer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try resolveSource(arena.allocator(),
        \\struct Grid { len: UInt64 }
        \\impl Grid {
        \\    trav positions(self: Self) = UInt64(0)..self.len
        \\}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    const receiver = bindingSpelled(&r.ast, &r.res, "self", 0);
    try testing.expectEqual(Kind.parameter, r.res.kindOf(receiver));
    const owner = r.res.parameterOwner(receiver).declaration;
    try testing.expectEqual(node.Decl.Tag.traversal_, r.ast.declTag(owner));
    try testing.expectEqual(receiver, r.res.parametersOf(owner)[0]);
    try testing.expect(firstNameReaching(&r.ast, &r.res, receiver) != .none);
}

test "phantom parameters cannot occur through nested field arguments" {
    const cases = [_][]const u8{
        \\struct Buffer[phantom A] { at: UInt64 }
        \\struct _Storage[phantom A] { buffer: Buffer[A] }
        \\fn main() -> UInt8 { 0 }
        ,
        \\struct Storage[phantom T] { at: UInt64 }
        \\struct _Vec[phantom T] { storage: Storage[T] }
        \\fn main() -> UInt8 { 0 }
        ,
    };
    for (cases) |text| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const result = try resolveSource(arena.allocator(), text);
        try testing.expectEqual(@as(u32, 1), result.errors);
    }
}

test "borrow written callable identity includes source effects and result targets" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\struct Data { number: UInt8 }
        \\fn compare(_a: fn(read x: Data) -> Data where carries(x), _b: fn(read x: Data) -> Data where carries(), _c: fn(read x: Data) -> Data where carries(.number: x)) -> UInt8 { 0 }
        \\fn main() -> UInt8 { 0 }
    );
    const ast = &result.ast;
    const params = ast.declParams(DeclId.at(1));
    try testing.expectEqual(@as(usize, 3), params.len);
    for (params[1..]) |other| {
        const unfolded: constfold.Memo = .empty;
        const settled: SettledWritten = .{ .ast = ast, .res = &result.res, .memo = &unfolded };
        try testing.expect(!try sameWrittenType(ast, settled, params[0].written, .{}, other.written, .{}));
        var first_hash = std.hash.Wyhash.init(0);
        var other_hash = std.hash.Wyhash.init(0);
        var left: usize = hashed_node_budget;
        try hashType(ast, settled, &first_hash, params[0].written, .{}, &left);
        left = hashed_node_budget;
        try hashType(ast, settled, &other_hash, other.written, .{}, &left);
        try testing.expect(first_hash.final() != other_hash.final());
    }
}

test "phantom identity parameters are independent of machine word width" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try resolveSource(arena.allocator(),
        \\struct _Brand[phantom T0, phantom T1, phantom T2, phantom T3, phantom T4, phantom T5, phantom T6, phantom T7, phantom T8, phantom T9, phantom T10, phantom T11, phantom T12, phantom T13, phantom T14, phantom T15, phantom T16, phantom T17, phantom T18, phantom T19, phantom T20, phantom T21, phantom T22, phantom T23, phantom T24, phantom T25, phantom T26, phantom T27, phantom T28, phantom T29, phantom T30, phantom T31, phantom T32] {}
        \\fn main() -> UInt8 { 0 }
    );
    try testing.expectEqual(@as(u32, 0), result.errors);
}

test "integer parameter namespaces share signature references and lexical visibility" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const r = try resolveSource(gpa,
        \\fn convert[T: Integer](value: T) -> T { T(value) }
        \\fn main() -> UInt8 { convert(UInt8(1)) }
    );
    try testing.expectEqual(@as(u32, 0), r.errors);
    const parameter = bindingSpelled(&r.ast, &r.res, "T", 0);
    try testing.expect(parameter != .none);
    const expression = firstNameReaching(&r.ast, &r.res, parameter);
    try testing.expect(expression != .none);
    var visible: std.ArrayList(BindingId) = .empty;
    try r.res.visibleIn(gpa, r.res.scopeOfExpr(expression), &visible);
    try testing.expect(holdsBinding(visible.items, parameter));
    var references: usize = 0;
    for (r.res.written) |binding| {
        if (binding == parameter) references += 1;
    }
    try testing.expectEqual(@as(usize, 2), references);
}

test "integer parameter namespaces retain enclosing owners and local shadowing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const r = try resolveSource(gpa,
        \\struct Box[T] { value: T }
        \\impl[T: Integer] Box[T] {
        \\    fn make[U: Integer](value: U) -> T { T(value) }
        \\}
        \\fn shadow[T: Integer](value: T) -> UInt8 {
        \\    let T = UInt8(1)
        \\    let _value: T = value
        \\    T
        \\}
        \\fn main() -> UInt8 { shadow(Box.make(UInt8(1))) }
    );
    // The local spelled like a type parameter is refused under [N-Case], and
    // that is the only error: each use still reaches the name it means.
    try testing.expectEqual(@as(u32, 1), r.errors);
    var visible: std.ArrayList(BindingId) = .empty;
    var namespace_uses: usize = 0;
    var local_uses: usize = 0;
    for (0..r.ast.exprCount()) |i| {
        const expression = ExprId.at(@intCast(i));
        if (r.ast.exprTag(expression) != .name_ref) continue;
        if (!std.mem.eql(u8, r.ast.tokenText(r.ast.exprMain(expression)), "T")) continue;
        const binding = r.res.targets[expression.index()];
        try r.res.visibleIn(gpa, r.res.scopeOfExpr(expression), &visible);
        try testing.expect(holdsBinding(visible.items, binding));
        switch (r.res.kinds[binding.index()]) {
            .type_parameter => namespace_uses += 1,
            .local => local_uses += 1,
            else => return error.TestUnexpectedResult,
        }
    }
    try testing.expectEqual(@as(usize, 1), namespace_uses);
    try testing.expectEqual(@as(usize, 1), local_uses);
}

test "integer parameter namespaces stay local to template declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    try resolveTestText(arena.allocator(), "main.lin",
        \\trait Convert {
        \\    fn value[U: Integer](self: Self, value: U) -> U
        \\}
        \\template impl Convert {
        \\    fn value[U: Integer](_self: Self, value: U) -> U { U(value) }
        \\}
        \\fn main() -> UInt8 { 0 }
    , &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
}

test "namespace mutation diagnostics describe immutable type namespaces" {
    const cases = [_]struct { source: []const u8, message: []const u8, labels: usize }{
        .{ .source = "fn main() -> UInt8 { UInt8.max = 0; 0 }", .message = "type namespace `UInt8` cannot be mutated", .labels = 1 },
        .{ .source = "fn _change[T: Integer](_value: T) { T.max = T(0) }\nfn main() -> UInt8 { 0 }", .message = "type namespace `T` cannot be mutated", .labels = 1 },
        .{ .source = "fn main() -> UInt8 { let value: UInt8 = 1; value = 0; value }", .message = "`value` is declared with `let`", .labels = 2 },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "namespace.lin", .text = case.source };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        _ = try resolveTree(gpa, &ast, &sink);
        try testing.expectEqual(@as(u32, 1), sink.error_count);
        try testing.expectEqual(@as(usize, 1), diagnosticCodeCount(&sink, .n_immutable));
        for (sink.items()) |diagnostic| {
            if (diagnostic.code != .n_immutable) continue;
            try testing.expectEqualStrings(case.message, diagnostic.message);
            try testing.expectEqual(case.labels, diagnostic.labels.len);
        }
    }
}

test "dereferenced assignment places resolve their observation as a read" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const resolved = try resolveSource(gpa,
        \\struct Entry { value: UInt8 }
        \\fn change(inout number: UInt8) { number = 1 }
        \\fn observe(entry: Entry) -> borrow Entry where borrows(entry) { borrow entry }
        \\fn main() -> UInt8 {
        \\    let entry: Entry = .{ value = 7 }
        \\    let view = borrow entry;
        \\    *view = entry;
        \\    *observe(entry) = entry;
        \\    (*view).value = 9;
        \\    (*view).value += 1;
        \\    change(&(*view).value)
        \\    entry.value
        \\}
    );
    try testing.expectEqual(@as(u32, 0), resolved.errors);
}

test "inout invocation requires writable callable storage" {
    const cases = [_]struct { source: []const u8, errors: u32 }{
        .{ .source = "fn main() -> UInt8 { let callback = [] || UInt8(0); &callback() }", .errors = 1 },
        .{ .source = "fn apply(callback: fn() -> UInt8) -> UInt8 { &callback() }\nfn main() -> UInt8 { let callback = [] || UInt8(0); apply(callback) }", .errors = 1 },
        .{ .source = "fn main() -> UInt8 { var callback = [] || UInt8(0); &callback() }", .errors = 0 },
        .{ .source = "fn apply(inout callback: fn() -> UInt8) -> UInt8 { &callback() }\nfn main() -> UInt8 { var callback = [] || UInt8(0); apply(&callback) }", .errors = 0 },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "t.lin", .text = case.source };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        _ = try resolveTree(gpa, &ast, &sink);
        if (sink.error_count != case.errors) {
            std.debug.print("invocation source: {s}\n", .{case.source});
            for (sink.items()) |diagnostic| std.debug.print("{any}: {s}\n", .{ diagnostic.code, diagnostic.message });
        }
        try testing.expectEqual(case.errors, sink.error_count);
        if (std.mem.startsWith(u8, case.source, "fn apply(callback:")) {
            try testing.expectEqualStrings("`callback` is a read-only parameter", sink.items()[0].message);
            try testing.expectEqualStrings("read-only parameter declared here", sink.items()[0].labels[0].message);
        }
    }
}

test "redundant read parameters reject written defaults and preserve callable type syntax" {
    const cases = [_]struct { source: []const u8, errors: u32 }{
        .{ .source = "fn identity(read value: UInt8) -> UInt8 { value }\nfn main() -> UInt8 { identity(0) }", .errors = 1 },
        .{ .source = "fn main() -> UInt8 { let identity = |read value: UInt8| value; identity(0) }", .errors = 1 },
        .{ .source = "fn identity(read // convention comment\n value: UInt8 = 0) -> UInt8 { value }\nfn main() -> UInt8 { identity() }", .errors = 1 },
        .{ .source = "trait Readable { fn get(read self: Self) -> UInt8 }\nstruct Value {}\nimpl Readable for Value { fn get(_self: Self) -> UInt8 { 0 } }\nfn main() -> UInt8 { let value: Value = .{}; Readable.get(value) }", .errors = 1 },
        .{ .source = "fn apply(callback: fn(read value: UInt8) -> UInt8) -> UInt8 { callback(0) }\nfn main() -> UInt8 { apply(|value: UInt8| value) }", .errors = 0 },
        .{ .source = "fn main() -> UInt8 { let source: UInt8 = 0; let callback = read [read source] |value: UInt8| source + value; callback(0) }", .errors = 0 },
        .{ .source = "fn consume(sink taken: UInt8, inout changed: UInt8) -> UInt8 { changed += 1; taken + changed }\nfn main() -> UInt8 { var changed: UInt8 = 0; consume(0, &changed) }", .errors = 0 },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const source: Source = .{ .path = "t.lin", .text = case.source };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        _ = try resolveTree(gpa, &ast, &sink);
        if (sink.error_count != case.errors) {
            std.debug.print("redundant-read source: {s}\n", .{case.source});
            for (sink.items()) |diagnostic| std.debug.print("{any}: {s}\n", .{ diagnostic.code, diagnostic.message });
        }
        try testing.expectEqual(case.errors, sink.error_count);
        for (sink.items()) |diagnostic| {
            try testing.expectEqual(.s_entry, diagnostic.code.?);
            try testing.expectEqualStrings("read", diagnostic.labels[0].span.slice(case.source));
        }
    }
}

test "duplicate closure bindings retain the first resolved target" {
    const cases = [_][]const u8{
        "fn main() -> UInt8 { let callback = [value = 1, value = 2] || value; callback() }",
        "fn main() -> UInt8 { let callback = [value = 1] |value: UInt8| value; callback(2) }",
        "fn main() -> UInt8 { let callback = |value: UInt8, value: UInt8| value; callback(1, 2) }",
    };
    for (cases) |text| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: Source = .{ .path = "t.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        const tree = try resolveTree(gpa, &ast, &sink);
        const res = &tree.resolution;
        try testing.expectEqual(@as(usize, 1), diagnosticCodeCount(&sink, .n_duplicate));
        const first = bindingSpelled(&ast, res, "value", 0);
        const rejected = bindingSpelled(&ast, res, "value", 1);
        try testing.expect(first != .none);
        try testing.expect(rejected != .none);
        try testing.expect(first != rejected);
        var bodies: usize = 0;
        for (0..ast.exprCount()) |i| {
            const expression = ExprId.at(@intCast(i));
            if (ast.exprTag(expression) != .lambda) continue;
            const body = ast.lambda(expression).body;
            try testing.expectEqual(.name_ref, ast.exprTag(body));
            try testing.expectEqual(first, res.targetOf(body));
            bodies += 1;
        }
        try testing.expectEqual(@as(usize, 1), bodies);
        try testing.expect(res.isReferenced(first));
        try testing.expect(!res.isReferenced(rejected));
    }
}

test "library resolution prefix retains private binding and scope state" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{
        .path = "std/prefix.lin",
        .text = "pub fn identity(value: UInt8) -> UInt8 { let forwarded = value; forwarded }",
    };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var modules = [_]program_mod.Module{.{
        .name = "std",
        .dir = "std",
        .files = &.{.from(0)},
        .decls = .{ .start = 0, .end = ast.declCount() },
        .imports = &.{},
        .library = true,
    }};
    const program: Program = .{ .ast = ast, .modules = &modules, .kind = .library };
    var prefix = try resolveLibraryPrefix(testing.allocator, &program, &interner, &sink);
    defer prefix.deinit();
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    const res = &prefix.result.resolution;
    try testing.expectEqual(res.kinds.len, prefix.seed.bindings.len);
    var local_count: usize = 0;
    for (prefix.seed.bindings, 0..) |binding, i| {
        try testing.expectEqual(res.kinds[i], binding.kind);
        try testing.expectEqual(res.decls[i], binding.decl);
        try testing.expectEqual(res.tokens[i], binding.at);
        try testing.expectEqual(res.isReferenced(BindingId.at(@intCast(i))), binding.used);
        if (binding.stmt != .none) {
            local_count += 1;
            try testing.expect(binding.used);
            try testing.expect(!binding.exempt);
        }
    }
    try testing.expectEqual(@as(usize, 1), local_count);
    try testing.expectEqual(prefix.seed.scope_bindings.len, prefix.seed.binding_scopes.len);
    for (prefix.seed.scope_bindings, prefix.seed.binding_scopes) |binding, scope| {
        const run = res.scopes[scope.index()];
        try testing.expect(std.mem.indexOfScalar(BindingId, res.scope_bindings[run.from..run.to], binding) != null);
    }
}

test "library resolution continuation preserves bindings and diagnoses application names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    for ([_][]const u8{
        "pub fn identity(value: UInt8) -> UInt8 { value }",
        "pub struct Box {} impl Box { fn touch(_self: Self) -> UInt8 { 0 } } pub fn identity(value: UInt8) -> UInt8 { let box: Box = .{}; let _ = box.touch(); value }",
        "pub trait Marker { fn mark(self: Self) -> UInt8 } template impl Marker { fn mark(_self: Self) -> UInt8 { 0 } } pub struct Stamp {} derive Marker for Stamp\npub fn identity(value: UInt8) -> UInt8 { let callback = [held = value] || held; callback() }",
    }) |library_text| {
        var sink = Sink.init(gpa);
        var names: Interner = .empty;
        const source: Source = .{ .path = "std/prefix.lin", .text = library_text };
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
        const ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var library_modules = [_]program_mod.Module{.{
            .name = "std",
            .dir = "std",
            .files = &.{.from(0)},
            .decls = .{ .start = 0, .end = ast.declCount() },
            .imports = &.{},
            .library = true,
            .root = .from(1),
        }};
        const library: Program = .{ .modules = &library_modules, .ast = ast, .kind = .library, .prelude = .from(0) };
        var prefix = try resolveLibraryPrefix(testing.allocator, &library, &names, &sink);
        defer prefix.deinit();
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        for ([_]struct { text: []const u8, reusable: bool }{
            .{ .text = "fn main() -> UInt8 { identity(0) }", .reusable = true },
            .{ .text = "fn main() -> UInt8 { absent(0) }", .reusable = true },
            .{ .text = "fn main() -> UInt8 { let callback = || UInt8(0); callback() }", .reusable = false },
            .{ .text = "fn main() -> UInt8 { let value: UInt8 = 0; let callback = [held = value] || held; callback() }", .reusable = false },
            .{ .text = "struct Other {} impl Other { fn touch(_self: Self) -> UInt8 { 0 } } fn main() -> UInt8 { let _other: Other = .{}; identity(0) }", .reusable = true },
            .{ .text = "fn main() -> UInt8 { let _linea_trait_0 = 0; identity(0) }", .reusable = false },
            .{ .text = "trait Local {} template impl Local {} struct Thing {} derive Local for Thing\nfn main() -> UInt8 { let _thing: Thing = .{}; identity(0) }", .reusable = false },
        }) |fixture| {
            var app_names = try Interner.initPrefix(gpa, &prefix.interner);
            var app_sink = Sink.init(gpa);
            var parser = try Modules.initPrefix(gpa, &app_sink, &app_names, &ast);
            const app_decls = try parser.add(&.{.{ .file = .from(1), .source = .{ .path = "main.lin", .text = fixture.text } }});
            var modules = [_]program_mod.Module{ library_modules[0], .{
                .name = "app",
                .dir = "app",
                .files = &.{.from(1)},
                .decls = app_decls,
                .imports = &.{},
            } };
            const program: Program = .{ .modules = &modules, .ast = try parser.finish(), .primary = .from(1), .prelude = .from(0) };
            try testing.expectEqual(@as(u32, 0), app_sink.error_count);
            try testing.expectEqual(fixture.reusable, prefix.canResume(&program, &app_names));
            const continued = try resolveWithPrefix(gpa, &program, &app_names, &app_sink, .program, &prefix);
            var fresh_sink = Sink.init(gpa);
            const fresh = try resolve(gpa, &program, &app_names, &fresh_sink, .program);
            try testing.expectEqual(fresh_sink.error_count, app_sink.error_count);
            try testing.expectEqual(fresh_sink.items().len, app_sink.items().len);
            for (fresh_sink.items(), app_sink.items()) |a, b| {
                try testing.expectEqual(a.code, b.code);
                try testing.expectEqualStrings(a.message, b.message);
            }
            const a = &continued.resolution;
            const b = &fresh.resolution;
            const relocation: Relocation = .{ .source = .of(&ast), .destination = .of(&program.ast) };
            if (fixture.reusable) for (prefix.result.resolution.targets, 0..) |target, i| {
                try testing.expectEqual(target, a.targets[relocation.id(ExprId, @enumFromInt(i)).index()]);
            };
            for (a.targets, b.targets) |actual, expected| {
                try testing.expectEqual(actual == .none, expected == .none);
                if (actual == .none) continue;
                try testing.expectEqual(b.kinds[expected.index()], a.kinds[actual.index()]);
                try testing.expectEqual(b.decls[expected.index()], a.decls[actual.index()]);
                try testing.expectEqual(b.tokens[expected.index()], a.tokens[actual.index()]);
            }

            // The inherent heads ride the prefix, so a type the library
            // declares chains the same members under it whether the
            // resolution was continued or fresh: `Box.touch` from the
            // library, `Other.touch` from the application.
            var chained: usize = 0;
            for (0..program.ast.declCount()) |i| {
                const d = DeclId.at(@intCast(i));
                var continued_members = a.membersOfType(d);
                var fresh_members = b.membersOfType(d);
                while (fresh_members.next()) |expected| {
                    const actual = continued_members.next() orelse return error.TestUnexpectedResult;
                    try testing.expectEqual(b.declaredBy(expected), a.declaredBy(actual));
                    try testing.expectEqual(b.tokens[expected.index()], a.tokens[actual.index()]);
                    chained += 1;
                }
                try testing.expectEqual(@as(?BindingId, null), continued_members.next());
            }
            const library_rows: usize = if (std.mem.indexOf(u8, library_text, "impl Box") != null) 1 else 0;
            const application_rows: usize = if (std.mem.indexOf(u8, fixture.text, "impl Other") != null) 1 else 0;
            try testing.expectEqual(library_rows + application_rows, chained);

            // The trait index is read off the whole program's type names in
            // both, so a library trait's members are indexed for every module
            // that names it whether the resolution was continued or fresh:
            // `Marker.mark` under the library's row and the application's.
            try testing.expectEqualSlices(DeclId, b.traits, a.traits);
            var marks: usize = 0;
            for (0..program.modules.len) |mi| {
                const m: ModuleId = .from(mi);
                var continued_seen = a.traitsSeenBy(m);
                var fresh_seen = b.traitsSeenBy(m);
                while (fresh_seen.next()) |expected| try testing.expectEqual(expected, continued_seen.next());
                try testing.expectEqual(@as(?DeclId, null), continued_seen.next());
                for (0..program.ast.declCount()) |i| {
                    const d = DeclId.at(@intCast(i));
                    try testing.expectEqual(b.seesTrait(m, d), a.seesTrait(m, d));
                    const name = program.ast.tokenName(program.ast.declName(d));
                    var continued_named = a.traitMembersNamed(m, name);
                    var fresh_named = b.traitMembersNamed(m, name);
                    while (fresh_named.next()) |expected| {
                        try testing.expectEqual(expected, continued_named.next());
                        if (expected.member == d and std.mem.eql(u8, program.ast.tokenText(program.ast.declName(d)), "mark")) marks += 1;
                    }
                    try testing.expectEqual(@as(?TraitMember, null), continued_named.next());
                    var continued_anywhere = a.traitMembersNamedAnywhere(name);
                    var fresh_anywhere = b.traitMembersNamedAnywhere(name);
                    while (fresh_anywhere.next()) |expected| try testing.expectEqual(expected, continued_anywhere.next());
                    try testing.expectEqual(@as(?TraitMember, null), continued_anywhere.next());
                }
            }
            // The library's `mark` is indexed once per module that names
            // `Marker`, and each name is visited once per module above.
            const marker_rows: usize = if (std.mem.indexOf(u8, library_text, "trait Marker") != null) program.modules.len else 0;
            try testing.expectEqual(marker_rows, marks);
        }
    }
}

test "construction skips malformed derive receiver shapes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "derive.lin", .text =
        \\trait Structural {}
        \\template impl Structural {}
        \\struct Pair[A, B] { left: A, right: B }
        \\derive[T] Structural for Pair[T, T]
        \\fn main() -> UInt8 {
        \\    let _pair: Pair[UInt8, UInt8] = .{ left = 0, right = 0 }
        \\    0
        \\}
    };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expectEqual(@as(u32, 1), sink.error_count);
    try testing.expectEqual(@as(usize, 1), diagnosticCodeCount(&sink, .t_derive));

    const tree = try resolveTree(gpa, &ast, &sink);
    try testing.expectEqual(@as(u32, 1), sink.error_count);
    try testing.expectEqual(@as(usize, 0), tree.expanded.generated_sources.buffers.len);
}
