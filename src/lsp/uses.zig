const std = @import("std");
const testing = std.testing;

const ast_mod = @import("../syntax/ast.zig");
const Ast = ast_mod.Ast;
const node = @import("../syntax/node.zig");
const ExprId = node.ExprId;
const resolve = @import("../sema/resolve.zig");
const BindingId = resolve.BindingId;
const Resolution = resolve.Resolution;
const types_mod = @import("../sema/types.zig");
const typecheck = @import("../sema/typecheck.zig");
const Typing = types_mod.Typing;
const CallIndex = types_mod.CallIndex;
const TokenId = @import("../lexer/token.zig").TokenId;

/// A source declaration's identity, including traits and constants. Parameters,
/// local bindings and module names do not identify declarations of their own.
pub fn sourceDeclaration(res: *const Resolution, binding: BindingId) node.DeclId {
    if (binding == .none) return .none;
    return switch (res.kindOf(binding)) {
        .function, .declared_type, .associated_type, .trait, .constant, .type_alias => res.declaredBy(binding),
        else => .none,
    };
}

/// Fields, variants and contextual callable parameters use source tokens as identities.
/// Queries read one map entry and the requested declaration's own use list.
const SourceNameUses = struct {
    targets: std.AutoHashMapUnmanaged(TokenId, TokenId) = .empty,
    sites: std.AutoHashMapUnmanaged(TokenId, std.ArrayList(TokenId)) = .empty,
    unpaired_interfaces: std.AutoHashMapUnmanaged(TokenId, void) = .empty,

    fn deinit(self: *SourceNameUses, gpa: std.mem.Allocator) void {
        var runs = self.sites.valueIterator();
        while (runs.next()) |run| run.deinit(gpa);
        self.sites.deinit(gpa);
        self.targets.deinit(gpa);
        self.unpaired_interfaces.deinit(gpa);
    }

    fn note(self: *SourceNameUses, gpa: std.mem.Allocator, at: TokenId, declaration: TokenId) !void {
        if (at == .none or declaration == .none) return;
        if (self.targets.contains(at)) return;
        try self.targets.put(gpa, at, declaration);
        const run = try self.sites.getOrPut(gpa, declaration);
        if (!run.found_existing) run.value_ptr.* = .empty;
        try run.value_ptr.append(gpa, at);
    }

    fn noteVariant(self: *SourceNameUses, gpa: std.mem.Allocator, ast: *const Ast, at: ExprId, declaration: node.DeclId, ordinal: types_mod.VariantOrdinal) !void {
        if (at.index() >= ast.exprCount()) return;
        try self.noteVariantToken(gpa, ast, ast.exprMain(at), declaration, ordinal);
    }

    fn noteVariantToken(self: *SourceNameUses, gpa: std.mem.Allocator, ast: *const Ast, token: TokenId, declaration: node.DeclId, ordinal: types_mod.VariantOrdinal) !void {
        if (token.index() >= ast.tokenCount() or declaration.index() >= ast.declCount()) return;
        const variants = ast.declVariants(declaration);
        const index = @intFromEnum(ordinal);
        if (index >= variants.len) return;
        try self.note(gpa, token, variants[index].name);
    }

    fn build(gpa: std.mem.Allocator, ast: *const Ast, res: *const Resolution, typing: *const Typing) !SourceNameUses {
        var result: SourceNameUses = .{};
        errdefer result.deinit(gpa);
        for (0..ast.declCount()) |index| {
            for (ast.declFields(node.DeclId.at(@intCast(index)))) |field| {
                try result.note(gpa, field.name, field.name);
            }
            for (ast.declVariants(node.DeclId.at(@intCast(index)))) |variant| {
                try result.note(gpa, variant.name, variant.name);
            }
        }
        // Constructor expressions have callable types. Their selected enum is
        // the recorded signature result, not the expression's type.
        for (typing.function_values) |record| {
            const value = typing.call_index.functionValueOf(typing, record.at) orelse continue;
            const constructor = switch (value.target) {
                .constructor => |selected| selected,
                else => continue,
            };
            const signature = typing.get(value.signature);
            if (signature != .callable) continue;
            const declaration = typing.declOfType(signature.callable.result) orelse continue;
            try result.noteVariant(gpa, ast, value.at, declaration, constructor.ordinal);
        }
        var contextual_variants = typing.variant_uses.iterator();
        while (contextual_variants.next()) |entry| {
            if (entry.key_ptr.index() >= ast.exprCount()) continue;
            const declaration = typing.declOfType(typing.exprType(entry.key_ptr.*)) orelse continue;
            try result.noteVariant(gpa, ast, entry.key_ptr.*, declaration, entry.value_ptr.ordinal);
        }
        var qualified_variants = res.variant_ordinals.iterator();
        while (qualified_variants.next()) |entry| {
            const binding = res.targetOf(entry.key_ptr.*);
            if (binding == .none) continue;
            const declaration = res.declIfDeclared(binding);
            if (declaration == .none) continue;
            try result.noteVariant(gpa, ast, entry.key_ptr.*, declaration, entry.value_ptr.*);
        }
        var contract_variants = typing.contract_variants.iterator();
        while (contract_variants.next()) |entry| {
            const declaration = typing.declOfType(entry.value_ptr.receiver) orelse continue;
            try result.noteVariantToken(gpa, ast, entry.key_ptr.*, declaration, entry.value_ptr.ordinal);
        }
        // Closure types preserve their source closure identity through specialization.
        // Index their environments once rather than searching closures per field use.
        var environments: std.AutoHashMapUnmanaged(types_mod.TypeId, resolve.ClosureId) = .empty;
        defer environments.deinit(gpa);
        for (typing.pool) |ty| switch (ty) {
            .closure => |closure| try environments.put(gpa, closure.environment, closure.closure),
            else => {},
        };
        var uses = typing.field_names.iterator();
        while (uses.next()) |entry| {
            // Generated declarations and tokens may lie beyond the source AST.
            if (entry.key_ptr.index() >= ast.tokenCount()) continue;
            const selection = entry.value_ptr.*;
            if (environments.get(selection.receiver)) |closure| {
                const descriptor = typing.closureOf(closure);
                if (descriptor.expr.index() >= ast.exprCount() or ast.exprTag(descriptor.expr) != .lambda) continue;
                const captures = ast.lambda(descriptor.expr).captures;
                if (selection.field.index() < captures.len)
                    try result.note(gpa, entry.key_ptr.*, captures[selection.field.index()].name);
                continue;
            }
            const declaration = typing.declOfType(selection.receiver) orelse continue;
            if (declaration.index() >= ast.declCount()) continue;
            const fields = ast.declFields(declaration);
            if (selection.field.index() >= fields.len) continue;
            try result.note(gpa, entry.key_ptr.*, fields[selection.field.index()].name);
        }
        return result;
    }
};

