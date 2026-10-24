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
const Edit = @import("../diagnostics/diagnostic.zig").Edit;
const Fix = @import("../diagnostics/diagnostic.zig").Fix;
const publish = @import("publish.zig");
const uri_mod = @import("uri.zig");
const placement = @import("../syntax/placement.zig");
const Placement = placement.Placement;
const placementIn = placement.placementIn;
const placementForUse = placement.placementForUse;

/// Every quick fix offered for the diagnostics a request carried: one
/// action per `Fix` the compiler attached to each of them, titled with the
/// help it writes.
///
/// **The compiler answers what edit fixes a diagnostic**, and this only
/// spells its answer for a client. A request's diagnostic is matched to the
/// compiler's by what was published for it -- range, rule and message -- so
/// an action is offered only for a problem the client is showing.
///
/// Allocated from the allocator handed in, which for a request is the
/// message's arena, and released with it.
///
/// **Bound:** the file's diagnostics, once per diagnostic the request
/// carried.
pub fn forFile(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    uri: []const u8,
    diagnostics: []const lsp.types.Diagnostic,
    encoding: lsp.offsets.Encoding,
) ![]const lsp.types.CodeAction.Result {
    const publication = try publish.Publication.init(gpa, checked);
    const published = try publication.forFile(gpa, file, encoding);
    const reported = publication.reportedIn(file);

    var offered: std.ArrayList(lsp.types.CodeAction.Result) = .empty;
    errdefer offered.deinit(gpa);
    for (diagnostics) |d| {
        for (published, reported) |p, r| {
            if (!samePublished(p, d)) continue;
            for (r.fixes) |f| try offered.append(gpa, .{ .code_action = .{
                .title = if (f.note) |at| r.notes[at] else r.primaryLabel().?.message,
                .kind = .quickfix,
                .diagnostics = try gpa.dupe(lsp.types.Diagnostic, &.{d}),
                .edit = try editOf(gpa, checked, file, uri, f, encoding),
            } });
            break;
        }
    }
    return offered.toOwnedSlice(gpa);
}

/// Whether a request's diagnostic is the one published as `p`.
fn samePublished(p: lsp.types.Diagnostic, d: lsp.types.Diagnostic) bool {
    if (!std.meta.eql(p.range, d.range)) return false;
    if (!std.mem.eql(u8, p.message, d.message)) return false;
    const pc = p.code orelse return d.code == null;
    const dc = d.code orelse return false;
    return switch (pc) {
        .string => |a| dc == .string and std.mem.eql(u8, a, dc.string),
        .number => |a| dc == .number and a == dc.number,
    };
}

/// A fix's edits as one change to the documents they edit: `file` under the
/// request's own `uri`, any other under its path's.
fn editOf(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    uri: []const u8,
    f: Fix,
    encoding: lsp.offsets.Encoding,
) !lsp.types.WorkspaceEdit {
    var changes: Changes = .empty;
    errdefer changes.deinit(gpa);
    var lists: std.ArrayList(std.ArrayList(lsp.types.TextEdit)) = .empty;
    var keys: std.ArrayList(FileId) = .empty;
    for (f.edits) |e| {
        const at = std.mem.indexOfScalar(FileId, keys.items, e.file) orelse at: {
            try keys.append(gpa, e.file);
            try lists.append(gpa, .empty);
            break :at keys.items.len - 1;
        };
        try lists.items[at].append(gpa, textEdit(checked.table.get(e.file).text, e, encoding));
    }
    for (keys.items, lists.items) |k, list| {
        const named = if (k == file) uri else try uri_mod.uriOf(gpa, checked.table.get(k).path);
        try changes.put(gpa, named, list.items);
    }
    return .{ .changes = .{ .map = changes } };
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

/// The `use` that brings one trait into scope, and the edits writing it, as
/// `typecheck.useWriting` writes them for the checker's fix.
pub fn writingUse(
    gpa: std.mem.Allocator,
    program: *const program_mod.Program,
    res: *const Resolution,
    file: FileId,
    declares: DeclId,
    text: []const u8,
    encoding: lsp.offsets.Encoding,
) !Import {
    const writing = try typecheck.useWriting(gpa, program, &program.ast, res, file, declares);
    errdefer gpa.free(writing.path);
    const edits = writing.edits();
    errdefer for (edits) |e| gpa.free(e.text);
    const last = if (std.mem.lastIndexOfScalar(u8, writing.path, '.')) |dot| dot + 1 else 0;
    const written = edits[edits.len - 1];
    return .{
        .path = writing.path,
        .binds = writing.path[last..],
        .edit = textEdit(text, written, encoding),
        .imports = if (edits.len == 2) textEdit(text, edits[0], encoding) else null,
        .import_path = writing.import_path,
    };
}

/// A compiler edit of `text` as the edit a client applies.
fn textEdit(text: []const u8, edit: Edit, encoding: lsp.offsets.Encoding) lsp.types.TextEdit {
    return .{
        .range = .{
            .start = lsp.offsets.indexToPosition(text, edit.span.start, encoding),
            .end = lsp.offsets.indexToPosition(text, edit.span.end, encoding),
        },
        .newText = edit.text,
    };
}

const Changes = std.StringArrayHashMapUnmanaged([]const lsp.types.TextEdit);
