const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const positions = @import("positions.zig");
const references = @import("references.zig");
const uri_mod = @import("uri.zig");
const isIdentifier = @import("../lexer/lexer.zig").isIdentifier;
const TokenId = @import("../lexer/token.zig").TokenId;
const resolve = @import("../sema/resolve.zig");
const BindingId = resolve.BindingId;
const Kind = resolve.Kind;
const DeclId = @import("../syntax/node.zig").DeclId;
const FileId = @import("../support/source.zig").FileId;
const name_case = @import("../support/name_case.zig");

/// Why a rename was refused.
///
/// Named one by one rather than answered as a single refusal, because they
/// have nothing in common for a reader: most say the name is not the
/// programmer's to change, and one says the new spelling is not a name. A
/// client shows the message, and "cannot rename" leaves a reader guessing
/// which.
///
/// Each of these is reached by some request. A name here that no input could
/// produce would be a promise about what the server checks, kept by nothing
/// and tested by nothing.
pub const Refused = error{
    APrimitiveIsNotRenameable,
    AModuleIsNamedByItsDirectory,
    AReExportedNameIsSpelledByWhatItNames,
    ANewNameMustBeAnIdentifier,
    ANewNameMustStartInItsKindsCase,
    ALibraryNameIsNotThisWorkspaceToChange,
    AnEntryPointIsNamedByItsSpelling,
    ACallableInterfaceRelationIsNotRenameable,
    AGeneratedMemberIsNotRenameable,
};

/// Return edits for the name under the cursor, or null if no name is selected.
///
/// Include every use in the current analysis, including public declarations.
/// The analysis is rooted at the file the editor opened; uses in other
/// programs importing the same module are outside its scope.
///
/// Refuse primitive names without source declarations, generated members,
/// modules whose rename requires moving a directory, re-exports whose spelling
/// belongs to another module, and the runtime entry point. The new name must
/// lex as one identifier and cannot be a reserved word. Refuse library names
/// and trait relations that would require edits to library declarations.
/// Inactive template interfaces return null. Callable interfaces whose uses
/// cannot be paired safely are refused.
///
/// Expand shorthand pattern binders when needed: renaming `f` in `S { f }`
/// writes `S { f: new_name }`, preserving the field name.
/// Callback implementation binders are independent of contextual labels;
/// renaming either one leaves the other unchanged.
///
/// Rename a trait operation together with its supplying implementation members.
/// Parameter renames include the signature, the corresponding parameter in
/// each implementation, and named arguments. `references.spelledAlike` supplies
/// these related bindings so rename and references use the same relation.
///
/// For related declarations, preserve each site's leading `_` when the new
/// name has none. The marker records deliberate non-use in that implementation
/// and prevents an N-Unused error after renaming. For a single declaration,
/// replace the complete spelling, allowing `_spare` to become `spare`.
///
/// Order edits by module file order and source position for deterministic
/// responses. Clients can apply each file's edits from last to first to keep
/// replacement lengths from invalidating later source ranges.
///
/// Cost depends on the related names, their uses and the affected files:
/// one binding lookup, traversal of the related-name record and reverse indexes,
/// sorting the selected sites, traversal of template-member plans and their
/// parameters, one scan of each affected file's bytes, and one read of each
/// affected library file.
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
    new_name: []const u8,
) !?lsp.types.WorkspaceEdit {
    return forPositionReporting(gpa, io, checked, file, position, encoding, root, new_name, null);
}

/// As `forPosition`, and where a new name is refused for its case, writes the
/// kind it was held to into `refused_kind`: the one answer a server words the
/// refusal from, rather than finding the declaration again.
pub fn forPositionReporting(
    gpa: std.mem.Allocator,
    io: std.Io,
    checked: *const Analysis,
    file: FileId,
    position: lsp.types.Position,
    encoding: lsp.offsets.Encoding,
    root: []const u8,
    new_name: []const u8,
    refused_kind: ?*?name_case.Kind,
) !?lsp.types.WorkspaceEdit {
    const named = references.namedAt(checked, file, position, encoding);
    if (named == BindingId.none) {
        const field = references.sourceNameAt(checked, file, position, encoding);
        if (field == .none) return null;
        if (checked.uses.sourceNameIsUnpairedInterface(field)) return Refused.ACallableInterfaceRelationIsNotRenameable;
        if (checked.library[checked.program.ast.fileOf(field).index()]) return Refused.ALibraryNameIsNotThisWorkspaceToChange;
        if (!try isIdentifier(gpa, new_name)) return Refused.ANewNameMustBeAnIdentifier;
        if (breaksCase(checked.semantics.res.nameKindAt(field), new_name)) |kind| {
            if (refused_kind) |out| out.* = kind;
            return Refused.ANewNameMustStartInItsKindsCase;
        }
        const sites = try references.sourceNameSites(gpa, checked, field, true, null);
        defer gpa.free(sites);
        return try editsAtSites(gpa, io, checked, sites, encoding, root, new_name, false);
    }

    // The binding introduced at no token, which is the one recognition
    // `definition` refuses to point at: nothing in source declares a primitive,
    // so there is no declaration to rewrite.
    const declared_token = checked.semantics.res.declaringToken(named);
    if (declared_token == TokenId.none) {
        return Refused.APrimitiveIsNotRenameable;
    }
    if (references.hasGeneratedSupplier(checked, named)) {
        return Refused.AGeneratedMemberIsNotRenameable;
    }
    // Template interfaces remain queryable in source but are not active. The
    // declaring token makes a parameter reference answer like its declaration;
    // the resolver's plan identifies the interface without enclosing locals.
    if (checked.semantics.expanded.isTemplateInterfaceToken(declared_token)) return null;
    if (checked.semantics.res.kindOf(named) == .parameter) {
        switch (checked.semantics.res.parameterOwner(named)) {
            .closure => |closure| if (checked.semantics.res.unpaired_template_closures.contains(closure))
                return Refused.ACallableInterfaceRelationIsNotRenameable,
            .declaration => {},
        }
    }

    // Every name this one rename has to change, which for all but a trait's
    // operation is the one under the cursor. Asked of `references`, because the
    // names a rename edits and the names a reader is shown are one answer: a
    // second reading here would rewrite a byte no highlight lit up.
    const spelled_alike = try references.spelledAlike(gpa, checked, named);
    defer gpa.free(spelled_alike);

    // Before the rest, because a library name is not this workspace's to
    // change whatever else is true of it, and because the alternative is a
    // rename reaching out of the project the editor opened and rewriting the
    // source the compiler was built from.
    //
    // Asked of every name that must change together: an implementation of a
    // library trait is this workspace's, and the signature it supplies is not,
    // so editing the member alone would leave it supplying nothing.
    for (spelled_alike) |b| {
        const declared_at = checked.semantics.res.declaringToken(b);
        if (checked.library[checked.program.ast.partOf(declared_at).file.index()]) {
            return Refused.ALibraryNameIsNotThisWorkspaceToChange;
        }
    }
    if (namesADirectory(checked.semantics.res.kindOf(named))) {
        return Refused.AModuleIsNamedByItsDirectory;
    }
    // A `use` binds the name its path ends with and offers no other spelling,
    // so the token that declares the re-export is the token naming what it
    // re-exports. Rewriting it asks the other module for a declaration of a
    // name it does not have.
    if (checked.semantics.res.isReExport(named)) {
        return Refused.AReExportedNameIsSpelledByWhatItNames;
    }
    // Which declaration the runtime calls, read from where the rule that there
    // is exactly one of them was enforced. Asking which name is the entry
    // point's would be that rule written a second time, and the two would
    // disagree the first time the spelling stopped being the whole of it.
    if (checked.semantics.res.entry != DeclId.none and
        checked.semantics.res.entry == checked.semantics.res.declIfDeclared(named))
    {
        return Refused.AnEntryPointIsNamedByItsSpelling;
    }
    if (!try isIdentifier(gpa, new_name)) return Refused.ANewNameMustBeAnIdentifier;
    if (breaksCase(recordedKind(checked, spelled_alike), new_name)) |kind| {
        if (refused_kind) |out| out.* = kind;
        return Refused.ANewNameMustStartInItsKindsCase;
    }

    const sites = try references.sitesOf(gpa, checked, spelled_alike, true, null);
    defer gpa.free(sites);

    return try editsAtSites(gpa, io, checked, sites, encoding, root, new_name, spelled_alike.len > 1);
}

/// The kind whose case `new_name` breaks, or null where it keeps the case of
/// `kind` or has no case to keep.
fn breaksCase(kind: ?name_case.Kind, new_name: []const u8) ?name_case.Kind {
    const k = kind orelse return null;
    const new_case = name_case.of(new_name) orelse return null;
    return if (k.case() == new_case) null else k;
}

/// The kind resolution recorded for a set of declarations spelled alike.
///
/// Read from what resolution recorded when it held each declaring token to
/// [N-Case], so a rename and the diagnostic ask one question once. A trait
/// implementation's member restates its trait's name and records no kind of
/// its own, so every declaration spelled alike is asked, and the first that
/// records one answers.
fn recordedKind(checked: *const Analysis, alike: []const BindingId) ?name_case.Kind {
    const res = &checked.semantics.res;
    for (alike) |b| {
        if (res.nameKindAt(res.declaringToken(b))) |k| return k;
    }
    return null;
}

/// Why a rename to `new_name` was refused for the case of `kind`, as the
/// diagnostic would say it: the kind, and the respelling to write instead.
/// The server shows it beside `ANewNameMustStartInItsKindsCase`, which is all
/// a refusal can carry.
pub fn caseRefusal(gpa: std.mem.Allocator, kind: name_case.Kind, new_name: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    return switch (try resolve.respelling(arena.allocator(), new_name, kind)) {
        .offered => |respelled| try std.fmt.allocPrint(gpa, "{s} start with {s}: rename it `{s}`", .{ kind.plural(), kind.case().describe(), respelled }),
        .unusable => |respelled| try std.fmt.allocPrint(gpa, "{s} start with {s}: `{s}` is not a name a program declares", .{ kind.plural(), kind.case().describe(), respelled }),
    };
}

