const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const positions = @import("positions.zig");
const references = @import("references.zig");
const uri_mod = @import("uri.zig");
const BindingId = @import("../sema/resolve.zig").BindingId;
const TokenId = @import("../lexer/token.zig").TokenId;
const FileId = @import("../support/source.zig").FileId;

/// Where the name under a cursor was declared, or null where nothing there
/// names anything.
///
/// Two lookups and no search. Which binding the cursor reached is `namedAt`'s
/// answer, and where that was declared is the token the resolver recorded when
/// it bound the name -- so nothing here matches a spelling against a
/// declaration, and a re-export, a shadowed local and a name the prelude offers
/// each reach whatever the resolver said rather than whatever is spelled alike.
///
/// The binding is asked for where `references` and `rename` ask for it, and not
/// worked out again. A capability that followed a name the others do not would
/// send a reader to a declaration nothing else agrees is the one.
///
/// A name reaching nothing is answered as nothing. So is a primitive, which is
/// the one binding introduced at no token: `UInt8` is declared nowhere, and a
/// server that pointed at the first mention of it would be inventing a
/// declaration.
///
/// Costs one pass over the document's bytes to reach the cursor, a binary
/// search over the file's own tokens, constant work to reach the binding, and
/// one pass over the declaring file's bytes to place the range. Nothing here
/// is sized by what the program holds.
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
) !?lsp.types.Location {
    const ast = &checked.program.ast;

    // An embed's path is defined by the file it names, opened at its start.
    if (try embeddedAt(gpa, checked, file, position, encoding)) |opened| return opened;

    const named = references.namedAt(checked, file, position, encoding);
    const token = if (named == BindingId.none)
        references.sourceNameAt(checked, file, position, encoding)
    else
        checked.semantics.res.declaringToken(named);
    if (token == TokenId.none) return null;

    const wrote_it = ast.partOf(token);
    const opens = try uri_mod.openable(gpa, io, checked, wrote_it.file, root) orelse return null;

    return .{
        .uri = opens,
        .range = positions.rangeOf(wrote_it.source, ast.tokenSpan(token), encoding),
    };
}

/// The file an embed under the cursor read, or null where the cursor sits on
/// no embed that read one.
fn embeddedAt(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    position: lsp.types.Position,
    encoding: lsp.offsets.Encoding,
) !?lsp.types.Location {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return null;
    const found = checked.cursors.atPosition(ast, part, position, encoding) orelse return null;
    const e = switch (found.node) {
        .expr => |e| e,
        else => return null,
    };
    const read = checked.program.embeds.of(e) orelse return null;
    if (read == .none) return null;
    return .{
        .uri = try uri_mod.uriOf(gpa, checked.program.embeds.files[read.index()].path),
        .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 0, .character = 0 } },
    };
}

const local_program =
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

/// Where a byte of a case's text sits, as the protocol names it.
fn at(text: []const u8, offset: usize) lsp.types.Position {
    return lsp.offsets.indexToPosition(text, offset, .@"utf-16");
}

/// What the answer names, as the text it points at -- which is the one reading
/// that says the range is the declaration and not merely somewhere in the file.
fn declared(
    checked: *const Analysis,
    found: lsp.types.Location,
) []const u8 {
    var it = @import("publish.zig").files(&checked.program);
    while (it.next()) |file| {
        const entry = checked.table.get(file);
        if (!std.mem.endsWith(u8, found.uri, entry.path)) continue;
        return lsp.offsets.rangeToSlice(entry.text, found.range, .@"utf-16");
    }
    return "";
}

test "a name reaches the declaration the resolver gave it" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();

    // The local, used as the block's tail.
    const tail = std.mem.lastIndexOf(u8, local_program, "total").?;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, tail + 1), .@"utf-16", "")).?;
    defer gpa.free(found.uri);

    try testing.expectEqualStrings("total", declared(&checked, found));
    try testing.expectEqual(@as(u32, 5), found.range.start.line);
}

test "a cursor on what names nothing reaches nothing" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();

    const literal = std.mem.indexOf(u8, local_program, "add(1, 2)").? + 4;
    try testing.expectEqual(
        @as(?lsp.types.Location, null),
        try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, literal), .@"utf-16", ""),
    );
}

test "a cursor on a declaration reaches that declaration" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = local_program },
    }, "main.lin");
    defer checked.deinit();

    // Which binding a cursor reached is one question, and a cursor on the token
    // a name was declared at reached that name. Answering nothing there would
    // be this capability following a name the others do not.
    const wrote = std.mem.indexOf(u8, local_program, "total").?;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(local_program, wrote + 1), .@"utf-16", "")).?;
    defer gpa.free(found.uri);

    try testing.expectEqualStrings("total", declared(&checked, found));
    try testing.expectEqual(@as(u32, 5), found.range.start.line);
}

