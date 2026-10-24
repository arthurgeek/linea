const std = @import("std");
const cloneColumns = @import("../support/columns.zig").cloneExact;
const FileId = @import("../support/source.zig").FileId;
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const StringId = @import("../support/interner.zig").StringId;
const Source = @import("../support/source.zig").Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const literal_text = @import("../support/text.zig");
const token = @import("../lexer/token.zig");
const TokenId = token.TokenId;
const TokenRange = token.TokenRange;
const TokenList = token.TokenList;
const node = @import("node.zig");
const Table = @import("../support/table.zig").Table;
const name_case = @import("../support/name_case.zig");
const Expr = node.Expr;
const Stmt = node.Stmt;
const Block = node.Block;
const Decl = node.Decl;
const Param = node.Param;
const Variant = node.Variant;
const ParamRange = node.ParamRange;
const ExprId = node.ExprId;
const StmtId = node.StmtId;
const BlockId = node.BlockId;
const DeclId = node.DeclId;

const ExprList = std.MultiArrayList(Expr);
const StmtList = std.MultiArrayList(Stmt);
const DeclList = std.MultiArrayList(Decl);

/// What one file of a module contributed to the tree.
///
/// A module is one tree, so which file a token belongs to is not constant
/// across it. The boundaries are stored rather than a file column on every
/// node: files number in the handful and nodes in the thousands.
///
/// Every run is written down rather than derived from the part before it. A
/// file's own nodes are what a document's outline, its folds, its inlay hints
/// and its colouring are each about, and each of those open-coded a walk of
/// `parts` remembering the previous boundary -- four answers to one question,
/// alike on every tree with one part per file and with nothing to say about
/// one where that stops holding. A run is also what makes those answers cost
/// the file rather than the program: a walk of every node in the compilation
/// asking which file it came from is the module's library included.
///
/// Each run is contiguous because a file is parsed in one go, so every node
/// the builder took while that file's tokens were being read is that file's.
pub const FilePart = struct {
    file: FileId,
    /// Borrowed from the `Source` that produced it.
    path: []const u8,
    /// Borrowed from the `Source` that produced it.
    source: []const u8,
    /// The first token this file contributed.
    token_start: u32,
    /// One past the last token this file contributed.
    token_end: u32,
    decl_start: u32,
    decl_end: u32,
    stmt_start: u32,
    stmt_end: u32,
    expr_start: u32,
    expr_end: u32,
};

/// A parsed syntax tree. Immutable once the builder returns it: later passes
/// annotate through side tables keyed by these ids, never by writing back.
///
/// One tree holds one module, which is every file in a directory. Ids run
/// across those files rather than restarting per file, which is what lets a
/// pass over a module stay a pass over a tree -- and is the same claim the
/// language makes, that a module's files see each other and have no order.
/// The identifiers of a dotted path, walked in order. See `Ast.pathElements`.
pub const PathElements = struct {
    ast: *const Ast,
    at: u32,
    end: u32,

    pub fn next(self: *PathElements) ?TokenId {
        while (self.at < self.end) {
            const id = TokenId.at(self.at);
            self.at += 1;
            if (self.ast.tokenTag(id) == .identifier) return id;
        }
        return null;
    }
};