fn editsAtSites(gpa: std.mem.Allocator, io: std.Io, checked: *const Analysis, sites: []const references.Site, encoding: lsp.offsets.Encoding, root: []const u8, new_name: []const u8, shared: bool) !lsp.types.WorkspaceEdit {
    var changes: Changes = .empty;
    errdefer release(gpa, &changes);

    // Grouped by file, which the ordering already did: a file's URI is
    // resolved once for the run and the run's offsets are converted in one
    // pass over that file. Inserted in that order too, so the answer is the
    // same object twice for one request rather than whatever a table's
    // iteration happened to hold.
    var from: usize = 0;
    while (from < sites.len) {
        const in = sites[from].file;
        var end = from;
        while (end < sites.len and sites[end].file == in) end += 1;
        const run = sites[from..end];
        from = end;

        // The one file this workspace cannot offer is the library's, and the
        // refusal above already established that this name is not the
        // library's -- nothing the library declares is edited here, and
        // nothing it holds names anything this workspace declared. So the same
        // fact answers from this side, rather than a second refusal saying it
        // in other words.
        const uri = try uri_mod.openable(gpa, io, checked, in, root) orelse
            return Refused.ALibraryNameIsNotThisWorkspaceToChange;
        errdefer gpa.free(uri);

        const offsets = try gpa.alloc(u32, run.len * 2);
        defer gpa.free(offsets);
        for (run, 0..) |s, i| {
            offsets[i * 2] = s.span.start;
            offsets[i * 2 + 1] = s.span.end;
        }

        const text = checked.program.ast.partOfFile(in).?.source;
        const places = try positions.positionsOf(gpa, text, offsets, encoding);
        defer gpa.free(places);

        const written = try gpa.alloc(lsp.types.TextEdit, run.len);
        errdefer gpa.free(written);
        var initialized: usize = 0;
        errdefer for (written[0..initialized]) |edit| gpa.free(edit.newText);
        for (written, run, 0..) |*w, site, i| {
            w.* = .{
                .range = .{ .start = places[i * 2], .end = places[i * 2 + 1] },
                .newText = try spelling(gpa, text[site.span.start..site.span.end], new_name, site, shared),
            };
            initialized += 1;
        }

        try changes.put(gpa, uri, written);
    }
    return .{ .changes = .{ .map = changes } };
}

/// What one site is written as: the new name, and whatever the bytes there say
/// about this place that the name does not carry.
///
/// The long form where the bytes name a field too: `S { f }` is `S { f: f }`
/// written short, so a binder renamed there is spelled out rather than replaced
/// -- replacing it renames the field with it and names a field the type does
/// not have.
///
/// And the `_` that marks a value deliberately unused, where the new name
/// brings none of its own -- but only while several declarations are being
/// edited together. One member of an `impl` marks a parameter its body ignores
/// while another uses it, and [N-Unused] admits no other spelling of the first;
/// the name under the marker is what the signature declares and what a call
/// writes, so the two halves move separately and only the name is the
/// programmer's to change. Where one declaration writes the name, the mark is
/// part of what the programmer asked to replace -- keeping it would make a
/// leading `_` something no rename can remove. A new name already marked is
/// written as it was given.
fn spelling(
    gpa: std.mem.Allocator,
    was: []const u8,
    new_name: []const u8,
    site: references.Site,
    /// Whether this site is one of several declarations the language holds to
    /// one spelling.
    shared: bool,
) ![]u8 {
    const marked = shared and
        std.mem.startsWith(u8, was, "_") and !std.mem.startsWith(u8, new_name, "_");
    const mark = if (marked) "_" else "";
    const separator = if (site.initializer) " = " else ": ";
    if (site.spells_a_binding) return std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ new_name, separator, was });
    if (site.spells_a_field) {
        return std.fmt.allocPrint(gpa, "{s}{s}{s}{s}", .{ was, separator, mark, new_name });
    }
    return std.fmt.allocPrint(gpa, "{s}{s}", .{ mark, new_name });
}

/// Whether this kind of name is the name of something the filesystem holds.
///
/// A module is a directory, so its name is that directory's name and every
/// path spelling it is spelling the directory. Rewriting those paths produces a
/// program importing a module that is not there, and the edit that would make
/// it true -- moving the directory -- is not one a `WorkspaceEdit` of text
/// changes carries.
///
/// Written over every kind rather than as a list of the ones that are refused,
/// so a kind added later has to say which side it is on instead of being
/// renamed by default.
fn namesADirectory(kind: Kind) bool {
    return switch (kind) {
        // A value's name, and a value is written where an expression is.
        .local, .parameter, .capture, .binder, .constant, .function => false,
        // A type and a trait are named in source and nowhere else. Every place
        // one is written -- as an expression, as an annotation, as a type
        // argument, as a bound, as an `impl` head -- is a site the reverse
        // index holds, so a rename of one reaches all of them.
        .declared_type, .builtin_type, .trait, .associated_type, .type_parameter, .type_alias => false,
        .module => true,
    };
}

/// What a document is edited to, by the URI a client opens it at.
const Changes = std.StringArrayHashMapUnmanaged([]const lsp.types.TextEdit);

/// Releases what `forPosition` returned.
pub fn free(gpa: std.mem.Allocator, edit: lsp.types.WorkspaceEdit) void {
    var changes = edit.changes orelse return;
    release(gpa, &changes.map);
}

fn release(gpa: std.mem.Allocator, changes: *Changes) void {
    var it = changes.iterator();
    while (it.next()) |entry| {
        for (entry.value_ptr.*) |e| gpa.free(e.newText);
        gpa.free(entry.value_ptr.*);
        gpa.free(entry.key_ptr.*);
    }
    changes.deinit(gpa);
}

/// One document's text with one document's edits applied.
///
/// What a client does with the answer, kept beside the answer: a case that
/// checks a rename has to apply it, and an applier written beside the case
/// would be a second opinion about what an edit means.
///
/// Applied from the last edit to the first, so no replacement moves a range
/// that has not been used yet. That the edits arrive in order is what makes it
/// sound, and it is why they are ordered.
pub fn applyTo(
    gpa: std.mem.Allocator,
    text: []const u8,
    edits: []const lsp.types.TextEdit,
    encoding: lsp.offsets.Encoding,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, text);

    var i = edits.len;
    while (i > 0) {
        i -= 1;
        const start = lsp.offsets.positionToIndex(text, edits[i].range.start, encoding);
        const end = lsp.offsets.positionToIndex(text, edits[i].range.end, encoding);
        try out.replaceRange(gpa, start, end - start, edits[i].newText);
    }
    return out.toOwnedSlice(gpa);
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

/// The edits the answer holds for the document whose path ends this way.
fn editsFor(edit: lsp.types.WorkspaceEdit, path: []const u8) []const lsp.types.TextEdit {
    var it = edit.changes.?.map.iterator();
    while (it.next()) |entry| {
        if (std.mem.endsWith(u8, entry.key_ptr.*, path)) return entry.value_ptr.*;
    }
    return &.{};
}

test "a name is changed everywhere it is used" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();

    const use = std.mem.lastIndexOf(u8, local_program, "total").?;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, use + 1), .@"utf-16", "", "sum")).?;
    defer free(gpa, edit);

    // The `let` that declared it, and both halves of the sum below it.
    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 3), edits.len);
    for (edits) |e| try testing.expectEqualStrings("sum", e.newText);

    var last: usize = 0;
    for (edits) |e| {
        const start = lsp.offsets.positionToIndex(local_program, e.range.start, .@"utf-16");
        try testing.expect(start >= last);
        last = lsp.offsets.positionToIndex(local_program, e.range.end, .@"utf-16");
    }

    const applied = try applyTo(gpa, local_program, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\fn twice(a: UInt8) -> UInt8 {
        \\    a + a
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let sum: UInt8 = twice(1)
        \\    sum + sum
        \\}
        \\
    , applied);
}

test "a lambda pattern's binder is renamed and its parenthesis is not a name" {
    const gpa = testing.allocator;
    const text =
        \\fn apply[F: fn(read pair: (UInt8, UInt8)) -> UInt8](pair: (UInt8, UInt8), check: F) -> UInt8 {
        \\    check(pair)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    apply((3, 4), |(left, right)| left + right)
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const binder = std.mem.indexOf(u8, text, "left").?;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, binder + 1), .@"utf-16", "", "near")).?;
    defer free(gpa, edit);
    const applied = try applyTo(gpa, text, editsFor(edit, "main.lin"), .@"utf-16");
    defer gpa.free(applied);
    try testing.expect(std.mem.indexOf(u8, applied, "|(near, right)| near + right") != null);

    const paren = std.mem.indexOf(u8, text, "|(").? + 1;
    try testing.expectEqual(@as(?lsp.types.WorkspaceEdit, null), try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, paren), .@"utf-16", "", "near"));
}

test "a qualified trait is renamed at every final component" {
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

    const main_file = checked.fileNamed("app/main.lin").?;
    const marker = std.mem.indexOf(u8, main_text, "Marker").? + 1;
    const edit = (try forPosition(gpa, testing.io, &checked, main_file, at(main_text, marker), .@"utf-16", "", "Label")).?;
    defer free(gpa, edit);

    try testing.expectEqual(@as(usize, 2), editsFor(edit, "app/main.lin").len);
    try testing.expectEqual(@as(usize, 1), editsFor(edit, "app/protocol/protocol.lin").len);
}

test "a selected function parameter is renamed independently of its structural interface" {
    const gpa = testing.allocator;
    const text =
        \\fn increment(value: UInt8) -> UInt8 { value }
        \\fn main() -> UInt8 {
        \\    let selected: fn(read value: UInt8) -> UInt8 = increment
        \\    selected(value: 2)
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "value: UInt8").?;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared + 1), .@"utf-16", "", "item")).?;
    defer free(gpa, edit);

    const applied = try applyTo(gpa, text, editsFor(edit, "main.lin"), .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\fn increment(item: UInt8) -> UInt8 { item }
        \\fn main() -> UInt8 {
        \\    let selected: fn(read value: UInt8) -> UInt8 = increment
        \\    selected(value: 2)
        \\}
        \\
    , applied);
}

