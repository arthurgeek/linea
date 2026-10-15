const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const positions = @import("positions.zig");
const uri_mod = @import("uri.zig");
const BindingId = @import("../sema/resolve.zig").BindingId;
const Resolution = @import("../sema/resolve.zig").Resolution;
const Ast = @import("../syntax/ast.zig").Ast;
const TokenId = @import("../lexer/token.zig").TokenId;
const DeclId = @import("../syntax/node.zig").DeclId;
const SupplyIndex = @import("../sema/types.zig").SupplyIndex;
const FileId = @import("../support/source.zig").FileId;
const Span = @import("../support/span.zig").Span;

/// Everywhere the name under a cursor is written, or null where nothing there
/// names anything.
///
/// Three lookups and no search. Which node a cursor sits on is the position
/// index's answer, what it names is `targetOf`'s for a name and `declaredAt`'s
/// for the token a declaration was written at, and where else that name appears
/// is the reverse index's -- so nothing here matches a spelling against
/// anything, and a shadowed local, a re-export and a name the prelude offers
/// each answer for whatever the resolver said rather than for whatever the
/// checker paired it with.
///
/// A trait's operation is several declarations the language obliges to share a
/// spelling, and every one of them is a place that name is written: asking
/// about the signature names the members supplying it, and asking about a
/// member names the signature and its siblings. Which those are is
/// `spelledAlike`'s answer, and it is the answer a rename edits -- a rename
/// that reached a site this did not would change a byte nobody was shown.
///
/// `only` narrows the answer to one file, which is what a highlight of the
/// document under the cursor is: the same question, the same lookups, and the
/// sites in another file dropped. A second function would be a second opinion
/// about what a name reaches.
///
/// `include_declaration` is the client's own parameter. A client that wants the
/// uses alone asks for them, and a server that always sent the declaration
/// would be answering a question it was not asked.
///
/// A site in a file no client can open is dropped, for the reason `definition`
/// drops one: a location an editor cannot follow surfaces as the editor's
/// failure rather than as this server having nothing to say.
///
/// **Bound:** the size of the answer and the files it lands in. One lookup to
/// reach the binding, one run of the record for the names that must stay
/// spelled alike, one run of the reverse index for each of their uses, a sort
/// of those, one pass over the bytes of each file they land in, and one read of
/// each such file that belongs to the library. Nothing is sized by what the
/// program holds: a name used twice costs two sites however large the module
/// is, and a trait's operation costs one site per implementation because that
/// is what the answer holds.
pub fn forPosition(
    gpa: std.mem.Allocator,
    io: std.Io,
    checked: *const Analysis,
    file: FileId,
    position: lsp.types.Position,
    encoding: lsp.offsets.Encoding,
    /// The directory the client opened, which the library's source sits under
    /// when the workspace is the compiler's own checkout.
    root: []const u8,
    include_declaration: bool,
    /// The one file to answer about, or null for every file of the module.
    only: ?FileId,
) !?[]const lsp.types.Location {
    const named = namedAt(checked, file, position, encoding);
    if (named == BindingId.none) {
        const field = sourceNameAt(checked, file, position, encoding);
        if (field == .none) return null;
        const sites = try sourceNameSites(gpa, checked, field, include_declaration, only);
        defer gpa.free(sites);
        return try locationsOf(gpa, io, checked, sites, encoding, root);
    }

    const alike = try spelledAlike(gpa, checked, named);
    defer gpa.free(alike);

    const sites = try sitesOf(gpa, checked, alike, include_declaration, only);
    defer gpa.free(sites);

    return try locationsOf(gpa, io, checked, sites, encoding, root);
}

/// The binding a cursor reached, or `.none` where it reached nothing.
///
/// A cursor on the token a name was declared at reaches what that token
/// declares; a cursor on a name written outside every expression -- an
/// annotation, a type argument, a bound, an `impl` head, a `use` path -- reaches
/// what the resolver settled that token on; a cursor on a name written as an
/// expression reaches what that expression reaches. The three are one question
/// with one lookup each, and no byte is two of them.
///
/// The third is asked of the reverse index rather than of the resolution, so
/// `a.of()` and `Measure.of(a)` answer alike: they are one call written two
/// ways, and the callee of the first resolves to nothing by construction.
///
/// Every capability that starts from a cursor and needs a binding asks this. A
/// second reading would let one of them follow a name the other refuses, which
/// for a rename means editing something a reader was never shown.
pub fn namedAt(
    checked: *const Analysis,
    file: FileId,
    position: lsp.types.Position,
    encoding: lsp.offsets.Encoding,
) BindingId {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return BindingId.none;
    const found = checked.cursors.atPosition(ast, part, position, encoding) orelse return BindingId.none;

    const declared = checked.uses.declaredAt(found.token);
    if (declared != BindingId.none) return declared;

    const source_declaration = checked.uses.sourceNameAt(found.token);
    const source_binding = checked.uses.declaredAt(source_declaration);
    if (source_binding != .none) return source_binding;

    const written = checked.uses.writesAt(&checked.semantics.res, found.token);
    if (written != BindingId.none) return written;
    if (checked.uses.initializerBindingAt(found.token)) |binding| return binding;
    // A qualified variant expression reaches its enum, but the variant token
    // has its own source identity. Only the qualifier names the enum binding.
    if (source_declaration != .none) return .none;

    return switch (found.node) {
        .expr => |e| checked.uses.reachedBy(ast, &checked.semantics.res, e),
        .decl, .stmt => BindingId.none,
    };
}

/// A source-token declaration, such as a field or contextual callable parameter.
pub fn sourceNameAt(checked: *const Analysis, file: FileId, position: lsp.types.Position, encoding: lsp.offsets.Encoding) TokenId {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return .none;
    const found = checked.cursors.atPosition(ast, part, position, encoding) orelse return .none;
    return checked.uses.sourceNameAt(found.token);
}

