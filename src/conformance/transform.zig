const std = @import("std");
const testing = std.testing;

const Source = @import("../support/source.zig").Source;
const FileId = @import("../support/source.zig").FileId;
const Span = @import("../support/span.zig").Span;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const Ast = @import("../syntax/ast.zig").Ast;
const Program = @import("../syntax/program.zig").Program;
const ModuleId = @import("../syntax/program.zig").ModuleId;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const DeclIndex = @import("../syntax/ast.zig").DeclIndex;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const TokenId = @import("../lexer/token.zig").TokenId;
const resolve_mod = @import("../sema/resolve.zig");
const resolveTree = resolve_mod.resolveTree;
const resolve = resolve_mod.resolve;
const typecheck = @import("../sema/typecheck.zig").typecheck;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;
const loader = @import("../driver/loader.zig");
const isCatchAll = @import("../sema/typecheck.zig").isCatchAll;
const FileTable = @import("../support/source.zig").FileTable;
const Resolution = resolve_mod.Resolution;
const BindingId = resolve_mod.BindingId;
const types_mod = @import("../sema/types.zig");
const Typing = types_mod.Typing;
const references = @import("../lsp/references.zig");
const Uses = @import("../lsp/uses.zig").Uses;
const perturb = @import("perturb.zig");
const fmt = @import("../fmt/fmt.zig");
const generate = @import("generate.zig");
const mutate = @import("mutate.zig");

/// Full-program answers used only to decide which source-local rewrite applies.
pub const Semantics = struct {
    ast: *const Ast,
    program: *const Program,
    res: *const Resolution,
    typing: *const Typing,
    file: FileId,
};

pub const MaterializedDerives = struct {
    files: []loader.InMemoryFile,

    pub fn deinit(self: *MaterializedDerives, gpa: std.mem.Allocator) void {
        for (self.files) |file| {
            gpa.free(file.path);
            gpa.free(file.text);
        }
        gpa.free(self.files);
        self.* = .{ .files = &.{} };
    }
};

fn moduleOfFile(program: *const Program, file: FileId) ModuleId {
    for (program.modules, 0..) |module, raw| {
        for (module.files) |candidate| {
            if (candidate == file) return ModuleId.from(raw);
        }
    }
    return .none;
}

/// Keep source aliases reached outside removed derive syntax, then follow the
/// retained aliases' own paths. Trait uses also retain method-lookup scope.
/// Resolution supplies every reference identity and alias kind.
const MaterializedAliasUses = struct {
    const Alias = struct {
        declaration: DeclId,
        dependencies: std.ArrayList(usize) = .empty,
        live: bool = false,
    };
    aliases: std.ArrayList(Alias) = .empty,
    by_binding: std.AutoHashMapUnmanaged(BindingId, usize) = .empty,
    owner_at: std.AutoHashMapUnmanaged(TokenId, usize) = .empty,
    pending: std.ArrayList(usize) = .empty,

    fn deinit(self: *MaterializedAliasUses, gpa: std.mem.Allocator) void {
        for (self.aliases.items) |*alias| alias.dependencies.deinit(gpa);
        self.aliases.deinit(gpa);
        self.by_binding.deinit(gpa);
        self.owner_at.deinit(gpa);
        self.pending.deinit(gpa);
    }

    fn keep(self: *MaterializedAliasUses, gpa: std.mem.Allocator, alias: usize) !void {
        if (self.aliases.items[alias].live) return;
        self.aliases.items[alias].live = true;
        try self.pending.append(gpa, alias);
    }

    fn note(self: *MaterializedAliasUses, gpa: std.mem.Allocator, token: TokenId, binding: BindingId, omitted: []const bool) !void {
        if (token == .none or token.index() >= omitted.len or omitted[token.index()]) return;
        const target = self.by_binding.get(binding) orelse return;
        if (self.owner_at.get(token)) |owner| {
            if (owner != target) try self.aliases.items[owner].dependencies.append(gpa, target);
        } else {
            try self.keep(gpa, target);
        }
    }
};

fn removeUnusedMaterializedAliases(
    gpa: std.mem.Allocator,
    program: *const Program,
    resolution: *const Resolution,
    omitted: []const bool,
    removed: []bool,
) !void {
    var uses: MaterializedAliasUses = .{};
    defer uses.deinit(gpa);
    var by_name: std.AutoHashMapUnmanaged(TokenId, usize) = .empty;
    defer by_name.deinit(gpa);
    for (program.modules) |module| {
        if (module.library) continue;
        for (module.decls.start..module.decls.end) |raw| {
            const declaration = DeclId.at(@intCast(raw));
            const tag = program.ast.declTag(declaration);
            if (tag != .import_ and tag != .use_) continue;
            const index = uses.aliases.items.len;
            try uses.aliases.append(gpa, .{ .declaration = declaration });
            try by_name.put(gpa, program.ast.declName(declaration), index);
            var tokens = program.ast.runOf(program.ast.declTokens(declaration));
            while (tokens.next()) |token| try uses.owner_at.put(gpa, token, index);
            if (program.ast.declVisibility(declaration) != .private) try uses.keep(gpa, index);
        }
    }
    for (resolution.tokens, 0..) |token, raw| {
        const index = by_name.get(token) orelse continue;
        try uses.by_binding.put(gpa, BindingId.at(@intCast(raw)), index);
        // A trait use contributes method scope without spelling its name at
        // each call. Preserve that scope just as resolution's unused check does.
        if (resolution.kinds[raw] == .trait and
            program.ast.declTag(uses.aliases.items[index].declaration) == .use_)
            try uses.keep(gpa, index);
    }
    for (resolution.written[0..@min(resolution.written.len, omitted.len)], 0..) |binding, raw| {
        try uses.note(gpa, TokenId.at(@intCast(raw)), binding, omitted);
    }
    for (resolution.targets, resolution.spelled) |binding, token| {
        try uses.note(gpa, token, binding, omitted);
    }
    var next: usize = 0;
    while (next < uses.pending.items.len) : (next += 1) {
        const index = uses.pending.items[next];
        for (uses.aliases.items[index].dependencies.items) |dependency| try uses.keep(gpa, dependency);
    }
    for (uses.aliases.items) |alias| removed[alias.declaration.index()] = !alias.live;
}

/// Replaces every admitted derive in the primary root with the immutable
/// ordinary source file expansion produced for it.
pub fn materializeDerives(
    gpa: std.mem.Allocator,
    program: *const Program,
    expanded: *const ExpandedProgram,
    resolution: *const Resolution,
) !?MaterializedDerives {
    const selected = try gpa.alloc(bool, program.ast.declCount());
    defer gpa.free(selected);
    @memset(selected, false);

    var generated_count: usize = 0;
    for (0..expanded.generatedSourceCount()) |raw| {
        const generated = expanded.generatedSource(@intCast(raw));
        if (generated.module == .none or program.get(generated.module).library) continue;
        selected[generated.origin.derive.index()] = true;
        generated_count += 1;
    }
    if (generated_count == 0) return null;

    const removed = try gpa.alloc(bool, program.ast.declCount());
    defer gpa.free(removed);
    @memset(removed, false);
    const omitted_tokens = try gpa.alloc(bool, program.ast.tokenCount());
    defer gpa.free(omitted_tokens);
    @memset(omitted_tokens, false);
    const omitted_traits = try gpa.alloc(bool, program.ast.derive_traits.len);
    defer gpa.free(omitted_traits);
    @memset(omitted_traits, false);

    var has_attached = false;
    for (selected, 0..) |chosen, raw| {
        if (!chosen) continue;
        const declaration = DeclId.at(@intCast(raw));
        if (program.ast.declTag(declaration) == .derive_impl) {
            removed[raw] = true;
            const range = program.ast.declTokens(declaration);
            @memset(omitted_tokens[range.start.index()..range.end.index()], true);
        } else {
            has_attached = true;
        }
    }
    for (0..expanded.generatedImplementationCount()) |raw| {
        const implementation = expanded.generatedImplementation(.at(@intCast(raw)));
        if (!selected[implementation.derive.index()]) continue;
        const index = implementation.derive_trait.index();
        omitted_traits[index] = true;
        const range = program.ast.derive_traits[index].tokens;
        @memset(omitted_tokens[range.start.index()..range.end.index()], true);
    }
    try removeUnusedMaterializedAliases(gpa, program, resolution, omitted_tokens, removed);
    var indexes: ?fmt.Indexes = if (has_attached) try fmt.Indexes.build(gpa, &program.ast) else null;
    defer if (indexes) |*value| value.deinit(gpa);

    var source_count: usize = 0;
    for (program.ast.parts) |part| {
        const module = moduleOfFile(program, part.file);
        if (module != .none and !program.get(module).library) source_count += 1;
    }

    const files = try gpa.alloc(loader.InMemoryFile, source_count + generated_count);
    var initialized: usize = 0;
    errdefer {
        for (files[0..initialized]) |file| {
            gpa.free(file.path);
            gpa.free(file.text);
        }
        gpa.free(files);
    }

    for (program.ast.parts) |part| {
        const module = moduleOfFile(program, part.file);
        if (module == .none or program.get(module).library) continue;

        var rewritten: std.ArrayList(u8) = .empty;
        defer rewritten.deinit(gpa);
        var cursor: u32 = 0;
        for (part.decl_start..part.decl_end) |raw| {
            const declaration = DeclId.at(@intCast(raw));
            if (!removed[raw] and !selected[raw]) continue;
            const range = program.ast.declTokens(declaration);
            const start = program.ast.tokenSpan(range.start).start;
            const end = program.ast.tokenSpan(TokenId.at(range.end.index() - 1)).end;
            try rewritten.appendSlice(gpa, part.source[cursor..start]);
            if (!removed[raw]) {
                var formatted: std.Io.Writer.Allocating = .init(gpa);
                defer formatted.deinit();
                try fmt.formatDecl(gpa, &program.ast, &indexes.?, .{ .omit_derive_traits = omitted_traits }, declaration, &formatted.writer);
                try rewritten.appendSlice(gpa, std.mem.trimEnd(u8, formatted.written(), "\r\n"));
            }
            cursor = end;
        }
        try rewritten.appendSlice(gpa, part.source[cursor..]);

        const path = try gpa.dupe(u8, part.path);
        const text = gpa.dupe(u8, rewritten.items) catch |err| {
            gpa.free(path);
            return err;
        };
        files[initialized] = .{ .path = path, .text = text };
        initialized += 1;
    }

    for (0..expanded.generatedSourceCount()) |raw| {
        const generated = expanded.generatedSource(@intCast(raw));
        if (generated.module == .none or program.get(generated.module).library) continue;
        const path = try std.fs.path.join(gpa, &.{ program.get(generated.module).dir, generated.path });
        for (files[0..initialized]) |file| {
            if (std.mem.eql(u8, file.path, path)) {
                gpa.free(path);
                return error.GeneratedSourcePathCollision;
            }
        }
        const text = gpa.dupe(u8, generated.text) catch |err| {
            gpa.free(path);
            return err;
        };
        files[initialized] = .{ .path = path, .text = text };
        initialized += 1;
    }

    std.debug.assert(initialized == files.len);
    return .{ .files = files };
}

/// A rewrite of a program's source that must not change what the program
/// answers.
///
/// The expectation is the program's own behaviour, so a transformation needs
/// no recorded output and no generator: every case that already records an
/// exit status is a case for this too, and one added tomorrow is one for free.
/// That is what a golden file cannot do — a golden compares the compiler
/// against what someone wrote down once, and every bug these transformations
/// exist for produced a program that built, ran, and answered confidently.
///
/// Each transformation is deterministic. A random one would find more, and
/// would also fail on a different case each run, which is how a suite stops
/// being believed.
pub const Transform = enum {
    reversed_declarations,
    /// Every trait's and every implementation's members, last first.
    ///
    /// Its own axis, because a member is not a declaration in the sense the
    /// rewrite above reorders: it lies inside its container's extent, so that
    /// one skips it by design and no rewrite moved one at all. What a member
    /// answers is decided by its name -- which signature an implementation
    /// supplies, which type a settled reference reaches -- so the order says
    /// nothing, and this is the axis the one order bug this feature had was on.
    reversed_members,
    rotated_match_arms,
    renamed_bindings,
    reordered_fields,
    /// Whitespace mangled and then formatted.
    ///
    /// It perturbs before formatting rather than simply formatting, and that is
    /// the whole point: a rewrite that only formatted would say nothing about a
    /// case already formatted, and would quietly cover less as the corpus was
    /// tidied while reporting success throughout.
    formatted,
    /// One logical operator replaced by what the semantics defines it to be.
    ///
    /// The others rewrite a program into one that must mean the same because
    /// nothing about meaning depends on what they changed. This one rewrites
    /// it into what the language says it already was, so it holds the compiler
    /// to a definition rather than to an invariance -- and the definition is
    /// stated in prose, which nothing else checks.
    desugared_logic,
    /// A postfix call written out as the call it is.
    postfix_written_out,
    /// One `defer let` written out as the binding and the `defer` it is
    /// defined to be.
    ///
    /// Held to the same code as the original, for the reason a logical
    /// operator is: the language says `defer let x = e` is `let x = e` followed
    /// by `defer x.release()`, and two lowerings agreeing only on what they
    /// compute would leave that unchecked.
    defer_let_written_out,
    /// A call's named arguments written in another order.
    permuted_named_arguments,
    /// An implementation or derive head's own type parameters spelled
    /// differently.
    ///
    /// The head is the constructor applied to those parameters, so what they
    /// are called is a spelling and nothing else: `impl[T: Display] Display for
    /// Option[T]` and `impl[A: Display] Display for Option[A]` are the same
    /// implementation. It is the one rewrite this position admits — reordering
    /// the parameters is not meaning-preserving, because the head must apply
    /// them in the order they were declared and permuting them changes which
    /// programs are legal.
    renamed_head_parameters,

    /// The rewritten source, or null where the transformation says nothing
    /// about this program — it does not apply, or it applies to no effect.
    ///
    /// Returning null rather than the input unchanged keeps "nothing to check"
    /// distinct from "checked and identical", so a transformation that quietly
    /// stops applying to the whole corpus is visible rather than green.
    pub fn apply(
        self: Transform,
        gpa: std.mem.Allocator,
        ast: *const Ast,
        res: *const Resolution,
        /// What the checker settled, for the rewrites that move a name a later
        /// pass rather than the resolver paired with its declaration.
        typing: *const Typing,
        semantics: Semantics,
        text: []const u8,
    ) !?[]const u8 {
        const rewritten = switch (self) {
            .reversed_declarations => try reverseDeclarations(gpa, ast, res, text),
            .reversed_members => try reverseMembers(gpa, ast, text),
            .rotated_match_arms => try rotateMatchArms(gpa, ast, text),
            .renamed_bindings => try renameBindings(gpa, ast, res, typing, text),
            .reordered_fields => try reorderFields(gpa, ast, text),
            .desugared_logic => try desugarLogic(gpa, ast, typing, text),
            .postfix_written_out => try postfixWrittenOut(gpa, semantics, text),
            .defer_let_written_out => try writeOutDeferLet(gpa, ast, text),
            .permuted_named_arguments => try permuteNamedArguments(gpa, ast, typing, text),
            .renamed_head_parameters => try renameHeadParameters(gpa, ast, res, text),
            .formatted => try perturb.perturbAndFormat(gpa, text),
        } orelse return null;

        // The convention below, enforced rather than asked for. A rewrite that
        // produced the input unchanged is a comparison of a program against
        // itself: it costs a build and a run and can never fail, and it counts
        // towards coverage while saying nothing. Each rewrite here promises to
        // return null instead; this is what makes the promise true, and what
        // stops one that has quietly degraded to the identity reading as
        // applied.
        if (std.mem.eql(u8, rewritten, text)) return null;
        return rewritten;
    }

    pub fn why(self: Transform) []const u8 {
        return switch (self) {
            .reversed_declarations => "declarations reversed",
            .reversed_members => "a trait's and an implementation's members reversed",
            .rotated_match_arms => "match arms rotated",
            .renamed_bindings => "bindings renamed",
            .reordered_fields => "a structure's fields reordered",
            .formatted => "whitespace mangled and reformatted",
            .desugared_logic => "a logical operator written out as what it means",
            .postfix_written_out => "a postfix call written out as the call it is",
            .defer_let_written_out => "a `defer let` written out as a binding and the `defer` of its release",
            .permuted_named_arguments => "a call's named arguments rotated",
            .renamed_head_parameters => "an implementation or derive head's own type parameters renamed",
        };
    }
};

