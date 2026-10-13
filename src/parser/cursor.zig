const std = @import("std");
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const Source = @import("../support/source.zig").Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const token = @import("../lexer/token.zig");
const Tag = token.Tag;
const TokenId = token.TokenId;
const TokenRange = token.TokenRange;
const TokenList = token.TokenList;

/// A view over the token stream with trivia skipped.
///
/// Comments are tokens so the stream can reproduce its source, but no grammar
/// rule should mention them. Skipping in one place keeps every rule free of
/// the concern. Invalid tokens are deliberately not skipped: the parser must
/// see them to report them.
pub const Cursor = struct {
    tags: []const Tag,
    spans: []const Span,
    source: []const u8,
    index: u32,

    /// `start` and `end` are where this file's tokens begin and end in a
    /// stream that may hold several. Indices stay stream-wide, so a `TokenId` a
    /// rule produces means the same thing whichever file it came from; `source`
    /// is that file's text, which is what its spans are offsets into.
    ///
    /// The view stops at `end`, so no lookahead can reach the next file's
    /// tokens and read their spans against this file's text.
    pub fn init(tokens: TokenList.Slice, source: []const u8, start: u32, end: u32) Cursor {
        var c: Cursor = .{
            .tags = tokens.items(.tag)[0..end],
            .spans = tokens.items(.span)[0..end],
            .source = source,
            .index = start,
        };
        c.skipTrivia();
        return c;
    }

    /// Whether a newline separates the current token from the one before it.
    ///
    /// Whitespace is the gap between adjacent spans, so this is a scan of that
    /// gap. Nothing about the token stream changes and nothing becomes a
    /// token: a newline is still not one.
    ///
    /// The token before is the one before in the *array*, comments included.
    /// That is what the rule wants -- a comment written between two statements
    /// sits on a line of its own, and the newline that ends the statement is
    /// the one before the comment rather than the one after it. Looking at the
    /// previous significant token instead would miss it.
    /// Whether the token before the cursor closes a brace.
    ///
    /// A statement whose last token is `}` is ended by it: a block is a
    /// delimiter a reader can see, so nothing after it can be mistaken for a
    /// continuation of what came before.
    pub fn precededByRBrace(self: *const Cursor) bool {
        if (self.index == 0 or self.index > self.tags.len) return false;
        return self.tags[self.index - 1] == .r_brace;
    }

    pub fn precededByNewline(self: *const Cursor) bool {
        return self.newlinesBefore() > 0;
    }

    /// Counts the line breaks between the current token and the one before
    /// it in the array, comments included, as `precededByNewline` reads it.
    /// More than one means a blank line separates them.
    pub fn newlinesBefore(self: *const Cursor) usize {
        if (self.index == 0 or self.index >= self.spans.len) return 0;
        const from = self.spans[self.index - 1].end;
        const to = self.spans[self.index].start;
        if (to <= from) return 0;
        return std.mem.count(u8, self.source[from..to], "\n");
    }

    /// The last significant token before the current one, or `.none` where
    /// nothing precedes it.
    ///
    /// Trivia is skipped here, unlike in `precededByNewline`: what the program
    /// last said is the last thing it said, and a comment says nothing. This
    /// is what a diagnostic about a break points at, and what `previousTag`
    /// reads, so the two cannot disagree about which token that is.
    pub fn previousToken(self: *const Cursor) TokenId {
        var i = self.index;
        while (i > 0) {
            i -= 1;
            if (!self.tags[i].isTrivia()) return TokenId.at(i);
        }
        return .none;
    }

    /// The tag of the last significant token before the current one.
    pub fn previousTag(self: *const Cursor) Tag {
        const previous = self.previousToken();
        if (previous == .none) return .eof;
        return self.tags[previous.index()];
    }

    /// Where the line the cursor sits on ends: the first token from here on
    /// that a line break precedes, or the end of the stream.
    ///
    /// The scan is over one line's tokens, not the program's -- it stops at
    /// the first break -- so a rule asking once per line pays for that line.
    pub fn lineEnd(self: *const Cursor) u32 {
        var c = self.*;
        while (!c.atEnd()) : (_ = c.advance()) {
            if (c.precededByNewline()) return c.index;
        }
        return c.index;
    }

    /// Reads no further than `end`, and answers with the view to restore.
    ///
    /// A rule written inside a region -- a refinement clause, which is the
    /// line its `where` opens -- reads it by hiding what lies past it: the
    /// region's end is then the end of input, so every rule reading inside it
    /// stops there through the check it already makes rather than through one
    /// of its own. Only the tags are hidden. The spans stay whole, so what a
    /// diagnostic points at is not bounded by where a rule may read.
    pub fn narrowTo(self: *Cursor, end: u32) Whole {
        const whole: Whole = .{ .tags = self.tags };
        self.tags = self.tags[0..end];
        return whole;
    }

    /// Reads the whole stream again, from wherever reading stopped.
    pub fn widen(self: *Cursor, whole: Whole) void {
        self.tags = whole.tags;
    }

    /// What `narrowTo` hid, which `widen` takes back.
    pub const Whole = struct { tags: []const Tag };

    fn skipTrivia(self: *Cursor) void {
        while (self.index < self.tags.len and self.tags[self.index].isTrivia()) {
            self.index += 1;
        }
    }

    pub fn atEnd(self: *const Cursor) bool {
        return self.index >= self.tags.len or self.tags[self.index] == .eof;
    }

    pub fn peek(self: *const Cursor) Tag {
        if (self.index >= self.tags.len) return .eof;
        return self.tags[self.index];
    }

    /// The tag `n` significant tokens ahead, trivia not counted.
    pub fn peekAt(self: *const Cursor, n: u32) Tag {
        const t = self.ahead(n) orelse return .eof;
        return self.tags[t.index()];
    }

    /// The token `n` significant tokens ahead, trivia not counted, or null
    /// past the end of this file's tokens.
    pub fn ahead(self: *const Cursor, n: u32) ?TokenId {
        var i = self.index;
        var remaining = n;
        while (remaining > 0) : (remaining -= 1) {
            if (i >= self.tags.len) return null;
            i += 1;
            while (i < self.tags.len and self.tags[i].isTrivia()) i += 1;
        }
        if (i >= self.tags.len) return null;
        return TokenId.at(i);
    }

    pub fn current(self: *const Cursor) TokenId {
        return TokenId.at(self.index);
    }

    /// Moves to a token-array position and applies the cursor's ordinary
    /// trivia rule. Used by syntax lookahead after a cached balanced region.
    pub fn seek(self: *Cursor, index: u32) void {
        self.index = index;
        self.skipTrivia();
    }

    pub fn textOf(self: *const Cursor, t: TokenId) []const u8 {
        return self.spans[t.index()].slice(self.source);
    }

    pub fn spanAt(self: *const Cursor, t: TokenId) Span {
        return self.spans[t.index()];
    }

    /// The spaces and tabs that indent the line `t` begins, or null where
    /// something else stands before `t` on its line. The scan reads back over
    /// the whitespace directly before `t` and no further, so it costs that gap
    /// however long the line is.
    pub fn lineIndent(self: *const Cursor, t: TokenId) ?[]const u8 {
        const offset = self.spans[t.index()].start;
        var start = offset;
        while (start > 0 and (self.source[start - 1] == ' ' or self.source[start - 1] == '\t')) start -= 1;
        if (start > 0 and self.source[start - 1] != '\n') return null;
        return self.source[start..offset];
    }

    test lineIndent {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        var c = try cursorOver(arena.allocator(), "a {\n    b }\r\n\t }");
        try testing.expectEqualStrings("", c.lineIndent(c.current()).?);
        _ = c.advance();
        try testing.expect(c.lineIndent(c.current()) == null);
        _ = c.advance();
        try testing.expectEqualStrings("    ", c.lineIndent(c.current()).?);
        _ = c.advance();
        try testing.expect(c.lineIndent(c.current()) == null);
        _ = c.advance();
        try testing.expectEqualStrings("\t ", c.lineIndent(c.current()).?);
    }

    /// The byte extent of a half-open token range. An empty range collapses to
    /// the position where its tokens would have started, which is what a
    /// diagnostic about something missing needs to point at.
    pub fn spanOf(self: *const Cursor, range: TokenRange) Span {
        if (range.len() == 0) {
            const offset = self.spans[range.start.index()].start;
            return .{ .start = offset, .end = offset };
        }
        return .{
            .start = self.spans[range.start.index()].start,
            .end = self.spans[range.end.index() - 1].end,
        };
    }

    pub fn at(self: *const Cursor, tag: Tag) bool {
        return self.peek() == tag;
    }

    /// Consumes the current token and returns it. At end of input the position
    /// does not move, so a rule that forgets to check cannot run away.
    pub fn advance(self: *Cursor) TokenId {
        const here = TokenId.at(self.index);
        if (self.atEnd()) return here;
        self.index += 1;
        self.skipTrivia();
        return here;
    }

    pub fn eat(self: *Cursor, tag: Tag) ?TokenId {
        if (!self.at(tag)) return null;
        return self.advance();
    }
};