test "generated generic template calls do not enter source rename analysis" {
    const gpa = testing.allocator;
    const text =
        \\trait Structural {
        \\    fn value[T: Copyable](self: Self, item: T) -> T where carries(item)
        \\}
        \\fn identity[T: Copyable](item: T) -> T { copy(item) }
        \\template impl Structural {
        \\    fn value[U: Copyable](_self: Self, item: U) -> U where carries(item) { identity(item) }
        \\}
        \\@derive(Structural)
        \\struct Box {}
        \\
        \\fn rename_me(item: UInt8) -> UInt8 { item }
        \\fn main() -> UInt8 {
        \\    let box: Box = .{}
        \\    let _ = Structural.value(box, UInt8(1))
        \\    rename_me(UInt8(2))
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const parameter = std.mem.indexOf(u8, text, "item: UInt8").?;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, parameter + 1), .@"utf-16", "", "byte")).?;
    defer free(gpa, edit);
    try testing.expectEqual(@as(usize, 2), editsFor(edit, "main.lin").len);
}

fn expectCheckedRename(gpa: std.mem.Allocator, checked: *const Analysis, text: []const u8, offset: usize, name: []const u8) !void {
    const edit = (try forPosition(gpa, testing.io, checked, checked.program.primaryFile(), at(text, offset), .@"utf-16", "", name)).?;
    defer free(gpa, edit);
    const edits = editsFor(edit, "main.lin");
    try testing.expect(edits.len >= 2);
    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
    defer renamed.deinit();
    try testing.expect(!renamed.sink.hasErrors());
}

test "borrow callback parameter rename keeps its own contract roots" {
    const gpa = testing.allocator;
    const text =
        \\fn observe(value: UInt8) -> borrow UInt8 where borrows(value) { borrow value }
        \\fn invoke(action: fn(read value: UInt8) -> borrow UInt8 where borrows(value), value: UInt8) -> borrow UInt8 where borrows(value) { action(value) }
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 7
        \\    let view = invoke(observe, number)
        \\    return *view
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const parameter = std.mem.indexOf(u8, text, "value: UInt8").?;
    try expectCheckedRename(gpa, &checked, text, parameter + 1, "item");
}

test "a callable-bound parameter is renamed independently of its interface" {
    const gpa = testing.allocator;
    const text =
        \\fn apply[F: fn(read value: UInt8) -> UInt8](f: F) -> UInt8 {
        \\    f(value: 1)
        \\}
        \\fn main() -> UInt8 {
        \\    apply(|value: UInt8| value)
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const lambda_parameter = std.mem.lastIndexOf(u8, text, "value: UInt8").?;
    try expectCheckedRename(gpa, &checked, text, lambda_parameter + 1, "item");
}

test "a parameter passed through a library callable bound is renamed locally" {
    const gpa = testing.allocator;
    const text =
        \\fn increment(sink item: Int64) -> Int64 { item + 1 }
        \\fn main() -> UInt8 {
        \\    let selected: fn(sink item: Int64) -> Int64 = increment
        \\    let incremented = (7..=7).map(selected)
        \\    let _found: Option[Int64] = incremented.find_map(|sink item| .Some(item))
        \\    return 0
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const parameter = std.mem.indexOf(u8, text, "item: Int64").?;
    try expectCheckedRename(gpa, &checked, text, parameter + 1, "value");
}

test "a parameter stored through a library implementation generic is renamed locally" {
    const gpa = testing.allocator;
    const text =
        \\import std.mem
        \\fn increment(value: UInt64) -> UInt64 { value + 1 }
        \\fn double(value: UInt64) -> UInt64 { value * 2 }
        \\fn main() -> UInt8 {
        \\    var functions: mem.Vec[fn(value: UInt64) -> UInt64, mem.SystemAllocator] = mem.Vec.new()
        \\    let operation: fn(value: UInt64) -> UInt64 = if true { increment } else { double }
        \\    match mem.Vec.push(&functions, operation) { Ok(_) => {}, Err(_) => panic("push failed") }
        \\    let selected = match mem.Vec.remove(&functions, 0) { Some(f) => f, None => panic("missing function") }
        \\    let answer = selected(7)
        \\    match mem.Vec.finish(functions) { Ok(_) => {}, Err(_) => panic("not empty") }
        \\    UInt8(answer)
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const parameter = std.mem.indexOf(u8, text, "value: UInt64").?;
    try expectCheckedRename(gpa, &checked, text, parameter + 1, "item");
}

test "a callable alias chain into a library generic preserves local parameter rename" {
    const gpa = testing.allocator;
    const text =
        \\fn increment(sink item: Int64) -> Int64 { item + 1 }
        \\fn main() -> UInt8 {
        \\    let selected: fn(sink item: Int64) -> Int64 = increment
        \\    let forwarded = selected
        \\    let incremented = (7..=7).map(forwarded)
        \\    let _found: Option[Int64] = incremented.find_map(|sink item| .Some(item))
        \\    return 0
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const parameter = std.mem.indexOf(u8, text, "item: Int64").?;
    try expectCheckedRename(gpa, &checked, text, parameter + 1, "value");
}

test "an unrelated same-signature library callable leaves function parameter rename local" {
    const gpa = testing.allocator;
    const text =
        \\fn local_increment(sink item: Int64) -> Int64 { item + 1 }
        \\fn library_increment(sink item: Int64) -> Int64 { item + 2 }
        \\fn main() -> UInt8 {
        \\    let local: fn(sink item: Int64) -> Int64 = local_increment
        \\    let _local_value = local(item: 1)
        \\    let library: fn(sink item: Int64) -> Int64 = library_increment
        \\    let incremented = (7..=7).map(library)
        \\    let _found: Option[Int64] = incremented.find_map(|sink item| .Some(item))
        \\    return 0
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const parameter = std.mem.indexOf(u8, text, "item: Int64").?;
    try expectCheckedRename(gpa, &checked, text, parameter + 1, "value");
}

test "an unrelated same-signature library callable leaves closure parameter rename local" {
    const gpa = testing.allocator;
    const text =
        \\fn main() -> UInt8 {
        \\    let local: fn(sink item: Int64) -> Int64 = |sink item: Int64| item + 1
        \\    let _local_value = local(item: 1)
        \\    let library: fn(sink item: Int64) -> Int64 = |sink item: Int64| item + 2
        \\    let incremented = (7..=7).map(library)
        \\    let _found: Option[Int64] = incremented.find_map(|sink item| .Some(item))
        \\    return 0
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const parameter = std.mem.indexOf(u8, text, "item: Int64| item + 1").?;
    try expectCheckedRename(gpa, &checked, text, parameter + 1, "value");
}

test "a name declared in a sibling file is changed in both" {
    const gpa = testing.allocator;

    const main_text = "fn main() -> UInt8 {\n    size() + twice()\n}\n";
    const sizes_text = "fn size() -> UInt8 {\n    1\n}\n\nfn twice() -> UInt8 {\n    size() + size()\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/sizes.lin", .text = sizes_text },
    }, "app");
    defer checked.deinit();

    const wanted = checked.fileNamed("app/main.lin").?;
    const call = std.mem.indexOf(u8, main_text, "size()").? + 1;
    const edit = (try forPosition(gpa, testing.io, &checked, wanted, at(main_text, call), .@"utf-16", "", "width")).?;
    defer free(gpa, edit);

    const in_main = editsFor(edit, "app/main.lin");
    const in_sizes = editsFor(edit, "app/sizes.lin");
    try testing.expectEqual(@as(usize, 1), in_main.len);
    // The declaration and the two calls written beside it.
    try testing.expectEqual(@as(usize, 3), in_sizes.len);

    const applied = try applyTo(gpa, sizes_text, in_sizes, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        "fn width() -> UInt8 {\n    1\n}\n\nfn twice() -> UInt8 {\n    width() + width()\n}\n",
        applied,
    );
}

test "a primitive is not the programmer's to rename" {
    const gpa = testing.allocator;

    // The one place a primitive is written as an expression: the receiver of a
    // member of it. `UInt8` is a name in every scope bound to no declaration,
    // so there is nothing to rewrite and every use of it belongs to someone
    // else.
    const text = "fn main() -> UInt8 {\n    UInt8.max\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const primitive = std.mem.lastIndexOf(u8, text, "UInt8").?;
    try testing.expectError(
        Refused.APrimitiveIsNotRenameable,
        forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, primitive + 1), .@"utf-16", "", "Byte"),
    );
}

test "a new name the lexer would not read as one is refused" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();

    const use = std.mem.lastIndexOf(u8, local_program, "total").?;
    // A reserved word, a digit where a name may not begin, two names, an
    // operator, and nothing at all. Each produces a program that does not
    // parse, and none of them is a rename anybody meant.
    for ([_][]const u8{ "let", "1st", "two names", "a+b", "", " total" }) |spelled| {
        try testing.expectError(
            Refused.ANewNameMustBeAnIdentifier,
            forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, use + 1), .@"utf-16", "", spelled),
        );
    }
}

test "a new name in the wrong case for its kind is refused, with the respelling" {
    const gpa = testing.allocator;
    const text =
        \\enum Signal {
        \\    Ready,
        \\    Idle,
        \\}
        \\
        \\struct Gauge {
        \\    level: UInt8,
        \\}
        \\
        \\fn total(signal: Signal, gauge: Gauge) -> UInt8 {
        \\    match read signal {
        \\        Ready => gauge.level,
        \\        Idle => 0,
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    total(Signal.Ready, Gauge { level = 1 })
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const cases = [_]struct { cursor: []const u8, new_name: []const u8, why: []const u8 }{
        .{ .cursor = "Ready,", .new_name = "ready", .why = "variants start with a capital letter: rename it `Ready`" },
        .{ .cursor = "total(signal", .new_name = "Total", .why = "functions start with a lowercase letter: rename it `total`" },
        .{ .cursor = "level: UInt8", .new_name = "Level", .why = "fields start with a lowercase letter: rename it `level`" },
        .{ .cursor = "Gauge {\n", .new_name = "gauge", .why = "types start with a capital letter: rename it `Gauge`" },
        .{ .cursor = "signal: Signal", .new_name = "For", .why = "parameters start with a lowercase letter: `for` is not a name a program declares" },
    };
    for (cases) |c| {
        const cursor = std.mem.indexOf(u8, text, c.cursor).?;
        var refused: ?name_case.Kind = null;
        try testing.expectError(
            Refused.ANewNameMustStartInItsKindsCase,
            forPositionReporting(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, cursor + 1), .@"utf-16", "", c.new_name, &refused),
        );
        const why = try caseRefusal(gpa, refused.?, c.new_name);
        defer gpa.free(why);
        try testing.expectEqualStrings(c.why, why);
    }

    // A name already in its kind's case is renamed as before.
    const kept = std.mem.indexOf(u8, text, "Ready,").?;
    var refused: ?name_case.Kind = null;
    const edit = (try forPositionReporting(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, kept + 1), .@"utf-16", "", "Waiting", &refused)).?;
    defer free(gpa, edit);
    try testing.expect(editsFor(edit, "main.lin").len > 0);
    try testing.expectEqual(@as(?name_case.Kind, null), refused);
}