/// `impl[T: Display] Display for Option[T]` written `impl[Zz0: Display] Display
/// for Option[Zz0]`.
///
/// Resolved references must name the implementation's own parameter. Names
/// shared with value bindings, fields, or variants are excluded before rewriting
/// the implementation extent, so a replacement cannot capture another meaning.
///
/// Every generic implementation and derive in the file at once, each parameter
/// to a spelling of its own.
fn renameHeadParameters(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    text: []const u8,
) !?[]const u8 {
    // A spelling the program does not already use. Without the leading `_` the
    // rewrite over bindings carries: a type parameter nothing writes is
    // [N-Unused], and a marker added here would answer a diagnostic the program
    // was owed.
    const prefix = "Zz";
    if (std.mem.indexOf(u8, text, prefix) != null) return null;

    // **Bound:** one pass over the bindings and one over the declarations,
    // reading each declaration's own fields and variants.
    var taken: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer taken.deinit(gpa);
    for (0..res.bindingCount()) |i| {
        const binding = BindingId.at(@intCast(i));
        if (res.kindOf(binding) == .type_parameter) continue;
        const tok = res.declaringToken(binding);
        if (tok == TokenId.none or tok.index() >= ast.tokenCount()) continue;
        try taken.put(gpa, @intFromEnum(ast.tokenName(tok)), {});
    }
    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        for (ast.declFields(d)) |f| {
            if (f.name == TokenId.none) continue;
            try taken.put(gpa, @intFromEnum(ast.tokenName(f.name)), {});
        }
        for (ast.declVariants(d)) |v| {
            try taken.put(gpa, @intFromEnum(ast.tokenName(v.name)), {});
            for (ast.variantFields(v)) |f| {
                if (f.name == TokenId.none) continue;
                try taken.put(gpa, @intFromEnum(ast.tokenName(f.name)), {});
            }
        }
    }

    // Which tokens an expression spells, so a value reference is never taken
    // for a type parameter written in the same letters.
    var spelled: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer spelled.deinit(gpa);
    for (0..ast.exprCount()) |i| {
        const tok = res.spelledAt(ExprId.at(@intCast(i)));
        if (tok == TokenId.none) continue;
        try spelled.put(gpa, @intFromEnum(tok), {});
    }

    const Site = struct { start: u32, end: u32, to: u32 };
    var sites: std.ArrayList(Site) = .empty;
    defer sites.deinit(gpa);

    var fresh: u32 = 0;
    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        const tag = ast.declTag(d);
        if (tag != .impl_ and tag != .derive_impl) continue;
        const params = ast.declTypeParams(d);
        if (params.len == 0) continue;

        if (tag == .derive_impl) {
            // A derive has no singular trait field. Its group entries and
            // target arguments are the complete head this rename preserves.
            // Reading both accessors keeps the rewrite on the source form
            // rather than treating it as an ordinary implementation.
            const traits = ast.deriveTraits(d);
            const target_args = ast.typeArgs(ast.declHead(d).args);
            if (traits.len == 0 or target_args.len != params.len) continue;
        }

        var respellable = true;
        for (params) |p| {
            if (p.name == TokenId.none or ast.tokenTag(p.name) != .identifier) {
                respellable = false;
                break;
            }
            if (tag == .impl_ and taken.contains(@intFromEnum(ast.tokenName(p.name)))) {
                respellable = false;
                break;
            }
            // A leading `_` says the parameter is deliberately unused, and a
            // spelling without one turns that into [N-Unused].
            if (std.mem.startsWith(u8, ast.tokenText(p.name), "_")) {
                respellable = false;
                break;
            }
        }
        if (!respellable) continue;

        const first = fresh;
        fresh += @intCast(params.len);

        var run = ast.runOf(ast.declTokens(d));
        var previous: ?TokenId = null;
        while (run.next()) |tok| {
            defer previous = tok;
            if (ast.tokenTag(tok) != .identifier) continue;

            const name = ast.tokenName(tok);
            var which: ?u32 = null;
            for (params, 0..) |p, k| {
                if (ast.tokenName(p.name) != name) continue;
                if (tag == .derive_impl and tok != p.name) {
                    const binding = res.writtenAt(tok);
                    if (binding == BindingId.none or res.declaringToken(binding) != p.name) continue;
                }
                which = @intCast(k);
                break;
            }
            const at = which orelse continue;

            if (tag == .impl_) {
                const binding = res.writtenAt(tok);
                if (binding != BindingId.none) {
                    if (res.declaringToken(binding) != params[at].name) return null;
                } else if (spelled.contains(@intFromEnum(tok))) return null;
                // A name after a dot is selected from whatever stands before it.
                if (previous) |before| {
                    if (ast.tokenTag(before) == .dot) return null;
                }
            }

            const span = ast.tokenSpan(tok);
            try sites.append(gpa, .{ .start = span.start, .end = span.end, .to = first + at });
        }
    }

    if (sites.items.len == 0) return null;

    std.mem.sort(Site, sites.items, {}, struct {
        fn before(_: void, a: Site, b: Site) bool {
            return a.start < b.start;
        }
    }.before);

    var out: std.Io.Writer.Allocating = .init(gpa);
    var cursor: u32 = 0;
    for (sites.items) |s| {
        try out.writer.writeAll(text[cursor..s.start]);
        try out.writer.print("{s}{d}", .{ prefix, s.to });
        cursor = s.end;
    }
    try out.writer.writeAll(text[cursor..]);
    return out.written();
}

fn bindingName(ast: *const Ast, res: *const Resolution, binding: BindingId) ?[]const u8 {
    if (res.builtinOf(binding)) |primitive| return primitive.nameOf();
    const token = res.declaringToken(binding);
    return if (token == .none) null else ast.tokenText(token);
}

fn namespaceSelects(
    gpa: std.mem.Allocator,
    semantics: Semantics,
    binding: BindingId,
    signature: DeclId,
    members: *std.ArrayList(resolve_mod.Selectable),
) !bool {
    if (!resolve_mod.namesANamespace(semantics.res.kindOf(binding))) return false;
    try resolve_mod.selectableUnder(gpa, semantics.ast, semantics.program, semantics.res, semantics.res.moduleOfFile(semantics.file), binding, members);
    for (members.items) |member| switch (member) {
        .member => |selected| if (semantics.res.declaredBy(selected) == signature) return true,
        .variant => {},
    };
    return false;
}

/// Finds a caller-visible namespace for the selected declaration. Binding
/// names preserve aliases; resolver tables preserve re-exports and visibility.
/// Costs the source file's statements, visible scope chain, and namespaces
/// reachable through that chain.
fn visibleCallOwner(gpa: std.mem.Allocator, semantics: Semantics, call: ExprId, signature: DeclId) !?[]const u8 {
    const ast = semantics.ast;
    const res = semantics.res;
    const writing = res.moduleOfFile(semantics.file);
    var visible: std.ArrayList(BindingId) = .empty;
    defer visible.deinit(gpa);
    try res.visibleIn(gpa, res.scopeOfExpr(call), &visible);
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(gpa);
    var members: std.ArrayList(resolve_mod.Selectable) = .empty;
    defer members.deinit(gpa);
    var reachable: std.ArrayList(BindingId) = .empty;
    defer reachable.deinit(gpa);

    // A scope retains all its bindings, but a declaration introduces its
    // names only after its initializer. Collect unavailable bindings once,
    // using the resolver's identities for both locals and pattern binders.
    var unavailable: std.AutoHashMapUnmanaged(BindingId, void) = .empty;
    defer unavailable.deinit(gpa);
    const part = ast.partOfFile(semantics.file) orelse return null;
    const call_start = ast.exprExtent(call).start;
    for (part.stmt_start..part.stmt_end) |raw| {
        const statement = node.StmtId.at(@intCast(raw));
        const tag = ast.stmtTag(statement);
        if (tag != .let_decl and !tag.isDestructure()) continue;
        const data = ast.stmtData(statement);
        if (data.init == .none or ast.exprExtent(data.init).end <= call_start) continue;
        if (tag == .let_decl) {
            const binding = res.bindingOf(statement);
            if (binding != .none) try unavailable.put(gpa, binding, {});
        } else {
            if (data.pattern == .none) continue;
            try putPatternBinders(gpa, ast, res, &unavailable, data.pattern);
        }
    }

    // A lexical binding in scope at the call shadows an import of its name,
    // so only the imports no such binding holds can head the written call.
    var lexical: std.StringHashMapUnmanaged(void) = .empty;
    defer lexical.deinit(gpa);
    for (visible.items) |binding| {
        if (!resolve_mod.kindShadowsAnImport(res.kindOf(binding)) or unavailable.contains(binding)) continue;
        const name = bindingName(ast, res, binding) orelse continue;
        try lexical.put(gpa, name, {});
    }

    // Qualified lookup checks the unshadowed file-local imports before
    // ordinary bindings.
    for (visible.items) |binding| {
        if (res.kindOf(binding) != .module) continue;
        if (ast.fileOfDecl(res.importOf(binding)) != semantics.file) continue;
        const name = bindingName(ast, res, binding) orelse continue;
        if (lexical.contains(name)) continue;
        if ((try seen.getOrPut(gpa, name)).found_existing) continue;
        const target = semantics.program.get(writing).importedBy(res.importOf(binding));
        if (target == .none) continue;
        try res.reachableThrough(gpa, semantics.program, target, writing, &reachable);
        for (reachable.items) |exported| {
            if (!try namespaceSelects(gpa, semantics, exported, signature, &members)) continue;
            const exported_name = bindingName(ast, res, exported) orelse continue;
            return try std.fmt.allocPrint(gpa, "{s}.{s}", .{ name, exported_name });
        }
    }

    for (visible.items) |binding| {
        if (res.kindOf(binding) == .module or unavailable.contains(binding)) continue;
        const name = bindingName(ast, res, binding) orelse continue;
        if ((try seen.getOrPut(gpa, name)).found_existing) continue;
        if (try namespaceSelects(gpa, semantics, binding, signature, &members)) return try gpa.dupe(u8, name);
    }
    return null;
}

/// `a.of()` written out as `Measure.of(a)`.
///
/// Reads the checked call target and finds a namespace visible to the caller.
/// Rewrites the first eligible call so each transformation is checked separately.
fn postfixWrittenOut(gpa: std.mem.Allocator, semantics: Semantics, text: []const u8) !?[]const u8 {
    const ast = semantics.ast;
    const typing = semantics.typing;
    const calls = &typing.call_index;
    for (typing.postfix) |p| {
        // Only source expressions can be rewritten; generated calls share
        // the checked index but have no syntax in this tree.
        if (p.call >= semantics.program.ast.exprCount()) continue;
        const call = ExprId.at(p.call);
        const normal = calls.callOf(typing, call) orelse continue;
        const signature = switch (normal.target) {
            .declared => |decl| decl,
            .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => continue,
        };

        // Which file a span indexes is decided by the token that opens it, not
        // by whichever text happens to be in hand. The program loaded here
        // carries the library, so a postfix call written in `std/` has a span
        // into another file -- and cutting this text at those offsets splices
        // the library's spelling into the middle of whatever sat there.
        //
        // The rewrite is of the file it was handed, so a call written
        // elsewhere is not one it can rewrite.
        if (ast.fileOf(ast.exprTokens(call).start) != semantics.file) continue;

        // By the extent rather than the span: a comment written after the call
        // sits inside its range, and cutting there deletes it from the text
        // that follows.
        const at = ast.exprExtent(call);
        if (at.end > text.len) continue;

        // Qualify the function through a visible namespace and pass the
        // receiver first, as recorded by the checker.
        const owner = try visibleCallOwner(gpa, semantics, call, signature) orelse continue;
        defer gpa.free(owner);
        const name = ast.tokenText(ast.declName(signature));

        // The record is receiver-first and the tree's names are not, so what
        // the source wrote is the tail. The head is the receiver, which is an
        // argument the source never spells and so names nothing.
        const receiver = p.args.len - ast.callNames(call).len;

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try out.print(gpa, "{s}.{s}(", .{ owner, name });
        // `&x.op(args)` lends the receiver `inout`, and the `&` is part of the
        // call's extent being replaced, so it moves onto the receiver argument
        // where the written-out call lends it.
        const marked = ast.exprTag(call) == .call and ast.callMarked(call);
        for (p.args[0..receiver], 0..) |a, i| {
            if (i > 0) try out.appendSlice(gpa, ", ");
            if (i == 0 and marked) try out.append(gpa, '&');
            // By the extent again, one argument down: a comment inside the last
            // argument's range would be written ahead of the paren that closes
            // the written-out call and comment it out.
            try out.appendSlice(gpa, ast.exprExtent(a).slice(text));
        }
        // The names the call wrote, carried across by the tree's own renderer,
        // which is the one the server's offer writes through as well.
        try ast.appendWrittenArguments(gpa, &out, text, call, receiver > 0);
        try out.append(gpa, ')');

        return try std.mem.concat(gpa, u8, &.{
            text[0..at.start],
            out.items,
            text[at.end..],
        });
    }
    return null;
}

/// The first logical operator, replaced by the form the semantics defines it
/// to be.
///
/// `a && b` **is** `if a { b } else { false }`, `a || b` **is**
/// `if a { true } else { b }`, and `!e` **is** `e == false`. The document says
/// "is" rather than "behaves like", and two lowerings that happen to agree are
/// what that claim rests on -- one of them written for the operator and one
/// for the conditional, neither reading the other.
///
/// One operator rather than all of them: an operand may hold another, and
/// rewriting an outer form moves the text an inner one was measured against.
fn desugarLogic(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    typing: *const Typing,
    text: []const u8,
) !?[]const u8 {
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        // By the extent rather than the span, here and at every operand below:
        // a comment written after the operator sits inside its range, so
        // cutting there deletes it and slicing an operand there writes it
        // inside the braces the conditional form puts around one -- where it
        // comments out the brace that closes them.
        const at = ast.exprExtent(id);
        if (at.end > text.len) continue;

        var out: std.Io.Writer.Allocating = .init(gpa);
        switch (ast.exprTag(id)) {
            .logical_and, .logical_or => {
                const b = ast.binary(id);
                const lhs = ast.exprExtent(b.lhs).slice(text);
                const rhs = ast.exprExtent(b.rhs).slice(text);
                const short = ast.exprTag(id) == .logical_and;
                // The operand becomes a control header, where a named
                // literal's brace would open the arm; parentheses delimit it.
                try out.writer.print("if ({s}) {{ {s} }} else {{ {s} }}", .{
                    lhs,
                    if (short) rhs else "true",
                    if (short) "false" else rhs,
                });
            },
            .not => {
                const operand = ast.unaryOperand(id);
                // Where the condition is what settles the operand's type, the
                // equality is a different program. Passed over rather than
                // abandoning the file: another operator in it may still be one
                // this rewrite can claim.
                if (holdsACallThroughATrait(ast, typing, operand)) continue;
                try out.writer.print("{s} == false", .{ast.exprExtent(operand).slice(text)});
            },
            else => continue,
        }

        var rewritten: std.Io.Writer.Allocating = .init(gpa);
        try rewritten.writer.writeAll(text[0..at.start]);
        try rewritten.writer.writeAll(out.written());
        try rewritten.writer.writeAll(text[at.end..]);
        return rewritten.written();
    }
    return null;
}

/// The first `defer let` in a file written as `let` and then `defer
/// name.release()`, which is what the semantics defines it to be.
///
/// The `defer ` prefix is cut, and the release goes on the line after the
/// binding at the binding's indentation, or after a `;` where the binding does
/// not begin its line. It follows the initialiser's last token, so a trailing
/// comment stays on the binding's line.
///
/// **Bound:** one pass over the statements until the first `defer let`.
fn writeOutDeferLet(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    for (0..ast.stmtCount()) |i| {
        const s = node.StmtId.at(@intCast(i));
        if (ast.stmtTag(s) != .let_decl or !ast.stmtIsDeferredBinding(s)) continue;
        const d = ast.stmtData(s);
        if (d.init == ExprId.none) continue;

        const keyword = ast.tokenSpan(ast.stmtTokens(s).start);
        const binding = ast.tokenSpan(ast.stmtMain(s));
        const end = ast.exprExtent(d.init).end;
        if (end > text.len) continue;

        var line = keyword.start;
        while (line > 0 and text[line - 1] != '\n') line -= 1;
        const alone = std.mem.indexOfNone(u8, text[line..keyword.start], " \t") == null;

        var out: std.Io.Writer.Allocating = .init(gpa);
        try out.writer.writeAll(text[0..keyword.start]);
        try out.writer.writeAll(text[binding.start..end]);
        if (alone) {
            try out.writer.print("\n{s}", .{text[line..keyword.start]});
        } else {
            try out.writer.writeAll("; ");
        }
        try out.writer.print("defer {s}.release()", .{ast.tokenText(d.name)});
        try out.writer.writeAll(text[end..]);
        return out.written();
    }
    return null;
}