pub const Ast = struct {
    /// In token order, so a token's file is the first part it falls inside.
    /// Never empty.
    parts: []const FilePart,
    tokens: TokenList.Slice,
    exprs: ExprList.Slice,
    stmts: StmtList.Slice,
    blocks: []const Block,
    block_stmts: []const StmtId,
    /// The program. Every declaration in the table is one, in source order,
    /// so there is no range: the table *is* the program.
    decls: DeclList.Slice,
    /// Written attribute groups, keyed densely by declaration.
    decl_attribute_groups: []const node.AttributeGroupRange,
    params: []const Param,
    captures: []const node.Capture,
    type_params: []const node.TypeParam,
    bounds: []const node.TraitBound,
    where_predicates: []const node.WherePredicate,
    contracts: []const node.Contract,
    contract_steps: []const node.ContractStep,
    derive_traits: []const node.DeriveTrait,
    attribute_items: []const node.AttributeItem,
    attribute_groups: []const node.AttributeGroup,
    template_requirements: []const node.TemplateRequirement,
    type_refs: []const node.TypeRef,
    callable_types: []const node.CallableType,
    variants: []const Variant,
    fields: []const node.Field,
    /// Children of nodes that hold more than a payload's two indices. A node
    /// stores where its run begins; how many it owns follows from its tag.
    extra: []const ExprId,
    /// Parallel to `extra`, index for index: where `extra[i]` is a call's
    /// argument, `call_names[i]` is the token of the name that argument
    /// wrote, or `.none` where it was positional. Kept the same length as
    /// `extra` so a call's own `ExtraIndex` indexes both without a second
    /// offset to keep in sync.
    call_names: []const TokenId,
    /// One entry per value embedded in an interpolation, in interpolation
    /// order. Text pieces have no entry because their format is fixed.
    interpolation_formats: []const node.InterpolationFormat,
    /// The written type before a named struct literal, keyed by expression.
    /// Every other expression, including a contextual literal, has `.none`.
    struct_literal_heads: []const node.TypeRefId,
    /// The type-list reading of each bracket written directly before a call,
    /// in increasing expression order.
    bracket_types: []const node.BracketTypes,

    pub fn deinit(self: *Ast, gpa: std.mem.Allocator) void {
        gpa.free(self.parts);
        self.tokens.deinit(gpa);
        self.exprs.deinit(gpa);
        self.stmts.deinit(gpa);
        gpa.free(self.blocks);
        gpa.free(self.block_stmts);
        gpa.free(self.extra);
        gpa.free(self.call_names);
        gpa.free(self.interpolation_formats);
        gpa.free(self.struct_literal_heads);
        gpa.free(self.bracket_types);
        self.decls.deinit(gpa);
        gpa.free(self.decl_attribute_groups);
        gpa.free(self.params);
        gpa.free(self.captures);
        gpa.free(self.type_params);
        gpa.free(self.bounds);
        gpa.free(self.where_predicates);
        gpa.free(self.contracts);
        gpa.free(self.contract_steps);
        gpa.free(self.derive_traits);
        gpa.free(self.attribute_items);
        gpa.free(self.attribute_groups);
        gpa.free(self.template_requirements);
        gpa.free(self.type_refs);
        gpa.free(self.callable_types);
        gpa.free(self.variants);
        gpa.free(self.fields);
        self.* = undefined;
    }

    pub fn declCount(self: *const Ast) u32 {
        return @intCast(self.decls.len);
    }

    /// A table with one entry per declaration this tree holds.
    ///
    /// Built here because this is what owns the count. A table keyed by
    /// `DeclId` and sized by anything else answers for the wrong elements --
    /// and sized *larger* it never trips the bounds check either, so it simply
    /// says `fill` for every declaration and the pass that reads it reports
    /// nothing, which is the failure a green suite cannot see.
    ///
    /// The caller owns the result.
    pub fn declTable(
        self: *const Ast,
        gpa: std.mem.Allocator,
        comptime T: type,
        fill: T,
    ) !Table(DeclId, T) {
        return Table(DeclId, T).of(gpa, self.declCount(), fill);
    }

    pub fn declTag(self: *const Ast, id: DeclId) Decl.Tag {
        return self.decls.items(.tag)[id.index()];
    }

    pub fn declMain(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.main_token)[id.index()];
    }

    pub fn declTokens(self: *const Ast, id: DeclId) TokenRange {
        return self.decls.items(.token_range)[id.index()];
    }

    pub fn declName(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.name)[id.index()];
    }

    /// Whether a declaration is a trait's signature: written inside something,
    /// and carrying no body.
    ///
    /// An `impl`'s member is written inside something too and has a body, which
    /// is the whole of the difference. Asked here because the answer is a fact
    /// about the tree, and every pass that wants it wants the same one -- open
    /// at each site, "no body" drifts into meaning whatever that site needed.
    ///
    /// A projection a trait declares is one of them. `Self` in its parameters
    /// and a bare declared type in its result are read through this, so a
    /// reading that admitted only `fn` would put a projection's header in a
    /// scope no other member of the same braces is in.
    pub fn declIsSignature(self: *const Ast, id: DeclId) bool {
        const tag = self.declTag(id);
        return (tag == .function or tag == .projection) and
            (self.declBody(id) == ExprId.none or self.declIsProvided(id)) and
            self.memberOwner(id) != TokenId.none;
    }

    /// Whether a trait's operation carries its own body, which every type
    /// implementing the trait runs and no implementation supplies. A provided
    /// operation is a signature to every reader asking what a call through
    /// the trait reaches, and has a body to check and to lower.
    pub fn declIsProvided(self: *const Ast, id: DeclId) bool {
        return self.decls.items(.origin)[id.index()] == .provided;
    }

    /// Whether a declaration is part of the relation a trait is: one side asks
    /// and the other answers.
    ///
    /// A trait's own signature, a type a trait declares, and a member of an
    /// implementation. Each is named for whatever stands opposite it rather
    /// than for anything that calls it, so each is reached by being reached
    /// through the trait -- which is the one question a reader of any of them
    /// is asking, and asking it three ways left the three drifting apart.
    pub fn declIsTraitMember(self: *const Ast, id: DeclId) bool {
        return self.declIsSignature(id) or
            self.declTag(id) == .associated_type or
            self.declTrait(id) != TokenId.none;
    }

    pub fn declBody(self: *const Ast, id: DeclId) ExprId {
        return self.decls.items(.body)[id.index()];
    }

    /// Whether this declaration names a symbol the runtime provides.
    ///
    /// Distinct from having no body, which a trait's signature also has: a
    /// signature is not called at all and this is called and not defined here.
    pub fn declIsExtern(self: *const Ast, id: DeclId) bool {
        return self.decls.items(.origin)[id.index()] == .external;
    }

    /// Whether an implementation was written `default impl`. The contextual
    /// `default` is the declaration's first token only in that form; an
    /// ordinary implementation begins with `impl`.
    pub fn declIsDefault(self: *const Ast, id: DeclId) bool {
        if (self.declTag(id) != .impl_) return false;
        const main = self.declMain(id);
        return self.tokenTag(main) == .identifier and std.mem.eql(u8, self.tokenText(main), "default");
    }

    /// Whether this function is a test: one the compiler writes the only call
    /// to, and which nothing that ships contains.
    pub fn declIsTest(self: *const Ast, id: DeclId) bool {
        return self.decls.items(.is_test)[id.index()];
    }

    /// Whether this test was written with a trap expectation.
    pub fn declExpectsTrap(self: *const Ast, id: DeclId) bool {
        return self.decls.items(.expects_trap)[id.index()];
    }

    /// Ordered field and dereference steps, normalized once during parsing.
    pub fn contractSteps(self: *const Ast, path: node.ContractPath) []const node.ContractStep {
        return self.contract_steps[path.steps.start..path.steps.end];
    }

    /// Written dependency contracts for this declaration.
    pub fn declContracts(self: *const Ast, id: DeclId) []const node.Contract {
        const r = self.decls.items(.contracts)[id.index()];
        return self.contracts[r.start..r.end];
    }

    /// What a constant is bound to, and `.none` for every other declaration.
    pub fn declInit(self: *const Ast, id: DeclId) ExprId {
        return self.decls.items(.init)[id.index()];
    }

    pub fn declVia(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.delegation)[id.index()].via;
    }

    pub fn declDelegation(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.delegation)[id.index()].target;
    }

    /// The tokens of an `import`'s dotted path, dots included.
    pub fn declPath(self: *const Ast, id: DeclId) TokenRange {
        return self.decls.items(.path)[id.index()];
    }

    /// The elements of a declaration's dotted path, in the order written.
    ///
    /// A path is stored as the token range it was written over, dots and all,
    /// because the formatter has to write it back exactly. Every other reader
    /// wants the identifiers -- the loader joining them into a directory, the
    /// resolver counting them for [M-Import], the dump printing them -- and
    /// each filtered the dots out for itself. Which tokens of the range are
    /// its elements is one question about the representation, so it is
    /// answered beside the representation.
    pub fn pathElements(self: *const Ast, id: DeclId) PathElements {
        const r = self.declPath(id);
        return .{ .ast = self, .at = @intCast(r.start.index()), .end = @intCast(r.end.index()) };
    }

    /// The name after the `impl`, or the trait's name, whose braces hold this
    /// declaration, or `.none` at the top level.
    ///
    /// Where a declaration is written, which is what the formatter and the
    /// source rewrites need: a test written inside an `impl` is printed and
    /// moved with it. Whether the declaration belongs to that type is
    /// `memberOwner`.
    pub fn declOwner(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.owner)[id.index()];
    }

    /// The name of the type or trait a declaration is a member of, or `.none`
    /// where it is a member of nothing.
    ///
    /// A test is a member of nothing wherever it is written. Inside an `impl`
    /// it is named, resolved and run at module scope ([S-Test]): it is not
    /// instantiated, so the implementation's parameters and `Self` would name
    /// nothing in it, and the compiler writes its one call, so no path through
    /// the type reaches it. Every question about membership asks this, so that
    /// is decided here once.
    pub fn memberOwner(self: *const Ast, id: DeclId) TokenId {
        if (self.declIsTest(id)) return .none;
        return self.declOwner(id);
    }

    /// The trait an `impl` names, whole.
    pub fn declTraitRef(self: *const Ast, id: DeclId) node.TraitRef {
        return self.decls.items(.trait_ref)[id.index()];
    }

    /// The arguments an `impl` supplied for its trait's parameters.
    pub fn declTraitArgs(self: *const Ast, id: DeclId) node.TypeRefRange {
        return self.declTraitRef(id).args;
    }

    /// The final name of the trait an `impl` names, or `.none` where it is
    /// inherent.
    pub fn declTrait(self: *const Ast, id: DeclId) TokenId {
        return self.declTraitRef(id).name;
    }

    /// The head an `impl` names, whole: its written start and the arguments a
    /// named constructor was applied to. Unit starts at `(` and has no name in
    /// the language, but remains one complete written type here.
    pub fn declHead(self: *const Ast, id: DeclId) node.TypeRef {
        if (self.decls.items(.head_kind)[id.index()] == .callable) {
            return self.typeArgs(self.decls.items(.head_args)[id.index()])[0];
        }
        return .{
            .at = self.declName(id),
            .name = self.declName(id),
            .args = self.decls.items(.head_args)[id.index()],
            .kind = self.decls.items(.head_kind)[id.index()],
        };
    }

    /// How an implementation or derive names its head: as written where the
    /// head is a tuple or a callable type, which have no name token, as `()`
    /// for unit, and by its name otherwise.
    pub fn implHeadText(self: *const Ast, id: DeclId) []const u8 {
        const head = self.declHead(id);
        if (head.kind == .tuple or head.kind == .callable) return self.writtenText(head);
        if (self.tokenTag(head.at) == .l_paren) return "()";
        return self.tokenText(self.declName(id));
    }

    /// Whether an implementation's whole written head names one of its own
    /// parameters. Bounds and module ownership are decided by semantic passes.
    pub fn declHasParameterHead(self: *const Ast, id: DeclId) bool {
        const head = self.declHead(id);
        if (head.kind != .named or head.args.len() != 0) return false;
        for (self.declTypeParams(id)) |parameter| {
            if (self.tokenName(parameter.name) == self.tokenName(head.name)) return true;
        }
        return false;
    }

    /// The ownership policy written on a type declaration.
    pub fn declOwnershipPolicy(self: *const Ast, id: DeclId) node.OwnershipPolicy {
        return self.decls.items(.ownership_policy)[id.index()];
    }

    /// Whether a struct or an enum is marked `@carrier`: values built from it
    /// live as long as it does, so a signature with one such parameter takes it
    /// as the source of its result when it writes no clause. Bounded by the
    /// attributes written on the declaration.
    pub fn declIsCarrier(self: *const Ast, id: DeclId) bool {
        switch (self.declTag(id)) {
            .struct_, .enum_ => {},
            else => return false,
        }
        for (self.declAttributeGroups(id)) |group| {
            for (self.attributeItems(group)) |item| if (item.kind == .carrier) return true;
        }
        return false;
    }

    /// How far a declaration's name reaches outside its own module.
    pub fn declVisibility(self: *const Ast, id: DeclId) node.Visibility {
        return self.decls.items(.visibility)[id.index()];
    }

    /// Whether a linker publishes this declaration.
    pub fn declIsExport(self: *const Ast, id: DeclId) bool {
        return self.decls.items(.is_export)[id.index()];
    }

    /// The written return type, whole.
    pub fn declReturnRef(self: *const Ast, id: DeclId) node.TypeRef {
        return self.decls.items(.returns)[id.index()];
    }

    pub fn declReturnToken(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.returns)[id.index()].name;
    }

    /// What a variant carries, in declaration order.
    pub fn variantFields(self: *const Ast, v: Variant) []const node.Field {
        return self.fields[v.fields.start..v.fields.end];
    }

    /// A structure's fields.
    pub fn declFields(self: *const Ast, id: DeclId) []const node.Field {
        const r = self.decls.items(.fields)[id.index()];
        return self.fields[r.start..r.end];
    }

    /// The name a structure gives its field at position `i`. A tuple's
    /// components are reached by position -- in a literal and in a pattern --
    /// and selected by this name, so everything that keys a component by
    /// name reads it here.
    pub fn declFieldName(self: *const Ast, id: DeclId, i: usize) StringId {
        return self.tokenName(self.declFields(id)[i].name);
    }

    test "declFieldName reads the interned name of the field at a position" {
        const gpa = testing.allocator;
        const source: Source = .{ .path = "t.lin", .text = "P x y" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

        var b = Ast.Builder.init(gpa);
        errdefer b.deinit();

        const mark = b.fieldMark();
        try b.addField(.{ .name = TokenId.at(1), .written = .{ .name = TokenId.at(0) } });
        try b.addField(.{ .name = TokenId.at(2), .written = .{ .name = TokenId.at(0) } });
        const decl = try b.addDecl(.{
            .tag = .struct_,
            .main_token = TokenId.at(0),
            .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(2) },
            .name = TokenId.at(0),
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = .none },
            .body = .none,
            .variants = .{ .start = 0, .end = 0 },
            .fields = .{ .start = mark, .end = b.fieldMark() },
        });

        var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
        defer ast.deinit(gpa);

        try testing.expectEqual(ast.tokenName(TokenId.at(1)), ast.declFieldName(decl, 0));
        try testing.expectEqual(ast.tokenName(TokenId.at(2)), ast.declFieldName(decl, 1));
        try testing.expect(ast.declFieldName(decl, 0) != ast.declFieldName(decl, 1));
    }

    pub fn declVariants(self: *const Ast, id: DeclId) []const Variant {
        const r = self.decls.items(.variants)[id.index()];
        return self.variants[r.start..r.end];
    }

    /// Indexes callable parameter spellings for lexical contract references.
    pub fn parameterNames(self: *const Ast, gpa: std.mem.Allocator, params: []const Param) !std.AutoHashMapUnmanaged(StringId, u32) {
        var names: std.AutoHashMapUnmanaged(StringId, u32) = .empty;
        errdefer names.deinit(gpa);
        for (params, 0..) |param, index| {
            if (param.name != .none) try names.put(gpa, self.tokenName(param.name), @intCast(index));
        }
        return names;
    }

    pub fn declParams(self: *const Ast, id: DeclId) []const Param {
        const r = self.decls.items(.params)[id.index()];
        return self.params[r.start..r.end];
    }

    /// The range of the parameter table a run of it occupies, for a run
    /// sliced out of that table.
    pub fn paramRangeOf(self: *const Ast, run: []const Param) node.ParamRange {
        if (run.len == 0) return .{ .start = 0, .end = 0 };
        const start: u32 = @intCast(@divExact(@intFromPtr(run.ptr) - @intFromPtr(self.params.ptr), @sizeOf(Param)));
        return .{ .start = start, .end = start + @as(u32, @intCast(run.len)) };
    }

    test paramRangeOf {
        var ast: Ast = undefined;
        const params = [_]Param{
            .{ .name = .none, .written = .{ .name = .none }, .convention = .read, .default = .none },
            .{ .name = .none, .written = .{ .name = .none }, .convention = .sink, .default = .none },
        };
        ast.params = &params;
        const range = ast.paramRangeOf(params[1..2]);
        try std.testing.expectEqual(@as(u32, 1), range.start);
        try std.testing.expectEqual(@as(u32, 2), range.end);
    }

    /// How a parameter is written: its name, or for a lambda parameter taken
    /// apart by a tuple pattern, the pattern.
    pub fn paramSpelling(self: *const Ast, p: Param) []const u8 {
        return if (p.pattern != ExprId.none) self.exprText(p.pattern) else self.tokenText(p.name);
    }

    test paramSpelling {
        const gpa = testing.allocator;
        const source: Source = .{ .path = "t.lin", .text = "x (a, b)" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

        var b = Ast.Builder.init(gpa);
        errdefer b.deinit();
        const left = try b.addLiteral(.name_ref, TokenId.at(2), .{ .start = TokenId.at(2), .end = TokenId.at(3) });
        const right = try b.addLiteral(.name_ref, TokenId.at(4), .{ .start = TokenId.at(4), .end = TokenId.at(5) });
        const pattern = try b.addCall(TokenId.at(1), .{ .start = TokenId.at(1), .end = TokenId.at(6) }, ExprId.none, &.{ left, right }, &.{});
        b.retag(pattern, .tuple_pattern);
        try b.addTypeRef(.{ .kind = .named, .name = .none });
        _ = try b.addDecl(.{
            .tag = .function,
            .main_token = TokenId.at(0),
            .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(6) },
            .name = TokenId.at(0),
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = TokenId.none },
            .body = pattern,
            .variants = .{ .start = 0, .end = 0 },
        });
        var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
        defer ast.deinit(gpa);

        const named: Param = .{ .name = TokenId.at(0), .written = .{ .name = .none }, .convention = .read, .default = .none };
        const patterned: Param = .{ .name = TokenId.at(1), .pattern = pattern, .written = .{ .name = .none }, .convention = .read, .default = .none };
        try testing.expectEqualStrings("x", ast.paramSpelling(named));
        try testing.expectEqualStrings("(a, b)", ast.paramSpelling(patterned));
    }

    /// Whether the author wrote this parameter's convention.
    ///
    /// `read` is the default, so a parameter that says nothing already reads
    /// that way and the word is a fact about the tokens rather than about the
    /// convention -- which is why it is asked of the tokens. The formatter must
    /// not delete a word someone wrote and a hint must not invent one they did
    /// not, and those are the same question.
    pub fn paramSpellsConvention(self: *const Ast, p: Param) bool {
        return self.paramConventionToken(p) != .none;
    }

    /// The written convention token, skipping comments before the name.
    pub fn paramConventionToken(self: *const Ast, p: Param) TokenId {
        if (p.name == .none) return .none;
        const tags = self.tokens.items(.tag);
        var i = p.name.index();
        while (i > 0) {
            i -= 1;
            if (tags[i] == .comment) continue;
            return switch (tags[i]) {
                .keyword_read, .keyword_inout, .keyword_sink => TokenId.at(@intCast(i)),
                else => .none,
            };
        }
        return .none;
    }

    /// The types a declaration is generic over.
    pub fn declTypeParams(self: *const Ast, id: DeclId) []const node.TypeParam {
        const r = self.decls.items(.type_params)[id.index()];
        return self.type_params[r.start..r.end];
    }

    /// How many type arguments a written type must give a declaration: its
    /// parameters before the first one that has a default. Defaults trail, so
    /// the rest are filled from the declaration.
    pub fn declRequiredTypeParams(self: *const Ast, id: DeclId) u32 {
        for (self.declTypeParams(id), 0..) |parameter, i| {
            if (parameter.default.wasWritten()) return @intCast(i);
        }
        return @intCast(self.declTypeParams(id).len);
    }

    pub fn declTypeParamRange(self: *const Ast, id: DeclId) node.TypeParamRange {
        return self.decls.items(.type_params)[id.index()];
    }

    /// What a type parameter requires of an argument, as written. Each is a
    /// name the resolver classifies as a universe or a trait.
    pub fn boundsOf(self: *const Ast, p: node.TypeParam) []const node.TraitBound {
        return self.boundsIn(p.bounds);
    }

    pub fn boundsIn(self: *const Ast, range: node.BoundRange) []const node.TraitBound {
        return self.bounds[range.start..range.end];
    }

    /// What a declared type requires of whatever settles it, as written. The
    /// same table a type parameter's bounds come from, so a bound means one
    /// thing wherever it is written.
    pub fn declBounds(self: *const Ast, id: DeclId) []const node.TraitBound {
        const r = self.decls.items(.bounds)[id.index()];
        return self.boundsIn(r);
    }

    /// The predicates in a callable's trailing `where` clause, as written.
    pub fn declWherePredicates(self: *const Ast, id: DeclId) []const node.WherePredicate {
        const r = self.decls.items(.where_predicates)[id.index()];
        return self.where_predicates[r.start..r.end];
    }

    pub fn declWhereToken(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.where_at)[id.index()];
    }

    pub fn deriveTraits(self: *const Ast, id: DeclId) []const node.DeriveTrait {
        const r = self.deriveTraitRange(id);
        return self.derive_traits[r.start..r.end];
    }

    pub fn deriveTraitRange(self: *const Ast, id: DeclId) node.DeriveTraitRange {
        return self.decls.items(.derive_traits)[id.index()];
    }

    pub fn deriveTrait(self: *const Ast, id: node.DeriveTraitId) node.DeriveTrait {
        return self.derive_traits[id.index()];
    }

    pub fn attachedDeriveTraitRange(self: *const Ast, id: DeclId) node.DeriveTraitRange {
        return if (self.declTag(id) == .struct_ or self.declTag(id) == .enum_ or self.declTag(id) == .newtype)
            self.deriveTraitRange(id)
        else
            .empty;
    }

    pub fn deriveRequestTraitRange(self: *const Ast, id: DeclId) node.DeriveTraitRange {
        return if (self.declTag(id) == .derive_impl) self.deriveTraitRange(id) else self.attachedDeriveTraitRange(id);
    }

    pub fn declAttributeGroupRange(self: *const Ast, id: DeclId) node.AttributeGroupRange {
        return self.decl_attribute_groups[id.index()];
    }

    pub fn declAttributeGroups(self: *const Ast, id: DeclId) []const node.AttributeGroup {
        return self.attributeGroups(self.declAttributeGroupRange(id));
    }

    pub fn attributeGroups(self: *const Ast, range: node.AttributeGroupRange) []const node.AttributeGroup {
        return self.attribute_groups[range.start..range.end];
    }

    pub fn attributeItems(self: *const Ast, group: node.AttributeGroup) []const node.AttributeItem {
        return self.attribute_items[group.items.start..group.items.end];
    }

    /// The written group containing `at`. Groups are appended in token order,
    /// including refused and dangling groups, so lookup is logarithmic.
    pub fn attributeGroupAt(self: *const Ast, at: TokenId) ?node.AttributeGroup {
        var lo: usize = 0;
        var hi = self.attribute_groups.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const group = self.attribute_groups[mid];
            if (at.index() < group.tokens.start.index()) {
                hi = mid;
            } else if (at.index() >= group.tokens.end.index()) {
                lo = mid + 1;
            } else {
                return group;
            }
        }
        return null;
    }

    pub fn deriveIsGrouped(self: *const Ast, id: DeclId) bool {
        return self.decls.items(.derive_syntax)[id.index()].group_open != .none;
    }

    pub fn deriveHeadIsValid(self: *const Ast, id: DeclId) bool {
        return self.decls.items(.derive_syntax)[id.index()].head_valid;
    }

    pub fn deriveGroupOpen(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.derive_syntax)[id.index()].group_open;
    }

    pub fn deriveGroupClose(self: *const Ast, id: DeclId) TokenId {
        return self.decls.items(.derive_syntax)[id.index()].group_close;
    }

    pub fn templateRequirements(self: *const Ast, id: DeclId) []const node.TemplateRequirement {
        const r = self.templateRequirementRange(id);
        return self.template_requirements[r.start..r.end];
    }

    pub fn templateRequirementRange(self: *const Ast, id: DeclId) node.TemplateRequirementRange {
        return self.decls.items(.template_requirements)[id.index()];
    }

    /// The arguments a declaration's return type was given.
    pub fn declReturnArgs(self: *const Ast, id: DeclId) node.TypeRefRange {
        return self.decls.items(.returns)[id.index()].args;
    }

    /// A newtype's `where it in lo..=hi` clause, or `null` where none was
    /// written. Meaningless for a declaration that is not a newtype.
    pub fn newtypeRefinement(self: *const Ast, id: DeclId) ?node.Refinement {
        if (!self.decls.items(.has_refinement)[id.index()]) return null;
        return .{
            .at = self.decls.items(.refinement_at)[id.index()],
            .lo_minus = self.decls.items(.refinement_lo_minus)[id.index()],
            .lo_token = self.decls.items(.refinement_lo)[id.index()],
            .hi_minus = self.decls.items(.refinement_hi_minus)[id.index()],
            .hi_token = self.decls.items(.refinement_hi)[id.index()],
            .inclusive = self.decls.items(.refinement_inclusive)[id.index()],
        };
    }

    /// The arguments an annotation was given, each a written type in its own
    /// right so a nested one needs no second shape.
    pub fn typeArgs(self: *const Ast, r: node.TypeRefRange) []const node.TypeRef {
        return self.type_refs[r.start..r.end];
    }

    pub fn structLiteralHead(self: *const Ast, id: ExprId) ?node.TypeRef {
        const head = self.struct_literal_heads[id.index()];
        return if (head == .none) null else self.type_refs[head.index()];
    }

    /// The base a structure literal ends with, `..base`, or null where the
    /// literal writes every field itself. The base occupies the callee slot of
    /// the call payload, which a structure literal has no other use for.
    pub fn structLiteralBase(self: *const Ast, id: ExprId) ?ExprId {
        std.debug.assert(self.exprTag(id) == .struct_literal);
        const base = self.exprs.items(.data)[id.index()].call.callee;
        return if (base == ExprId.none) null else base;
    }

    test structLiteralBase {
        const gpa = testing.allocator;
        const source: Source = .{ .path = "t.lin", .text = ".{ ..a }" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

        var b = Ast.Builder.init(gpa);
        errdefer b.deinit();
        const whole: TokenRange = .{ .start = TokenId.at(0), .end = TokenId.at(4) };
        const base = try b.addLiteral(.name_ref, TokenId.at(2), .{ .start = TokenId.at(2), .end = TokenId.at(3) });
        const updated = try b.addCall(TokenId.at(0), whole, base, &.{}, &.{});
        b.retag(updated, .struct_literal);
        const complete = try b.addCall(TokenId.at(0), whole, ExprId.none, &.{}, &.{});
        b.retag(complete, .struct_literal);
        _ = try b.addDecl(.{
            .tag = .function,
            .main_token = TokenId.at(0),
            .token_range = whole,
            .name = TokenId.at(0),
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = TokenId.none },
            .body = updated,
            .variants = .{ .start = 0, .end = 0 },
        });
        var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
        defer ast.deinit(gpa);

        try testing.expectEqual(@as(?ExprId, base), ast.structLiteralBase(updated));
        try testing.expectEqual(@as(?ExprId, null), ast.structLiteralBase(complete));
    }

    /// The types a bracket directly before a call holds, where its contents
    /// read as a list of types. An index node with none has only its index
    /// reading.
    ///
    /// **Bound:** a binary search over the brackets that have such a reading.
    pub fn bracketTypes(self: *const Ast, id: ExprId) ?node.TypeRefRange {
        return findBracketTypes(self.bracket_types, id);
    }

    test "bracketTypes answers only for the brackets recorded with a type reading" {
        var b = Ast.Builder.init(testing.allocator);
        defer b.deinit();
        const plain = try b.addExpr(.{ .tag = .name_ref, .main_token = TokenId.at(0), .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(1) }, .data = .{ .none = {} } });
        const typed = try b.addExpr(.{ .tag = .name_ref, .main_token = TokenId.at(0), .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(1) }, .data = .{ .none = {} } });
        try b.addBracketTypes(typed, .{ .start = 2, .end = 3 });
        try testing.expectEqual(@as(?node.TypeRefRange, null), findBracketTypes(b.bracket_types.items, plain));
        try testing.expectEqual(@as(?node.TypeRefRange, .{ .start = 2, .end = 3 }), findBracketTypes(b.bracket_types.items, typed));
    }

    pub fn callableType(self: *const Ast, ref: node.TypeRef) node.CallableType {
        std.debug.assert(ref.kind == .callable);
        return self.callableTypeById(ref.callable);
    }

    pub fn callableTypeById(self: *const Ast, id: node.CallableTypeId) node.CallableType {
        return self.callable_types[id.index()];
    }

    /// The shape a written callable type keys its implementations by.
    pub fn callableShape(self: *const Ast, ref: node.TypeRef) ?node.CallableShape {
        const callable = self.callableType(ref);
        var shape: node.CallableShape.Builder = .begin(callable.invocation);
        for (self.params[callable.params.start..callable.params.end]) |param| shape.parameter(param.convention);
        return shape.finish();
    }

    pub fn callableRef(self: *const Ast, id: node.CallableTypeId) node.TypeRef {
        const callable = self.callableTypeById(id);
        return .{ .kind = .callable, .at = callable.at, .name = .none, .callable = id };
    }

    /// The names and dots a run was written from, in the order they were
    /// written and with nothing else in it.
    ///
    /// One walk, because every reader of a run wants the same one: what a
    /// settled reference resolves to is the last name in it, and a dump and the
    /// formatter each print the run as text. Each had written the walk out, and
    /// each had to know that a comment may sit inside the range -- so each was
    /// a place where a run could come to mean something slightly else.
    ///
    /// **Bound:** the tokens the run itself occupies. The parser records the
    /// range tight, from the first token of the run to one past its last, so
    /// this reads no token the run does not hold.
    pub fn runOf(self: *const Ast, range: TokenRange) TokenRun {
        return .{ .ast = self, .at = range.start.index(), .end = range.end.index() };
    }

    /// The tokens of a run, trivia left out.
    pub const TokenRun = struct {
        ast: *const Ast,
        at: u32,
        end: u32,

        pub fn next(self: *TokenRun) ?TokenId {
            while (self.at < self.end) {
                const id = TokenId.at(self.at);
                self.at += 1;
                // A comment may sit between two elements of a run. It belongs
                // to the line rather than to the run, and a reader
                // concatenating it into one writes a `//` into the middle of a
                // path.
                if (self.ast.tokenTag(id) == .comment) continue;
                return id;
            }
            return null;
        }
    };

    /// The names a run was written from, in order and with the dots left out.
    ///
    /// One filter, because counting the names of a run and walking them are
    /// the same question: a reader deciding for itself what counts as a name
    /// could count a run of one length and walk one of another.
    ///
    /// **Bound:** the tokens the run itself occupies.
    pub fn namesOf(self: *const Ast, range: TokenRange) NameRun {
        return .{ .run = self.runOf(range) };
    }

    /// The names of a run, everything that is not one left out.
    pub const NameRun = struct {
        run: TokenRun,

        pub fn next(self: *NameRun) ?TokenId {
            while (self.run.next()) |id| {
                if (self.run.ast.tokenTag(id) == .identifier) return id;
            }
            return null;
        }
    };

    pub fn selectionBase(self: *const Ast, ref: node.TypeRef) node.TypeRef {
        std.debug.assert(ref.kind == .selection);
        return self.type_refs[ref.base.index()];
    }

    /// The whole of a written type, its arguments' brackets included:
    /// `Option[B.D]` rather than `writtenSpan`'s `Option`.
    pub fn wholeWrittenSpan(self: *const Ast, ref: node.TypeRef) Span {
        if (ref.kind == .named and ref.name != TokenId.none and ref.args.len() > 0) return self.firstBracketsSpan(ref.name);
        return self.writtenSpan(ref);
    }

    /// From `start` through the bracket closing the first one opened at or
    /// after it. Bound: the written type's own tokens.
    fn firstBracketsSpan(self: *const Ast, start: TokenId) Span {
        const open = self.tokenSpan(start);
        var depth: u32 = 0;
        var at = start.index();
        while (at < self.tokenCount()) : (at += 1) {
            switch (self.tokenTag(TokenId.at(at)).nesting()) {
                1 => depth += 1,
                -1 => {
                    depth -|= 1;
                    if (depth == 0) return .{ .start = open.start, .end = self.tokenSpan(TokenId.at(at)).end };
                },
                else => {},
            }
        }
        return open;
    }

    /// The written form's extent through its last named component.
    pub fn writtenSpan(self: *const Ast, ref: node.TypeRef) Span {
        if (ref.kind == .grouped) return .{ .start = self.tokenSpan(ref.at).start, .end = self.tokenSpan(ref.name).end };
        if (ref.kind == .borrow) {
            const head = self.tokenSpan(ref.at);
            const args = self.typeArgs(ref.args);
            if (args.len == 0 or !args[0].wasWritten()) return head;
            return .{ .start = head.start, .end = self.writtenSpan(args[0]).end };
        }
        if (ref.kind == .callable) {
            const head = self.tokenSpan(ref.at);
            const result = self.callableType(ref).result;
            // Without a result it ends at the `)` closing its parameters.
            if (!result.wasWritten()) return self.firstBracketsSpan(ref.at);
            return .{ .start = head.start, .end = self.writtenSpan(result).end };
        }
        if (ref.kind == .selection) return .{
            .start = self.tokenSpan(ref.at).start,
            .end = self.tokenSpan(if (ref.name == .none) ref.dot else ref.name).end,
        };
        // `[T; N]` and `(A, B)` name no token, so each spans its brackets.
        if (ref.kind == .array or ref.kind == .tuple) return self.firstBracketsSpan(ref.at);
        if (ref.name == TokenId.none) return self.tokenSpan(ref.at);
        const head = self.tokenSpan(ref.name);
        if (ref.kind == .named and ref.name != TokenId.none and self.tokenTag(ref.name) == .l_paren) {
            const close = TokenId.at(ref.name.index() + 1);
            if (self.tokenTag(close) == .r_paren) return .{ .start = head.start, .end = self.tokenSpan(close).end };
        }
        return head;
    }

    test writtenSpan {
        const gpa = testing.allocator;
        const source: Source = .{ .path = "t.lin", .text = "[[UInt8; 2]; 3]" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var b = Ast.Builder.init(gpa);
        var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
        defer ast.deinit(gpa);

        const outer = ast.writtenSpan(.{ .kind = .array, .at = TokenId.at(0), .name = .none });
        try testing.expectEqualStrings("[[UInt8; 2]; 3]", source.text[outer.start..outer.end]);
        const inner = ast.writtenSpan(.{ .kind = .array, .at = TokenId.at(1), .name = .none });
        try testing.expectEqualStrings("[UInt8; 2]", source.text[inner.start..inner.end]);
    }

    test "a tuple type spans its parentheses, and its text is all of it" {
        const gpa = testing.allocator;
        const source: Source = .{ .path = "t.lin", .text = "(UInt8, (Bool, Str))" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var b = Ast.Builder.init(gpa);
        errdefer b.deinit();
        try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(1), .name = TokenId.at(1) });
        try b.addTypeRef(.{ .kind = .tuple, .at = TokenId.at(3), .name = .none, .args = .{ .start = 2, .end = 4 } });
        try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(4), .name = TokenId.at(4) });
        try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(6), .name = TokenId.at(6) });
        var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
        defer ast.deinit(gpa);

        const outer: node.TypeRef = .{ .kind = .tuple, .at = TokenId.at(0), .name = .none, .args = .{ .start = 0, .end = 2 } };
        const whole = ast.writtenSpan(outer);
        try testing.expectEqualStrings("(UInt8, (Bool, Str))", source.text[whole.start..whole.end]);
        try testing.expectEqualStrings("(UInt8, (Bool, Str))", ast.writtenText(outer));
        try testing.expectEqualStrings("(Bool, Str)", ast.writtenText(ast.typeArgs(outer.args)[1]));
    }

    /// The span of a declaration's name, which is what a diagnostic about the
    /// declaration itself underlines. An implementation and a derive request
    /// declare no name; what stands for one is the whole written head.
    pub fn declNameSpan(self: *const Ast, id: DeclId) Span {
        if (self.declTag(id) == .impl_ or self.declTag(id) == .derive_impl) return self.writtenSpan(self.declHead(id));
        return self.tokenSpan(self.declName(id));
    }

    /// The full extent of a declaration, which is what a rewrite of the source
    /// moves when it moves the declaration.
    pub fn declSpan(self: *const Ast, id: DeclId) Span {
        return self.rangeSpan(self.declTokens(id));
    }

    pub fn exprCount(self: *const Ast) u32 {
        return @intCast(self.exprs.len);
    }

    pub fn tokenCount(self: *const Ast) u32 {
        return @intCast(self.tokens.len);
    }

    pub fn stmtCount(self: *const Ast) u32 {
        return @intCast(self.stmts.len);
    }

    pub fn exprTag(self: *const Ast, id: ExprId) Expr.Tag {
        return self.exprs.items(.tag)[id.index()];
    }

    /// Whether `id` refers to a binding: a written name, or the argument a
    /// lambda's tuple-pattern parameter stands for, which is the parameter's
    /// own binding. Every analysis reading a place's root through its binding
    /// asks this, so the argument is read as a named parameter is.
    pub fn refersToBinding(self: *const Ast, id: ExprId) bool {
        return switch (self.exprTag(id)) {
            .name_ref, .param_argument => true,
            else => false,
        };
    }

    test refersToBinding {
        const gpa = testing.allocator;
        const source: Source = .{ .path = "t.lin", .text = "a ( 1" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

        var b = Ast.Builder.init(gpa);
        errdefer b.deinit();
        const name = try b.addLiteral(.name_ref, TokenId.at(0), .{ .start = TokenId.at(0), .end = TokenId.at(1) });
        const argument = try b.addLiteral(.param_argument, TokenId.at(1), .{ .start = TokenId.at(1), .end = TokenId.at(2) });
        const literal = try b.addLiteral(.int_literal, TokenId.at(2), .{ .start = TokenId.at(2), .end = TokenId.at(3) });
        try b.addTypeRef(.{ .kind = .named, .name = .none });
        _ = try b.addDecl(.{
            .tag = .function,
            .main_token = TokenId.at(0),
            .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(3) },
            .name = TokenId.at(0),
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = TokenId.none },
            .body = literal,
            .variants = .{ .start = 0, .end = 0 },
        });
        var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
        defer ast.deinit(gpa);

        try testing.expect(ast.refersToBinding(name));
        try testing.expect(ast.refersToBinding(argument));
        try testing.expect(!ast.refersToBinding(literal));
    }

    pub fn stmtTag(self: *const Ast, id: StmtId) Stmt.Tag {
        return self.stmts.items(.tag)[id.index()];
    }

    pub fn exprMain(self: *const Ast, id: ExprId) TokenId {
        return self.exprs.items(.main_token)[id.index()];
    }

    pub fn stmtMain(self: *const Ast, id: StmtId) TokenId {
        return self.stmts.items(.main_token)[id.index()];
    }

    /// Which of the two truths a `bool_literal` names, read from the keyword
    /// that spells it rather than stored beside it. One place answers it: the
    /// checker folds a truth value and lowering emits one, and a second
    /// reading of the same keyword is a place the two could come to disagree.
    pub fn boolIsTrue(self: *const Ast, id: ExprId) bool {
        std.debug.assert(self.exprTag(id) == .bool_literal);
        return self.tokenTag(self.exprMain(id)) == .keyword_true;
    }

    pub fn exprTokens(self: *const Ast, id: ExprId) TokenRange {
        return self.exprs.items(.token_range)[id.index()];
    }

    pub fn stmtTokens(self: *const Ast, id: StmtId) TokenRange {
        return self.stmts.items(.token_range)[id.index()];
    }

    pub fn stmtData(self: *const Ast, id: StmtId) Stmt.Data {
        return self.stmts.items(.data)[id.index()];
    }

    /// Whether a binding may be assigned again. Read from the keyword that
    /// introduced it rather than stored: `let` and `var` differ only in that
    /// word, and a flag beside it could disagree with it.
    pub fn stmtIsMutable(self: *const Ast, id: StmtId) bool {
        std.debug.assert(self.stmtTag(id) == .let_decl);
        return self.tokenTag(self.stmtMain(id)) == .keyword_var;
    }

    /// Whether a `let` or `var` binding was written `defer let` or `defer var`,
    /// which is where its statement's tokens begin.
    pub fn stmtIsDeferredBinding(self: *const Ast, id: StmtId) bool {
        std.debug.assert(self.stmtTag(id) == .let_decl);
        return self.tokenTag(self.stmtTokens(id).start) == .keyword_defer;
    }

    /// Whether a call is the release a `defer let` schedules, whose callee is a
    /// name standing at the `defer` keyword: the operation it calls is the
    /// `release` of its one argument.
    pub fn callIsScheduledRelease(self: *const Ast, id: ExprId) bool {
        return self.exprTag(id) == .call and self.tokenTag(self.exprMain(self.call(id).callee)) == .keyword_defer;
    }

    /// The source text a type was written in, its arguments included.
    pub fn writtenText(self: *const Ast, ref: node.TypeRef) []const u8 {
        return self.writtenWhole(ref).slice(self.partOf(ref.at).source);
    }

    /// `writtenSpan`, reaching past a named type's arguments to the bracket
    /// that closes them. Bound: the written type's own tokens.
    fn writtenWhole(self: *const Ast, ref: node.TypeRef) Span {
        const span = self.writtenSpan(ref);
        if (ref.kind != .named and ref.kind != .selection) return span;
        const args = self.typeArgs(ref.args);
        if (args.len == 0) return span;
        const last = self.writtenWhole(args[args.len - 1]);
        var at = ref.at.index();
        while (at < self.tokenCount() and self.tokenSpan(TokenId.at(at)).start < last.end) : (at += 1) {}
        while (at < self.tokenCount()) : (at += 1) {
            if (self.tokenTag(TokenId.at(at)) == .r_bracket) return .{ .start = span.start, .end = self.tokenSpan(TokenId.at(at)).end };
        }
        return .{ .start = span.start, .end = last.end };
    }

    /// The written count or inference marker, without interpreting either.
    pub fn arrayLengthText(self: *const Ast, ref: node.TypeRef) []const u8 {
        return if (ref.inferred_length != .none)
            self.tokenText(ref.inferred_length)
        else
            self.exprText(ref.length);
    }

    /// The semantic type inside explicit type parentheses.
    pub fn withoutTypeGroups(self: *const Ast, written: node.TypeRef) node.TypeRef {
        var result = written;
        while (result.kind == .grouped) result = self.typeArgs(result.args)[0];
        return result;
    }

    /// What a parenthesised expression wraps, however many layers deep.
    ///
    /// Parentheses are a node because a formatter that dropped them would
    /// rewrite the programmer's source. Every walk that asks what an
    /// expression *is* therefore has to step through them: `(o).inner` names
    /// the same place as `o.inner`, and a rule that could not see that would
    /// hold for one spelling and not the other.
    pub fn withoutGroups(self: *const Ast, id: ExprId) ExprId {
        var at = id;
        while (self.exprTag(at) == .grouped) at = self.unaryOperand(at);
        return at;
    }

    test "parentheses are stepped through and a tuple is not" {
        const gpa = testing.allocator;
        const source: Source = .{ .path = "t.lin", .text = "((1, 2))" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

        var b = Ast.Builder.init(gpa);
        errdefer b.deinit();
        const one = try b.addLiteral(.int_literal, TokenId.at(2), .{ .start = TokenId.at(2), .end = TokenId.at(3) });
        const two = try b.addLiteral(.int_literal, TokenId.at(4), .{ .start = TokenId.at(4), .end = TokenId.at(5) });
        const pair = try b.addCall(TokenId.at(1), .{ .start = TokenId.at(1), .end = TokenId.at(6) }, ExprId.none, &.{ one, two }, &.{});
        b.retag(pair, .tuple_literal);
        const grouped = try b.addExpr(.{
            .tag = .grouped,
            .main_token = TokenId.at(0),
            .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(7) },
            .data = .{ .unary = .{ .operand = pair } },
        });
        try b.addTypeRef(.{ .kind = .named, .name = .none });
        try b.addTypeRef(.{ .kind = .named, .name = .none });
        try b.addTypeRef(.{ .kind = .tuple, .name = .none, .args = .{ .start = 0, .end = 2 } });
        _ = try b.addDecl(.{
            .tag = .function,
            .main_token = TokenId.at(0),
            .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(7) },
            .name = TokenId.at(0),
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = TokenId.none },
            .body = grouped,
            .variants = .{ .start = 0, .end = 0 },
        });
        var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
        defer ast.deinit(gpa);

        try testing.expectEqual(pair, ast.withoutGroups(grouped));
        const written: node.TypeRef = .{ .kind = .grouped, .name = .none, .args = .{ .start = 2, .end = 3 } };
        const inner = ast.withoutTypeGroups(written);
        try testing.expectEqual(node.TypeRef.Kind.tuple, inner.kind);
        try testing.expectEqual(@as(u32, 2), inner.args.len());
    }

    /// Where a place path leads, and how many steps it took.
    ///
    /// `root` is the expression the selections ran out at, which is a name
    /// where the path is one and is whatever else was written where it is not.
    /// `depth` counts the steps, so zero is a whole thing and anything else is
    /// a part of one.
    pub const PlacePath = struct { root: ExprId, depth: u32 };

    /// The place a chain of selections names, followed to its root.
    ///
    /// An index is a step like a field is: `a[i].x` and `a.x[i]` each reach one
    /// element of one binding, and a move takes the whole binding either way.
    ///
    /// One walk on the tree rather than one per pass, because every pass asking
    /// where a path leads is asking the same question of the same nodes:
    /// ownership decides what a `copy` copies from it, and a projection is
    /// refused unless its body is one -- and two walks would come to disagree
    /// about which spellings are paths, which is precisely the disagreement
    /// neither pass could see.
    pub fn placePath(self: *const Ast, id: ExprId) PlacePath {
        var depth: u32 = 0;
        var steps = self.placeSteps(id);
        while (steps.next()) |_| depth += 1;
        return .{ .root = steps.at, .depth = depth };
    }

    /// The selections a place path is made of, outermost first, ending at the
    /// root the path is rooted in.
    ///
    /// The step-yielding form of `placePath`, and the reason there is only one
    /// walk: a rule about a path asks something of each step rather than of the
    /// root, and a rule that spelled the descent out again would hold for the
    /// formers its author had in mind and not for one added afterwards. A
    /// former therefore lands in the switch below and every rule inherits it.
    pub const PlaceSteps = struct {
        ast: *const Ast,
        /// What the walk has reached, which is the root once it is spent.
        at: ExprId,

        pub fn next(self: *PlaceSteps) ?ExprId {
            const step = self.at;
            self.at = self.ast.stepBase(step) orelse return null;
            return step;
        }
    };

    /// What one selection step selects from -- the operand of a field or a
    /// dereference, the head of an index, seen through parentheses -- or null
    /// where `id` is not a selection step. The one place that says which
    /// expression forms are steps of a place path.
    pub fn stepBase(self: *const Ast, id: ExprId) ?ExprId {
        return switch (self.exprTag(id)) {
            .field, .dereference => self.withoutGroups(self.unaryOperand(id)),
            .index => self.withoutGroups(self.binary(id).lhs),
            else => null,
        };
    }

    test stepBase {
        var sample = try PathSample.build(testing.allocator);
        defer sample.ast.deinit(testing.allocator);
        const ast = &sample.ast;

        try testing.expectEqual(@as(?ExprId, sample.name), ast.stepBase(sample.field));
        try testing.expectEqual(@as(?ExprId, sample.field), ast.stepBase(sample.index));
        try testing.expectEqual(@as(?ExprId, sample.index), ast.stepBase(sample.deref));
        try testing.expectEqual(@as(?ExprId, null), ast.stepBase(sample.name));
        try testing.expectEqual(@as(?ExprId, null), ast.stepBase(sample.grouped_deref));
        try testing.expectEqual(@as(?ExprId, null), ast.stepBase(sample.call));
    }

    /// The expression a path written as an argument or a target is rooted at,
    /// through a `&` mark, parentheses and every selection step. A name where
    /// the path is one, and whatever else was written where it is not.
    pub fn pathRoot(self: *const Ast, id: ExprId) ExprId {
        var steps = self.placeSteps(if (self.exprTag(id) == .marked) self.unaryOperand(id) else id);
        while (steps.next()) |_| {}
        return steps.at;
    }

    test pathRoot {
        var sample = try PathSample.build(testing.allocator);
        defer sample.ast.deinit(testing.allocator);
        const ast = &sample.ast;

        try testing.expectEqual(sample.name, ast.pathRoot(sample.name));
        try testing.expectEqual(sample.name, ast.pathRoot(sample.deref));
        try testing.expectEqual(sample.name, ast.pathRoot(sample.marked_deref));
        try testing.expectEqual(sample.name, ast.pathRoot(sample.grouped_deref));
        try testing.expectEqual(sample.call, ast.pathRoot(sample.call_field));
    }

    /// Whether an expression, seen through parentheses, is a selection step:
    /// a path whose address is walked rather than a value evaluated.
    pub fn isSelection(self: *const Ast, id: ExprId) bool {
        return self.stepBase(self.withoutGroups(id)) != null;
    }

    test isSelection {
        var sample = try PathSample.build(testing.allocator);
        defer sample.ast.deinit(testing.allocator);
        const ast = &sample.ast;

        try testing.expect(ast.isSelection(sample.field));
        try testing.expect(ast.isSelection(sample.index));
        try testing.expect(ast.isSelection(sample.grouped_deref));
        try testing.expect(!ast.isSelection(sample.name));
        try testing.expect(!ast.isSelection(sample.call));
        try testing.expect(!ast.isSelection(sample.marked_deref));
    }

    pub fn placeSteps(self: *const Ast, id: ExprId) PlaceSteps {
        return .{ .ast = self, .at = self.withoutGroups(id) };
    }

    pub fn unaryOperand(self: *const Ast, id: ExprId) ExprId {
        std.debug.assert(self.exprTag(id).payload() == .unary);
        return self.exprs.items(.data)[id.index()].unary.operand;
    }

    pub fn binary(self: *const Ast, id: ExprId) struct { lhs: ExprId, rhs: ExprId } {
        std.debug.assert(self.exprTag(id).payload() == .binary);
        const d = self.exprs.items(.data)[id.index()].binary;
        return .{ .lhs = d.lhs, .rhs = d.rhs };
    }

    pub fn conditional(self: *const Ast, id: ExprId) struct { cond: ExprId, then: ExprId, otherwise: ExprId } {
        std.debug.assert(self.exprTag(id).payload() == .conditional);
        const d = self.exprs.items(.data)[id.index()].conditional;
        const at = d.arms.index();
        return .{ .cond = d.cond, .then = self.extra[at], .otherwise = self.extra[at + 1] };
    }

    /// A range's two ends. `lo` sits inline; `hi` is the first of the two
    /// extra slots the flag `rangeInclusive` reads the second of.
    pub fn rangeEnds(self: *const Ast, id: ExprId) struct { lhs: ExprId, rhs: ExprId } {
        std.debug.assert(self.exprTag(id) == .range);
        const d = self.exprs.items(.data)[id.index()].range;
        const at = d.extra.index();
        return .{ .lhs = d.lhs, .rhs = self.extra[at] };
    }

    /// Whether a range includes its high end: `..=` does, `..` does not.
    pub fn rangeInclusive(self: *const Ast, id: ExprId) bool {
        std.debug.assert(self.exprTag(id) == .range);
        const d = self.exprs.items(.data)[id.index()].range;
        return self.extra[d.extra.index() + 1].index() != 0;
    }

    pub fn blockOf(self: *const Ast, id: ExprId) Block {
        std.debug.assert(self.exprTag(id) == .block);
        return self.blocks[self.exprs.items(.data)[id.index()].block.index()];
    }

    /// A shorthand field pair shares one written identifier between its label
    /// and value or binder. Explicit equal names occupy distinct tokens.
    /// A label the parser could not read names no field, so it abbreviates
    /// nothing.
    pub fn fieldIsShorthand(self: *const Ast, label: ExprId, value: ExprId) bool {
        return self.exprTag(label) != .err and self.exprMain(label) == self.exprMain(value);
    }

    /// Whether a pattern's part is a binder: a bare lowercase name or `_`,
    /// in a payload, a tuple's component or after a struct field's `:`. A
    /// bare capitalised name there is a variant, which binds nothing. A name's
    /// case is part of its kind, so the spelling settles which it is; the
    /// resolver declares a binder by this answer and the checker types it by
    /// the same one.
    pub fn partBinds(self: *const Ast, part: ExprId) bool {
        if (self.exprTag(part) != .name_ref) return false;
        return name_case.of(self.tokenText(self.exprMain(part))) != .capital;
    }

    /// The forms a pattern node takes. Every pass that walks a pattern
    /// switches on this with no `else`, so a form added here is a compile
    /// error at each of them until it says what the form does.
    pub const PatternForm = enum {
        /// A bare name: a binder or `_` inside a pattern, `_` or a variant
        /// carrying nothing at an arm's head, as `partBinds` and the checker
        /// read it.
        name,
        /// `N(p, ...)`: a variant taking apart what it carries, or a newtype
        /// taking apart its base.
        call,
        /// `(p, ...)`.
        tuple,
        /// `S { f: p, ... }`.
        struct_,
        /// An integer literal, a negated one, or a string literal.
        literal,
        /// `lo..hi` or `lo..=hi`.
        range,
        /// A part the parser could not read, reported where it stands.
        malformed,
        /// An expression no pattern form admits, refused by the checker.
        other,
    };

    pub fn patternForm(self: *const Ast, pattern: ExprId) PatternForm {
        return switch (self.exprTag(pattern)) {
            .name_ref => .name,
            .call => .call,
            .tuple_pattern => .tuple,
            .struct_pattern => .struct_,
            .int_literal, .negate, .str_literal => .literal,
            .range => .range,
            .err => .malformed,
            else => .other,
        };
    }

    /// Whether a walk's binder is a tuple pattern, which takes each element
    /// apart, rather than one name for the whole element. The grammar gives a
    /// `for` a name, a tuple pattern, or a part it could not read, which binds
    /// as a name binding nothing does.
    pub fn walkBinderIsTuple(self: *const Ast, binder: ExprId) bool {
        return switch (self.patternForm(binder)) {
            .tuple => true,
            .name, .malformed => false,
            .call, .struct_, .literal, .range, .other => unreachable,
        };
    }

    /// The parts a pattern node takes its value apart into, in source order:
    /// what a variant's or newtype's pattern names inside its parentheses, a
    /// tuple pattern's components, and a struct pattern's field patterns
    /// (each after the field it takes). Nothing for any other form. The one
    /// place a pattern's argument layout is read.
    pub fn patternParts(self: *const Ast, pattern: ExprId) PatternParts {
        return switch (self.patternForm(pattern)) {
            .struct_ => .{ .args = self.call(pattern).args, .at = 1, .stride = 2 },
            .tuple, .call => .{ .args = self.call(pattern).args, .at = 0, .stride = 1 },
            .name, .literal, .range, .malformed, .other => .{ .args = &.{}, .at = 0, .stride = 1 },
        };
    }

    pub const PatternParts = struct {
        args: []const ExprId,
        at: usize,
        stride: usize,

        /// One part of a pattern.
        pub const Part = struct {
            /// The part's own pattern.
            node: ExprId,
            /// Its index among the pattern node's arguments.
            index: usize,
            /// The field name a struct pattern writes before the part, and
            /// `.none` for every other form.
            label: ExprId,
        };

        /// How many parts the pattern node writes.
        pub fn count(self: PatternParts) usize {
            if (self.at >= self.args.len) return 0;
            return (self.args.len - self.at + self.stride - 1) / self.stride;
        }

        /// The first part, or null where the node writes none.
        pub fn first(self: PatternParts) ?Part {
            var copy = self;
            return copy.next();
        }

        pub fn next(self: *PatternParts) ?Part {
            if (self.at >= self.args.len) return null;
            const part: Part = .{
                .node = self.args[self.at],
                .index = self.at,
                .label = if (self.stride == 2) self.args[self.at - 1] else ExprId.none,
            };
            self.at += self.stride;
            return part;
        }
    };

    /// A call's callee and its arguments. The count is stored ahead of the
    /// run, so the arguments are a slice rather than a walk.
    pub fn call(self: *const Ast, id: ExprId) struct { callee: ExprId, args: []const ExprId } {
        // The tag's own answer about how it is encoded, rather than a second
        // list here: a tag that says it uses the call payload is a tag whose
        // callee and run are these, and a list would be a place for the two to
        // disagree.
        std.debug.assert(self.exprTag(id).payload() == .call);
        const c = self.exprs.items(.data)[id.index()].call;
        const at = c.args.index();
        const n = self.extra[at].index();
        return .{ .callee = c.callee, .args = self.extra[at + 1 ..][0..n] };
    }

    pub const UnwrapElse = struct {
        /// The `Option` or `Result` being unwrapped.
        operand: ExprId,
        /// The name written between the bars, or `.none` where `else` has no
        /// binder. `_` is a binder like any other name.
        binder: ExprId,
        /// The block run on a failure.
        body: ExprId,
    };

    /// Returns the parts of `e else |error| { … }`. The run holds the binder,
    /// where one was written, then the block, so every reader asks here rather
    /// than counting the run itself.
    pub fn unwrapElse(self: *const Ast, id: ExprId) UnwrapElse {
        std.debug.assert(self.exprTag(id) == .unwrap_else);
        const c = self.call(id);
        std.debug.assert(c.args.len == 1 or c.args.len == 2);
        return .{
            .operand = c.callee,
            .binder = if (c.args.len == 2) c.args[0] else ExprId.none,
            .body = c.args[c.args.len - 1],
        };
    }

    test unwrapElse {
        const gpa = testing.allocator;

        const source: Source = .{ .path = "t.lin", .text = "f else |e| {} g else {}" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

        var b = Ast.Builder.init(gpa);
        errdefer b.deinit();

        const name = struct {
            fn at(builder: *Ast.Builder, i: u32) !ExprId {
                return builder.addLiteral(.name_ref, TokenId.at(i), .{ .start = TokenId.at(i), .end = TokenId.at(i + 1) });
            }
        }.at;
        const empty = try b.addBlock(&.{}, ExprId.none);
        const bound_body = try b.addBlockExpr(TokenId.at(5), .{ .start = TokenId.at(5), .end = TokenId.at(7) }, empty);
        const bound = try b.addCall(TokenId.at(1), .{ .start = TokenId.at(0), .end = TokenId.at(7) }, try name(&b, 0), &.{ try name(&b, 3), bound_body }, &.{});
        b.retag(bound, .unwrap_else);
        const bare_body = try b.addBlockExpr(TokenId.at(9), .{ .start = TokenId.at(9), .end = TokenId.at(11) }, empty);
        const bare = try b.addCall(TokenId.at(8), .{ .start = TokenId.at(7), .end = TokenId.at(11) }, try name(&b, 7), &.{bare_body}, &.{});
        b.retag(bare, .unwrap_else);

        _ = try b.addDecl(.{
            .tag = .function,
            .main_token = TokenId.at(0),
            .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(11) },
            .name = TokenId.at(0),
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = TokenId.none },
            .body = bound,
            .variants = .{ .start = 0, .end = 0 },
        });

        var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
        defer ast.deinit(gpa);

        const with_binder = ast.unwrapElse(bound);
        try testing.expectEqualStrings("f", ast.tokenText(ast.exprMain(with_binder.operand)));
        try testing.expectEqualStrings("e", ast.tokenText(ast.exprMain(with_binder.binder)));
        try testing.expectEqual(bound_body, with_binder.body);

        const without = ast.unwrapElse(bare);
        try testing.expectEqualStrings("g", ast.tokenText(ast.exprMain(without.operand)));
        try testing.expectEqual(ExprId.none, without.binder);
        try testing.expectEqual(bare_body, without.body);
    }

    pub const Interpolation = struct {
        pieces: []const ExprId,
        formats: []const node.InterpolationFormat,
    };

    /// An interpolation's alternating text/value pieces and the format of
    /// each value, recorded where the selector was parsed.
    pub fn interpolation(self: *const Ast, id: ExprId) Interpolation {
        std.debug.assert(self.exprTag(id) == .interp);
        const record = self.exprs.items(.data)[id.index()].interpolation;
        const piece_start = record.pieces.index();
        const piece_count = self.extra[piece_start].index();
        const pieces = self.extra[piece_start + 1 ..][0..piece_count];
        return .{
            .pieces = pieces,
            .formats = self.interpolation_formats[record.formats.index()..][0 .. pieces.len / 2],
        };
    }

    pub const Lambda = struct {
        params: []const Param,
        contracts: node.ContractRange,
        result: node.TypeRef,
        result_arrow: TokenId,
        body: ExprId,
        captures: []const node.Capture,
        invocation: node.Convention,
        invocation_token: TokenId,
        capture_open: TokenId,
        capture_close: TokenId,
        open: TokenId,
        close: TokenId,
    };

    pub fn lambda(self: *const Ast, id: ExprId) Lambda {
        std.debug.assert(self.exprTag(id) == .lambda);
        const data = self.exprs.items(.data)[id.index()].lambda;
        const at = data.extra.index();
        const start = self.extra[at].index();
        const end = self.extra[at + 1].index();
        return .{
            .params = self.params[start..end],
            .body = data.body,
            .invocation_token = tokenFromExpr(self.extra[at + 2]),
            .invocation = @enumFromInt(self.extra[at + 4].index()),
            .captures = self.captures[self.extra[at + 5].index()..self.extra[at + 6].index()],
            .capture_open = tokenFromExpr(self.extra[at + 7]),
            .capture_close = tokenFromExpr(self.extra[at + 8]),
            .contracts = .{ .start = self.extra[at + 9].index(), .end = self.extra[at + 10].index() },
            .result = self.type_refs[self.extra[at + 11].index()],
            .result_arrow = tokenFromExpr(self.extra[at + 12]),
            .open = self.exprMain(id),
            .close = tokenFromExpr(self.extra[at + 3]),
        };
    }

    fn tokenFromExpr(id: ExprId) TokenId {
        return if (id == ExprId.none) .none else TokenId.at(id.index());
    }

    /// One token per argument of a `.call`-tagged expression, `.none` where
    /// the argument is positional, aligned index-for-index with `call(id).args`.
    ///
    /// Empty for the six other call-shaped tags: a name is a fact about a
    /// call's own syntax, not about a match's arms, a literal's fields, or an
    /// array's elements, which reuse the same payload for their own runs. Which
    /// tags those are is the tag's own answer, so a seventh joining them says
    /// so once.
    pub fn callNames(self: *const Ast, id: ExprId) []const TokenId {
        if (!self.exprTag(id).namesArguments()) return &.{};
        const c = self.exprs.items(.data)[id.index()].call;
        const at = c.args.index();
        const n = self.extra[at].index();
        return self.call_names[at + 1 ..][0..n];
    }

    /// The arguments a call wrote, appended as a rewrite must write them: each
    /// preceded by the name it gave the parameter it fills, and each taken by
    /// its extent.
    ///
    /// One routine, because two rewrites write a postfix call out -- the
    /// server's offer and the harness's -- and they have to write the same
    /// call. An argument that names its parameter says which parameter takes
    /// it, so dropping the name leaves the values to be paired by position, and
    /// where the two orders differ that is a different program. By the extent
    /// for the reason every rewrite that moves an expression uses it: a comment
    /// written after an argument reaches the end of its line, so slicing at the
    /// span comments out whatever the splice puts after it.
    ///
    /// `separated` is whether anything already sits inside the brackets, which
    /// is what decides the first separator. Nothing here writes the receiver:
    /// it is an argument the source never spells, so a caller that puts it
    /// inside the brackets writes it and says so.
    pub fn appendWrittenArguments(
        self: *const Ast,
        gpa: std.mem.Allocator,
        out: *std.ArrayList(u8),
        source: []const u8,
        id: ExprId,
        separated: bool,
    ) !void {
        std.debug.assert(self.exprTag(id).namesArguments());
        for (self.call(id).args, self.callNames(id), 0..) |a, name, i| {
            if (separated or i > 0) try out.appendSlice(gpa, ", ");
            if (name != TokenId.none) {
                try out.appendSlice(gpa, self.tokenText(name));
                try out.appendSlice(gpa, ": ");
            }
            try out.appendSlice(gpa, self.exprExtent(a).slice(source));
        }
    }

    /// Whether a tuple pattern's `)` was never found, so its parts may stop
    /// short of what was written and its arity says nothing.
    pub fn tuplePatternCutShort(self: *const Ast, id: ExprId) bool {
        std.debug.assert(self.exprTag(id) == .tuple_pattern);
        return self.exprs.items(.call_flags)[id.index()].cut_short;
    }

    /// Whether a call is `Name?(e)`, a newtype's unproven construction,
    /// rather than `Name(e)`. Meaningless for anything but `.call`.
    pub fn callFallible(self: *const Ast, id: ExprId) bool {
        std.debug.assert(self.exprTag(id) == .call);
        return self.exprs.items(.call_flags)[id.index()].fallible;
    }

    /// Whether the call is written with `&` before it. The flag records what
    /// the source wrote. The checker settles what the `&` lends: the receiver
    /// of a postfix call, `&x.op(args)`, or otherwise the callable place the
    /// call invokes, `&callback(args)`.
    pub fn callMarked(self: *const Ast, id: ExprId) bool {
        std.debug.assert(self.exprTag(id) == .call);
        return self.exprs.items(.call_flags)[id.index()].marked;
    }

    pub fn blockStmts(self: *const Ast, b: Block) []const StmtId {
        return self.block_stmts[b.stmts.start..b.stmts.end];
    }

    pub fn tokenTag(self: *const Ast, t: TokenId) token.Tag {
        return self.tokens.items(.tag)[t.index()];
    }

    pub fn tokenSpan(self: *const Ast, t: TokenId) Span {
        return self.tokens.items(.span)[t.index()];
    }

    /// The interned identifier a token carries, or `.none` where it is not an
    /// identifier. Comparing two of these answers "are these the same name?"
    /// without touching the source.
    pub fn tokenName(self: *const Ast, t: TokenId) StringId {
        return self.tokens.items(.name)[t.index()];
    }

    pub fn tokenText(self: *const Ast, t: TokenId) []const u8 {
        return self.tokens.items(.span)[t.index()].slice(self.partOf(t).source);
    }

    /// The file a token came from.
    ///
    /// Searched rather than walked, and the difference is the whole
    /// compilation rather than one module: the tree is the program's, so
    /// `parts` holds every file of every module the loader reached, the
    /// standard library included. A scan cost a token's file its position in
    /// that list, and reading a name's text, its file or its span all go
    /// through here -- so it was paid once per name in the program.
    ///
    /// Each file contributes a run of tokens and the runs are laid down in
    /// order, so `token_end` ascends and the first part ending past a token is
    /// the one holding it.
    pub fn partOf(self: *const Ast, t: TokenId) *const FilePart {
        var lo: usize = 0;
        var hi: usize = self.parts.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.parts[mid].token_end <= t.index()) lo = mid + 1 else hi = mid;
        }
        // A token past the last boundary can only be the final `eof`, which
        // belongs to the file that produced it.
        if (lo == self.parts.len) return &self.parts[self.parts.len - 1];
        return &self.parts[lo];
    }

    pub fn fileOf(self: *const Ast, t: TokenId) FileId {
        return self.partOf(t).file;
    }

    /// What a file contributed, or null where the tree holds nothing of it.
    ///
    /// Scans the file parts in token order; file IDs need not share that order.
    pub fn partOfFile(self: *const Ast, file: FileId) ?*const FilePart {
        for (self.parts) |*p| {
            if (p.file == file) return p;
        }
        return null;
    }

    pub fn fileOfExpr(self: *const Ast, id: ExprId) FileId {
        return self.fileOf(self.exprTokens(id).start);
    }

    pub fn fileOfStmt(self: *const Ast, id: StmtId) FileId {
        return self.fileOf(self.stmtTokens(id).start);
    }

    pub fn fileOfDecl(self: *const Ast, id: DeclId) FileId {
        return self.fileOf(self.declTokens(id).start);
    }

    /// The source text an expression was written in.
    pub fn exprText(self: *const Ast, id: ExprId) []const u8 {
        const r = self.exprTokens(id);
        return self.rangeSpan(r).slice(self.partOf(r.start).source);
    }

    /// Appends the text a string literal holds to `out`, and returns whether
    /// every escape in it could be read.
    ///
    /// A quoted or raw literal is decoded from its one token. A multi-line
    /// literal is decoded one `\\` line token at a time, with a line break
    /// between each two, so its lines are exactly the tokens the lexer made
    /// and the parser gathered, and the layout between them is never read.
    /// The only other tokens its range can hold are comments the parser
    /// refused between two lines, and they add nothing.
    pub fn literalText(self: *const Ast, gpa: std.mem.Allocator, out: *std.ArrayList(u8), id: ExprId) std.mem.Allocator.Error!bool {
        std.debug.assert(self.exprTag(id) == .str_literal);
        const main = self.exprMain(id);
        if (self.tokenTag(main) != .string_line) {
            return try literal_text.decode(gpa, out, self.tokenText(main)) == null;
        }
        const range = self.exprTokens(id);
        var i = range.start.index();
        while (i < range.end.index()) : (i += 1) {
            const line = TokenId.at(i);
            if (self.tokenTag(line) != .string_line) continue;
            if (line != main) try out.append(gpa, '\n');
            _ = try literal_text.decode(gpa, out, self.tokenText(line));
        }
        return true;
    }

    /// Appends the path an `embed` or `embed_bytes` names to `out`, decoded
    /// as its string literal is, and returns whether every escape in it could
    /// be read. The parser admits only a quoted or raw literal there, so the
    /// path is the literal's one token.
    pub fn embeddedPath(self: *const Ast, gpa: std.mem.Allocator, out: *std.ArrayList(u8), id: ExprId) std.mem.Allocator.Error!bool {
        std.debug.assert(self.exprTag(id) == .embed or self.exprTag(id) == .embed_bytes);
        return try literal_text.decode(gpa, out, self.tokenText(self.exprMain(id))) == null;
    }

    /// The first file of the module, which is where a diagnostic about the
    /// module as a whole -- rather than about anything written in it -- points.
    pub fn firstFile(self: *const Ast) FileId {
        return self.parts[0].file;
    }

    /// Byte extent of a node, derived from its token range in constant time.
    pub fn exprSpan(self: *const Ast, id: ExprId) Span {
        return self.rangeSpan(self.exprTokens(id));
    }

    pub fn stmtSpan(self: *const Ast, id: StmtId) Span {
        return self.rangeSpan(self.stmtTokens(id));
    }

    /// The same extent, back to the last token of the node that is not trivia.
    ///
    /// A node's token range ends at the next token the parser had not
    /// consumed, and the parser walks past comments -- so a comment written
    /// after an expression sits inside that expression's range. Underlining
    /// one is harmless, which is why `exprSpan` does not care. *Cutting text*
    /// at one is not: a comment reaches the end of its line, so a rewrite that
    /// splices the slice anywhere but where it came from comments out whatever
    /// followed it there, and what fails is the compiler being blamed for
    /// refusing the program the splice truncated.
    ///
    /// One routine rather than one per rewrite. Every rewrite that moves an
    /// expression had this exposure; a second answer to "where does this
    /// expression end for the purpose of moving it" is the drift that put it
    /// in all of them.
    pub fn exprExtent(self: *const Ast, id: ExprId) Span {
        const r = self.exprTokens(id);
        var end = r.end.index();
        while (end > r.start.index() and self.tokenTag(TokenId.at(end - 1)).isTrivia()) {
            end -= 1;
        }
        return self.rangeSpan(.{ .start = r.start, .end = TokenId.at(end) });
    }

    /// The byte extent of a run of tokens, which is what a diagnostic about a
    /// construct spelled as several of them underlines.
    pub fn rangeSpan(self: *const Ast, r: TokenRange) Span {
        const spans = self.tokens.items(.span);
        if (r.len() == 0) {
            const at = spans[r.start.index()].start;
            return .{ .start = at, .end = at };
        }
        return .{
            .start = spans[r.start.index()].start,
            .end = spans[r.end.index() - 1].end,
        };
    }

    /// Accumulates nodes while parsing. The parser owns one and discards it,
    /// so nothing outside construction can mutate a tree.
    pub const Builder = struct {
        gpa: std.mem.Allocator,
        exprs: ExprList = .empty,
        stmts: StmtList = .empty,
        blocks: std.ArrayList(Block) = .empty,
        block_stmts: std.ArrayList(StmtId) = .empty,
        extra: std.ArrayList(ExprId) = .empty,
        /// Grown in lockstep with `extra`: every append to one is matched by
        /// an append of equal length to the other, `.none` where nothing was
        /// named, so the two stay the same length and one `ExtraIndex` reads
        /// both.
        call_names: std.ArrayList(TokenId) = .empty,
        interpolation_formats: std.ArrayList(node.InterpolationFormat) = .empty,
        struct_literal_heads: std.ArrayList(node.TypeRefId) = .empty,
        bracket_types: std.ArrayList(node.BracketTypes) = .empty,
        decls: DeclList = .empty,
        decl_attribute_groups: std.ArrayList(node.AttributeGroupRange) = .empty,
        params: std.ArrayList(Param) = .empty,
        captures: std.ArrayList(node.Capture) = .empty,
        type_params: std.ArrayList(node.TypeParam) = .empty,
        bounds: std.ArrayList(node.TraitBound) = .empty,
        where_predicates: std.ArrayList(node.WherePredicate) = .empty,
        contracts: std.ArrayList(node.Contract) = .empty,
        contract_steps: std.ArrayList(node.ContractStep) = .empty,
        derive_traits: std.ArrayList(node.DeriveTrait) = .empty,
        attribute_items: std.ArrayList(node.AttributeItem) = .empty,
        attribute_groups: std.ArrayList(node.AttributeGroup) = .empty,
        template_requirements: std.ArrayList(node.TemplateRequirement) = .empty,
        type_refs: std.ArrayList(node.TypeRef) = .empty,
        callable_types: std.ArrayList(node.CallableType) = .empty,
        variants: std.ArrayList(Variant) = .empty,
        fields: std.ArrayList(node.Field) = .empty,

        pub fn init(gpa: std.mem.Allocator) Builder {
            return .{ .gpa = gpa };
        }

        /// Starts a builder with every row of an existing tree at the same ID.
        pub fn initPrefix(gpa: std.mem.Allocator, source: *const Ast) !Builder {
            var out = Builder.init(gpa);
            errdefer out.deinit();

            out.exprs = try cloneColumns(Expr, gpa, source.exprs);
            out.stmts = try cloneColumns(Stmt, gpa, source.stmts);
            try out.blocks.appendSlice(gpa, source.blocks);
            try out.block_stmts.appendSlice(gpa, source.block_stmts);
            try out.extra.appendSlice(gpa, source.extra);
            try out.call_names.appendSlice(gpa, source.call_names);
            try out.interpolation_formats.appendSlice(gpa, source.interpolation_formats);
            try out.struct_literal_heads.appendSlice(gpa, source.struct_literal_heads);
            try out.bracket_types.appendSlice(gpa, source.bracket_types);
            out.decls = try cloneColumns(Decl, gpa, source.decls);
            try out.decl_attribute_groups.appendSlice(gpa, source.decl_attribute_groups);
            try out.params.appendSlice(gpa, source.params);
            try out.captures.appendSlice(gpa, source.captures);
            try out.type_params.appendSlice(gpa, source.type_params);
            try out.bounds.appendSlice(gpa, source.bounds);
            try out.where_predicates.appendSlice(gpa, source.where_predicates);
            try out.contracts.appendSlice(gpa, source.contracts);
            try out.contract_steps.appendSlice(gpa, source.contract_steps);
            try out.derive_traits.appendSlice(gpa, source.derive_traits);
            try out.attribute_items.appendSlice(gpa, source.attribute_items);
            try out.attribute_groups.appendSlice(gpa, source.attribute_groups);
            try out.template_requirements.appendSlice(gpa, source.template_requirements);
            try out.type_refs.appendSlice(gpa, source.type_refs);
            try out.callable_types.appendSlice(gpa, source.callable_types);
            try out.variants.appendSlice(gpa, source.variants);
            try out.fields.appendSlice(gpa, source.fields);
            return out;
        }

        pub fn deinit(self: *Builder) void {
            self.exprs.deinit(self.gpa);
            self.stmts.deinit(self.gpa);
            self.blocks.deinit(self.gpa);
            self.block_stmts.deinit(self.gpa);
            self.extra.deinit(self.gpa);
            self.call_names.deinit(self.gpa);
            self.interpolation_formats.deinit(self.gpa);
            self.struct_literal_heads.deinit(self.gpa);
            self.bracket_types.deinit(self.gpa);
            self.decls.deinit(self.gpa);
            self.decl_attribute_groups.deinit(self.gpa);
            self.params.deinit(self.gpa);
            self.captures.deinit(self.gpa);
            self.type_params.deinit(self.gpa);
            self.bounds.deinit(self.gpa);
            self.where_predicates.deinit(self.gpa);
            self.contracts.deinit(self.gpa);
            self.contract_steps.deinit(self.gpa);
            self.derive_traits.deinit(self.gpa);
            self.attribute_items.deinit(self.gpa);
            self.attribute_groups.deinit(self.gpa);
            self.template_requirements.deinit(self.gpa);
            self.type_refs.deinit(self.gpa);
            self.callable_types.deinit(self.gpa);
            self.variants.deinit(self.gpa);
            self.fields.deinit(self.gpa);
            self.* = undefined;
        }

        pub fn addExpr(self: *Builder, e: Expr) !ExprId {
            const i: u32 = @intCast(self.exprs.len);
            try self.exprs.append(self.gpa, e);
            try self.struct_literal_heads.append(self.gpa, .none);
            return ExprId.at(i);
        }

        /// Records the type-list reading of a bracket. Brackets are recorded
        /// in the order their nodes are built, which is increasing.
        pub fn addBracketTypes(self: *Builder, id: ExprId, args: node.TypeRefRange) !void {
            if (self.bracket_types.items.len > 0) std.debug.assert(self.bracket_types.items[self.bracket_types.items.len - 1].at.index() < id.index());
            try self.bracket_types.append(self.gpa, .{ .at = id, .args = args });
        }

        test "addBracketTypes keeps the table in expression order" {
            var b = Builder.init(testing.allocator);
            defer b.deinit();
            try b.addBracketTypes(ExprId.at(1), .{ .start = 0, .end = 1 });
            try b.addBracketTypes(ExprId.at(4), .{ .start = 1, .end = 3 });
            try testing.expectEqual(ExprId.at(4), b.bracket_types.items[1].at);
            try testing.expectEqual(@as(u32, 2), b.bracket_types.items[1].args.len());
        }

        /// The length of every table, so rows appended while trying a reading
        /// that did not fit can be removed again.
        pub const Checkpoint = struct {
            lengths: [table_count]usize,
        };

        const table_count = @typeInfo(Builder).@"struct".fields.len - 1;

        pub fn checkpoint(self: *const Builder) Checkpoint {
            var result: Checkpoint = undefined;
            var at: usize = 0;
            inline for (@typeInfo(Builder).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "gpa")) continue;
                const table = @field(self, field.name);
                result.lengths[at] = if (@hasField(@TypeOf(table), "items")) table.items.len else table.len;
                at += 1;
            }
            return result;
        }

        test "checkpoint records the length of every table" {
            var b = Builder.init(testing.allocator);
            defer b.deinit();
            try b.addTypeRef(.{ .name = TokenId.at(0) });
            const before = b.checkpoint();
            try b.addTypeRef(.{ .name = TokenId.at(1) });
            try testing.expect(!std.meta.eql(before, b.checkpoint()));
        }

        /// Removes every row appended since the checkpoint.
        pub fn rollback(self: *Builder, to: Checkpoint) void {
            var at: usize = 0;
            inline for (@typeInfo(Builder).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "gpa")) continue;
                @field(self, field.name).shrinkRetainingCapacity(to.lengths[at]);
                at += 1;
            }
        }

        test "rollback removes the rows a failed reading appended" {
            var b = Builder.init(testing.allocator);
            defer b.deinit();
            try b.addTypeRef(.{ .name = TokenId.at(0) });
            const before = b.checkpoint();
            _ = try b.addExpr(.{ .tag = .name_ref, .main_token = TokenId.at(1), .token_range = .{ .start = TokenId.at(1), .end = TokenId.at(2) }, .data = .{ .none = {} } });
            try b.addTypeRef(.{ .name = TokenId.at(1) });
            b.rollback(before);
            try testing.expectEqual(@as(usize, 1), b.type_refs.items.len);
            try testing.expectEqual(@as(usize, 0), b.exprs.len);
            try testing.expectEqual(@as(usize, 0), b.struct_literal_heads.items.len);
        }

        pub fn markStructLiteralHead(self: *Builder, id: ExprId, head: node.TypeRef) !void {
            const at = node.TypeRefId.at(self.type_refs.items.len);
            try self.addTypeRef(head);
            self.struct_literal_heads.items[id.index()] = at;
        }

        /// The first token of an already-built expression, so a caller
        /// combining nodes can span from it without reading the storage.
        pub fn exprStart(self: *const Builder, id: ExprId) TokenId {
            return self.exprs.items(.token_range)[id.index()].start;
        }

        /// The tag of an already-built expression, so a caller can tell whether
        /// a subexpression was already reported.
        pub fn exprTag(self: *const Builder, id: ExprId) Expr.Tag {
            return self.exprs.items(.tag)[id.index()];
        }

        pub fn addLiteral(self: *Builder, tag: Expr.Tag, at: TokenId, range: TokenRange) !ExprId {
            return self.addExpr(.{
                .tag = tag,
                .main_token = at,
                .token_range = range,
                .data = .{ .none = {} },
            });
        }

        pub fn addUnary(
            self: *Builder,
            tag: Expr.Tag,
            at: TokenId,
            range: TokenRange,
            operand: ExprId,
        ) !ExprId {
            return self.addExpr(.{
                .tag = tag,
                .main_token = at,
                .token_range = range,
                .data = .{ .unary = .{ .operand = operand } },
            });
        }

        /// Appends children to the side array and returns where they begin.
        ///
        /// Pads `call_names` by the same count so it stays exactly as long as
        /// `extra` -- this run carries no names of its own (a conditional's
        /// arms, a binder list's names), but a later call's `ExtraIndex`
        /// still has to find its own names at the offset `extra.items.len`
        /// gives it.
        fn addExtra(self: *Builder, items: []const ExprId) !node.ExtraIndex {
            const at: u32 = @intCast(self.extra.items.len);
            try self.extra.appendSlice(self.gpa, items);
            try self.call_names.appendNTimes(self.gpa, TokenId.none, items.len);
            return node.ExtraIndex.at(at);
        }

        pub fn addExprStmt(self: *Builder, e: ExprId) !StmtId {
            return self.addStmt(.{
                .tag = .expr_stmt,
                .main_token = self.exprStart(e),
                .token_range = self.exprs.items(.token_range)[e.index()],
                .data = .{ .name = .none, .annotation = .{ .name = .none }, .init = e },
            });
        }

        pub fn addConditional(
            self: *Builder,
            at: TokenId,
            range: TokenRange,
            cond: ExprId,
            then: ExprId,
            otherwise: ExprId,
        ) !ExprId {
            const arms = try self.addExtra(&.{ then, otherwise });
            return self.addExpr(.{
                .tag = .conditional,
                .main_token = at,
                .token_range = range,
                .data = .{ .conditional = .{ .cond = cond, .arms = arms } },
            });
        }

        pub fn addBinary(
            self: *Builder,
            tag: Expr.Tag,
            op: TokenId,
            range: TokenRange,
            lhs: ExprId,
            rhs: ExprId,
        ) !ExprId {
            return self.addExpr(.{
                .tag = tag,
                .main_token = op,
                .token_range = range,
                .data = .{ .binary = .{ .lhs = lhs, .rhs = rhs } },
            });
        }

        /// `lo..hi` or `lo..=hi`. `hi` and the flag share the side array a
        /// call's arguments use, the flag stored as `ExprId.at(0)` or
        /// `ExprId.at(1)` exactly as a call's argument count borrows the same
        /// type for a bare number.
        pub fn addRange(
            self: *Builder,
            op: TokenId,
            range: TokenRange,
            lhs: ExprId,
            rhs: ExprId,
            inclusive: bool,
        ) !ExprId {
            const extra = try self.addExtra(&.{ rhs, ExprId.at(@intFromBool(inclusive)) });
            return self.addExpr(.{
                .tag = .range,
                .main_token = op,
                .token_range = range,
                .data = .{ .range = .{ .lhs = lhs, .extra = extra } },
            });
        }

        pub fn addLambda(
            self: *Builder,
            open: TokenId,
            close: TokenId,
            invocation_token: TokenId,
            invocation: node.Convention,
            captures: []const node.Capture,
            capture_open: TokenId,
            capture_close: TokenId,
            range: TokenRange,
            params: node.ParamRange,
            contracts: node.ContractRange,
            result: node.TypeRef,
            result_arrow: TokenId,
            body: ExprId,
        ) !ExprId {
            const capture_start: u32 = @intCast(self.captures.items.len);
            try self.captures.appendSlice(self.gpa, captures);
            const result_index = self.typeRefMark();
            try self.addTypeRef(result);
            const extra = try self.addExtra(&.{
                ExprId.at(params.start),
                ExprId.at(params.end),
                if (invocation_token == .none) ExprId.none else ExprId.at(invocation_token.index()),
                ExprId.at(close.index()),
                ExprId.at(@intFromEnum(invocation)),
                ExprId.at(capture_start),
                ExprId.at(@intCast(self.captures.items.len)),
                if (capture_open == .none) ExprId.none else ExprId.at(capture_open.index()),
                if (capture_close == .none) ExprId.none else ExprId.at(capture_close.index()),
                ExprId.at(contracts.start),
                ExprId.at(contracts.end),
                ExprId.at(result_index),
                if (result_arrow == .none) ExprId.none else ExprId.at(result_arrow.index()),
            });
            return self.addExpr(.{
                .tag = .lambda,
                .main_token = open,
                .token_range = range,
                .data = .{ .lambda = .{ .body = body, .extra = extra } },
            });
        }

        pub fn addBlockExpr(
            self: *Builder,
            at: TokenId,
            range: TokenRange,
            block: BlockId,
        ) !ExprId {
            return self.addExpr(.{
                .tag = .block,
                .main_token = at,
                .token_range = range,
                .data = .{ .block = block },
            });
        }

        pub fn addStmt(self: *Builder, s: Stmt) !StmtId {
            const i: u32 = @intCast(self.stmts.len);
            try self.stmts.append(self.gpa, s);
            return StmtId.at(i);
        }

        pub fn addParam(self: *Builder, p: Param) !void {
            try self.params.append(self.gpa, p);
        }

        pub fn paramMark(self: *const Builder) u32 {
            return @intCast(self.params.items.len);
        }

        pub fn typeParamMark(self: *const Builder) u32 {
            return @intCast(self.type_params.items.len);
        }

        pub fn addTypeParam(self: *Builder, p: node.TypeParam) !void {
            try self.type_params.append(self.gpa, p);
        }

        /// The parameters a range names, while the tree is still being built.
        ///
        /// A range indexes the table it was marked out of, and this is where
        /// that is known: a producer reading its own range back through the
        /// slice is a second place deciding what a range means.
        pub fn typeParams(self: *const Builder, r: node.TypeParamRange) []const node.TypeParam {
            return self.type_params.items[r.start..r.end];
        }

        pub fn boundMark(self: *const Builder) u32 {
            return @intCast(self.bounds.items.len);
        }

        pub fn addBound(self: *Builder, b: node.TraitBound) !void {
            try self.bounds.append(self.gpa, b);
        }

        pub fn wherePredicateMark(self: *const Builder) u32 {
            return @intCast(self.where_predicates.items.len);
        }

        pub fn addWherePredicate(self: *Builder, p: node.WherePredicate) !void {
            try self.where_predicates.append(self.gpa, p);
        }

        pub fn deriveTraitMark(self: *const Builder) u32 {
            return @intCast(self.derive_traits.items.len);
        }

        pub fn addDeriveTrait(self: *Builder, t: node.DeriveTrait) !void {
            try self.derive_traits.append(self.gpa, t);
        }

        pub fn attributeItemMark(self: *const Builder) u32 {
            return @intCast(self.attribute_items.items.len);
        }

        pub fn addAttributeItem(self: *Builder, item: node.AttributeItem) !void {
            try self.attribute_items.append(self.gpa, item);
        }

        pub fn attributeGroupMark(self: *const Builder) u32 {
            return @intCast(self.attribute_groups.items.len);
        }

        pub fn addAttributeGroup(self: *Builder, group: node.AttributeGroup) !void {
            try self.attribute_groups.append(self.gpa, group);
        }

        pub fn markAttributeGroups(self: *Builder, d: DeclId, groups: node.AttributeGroupRange) void {
            self.decl_attribute_groups.items[d.index()] = groups;
        }

        pub fn markAttachedDeriveTraits(self: *Builder, d: DeclId, traits: node.DeriveTraitRange) void {
            self.decls.items(.derive_traits)[d.index()] = traits;
        }

        pub fn templateRequirementMark(self: *const Builder) u32 {
            return @intCast(self.template_requirements.items.len);
        }

        pub fn addTemplateRequirement(self: *Builder, r: node.TemplateRequirement) !void {
            try self.template_requirements.append(self.gpa, r);
        }

        pub fn typeRefMark(self: *const Builder) u32 {
            return @intCast(self.type_refs.items.len);
        }

        /// The written types a range names, on the terms `typeParams` is read
        /// on.
        pub fn typeArgs(self: *const Builder, r: node.TypeRefRange) []const node.TypeRef {
            return self.type_refs.items[r.start..r.end];
        }

        pub fn addTypeRef(self: *Builder, r: node.TypeRef) !void {
            try self.type_refs.append(self.gpa, r);
        }

        pub fn addCallableType(self: *Builder, signature: node.CallableType) !node.CallableTypeId {
            const id = node.CallableTypeId.at(self.callable_types.items.len);
            try self.callable_types.append(self.gpa, signature);
            return id;
        }

        pub fn addVariant(self: *Builder, v: Variant) !void {
            try self.variants.append(self.gpa, v);
        }

        pub fn addField(self: *Builder, f: node.Field) !void {
            try self.fields.append(self.gpa, f);
        }

        pub fn fieldMark(self: *const Builder) u32 {
            return @intCast(self.fields.items.len);
        }

        pub fn variantMark(self: *const Builder) u32 {
            return @intCast(self.variants.items.len);
        }

        /// Records how far a declaration reaches, and that its text begins at
        /// the prefix rather than at the keyword its rule consumed.
        ///
        /// Written after the rule returns because the prefix is read before
        /// the rule is chosen: which rule runs is what the prefix precedes.
        pub fn markVisibility(
            self: *Builder,
            d: DeclId,
            visibility: node.Visibility,
            start: TokenId,
        ) void {
            self.decls.items(.visibility)[d.index()] = visibility;
            self.decls.items(.token_range)[d.index()].start = start;
        }

        /// How many declarations have been added, which is where the next
        /// one lands. What bounds a module's range within the program's tree.
        pub fn declMark(self: *const Builder) u32 {
            return @intCast(self.decls.len);
        }

        /// How many statements have been added, which is where the next one
        /// lands. What bounds a file's run within the program's tree.
        pub fn stmtMark(self: *const Builder) u32 {
            return @intCast(self.stmts.len);
        }

        /// How many expressions have been added, which is where the next one
        /// lands. What bounds a file's run within the program's tree.
        pub fn exprMark(self: *const Builder) u32 {
            return @intCast(self.exprs.len);
        }

        /// Records the type a declaration belongs to: the name after `impl`.
        pub fn markOwner(self: *Builder, d: DeclId, of: TokenId) void {
            self.decls.items(.owner)[d.index()] = of;
        }

        /// Records which trait a declaration belongs to: the trait an
        /// implementation names, carried onto each of its members so a member
        /// says what it satisfies without anyone re-deriving it from where it
        /// sits.
        pub fn markTrait(self: *Builder, d: DeclId, ref: node.TraitRef) void {
            self.decls.items(.trait_ref)[d.index()] = ref;
        }

        pub fn markDelegation(self: *Builder, d: DeclId, via: TokenId, target: TokenId) void {
            self.decls.items(.delegation)[d.index()] = .{ .via = via, .target = target };
        }

        pub fn markOwnershipPolicy(self: *Builder, d: DeclId, policy: node.OwnershipPolicy) void {
            self.decls.items(.ownership_policy)[d.index()] = policy;
        }

        pub fn markTest(self: *Builder, d: DeclId, is_test: bool) void {
            self.decls.items(.is_test)[d.index()] = is_test;
        }

        pub fn markExpectedTrap(self: *Builder, d: DeclId, expects_trap: bool) void {
            self.decls.items(.expects_trap)[d.index()] = expects_trap;
        }

        pub fn markExport(self: *Builder, d: DeclId, is_export: bool) void {
            self.decls.items(.is_export)[d.index()] = is_export;
        }

        /// Extends an expression's extent to end at `at`.
        ///
        /// A construct whose closing token is consumed by its caller cannot
        /// know its own end when it is built. Written here rather than by
        /// rebuilding the node, because everything else about it is settled.
        pub fn endExpr(self: *Builder, id: ExprId, at: TokenId) void {
            self.exprs.items(.token_range)[id.index()].end = at;
        }

        pub fn addDecl(self: *Builder, d: Decl) !DeclId {
            const i: u32 = @intCast(self.decls.len);
            try self.decls.append(self.gpa, d);
            try self.decl_attribute_groups.append(self.gpa, .empty);
            return DeclId.at(i);
        }

        /// A call's arguments, held out of line: the count comes first so a
        /// reader of the side array knows how far the run goes.
        ///
        /// `names` is empty for every call-shaped construct but a written
        /// call (a match, a struct literal, an array literal, a struct
        /// pattern, an interpolation, a pattern's binder list) -- none of
        /// them has argument names to collect. Where it is given, it must
        /// hold exactly one entry per argument, `.none` where that argument
        /// was positional.
        pub fn addCall(
            self: *Builder,
            at: TokenId,
            range: TokenRange,
            callee: ExprId,
            args: []const ExprId,
            names: []const TokenId,
        ) !ExprId {
            std.debug.assert(names.len == 0 or names.len == args.len);
            const start: u32 = @intCast(self.extra.items.len);
            try self.extra.append(self.gpa, ExprId.at(@intCast(args.len)));
            try self.extra.appendSlice(self.gpa, args);

            try self.call_names.append(self.gpa, TokenId.none);
            if (names.len == 0) {
                try self.call_names.appendNTimes(self.gpa, TokenId.none, args.len);
            } else {
                try self.call_names.appendSlice(self.gpa, names);
            }

            return self.addExpr(.{
                .tag = .call,
                .main_token = at,
                .token_range = range,
                .data = .{ .call = .{ .callee = callee, .args = node.ExtraIndex.at(start) } },
            });
        }

        /// Adds alternating text/value pieces and one format per value.
        pub fn addInterpolation(
            self: *Builder,
            at: TokenId,
            range: TokenRange,
            pieces: []const ExprId,
            formats: []const node.InterpolationFormat,
        ) !ExprId {
            std.debug.assert(pieces.len % 2 == 1);
            std.debug.assert(formats.len == pieces.len / 2);

            const piece_start: u32 = @intCast(self.extra.items.len);
            try self.extra.append(self.gpa, ExprId.at(@intCast(pieces.len)));
            try self.extra.appendSlice(self.gpa, pieces);
            try self.call_names.appendNTimes(self.gpa, TokenId.none, pieces.len + 1);

            const format_start: u32 = @intCast(self.interpolation_formats.items.len);
            try self.interpolation_formats.appendSlice(self.gpa, formats);

            return self.addExpr(.{
                .tag = .interp,
                .main_token = at,
                .token_range = range,
                .data = .{ .interpolation = .{
                    .pieces = node.ExtraIndex.at(piece_start),
                    .formats = node.InterpolationFormatIndex.at(format_start),
                } },
            });
        }

        /// Changes a node's tag without rebuilding it. A match is assembled
        /// as a call — same payload, same side array — and says what it is
        /// afterwards.
        pub fn retag(self: *Builder, id: ExprId, tag: Expr.Tag) void {
            self.exprs.items(.tag)[id.index()] = tag;
        }

        /// Marks an already-built call as `Name?(e)` rather than `Name(e)`.
        /// Set after the call is built, the way `retag` changes a match built
        /// as a call after the fact -- the parser knows only once the `?` and
        /// the `(` that follows it have both been seen.
        pub fn markFallible(self: *Builder, id: ExprId) void {
            self.exprs.items(.call_flags)[id.index()].fallible = true;
        }

        /// Marks an already-built tuple pattern as one whose `)` was never
        /// found.
        pub fn markCutShort(self: *Builder, id: ExprId) void {
            std.debug.assert(self.exprTag(id) == .tuple_pattern);
            self.exprs.items(.call_flags)[id.index()].cut_short = true;
        }

        /// Records that an already-built call is written with `&` before it.
        /// What the `&` lends is settled by the checker.
        pub fn markCall(self: *Builder, id: ExprId) void {
            std.debug.assert(self.exprTag(id) == .call);
            self.exprs.items(.call_flags)[id.index()].marked = true;
        }

        pub fn addBlock(self: *Builder, stmts: []const StmtId, tail: ExprId) !BlockId {
            const start: u32 = @intCast(self.block_stmts.items.len);
            try self.block_stmts.appendSlice(self.gpa, stmts);
            const i: u32 = @intCast(self.blocks.items.len);
            try self.blocks.append(self.gpa, .{
                .stmts = .{ .start = start, .end = @intCast(self.block_stmts.items.len) },
                .tail = tail,
            });
            return BlockId.at(i);
        }

        /// A tree of one file, which is what parsing a single file produces.
        /// Consumes `tokens`, including on allocation failure.
        pub fn finishOne(
            self: *Builder,
            path: []const u8,
            source: []const u8,
            file: FileId,
            tokens: TokenList,
        ) !Ast {
            const parts = self.gpa.alloc(FilePart, 1) catch |err| {
                var owned_tokens = tokens;
                owned_tokens.deinit(self.gpa);
                return err;
            };
            errdefer self.gpa.free(parts);
            parts[0] = .{
                .file = file,
                .path = path,
                .source = source,
                .token_start = 0,
                .token_end = @intCast(tokens.len),
                .decl_start = 0,
                .decl_end = self.declMark(),
                .stmt_start = 0,
                .stmt_end = self.stmtMark(),
                .expr_start = 0,
                .expr_end = self.exprMark(),
            };
            return self.finish(parts, tokens);
        }

        /// Takes ownership of `parts`, which the tree frees.
        pub fn finish(
            self: *Builder,
            parts: []const FilePart,
            tokens: TokenList,
        ) !Ast {
            // The names are a parallel array, so an index into one is an index
            // into the other and only their lengths say the two were kept in
            // step. Two places append to both; a third that appends to one
            // silently shifts every name written after it onto some other
            // call's argument, which reads as the wrong parameter having been
            // named rather than as a tree that was built wrong.
            std.debug.assert(self.extra.items.len == self.call_names.items.len);
            std.debug.assert(self.exprs.len == self.struct_literal_heads.items.len);

            var owned_tokens = tokens;
            var finished_tokens = owned_tokens.toOwnedSlice();
            errdefer finished_tokens.deinit(self.gpa);
            var finished_exprs = self.exprs.toOwnedSlice();
            errdefer finished_exprs.deinit(self.gpa);
            var finished_stmts = self.stmts.toOwnedSlice();
            errdefer finished_stmts.deinit(self.gpa);
            const finished_blocks = try self.blocks.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_blocks);
            const finished_block_stmts = try self.block_stmts.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_block_stmts);
            const finished_extra = try self.extra.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_extra);
            const finished_call_names = try self.call_names.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_call_names);
            const finished_interpolation_formats = try self.interpolation_formats.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_interpolation_formats);
            const finished_struct_literal_heads = try self.struct_literal_heads.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_struct_literal_heads);
            const finished_bracket_types = try self.bracket_types.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_bracket_types);
            var finished_decls = self.decls.toOwnedSlice();
            errdefer finished_decls.deinit(self.gpa);
            const finished_decl_attribute_groups = try self.decl_attribute_groups.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_decl_attribute_groups);
            const finished_captures = try self.captures.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_captures);
            const finished_params = try self.params.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_params);
            const finished_type_params = try self.type_params.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_type_params);
            const finished_bounds = try self.bounds.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_bounds);
            const finished_contract_steps = try self.contract_steps.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_contract_steps);
            const finished_contracts = try self.contracts.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_contracts);
            const finished_where_predicates = try self.where_predicates.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_where_predicates);
            const finished_derive_traits = try self.derive_traits.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_derive_traits);
            const finished_attribute_items = try self.attribute_items.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_attribute_items);
            const finished_attribute_groups = try self.attribute_groups.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_attribute_groups);
            const finished_template_requirements = try self.template_requirements.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_template_requirements);
            const finished_type_refs = try self.type_refs.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_type_refs);
            const finished_callable_types = try self.callable_types.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_callable_types);
            const finished_variants = try self.variants.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_variants);
            const finished_fields = try self.fields.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(finished_fields);

            return .{
                .parts = parts,
                .tokens = finished_tokens,
                .exprs = finished_exprs,
                .stmts = finished_stmts,
                .blocks = finished_blocks,
                .block_stmts = finished_block_stmts,
                .extra = finished_extra,
                .call_names = finished_call_names,
                .interpolation_formats = finished_interpolation_formats,
                .struct_literal_heads = finished_struct_literal_heads,
                .bracket_types = finished_bracket_types,
                .decls = finished_decls,
                .decl_attribute_groups = finished_decl_attribute_groups,
                .params = finished_params,
                .captures = finished_captures,
                .type_params = finished_type_params,
                .bounds = finished_bounds,
                .where_predicates = finished_where_predicates,
                .contracts = finished_contracts,
                .contract_steps = finished_contract_steps,
                .derive_traits = finished_derive_traits,
                .attribute_items = finished_attribute_items,
                .attribute_groups = finished_attribute_groups,
                .template_requirements = finished_template_requirements,
                .type_refs = finished_type_refs,
                .callable_types = finished_callable_types,
                .variants = finished_variants,
                .fields = finished_fields,
            };
        }
    };
};

