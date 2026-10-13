const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const positions = @import("positions.zig");
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const TokenId = @import("../lexer/token.zig").TokenId;
const FileId = @import("../support/source.zig").FileId;

/// What a client is told a fold is.
///
/// The protocol names two categories and leaves everything else uncategorised,
/// which is what `plain` is: a client folds it and no command that folds "all
/// comments" or "all imports" reaches it.
const Kind = enum {
    plain,
    comment,
    imports,

    fn reported(self: Kind) ?lsp.types.FoldingRange.Kind {
        return switch (self) {
            .plain => null,
            .comment => .comment,
            .imports => .imports,
        };
    }
};

/// Whether a declaration's own extent is a fold.
///
/// Exhaustive, with no `else`: a declaration form added to the language is
/// classified before the build succeeds.
///
/// An `import` and a `use` are the two that are written at the top and are
/// still not folded here. The run of them folds as one thing, which is what
/// the protocol's `imports` category is for; a fold per declaration would put
/// a marker on every line of that run.
///
/// A constant is not folded because it writes no braces of its own: what it
/// binds is an expression, and the block forms inside one are folded as
/// blocks wherever they sit.
fn foldsAsBody(tag: node.Decl.Tag) bool {
    return switch (tag) {
        .function, .projection, .enum_, .struct_, .impl_, .template_impl, .trait_ => true,
        // A declared type is one line and writes no braces of its own. A
        // newtype writes no braces either -- its refinement clause may sit on
        // its own line, but that is a clause growing, not a body opening.
        // A traversal writes no braces of its own either: what it names is an
        // expression, folded wherever a block form inside one sits.
        .constant, .derive_impl, .import_, .use_, .associated_type, .traversal_, .newtype, .alias => false,
        // A declaration the parser gave up on has no extent anyone wrote.
        .err => false,
    };
}

/// Whether a declaration binds another module's name into this file, which is
/// what the run at the top of a file is made of.
fn opensAModule(tag: node.Decl.Tag) bool {
    return tag == .import_ or tag == .use_;
}

/// One fold, as lines.
const Fold = struct {
    start: u32,
    end: u32,
    kind: Kind,
};

fn beforeInFile(_: void, a: Fold, b: Fold) bool {
    if (a.start != b.start) return a.start < b.start;
    if (a.end != b.end) return a.end < b.end;
    return @intFromEnum(a.kind) < @intFromEnum(b.kind);
}

fn declaredBefore(ast: *const Ast, a: DeclId, b: DeclId) bool {
    return ast.declSpan(a).start < ast.declSpan(b).start;
}