pub fn sourceNameSites(gpa: std.mem.Allocator, checked: *const Analysis, declaration: TokenId, include_declaration: bool, only: ?FileId) ![]Site {
    const ast = &checked.program.ast;
    var sites: std.ArrayList(Site) = .empty;
    errdefer sites.deinit(gpa);
    for (checked.uses.sourceNameSites(declaration)) |token| {
        if (!include_declaration and token == declaration) continue;
        const file = ast.fileOf(token);
        if (only) |wanted| if (wanted != file) continue;
        const binding = checked.uses.declaredAt(token);
        const initializer = checked.uses.initializerBindingAt(token) != null;
        try sites.append(gpa, .{
            .file = file,
            .span = ast.tokenSpan(token),
            .spells_a_binding = initializer or (binding != .none and checked.semantics.res.bindsAFieldByItsOwnName(binding)),
            .initializer = initializer,
        });
    }
    std.mem.sortUnstable(Site, sites.items, {}, Site.before);
    return sites.toOwnedSlice(gpa);
}

/// Every place a set of bindings is written, in the order a reader reads them.
///
/// The declaration and the reverse index's two runs -- the expressions that
/// reach it and the tokens that write its name outside one -- sorted and
/// nothing else. No spelling is compared and nothing is walked. A capability
/// that reports where a name appears and one that rewrites every such place are
/// asking one question, so they ask it here: a rename that found one site the
/// highlight did not would change a byte nobody was shown.
///
/// Several bindings rather than one, because a name is sometimes several
/// declarations the language obliges to be spelled alike -- a trait's operation
/// and every member supplying it. Which bindings those are is `spelledAlike`'s
/// question; where each of them is written is this one, and asking it once per
/// binding is what keeps the two apart.
///
/// Source `use` bindings join their canonical declaration through the reverse
/// alias index. Each selected declaration family is expanded once.
///
/// **Bound:** O(selected bindings + aliases + k log k) for `k` sites, with
/// temporary storage proportional to selected declaration families and sites.
pub fn sitesOf(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    named: []const BindingId,
    include_declaration: bool,
    /// The one file to answer about, or null for every file of the module.
    only: ?FileId,
) ![]Site {
    var sites: std.ArrayList(Site) = .empty;
    errdefer sites.deinit(gpa);
    var expanded: std.AutoHashMapUnmanaged(DeclId, void) = .empty;
    defer expanded.deinit(gpa);

    for (named) |binding| {
        const declaration = @import("uses.zig").sourceDeclaration(&checked.semantics.res, binding);
        const aliases = checked.uses.aliasesOfDeclaration(declaration);
        if (aliases.len == 0) {
            try appendBindingSites(gpa, checked, binding, include_declaration, only, &sites);
            continue;
        }
        const entry = try expanded.getOrPut(gpa, declaration);
        if (entry.found_existing) continue;
        const original = checked.uses.bindingOfDeclaration(declaration);
        if (original != .none)
            try appendBindingSites(gpa, checked, original, include_declaration, only, &sites);
        for (aliases) |alias|
            try appendBindingSites(gpa, checked, alias, include_declaration, only, &sites);
    }

    if (only) |wanted| {
        var kept: usize = 0;
        for (sites.items) |s| {
            if (s.file != wanted) continue;
            sites.items[kept] = s;
            kept += 1;
        }
        sites.shrinkRetainingCapacity(kept);
    }

    std.mem.sortUnstable(Site, sites.items, {}, Site.before);

    // One site per place, however many ways the resolution reached it. A
    // pattern's binder is declared and reached at one token, and a qualified
    // variant reaches its enum through the selection as well as through the
    // name it selects from -- so the same bytes arrive here twice, and a
    // reader shown a location twice is only puzzled while an applier handed
    // one edit twice writes the replacement over itself.
    //
    // Here rather than in a caller, because reporting where a name is written
    // and rewriting every such place are the same question: a fix in one of
    // them would leave the other two answering with a duplicate.
    //
    // The order already put equal sites beside each other, so this is one pass
    // over the answer and not a search per site.
    var kept: usize = 0;
    for (sites.items) |s| {
        if (kept > 0 and sites.items[kept - 1].file == s.file and sites.items[kept - 1].span.start == s.span.start) {
            // What the survivor says about the place is what any of them said
            // about it, so which one the sort left first decides nothing.
            sites.items[kept - 1].spells_a_field =
                sites.items[kept - 1].spells_a_field or s.spells_a_field;
            sites.items[kept - 1].initializer = sites.items[kept - 1].initializer or s.initializer;
            continue;
        }
        sites.items[kept] = s;
        kept += 1;
    }
    sites.shrinkRetainingCapacity(kept);

    return sites.toOwnedSlice(gpa);
}

fn appendBindingSites(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    b: BindingId,
    include_declaration: bool,
    only: ?FileId,
    sites: *std.ArrayList(Site),
) !void {
    const ast = &checked.program.ast;
    if (include_declaration) {
        const wrote = checked.semantics.res.declaringToken(b);
        // A primitive is introduced at no token, so there is no declaration
        // to include and its uses stand on their own.
        if (wrote != TokenId.none and wrote.index() < ast.tokenCount()) {
            try sites.append(gpa, .{
                .file = ast.fileOf(wrote),
                .span = ast.tokenSpan(wrote),
                .spells_a_field = checked.semantics.res.bindsAFieldByItsOwnName(b),
                .spells_a_binding = checked.semantics.res.kindOf(b) == .capture and checked.uses.initializerBindingAt(wrote) != null,
                .initializer = checked.semantics.res.kindOf(b) == .capture and checked.uses.initializerBindingAt(wrote) != null,
            });
        }
    }
    for (checked.uses.of(b)) |wrote| {
        if (wrote.index() >= ast.tokenCount()) continue;
        // The token the resolver settled the expression on, read rather
        // than taken from the shape of the node: a selection reaches its
        // binding through one of its two names and which one is not always
        // the last, so `Shade.Dim` is a use of `Shade` written at `Shade`.
        const initializer = checked.uses.initializerBindingAt(wrote) != null;
        try sites.append(gpa, .{
            .file = ast.fileOf(wrote),
            .span = ast.tokenSpan(wrote),
            .spells_a_field = initializer,
            .initializer = initializer,
        });
    }
    if (checked.semantics.res.kindOf(b) == .capture) {
        const fields = try sourceNameSites(gpa, checked, checked.semantics.res.declaringToken(b), false, only);
        defer gpa.free(fields);
        try sites.appendSlice(gpa, fields);
    }
    // The tokens that write the name where no expression is: an annotation,
    // a type argument, a bound, an `impl` head, a `use` path. The token
    // itself rather than what encloses it, for the reason an expression's
    // main token is taken -- a bound is written inside a parameter list and
    // highlighting the list would cover names the cursor is not on.
    for (checked.uses.writtenOf(b)) |t| {
        if (t.index() >= ast.tokenCount()) continue;
        try sites.append(gpa, .{ .file = ast.fileOf(t), .span = ast.tokenSpan(t) });
    }
}

