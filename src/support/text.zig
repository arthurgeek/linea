const std = @import("std");

/// Validates string-literal escapes and optionally appends the decoded bytes.
/// The lexer passes no output buffer; lowering requests the bytes. Both use
/// the same escape rules, and validation alone performs no allocation.
///
/// `quoted` includes both delimiters. Ordinary literals use quotes;
/// interpolation pieces may use a quote or brace at either end. Decoding
/// strips one byte from each end in all four combinations.
///
/// A raw literal, `r"…"` or `r#"…"#`, begins with `r`, which no other piece
/// does. It has no escapes and no doubled braces, so its bytes between the
/// delimiters are its text exactly.
///
/// One line of a multi-line literal begins with `\\`, which no other piece
/// does. It has no escapes and ends at its line, so its text is every byte
/// after the `\\`. Joining the lines of one literal is the tree's work, since
/// the tree knows which line tokens belong to it.
///
/// Returns the byte offset of the first invalid escape in `quoted`, or null
/// when all escapes are valid.
pub fn decode(
    gpa: std.mem.Allocator,
    out: ?*std.ArrayList(u8),
    quoted: []const u8,
) std.mem.Allocator.Error!?usize {
    if (quoted[0] == 'r') {
        // `r`, the opening hashes, then the quote; the closing quote is
        // followed by as many hashes.
        const hashes = std.mem.indexOfScalar(u8, quoted, '"').? - 1;
        if (out) |written| try written.appendSlice(gpa, quoted[hashes + 2 .. quoted.len - 1 - hashes]);
        return null;
    }

    if (quoted[0] == '\\') {
        if (out) |written| try written.appendSlice(gpa, quoted[2..]);
        return null;
    }

    const body = quoted[1 .. quoted.len - 1];

    var i: usize = 0;
    while (i < body.len) {
        // Decode doubled braces as one literal brace. The scanner has
        // already distinguished `{{` from an interpolation. A lone `}` is
        // also literal outside interpolation; doubling works for both braces.
        if ((body[i] == '{' or body[i] == '}') and i + 1 < body.len and body[i + 1] == body[i]) {
            if (out) |written| try written.append(gpa, body[i]);
            i += 2;
            continue;
        }
        if (body[i] != '\\') {
            if (out) |written| try written.append(gpa, body[i]);
            i += 1;
            continue;
        }

        const at = i + 1;
        if (at >= body.len) return i + 1;
        i += 2;
        switch (body[at]) {
            'n' => if (out) |written| try written.append(gpa, '\n'),
            't' => if (out) |written| try written.append(gpa, '\t'),
            'r' => if (out) |written| try written.append(gpa, '\r'),
            '0' => if (out) |written| try written.append(gpa, 0),
            '\\' => if (out) |written| try written.append(gpa, '\\'),
            '"' => if (out) |written| try written.append(gpa, '"'),
            'u' => {
                // Encode the Unicode scalar named by `\u{...}` as UTF-8.
                if (at + 1 >= body.len or body[at + 1] != '{') return i - 2 + 1;
                const opens = at + 2;
                const closes = std.mem.indexOfScalarPos(u8, body, opens, '}') orelse return i - 2 + 1;
                const digits = body[opens..closes];
                i = closes + 1;

                if (digits.len == 0 or digits.len > 6) return at;
                const scalar = std.fmt.parseInt(u21, digits, 16) catch return at;
                // Surrogates and values above U+10FFFF are not Unicode scalars.
                if (scalar > 0x10FFFF or (scalar >= 0xD800 and scalar <= 0xDFFF)) return at;

                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(scalar, &buf) catch return at;
                if (out) |written| try written.appendSlice(gpa, buf[0..n]);
            },
            else => return at,
        }
    }
    return null;
}

/// Returns the one Unicode scalar a literal's decoded text holds. The checker
/// uses it to interpret scalar-valued range ends.
///
/// Returns null for empty or multi-scalar text, or invalid UTF-8. The caller
/// then treats the literal as an ordinary string.
pub fn oneScalar(text: []const u8) ?u21 {
    const count = std.unicode.utf8CountCodepoints(text) catch return null;
    if (count != 1) return null;
    const len = std.unicode.utf8ByteSequenceLength(text[0]) catch return null;
    return std.unicode.utf8Decode(text[0..len]) catch null;
}

test "an escape means one byte" {
    const gpa = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    try std.testing.expectEqual(@as(?usize, null), try decode(gpa, &out, "\"a\\\"b\""));
    try std.testing.expectEqualStrings("a\"b", out.items);
}

test "escape validation needs no output allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const gpa = failing.allocator();
    try std.testing.expectEqual(@as(?usize, null), try decode(gpa, null, "\"\""));
    try std.testing.expectEqual(@as(?usize, null), try decode(gpa, null, "\"a\\n\\u{1F600}{{}}\""));
    try std.testing.expectEqual(@as(?usize, 2), try decode(gpa, null, "\"a\\qb\""));
    try std.testing.expectEqual(@as(?usize, 2), try decode(gpa, null, "\"a\\u{110000}\""));
    try std.testing.expectEqual(@as(?usize, 2), try decode(gpa, null, "\"a\\u{D800}\""));
}