// Makes every test build compile the tests `Ast` holds, including a build
// filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Ast;
    _ = Ast.Builder;
}

/// The type reading recorded for a bracket, found by binary search: brackets
/// are recorded in the order their nodes are built.
fn findBracketTypes(rows: []const node.BracketTypes, id: ExprId) ?node.TypeRefRange {
    var lo: usize = 0;
    var hi: usize = rows.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const at = rows[mid].at.index();
        if (at == id.index()) return rows[mid].args;
        if (at < id.index()) lo = mid + 1 else hi = mid;
    }
    return null;
}

/// Builds `let x = 1;` plus a tail of `x` by hand, so the tree can be tested
/// before a parser exists.
fn buildSample(gpa: std.mem.Allocator) !Ast {
    const source: Source = .{ .path = "t.lin", .text = "let x = 1; x" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var b = Ast.Builder.init(gpa);
    errdefer b.deinit();

    const one = try b.addExpr(.{
        .tag = .int_literal,
        .main_token = TokenId.at(3),
        .token_range = .{ .start = TokenId.at(3), .end = TokenId.at(4) },
        .data = .{ .none = {} },
    });
    const decl = try b.addStmt(.{
        .tag = .let_decl,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(5) },
        .data = .{ .name = TokenId.at(1), .annotation = .{ .name = .none }, .init = one },
    });
    const tail = try b.addExpr(.{
        .tag = .name_ref,
        .main_token = TokenId.at(5),
        .token_range = .{ .start = TokenId.at(5), .end = TokenId.at(6) },
        .data = .{ .none = {} },
    });
    const blk = try b.addBlock(&.{decl}, tail);
    const root = try b.addExpr(.{
        .tag = .block,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(6) },
        .data = .{ .block = blk },
    });

    // A program is a list of declarations, so a tree built by hand needs one
    // for its body to belong to.
    _ = try b.addDecl(.{
        .tag = .function,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(6) },
        .name = TokenId.at(0),
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = TokenId.none },
        .body = root,
        .variants = .{ .start = 0, .end = 0 },
    });

    return b.finishOne(source.path, source.text, .from(0), tokens);
}

