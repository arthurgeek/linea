const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const positions = @import("positions.zig");
const fix = @import("fix.zig");
const workspace = @import("workspace.zig");
const exports = @import("exports.zig");
const loader = @import("../driver/loader.zig");
const ast_mod = @import("../syntax/ast.zig");
const Ast = ast_mod.Ast;
const FilePart = ast_mod.FilePart;
const program_mod = @import("../syntax/program.zig");
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const TokenId = @import("../lexer/token.zig").TokenId;
const FileId = @import("../support/source.zig").FileId;
const Span = @import("../support/span.zig").Span;
const resolve = @import("../sema/resolve.zig");
const Resolution = resolve.Resolution;
const BindingId = resolve.BindingId;
const ScopeId = resolve.ScopeId;
const types = @import("../sema/types.zig");
const Typing = types.Typing;
const typecheck = @import("../sema/typecheck.zig");
const ExprId = node.ExprId;

const Item = lsp.types.completion.Item;

/// Whether the client reads `${1:a}` as a tab stop or as six characters.
///
/// `completionItem.snippetSupport` is a capability and not an assumption: a
/// client that did not advertise it writes the placeholder syntax into the
/// buffer verbatim, so what it is offered is the name alone.
pub const Snippets = enum { supported, unsupported };

/// The call an item writes, and how many of its arguments a client tabs
/// through.
const Call = struct {
    /// The text, in the protocol's own snippet syntax where it carries a stop.
    text: []const u8,
    /// Placeholders, which is what decides whether the text is a snippet at
    /// all: `$0` is written only where one of these is, so a call with no
    /// argument left to fill in carries no snippet syntax and is plain text.
    stops: u32,
};

/// A stop for every parameter nobody has written, appended in the order the
/// parameters take, and how many that was.
///
/// **A placeholder is the parameter's declared name**, read off the same
/// parameter list a hint renders and ownership reads a convention from. It is
/// not a guess at the argument: nothing here knows what the caller means to
/// pass, and a name invented for the slot would be one no pass agrees with.
///
/// **The tab order is the parameter order**, because that is the order the
/// arguments go in. `taken` is how many the reader has already written -- the
/// receiver of a postfix call, and whatever follows it inside the brackets --
/// and they are the ones at the front, so what remains is a suffix of the list.
/// `inside` is how many of those sit inside the brackets, which is what decides
/// whether the first stop needs a separator before it.
///
/// Nothing is escaped, because there is nothing that could need it: a
/// parameter's name is an identifier, and `$`, `}` and `\` are the three bytes
/// snippet syntax reserves and the three an identifier cannot hold.
///
/// Nothing is written where the name reaches no function to read parameters
/// from -- a primitive the resolver put in scope, a name the index holds and
/// nobody checked -- because a call written from no signature is a guess.
///
/// **Bound: one pass over that declaration's parameters.** The list is a slice
/// the tree already holds, so an item costs its own arity and nothing here is
/// sized by the program.
fn appendStops(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    written: *std.ArrayList(u8),
    signature: DeclId,
    taken: usize,
    inside: usize,
) !u32 {
    if (signature == DeclId.none or ast.declTag(signature) != .function) return 0;
    const params = ast.declParams(signature);

    var stops: u32 = 0;
    for (params[@min(taken, params.len)..]) |p| {
        if (inside > 0 or stops > 0) try written.appendSlice(gpa, ", ");
        stops += 1;
        try written.print(gpa, "${{{d}:{s}}}", .{ stops, ast.tokenText(p.name) });
    }
    return stops;
}

/// The call accepting a function writes: its name, its brackets, and a stop
/// per argument.
///
/// Null where the name reaches no function, because there is then no call to
/// write and the name alone is the whole of the offer.
fn callWritten(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    name: []const u8,
    signature: DeclId,
) !?Call {
    if (signature == DeclId.none or ast.declTag(signature) != .function) return null;

    var written: std.ArrayList(u8) = .empty;
    defer written.deinit(gpa);

    try written.appendSlice(gpa, name);
    try written.append(gpa, '(');
    const stops = try appendStops(gpa, ast, &written, signature, 0, 0);
    try written.append(gpa, ')');

    // The last stop, which is where the cursor lands once the arguments are
    // filled in. A call with none of them left to fill in leaves the cursor
    // after the bracket by being written there, so there is nothing for a stop
    // to say and the text carries no snippet syntax at all.
    if (stops > 0) try written.appendSlice(gpa, "$0");

    return .{ .text = try written.toOwnedSlice(gpa), .stops = stops };
}

/// What a client is told to do with an item's text: read its stops, or write
/// it as it stands.
///
/// The text is a snippet exactly where it carries a stop, so a call with
/// nothing left to fill in is offered as the plain text it is. Null is what the
/// protocol reads as plain text, and saying so is what it says by default.
fn formatOf(stops: u32) ?lsp.types.InsertTextFormat {
    return if (stops > 0) .Snippet else null;
}

/// The workspace an open file sits in, for the half of the answer that is
/// about modules nobody imported.
///
/// Null where there is no workspace to read: a server before the client has
/// named a folder holds an index of nothing, and what could be imported is a
/// question about files nobody has told it about.
pub const Workspace = struct {
    query: workspace.Query,
    /// The program the file belongs to, as the loader resolves one. The index
    /// filters its answers to this, and a name from another program is one no
    /// import written here could reach.
    program: []const u8,
};

/// What could be written at a point: every name already within reach there.
///
/// A reading of what two passes and one index recorded and nothing else.
/// The scope chain says which bindings a reference at that point would search;
/// each module's own run says what an import of it brings within reach; the
/// workspace index says which modules of this program nobody here imported and
/// what they export. Nothing here resolves a name, because a list that
/// disagreed with what the compiler would bind is a list that teaches the wrong
/// thing.
///
/// **A name the index holds is offered with the import that would reach it**,
/// and spelled the only way it can be written once that import is there.
/// [M-Vis] makes qualified access the one way a name crosses a module boundary,
/// so `size` alone is text no import can make work and `ledger.size` is the
/// offer. The module is offered beside its names, because a reader who knows
/// the module and a reader who knows the name are looking for the same thing.
///
/// **Where the cursor is half-written**, which is nearly always. `add(` is a
/// call the parser never closed, and it recovers with an error node rather than
/// failing -- so the answer comes from the nearest scope the resolver recorded,
/// walking outward from whatever covers the cursor. The construct is unfinished;
/// the body around it is not, and its locals and parameters are what somebody
/// typing there is reaching for. Answering nothing until the construct parses is
/// silence at exactly the moment the question was asked.
///
/// Nothing here spells a type. `nameOf` is what a diagnostic and a dump are
/// spelled with, and a speller of this module's own would agree about `UInt8`
/// and disagree about an instantiation.
///
/// The list is sent whole and marked complete: it is already filtered to one
/// program, and the client's own matching narrows it as the reader types. A
/// server that ranked it as well would be two matchers disagreeing.
///
/// **Costs, at a cursor that is not after a dot:** the binary search over the
/// file's tokens that finding the cursor costs, then the depth of the nesting
/// to reach a recorded scope, then the size of the answer -- the chain's own
/// runs, plus one run per module the file imported, plus this program's own run
/// of the index, a binary search and a slice. Nothing walks the program and
/// nothing walks the workspace.
///
/// **After a dot on a value, what the type declares and one run per trait the
/// module can see.** That is `Reach.each`, and it is what deciding a single
/// written name already costs: the checker asks the same routine, so this
/// offers what a call would mean rather than a reading of its own. Nothing
/// there is sized by the program's declarations -- which declarations were
/// written under each name and which signatures each trait declares are both
/// the resolver's recordings, read here rather than searched for.
///
/// What is left sized by the program is the module's own type names, which is
/// where the traits in scope are found. A file outside this program declares
/// none of them, so the index the workspace keeps does not enter it.
///
/// **Each item written out as a call walks the file's bytes up to the cursor**,
/// which is what converting the edit's range costs. That is the one thing here
/// an editor pays per keystroke that a longer file moves, and it is what to
/// measure first.
///
/// After a dot on a type's, a trait's or a primitive's name it is one lookup
/// and the length of that namespace, both recorded runs. After one on a module
/// an import bound it is that module's own exported run; after one on a name no
/// import bound it is what `appendQualified` costs: the matching modules and their
/// exports, sorted back into the index's original answer order.
///
/// **A function is offered as the call it takes**, with a stop per argument
/// nobody has written -- one pass over that declaration's parameters, and no
/// item costs anything the program's size decides. `snippets` is what the
/// client said at `initialize`, and a client that reads no stop is offered the
/// name alone, which is what it can accept.
pub fn forPosition(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    position: lsp.types.Position,
    encoding: lsp.offsets.Encoding,
    query: workspace.Query,
    program: []const u8,
    snippets: Snippets,
) !?lsp.types.completion.Result {
    const part = checked.program.ast.partOfFile(file) orelse return null;
    const offset = lsp.offsets.positionToIndex(part.source, position, encoding);
    return .{ .completion_list = .{
        .isIncomplete = false,
        .items = try atOffset(
            gpa,
            &checked.program,
            &checked.semantics.res,
            &checked.semantics.typing,
            &checked.cursors,
            file,
            @intCast(offset),
            encoding,
            .{
                .query = query,
                .program = program,
            },
            snippets,
        ),
    } };
}

/// The same answer, at a byte offset and over the recordings themselves.
///
/// The pieces rather than an `Analysis`, so a caller that already checked the
/// program -- the conformance runner, which checks every case once -- asks
/// without checking it a second time. A byte offset rather than a protocol
/// position for the same reason: a property is about a program's own bytes, and
/// converting each of its points would read the file again for every one.
pub fn atOffset(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    typing: *const Typing,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
    encoding: lsp.offsets.Encoding,
    from: ?Workspace,
    snippets: Snippets,
) ![]const Item {
    const ast = &program.ast;
    const in = res.moduleOfFile(file);
    const attribute = attributeContext(ast, file, offset);
    if (attribute == .trait_arguments) return &.{};
    if (attribute == .items) {
        var offered: std.ArrayList(Item) = .empty;
        errdefer {
            for (offered.items) |item| gpa.free(item.label);
            offered.deinit(gpa);
        }
        try offered.ensureTotalCapacity(gpa, std.meta.tags(node.AttributeItemKind).len - 1);
        inline for (std.meta.tags(node.AttributeItemKind)) |kind| {
            if (kind != .unknown) {
                const name = if (kind == .opaque_) "opaque" else @tagName(kind);
                offered.appendAssumeCapacity(.{ .label = try gpa.dupe(u8, name), .kind = .Keyword });
            }
        }
        return offered.toOwnedSlice(gpa);
    }

    // After a dot the answer is what the receiver can do, and only that: the
    // chain's own names cannot be written there, so offering them would be
    // offering text nothing would read.
    if (selectionAt(program, cursors, file, offset)) |sel| {
        return afterADot(gpa, program, res, typing, cursors, file, offset, encoding, sel, from, snippets);
    }

    if (try recipeTypeSelectionAt(gpa, program, res, cursors, file, offset)) {
        var offered: std.ArrayList(Item) = .empty;
        errdefer {
            for (offered.items) |item| gpa.free(item.label);
            offered.deinit(gpa);
        }
        try appendReflectionItem(gpa, &offered, "Type", .TypeParameter);
        return offered.toOwnedSlice(gpa);
    }

    if (writtenTypeSelectionAt(program, typing, file, offset)) |selection| {
        var offered: std.ArrayList(Item) = .empty;
        errdefer {
            for (offered.items) |item| gpa.free(item.label);
            offered.deinit(gpa);
        }
        const owner = cursors.declarationAt(ast, file, offset);
        var candidates: std.ArrayList(typecheck.Associated) = .empty;
        defer candidates.deinit(gpa);
        try typecheck.reachIn(ast, program, res, typing, in, owner)
            .associated(gpa, selection.base, null, &candidates);
        var names: std.AutoHashMapUnmanaged(@import("../support/interner.zig").StringId, ?DeclId) = .empty;
        defer names.deinit(gpa);
        for (candidates.items) |candidate| {
            const name = ast.tokenName(ast.declName(candidate.sig));
            const entry = try names.getOrPut(gpa, name);
            entry.value_ptr.* = if (entry.found_existing) null else candidate.sig;
        }
        for (candidates.items) |candidate| {
            const token = ast.declName(candidate.sig);
            if (names.get(ast.tokenName(token)).? == null) continue;
            const label = try gpa.dupe(u8, ast.tokenText(token));
            errdefer gpa.free(label);
            try offered.append(gpa, .{ .label = label, .kind = .TypeParameter });
        }
        return offered.toOwnedSlice(gpa);
    }

    if (try writtenReferenceModuleFrom(gpa, program, res, cursors, file, offset, attribute)) |module_binding| {
        var offered: std.ArrayList(Item) = .empty;
        errdefer offered.deinit(gpa);
        const target = program.get(in).importedBy(res.importOf(module_binding));
        if (target == .none) return offered.toOwnedSlice(gpa);

        var reachable: std.ArrayList(BindingId) = .empty;
        defer reachable.deinit(gpa);
        try res.reachableThrough(gpa, program, target, in, &reachable);
        for (reachable.items) |binding| {
            if (res.kindOf(binding) != .trait) continue;
            const name = nameOf(ast, res, binding) orelse continue;
            try offered.append(gpa, try itemFor(gpa, ast, res, typing, snippets, name, binding));
        }
        return offered.toOwnedSlice(gpa);
    }

    var visible: std.ArrayList(BindingId) = .empty;
    defer visible.deinit(gpa);
    try res.visibleIn(gpa, scopeAt(program, res, cursors, file, offset), &visible);

    var offered: std.ArrayList(Item) = .empty;
    errdefer offered.deinit(gpa);

    // The names a scope declares twice are one name to whoever writes it, and
    // the chain is ordered innermost first -- so the first of a spelling is the
    // one a reference there would reach, and the rest are what it shadows.
    // Sized by what is visible here, which is the chain and not the program.
    var already: std.StringHashMapUnmanaged(void) = .empty;
    defer already.deinit(gpa);

    for (visible.items) |b| {
        if (res.kindOf(b) == .module and !importedIn(ast, res, b, file)) continue;
        if (attribute == .traits and res.kindOf(b) != .trait and res.kindOf(b) != .module) continue;
        const name = nameOf(ast, res, b) orelse continue;
        if ((try already.getOrPut(gpa, name)).found_existing) continue;
        try offered.append(gpa, try itemFor(gpa, ast, res, typing, snippets, name, b));
    }

    // What each module the file imported makes reachable, spelled the only way
    // it can be written from here. [M-Vis] makes qualified access the one way a
    // name crosses a module boundary, so `size` alone names nothing however it
    // is offered.
    var reachable: std.ArrayList(BindingId) = .empty;
    defer reachable.deinit(gpa);

    var shadowing: std.StringHashMapUnmanaged(void) = .empty;
    defer shadowing.deinit(gpa);
    try namesShadowingImports(gpa, program, res, cursors, file, offset, visible.items, &shadowing);
    for (visible.items) |b| {
        if (res.kindOf(b) != .module) continue;
        if (!importedIn(ast, res, b, file)) continue;
        const qualifier = nameOf(ast, res, b) orelse continue;
        if (shadowing.contains(qualifier)) continue;

        const target = program.get(in).importedBy(res.importOf(b));
        if (target == .none) continue;

        try res.reachableThrough(gpa, program, target, in, &reachable);
        for (reachable.items) |x| {
            if (attribute == .traits and res.kindOf(x) != .trait) continue;
            const name = nameOf(ast, res, x) orelse continue;
            const written = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ qualifier, name });
            defer gpa.free(written);
            try offered.append(gpa, try itemFor(gpa, ast, res, typing, snippets, written, x));
        }
    }

    if (attribute != .traits) {
        if (from) |ws| try appendImportable(gpa, program, file, &offered, ws, encoding);
    }

    return offered.toOwnedSlice(gpa);
}

/// The lexical bindings, among `visible`, that shadow an import of their name
/// at the cursor, collected by name into `into` -- or nothing where the cursor
/// is not on a name written in an expression. A type path at the same point
/// still names the module, so only an expression is filtered.
///
/// Read from the bindings in scope rather than from what the written name
/// resolved to, because a half-typed name resolves to nothing. A binding
/// counts once its declaration has ended before the cursor: one declared
/// later, or whose initializer holds the cursor, is not in scope there yet.
fn namesShadowingImports(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
    visible: []const BindingId,
    into: *std.StringHashMapUnmanaged(void),
) !void {
    const ast = &program.ast;
    const written = positions.tokenBefore(ast, file, offset);
    if (written == .none or ast.tokenTag(written) != .identifier) return;
    if (ast.tokenSpan(written).end != offset) return;
    var chain = cursors.enclosing(ast, file, ast.tokenSpan(written).start);
    const named = switch (chain.next() orelse return) {
        .expr => |e| e,
        else => return,
    };
    if (ast.exprTag(named) != .name_ref or ast.exprMain(named) != written) return;

    for (visible) |b| {
        if (!resolve.kindShadowsAnImport(res.kindOf(b))) continue;
        const declared = res.declaringToken(b);
        if (declared == .none or ast.fileOf(declared) != file) continue;
        if (ast.tokenSpan(declared).start >= offset) continue;
        const statement = res.stmtOf(b);
        if (statement != .none) {
            const init = ast.stmtData(statement).init;
            if (init != .none) {
                const extent = ast.exprExtent(init);
                if (extent.start <= offset and offset <= extent.end) continue;
            }
        }
        try into.put(gpa, ast.tokenText(declared), {});
    }
}

