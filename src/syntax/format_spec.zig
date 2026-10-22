//! This file reads the format spec after an interpolation's colon, as in
//! `{price:>8.2}`.
//!
//! The spec is written `[[fill]align][+][0][width][.precision][x|X|?]`. The lexer
//! decides where its text ends; this file decides what the text means, once,
//! for the parser that records it and every later reader of the record. What
//! the spec does to a value is `std.fmt`'s: interpolation hands the recorded
//! parts to that library, so there is no second formatter here.

const std = @import("std");
const testing = std.testing;

/// An alignment places a value inside its width. `none` leaves the choice to
/// the value's type: numbers sit on the right and everything else on the left.
pub const Alignment = enum(u2) { none, left, right, center };

/// Hexadecimal digits write an integer in base 16, with lowercase letters
/// (`x`) or capitals (`X`). `none` writes decimal digits.
pub const Hex = enum(u2) { none, lower, upper };

/// A width or precision is at most this. A literal width needs a bound for
/// the record to have a fixed size, and no column of text is wider.
pub const max_count = std.math.maxInt(u16);

/// A format records how one interpolated value renders. It has a fixed size,
/// so an interpolation's formats sit in one array and compare and hash as
/// plain bits.
pub const Format = packed struct(u64) {
    /// `?` renders the value through `Debug` rather than `Display`.
    debug: bool = false,
    alignment: Alignment = .none,
    /// `+` writes a sign before a number that is not negative.
    plus: bool = false,
    /// `0` pads a number with zeros between its sign and its digits.
    zero: bool = false,
    has_precision: bool = false,
    /// Padding writes this Unicode scalar once for each column.
    fill: u21 = ' ',
    width: u16 = 0,
    precision: u16 = 0,
    /// `x` and `X` write an integer's digits in base 16.
    hex: Hex = .none,
    _unused: u3 = 0,

    pub const display: Format = .{};
    pub const debug_only: Format = .{ .debug = true };

    /// Answer true when this format asks for more than the trait it renders
    /// through, so rendering it needs the library's layout routines.
    pub fn laysOut(self: Format) bool {
        return self.alignment != .none or self.plus or self.zero or self.width != 0 or self.has_precision or self.hex != .none;
    }

    test "a format lays out a value only when it asks for more than a trait" {
        try testing.expect(!Format.display.laysOut());
        try testing.expect(!Format.debug_only.laysOut());
        try testing.expect((Format{ .width = 4 }).laysOut());
        try testing.expect((Format{ .plus = true }).laysOut());
        try testing.expect((Format{ .has_precision = true }).laysOut());
        try testing.expect((Format{ .alignment = .left, .width = 1 }).laysOut());
        try testing.expect((Format{ .hex = .lower }).laysOut());
    }

    pub fn eql(self: Format, other: Format) bool {
        return self.bits() == other.bits();
    }

    test "two formats are equal exactly when every part is" {
        try testing.expect(Format.display.eql(.{}));
        try testing.expect(!Format.display.eql(.debug_only));
        try testing.expect(!(Format{ .fill = '*', .alignment = .left, .width = 3 }).eql(.{ .alignment = .left, .width = 3 }));
    }

    pub fn bits(self: Format) u64 {
        return @bitCast(self);
    }

    test "a format's bits tell every part apart" {
        try testing.expectEqual(@as(u64, 0) | (@as(u64, ' ') << 6), Format.display.bits());
        try testing.expect(Format.display.bits() != Format.debug_only.bits());
        try testing.expect((Format{ .width = 1 }).bits() != (Format{ .precision = 1, .has_precision = true }).bits());
        try testing.expect((Format{ .hex = .lower }).bits() != (Format{ .hex = .upper }).bits());
    }

    /// Write the spec in its canonical spelling, without the colon: `*>+6.2?`.
    /// Two formats spell the same text exactly when they are equal, so a type
    /// named by its formats is named injectively.
    pub fn format(self: Format, w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.alignment != .none) {
            if (self.fill != ' ') {
                var encoded: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(self.fill, &encoded) catch unreachable;
                try w.writeAll(encoded[0..n]);
            }
            try w.writeByte(alignmentByte(self.alignment));
        }
        if (self.plus) try w.writeByte('+');
        if (self.zero) try w.writeByte('0');
        if (self.width != 0) try w.print("{d}", .{self.width});
        if (self.has_precision) try w.print(".{d}", .{self.precision});
        switch (self.hex) {
            .none => {},
            .lower => try w.writeByte('x'),
            .upper => try w.writeByte('X'),
        }
        if (self.debug) try w.writeByte('?');
    }

    test "a format's canonical spelling reads back as the same format" {
        const texts = [_][]const u8{ "?", "02", ">4", ".2", "*^9?", "+08.3", "·>5", " <3", "+", ".0", "x", "08X", "x>4x" };
        for (texts) |text| {
            const parsed = parse(text).format;
            var buffer: [32]u8 = undefined;
            var w: std.Io.Writer = .fixed(&buffer);
            try parsed.format(&w);
            try testing.expectEqual(parsed.bits(), parse(w.buffered()).format.bits());
        }
    }
};