/// Every name one cursor asks about, the one under it first.
///
/// One name for all but a trait's operation. A signature and the `impl` members
/// supplying it are declarations the language obliges to share a spelling, so
/// they are one name written in several places: reporting where that name is
/// used names all of them, and renaming any of them renames all of them --
/// editing one side alone leaves the other declaring a name its trait does not
/// declare.
///
/// Which member supplies which signature is read from the record the checker
/// wrote when it discharged each implementation against its trait. Pairing them
/// here by the name they share would be that relation implemented a second time,
/// and it is the implementation that cannot survive its own answer: renaming one
/// side is exactly what makes the spellings differ.
///
/// A member the record does not pair with a signature stands alone. Its
/// implementation supplies a signature its trait does not declare, which the
/// checker reports, and there is no second name to keep in step.
///
/// A parameter is the same relation one level down: [T-Impl] holds a member's
/// k-th parameter to the name the signature's k-th declares, so those are one
/// name written in several places too, and a rename that moved one of them
/// alone would write a program the checker refuses.
///
/// **Bound:** the size of the answer -- one lookup per side of the record, and a
/// run whose length is the number of implementations supplying that signature.
/// For a parameter, one walk of each such declaration's own parameters.
pub fn spelledAlike(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    named: BindingId,
) ![]const BindingId {
    const ast = &checked.program.ast;
    const res = &checked.semantics.res;
    const supply = &checked.semantics.typing.supply_index;

    // A parameter's answer needs the resolution and the record and nothing a
    // session holds, so it is the one every rewriter of a program can ask --
    // and asking it here is what keeps the two halves of one relation from
    // being two readings of it.
    if (res.kindOf(named) == .parameter) return parametersAlike(gpa, ast, res, supply, named);

    const sig = signatureFor(ast, supply, res.declIfDeclared(named)) orelse
        return gpa.dupe(BindingId, &.{named});

    var out: std.ArrayList(BindingId) = .empty;
    errdefer out.deinit(gpa);
    const members = supply.membersOf(DeclId.at(sig));
    // The queried binding and signature add at most two entries to the
    // supplier run. Reserve the answer before filling it so a request arena
    // retains no intermediate growth buffers.
    try out.ensureTotalCapacityPrecise(gpa, members.len + 2);
    out.appendAssumeCapacity(named);

    // The members first and the signature last, because the order here decides
    // nothing: the sites they resolve to are ordered by where they are written.
    for (members) |m| appendNamed(checked, &out, DeclId.at(m));
    appendNamed(checked, &out, DeclId.at(sig));

    return out.toOwnedSlice(gpa);
}

/// Every parameter one parameter is spelled alike with: the one asked about
/// first, then the parameter standing in its position in each of the other
/// declarations of the operation.
///
/// The parameter half of `spelledAlike`, and separate from it because it needs
/// nothing a language server holds: a rewriter of source asks the same question
/// about a rename it is about to apply, and a second answer to it is a rename
/// that writes a program the checker refuses.
///
/// **Bound:** one run of the record for the declarations supplying the
/// signature, and one index into each one's parameters. So the answer costs its
/// own size, and asking it of every parameter of a signature costs one entry
/// per parameter the implementations declare.
pub fn parametersAlike(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    supply: *const SupplyIndex,
    named: BindingId,
) ![]const BindingId {
    if (res.kindOf(named) != .parameter) return gpa.dupe(BindingId, &.{named});

    const owner = switch (res.parameterOwner(named)) {
        .declaration => |decl| decl,
        .closure => return gpa.dupe(BindingId, &.{named}),
    };
    const sig = signatureFor(ast, supply, owner) orelse
        return gpa.dupe(BindingId, &.{named});

    var out: std.ArrayList(BindingId) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, named);

    const position = res.paramIndexOf(named);
    for (supply.membersOf(DeclId.at(sig))) |m| try appendParameter(gpa, ast, res, &out, DeclId.at(m), position);
    try appendParameter(gpa, ast, res, &out, DeclId.at(sig), position);

    return out.toOwnedSlice(gpa);
}

/// The signature a declaration is, or the one it supplies, or null where it is
/// neither -- an ordinary function, an inherent member, a member whose trait
/// declares no such operation.
fn signatureFor(ast: *const Ast, supply: *const SupplyIndex, d: DeclId) ?u32 {
    if (d == DeclId.none or d.index() >= ast.declCount()) return null;
    if (ast.declIsSignature(d)) return @intCast(d.index());
    if (supply.signatureOf(d)) |s| return s.index();
    // A member a trait declares that is not a signature -- a type its
    // implementations settle. What supplies one is recorded against this
    // declaration, so the run standing against it is what says it is the
    // trait's side, and no second reading of the tree decides it.
    if (supply.membersOf(d).len > 0) return d.index();
    return null;
}

/// The binding declared by the parameter standing at `position`, appended
/// unless it is already there.
///
/// Walked from the bindings, because a parameter the resolver never bound has
/// none to rename -- a name that did not read as an identifier is one.
///
/// **Bound:** one index. The bindings are in declaration order, so the
/// parameter at a position is the entry at that index, and only a declaration
/// with a parameter the resolver never bound is searched. The guard is one
/// comparison rather than a scan of the answer: each declaration contributes
/// one parameter and each is asked once, so the only binding that can already
/// be there is the one asked about, which is the first.
fn appendParameter(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    out: *std.ArrayList(BindingId),
    d: DeclId,
    position: u32,
) !void {
    if (d.index() >= ast.declCount()) return;
    const params = res.parametersOf(d);
    const b = if (position < params.len and res.paramIndexOf(params[position]) == position)
        params[position]
    else blk: {
        for (params) |x| if (res.paramIndexOf(x) == position) break :blk x;
        return;
    };
    if (out.items.len > 0 and out.items[0] == b) return;
    try out.append(gpa, b);
}

