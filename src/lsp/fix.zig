const std = @import("std");
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const workspace = @import("workspace.zig");
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const ast_mod = @import("../syntax/ast.zig");
const Ast = ast_mod.Ast;
const program_mod = @import("../syntax/program.zig");
const FileId = @import("../support/source.zig").FileId;
const TokenId = @import("../lexer/token.zig").TokenId;
const typecheck = @import("../sema/typecheck.zig");
const Resolution = @import("../sema/resolve.zig").Resolution;
const Code = @import("../diagnostics/diagnostic.zig").Code;
const placement = @import("../syntax/placement.zig");
const Placement = placement.Placement;
const placementIn = placement.placementIn;
const placementForUse = placement.placementForUse;

/// Every quick fix offered for the diagnostics a request carried.
///
/// One action per module of the file's own program that an `import` written
/// here would name, for each `[N-Undefined]` the request carried.
///
/// Allocated from the allocator handed in, which for a request is the
/// message's arena, and released with it.
pub fn forFile(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    query: workspace.Query,
    program: []const u8,
    uri: []const u8,
    diagnostics: []const lsp.types.Diagnostic,
    encoding: lsp.offsets.Encoding,
) ![]const lsp.types.CodeAction.Result {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return &.{};
    const text = part.source;
    const place = placementIn(ast, part, text);

    var offered: std.ArrayList(lsp.types.CodeAction.Result) = .empty;
    errdefer offered.deinit(gpa);

    // Grouped by the name that was undefined, so a name reported twice in one
    // request is offered one action naming both reports rather than the same
    // action twice.
    var seen: std.ArrayList([]const u8) = .empty;
    defer seen.deinit(gpa);

    const taken = try takenFromAnImportIn(gpa, &checked.program, file);
    defer gpa.free(taken);

    for (diagnostics, 0..) |d, i| {
        const name = importableNameIn(checked, file, text, d, encoding) orelse continue;
        if (indexOfName(seen.items, name) != null) continue;
        try seen.append(gpa, name);

        if (indexOfName(taken, name) != null) continue;

        var reports: std.ArrayList(lsp.types.Diagnostic) = .empty;
        errdefer reports.deinit(gpa);
        for (diagnostics[i..]) |other| {
            const also = importableNameIn(checked, file, text, other, encoding) orelse continue;
            if (std.mem.eql(u8, also, name)) try reports.append(gpa, other);
        }
        const held = try reports.toOwnedSlice(gpa);

        // Which modules carry that name is the index's answer, and it already
        // answers for this program alone -- a filter written again here would
        // be a second decision about what an import can reach.
        for (query.modulesNamed(program, name)) |m| {
            const writes = try writingImport(gpa, program, m.dir, text, place, encoding) orelse continue;
            try offered.append(gpa, .{ .code_action = .{
                .title = try std.fmt.allocPrint(gpa, "import {s}", .{writes.path}),
                .kind = .quickfix,
                .diagnostics = held,
                .edit = try editIn(gpa, uri, writes.edit),
            } });
        }
    }

    try appendUses(gpa, checked, file, text, uri, diagnostics, encoding, &offered);
    return offered.toOwnedSlice(gpa);
}