test "a raw literal holds its bytes exactly" {
    const gpa = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    try std.testing.expectEqual(@as(?usize, null), try decode(gpa, &out, "r\"{name}\\n{{\""));
    try std.testing.expectEqualStrings("{name}\\n{{", out.items);

    out.clearRetainingCapacity();
    try std.testing.expectEqual(@as(?usize, null), try decode(gpa, &out, "r##\"a \"# b\"##"));
    try std.testing.expectEqualStrings("a \"# b", out.items);

    out.clearRetainingCapacity();
    try std.testing.expectEqual(@as(?usize, null), try decode(gpa, &out, "r\"\""));
    try std.testing.expectEqualStrings("", out.items);

    // Validation alone asks for no output and allocates nothing.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectEqual(@as(?usize, null), try decode(failing.allocator(), null, "r#\"\\q\"#"));
}

test "a line of a multi-line literal holds every byte after its backslashes" {
    const gpa = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    try std.testing.expectEqual(@as(?usize, null), try decode(gpa, &out, "\\\\{a} \\n \"q\"  "));
    try std.testing.expectEqualStrings("{a} \\n \"q\"  ", out.items);

    out.clearRetainingCapacity();
    _ = try decode(gpa, &out, "\\\\");
    try std.testing.expectEqualStrings("", out.items);

    // Validation alone asks for no output and allocates nothing.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectEqual(@as(?usize, null), try decode(failing.allocator(), null, "\\\\\\q"));
}

test "a scalar is written out as utf-8" {
    const gpa = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    // The escaped scalar and its literal UTF-8 spelling produce identical bytes.
    try std.testing.expectEqual(@as(?usize, null), try decode(gpa, &out, "\"Ol\\u{e1}\""));
    try std.testing.expectEqualStrings("Olá", out.items);
}

test "an escape nothing defines is refused, and says where" {
    const gpa = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    try std.testing.expectEqual(@as(?usize, 2), try decode(gpa, &out, "\"a\\qb\""));
    // U+110000 is above the Unicode scalar range.
    out.clearRetainingCapacity();
    try std.testing.expectEqual(@as(?usize, 2), try decode(gpa, &out, "\"a\\u{110000}\""));
}

test "one scalar however many bytes it takes" {
    try std.testing.expectEqual(@as(?u21, 'a'), oneScalar("a"));
    try std.testing.expectEqual(@as(?u21, '\n'), oneScalar("\n"));
    try std.testing.expectEqual(@as(?u21, 0x1F600), oneScalar("\u{1F600}"));
}

test "more than one scalar, or none, is not one" {
    try std.testing.expectEqual(@as(?u21, null), oneScalar("ab"));
    try std.testing.expectEqual(@as(?u21, null), oneScalar(""));
}

/// The offset of the first byte of `bytes` that begins no UTF-8 sequence, or
/// null when every byte is part of one. A source file is checked with it
/// ([S-Encoding]), and so is a file embedded as text ([M-EmbedText]).
///
/// A byte under 0x80 stands for itself, and program text is nearly all of
/// them, so the common byte is skipped without being decoded -- a word at a
/// time while none in it has the high bit set. What is left is what actually
/// needs UTF-8 read out of it.
///
/// This is one pass over every byte of every file before a token is read, and
/// decoding each of them made it a fifth of what lexing costs, which is the
/// largest thing the front end does.
pub fn firstInvalidUtf8(bytes: []const u8) ?usize {
    const stride = @sizeOf(usize);
    const high: usize = @bitCast([_]u8{0x80} ** stride);

    var i: usize = 0;
    while (i < bytes.len) {
        while (i + stride <= bytes.len) {
            const chunk: usize = @bitCast(bytes[i..][0..stride].*);
            if (chunk & high != 0) break;
            i += stride;
        }
        if (i >= bytes.len) break;

        if (bytes[i] < 0x80) {
            i += 1;
            continue;
        }
        const n = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return i;
        if (i + n > bytes.len) return i;
        _ = std.unicode.utf8Decode(bytes[i..][0..n]) catch return i;
        i += n;
    }
    return null;
}

test "the first byte that begins no utf-8 sequence is found" {
    try std.testing.expectEqual(@as(?usize, null), firstInvalidUtf8("plain text, and olá"));
    try std.testing.expectEqual(@as(?usize, null), firstInvalidUtf8(""));
    // 0xC3 opens a two-byte sequence, so on its own it is not UTF-8.
    try std.testing.expectEqual(@as(?usize, 3), firstInvalidUtf8("abc\xC3"));
    // An overlong form of `/` and an encoded surrogate are refused.
    try std.testing.expectEqual(@as(?usize, 0), firstInvalidUtf8("\xC0\xAF"));
    try std.testing.expectEqual(@as(?usize, 1), firstInvalidUtf8("a\xED\xA0\x80"));
    // A continuation byte cannot begin a sequence; long ASCII runs are skipped.
    try std.testing.expectEqual(@as(?usize, 17), firstInvalidUtf8("0123456789abcdefg\x80"));
}

/// The line and column, both counted from one, of byte `offset` in `bytes`. A
/// column counts bytes, since the text may not be UTF-8 at all; a `\r\n` is
/// one line break.
pub fn lineColumnOf(bytes: []const u8, offset: usize) struct { line: usize, column: usize } {
    var line: usize = 1;
    var line_start: usize = 0;
    for (bytes[0..@min(offset, bytes.len)], 0..) |c, i| {
        if (c == '\n') {
            line += 1;
            line_start = i + 1;
        }
    }
    return .{ .line = line, .column = offset - line_start + 1 };
}

test "a byte's line and column count from one" {
    const at = lineColumnOf("ab\r\ncd\nef", 8);
    try std.testing.expectEqual(@as(usize, 3), at.line);
    try std.testing.expectEqual(@as(usize, 2), at.column);
    const first = lineColumnOf("xyz", 0);
    try std.testing.expectEqual(@as(usize, 1), first.line);
    try std.testing.expectEqual(@as(usize, 1), first.column);
}