test "a type is changed everywhere it is written" {
    const gpa = testing.allocator;

    // `Point` is written as a declaration, as an `impl` head, as a return, as
    // an annotation, as a type argument and as the receiver of a member of it.
    // Only the last is an expression, and a rename that changed only that one
    // would leave the rest naming something no longer there.
    const text =
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
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "Point").?;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared + 1), .@"utf-16", "", "Spot")).?;
    defer free(gpa, edit);

    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 6), edits.len);

    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\struct Spot {
        \\    x: UInt8,
        \\}
        \\
        \\struct Cell[T] {
        \\    v: T,
        \\}
        \\
        \\impl Spot {
        \\    fn zero() -> Spot {
        \\        .{ x = 0 }
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let p: Spot = Spot.zero()
        \\    let c: Cell[Spot] = .{ v = p }
        \\    c.v.x
        \\}
        \\
    , applied);
}

test "a name written once is changed once" {
    const gpa = testing.allocator;

    // A match arm's binder is declared at the token an expression reaching it
    // is written at. Two edits over one range are applied twice, and the
    // second lands on bytes the first already replaced.
    const text =
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
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "Some(n)").? + 5;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared), .@"utf-16", "", "held")).?;
    defer free(gpa, edit);

    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 2), edits.len);

    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\enum Held { Some(UInt8), Empty }
        \\
        \\fn main() -> UInt8 {
        \\    match Held.Some(1) {
        \\        Some(held) => held,
        \\        Empty => 0,
        \\    }
        \\}
        \\
    , applied);
}

test "an enum is changed everywhere it is written, and its variants are left alone" {
    const gpa = testing.allocator;

    // A qualified variant names two things and only one of them is the enum.
    // An answer that rewrote `Dim` would leave the program selecting a variant
    // the enum does not declare, which is the failure a refusal exists to
    // avoid and is worse than either.
    const text =
        \\enum Shade {
        \\    Dim,
        \\    Bright,
        \\}
        \\
        \\fn pick(s: Shade) -> UInt8 {
        \\    match read s {
        \\        Dim => 1,
        \\        Bright => 2,
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    pick(Shade.Dim) + pick(Shade.Bright)
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "Shade").?;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared + 1), .@"utf-16", "", "Tone")).?;
    defer free(gpa, edit);

    const edits = editsFor(edit, "main.lin");
    // The declaration, the annotation on `s`, and the two selections.
    try testing.expectEqual(@as(usize, 4), edits.len);

    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\enum Tone {
        \\    Dim,
        \\    Bright,
        \\}
        \\
        \\fn pick(s: Tone) -> UInt8 {
        \\    match read s {
        \\        Dim => 1,
        \\        Bright => 2,
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    pick(Tone.Dim) + pick(Tone.Bright)
        \\}
        \\
    , applied);
}

test "a trait is changed everywhere it is written" {
    const gpa = testing.allocator;

    // A bound and an `impl` header name a trait outside every expression.
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
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared + 1), .@"utf-16", "", "Sized")).?;
    defer free(gpa, edit);

    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 4), edits.len);

    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\trait Sized {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\
        \\struct Coins {
        \\    count: UInt8,
        \\}
        \\
        \\impl Sized for Coins {
        \\    fn of(x: Self) -> UInt8 {
        \\        x.count
        \\    }
        \\}
        \\
        \\fn total[T: Sized](a: T) -> UInt8 {
        \\    Sized.of(a)
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let c: Coins = .{ count = 4 }
        \\    total(c)
        \\}
        \\
    , applied);
}

test "component requirement rename edits source only" {
    const gpa = testing.allocator;
    const text = references.structural_derive_source;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(checked.semantics.expanded.generated_sources.buffers.len > 0);

    var generated_plain = false;
    for (checked.semantics.expanded.generated_sources.buffers) |generated| {
        generated_plain = generated_plain or std.mem.indexOf(u8, generated, "impl Plain for Generated") != null;
    }
    try testing.expect(generated_plain);

    const Case = struct {
        cursor: []const u8,
        within: usize,
        replacement: []const u8,
        count: usize,
    };
    const cases = [_]Case{
        .{ .cursor = "    Inspect[UInt64]", .within = 5, .replacement = "Inspectable", .count = 3 },
        .{ .cursor = "    Marker[T]", .within = 5, .replacement = "Marked", .count = 4 },
        .{ .cursor = "reflect.components: Lookup", .within = 21, .replacement = "Find", .count = 4 },
        .{ .cursor = "Linear + Project", .within = 10, .replacement = "Projected", .count = 2 },
        .{ .cursor = ") for Box[T]", .within = 7, .replacement = "Crate", .count = 3 },
        .{ .cursor = ") for Box[T]", .within = 10, .replacement = "Element", .count = 4 },
        .{ .cursor = "T.Item: Lookup", .within = 3, .replacement = "Output", .count = 2 },
        .{ .cursor = "    Plain,", .within = 5, .replacement = "Ordinary", .count = 3 },
    };

    for (cases) |case| {
        const cursor = std.mem.indexOf(u8, text, case.cursor).? + case.within;
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, cursor), .@"utf-16", "", case.replacement)).?;
        defer free(gpa, edit);
        const edits = editsFor(edit, "main.lin");
        try testing.expectEqual(case.count, edits.len);
        try testing.expectEqual(@as(usize, 1), edit.changes.?.map.count());
        for (edits) |source_edit| try testing.expectEqualStrings(case.replacement, source_edit.newText);
    }

    const primitive = std.mem.indexOf(u8, text, "reflect.components: Lookup[UInt64]").? + 27;
    try testing.expectError(
        Refused.APrimitiveIsNotRenameable,
        forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, primitive), .@"utf-16", "", "Word"),
    );
}

/// A trait, one implementation of it, and the operation called both ways.
const trait_program =
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

test "a trait operation is renamed together with what supplies it" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = trait_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    // Four places one name is written: the signature the trait declares, the
    // member the implementation wrote to supply it, and the operation called
    // both ways. Each answers the same edit, because they are one rename --
    // changing the signature alone leaves the member declaring a name the
    // trait does not declare, and changing the member alone leaves it
    // supplying nothing.
    const signature = std.mem.indexOf(u8, trait_program, "fn of(x: Self, since: UInt8) -> UInt8\n").? + 3;
    const member = std.mem.lastIndexOf(u8, trait_program, "fn of(x: Self, since: UInt8) -> UInt8 {").? + 3;
    const dotted = std.mem.indexOf(u8, trait_program, "b.of(1)").? + 2;
    const written = std.mem.indexOf(u8, trait_program, "Measure.of(a, 4)").? + 8;

    for ([_]usize{ signature, member, dotted, written }) |offset| {
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(trait_program, offset), .@"utf-16", "", "size")).?;
        defer free(gpa, edit);

        const applied = try applyTo(gpa, trait_program, editsFor(edit, "main.lin"), .@"utf-16");
        defer gpa.free(applied);
        try testing.expectEqualStrings(
            \\struct Account {
            \\    balance: UInt8,
            \\}
            \\
            \\trait Measure {
            \\    fn size(x: Self, since: UInt8) -> UInt8
            \\}
            \\
            \\impl Measure for Account {
            \\    fn size(x: Self, since: UInt8) -> UInt8 {
            \\        x.balance + since
            \\    }
            \\}
            \\
            \\fn main() -> UInt8 {
            \\    let a: Account = .{ balance = 1 }
            \\    let b: Account = .{ balance = 2 }
            \\    Measure.size(a, 4) + b.size(1)
            \\}
            \\
        , applied);
    }
}

test "a trait operation supplied by a generated derive is not renameable" {
    const gpa = testing.allocator;
    const text =
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
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const signature = std.mem.indexOf(u8, text, "fn value(self: Self) -> UInt8\n").? + 3;
    try testing.expectError(
        Refused.AGeneratedMemberIsNotRenameable,
        forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, signature), .@"utf-16", "", "size"),
    );
}

const template_rename_program =
    \\trait Structural {
    \\    fn value(self: Self, amount: UInt8) -> UInt8
    \\}
    \\
    \\template impl Structural {
    \\    fn value(_self: Self, amount: UInt8) -> UInt8 {
    \\        let local = amount
    \\        local
    \\    }
    \\}
    \\
    \\fn main() -> UInt8 { 0 }
    \\
;

test "an inactive source template member offers no rename edit" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = template_rename_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const member = std.mem.indexOf(u8, template_rename_program, "fn value(_self").? + 3;
    const edit = try forPosition(
        gpa,
        testing.io,
        &checked,
        checked.fileNamed("main.lin").?,
        at(template_rename_program, member),
        .@"utf-16",
        "",
        "size",
    );
    defer if (edit) |owned| free(gpa, owned);
    try testing.expect(edit == null);
}

test "an inactive source template parameter declaration offers no rename edit" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = template_rename_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const member = std.mem.indexOf(u8, template_rename_program, "fn value(_self").?;
    const parameter = member + std.mem.indexOf(u8, template_rename_program[member..], "amount: UInt8").?;
    const edit = try forPosition(
        gpa,
        testing.io,
        &checked,
        checked.fileNamed("main.lin").?,
        at(template_rename_program, parameter),
        .@"utf-16",
        "",
        "quantity",
    );
    defer if (edit) |owned| free(gpa, owned);
    try testing.expect(edit == null);
}

test "an inactive source template parameter reference offers no rename edit" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = template_rename_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const parameter = std.mem.lastIndexOf(u8, template_rename_program, "amount").?;
    const edit = try forPosition(
        gpa,
        testing.io,
        &checked,
        checked.fileNamed("main.lin").?,
        at(template_rename_program, parameter),
        .@"utf-16",
        "",
        "quantity",
    );
    defer if (edit) |owned| free(gpa, owned);
    try testing.expect(edit == null);
}