/// The binding a declaration's name declares, appended unless it is already
/// there.
///
/// The name under the cursor is one of these, so the guard is what keeps a
/// caller from being handed the same binding twice. A declaration whose name
/// declares nothing is one the resolver never bound, which no program it
/// accepted has -- and an answer about a program with a hole in it speaks for
/// the names that are there.
/// Each signature's supply run contains one member per implementation, whose
/// source extents are disjoint. Source declarations consume distinct name
/// tokens, and generated declarations are excluded below. Thus only the
/// queried binding, placed first, can already be in the answer.
fn appendNamed(
    checked: *const Analysis,
    out: *std.ArrayList(BindingId),
    d: DeclId,
) void {
    if (d.index() >= checked.program.ast.declCount()) return;
    const b = checked.uses.bindingOfDeclaration(d);
    if (b == BindingId.none) return;
    if (out.items[0] == b) return;
    out.appendAssumeCapacity(b);
}

/// Whether the source name participates in a trait operation supplied by a
/// generated declaration. Such a declaration remains part of semantic lookup,
/// but no workspace document owns its token and a rename cannot edit it.
pub fn hasGeneratedSupplier(checked: *const Analysis, named: BindingId) bool {
    const ast = &checked.program.ast;
    const res = &checked.semantics.res;
    const supply = &checked.semantics.typing.supply_index;
    const declared = if (res.kindOf(named) == .parameter)
        switch (res.parameterOwner(named)) {
            .declaration => |d| d,
            .closure => return false,
        }
    else
        res.declIfDeclared(named);
    const sig = signatureFor(ast, supply, declared) orelse return false;
    for (supply.membersOf(DeclId.at(sig))) |member| {
        if (member >= ast.declCount()) return true;
    }
    return false;
}

/// Where a name is written, before the file's own bytes turn it into a range.
pub const Site = struct {
    file: FileId,
    span: Span,
    /// Whether these bytes name a field as well as the binding. A struct
    /// pattern's shorthand writes the field and the binder at one token, so a
    /// rename replacing the token in place would rename the field with it and
    /// name a field the type does not have.
    ///
    /// Carried on the site rather than asked at the point of use, because only
    /// the answer's producer knows which of a binding's places this is: the
    /// binder's other uses are ordinary names and take the new spelling alone.
    spells_a_field: bool = false,
    /// A field rename expands shorthand without renaming its local binder.
    spells_a_binding: bool = false,
    /// Construction shorthand expands with `=`, while a pattern uses `:`.
    initializer: bool = false,

    /// By file and then by where in it, which is the order a reader reads them
    /// in -- and an order at all, which is what makes one input give one answer
    /// twice.
    fn before(_: void, a: Site, b: Site) bool {
        if (a.file != b.file) return a.file.index() < b.file.index();
        return a.span.start < b.span.start;
    }
};

/// The sites as the protocol names them, dropping every file no client can
/// open.
///
/// Grouped by file, which the ordering already did: a file's URI is resolved
/// once for the run rather than once per site, and the run's byte offsets are
/// converted in one pass over that file rather than one pass each.
fn locationsOf(
    gpa: std.mem.Allocator,
    io: std.Io,
    checked: *const Analysis,
    sites: []const Site,
    encoding: lsp.offsets.Encoding,
    root: []const u8,
) ![]const lsp.types.Location {
    var out: std.ArrayList(lsp.types.Location) = .empty;
    errdefer out.deinit(gpa);

    var from: usize = 0;
    while (from < sites.len) {
        const file = sites[from].file;
        var end = from;
        while (end < sites.len and sites[end].file == file) end += 1;
        const run = sites[from..end];
        from = end;

        const uri = try uri_mod.openable(gpa, io, checked, file, root) orelse continue;
        defer gpa.free(uri);

        const offsets = try gpa.alloc(u32, run.len * 2);
        defer gpa.free(offsets);
        for (run, 0..) |s, i| {
            offsets[i * 2] = s.span.start;
            offsets[i * 2 + 1] = s.span.end;
        }

        const text = checked.program.ast.partOfFile(file).?.source;
        const places = try positions.positionsOf(gpa, text, offsets, encoding);
        defer gpa.free(places);

        for (0..run.len) |i| try out.append(gpa, .{
            // One per location rather than one shared: a caller that releases
            // what it was handed releases each of these, and a caller holding
            // an arena is not asked to know which is which.
            .uri = try gpa.dupe(u8, uri),
            .range = .{ .start = places[i * 2], .end = places[i * 2 + 1] },
        });
    }
    return out.toOwnedSlice(gpa);
}

/// Releases what `forPosition` returned.
pub fn free(gpa: std.mem.Allocator, found: []const lsp.types.Location) void {
    for (found) |l| gpa.free(l.uri);
    gpa.free(found);
}

const local_program =
    \\fn twice(a: UInt8) -> UInt8 {
    \\    a + a
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let total: UInt8 = twice(1)
    \\    total + total
    \\}
    \\
;

/// Where a byte of a case's text sits, as the protocol names it.
fn at(text: []const u8, offset: usize) lsp.types.Position {
    return lsp.offsets.indexToPosition(text, offset, .@"utf-16");
}

/// What each answer names, as the text of the file it points into -- which is
/// the one reading that says a range covers the name and not merely somewhere
/// near it.
fn spelled(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    found: []const lsp.types.Location,
) ![]const []const u8 {
    const out = try gpa.alloc([]const u8, found.len);
    for (out, found) |*o, l| {
        o.* = "";
        var it = @import("publish.zig").files(&checked.program);
        while (it.next()) |file| {
            const entry = checked.table.get(file);
            if (!std.mem.endsWith(u8, l.uri, entry.path)) continue;
            o.* = lsp.offsets.rangeToSlice(entry.text, l.range, .@"utf-16");
        }
    }
    return out;
}

test "a name says every place it is used" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();

    const use = std.mem.lastIndexOf(u8, local_program, "total").?;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, use + 1), .@"utf-16", "", true, null)).?;
    defer free(gpa, found);

    // The `let` that declared it, and both halves of the sum below it.
    const names = try spelled(gpa, &checked, found);
    defer gpa.free(names);
    try testing.expectEqual(@as(usize, 3), names.len);
    for (names) |n| try testing.expectEqualStrings("total", n);
    try testing.expectEqual(@as(u32, 5), found[0].range.start.line);
    try testing.expectEqual(@as(u32, 6), found[1].range.start.line);
    try testing.expectEqual(@as(u32, 6), found[2].range.start.line);

    // A client asking for uses alone receives the same sites without the
    // declaration.
    const uses_only = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, use + 1), .@"utf-16", "", false, null)).?;
    defer free(gpa, uses_only);
    try testing.expectEqual(@as(usize, 2), uses_only.len);
    for (uses_only, found[1..]) |actual, expected| {
        try testing.expectEqualDeep(expected, actual);
    }
}

