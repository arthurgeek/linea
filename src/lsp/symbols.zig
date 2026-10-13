const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const positions = @import("positions.zig");
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const TokenId = @import("../lexer/token.zig").TokenId;
const FileId = @import("../support/source.zig").FileId;

/// What a client is told a declaration is.
///
/// A translation between two vocabularies and nothing else. Which kind of
/// declaration was written was settled by the parser, and a second opinion
/// here -- a name re-read to see whether it looks like a type, a body checked
/// for whether it is really a function -- would be a second parser that agrees
/// on every file anyone tried.
///
/// Exhaustive, with no `else`: a declaration form added to the language is
/// classified before the build succeeds.
///
/// `err` is the one that has none. A declaration the parser gave up on has no
/// name to show, and an outline entry with an empty name is one the protocol
/// forbids.
fn kindOf(tag: node.Decl.Tag) ?lsp.types.SymbolKind {
    return switch (tag) {
        .function => .Function,
        // A member reached through a bracket rather than through a call. The
        // protocol's `Property` is what it has for a member accessed as a
        // place, which is what a projection is.
        .projection => .Property,
        // A member naming the positions a walk runs through. Bound to an
        // expression and read by name nowhere, which is what the protocol's
        // `Constant` is closest to.
        .traversal_ => .Constant,
        .constant => .Constant,
        .enum_ => .Enum,
        .struct_ => .Struct,
        // An `impl` declares no name of its own -- it groups what a type can
        // do -- so it is the one entry that names something other than what it
        // declares. `Object` is what the protocol has for a grouping that is
        // neither a type nor a namespace.
        .impl_, .template_impl, .derive_impl => .Object,
        .trait_ => .Interface,
        // A name standing for a type, which is what the protocol's
        // `TypeParameter` is: what it stands for is settled elsewhere.
        .associated_type => .TypeParameter,
        // What an `import` binds is a module. What a `use` binds is one
        // declaration of another module, reached through its path; the
        // protocol has no kind for an alias, and a path element is what
        // `Namespace` renders.
        .import_ => .Module,
        .use_ => .Namespace,
        // A distinct nominal type over one base -- the protocol's `Struct` is
        // the nearest kind it has for a declared type with no members of its
        // own to enumerate.
        .newtype => .Struct,
        // Another name for a type, which the protocol has no kind for; a
        // name standing for a type is what `TypeParameter` renders.
        .alias => .TypeParameter,
        .err => null,
    };
}

/// Every declaration written in one file, as the outline a client draws.
///
/// Flat rather than nested: an `impl`'s members are declarations in their own
/// right and each carries its own extent, so a client shows them by where they
/// sit. Nesting them would be this module deciding which declarations belong
/// inside which, and the tree already says.
///
/// The declarations of that file and not of its module: an outline is drawn
/// beside one document, and a module's other files have outlines of their own.
///
/// Every name is copied into `gpa` rather than pointed at where it was
/// written. The answer is serialised after the caller has released the
/// analysis it was read from, so a name borrowed from the tree is a name
/// nobody owns by the time it is written out.
///
/// Costs one pass over the file's declarations, one sort of them, and one pass
/// over the file's bytes. Which declarations are the file's is the run the
/// tree recorded when it parsed it, so the cost is the document's and not the
/// program's -- a walk of every declaration in the compilation would be the
/// library's too, on every jump into a file. The last pass is what
/// `positionsOf` costs however many declarations ask about it, which is why
/// the offsets are gathered before any of them is converted rather than found
/// one at a time.
pub fn forFile(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    encoding: lsp.offsets.Encoding,
) ![]const lsp.types.DocumentSymbol {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return &.{};

    // Which declarations, and the four offsets each of them asks about,
    // gathered in one pass so the file is read once for all of them.
    var found: std.ArrayList(DeclId) = .empty;
    defer found.deinit(gpa);
    var offsets: std.ArrayList(u32) = .empty;
    defer offsets.deinit(gpa);

    for (part.decl_start..part.decl_end) |i| {
        const d = DeclId.at(@intCast(i));
        if (kindOf(ast.declTag(d)) == null) continue;
        if (ast.declName(d) == TokenId.none) continue;
        try found.append(gpa, d);
    }

    // In the order they were written, which is not the order they were built:
    // an `impl` is recorded once its members have been read, so the block
    // comes after what it contains. An outline is a picture of the file, and
    // a container listed below its contents is not one.
    std.mem.sort(DeclId, found.items, ast, struct {
        fn before(tree: *const @TypeOf(checked.program.ast), a: DeclId, b: DeclId) bool {
            return tree.declSpan(a).start < tree.declSpan(b).start;
        }
    }.before);

    for (found.items) |d| {
        const extent = ast.declSpan(d);
        const name = ast.declNameSpan(d);
        try offsets.appendSlice(gpa, &.{ extent.start, extent.end, name.start, name.end });
    }

    const at = try positions.positionsOf(gpa, part.source, offsets.items, encoding);
    defer gpa.free(at);

    const out = try gpa.alloc(lsp.types.DocumentSymbol, found.items.len);
    for (out, found.items, 0..) |*symbol, d, i| {
        // A tuple, unit or callable head has no name token: it is named as
        // written.
        const headed = ast.declTag(d) == .impl_ or ast.declTag(d) == .derive_impl;
        const name = if (headed) ast.implHeadText(d) else ast.tokenText(ast.declName(d));
        symbol.* = .{
            .name = try gpa.dupe(u8, name),
            .kind = kindOf(ast.declTag(d)).?,
            .range = .{ .start = at[i * 4], .end = at[i * 4 + 1] },
            .selectionRange = .{ .start = at[i * 4 + 2], .end = at[i * 4 + 3] },
        };
    }
    return out;
}