/// The resolution read backwards: where a binding's name is written by an
/// expression that reaches it, where it is written outside every expression,
/// and which binding a token declares.
///
/// `targets` is a flat `ExprId -> BindingId` array and `written` a flat
/// `TokenId -> BindingId` one, so all of these are those arrays and `tokens`
/// turned around. Held rather than searched for the reason every other index
/// here is: a capability asking "where else is this name used" that walked the
/// program's expressions would read every expression in the module for every
/// name asked about, and a capability asking "what does this declaration
/// declare" would read every binding.
///
/// **Bound, building:** each expression's target is read twice -- once to count
/// how many reach each binding and once to place it -- each token's written
/// binding twice for the same reason, plus one pass over the bindings.
/// O(expressions + tokens + bindings + declarations). It holds one entry per
/// expression that reaches anything, one per token that writes a name, one per
/// binding, and one per token and source declaration.
///
/// **Bound, answering:** `of` and `writtenOf` are each two array reads and a
/// subslice, so producing an answer is constant and reading it is the size of
/// the answer. `declaredAt` and `bindingOfDeclaration` are one array read.
/// Neither lookup depends on program size. Source `use` bindings are also
/// grouped once by canonical declaration in a sparse map; an alias query
/// reads one map entry and only that declaration's bindings.
pub const Uses = struct {
    /// Local references at a construction's shared field/value token.
    initializers: std.AutoHashMapUnmanaged(TokenId, BindingId) = .empty,
    source_names: SourceNameUses,
    /// Source `use` bindings grouped by the declaration they re-export.
    aliases: std.AutoHashMapUnmanaged(node.DeclId, std.ArrayList(BindingId)) = .empty,
    /// Where each binding's tokens begin in `spellings`, with one more
    /// entry than there are bindings so that the last one's run is bounded.
    starts: []const u32,
    /// Every token that spells a binding an expression reaches, grouped by
    /// the binding and in the order of the expressions that reached it.
    ///
    /// The token rather than the expression, because where a name is written
    /// is the question every consumer asks and the expression does not always
    /// answer it: a qualified variant reaches the enum and is spelled by the
    /// token before its own. Which token that is, is settled once -- by the
    /// resolver for a name and by the checker's record for the callee of a
    /// call written with a dot -- and kept here.
    ///
    /// In the order of the `ExprId`s that reached the binding, which is source
    /// order within a file and file order across a module: a file's
    /// expressions are a contiguous run, so a group read in this order is read
    /// in the order a person would read it.
    spellings: []const TokenId,
    /// Where each binding's written tokens begin in `tokens`, with one more
    /// entry than there are bindings so that the last one's run is bounded.
    written_starts: []const u32,
    /// Every token that writes a name outside an expression, grouped by the
    /// binding it reaches and ascending within a group.
    ///
    /// An annotation, a type argument, a bound, an `impl` head, a `use` path --
    /// and the name an argument writes to say which parameter it fills, which
    /// is a reference to that parameter and belongs here for the same reason
    /// the others do. The resolver settles the first kind; the matcher settles
    /// the second, and its answer is read back rather than worked out again.
    ///
    /// Ascending by `TokenId`, which is source order within a file and file
    /// order across a module, for the reason `spellings` is.
    tokens: []const TokenId,
    /// The binding each token declares, or `.none` for a token that declares
    /// nothing -- which is nearly all of them.
    declared: []const BindingId,
    /// The same bindings indexed by source declaration. Reference families
    /// traverse declarations, so this avoids reading the sparse token table
    /// for every member on each editor request.
    declaration_bindings: []const BindingId,
    /// What the callee of a call written with a dot reaches, per expression,
    /// and `.none` for every expression that is not one.
    ///
    /// `a.of()` and `Measure.of(a)` are one call written two ways. The callee
    /// of the first selects a name the receiver's type does not have, so the
    /// resolver settles it on nothing -- which trait declares the operation is
    /// a question about the value's type, and only the checker asks it. What
    /// the checker settled is read back here through `CallIndex` rather than
    /// asked again, so the two spellings reach one binding, no capability tells
    /// them apart, and a call the checker recorded twice is the record every
    /// other pass reads.
    dotted: []const BindingId,
    /// Bindings selected by type checking, keyed by their written name token.
    ///
    /// Store binding-backed argument names paired by call normalization and
    /// source-contract roots paired by signature normalization, plus associated
    /// type selections. Contextual
    /// callable labels and their indirect argument uses belong to source_names.
    ///
    /// A map rather than an array over the tokens: a program writes few
    /// such names and most write none, so this holds one entry per name written
    /// and is empty for nearly every module.
    semantic_names: std.AutoHashMapUnmanaged(TokenId, BindingId),
    /// How many expression targets the build read.
    ///
    /// Recorded because the difference between this index and the scan it
    /// replaces is invisible in every other way: both answer the same
    /// questions, both allocate the same tables, and both are the same number
    /// of milliseconds on a module of a few hundred bytes.
    ///
    /// A count of the targets read and not of the steps a loop took: reading
    /// what an expression reaches is the only way a build learns anything about
    /// it, so this is a consequence of producing the tables rather than a claim
    /// about how they were produced. Grouping by binding reads each
    /// expression's target twice; asking each binding which expressions reach
    /// it reads every expression's target once per binding, and no shape of
    /// loop makes that fewer.
    reads: u64,

    pub fn build(
        gpa: std.mem.Allocator,
        ast: *const Ast,
        res: *const Resolution,
        typing: *const Typing,
        /// Which record the checker's tables hold for each call. Asked rather
        /// than searched, so what a call takes is one answer here and in the
        /// passes that emit it.
        calls: *const CallIndex,
    ) !Uses {
        const bindings = res.bindingCount();
        const expressions = ast.exprCount();
        const token_count = ast.tokenCount();

        const declared = try gpa.alloc(BindingId, token_count);
        errdefer gpa.free(declared);
        @memset(declared, BindingId.none);
        var aliases: std.AutoHashMapUnmanaged(node.DeclId, std.ArrayList(BindingId)) = .empty;
        errdefer deinitAliases(gpa, &aliases);
        for (0..bindings) |i| {
            const b = BindingId.at(@intCast(i));
            const at = res.declaringToken(b);
            // A primitive is declared at no token, which is what makes it the
            // one binding a cursor can never sit on the declaration of.
            if (at == TokenId.none or at.index() >= declared.len) continue;
            // A tuple-pattern parameter's binding stands at the pattern's
            // parenthesis, which names nothing a cursor could rename.
            if (res.kindOf(b) == .parameter and ast.tokenTag(at) != .identifier) continue;
            declared[at.index()] = b;
            if (res.isReExport(b)) {
                const declaration = sourceDeclaration(res, b);
                if (declaration == .none) continue;
                const entry = try aliases.getOrPut(gpa, declaration);
                if (!entry.found_existing) entry.value_ptr.* = .empty;
                try entry.value_ptr.append(gpa, b);
            }
        }

        const declaration_bindings = try gpa.alloc(BindingId, ast.declCount());
        errdefer gpa.free(declaration_bindings);
        for (declaration_bindings, 0..) |*binding, i| {
            binding.* = declaredInTokens(declared, ast.declName(node.DeclId.at(@intCast(i))));
        }

        // What each call written with a dot reaches, keyed by the expression a
        // cursor lands on: the callee. One pass over the module's expressions,
        // asking the index which record answers for each -- the same question
        // ownership and lowering ask, so a call that carries two records is
        // read here as the one they read.
        const dotted = try gpa.alloc(BindingId, expressions);
        errdefer gpa.free(dotted);
        @memset(dotted, BindingId.none);
        var initializers: std.AutoHashMapUnmanaged(TokenId, BindingId) = .empty;
        errdefer initializers.deinit(gpa);
        for (0..expressions) |i| {
            const call = ExprId.at(@intCast(i));
            if (ast.exprTag(call) == .lambda) {
                for (ast.lambda(call).captures) |capture| {
                    if (capture.equals == .none)
                        try initializers.put(gpa, capture.name, res.targetOf(capture.source));
                }
            }
            if (ast.exprTag(call) == .struct_literal) {
                const args = ast.call(call).args;
                var at: usize = 0;
                while (at + 1 < args.len) : (at += 2) {
                    if (ast.fieldIsShorthand(args[at], args[at + 1])) {
                        try initializers.put(gpa, ast.exprMain(args[at]), res.targetOf(args[at + 1]));
                    }
                }
            }
            // A call written after a type's name, `Account.of(a)`, reaches a
            // trait's operation the resolver left to the checker, and names it
            // at its callee as a postfix call does.
            const through_type = ast.exprTag(call) == .call and res.selectsThroughTrait(ast.call(call).callee);
            if (!through_type) _ = calls.postfixOf(typing, call) orelse continue;
            const normal = calls.callOf(typing, call) orelse continue;
            const target = switch (normal.target) {
                .declared => |decl| decl,
                .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => continue,
            };
            // A call in the postfix table has a selection as its callee, written
            // without parentheses: `(a.of)(2)` calls a field's value and is not
            // postfix, while `(a).of(2)` groups only the receiver.
            const callee = typecheck.calleeName(ast, normal);
            if (callee == ExprId.none or callee.index() >= expressions) continue;
            const name = ast.declName(target);
            if (name == TokenId.none or name.index() >= declared.len) continue;
            dotted[callee.index()] = declared[name.index()];
        }
        // `Crate.default` without a call is a function value of the trait's
        // operation, named at the selection.
        for (typing.function_values) |value| {
            if (value.at.index() >= expressions or !res.selectsThroughTrait(value.at)) continue;
            const target = switch (value.target) {
                .declared => |decl| decl,
                else => continue,
            };
            const name = ast.declName(target);
            if (name == TokenId.none or name.index() >= declared.len) continue;
            dotted[value.at.index()] = declared[name.index()];
        }

        // Contextual callable labels belong to the written annotation. Index
        // each converted local by initializer and record its labels separately
        // from the function or lambda parameter bindings.
        const Interface = struct {
            callable: node.CallableTypeId,
            binding: BindingId,
            mutable: bool,
        };
        var interfaces: std.AutoHashMapUnmanaged(ExprId, Interface) = .empty;
        defer interfaces.deinit(gpa);
        for (0..ast.stmtCount()) |i| {
            const data = ast.stmtData(node.StmtId.at(@intCast(i)));
            if (data.annotation.kind != .callable) continue;
            if (data.name == TokenId.none or data.name.index() >= declared.len) continue;
            const binding = declared[data.name.index()];
            if (binding == BindingId.none) continue;
            try interfaces.put(gpa, ast.withoutGroups(data.init), .{
                .callable = data.annotation.callable,
                .binding = binding,
                .mutable = ast.stmtIsMutable(node.StmtId.at(@intCast(i))),
            });
        }

        var source_names = try SourceNameUses.build(gpa, ast, res, typing);
        errdefer source_names.deinit(gpa);
        var semantic_names: std.AutoHashMapUnmanaged(TokenId, BindingId) = .empty;
        errdefer semantic_names.deinit(gpa);
        var type_selections = typing.type_selections.valueIterator();
        while (type_selections.next()) |selection| {
            if (selection.member == .none or selection.declaration == .none) continue;
            const binding = declaration_bindings[selection.declaration.index()];
            if (binding != .none) try semantic_names.put(gpa, selection.member, binding);
        }
        var callable_tokens: std.AutoHashMapUnmanaged(u64, TokenId) = .empty;
        defer callable_tokens.deinit(gpa);
        var interface_owners: std.AutoHashMapUnmanaged(TokenId, BindingId) = .empty;
        defer interface_owners.deinit(gpa);
        for (typing.function_values) |value| {
            if (value.at.index() >= expressions) continue;
            const local = interfaces.get(ast.withoutGroups(value.at)) orelse continue;
            const callable = ast.callableTypeById(local.callable);
            const interface = ast.params[callable.params.start..callable.params.end];
            for (interface, 0..) |written, slot| {
                const key = (@as(u64, @intCast(local.binding.index())) << 32) | @as(u32, @intCast(slot));
                try callable_tokens.put(gpa, key, written.name);
                try source_names.note(gpa, written.name, written.name);
                try interface_owners.put(gpa, written.name, local.binding);
                if (local.mutable) try source_names.unpaired_interfaces.put(gpa, written.name, {});
            }
        }

        // Which binding each written argument name reaches, from the pairing
        // the checker's matcher made. Direct names carry a parameter token;
        // indirect names carry the callee binding and parameter slot that the
        // contextual conversion indexed above. Nowhere compares a spelling.
        //
        // A call the checker walked twice records its names twice and writes
        // the same entry twice, so the token appears once however many records
        // it has -- which is what stops a rename editing one byte range twice.
        for (typing.named) |n| {
            if (n.call.index() >= expressions) continue;
            const source_token = if (n.param != .none)
                source_names.targets.get(n.param)
            else blk: {
                const written = ast.withoutGroups(ast.call(n.call).callee);
                // A function named with type arguments is the name in front
                // of the brackets.
                const typed = if (res.bracketReading(written)) |reading| reading == .type_arguments else false;
                const callee = if (typed) ast.binary(written).lhs else written;
                const binding = res.targetOf(callee);
                if (binding == .none) break :blk null;
                const key = (@as(u64, @intCast(binding.index())) << 32) | n.slot;
                break :blk callable_tokens.get(key);
            };
            if (source_token) |declaration| {
                if (n.name.index() < token_count) try source_names.note(gpa, n.name, declaration);
                continue;
            }
            const b = if (n.param != TokenId.none and n.param.index() < declared.len and declared[n.param.index()] != BindingId.none)
                declared[n.param.index()]
            else if (n.param != TokenId.none)
                semantic_names.get(n.param) orelse continue
            else
                continue;
            if (b == BindingId.none) continue;
            if (n.name == TokenId.none or n.name.index() >= token_count) continue;
            try semantic_names.put(gpa, n.name, b);
        }

        // Contract roots use the checker's positional parameter pairing and
        // retain the identity of the declaration that spells the contract.
        var contracts = typing.contract_parameters.iterator();
        while (contracts.next()) |entry| {
            if (source_names.targets.get(entry.value_ptr.*)) |declaration| {
                if (entry.key_ptr.index() < token_count) try source_names.note(gpa, entry.key_ptr.*, declaration);
                continue;
            }
            const target = declaredInTokens(declared, entry.value_ptr.*);
            const binding = if (target != .none) target else semantic_names.get(entry.value_ptr.*) orelse continue;
            try semantic_names.put(gpa, entry.key_ptr.*, binding);
        }

        var reached: Reached = .{
            .ast = ast,
            .res = res,
            .dotted = dotted,
            .semantic_names = &semantic_names,
        };

        // Grouped by counting first and placing second, so each group is a run
        // of one array and no group is a list of its own: a list per binding is
        // one allocation per binding, and a module of many small functions is
        // mostly bindings.
        const starts = try gpa.alloc(u32, bindings + 1);
        errdefer gpa.free(starts);
        @memset(starts, 0);
        for (0..expressions) |i| {
            const r = reached.by(@intCast(i));
            if (r.binding == BindingId.none) continue;
            starts[r.binding.index()] += 1;
        }

        var total: u32 = 0;
        for (starts[0..bindings]) |*s| {
            const held = s.*;
            s.* = total;
            total += held;
        }
        starts[bindings] = total;

        const held = try gpa.alloc(TokenId, total);
        errdefer gpa.free(held);

        // Where the next expression of each binding goes, which begins at the
        // group's start and ends at the next group's.
        const filled = try gpa.alloc(u32, bindings);
        defer gpa.free(filled);
        @memcpy(filled, starts[0..bindings]);

        for (0..expressions) |i| {
            const r = reached.by(@intCast(i));
            if (r.binding == BindingId.none) continue;
            held[filled[r.binding.index()]] = r.at;
            filled[r.binding.index()] += 1;
        }

        // An interface can be renamed locally only while every use invokes
        // that value. Passing or storing it may impose another exact signature.
        var invocations: std.AutoHashMapUnmanaged(TokenId, void) = .empty;
        defer invocations.deinit(gpa);
        if (interface_owners.count() != 0) for (typing.calls) |call| {
            const expression = switch (call.target) {
                .indirect => |callee| callee,
                else => continue,
            };
            if (expression.index() >= expressions) continue;
            const callee = ast.withoutGroups(expression);
            if (ast.exprTag(callee) == .name_ref) try invocations.put(gpa, ast.exprMain(callee), {});
        };
        var owners = interface_owners.iterator();
        while (owners.next()) |owner| {
            const binding = owner.value_ptr.*;
            for (held[starts[binding.index()]..starts[binding.index() + 1]]) |use| {
                if (invocations.contains(use)) continue;
                try source_names.unpaired_interfaces.put(gpa, owner.key_ptr.*, {});
                break;
            }
        }

        // The same grouping over the tokens that write a name outside every
        // expression. Two arrays rather than one, because the two answer
        // different questions about the same binding: where its name is written
        // and where a value of it is reached, and only the first has a token
        // with no expression around it.
        const written_starts = try gpa.alloc(u32, bindings + 1);
        errdefer gpa.free(written_starts);
        @memset(written_starts, 0);
        for (0..token_count) |i| {
            const b = reached.writing(@intCast(i));
            if (b == BindingId.none) continue;
            written_starts[b.index()] += 1;
        }

        var written_total: u32 = 0;
        for (written_starts[0..bindings]) |*s| {
            const count = s.*;
            s.* = written_total;
            written_total += count;
        }
        written_starts[bindings] = written_total;

        const tokens = try gpa.alloc(TokenId, written_total);
        errdefer gpa.free(tokens);

        const written_filled = try gpa.alloc(u32, bindings);
        defer gpa.free(written_filled);
        @memcpy(written_filled, written_starts[0..bindings]);

        for (0..token_count) |i| {
            const b = reached.writing(@intCast(i));
            if (b == BindingId.none) continue;
            tokens[written_filled[b.index()]] = TokenId.at(@intCast(i));
            written_filled[b.index()] += 1;
        }

        return .{
            .initializers = initializers,
            .source_names = source_names,
            .aliases = aliases,
            .starts = starts,
            .spellings = held,
            .written_starts = written_starts,
            .tokens = tokens,
            .declared = declared,
            .declaration_bindings = declaration_bindings,
            .dotted = dotted,
            .semantic_names = semantic_names,
            .reads = reached.read,
        };
    }

    pub fn deinit(self: *Uses, gpa: std.mem.Allocator) void {
        self.initializers.deinit(gpa);
        self.source_names.deinit(gpa);
        deinitAliases(gpa, &self.aliases);
        gpa.free(self.starts);
        gpa.free(self.spellings);
        gpa.free(self.written_starts);
        gpa.free(self.tokens);
        gpa.free(self.declared);
        gpa.free(self.declaration_bindings);
        gpa.free(self.dotted);
        self.semantic_names.deinit(gpa);
    }

    fn deinitAliases(gpa: std.mem.Allocator, aliases: *std.AutoHashMapUnmanaged(node.DeclId, std.ArrayList(BindingId))) void {
        var runs = aliases.valueIterator();
        while (runs.next()) |run| run.deinit(gpa);
        aliases.deinit(gpa);
    }

    /// Only explicit `use` bindings participate; fields, variants and module
    /// aliases retain their independent source identities.
    pub fn aliasesOfDeclaration(self: *const Uses, declaration: node.DeclId) []const BindingId {
        return if (self.aliases.get(declaration)) |bindings| bindings.items else &.{};
    }

    pub fn sourceNameAt(self: *const Uses, token: TokenId) TokenId {
        return self.source_names.targets.get(token) orelse .none;
    }

    pub fn sourceNameIsUnpairedInterface(self: *const Uses, declaration: TokenId) bool {
        return self.source_names.unpaired_interfaces.contains(declaration);
    }

    /// The local a shorthand initializer reads at its shared field token.
    pub fn initializerBindingAt(self: *const Uses, token: TokenId) ?BindingId {
        return self.initializers.get(token);
    }

    pub fn sourceNameSites(self: *const Uses, declaration: TokenId) []const TokenId {
        return if (self.source_names.sites.get(declaration)) |sites| sites.items else &.{};
    }

    /// What each expression reaches, read through a counter.
    ///
    /// The build reaches the resolution only through this, so learning what an
    /// expression reaches and counting that it was learned are one operation. A
    /// count kept beside the loop counts what the loop says about itself, and
    /// says nothing about a loop written next to it.
    const Reached = struct {
        ast: *const Ast,
        res: *const Resolution,
        dotted: []const BindingId,
        semantic_names: *const std.AutoHashMapUnmanaged(TokenId, BindingId),
        read: u64 = 0,

        fn by(self: *Reached, expression: u32) Reach {
            self.read += 1;
            return reaches(self.ast, self.res, self.dotted, ExprId.at(expression));
        }

        /// What a token writes, where it writes a name outside every
        /// expression. Not counted in `read`, which is a statement about how
        /// many times each expression's target was consulted.
        ///
        /// Through the same function the finished index answers with, so a
        /// token the grouping holds is a token a cursor on it reaches.
        fn writing(self: *Reached, token: u32) BindingId {
            return writes(self.res, self.semantic_names, TokenId.at(token));
        }
    };

    /// The binding a token writes the name of, where no expression encloses it.
    ///
    /// The resolver's answer where it has one, and the matcher's for an
    /// argument that names the parameter it fills. Two sources and one
    /// question, so they are read together here and nowhere else: a capability
    /// that consulted only the resolver would find nothing at a token this
    /// index lists as a use, and a rename would offer to edit a site a cursor
    /// on it could not start from. A token is never both, so the two cannot
    /// disagree.
    pub fn writesAt(self: *const Uses, res: *const Resolution, t: TokenId) BindingId {
        return writes(res, &self.semantic_names, t);
    }

    fn writes(
        res: *const Resolution,
        semantic_names: *const std.AutoHashMapUnmanaged(TokenId, BindingId),
        t: TokenId,
    ) BindingId {
        if (t == TokenId.none) return BindingId.none;
        const b = res.writtenAt(t);
        if (b != BindingId.none) return b;
        if (semantic_names.count() == 0) return BindingId.none;
        return semantic_names.get(t) orelse BindingId.none;
    }

    /// What one expression reaches, and where that name is written.
    ///
    /// Two answers out of one branch, because they are one decision. The
    /// resolver settled both for a name; for the callee of a call written with
    /// a dot -- which the resolver settles on nothing -- the checker's record
    /// supplies the binding and the callee's own last name spells it, which is
    /// the token `a.of()` puts `of` at.
    const Reach = struct {
        binding: BindingId = .none,
        at: TokenId = .none,
    };

    /// What one expression reaches, which is what this index is grouped by.
    ///
    /// The resolver's answer where a name has one, and the checker's for the
    /// callee of a call written with a dot. Every capability that starts from a
    /// cursor asks this, and the grouping is built from it, so where a name is
    /// used and what a cursor reached cannot disagree.
    pub fn reachedBy(
        self: *const Uses,
        ast: *const Ast,
        res: *const Resolution,
        e: ExprId,
    ) BindingId {
        return reaches(ast, res, self.dotted, e).binding;
    }

    fn reaches(
        ast: *const Ast,
        res: *const Resolution,
        dotted: []const BindingId,
        e: ExprId,
    ) Reach {
        const b = res.targetOf(e);
        if (b != BindingId.none) return .{ .binding = b, .at = res.spelledAt(e) };
        if (e == ExprId.none or e.index() >= dotted.len) return .{};
        if (dotted[e.index()] == BindingId.none) return .{};
        return .{ .binding = dotted[e.index()], .at = ast.exprMain(e) };
    }

    /// The tokens spelling a binding where an expression reaches it, in the
    /// order they were written.
    pub fn of(self: *const Uses, b: BindingId) []const TokenId {
        if (b == BindingId.none or b.index() + 1 >= self.starts.len) return &.{};
        return self.spellings[self.starts[b.index()]..self.starts[b.index() + 1]];
    }

    /// The tokens that write a binding's name outside every expression, in the
    /// order they were written.
    pub fn writtenOf(self: *const Uses, b: BindingId) []const TokenId {
        if (b == BindingId.none or b.index() + 1 >= self.written_starts.len) return &.{};
        return self.tokens[self.written_starts[b.index()]..self.written_starts[b.index() + 1]];
    }

    /// The binding a token declares, or `.none` where it declares nothing.
    pub fn declaredAt(self: *const Uses, t: TokenId) BindingId {
        return declaredInTokens(self.declared, t);
    }

    fn declaredInTokens(declared: []const BindingId, t: TokenId) BindingId {
        if (t == TokenId.none or t.index() >= declared.len) return BindingId.none;
        return declared[t.index()];
    }

    /// The binding a source declaration names; generated declarations have none.
    pub fn bindingOfDeclaration(self: *const Uses, d: node.DeclId) BindingId {
        if (d == node.DeclId.none or d.index() >= self.declaration_bindings.len) return BindingId.none;
        return self.declaration_bindings[d.index()];
    }
};

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;