test "a name declared in a sibling file is used in both" {
    const gpa = testing.allocator;

    const main_text = "fn main() -> UInt8 {\n    size() + twice()\n}\n";
    const sizes_text = "fn size() -> UInt8 {\n    1\n}\n\nfn twice() -> UInt8 {\n    size() + size()\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/sizes.lin", .text = sizes_text },
    }, "app");
    defer checked.deinit();

    var wanted: FileId = checked.fileNamed("app/main.lin").?;
    for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, "app/main.lin")) wanted = f;
    }

    const call = std.mem.indexOf(u8, main_text, "size()").? + 1;
    const found = (try forPosition(gpa, testing.io, &checked, wanted, at(main_text, call), .@"utf-16", "", true, null)).?;
    defer free(gpa, found);

    var in_main: usize = 0;
    var in_sizes: usize = 0;
    for (found) |l| {
        if (std.mem.endsWith(u8, l.uri, "app/main.lin")) in_main += 1;
        if (std.mem.endsWith(u8, l.uri, "app/sizes.lin")) in_sizes += 1;
    }
    try testing.expectEqual(@as(usize, 1), in_main);
    // The declaration and the two calls written beside it.
    try testing.expectEqual(@as(usize, 3), in_sizes);
}

test "qualified trait references are indexed with their declaration" {
    const gpa = testing.allocator;
    const main_text =
        \\import protocol
        \\
        \\struct Item {}
        \\impl protocol.Marker for Item {}
        \\fn accepts[T: protocol.Marker](_value: T) {}
        \\
        \\fn main() -> UInt8 {
        \\    let item: Item = .{}
        \\    accepts(item)
        \\    0
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/protocol/protocol.lin", .text = "pub trait Marker {}\n" },
    }, "app");
    defer checked.deinit();

    var main_file: FileId = checked.fileNamed("app/main.lin").?;
    for (0..checked.table.count()) |i| {
        const file: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(file).path, "app/main.lin")) main_file = file;
    }
    const marker = std.mem.indexOf(u8, main_text, "Marker").? + 1;
    const found = (try forPosition(gpa, testing.io, &checked, main_file, at(main_text, marker), .@"utf-16", "", true, null)).?;
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 3), found.len);
}

test "a highlight says only what the file it was asked about holds" {
    const gpa = testing.allocator;

    const main_text = "fn main() -> UInt8 {\n    size() + twice()\n}\n";
    const sizes_text = "fn size() -> UInt8 {\n    1\n}\n\nfn twice() -> UInt8 {\n    size() + size()\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/sizes.lin", .text = sizes_text },
    }, "app");
    defer checked.deinit();

    var wanted: FileId = checked.fileNamed("app/main.lin").?;
    for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, "app/main.lin")) wanted = f;
    }

    const call = std.mem.indexOf(u8, main_text, "size()").? + 1;
    const found = (try forPosition(gpa, testing.io, &checked, wanted, at(main_text, call), .@"utf-16", "", true, wanted)).?;
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expect(std.mem.endsWith(u8, found[0].uri, "app/main.lin"));
}

test "a name used nowhere is used only where it was declared" {
    const gpa = testing.allocator;

    // Deliberately unused, which the language spells with a leading `_`.
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

    const declared = std.mem.indexOf(u8, text, "_spare").?;
    const with = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared + 1), .@"utf-16", "", true, null)).?;
    defer free(gpa, with);
    try testing.expectEqual(@as(usize, 1), with.len);

    const without = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared + 1), .@"utf-16", "", false, null)).?;
    defer free(gpa, without);
    try testing.expectEqual(@as(usize, 0), without.len);
}

/// A type written everywhere a type can be written: as a return, as an `impl`
/// head, as an annotation, as a type argument, and as the receiver of a member
/// of it. Only the last of those is an expression.
const written_program =
    \\struct Point {
    \\    x: UInt8,
    \\}
    \\
    \\struct Cell[T] {
    \\    v: T,
    \\}
    \\
    \\impl Point {
    \\    fn zero() -> Point {
    \\        .{ x = 0 }
    \\    }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let p: Point = Point.zero()
    \\    let c: Cell[Point] = .{ v = p }
    \\    c.v.x
    \\}
    \\
;

test "a type says every place it is written" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = written_program },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, written_program, "Point").?;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(written_program, declared + 1), .@"utf-16", "", true, null)).?;
    defer free(gpa, found);

    const names = try spelled(gpa, &checked, found);
    defer gpa.free(names);
    for (names) |n| try testing.expectEqualStrings("Point", n);

    // The declaration, the `impl` head, the return it carries, the annotation
    // on `p`, the call written through it, and the argument to `Cell`.
    try testing.expectEqual(@as(usize, 6), names.len);
    const lines = [_]u32{ 0, 8, 9, 15, 15, 16 };
    for (found, lines) |l, line| try testing.expectEqual(line, l.range.start.line);
}

/// A match arm's binder, which the resolver declares and points its own
/// `name_ref` at: one token that is both the declaration and an expression
/// reaching it.
const binder_program =
    \\enum Held { Some(UInt8), Empty }
    \\
    \\fn main() -> UInt8 {
    \\    match Held.Some(1) {
    \\        Some(n) => n,
    \\        Empty => 0,
    \\    }
    \\}
    \\
;

test "a name written once is answered once" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = binder_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, binder_program, "Some(n)").? + 5;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(binder_program, declared), .@"utf-16", "", true, null)).?;
    defer free(gpa, found);

    // The binder and the one use of it. The binder is declared at the token an
    // expression reaching it is written at, so a list that reported each of
    // those separately would name one place twice -- and a client applying an
    // edit list would write the replacement over itself.
    const names = try spelled(gpa, &checked, found);
    defer gpa.free(names);
    try testing.expectEqual(@as(usize, 2), names.len);
    for (names) |n| try testing.expectEqualStrings("n", n);
    for (found[1..], found[0 .. found.len - 1]) |after, before| {
        try testing.expect(!std.meta.eql(after.range, before.range));
    }
}

