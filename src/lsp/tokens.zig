const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const token = @import("../lexer/token.zig");
const TokenId = token.TokenId;
const node = @import("../syntax/node.zig");
const ExprId = node.ExprId;
const BindingId = @import("../sema/resolve.zig").BindingId;
const FileId = @import("../support/source.zig").FileId;
const positions = @import("positions.zig");
const Cursor = positions.Cursor;

/// What a client is told a token is.
///
/// The whole list, and the order the protocol indexes it by: a `tokenType` in
/// an encoded token is a position in the legend `initialize` advertised, so
/// the two must be one thing rather than two that agree.
const Kind = enum {
    keyword,
    variable,
    number,
    string,
    comment,
    operator,
};

/// The names of the kinds, in the order the protocol reads them.
const names = blk: {
    const fields = @typeInfo(Kind).@"enum".fields;
    var out: [fields.len][]const u8 = undefined;
    for (fields, 0..) |f, i| out[i] = f.name;
    break :blk out;
};

comptime {
    // A name the specification does not define is a colour no client has, so
    // the legend is checked against the protocol's own list rather than
    // against a reader's memory of it.
    for (names) |name| {
        var defined = false;
        for (@typeInfo(lsp.types.semantic_tokens.Type).@"union".fields) |f| {
            if (std.mem.eql(u8, f.name, name)) defined = true;
        }
        if (!defined) @compileError("`" ++ name ++ "` is not a token type the protocol defines");
    }
}

/// What a client is told about a token beyond what kind of thing it is.
///
/// The whole list, and the order the protocol indexes it by: a token's
/// modifiers travel as a bitset whose bit *i* is the *i*th entry of the legend
/// `initialize` advertised, so the two must be one thing rather than two that
/// agree.
const Modifier = enum {
    /// Where a name is introduced, as opposed to where it is used.
    declaration,
    /// A binding the language will not let anything assign to again, which
    /// `let` says and `var` does not.
    readonly,
    /// A name reaching a declaration the standard library wrote.
    defaultLibrary,
    /// A binding whose type is in the linear universe: a value that must be
    /// consumed exactly once.
    ///
    /// The one name here the protocol does not define, and deliberately: no
    /// theme styles it without being asked to, and the alternative is to
    /// report a property of this language under the name of a property of
    /// another one.
    linear,

    fn bit(self: Modifier) u32 {
        return @as(u32, 1) << @intFromEnum(self);
    }
};

/// The names of the modifiers, in the order the protocol reads them.
const modifier_names = blk: {
    const fields = @typeInfo(Modifier).@"enum".fields;
    var out: [fields.len][]const u8 = undefined;
    for (fields, 0..) |f, i| out[i] = f.name;
    break :blk out;
};

comptime {
    // Every modifier but the custom one is checked against the protocol's own
    // list, for the reason a kind is: a name the specification does not define
    // is a decoration no client has.
    for (modifier_names, 0..) |name, i| {
        if (@as(Modifier, @enumFromInt(i)) == .linear) continue;
        var defined = false;
        for (@typeInfo(lsp.types.semantic_tokens.Modifier).@"union".fields) |f| {
            if (std.mem.eql(u8, f.name, name)) defined = true;
        }
        if (!defined) @compileError("`" ++ name ++ "` is not a token modifier the protocol defines");
    }
}

pub const legend: lsp.types.semantic_tokens.Options.Legend = .{
    .tokenTypes = &names,
    .tokenModifiers = &modifier_names,
};