test writeOutDeferLet {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .defer_let_written_out,
        \\fn main() -> UInt8 {
        \\    defer let a: UInt8 = 1 // kept
        \\    defer var b: UInt8 = 2;
        \\    a + b
        \\}
        \\
    )).?;
    try testing.expectEqualStrings(
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1
        \\    defer a.release() // kept
        \\    defer var b: UInt8 = 2;
        \\    a + b
        \\}
        \\
    , got);

    const inline_form = (try applyTo(gpa, .defer_let_written_out,
        \\fn main() -> UInt8 { defer let a: UInt8 = 1; a }
        \\
    )).?;
    try testing.expectEqualStrings(
        \\fn main() -> UInt8 { let a: UInt8 = 1; defer a.release(); a }
        \\
    , inline_form);

    try testing.expectEqual(@as(?[]const u8, null), try applyTo(gpa, .defer_let_written_out,
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1
        \\    a
        \\}
        \\
    ));
}

test "a defer let and the pair it is written out as reach one verdict" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const lamp =
        \\@linear
        \\struct Lamp {
        \\    id: UInt8,
        \\}
        \\
        \\impl Release for Lamp {
        \\    fn release(sink self: Self) {
        \\        let Lamp { id: _ } = self
        \\    }
        \\}
        \\
        \\fn give(sink lamp: Lamp) -> UInt8 {
        \\    let Lamp { id } = lamp
        \\    id
        \\}
        \\
        \\
    ;
    const cases = [_]struct { body: []const u8, rule: []const u8 }{
        .{ .body = "fn main() -> UInt8 {\n    defer let lamp: Lamp = .{ id = 1 }\n    give(Lamp { id = 2 })\n}\n", .rule = "" },
        .{ .body = "fn main() -> UInt8 {\n    defer let lamp: Lamp = .{ id = 1 }\n    give(lamp)\n}\n", .rule = "O-DeferDead " },
        .{
            .body = "fn go(flag: Bool) -> UInt8 {\n    defer let lamp: Lamp = .{ id = 1 }\n    if flag { give(lamp) } else { 0 }\n}\n" ++
                "fn main() -> UInt8 {\n    go(true)\n}\n",
            .rule = "O-Merge ",
        },
    };
    for (cases) |case| {
        const text = try std.mem.concat(gpa, u8, &.{ lamp, case.body });
        const written_out = (try applyTo(gpa, .defer_let_written_out, text)).?;
        const deferred = try mutate.verdictOf(gpa, text, .program);
        const pair = try mutate.verdictOf(gpa, written_out, .program);
        try testing.expectEqualStrings(case.rule, deferred.text);
        try testing.expectEqualStrings(pair.text, deferred.text);
        try testing.expectEqual(pair.rejected, deferred.rejected);
    }

    // A type with no `Release` is refused by both, and each says why in its
    // own words: the pair finds no operation, the keyword has no ending to pick.
    const transfer =
        \\@linear
        \\struct Transfer {
        \\    cents: UInt64,
        \\}
        \\
        \\impl Transfer {
        \\    fn commit(sink self: Self) -> UInt64 {
        \\        let Transfer { cents } = self
        \\        cents
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _paid = Transfer { cents = 1 }.commit()
        \\    defer let transfer = Transfer { cents = 3 }
        \\    0
        \\}
        \\
    ;
    const refused = try mutate.verdictOf(gpa, transfer, .program);
    const refused_pair = try mutate.verdictOf(gpa, (try applyTo(gpa, .defer_let_written_out, transfer)).?, .program);
    try testing.expectEqualStrings("T-DeferLet ", refused.text);
    try testing.expectEqualStrings("T-UnknownOperation ", refused_pair.text);
}

/// Whether an expression holds a call that reaches its body through a trait.
///
/// `!e` checks `e` as a condition, which asks it for a `Bool`. `e == false`
/// checks it as the left operand of an equality, which asks it for nothing and
/// takes whatever it determines on its own. Those are one answer for almost
/// every expression, because almost every expression determines its own type.
/// A call through a trait is the exception: `Self` and the trait's own
/// parameters may be settled by what the call is asked for, so a signature
/// writing one only as its return type is settled in the first form and
/// settled by nothing in the second. The two spellings are two programs there,
/// and this rewrite claims neither -- the premise every rewrite here rests on
/// is that it cannot change what the program means.
///
/// Read off the records the checker left rather than worked out here: which
/// calls go through a trait is its answer, and reading the tree for it again
/// would be a second answer to one question.
///
/// The whole operand rather than its outermost node, because an expectation
/// reaches through whatever passes one on -- a conditional's arms, a block's
/// tail. An operand holding such a call somewhere that settles it another way
/// is passed over too, which loses coverage and never loses correctness.
///
/// **Bound:** one pass over the calls the checker recorded going through a
/// trait, per `!` this walk reaches before it rewrites an operator.
fn holdsACallThroughATrait(ast: *const Ast, typing: *const Typing, operand: ExprId) bool {
    const within = ast.exprExtent(operand);
    for (typing.calls) |call| {
        const rec = call.selection.implementation orelse continue;
        if (!rec.ofATrait()) continue;
        if (call.at.index() >= ast.exprCount()) continue;
        const at = ast.exprExtent(call.at);
        if (at.start >= within.start and at.end <= within.end) return true;
    }
    return false;
}

/// Every declaration, last first.
///
/// A declaration is entered before any body is walked, so a name is visible to
/// every declaration whatever the order — which is exactly why the order is
/// free to be wrong somewhere else. It decides the order types enter the pool,
/// the order functions reach the backend, and the order diagnostics are
/// reported, and a program may observe none of those.
fn reverseDeclarations(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    text: []const u8,
) !?[]const u8 {
    const n = ast.declCount();
    if (n < 2) return null;

    // Except where the order is what decides which implementation a call
    // reaches, which is a program this rewrite has nothing to say about.
    if (try twoImplementationsForOneHead(gpa, ast, res)) return null;

    // A declaration the parser could not read has no boundary worth trusting,
    // and moving it would rewrite the program rather than reorder it.
    for (0..n) |i| {
        if (ast.declTag(DeclId.at(@intCast(i))) == .err) return null;
    }

    // Only what is written at the top level. A declaration inside a type lies
    // within its type's own extent, so emitting one beside the others would
    // write it twice and rewrite the program rather than reorder it.
    var top: u32 = 0;
    for (0..n) |i| {
        if (ast.declOwner(DeclId.at(@intCast(i))) == TokenId.none) top += 1;
    }
    if (top < 2) return null;

    var out: std.Io.Writer.Allocating = .init(gpa);
    var i = n;
    while (i > 0) {
        i -= 1;
        const d = DeclId.at(@intCast(i));
        if (ast.declOwner(d) != TokenId.none) continue;
        try out.writer.writeAll(ast.declSpan(d).slice(text));
        try out.writer.writeAll("\n\n");
    }
    return out.written();
}

/// Whether the program writes two implementations of one trait for one head.
///
/// Two of them are told apart by what each head applies, and a pair whose heads
/// both answer for one receiver is accepted: which of them a call reaches is
/// then decided by which was written first. Reversing the declarations of such
/// a program rewrites what it answers, so this rewrite must not claim one --
/// the premise every rewrite here rests on is that it cannot change what the
/// program means, and for this shape that premise does not hold.
///
/// Written for the pair rather than for the overlap, which is a question about
/// two heads that no pass answers. A pair that does not overlap is passed over
/// too, which loses coverage and never loses correctness.
///
/// By the declarations the two names reach and not by their spellings: a
/// re-exported trait is one trait under either name, and a rewrite comparing
/// text would hold a program it can change.
///
/// An inherent block declares its members by name, so two of them for one type
/// is a name declared twice rather than an order, and neither is passed over
/// here.
///
/// Public because the generator is held to the other side of the same
/// sentence: this rewrite says nothing about such a program, and the generator
/// writes none. Two readings of what the pair is would let the generator
/// manufacture the shape this passes over.
///
/// At least one of the pair has to declare type parameters. Two settled heads
/// over one constructor answer for one type each and no receiver reaches both,
/// so which was written first decides nothing — and declining those was
/// declining the programs whose subject is which implementation a reference
/// reaches, which are exactly the ones the rewrite has most to say about.
///
/// **Bound:** one pass over the declarations, and one entry per implementation
/// naming a trait.
pub fn twoImplementationsForOneHead(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
) !bool {
    // Whether some implementation already recorded under this key is open. The
    // flag rather than a count, because a third implementation is ambiguous
    // with the pair only if one of the three is open, and the order they are
    // walked in is not the order they were written.
    var seen: std.AutoHashMapUnmanaged(u64, bool) = .empty;
    defer seen.deinit(gpa);

    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) != .impl_) continue;
        const trait = ast.declTrait(d);
        if (trait == TokenId.none) continue;

        const open = ast.declTypeParams(d).len > 0;
        const key = (@as(u64, @intFromEnum(res.writtenAt(trait))) << 32) |
            @intFromEnum(res.writtenAt(ast.declName(d)));
        const gop = try seen.getOrPut(gpa, key);
        if (gop.found_existing) {
            if (open or gop.value_ptr.*) return true;
            continue;
        }
        gop.value_ptr.* = open;
    }
    return false;
}

/// Every trait's and every implementation's members, last first.
///
/// A member is named rather than positioned. Which signature an implementation
/// supplies is decided by the name the two share, and which type a settled
/// reference reaches is decided by what the implementation settled -- so a
/// compiler pairing members by position, or reading the first settled type for
/// every settled reference, answers with whichever it reaches first, and only a
/// reordering tells the difference.
///
/// The declarations of a program are in the order the parser finished them, so
/// a container comes *after* its own members. They are read in token order
/// here instead, where a container opens before everything it holds -- which
/// makes membership a running answer rather than a search of the declarations
/// per container.
fn reverseMembers(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    const n = ast.declCount();
    if (n < 2) return null;

    // A declaration the parser could not read has no boundary worth trusting,
    // and moving one would rewrite the program rather than reorder it.
    var order: std.ArrayList(DeclId) = .empty;
    defer order.deinit(gpa);
    for (0..n) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) == .err) return null;
        try order.append(gpa, d);
    }

    std.mem.sort(DeclId, order.items, ast, struct {
        fn before(tree: *const Ast, a: DeclId, b: DeclId) bool {
            return tree.declTokens(a).start.index() < tree.declTokens(b).start.index();
        }
    }.before);

    const Region = struct { start: u32, end: u32, written: []const u8 };
    var regions: std.ArrayList(Region) = .empty;
    defer regions.deinit(gpa);

    var members: std.ArrayList(DeclId) = .empty;
    defer members.deinit(gpa);

    var holding: ?DeclId = null;
    for (order.items) |d| {
        if (holding) |c| {
            const extent = ast.declTokens(c);
            if (ast.declTokens(d).start.index() < extent.end.index()) {
                try members.append(gpa, d);
                continue;
            }
            if (try memberRegion(gpa, ast, text, members.items)) |r| {
                try regions.append(gpa, .{ .start = r.start, .end = r.end, .written = r.written });
            }
            members.clearRetainingCapacity();
            holding = null;
        }
        switch (ast.declTag(d)) {
            .trait_, .impl_ => holding = d,
            else => {},
        }
    }
    if (holding != null) {
        if (try memberRegion(gpa, ast, text, members.items)) |r| {
            try regions.append(gpa, .{ .start = r.start, .end = r.end, .written = r.written });
        }
    }
    if (regions.items.len == 0) return null;

    var out: std.Io.Writer.Allocating = .init(gpa);
    var cursor: u32 = 0;
    for (regions.items) |r| {
        try out.writer.writeAll(text[cursor..r.start]);
        try out.writer.writeAll(r.written);
        cursor = r.end;
    }
    try out.writer.writeAll(text[cursor..]);
    return out.written();
}

/// The run one container's members occupy, and those members written back last
/// first, or null where there are too few to reorder.
///
/// Each is written from where its own first token stands, so what separates
/// two of them is written here rather than carried across: the text between
/// them holds the blank lines and the comments of whichever member they were
/// written above, and carrying that along would move a comment to a member it
/// was not written about.
fn memberRegion(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    text: []const u8,
    members: []const DeclId,
) !?struct { start: u32, end: u32, written: []const u8 } {
    if (members.len < 2) return null;

    const first = ast.declSpan(members[0]);
    const last = ast.declSpan(members[members.len - 1]);

    // What the first member is indented by, which is what the rest are written
    // under: the region begins at a member's first token, so the indentation
    // in front of it stays where it is and every later one needs its own.
    var line_start = first.start;
    while (line_start > 0 and text[line_start - 1] != '\n') line_start -= 1;
    const indent = text[line_start..first.start];

    var out: std.Io.Writer.Allocating = .init(gpa);
    var i = members.len;
    while (i > 0) {
        i -= 1;
        if (i + 1 != members.len) {
            try out.writer.writeAll("\n\n");
            try out.writer.writeAll(indent);
        }
        try out.writer.writeAll(ast.declSpan(members[i]).slice(text));
    }
    return .{ .start = first.start, .end = last.end, .written = out.written() };
}

/// Whether no value matches both patterns, as far as what they write shows:
/// two variants with different names, two integer literals with different
/// values, or two patterns of the same shape with some part apart. A range or
/// anything else the text does not settle answers no, which keeps a match
/// from being rotated rather than rotating one whose meaning would change.
fn patternsApart(ast: *const Ast, text: []const u8, a: ExprId, b: ExprId) bool {
    const ta = ast.exprTag(a);
    const tb = ast.exprTag(b);
    if (ast.partBinds(a) or ast.partBinds(b) or isCatchAll(ast, a) or isCatchAll(ast, b)) return false;
    if (literalInterval(ast, text, a)) |x| if (literalInterval(ast, text, b)) |y| return x[1] < y[0] or y[1] < x[0];
    const variant_a = ta == .name_ref or ta == .call;
    const variant_b = tb == .name_ref or tb == .call;
    if (variant_a and variant_b) {
        const name_a = ast.tokenText(ast.exprMain(a));
        const name_b = ast.tokenText(ast.exprMain(b));
        if (!std.mem.eql(u8, name_a, name_b)) return true;
        if (ta != .call or tb != .call) return false;
        return partsApart(ast, text, ast.call(a).args, ast.call(b).args);
    }
    if (ta == .tuple_pattern and tb == .tuple_pattern) return partsApart(ast, text, ast.call(a).args, ast.call(b).args);
    if (ta == .struct_pattern and tb == .struct_pattern) {
        var fa = ast.patternParts(a);
        while (fa.next()) |x| {
            var fb = ast.patternParts(b);
            while (fb.next()) |y| {
                if (!std.mem.eql(u8, ast.tokenText(ast.exprMain(x.label)), ast.tokenText(ast.exprMain(y.label)))) continue;
                if (patternsApart(ast, text, x.node, y.node)) return true;
            }
        }
    }
    return false;
}

/// The closed interval an integer literal or a range of integer literals
/// matches, or null where its text is anything else.
fn literalInterval(ast: *const Ast, text: []const u8, e: ExprId) ?[2]i128 {
    switch (ast.exprTag(e)) {
        .int_literal, .negate => {
            const v = literalValue(ast, text, e) orelse return null;
            return .{ v, v };
        },
        .range => {
            const ends = ast.rangeEnds(e);
            const lo = literalValue(ast, text, ends.lhs) orelse return null;
            const hi = literalValue(ast, text, ends.rhs) orelse return null;
            return .{ lo, if (ast.rangeInclusive(e)) hi else hi - 1 };
        },
        else => return null,
    }
}

fn literalValue(ast: *const Ast, text: []const u8, e: ExprId) ?i128 {
    if (ast.exprTag(e) == .negate) return -(literalValue(ast, text, ast.unaryOperand(e)) orelse return null);
    if (ast.exprTag(e) != .int_literal) return null;
    var digits: [64]u8 = undefined;
    var n: usize = 0;
    for (ast.exprSpan(e).slice(text)) |c| {
        if (c == '_') continue;
        if (n == digits.len) return null;
        digits[n] = c;
        n += 1;
    }
    return std.fmt.parseInt(i128, digits[0..n], 0) catch null;
}

/// Whether two lists of parts, taken position by position, hold a pair no
/// value matches both of.
fn partsApart(ast: *const Ast, text: []const u8, a: []const ExprId, b: []const ExprId) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (patternsApart(ast, text, x, y)) return true;
    }
    return false;
}