// Compiles the tests `Cursor` holds beside the functions they test.
comptime {
    _ = Cursor;
}

fn cursorOver(gpa: std.mem.Allocator, text: []const u8) !Cursor {
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    return Cursor.init(tokens.slice(), text, 0, @intCast(tokens.len));
}

test "comments are invisible to the parser" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var c = try cursorOver(arena.allocator(), "let // note\nx");
    try testing.expectEqual(Tag.keyword_let, c.peek());
    _ = c.advance();
    try testing.expectEqual(Tag.identifier, c.peek());
}

test "leading trivia is skipped before the first token" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var c = try cursorOver(arena.allocator(), "// header\nlet x");
    try testing.expectEqual(Tag.keyword_let, c.peek());
}

test "invalid tokens stay visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The parser must see these to report them; only comments are trivia.
    var c = try cursorOver(arena.allocator(), "###");
    try testing.expectEqual(Tag.invalid, c.peek());
}

test "eat consumes on match and leaves position on mismatch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var c = try cursorOver(arena.allocator(), "let x");
    try testing.expect(c.eat(.semicolon) == null);
    try testing.expectEqual(Tag.keyword_let, c.peek());
    try testing.expect(c.eat(.keyword_let) != null);
    try testing.expectEqual(Tag.identifier, c.peek());
}