/// Where a cursor sits inside a declaration attribute. A derive entry takes no
/// trait arguments ([T-Derive] refuses them), so nothing is offered inside
/// their brackets.
const AttributeContext = enum { items, traits, trait_arguments };

/// Attribute ranges remain available for incomplete and dangling sequences.
/// Locate one group by token index, then inspect only that group's written items.
fn attributeContext(ast: *const Ast, file: FileId, offset: u32) ?AttributeContext {
    var token = positions.tokenBefore(ast, file, offset);
    if (token == .none) return null;
    if (ast.tokenTag(token) == .eof) {
        if (token.index() == 0) return null;
        token = TokenId.at(token.index() - 1);
    }
    const group = ast.attributeGroupAt(token) orelse return null;
    if (ast.fileOf(group.at) != file or group.tokens.len() == 0) return null;
    const last = TokenId.at(group.tokens.end.index() - 1);
    if (offset > ast.tokenSpan(last).end) return null;
    if (group.close != .none and offset > ast.tokenSpan(group.close).start) return null;
    for (ast.attributeItems(group)) |item| {
        if (item.kind != .derive or item.tokens.len() == 0) continue;
        var open: TokenId = .none;
        for (item.tokens.start.index()..item.tokens.end.index()) |index| {
            const candidate = TokenId.at(@intCast(index));
            if (ast.tokenTag(candidate) == .l_paren) {
                open = candidate;
                break;
            }
        }
        if (open == .none or offset < ast.tokenSpan(open).end) continue;
        const end = TokenId.at(item.tokens.end.index() - 1);
        const closed = ast.tokenTag(end) == .r_paren;
        const limit = if (closed) ast.tokenSpan(end).start else ast.tokenSpan(end).end;
        if (offset <= limit) {
            var brackets: usize = 0;
            for (open.index() + 1..item.tokens.end.index()) |index| {
                const at = TokenId.at(@intCast(index));
                if (ast.tokenSpan(at).start >= offset) break;
                switch (ast.tokenTag(at)) {
                    .l_bracket => brackets += 1,
                    .r_bracket => if (brackets > 0) {
                        brackets -= 1;
                    },
                    else => {},
                }
            }
            return if (brackets == 0) .traits else .trait_arguments;
        }
        if (group.open == .none) return null;
    }
    return .items;
}

fn writtenReferenceModuleFrom(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
    attribute: ?AttributeContext,
) !?BindingId {
    const ast = &program.ast;
    const dot = positions.tokenBefore(ast, file, offset);
    if (dot == .none or ast.tokenTag(dot) != .dot or dot.index() == 0) return null;
    const receiver = TokenId.at(dot.index() - 1);
    if (ast.tokenTag(receiver) != .identifier) return null;

    if (attribute != .traits) {
        var enclosing = cursors.enclosing(ast, file, ast.tokenSpan(receiver).start);
        const declaration = while (enclosing.next()) |entry| switch (entry) {
            .decl => |decl| break decl,
            else => {},
        } else return null;
        if (!declarationEndsTraitReferenceAt(ast, declaration, receiver)) return null;
    }

    var visible: std.ArrayList(BindingId) = .empty;
    defer visible.deinit(gpa);
    try res.visibleIn(gpa, scopeAt(program, res, cursors, file, offset), &visible);
    const wanted = ast.tokenName(receiver);
    for (visible.items) |binding| {
        if (res.kindOf(binding) != .module or ast.tokenName(res.declaringToken(binding)) != wanted) continue;
        if (!importedIn(ast, res, binding, file)) continue;
        return binding;
    }
    return null;
}

fn declarationEndsTraitReferenceAt(ast: *const Ast, decl: DeclId, at: TokenId) bool {
    if (traitReferenceContains(ast.declTraitRef(decl), at)) return true;
    if (ast.declTag(decl) == .derive_impl) {
        for (ast.deriveTraits(decl)) |entry| {
            if (traitReferenceContains(entry.ref, at)) return true;
        }
    }
    for (ast.declAttributeGroups(decl)) |group| {
        for (ast.attributeItems(group)) |item| {
            for (ast.derive_traits[item.derive_traits.start..item.derive_traits.end]) |entry| {
                if (traitReferenceContains(entry.ref, at)) return true;
            }
        }
    }
    for (ast.declBounds(decl)) |bound| {
        if (bound.kind == .named and traitReferenceContains(bound.named, at)) return true;
    }
    for (ast.declTypeParams(decl)) |parameter| {
        for (ast.boundsIn(parameter.bounds)) |bound| {
            if (bound.kind == .named and traitReferenceContains(bound.named, at)) return true;
        }
    }
    for (ast.declWherePredicates(decl)) |predicate| {
        for (ast.boundsIn(predicate.bounds)) |bound| {
            if (bound.kind == .named and traitReferenceContains(bound.named, at)) return true;
        }
    }
    for (ast.templateRequirements(decl)) |requirement| {
        for (ast.boundsIn(requirement.bounds)) |bound| {
            if (bound.kind == .named and traitReferenceContains(bound.named, at)) return true;
        }
    }
    return false;
}

fn traitReferenceContains(ref: node.TraitRef, at: TokenId) bool {
    if (ref.name == at) return true;
    return ref.path.len() != 0 and at.index() >= ref.path.start.index() and at.index() < ref.path.end.index();
}

/// A cursor written after a dot, and what the dot selects from.
const Selection = struct {
    /// What the dot selects from: the receiver of a postfix call, or the
    /// qualifier of a module member. Its groups stripped, because what the
    /// receiver *is* does not depend on how many brackets were written round
    /// it.
    receiver: ExprId,
    /// The call whose callee the selection is, and `.none` where the reader
    /// has not written one. It is what a rewrite replaces, because the
    /// arguments already written belong to the call it becomes.
    call: ExprId,
    /// The whole postfix form as it was written: the call where one was, the
    /// selection otherwise.
    ///
    /// A rewrite replaces this rather than reaching for the receiver's own
    /// extent. The tree keeps parentheses as nodes deliberately, so a range
    /// read off the receiver begins after an opening bracket the node it sits
    /// in still holds -- and accepting the offer leaves that bracket with
    /// nothing to close it.
    whole: ExprId,
    /// Whether the reader has already written `&` before this postfix form:
    /// `&x.op(` while `call` is still `.none`, or a completed call the parser
    /// already recorded as marked. Read off the tree the same way `call` is,
    /// because the marker attaches to whichever of the two exists and never
    /// to both.
    ///
    /// What the marker means once accepted: an operation this offers must
    /// lend its receiver, `inout`, exactly where this is true, so a lend
    /// already written narrows the list to what `&` can reach. Where it is
    /// false, every operation is offered, and accepting one that lends its
    /// receiver is what writes the marker in.
    marked: bool,
};

/// Where a cursor sits after a dot, or null where it does not.
///
/// The tree's own answer rather than a reading of the bytes. `p.` is a
/// selection the parser builds whether or not a name follows the dot, so what
/// the dot selects from is resolved and typed either way.
///
/// **Two points, because a selection with no name ends at its dot.** A cursor
/// inside the name is inside the node; a cursor typed straight after the dot
/// is past the node's last byte, and what the tree records over that point is
/// whatever call or block surrounds it. So the dot itself is the second place
/// to ask from, and the token before the cursor is what says a dot was
/// written.
///
/// A cursor at the receiver's end is still writing the receiver: `coppers|.of`
/// is a point where `coppers` could still become `coppersworth`.
///
/// Costs the binary search finding the cursor, at most one more finding the
/// token in front of it, and two steps outward.
fn selectionAt(
    program: *const program_mod.Program,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
) ?Selection {
    if (selectionOver(program, cursors, file, offset, offset)) |sel| return sel;

    const ast = &program.ast;
    const dot = positions.tokenBefore(ast, file, offset);
    if (dot == TokenId.none or ast.tokenTag(dot) != .dot) return null;
    return selectionOver(program, cursors, file, ast.tokenSpan(dot).start, offset);
}

/// The same question asked from `at`, about a cursor written at `offset`.
///
/// The two are one point wherever the reader has written a name, and the dot's
/// own byte and the cursor after it where they have not.
fn selectionOver(
    program: *const program_mod.Program,
    cursors: *const positions.Index,
    file: FileId,
    at: u32,
    offset: u32,
) ?Selection {
    const ast = &program.ast;
    var chain = cursors.enclosing(ast, file, at);

    var selected = switch (chain.next() orelse return null) {
        .expr => |e| e,
        else => return null,
    };
    if (ast.exprTag(selected) != .field) {
        // At the start of a dot the cursor index favors the identifier ending
        // there. A completion after that dot belongs to its enclosing field.
        if (offset <= ast.exprSpan(selected).end) return null;
        const parent = switch (chain.next() orelse return null) {
            .expr => |e| e,
            else => return null,
        };
        if (ast.exprTag(parent) != .field or
            ast.withoutGroups(ast.unaryOperand(parent)) != ast.withoutGroups(selected)) return null;
        selected = parent;
    }

    const receiver = ast.withoutGroups(ast.unaryOperand(selected));
    if (receiver == ExprId.none) return null;
    if (offset <= ast.exprSpan(receiver).end) return null;

    if (chain.next()) |around| {
        switch (around) {
            .expr => |e| {
                if (ast.exprTag(e) == .call and ast.withoutGroups(ast.call(e).callee) == selected) {
                    return .{ .receiver = receiver, .call = e, .whole = e, .marked = ast.callMarked(e) };
                }
                // `&x.op` with no call written yet: the parser has nowhere on
                // a call to set the marker, so it wraps the selection itself.
                if (ast.exprTag(e) == .marked and ast.withoutGroups(ast.unaryOperand(e)) == selected) {
                    return .{ .receiver = receiver, .call = ExprId.none, .whole = selected, .marked = true };
                }
            },
            else => {},
        }
    }
    return .{ .receiver = receiver, .call = ExprId.none, .whole = selected, .marked = false };
}

fn reflectionSelectionNamed(ast: *const Ast, id: ExprId, name: []const u8) bool {
    if (ast.exprTag(id) != .field or !std.mem.eql(u8, ast.tokenText(ast.exprMain(id)), name)) return false;
    return ast.exprTag(ast.withoutGroups(ast.unaryOperand(id))) == .reflection_root;
}

fn reflectedSequence(ast: *const Ast, id: ExprId) bool {
    const sequence = ast.withoutGroups(id);
    if (reflectionSelectionNamed(ast, sequence, "components")) return true;
    if (ast.exprTag(sequence) != .field or
        !std.mem.eql(u8, ast.tokenText(ast.exprMain(sequence)), "reversed")) return false;
    return reflectionSelectionNamed(ast, ast.withoutGroups(ast.unaryOperand(sequence)), "components");
}

fn spanContains(span: Span, offset: u32) bool {
    return offset >= span.start and offset <= span.end;
}

const ReflectionCompletionContext = struct {
    in_template: bool = false,
    active_case: bool = false,
    component_binder: bool = false,
    recipe_binder: bool = false,
    in_components: bool = false,
};

fn reflectionCompletionContext(
    program: *const program_mod.Program,
    res: *const Resolution,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
    receiver_binding: BindingId,
) ReflectionCompletionContext {
    const ast = &program.ast;
    var answer: ReflectionCompletionContext = .{};
    var chain = cursors.enclosing(ast, file, offset);
    while (chain.next()) |entry| switch (entry) {
        .decl => |decl| if (ast.declTag(decl) == .template_impl) {
            answer.in_template = true;
        },
        .expr => |expression| switch (ast.exprTag(expression)) {
            .match_, .match_read => {
                const matched = ast.call(expression);
                var arm: usize = 0;
                while (arm + 1 < matched.args.len) : (arm += 2) {
                    const pattern = ast.withoutGroups(matched.args[arm]);
                    if (!reflectionSelectionNamed(ast, pattern, "case") and
                        !reflectionSelectionNamed(ast, pattern, "same_case")) continue;
                    if (spanContains(ast.exprSpan(matched.args[arm + 1]), offset)) answer.active_case = true;
                }
            },
            .for_, .for_read, .for_inout => {
                const loop = ast.call(expression);
                if (!reflectedSequence(ast, loop.callee) or
                    !spanContains(ast.exprSpan(loop.args[1]), offset)) continue;
                answer.in_components = true;
                if (receiver_binding != .none and res.targetOf(loop.args[0]) == receiver_binding) {
                    answer.component_binder = true;
                }
            },
            .call => {
                const call = ast.call(expression);
                if (!reflectionSelectionNamed(ast, call.callee, "construct") or call.args.len != 3 or
                    ast.exprTag(call.args[1]) != .lambda) continue;
                const recipe = ast.lambda(call.args[1]);
                if (recipe.params.len != 1 or !spanContains(ast.exprSpan(recipe.body), offset)) continue;
                answer.in_components = true;
                if (receiver_binding != .none and res.declaringToken(receiver_binding) == recipe.params[0].name) {
                    answer.recipe_binder = true;
                }
            },
            else => {},
        },
        else => {},
    };
    return answer;
}

fn appendReflectionItem(
    gpa: std.mem.Allocator,
    offered: *std.ArrayList(Item),
    label: []const u8,
    kind: Item.Kind,
) !void {
    try offered.append(gpa, .{ .label = try gpa.dupe(u8, label), .kind = kind });
}

fn appendReflectionSelections(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
    receiver: ExprId,
    offered: *std.ArrayList(Item),
) !bool {
    const ast = &program.ast;
    const root = ast.withoutGroups(receiver);
    const context = reflectionCompletionContext(program, res, cursors, file, offset, res.targetOf(root));

    if (ast.exprTag(root) == .reflection_root) {
        if (!context.in_template) return true;
        if (!context.in_components) {
            try appendReflectionItem(gpa, offered, "construct", .Function);
            try appendReflectionItem(gpa, offered, "product", .Field);
        }
        if (context.active_case) {
            try appendReflectionItem(gpa, offered, "same_case", .Field);
            try appendReflectionItem(gpa, offered, "other_case", .Field);
            try appendReflectionItem(gpa, offered, "components", .Field);
        } else {
            try appendReflectionItem(gpa, offered, "case", .Field);
            try appendReflectionItem(gpa, offered, "ordinal_of", .Function);
        }
        return true;
    }

    if (reflectionSelectionNamed(ast, root, "case")) {
        if (context.in_template and context.active_case) {
            try appendReflectionItem(gpa, offered, "name", .Field);
            try appendReflectionItem(gpa, offered, "ordinal", .Field);
            try appendReflectionItem(gpa, offered, "components_named", .Field);
        }
        return true;
    }

    if (context.in_template and (context.recipe_binder or (context.active_case and context.component_binder))) {
        try appendReflectionItem(gpa, offered, "name", .Field);
        try appendReflectionItem(gpa, offered, "ordinal", .Field);
        if (context.component_binder) try appendReflectionItem(gpa, offered, "of", .Method);
        return true;
    }
    return false;
}