/// One action per `[T-UnknownOperation]` the request carried whose name a
/// trait out of scope declares, offering the `use` that brings the trait in.
///
/// The same code carries a name no operation answers to at all. Whether a
/// trait out of scope declares it is the checker's question, asked below.
///
/// **The message is not parsed.** A fix built by reading the words back out of
/// a diagnostic is a second copy of the rule that wrote them, and the two come
/// apart the first time the sentence is reworded. What is read is the range --
/// which expression the report was about -- and the trait is found by asking
/// the routine the checker asked, over the same receiver type.
fn appendUses(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    text: []const u8,
    uri: []const u8,
    diagnostics: []const lsp.types.Diagnostic,
    encoding: lsp.offsets.Encoding,
    offered: *std.ArrayList(lsp.types.CodeAction.Result),
) !void {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return;
    const place = placementForUse(ast, part, text);

    var seen: std.ArrayList(DeclId) = .empty;
    defer seen.deinit(gpa);

    for (diagnostics) |d| {
        const code = d.code orelse continue;
        switch (code) {
            .string => |rule| if (!std.mem.eql(u8, rule, Code.t_unknown_operation.ruleName())) continue,
            .number => continue,
        }

        const at: u32 = @intCast(lsp.offsets.positionToIndex(text, d.range.start, encoding));
        const trait = try traitFor(gpa, checked, file, at) orelse continue;
        if (indexOfDecl(seen.items, trait) != null) continue;
        try seen.append(gpa, trait);

        const writes = try writingUse(gpa, &checked.program, &checked.semantics.res, file, trait, text, place, encoding);
        try offered.append(gpa, .{ .code_action = .{
            .title = if (writes.import_path != null)
                try std.fmt.allocPrint(gpa, "import {s} and use {s}", .{ writes.import_path.?, writes.path })
            else
                try std.fmt.allocPrint(gpa, "use {s}", .{writes.path}),
            .kind = .quickfix,
            .diagnostics = try gpa.dupe(lsp.types.Diagnostic, &.{d}),
            .edit = try editsIn(gpa, uri, writes),
        } });
    }
}

/// The trait that would declare what is selected at a byte, if this module
/// could see it.
fn traitFor(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    at: u32,
) !?DeclId {
    const ast = &checked.program.ast;
    const under = checked.cursors.under(ast, file, at) orelse return null;

    // The report covers the whole selection, so its first byte is the
    // receiver's -- and what sits at a byte is the name, with the selection
    // written around it. The selection is what carries the name being reached
    // for, which is the same pair `qualifies` reads for an import.
    const named = switch (under.node) {
        .expr => |e| e,
        else => return null,
    };
    const selected = switch (under.around orelse return null) {
        .expr => |e| e,
        else => return null,
    };
    if (ast.exprTag(selected) != .field) return null;

    const base = ast.unaryOperand(selected);
    if (base != named) return null;
    const held = checked.semantics.typing.exprType(base);
    if (held == .poison) return null;

    const wanted = ast.tokenName(ast.exprMain(selected));
    const found = try typecheck.reachIn(
        ast,
        &checked.program,
        &checked.semantics.res,
        &checked.semantics.typing,
        checked.semantics.res.moduleOfFile(file),
        checked.cursors.declarationAt(ast, file, at),
    ).elsewhere(gpa, held, wanted);
    return if (found == DeclId.none) null else found;
}

fn indexOfDecl(held: []const DeclId, wanted: DeclId) ?usize {
    return std.mem.indexOfScalar(DeclId, held, wanted);
}

/// Every name an `import` written in this file would collide with.
///
/// **The one answer to "may this file import that".** A quick fix offering an
/// import, a completion offering a module and a completion offering what a
/// module holds all ask it, and an answer of their own would be three rules
/// that agree until the file they disagree about is written.
///
/// What an import declares is a name, and [N-Duplicate] says a module declares
/// a name once -- so an import of a name the module already declares reports
/// rather than binds. A name is undefined at a use without being absent from
/// its module: a module bound by an import is a scope rather than a value, and
/// a name declared twice is reached by neither of them, so both are undefined
/// at a use while being written already.
///
/// **A sibling file's import is not among them.** An import binds inside the
/// file that wrote it and nowhere else, so two files of one module may each
/// import the same dependency and the second is not a duplicate of the first --
/// which is what leaves this file needing an import of its own for a module the
/// file beside it already names. This file's own import is here, under the name
/// it bound, which is why a second import of one module in one file is not a
/// case of its own.
///
/// Costs one pass over the declarations of the module the file belongs to,
/// which is what a module holds and never what the program holds.
pub fn takenFromAnImportIn(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    file: FileId,
) ![]const []const u8 {
    const ast = &program.ast;
    var written: std.ArrayList([]const u8) = .empty;
    errdefer written.deinit(gpa);

    // Reached through a declaration the file holds rather than by asking which
    // module holds the file: `moduleOf` is the search the program already
    // offers, and a second lookup keyed by the file would answer the same
    // question a second way.
    //
    // A file declaring nothing names nothing an import could collide with, and
    // has no declaration to reach its module through.
    const here = ast.partOfFile(file) orelse return written.toOwnedSlice(gpa);
    if (here.decl_start == here.decl_end) return written.toOwnedSlice(gpa);
    const holding = program.moduleOf(DeclId.at(@intCast(here.decl_start)));

    for (program.get(holding).files) |of| {
        const part = ast.partOfFile(of) orelse continue;
        for (part.decl_start..part.decl_end) |i| {
            const d = DeclId.at(@intCast(i));
            // A member is reached through the type or trait that holds it
            // rather than by a name of the module's, so it is not a name an
            // import would collide with.
            if (ast.memberOwner(d) != TokenId.none) continue;
            // Nor is an import another file wrote, which binds only there.
            if (ast.declTag(d) == .import_ and of != file) continue;
            const at = ast.declName(d);
            if (at == TokenId.none) continue;
            try written.append(gpa, ast.tokenText(at));
        }
    }
    return written.toOwnedSlice(gpa);
}

