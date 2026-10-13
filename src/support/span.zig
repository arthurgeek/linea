const std = @import("std");
const testing = std.testing;

/// A half-open byte range `[start, end)` into a `Source`'s text.
///
/// Offsets are `u32`. What that caps a source at is `source.max_bytes`, which
/// is half the field rather than all of it, because two offsets into one
/// source are added in the same width. The number lives there, with the read
/// that enforces it, rather than here where nothing could. Spans are the only
/// positional currency in the compiler; line and column are derived from them
/// by `SourceMap` when a diagnostic is rendered, and never stored.
pub const Span = struct {
    start: u32,
    end: u32,

    pub const empty: Span = .{ .start = 0, .end = 0 };

    pub fn len(self: Span) u32 {
        return self.end - self.start;
    }

    /// The smallest span covering both operands.
    pub fn merge(a: Span, b: Span) Span {
        return .{
            .start = @min(a.start, b.start),
            .end = @max(a.end, b.end),
        };
    }

    pub fn contains(self: Span, offset: u32) bool {
        return offset >= self.start and offset < self.end;
    }

    pub fn slice(self: Span, text: []const u8) []const u8 {
        return text[self.start..self.end];
    }
};

/// A span together with the file its offsets index into.
///
/// A pass that carries a position across a tree carries one of these, never a
/// bare `Span`: a module holds several files, and two spans from different
/// files compare and render as though they named the same place. The tree
/// stores spans alone because a token's file follows from where it sits; a
/// position lifted out of the tree and held has lost that.
pub const Loc = struct {
    file: @import("source.zig").FileId,
    span: Span,

    /// No position at all, which is distinct from a zero-width one: a caret
    /// between two bytes is somewhere, and this is nowhere.
    pub const nowhere: Loc = .{ .file = .none, .span = .empty };

    pub fn isNowhere(self: Loc) bool {
        return self.file == .none;
    }
};

test "len measures the half-open extent" {
    const s: Span = .{ .start = 4, .end = 9 };
    try testing.expectEqual(@as(u32, 5), s.len());
    try testing.expectEqual(@as(u32, 0), (Span{ .start = 3, .end = 3 }).len());
}

test "merge covers both operands" {
    const a: Span = .{ .start = 10, .end = 12 };
    const b: Span = .{ .start = 4, .end = 6 };
    const m = Span.merge(a, b);
    try testing.expectEqual(@as(u32, 4), m.start);
    try testing.expectEqual(@as(u32, 12), m.end);
}

test "contains is half-open" {
    const s: Span = .{ .start = 2, .end = 5 };
    try testing.expect(!s.contains(1));
    try testing.expect(s.contains(2));
    try testing.expect(s.contains(4));
    try testing.expect(!s.contains(5));
}

test "slice extracts the covered text" {
    const text = "let x = 42;";
    const s: Span = .{ .start = 8, .end = 10 };
    try testing.expectEqualStrings("42", s.slice(text));
}