/// What can be written after a dot: the parts the receiver's type holds and
/// the operations it answers to, or every name the module it qualifies
/// exports.
///
/// **The names in scope are not among them.** A local, a module or a type
/// cannot be written after a dot, so offering the enclosing scope there is a
/// list of everything the position rejects. Where the receiver holds no part
/// and answers to no operation, the answer is empty.
///
/// **Fields come first**, because reading one is the commoner gesture by far.
///
/// **Which operations apply is the checker's answer.** `Reach` is the routine
/// that decided what `coppers.weight()` means; asking it here is what keeps an
/// editor from offering an operation the compiler would refuse. A name matched
/// against the traits from this side would be a second reading of a rule that
/// has three parts -- what the module can see, what the type implements, and
/// what the trait declares with `Self` first.
///
/// **A type's name is not a value of that type.** `Pair.` opens the namespace
/// the name is written for, and what may follow it is what that namespace
/// holds: an enum's variants, a trait's operations, a type's own declarations,
/// what the library wrote for a primitive. A field belongs to a value and an
/// operation is reached through the trait that declares it, so neither can be
/// written there -- and `Resolution` is what says which, because it is what
/// settled the same names where the corpus already writes them.
///
/// A module qualifier is the other shape, and there are two of them: one an
/// import already bound, whose names are reached with nothing further to
/// write, and one nobody imported, whose names carry the import that binds the
/// qualifier. The second is the rule for an unimported name reaching the one
/// place a qualifier is already written, not a rule of its own.
fn afterADot(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    typing: *const Typing,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
    encoding: lsp.offsets.Encoding,
    sel: Selection,
    from: ?Workspace,
    snippets: Snippets,
) ![]const Item {
    const ast = &program.ast;

    var offered: std.ArrayList(Item) = .empty;
    errdefer offered.deinit(gpa);

    if (try appendReflectionSelections(gpa, program, res, cursors, file, offset, sel.receiver, &offered)) {
        return offered.toOwnedSlice(gpa);
    }

    const names = res.targetOf(sel.receiver);
    if (names != BindingId.none) {
        if (res.kindOf(names) == .module) {
            if (importedIn(ast, res, names, file)) {
                try appendReached(gpa, program, res, typing, file, &offered, names, snippets);
            }
            return offered.toOwnedSlice(gpa);
        }
        if (resolve.namesANamespace(res.kindOf(names))) {
            const receiver_type = typing.exprType(sel.receiver);
            const owner = cursors.declarationAt(ast, file, offset);
            if (typing.isIntegerWithin(owner, receiver_type)) {
                for (std.enums.values(types.IntegerEndpoint)) |endpoint| {
                    const label = try gpa.dupe(u8, @tagName(endpoint));
                    errdefer gpa.free(label);
                    const detail = try gpa.dupe(u8, typing.nameOf(receiver_type));
                    errdefer gpa.free(detail);
                    try offered.append(gpa, .{ .label = label, .kind = .Constant, .detail = detail });
                }
            }
            try appendSelectable(gpa, program, res, typing, file, &offered, names, snippets);
            if (res.kindOf(names) != .trait) try appendOperationsThroughType(gpa, program, res, typing, file, owner, receiver_type, &offered, snippets);
            return offered.toOwnedSlice(gpa);
        }
    } else if (ast.exprTag(sel.receiver) == .name_ref) {
        if (from) |ws| {
            try appendQualified(gpa, program, file, &offered, ws, encoding, ast.exprText(sel.receiver));
            return offered.toOwnedSlice(gpa);
        }
    }

    const held = typing.exprType(sel.receiver);
    if (held == .poison) return offered.toOwnedSlice(gpa);

    const owner = cursors.declarationAt(ast, file, offset);
    try appendFields(gpa, typing, held, &offered);
    if (typing.arrayViewReceiver(held)) |adjustment| {
        const element = typing.get(adjustment.receiver).array.element;
        const label = try gpa.dupe(u8, types.array_view_name);
        errdefer gpa.free(label);
        const detail = try std.fmt.allocPrint(gpa, "fn() -> mem.Slice[{s}] where borrows(source)", .{typing.nameOf(element)});
        errdefer gpa.free(detail);
        try offered.append(gpa, .{ .label = label, .kind = .Method, .detail = detail });
    }
    if (typing.get(typing.observedReceiver(held).receiver) == .array) {
        const label = try gpa.dupe(u8, types.array_length_name);
        errdefer gpa.free(label);
        const detail = try gpa.dupe(u8, "fn() -> UInt64");
        errdefer gpa.free(detail);
        try offered.append(gpa, .{ .label = label, .kind = .Method, .detail = detail });
    }
    // What declares each name the receiver answers to, because that is what
    // decides which item the postfix form reaches -- and an operation a `use`
    // would bring is judged against the same table, with itself added.
    var declaring: std.StringHashMapUnmanaged(typecheck.NameReach) = .empty;
    defer declaring.deinit(gpa);
    try appendOperations(gpa, program, res, typing, file, owner, offset, encoding, sel, held, &offered, snippets, &declaring);
    try appendOperationsElsewhere(gpa, program, res, typing, file, owner, offset, encoding, sel, held, &offered, snippets, &declaring);
    return offered.toOwnedSlice(gpa);
}

/// What the receiver would answer to if a trait this module cannot see were
/// brought into scope, each item carrying the `use` that would bring it.
///
/// **Offering these is not the editor disagreeing with the compiler.** The
/// compiler refuses the call as written, and so it should: the trait is out of
/// scope. What an item here says is what the reader would have to write for it
/// to resolve, and accepting one writes both halves -- the name at the cursor
/// and the `use` above. A reader who never accepts it is told nothing false.
///
/// The enumeration is `Reach`'s, the same one that decides what a call means,
/// asked with the scope test turned round. Matching names against traits here
/// would be a second reading of a rule that has three parts, and the editor
/// would be free to offer what the compiler would refuse.
///
/// **An item that keeps its dot must reach what it describes once the `use`
/// is written.** With the trait in scope, the postfix form still reaches the
/// type's own operation of that name, and two traits declaring it leave the
/// call ambiguous; `typecheck.NameReach.reaches`, asked over what is in scope
/// with this trait added, says which. Where the dot would not reach it, the
/// item writes the call out as `Shut.close(door)` beside its `use`, and where
/// the call spans lines and cannot be written out, the item is left out: an
/// item accepted must not run something other than what it named.
///
/// Costs one walk of the traits the program declares, and per item one
/// signature's name. The `use` each would need is worked out once.
fn appendOperationsElsewhere(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    typing: *const Typing,
    file: FileId,
    owner: node.DeclId,
    offset: u32,
    encoding: lsp.offsets.Encoding,
    sel: Selection,
    held: types.TypeId,
    offered: *std.ArrayList(Item),
    snippets: Snippets,
    declaring: *const std.StringHashMapUnmanaged(typecheck.NameReach),
) !void {
    const ast = &program.ast;
    const part = ast.partOfFile(file) orelse return;

    var applicable: std.ArrayList(typecheck.Applicable) = .empty;
    defer applicable.deinit(gpa);
    try typecheck.reachIn(ast, program, res, typing, res.moduleOfFile(file), owner)
        .eachElsewhere(gpa, held, &applicable);
    if (applicable.items.len == 0) return;

    const place = fix.placementForUse(ast, part, part.source);
    const replaced = replacedRange(ast, part, sel, offset, encoding);

    // One edit per trait rather than per operation: a trait declaring three
    // operations needs one `use`, and working it out per item would write the
    // same line three times over.
    var written: std.AutoHashMapUnmanaged(node.DeclId, fix.Import) = .empty;
    defer {
        var held_edits = written.valueIterator();
        while (held_edits.next()) |w| release(gpa, w.*);
        written.deinit(gpa);
    }

    for (applicable.items) |a| {
        // The same lend the dot-kept offer honours: once `&` is written, only
        // an operation it could reach is worth suggesting, in scope or not.
        const convention = receiverConvention(ast, a.sig);
        if (sel.marked and convention != .inout) continue;

        const name = ast.tokenText(ast.declName(a.sig));

        // Whether `x.name()` would reach this operation once its trait is in
        // scope: what is in scope already, with this trait added.
        var reach: typecheck.NameReach = declaring.get(name) orelse .{};
        reach.note(a);
        const dotted = reach.reaches(a);
        if (!dotted and replaced == null) continue;

        // Whether accepting this item must write `&` in, exactly as the
        // dot-kept offer decides it -- the item keeps its dot or writes the
        // qualifier out, but either way lends the same receiver.
        const needs_marker = convention == .inout and !sel.marked;
        const writability: Writability = if (needs_marker)
            try receiverWritability(gpa, res, ast, sel.receiver)
        else
            .{ .writable = false, .detail = null };
        const marker = needs_marker and writability.writable and replaced != null;
        const detail = writability.detail;

        const writes = written.get(a.trait) orelse blk: {
            const made = try fix.writingUse(
                gpa,
                program,
                res,
                file,
                a.trait,
                part.source,
                place,
                encoding,
            );
            errdefer release(gpa, made);
            try written.put(gpa, a.trait, made);
            break :blk made;
        };

        // The `use` binds the trait's own name, which is what the written-out
        // call spells it by.
        const rewritten = if (dotted and !marker)
            null
        else if (replaced) |range|
            try writtenOut(gpa, ast, part, sel, range, if (dotted) null else writes.binds, name, a.sig, snippets, marker)
        else
            null;

        try offered.append(gpa, .{
            .label = try gpa.dupe(u8, name),
            .labelDetails = .{ .description = try gpa.dupe(u8, writes.path) },
            .kind = .Method,
            .detail = detail,
            .textEdit = if (rewritten) |w| .{ .text_edit = w.edit } else null,
            .insertTextFormat = if (rewritten) |w| formatOf(w.stops) else null,
            .additionalTextEdits = try useEdits(gpa, writes),
        });
    }
}

/// The range a written-out call replaces: the postfix form the reader
/// started, from its receiver to the end of the call or to the cursor. Null
/// where the call spans lines, since an item's own edit replaces one line and
/// a client given more may refuse the item or apply it somewhere else.
///
/// Computed once per request rather than per item, because converting a byte
/// offset walks the file's bytes to reach it.
fn replacedRange(
    ast: *const Ast,
    part: *const FilePart,
    sel: Selection,
    offset: u32,
    encoding: lsp.offsets.Encoding,
) ?lsp.types.Range {
    const span: Span = .{
        .start = ast.exprSpan(sel.whole).start,
        .end = if (sel.call != ExprId.none) ast.exprSpan(sel.call).end else offset,
    };
    const range = positions.rangeOf(part.source, span, encoding);
    return if (range.start.line != range.end.line) null else range;
}

/// Find the checker's base type at a complete or unfinished selection.
fn writtenTypeSelectionAt(
    program: *const program_mod.Program,
    typing: *const Typing,
    file: FileId,
    offset: u32,
) ?types.TypeSelection {
    return typing.typeSelection(writtenDotAt(&program.ast, file, offset) orelse return null);
}

fn writtenDotAt(ast: *const Ast, file: FileId, offset: u32) ?TokenId {
    const part = ast.partOfFile(file) orelse return null;
    const before = positions.tokenBefore(ast, file, offset);
    if (before == .none) return null;
    if (ast.tokenTag(before) == .dot) return before;
    if (ast.tokenTag(before) != .identifier or before.index() == part.token_start) return null;
    const prior = TokenId.at(before.index() - 1);
    return if (ast.tokenTag(prior) == .dot) prior else null;
}

/// Recipes erase their component types before checking. Read the parsed local
/// annotation and the resolver's lexical binding, including recovery scopes.
fn recipeTypeSelectionAt(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
) !bool {
    const ast = &program.ast;
    const dot = writtenDotAt(ast, file, offset) orelse return false;
    var enclosing = cursors.enclosing(ast, file, offset);
    const base = while (enclosing.next()) |entry| switch (entry) {
        .stmt => |statement| {
            if (ast.stmtTag(statement) != .let_decl) continue;
            if (selectionBaseAt(ast, ast.stmtData(statement).annotation, dot)) |candidate| break candidate;
        },
        else => {},
    } else return false;
    const named = ast.withoutTypeGroups(base);
    if (named.kind != .named or named.name == .none or named.args.len() != 0) return false;
    var binding = res.writtenAt(named.name);
    if (binding == .none) {
        var visible: std.ArrayList(BindingId) = .empty;
        defer visible.deinit(gpa);
        try res.visibleIn(gpa, scopeAt(program, res, cursors, file, offset), &visible);
        for (visible.items) |candidate| {
            const token = res.declaringToken(candidate);
            if (token != .none and ast.tokenName(token) == ast.tokenName(named.name)) {
                binding = candidate;
                break;
            }
        }
    }
    const context = reflectionCompletionContext(program, res, cursors, file, offset, binding);
    return context.in_template and context.recipe_binder;
}

fn selectionBaseAt(ast: *const Ast, written: node.TypeRef, dot: TokenId) ?node.TypeRef {
    if (!written.wasWritten()) return null;
    if (written.kind == .selection) {
        if (written.dot == dot) return ast.selectionBase(written);
        if (selectionBaseAt(ast, ast.selectionBase(written), dot)) |base| return base;
    }
    if (written.kind == .callable) {
        const callable = ast.callableType(written);
        for (ast.params[callable.params.start..callable.params.end]) |parameter| if (selectionBaseAt(ast, parameter.written, dot)) |base| return base;
        if (selectionBaseAt(ast, callable.result, dot)) |base| return base;
    }
    for (ast.typeArgs(written.args)) |argument| if (selectionBaseAt(ast, argument, dot)) |base| return base;
    return null;
}

/// What may be written after a dot on a type's, a trait's or a primitive's
/// name: what that namespace holds, and an enum's variants.
///
/// **The resolver's own answer.** `selectableUnder` is the list form of what
/// settles every qualified name the program already writes -- the same rows,
/// the same order, the same visibility rule. A reading of the declarations from
/// here would be a second answer to what `Colour.` means, and the one this
/// module is not entitled to give.
///
/// Costs what that answer costs: one lookup and the length of the namespace.
fn appendSelectable(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    typing: *const Typing,
    file: FileId,
    offered: *std.ArrayList(Item),
    b: BindingId,
    snippets: Snippets,
) !void {
    const ast = &program.ast;

    var reaches: std.ArrayList(resolve.Selectable) = .empty;
    defer reaches.deinit(gpa);
    try resolve.selectableUnder(gpa, ast, program, res, res.moduleOfFile(file), b, &reaches);

    for (reaches.items) |written| switch (written) {
        .member => |m| {
            // Associated types are offered only in written type selections.
            if (!resolve.standsWhereAValueBelongs(res.kindOf(m))) continue;
            const name = nameOf(ast, res, m) orelse continue;
            try offered.append(gpa, try itemFor(gpa, ast, res, typing, snippets, name, m));
        },
        .variant => |at| try offered.append(gpa, .{
            .label = try gpa.dupe(u8, ast.tokenText(at)),
            .kind = .EnumMember,
            // What a variant is worth is the enum, which is written to the
            // left of the dot -- so the label leaves nothing out.
            .detail = null,
        }),
    };
}

/// The operations of the traits in scope that a type implements, or that a
/// type parameter's bounds promise, which a name written after the type's
/// name reaches: `Limits.` offers `default` where `Limits` implements
/// `Default`.
///
/// **`Reach.namespaced` is the checker's own answer**, read through
/// `keepReached`, so an item is offered exactly where the checker accepts
/// `Limits.default()`. The type's own operations are offered with its
/// namespace and win their name, and a name two traits answer is ambiguous
/// after the dot, so neither is offered here.
///
/// Costs one walk of the traits the module sees and one applicability
/// question per trait, and a lookup per item among the names offered so far.
fn appendOperationsThroughType(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    typing: *const Typing,
    file: FileId,
    owner: node.DeclId,
    held: types.TypeId,
    offered: *std.ArrayList(Item),
    snippets: Snippets,
) !void {
    const ast = &program.ast;
    if (held == .poison) return;

    var applicable: std.ArrayList(typecheck.Applicable) = .empty;
    defer applicable.deinit(gpa);
    try typecheck.reachIn(ast, program, res, typing, res.moduleOfFile(file), owner)
        .namespaced(gpa, held, null, true, &applicable, null);
    if (applicable.items.len == 0) return;

    var own: std.StringHashMapUnmanaged(void) = .empty;
    defer own.deinit(gpa);
    for (offered.items) |item| try own.put(gpa, item.label, {});

    try typecheck.keepReached(gpa, ast, &applicable);
    for (applicable.items) |a| {
        // The type's own operations were offered with its namespace.
        if (a.trait == node.DeclId.none) continue;
        const name = ast.tokenText(ast.declName(a.sig));
        if (own.contains(name)) continue;
        const call = if (snippets == .supported) try callWritten(gpa, ast, name, a.sig) else null;
        try offered.append(gpa, .{
            .label = try gpa.dupe(u8, name),
            .labelDetails = .{ .description = try gpa.dupe(u8, ast.tokenText(ast.declName(a.trait))) },
            .kind = .Method,
            .insertText = if (call) |c| c.text else null,
            .insertTextFormat = if (call) |c| formatOf(c.stops) else null,
        });
    }
}

/// Every part the receiver's type holds, in the order the type declares them.
///
/// **The checker's own answer.** What a type holds is decided once, where the
/// declaration is read, and a reading of the tree from here would be a second
/// one -- which is how an editor comes to offer a part a type does not have.
/// It is the same routine that decided `p.x` was a field rather than an
/// operation.
///
/// Costs one pass over what this type holds. Nothing here is sized by the
/// program.
fn appendFields(
    gpa: std.mem.Allocator,
    typing: *const Typing,
    held: types.TypeId,
    offered: *std.ArrayList(Item),
) !void {
    const receiver = typing.observedReceiver(held).receiver;
    for (0..typing.fieldCount(receiver)) |i| {
        const at: u32 = @intCast(i);
        try appendField(gpa, typing, typing.fieldName(receiver, at), typing.fieldType(receiver, at), offered);
    }
}

fn appendField(gpa: std.mem.Allocator, typing: *const Typing, name: []const u8, ty: types.TypeId, offered: *std.ArrayList(Item)) !void {
    const label = try gpa.dupe(u8, name);
    errdefer gpa.free(label);
    const detail = if (typing.settledName(ty)) |text| try gpa.dupe(u8, text) else null;
    errdefer if (detail) |text| gpa.free(text);
    try offered.append(gpa, .{ .label = label, .kind = .Field, .detail = detail });
}

/// What a module an import already bound exports, under the names it exports
/// them by. The qualifier is written, so the text after the dot is the bare
/// name.
fn appendReached(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    typing: *const Typing,
    file: FileId,
    offered: *std.ArrayList(Item),
    b: BindingId,
    snippets: Snippets,
) !void {
    const ast = &program.ast;
    const writing = res.moduleOfFile(file);
    const target = program.get(writing).importedBy(res.importOf(b));
    if (target == .none) return;

    var reachable: std.ArrayList(BindingId) = .empty;
    defer reachable.deinit(gpa);
    try res.reachableThrough(gpa, program, target, writing, &reachable);

    for (reachable.items) |x| {
        const name = nameOf(ast, res, x) orelse continue;
        try offered.append(gpa, try itemFor(gpa, ast, res, typing, snippets, name, x));
    }
}