/// What the lexer already decided a token is, said the way a client reads it.
///
/// A translation between two enumerations and nothing else. What a run of
/// bytes is was settled when the file was lexed, and a second opinion here --
/// a name re-read to see whether it looks like a type, a literal re-scanned
/// for a decimal point -- would be a second lexer that agrees on every file
/// anyone tried.
///
/// Exhaustive, with no `else`: a tag added to the language is classified
/// before the build succeeds.
///
/// A token nothing colours is `null` rather than a kind of its own. The
/// protocol's list has no member for punctuation, and a delimiter given the
/// nearest one would be reported as an operator, which is a claim about the
/// language rather than a gap in the legend.
fn kindOf(tag: token.Tag) ?Kind {
    return switch (tag) {
        // Where a file ends, and a run of bytes that begins no token. Neither
        // is anything a reader can be told about.
        .eof, .invalid => null,

        .comment => .comment,
        .identifier => .variable,
        .int_literal => .number,
        .float_literal => .number,
        .string_literal => .string,
        // Each line of a multi-line literal is a string token of its own, so
        // no token a client is sent spans a line break.
        .string_line => .string,
        // The pieces of an interpolated literal are the literal, coloured as
        // one: `"a{` and `}b"` are text a reader is looking at as text, and the
        // expression between them carries its own tokens and its own colours.
        .str_open, .str_mid, .str_close => .string,
        // A format spec tells the renderer how to lay out one value, which
        // is an instruction rather than text, so it is coloured as one.
        .format_spec => .operator,

        .keyword_defer,
        .keyword_let,
        .keyword_var,
        .keyword_fn,
        .keyword_import,
        .keyword_use,
        .keyword_as,
        .keyword_pub,
        .keyword_internal,
        .keyword_export,
        .keyword_opaque,
        .keyword_linear,
        .keyword_copyable,
        .keyword_carrier,
        .keyword_test,
        .keyword_trap,
        .keyword_phantom,
        .keyword_sink,
        .keyword_copy,
        .keyword_borrow,
        .keyword_borrows,
        .keyword_carries,
        .keyword_retains,
        .keyword_panic,
        .keyword_template,
        .keyword_derive,
        .keyword_reflect,
        .keyword_impl,
        .keyword_trait,
        .keyword_for,
        .keyword_true,
        .keyword_false,
        .keyword_if,
        .keyword_else,
        .keyword_while,
        .keyword_loop,
        .keyword_break,
        .keyword_continue,
        .keyword_read,
        .keyword_inout,
        .keyword_return,
        .keyword_enum,
        .keyword_struct,
        .keyword_match,
        .keyword_extern,
        .keyword_where,
        .keyword_in,
        => .keyword,

        .at_sign,
        .ampersand,
        .ampersand_ampersand,
        .pipe_pipe,
        .bang,
        .equal,
        .equal_equal,
        .bang_equal,
        .less,
        .less_equal,
        .greater,
        .greater_equal,
        .plus,
        .minus,
        .star,
        .slash,
        .plus_equal,
        .minus_equal,
        .star_equal,
        .slash_equal,
        .percent,
        .percent_equal,
        .arrow,
        .fat_arrow,
        .question,
        .caret,
        .dot_dot,
        .dot_dot_equal,
        => .operator,

        // Punctuation. It separates rather than computes, and every editor
        // already draws it from the grammar.
        .colon,
        .dot,
        .pipe,
        .l_paren,
        .r_paren,
        .l_brace,
        .r_brace,
        .l_bracket,
        .r_bracket,
        .comma,
        .semicolon,
        => null,
    };
}

test "a format spec is highlighted as an instruction beside the text around it" {
    try testing.expectEqual(@as(?Kind, .operator), kindOf(.format_spec));
    try testing.expectEqual(@as(?Kind, .string), kindOf(.str_mid));
}

/// What is known about the binding a token names, as the bits the protocol
/// reads.
///
/// Every one of them is read from wherever it was decided. Which statement
/// declared a local and which token declares a binding are the resolver's; the
/// keyword that introduced a statement is the tree's; a binding's type and the
/// universe that type is in are the checker's; and which files are the
/// library's is what the loader recorded. Nothing here re-decides any of them.
fn modifiersOf(checked: *const Analysis, library: []const bool, b: BindingId) u32 {
    const ast = &checked.program.ast;
    const res = &checked.semantics.res;
    const typing = &checked.semantics.typing;

    var bits: u32 = 0;

    // A local is readonly when the statement that declared it said `let`.
    // Asked through `Resolution.bindingIsMutable` rather than reading the
    // statement here, so this and a receiver completion's marker decision
    // answer from the one routine rather than each rereading `let` and `var`.
    // Scoped to `.local` here: a read-only parameter or capture is a
    // different modifier this pass does not report.
    if (res.kindOf(b) == .local and !res.bindingIsMutable(ast, b)) {
        bits |= Modifier.readonly.bit();
    }

    // Where the name was introduced decides whose declaration it is. A
    // primitive is introduced nowhere, and is the one binding with no token.
    const at = res.declaringToken(b);
    if (at != TokenId.none and library[ast.fileOf(at).index()]) {
        bits |= Modifier.defaultLibrary.bit();
    }

    if (typing.mustConsume(typing.bindingType(b))) {
        bits |= Modifier.linear.bit();
    }

    return bits;
}