test "a local inside an inactive source template remains renameable" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = template_rename_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const local = std.mem.indexOf(u8, template_rename_program, "local =").?;
    const edit = (try forPosition(
        gpa,
        testing.io,
        &checked,
        checked.fileNamed("main.lin").?,
        at(template_rename_program, local),
        .@"utf-16",
        "",
        "result",
    )).?;
    defer free(gpa, edit);

    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 2), edits.len);
    const applied = try applyTo(gpa, template_rename_program, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expect(std.mem.indexOf(u8, applied, "let result = amount\n        result") != null);
}

/// A trait declaring a type, and the implementation that settles it.
const alias_program =
    \\alias Meters = UInt64
    \\
    \\fn double(m: Meters) -> Meters {
    \\    m * 2
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let d: Meters = double(3)
    \\    UInt8(d)
    \\}
    \\
;

test "an alias is renamed where it is declared and everywhere it is written" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = alias_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, alias_program, "Meters").? + 1;
    const written = std.mem.indexOf(u8, alias_program, "d: Meters").? + 4;
    for ([_]usize{ declared, written }) |offset| {
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(alias_program, offset), .@"utf-16", "", "Distance")).?;
        defer free(gpa, edit);

        const applied = try applyTo(gpa, alias_program, editsFor(edit, "main.lin"), .@"utf-16");
        defer gpa.free(applied);
        try testing.expectEqualStrings(
            \\alias Distance = UInt64
            \\
            \\fn double(m: Distance) -> Distance {
            \\    m * 2
            \\}
            \\
            \\fn main() -> UInt8 {
            \\    let d: Distance = double(3)
            \\    UInt8(d)
            \\}
            \\
        , applied);
    }
}

const generic_alias_head_program =
    \\struct Cell[T] {
    \\    value: T,
    \\}
    \\
    \\impl[T] Cell[T] {
    \\    fn wrap(sink value: T) -> Cell[T] {
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

test "a generic alias heading a path is renamed with its declaration and every use" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = generic_alias_head_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, generic_alias_head_program, "Slot[T]").? + 1;
    const written = std.mem.indexOf(u8, generic_alias_head_program, "held: Slot").? + 7;
    const head = std.mem.indexOf(u8, generic_alias_head_program, "Slot.wrap").? + 1;
    for ([_]usize{ declared, written, head }) |offset| {
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(generic_alias_head_program, offset), .@"utf-16", "", "Pocket")).?;
        defer free(gpa, edit);

        const applied = try applyTo(gpa, generic_alias_head_program, editsFor(edit, "main.lin"), .@"utf-16");
        defer gpa.free(applied);
        try testing.expect(std.mem.indexOf(u8, applied, "alias Pocket[T] = Cell[T]") != null);
        try testing.expect(std.mem.indexOf(u8, applied, "let held: Pocket[UInt8] = Pocket.wrap(3)") != null);
        try testing.expect(std.mem.indexOf(u8, applied, "Slot") == null);
    }
}

const declared_type_program =
    \\struct Account {
    \\    balance: UInt8,
    \\}
    \\
    \\trait Measure {
    \\    type Item
    \\    fn of(x: Self) -> UInt8
    \\}
    \\
    \\impl Measure for Account {
    \\    type Item = UInt8
    \\
    \\    fn of(x: Self) -> UInt8 {
    \\        x.balance
    \\    }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let a: Account = .{ balance = 1 }
    \\    Measure.of(a)
    \\}
    \\
;

test "a declared type is renamed together with what settles it" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = declared_type_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    // Two declarations of one name, and either end answers the same edit:
    // renaming the trait's side alone leaves the implementation settling a
    // type the trait does not declare, and renaming the implementation's alone
    // leaves the trait's unsettled.
    const declared = std.mem.indexOf(u8, declared_type_program, "type Item\n").? + 5;
    const settled = std.mem.indexOf(u8, declared_type_program, "type Item = UInt8").? + 5;

    for ([_]usize{ declared, settled }) |offset| {
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(declared_type_program, offset), .@"utf-16", "", "Held")).?;
        defer free(gpa, edit);

        const applied = try applyTo(gpa, declared_type_program, editsFor(edit, "main.lin"), .@"utf-16");
        defer gpa.free(applied);
        try testing.expectEqualStrings(
            \\struct Account {
            \\    balance: UInt8,
            \\}
            \\
            \\trait Measure {
            \\    type Held
            \\    fn of(x: Self) -> UInt8
            \\}
            \\
            \\impl Measure for Account {
            \\    type Held = UInt8
            \\
            \\    fn of(x: Self) -> UInt8 {
            \\        x.balance
            \\    }
            \\}
            \\
            \\fn main() -> UInt8 {
            \\    let a: Account = .{ balance = 1 }
            \\    Measure.of(a)
            \\}
            \\
        , applied);
    }
}

test "written type selection rename follows the checked declaration" {
    const gpa = testing.allocator;
    const text =
        \\trait Source { type Item }
        \\struct Wrapper[T] { value: T }
        \\impl[T] Source for Wrapper[T] { type Item = T }
        \\fn _identity[T](sink value: Wrapper[T].Item) -> T where carries(value) { value }
        \\fn main() -> UInt8 {
        \\    let value: Wrapper[UInt8].Item = 7
        \\    value - 7
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    for ([_][]const u8{ "type Item }", "type Item =", "Wrapper[T].Item", "Wrapper[UInt8].Item" }) |written| {
        const offset = std.mem.indexOf(u8, text, written).? + std.mem.indexOf(u8, written, "Item").?;
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, offset), .@"utf-16", "", "Held")).?;
        defer free(gpa, edit);
        const edits = editsFor(edit, "main.lin");
        try testing.expectEqual(@as(usize, 4), edits.len);
        const applied = try applyTo(gpa, text, edits, .@"utf-16");
        defer gpa.free(applied);
        try testing.expect(std.mem.indexOf(u8, applied, "Item") == null);
        var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
        defer renamed.deinit();
        try testing.expect(!renamed.sink.hasErrors());
    }
}

test "construction descriptor rename includes its component type" {
    const gpa = testing.allocator;
    const text =
        \\trait Zero { fn zero() -> Self }
        \\impl Zero for UInt8 { fn zero() -> Self { 0 } }
        \\template impl Zero where reflect.target: struct, reflect.components: Zero {
        \\    fn zero() -> Self {
        \\        reflect.construct(reflect.product, |component| {
        \\            let value: component.Type = Zero.zero()
        \\            value
        \\        }, {})
        \\    }
        \\}
        \\struct Pair { first: UInt8, second: UInt8 }
        \\derive Zero for Pair
        \\fn main() -> UInt8 { let pair: Pair = Zero.zero(); pair.first + pair.second }
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const offset = std.mem.indexOf(u8, text, "|component|").? + 1;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, offset), .@"utf-16", "", "field")).?;
    defer free(gpa, edit);
    const applied = try applyTo(gpa, text, editsFor(edit, "main.lin"), .@"utf-16");
    defer gpa.free(applied);
    try testing.expect(std.mem.indexOf(u8, applied, "field.Type") != null);
    var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
    defer renamed.deinit();
    try testing.expect(!renamed.sink.hasErrors());
}

test "a library trait member with generated suppliers is not renamed" {
    const gpa = testing.allocator;

    // The member is this workspace's, but the signature it supplies also has
    // generated structural implementations. Renaming the relation would have
    // to rewrite generated source, which no workspace edit can name.
    const text =
        \\struct Coins {
        \\    count: UInt8,
        \\}
        \\
        \\impl Display for Coins {
        \\    fn fmt[W: Writer](self: Coins, inout w: W) -> Result[(), W.Error] where carries(.Err: w) {
        \\        Display.fmt(self.count, &w)
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let c: Coins = .{ count = 4 }
        \\    c.count
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const member = std.mem.indexOf(u8, text, "fn fmt[W: Writer]").? + 3;
    try testing.expectError(
        Refused.AGeneratedMemberIsNotRenameable,
        forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, member), .@"utf-16", "", "render"),
    );
}

test "a member a type declares for itself is changed everywhere it is used" {
    const gpa = testing.allocator;

    // An inherent `impl` supplies no trait operation: the member is the whole
    // of what the name means, and every call to it selects it by that name in
    // the type's own namespace. Renaming it reaches all of them.
    const text =
        \\struct Point {
        \\    x: UInt8,
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
        \\    p.x
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "fn zero()").? + 3;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared), .@"utf-16", "", "origin")).?;
    defer free(gpa, edit);

    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 2), edits.len);

    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\struct Point {
        \\    x: UInt8,
        \\}
        \\
        \\impl Point {
        \\    fn origin() -> Point {
        \\        .{ x = 0 }
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let p: Point = Point.origin()
        \\    p.x
        \\}
        \\
    , applied);
}

test "a binder written as the field's own name is changed into the long form" {
    const gpa = testing.allocator;

    // `S { f }` binds the field to its own name, and the field and the binder
    // are one token. Rewriting that token in place renames the field with the
    // binder and names a field the type does not have, so the edit writes back
    // what a reader spelling it out would have written.
    const text =
        \\struct Point {
        \\    x: UInt8,
        \\    y: UInt8,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let p: Point = .{ x = 4, y = 3 }
        \\    let Point { x, y } = p
        \\    x + y
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "{ x, y }").? + 2;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared), .@"utf-16", "", "across")).?;
    defer free(gpa, edit);

    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 2), edits.len);

    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\struct Point {
        \\    x: UInt8,
        \\    y: UInt8,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let p: Point = .{ x = 4, y = 3 }
        \\    let Point { x: across, y } = p
        \\    across + y
        \\}
        \\
    , applied);
}

test "the mark on a name one declaration writes is renamed away with it" {
    const gpa = testing.allocator;

    // A `_` says the value is deliberately unused, and where one declaration
    // writes the name it says it about that declaration alone -- so it is part
    // of what the programmer asked to replace. Kept, a rename could never
    // remove a leading `_` from anything, and asking to drop one would answer
    // with the spelling that was already there.
    const text =
        \\fn main() -> UInt8 {
        \\    let _spare: UInt8 = 1
        \\    _spare + 1
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, text, "_spare").? + 1;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, declared), .@"utf-16", "", "spare")).?;
    defer free(gpa, edit);

    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 2), edits.len);
    for (edits) |e| try testing.expectEqualStrings("spare", e.newText);

    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\fn main() -> UInt8 {
        \\    let spare: UInt8 = 1
        \\    spare + 1
        \\}
        \\
    , applied);
}