/// What a module of this program that nothing imported exports, each item
/// carrying the import that binds the qualifier already written.
///
/// The qualifier decides which modules are in play, so this is the run of them
/// that share its leaf, then only those modules' exported entries. Matching
/// entries are sorted by their original index, preserving the order across
/// ambiguous module leaves without reading unrelated exports.
///
/// A module whose name an import written here could not bind is left out, which
/// is `takenFromAnImportIn` and not a rule of this function's: what a file may
/// import is one question, and the answer an offer beside a dot gives is the
/// answer the one beside a plain name gives.
fn appendQualified(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    file: FileId,
    offered: *std.ArrayList(Item),
    ws: Workspace,
    encoding: lsp.offsets.Encoding,
    leaf: []const u8,
) !void {
    const part = program.ast.partOfFile(file) orelse return;
    const place = fix.placementIn(&program.ast, part, part.source);

    // Each matching module supplies one import and its own export run. The
    // final sort touches only offered entries, restoring the index's order.
    var reached: std.StringHashMapUnmanaged(fix.Import) = .empty;
    defer {
        var held = reached.valueIterator();
        while (held.next()) |w| release(gpa, w.*);
        reached.deinit(gpa);
    }

    const taken = try fix.takenFromAnImportIn(gpa, program, file);
    defer gpa.free(taken);

    var matches: std.ArrayList(workspace.EntryId) = .empty;
    defer matches.deinit(gpa);

    for (ws.query.modulesNamed(ws.program, leaf)) |m| {
        const writes = try fix.writingImport(gpa, ws.program, m.dir, part.source, place, encoding) orelse continue;
        if (fix.indexOfName(taken, writes.binds) != null) {
            release(gpa, writes);
            continue;
        }
        reached.put(gpa, m.dir, writes) catch |err| {
            release(gpa, writes);
            return err;
        };
        try matches.appendSlice(gpa, ws.query.entriesIn(m));
    }
    std.mem.sort(workspace.EntryId, matches.items, {}, struct {
        fn less(_: void, a: workspace.EntryId, b: workspace.EntryId) bool {
            return a.index() < b.index();
        }
    }.less);

    for (matches.items) |id| {
        const e = ws.query.entry(id);
        const writes = reached.get(e.module).?;
        try offered.append(gpa, .{
            .label = try gpa.dupe(u8, e.name),
            .labelDetails = .{ .description = try gpa.dupe(u8, writes.path) },
            .kind = exported(e.kind),
            .detail = try gpa.dupe(u8, e.header),
            .additionalTextEdits = try useEdits(gpa, writes),
        });
    }
}

/// The convention an operation's own receiver parameter declares: `read`,
/// `inout` or `sink`.
///
/// The receiver is always an applicable operation's first parameter --
/// `Reach` only ever notes a function whose first parameter took the
/// receiver -- so this is the one lookup that answers, and the checker's own
/// marking rule reads the same parameter the same way.
fn receiverConvention(ast: *const Ast, sig: DeclId) node.Convention {
    return ast.declParams(sig)[0].convention;
}

/// Whether an unmarked `inout` operation's receiver may be marked `&`, and
/// why not when it may not.
const Writability = struct {
    writable: bool,
    /// Set only where `writable` is false, for an item offered without the
    /// edit instead of not offered at all.
    detail: ?[]const u8,
};

/// Decides whether accepting an `inout` operation on `sel.receiver` may write
/// `&` in for the reader, one routine for both the dot-kept offer and the
/// qualified, out-of-scope one.
///
/// **Reads `Resolution.placeIsMutable`, not a second analysis of its own.**
/// That is the same walk-to-a-root-place answer `&` and an assignment are
/// checked against, so a call's result and a field reached through a
/// read-only parameter both answer `false` here exactly because they answer
/// `false` there -- neither needs a special case written beside this call,
/// and neither can drift from what the checker would say about the same
/// receiver.
///
/// The detail names what `Resolution.placeRoot` finds at the root of the
/// same walk: the local or parameter whose own declaration settles it, or,
/// where the walk never reaches one, that the receiver is not a place a
/// caller could bind and mark instead.
fn receiverWritability(gpa: std.mem.Allocator, res: *const Resolution, ast: *const Ast, receiver: ExprId) !Writability {
    if (res.placeIsMutable(ast, receiver)) return .{ .writable = true, .detail = null };
    const root = res.placeRoot(ast, receiver);
    const detail = if (root == BindingId.none)
        try gpa.dupe(u8, "mutates its receiver, and a value that is not a place cannot be lent")
    else switch (res.kindOf(root)) {
        .local => try std.fmt.allocPrint(gpa, "mutates its receiver; `{s}` is declared with `let`", .{ast.tokenText(res.declaringToken(root))}),
        .parameter => try std.fmt.allocPrint(gpa, "mutates its receiver; `{s}` is a read-only parameter", .{ast.tokenText(res.declaringToken(root))}),
        else => try gpa.dupe(u8, "mutates its receiver, which cannot be written here"),
    };
    return .{ .writable = false, .detail = detail };
}

/// Every operation applicable to the receiver's type, one item per trait that
/// declares it.
///
/// **Where the postfix form does not reach an item, accepting rewrites the
/// call.** Two traits declaring it is [N-Ambiguous], and a trait's operation
/// beside the type's own is reached only written out, so the item replaces the
/// whole postfix call with `Measure.weight(coppers)`. An insertion at the
/// cursor would leave text that runs something else or that the compiler
/// refuses. Which item the postfix form reaches is
/// `typecheck.NameReach.reaches`, the rule the checker applies.
///
/// **Where the postfix form reaches it, the dot stays.** Rewriting a call nothing is wrong
/// with would be this module having an opinion about spelling, which the tree
/// deliberately does not have: it keeps both spellings so that nothing below it
/// can tell them apart.
///
/// **Both spellings are written over the postfix form the reader started**,
/// where the client reads a stop. This is the one place an item knows what is
/// already in the buffer -- finding the operation at all meant finding the call
/// the dot belongs to -- so the brackets a reader typed are replaced rather
/// than left standing beside a second pair. Everywhere else the client's own
/// replacement of the word being typed is what applies, which is the protocol's
/// rule and the one every other item here is written under.
///
/// Costs what deciding one written name costs -- what the type declares and
/// one run per trait the module can see -- plus one pass over what applies,
/// and per item one pass over one signature's parameters and one walk of the
/// file's bytes up to the cursor, which is what the edit's range costs. The
/// table counting the names, `declaring`, is sized by what applies to this
/// type, not by the program; it is left filled for the caller, so the items
/// a `use` would bring are judged against the same count.
fn appendOperations(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    typing: *const Typing,
    file: FileId,
    owner: node.DeclId,
    offset: u32,
    encoding: lsp.offsets.Encoding,
    sel: Selection,
    held: types.TypeId,
    offered: *std.ArrayList(Item),
    snippets: Snippets,
    declaring: *std.StringHashMapUnmanaged(typecheck.NameReach),
) !void {
    const ast = &program.ast;
    const part = ast.partOfFile(file) orelse return;

    var applicable: std.ArrayList(typecheck.Applicable) = .empty;
    defer applicable.deinit(gpa);
    try typecheck.reachIn(ast, program, res, typing, res.moduleOfFile(file), owner)
        .each(gpa, held, &applicable);

    // The range a rewrite replaces, and whether one may be offered at all.
    // Where the call spans lines, an item is written in at the cursor like
    // any other -- an offer worse than the rewrite, but an offer, which a
    // dropped item is not.
    const replaced = replacedRange(ast, part, sel, offset, encoding);

    // What declares each name, because that is what decides which item the
    // postfix form reaches.
    for (applicable.items) |a| {
        const gop = try declaring.getOrPut(gpa, ast.tokenText(ast.declName(a.sig)));
        if (!gop.found_existing) gop.value_ptr.* = .{};
        gop.value_ptr.note(a);
    }

    for (applicable.items) |a| {
        // `&` lends the receiver of the postfix call it marks, so once it is
        // written the offer is only what it can lend: an operation whose own
        // receiver is `read` or `sink` cannot be reached through it, and
        // suggesting one would be an item accepting itself into a call the
        // checker refuses.
        const convention = receiverConvention(ast, a.sig);
        if (sel.marked and convention != .inout) continue;

        const name = ast.tokenText(ast.declName(a.sig));
        // What declares it: the trait, or the type itself for an inherent one.
        // Beside the label rather than in it, because two items reading the
        // same name is the whole point -- the description is what says which.
        const through = ast.tokenText(ast.declOwner(a.sig));

        // Which spelling the item writes. An item the postfix form does not
        // reach needs the qualifier; the one it reaches keeps its dot.
        const ambiguous = !declaring.get(name).?.reaches(a);
        const qualifier: ?[]const u8 = if (ambiguous) through else null;

        // Whether accepting this item must write `&` in for the reader: an
        // operation that lends its receiver, where the reader has not already
        // marked the call, and where the receiver is a place `&` may lend at
        // all. Where it may not, the item is offered without the edit and
        // says why in its detail instead -- it still names a real operation,
        // and the checker's own suggestion is what walks the reader from
        // there to a place it can mark.
        const needs_marker = convention == .inout and !sel.marked;
        const writability: Writability = if (needs_marker)
            try receiverWritability(gpa, res, ast, sel.receiver)
        else
            .{ .writable = false, .detail = null };
        const marker = needs_marker and writability.writable;
        const detail = writability.detail;

        // An unambiguous call is written out only where the client reads a
        // stop, or where writing it is the only way to put the marker in --
        // the label alone cannot, and an item nothing can accept correctly is
        // no offer at all.
        const writes = marker or ambiguous or snippets == .supported;

        const rewritten = if (writes and replaced != null)
            try writtenOut(gpa, ast, part, sel, replaced.?, qualifier, name, a.sig, snippets, marker)
        else
            null;

        try offered.append(gpa, .{
            .label = try gpa.dupe(u8, name),
            .labelDetails = .{ .description = try gpa.dupe(u8, through) },
            .kind = .Method,
            .detail = detail,
            .textEdit = if (rewritten) |w| .{ .text_edit = w.edit } else null,
            .insertTextFormat = if (rewritten) |w| formatOf(w.stops) else null,
        });
    }
}

/// A postfix call written out, and how many arguments a client tabs through.
const Rewritten = struct {
    edit: lsp.types.TextEdit,
    stops: u32,
};

/// The edit that replaces a postfix call with the call as it must be written,
/// or null where that call is written over more than one line.
///
/// `through` is the trait the qualified form names, and null where the dot
/// stays: the two differ in where the receiver goes and in nothing else, since
/// `a.of(1)` and `Measure.of(a, 1)` are one call and the receiver is the
/// argument in the first position either way.
///
/// The range it replaces is the caller's, computed once for the request: it
/// reads the selection and the cursor, which every item of the answer shares.
/// The arguments already written follow the receiver, which is the order the
/// form takes them in -- carried across by the tree's own renderer, so an
/// argument that names its parameter keeps that name and the call the reader
/// accepts is the call they wrote.
///
/// **What nobody has written becomes a stop.** The receiver is the parameter
/// in the first position and the arguments inside the brackets are the ones
/// after it, so what a reader has yet to fill in is the suffix of the
/// signature that begins where those run out.
///
/// What is written in place of a grouped receiver needs no group, because the
/// receiver becomes one argument of a call.
///
/// `marker` writes the `&` an `inout` receiver needs and the reader has not
/// written: before the receiver for the dot form, `&x.op(`, and before it as
/// the first argument for the qualified form, `Trait.op(&x, `. A written-out
/// call still lends the same place a postfix one would; only where the
/// marker goes differs, since a qualified call is not itself a postfix form
/// for `lentReceiver` to mark.
fn writtenOut(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    part: *const FilePart,
    sel: Selection,
    range: lsp.types.Range,
    through: ?[]const u8,
    name: []const u8,
    signature: DeclId,
    snippets: Snippets,
    marker: bool,
) !?Rewritten {
    const receiver = ast.exprSpan(sel.receiver).slice(part.source);
    const args = if (sel.call != ExprId.none) ast.call(sel.call).args else &.{};

    var written: std.ArrayList(u8) = .empty;
    defer written.deinit(gpa);

    // Where the receiver goes is the whole of the difference between the two
    // spellings: inside the brackets for the qualified form, before the dot
    // for the one that keeps it.
    if (through) |trait| {
        try written.print(gpa, "{s}.{s}({s}{s}", .{ trait, name, if (marker) "&" else "", receiver });
    } else {
        try written.print(gpa, "{s}{s}.{s}(", .{ if (marker) "&" else "", receiver, name });
    }

    // What is inside the brackets already, which decides the separators; and
    // what of the signature is accounted for, which is that plus the receiver.
    var inside: usize = if (through != null) 1 else 0;
    if (sel.call != ExprId.none) {
        try ast.appendWrittenArguments(gpa, &written, part.source, sel.call, inside > 0);
        inside += args.len;
    }

    const stops = if (snippets == .supported)
        try appendStops(gpa, ast, &written, signature, 1 + args.len, inside)
    else
        0;

    try written.append(gpa, ')');
    if (stops > 0) try written.appendSlice(gpa, "$0");

    return .{
        .edit = .{ .range = range, .newText = try written.toOwnedSlice(gpa) },
        .stops = stops,
    };
}

/// What this program holds that nothing here has imported, each item carrying
/// the import that would reach it.
///
/// Two shapes and one rule. A module inserts the name an import of it binds;
/// a name it exports inserts the qualified form, because [M-Vis] makes that
/// the only spelling that crosses a module boundary and an import binds the
/// module name and nothing else. Both carry the same edit, so accepting either
/// leaves text the compiler reads.
///
/// **A function here is written as a name and not as a call.** It has been
/// parsed and never checked -- this is a module the program does not include --
/// so what is known about it is the header the source wrote, and reading
/// parameter names back out of that header would be a second parse of a
/// declaration nobody resolved. It is the same split as the detail beside it.
///
/// A module whose name an import written here could not bind is left out --
/// the import this file already wrote, under the name it bound, and any other
/// declaration of that name -- because an offer nobody can accept is worse than
/// no offer. Which names those are is `takenFromAnImportIn`, the same answer the
/// quick fix and the offer beside a dot read: a file that could import a module
/// through one route and not another would be this module holding two rules.
///
/// Costs one pass over this program's modules in the index, one pass over the
/// names they export, and one pass over the module's own declarations. Every
/// one of those is a contiguous run the index or the tree already holds;
/// nothing walks the workspace.
fn appendImportable(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    file: FileId,
    offered: *std.ArrayList(Item),
    ws: Workspace,
    encoding: lsp.offsets.Encoding,
) !void {
    const ast = &program.ast;
    const part = ast.partOfFile(file) orelse return;
    const place = fix.placementIn(ast, part, part.source);

    const taken = try fix.takenFromAnImportIn(gpa, program, file);
    defer gpa.free(taken);

    // The import each module's names would be written under. Sized by this
    // program's modules and filled in one pass, so the pass over the names
    // below is a lookup each rather than a search of them.
    //
    // Released once the names have been read: an item owns copies of
    // everything it carries, so this is scratch by then.
    var reached: std.StringHashMapUnmanaged(fix.Import) = .empty;
    defer {
        var held = reached.valueIterator();
        while (held.next()) |w| release(gpa, w.*);
        reached.deinit(gpa);
    }

    for (ws.query.modulesIn(ws.program)) |m| {
        const writes = try fix.writingImport(gpa, ws.program, m.dir, part.source, place, encoding) orelse continue;
        if (fix.indexOfName(taken, writes.binds) != null) {
            release(gpa, writes);
            continue;
        }
        try reached.put(gpa, m.dir, writes);
        try offered.append(gpa, .{
            .label = try gpa.dupe(u8, writes.binds),
            .kind = .Module,
            .additionalTextEdits = try useEdits(gpa, writes),
        });
    }

    for (ws.query.offers(ws.program, "")) |e| {
        const writes = reached.get(e.module) orelse continue;
        try offered.append(gpa, .{
            .label = try gpa.dupe(u8, e.name),
            // Which module holds it, beside the label rather than inside it.
            // A client matches what was typed against the label alone, so a
            // label of `ledger.size` would mean finding `size` required
            // already knowing where it lives -- which is what offering the
            // module covers. The path an import writes rather than the name it
            // binds, because two modules of one program may share a leaf and
            // the path is what tells them apart.
            .labelDetails = .{ .description = try gpa.dupe(u8, writes.path) },
            .kind = exported(e.kind),
            // The header the file wrote, because nothing here has been checked:
            // this is a parse of a module the program does not include, so the
            // source's own words are the whole of what is known about it.
            .detail = try gpa.dupe(u8, e.header),
            // What accepting it writes, which is not what it is called.
            // [M-Vis] makes qualified access the one way a name crosses a
            // module boundary, so a bare `size` is text no import can make
            // work.
            .insertText = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ writes.binds, e.name }),
            .additionalTextEdits = try useEdits(gpa, writes),
        });
    }
}

/// Releases what working out one import cost.
fn release(gpa: std.mem.Allocator, writes: fix.Import) void {
    gpa.free(writes.path);
    gpa.free(writes.edit.newText);
    if (writes.imports) |imports| gpa.free(imports.newText);
}