/// Adds every binder of a pattern, at any depth, to `into`.
fn putPatternBinders(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    into: *std.AutoHashMapUnmanaged(BindingId, void),
    pattern: ExprId,
) std.mem.Allocator.Error!void {
    var parts = ast.patternParts(pattern);
    while (parts.next()) |each| {
        const part = each.node;
        if (!ast.partBinds(part)) {
            try putPatternBinders(gpa, ast, res, into, part);
            continue;
        }
        const binding = res.targetOf(part);
        if (binding != .none and res.kindOf(binding) == .binder) try into.put(gpa, binding, {});
    }
}

fn rootedInReflection(ast: *const Ast, id: ExprId) bool {
    var at = id;
    while (true) switch (ast.exprTag(at)) {
        .field, .grouped => at = ast.unaryOperand(at),
        .call => at = ast.call(at).callee,
        else => return ast.exprTag(at) == .reflection_root,
    };
}

/// Every exhaustive `match`, with its last arm moved to the front.
///
/// An arm's pattern selects it, so an exhaustive cover of distinct patterns
/// answers the same whatever order the arms are written in. A compiler that
/// tests the wrong thing — the same tag for every arm, or the arm's position
/// instead of its pattern — answers with whichever arm it reaches first, and
/// only a reordering can tell the difference.
///
/// A `_` arm is excluded: it is defined to come last, so moving it to the
/// front is a different program rather than the same one rewritten. So is a
/// match whose arms are not shown apart by what they write: where one arm
/// takes a value another also takes, the first written answers, and moving it
/// changes which one does.
fn rotateMatchArms(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    const Region = struct { start: u32, end: u32, arms: []const u8 };

    var regions: std.ArrayList(Region) = .empty;
    defer regions.deinit(gpa);

    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (!ast.exprTag(id).isMatch()) continue;

        const args = ast.call(id).args;
        const count = args.len / 2;
        if (count < 2) continue;

        var eligible = true;
        for (0..count) |a| {
            const pattern = args[a * 2];
            if (isCatchAll(ast, pattern) or rootedInReflection(ast, pattern)) eligible = false;
            for (0..a) |b| {
                if (!patternsApart(ast, text, pattern, args[b * 2])) eligible = false;
            }
        }
        if (!eligible) continue;

        var arms: std.Io.Writer.Allocating = .init(gpa);
        for (0..count) |a| {
            // The last arm first, and every other arm one place later.
            const from = (a + count - 1) % count;
            if (a > 0) try arms.writer.writeAll(",\n");
            // By the extent rather than the span: a comment written after an
            // arm sits inside that arm's range, and writing it between two
            // rotated arms would comment out the comma that separates them.
            try arms.writer.print("{s} => {s}", .{
                ast.exprExtent(args[from * 2]).slice(text),
                ast.exprExtent(args[from * 2 + 1]).slice(text),
            });
        }

        try regions.append(gpa, .{
            .start = ast.exprSpan(args[0]).start,
            .end = ast.exprExtent(args[args.len - 1]).end,
            .arms = arms.written(),
        });
    }

    if (regions.items.len == 0) return null;

    std.mem.sort(Region, regions.items, {}, struct {
        fn lessThan(_: void, a: Region, b: Region) bool {
            return a.start < b.start;
        }
    }.lessThan);

    var out: std.Io.Writer.Allocating = .init(gpa);
    var cursor: u32 = 0;
    for (regions.items) |r| {
        // A match nested inside an arm sits within the region that arm belongs
        // to, and the outer rewrite carries it along. Rewriting both would
        // splice one region into the middle of the other.
        if (r.start < cursor) continue;
        try out.writer.writeAll(text[cursor..r.start]);
        try out.writer.writeAll(r.arms);
        cursor = r.end;
    }
    try out.writer.writeAll(text[cursor..]);
    return out.written();
}

/// Every call naming two or more parameters, with its last name moved to the
/// front of the names.
///
/// A named argument fills the parameter it names and arguments evaluate in the
/// callee's parameter order however the call spells them, so the order the
/// names are written in carries no meaning at all — which is the whole of what
/// makes them reorderable, and is exactly the claim nothing else checks. A
/// compiler pairing by position under a name, or evaluating in written order,
/// answers differently here and identically everywhere else.
///
/// The positional prefix is left where it is. Position is what says which
/// parameter those fill, so moving one writes a different call rather than the
/// same one spelled again.
fn permuteNamedArguments(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    typing: *const Typing,
    text: []const u8,
) !?[]const u8 {
    const Region = struct { start: u32, end: u32, args: []const u8 };

    var regions: std.ArrayList(Region) = .empty;
    defer regions.deinit(gpa);

    const calls = &typing.call_index;

    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        // A call and none of the six other tags that share its payload: a
        // name is a fact about a call's own syntax, so `callNames` answers
        // empty for a match's arms and a literal's fields and there is
        // nothing here to move them by. The tag says which it is.
        if (!ast.exprTag(id).namesArguments()) continue;
        // Which callable this reaches and whether its written names were
        // accepted are the checker's answers. A syntax-shaped call with no row
        // is not a call this meaning-preserving rewrite can claim.
        if (calls.callOf(typing, id) == null) continue;

        const names = ast.callNames(id);
        const args = ast.call(id).args;

        // The named arguments, which are a suffix: a positional argument
        // after a named one is [S-Args] and the program was refused, so the
        // longest run of names at the end is every name there is.
        var first = names.len;
        while (first > 0 and names[first - 1] != TokenId.none) first -= 1;
        const count = names.len - first;
        if (count < 2) continue;

        // By the extent rather than the span: a comment written after an
        // argument sits inside that argument's range, and moving it into the
        // middle of the list comments out every argument after it.
        const start = ast.tokenSpan(names[first]).start;
        const end = ast.exprExtent(args[args.len - 1]).end;

        // The tree is of the text handed in, which is what makes a span an
        // index into it. Stated rather than guarded around: a tree of some
        // other text has no extent here worth skipping, and cutting at one
        // would rewrite arbitrary bytes.
        std.debug.assert(end <= text.len);

        var out: std.Io.Writer.Allocating = .init(gpa);
        for (0..count) |a| {
            // The last name first, and every other one place later.
            const from = first + (a + count - 1) % count;
            if (a > 0) try out.writer.writeAll(", ");
            try out.writer.print("{s}: {s}", .{
                ast.tokenSpan(names[from]).slice(text),
                ast.exprExtent(args[from]).slice(text),
            });
        }

        try regions.append(gpa, .{ .start = start, .end = end, .args = out.written() });
    }

    if (regions.items.len == 0) return null;

    std.mem.sort(Region, regions.items, {}, struct {
        fn lessThan(_: void, a: Region, b: Region) bool {
            return a.start < b.start;
        }
    }.lessThan);

    var out: std.Io.Writer.Allocating = .init(gpa);
    var cursor: u32 = 0;
    for (regions.items) |r| {
        // A call written inside a named argument sits within the region that
        // argument belongs to, and the outer rewrite carries its text along.
        // Rewriting both would splice one region into the middle of the other.
        if (r.start < cursor) continue;
        try out.writer.writeAll(text[cursor..r.start]);
        try out.writer.writeAll(r.args);
        cursor = r.end;
    }
    try out.writer.writeAll(text[cursor..]);
    return out.written();
}

/// Every local and parameter given a name of its own.
///
/// A consistent renaming leaves a program saying exactly what it said, so this
/// holds whatever the original names were and however they shadowed. What it
/// disturbs is every place a later pass might have kept hold of a *name*: a
/// pass that re-resolves by string rather than through the handle the resolver
/// gave it answers differently once no two bindings share a spelling, which is
/// the same confusion between a name and the thing it denotes that the passes
/// have been wrong about before.
///
/// It does not catch a resolver that binds a use to the wrong declaration. The
/// rename is driven by that same answer, so an error in it is carried into the
/// rewrite and both programs agree. Catching that needs an invariant on
/// resolution itself rather than a rewrite of the source.
///
/// A name of its own means one per name the language lets move on its own. A
/// trait's signature and the members supplying it are held to one spelling for
/// each parameter, so those bindings take one new name between them -- read
/// from the server's answer about what a rename has to move, because a rename
/// that moved a different set would be a second reading of the rule that
/// refuses the result.
///
/// Both of those readings are of a tree of this file alone, and a file alone is
/// not the whole of the relation: a member may supply a signature another file
/// declares, and a call may reach a member through a type another file declares.
/// Where the tree cannot see a relation whole, the rename declines rather than
/// renaming the half it can see -- which is what `declines` decides, and why it
/// is decided before a single site is listed.
fn renameBindings(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    typing: *const Typing,
    text: []const u8,
) !?[]const u8 {
    // A fresh spelling has to be one the program does not already use. The
    // prefix is checked rather than assumed, because a collision would rename
    // two bindings to one name and quietly change what the program means.
    //
    // It begins with `_`, and that is load-bearing rather than a spelling
    // someone liked: a binding this rewrite renames may be one a body never
    // uses -- a member's parameter it ignores is obliged to be marked -- and a
    // new name without the marker would leave a program [N-Unused] refuses.
    // Every name written here carries one, so every such site keeps its mark.
    const prefix = "_zz";
    if (std.mem.indexOf(u8, text, prefix) != null) return null;

    const calls = &typing.call_index;
    var uses = try Uses.build(gpa, ast, res, typing, calls);
    defer uses.deinit(gpa);
    if (try declines(gpa, ast, typing)) return null;

    const Site = struct {
        start: u32,
        end: u32,
        to: u32,
        /// Whether this token is a field name as well as a binder.
        ///
        /// `S { f }` binds the field to its own name, and the parser records
        /// the field and the binder as two nodes over one token. Renaming that
        /// token renames the field with it, so what is written back is
        /// `f: _zz3` -- the form the shorthand abbreviates.
        shorthand: ?bool = null,
    };
    var sites: std.ArrayList(Site) = .empty;
    defer sites.deinit(gpa);

    // Template member parameters are paired by name with the trait's
    // signature, so renaming either half alone breaks the pairing. A template
    // impl is left as written: every binding declared inside one stays, and so
    // does every parameter spelled as one of its parameters, which is where
    // the trait's half is declared.
    var held = try std.DynamicBitSetUnmanaged.initEmpty(gpa, res.bindingCount());
    defer held.deinit(gpa);
    try holdTemplateBindings(gpa, ast, res, &held);

    // Shorthand captures and recovered fields each pair two binding identities.
    const CapturePair = struct { alias: BindingId, source: BindingId, initializer: bool = true };
    var capture_pairs: std.AutoHashMapUnmanaged(u32, CapturePair) = .empty;
    defer capture_pairs.deinit(gpa);

    // Shared field tokens, with true for construction and false for a pattern.
    var shorthand: std.AutoHashMapUnmanaged(u32, bool) = .empty;
    defer shorthand.deinit(gpa);
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        const kind = ast.exprTag(id);
        if (kind == .lambda) {
            const closure = res.closures.closureOf(id);
            if (closure == .none) continue;
            for (ast.lambda(id).captures, res.closureCaptures(closure)) |capture, resolved| {
                if (capture.equals != .none) continue;
                try capture_pairs.put(gpa, ast.tokenSpan(capture.name).start, .{
                    .alias = resolved.binding,
                    .source = res.targetOf(capture.source),
                });
            }
            continue;
        }
        if (kind != .struct_pattern and kind != .struct_literal) continue;
        const args = ast.call(id).args;
        var j: usize = 0;
        while (j + 1 < args.len) : (j += 2) {
            if (ast.fieldIsShorthand(args[j], args[j + 1])) {
                try shorthand.put(gpa, ast.tokenSpan(ast.exprMain(args[j])).start, kind == .struct_literal);
            }
        }
    }

    // The new spelling each binding takes, where that is not its own index: a
    // parameter a member declares takes the name the signature's parameter in
    // that position takes. Only those are in the table, so a program with no
    // implementation in it allocates nothing here.
    //
    // Asked once per parameter of each signature, and never from a member's
    // side. The group is the same however it is reached, so asking it from
    // every parameter in turn rebuilt each group once per member of it -- a
    // walk of the implementations inside a walk of their parameters, which is
    // quadratic in the implementations of one trait and reads as correct.
    //
    // **Bound:** one run of the record per signature, and one entry per
    // parameter an implementation declares -- which is the size of the table.
    // The declarations are walked once to find the signatures; nothing is
    // walked per binding.
    var alike: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer alike.deinit(gpa);

    for (0..ast.declCount()) |i| {
        if (typing.supply_index.membersOf(node.DeclId.at(@intCast(i))).len == 0) continue;
        for (res.parametersOf(DeclId.at(@intCast(i)))) |p| {
            const group = try references.parametersAlike(gpa, ast, res, &typing.supply_index, p);
            defer gpa.free(group);
            for (group) |g| {
                if (g == p) continue;
                try alike.put(gpa, @intCast(g.index()), @intCast(p.index()));
            }
        }
    }

    for (0..res.bindingCount()) |i| {
        const b = BindingId.at(@intCast(i));
        if (!renamesBinding(res.kindOf(b)) or held.isSet(i)) continue;
        // A pattern binder's declaration is also a recorded use below.
        if (res.kindOf(b) == .binder) continue;
        const declaring = res.declaringToken(b);
        if (declaring == .none or declaring.index() >= ast.tokenCount()) continue;
        const span = ast.tokenSpan(declaring);
        try sites.append(gpa, .{
            .start = span.start,
            .end = span.end,
            .to = @intCast(i),
            .shorthand = shorthand.get(span.start),
        });
    }

    // Declaration sites, expression uses, contract roots and direct named
    // arguments all follow the same binding relation. The index combines the
    // resolver's and checker's answers once; this rewrite only reads it back.
    for (0..res.bindingCount()) |i| {
        const b = BindingId.at(@intCast(i));
        if (!renamesBinding(res.kindOf(b)) or held.isSet(i)) continue;
        for (uses.of(b)) |token| {
            if (token.index() >= ast.tokenCount()) continue;
            const at = ast.tokenSpan(token);
            try sites.append(gpa, .{
                .start = at.start,
                .end = at.end,
                .to = b.index(),
                .shorthand = shorthand.get(at.start),
            });
        }
        if (res.kindOf(b) == .capture) for (uses.sourceNameSites(res.declaringToken(b))) |token| {
            if (token.index() >= ast.tokenCount()) continue;
            const at = ast.tokenSpan(token);
            try sites.append(gpa, .{ .start = at.start, .end = at.end, .to = b.index() });
            const local = uses.declaredAt(token);
            if (local != .none and res.bindsAFieldByItsOwnName(local)) {
                try capture_pairs.put(gpa, at.start, .{ .alias = b, .source = local, .initializer = false });
            }
        };
        for (uses.writtenOf(b)) |token| {
            if (token.index() >= ast.tokenCount()) continue;
            const at = ast.tokenSpan(token);
            try sites.append(gpa, .{ .start = at.start, .end = at.end, .to = b.index() });
        }
    }

    if (sites.items.len == 0) return null;

    std.mem.sort(Site, sites.items, {}, struct {
        fn lessThan(_: void, a: Site, b: Site) bool {
            return a.start < b.start;
        }
    }.lessThan);

    var out: std.Io.Writer.Allocating = .init(gpa);
    var cursor: u32 = 0;
    for (sites.items) |s| {
        // A capture alias and its source share one token; their paired entry
        // supplies both spellings. Repeated interface sites also write once.
        if (s.start < cursor) continue;
        try out.writer.writeAll(text[cursor..s.start]);
        if (capture_pairs.get(s.start)) |pair| {
            try out.writer.print(prefix ++ "{d}{s}", .{ alike.get(pair.alias.index()) orelse pair.alias.index(), if (pair.initializer) " = " else ": " });
            const rename_source = pair.source != .none and renamesBinding(res.kindOf(pair.source));
            if (rename_source) {
                const source_group = alike.get(pair.source.index()) orelse pair.source.index();
                try out.writer.print(prefix ++ "{d}", .{source_group});
            } else {
                try out.writer.writeAll(text[s.start..s.end]);
            }
        } else {
            if (s.shorthand) |initializer| try out.writer.print("{s}{s}", .{ text[s.start..s.end], if (initializer) " = " else ": " });
            try out.writer.print(prefix ++ "{d}", .{alike.get(s.to) orelse s.to});
        }
        cursor = s.end;
    }
    try out.writer.writeAll(text[cursor..]);
    return out.written();
}