/// The name a diagnostic says nothing has bound and an import would bind, or
/// null where it names something else.
///
/// Read out of the source the diagnostic points at rather than out of its
/// message: the range is where the name is written, and a message parsed for
/// the name between its backticks would be a second place deciding what the
/// diagnostic is about.
///
/// Where it is written decides as much as what it says. An import binds a
/// module, and [M-Vis] makes qualified access the only way a module's name is
/// reached -- so a name written anywhere else is one no import binds, and an
/// import written for it would leave the name as undefined as it was and add
/// an import nothing names.
///
/// Costs one pass over the file's bytes to reach the offset and the lookup
/// that says what sits there, which is a binary search over the file's tokens.
fn importableNameIn(
    checked: *const Analysis,
    file: FileId,
    text: []const u8,
    d: lsp.types.Diagnostic,
    encoding: lsp.offsets.Encoding,
) ?[]const u8 {
    const code = d.code orelse return null;
    switch (code) {
        .string => |rule| if (!std.mem.eql(u8, rule, Code.n_undefined.ruleName())) return null,
        .number => return null,
    }
    const start = lsp.offsets.positionToIndex(text, d.range.start, encoding);
    const end = lsp.offsets.positionToIndex(text, d.range.end, encoding);
    if (end <= start or end > text.len) return null;
    if (!qualifies(checked, file, @intCast(start))) return null;
    return text[start..end];
}

/// Whether what is written at a byte is the left side of a qualified access.
///
/// The node covering it and the node written around it are one lookup, which
/// is what the index of what sits where a cursor is exists for: `a` in
/// `a.open()` is a name inside a selection, and the selection is what says the
/// name is being reached through.
fn qualifies(checked: *const Analysis, file: FileId, at: u32) bool {
    const ast = &checked.program.ast;
    const under = checked.cursors.under(ast, file, at) orelse return false;
    const named = switch (under.node) {
        .expr => |e| e,
        else => return false,
    };
    const around = switch (under.around orelse return false) {
        .expr => |e| e,
        else => return false,
    };
    if (ast.exprTag(around) != .field) return false;
    return ast.unaryOperand(around) == named;
}

/// Whether a name is among a list of them.
pub fn indexOfName(among: []const []const u8, name: []const u8) ?usize {
    for (among, 0..) |seen, i| {
        if (std.mem.eql(u8, seen, name)) return i;
    }
    return null;
}

/// What an `import` naming a module from a file is: the text it spells, and
/// the one edit that writes it.
pub const Import = struct {
    /// The path the import writes.
    path: []const u8,
    /// The name the import binds, which is the last element of that path. A
    /// slice of it.
    ///
    /// The elements of an import path are separated by dots, because they are
    /// what separates directories in the text an import writes -- so the last
    /// one is what follows the last dot, and never what follows the last
    /// separator of a filesystem path. `import mid.inner` binds `inner`, and a
    /// qualifier read off the path any other way spells a name nothing bound.
    binds: []const u8,
    edit: lsp.types.TextEdit,
    /// The import a `use` needs, as an edit of its own where it goes apart
    /// from the `use`; where the two sit together, `edit` writes both.
    imports: ?lsp.types.TextEdit = null,
    /// The path of the import the `use` needs, borrowed from the program, or
    /// null where the file already imports the module it names.
    import_path: ?[]const u8 = null,
};