/// Every region of one file a client may collapse.
///
/// Nothing here decides what nests. A declaration's extent and a block's are
/// recorded by the parser and read from the tree, exactly as the outline reads
/// them, so a fold and a symbol cannot disagree about where a declaration
/// ends. The two categories the protocol names are the two this file finds for
/// itself -- a run of comments and the run of imports a file opens with -- and
/// both are read off what the lexer and the parser already produced.
///
/// Lines only. The protocol's fold is a pair of line numbers with optional
/// character offsets, and a fold that stops short of the end of its last line
/// is a fold no editor draws differently; leaving them out is also what a
/// client reporting `lineFoldingOnly` asks for.
///
/// A fold that opens and closes on one line is not reported: collapsing it
/// hides nothing.
///
/// Costs one pass over the file's declarations, one over its expressions, one
/// over its tokens and one over its bytes, plus a sort of its own folds. Each
/// run is the one the tree recorded when it parsed the file, so a fold refresh
/// costs the document and not the compilation. Every table here is as long as
/// the file's folds or the file's declarations, never as long as the program.
pub fn forFile(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    encoding: lsp.offsets.Encoding,
) ![]const lsp.types.FoldingRange {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return &.{};

    // What each fold is, and the two offsets each of them asks about,
    // gathered in one pass so the file is read once for all of them.
    var kinds: std.ArrayList(Kind) = .empty;
    defer kinds.deinit(gpa);
    var offsets: std.ArrayList(u32) = .empty;
    defer offsets.deinit(gpa);

    // The file's declarations, in the order they were written -- which is not
    // the order they were built, because an `impl` is recorded once its
    // members have been read. The run of imports is a prefix of what someone
    // wrote, so the order has to be the source's.
    var decls: std.ArrayList(DeclId) = .empty;
    defer decls.deinit(gpa);
    for (part.decl_start..part.decl_end) |i| {
        try decls.append(gpa, DeclId.at(@intCast(i)));
    }
    std.mem.sort(DeclId, decls.items, ast, declaredBefore);

    for (decls.items) |d| {
        if (ast.declDelegation(d) != .none or !foldsAsBody(ast.declTag(d))) continue;
        const extent = ast.declSpan(d);
        try kinds.append(gpa, .plain);
        try offsets.appendSlice(gpa, &.{ extent.start, extent.end });
    }

    var opening: usize = 0;
    while (opening < decls.items.len and opensAModule(ast.declTag(decls.items[opening]))) opening += 1;
    if (opening > 0) {
        const first = ast.declSpan(decls.items[0]);
        const last = ast.declSpan(decls.items[opening - 1]);
        try kinds.append(gpa, .imports);
        try offsets.appendSlice(gpa, &.{ first.start, last.end });
    }

    // Every block: an `if` arm, a `while` body, a `match` arm that writes
    // one, and an ordinary block. One tag rather than a list of the forms
    // that hold one, because a form added later holds its body the same way.
    for (part.expr_start..part.expr_end) |i| {
        const e = ExprId.at(@intCast(i));
        if (ast.exprTag(e) != .block) continue;
        const extent = ast.exprSpan(e);
        try kinds.append(gpa, .plain);
        try offsets.appendSlice(gpa, &.{ extent.start, extent.end });
    }

    // Runs of comments, read off the token stream rather than the bytes: a
    // comment is a token, so which runs of bytes are comments was settled
    // when the file was lexed.
    //
    // Two comments continue one run when they are neighbours in the stream
    // and exactly one newline separates them. Both conditions are needed:
    // adjacent comments with a blank line between them are two runs, and a
    // comment trailing code is not the start of the run below it.
    var at = part.token_start;
    while (at < part.token_end) : (at += 1) {
        if (ast.tokenTag(TokenId.at(at)) != .comment) continue;
        const opened = ast.tokenSpan(TokenId.at(at));
        var closed = opened;
        while (at + 1 < part.token_end and ast.tokenTag(TokenId.at(at + 1)) == .comment) {
            const next = ast.tokenSpan(TokenId.at(at + 1));
            if (std.mem.count(u8, part.source[closed.end..next.start], "\n") != 1) break;
            closed = next;
            at += 1;
        }
        try kinds.append(gpa, .comment);
        try offsets.appendSlice(gpa, &.{ opened.start, closed.end });
    }

    const lines = try positions.positionsOf(gpa, part.source, offsets.items, encoding);
    defer gpa.free(lines);

    var found: std.ArrayList(Fold) = .empty;
    defer found.deinit(gpa);
    for (kinds.items, 0..) |kind, i| {
        const start = lines[i * 2].line;
        const end = lines[i * 2 + 1].line;
        if (start >= end) continue;
        try found.append(gpa, .{ .start = start, .end = end, .kind = kind });
    }

    // Sorted so that an answer is the file read top to bottom, and so that a
    // repeat sits beside what it repeats. A function and its body are the
    // same lines whenever the brace opens on the declaration's own line, and
    // a client offered one fold twice draws two markers on one line.
    std.mem.sort(Fold, found.items, {}, beforeInFile);

    var out: std.ArrayList(lsp.types.FoldingRange) = .empty;
    for (found.items, 0..) |f, i| {
        if (i > 0 and std.meta.eql(found.items[i - 1], f)) continue;
        try out.append(gpa, .{
            .startLine = f.start,
            .endLine = f.end,
            .kind = f.kind.reported(),
        });
    }
    return out.toOwnedSlice(gpa);
}