test "a qualified variant is a use of the enum, at the enum's own name" {
    const gpa = testing.allocator;

    // `Shade.Dim` reaches the enum: which variant was selected is the
    // checker's question, and the name the expression settles on is `Shade`.
    // So the site is the token spelling `Shade`, and a reader shown `Dim`
    // would be shown a name this answer does not speak for.
    const text =
        \\enum Shade {
        \\    Dim,
        \\    Bright,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    match read Shade.Dim {
        \\        Dim => 1,
        \\        Bright => 2,
        \\    }
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "Shade").?;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared + 1), .@"utf-16", "", true, null)).?;
    defer free(gpa, found);

    const names = try spelled(gpa, &checked, found);
    defer gpa.free(names);
    for (names) |n| try testing.expectEqualStrings("Shade", n);

    // The `enum` that declared it and the one selection written through it.
    try testing.expectEqual(@as(usize, 2), names.len);
}

test "a trait says every place it is written" {
    const gpa = testing.allocator;

    // A bound and an `impl` header are the two places a trait is named outside
    // an expression, and neither is one.
    const text =
        \\trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\
        \\struct Coins {
        \\    count: UInt8,
        \\}
        \\
        \\impl Measure for Coins {
        \\    fn of(x: Self) -> UInt8 {
        \\        x.count
        \\    }
        \\}
        \\
        \\fn total[T: Measure](a: T) -> UInt8 {
        \\    Measure.of(a)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let c: Coins = .{ count = 4 }
        \\    total(c)
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "Measure").?;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared + 1), .@"utf-16", "", true, null)).?;
    defer free(gpa, found);

    const names = try spelled(gpa, &checked, found);
    defer gpa.free(names);
    for (names) |n| try testing.expectEqualStrings("Measure", n);

    // The `trait` that declared it, the `impl` header, the bound on `T`, and
    // the call written through it.
    try testing.expectEqual(@as(usize, 4), names.len);
    const lines = [_]u32{ 0, 8, 14, 15 };
    for (found, lines) |l, line| try testing.expectEqual(line, l.range.start.line);
}

test "a module says every place it is written" {
    const gpa = testing.allocator;

    // A `use` path names a module with a token rather than an expression, and
    // the module is the same one the qualified call below reaches.
    const main_text =
        \\import sizes
        \\
        \\use sizes.Width
        \\
        \\fn main() -> UInt8 {
        \\    let w: Width = .{ of = 2 }
        \\    sizes.twice(w.of)
        \\}
        \\
    ;
    const sizes_text =
        \\pub struct Width {
        \\    of: UInt8,
        \\}
        \\
        \\pub fn twice(n: UInt8) -> UInt8 {
        \\    n * 2
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/sizes/sizes.lin", .text = sizes_text },
        .{ .path = "app/sizes/linea.json", .text = "{}\n" },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const wanted = checked.fileNamed("app/main.lin").?;
    const path = std.mem.indexOf(u8, main_text, "use sizes").? + 4;
    const found = (try forPosition(gpa, testing.io, &checked, wanted, at(main_text, path + 1), .@"utf-16", "", true, null)).?;
    defer free(gpa, found);

    const names = try spelled(gpa, &checked, found);
    defer gpa.free(names);
    for (names) |n| try testing.expectEqualStrings("sizes", n);

    // The `import` that bound it, the `use` path, and the qualified call.
    try testing.expectEqual(@as(usize, 3), names.len);
    const lines = [_]u32{ 0, 2, 6 };
    for (found, lines) |l, line| try testing.expectEqual(line, l.range.start.line);
}

/// One trait operation, called both ways: `Measure.of(a, 4)` writes out what
/// `b.of(1)` spells with a dot, and the tree keeps the spelling the programmer
/// chose.
const both_spellings =
    \\struct Account {
    \\    balance: UInt8,
    \\}
    \\
    \\trait Measure {
    \\    fn of(x: Self, since: UInt8) -> UInt8
    \\}
    \\
    \\impl Measure for Account {
    \\    fn of(x: Self, since: UInt8) -> UInt8 {
    \\        x.balance + since
    \\    }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let a: Account = .{ balance = 1 }
    \\    let b: Account = .{ balance = 2 }
    \\    Measure.of(a, 4) + b.of(1)
    \\}
    \\
;

const derived_operation =
    \\trait Structural {
    \\    fn value(self: Self) -> UInt8
    \\}
    \\
    \\template impl Structural {
    \\    fn value(_self: Self) -> UInt8 { 7 }
    \\}
    \\
    \\@derive(Structural)
    \\struct Mark {
    \\    value: UInt8,
    \\}
    \\
    \\
    \\fn main() -> UInt8 {
    \\    let mark: Mark = .{ value = 1 }
    \\    Structural.value(mark)
    \\}
    \\
;

/// One source spelling every structural derive name shape. Shared by the LSP
/// capability tests so each asks about the same program rather than a nearby
/// syntax assembled independently.
pub const structural_derive_source =
    \\trait Inspect[phantom A] {}
    \\trait Marker[phantom A] {}
    \\trait Lookup[phantom A] {}
    \\trait Project {
    \\    type Item
    \\}
    \\
    \\template impl Inspect where reflect.components: Lookup[UInt64] {
    \\}
    \\
    \\template impl Marker {}
    \\
    \\struct Box[T] { value: T }
    \\struct Solo {}
    \\
    \\derive[T: Linear + Project + Lookup[UInt64]] (
    \\    Inspect[UInt64],
    \\    Marker[T],
    \\) for Box[T] where
    \\    T.Item: Lookup[UInt64],
    \\
    \\derive (
    \\    Marker[UInt64],
    \\) for Solo
    \\
    \\trait Plain {
    \\    fn value(self: Self) -> UInt8
    \\}
    \\template impl Plain {
    \\    fn value(_self: Self) -> UInt8 { 1 }
    \\}
    \\struct Generated {}
    \\derive (
    \\    Plain,
    \\) for Generated
    \\
    \\fn main() -> UInt8 {
    \\    let _box: Box[UInt64] = .{ value = 1 }
    \\    0
    \\}
    \\
;

test "grouped derive references stay in source" {
    const gpa = testing.allocator;
    const text = structural_derive_source;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(checked.semantics.expanded.generated_sources.buffers.len > 0);

    var generated_plain = false;
    for (checked.semantics.expanded.generated_sources.buffers) |generated| {
        generated_plain = generated_plain or std.mem.indexOf(u8, generated, "impl Plain for Generated") != null;
    }
    try testing.expect(generated_plain);

    var grouped_plain = false;
    for (0..checked.program.ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (checked.program.ast.declTag(d) != .derive_impl) continue;
        if (!std.mem.eql(u8, checked.program.ast.tokenText(checked.program.ast.declName(d)), "Generated")) continue;
        grouped_plain = checked.program.ast.deriveIsGrouped(d);
    }
    try testing.expect(grouped_plain);

    const Case = struct {
        cursor: []const u8,
        within: usize = 0,
        spelling: []const u8,
        count: usize,
    };
    const cases = [_]Case{
        .{ .cursor = "    Inspect[UInt64]", .within = 5, .spelling = "Inspect", .count = 3 },
        .{ .cursor = "    Marker[T]", .within = 5, .spelling = "Marker", .count = 4 },
        .{ .cursor = "reflect.components: Lookup", .within = 21, .spelling = "Lookup", .count = 4 },
        .{ .cursor = ") for Box[T]", .within = 7, .spelling = "Box", .count = 3 },
        .{ .cursor = ") for Box[T]", .within = 10, .spelling = "T", .count = 4 },
        .{ .cursor = "T.Item: Lookup", .within = 2, .spelling = "Item", .count = 2 },
        .{ .cursor = "    Plain,", .within = 5, .spelling = "Plain", .count = 3 },
    };

    for (cases) |case| {
        const cursor = std.mem.indexOf(u8, text, case.cursor).? + case.within;
        const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, cursor), .@"utf-16", "", true, null)).?;
        defer free(gpa, found);
        try testing.expectEqual(case.count, found.len);
        const names = try spelled(gpa, &checked, found);
        defer gpa.free(names);
        for (names) |name| try testing.expectEqualStrings(case.spelling, name);
        for (found) |location| try testing.expect(std.mem.endsWith(u8, location.uri, "main.lin"));
    }

    const primitive = std.mem.indexOf(u8, text, "reflect.components: Lookup[UInt64]").? + 28;
    const primitive_refs = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, primitive), .@"utf-16", "", true, null)).?;
    defer free(gpa, primitive_refs);
    var source_spellings: usize = 0;
    for (primitive_refs) |location| {
        if (std.mem.endsWith(u8, location.uri, "main.lin")) source_spellings += 1;
    }
    try testing.expectEqual(@as(usize, 6), source_spellings);
}