test "a type is changed where a pattern in another module takes it apart" {
    const gpa = testing.allocator;

    // A pattern cannot qualify its head, so a module holding no type of that
    // name writes the spelling alone and is still taking apart what the other
    // module's function returned. That head is a place the type's name is
    // written, and a rename leaving it behind gives a pattern naming a type
    // that is no longer there.
    const main_text =
        \\import shapes
        \\
        \\fn main() -> UInt8 {
        \\    match shapes.make() {
        \\        Point { x: c, y: d } => c + d,
        \\    }
        \\}
        \\
    ;
    const shapes_text =
        \\pub struct Point {
        \\    x: UInt8,
        \\    y: UInt8,
        \\}
        \\
        \\pub fn make() -> Point {
        \\    .{ x = 1, y = 2 }
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/shapes/shapes.lin", .text = shapes_text },
        .{ .path = "app/shapes/linea.json", .text = "{}\n" },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = checked.fileNamed("app/shapes/shapes.lin").?;
    const at_type = std.mem.indexOf(u8, shapes_text, "Point").?;
    const edit = (try forPosition(gpa, testing.io, &checked, declared, at(shapes_text, at_type + 1), .@"utf-16", "", "Spot")).?;
    defer free(gpa, edit);

    const in_main = editsFor(edit, "app/main.lin");
    try testing.expectEqual(@as(usize, 1), in_main.len);

    const applied = try applyTo(gpa, main_text, in_main, .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings(
        \\import shapes
        \\
        \\fn main() -> UInt8 {
        \\    match shapes.make() {
        \\        Spot { x: c, y: d } => c + d,
        \\    }
        \\}
        \\
    , applied);
}

test "a re-exported name is not the re-exporting module's to change" {
    const gpa = testing.allocator;

    // A `use` binds the name the path ends with and offers no other spelling,
    // so the token that declares the re-export is the token that names what it
    // re-exports. Rewriting it asks the other module for a declaration of a
    // name it does not have.
    const main_text =
        \\import sizes
        \\
        \\use sizes.Width
        \\
        \\fn main() -> UInt8 {
        \\    let w: Width = .{ of = 2 }
        \\    w.of
        \\}
        \\
    ;
    const sizes_text =
        \\pub struct Width {
        \\    of: UInt8,
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/sizes/sizes.lin", .text = sizes_text },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const wanted = checked.fileNamed("app/main.lin").?;
    const path = std.mem.indexOf(u8, main_text, "sizes.Width").? + 6;
    try testing.expectError(
        Refused.AReExportedNameIsSpelledByWhatItNames,
        forPosition(gpa, testing.io, &checked, wanted, at(main_text, path), .@"utf-16", "", "Span"),
    );
}

test "the entry point is named by its spelling and is not renamed" {
    const gpa = testing.allocator;

    // The runtime calls `main` because it is called `main`. A rename answers
    // with the one edit there is to make, and applying it leaves a program
    // declaring no entry point at all.
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const declared = std.mem.indexOf(u8, local_program, "fn main()").? + 3;
    try testing.expectError(
        Refused.AnEntryPointIsNamedByItsSpelling,
        forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, declared), .@"utf-16", "", "start"),
    );
}

test "a cursor on what names nothing is renamed nowhere" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();

    const literal = std.mem.indexOf(u8, local_program, "twice(1)").? + 6;
    try testing.expectEqual(
        @as(?lsp.types.WorkspaceEdit, null),
        try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, literal), .@"utf-16", "", "other"),
    );
}

test "a name the standard library declared is refused" {
    const gpa = testing.allocator;

    // `Option` is the library's, and a rename of it would rewrite files under
    // the checkout the compiler was built from rather than anything this
    // workspace opened.
    const text = "fn main() -> UInt8 {\n    let held: Option[UInt8] = Option.some(1)\n    match held {\n        Option.some(n) => n,\n        Option.none => 0,\n    }\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = text },
    }, "main.lin");
    defer checked.deinit();

    const written = std.mem.indexOf(u8, text, "Option[UInt8]").?;
    try testing.expectError(
        Refused.ALibraryNameIsNotThisWorkspaceToChange,
        forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, written + 1), .@"utf-16", ".", "Maybe"),
    );
}

test "intrinsic integer properties cannot be renamed but their parameter can" {
    const gpa = testing.allocator;
    const text = "fn limit[T: Integer](_value: T) -> T { T.max }\nfn main() -> UInt8 { limit(UInt8.min) }\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    for ([_][]const u8{ "max", "min" }) |property| {
        const edit = try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, std.mem.indexOf(u8, text, property).?), .@"utf-16", "", "endpoint");
        try testing.expect(edit == null);
    }
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, std.mem.indexOf(u8, text, "T.max").?), .@"utf-16", "", "Number")).?;
    defer free(gpa, edit);
    const applied = try applyTo(gpa, text, editsFor(edit, "main.lin"), .@"utf-16");
    defer gpa.free(applied);
    try testing.expectEqualStrings("fn limit[Number: Integer](_value: Number) -> Number { Number.max }\nfn main() -> UInt8 { limit(UInt8.min) }\n", applied);
}

test "record shorthand renames locals and fields independently" {
    const gpa = testing.allocator;
    const text =
        \\struct Entry { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let value: UInt8 = 3
        \\    let entry: Entry = .{ value }
        \\    entry.value + value
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const cases = [_]struct { offset: usize, preserved: []const u8, count: usize }{
        .{ .offset = std.mem.indexOf(u8, text, ".{ value").? + ".{ ".len, .preserved = ".{ value = amount }", .count = 3 },
        .{ .offset = std.mem.indexOf(u8, text, "value:").?, .preserved = ".{ amount = value }", .count = 3 },
    };
    for (cases) |case| {
        const cursor = at(text, case.offset);
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "", "amount")).?;
        defer free(gpa, edit);
        const edits = editsFor(edit, "main.lin");
        try testing.expectEqual(case.count, edits.len);
        const applied = try applyTo(gpa, text, edits, .@"utf-16");
        defer gpa.free(applied);
        try testing.expect(std.mem.indexOf(u8, applied, case.preserved) != null);
        var again = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
        defer again.deinit();
        try testing.expect(!again.sink.hasErrors());
    }
}

test "transparent fields share definition references and rename across instances" {
    const gpa = testing.allocator;
    const text =
        \\struct Entry[T] { value: T }
        \\struct Other { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let first: Entry[UInt8] = .{ value = 3 }
        \\    let second: Entry[UInt16] = .{ value = 4 }
        \\    let other: Other = .{ value = 5 }
        \\    let view = borrow first
        \\    let nested = borrow view
        \\    nested.value + UInt8(second.value) + other.value
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const cursor = at(text, std.mem.indexOf(u8, text, "nested.value").? + "nested.".len);
    const target = try @import("definition.zig").forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "");
    try testing.expect(target != null);
    defer gpa.free(target.?.uri);
    try testing.expectEqual(@as(u32, 0), target.?.range.start.line);
    const found = (try references.forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "", true, null)).?;
    defer references.free(gpa, found);
    try testing.expectEqual(@as(usize, 5), found.len);
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "", "amount")).?;
    defer free(gpa, edit);
    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(found.len, edits.len);
    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expect(std.mem.indexOf(u8, applied, "nested.amount") != null);
    try testing.expect(std.mem.indexOf(u8, applied, "other.value") != null);
    var again = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
    defer again.deinit();
    try testing.expect(!again.sink.hasErrors());
}

test "transparent fields rename contract labels and preserve pattern binders" {
    const gpa = testing.allocator;
    const cases = [_]struct { source: []const u8, count: usize, preserved: []const u8 }{
        .{ .source =
        \\struct Entry { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let entry: Entry = .{ value = 3 }
        \\    let Entry { value } = entry
        \\    value
        \\}
        , .count = 3, .preserved = "amount: value" },
        .{ .source =
        \\struct Entry { value: UInt8 }
        \\fn main() -> UInt8 {
        \\    let entry: Entry = .{ value = 3 }
        \\    let { value } = entry
        \\    value
        \\}
        , .count = 3, .preserved = "amount: value" },
        .{ .source =
        \\struct Holder { value: borrow UInt8 }
        \\fn extract(view: borrow Holder) -> borrow UInt8 where carries(view.value) {
        \\    copy(view.value)
        \\}
        \\fn main() -> UInt8 {
        \\    let number: UInt8 = 7
        \\    let holder: Holder = .{ value = borrow number }
        \\    let saved = extract(borrow holder)
        \\    return *saved
        \\}
        , .count = 4, .preserved = "carries(view.amount)" },
    };
    for (cases) |case| {
        var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = case.source }}, "main.lin");
        defer checked.deinit();
        try testing.expect(!checked.sink.hasErrors());
        const cursor = at(case.source, std.mem.indexOf(u8, case.source, "value:").?);
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "", "amount")).?;
        defer free(gpa, edit);
        const edits = editsFor(edit, "main.lin");
        try testing.expectEqual(case.count, edits.len);
        const applied = try applyTo(gpa, case.source, edits, .@"utf-16");
        defer gpa.free(applied);
        try testing.expect(std.mem.indexOf(u8, applied, case.preserved) != null);
        var again = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
        defer again.deinit();
        try testing.expect(!again.sink.hasErrors());
    }
}

fn renameFieldsWithFailures(gpa: std.mem.Allocator, checked: *const Analysis, cursor: lsp.types.Position) !void {
    const edit = (try forPosition(gpa, testing.io, checked, checked.program.primaryFile(), cursor, .@"utf-16", "", "amount")).?;
    defer free(gpa, edit);
}

test "transparent fields release partial rename edits on allocation failure" {
    const gpa = testing.allocator;
    const text = "struct Entry { value: UInt8 }\nfn main() -> UInt8 { let entry: Entry = .{ value = 3 }; entry.value }";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    try testing.checkAllAllocationFailures(gpa, renameFieldsWithFailures, .{ &checked, at(text, std.mem.indexOf(u8, text, "value:").?) });
}

test "constructor interface rename follows contracts and named arguments" {
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
    const offset = std.mem.lastIndexOf(u8, text, "payload").?;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, offset), .@"utf-16", "", "item")).?;
    defer free(gpa, edit);
    const edits = editsFor(edit, "main.lin");
    try testing.expectEqual(@as(usize, 3), edits.len);
    const applied = try applyTo(gpa, text, edits, .@"utf-16");
    defer gpa.free(applied);
    try testing.expect(std.mem.indexOf(u8, applied, "payload") == null);
    var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
    defer renamed.deinit();
    try testing.expect(!renamed.sink.hasErrors());
}