/// What every token of one file has to say about the name on it.
///
/// Indexed by the file's own tokens, so what is held is as long as the file
/// rather than as long as the program. Two passes fill it: one over the file's
/// tokens, reading the declaration index, and one over its expression run,
/// reading the resolved targets. Classifying a binding retains the token-file
/// binary search and the type-universe query that its modifiers require.
///
/// Which binding a name reaches is `targetOf` and is not decided again here. A
/// second walk of scopes would agree on every program anyone wrote and
/// disagree on a re-export, an alias or a name the prelude offers.
fn modifierTable(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    part: *const @import("../syntax/ast.zig").FilePart,
) ![]const u32 {
    const ast = &checked.program.ast;
    const res = &checked.semantics.res;
    const from = part.token_start;
    const to = part.token_end;

    const out = try gpa.alloc(u32, to - from);
    errdefer gpa.free(out);
    @memset(out, 0);

    const library = checked.library;

    for (from..to) |k| {
        const b = checked.uses.declaredAt(TokenId.at(@intCast(k)));
        if (b == BindingId.none) continue;
        out[k - from] |= Modifier.declaration.bit() | modifiersOf(checked, library, b);
    }

    for (part.expr_start..part.expr_end) |i| {
        const e = ExprId.at(@intCast(i));
        // The token a name expression is written at, which for a selection is
        // the name after the dot -- the one the reader is looking at.
        const k = ast.exprMain(e).index();
        if (k < from or k >= to) continue;
        if (checked.semantics.typing.integerProperty(e) != null) {
            out[k - from] |= Modifier.readonly.bit();
        }
        const b = res.targetOf(e);
        if (b != BindingId.none) out[k - from] |= modifiersOf(checked, library, b);
    }

    return out;
}

/// Every token of one file, encoded as the protocol wants them.
///
/// Five integers each: how many lines on from the token before, how far along
/// the line, how long, which legend entry, and the set of modifiers as a
/// bitset over the legend's own order.
///
/// Read off the stream the lexer produced, in the order it produced them.
/// That order is the source's, which is what makes the deltas a fold and not a
/// sort, and it is also why nothing here re-lexes: the tokens a file has were
/// settled once, and the file is not read again to find out.
///
/// No reported kind spans a line, so a length is a count of code units and
/// never a range: a comment ends at the newline, a string that reaches one is
/// `invalid` instead, and `invalid` is not reported.
///
/// Costs one pass over the file's bytes plus one step per token, plus the two
/// passes the modifier table costs over the file's tokens and expressions.
/// Scratch is one word per token of the file, plus the encoded result. The
/// library membership table is borrowed from Analysis. Finding the file's run
/// is one pass over the compilation's files.
pub fn forFile(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    encoding: lsp.offsets.Encoding,
) ![]const u32 {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return &.{};

    const modifiers = try modifierTable(gpa, checked, part);
    defer gpa.free(modifiers);

    var out: std.ArrayList(u32) = .empty;
    var cursor: Cursor = .{ .text = part.source, .encoding = encoding };
    var line: u32 = 0;
    var character: u32 = 0;

    var at = part.token_start;
    while (at < part.token_end) : (at += 1) {
        const id = TokenId.at(at);
        const kind = kindOf(ast.tokenTag(id)) orelse continue;
        const span = ast.tokenSpan(id);

        cursor.advanceTo(span.start);
        const length = positions.widthOf(part.source[span.start..span.end], encoding);
        try out.appendSlice(gpa, &.{
            cursor.line - line,
            if (cursor.line == line) cursor.character - character else cursor.character,
            @intCast(length),
            @intFromEnum(kind),
            modifiers[at - part.token_start],
        });
        line = cursor.line;
        character = cursor.character;
    }
    return out.toOwnedSlice(gpa);
}