/// Marks every binding a template impl declares, then every parameter spelled
/// as any name the impl writes, which is where the trait's signature, or a
/// callable type the impl names a parameter in, declares the other half of a
/// pairing by name. A leading `_` marks a parameter unused without changing
/// which parameter it pairs with, so names are compared without it.
///
/// **Bound:** one pass over the tokens of the template impls and one over the
/// bindings, each binding answered by a lookup.
fn holdTemplateBindings(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    held: *std.DynamicBitSetUnmanaged,
) !void {
    var inside = try std.DynamicBitSetUnmanaged.initEmpty(gpa, ast.tokenCount());
    defer inside.deinit(gpa);
    var names: std.StringHashMapUnmanaged(void) = .empty;
    defer names.deinit(gpa);
    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) != .template_impl) continue;
        var tokens = ast.runOf(ast.declTokens(d));
        while (tokens.next()) |token| {
            inside.set(token.index());
            try names.put(gpa, std.mem.trimStart(u8, ast.tokenText(token), "_"), {});
        }
    }
    if (names.count() == 0) return;

    for (0..res.bindingCount()) |i| {
        const b = BindingId.at(@intCast(i));
        if (!renamesBinding(res.kindOf(b))) continue;
        const declaring = res.declaringToken(b);
        if (declaring == .none or declaring.index() >= ast.tokenCount()) continue;
        if (inside.isSet(declaring.index()) or
            (res.kindOf(b) == .parameter and names.contains(std.mem.trimStart(u8, ast.tokenText(declaring), "_"))))
            held.set(i);
    }
}

fn renamesBinding(kind: resolve_mod.Kind) bool {
    return switch (kind) {
        .local, .parameter, .capture, .binder => true,
        .constant, .function, .declared_type, .builtin_type, .trait, .module, .associated_type, .type_parameter, .type_alias => false,
    };
}

/// Whether the rename must decline this program: whether some relation it would
/// have to move lives partly outside the tree it was handed.
///
/// The tree is of one file, and two of the relations the rename moves reach
/// past a file. A member supplies a signature, and the signature may be
/// declared in another one: the parameters are then held to a single spelling
/// by a declaration this tree does not hold, so renaming the member's half
/// alone writes a program [T-Impl] refuses. An argument names a parameter, and
/// which parameter it names is the checker's answer: a call this tree could not
/// settle records no answer, so renaming the parameter's declaration leaves the
/// written name standing and writes a program [T-UnknownParameter] refuses.
///
/// Declining rather than guessing, and asked of what the rename reads rather
/// than of the source. Filling either gap here -- pairing a member with a
/// signature by spelling, pairing an argument with a parameter by spelling --
/// would be a second matcher beside the checker's, and it would answer for
/// exactly the programs this cannot see.
///
/// **Bound:** one pass over the bounds, one over the declarations, one over the
/// expressions, and one over the rows the checker recorded. An `impl`'s members
/// are reached through the index the checker pairs them with. The blocks have
/// disjoint extents, so no declaration is visited by more than one of them.
fn declines(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    typing: *const Typing,
) !bool {
    var index = try DeclIndex.build(gpa, ast);
    defer index.deinit(gpa);

    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) != .impl_) continue;
        // An inherent block supplies nothing and is held to nothing: its
        // members' parameters are named by this file and by no other, which is
        // exactly what the rename is free to move.
        if (ast.declTrait(d) == TokenId.none) continue;
        for (index.within(ast.declTokens(d))) |m| {
            if (m == d) continue;
            // A projection's parameters are held to a signature's exactly as a
            // function's are, so the same half-seen relation is the same
            // refusal to rename: the trait `Index` is another file's, and a
            // receiver renamed here alone no longer names what it supplies.
            switch (ast.declTag(m)) {
                .function, .projection => {},
                else => continue,
            }
            if (typing.supply_index.signatureOf(m) == null) return true;
        }
    }

    // The name each written argument was paired with, by the token that wrote
    // it. A call the tree could settle records one row per name it wrote, so a
    // name missing from these is a name whose parameter this tree never found.
    var paired: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer paired.deinit(gpa);
    try paired.ensureTotalCapacity(gpa, @intCast(typing.named.len));
    for (typing.named) |n| paired.putAssumeCapacity(n.name.index(), {});

    for (0..ast.exprCount()) |i| {
        for (ast.callNames(ExprId.at(@intCast(i)))) |t| {
            if (t == TokenId.none) continue;
            if (!paired.contains(t.index())) return true;
        }
    }

    // A closure's captures are recovered as a record whose fields are named by
    // its capture aliases, so renaming an alias renames those fields, and the
    // rename follows the checker's pairing of each recovered field with its
    // alias. A recovery this tree could not settle -- the closure captures a
    // value whose type another file declares -- pairs nothing, and renaming
    // the alias alone leaves a field [T-UnknownField] refuses. Declining
    // costs the whole file its rename; pairing from the program's full
    // semantics, as the postfix rewrite reads them, would keep the rest.
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .call) continue;
        const callee = ast.call(id).callee;
        if (ast.exprTag(callee) != .field) continue;
        if (!std.mem.eql(u8, ast.tokenText(ast.exprMain(callee)), "into_captures")) continue;
        const settled = typing.call_index.callOf(typing, id) orelse return true;
        if (settled.target != .closure_recovery) return true;
    }

    return false;
}

/// Where a field's written type ends, arguments included.
///
/// A generic type is written as a name and a bracketed run, and the name is
/// one token: moving a field by the name's extent alone leaves the arguments
/// where they were and writes a template where a type belonged.
///
/// Read from the tree rather than found by matching brackets. A second walker
/// over the tokens would be a second reader of the grammar, and one that has
/// to be taught every shape a type later grows -- an argument list that wraps,
/// a bound written inside the brackets, anything at all after the name.
fn endOfWrittenType(ast: *const Ast, f: node.Field) u32 {
    const end = if (f.type_end == .none) f.written.name else f.type_end;
    return ast.tokenSpan(end).end;
}

/// Property: reordering a structure's fields cannot change what a program
/// computes.
///
/// A field is reached by naming it, so where it sits is the compiler's to
/// decide -- and deciding differently must not change an answer. That is what
/// catches an offset read from a fixed position rather than from the field's
/// own, which is the shape of mistake layout code makes.
///
/// One structure's fields move, not every structure's. Reversing them all
/// would still be one arrangement, and two arrangements is the whole of what
/// this compares.
fn reorderFields(gpa: std.mem.Allocator, ast: *const Ast, text: []const u8) !?[]const u8 {
    // A structural derive makes declaration order observable through its
    // component sequence. Only a structure a derive names is reflected over,
    // and the loop below leaves each of those where it is.
    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) != .struct_) continue;
        if (ast.deriveTraits(d).len != 0) continue;

        const fields = ast.declFields(d);
        if (fields.len < 2) continue;

        const name = ast.declName(d);
        var structurally_observed = false;
        for (0..ast.declCount()) |j| {
            const derive = DeclId.at(@intCast(j));
            if (ast.declTag(derive) != .derive_impl) continue;
            const head = ast.declHead(derive);
            if (head.name == .none or name == .none) continue;
            if (!std.mem.eql(u8, ast.tokenText(head.name), ast.tokenText(name))) continue;
            structurally_observed = true;
            break;
        }
        if (structurally_observed) continue;

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);

        // Each field runs from its name to the end of its type; what sits
        // between them is a comma and whatever spacing was written, and that
        // is what the rewrite replaces rather than preserves.
        const first = ast.tokenSpan(fields[0].name).start;
        const last = endOfWrittenType(ast, fields[fields.len - 1]);
        try out.appendSlice(gpa, text[0..first]);

        var k = fields.len;
        while (k > 0) {
            k -= 1;
            if (k + 1 != fields.len) try out.appendSlice(gpa, ", ");
            const from = ast.tokenSpan(fields[k].name).start;
            const to = endOfWrittenType(ast, fields[k]);
            try out.appendSlice(gpa, text[from..to]);
        }

        try out.appendSlice(gpa, text[last..]);
        return try out.toOwnedSlice(gpa);
    }
    return null;
}

fn parseText(gpa: std.mem.Allocator, text: []const u8) !Ast {
    const source: Source = .{ .path = "transform.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    return parse(gpa, &source, .from(0), tokens, &sink);
}

fn applyTo(gpa: std.mem.Allocator, t: Transform, text: []const u8) !?[]const u8 {
    var ast = try parseText(gpa, text);
    var sink = Sink.init(gpa);
    var res = try resolveTree(gpa, &ast, &sink);
    const types_of = try typecheckTree(gpa, &res, &sink);

    if (t == .postfix_written_out) {
        var full_sink = Sink.init(gpa);
        var interner: Interner = .empty;
        var table: FileTable = .empty;
        const one = [_]loader.InMemoryFile{.{ .path = "transform.lin", .text = text }};
        var program = try loader.loadFromMemory(gpa, &table, &full_sink, &interner, "transform.lin", &one, .program, true, .borrow);
        const resolved = try resolve(gpa, &program, &interner, &full_sink, .program);
        var expanded = resolved.expanded;
        defer expanded.deinit(gpa);
        var full_res = resolved.resolution;
        defer full_res.deinit(gpa);
        var full_typing = try typecheck(gpa, &expanded, &full_res, &full_sink);
        defer full_typing.deinit(gpa);
        if (full_sink.hasErrors()) return null;
        return t.apply(gpa, &ast, &res.resolution, &types_of, .{
            .ast = &expanded.ast,
            .program = &program,
            .res = &full_res,
            .typing = &full_typing,
            .file = program.primaryFile(),
        }, text);
    }

    return t.apply(gpa, &ast, &res.resolution, &types_of, .{
        .ast = &ast,
        .program = res.source,
        .res = &res.resolution,
        .typing = &types_of,
        .file = ast.firstFile(),
    }, text);
}

test "materialized derives are ordinary source files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text =
        \\trait Mark {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\template impl Mark {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\struct Target {}
        \\derive Mark for Target
        \\fn main() -> UInt8 {
        \\    let target: Target = .{}
        \\    Mark.value(target)
        \\}
    ;
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const files = [_]loader.InMemoryFile{.{ .path = "app/main.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "app", &files, .program, true, .borrow);
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var resolution = resolved.resolution;
    defer resolution.deinit(gpa);
    try testing.expect(!sink.hasErrors());

    var materialized = (try materializeDerives(gpa, &program, &expanded, &resolution)).?;
    defer materialized.deinit(gpa);
    try testing.expectEqual(@as(usize, 2), materialized.files.len);
    try testing.expect(std.mem.indexOf(u8, materialized.files[0].text, "derive Mark for Target") == null);
    try testing.expect(std.mem.indexOf(u8, materialized.files[1].text, "impl Mark") != null);
    try testing.expect(std.mem.indexOf(u8, materialized.files[1].text, "for Target") != null);

    var materialized_table: FileTable = .empty;
    var materialized_sink = Sink.init(gpa);
    var materialized_interner: Interner = .empty;
    var materialized_program = try loader.loadFromMemory(
        gpa,
        &materialized_table,
        &materialized_sink,
        &materialized_interner,
        "app",
        materialized.files,
        .program,
        true,
        .borrow,
    );
    const materialized_resolved = try resolve(
        gpa,
        &materialized_program,
        &materialized_interner,
        &materialized_sink,
        .program,
    );
    var materialized_expanded = materialized_resolved.expanded;
    defer materialized_expanded.deinit(gpa);
    var materialized_resolution = materialized_resolved.resolution;
    defer materialized_resolution.deinit(gpa);
    var materialized_typing = try typecheck(
        gpa,
        &materialized_expanded,
        &materialized_resolution,
        &materialized_sink,
    );
    defer materialized_typing.deinit(gpa);
    try testing.expect(!materialized_sink.hasErrors());
}

test "materialized declaration attributes preserve types policies and comments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\import std.cmp as laws
        \\
        \\@(
        \\    opaque,
        \\    copyable,
        \\    derive(
        \\        laws.Equatable,
        \\        // equality law
        \\        laws.Equivalent,
        \\    ),
        \\)
        \\@derive(
        \\    // diagnostic shape
        \\    Debug,
        \\)
        \\struct Target { value: UInt8 }
        \\
        \\fn main() -> UInt8 {
        \\    let one = Target { value = 7 }
        \\    let two = copy(one)
        \\    if one == two { 0 } else { 1 }
        \\}
    ;
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const files = [_]loader.InMemoryFile{.{ .path = "app/main.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "app", &files, .program, true, .borrow);
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var resolution = resolved.resolution;
    defer resolution.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &resolution, &sink);
    defer typing.deinit(gpa);
    try testing.expect(!sink.hasErrors());

    var materialized = (try materializeDerives(gpa, &program, &expanded, &resolution)).?;
    defer materialized.deinit(gpa);
    const source = materialized.files[0].text;
    try testing.expect(std.mem.indexOf(u8, source, "struct Target") != null);
    try testing.expect(std.mem.indexOf(u8, source, "opaque") != null);
    try testing.expect(std.mem.indexOf(u8, source, "copyable") != null);
    try testing.expect(std.mem.indexOf(u8, source, "equality law") != null);
    try testing.expect(std.mem.indexOf(u8, source, "diagnostic shape") != null);
    try testing.expect(std.mem.indexOf(u8, source, "derive") == null);
    try testing.expect(std.mem.indexOf(u8, source, "import std.cmp as laws") == null);

    var materialized_table: FileTable = .empty;
    var materialized_sink = Sink.init(gpa);
    var materialized_interner: Interner = .empty;
    var materialized_program = try loader.loadFromMemory(
        gpa,
        &materialized_table,
        &materialized_sink,
        &materialized_interner,
        "app",
        materialized.files,
        .program,
        true,
        .borrow,
    );
    const materialized_resolved = try resolve(gpa, &materialized_program, &materialized_interner, &materialized_sink, .program);
    var materialized_expanded = materialized_resolved.expanded;
    defer materialized_expanded.deinit(gpa);
    var materialized_resolution = materialized_resolved.resolution;
    defer materialized_resolution.deinit(gpa);
    var materialized_typing = try typecheck(gpa, &materialized_expanded, &materialized_resolution, &materialized_sink);
    defer materialized_typing.deinit(gpa);
    try testing.expect(!materialized_sink.hasErrors());
}

test "materialized attributes remove derives inside formatting escape hatches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\import std.cmp as laws
        \\
        \\@(
        \\    opaque,
        \\    copyable,
        \\    derive(
        \\        // linea fmt: off
        \\        laws.Equatable,
        \\        // equality law
        \\        laws.Equivalent,
        \\        // linea fmt: on
        \\    ),
        \\)
        \\@derive(
        \\    // diagnostic shape
        \\    Debug,
        \\)
        \\struct Target { value: UInt8 }
        \\
        \\fn main() -> UInt8 {
        \\    let one = Target { value = 7 }
        \\    let two = copy(one)
        \\    if one == two { 0 } else { 1 }
        \\}
    ;
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const files = [_]loader.InMemoryFile{.{ .path = "app/main.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "app", &files, .program, true, .borrow);
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var resolution = resolved.resolution;
    defer resolution.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &resolution, &sink);
    defer typing.deinit(gpa);
    try testing.expect(!sink.hasErrors());

    var materialized = (try materializeDerives(gpa, &program, &expanded, &resolution)).?;
    defer materialized.deinit(gpa);
    const source = materialized.files[0].text;
    try testing.expect(std.mem.indexOf(u8, source, "struct Target") != null);
    try testing.expect(std.mem.indexOf(u8, source, "opaque") != null);
    try testing.expect(std.mem.indexOf(u8, source, "copyable") != null);
    try testing.expect(std.mem.indexOf(u8, source, "equality law") != null);
    try testing.expect(std.mem.indexOf(u8, source, "diagnostic shape") != null);
    try testing.expect(std.mem.indexOf(u8, source, "derive") == null);
    try testing.expect(std.mem.indexOf(u8, source, "import std.cmp as laws") == null);

    var materialized_table: FileTable = .empty;
    var materialized_sink = Sink.init(gpa);
    var materialized_interner: Interner = .empty;
    var materialized_program = try loader.loadFromMemory(
        gpa,
        &materialized_table,
        &materialized_sink,
        &materialized_interner,
        "app",
        materialized.files,
        .program,
        true,
        .borrow,
    );
    const materialized_resolved = try resolve(gpa, &materialized_program, &materialized_interner, &materialized_sink, .program);
    var materialized_expanded = materialized_resolved.expanded;
    defer materialized_expanded.deinit(gpa);
    var materialized_resolution = materialized_resolved.resolution;
    defer materialized_resolution.deinit(gpa);
    var materialized_typing = try typecheck(gpa, &materialized_expanded, &materialized_resolution, &materialized_sink);
    defer materialized_typing.deinit(gpa);
    try testing.expect(!materialized_sink.hasErrors());
}

test "materialized attributes remove derive-only aliases and keep nominal type imports" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\import std.cmp as laws
        \\use laws.Equivalent
        \\import std.fmt as formatting
        \\import std.option as choices
        \\@derive(laws.Equatable, Equivalent, formatting.Debug)
        \\struct Target { value: choices.Option[UInt8] }
        \\fn main() -> UInt8 {
        \\    let laws: UInt8 = 0
        \\    let _target = Target { value = .Some(7) }
        \\    laws
        \\}
    ;
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const files = [_]loader.InMemoryFile{.{ .path = "app/main.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "app", &files, .program, true, .borrow);
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var resolution = resolved.resolution;
    defer resolution.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &resolution, &sink);
    defer typing.deinit(gpa);
    try testing.expect(!sink.hasErrors());

    var materialized = (try materializeDerives(gpa, &program, &expanded, &resolution)).?;
    defer materialized.deinit(gpa);
    const source = materialized.files[0].text;
    try testing.expect(std.mem.indexOf(u8, source, "import std.cmp as laws") != null);
    try testing.expect(std.mem.indexOf(u8, source, "use laws.Equivalent") != null);
    try testing.expect(std.mem.indexOf(u8, source, "import std.fmt as formatting") == null);
    try testing.expect(std.mem.indexOf(u8, source, "import std.option as choices") != null);
    try testing.expect(std.mem.indexOf(u8, source, "choices.Option[UInt8]") != null);
    try testing.expect(std.mem.indexOf(u8, source, "struct Target") != null);

    var materialized_table: FileTable = .empty;
    var materialized_sink = Sink.init(gpa);
    var materialized_interner: Interner = .empty;
    var materialized_program = try loader.loadFromMemory(
        gpa,
        &materialized_table,
        &materialized_sink,
        &materialized_interner,
        "app",
        materialized.files,
        .program,
        true,
        .borrow,
    );
    const materialized_resolved = try resolve(gpa, &materialized_program, &materialized_interner, &materialized_sink, .program);
    var materialized_expanded = materialized_resolved.expanded;
    defer materialized_expanded.deinit(gpa);
    var materialized_resolution = materialized_resolved.resolution;
    defer materialized_resolution.deinit(gpa);
    var materialized_typing = try typecheck(gpa, &materialized_expanded, &materialized_resolution, &materialized_sink);
    defer materialized_typing.deinit(gpa);
    try testing.expect(!materialized_sink.hasErrors());
}

test "materialized attributes preserve trait imports used by postfix calls" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\import std.hash
        \\use hash.Hash
        \\@derive(Equatable, Equivalent, Hash)
        \\struct Ticket { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let ticket = Ticket { value = 7 }
        \\    UInt8(ticket.hash() % 2)
        \\}
    ;
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const files = [_]loader.InMemoryFile{.{ .path = "app/main.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "app", &files, .program, true, .borrow);
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var resolution = resolved.resolution;
    defer resolution.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &resolution, &sink);
    defer typing.deinit(gpa);
    try testing.expect(!sink.hasErrors());

    var materialized = (try materializeDerives(gpa, &program, &expanded, &resolution)).?;
    defer materialized.deinit(gpa);
    var materialized_table: FileTable = .empty;
    var materialized_sink = Sink.init(gpa);
    var materialized_interner: Interner = .empty;
    var materialized_program = try loader.loadFromMemory(
        gpa,
        &materialized_table,
        &materialized_sink,
        &materialized_interner,
        "app",
        materialized.files,
        .program,
        true,
        .borrow,
    );
    const materialized_resolved = try resolve(gpa, &materialized_program, &materialized_interner, &materialized_sink, .program);
    var materialized_expanded = materialized_resolved.expanded;
    defer materialized_expanded.deinit(gpa);
    var materialized_resolution = materialized_resolved.resolution;
    defer materialized_resolution.deinit(gpa);
    var materialized_typing = try typecheck(gpa, &materialized_expanded, &materialized_resolution, &materialized_sink);
    defer materialized_typing.deinit(gpa);
    try testing.expect(!materialized_sink.hasErrors());
}

test "reversing puts the last declaration first" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .reversed_declarations,
        \\fn one() -> UInt8 { 1 }
        \\
        \\fn two() -> UInt8 { 2 }
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "fn two").? < std.mem.indexOf(u8, got, "fn one").?);
}

test "reversing preserves a context-selected function value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .reversed_declarations,
        \\fn increment(value: UInt8) -> UInt8 { value }
        \\
        \\fn main() -> UInt8 {
        \\    let selected: fn(read value: UInt8) -> UInt8 = increment
        \\    selected(value: 2)
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "fn main").? < std.mem.indexOf(u8, got, "fn increment").?);

    var ast = try parseText(gpa, got);
    var sink = Sink.init(gpa);
    var res = try resolveTree(gpa, &ast, &sink);
    _ = try typecheckTree(gpa, &res, &sink);
    try testing.expect(!sink.hasErrors());
}