/// The import a file would have to write to name the module the directory
/// `dir` is, or null where no import written there names it.
///
/// **The one answer to what naming a module from a file costs**, so a quick
/// fix and a completion cannot come to disagree about it. Which text names the
/// module is `workspace.importOf`, the inverse of the rule the loader follows;
/// where the text goes is `placementIn`, decided by the file's own shape. Both
/// answers are a client's to apply verbatim, and a second speller of either
/// would write an import the compiler refuses.
///
/// Costs what `importOf` costs and one conversion of an offset into a
/// position. The caller owns the text.
pub fn writingImport(
    gpa: std.mem.Allocator,
    root: []const u8,
    dir: []const u8,
    text: []const u8,
    place: Placement,
    encoding: lsp.offsets.Encoding,
) !?Import {
    const path = try workspace.importOf(gpa, root, dir) orelse return null;
    errdefer gpa.free(path);
    const at = lsp.offsets.indexToPosition(text, place.at, encoding);
    const last = if (std.mem.lastIndexOfScalar(u8, path, '.')) |dot| dot + 1 else 0;
    return .{
        .path = path,
        .binds = path[last..],
        .edit = .{
            .range = .{ .start = at, .end = at },
            .newText = try std.fmt.allocPrint(gpa, "{s}import {s}{s}", .{ place.lead, path, place.trail }),
        },
    };
}

/// The `use` that brings one trait into scope, and the edits writing it.
///
/// Which module the `use` names is the resolution's answer, the one the
/// checker's help gives: the import that passes the trait on, as that import
/// binds it, or else the module that reaches it on the shortest path, whose
/// import is written too.
pub fn writingUse(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    file: FileId,
    declares: DeclId,
    text: []const u8,
    place: Placement,
    encoding: lsp.offsets.Encoding,
) !Import {
    const ast = &program.ast;
    const route = res.useRoute(program, ast, file, declares);
    const name = ast.tokenText(ast.declName(declares));
    const at = lsp.offsets.indexToPosition(text, place.at, encoding);
    const path = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ route.module, name });
    errdefer gpa.free(path);
    const binds = path[route.module.len + 1 ..];

    const alone: Import = .{
        .path = path,
        .binds = binds,
        .edit = .{
            .range = .{ .start = at, .end = at },
            .newText = try std.fmt.allocPrint(gpa, "{s}use {s}{s}", .{ place.lead, path, place.trail }),
        },
    };
    const needed = route.import orelse return alone;
    const part = ast.partOfFile(file) orelse return alone;
    gpa.free(alone.edit.newText);
    const above = placementIn(ast, part, text);
    const from = lsp.offsets.indexToPosition(text, above.at, encoding);

    // A file with no `use` yet opens its group right below the imports, where
    // the new import goes too, so the two are written as one edit: the
    // import, a blank line, the `use`, and whatever spacing the import's own
    // placement leaves after it.
    if (above.at == place.at) {
        const after = above.trail[1..];
        return .{
            .path = path,
            .binds = binds,
            .edit = .{
                .range = .{ .start = from, .end = from },
                .newText = try std.fmt.allocPrint(gpa, "{s}import {s}\n\nuse {s}\n{s}", .{ above.lead, needed, path, after }),
            },
            .import_path = needed,
        };
    }
    const written = try std.fmt.allocPrint(gpa, "{s}use {s}{s}", .{ place.lead, path, place.trail });
    errdefer gpa.free(written);
    return .{
        .path = path,
        .binds = binds,
        .edit = .{ .range = .{ .start = at, .end = at }, .newText = written },
        .imports = .{
            .range = .{ .start = from, .end = from },
            .newText = try std.fmt.allocPrint(gpa, "{s}import {s}{s}", .{ above.lead, needed, above.trail }),
        },
        .import_path = needed,
    };
}

/// A `use` and the import it needs, if any, as edits to one document.
fn editsIn(gpa: std.mem.Allocator, uri: []const u8, writes: Import) !lsp.types.WorkspaceEdit {
    const count: usize = if (writes.imports != null) 2 else 1;
    const edits = try gpa.alloc(lsp.types.TextEdit, count);
    if (writes.imports) |first| edits[0] = first;
    edits[count - 1] = writes.edit;

    var changes: Changes = .empty;
    errdefer changes.deinit(gpa);
    try changes.put(gpa, uri, edits);
    return .{ .changes = .{ .map = changes } };
}