test "references omit a generated derived member location" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = derived_operation }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const signature = std.mem.indexOf(u8, derived_operation, "fn value(self: Self) -> UInt8\n").? + 3;
    const found = (try forPosition(
        gpa,
        testing.io,
        &checked,
        checked.fileNamed("main.lin").?,
        at(derived_operation, signature),
        .@"utf-16",
        "",
        true,
        null,
    )).?;
    defer free(gpa, found);

    const names = try spelled(gpa, &checked, found);
    defer gpa.free(names);
    try testing.expectEqual(@as(usize, 2), names.len);
    for (names) |name| try testing.expectEqualStrings("value", name);
}

test "a call written with a dot is a use of what the call written out uses" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = both_spellings },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    // The operation the trait declares, asked about at the two spellings of one
    // call. A list that held one and not the other would say the dot is a
    // different name.
    const dotted = std.mem.indexOf(u8, both_spellings, "b.of(1)").? + 2;
    const written = std.mem.indexOf(u8, both_spellings, "Measure.of(a, 4)").? + 8;

    const from_dot = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(both_spellings, dotted), .@"utf-16", "", true, null)).?;
    defer free(gpa, from_dot);
    const from_written = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(both_spellings, written), .@"utf-16", "", true, null)).?;
    defer free(gpa, from_written);

    // The signature the trait declares, the member supplying it, and both calls
    // written through it.
    const names = try spelled(gpa, &checked, from_dot);
    defer gpa.free(names);
    try testing.expectEqual(@as(usize, 4), names.len);
    for (names) |n| try testing.expectEqualStrings("of", n);
    const lines = [_]u32{ 5, 9, 17, 17 };
    for (from_dot, lines) |l, line| try testing.expectEqual(line, l.range.start.line);

    try testing.expectEqual(from_written.len, from_dot.len);
    for (from_written, from_dot) |a, b| try testing.expectEqual(a.range, b.range);
}

/// One trait operation supplied twice, so the name is written in two `impl`
/// blocks as well as in the trait.
const two_implementations =
    \\struct Account {
    \\    balance: UInt8,
    \\}
    \\
    \\struct Weight {
    \\    grams: UInt8,
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
    \\impl Measure for Weight {
    \\    fn of(x: Self) -> UInt8 {
    \\        x.grams
    \\    }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let a: Account = .{ balance = 1 }
    \\    let w: Weight = .{ grams = 2 }
    \\    a.of() + w.of()
    \\}
    \\
;

test "a trait operation is used wherever it is supplied" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = two_implementations },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    // The signature, both members supplying it, and both calls. Every one of
    // them is a place this one name is written, and each answers for all of
    // them: a member is not a second name that happens to be spelled the same.
    const signature = std.mem.indexOf(u8, two_implementations, "fn of(x: Self) -> UInt8\n").? + 3;
    const first = std.mem.indexOf(u8, two_implementations, "fn of(x: Self) -> UInt8 {").? + 3;
    const second = std.mem.lastIndexOf(u8, two_implementations, "fn of(x: Self) -> UInt8 {").? + 3;
    const dotted = std.mem.indexOf(u8, two_implementations, "a.of()").? + 2;
    const other = std.mem.indexOf(u8, two_implementations, "w.of()").? + 2;

    for ([_]usize{ signature, first, second, dotted, other }) |offset| {
        const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(two_implementations, offset), .@"utf-16", "", true, null)).?;
        defer free(gpa, found);

        const names = try spelled(gpa, &checked, found);
        defer gpa.free(names);
        for (names) |n| try testing.expectEqualStrings("of", n);

        try testing.expectEqual(@as(usize, 5), names.len);
        const lines = [_]u32{ 9, 13, 19, 27, 27 };
        for (found, lines) |l, line| try testing.expectEqual(line, l.range.start.line);
    }
}