/// A `use` and the import it needs, if any, as the list an item carries, the
/// import first. The texts are copied for the reason `oneEdit` copies.
fn useEdits(gpa: std.mem.Allocator, writes: fix.Import) ![]const lsp.types.TextEdit {
    const imports = writes.imports orelse return oneEdit(gpa, writes.edit);
    const edits = try gpa.alloc(lsp.types.TextEdit, 2);
    edits[0] = .{ .range = imports.range, .newText = try gpa.dupe(u8, imports.newText) };
    edits[1] = .{ .range = writes.edit.range, .newText = try gpa.dupe(u8, writes.edit.newText) };
    return edits;
}

/// One edit, as the list an item carries.
///
/// The text is copied for the reason a label is: an answer is serialised after
/// what it was read from has been released.
fn oneEdit(gpa: std.mem.Allocator, edit: lsp.types.TextEdit) ![]const lsp.types.TextEdit {
    const edits = try gpa.alloc(lsp.types.TextEdit, 1);
    edits[0] = .{ .range = edit.range, .newText = try gpa.dupe(u8, edit.newText) };
    return edits;
}

/// What a client is told a name the index holds stands for.
///
/// A translation of what the parser decided when the file was read, the way a
/// binding's kind is a translation of what the resolver decided. Exhaustive,
/// with no `else`: a declaration form added to the language is classified
/// before the build succeeds.
///
/// A re-export is a reference and says so. Which kind of thing it names takes
/// resolution to settle, and the index is built without one -- so a kind
/// guessed here would be this module deciding what a declaration in a module
/// nobody opened is.
fn exported(kind: exports.Kind) Item.Kind {
    return switch (kind) {
        .function => .Function,
        .constant => .Constant,
        .enum_ => .Enum,
        .struct_ => .Struct,
        .trait_ => .Interface,
        .re_export => .Reference,
        // A distinct nominal type over one base -- the protocol's `Struct` is
        // the nearest kind it has for a declared type with no members of its
        // own to offer.
        .newtype => .Struct,
        // Another name for a type written elsewhere, which is what the
        // protocol's type parameter is closest to: a name standing for a type.
        .alias => .TypeParameter,
    };
}

/// Releases a list, which owns the text of every item in it.
pub fn free(gpa: std.mem.Allocator, offered: []const Item) void {
    for (offered) |i| {
        gpa.free(i.label);
        if (i.labelDetails) |d| {
            if (d.description) |t| gpa.free(t);
        }
        if (i.detail) |d| gpa.free(d);
        if (i.insertText) |t| gpa.free(t);
        if (i.textEdit) |e| switch (e) {
            .text_edit => |t| gpa.free(t.newText),
            .insert_replace_edit => |t| gpa.free(t.newText),
        };
        if (i.additionalTextEdits) |edits| {
            for (edits) |e| gpa.free(e.newText);
            gpa.free(edits);
        }
    }
    gpa.free(offered);
}

/// The innermost scope the resolver recorded around a point.
///
/// Walking outward from whatever the tree covers the offset with, because the
/// node a cursor lands on in half-written text is usually one the resolver
/// recorded nothing for -- an argument list with no closing bracket, a name
/// that reaches nothing. Every expression the walk reached carries the scope it
/// was read in, and every statement carries the one it sits in, so the first
/// answer found on the way out is the nearest one.
///
/// A declaration carries none of its own, with one exception: a parameter's
/// default sits directly in the parameter list, wrapped in no statement and no
/// enclosing expression, so a cursor just past one -- where nothing is left
/// open but the declaration itself -- would otherwise fall all the way out to
/// the module. `declParamScope` answers for that position, and only for it: a
/// declaration is not a scope, and the rest of what it covers is written types
/// rather than a place a value's name can stand.
/// What is left when nothing answers at all is the module's own run, which is
/// what a point above the first declaration sees.
fn scopeAt(
    program: *const program_mod.Program,
    res: *const Resolution,
    cursors: *const positions.Index,
    file: FileId,
    offset: u32,
) ScopeId {
    var chain = cursors.enclosing(&program.ast, file, offset);
    while (chain.next()) |n| {
        const sc = switch (n) {
            .expr => |e| res.scopeOfExpr(e),
            .stmt => |s| res.scopeOfStmt(s),
            .decl => |d| declParamScope(&program.ast, res, d, offset),
        };
        if (sc != .none) return sc;
    }
    return res.moduleScope(res.moduleOfFile(file));
}

/// The scope a declaration's own parameters were bound into, where the point
/// asked about is one they can be written at, and `.none` everywhere else in
/// the declaration.
///
/// Two questions, and they take different answers. **Whether** a declaration
/// answers is decided by the point: a default is the only thing in a parameter
/// list that names values, so the parameters are in scope inside one and
/// nowhere else the declaration reaches. A return type and a parameter's
/// written type name types, and a parameter offered there is a name that
/// cannot stand where it would be written.
///
/// **What** it answers is read off whichever default the resolver visited,
/// which need not be the one the point is in -- there is nothing else on a
/// declaration that scope was ever recorded against, and every default a
/// declaration writes was resolved in the one scope its parameters share. So a
/// point inside a default the resolver could not read is still answered by the
/// scope beside it, which is what a cursor in half-written text needs.
///
/// The extent runs to the last byte of the default and includes it: a cursor
/// just past a written name is a cursor completing that name.
fn declParamScope(ast: *const Ast, res: *const Resolution, d: DeclId, offset: u32) ScopeId {
    var within = false;
    var scope: ScopeId = .none;
    for (ast.declParams(d)) |p| {
        if (p.default == ExprId.none) continue;
        const at = ast.exprSpan(p.default);
        if (offset >= at.start and offset <= at.end) within = true;
        if (scope == .none) scope = res.scopeOfExpr(p.default);
    }
    return if (within) scope else .none;
}

/// One item: the text that would be written, what kind of thing it names, and
/// what the checker settled about it.
///
/// **A function is written as the call it takes**, with a stop per argument,
/// where the client reads one. What it is called and what accepting it writes
/// are two answers here for the same reason they are two beside an unimported
/// name: a client matches what was typed against the label, and the label is
/// the name.
///
/// Every string is copied, because an answer is serialised after the analysis
/// it was read from has been released: a label borrowed from the tree is a
/// label nobody owns by the time it is written out.
fn itemFor(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    typing: *const Typing,
    snippets: Snippets,
    written: []const u8,
    b: BindingId,
) !Item {
    const detail = detailOf(res, typing, b);
    const call = if (snippets == .supported)
        try callWritten(gpa, ast, written, res.declIfDeclared(b))
    else
        null;

    return .{
        .label = try gpa.dupe(u8, written),
        .kind = kindOf(res.kindOf(b)),
        .detail = if (detail) |d| try gpa.dupe(u8, d) else null,
        .insertText = if (call) |c| c.text else null,
        .insertTextFormat = if (call) |c| formatOf(c.stops) else null,
    };
}

/// The text a binding answers to.
///
/// The token the resolver recorded as declaring it, except for a primitive:
/// nothing in source declares one, so its name is the type's own spelling --
/// which is what put it in every module's scope in the first place.
pub fn nameOf(ast: *const Ast, res: *const Resolution, b: BindingId) ?[]const u8 {
    if (res.builtinOf(b)) |t| return t.nameOf();
    const at = res.declaringToken(b);
    if (at == TokenId.none) return null;
    return ast.tokenText(at);
}

/// The type the checker settled for a name, or null where the label already
/// says everything there is.
///
/// **Detail says what the label does not.** A value's name does not say its
/// type, so a local, a parameter, a binder and a constant carry the one the
/// checker settled. A type's name *is* the type -- what the checker settled for
/// `UInt8` is `UInt8` -- so showing it writes the label twice and says nothing.
/// A function, a trait and a module carry nothing either, and for a second
/// reason: no value has any of them for its type, so what one is worth is a
/// question the checker was never asked, and a signature rendered here would be
/// this module having an opinion the compiler does not.
///
/// A name the index holds is the other half of the same rule and is answered
/// where it is built: it has been parsed and not checked, so its detail is the
/// header the source wrote. A module has neither, because nothing declares one.
///
/// Exhaustive, with no `else`, so a kind of name added to the language says
/// what it shows before the build succeeds.
fn detailOf(res: *const Resolution, typing: *const Typing, b: BindingId) ?[]const u8 {
    return switch (res.kindOf(b)) {
        .local, .parameter, .capture, .binder, .constant => typing.settledName(typing.bindingType(b)),
        // An alias's name is not the type it names, so the detail says which.
        .type_alias => typing.settledName(typing.aliasedType(res.declaredBy(b))),
        .declared_type, .builtin_type, .function, .trait, .module, .associated_type, .type_parameter => null,
    };
}

/// What a client is told a name stands for.
///
/// A translation between two vocabularies and nothing else, from what the
/// resolver decided the name refers to. The resolver has one kind for a
/// declared type whichever form declared it, so the icon follows what the name
/// refers to rather than how it was written -- a second reading of the
/// declaration here would be a classification that could disagree with the one
/// every other answer about that name is built on.
///
/// Exhaustive, with no `else`: a kind of name added to the language is
/// classified before the build succeeds.
fn kindOf(kind: resolve.Kind) Item.Kind {
    return switch (kind) {
        .local, .parameter, .capture, .binder => .Variable,
        .constant => .Constant,
        .function => .Function,
        .declared_type, .builtin_type => .Struct,
        // A name standing for a type an implementation settles, which is what
        // the protocol's type parameter is.
        .associated_type, .type_parameter, .type_alias => .TypeParameter,
        .trait => .Interface,
        .module => .Module,
    };
}

/// Whether the `import` that bound a module name was written in this file.
///
/// An import binds a module inside the file that wrote it and nowhere else, or
/// else which names a file has would depend on what its neighbours happened to
/// import. The binding sits in the module's scope all the same, so this is what
/// keeps a sibling's import from being offered here.
fn importedIn(ast: *const Ast, res: *const Resolution, b: BindingId, file: FileId) bool {
    const d = res.importOf(b);
    if (d == DeclId.none) return false;
    return ast.fileOfDecl(d) == file;
}

const scope_program =
    \\fn add(a: UInt8, b: UInt8) -> UInt8 {
    \\    a + b
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let total: UInt8 = add(1, 2)
    \\    total
    \\}
    \\
;

test "an alias is offered with the type it names" {
    const gpa = testing.allocator;
    const text =
        \\alias Meters = UInt64
        \\
        \\fn main() -> UInt8 {
        \\    let distance: Meters = 4
        \\    UInt8(distance)
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const items = try offeredIn(gpa, &checked, checked.fileNamed("main.lin").?, std.mem.indexOf(u8, text, "    UInt8(").? + 4);
    defer free(gpa, items);
    const meters = try requireItem(items, "Meters");
    try testing.expectEqual(Item.Kind.TypeParameter, meters.kind.?);
    try testing.expectEqualStrings("UInt64", meters.detail.?);
}

/// What one point of a checked module is offered, with no workspace to read.
fn offeredIn(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    offset: usize,
) ![]const Item {
    return offeredReading(gpa, checked, file, offset, .unsupported);
}

/// The same, for a client that reads a stop.
fn offeredReading(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    offset: usize,
    snippets: Snippets,
) ![]const Item {
    return atOffset(
        gpa,
        &checked.program,
        &checked.semantics.res,
        &checked.semantics.typing,
        &checked.cursors,
        file,
        @intCast(offset),
        .@"utf-16",
        null,
        snippets,
    );
}

/// The labels offered at an offset in a one-file program, in the order sent.
fn offeredAt(gpa: std.mem.Allocator, text: []const u8, offset: usize) ![]const []const u8 {
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const items = try offeredIn(gpa, &checked, checked.fileNamed("main.lin").?, offset);
    defer free(gpa, items);

    const out = try gpa.alloc([]const u8, items.len);
    errdefer gpa.free(out);
    for (out, items) |*o, i| o.* = try gpa.dupe(u8, i.label);
    return out;
}

fn releaseAll(gpa: std.mem.Allocator, labels: []const []const u8) void {
    for (labels) |l| gpa.free(l);
    gpa.free(labels);
}

fn holds(labels: []const []const u8, wanted: []const u8) bool {
    for (labels) |l| {
        if (std.mem.eql(u8, l, wanted)) return true;
    }
    return false;
}

fn requireItem(items: []const Item, wanted: []const u8) !Item {
    for (items) |item| {
        if (std.mem.eql(u8, item.label, wanted)) return item;
    }
    return error.TestExpectedCompletion;
}

fn howMany(labels: []const []const u8, wanted: []const u8) usize {
    var n: usize = 0;
    for (labels) |l| {
        if (std.mem.eql(u8, l, wanted)) n += 1;
    }
    return n;
}

test "a point in a body is offered what the chain makes visible there" {
    const gpa = testing.allocator;

    // Just past `a`, which is where a cursor sits when a name is half typed.
    const inside_add = std.mem.indexOf(u8, scope_program, "a + b").? + 1;
    const in_add = try offeredAt(gpa, scope_program, inside_add);
    defer releaseAll(gpa, in_add);

    // Its own parameters, the module's declarations, and a primitive.
    try testing.expect(holds(in_add, "a"));
    try testing.expect(holds(in_add, "b"));
    try testing.expect(holds(in_add, "add"));
    try testing.expect(holds(in_add, "main"));
    try testing.expect(holds(in_add, "UInt8"));

    // And not another function's parameters, which is what the chain says.
    const inside_main = std.mem.indexOf(u8, scope_program, "    total\n").? + 5;
    const in_main = try offeredAt(gpa, scope_program, inside_main);
    defer releaseAll(gpa, in_main);

    try testing.expect(holds(in_main, "total"));
    try testing.expect(!holds(in_main, "a"));
    try testing.expect(!holds(in_main, "b"));
}

test "a point after a lambda body name remains in the lambda scope" {
    const gpa = testing.allocator;
    const text =
        \\fn main() -> UInt8 {
        \\    let f = |item: UInt8| item
        \\    f(1)
        \\}
    ;
    const after_item = std.mem.indexOf(u8, text, "| item").? + "| item".len;
    const labels = try offeredAt(gpa, text, after_item);
    defer releaseAll(gpa, labels);

    try testing.expect(holds(labels, "item"));
}

test "a parameter is offered after a default but not after the parameter list" {
    const gpa = testing.allocator;
    const text =
        \\fn choose(first: UInt8, second: UInt8 = first) -> UInt8 {
        \\    second
        \\}
        \\fn main() -> UInt8 { choose(1) }
    ;
    const after_default = std.mem.indexOf(u8, text, "= first").? + "= first".len;
    const in_default = try offeredAt(gpa, text, after_default);
    defer releaseAll(gpa, in_default);
    try testing.expect(holds(in_default, "first"));
    try testing.expect(holds(in_default, "second"));

    const in_return_type = std.mem.indexOf(u8, text, ") -> UInt8").? + ") -> ".len;
    const after_params = try offeredAt(gpa, text, in_return_type);
    defer releaseAll(gpa, after_params);
    try testing.expect(!holds(after_params, "first"));
    try testing.expect(!holds(after_params, "second"));
}

test "a completion item carries its type and the call the client can read" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = scope_program },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const at = std.mem.indexOf(u8, scope_program, "    total\n").? + 5;
    for ([_]Snippets{ .supported, .unsupported }) |snippets| {
        const items = try offeredReading(gpa, &checked, checked.fileNamed("main.lin").?, at, snippets);
        defer free(gpa, items);

        const total = try requireItem(items, "total");
        try testing.expectEqual(Item.Kind.Variable, total.kind.?);
        try testing.expectEqualStrings("UInt8", total.detail.?);

        // A function has no value type to report, so it says nothing about
        // its type rather than saying unit.
        const add = try requireItem(items, "add");
        try testing.expectEqual(Item.Kind.Function, add.kind.?);
        try testing.expect(add.detail == null);
        const main = try requireItem(items, "main");
        const number = try requireItem(items, "UInt8");
        try testing.expect(number.insertText == null);

        if (snippets == .supported) {
            // The declared names, in the order the arguments go in, and a last
            // stop after the bracket.
            try testing.expectEqualStrings("add(${1:a}, ${2:b})$0", add.insertText.?);
            try testing.expectEqual(lsp.types.InsertTextFormat.Snippet, add.insertTextFormat.?);
            // An empty call has no stop and carries no snippet syntax.
            try testing.expectEqualStrings("main()", main.insertText.?);
            try testing.expect(main.insertTextFormat == null);
        } else {
            // A client that reads no stops writes the name alone.
            for (items) |item| try testing.expect(item.insertText == null);
        }
    }
}