// Makes every test build compile the tests `Format` holds, including a build
// filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Format;
}

fn alignmentByte(alignment: Alignment) u8 {
    return switch (alignment) {
        .none => unreachable,
        .left => '<',
        .right => '>',
        .center => '^',
    };
}

fn alignmentOf(scalar: u21) ?Alignment {
    return switch (scalar) {
        '<' => .left,
        '>' => .right,
        '^' => .center,
        else => null,
    };
}

/// A refusal says what is wrong with a spec's text and what to write instead.
pub const Refusal = struct {
    message: []const u8,
    help: []const u8,
};

pub const Parsed = union(enum) {
    format: Format,
    refused: Refusal,
};

/// Read the text after a colon. The text is non-empty and holds no `}`,
/// quote or line break, because the lexer ends it before any of them.
pub fn parse(text: []const u8) Parsed {
    var format: Format = .{};
    var at: usize = 0;

    // A fill is one scalar, and it is a fill only when an alignment follows
    // it; otherwise the first scalar is read as whatever else it can be.
    if (scalarAt(text, 0)) |first| {
        if (scalarAt(text, first.len)) |second| {
            if (alignmentOf(second.value)) |alignment| {
                if (first.value == '{' or first.value == '\\') return refuse(
                    "a fill cannot be `{` or `\\`",
                    "these characters mean something else inside a string literal",
                );
                format.fill = first.value;
                format.alignment = alignment;
                at = first.len + second.len;
            }
        }
        if (format.alignment == .none) {
            if (alignmentOf(first.value)) |alignment| {
                format.alignment = alignment;
                at = first.len;
            }
        }
    } else return refuse("a format spec is text", "this byte begins no character");

    if (at < text.len and text[at] == '+') {
        format.plus = true;
        at += 1;
    }
    if (at < text.len and text[at] == '0') {
        format.zero = true;
        at += 1;
    }
    if (at < text.len and text[at] >= '1' and text[at] <= '9') {
        const count = number(text, &at) orelse return refuse(
            "a width is at most 65535",
            "no column of text is this wide",
        );
        format.width = count;
    }
    if (at < text.len and text[at] == '.') {
        at += 1;
        if (at == text.len or text[at] < '0' or text[at] > '9') return refuse(
            "a precision is a number of digits",
            "write digits after `.`, as in `.2`",
        );
        const count = number(text, &at) orelse return refuse(
            "a precision is at most 65535",
            "no Float64 has this many digits worth writing",
        );
        format.precision = count;
        format.has_precision = true;
    }
    // The last part chooses how the value's text is spelled: `x` or `X` for
    // an integer's base-16 digits, or `?` for Debug. A value has one
    // spelling, so a second of them is refused by name rather than as a part
    // out of order.
    if (at < text.len) switch (text[at]) {
        'x' => format.hex = .lower,
        'X' => format.hex = .upper,
        '?' => format.debug = true,
        else => {},
    };
    if (format.hex != .none or format.debug) {
        at += 1;
        if (at < text.len and (text[at] == 'x' or text[at] == 'X' or text[at] == '?')) return refuse(
            "a format spec takes one of `x`, `X` and `?`",
            "`x` and `X` write an integer's digits in base 16 and `?` renders through Debug; keep one",
        );
    }

    if (at != text.len) return refuse(
        "a format spec is written `[[fill]align][+][0][width][.precision][x|X|?]`",
        "this part is out of that order or is not one of them",
    );
    if (format.zero and format.alignment != .none) return refuse(
        "zero padding and an alignment cannot both lay out one value",
        "zeros always go between a number's sign and its digits; remove one",
    );
    if (format.zero and format.width == 0) return refuse(
        "zero padding needs a width",
        "write the width after `0`, as in `02`",
    );
    if (format.alignment != .none and format.width == 0) return refuse(
        "an alignment needs a width",
        "write the width after the alignment, as in `>4`",
    );
    return .{ .format = format };
}

fn expectFormat(text: []const u8, expected: Format) !void {
    switch (parse(text)) {
        .format => |got| try testing.expectEqual(expected.bits(), got.bits()),
        .refused => |refusal| {
            std.debug.print("`{s}` was refused: {s}\n", .{ text, refusal.message });
            return error.TestUnexpectedResult;
        },
    }
}