test "reference families remain unique after malformed implementation recovery" {
    const gpa = testing.allocator;
    const text =
        "pub trait Score {\n" ++
        "    fn score(x: Self) -> UInt8\n" ++
        "    fn score(x: Self) -> UInt8\n" ++
        "}\n" ++
        "pub struct A { value: UInt8 }\n" ++
        "pub struct B { value: UInt8 }\n" ++
        "impl Score for A { impl Score for B {\n" ++
        "    fn score(x: Self) -> UInt8 { x.value }\n" ++
        "} }\n" ++
        "impl Score for B { fn score(x: Self) -> UInt8 { x.value } }\n" ++
        "fn main() -> UInt8 { 0 }\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(checked.sink.hasErrors());

    const first = std.mem.indexOf(u8, text, "fn score").? + 3;
    const second = std.mem.indexOfPos(u8, text, first, "fn score").? + 3;
    const recovered = std.mem.indexOf(u8, text, "fn score(x: Self) -> UInt8 {").? + 3;
    const last = std.mem.lastIndexOf(u8, text, "fn score").? + 3;
    try testing.expectEqual(BindingId.none, namedAt(&checked, checked.fileNamed("main.lin").?, at(text, second), .@"utf-16"));
    for ([_]usize{ first, recovered, last }) |offset| {
        const named = namedAt(&checked, checked.fileNamed("main.lin").?, at(text, offset), .@"utf-16");
        try testing.expect(named != .none);
        const family = try spelledAlike(gpa, &checked, named);
        defer gpa.free(family);
        const expected: []const usize = if (offset == first) &.{ first, recovered, last } else &.{ recovered, last };
        try testing.expectEqual(expected.len, family.len);
        try testing.expectEqual(named, family[0]);
        for (expected) |expected_offset| {
            var count: usize = 0;
            for (family) |binding| {
                const token = checked.semantics.res.declaringToken(binding);
                if (checked.program.ast.tokenSpan(token).start == expected_offset) count += 1;
            }
            try testing.expectEqual(@as(usize, 1), count);
        }
    }
}

test "reference families preserve all names through allocation failures" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = two_implementations },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const offsets = [_]usize{
        std.mem.indexOf(u8, two_implementations, "fn of(x: Self) -> UInt8\n").? + 3,
        std.mem.indexOf(u8, two_implementations, "fn of(x: Self) -> UInt8 {").? + 3,
        std.mem.lastIndexOf(u8, two_implementations, "fn of(x: Self) -> UInt8 {").? + 3,
    };
    var expected: [3]BindingId = undefined;
    for (offsets, &expected) |offset, *binding| {
        binding.* = namedAt(&checked, checked.fileNamed("main.lin").?, at(two_implementations, offset), .@"utf-16");
        try testing.expect(binding.* != .none);
    }

    const Query = struct {
        fn check(allocator: std.mem.Allocator, analysis: *const Analysis, names: [3]BindingId, queried: BindingId) !void {
            const family = try spelledAlike(allocator, analysis, queried);
            defer allocator.free(family);
            try testing.expectEqual(@as(usize, 3), family.len);
            try testing.expectEqual(queried, family[0]);
            for (names) |name| {
                var count: usize = 0;
                for (family) |binding| {
                    if (binding == name) count += 1;
                }
                try testing.expectEqual(@as(usize, 1), count);
            }
        }
    };
    for (expected) |queried| {
        try testing.checkAllAllocationFailures(gpa, Query.check, .{ &checked, expected, queried });
    }
}

test "a trait operation family excludes unrelated identical spellings across files" {
    const gpa = testing.allocator;
    const main_text =
        "pub trait Score { fn score(x: Self) -> UInt8 }\n" ++
        "pub trait Other { fn score(x: Self) -> UInt8 }\n" ++
        "fn main() -> UInt8 { 0 }\n";
    const work_text =
        "pub struct A { value: UInt8 }\n" ++
        "pub struct B { value: UInt8 }\n" ++
        "impl Score for A { fn score(x: Self) -> UInt8 { x.value } }\n" ++
        "impl Score for B { fn score(x: Self) -> UInt8 { x.value } }\n" ++
        "impl Other for A { fn score(x: Self) -> UInt8 { x.value } }\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/work.lin", .text = work_text },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const main_file = checked.fileNamed("app/main.lin").?;
    const work_file = checked.fileNamed("app/work.lin").?;
    const signature = std.mem.indexOf(u8, main_text, "score").?;
    const supplier = std.mem.indexOf(u8, work_text, "score").?;
    for ([_]struct { file: FileId, text: []const u8, offset: usize }{
        .{ .file = main_file, .text = main_text, .offset = signature },
        .{ .file = work_file, .text = work_text, .offset = supplier },
    }) |query| {
        const found = (try forPosition(gpa, testing.io, &checked, query.file, at(query.text, query.offset), .@"utf-16", "", true, null)).?;
        defer free(gpa, found);
        try testing.expectEqual(@as(usize, 3), found.len);
        try testing.expect(std.mem.endsWith(u8, found[0].uri, "app/main.lin"));
        try testing.expectEqual(@as(u32, 0), found[0].range.start.line);
        for (found[1..], [_]u32{ 2, 3 }) |location, line| {
            try testing.expect(std.mem.endsWith(u8, location.uri, "app/work.lin"));
            try testing.expectEqual(line, location.range.start.line);
        }
    }

    const highlighted = (try forPosition(gpa, testing.io, &checked, main_file, at(main_text, signature), .@"utf-16", "", true, main_file)).?;
    defer free(gpa, highlighted);
    try testing.expectEqual(@as(usize, 1), highlighted.len);
    try testing.expectEqual(@as(u32, 0), highlighted[0].range.start.line);
}

test "a cursor on what names nothing is used nowhere" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();

    const literal = std.mem.indexOf(u8, local_program, "twice(1)").? + 6;
    try testing.expectEqual(
        @as(?[]const lsp.types.Location, null),
        try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, literal), .@"utf-16", "", true, null),
    );
}