/// The declarations of a program, reached by who owns them and by where they
/// sit.
///
/// Two passes ask the same two questions of a tree: which declarations a token
/// owns, and which lie inside a token range. Both were answered by reading
/// every declaration in the program, so a module of many `impl` blocks paid the
/// product -- in the checker, which asks per `impl`, and in the formatter,
/// which asks per container it prints.
///
/// Beside the tree rather than in either pass, because it is one answer and
/// two askers.
pub const DeclIndex = struct {
    /// Declarations grouped by the token that owns them, which for a member is
    /// the name after `impl` and for a signature is the trait's own name.
    owner_starts: []u32,
    by_owner: []DeclId,
    /// Declarations by the token they start at. Sorted rather than searched
    /// over `DeclId`, because a container's members are built before it is.
    by_start: []DeclId,
    ast: *const Ast,

    pub fn build(gpa: std.mem.Allocator, ast: *const Ast) !DeclIndex {
        const tokens = ast.tokenCount();
        const owner_starts = try gpa.alloc(u32, tokens + 1);
        errdefer gpa.free(owner_starts);
        @memset(owner_starts, 0);

        var total: u32 = 0;
        for (0..ast.declCount()) |i| {
            const of = ast.memberOwner(DeclId.at(@intCast(i)));
            if (of == TokenId.none or of.index() >= tokens) continue;
            owner_starts[of.index() + 1] += 1;
            total += 1;
        }
        for (1..tokens + 1) |i| owner_starts[i] += owner_starts[i - 1];

        const by_owner = try gpa.alloc(DeclId, total);
        errdefer gpa.free(by_owner);

        const cursor = try gpa.alloc(u32, tokens);
        defer gpa.free(cursor);
        @memcpy(cursor, owner_starts[0..tokens]);

        // In declaration order, so each run keeps it: what these walks report
        // first should not change.
        for (0..ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            const of = ast.memberOwner(d);
            if (of == TokenId.none or of.index() >= tokens) continue;
            by_owner[cursor[of.index()]] = d;
            cursor[of.index()] += 1;
        }

        const by_start = try gpa.alloc(DeclId, ast.declCount());
        errdefer gpa.free(by_start);
        for (by_start, 0..) |*at, i| at.* = DeclId.at(@intCast(i));
        std.mem.sortUnstable(DeclId, by_start, ast, startsBefore);

        return .{
            .owner_starts = owner_starts,
            .by_owner = by_owner,
            .by_start = by_start,
            .ast = ast,
        };
    }

    fn startsBefore(ast: *const Ast, a: DeclId, b: DeclId) bool {
        const x = ast.declTokens(a).start.index();
        const y = ast.declTokens(b).start.index();
        return if (x == y) a.index() < b.index() else x < y;
    }

    pub fn deinit(self: *DeclIndex, gpa: std.mem.Allocator) void {
        gpa.free(self.owner_starts);
        gpa.free(self.by_owner);
        gpa.free(self.by_start);
    }

    /// The declarations a token owns, in declaration order.
    pub fn ownedBy(self: *const DeclIndex, of: TokenId) []const DeclId {
        if (of == TokenId.none or of.index() + 1 >= self.owner_starts.len) return &.{};
        return self.by_owner[self.owner_starts[of.index()]..self.owner_starts[of.index() + 1]];
    }

    /// The declarations starting inside a token range, in source order.
    pub fn within(self: *const DeclIndex, extent: TokenRange) []const DeclId {
        const from = self.lowerBound(extent.start.index());
        var to = from;
        while (to < self.by_start.len and
            self.ast.declTokens(self.by_start[to]).start.index() < extent.end.index()) to += 1;
        return self.by_start[from..to];
    }

    fn lowerBound(self: *const DeclIndex, at: u32) usize {
        var lo: usize = 0;
        var hi: usize = self.by_start.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.ast.declTokens(self.by_start[mid]).start.index() < at) lo = mid + 1 else hi = mid;
        }
        return lo;
    }
};