test "structural reflection completion follows its lexical context" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\trait Structural { fn inspect(self: Self, other: Self) -> UInt64 }
        \\template impl Structural {
        \\    fn inspect(self: Self, other: Self) -> UInt64 {
        \\        let before = reflect.ordinal_of(self)
        \\        match read self {
        \\            reflect.case => match read other {
        \\                reflect.same_case => {
        \\                    let case = reflect.case.ordinal
        \\                    for component in reflect.components {
        \\                        let part = component.ordinal
        \\                    }
        \\                    before + case
        \\                },
        \\                reflect.other_case => before,
        \\            },
        \\        }
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
        \\
    ;

    const ordinary = std.mem.indexOf(u8, text, "reflect.ordinal_of").? + "reflect.".len;
    const ordinary_labels = try offeredAt(gpa, text, ordinary);
    defer releaseAll(gpa, ordinary_labels);
    try testing.expect(holds(ordinary_labels, "case"));
    try testing.expect(holds(ordinary_labels, "ordinal_of"));
    try testing.expect(!holds(ordinary_labels, "components"));

    const same = std.mem.indexOf(u8, text, "reflect.same_case").? + "reflect.".len;
    const same_labels = try offeredAt(gpa, text, same);
    defer releaseAll(gpa, same_labels);
    try testing.expect(holds(same_labels, "same_case"));
    try testing.expect(holds(same_labels, "other_case"));
    try testing.expect(holds(same_labels, "components"));
    try testing.expect(!holds(same_labels, "ordinal_of"));

    const case_metadata = std.mem.indexOf(u8, text, "reflect.case.ordinal").? + "reflect.case.".len;
    const case_labels = try offeredAt(gpa, text, case_metadata);
    defer releaseAll(gpa, case_labels);
    try testing.expect(holds(case_labels, "name"));
    try testing.expect(holds(case_labels, "ordinal"));
    try testing.expect(holds(case_labels, "components_named"));

    const component_metadata = std.mem.indexOf(u8, text, "component.ordinal").? + "component.".len;
    const component_labels = try offeredAt(gpa, text, component_metadata);
    defer releaseAll(gpa, component_labels);
    try testing.expect(holds(component_labels, "name"));
    try testing.expect(holds(component_labels, "ordinal"));
    try testing.expect(holds(component_labels, "of"));
}

test "construction completion distinguishes recipes from observed components" {
    const gpa = testing.allocator;
    const text =
        \\trait Make { fn make() -> Self }
        \\template impl Make where reflect.target: struct {
        \\    fn make() -> Self {
        \\        reflect.construct(reflect.product, |component| {
        \\            let ordinal = component.ordinal
        \\            let value = ordinal
        \\            value
        \\        }, {})
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    ;
    const operation = std.mem.indexOf(u8, text, "reflect.construct").? + "reflect.".len;
    const operations = try offeredAt(gpa, text, operation);
    defer releaseAll(gpa, operations);
    try testing.expect(holds(operations, "construct"));
    try testing.expect(holds(operations, "product"));

    const metadata = std.mem.indexOf(u8, text, "component.ordinal").? + "component.".len;
    const fields = try offeredAt(gpa, text, metadata);
    defer releaseAll(gpa, fields);
    try testing.expect(holds(fields, "name"));
    try testing.expect(holds(fields, "ordinal"));
    try testing.expect(!holds(fields, "of"));
}

test "construction descriptor completion offers its written component type" {
    const gpa = testing.allocator;
    for ([_][]const u8{ "component.Type", "component.", "(component).Type", "(component).", "Option[component.Type]" }) |annotation| {
        const text = try std.fmt.allocPrint(gpa,
            \\trait Zero {{ fn zero() -> Self }}
            \\template impl Zero where reflect.target: struct, reflect.components: Zero {{
            \\    fn zero() -> Self {{
            \\        reflect.construct(reflect.product, |component| {{
            \\            let value: {s} = Zero.zero()
            \\            value
            \\        }}, {{}})
            \\    }}
            \\}}
            \\fn main() -> UInt8 {{ 0 }}
        , .{annotation});
        defer gpa.free(text);
        const offset = std.mem.indexOf(u8, text, annotation).? + std.mem.indexOf(u8, annotation, ".").? + 1;
        const fields = try offeredAt(gpa, text, offset);
        defer releaseAll(gpa, fields);
        try testing.expect(holds(fields, "Type"));
        try testing.expectEqual(@as(usize, 1), fields.len);
    }
}

test "construction descriptor completion respects local shadowing" {
    const gpa = testing.allocator;
    const text =
        \\trait Zero { fn zero() -> Self }
        \\template impl Zero where reflect.target: struct, reflect.components: Zero {
        \\    fn zero() -> Self {
        \\        reflect.construct(reflect.product, |component| {
        \\            let ordinal = component.ordinal
        \\            let component = ordinal
        \\            let value: component.Type = Zero.zero()
        \\            value
        \\        }, {})
        \\    }
        \\}
        \\fn main() -> UInt8 { 0 }
    ;
    const offset = std.mem.indexOf(u8, text, "component.Type").? + "component.".len;
    const fields = try offeredAt(gpa, text, offset);
    defer releaseAll(gpa, fields);
    try testing.expect(!holds(fields, "Type"));
}

test "an operation after a dot is written over the call the reader started" {
    const gpa = testing.allocator;

    const text =
        \\trait Measure {
        \\    fn of(self: Self, fee: UInt8) -> UInt8
        \\}
        \\
        \\struct Coins {
        \\    n: UInt8,
        \\}
        \\
        \\impl Measure for Coins {
        \\    fn of(self: Self, fee: UInt8) -> UInt8 {
        \\        self.n + fee
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let coppers: Coins = .{ n = 3 }
        \\    coppers.of()
        \\}
        \\
    ;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const at = std.mem.indexOf(u8, text, "coppers.of()").? + "coppers.".len;
    const items = try offeredReading(gpa, &checked, checked.fileNamed("main.lin").?, at, .supported);
    defer free(gpa, items);

    const item = try requireItem(items, "of");
    // The dot stays, because one trait declares it. The receiver is the
    // argument in the first position and is already written, so what is
    // left to fill in is the one after it -- and the brackets the reader
    // typed are replaced rather than left standing beside a second pair.
    try testing.expectEqualStrings(
        "coppers.of(${1:fee})$0",
        item.textEdit.?.text_edit.newText,
    );
    try testing.expectEqual(lsp.types.InsertTextFormat.Snippet, item.insertTextFormat.?);
}

const counter_program =
    \\struct Counter { n: UInt8 }
    \\
    \\impl Counter {
    \\    fn increment(inout self: Self) -> () {
    \\        self.n += 1
    \\    }
    \\    fn value(self: Self) -> UInt8 {
    \\        self.n
    \\    }
    \\}
    \\
;

test "a marked dot offers only the operations that lend the receiver" {
    const gpa = testing.allocator;
    const text = counter_program ++
        \\fn main() -> UInt8 {
        \\    var counter: Counter = .{ n = 0 }
        \\    &counter.increment()
        \\}
        \\
    ;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const at = std.mem.indexOf(u8, text, "&counter.increment()").? + "&counter.".len;
    const items = try offeredReading(gpa, &checked, checked.fileNamed("main.lin").?, at, .supported);
    defer free(gpa, items);

    _ = try requireItem(items, "increment");
    for (items) |item| try testing.expect(!std.mem.eql(u8, item.label, "value"));
}

test "an operation that mutates its receiver is written with the marker" {
    const gpa = testing.allocator;
    const text = counter_program ++
        \\fn main() -> UInt8 {
        \\    var counter: Counter = .{ n = 0 }
        \\    counter.value()
        \\}
        \\
    ;
    const at = std.mem.indexOf(u8, text, "counter.value()").? + "counter.".len;

    // A client that reads a stop, and one that writes text back verbatim: the
    // marker is written either way, since the label alone can never carry it.
    for ([_]Snippets{ .supported, .unsupported }) |snippets| {
        var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
        defer checked.deinit();

        const items = try offeredReading(gpa, &checked, checked.fileNamed("main.lin").?, at, snippets);
        defer free(gpa, items);

        const mutates = try requireItem(items, "increment");
        try testing.expectEqualStrings("&counter.increment()", mutates.textEdit.?.text_edit.newText);
        try testing.expect(mutates.detail == null);

        const reads = try requireItem(items, "value");
        if (reads.textEdit) |edit| try testing.expect(!std.mem.startsWith(u8, edit.text_edit.newText, "&"));
    }
}

test "a read-only receiver offers a mutating operation with a note instead of the marker" {
    const gpa = testing.allocator;
    const text = counter_program ++
        \\fn main() -> UInt8 {
        \\    let counter: Counter = .{ n = 0 }
        \\    counter.value()
        \\}
        \\
    ;

    const at = std.mem.indexOf(u8, text, "counter.value()").? + "counter.".len;

    for ([_]Snippets{ .supported, .unsupported }) |snippets| {
        var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
        defer checked.deinit();

        const items = try offeredReading(gpa, &checked, checked.fileNamed("main.lin").?, at, snippets);
        defer free(gpa, items);

        const mutates = try requireItem(items, "increment");
        // Whatever the client reads, no edit here writes `&` before a `let`.
        if (mutates.textEdit) |edit| try testing.expect(!std.mem.startsWith(u8, edit.text_edit.newText, "&"));
        try testing.expectEqualStrings(
            "mutates its receiver; `counter` is declared with `let`",
            mutates.detail.?,
        );
    }
}

test "a field reached through a read-only parameter offers a mutating operation with a note" {
    const gpa = testing.allocator;
    const text = counter_program ++
        \\struct Holder { counter: Counter }
        \\
        \\impl Holder {
        \\    fn tryIt(self: Self) -> UInt8 {
        \\        self.counter.value()
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let holder: Holder = .{ counter = .{ n = 0 } }
        \\    holder.tryIt()
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const at = std.mem.indexOf(u8, text, "self.counter.value()").? + "self.counter.".len;
    const items = try offeredReading(gpa, &checked, checked.fileNamed("main.lin").?, at, .supported);
    defer free(gpa, items);

    // `self` here has no explicit convention, which is `read`: a field
    // reached through it is a place, but not one this offer may mark.
    const mutates = try requireItem(items, "increment");
    if (mutates.textEdit) |edit| try testing.expect(!std.mem.startsWith(u8, edit.text_edit.newText, "&"));
    try testing.expectEqualStrings(
        "mutates its receiver; `self` is a read-only parameter",
        mutates.detail.?,
    );
}

test "a call's result offers a mutating operation with a note, never a marker" {
    const gpa = testing.allocator;
    const text = counter_program ++
        \\fn made() -> Counter { .{ n = 0 } }
        \\
        \\fn main() -> UInt8 {
        \\    made().value()
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const at = std.mem.indexOf(u8, text, "made().value()").? + "made().".len;
    const items = try offeredReading(gpa, &checked, checked.fileNamed("main.lin").?, at, .supported);
    defer free(gpa, items);

    // `made()` is a value, not a place at all -- there is nothing here to
    // bind a `var` and mark, so the note says that instead.
    const mutates = try requireItem(items, "increment");
    if (mutates.textEdit) |edit| try testing.expect(!std.mem.startsWith(u8, edit.text_edit.newText, "&"));
    try testing.expectEqualStrings(
        "mutates its receiver, and a value that is not a place cannot be lent",
        mutates.detail.?,
    );
}

test "a marker on a chain lends only the receiver at its head" {
    const gpa = testing.allocator;
    const text =
        \\struct Counter { n: UInt8 }
        \\
        \\impl Counter {
        \\    fn increment(inout self: Self) -> Counter {
        \\        self.n += 1
        \\        .{ n = self.n }
        \\    }
        \\    fn value(self: Self) -> UInt8 {
        \\        self.n
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    var counter: Counter = .{ n = 0 }
        \\    &counter.increment().value()
        \\}
        \\
    ;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const at = std.mem.indexOf(u8, text, ".value()").? + ".".len;
    const items = try offeredReading(gpa, &checked, checked.fileNamed("main.lin").?, at, .supported);
    defer free(gpa, items);

    // The marker lent `increment`'s own receiver; the value it returned is a
    // fresh place with nothing lent to it, so both operations are offered
    // here exactly as they would be after an unmarked dot.
    const value = try requireItem(items, "value");
    try testing.expect(value.detail == null);
    try testing.expectEqualStrings("&counter.increment().value()", value.textEdit.?.text_edit.newText);

    // `increment` reads here too, its receiver now the call this chain's own
    // marker already reached -- not a place a second `&` could lend, so this
    // is offered with a note rather than a rewrite carrying a second marker.
    // A written call still keeps the one marker the source already wrote:
    // the receiver's own text is copied forward, `&&` is never written.
    const increment = try requireItem(items, "increment");
    try testing.expectEqualStrings(
        "mutates its receiver, and a value that is not a place cannot be lent",
        increment.detail.?,
    );
    const rewritten = increment.textEdit.?.text_edit.newText;
    try testing.expectEqualStrings("&counter.increment().increment()", rewritten);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, rewritten, "&"));
}

test "completion releases only initialized trait use edits on allocation failure" {
    const gpa = testing.allocator;
    const text =
        \\import operations
        \\fn main() -> UInt8 {
        \\    let counter: operations.Counter = .{}
        \\    counter.first()
        \\}
    ;
    const operations =
        \\pub struct Counter {}
        \\pub trait Readings {
        \\    fn first(self: Self) -> UInt8
        \\    fn second(self: Self) -> UInt8
        \\}
        \\impl Readings for Counter {
        \\    fn first(_self: Self) -> UInt8 { 1 }
        \\    fn second(_self: Self) -> UInt8 { 2 }
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = text },
        .{ .path = "operations/main.lin", .text = operations },
    }, "main.lin");
    defer checked.deinit();
    const offset = std.mem.indexOf(u8, text, "counter.first").? + "counter.".len;
    const selected = selectionAt(&checked.program, &checked.cursors, checked.fileNamed("main.lin").?, @intCast(offset)).?;
    const held = checked.semantics.typing.exprType(selected.receiver);
    // Nothing in scope declares `first` or `second`, so each item is judged
    // against an empty table of what the dot already reaches.
    const declaring: std.StringHashMapUnmanaged(typecheck.NameReach) = .empty;

    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        // One request owns all its result strings in an arena, including a
        // partially built result when an allocation fails.
        var message = std.heap.ArenaAllocator.init(gpa);
        defer message.deinit();
        var failing = testing.FailingAllocator.init(message.allocator(), .{ .fail_index = fail_index });
        var items: std.ArrayList(Item) = .empty;
        appendOperationsElsewhere(
            failing.allocator(),
            &checked.program,
            &checked.semantics.res,
            &checked.semantics.typing,
            checked.fileNamed("main.lin").?,
            checked.cursors.declarationAt(&checked.program.ast, checked.fileNamed("main.lin").?, @intCast(offset)),
            @intCast(offset),
            .@"utf-16",
            selected,
            held,
            &items,
            .unsupported,
            &declaring,
        ) catch |err| {
            if (err != error.OutOfMemory) return err;
            try testing.expect(failing.has_induced_failure);
            continue;
        };
        try testing.expect(!failing.has_induced_failure);
        for ([_][]const u8{ "first", "second" }) |name| {
            const item = try requireItem(items.items, name);
            try testing.expectEqualStrings("\nuse operations.Readings\n", item.additionalTextEdits.?[0].newText);
        }
        break;
    }
}

test "a dependent callable implementation is offered from finished typing" {
    const gpa = testing.allocator;
    const text =
        \\trait Source {
        \\    type Item
        \\    fn take(sink self: Self) -> Self.Item
        \\}
        \\
        \\struct Counter {
        \\    value: UInt8,
        \\}
        \\
        \\impl Source for Counter {
        \\    type Item = UInt8
        \\
        \\    fn take(sink self: Counter) -> UInt8 {
        \\        let Counter { value } = self
        \\        value
        \\    }
        \\}
        \\
        \\struct Adapter[I, F] {
        \\    source: I,
        \\    transform: F,
        \\}
        \\
        \\fn adapt[
        \\    I: Source,
        \\    F: fn(sink item: I.Item) -> I.Item + Discardable,
        \\](sink source: I, sink transform: F) -> Adapter[I, F] where carries(source, transform) {
        \\    .{ source = source, transform = transform }
        \\}
        \\
        \\trait Apply {
        \\    type Output
        \\    fn apply(sink self: Self) -> Self.Output
        \\}
        \\
        \\impl[
        \\    I: Source,
        \\    F: fn(sink item: I.Item) -> I.Item + Discardable,
        \\] Apply for Adapter[I, F] {
        \\    type Output = I.Item
        \\
        \\    fn apply(sink self: Adapter[I, F]) -> I.Item {
        \\        let Adapter { source, transform } = self
        \\        transform(Source.take(source))
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let counter: Counter = .{ value = 4 }
        \\    let adapter = adapt(counter, |sink item| item * 2)
        \\    adapter.apply()
        \\}
        \\
    ;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const at = std.mem.indexOf(u8, text, "adapter.apply()").? + "adapter.".len;
    const items = try offeredIn(gpa, &checked, checked.fileNamed("main.lin").?, at);
    defer free(gpa, items);
    var found = false;
    for (items) |item| if (std.mem.eql(u8, item.label, "apply")) {
        found = true;
    };
    try testing.expect(found);
}

test "completion uses scoped capabilities through phantom type arguments" {
    const gpa = testing.allocator;
    const text =
        \\trait Source { type Item }
        \\@copyable
        \\struct Box[T] { value: T }
        \\struct Marker[phantom T] {}
        \\impl[T] Marker[T] {
        \\    fn base(_self: Self) -> UInt8 { 0 }
        \\}
        \\trait Inspect { fn inspect(self: Self) -> UInt8 }
        \\impl[T: Copyable] Inspect for Marker[T] {
        \\    fn inspect(_self: Self) -> UInt8 { 1 }
        \\}
        \\fn _bounded[S: Source](bounded: Marker[Box[S.Item]]) -> UInt8 where S.Item: Copyable {
        \\    bounded.base()
        \\}
        \\fn _unbounded[S: Source](unbounded: Marker[Box[S.Item]]) -> UInt8 {
        \\    unbounded.base()
        \\}
        \\fn main() -> UInt8 { 0 }
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    if (checked.sink.hasErrors()) for (checked.sink.items()) |diagnostic|
        std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code.?), diagnostic.message });
    try testing.expect(!checked.sink.hasErrors());

    const cases = .{
        .{ "bounded.base()", true },
        .{ "unbounded.base()", false },
    };
    inline for (cases) |case| {
        const at = std.mem.indexOf(u8, text, case[0]).? + std.mem.indexOfScalar(u8, case[0], '.').? + 1;
        const items = try offeredIn(gpa, &checked, checked.fileNamed("main.lin").?, at);
        defer free(gpa, items);
        var found = false;
        for (items) |item| if (std.mem.eql(u8, item.label, "inspect")) {
            found = true;
        };
        try testing.expectEqual(case[1], found);
    }
}

test "completion evaluates constructed capability predicates absent from source values" {
    const gpa = testing.allocator;
    const text =
        \\trait Source { type Item }
        \\@copyable
        \\struct Box[T] { value: T }
        \\struct Marker[phantom T] {}
        \\impl[T] Marker[T] {
        \\    fn base(_self: Self) -> UInt8 { 0 }
        \\}
        \\trait Inspect { fn inspect(self: Self) -> UInt8 }
        \\impl[T] Inspect for Marker[T] where Box[T]: Copyable {
        \\    fn inspect(_self: Self) -> UInt8 { 1 }
        \\}
        \\fn _bounded[S: Source](bounded: Marker[S.Item]) -> UInt8 where S.Item: Copyable {
        \\    bounded.base()
        \\}
        \\fn _unbounded[S: Source](unbounded: Marker[S.Item]) -> UInt8 {
        \\    unbounded.base()
        \\}
        \\fn main() -> UInt8 { 0 }
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    if (checked.sink.hasErrors()) for (checked.sink.items()) |diagnostic|
        std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code.?), diagnostic.message });
    try testing.expect(!checked.sink.hasErrors());

    const cases = .{
        .{ "bounded.base()", true },
        .{ "unbounded.base()", false },
    };
    inline for (cases) |case| {
        const at = std.mem.indexOf(u8, text, case[0]).? + std.mem.indexOfScalar(u8, case[0], '.').? + 1;
        const items = try offeredIn(gpa, &checked, checked.fileNamed("main.lin").?, at);
        defer free(gpa, items);
        var found = false;
        for (items) |item| if (std.mem.eql(u8, item.label, "inspect")) {
            found = true;
        };
        try testing.expectEqual(case[1], found);
    }
}