test "a written type reaches the declaration the resolver gave it" {
    const gpa = testing.allocator;

    // An annotation is a written type rather than an expression, and the
    // declaration it reaches is the one the resolver settled it on.
    const text =
        \\struct Point {
        \\    x: UInt8,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let p: Point = .{ x = 1 }
        \\    p.x
        \\}
        \\
    ;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const annotation = std.mem.lastIndexOf(u8, text, "Point").?;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, annotation + 1), .@"utf-16", "")).?;
    defer gpa.free(found.uri);

    try testing.expectEqualStrings("Point", declared(&checked, found));
    try testing.expectEqual(@as(u32, 0), found.range.start.line);
}

test "a generic alias heading a path reaches the alias, and the operation after it reaches the type's own" {
    const gpa = testing.allocator;

    const text =
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
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const head = std.mem.indexOf(u8, text, "Slot.wrap").?;
    const alias = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, head + 1), .@"utf-16", "")).?;
    defer gpa.free(alias.uri);
    try testing.expectEqualStrings("Slot", declared(&checked, alias));

    const operation = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, head + 6), .@"utf-16", "")).?;
    defer gpa.free(operation.uri);
    try testing.expectEqualStrings("wrap", declared(&checked, operation));
}

test "structural derive source names reach source declarations" {
    const gpa = testing.allocator;
    const text = references.structural_derive_source;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(checked.semantics.expanded.generated_sources.buffers.len > 0);

    const Case = struct {
        cursor: []const u8,
        within: usize,
        declared_name: []const u8,
    };
    const cases = [_]Case{
        .{ .cursor = "    Inspect[UInt64]", .within = 5, .declared_name = "Inspect" },
        .{ .cursor = "    Marker[T]", .within = 5, .declared_name = "Marker" },
        .{ .cursor = "reflect.components: Lookup", .within = 21, .declared_name = "Lookup" },
        .{ .cursor = ") for Box[T]", .within = 7, .declared_name = "Box" },
        .{ .cursor = ") for Box[T]", .within = 10, .declared_name = "T" },
        .{ .cursor = "T.Item: Lookup", .within = 3, .declared_name = "Item" },
    };

    for (cases) |case| {
        const cursor = std.mem.indexOf(u8, text, case.cursor).? + case.within;
        const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, cursor), .@"utf-16", "")).?;
        defer gpa.free(found.uri);
        try testing.expectEqualStrings(case.declared_name, declared(&checked, found));
        try testing.expect(std.mem.endsWith(u8, found.uri, "main.lin"));
    }

    const primitive = std.mem.indexOf(u8, text, "reflect.components: Lookup[UInt64]").? + 27;
    try testing.expectEqual(
        @as(?lsp.types.Location, null),
        try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, primitive), .@"utf-16", ""),
    );
}

test "a qualified trait reference reaches its declaration" {
    const gpa = testing.allocator;
    const main_text =
        \\import protocol
        \\
        \\struct Item {}
        \\impl protocol.Marker for Item {}
        \\
        \\fn main() -> UInt8 { 0 }
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
    const found = (try forPosition(gpa, testing.io, &checked, main_file, at(main_text, marker), .@"utf-16", "")).?;
    defer gpa.free(found.uri);

    try testing.expectEqualStrings("Marker", declared(&checked, found));
    try testing.expect(std.mem.endsWith(u8, found.uri, "app/protocol/protocol.lin"));
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

test "a call written with a dot reaches what the call written out reaches" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = both_spellings },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    // Two spellings of one call, and nothing below the tree tells them apart:
    // a reader pointing at either is pointing at the operation the trait
    // declares.
    const dotted = std.mem.indexOf(u8, both_spellings, "b.of(1)").? + 2;
    const written = std.mem.indexOf(u8, both_spellings, "Measure.of(a, 4)").? + 8;

    const through_dot = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(both_spellings, dotted), .@"utf-16", "")).?;
    defer gpa.free(through_dot.uri);
    const spelled_out = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(both_spellings, written), .@"utf-16", "")).?;
    defer gpa.free(spelled_out.uri);

    try testing.expectEqualStrings("of", declared(&checked, through_dot));
    try testing.expectEqualStrings(spelled_out.uri, through_dot.uri);
    try testing.expectEqual(spelled_out.range, through_dot.range);
}