/// `a`, `(a).f`, `(a).f[a]`, `*(a).f[a]`, `&*(a).f[a]`, `(*(a).f[a])`,
/// a call, and a field selected from the call.
const PathSample = struct {
    ast: Ast,
    name: ExprId,
    field: ExprId,
    index: ExprId,
    deref: ExprId,
    marked_deref: ExprId,
    grouped_deref: ExprId,
    call: ExprId,
    call_field: ExprId,

    fn build(gpa: std.mem.Allocator) !PathSample {
        const source: Source = .{ .path = "t.lin", .text = "a" };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

        var b = Ast.Builder.init(gpa);
        errdefer b.deinit();
        const at = TokenId.at(0);
        const range: TokenRange = .{ .start = at, .end = TokenId.at(1) };
        const name = try b.addLiteral(.name_ref, at, range);
        const wrapped = try b.addUnary(.grouped, at, range, name);
        const field = try b.addUnary(.field, at, range, wrapped);
        const index = try b.addBinary(.index, at, range, field, name);
        const deref = try b.addUnary(.dereference, at, range, index);
        const marked_deref = try b.addUnary(.marked, at, range, deref);
        const grouped_deref = try b.addUnary(.grouped, at, range, deref);
        const call = try b.addCall(at, range, name, &.{}, &.{});
        const call_field = try b.addUnary(.field, at, range, call);
        _ = try b.addDecl(.{
            .tag = .function,
            .main_token = at,
            .token_range = range,
            .name = at,
            .params = .{ .start = 0, .end = 0 },
            .returns = .{ .name = TokenId.none },
            .body = name,
            .variants = .{ .start = 0, .end = 0 },
        });
        return .{
            .ast = try b.finishOne(source.path, source.text, .from(0), tokens),
            .name = name,
            .field = field,
            .index = index,
            .deref = deref,
            .marked_deref = marked_deref,
            .grouped_deref = grouped_deref,
            .call = call,
            .call_field = call_field,
        };
    }
};