/// The token beginning at a byte of a case's text, which is how a case names a
/// declaration without asking the index what it holds.
fn tokenAt(checked: *const Analysis, at: usize) TokenId {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(checked.program.primaryFile()).?;
    for (part.token_start..part.token_end) |i| {
        const id = TokenId.at(@intCast(i));
        if (ast.tokenSpan(id).start == at) return id;
    }
    return TokenId.none;
}

/// What each of a binding's sites is spelled, which is the one reading that
/// says the answer names the uses and not merely some tokens.
fn spellings(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    b: BindingId,
) ![]const []const u8 {
    const ast = &checked.program.ast;
    const found = checked.uses.of(b);
    const out = try gpa.alloc([]const u8, found.len);
    for (out, found) |*o, t| o.* = ast.tokenText(t);
    return out;
}

test "a binding names every expression that reaches it" {
    const gpa = testing.allocator;

    const text =
        \\fn main() -> UInt8 {
        \\    let total: UInt8 = 1
        \\    total + total + total
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const total = checked.uses.declaredAt(tokenAt(&checked, std.mem.indexOf(u8, text, "total").?));
    try testing.expect(total != BindingId.none);

    const found = try spellings(gpa, &checked, total);
    defer gpa.free(found);
    try testing.expectEqual(@as(usize, 3), found.len);
    for (found) |s| try testing.expectEqualStrings("total", s);

    // In the order they were written, which is what a client shows a reader.
    const ast = &checked.program.ast;
    var last: u32 = 0;
    for (checked.uses.of(total)) |t| {
        const at = ast.tokenSpan(t).start;
        try testing.expect(at > last);
        last = at;
    }
}

test "a binding nothing reaches names no expression at all" {
    const gpa = testing.allocator;

    // Deliberately unused, which the language spells with a leading `_`, so
    // the program is one the compiler accepts rather than one it rejects.
    const text =
        \\fn keep(_spare: UInt8) -> UInt8 {
        \\    1
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    keep(2)
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const spare = checked.uses.declaredAt(tokenAt(&checked, std.mem.indexOf(u8, text, "_spare").?));
    try testing.expect(spare != BindingId.none);
    try testing.expectEqual(@as(usize, 0), checked.uses.of(spare).len);
}

test "a selected declaration and direct parameter name retain their uses" {
    const gpa = testing.allocator;
    const text =
        \\fn increment(value: UInt8) -> UInt8 { value }
        \\fn main() -> UInt8 {
        \\    let selected: fn(read value: UInt8) -> UInt8 = increment
        \\    selected(value: 1) + increment(value: 2)
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const decl_at = std.mem.indexOf(u8, text, "increment(value").?;
    const declaration = checked.uses.declaredAt(tokenAt(&checked, decl_at));
    try testing.expect(declaration != BindingId.none);
    try testing.expectEqual(@as(usize, 2), checked.uses.of(declaration).len);

    const param_at = std.mem.indexOf(u8, text, "value: UInt8").?;
    const parameter = checked.uses.declaredAt(tokenAt(&checked, param_at));
    try testing.expect(parameter != BindingId.none);
    try testing.expectEqual(@as(usize, 1), checked.uses.writtenOf(parameter).len);
}

test "borrow contract roots retain their own callable declaration identity" {
    const gpa = testing.allocator;
    const text =
        \\struct Holder { view: borrow UInt8 }
        \\enum Outcome { Item(Holder), Empty }
        \\fn observe(value: UInt8) -> borrow UInt8 where borrows(value) { borrow value }
        \\fn wrap(source: UInt8) -> Outcome where borrows(.Item.view: source) { .Item(.{ view = borrow source }) }
        \\fn retain(inout holder: Holder, source: UInt8) -> () where retains(holder.view: borrow source) { holder.view = borrow source }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 7
        \\    var holder: Holder = .{ view = borrow number }
        \\    retain(&holder, number)
        \\    let wrapped = wrap(number)
        \\    let selected: fn(read value: UInt8) -> borrow UInt8 where borrows(value) = observe
        \\    let view = selected(value: number)
        \\    match wrapped { Item(box) => *view + *holder.view + *box.view, Empty => 0 }
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    if (checked.sink.hasErrors()) for (checked.sink.items()) |diagnostic| {
        std.debug.print("{s}: {s} at {d}\n", .{ @tagName(diagnostic.code.?), diagnostic.message, diagnostic.labels[0].span.start });
    };
    try testing.expect(!checked.sink.hasErrors());
    const parameter = checked.uses.declaredAt(tokenAt(&checked, std.mem.indexOf(u8, text, "value: UInt8").?));
    try testing.expect(parameter != .none);
    try testing.expectEqual(@as(usize, 1), checked.uses.writtenOf(parameter).len);
    const direct_root = std.mem.indexOf(u8, text, "borrows(value)").? + "borrows(".len;
    try testing.expectEqual(parameter, checked.uses.writesAt(&checked.semantics.res, tokenAt(&checked, direct_root)));
    const contextual_root = std.mem.lastIndexOf(u8, text, "borrows(value)").? + "borrows(".len;
    const contextual_parameter = std.mem.lastIndexOf(u8, text, "value: UInt8").?;
    try testing.expectEqual(tokenAt(&checked, contextual_parameter), checked.uses.sourceNameAt(tokenAt(&checked, contextual_root)));
    const holder_parameter = checked.uses.declaredAt(tokenAt(&checked, std.mem.indexOf(u8, text, "holder: Holder").?));
    const destination = std.mem.indexOf(u8, text, "retains(holder.view").? + "retains(".len;
    try testing.expectEqual(holder_parameter, checked.uses.writesAt(&checked.semantics.res, tokenAt(&checked, destination)));
    // Field and variant contract components are not parameter references.
    const target = std.mem.indexOf(u8, text, "borrows(.Item.view:").? + "borrows(.".len;
    for ([_]usize{ target, target + "Item.".len, destination + "holder.".len }) |component| {
        try testing.expectEqual(BindingId.none, checked.uses.writesAt(&checked.semantics.res, tokenAt(&checked, component)));
    }
}

test "a converted lambda keeps contextual labels separate from its binders" {
    const gpa = testing.allocator;
    const text =
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
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const annotation_at = std.mem.indexOf(u8, text, "first: UInt8").?;
    const lambda_at = std.mem.indexOfPos(u8, text, annotation_at + 1, "first").?;
    const argument_at = std.mem.lastIndexOf(u8, text, "first:").?;
    const parameter = checked.uses.declaredAt(tokenAt(&checked, lambda_at));
    try testing.expect(parameter != BindingId.none);
    const annotation_token = tokenAt(&checked, annotation_at);
    try testing.expectEqual(annotation_token, checked.uses.sourceNameAt(annotation_token));
    try testing.expectEqual(annotation_token, checked.uses.sourceNameAt(tokenAt(&checked, argument_at)));
    try testing.expectEqual(@as(usize, 0), checked.uses.writtenOf(parameter).len);
}

test "a binding names the sites of every file that reaches it" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 {\n    size() + twice()\n}\n" },
        .{
            .path = "app/sizes.lin",
            .text = "fn size() -> UInt8 {\n    1\n}\n\nfn twice() -> UInt8 {\n    size() + size()\n}\n",
        },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const ast = &checked.program.ast;
    var size = BindingId.none;
    for (0..checked.semantics.res.bindingCount()) |i| {
        const b = BindingId.at(@intCast(i));
        const at = checked.semantics.res.declaringToken(b);
        if (at == TokenId.none or at.index() >= ast.tokenCount()) continue;
        if (!std.mem.eql(u8, ast.tokenText(at), "size")) continue;
        // The one this file declares: the walk covers the library too, and any
        // library binding may share the name.
        if (!std.mem.eql(u8, checked.table.get(ast.fileOf(at)).path, "app/sizes.lin")) continue;
        size = b;
    }
    try testing.expect(size != BindingId.none);

    var in_main: usize = 0;
    var in_sizes: usize = 0;
    for (checked.uses.of(size)) |t| {
        const path = checked.table.get(ast.fileOf(t)).path;
        if (std.mem.eql(u8, path, "app/main.lin")) in_main += 1;
        if (std.mem.eql(u8, path, "app/sizes.lin")) in_sizes += 1;
    }
    try testing.expectEqual(@as(usize, 1), in_main);
    try testing.expectEqual(@as(usize, 2), in_sizes);
}

test "a token that declares nothing names nothing" {
    const gpa = testing.allocator;

    const text = "fn main() -> UInt8 {\n    let x: UInt8 = 1\n    x\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    // The `let` keyword, the use of `x` below it, and no token at all. None of
    // the three declares anything, and neither does whatever a primitive is:
    // `UInt8` is introduced at no token.
    const let = tokenAt(&checked, std.mem.indexOf(u8, text, "let").?);
    try testing.expectEqual(BindingId.none, checked.uses.declaredAt(let));
    const use = tokenAt(&checked, std.mem.lastIndexOf(u8, text, "x").?);
    try testing.expectEqual(BindingId.none, checked.uses.declaredAt(use));
    try testing.expectEqual(BindingId.none, checked.uses.declaredAt(TokenId.none));

    // And nothing names nothing: a cursor that reached no binding asks this,
    // and an answer of every expression in the program would be the worst
    // possible one.
    try testing.expectEqual(@as(usize, 0), checked.uses.of(BindingId.none).len);
}

test "a call recorded twice is grouped under the record every pass reads" {
    const gpa = testing.allocator;

    // Two traits, each declaring an operation, and one call written with a
    // dot. Which of the two the call reaches is the whole of what a second
    // tie-break would change.
    const text =
        \\struct Account {
        \\    balance: UInt8,
        \\}
        \\
        \\trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\
        \\trait Weigh {
        \\    fn mass(x: Self) -> UInt8
        \\}
        \\
        \\impl Measure for Account {
        \\    fn of(x: Self) -> UInt8 {
        \\        x.balance
        \\    }
        \\}
        \\
        \\impl Weigh for Account {
        \\    fn mass(x: Self) -> UInt8 {
        \\        x.balance
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ balance = 1 }
        \\    a.of()
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const res = &checked.semantics.res;
    const of = checked.uses.declaredAt(tokenAt(&checked, std.mem.indexOf(u8, text, "of(x: Self) -> UInt8\n").?));
    const mass = checked.uses.declaredAt(tokenAt(&checked, std.mem.indexOf(u8, text, "mass(x: Self) -> UInt8\n").?));
    try testing.expect(of != BindingId.none and mass != BindingId.none);

    // The checker records one signature per call. A second record for that
    // call is what a re-check under another expectation would leave, and the
    // question it raises -- which of the two answers for the call -- is
    // answered once, by the index ownership and lowering read.
    //
    // This program's own call is found rather than counted. The library is
    // checked beside it, so a method call written anywhere in the library is a
    // record here too: a total is a statement about how the library happens to
    // be written, and this one is about the checker.
    const settled = checked.semantics.typing.postfix;
    const of_decl: u32 = @intCast(res.declIfDeclared(of).index());
    var mine: ?u32 = null;
    for (settled) |row| {
        const normal = checked.semantics.typing.call_index.callOf(&checked.semantics.typing, ExprId.at(row.call)) orelse continue;
        const reaches_of = switch (normal.target) {
            .declared => |decl| decl == node.DeclId.at(of_decl),
            .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => false,
        };
        if (!reaches_of) continue;
        try testing.expect(mine == null);
        mine = row.call;
    }
    try testing.expect(mine != null);

    var forged = checked.semantics.typing;
    const original = checked.semantics.typing.call_index.callOf(&checked.semantics.typing, ExprId.at(mine.?)).?;
    var redirected = original;
    redirected.target = .{ .declared = res.declIfDeclared(mass) };
    forged.calls = &.{ original, redirected };

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    const ast = &checked.program.ast;
    forged.call_index = try CallIndex.build(a, checked.semantics.expanded.ast.exprCount(), &forged);
    defer forged.call_index.deinit(a);
    const calls = &forged.call_index;
    const twice = try Uses.build(a, ast, res, &forged, calls);

    try testing.expectEqual(types_mod.CallTarget{ .declared = res.declIfDeclared(of) }, calls.callOf(&forged, ExprId.at(mine.?)).?.target);
    try testing.expectEqual(@as(usize, 1), twice.of(of).len);
    try testing.expectEqual(@as(usize, 0), twice.of(mass).len);
}

/// One function of `n` locals, each reaching the one before it: many bindings
/// and many expressions in one module, which is the shape that separates a
/// grouping from a scan.
fn manyBindings(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("fn main() -> UInt8 {\n    let v0: UInt8 = 1\n");
    for (1..n) |i| try w.print("    let v{d}: UInt8 = v{d}\n", .{ i, i - 1 });
    try w.print("    v{d}\n}}\n", .{n - 1});
    return out.toOwnedSlice();
}

test "the index reads each expression's target twice, not once per binding" {
    const gpa = testing.allocator;

    const text = try manyBindings(gpa, 500);
    defer gpa.free(text);

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const expressions: u64 = checked.program.ast.exprCount();
    const bindings: u64 = checked.semantics.res.bindingCount();

    // Once to count what reaches each binding and once to place it. A build
    // that asked each binding which expressions reach it reads one target per
    // (binding, expression) pair instead, which on this module is more -- so
    // the number above is not one such a build could also report.
    try testing.expectEqual(2 * expressions, checked.uses.reads);
    try testing.expect(bindings * expressions > checked.uses.reads);
}

fn buildFieldsWithFailures(gpa: std.mem.Allocator, checked: *const analysis_mod.Analysis) !void {
    var fields = try SourceNameUses.build(gpa, &checked.program.ast, &checked.semantics.res, &checked.semantics.typing);
    defer fields.deinit(gpa);
}

test "transparent fields release partial indexes on allocation failure" {
    const gpa = testing.allocator;
    const text = "struct Entry { value: UInt8 }\nfn main() -> UInt8 { let entry: Entry = .{ value = 3 }; entry.value }";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    try testing.checkAllAllocationFailures(gpa, buildFieldsWithFailures, .{&checked});
}

fn buildUsesWithFailures(gpa: std.mem.Allocator, checked: *const analysis_mod.Analysis) !void {
    var uses = try Uses.build(gpa, &checked.program.ast, &checked.semantics.res, &checked.semantics.typing, &checked.semantics.typing.call_index);
    defer uses.deinit(gpa);
}

test "record shorthand releases partial local indexes on allocation failure" {
    const gpa = testing.allocator;
    const text = "struct Entry { value: UInt8 }\nfn main() -> UInt8 { let value: UInt8 = 3; let entry: Entry = .{ value }; entry.value }";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    try testing.checkAllAllocationFailures(gpa, buildUsesWithFailures, .{&checked});
}

test "constructor callable names share their source interface identity" {
    const gpa = testing.allocator;
    const text =
        \\enum Held { Some(borrow UInt64) }
        \\fn main() -> UInt8 {
        \\    let make: fn(sink payload: borrow UInt64) -> Held where carries(.Some: payload) = Held.Some
        \\    let owner: UInt64 = 7
        \\    match make(payload: borrow owner) { Some(value) => if *value == 7 { 0 } else { 1 } }
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const ast = &checked.program.ast;
    var declaration: TokenId = .none;
    var count: usize = 0;
    for (0..ast.tokenCount()) |index| {
        const token = TokenId.at(@intCast(index));
        if (!std.mem.eql(u8, checked.table.get(ast.fileOf(token)).path, "main.lin")) continue;
        if (!std.mem.eql(u8, ast.tokenText(token), "payload")) continue;
        const target = checked.uses.sourceNameAt(token);
        try testing.expect(target != .none);
        if (declaration == .none) declaration = target;
        try testing.expectEqual(declaration, target);
        try testing.expectEqual(BindingId.none, checked.uses.writesAt(&checked.semantics.res, token));
        count += 1;
    }
    try testing.expectEqual(@as(usize, 3), count);
    try testing.expectEqual(@as(usize, 3), checked.uses.sourceNameSites(declaration).len);
}

test "an inherent member used as a function value keeps its member uses" {
    const gpa = testing.allocator;
    const text =
        \\struct Scale { factor: UInt64 }
        \\impl Scale {
        \\    fn double(value: UInt64) -> UInt64 { value * 2 }
        \\}
        \\fn main() -> UInt8 {
        \\    let operation: fn(value: UInt64) -> UInt64 = Scale.double
        \\    UInt8(operation(3) - Scale.double(3))
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const decl_at = std.mem.indexOf(u8, text, "double(value: UInt64) -> UInt64 {").?;
    const declaration = checked.uses.declaredAt(tokenAt(&checked, decl_at));
    try testing.expect(declaration != BindingId.none);
    try testing.expectEqual(@as(usize, 2), checked.uses.of(declaration).len);
}

test "use binding families release partial indexes on allocation failure" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "import values\nuse values.Entry\nfn main() -> UInt8 { let entry = Entry { value = 3 }; entry.value }" },
        .{ .path = "app/values/values.lin", .text = "pub struct Entry { value: UInt8 }" },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    try testing.checkAllAllocationFailures(gpa, buildUsesWithFailures, .{&checked});
}