test "a declaration and the blocks inside it each fold once" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
        \\fn main() -> UInt8 {
        \\    var n: UInt8 = 0
        \\    while n < 1 {
        \\        n = n + 1
        \\    }
        \\    n
        \\}
        \\
        },
    }, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(found);

    // The function, whose body block is the same lines and is not reported a
    // second time, and the `while` body.
    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqual(@as(u32, 0), found[0].startLine);
    try testing.expectEqual(@as(u32, 6), found[0].endLine);
    try testing.expectEqual(@as(?lsp.types.FoldingRange.Kind, null), found[0].kind);
    try testing.expectEqual(@as(u32, 2), found[1].startLine);
    try testing.expectEqual(@as(u32, 4), found[1].endLine);
}

test "a fold that opens and closes on one line is not reported" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 { 0 }\n" },
    }, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(found);

    try testing.expectEqual(@as(usize, 0), found.len);
}

test "bodyless grouped derives do not fold" {
    const gpa = testing.allocator;
    const text = @import("references.zig").structural_derive_source;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(checked.semantics.expanded.generated_sources.buffers.len > 0);

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(found);

    const expected = [_]struct { start: u32, end: u32 }{
        .{ .start = 3, .end = 5 },
        .{ .start = 7, .end = 8 },
        .{ .start = 25, .end = 27 },
        .{ .start = 28, .end = 30 },
        .{ .start = 36, .end = 39 },
    };
    try testing.expectEqual(expected.len, found.len);
    for (expected, found) |want, fold| {
        try testing.expectEqual(want.start, fold.startLine);
        try testing.expectEqual(want.end, fold.endLine);
        try testing.expectEqual(@as(?lsp.types.FoldingRange.Kind, null), fold.kind);
    }
}

test "consecutive comments fold as one run, and a blank line ends it" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
        \\// one
        \\// two
        \\
        \\// alone
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\
        },
    }, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(found);

    // The run of two, and the function. The comment on its own covers one
    // line, and the one below it is separated by a blank line, so neither is
    // a fold.
    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqual(@as(u32, 0), found[0].startLine);
    try testing.expectEqual(@as(u32, 1), found[0].endLine);
    try testing.expectEqual(@as(?lsp.types.FoldingRange.Kind, .comment), found[0].kind);
    try testing.expectEqual(@as(u32, 4), found[1].startLine);
}

test "the run of imports a file opens with folds as one" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text =
        \\import app.counters
        \\
        \\use counters.one
        \\
        \\fn main() -> UInt8 {
        \\    one()
        \\}
        \\
        },
        .{ .path = "app/counters/tally.lin", .text = "pub fn one() -> UInt8 {\n    1\n}\n" },
    }, "app");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("app/main.lin").?, .@"utf-16");
    defer gpa.free(found);

    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqual(@as(?lsp.types.FoldingRange.Kind, .imports), found[0].kind);
    try testing.expectEqual(@as(u32, 0), found[0].startLine);
    try testing.expectEqual(@as(u32, 2), found[0].endLine);
}

test "a file of a module folds by its own declarations" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 {\n    helper()\n}\n" },
        .{ .path = "app/helper.lin", .text = "fn helper() -> UInt8 {\n    1\n}\n" },
    }, "app");
    defer checked.deinit();

    var wanted: FileId = checked.fileNamed("app/main.lin").?;
    for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, "app/helper.lin")) wanted = f;
    }

    const found = try forFile(gpa, &checked, wanted, .@"utf-16");
    defer gpa.free(found);

    // One fold, on the first line of *that* file rather than wherever the
    // declaration sits in the module's token stream.
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqual(@as(u32, 0), found[0].startLine);
    try testing.expectEqual(@as(u32, 2), found[0].endLine);
}

test "field delegation without braces does not fold subsequent declarations" {
    const gpa = testing.allocator;
    const text =
        \\struct Board { scores: [UInt8; 2] }
        \\impl Index[UInt64]
        \\    for Board
        \\    via scores
        \\impl Board {
        \\    trav positions via scores
        \\}
        \\fn main() -> UInt8 {
        \\    let board: Board = .{ scores = [1, 2] }
        \\    board[UInt64(0)]
        \\}
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(found);
    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqual(@as(u32, 4), found[0].startLine);
    try testing.expectEqual(@as(u32, 6), found[0].endLine);
    try testing.expectEqual(@as(u32, 7), found[1].startLine);
    try testing.expectEqual(@as(u32, 10), found[1].endLine);
}