test "builder produces a readable tree" {
    var ast = try buildSample(testing.allocator);
    defer ast.deinit(testing.allocator);

    try testing.expectEqual(Expr.Tag.block, ast.exprTag(ast.declBody(node.DeclId.at(0))));
    const blk = ast.blockOf(ast.declBody(node.DeclId.at(0)));
    const stmts = ast.blockStmts(blk);
    try testing.expectEqual(@as(usize, 1), stmts.len);
    try testing.expectEqual(Stmt.Tag.let_decl, ast.stmtTag(stmts[0]));
    try testing.expectEqual(Expr.Tag.name_ref, ast.exprTag(blk.tail));
}

test "declaration trait accessors preserve builder inputs" {
    const gpa = testing.allocator;
    const source: Source = .{
        .path = "t.lin",
        .text = "impl T Trait Arg Outer Head Member Inherent",
    };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var b = Ast.Builder.init(gpa);
    errdefer b.deinit();

    try b.addTypeParam(.{ .name = TokenId.at(1), .bounds = .empty });
    try b.addTypeRef(.{ .name = TokenId.at(3) });
    const nested_args: node.TypeRefRange = .{ .start = 0, .end = 1 };
    try b.addTypeRef(.{ .name = TokenId.at(4), .args = nested_args });
    const trait_args: node.TypeRefRange = .{ .start = 1, .end = 2 };
    try b.addTypeRef(.{ .name = TokenId.at(1) });
    const head_args: node.TypeRefRange = .{ .start = 2, .end = 3 };

    const generic_impl = try b.addDecl(.{
        .tag = .impl_,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(1) },
        .name = TokenId.at(5),
        .params = .{ .start = 0, .end = 0 },
        .type_params = .{ .start = 0, .end = 1 },
        .returns = .{ .name = .none },
        .body = .none,
        .variants = .{ .start = 0, .end = 0 },
        .head_args = head_args,
    });
    b.markTrait(generic_impl, .{ .name = TokenId.at(2), .args = trait_args });

    const member = try b.addDecl(.{
        .tag = .function,
        .main_token = TokenId.at(6),
        .token_range = .{ .start = TokenId.at(6), .end = TokenId.at(7) },
        .name = TokenId.at(6),
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = .none },
        .body = .none,
        .variants = .{ .start = 0, .end = 0 },
    });
    b.markOwner(member, TokenId.at(5));
    b.markTrait(member, .{ .name = TokenId.at(2), .args = trait_args });

    const inherent_impl = try b.addDecl(.{
        .tag = .impl_,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(1) },
        .name = TokenId.at(7),
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = .none },
        .body = .none,
        .variants = .{ .start = 0, .end = 0 },
    });

    var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
    defer ast.deinit(gpa);

    try testing.expectEqual(TokenId.at(2), ast.declTrait(generic_impl));
    try testing.expectEqual(trait_args, ast.declTraitArgs(generic_impl));
    try testing.expectEqual(TokenId.at(2), ast.declTrait(member));
    try testing.expectEqual(trait_args, ast.declTraitArgs(member));
    try testing.expectEqual(TokenId.none, ast.declTrait(inherent_impl));
    try testing.expectEqual(node.TypeRefRange.empty, ast.declTraitArgs(inherent_impl));

    const outer = ast.typeArgs(ast.declTraitArgs(generic_impl));
    try testing.expectEqual(@as(usize, 1), outer.len);
    try testing.expectEqual(TokenId.at(4), outer[0].name);
    try testing.expectEqual(nested_args, outer[0].args);
    try testing.expectEqual(TokenId.at(3), ast.typeArgs(outer[0].args)[0].name);
    try testing.expectEqual(TokenId.at(1), ast.typeArgs(ast.declHead(generic_impl).args)[0].name);
}