test "reversing a program of one declaration says nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(
        @as(?[]const u8, null),
        try applyTo(arena.allocator(), .reversed_declarations, "fn main() -> UInt8 { 1 }\n"),
    );
}

test "reversing says nothing about two implementations of one trait for one head" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Both heads answer for a `Holder[Bool]`, and which body the call runs is
    // decided by which was written first -- so the two orders of this program
    // are two programs, and the rewrite claims neither.
    try testing.expectEqual(@as(?[]const u8, null), try applyTo(arena.allocator(), .reversed_declarations,
        \\trait Give[U] { fn give(self: Self, u: U) -> UInt8 }
        \\
        \\struct Pair[A: Discardable, B: Discardable] { a: A, b: B }
        \\
        \\struct Holder[T: Discardable] { v: T }
        \\
        \\impl[T: Discardable] Give[Pair[T, T]] for Holder[T] {
        \\    fn give(_self: Self, _u: Pair[T, T]) -> UInt8 { 1 }
        \\}
        \\
        \\impl[T: Discardable] Give[Pair[T, Bool]] for Holder[T] {
        \\    fn give(_self: Self, _u: Pair[T, Bool]) -> UInt8 { 2 }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let h: Holder[Bool] = .{ v = true }
        \\    let p: Pair[Bool, Bool] = .{ a = true, b = false }
        \\    Give.give(h, p)
        \\}
        \\
    ));
}

test "reversing still moves two settled implementations over one constructor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Neither head is open, so each answers for exactly one type and no
    // receiver reaches both. Which was written first decides nothing, and the
    // rewrite claims the program.
    const got = (try applyTo(gpa, .reversed_declarations,
        \\trait Held { fn held(self: Self) -> UInt8 }
        \\
        \\struct Holder[T: Discardable] { v: T }
        \\
        \\impl Held for Holder[UInt8] { fn held(self: Self) -> UInt8 { self.v } }
        \\
        \\impl Held for Holder[Bool] { fn held(_self: Self) -> UInt8 { 2 } }
        \\
        \\fn main() -> UInt8 {
        \\    let a: Holder[UInt8] = .{ v = 1 }
        \\    Held.held(a)
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "for Holder[Bool]").? < std.mem.indexOf(u8, got, "for Holder[UInt8]").?);
}

test "reversing still moves two implementations of one trait for two heads" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .reversed_declarations,
        \\trait Held { fn held(self: Self) -> UInt8 }
        \\
        \\struct One { n: UInt8 }
        \\
        \\struct Two { n: UInt8 }
        \\
        \\impl Held for One { fn held(self: One) -> UInt8 { self.n } }
        \\
        \\impl Held for Two { fn held(self: Two) -> UInt8 { self.n } }
        \\
        \\fn main() -> UInt8 {
        \\    let a: One = .{ n = 1 }
        \\    Held.held(a)
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "for Two").? < std.mem.indexOf(u8, got, "for One").?);
}

test "a reversed program still parses to the same declarations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text =
        \\enum Shape { Circle, Square }
        \\
        \\fn pick() -> UInt8 { 7 }
        \\
        \\fn main() -> UInt8 { pick() }
        \\
    ;
    const got = (try applyTo(gpa, .reversed_declarations, text)).?;

    var before = try parseText(gpa, text);
    var after = try parseText(gpa, got);
    try testing.expectEqual(before.declCount(), after.declCount());
}

test "rotating moves the last arm to the front" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .rotated_match_arms,
        \\enum Shape { Circle, Square }
        \\
        \\fn main() -> UInt8 {
        \\    match Shape.Circle {
        \\        Circle => 1,
        \\        Square => 2,
        \\    }
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "Square => 2").? <
        std.mem.indexOf(u8, got, "Circle => 1").?);
}

test "a match with a wildcard arm is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(?[]const u8, null), try applyTo(arena.allocator(), .rotated_match_arms,
        \\enum Shape { Circle, Square }
        \\
        \\fn main() -> UInt8 {
        \\    match Shape.Circle {
        \\        Circle => 1,
        \\        _ => 2,
        \\    }
        \\}
        \\
    ));
}

test "reflected match arms retain their required order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(?[]const u8, null), try applyTo(arena.allocator(), .rotated_match_arms,
        \\trait Structural { fn same(self: Self, other: Self) -> Bool }
        \\template impl Structural {
        \\    fn same(self: Self, other: Self) -> Bool {
        \\        match read self {
        \\            reflect.case => match read other {
        \\                reflect.same_case => true,
        \\                reflect.other_case => false,
        \\            },
        \\        }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
        \\
    ));
}

test "a program with no match says nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(
        @as(?[]const u8, null),
        try applyTo(arena.allocator(), .rotated_match_arms, "fn main() -> UInt8 { 1 }\n"),
    );
}

test "renaming replaces a binding and every use of it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .renamed_bindings,
        \\fn main() -> UInt8 {
        \\    let total: UInt8 = 1;
        \\    total
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "total") == null);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, "_zz"));
}

test "borrow contract renaming preserves roots with unresolved imported types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = (try applyTo(arena.allocator(), .renamed_bindings,
        \\import std.mem
        \\fn _observe(owner: mem.Arena[mem.SystemAllocator]) -> borrow mem.Arena[mem.SystemAllocator] where borrows(owner) {
        \\    borrow owner
        \\}
        \\fn main() -> UInt8 { 0 }
    )).?;
    try testing.expect(std.mem.indexOf(u8, got, "owner") == null);
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, got, "_zz"));
}

test "renaming leaves a template impl as written and renames the rest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source =
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 {
        \\        let generated: UInt8 = 7
        \\        generated
        \\    }
        \\}
        \\struct Mark { value: UInt8 }
        \\derive Structural for Mark
        \\fn main() -> UInt8 {
        \\    let mark: Mark = .{ value = 1 }
        \\    Structural.value(mark)
        \\}
    ;
    const got = (try applyTo(gpa, .renamed_bindings, source)).?;
    try testing.expect(std.mem.indexOf(u8, got, "let generated: UInt8 = 7") != null);
    try testing.expect(std.mem.indexOf(u8, got, "fn value(_self: Self)") != null);
    try testing.expect(std.mem.indexOf(u8, got, "trait Structural { fn value(self: Self)") != null);
    try testing.expect(std.mem.indexOf(u8, got, "let mark") == null);
    try testing.expectEqual(@as(?[]const u8, null), try applyTo(gpa, .renamed_head_parameters, source));
}

test "shadowed bindings are told apart" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The inner and outer `x` are different bindings, so a consistent renaming
    // gives them different names -- and the program still answers 1, because
    // the tail is outside the block the inner one belongs to.
    const got = (try applyTo(gpa, .renamed_bindings,
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1;
        \\    if true {
        \\        let x: UInt8 = 2;
        \\        let _ = x;
        \\    }
        \\    x
        \\}
        \\
    )).?;

    // Two declarations, two uses, and the discard -- `_` binds too, and the
    // name it is given still begins with `_`, so it stays deliberately unused.
    // The two `x` bindings do not share a name: the tail is the outer one, and
    // the use inside the block is the inner.
    try testing.expectEqual(@as(usize, 5), std.mem.count(u8, got, "_zz"));

    const outer = nameAfter(got, "let ").?;
    const inner = nameAfter(got[std.mem.indexOf(u8, got, "if true").?..], "let ").?;
    try testing.expect(!std.mem.eql(u8, outer, inner));
    try testing.expectEqualStrings(outer, nameAfter(got, "    }\n    ").?);
}

/// The `_zz…` name beginning just after `needle`.
fn nameAfter(text: []const u8, needle: []const u8) ?[]const u8 {
    const at = (std.mem.indexOf(u8, text, needle) orelse return null) + needle.len;
    var end = at;
    while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1;
    return text[at..end];
}

test "a parameter is renamed with its uses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .renamed_bindings,
        \\fn double(n: UInt8) -> UInt8 { n + n }
        \\
        \\fn main() -> UInt8 { double(3) }
        \\
    )).?;

    // The function keeps its name; the parameter and both uses of it change.
    try testing.expect(std.mem.indexOf(u8, got, "fn double(") != null);
    try testing.expect(std.mem.indexOf(u8, got, " n ") == null);
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, got, "_zz"));
}

test "a lambda parameter is renamed with its uses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .renamed_bindings,
        \\fn main() -> UInt8 {
        \\    let double = |value: UInt8| value + value
        \\    double(3)
        \\}
        \\
    )).?;

    const parameter = nameAfter(got, "|").?;
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, got, parameter));
}

test "capture renaming separates aliases from renamed sources" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const sources = [_][]const u8{
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 3
        \\    let outer = read [read number] || {
        \\        let inner = read [read number] || number
        \\        inner()
        \\    }
        \\    outer()
        \\}
        ,
        \\fn evaluate(value: UInt8) -> UInt8 {
        \\    let closure = read [read value] || value
        \\    closure()
        \\}
        \\fn main() -> UInt8 {
        \\    let selected: fn(value: UInt8) -> UInt8 = evaluate
        \\    selected(value: 3)
        \\}
        ,
    };
    for (sources, 0..) |source, index| {
        const got = (try applyTo(gpa, .renamed_bindings, source)).?;
        try testing.expect(std.mem.indexOf(u8, got, "read _zz") != null);
        if (index == 0) {
            try testing.expect(std.mem.indexOf(u8, got, "number") == null);
            try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, " = _zz"));
        } else {
            try testing.expect(std.mem.indexOf(u8, got, " = _zz") != null);
        }
        var ast = try parseText(gpa, got);
        var sink = Sink.init(gpa);
        var resolved = try resolveTree(gpa, &ast, &sink);
        _ = try typecheckTree(gpa, &resolved, &sink);
        try testing.expect(!sink.hasErrors());
    }
}

test "a selected function binder is renamed independently of contextual labels" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .renamed_bindings,
        \\fn identity(value: UInt8) -> UInt8 { value }
        \\
        \\fn main() -> UInt8 {
        \\    let selected: fn(read value: UInt8) -> UInt8 = identity
        \\    selected(value: 3)
        \\}
        \\
    )).?;

    const declared = nameAfter(got, "fn identity(").?;
    const selected = nameAfter(got, "let ").?;
    const call = std.mem.lastIndexOf(u8, got, selected).? + selected.len;
    try testing.expectEqualStrings("value", nameAfter(got, ": fn(read ").?);
    try testing.expectEqualStrings("value", nameAfter(got[call..], "(").?);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, declared));
}

test "a converted lambda binder is renamed independently of contextual labels" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .renamed_bindings,
        \\import std.io
        \\
        \\use io.IoError
        \\use io.println
        \\
        \\fn say(name: Str, sink value: UInt8) -> Result[UInt8, IoError] {
        \\    println(name)?
        \\    return .Ok(value)
        \\}
        \\
        \\fn main() -> Result[UInt8, IoError] {
        \\    let selected: fn(read first: UInt8, read second: UInt8, read base: UInt8 = 3) -> UInt8 = (|first, second: UInt8, base = 3| first + second + base)
        \\    let result = selected(second: say("second", 2)?, first: say("first", 1)?)
        \\    return .Ok(result)
        \\}
        \\
    )).?;

    const annotated = nameAfter(got, "fn(read ").?;
    try testing.expect(!std.mem.eql(u8, annotated, nameAfter(got, "= (|").?));
    const selected = nameAfter(got, "let ").?;
    const call = std.mem.lastIndexOf(u8, got, selected).? + selected.len;
    try testing.expectEqualStrings(annotated, nameAfter(got[call..], "?, ").?);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, nameAfter(got, "= (|").?));
}

test "callable-bound labels remain unchanged when implementation binders are renamed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expect(null != try applyTo(arena.allocator(), .renamed_bindings,
        \\fn apply[F: fn(read value: UInt8) -> UInt8](f: F) -> UInt8 {
        \\    f(value: 1)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    apply(|value: UInt8| value)
        \\}
        \\
    ));
}