/// Releases an outline, which owns the names in it.
fn free(gpa: std.mem.Allocator, found: []const lsp.types.DocumentSymbol) void {
    for (found) |symbol| gpa.free(symbol.name);
    gpa.free(found);
}

test "an outline outlives the analysis it was read from" {
    const gpa = testing.allocator;

    var answers = std.heap.ArenaAllocator.init(gpa);
    defer answers.deinit();

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 {\n    0\n}\n" },
    }, "main.lin");

    const found = try forFile(answers.allocator(), &checked, checked.fileNamed("main.lin").?, .@"utf-16");

    // Overwrite the owned source before releasing it so a borrowed symbol
    // name cannot survive by accident.
    @memset(@constCast(checked.table.get(checked.fileNamed("main.lin").?).text), 0xAA);
    checked.deinit();

    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("main", found[0].name);
}

test "a symbol carries the kind the parser gave its declaration" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
        \\pub let limit: UInt8 = 9
        \\
        \\struct Account {
        \\    balance: UInt8,
        \\}
        \\
        \\enum Colour {
        \\    Red,
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
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ balance = limit }
        \\    Measure.of(a)
        \\}
        \\
        },
    }, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer free(gpa, found);

    // In the order they were written, so a `trait` and an `impl` each stand
    // above the members inside them -- which is not the order the parser
    // recorded them in, because a block's extent is not known until its
    // members have been read.
    const expected = [_]struct { name: []const u8, kind: lsp.types.SymbolKind }{
        .{ .name = "limit", .kind = .Constant },
        .{ .name = "Account", .kind = .Struct },
        .{ .name = "Colour", .kind = .Enum },
        .{ .name = "Measure", .kind = .Interface },
        .{ .name = "of", .kind = .Function },
        .{ .name = "Account", .kind = .Object },
        .{ .name = "of", .kind = .Function },
        .{ .name = "main", .kind = .Function },
    };
    try testing.expectEqual(expected.len, found.len);
    for (expected, found) |want, got| {
        try testing.expectEqualStrings(want.name, got.name);
        try testing.expectEqual(want.kind, got.kind);
    }
}

test "a symbol's ranges are where the declaration and its name sit" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 {\n    0\n}\n" },
    }, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 1), found.len);
    // The whole declaration, and then the four columns `main` occupies.
    try testing.expectEqual(lsp.types.Position{ .line = 0, .character = 0 }, found[0].range.start);
    try testing.expectEqual(lsp.types.Position{ .line = 2, .character = 1 }, found[0].range.end);
    try testing.expectEqual(lsp.types.Position{ .line = 0, .character = 3 }, found[0].selectionRange.start);
    try testing.expectEqual(lsp.types.Position{ .line = 0, .character = 7 }, found[0].selectionRange.end);
}