test "token text comes from the span" {
    var ast = try buildSample(testing.allocator);
    defer ast.deinit(testing.allocator);

    const decl = ast.blockStmts(ast.blockOf(ast.declBody(node.DeclId.at(0))))[0];
    try testing.expectEqualStrings("x", ast.tokenText(ast.stmtData(decl).name));
}

test "literalText decodes a quoted literal's token, or joins a multi-line literal's line tokens" {
    const gpa = testing.allocator;
    const source: Source = .{ .path = "t.lin", .text = "\"o\\tne\" // note\n\\\\two\n\r    \\\\three" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var b = Ast.Builder.init(gpa);
    errdefer b.deinit();
    // A quoted literal's range runs on over the comment after it, as the
    // parser records it; only its token is decoded.
    const quoted = try b.addExpr(.{
        .tag = .str_literal,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(2) },
        .data = .{ .none = {} },
    });
    const lines = try b.addExpr(.{
        .tag = .str_literal,
        .main_token = TokenId.at(2),
        .token_range = .{ .start = TokenId.at(2), .end = TokenId.at(4) },
        .data = .{ .none = {} },
    });
    _ = try b.addDecl(.{
        .tag = .function,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(4) },
        .name = TokenId.at(0),
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = TokenId.none },
        .body = lines,
        .variants = .{ .start = 0, .end = 0 },
    });
    var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
    defer ast.deinit(gpa);

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try testing.expect(try ast.literalText(gpa, &text, quoted));
    try testing.expectEqualStrings("o\tne", text.items);

    // A carriage return in the indentation before `\\` is layout, as the
    // lexer reads it.
    text.clearRetainingCapacity();
    try testing.expect(try ast.literalText(gpa, &text, lines));
    try testing.expectEqualStrings("two\nthree", text.items);
}