test "a call the parser never closed is answered from the body around it" {
    const gpa = testing.allocator;

    const text =
        \\fn add(a: UInt8, b: UInt8) -> UInt8 {
        \\    a + b
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let n: UInt8 = 1
        \\    let total = add(
        \\    total
        \\}
        \\
    ;

    // Immediately after the bracket, where the text stops being a call.
    const at = std.mem.indexOf(u8, text, "add(\n").? + 4;
    const offered = try offeredAt(gpa, text, at);
    defer releaseAll(gpa, offered);

    try testing.expect(holds(offered, "n"));
    try testing.expect(holds(offered, "add"));
    try testing.expect(holds(offered, "UInt8"));
}

/// A type name, an enum name and a trait name, each with a dot written on it.
///
/// What follows a dot on one of these is not what follows a dot on a value:
/// the name opens a namespace rather than standing for something that holds
/// fields, so what may be written is what the namespace declares.
const namespace_program =
    \\enum Colour {
    \\    Red,
    \\    Green,
    \\}
    \\
    \\trait Measure {
    \\    fn weight(self: Self) -> UInt8
    \\}
    \\
    \\struct Pair {
    \\    a: UInt8,
    \\}
    \\
    \\impl Pair {
    \\    pub fn made(n: UInt8) -> Pair {
    \\        .{ a = n }
    \\    }
    \\}
    \\
    \\impl Measure for Pair {
    \\    fn weight(self: Self) -> UInt8 {
    \\        self.a
    \\    }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let _held: Colour = Colour.Red
    \\    let p: Pair = Pair.made(1)
    \\    Measure.weight(p)
    \\}
    \\
;

/// The labels offered just after the dot written in `written`.
fn offeredAfter(gpa: std.mem.Allocator, text: []const u8, written: []const u8) ![]const []const u8 {
    const dot = std.mem.indexOf(u8, written, ".").? + 1;
    return offeredAt(gpa, text, std.mem.indexOf(u8, text, written).? + dot);
}

test "transparent observation completion offers real referent fields" {
    const gpa = testing.allocator;
    const source =
        \\struct Number { amount: UInt8, value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let number: Number = .{ amount = 7, value = 2 }
        \\    let view = borrow number
        \\    view.amount + view.value
        \\}
    ;
    const members = try offeredAfter(gpa, source, "view.amount");
    defer releaseAll(gpa, members);
    try testing.expect(holds(members, "value"));
    try testing.expect(holds(members, "amount"));

    const scalar =
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 7
        \\    let view = borrow number
        \\    view.missing
        \\}
    ;
    const scalar_members = try offeredAfter(gpa, scalar, "view.missing");
    defer releaseAll(gpa, scalar_members);
    try testing.expect(!holds(scalar_members, "value"));
}

test "transparent observation completion offers readonly mixed trait operations" {
    const gpa = testing.allocator;
    const source =
        \\trait Counter {
        \\    fn count(self: Self) -> UInt8
        \\    fn advance(inout self: Self) -> ()
        \\}
        \\struct State { number: UInt8 }
        \\impl Counter for State {
        \\    fn count(self: Self) -> UInt8 { self.number }
        \\    fn advance(inout self: Self) -> () { self.number += 1 }
        \\}
        \\fn main() -> UInt8 {
        \\    let state: State = .{ number = 7 }
        \\    let view = borrow state
        \\    view.count()
        \\}
    ;
    const members = try offeredAfter(gpa, source, "view.count");
    defer releaseAll(gpa, members);
    try testing.expect(holds(members, "count"));
    try testing.expect(!holds(members, "advance"));
}

test "a dot on a value offers an operation beside a field of its name" {
    const gpa = testing.allocator;
    const text =
        \\struct Door { width: UInt8 }
        \\impl Door {
        \\    fn width(self: Door) -> UInt8 { self.width }
        \\}
        \\fn main() -> UInt8 {
        \\    let door: Door = .{ width = 3 }
        \\    door.width()
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    const offset = std.mem.indexOf(u8, text, "door.width()").? + "door.".len;
    const items = try offeredIn(gpa, &checked, checked.fileNamed("main.lin").?, offset);
    defer free(gpa, items);

    var field = false;
    var method = false;
    for (items) |item| {
        if (!std.mem.eql(u8, item.label, "width")) continue;
        if (item.kind == .Field) field = true;
        if (item.kind == .Method) method = true;
    }
    try testing.expect(field);
    try testing.expect(method);
}

test "a dot on an enum offers its variants" {
    const gpa = testing.allocator;

    const after = try offeredAfter(gpa, namespace_program, "Colour.Red");
    defer releaseAll(gpa, after);

    // A variant is named through its enum, so this is the only spelling of one
    // outside a match arm.
    try testing.expect(holds(after, "Red"));
    try testing.expect(holds(after, "Green"));
    // And nothing the enclosing scope holds, which is the rule for every dot.
    try testing.expect(!holds(after, "main"));
    try testing.expect(!holds(after, "Colour"));
}

test "a dot on a trait offers the operations it declares" {
    const gpa = testing.allocator;

    const after = try offeredAfter(gpa, namespace_program, "Measure.weight(p)");
    defer releaseAll(gpa, after);

    // The written-out form is what a trait's name is written for, and it is the
    // form this module's own rewrite writes.
    try testing.expect(holds(after, "weight"));
    try testing.expectEqual(@as(usize, 1), after.len);
}

test "written type selection completion uses the checked base" {
    const gpa = testing.allocator;
    const prefix =
        \\trait Source { type Item }
        \\struct Wrapper[T] { value: T }
        \\impl[T] Source for Wrapper[T] { type Item = T }
        \\fn main() -> UInt8 { 0 }
        \\
    ;
    for ([_][]const u8{ "Wrapper[T].Item", "(Wrapper[T]).Item", "Wrapper[T].", "(Wrapper[T])." }) |selection| {
        const text = try std.fmt.allocPrint(gpa, "{s}fn _identity[T](sink value: {s}) -> T where carries(value) {{ value }}\n", .{ prefix, selection });
        defer gpa.free(text);
        const offset = std.mem.indexOf(u8, text, selection).? + std.mem.indexOf(u8, selection, ".").? + 1;
        const after = try offeredAt(gpa, text, offset);
        defer releaseAll(gpa, after);
        try testing.expect(holds(after, "Item"));
        try testing.expectEqual(@as(usize, 1), after.len);
    }
}

test "written type selection completion preserves promised members" {
    const gpa = testing.allocator;
    const text =
        \\trait Source {
        \\    type Item
        \\    fn take(sink self: Self) -> Self.Item
        \\}
        \\fn _take[I: Source](sink source: I) -> I.Item { Source.take(source) }
        \\fn main() -> UInt8 { 0 }
    ;
    for ([_][]const u8{ "Self.Item", "I.Item" }) |written| {
        const after = try offeredAfter(gpa, text, written);
        defer releaseAll(gpa, after);
        try testing.expect(holds(after, "Item"));
        try testing.expectEqual(@as(usize, 1), after.len);
    }
}

test "a dot in a trait reference offers traits from that module" {
    const gpa = testing.allocator;
    const text =
        \\import protocol
        \\
        \\struct Item {}
        \\impl protocol. for Item {}
        \\
        \\fn main() -> UInt8 { 0 }
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = text },
        .{ .path = "app/protocol/protocol.lin", .text = "pub trait Label {}\npub fn seven() -> UInt8 { 7 }\n" },
    }, "app");
    defer checked.deinit();

    const offset = std.mem.indexOf(u8, text, "protocol.").? + "protocol.".len;
    const items = try offeredIn(gpa, &checked, checked.fileNamed("app/main.lin").?, offset);
    defer free(gpa, items);

    var labels: std.ArrayList([]const u8) = .empty;
    defer labels.deinit(gpa);
    for (items) |item| try labels.append(gpa, item.label);
    try testing.expect(holds(labels.items, "Label"));
    try testing.expect(!holds(labels.items, "seven"));
}

test "a dot on a type offers what the type declares and its traits' operations, and not what a value of it holds" {
    const gpa = testing.allocator;

    const after = try offeredAfter(gpa, namespace_program, "Pair.made(1)");
    defer releaseAll(gpa, after);

    // What the type's own namespace declares.
    try testing.expect(holds(after, "made"));
    // A field is part of a value, and a type is not a value: `Pair.a` is
    // [N-Variant].
    try testing.expect(!holds(after, "a"));
    // The type implements `Measure`, so `Pair.weight(pair)` reaches its
    // operation.
    try testing.expect(holds(after, "weight"));
}

test "a dot on a generic alias offers what the type it names declares" {
    const gpa = testing.allocator;

    const text =
        \\struct Cell[T] {
        \\    value: T,
        \\}
        \\
        \\impl[T] Cell[T] {
        \\    pub fn wrap(sink value: T) -> Cell[T] {
        \\        .{ value = value }
        \\    }
        \\}
        \\
        \\alias Slot[T] = Cell[T]
        \\
        \\fn main() -> UInt8 {
        \\    let held: Slot[UInt8] = Slot.wrap(3)
        \\    let Cell { value } = held
        \\    value
        \\}
        \\
    ;
    const after = try offeredAfter(gpa, text, "Slot.wrap(3)");
    defer releaseAll(gpa, after);

    try testing.expect(holds(after, "wrap"));
    try testing.expect(!holds(after, "value"));
}

test "intrinsic integer properties appear in primitive completion" {
    const gpa = testing.allocator;

    const text =
        \\fn main() -> UInt8 {
        \\    UInt8.max
        \\}
        \\
    ;
    const after = try offeredAfter(gpa, text, "UInt8.max");
    defer releaseAll(gpa, after);

    // Integer endpoints belong to the primitive namespace.
    try testing.expect(holds(after, "max"));
    try testing.expect(holds(after, "min"));
}

test "a name declared twice over one point is offered once" {
    const gpa = testing.allocator;

    const text =
        \\fn shadow(n: UInt8) -> UInt8 {
        \\    let n: UInt16 = UInt16(n) + 1
        \\    UInt8(n)
        \\}
        \\
    ;

    const at = std.mem.indexOf(u8, text, "UInt8(n)").? + 7;
    const offered = try offeredAt(gpa, text, at);
    defer releaseAll(gpa, offered);

    try testing.expectEqual(@as(usize, 1), howMany(offered, "n"));
}

test "an internal name is offered to another module in its root" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "import ledger\n\nfn main() -> UInt8 {\n    ledger.size()\n}\n" },
        .{ .path = "app/ledger/ledger.lin", .text = "internal fn size() -> UInt8 {\n    7\n}\n\nfn _kept() -> UInt8 {\n    1\n}\n" },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const text = checked.table.get(checked.fileNamed("app/main.lin").?).text;
    const items = try offeredIn(gpa, &checked, checked.fileNamed("app/main.lin").?, std.mem.indexOf(u8, text, "ledger.size").?);
    defer free(gpa, items);

    var labels: std.ArrayList([]const u8) = .empty;
    defer labels.deinit(gpa);
    for (items) |i| try labels.append(gpa, i.label);

    // The module and the qualified internal name are available throughout the
    // loaded root; the bare spelling still names nothing here.
    try testing.expect(holds(labels.items, "ledger"));
    try testing.expect(holds(labels.items, "ledger.size"));
    try testing.expect(!holds(labels.items, "size"));
    // What the module keeps to itself is offered under neither spelling.
    try testing.expect(!holds(labels.items, "ledger._kept"));
}

test "a module a sibling file imported binds no name here" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "import ledger\n\nfn main() -> UInt8 {\n    twice(ledger.size())\n}\n" },
        .{ .path = "app/helper.lin", .text = "fn twice(n: UInt8) -> UInt8 {\n    n + n\n}\n" },
        .{ .path = "app/ledger/ledger.lin", .text = "pub fn size() -> UInt8 {\n    7\n}\n" },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const helper = for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, "app/helper.lin")) break f;
    } else unreachable;

    const text = checked.table.get(helper).text;
    const items = try offeredIn(gpa, &checked, helper, std.mem.indexOf(u8, text, "n + n").? + 1);
    defer free(gpa, items);

    var labels: std.ArrayList([]const u8) = .empty;
    defer labels.deinit(gpa);
    for (items) |i| try labels.append(gpa, i.label);

    // An import binds a module name inside the file that wrote it, so nothing
    // is in scope here under either spelling. What an import written here
    // would reach is a different question, and no index is handed to this
    // call to answer it.
    try testing.expect(holds(labels.items, "twice"));
    try testing.expect(!holds(labels.items, "ledger"));
    try testing.expect(!holds(labels.items, "ledger.size"));
}

/// A workspace on disk and the paths a case names it by, so the index reads
/// files and the analysis reads the same ones.
///
/// The whole workspace is loaded by the caller and handed to the analysis, so
/// what the server sees and what the index holds are the same files.
const Scratch = struct {
    dir: testing.TmpDir,
    root: []const u8,

    fn init(files: []const struct { at: []const u8, text: []const u8 }) !Scratch {
        var tmp = testing.tmpDir(.{ .iterate = true });
        errdefer tmp.cleanup();

        for (files) |f| {
            if (std.fs.path.dirname(f.at)) |parent| try tmp.dir.createDirPath(testing.io, parent);
            try tmp.dir.writeFile(testing.io, .{ .sub_path = f.at, .data = f.text });
        }

        return .{
            .dir = tmp,
            .root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path}),
        };
    }

    fn deinit(self: *Scratch) void {
        testing.allocator.free(self.root);
        self.dir.cleanup();
    }

    fn at(self: *const Scratch, rest: []const u8) ![]u8 {
        return std.fs.path.join(testing.allocator, &.{ self.root, rest });
    }
};

test "qualified completion preserves export order across modules sharing a leaf" {
    const gpa = testing.allocator;
    const text = "fn main() -> UInt8 { ledger.same() }\n";
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = text },
        .{ .at = "a/ledger/one.lin", .text = "pub fn zeta() -> UInt8 { 0 }\npub fn same() -> UInt8 { 0 }\n" },
        .{ .at = "z/ledger/one.lin", .text = "pub fn alpha() -> UInt8 { 0 }\npub fn same() -> UInt8 { 0 }\n" },
        .{ .at = "other/item.lin", .text = "pub fn ignored() -> UInt8 { 0 }\n" },
        .{ .at = "separate/linea.json", .text = "{}" },
        .{ .at = "separate/ledger/item.lin", .text = "pub fn outside() -> UInt8 { 0 }\n" },
    });
    defer ws.deinit();
    var index = try workspace.Index.build(gpa, testing.io, ws.root);
    defer index.deinit();
    const query = try index.query();
    const main_path = try ws.at("main.lin");
    defer gpa.free(main_path);
    const entry = try loader.entryOf(gpa, testing.io, main_path, .its_program, ws.root);
    defer gpa.free(entry);
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = main_path, .text = text }}, entry);
    defer checked.deinit();

    for (0..2) |_| {
        const items = try atOffset(gpa, &checked.program, &checked.semantics.res, &checked.semantics.typing, &checked.cursors, checked.program.primaryFile(), @intCast(std.mem.indexOf(u8, text, "same").? + 2), .@"utf-16", .{ .query = query, .program = entry }, .unsupported);
        defer free(gpa, items);
        try testing.expectEqual(@as(usize, 4), items.len);
        const labels = [_][]const u8{ "alpha", "same", "same", "zeta" };
        const imports = [_][]const u8{ "z.ledger", "a.ledger", "z.ledger", "a.ledger" };
        for (items, labels, imports) |item, label, imported| {
            try testing.expectEqualStrings(label, item.label);
            try testing.expectEqualStrings(imported, item.labelDetails.?.description.?);
            try testing.expectEqual(@as(usize, 1), item.additionalTextEdits.?.len);
            try testing.expect(std.mem.indexOf(u8, item.additionalTextEdits.?[0].newText, imported) != null);
        }
    }
}