test "peekAt counts significant tokens, not trivia" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var c = try cursorOver(arena.allocator(), "let // c\n y = 1;");
    try testing.expectEqual(Tag.keyword_let, c.peekAt(0));
    try testing.expectEqual(Tag.identifier, c.peekAt(1));
    try testing.expectEqual(Tag.equal, c.peekAt(2));
}

test "advancing past the end stays at eof" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var c = try cursorOver(arena.allocator(), "x");
    _ = c.advance();
    try testing.expect(c.atEnd());
    _ = c.advance();
    try testing.expect(c.atEnd());
    try testing.expectEqual(Tag.eof, c.peek());
}

test "a newline between two tokens is visible to the cursor" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var c = try cursorOver(arena.allocator(), "let x\n= 1");
    // Nothing precedes the first token.
    try testing.expect(!c.precededByNewline());
    _ = c.advance(); // x
    try testing.expect(!c.precededByNewline());
    _ = c.advance(); // =
    try testing.expect(c.precededByNewline());
}

test "newlinesBefore counts the breaks between a token and the one before it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var c = try cursorOver(arena.allocator(), "a b\n\n  c");
    try testing.expectEqual(@as(usize, 0), c.newlinesBefore());
    _ = c.advance(); // b
    try testing.expectEqual(@as(usize, 0), c.newlinesBefore());
    _ = c.advance(); // c, after a blank line
    try testing.expectEqual(@as(usize, 2), c.newlinesBefore());
}

test "a comment between two tokens does not hide the newline before them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var c = try cursorOver(arena.allocator(), "x\n// why\ny");
    _ = c.advance(); // y, with a comment and two newlines in between
    try testing.expectEqual(Tag.identifier, c.peek());
    try testing.expect(c.precededByNewline());
}

test "spans are reachable for diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const c = try cursorOver(arena.allocator(), "let x");
    try testing.expectEqual(@as(u32, 0), c.spanAt(c.current()).start);
    try testing.expectEqual(@as(u32, 3), c.spanAt(c.current()).end);
}