test "a name declared in a sibling file reaches that file" {
    const gpa = testing.allocator;

    const main_text = "fn main() -> UInt8 {\n    size()\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = main_text },
        .{ .path = "app/sizes.lin", .text = "fn size() -> UInt8 {\n    1\n}\n" },
    }, "app");
    defer checked.deinit();

    var wanted: FileId = checked.fileNamed("app/main.lin").?;
    for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, "app/main.lin")) wanted = f;
    }

    const call = std.mem.indexOf(u8, main_text, "size()").? + 1;
    const found = (try forPosition(gpa, testing.io, &checked, wanted, at(main_text, call), .@"utf-16", "")).?;
    defer gpa.free(found.uri);

    try testing.expect(std.mem.endsWith(u8, found.uri, "app/sizes.lin"));
    try testing.expectEqualStrings("size", declared(&checked, found));
}

/// The file of the analysis whose path ends this way, or null where the module
/// holds none.
fn fileEnding(checked: *const Analysis, suffix: []const u8) ?FileId {
    for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.endsWith(u8, checked.table.get(f).path, suffix)) return f;
    }
    return null;
}

test "a name the library declared reaches the file that declares it" {
    const gpa = testing.allocator;

    const text = "fn main() -> UInt8 {\n    UInt8(Str.length(\"abc\"))\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = text },
    }, "main.lin");
    defer checked.deinit();

    // A workspace of its own holding the library's source as the compiler read
    // it. The library is named by the path it was written at, so what decides
    // this is whether that path holds those bytes -- not where the checkout the
    // tests happen to run from keeps its own copy.
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const declares = fileEnding(&checked, "std/text/str.lin").?;
    const library = checked.table.get(declares);
    try tmp.dir.createDirPath(testing.io, std.fs.path.dirname(library.path).?);
    {
        const file = try tmp.dir.createFile(testing.io, library.path, .{});
        defer file.close(testing.io);
        try file.writeStreamingAll(testing.io, library.text);
    }

    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);

    const at_length = std.mem.indexOf(u8, text, "length").?;
    const found = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, at_length + 1), .@"utf-16", root)).?;
    defer gpa.free(found.uri);

    try testing.expect(std.mem.endsWith(u8, found.uri, "std/text/str.lin"));
    try testing.expect(std.mem.indexOf(u8, found.uri, &tmp.sub_path) != null);
    // The declaration itself, read out of the library's own bytes: a URI
    // naming the file says nothing about where in it the client is sent.
    try testing.expectEqualStrings(
        "length",
        lsp.offsets.rangeToSlice(library.text, found.range, .@"utf-16"),
    );
}

test "a library name is not offered where the file at its path is another file" {
    const gpa = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // A workspace of its own that happens to hold a file where the library's
    // source would sit. `std` is an ordinary directory name for a project, and
    // the range answered here is measured in the library's text -- so a client
    // sent to this file would open it and be put at a line it does not have.
    try tmp.dir.createDirPath(testing.io, "std/text");
    {
        const file = try tmp.dir.createFile(testing.io, "std/text/str.lin", .{});
        defer file.close(testing.io);
        try file.writeStreamingAll(testing.io, "fn nothing() -> UInt8 {\n    0\n}\n");
    }

    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);

    const text = "fn main() -> UInt8 {\n    UInt8(Str.length(\"abc\"))\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = text },
    }, "main.lin");
    defer checked.deinit();

    const at_length = std.mem.indexOf(u8, text, "length").?;
    try testing.expectEqual(
        @as(?lsp.types.Location, null),
        try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, at_length + 1), .@"utf-16", root),
    );
}

test "a library name is not offered where its source is not" {
    const gpa = testing.allocator;

    const text = "fn main() -> UInt8 {\n    UInt8(Str.length(\"abc\"))\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = text },
    }, "main.lin");
    defer checked.deinit();

    // A workspace holding no library source. A location a client cannot follow
    // would surface as the editor failing to open a file, which reads as the
    // editor's fault rather than as this server having nothing to say.
    const at_length = std.mem.indexOf(u8, text, "length").?;
    try testing.expectEqual(
        @as(?lsp.types.Location, null),
        try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, at_length + 1), .@"utf-16", "tests/lsp"),
    );
}

test "intrinsic integer properties have no source definition" {
    const gpa = testing.allocator;
    const text = "fn limit[T: Integer](_value: T) -> T { T.max }\nfn main() -> UInt8 { limit(UInt8.min) }\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    for ([_][]const u8{ "max", "min" }) |property| {
        const found = try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, std.mem.indexOf(u8, text, property).?), .@"utf-16", "");
        try testing.expect(found == null);
    }
    const receiver = (try forPosition(gpa, testing.io, &checked, checked.fileNamed("main.lin").?, at(text, std.mem.indexOf(u8, text, "T.max").?), .@"utf-16", "")).?;
    defer gpa.free(receiver.uri);
    try testing.expectEqualStrings("T", declared(&checked, receiver));
    try testing.expectEqual(at(text, std.mem.indexOf(u8, text, "T: Integer").?), receiver.range.start);
}