test "exprSpan covers the node's tokens" {
    var ast = try buildSample(testing.allocator);
    defer ast.deinit(testing.allocator);

    const span = ast.exprSpan(ast.declBody(node.DeclId.at(0)));
    try testing.expectEqual(@as(u32, 0), span.start);
    try testing.expectEqual(@as(u32, 12), span.end);
}

test "binary accessor returns both operands" {
    const gpa = testing.allocator;

    const source: Source = .{ .path = "t.lin", .text = "1 + 2" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var b = Ast.Builder.init(gpa);
    errdefer b.deinit();

    const l = try b.addExpr(.{
        .tag = .int_literal,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(1) },
        .data = .{ .none = {} },
    });
    const r = try b.addExpr(.{
        .tag = .int_literal,
        .main_token = TokenId.at(2),
        .token_range = .{ .start = TokenId.at(2), .end = TokenId.at(3) },
        .data = .{ .none = {} },
    });
    const sum = try b.addExpr(.{
        .tag = .add,
        .main_token = TokenId.at(1),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(3) },
        .data = .{ .binary = .{ .lhs = l, .rhs = r } },
    });

    _ = try b.addDecl(.{
        .tag = .function,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(3) },
        .name = TokenId.at(0),
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = TokenId.none },
        .body = sum,
        .variants = .{ .start = 0, .end = 0 },
    });

    var ast = try b.finishOne(source.path, source.text, .from(0), tokens);
    defer ast.deinit(gpa);

    const bin = ast.binary(sum);
    try testing.expectEqual(l, bin.lhs);
    try testing.expectEqual(r, bin.rhs);
}
