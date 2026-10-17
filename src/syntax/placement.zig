//! Where a written `import` or `use` goes in a file, decided by the file's
//! own shape. One answer for every writer of one: a quick fix, a completion,
//! and a help's fix.

const std = @import("std");
const ast_mod = @import("ast.zig");
const Ast = ast_mod.Ast;
const DeclId = @import("node.zig").DeclId;

/// Where an import is written into a file, and what surrounds it there.
pub const Placement = struct {
    at: u32,
    lead: []const u8,
    trail: []const u8,
};

/// Where a `use` goes in a file, decided by the file's own shape.
///
/// Beside the ones already written, where there are any: a `use` names a
/// declaration of a module an import bound, so the group of them sits below
/// the imports and above everything else, and a new one joins that group
/// rather than opening a second.
///
/// A file with no `use` at all starts the group after the imports, separated
/// from them by the blank line canonical Linea writes there. With neither, the
/// import placement answers -- a file with nothing to reach through has
/// nowhere better to put it, and the module it names has to be imported for
/// the `use` to mean anything anyway.
///
/// Costs one pass over the file's declarations, as the import placement does.
pub fn placementForUse(ast: *const Ast, part: *const ast_mod.FilePart, text: []const u8) Placement {
    var last_use: ?u32 = null;

    for (part.decl_start..part.decl_end) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) != .use_) continue;
        const span = ast.declSpan(d);
        if (last_use == null or span.end > last_use.?) last_use = span.end;
    }

    if (last_use) |end| {
        const at = lineAfter(text, end);
        const lead: []const u8 = if (at == text.len and text.len > 0 and text[text.len - 1] != '\n') "\n" else "";
        return .{ .at = at, .lead = lead, .trail = "\n" };
    }

    // No group yet, so one opens below the imports.
    const after = placementIn(ast, part, text);
    return .{ .at = after.at, .lead = "\n", .trail = "\n" };
}

/// Where an `import` goes in a file, decided by the file's own shape.
///
/// The grammar makes imports a prefix of a file -- `file ::= import*
/// declaration*` -- so a new one joins the prefix: on the line after the last
/// import the file already has.
///
/// A file with none has its prefix begin above the first declaration, and
/// above the comment block written directly on it, because a comment written
/// directly above a declaration is written about it. A blank line separates
/// the prefix from what follows, which is how canonical Linea writes one.
///
/// Costs one pass over the file's declarations and one over the lines above
/// the first of them.
pub fn placementIn(ast: *const Ast, part: *const ast_mod.FilePart, text: []const u8) Placement {
    var last_import: ?u32 = null;
    var first_decl: ?u32 = null;

    for (part.decl_start..part.decl_end) |i| {
        const d = DeclId.at(@intCast(i));
        const span = ast.declSpan(d);
        if (ast.declTag(d) == .import_) {
            if (last_import == null or span.end > last_import.?) last_import = span.end;
        }
        if (first_decl == null or span.start < first_decl.?) first_decl = span.start;
    }

    if (last_import) |end| {
        const at = lineAfter(text, end);
        // A file whose last line has no newline of its own needs one, or the
        // import joins the line already there.
        const lead: []const u8 = if (at == text.len and text.len > 0 and text[text.len - 1] != '\n') "\n" else "";
        return .{ .at = at, .lead = lead, .trail = "\n" };
    }

    const first = first_decl orelse return .{ .at = 0, .lead = "", .trail = "\n" };
    return .{ .at = aboveComments(text, lineStart(text, first)), .lead = "", .trail = "\n\n" };
}

/// The offset just past the next line break at or after `from`.
fn lineAfter(text: []const u8, from: u32) u32 {
    const nl = std.mem.indexOfScalarPos(u8, text, from, '\n') orelse return @intCast(text.len);
    return @intCast(nl + 1);
}

/// The offset the line holding `at` begins at.
fn lineStart(text: []const u8, at: u32) u32 {
    const nl = std.mem.lastIndexOfScalar(u8, text[0..at], '\n') orelse return 0;
    return @intCast(nl + 1);
}

/// The offset the run of comment lines directly above `line` begins at, or
/// `line` where nothing is written directly above it.
fn aboveComments(text: []const u8, line: u32) u32 {
    var at = line;
    while (at > 0) {
        const previous = lineStart(text, at - 1);
        const written = std.mem.trim(u8, text[previous .. at - 1], " \t\r");
        if (!std.mem.startsWith(u8, written, "//")) break;
        at = previous;
    }
    return at;
}