test "a token carries the kind the lexer gave it" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "// why\nfn main() -> UInt8 {\n    0\n}\n" },
    }, "main.lin");
    defer checked.deinit();

    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);

    // The comment, `fn`, `main`, `UInt8` and `0`. The parentheses, the braces
    // and the arrow's neighbours are punctuation or nothing at all.
    try testing.expectEqualSlices(u32, &.{
        // `// why` on line 0, column 0, six units, a comment.
        0, 0, 6, @intFromEnum(Kind.comment),  0,
        // `fn` on the next line.
        1, 0, 2, @intFromEnum(Kind.keyword),  0,
        // `main`, three units along from `fn`, where the name is introduced.
        0, 3, 4, @intFromEnum(Kind.variable), Modifier.declaration.bit(),
        // `->`.
        0, 7, 2, @intFromEnum(Kind.operator), 0,
        // `UInt8`.
        0, 3, 5, @intFromEnum(Kind.variable), 0,
        // `0`, on the line after it.
        1, 4, 1, @intFromEnum(Kind.number),   0,
    }, data);
}

test "a raw literal is one string token from its `r` to its last hash" {
    const gpa = testing.allocator;

    const text = "fn main() -> UInt8 {\n    UInt8(r#\"{\"a\"}\"#.length() - 5)\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);

    const literal = "r#\"{\"a\"}\"#";
    const wanted = std.mem.indexOf(u8, text, literal).?;
    var line: u32 = 0;
    var character: u32 = 0;
    var i: usize = 0;
    const found: [2]u32 = while (i < data.len) : (i += 5) {
        line += data[i];
        character = if (data[i] == 0) character + data[i + 1] else data[i + 1];
        const offset = lsp.offsets.positionToIndex(text, .{ .line = line, .character = character }, .@"utf-16");
        if (offset == wanted) break .{ data[i + 2], data[i + 3] };
    } else return error.TestExpectedEqual;
    try testing.expectEqual(@as(u32, literal.len), found[0]);
    try testing.expectEqual(@as(u32, @intFromEnum(Kind.string)), found[1]);
}

test "each line of a multi-line literal is a string token of its own" {
    const gpa = testing.allocator;

    const text = "fn main() -> UInt8 {\n    let t =\n        \\\\{a}\n        \\\\b\n    UInt8(t.length() - 5)\n}\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);

    // Collect the line, character and length of every string token, in order.
    var strings: std.ArrayList([3]u32) = .empty;
    defer strings.deinit(gpa);
    var line: u32 = 0;
    var character: u32 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 5) {
        line += data[i];
        character = if (data[i] == 0) character + data[i + 1] else data[i + 1];
        if (data[i + 3] == @intFromEnum(Kind.string)) try strings.append(gpa, .{ line, character, data[i + 2] });
    }
    try testing.expectEqualSlices([3]u32, &.{ .{ 2, 8, 5 }, .{ 3, 8, 3 } }, strings.items);
}

/// The modifiers reported for the `n`th token that carries a kind.
///
/// A token is five integers and the modifiers are the last of them, so a test
/// naming a token by its position in the stream reads the same field the
/// protocol does.
fn modifiersAt(data: []const u32, n: usize) u32 {
    return data[n * 5 + 4];
}

fn modifiersAtOffset(text: []const u8, data: []const u32, wanted: usize) ?u32 {
    var line: u32 = 0;
    var character: u32 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 5) {
        line += data[i];
        character = if (data[i] == 0) character + data[i + 1] else data[i + 1];
        const offset = lsp.offsets.positionToIndex(text, .{ .line = line, .character = character }, .@"utf-16");
        if (offset == wanted) return data[i + 4];
    }
    return null;
}

test "structural derive source names carry semantic modifiers" {
    const gpa = testing.allocator;
    const text = @import("references.zig").structural_derive_source;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);

    const declaration = std.mem.indexOf(u8, text, "derive[T:").? + 7;
    try testing.expectEqual(Modifier.declaration.bit(), modifiersAtOffset(text, data, declaration).?);
    const target_argument = std.mem.indexOf(u8, text, ") for Box[T]").? + 10;
    const trait_argument = std.mem.indexOf(u8, text, "    Marker[T]").? + 11;
    const predicate_subject = std.mem.indexOf(u8, text, "T.Item: Lookup").?;
    for ([_]usize{ target_argument, trait_argument, predicate_subject }) |offset| {
        try testing.expectEqual(@as(u32, 0), modifiersAtOffset(text, data, offset).?);
    }

    const required_trait = std.mem.indexOf(u8, text, "reflect.components: Lookup").? + 20;
    const required_argument = std.mem.indexOf(u8, text, "reflect.components: Lookup[UInt64]").? + 27;
    try testing.expect(modifiersAtOffset(text, data, required_trait) != null);
    try testing.expect(modifiersAtOffset(text, data, required_argument) != null);
}