test "constructor interface rename preserves an escaping exact signature" {
    const gpa = testing.allocator;
    const text =
        \\enum Held { Some(UInt8) }
        \\fn invoke(callback: fn(sink payload: UInt8) -> Held) -> UInt8 {
        \\    match callback(payload: 7) { Some(value) => value }
        \\}
        \\fn main() -> UInt8 {
        \\    let make: fn(sink payload: UInt8) -> Held = Held.Some
        \\    invoke(make)
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const offset = std.mem.lastIndexOf(u8, text, "payload").?;
    try testing.expectError(Refused.ACallableInterfaceRelationIsNotRenameable, forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, offset), .@"utf-16", "", "item"));
}

test "explicit read capture rename separates shorthand source and alias" {
    const gpa = testing.allocator;
    const text =
        \\fn main() -> UInt8 {
        \\    let threshold = UInt8(3)
        \\    let above = read [read threshold] |item: UInt8| item > threshold
        \\    if above(4) { 0 } else { 1 }
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    const capture_positions = [_]usize{
        std.mem.indexOf(u8, text, "threshold").?,
        std.mem.lastIndexOf(u8, text, "threshold").?,
    };
    const expansions = [_][]const u8{ "read threshold = limit", "read limit = threshold" };
    for (capture_positions, expansions) |position, expansion| {
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, position + 1), .@"utf-16", "", "limit")).?;
        defer free(gpa, edit);
        const applied = try applyTo(gpa, text, editsFor(edit, "main.lin"), .@"utf-16");
        defer gpa.free(applied);
        try testing.expect(std.mem.indexOf(u8, applied, expansion) != null);
        var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
        defer renamed.deinit();
        try testing.expect(!renamed.sink.hasErrors());
    }
}

test "capture recovery fields rename with aliases and preserve local binders" {
    const gpa = testing.allocator;
    const text =
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
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const cases = [_]struct { needle: []const u8, expected: []const u8, count: usize }{
        .{ .needle = "value = source", .expected = "{ amount: recovered }", .count = 4 },
        .{ .needle = "value\n    let { value: recovered", .expected = "environment.amount", .count = 4 },
        .{ .needle = "value = source] || value\n    let { value }", .expected = "{ amount: value }", .count = 3 },
        .{ .needle = "value } = second", .expected = "{ value: amount }", .count = 2 },
    };
    for (cases) |case| {
        const cursor = at(text, std.mem.indexOf(u8, text, case.needle).?);
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "", "amount")).?;
        defer free(gpa, edit);
        const edits = editsFor(edit, "main.lin");
        try testing.expectEqual(case.count, edits.len);
        const applied = try applyTo(gpa, text, edits, .@"utf-16");
        defer gpa.free(applied);
        try testing.expect(std.mem.indexOf(u8, applied, case.expected) != null);
        try testing.expect(std.mem.indexOf(u8, applied, "other.value") != null);
        var again = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
        defer again.deinit();
        try testing.expect(!again.sink.hasErrors());
    }
}

test "captured contract roots rename with their bindings" {
    const gpa = testing.allocator;
    const text =
        \\fn main() -> UInt8 {
        \\    let first: UInt8 = 1
        \\    let second: UInt8 = 7
        \\    var remember = inout [sink saved = borrow first] |value: borrow UInt8| -> where retains(saved: value) {
        \\        saved = copy(value)
        \\    }
        \\    &remember(borrow second)
        \\    let { saved: result } = remember.into_captures()
        \\    *result
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const cases = [_]struct { needle: []const u8, replacement: []const u8, expected: []const u8 }{
        .{ .needle = "saved: value", .replacement = "stored", .expected = "retains(stored: value)" },
        .{ .needle = "value) {", .replacement = "incoming", .expected = "retains(saved: incoming)" },
    };
    for (cases) |case| {
        const cursor = at(text, std.mem.indexOf(u8, text, case.needle).?);
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "", case.replacement)).?;
        defer free(gpa, edit);
        const applied = try applyTo(gpa, text, editsFor(edit, "main.lin"), .@"utf-16");
        defer gpa.free(applied);
        try testing.expect(std.mem.indexOf(u8, applied, case.expected) != null);
        var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
        defer renamed.deinit();
        try testing.expect(!renamed.sink.hasErrors());
    }
}

const construction_closure_rename_program =
    \\trait Zero { fn zero() -> Self }
    \\impl Zero for UInt64 { fn zero() -> Self { 0 } }
    \\template impl Zero where reflect.target: struct, reflect.components: Zero {
    \\    fn zero() -> Self {
    \\        reflect.construct(reflect.product, |component| {
    \\            let callback = |value: UInt64| -> where borrows(value) borrow value
    \\            let number: UInt64 = 7
    \\            let alias = callback
    \\            let viewed = alias(value: number)
    \\            let capture = [viewed] || -> where carries(viewed) copy(viewed)
    \\            let _seen = capture()
    \\            let converted: fn(read external: UInt64) -> UInt64 = |local_value: UInt64| local_value
    \\            let _converted = converted(external: number)
    \\            let field: component.Type = Zero.zero()
    \\            field
    \\        }, {})
    \\    }
    \\}
    \\struct Pair { first: UInt64, second: UInt64 }
    \\derive Zero for Pair
    \\fn main() -> UInt8 {
    \\    let pair: Pair = Zero.zero()
    \\    if pair.first == 0 && pair.second == 0 { 0 } else { 1 }
    \\}
;

test "construction recipe closure names rename contracts and direct call labels" {
    const gpa = testing.allocator;
    const text = construction_closure_rename_program;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    for ([_]struct { needle: []const u8, offset: usize }{
        .{ .needle = "value: UInt64|", .offset = 0 },
        .{ .needle = "borrows(value)", .offset = "borrows(".len },
        .{ .needle = "alias(value:", .offset = "alias(".len },
        .{ .needle = "[viewed]", .offset = 1 },
        .{ .needle = "let viewed", .offset = "let ".len },
        .{ .needle = "local_value: UInt64|", .offset = 0 },
    }) |case| {
        const at_name = std.mem.indexOf(u8, text, case.needle).? + case.offset;
        try expectCheckedRename(gpa, &checked, text, at_name, "renamed");
    }
}

fn expectSafeSourceClosureRename(gpa: std.mem.Allocator, text: []const u8, allow_refusal: bool) !void {
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const name = std.mem.indexOf(u8, text, "value: UInt64|").?;
    const edit = forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, name), .@"utf-16", "", "renamed") catch |err| {
        if (allow_refusal and err == Refused.ACallableInterfaceRelationIsNotRenameable) return;
        return err;
    };
    if (edit == null) {
        try testing.expect(allow_refusal);
        return;
    }
    defer free(gpa, edit.?);
    const applied = try applyTo(gpa, text, editsFor(edit.?, "main.lin"), .@"utf-16");
    defer gpa.free(applied);
    var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
    defer renamed.deinit();
    try testing.expect(!renamed.sink.hasErrors());
}

test "source template closure provenance follows a captured callable" {
    const gpa = testing.allocator;
    const text = try std.mem.replaceOwned(
        u8,
        gpa,
        construction_closure_rename_program,
        "let alias = callback",
        "let alias = [callback] |argument: UInt64| -> where borrows(argument) callback(value: argument)",
    );
    defer gpa.free(text);
    const called = try std.mem.replaceOwned(u8, gpa, text, "alias(value: number)", "alias(argument: number)");
    defer gpa.free(called);
    try expectSafeSourceClosureRename(gpa, called, false);
}

test "source template closure provenance follows a copied callable" {
    const gpa = testing.allocator;
    const capturing = try std.mem.replaceOwned(
        u8,
        gpa,
        construction_closure_rename_program,
        "|value: UInt64| -> where borrows(value) borrow value",
        "[sink held = UInt64(1)] |value: UInt64| -> where borrows(value) { let _held = held; borrow value }",
    );
    defer gpa.free(capturing);
    const text = try std.mem.replaceOwned(u8, gpa, capturing, "let alias = callback", "let alias = copy(callback)\n            let _original = callback(value: number)");
    defer gpa.free(text);
    try expectSafeSourceClosureRename(gpa, text, false);
}

test "source template closure provenance never returns incomplete edits through a generic call" {
    const gpa = testing.allocator;
    const helper = "fn identity[T: Copyable](value: T) -> T where carries(value) { copy(value) }\n";
    const source = try std.mem.concat(gpa, u8, &.{ helper, construction_closure_rename_program });
    defer gpa.free(source);
    const text = try std.mem.replaceOwned(u8, gpa, source, "let alias = callback", "let alias = identity(callback)");
    defer gpa.free(text);
    try expectSafeSourceClosureRename(gpa, text, true);
}

test "field delegation shares field definition references and rename" {
    const gpa = testing.allocator;
    const text =
        \\struct Board { scores: [UInt8; 2] }
        \\struct Other { scores: UInt8 }
        \\impl Index[UInt64] for Board via scores
        \\impl Index[FromEnd] for Board via scores
        \\impl Board { trav positions via scores }
        \\fn main() -> UInt8 {
        \\    let board: Board = .{ scores = [1, 2] }
        \\    let other: Other = .{ scores = 3 }
        \\    board[UInt64(0)] + other.scores
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, text, offset, "via scores")) |start| {
        const cursor = at(text, start + "via ".len);
        offset = start + "via scores".len;
        const target = (try @import("definition.zig").forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "")).?;
        defer gpa.free(target.uri);
        try testing.expectEqual(@as(u32, 0), target.range.start.line);
        try testing.expectEqual(@as(u32, 15), target.range.start.character);
        const found = (try references.forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "", true, null)).?;
        defer references.free(gpa, found);
        try testing.expectEqual(@as(usize, 5), found.len);
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, cursor, .@"utf-16", "", "points")).?;
        defer free(gpa, edit);
        const edits = editsFor(edit, "main.lin");
        try testing.expectEqual(found.len, edits.len);
        const applied = try applyTo(gpa, text, edits, .@"utf-16");
        defer gpa.free(applied);
        try testing.expectEqual(@as(usize, 3), std.mem.count(u8, applied, "via points"));
        try testing.expect(std.mem.indexOf(u8, applied, "struct Other { scores: UInt8 }") != null);
        try testing.expect(std.mem.indexOf(u8, applied, "other.scores") != null);
        var again = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
        defer again.deinit();
        try testing.expect(!again.sink.hasErrors());
    }
}