/// One edit, as an edit to one document.
fn editIn(
    gpa: std.mem.Allocator,
    uri: []const u8,
    edit: lsp.types.TextEdit,
) !lsp.types.WorkspaceEdit {
    const edits = try gpa.alloc(lsp.types.TextEdit, 1);
    edits[0] = edit;

    var changes: Changes = .empty;
    errdefer changes.deinit(gpa);
    try changes.put(gpa, uri, edits);
    return .{ .changes = .{ .map = changes } };
}

const Changes = std.StringArrayHashMapUnmanaged([]const lsp.types.TextEdit);

test "a trait quick fix uses the callers associated capability bounds" {
    const gpa = std.testing.allocator;
    const text =
        \\import models
        \\use models.Source
        \\use models.Marker
        \\fn _bounded[S: Source](value: Marker[S.Item]) -> UInt8 where S.Item: Copyable {
        \\    value.inspect()
        \\}
        \\fn main() -> UInt8 { 0 }
    ;
    const models =
        \\pub trait Source { type Item }
        \\pub struct Marker[phantom T] {}
        \\pub trait Inspect { fn inspect(self: Self) -> UInt8 }
        \\impl[T: Copyable] Inspect for Marker[T] {
        \\    fn inspect(_self: Self) -> UInt8 { 1 }
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = text },
        .{ .path = "models/models.lin", .text = models },
    }, "main.lin");
    defer checked.deinit();
    try std.testing.expectEqual(@as(u32, 1), checked.sink.error_count);
    try std.testing.expectEqual(Code.t_unknown_operation, checked.sink.items()[0].code.?);
    const at: u32 = @intCast(std.mem.indexOf(u8, text, "value.inspect()").?);
    const trait = try traitFor(gpa, &checked, checked.fileNamed("main.lin").?, at);
    try std.testing.expect(trait != null);
    try std.testing.expectEqualStrings("Inspect", checked.program.ast.tokenText(checked.program.ast.declName(trait.?)));
}

test "a trait quick fix propagates allocation failure while finding its trait" {
    const testing = std.testing;
    const gpa = testing.allocator;
    const text =
        \\import std.hash
        \\fn main() -> UInt8 {
        \\    let seat = UInt64(12)
        \\    UInt8(seat.hash() % 2)
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    var messages = std.heap.ArenaAllocator.init(gpa);
    defer messages.deinit();
    const a = messages.allocator();
    const publication = try @import("publish.zig").Publication.init(a, &checked);
    const diagnostics = try publication.forFile(a, checked.fileNamed("main.lin").?, .@"utf-16");
    var offered: std.ArrayList(lsp.types.CodeAction.Result) = .empty;
    try appendUses(a, &checked, checked.fileNamed("main.lin").?, text, "file:///main.lin", diagnostics, .@"utf-16", &offered);
    try testing.expectEqual(@as(usize, 1), offered.items.len);
    try testing.expectEqualStrings("use hash.Hash", offered.items[0].code_action.title);

    const trait = (try traitFor(gpa, &checked, checked.fileNamed("main.lin").?, @intCast(std.mem.indexOf(u8, text, "seat.hash").?))).?;
    const writes = try writingUse(gpa, &checked.program, &checked.semantics.res, checked.fileNamed("main.lin").?, trait, text, .{ .at = 0, .lead = "", .trail = "\n" }, .@"utf-16");
    defer gpa.free(writes.path);
    defer gpa.free(writes.edit.newText);
    try testing.expectEqualStrings("Hash", writes.binds);
    try testing.expectEqualStrings("use hash.Hash\n", writes.edit.newText);

    var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    var failed: std.ArrayList(lsp.types.CodeAction.Result) = .empty;
    defer failed.deinit(failing.allocator());
    try testing.expectError(error.OutOfMemory, appendUses(
        failing.allocator(),
        &checked,
        checked.fileNamed("main.lin").?,
        text,
        "file:///main.lin",
        diagnostics,
        .@"utf-16",
        &failed,
    ));
}