test "a unit implementation symbol names its complete head" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text =
        \\trait Value {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\
        \\impl Value for () {
        \\    fn value(_self: ()) -> UInt8 { 7 }
        \\}
        \\
        \\fn main() -> UInt8 { Value.value(()) }
        \\
    }}, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer free(gpa, found);

    for (found) |symbol| {
        if (symbol.kind != .Object) continue;
        try testing.expectEqualStrings("()", symbol.name);
        try testing.expectEqual(lsp.types.Position{ .line = 4, .character = 15 }, symbol.selectionRange.start);
        try testing.expectEqual(lsp.types.Position{ .line = 4, .character = 17 }, symbol.selectionRange.end);
        return;
    }
    return error.TestExpectedEqual;
}

test "a tuple implementation symbol names its complete head" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text =
        \\trait Value {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\
        \\impl Value for (UInt8, Bool) {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\
        \\fn main() -> UInt8 { 0 }
        \\
    }}, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer free(gpa, found);

    for (found) |symbol| {
        if (symbol.kind != .Object) continue;
        try testing.expectEqualStrings("(UInt8, Bool)", symbol.name);
        try testing.expectEqual(lsp.types.Position{ .line = 4, .character = 15 }, symbol.selectionRange.start);
        try testing.expectEqual(lsp.types.Position{ .line = 4, .character = 28 }, symbol.selectionRange.end);
        return;
    }
    return error.TestExpectedEqual;
}

test "a derive symbol selects the name its head applies, as an implementation's does" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text =
        \\trait Marker {}
        \\
        \\template impl Marker {}
        \\
        \\struct Box[T] {
        \\    value: T,
        \\}
        \\
        \\derive[T] Marker for Box[T]
        \\
        \\fn main() -> UInt8 { 0 }
        \\
    }}, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer free(gpa, found);

    for (found) |symbol| {
        if (symbol.kind != .Object or !std.mem.eql(u8, symbol.name, "Box")) continue;
        // The three columns `Box` occupies, not its argument list.
        try testing.expectEqual(lsp.types.Position{ .line = 8, .character = 21 }, symbol.selectionRange.start);
        try testing.expectEqual(lsp.types.Position{ .line = 8, .character = 24 }, symbol.selectionRange.end);
        return;
    }
    return error.TestExpectedEqual;
}

test "grouped derives remain one source symbol" {
    const gpa = testing.allocator;
    const text = @import("references.zig").structural_derive_source;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(checked.semantics.expanded.generated_sources.buffers.len > 0);

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer free(gpa, found);

    var box_groups: usize = 0;
    var solo_groups: usize = 0;
    var generated_groups: usize = 0;
    for (found) |symbol| {
        if (symbol.kind != .Object) continue;
        if (std.mem.eql(u8, symbol.name, "Box")) box_groups += 1;
        if (std.mem.eql(u8, symbol.name, "Solo")) solo_groups += 1;
        if (std.mem.eql(u8, symbol.name, "Generated")) generated_groups += 1;
    }
    try testing.expectEqual(@as(usize, 1), box_groups);
    try testing.expectEqual(@as(usize, 1), solo_groups);
    try testing.expectEqual(@as(usize, 1), generated_groups);
}

test "the outline is the file's declarations, not its module's" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 { helper() }\n" },
        .{ .path = "app/helper.lin", .text = "fn helper() -> UInt8 { 1 }\n" },
    }, "app");
    defer checked.deinit();

    var wanted: FileId = checked.fileNamed("app/main.lin").?;
    for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, "app/helper.lin")) wanted = f;
    }

    const found = try forFile(gpa, &checked, wanted, .@"utf-16");
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("helper", found[0].name);
    // The first line of *that* file, not wherever it sits in the module's
    // token stream.
    try testing.expectEqual(@as(u32, 0), found[0].range.start.line);
}