test "contextual constructor rename keeps selected variants separate from their enums" {
    const gpa = testing.allocator;
    const text =
        \\enum RenderError { Allocation(UInt8) }
        \\enum OtherError { Allocation(UInt8) }
        \\fn code(error: RenderError) -> UInt8 {
        \\    match read error { Allocation(value) => value }
        \\}
        \\fn other_code(error: OtherError) -> UInt8 {
        \\    match read error { Allocation(value) => value }
        \\}
        \\fn main() -> UInt8 {
        \\    let first: fn(sink value: UInt8) -> RenderError = .Allocation
        \\    let second: fn(sink value: UInt8) -> RenderError = RenderError.Allocation
        \\    let other: fn(sink value: UInt8) -> OtherError = .Allocation
        \\    let direct = RenderError.Allocation(3)
        \\    code(first(value: 1)) + code(second(value: 2)) + other_code(other(value: 4)) + code(direct)
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const Request = struct { offset: usize, name: []const u8, count: usize };
    const requests = [_]Request{
        .{ .offset = std.mem.indexOf(u8, text, "= .Allocation").? + 4, .name = "OutOfMemory", .count = 5 },
        .{ .offset = std.mem.lastIndexOf(u8, text, "= .Allocation").? + 4, .name = "Unavailable", .count = 3 },
        .{ .offset = std.mem.indexOf(u8, text, "RenderError").?, .name = "RenderFailure", .count = 6 },
    };
    for (requests) |request| {
        const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, request.offset), .@"utf-16", "", request.name)).?;
        defer free(gpa, edit);
        const edits = editsFor(edit, "main.lin");
        try testing.expectEqual(request.count, edits.len);
        const applied = try applyTo(gpa, text, edits, .@"utf-16");
        defer gpa.free(applied);
        if (std.mem.eql(u8, request.name, "OutOfMemory")) {
            try testing.expect(std.mem.indexOf(u8, applied, "enum OtherError { Allocation(UInt8) }") != null);
            try testing.expect(std.mem.indexOf(u8, applied, "OtherError = .Allocation") != null);
        } else if (std.mem.eql(u8, request.name, "RenderFailure")) {
            try testing.expect(std.mem.indexOf(u8, applied, "RenderFailure.Allocation") != null);
            try testing.expect(std.mem.indexOf(u8, applied, "RenderError") == null);
        }
        var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = applied }}, "main.lin");
        defer renamed.deinit();
        try testing.expect(!renamed.sink.hasErrors());
    }
}

test "an exported declaration rename follows use bindings through attached derives" {
    const gpa = testing.allocator;
    const main_text =
        \\import origin
        \\import facade
        \\use facade.Marker
        \\
        \\@derive(origin.Marker)
        \\struct Item {}
        \\
        \\fn _accepts[T: Marker](_value: T) {}
        \\fn main() -> UInt8 { Marker.score(Item {}) }
    ;
    const origin_text =
        \\pub trait Marker { fn score(self: Self) -> UInt8 }
        \\template impl Marker { fn score(_self: Self) -> UInt8 { 7 } }
    ;
    const facade_text = "import origin\npub use origin.Marker\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/origin/origin.lin", .text = origin_text },
        .{ .path = "app/facade/facade.lin", .text = facade_text },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const wanted = std.mem.indexOf(u8, main_text, "origin.Marker").? + "origin.".len;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("app/main.lin").?, at(main_text, wanted), .@"utf-16", "", "Label")).?;
    defer free(gpa, edit);
    try testing.expectEqual(@as(usize, 4), editsFor(edit, "app/main.lin").len);
    try testing.expectEqual(@as(usize, 2), editsFor(edit, "app/origin/origin.lin").len);
    try testing.expectEqual(@as(usize, 1), editsFor(edit, "app/facade/facade.lin").len);
    const main_after = try applyTo(gpa, main_text, editsFor(edit, "app/main.lin"), .@"utf-16");
    defer gpa.free(main_after);
    const origin_after = try applyTo(gpa, origin_text, editsFor(edit, "app/origin/origin.lin"), .@"utf-16");
    defer gpa.free(origin_after);
    const facade_after = try applyTo(gpa, facade_text, editsFor(edit, "app/facade/facade.lin"), .@"utf-16");
    defer gpa.free(facade_after);
    var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_after },
        .{ .path = "app/origin/origin.lin", .text = origin_after },
        .{ .path = "app/facade/facade.lin", .text = facade_after },
    }, "app");
    defer renamed.deinit();
    try testing.expect(!renamed.sink.hasErrors());
    try testing.expect(std.mem.indexOf(u8, main_after, "use facade.Label") != null);
    try testing.expect(std.mem.indexOf(u8, main_after, "@derive(origin.Label)") != null);
    try testing.expect(std.mem.indexOf(u8, main_after, "T: Label") != null);
    try testing.expect(std.mem.indexOf(u8, main_after, "Label.score") != null);
    const Query = struct {
        fn run(allocator: std.mem.Allocator, analysis: *const Analysis, cursor: lsp.types.Position) !void {
            const changes = (try forPosition(allocator, testing.io, analysis, analysis.fileNamed("app/main.lin").?, cursor, .@"utf-16", "", "Label")).?;
            defer free(allocator, changes);
        }
    };
    try testing.checkAllAllocationFailures(gpa, Query.run, .{ &checked, at(main_text, wanted) });
}

test "an exported enum rename preserves its same-named variant through use bindings" {
    const gpa = testing.allocator;
    const main_text =
        \\import origin
        \\import facade
        \\use facade.State
        \\fn main() -> UInt8 {
        \\    let value: State = origin.State.State
        \\    match value { State => 0, Ready => 1 }
        \\}
    ;
    const origin_text = "pub enum State { State, Ready }\n";
    const facade_text = "import origin\npub use origin.State\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/origin/origin.lin", .text = origin_text },
        .{ .path = "app/facade/facade.lin", .text = facade_text },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const wanted = std.mem.indexOf(u8, main_text, "origin.State").? + "origin.".len;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("app/main.lin").?, at(main_text, wanted), .@"utf-16", "", "Status")).?;
    defer free(gpa, edit);
    try testing.expectEqual(@as(usize, 3), editsFor(edit, "app/main.lin").len);
    try testing.expectEqual(@as(usize, 1), editsFor(edit, "app/origin/origin.lin").len);
    try testing.expectEqual(@as(usize, 1), editsFor(edit, "app/facade/facade.lin").len);
    const main_after = try applyTo(gpa, main_text, editsFor(edit, "app/main.lin"), .@"utf-16");
    defer gpa.free(main_after);
    const origin_after = try applyTo(gpa, origin_text, editsFor(edit, "app/origin/origin.lin"), .@"utf-16");
    defer gpa.free(origin_after);
    const facade_after = try applyTo(gpa, facade_text, editsFor(edit, "app/facade/facade.lin"), .@"utf-16");
    defer gpa.free(facade_after);
    var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_after },
        .{ .path = "app/origin/origin.lin", .text = origin_after },
        .{ .path = "app/facade/facade.lin", .text = facade_after },
    }, "app");
    defer renamed.deinit();
    try testing.expect(!renamed.sink.hasErrors());
    try testing.expect(std.mem.indexOf(u8, main_after, "let value: Status = origin.Status.State") != null);
    try testing.expect(std.mem.indexOf(u8, main_after, "match value { State => 0, Ready => 1 }") != null);
    try testing.expectEqualStrings("pub enum Status { State, Ready }\n", origin_after);
}

test "an exported alias rename follows use bindings" {
    const gpa = testing.allocator;
    const main_text =
        \\import origin
        \\use origin.Meters
        \\fn main() -> UInt8 {
        \\    let near: Meters = 1
        \\    let far: origin.Meters = 2
        \\    UInt8(near + far)
        \\}
    ;
    const origin_text = "pub alias Meters = UInt64\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/origin/origin.lin", .text = origin_text },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const wanted = std.mem.indexOf(u8, main_text, "origin.Meters =").? + "origin.".len;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("app/main.lin").?, at(main_text, wanted), .@"utf-16", "", "Distance")).?;
    defer free(gpa, edit);
    const main_after = try applyTo(gpa, main_text, editsFor(edit, "app/main.lin"), .@"utf-16");
    defer gpa.free(main_after);
    const origin_after = try applyTo(gpa, origin_text, editsFor(edit, "app/origin/origin.lin"), .@"utf-16");
    defer gpa.free(origin_after);
    try testing.expectEqualStrings(
        \\import origin
        \\use origin.Distance
        \\fn main() -> UInt8 {
        \\    let near: Distance = 1
        \\    let far: origin.Distance = 2
        \\    UInt8(near + far)
        \\}
    , main_after);
    try testing.expectEqualStrings("pub alias Distance = UInt64\n", origin_after);
}

test "an exported constant rename follows use bindings and preserves module aliases" {
    const gpa = testing.allocator;
    const main_text = "import origin as source\nuse source.amount\nfn main() -> UInt8 { amount + source.amount }\n";
    const origin_text = "pub let amount: UInt8 = 3\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/origin/origin.lin", .text = origin_text },
    }, "app");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const wanted = std.mem.lastIndexOf(u8, main_text, "source.amount").? + "source.".len;
    const edit = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("app/main.lin").?, at(main_text, wanted), .@"utf-16", "", "total")).?;
    defer free(gpa, edit);
    try testing.expectEqual(@as(usize, 3), editsFor(edit, "app/main.lin").len);
    try testing.expectEqual(@as(usize, 1), editsFor(edit, "app/origin/origin.lin").len);
    const main_after = try applyTo(gpa, main_text, editsFor(edit, "app/main.lin"), .@"utf-16");
    defer gpa.free(main_after);
    const origin_after = try applyTo(gpa, origin_text, editsFor(edit, "app/origin/origin.lin"), .@"utf-16");
    defer gpa.free(origin_after);
    var renamed = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_after },
        .{ .path = "app/origin/origin.lin", .text = origin_after },
    }, "app");
    defer renamed.deinit();
    try testing.expect(!renamed.sink.hasErrors());
    try testing.expectEqualStrings("import origin as source\nuse source.total\nfn main() -> UInt8 { total + source.total }\n", main_after);
}