test "a modifier is the bit its place in the legend gives it" {
    // The wire format is a bitset over the legend's own order, and getting it
    // wrong is silent: a client renders the modifier that sits where the bit
    // points, and every token still arrives.
    try testing.expectEqual(@as(usize, 4), legend.tokenModifiers.len);
    try testing.expectEqualStrings("declaration", legend.tokenModifiers[0]);
    try testing.expectEqualStrings("readonly", legend.tokenModifiers[1]);
    try testing.expectEqualStrings("defaultLibrary", legend.tokenModifiers[2]);
    try testing.expectEqualStrings("linear", legend.tokenModifiers[3]);

    try testing.expectEqual(@as(u32, 1), Modifier.declaration.bit());
    try testing.expectEqual(@as(u32, 2), Modifier.readonly.bit());
    try testing.expectEqual(@as(u32, 4), Modifier.defaultLibrary.bit());
    try testing.expectEqual(@as(u32, 8), Modifier.linear.bit());
}

test "a `let` is readonly and a `var` is not" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1
        \\    var b: UInt8 = 0
        \\    b = a
        \\    b
        \\}
        \\
        },
    }, "main.lin");
    defer checked.deinit();

    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);

    // `fn`, `main`, `->`, `UInt8`, `let`, `a`, `UInt8`, `=`, `1`, `var`, `b`,
    // `UInt8`, `=`, `0`, `b`, `=`, `a`, `b`.
    try testing.expectEqual(Modifier.declaration.bit() | Modifier.readonly.bit(), modifiersAt(data, 5));
    try testing.expectEqual(Modifier.declaration.bit(), modifiersAt(data, 10));
    // A use carries what the binding is and not that it was introduced here.
    try testing.expectEqual(Modifier.readonly.bit(), modifiersAt(data, 16));
    try testing.expectEqual(@as(u32, 0), modifiersAt(data, 17));
}

test "a binding of a linear type is marked wherever its name is written" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
        \\@linear
        \\struct Key {
        \\    n: UInt8,
        \\}
        \\
        \\fn take(sink k: Key) -> UInt8 {
        \\    let Key { n: taken } = k
        \\    taken
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    take(.{ n = 1 })
        \\}
        \\
        },
    }, "main.lin");
    defer checked.deinit();

    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);

    // `@`, `linear`, `struct`, `Key`, `n`, `UInt8`, `fn`, `take`, `sink`, `k`,
    // `Key`, `->`, `UInt8`, `let`, `Key`, `n`, `taken`, `=`, `k`, ...
    try testing.expectEqual(Modifier.declaration.bit(), modifiersAt(data, 3));
    // A parameter, so introduced here and not assignable again -- but not a
    // `let`, which is the distinction `readonly` reports.
    try testing.expectEqual(Modifier.declaration.bit() | Modifier.linear.bit(), modifiersAt(data, 9));
    try testing.expectEqual(Modifier.linear.bit(), modifiersAt(data, 18));
}

test "intrinsic integer properties are readonly without a library declaration" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 {\n    UInt8.max\n}\n" },
    }, "main.lin");
    defer checked.deinit();

    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);

    // `fn`, `main`, `->`, `UInt8`, `UInt8`, `max`. The endpoint is immutable
    // and neither the primitive nor its property has a library declaration.
    try testing.expectEqual(@as(u32, 0), modifiersAt(data, 4));
    try testing.expectEqual(Modifier.readonly.bit(), modifiersAt(data, 5));
}

test "a position is where the protocol says it is" {
    const gpa = testing.allocator;

    // An em-dash before the token: three bytes, one UTF-16 code unit. A
    // cursor counting bytes would put `fn` two columns to the right, and a
    // file of ASCII could not say so.
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "// \u{2014}\nfn main() -> UInt8 {\n    0\n}\n" },
    }, "main.lin");
    defer checked.deinit();

    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);

    const text = checked.table.get(checked.fileNamed("main.lin").?).text;
    var at: usize = 0;
    var line: u32 = 0;
    var character: u32 = 0;
    while (at < data.len) : (at += 5) {
        line += data[at];
        character = if (data[at] == 0) character + data[at + 1] else data[at + 1];

        // Every position the fold produced is the one the protocol's own
        // conversion finds for the same offset. The two answer the same
        // question, and only one of them is allowed to be quick about it.
        const offset = lsp.offsets.positionToIndex(text, .{ .line = line, .character = character }, .@"utf-16");
        try testing.expectEqual(
            lsp.types.Position{ .line = line, .character = character },
            lsp.offsets.indexToPosition(text, offset, .@"utf-16"),
        );
    }

    // The comment is the first token, and it is four code units wide.
    try testing.expectEqual(@as(u32, 4), data[2]);
}