test "a name nobody imported is called what it is called, and inserts what compiles" {
    const gpa = testing.allocator;

    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "fn main() -> UInt8 {\n    0\n}\n" },
        .{ .at = "coins/ledger/l.lin", .text = "pub fn size() -> UInt8 {\n    7\n}\n" },
    });
    defer ws.deinit();

    var index = try workspace.Index.build(gpa, testing.io, ws.root);
    defer index.deinit();
    const query = try index.query();

    const main = try ws.at("main.lin");
    defer gpa.free(main);
    const text = "fn main() -> UInt8 {\n    0\n}\n";

    // Which program the file belongs to is the loader's answer, which is what
    // the index was keyed by and what the server asks it for.
    const program = try loader.entryOf(gpa, testing.io, main, .its_program, ws.root);
    defer gpa.free(program);

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = main, .text = text }}, program);
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const items = try atOffset(
        gpa,
        &checked.program,
        &checked.semantics.res,
        &checked.semantics.typing,
        &checked.cursors,
        checked.program.primaryFile(),
        @intCast(std.mem.indexOf(u8, text, "    0").? + 5),
        .@"utf-16",
        .{ .query = query, .program = program },
        .unsupported,
    );
    defer free(gpa, items);

    var module: ?Item = null;
    var name: ?Item = null;
    for (items) |i| {
        if (std.mem.eql(u8, i.label, "ledger")) module = i;
        if (std.mem.eql(u8, i.label, "size")) name = i;
        // The qualified form is what accepting writes, not what the item is
        // called: a client matches what was typed against the label.
        try testing.expect(!std.mem.eql(u8, i.label, "ledger.size"));
    }

    // The module is named by the last element of the path an import writes,
    // and the path is what descends to it.
    try testing.expectEqual(Item.Kind.Module, module.?.kind.?);
    try testing.expect(module.?.detail == null);
    try testing.expectEqualStrings(
        "import coins.ledger\n\n",
        module.?.additionalTextEdits.?[0].newText,
    );

    // The name is its own, and which module holds it sits in the description
    // beside it, where it says which one without competing with what was
    // typed.
    try testing.expectEqual(Item.Kind.Function, name.?.kind.?);
    try testing.expectEqualStrings("coins.ledger", name.?.labelDetails.?.description.?);
    // A name it exports has been parsed and not checked, so what it shows is
    // the header the source wrote.
    try testing.expectEqualStrings("pub fn size() -> UInt8", name.?.detail.?);
    // And accepting it writes the one spelling that crosses a module boundary,
    // with the import that binds the qualifier.
    try testing.expectEqualStrings("ledger.size", name.?.insertText.?);
    try testing.expectEqualStrings(
        "import coins.ledger\n\n",
        name.?.additionalTextEdits.?[0].newText,
    );
}

test "a nested module completion carries a root-relative sibling import" {
    const gpa = testing.allocator;
    const nested_text = "pub fn value() -> UInt8 {\n    0\n}\n";

    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "import nested\n\nfn main() -> UInt8 { nested.value() }\n" },
        .{ .at = "nested/n.lin", .text = nested_text },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 7 }\n" },
    });
    defer ws.deinit();

    var index = try workspace.Index.build(gpa, testing.io, ws.root);
    defer index.deinit();
    const query = try index.query();

    const main = try ws.at("main.lin");
    defer gpa.free(main);
    const nested = try ws.at("nested/n.lin");
    defer gpa.free(nested);

    const program = try loader.entryOf(gpa, testing.io, nested, .its_program, ws.root);
    defer gpa.free(program);

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = main, .text = "import nested\n\nfn main() -> UInt8 { nested.value() }\n" },
        .{ .path = nested, .text = nested_text },
    }, program);
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const asked = for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, nested)) break f;
    } else unreachable;

    const items = try atOffset(
        gpa,
        &checked.program,
        &checked.semantics.res,
        &checked.semantics.typing,
        &checked.cursors,
        asked,
        @intCast(std.mem.indexOf(u8, nested_text, "    0").? + 5),
        .@"utf-16",
        .{ .query = query, .program = program },
        .unsupported,
    );
    defer free(gpa, items);

    var ledger: ?Item = null;
    var size: ?Item = null;
    for (items) |item| {
        if (std.mem.eql(u8, item.label, "ledger")) ledger = item;
        if (std.mem.eql(u8, item.label, "size")) size = item;
    }

    try testing.expect(ledger != null);
    try testing.expect(size != null);
    try testing.expectEqualStrings(
        "import ledger\n\n",
        ledger.?.additionalTextEdits.?[0].newText,
    );
    try testing.expectEqualStrings("ledger.size", size.?.insertText.?);
    try testing.expectEqualStrings(
        "import ledger\n\n",
        size.?.additionalTextEdits.?[0].newText,
    );
}

test "a module a sibling file imported is offered here with the import this file needs" {
    const gpa = testing.allocator;

    const main_text = "fn main() -> UInt8 {\n    0\n}\n";
    const sibling = "import ledger\n\nfn twice() -> UInt8 {\n    ledger.size() + ledger.size()\n}\n";

    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = main_text },
        .{ .at = "other.lin", .text = sibling },
        .{ .at = "ledger/ledger.lin", .text = "pub fn size() -> UInt8 {\n    7\n}\n" },
    });
    defer ws.deinit();

    var index = try workspace.Index.build(gpa, testing.io, ws.root);
    defer index.deinit();
    const query = try index.query();

    const main = try ws.at("main.lin");
    defer gpa.free(main);
    const other = try ws.at("other.lin");
    defer gpa.free(other);
    const held = try ws.at("ledger/ledger.lin");
    defer gpa.free(held);

    const program = try loader.entryOf(gpa, testing.io, main, .its_program, ws.root);
    defer gpa.free(program);

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = main, .text = main_text },
        .{ .path = other, .text = sibling },
        .{ .path = held, .text = "pub fn size() -> UInt8 {\n    7\n}\n" },
    }, program);
    defer checked.deinit();

    const asked = for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, main)) break f;
    } else unreachable;

    const items = try atOffset(
        gpa,
        &checked.program,
        &checked.semantics.res,
        &checked.semantics.typing,
        &checked.cursors,
        asked,
        @intCast(std.mem.indexOf(u8, main_text, "    0").? + 5),
        .@"utf-16",
        .{ .query = query, .program = program },
        .unsupported,
    );
    defer free(gpa, items);

    var labels: std.ArrayList([]const u8) = .empty;
    defer labels.deinit(gpa);
    for (items) |i| try labels.append(gpa, i.label);

    // An import binds in the file that wrote it, so the sibling's import is not
    // one this file can name through and not one its own import collides with:
    // two files of a module may each write `import ledger`.
    try testing.expect(holds(labels.items, "ledger"));
    try testing.expect(holds(labels.items, "size"));
}

test "intrinsic integer properties complete an unfinished constrained namespace" {
    const gpa = testing.allocator;
    for ([_][]const u8{
        "fn limit[T: Integer](_value: T) -> T { T. }\nfn main() -> UInt8 { 0 }\n",
        "fn limit[T](_value: T) -> T where T: Integer { T. }\nfn main() -> UInt8 { 0 }\n",
    }) |text| {
        const after = try offeredAfter(gpa, text, "T.");
        defer releaseAll(gpa, after);
        try testing.expect(holds(after, "min"));
        try testing.expect(holds(after, "max"));
    }
}

test "intrinsic integer properties exclude unconstrained namespaces and values" {
    const gpa = testing.allocator;
    for ([_][]const u8{
        "fn limit[T](_value: T) -> T { T. }\nfn main() -> UInt8 { 0 }\n",
        "fn main() -> UInt8 { let T = UInt8(1)\n T. }\n",
        "fn main() -> UInt8 { Bool. }\n",
        "fn main() -> UInt8 { Float64. }\n",
        "type Distance = UInt8\nfn main() -> UInt8 { Distance. }\n",
        "trait Integer {}\nfn limit[T: Integer](_value: T) -> T { T. }\nfn main() -> UInt8 { 0 }\n",
    }) |text| {
        const dot = std.mem.indexOf(u8, text, ".").? + 1;
        const after = try offeredAt(gpa, text, dot);
        defer releaseAll(gpa, after);
        try testing.expect(!holds(after, "min"));
        try testing.expect(!holds(after, "max"));
    }
}

test "a primitive offers each library method once however many impl blocks hold them" {
    const gpa = testing.allocator;
    // The library writes each Float64 method in an `impl Float64` block of its own.
    const text = "fn main() -> UInt8 { Float64. }\n";
    const after = try offeredAt(gpa, text, std.mem.indexOf(u8, text, ".").? + 1);
    defer releaseAll(gpa, after);
    try testing.expect(holds(after, "sqrt"));
    try testing.expect(holds(after, "floor"));
    for (after, 0..) |label, i| {
        for (after[i + 1 ..]) |other| try testing.expect(!std.mem.eql(u8, label, other));
    }

    // Every lookup walks the primitive's namespace rows, so they stay one per
    // module rather than one per block.
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    var float_rows: usize = 0;
    for (checked.semantics.res.builtin_namespaces) |ns| {
        if (ns.of == .f64) float_rows += 1;
    }
    try testing.expectEqual(@as(usize, 1), float_rows);
}

test "array view completion offers checked traversal for arrays and observations" {
    const gpa = testing.allocator;
    const source =
        \\fn main() -> UInt8 {
        \\    let values = [UInt8(3), UInt8(7)]
        \\    let view = borrow values
        \\    view.as_slice()[0]
        \\}
    ;
    const members = try offeredAfter(gpa, source, "view.as_slice");
    defer releaseAll(gpa, members);
    try testing.expect(holds(members, "as_slice"));
    try testing.expect(holds(members, "length"));
}

test "parameter head completion retains methods awaiting a destination" {
    const gpa = testing.allocator;
    const source =
        \\trait Build[T] { fn build(source: T) -> Self }
        \\trait Deliver[T] { fn deliver(self: Self) -> T }
        \\impl[T, U: Build[T]] Deliver[U] for T {
        \\    fn deliver(self: T) -> U { Build.build(self) }
        \\}
        \\struct Packet { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let packet: Packet = .{ value = 7 }
        \\    packet.value
        \\}
    ;
    const members = try offeredAfter(gpa, source, "packet.value");
    defer releaseAll(gpa, members);
    try testing.expect(holds(members, "deliver"));
}

test "declaration attribute completion offers only closed item names" {
    const gpa = testing.allocator;
    const cases = [_]struct { text: []const u8, offset: usize }{
        .{ .text = "@", .offset = 1 },
        .{ .text = "@(li)\nstruct Point { value: UInt8 }\nfn main() -> UInt8 { 0 }\n", .offset = 4 },
        .{ .text = "fn main() -> UInt8 { 0 }\n@", .offset = "fn main() -> UInt8 { 0 }\n@".len },
    };
    for (cases) |case| {
        const offered = try offeredAt(gpa, case.text, case.offset);
        defer releaseAll(gpa, offered);
        try testing.expectEqual(@as(usize, 5), offered.len);
        for ([_][]const u8{ "opaque", "linear", "copyable", "carrier", "derive" }) |name| {
            try testing.expect(holds(offered, name));
        }
    }
}

test "declaration attribute derive completion excludes ordinary values and types" {
    const gpa = testing.allocator;
    const text =
        \\trait Score {}
        \\template impl Score {}
        \\@derive(Sc)
        \\struct Point { value: UInt8 }
        \\fn main() -> UInt8 { 0 }
    ;
    const offset = std.mem.indexOf(u8, text, "Sc)").? + 2;
    const offered = try offeredAt(gpa, text, offset);
    defer releaseAll(gpa, offered);
    try testing.expect(holds(offered, "Score"));
    try testing.expect(!holds(offered, "Point"));
    try testing.expect(!holds(offered, "main"));
    try testing.expect(!holds(offered, "UInt8"));
}

test "declaration attribute trait arguments offer nothing" {
    const gpa = testing.allocator;
    const text =
        \\trait Score[T] {}
        \\@derive(Score[Ui])
        \\struct Point { value: UInt8 }
        \\fn main() -> UInt8 { 0 }
    ;
    const offset = std.mem.indexOf(u8, text, "Ui]").? + 2;
    const offered = try offeredAt(gpa, text, offset);
    defer releaseAll(gpa, offered);
    try testing.expectEqual(@as(usize, 0), offered.len);
}

test "declaration attribute qualified trait arguments offer nothing" {
    const gpa = testing.allocator;
    const text =
        \\import protocol
        \\trait Score[T] {}
        \\@derive(Score[protocol.])
        \\struct Point { value: UInt8 }
        \\fn main() -> UInt8 { 0 }
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = text },
        .{ .path = "app/protocol/protocol.lin", .text = "pub struct Data { value: UInt8 }\n" },
    }, "app");
    defer checked.deinit();
    const offset = std.mem.indexOf(u8, text, "protocol.").? + "protocol.".len;
    const items = try offeredIn(gpa, &checked, checked.fileNamed("app/main.lin").?, offset);
    defer free(gpa, items);
    try testing.expectEqual(@as(usize, 0), items.len);
}

test "a local that shadows a module is completed as the local in an expression and the module in a type" {
    const gpa = testing.allocator;
    const text =
        \\import std.text
        \\fn size(text: Str) -> UInt64 {
        \\    let _unused: Option[text.ParseError] = .None
        \\    text.length()
        \\}
        \\fn main() -> UInt8 {
        \\    UInt8.try_from(size("ab")).unwrap_or(0)
        \\}
    ;
    // After the dot in an expression, `text` is the parameter.
    const members = try offeredAfter(gpa, text, "text.length()");
    defer releaseAll(gpa, members);
    try testing.expect(holds(members, "length"));
    try testing.expect(!holds(members, "ParseError"));
    try testing.expect(!holds(members, "text.ParseError"));

    // The name itself in that expression is the parameter, so nothing is
    // offered through the module it shadows.
    const head = try offeredAt(gpa, text, std.mem.indexOf(u8, text, "text.length()").? + "text".len);
    defer releaseAll(gpa, head);
    try testing.expect(holds(head, "text"));
    try testing.expect(!holds(head, "text.ParseError"));

    // A type path in the same scope still names the module.
    const in_type = try offeredAt(gpa, text, std.mem.indexOf(u8, text, "text.ParseError]").? + "text".len);
    defer releaseAll(gpa, in_type);
    try testing.expect(holds(in_type, "text.ParseError"));
}

test "an unfinished dot on a local that shadows a module offers the local's members" {
    const gpa = testing.allocator;
    const text =
        \\import std.text
        \\fn size(text: Str) -> UInt64 {
        \\    let _unused: Option[text.ParseError] = .None
        \\    text.
        \\}
    ;
    const members = try offeredAt(gpa, text, std.mem.indexOf(u8, text, "text.\n").? + "text.".len);
    defer releaseAll(gpa, members);
    try testing.expect(holds(members, "length"));
    try testing.expect(!holds(members, "ParseError"));
    try testing.expect(!holds(members, "text.ParseError"));
}

test "a half-typed name completes no module items a local shadows in an expression" {
    const gpa = testing.allocator;
    const text =
        \\import std.text
        \\fn size(text: Str) -> UInt64 {
        \\    let _unused: Option[te] = .None
        \\    let later = te
        \\    later.length()
        \\}
        \\fn main() -> UInt8 {
        \\    let before = te
        \\    let text = 3
        \\    UInt8.try_from(size("ab")).unwrap_or(text)
        \\}
    ;
    // In an expression inside `size`, `text` is the parameter.
    const in_expression = try offeredAt(gpa, text, std.mem.indexOf(u8, text, "later = te").? + "later = te".len);
    defer releaseAll(gpa, in_expression);
    try testing.expect(holds(in_expression, "text"));
    try testing.expect(!holds(in_expression, "text.ParseError"));

    // A type path in the same scope still names the module.
    const in_type = try offeredAt(gpa, text, std.mem.indexOf(u8, text, "Option[te").? + "Option[te".len);
    defer releaseAll(gpa, in_type);
    try testing.expect(holds(in_type, "text.ParseError"));

    // Before `let text` in `main`, the module is still what `text` names.
    const before = try offeredAt(gpa, text, std.mem.indexOf(u8, text, "before = te").? + "before = te".len);
    defer releaseAll(gpa, before);
    try testing.expect(holds(before, "text.ParseError"));
}