test "renaming does not require callback implementation labels to match unresolved bounds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const sources = [_][]const u8{
        \\let greeting = "hello"
        \\fn size(value: Str = greeting) -> UInt64 { value.length() }
        \\fn invoke[F: fn(read value: Str = "hello") -> UInt64](callback: F) -> UInt64 {
        \\    callback()
        \\}
        \\fn main() -> UInt8 { if invoke(size) == 5 { 0 } else { 1 } }
        ,
        \\let greeting = "hello"
        \\fn size(value: Str = greeting) -> UInt64 { value.length() }
        \\fn invoke[F](callback: F) -> UInt64
        \\where F: fn(read value: Str = "hello") -> UInt64 {
        \\    callback()
        \\}
        \\fn main() -> UInt8 { if invoke(size) == 5 { 0 } else { 1 } }
        ,
    };
    for (sources) |source| {
        try testing.expect(null != try applyTo(arena.allocator(), .renamed_bindings, source));
    }
}

test "a match pattern is not a binding and is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .renamed_bindings,
        \\enum Shape { Circle, Square }
        \\
        \\fn main() -> UInt8 {
        \\    let s: Shape = Shape.Circle;
        \\    match s { Circle => 1, Square => 2 }
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "Circle => 1") != null);
    try testing.expect(std.mem.indexOf(u8, got, "Square => 2") != null);
    try testing.expect(std.mem.indexOf(u8, got, "Shape.Circle") != null);
}

test "a member and the signature it supplies take one name between them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Both halves are in the file, so the relation is one the tree sees whole:
    // the signature's parameter and the member's take the same new name, which
    // is what [T-Impl] obliges.
    const got = (try applyTo(gpa, .renamed_bindings,
        \\trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\
        \\struct Coin { n: UInt8 }
        \\
        \\impl Measure for Coin {
        \\    fn of(x: Coin) -> UInt8 { x.n }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let c: Coin = .{ n = 1 };
        \\    Measure.of(c)
        \\}
        \\
    )).?;

    try testing.expectEqualStrings(
        nameAfter(got, "fn of(").?,
        nameAfter(got[std.mem.indexOf(u8, got, "impl Measure").?..], "fn of(").?,
    );
}

test "a member supplying a signature the file does not hold is declined" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `Display` is declared by the library, so this tree holds one half of the
    // relation its parameters are held to. Renaming that half writes a program
    // the checker refuses, so the rename says nothing about this program.
    try testing.expectEqual(@as(?[]const u8, null), try applyTo(arena.allocator(), .renamed_bindings,
        \\struct Box { v: UInt8 }
        \\
        \\impl Display for Box {
        \\    fn fmt[W: Writer](self: Box, inout w: W) -> Result[(), W.Error] {
        \\        Display.fmt(self.v, &w)
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 { 0 }
        \\
    ));
}

test "an argument naming a parameter the file cannot find is declined" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The receiver's type is the library's, so this tree cannot say which
    // operation the postfix call reaches and therefore which parameter `width`
    // names. Renaming the declaration would leave the written name behind.
    try testing.expectEqual(@as(?[]const u8, null), try applyTo(arena.allocator(), .renamed_bindings,
        \\trait Pad {
        \\    fn pad(s: Self, width: UInt8) -> UInt8
        \\}
        \\
        \\impl Pad for Str {
        \\    fn pad(s: Str, width: UInt8) -> UInt8 { width }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let t: Str = "ab";
        \\    t.pad(width: 3)
        \\}
        \\
    ));
}

test "a program with no local bindings says nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(
        @as(?[]const u8, null),
        try applyTo(arena.allocator(), .renamed_bindings, "fn main() -> UInt8 { 1 }\n"),
    );
}

test "a nested match is carried by the arm it sits in, not rewritten twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .rotated_match_arms,
        \\enum Shape { Circle, Square }
        \\
        \\fn main() -> UInt8 {
        \\    match Shape.Circle {
        \\        Circle => match Shape.Square {
        \\            Circle => 1,
        \\            Square => 2,
        \\        },
        \\        Square => 3,
        \\    }
        \\}
        \\
    )).?;

    // The outer rotation moved the whole inner match, which is still written
    // exactly once and in its original arm order.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got, "match Shape.Square"));
    try testing.expect(std.mem.indexOf(u8, got, "Circle => 1").? <
        std.mem.indexOf(u8, got, "Square => 2").?);

    var after = try parseText(gpa, got);
    try testing.expectEqual(@as(u32, 2), after.declCount());
}

test "permuting moves the last named argument to the front" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .permuted_named_arguments,
        \\fn add(a: UInt8, b: UInt8) -> UInt8 { a + b }
        \\
        \\fn main() -> UInt8 { add(a: 40, b: 2) }
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "add(b: 2, a: 40)") != null);
}

test "permuting reaches closure and pointer calls" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .permuted_named_arguments,
        \\fn main() -> UInt8 {
        \\    let direct = |high: UInt8, low: UInt8| high - low
        \\    let indirect: fn(read high: UInt8, read low: UInt8) -> UInt8 = |high, low| high - low
        \\    direct(high: 9, low: 4) + indirect(high: 8, low: 3)
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "direct(low: 4, high: 9)") != null);
    try testing.expect(std.mem.indexOf(u8, got, "indirect(low: 3, high: 8)") != null);
}

test "the positional prefix stays where position put it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .permuted_named_arguments,
        \\fn add(a: UInt8, b: UInt8, c: UInt8) -> UInt8 { a + b + c }
        \\
        \\fn main() -> UInt8 { add(1, b: 2, c: 3) }
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "add(1, c: 3, b: 2)") != null);
}

test "a call naming one parameter has one order and says nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expectEqual(@as(?[]const u8, null), try applyTo(gpa, .permuted_named_arguments,
        \\fn add(a: UInt8, b: UInt8) -> UInt8 { a + b }
        \\
        \\fn main() -> UInt8 { add(40, b: 2) }
        \\
    ));

    try testing.expectEqual(@as(?[]const u8, null), try applyTo(gpa, .permuted_named_arguments,
        \\fn add(a: UInt8, b: UInt8) -> UInt8 { a + b }
        \\
        \\fn main() -> UInt8 { add(40, 2) }
        \\
    ));
}

test "a struct literal's fields are not arguments and are left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The literal and the match below are written with the payload every call
    // is written with, and neither names a parameter. A rewrite reading the
    // shape rather than the tag would rotate both.
    try testing.expectEqual(@as(?[]const u8, null), try applyTo(gpa, .permuted_named_arguments,
        \\struct Point { x: UInt8, y: UInt8 }
        \\
        \\enum Shape { Circle, Square }
        \\
        \\fn main() -> UInt8 {
        \\    let p: Point = .{ x = 1, y = 2 }
        \\    match Shape.Circle { Circle => p.x, Square => p.y }
        \\}
        \\
    ));
}

test "a call inside a named argument is carried, not rewritten twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .permuted_named_arguments,
        \\fn add(a: UInt8, b: UInt8) -> UInt8 { a + b }
        \\
        \\fn main() -> UInt8 { add(a: add(a: 1, b: 2), b: 3) }
        \\
    )).?;

    // The outer rotation moved the inner call, which is written exactly once
    // and in the order it was written in.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got, "add(a: 1, b: 2)"));
    try testing.expect(std.mem.indexOf(u8, got, "add(b: 3, a: add(a: 1, b: 2))") != null);
}

test "a comment after the last argument is not carried into the list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A node's token range runs to the next token that is not trivia, so a
    // comment written after an argument sits inside that argument's span. A
    // rewrite slicing by that span carries the `//` into the middle of the
    // list, where it comments out every argument after it -- and the runner
    // reports the compiler for refusing a call the rewrite truncated.
    const got = (try applyTo(gpa, .permuted_named_arguments,
        \\fn add(a: UInt8, b: UInt8) -> UInt8 { a + b }
        \\
        \\fn main() -> UInt8 {
        \\    add(a: 40, b: 2 // note
        \\    )
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "add(b: 2, a: 40") != null);

    // And the call still passes two arguments, which is the property the
    // splice broke rather than the spelling that showed it.
    var after = try parseText(gpa, got);
    for (0..after.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (after.exprTag(id) != .call) continue;
        try testing.expectEqual(@as(usize, 2), after.call(id).args.len);
    }
}

test "a comment after the last arm is not carried into the arms" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The same exposure, in the rewrite this one was written from: the arms
    // are spliced by span too, so the trailing comment would be written
    // between the rotated arms and swallow the comma that separates them.
    const got = (try applyTo(gpa, .rotated_match_arms,
        \\enum Shape { Circle, Square }
        \\
        \\fn main() -> UInt8 {
        \\    match Shape.Circle {
        \\        Circle => 1,
        \\        Square => 2 // note
        \\    }
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "Square => 2,") != null);

    var after = try parseText(gpa, got);
    for (0..after.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (!after.exprTag(id).isMatch()) continue;
        try testing.expectEqual(@as(usize, 4), after.call(id).args.len);
    }
}

test "a comment after the last argument is not carried into the written-out call" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The receiver moves to the front and the written arguments follow it, so
    // a comment sitting inside the last argument's range is spliced ahead of
    // the paren that closes the call and comments it out.
    const got = (try applyTo(gpa, .postfix_written_out,
        \\struct Account { balance: UInt8 }
        \\
        \\trait Measure {
        \\    fn plus(x: Self, n: UInt8) -> UInt8
        \\}
        \\
        \\impl Measure for Account {
        \\    fn plus(x: Self, n: UInt8) -> UInt8 { x.balance + n }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ balance = 7 }
        \\    a.plus(2 // note
        \\    )
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "Measure.plus(a, 2)") != null);

    // And the rewritten program still parses, which is the property the splice
    // broke rather than the spelling that showed it.
    const source: Source = .{ .path = "transform.lin", .text = got };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var after = parse(gpa, &source, .from(0), tokens, &sink);
    _ = &after;
    try testing.expect(!sink.hasErrors());
}

fn checkedPostfixRewrite(gpa: std.mem.Allocator, files: []const loader.InMemoryFile) !?[]const u8 {
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var table: FileTable = .empty;
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, files[0].path, files, .program, true, .borrow);
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var res = resolved.resolution;
    defer res.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &res, &sink);
    defer typing.deinit(gpa);
    try testing.expect(!sink.hasErrors());
    const rewritten = try postfixWrittenOut(gpa, .{
        .ast = &expanded.ast,
        .program = &program,
        .res = &res,
        .typing = &typing,
        .file = program.primaryFile(),
    }, files[0].text);
    if (rewritten) |text| {
        const after_files = try gpa.dupe(loader.InMemoryFile, files);
        after_files[0].text = text;
        var after_sink = Sink.init(gpa);
        var after_interner: Interner = .empty;
        var after_table: FileTable = .empty;
        var after_program = try loader.loadFromMemory(gpa, &after_table, &after_sink, &after_interner, files[0].path, after_files, .program, true, .borrow);
        const after_resolved = try resolve(gpa, &after_program, &after_interner, &after_sink, .program);
        var after_expanded = after_resolved.expanded;
        defer after_expanded.deinit(gpa);
        var after_res = after_resolved.resolution;
        defer after_res.deinit(gpa);
        var after_typing = try typecheck(gpa, &after_expanded, &after_res, &after_sink);
        defer after_typing.deinit(gpa);
        try testing.expect(!after_sink.hasErrors());
    }
    return rewritten;
}

test "postfix written-out qualification reaches an inferred library type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const rewritten = (try checkedPostfixRewrite(arena.allocator(), &.{.{
        .path = "main.lin",
        .text =
        \\import std.env
        \\fn main() -> UInt8 {
        \\    let given = env.args()
        \\    if given.count() > 0 { 0 } else { 1 }
        \\}
        ,
    }})).?;
    try testing.expect(std.mem.indexOf(u8, rewritten, "env.Args.count(given)") != null);
}

test "postfix written-out qualification checks with a directly visible owner" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const rewritten = (try checkedPostfixRewrite(arena.allocator(), &.{.{
        .path = "main.lin",
        .text =
        \\import std.env
        \\use env.Args
        \\fn main() -> UInt8 {
        \\    let given: Args = env.args()
        \\    if given.count() > 0 { 0 } else { 1 }
        \\}
        ,
    }})).?;
    try testing.expect(std.mem.indexOf(u8, rewritten, ".count(given)") != null);
}

test "postfix written-out qualification declines an owner the source cannot name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const rewritten = try checkedPostfixRewrite(arena.allocator(), &.{
        .{
            .path = "main.lin",
            .text =
            \\import maker
            \\fn main() -> UInt8 {
            \\    let value = maker.make()
            \\    value.count()
            \\}
            ,
        },
        .{
            .path = "maker/maker.lin",
            .text =
            \\struct Hidden {}
            \\impl Hidden {
            \\    pub fn count(_self: Hidden) -> UInt8 { 7 }
            \\}
            \\pub fn make() -> Hidden { .{} }
            ,
        },
    });
    try testing.expect(rewritten == null);
}

test "postfix written-out qualification ignores shadows not yet introduced" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{
        \\import std.env as process
        \\fn main() -> UInt8 {
        \\    let given = process.args()
        \\    let count = given.count()
        \\    let process = count
        \\    if process > 0 { 0 } else { 1 }
        \\}
        ,
        \\import std.env as process
        \\fn main() -> UInt8 {
        \\    let given = process.args()
        \\    let process = given.count()
        \\    if process > 0 { 0 } else { 1 }
        \\}
        ,
    }) |source| {
        const rewritten = (try checkedPostfixRewrite(arena.allocator(), &.{.{ .path = "main.lin", .text = source }})).?;
        try testing.expect(std.mem.indexOf(u8, rewritten, "process.Args.count(given)") != null);
    }
}

test "canonical call index keeps generated postfix calls out of source rewrites" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try applyTo(arena.allocator(), .postfix_written_out,
        \\struct Mark {}
        \\trait Literal { fn value(self: Self) -> UInt8 }
        \\impl Literal for UInt8 {
        \\    fn value(self: UInt8) -> UInt8 { self }
        \\}
        \\trait Structural { fn result(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn result(_self: Self) -> UInt8 {
        \\        let n: UInt8 = 7
        \\        n.value()
        \\    }
        \\}
        \\derive Structural for Mark
        \\fn main() -> UInt8 {
        \\    let mark: Mark = .{}
        \\    Structural.result(mark)
        \\}
    );
    try testing.expect(got == null);
}

test "a postfix call on an inferred imported type uses a visible module name" {
    for ([_][]const u8{ "env", "process" }) |module_name| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const text = try std.fmt.allocPrint(gpa,
            \\import std.env{s}
            \\use {s}.args
            \\fn main() -> UInt8 {{
            \\    let given = args()
            \\    if given.count() > 0 {{ 0 }} else {{ 1 }}
            \\}}
            \\
        , .{ if (std.mem.eql(u8, module_name, "env")) "" else " as process", module_name });
        const got = (try applyTo(gpa, .postfix_written_out, text)).?;

        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        var table: FileTable = .empty;
        const one = [_]loader.InMemoryFile{.{ .path = "rewritten.lin", .text = got }};
        var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "rewritten.lin", &one, .program, true, .borrow);
        const resolved = try resolve(gpa, &program, &interner, &sink, .program);
        var expanded = resolved.expanded;
        defer expanded.deinit(gpa);
        var res = resolved.resolution;
        defer res.deinit(gpa);
        var typing = try typecheck(gpa, &expanded, &res, &sink);
        defer typing.deinit(gpa);
        try testing.expect(!sink.hasErrors());
        const written_call = try std.fmt.allocPrint(gpa, "{s}.Args.count(given)", .{module_name});
        try testing.expect(std.mem.indexOf(u8, got, written_call) != null);
    }
}

test "a postfix vector call keeps its caller-visible namespace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const body =
        \\fn main() -> UInt8 {
        \\    let values: mem.Vec[UInt8, mem.SystemAllocator] = mem.Vec.new()
        \\    let length = values.length()
        \\    match mem.Vec.finish(values) { Ok(_) => {}, Err(_) => panic("not empty") }
        \\    if length == 0 { 0 } else { 1 }
        \\}
    ;
    const qualified = try std.mem.concat(gpa, u8, &.{ "import std.mem\n", body });
    try expectPostfixRewriteChecks(gpa, qualified, "mem.Vec.length(values)");

    const named_body = try std.mem.replaceOwned(u8, gpa, body, "mem.Vec", "Vec");
    const unqualified = try std.mem.concat(gpa, u8, &.{ "import std.mem\nuse mem.Vec\n", named_body });
    try expectPostfixRewriteChecks(gpa, unqualified, "Vec.length(values)");
}

test "a postfix call marking its receiver passes the receiver marked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectPostfixRewriteChecks(arena.allocator(),
        \\import std.mem
        \\
        \\fn main() -> UInt8 {
        \\    var values: mem.Vec[UInt64, mem.SystemAllocator] = mem.Vec.new()
        \\    &values.push(3).unwrap()
        \\    let length = values.length()
        \\    values.release()
        \\    UInt8(length)
        \\}
    , "mem.Vec.push(&values, 3)");
}

