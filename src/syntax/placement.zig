//! Where a written `import` or `use` goes in a file, decided by the file's
//! own shape. One answer for every writer of one: a quick fix, a completion,
//! and a help's fix.

const std = @import("std");
const ast_mod = @import("ast.zig");
const Ast = ast_mod.Ast;
const DeclId = @import("node.zig").DeclId;
const Span = @import("../support/span.zig").Span;

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

/// The bytes that removing the declaration written at `span` takes out of
/// `text`: its whole lines, the comment lines directly above it, which are
/// written about it, and one blank line above those where one separates it
/// from what precedes, so what is left reads as if it had never been written.
///
/// Only the lines the declaration has to itself. Code written before it on
/// its first line keeps that line, and the declaration goes with the spaces
/// before it; code written after it on its last line, such as the `}`
/// closing what holds it, stays, starting the line the declaration began.
pub fn removal(text: []const u8, span: Span) Span {
    const first = lineStart(text, span.start);
    if (std.mem.trim(u8, text[first..span.start], " \t").len != 0) {
        var start = span.start;
        while (start > first and (text[start - 1] == ' ' or text[start - 1] == '\t')) start -= 1;
        return .{ .start = start, .end = span.end };
    }
    var start = aboveComments(text, first);
    if (start > 0) {
        const previous = lineStart(text, start - 1);
        if (std.mem.trim(u8, text[previous .. start - 1], " \t\r").len == 0) start = previous;
    }
    const after = lineAfter(text, span.end);
    const rest = std.mem.trim(u8, text[span.end..after], " \t\r\n");
    if (rest.len == 0 or std.mem.startsWith(u8, rest, "//")) return .{ .start = start, .end = after };
    var end = span.end;
    while (end < after and (text[end] == ' ' or text[end] == '\t')) end += 1;
    return .{ .start = start, .end = end };
}

test removal {
    const text =
        \\impl Named for Station {
        \\    fn name(self: Self) -> Str { "" }
        \\
        \\    // Written about `label`.
        \\    fn label(self: Self) -> Str { "" }
        \\}
        \\
    ;
    const at: u32 = @intCast(std.mem.indexOf(u8, text, "fn label").?);
    const end: u32 = @intCast(std.mem.indexOf(u8, text, "\"\" }\n}").? + 4);
    const gone = removal(text, .{ .start = at, .end = end });
    const left = try std.mem.concat(std.testing.allocator, u8, &.{ text[0..gone.start], text[gone.end..] });
    defer std.testing.allocator.free(left);
    try std.testing.expectEqualStrings(
        \\impl Named for Station {
        \\    fn name(self: Self) -> Str { "" }
        \\}
        \\
    , left);
}

test "a removal leaves the code sharing the declaration's lines" {
    const gpa = std.testing.allocator;
    const after =
        \\impl Named for Station {
        \\    fn name(self: Self) -> Str { "" }
        \\
        \\    fn label(self: Self) -> Str { "" } }
        \\
    ;
    const at: u32 = @intCast(std.mem.indexOf(u8, after, "fn label").?);
    const gone = removal(after, .{ .start = at, .end = at + @as(u32, @intCast("fn label(self: Self) -> Str { \"\" }".len)) });
    const left = try std.mem.concat(gpa, u8, &.{ after[0..gone.start], after[gone.end..] });
    defer gpa.free(left);
    try std.testing.expectEqualStrings(
        \\impl Named for Station {
        \\    fn name(self: Self) -> Str { "" }
        \\}
        \\
    , left);

    const before = "impl Named for Station { fn label(self: Self) -> Str { \"\" }\n}\n";
    const from: u32 = @intCast(std.mem.indexOf(u8, before, "fn label").?);
    const cut = removal(before, .{ .start = from, .end = from + @as(u32, @intCast("fn label(self: Self) -> Str { \"\" }".len)) });
    const kept = try std.mem.concat(gpa, u8, &.{ before[0..cut.start], before[cut.end..] });
    defer gpa.free(kept);
    try std.testing.expectEqualStrings("impl Named for Station {\n}\n", kept);
}