fn expectRefused(text: []const u8, message: []const u8) !void {
    switch (parse(text)) {
        .format => {
            std.debug.print("`{s}` was accepted\n", .{text});
            return error.TestUnexpectedResult;
        },
        .refused => |refusal| try testing.expectEqualStrings(message, refusal.message),
    }
}

test "a format spec reads each part in order" {
    try expectFormat("?", .{ .debug = true });
    try expectFormat("02", .{ .zero = true, .width = 2 });
    try expectFormat(">4", .{ .alignment = .right, .width = 4 });
    try expectFormat(".2", .{ .has_precision = true, .precision = 2 });
    try expectFormat("<10", .{ .alignment = .left, .width = 10 });
    try expectFormat("*^9?", .{ .fill = '*', .alignment = .center, .width = 9, .debug = true });
    try expectFormat("+08.3", .{ .plus = true, .zero = true, .width = 8, .has_precision = true, .precision = 3 });
    try expectFormat("·>5", .{ .fill = '·', .alignment = .right, .width = 5 });
    try expectFormat(">>3", .{ .fill = '>', .alignment = .right, .width = 3 });
    try expectFormat(".0", .{ .has_precision = true });
    try expectFormat("+", .{ .plus = true });
    try expectFormat("65535", .{ .width = 65535 });
    try expectFormat("x", .{ .hex = .lower });
    try expectFormat("08X", .{ .zero = true, .width = 8, .hex = .upper });
    try expectFormat("*>+6x", .{ .fill = '*', .alignment = .right, .plus = true, .width = 6, .hex = .lower });
    try expectFormat("x>3", .{ .fill = 'x', .alignment = .right, .width = 3 });
}

test "a format spec refuses parts out of order or without what they need" {
    try expectRefused("name", "a format spec is written `[[fill]align][+][0][width][.precision][x|X|?]`");
    try expectRefused("?4", "a format spec is written `[[fill]align][+][0][width][.precision][x|X|?]`");
    try expectRefused("0+4", "a format spec is written `[[fill]align][+][0][width][.precision][x|X|?]`");
    try expectRefused("<05", "zero padding and an alignment cannot both lay out one value");
    try expectRefused("0", "zero padding needs a width");
    try expectRefused(">", "an alignment needs a width");
    try expectRefused(".", "a precision is a number of digits");
    try expectRefused("65536", "a width is at most 65535");
    try expectRefused(".70000", "a precision is at most 65535");
    try expectRefused("{>4", "a fill cannot be `{` or `\\`");
    try expectRefused("\\>4", "a fill cannot be `{` or `\\`");
    try expectRefused("\xff", "a format spec is text");
    try expectRefused("x4", "a format spec is written `[[fill]align][+][0][width][.precision][x|X|?]`");
    try expectRefused("x?", "a format spec takes one of `x`, `X` and `?`");
    try expectRefused("xX", "a format spec takes one of `x`, `X` and `?`");
    try expectRefused("?x", "a format spec takes one of `x`, `X` and `?`");
}

test "fuzz: a parsed format spells text that parses back to it" {
    try testing.fuzz({}, struct {
        fn one(_: void, smith: *testing.Smith) anyerror!void {
            var bytes: [12]u8 = undefined;
            const text = bytes[0..smith.slice(&bytes)];
            if (text.len == 0) return;
            const format = switch (parse(text)) {
                .format => |f| f,
                .refused => return,
            };
            var buffer: [32]u8 = undefined;
            var w: std.Io.Writer = .fixed(&buffer);
            try format.format(&w);
            try testing.expectEqual(format.bits(), parse(w.buffered()).format.bits());
        }
    }.one, .{});
}

fn refuse(message: []const u8, help: []const u8) Parsed {
    return .{ .refused = .{ .message = message, .help = help } };
}

const Scalar = struct { value: u21, len: usize };

fn scalarAt(text: []const u8, at: usize) ?Scalar {
    if (at >= text.len) return null;
    const len = std.unicode.utf8ByteSequenceLength(text[at]) catch return null;
    if (at + len > text.len) return null;
    const value = std.unicode.utf8Decode(text[at..][0..len]) catch return null;
    return .{ .value = value, .len = len };
}

/// Read decimal digits from `at`, answering null once they pass `max_count`.
fn number(text: []const u8, at: *usize) ?u16 {
    var value: u32 = 0;
    while (at.* < text.len and text[at.*] >= '0' and text[at.*] <= '9') : (at.* += 1) {
        value = value * 10 + (text[at.*] - '0');
        if (value > max_count) return null;
    }
    return @intCast(value);
}