fn expectSourceChecks(gpa: std.mem.Allocator, text: []const u8) !void {
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var table: FileTable = .empty;
    const files = [_]loader.InMemoryFile{.{ .path = "rewritten.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "rewritten.lin", &files, .program, true, .borrow);
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var res = resolved.resolution;
    defer res.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &res, &sink);
    defer typing.deinit(gpa);
    try testing.expect(!sink.hasErrors());
}

fn expectPostfixRewriteChecks(gpa: std.mem.Allocator, text: []const u8, written_call: []const u8) !void {
    try expectSourceChecks(gpa, text);
    const rewritten = try applyTo(gpa, .postfix_written_out, text);
    try testing.expect(rewritten != null);
    const got = rewritten.?;
    try testing.expect(std.mem.indexOf(u8, got, written_call) != null);
    try expectSourceChecks(gpa, got);
}

test "postfix written-out qualification ignores a destructuring binder not yet introduced" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const rewritten = (try checkedPostfixRewrite(arena.allocator(), &.{.{
        .path = "main.lin",
        .text =
        \\import std.env as process
        \\struct Box { value: UInt64 }
        \\fn box(sink value: UInt64) -> Box { .{ value = value } }
        \\fn main() -> UInt8 {
        \\    let given = process.args()
        \\    let Box { value: process } = box(given.count())
        \\    if process > 0 { 0 } else { 1 }
        \\}
        ,
    }})).?;
    try testing.expect(std.mem.indexOf(u8, rewritten, "process.Args.count(given)") != null);
}

test "postfix owner remains visible before a later destructuring binder shadows it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const rewritten = (try checkedPostfixRewrite(arena.allocator(), &.{.{
        .path = "main.lin",
        .text =
        \\import std.env as process
        \\struct Box { value: UInt64 }
        \\fn main() -> UInt8 {
        \\    let given = process.args()
        \\    let got = given.count()
        \\    let packed: Box = .{ value = got }
        \\    let Box { value: process } = packed
        \\    if process > 0 { 0 } else { 1 }
        \\}
        ,
    }})).?;
    try testing.expect(std.mem.indexOf(u8, rewritten, "process.Args.count(given)") != null);
}

test "postfix written-out qualification uses the import alias where a type parameter shadows the owner" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const rewritten = (try checkedPostfixRewrite(arena.allocator(), &.{.{
        .path = "main.lin",
        .text =
        \\import std.env as process
        \\fn count[Args](_marker: Args) -> UInt64 {
        \\    let given = process.args()
        \\    given.count()
        \\}
        \\fn main() -> UInt8 {
        \\    if count(true) > 0 { 0 } else { 1 }
        \\}
        ,
    }})).?;
    try testing.expect(std.mem.indexOf(u8, rewritten, "process.Args.count(given)") != null);
}

test "postfix owner is not qualified through an import a local shadows" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\import std.env
        \\use env.args
        \\fn main() -> UInt8 {
        \\    let env: UInt8 = 1
        \\    let given = args()
        \\    if given.count() > 0 { env } else { 0 }
        \\}
    ;
    try expectSourceChecks(gpa, text);
    try testing.expect(try applyTo(gpa, .postfix_written_out, text) == null);
}

test "a derived postfix call is written out from expanded semantics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .postfix_written_out,
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
        \\derive Structural for Mark
        \\
        \\fn main() -> UInt8 {
        \\    let mark: Mark = .{}
        \\    mark.value()
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "Structural.value(mark)") != null);
}

test "reordering moves a structure's fields and nothing else" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try applyTo(gpa, .reordered_fields,
        \\struct Point { x: UInt8, y: Bool }
        \\fn main() -> UInt8 { 0 }
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "y: Bool, x: UInt8") != null);
    // The rest of the program is untouched, which is what makes the two
    // comparable at all.
    try testing.expect(std.mem.indexOf(u8, out, "fn main() -> UInt8 { 0 }") != null);
}

test "reordering leaves a tuple literal and a tuple pattern as written" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try applyTo(gpa, .reordered_fields,
        \\struct Point { x: UInt8, y: Bool }
        \\fn main() -> UInt8 {
        \\    let (a, b) = (UInt8(1), true)
        \\    let _ = b
        \\    a
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "y: Bool, x: UInt8") != null);
    try testing.expect(std.mem.indexOf(u8, out, "let (a, b) = (UInt8(1), true)") != null);

    // A program whose only multi-component aggregate is a tuple has no
    // structure to reorder.
    try testing.expect(try applyTo(gpa, .reordered_fields,
        \\fn main() -> UInt8 {
        \\    let (a, b) = (UInt8(1), true)
        \\    let _ = b
        \\    a
        \\}
    ) == null);
}

test "a structure of one field says nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try applyTo(gpa, .reordered_fields,
        \\struct Point { x: UInt8 }
        \\fn main() -> UInt8 { 0 }
    ) == null);

    try testing.expect(try applyTo(gpa, .reordered_fields, "fn main() -> UInt8 { 0 }") == null);
}

test "fields observed through structural reflection retain declaration order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(?[]const u8, null), try applyTo(arena.allocator(), .reordered_fields,
        \\trait Structural { fn value(self: Self) -> UInt8 }
        \\struct Pair { left: UInt8, right: UInt8 }
        \\derive Structural for Pair
        \\fn main() -> UInt8 { 0 }
    ));
}

test "attached derives preserve field order while ordinary structures may move" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expectEqual(@as(?[]const u8, null), try applyTo(gpa, .reordered_fields,
        \\@derive(Comparable)
        \\struct Version { major: UInt8, minor: UInt8 }
    ));

    const out = (try applyTo(gpa, .reordered_fields,
        \\@(copyable, derive(Comparable))
        \\struct Version { major: UInt8, minor: UInt8 }
        \\struct Point { x: UInt8, y: UInt8 }
    )).?;
    try testing.expect(std.mem.indexOf(u8, out, "major: UInt8, minor: UInt8") != null);
    try testing.expect(std.mem.indexOf(u8, out, "y: UInt8, x: UInt8") != null);
}

test "renaming respells an implementation's parameters everywhere they are written" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try applyTo(gpa, .renamed_head_parameters,
        \\trait Show {
        \\    fn show(self: Self) -> UInt8
        \\}
        \\
        \\struct Holder[T] {
        \\    v: T,
        \\}
        \\
        \\impl[T: Copyable + Show] Show for Holder[T] {
        \\    fn show(self: Holder[T]) -> UInt8 {
        \\        let held: T = copy(self.v)
        \\        Show.show(held)
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    0
        \\}
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "impl[Zz0: Copyable + Show] Show for Holder[Zz0]") != null);
    try testing.expect(std.mem.indexOf(u8, out, "self: Holder[Zz0]") != null);
    try testing.expect(std.mem.indexOf(u8, out, "let held: Zz0 =") != null);
    // The type's own parameter is not the implementation's, and stands where
    // it was written.
    try testing.expect(std.mem.indexOf(u8, out, "struct Holder[T] {") != null);
}

test "renaming respells a derive head and preserves its grouped traits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try applyTo(gpa, .renamed_head_parameters,
        \\trait First {}
        \\template impl First {}
        \\trait Second {}
        \\template impl Second {}
        \\struct Pair[A, B] { first: A, second: B }
        \\derive[T, U] (
        \\    First,
        \\    Second,
        \\) for Pair[T, U]
        \\fn main() -> UInt8 { 0 }
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "derive[Zz0, Zz1]") != null);
    try testing.expect(std.mem.indexOf(u8, out, "for Pair[Zz0, Zz1]") != null);
    try testing.expect(std.mem.indexOf(u8, out, "    First,\n    Second,") != null);
}

test "renaming a derive parameter leaves a same-spelled trait entry alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try applyTo(gpa, .renamed_head_parameters,
        \\trait T {}
        \\template impl T {}
        \\struct Box[A] { value: A }
        \\derive[T] T for Box[T]
        \\fn main() -> UInt8 { 0 }
    )).?;

    try testing.expect(std.mem.indexOf(u8, out, "derive[Zz0] T for Box[Zz0]") != null);
}

test "reversing moves a grouped derive whole and preserves entry order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const out = (try applyTo(gpa, .reversed_declarations,
        \\trait First {}
        \\template impl First {}
        \\trait Second {}
        \\template impl Second {}
        \\struct Pair { first: UInt8, second: UInt8 }
        \\derive (
        \\    First,
        \\    Second,
        \\) for Pair
        \\fn main() -> UInt8 { 0 }
    )).?;

    var ast = try parseText(gpa, out);
    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) != .derive_impl) continue;
        const traits = ast.deriveTraits(d);
        try testing.expect(ast.deriveIsGrouped(d));
        try testing.expectEqual(@as(usize, 2), traits.len);
        try testing.expectEqualStrings("First", ast.tokenText(traits[0].ref.name));
        try testing.expectEqualStrings("Second", ast.tokenText(traits[1].ref.name));
        return;
    }
    return error.GroupedDeriveMissingAfterReversal;
}

test "renaming says nothing about a program with no generic implementation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try applyTo(gpa, .renamed_head_parameters,
        \\struct Coins { count: UInt8 }
        \\
        \\impl Coins {
        \\    fn of(self: Coins) -> UInt8 { self.count }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let c: Coins = .{ count = 1 }
        \\    Coins.of(c)
        \\}
    ) == null);
}

test "a parameter spelled like something the program binds is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try applyTo(gpa, .renamed_head_parameters,
        \\trait Show {
        \\    fn show(self: Self) -> UInt8
        \\}
        \\
        \\struct T { count: UInt8 }
        \\
        \\struct Holder[A] {
        \\    v: A,
        \\}
        \\
        \\impl[T] Show for Holder[T] {
        \\    fn show(self: Holder[T]) -> UInt8 {
        \\        1
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    0
        \\}
    ) == null);
}

test "desugaring says nothing about a `!` whose operand the condition settles" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `U` is written only as the signature's return type, so what settles it is
    // what the call is asked for. Under `!` that is a condition, which asks for
    // `Bool`; on the left of `==` nothing asks for anything. The two spellings
    // are two programs, and the rewrite claims neither.
    try testing.expectEqual(@as(?[]const u8, null), try applyTo(arena.allocator(), .desugared_logic,
        \\trait Innermost[U] { fn of(x: Self) -> U }
        \\
        \\struct Envelope[T] { v: T }
        \\
        \\impl Innermost[Bool] for Envelope[Bool] {
        \\    fn of(x: Self) -> Bool { x.v }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let f: Envelope[Bool] = .{ v = false }
        \\    if !Innermost.of(f) { 13 } else { 3 }
        \\}
        \\
    ));
}

test "desugaring still writes out a `!` whose operand settles itself" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .desugared_logic,
        \\fn main() -> UInt8 {
        \\    if !false { 1 } else { 0 }
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "false == false") != null);
}

test "desugaring keeps a named literal operand out of the arm's brace" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try applyTo(gpa, .desugared_logic,
        \\struct Flag { on: Bool }
        \\
        \\fn main() -> UInt8 {
        \\    let both = Flag { on = true }.on && true
        \\    if both { 0 } else { 1 }
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "if (Flag { on = true }.on) { true } else { false }") != null);
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "transform.lin", .text = got };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    _ = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(!sink.hasErrors());
}

test "source renaming keeps a parameter spelled as one a template member names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const changed = (try applyTo(arena.allocator(), .renamed_bindings,
        \\struct Item {}
        \\trait Label { fn label(self: Self) -> UInt8 }
        \\fn seven(number: UInt8) -> UInt8 { number }
        \\template impl Label {
        \\    fn label(_self: Self) -> UInt8 {
        \\        let held: fn(read number: UInt8) -> UInt8 = seven
        \\        held(7)
        \\    }
        \\}
        \\derive Label for Item
        \\fn main() -> UInt8 {
        \\    let item: Item = .{}
        \\    Label.label(item)
        \\}
    )).?;
    try testing.expect(std.mem.indexOf(u8, changed, "fn seven(number: UInt8)") != null);
    try testing.expect(std.mem.indexOf(u8, changed, "fn(read number: UInt8)") != null);
    try testing.expect(std.mem.indexOf(u8, changed, "let item") == null);
}

test "capture recovery renaming preserves field and local identities" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source =
        \\struct Other { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let source: UInt8 = 3
        \\    let callback = [sink value = source] || value
        \\    let environment = callback.into_captures()
        \\    let observed = environment.value
        \\    let { value: recovered } = environment
        \\    let second = [sink value = source] || value
        \\    let { value } = second.into_captures()
        \\    let other: Other = .{ value = 1 }
        \\    observed + recovered + value + other.value
        \\}
    ;
    const got = (try applyTo(gpa, .renamed_bindings, source)).?;
    try testing.expect(std.mem.indexOf(u8, got, ": _zz") != null);
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, got, "value"));
    var ast = try parseText(gpa, got);
    var sink = Sink.init(gpa);
    var resolved = try resolveTree(gpa, &ast, &sink);
    _ = try typecheckTree(gpa, &resolved, &sink);
    try testing.expect(!sink.hasErrors());
}

test "renaming declines a capture recovery the file alone cannot settle" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `seen` has a type `std.mem` declares, so the tree of this file alone
    // cannot pair the recovered field with the capture alias that names it.
    try testing.expectEqual(@as(?[]const u8, null), try applyTo(arena.allocator(), .renamed_bindings,
        \\import std.mem
        \\
        \\fn main() -> UInt8 {
        \\    let seen = mem.Vec.filled(2, UInt64(7)) else |_| {
        \\        return 1
        \\    }
        \\    var heavy = [sink seen] |sink weight: UInt64| weight > seen.length()
        \\    let found = (UInt64(1)..10).any_inout(&heavy)
        \\    let { seen } = heavy.into_captures()
        \\    seen.release()
        \\    if found { 0 } else { 3 }
        \\}
    ));
}

test "capture renaming includes a library callback's local binders" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source =
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 7
        \\    let callback = [number] |sink value: UInt8| -> where borrows(number) {
        \\        let _ = value
        \\        borrow number
        \\    }
        \\    let input: Option[UInt8] = .Some(1)
        \\    let mapped = input.map(callback).unwrap()
        \\    let second: Option[UInt8] = .Some(2)
        \\    let inline_result = second.map([number] |sink value: UInt8| -> where borrows(number) {
        \\        let _ = value
        \\        borrow number
        \\    }).unwrap()
        \\    *mapped + *inline_result
        \\}
    ;
    var ast = try parseText(gpa, source);
    var local_sink = Sink.init(gpa);
    var local_res = try resolveTree(gpa, &ast, &local_sink);
    const local_typing = try typecheckTree(gpa, &local_res, &local_sink);
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var table: FileTable = .empty;
    const files = [_]loader.InMemoryFile{.{ .path = "transform.lin", .text = source }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "transform.lin", &files, .program, true, .borrow);
    const resolved = try resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    var full_res = resolved.resolution;
    var typing = try typecheck(gpa, &expanded, &full_res, &sink);
    try testing.expect(!sink.hasErrors());
    const got = (try Transform.renamed_bindings.apply(gpa, &ast, &local_res.resolution, &local_typing, .{
        .ast = &expanded.ast,
        .program = &program,
        .res = &full_res,
        .typing = &typing,
        .file = program.primaryFile(),
    }, source)).?;
    try testing.expectEqual(@as(usize, 0), std.mem.count(u8, got, "|sink value: UInt8|"));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, "|sink _zz"));
    try testing.expect(std.mem.indexOf(u8, got, "let _zz") != null);
}

test "every rewrite that holds a program's meaning applies to some generated program" {
    // One program's compilations at a time: each application checks the
    // program, and the postfix rewrite checks it again beside the library, so
    // an arena kept across the seeds would hold every one of them at once.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const kinds = [_]Transform{ .renamed_bindings, .reordered_fields, .postfix_written_out, .permuted_named_arguments };
    var applied = [_]u32{0} ** kinds.len;
    // A call naming two arguments of one function is the rare shape, which is
    // why the range reaches past the sixty-four programs a run generates.
    for (0..128) |seed| {
        _ = arena.reset(.retain_capacity);
        const gpa = arena.allocator();
        const bytes = try generate.choicesFromSeed(gpa, seed, 64);
        // `applyTo` checks a text with no library, which refuses a tuple.
        const text = try generate.generate(gpa, bytes, .{ .max_tuples = 0 });
        for (kinds, &applied) |kind, *count| {
            if (try applyTo(gpa, kind, text) != null) count.* += 1;
        }
    }
    for (kinds, applied) |kind, count| {
        if (count == 0) {
            std.debug.print("{s} applies to no generated program\n", .{@tagName(kind)});
            return error.RewriteNeverApplies;
        }
    }
}
