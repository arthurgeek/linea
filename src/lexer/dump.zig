const std = @import("std");

const TokenList = @import("token.zig").TokenList;

pub fn writeEscaped(w: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    for (s) |ch| switch (ch) {
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        else => try w.writeByte(ch),
    };
}

/// A stable view of one file's token stream, numbered from zero independently
/// of its position in a combined token table.
pub fn dumpTokens(
    w: *std.Io.Writer,
    text: []const u8,
    tokens: TokenList.Slice,
    from: u32,
    to: u32,
) std.Io.Writer.Error!void {
    const tags = tokens.items(.tag)[from..to];
    const spans = tokens.items(.span)[from..to];

    for (tags, spans, 0..) |tag, span, i| {
        try w.print("{d} {s} {d}..{d} \"", .{ i, @tagName(tag), span.start, span.end });
        try writeEscaped(w, span.slice(text));
        try w.writeAll("\"\n");
    }
}

test "dumpTokens numbers each file independently of preceding tokens" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const Source = @import("../support/source.zig").Source;
    var sink = @import("../diagnostics/sink.zig").Sink.init(gpa);
    var interner: @import("../support/interner.zig").Interner = .empty;
    const prefix: Source = .{ .path = "std.lin", .text = "fn library() {}" };
    const source: Source = .{ .path = "main.lin", .text = "let x // c\n" };
    var joined = try @import("lexer.zig").tokenize(gpa, &prefix, .from(0), &sink, &interner);
    const start = joined.len;
    var tokens = try @import("lexer.zig").tokenize(gpa, &source, .from(1), &sink, &interner);
    for (0..tokens.len) |i| try joined.append(gpa, tokens.get(i));
    var standalone: std.Io.Writer.Allocating = .init(gpa);
    var prefixed: std.Io.Writer.Allocating = .init(gpa);
    try dumpTokens(&standalone.writer, source.text, tokens.slice(), 0, @intCast(tokens.len));
    try dumpTokens(&prefixed.writer, source.text, joined.slice(), @intCast(start), @intCast(joined.len));
    try testing.expectEqualStrings(
        \\0 keyword_let 0..3 "let"
        \\1 identifier 4..5 "x"
        \\2 comment 6..10 "// c"
        \\3 eof 11..11 ""
        \\
    , standalone.written());
    try testing.expectEqualStrings(standalone.written(), prefixed.written());
}