test "a file of a module is coloured by its own tokens" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 { helper() }\n" },
        .{ .path = "app/helper.lin", .text = "// helper\nfn helper() -> UInt8 { 1 }\n" },
    }, "app");
    defer checked.deinit();

    var wanted: FileId = checked.fileNamed("app/main.lin").?;
    for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, "app/helper.lin")) wanted = f;
    }

    const data = try forFile(gpa, &checked, wanted, .@"utf-16");
    defer gpa.free(data);

    // The first token is the comment on the first line of *that* file, not
    // whatever the module's stream happened to hold before it.
    try testing.expectEqual(@as(u32, 0), data[0]);
    try testing.expectEqual(@as(u32, 0), data[1]);
    try testing.expectEqual(@as(u32, 9), data[2]);
    try testing.expectEqual(@intFromEnum(Kind.comment), data[3]);
}

test "source token declarations retain every binding modifier" {
    const fixtures = [_][]const u8{
        \\@linear
        \\struct Key { n: UInt8 }
        \\fn take(sink k: Key) -> UInt8 {
        \\    let Key { n: taken } = k
        \\    taken
        \\}
        \\fn main() -> UInt8 { take(.{ n = 7 }) }
        ,
        \\fn seven(number: UInt8) -> UInt8 { number }
        \\fn main() -> UInt8 {
        \\    let held: fn(read number: UInt8) -> UInt8 = seven
        \\    held(number: 7)
        \\}
        ,
        \\@derive(Label)
        \\struct Item {}
        \\trait Label { fn label(self: Self) -> UInt8 }
        \\fn seven(number: UInt8) -> UInt8 { number }
        \\template impl Label {
        \\    fn label(_self: Self) -> UInt8 {
        \\        let held: fn(read number: UInt8) -> UInt8 = seven
        \\        held(number: 7)
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let item: Item = .{}
        \\    Label.label(item)
        \\}
        ,
    };
    for (fixtures) |text| {
        var checked = try analysis_mod.of(testing.allocator, testing.allocator, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
        defer checked.deinit();
        try testing.expect(!checked.sink.hasErrors());
        const ast = &checked.program.ast;
        const res = &checked.semantics.res;
        const expected = try testing.allocator.alloc(u32, ast.tokenCount());
        defer testing.allocator.free(expected);
        @memset(expected, 0);
        // The semantic contract is the union of all declarations at a token,
        // including source declarations revisited during template resolution.
        for (0..res.bindingCount()) |i| {
            const b = BindingId.at(@intCast(i));
            const token_id = res.declaringToken(b);
            if (token_id == TokenId.none or token_id.index() >= expected.len) continue;
            expected[token_id.index()] |= Modifier.declaration.bit() | modifiersOf(&checked, checked.library, b);
        }
        for (expected, 0..) |wanted, i| {
            const b = checked.uses.declaredAt(TokenId.at(@intCast(i)));
            const found = if (b == BindingId.none) 0 else Modifier.declaration.bit() | modifiersOf(&checked, checked.library, b);
            try testing.expectEqual(wanted, found);
        }
    }
}

test "intrinsic integer properties retain readonly tokens under a generic receiver" {
    const gpa = testing.allocator;
    const text = "fn limit[T: Integer](_value: T) -> T { T.max }\nfn main() -> UInt8 { limit(UInt8.min) }\n";
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const data = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .@"utf-16");
    defer gpa.free(data);
    // `T.max` and `UInt8.min` select the same intrinsic property family.
    const maximum = std.mem.indexOf(u8, text, "T.max").? + 2;
    const minimum = std.mem.indexOf(u8, text, "UInt8.min").? + 6;
    try testing.expectEqual(Modifier.readonly.bit(), modifiersAtOffset(text, data, maximum).?);
    try testing.expectEqual(Modifier.readonly.bit(), modifiersAtOffset(text, data, minimum).?);
}
