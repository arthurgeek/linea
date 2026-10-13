const std = @import("std");
const tracy = @import("../support/tracy.zig");
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const source_mod = @import("../support/source.zig");
const Source = source_mod.Source;
const FileId = source_mod.FileId;
const Sink = @import("../diagnostics/sink.zig").Sink;
const interner_mod = @import("../support/interner.zig");
const literal_text = @import("../support/text.zig");
const Interner = interner_mod.Interner;
const StringId = interner_mod.StringId;
const Code = @import("../diagnostics/diagnostic.zig").Code;
const token = @import("token.zig");
const Tag = token.Tag;
const Token = token.Token;
const TokenList = token.TokenList;

/// Converts source text into a token stream.
///
/// Cannot fail on malformed input. Unrecognised bytes become `.invalid` tokens
/// and problems are appended to `sink`; the only errors are allocation
/// failures.
///
/// The result always ends with an `.eof` token. Token spans are ordered and
/// non-overlapping, and the gap between one span's end and the next span's
/// start is exactly the whitespace between them, which is what allows the
/// stream to reconstruct the source.
pub fn tokenize(
    gpa: std.mem.Allocator,
    source: *const Source,
    file: FileId,
    sink: *Sink,
    interner: *Interner,
) std.mem.Allocator.Error!TokenList {
    var list: TokenList = .empty;
    errdefer list.deinit(gpa);
    try tokenizeInto(gpa, source, file, sink, interner, &list);
    return list;
}

/// Appends one file's tokens to a stream that may already hold others.
///
/// Spans stay offsets into their own file: what a token stream describes is a
/// file, and only the identity of the file the run belongs to is external to
/// it. This is what lets a module's files share one stream without any of them
/// being rewritten to sit inside it.
pub fn tokenizeInto(
    gpa: std.mem.Allocator,
    source: *const Source,
    file: FileId,
    sink: *Sink,
    interner: *Interner,
    list: *TokenList,
) std.mem.Allocator.Error!void {
    const zone = tracy.beginZone(@src(), "lex");
    defer zone.end();

    // Once over the file, before a token is read. `[S-Encoding]` says a source
    // is UTF-8, and a `Str`'s invariant rests on it: a literal's bytes are text
    // by construction only if the file they came from was. Checked here rather
    // than per literal, because it is a fact about the file.
    const z_utf8 = tracy.beginZone(@src(), "lex.utf8");
    const invalid = firstInvalidUtf8(source.text);
    z_utf8.end();
    if (invalid) |at| {
        try sink.addError(
            .s_encoding,
            file,
            .{ .start = @intCast(at), .end = @intCast(@min(at + 1, source.text.len)) },
            "save the file as UTF-8",
            "this byte begins no UTF-8 sequence",
        );
    }

    var lexer: Lexer = .{ .text = source.text, .file = file };
    while (true) {
        var t = try lexer.next(sink);
        // Only an identifier carries a name. A reserved word is told from an
        // identifier by its tag, and nothing looks either up by text.
        if (t.tag == .identifier) {
            t.name = try interner.intern(gpa, t.span.slice(source.text));
        }
        // Whether a literal's escapes can be read, asked through the routine
        // that later writes out what they mean -- so what is validated here
        // and what is emitted there cannot come to disagree.
        if (t.tag == .string_literal or t.tag == .str_open or
            t.tag == .str_mid or t.tag == .str_close)
        {
            if (try literal_text.decode(gpa, null, t.span.slice(source.text))) |at| {
                const from = t.span.start + @as(u32, @intCast(at)) + 1;
                try sink.addError(
                    .s_escape,
                    file,
                    .{ .start = from, .end = @min(from + 1, t.span.end) },
                    "an escape names one of `n`, `t`, `r`, `0`, a backslash, a quote, or `u{...}`",
                    "this escape means nothing",
                );
            }
        }
        try list.append(gpa, t);
        if (t.tag == .eof) break;
    }
}

/// Whether the whole of this text is read as one identifier.
///
/// **This is the answer to whether a text is a name**, and the only one: what
/// an identifier is, is decided by the scanner above, and a predicate written
/// beside it would accept `let` -- a reserved word is told from an identifier
/// by the tag a token carries, and nothing else assigns one.
///
/// The whole of the text, so a name with a space in it is refused rather than
/// silently trimmed.
///
/// Costs one scan of the text, and holds what one scan of it produced.
pub fn isIdentifier(gpa: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!bool {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    const source: Source = .{ .path = "", .text = text };
    var sink = Sink.init(a);
    var interner: Interner = .empty;
    var tokens = try tokenize(a, &source, .from(0), &sink, &interner);

    const list = tokens.slice();
    const tags = list.items(.tag);
    if (tags.len != 2 or tags[0] != .identifier or tags[1] != .eof) return false;

    const span = list.items(.span)[0];
    return span.start == 0 and span.end == text.len;
}

/// Where a file stops being UTF-8, or null where it never does.
///
/// The offset rather than a yes or no, so the diagnostic can point at the byte
/// instead of at the file.
/// A byte under 0x80 stands for itself, and program text is nearly all of
/// them, so the common byte is skipped without being decoded -- a word at a
/// time while none in it has the high bit set. What is left is what actually
/// needs UTF-8 read out of it.
///
/// This is one pass over every byte of every file before a token is read, and
/// decoding each of them made it a fifth of what lexing costs, which is the
/// largest thing the front end does.
fn firstInvalidUtf8(bytes: []const u8) ?usize {
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

/// How many interpolations may be open at once. A literal inside an
/// interpolation may interpolate in turn, and each level is one entry; past
/// this the program is a mistake rather than a program, and the scanner says so
/// rather than losing count.
const max_interpolation = 16;

/// How many `#` may open a raw literal. Text that needs `n` of them contains a
/// `"` followed by `n - 1`, so this is far beyond real text; the bound lets an
/// editor grammar, which can match each count only as its own regular
/// expression, agree with the compiler about every literal.
pub const max_raw_hashes = 8;

const Lexer = struct {
    text: []const u8,
    /// Which file the spans it produces index into. Carried so a diagnostic
    /// raised deep in the scanner names its own file without threading it
    /// through every helper.
    file: FileId,
    index: u32 = 0,
    /// The brace depth inside each interpolation currently open, innermost
    /// last. A `}` where the innermost depth is zero is not punctuation: it
    /// ends the expression and the literal resumes.
    ///
    /// A stack rather than a counter, because a literal may appear inside an
    /// interpolation and interpolate in turn. Fixed, because the scanner has no
    /// allocator, and small: nesting this deep is a mistake rather than a
    /// program, and it is refused rather than miscounted.
    interpolation: [max_interpolation]u32 = undefined,
    /// `grouping` counts the parenthesis and bracket depth inside each open
    /// interpolation. A colon where this and the brace depth are zero begins
    /// the value's format spec; one inside `f(name: x)` or `[T: Bound]` is
    /// punctuation.
    grouping: [max_interpolation]u32 = undefined,
    open: u32 = 0,
    /// The colon that begins a format spec sets this, so the next token is
    /// the spec's text rather than ordinary tokens.
    spec_next: bool = false,

    fn atEnd(self: *const Lexer) bool {
        return self.index >= self.text.len;
    }

    /// Whether a `}` here closes an interpolation rather than punctuating one.
    fn resumesLiteral(self: *const Lexer) bool {
        if (self.open == 0) return false;
        return self.interpolation[self.open - 1] == 0;
    }

    /// What opened the run of literal text being scanned.
    const Opener = enum { quote, brace };

    /// One run of literal text, from an opening `"` or a closing `}` up to
    /// whichever comes first: the `{` that opens an interpolation, or the `"`
    /// that ends the literal.
    ///
    /// Which of the four tags this is falls out of the pair — what opened the
    /// run and what closed it — so the scanner decides where the run ends and
    /// nothing else has to agree about it.
    ///
    /// `{{` is a literal `{`. A `}` is ordinary here and needs no doubling:
    /// this scanner only runs where no interpolation is open, so there is
    /// nothing for one to close and nothing to be ambiguous about.
    fn literalRun(self: *Lexer, sink: *Sink, start: u32, opened: Opener) !Token {
        while (self.peek()) |c| {
            self.index += 1;

            // A backslash takes the next byte with it, which is what stops
            // `"say \"hi\""` ending at the quote in the middle. Whether the
            // escape means anything is the decoder's question; the lexer's is
            // only where the literal ends.
            if (c == '\\') {
                if (self.peek()) |escaped| {
                    if (escaped == '\n') continue;
                    self.index += 1;
                    // `\u{...}` carries braces of its own, and they are the
                    // escape's rather than an interpolation's. Consumed here,
                    // or `"\u{e1}"` opens an interpolation at the `{` and the
                    // literal ends somewhere nobody wrote.
                    if (escaped == 'u') {
                        while (self.peek()) |u| {
                            if (u == '\n' or u == '"') break;
                            self.index += 1;
                            if (u == '}') break;
                        }
                    }
                }
                continue;
            }

            if (c == '{') {
                // Doubled, so it is a `{` in the text rather than the start of
                // an expression. Both bytes belong to the run.
                if (self.peek() == @as(?u8, '{')) {
                    self.index += 1;
                    continue;
                }
                if (self.open == max_interpolation) {
                    const t = self.make(.invalid, start);
                    try sink.addError(
                        .s_string,
                        self.file,
                        t.span,
                        "this literal interpolates too deeply",
                        "an interpolation inside an interpolation, too many times over",
                    );
                    return t;
                }
                self.interpolation[self.open] = 0;
                self.grouping[self.open] = 0;
                self.open += 1;
                return self.make(if (opened == .quote) .str_open else .str_mid, start);
            }

            if (c == '"') {
                return self.make(if (opened == .quote) .string_literal else .str_close, start);
            }
            if (c == '\n') break;
        }

        const t = self.make(.invalid, start);
        try sink.addError(
            .s_string,
            self.file,
            t.span,
            "unterminated string literal",
            "string starts here and is never closed",
        );
        return t;
    }

    /// The number of `#` between an `r` at the current index and the `"` that
    /// opens a raw literal, or null where no quote follows them and the `r`
    /// begins an ordinary name.
    fn rawOpener(self: *const Lexer) ?u32 {
        var at: u32 = 1;
        while (self.peekAt(at) == @as(?u8, '#')) at += 1;
        if (self.peekAt(at) != @as(?u8, '"')) return null;
        return at - 1;
    }

    /// A raw literal, `r"…"` or `r#"…"#`, from its `r` to the `"` followed by
    /// as many `#` as opened it. Nothing between the quotes is read: a `{`
    /// opens no interpolation and a backslash begins no escape, so the first
    /// such closing sequence ends the literal.
    ///
    /// It is a `string_literal` token, because a raw literal is a string
    /// literal wherever one may stand; only its spelling differs, and the text
    /// decoder reads the spelling.
    ///
    /// Like an ordinary literal it ends at a line break, and an unclosed one
    /// becomes an invalid token running to the end of its line.
    ///
    /// At most `max_raw_hashes` may open one. A literal opened by more is read
    /// to its close all the same, so the text after it lexes as it would, and
    /// becomes one invalid token.
    fn rawLiteral(self: *Lexer, sink: *Sink, start: u32, hashes: u32) !Token {
        self.index += hashes + 2;
        const closed = while (self.peek()) |c| {
            self.index += 1;
            if (c == '"' and self.closesRaw(hashes)) {
                self.index += hashes;
                break true;
            }
            if (c == '\n') break false;
        } else false;

        if (hashes > max_raw_hashes) {
            const t = self.make(.invalid, start);
            try sink.addErrorFmt(
                .s_string,
                self.file,
                t.span,
                "open it with fewer `#`",
                "a raw literal opens with at most {d} `#`, and this one opens with {d}",
                .{ max_raw_hashes, hashes },
            );
            return t;
        }
        if (closed) return self.make(.string_literal, start);

        const t = self.make(.invalid, start);
        if (hashes == 0) {
            try sink.addError(
                .s_string,
                self.file,
                t.span,
                "unterminated raw string literal",
                "string starts here and is never closed",
            );
        } else {
            try sink.addErrorFmt(
                .s_string,
                self.file,
                t.span,
                "string starts here and is never closed",
                "unterminated raw string literal: it closes at `\"{s}`",
                .{self.text[start + 1 ..][0..hashes]},
            );
        }
        return t;
    }

    /// Scans one line of a multi-line literal, from its `\\` to the end of
    /// its line.
    ///
    /// Nothing on the line is read: a quote, a brace, a backslash and `//`
    /// are all text, so the line always ends where the source line does and
    /// needs no closing delimiter. A `\r` directly before the `\n` belongs to
    /// the line break rather than to the text, so a file saved with either
    /// line ending holds the same text.
    ///
    /// Each line is a token of its own. Which lines make up one literal is the
    /// parser's question, answered from what separates them.
    fn stringLine(self: *Lexer, start: u32) Token {
        self.index += 2;
        while (self.peek()) |c| {
            if (c == '\n') break;
            if (c == '\r' and self.peekAt(1) == @as(?u8, '\n')) break;
            self.index += 1;
        }
        return self.make(.string_line, start);
    }

    /// Whether the `hashes` bytes at the current index are all `#`, so that
    /// the quote just read closes a raw literal opened with that many.
    fn closesRaw(self: *const Lexer, hashes: u32) bool {
        if (self.text.len - self.index < hashes) return false;
        for (self.text[self.index..][0..hashes]) |c| {
            if (c != '#') return false;
        }
        return true;
    }

    /// Scan the spec after an interpolation's colon: every byte up to the `}`
    /// that closes the interpolation, less the spaces around it. It stops at a
    /// quote or a line break too, where the literal would end with the
    /// interpolation still open, so the parser reports that as it would for
    /// any unclosed interpolation. It answers null where only
    /// spaces follow the colon.
    fn formatSpec(self: *Lexer) ?Token {
        while (self.peek()) |c| {
            if (c != ' ' and c != '\t') break;
            self.index += 1;
        }
        const start = self.index;
        var end = start;
        while (self.peek()) |c| {
            if (c == '}' or c == '"' or c == '\n' or c == '\r') break;
            self.index += 1;
            if (c != ' ' and c != '\t') end = self.index;
        }
        self.index = end;
        if (end == start) return null;
        return self.make(.format_spec, start);
    }

    fn peek(self: *const Lexer) ?u8 {
        if (self.atEnd()) return null;
        return self.text[self.index];
    }

    fn peekAt(self: *const Lexer, offset: u32) ?u8 {
        const i = self.index + offset;
        if (i >= self.text.len) return null;
        return self.text[i];
    }

    fn isDigitAt(self: *const Lexer, offset: u32) bool {
        const c = self.peekAt(offset) orelse return false;
        return std.ascii.isDigit(c);
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.peek()) |ch| {
            if (classify(ch) != .whitespace) return;
            self.index += 1;
        }
    }

    fn make(self: *const Lexer, tag: Tag, start: u32) Token {
        return .{ .tag = tag, .span = .{ .start = start, .end = self.index } };
    }

    fn isIdentStart(ch: u8) bool {
        return std.ascii.isAlphabetic(ch) or ch == '_';
    }

    fn isIdentContinue(ch: u8) bool {
        return std.ascii.isAlphanumeric(ch) or ch == '_';
    }

    /// What a byte can begin.
    ///
    /// The single place a byte is classified. Dispatch and invalid-run
    /// recovery both consult it, so a new token cannot be recognised in one
    /// and overlooked in the other.
    const Start = union(enum) {
        whitespace,
        ident,
        digit,
        string,
        /// `\\` opens a line of a multi-line literal; a lone backslash begins
        /// no token.
        backslash,
        /// A token whose spelling is exactly this one byte.
        punct: Tag,
        /// Begins no token at all, which is what bounds an invalid run.
        none,
    };

    fn classify(ch: u8) Start {
        if (isIdentStart(ch)) return .ident;
        if (std.ascii.isDigit(ch)) return .digit;
        return switch (ch) {
            ' ', '\t', '\r', '\n' => .whitespace,
            '"' => .string,
            '\\' => .backslash,
            '.' => .{ .punct = .dot },
            '?' => .{ .punct = .question },
            ':' => .{ .punct = .colon },
            '&' => .{ .punct = .ampersand },
            '|' => .{ .punct = .pipe },
            '!' => .{ .punct = .bang },
            '=' => .{ .punct = .equal },
            '<' => .{ .punct = .less },
            '>' => .{ .punct = .greater },
            '+' => .{ .punct = .plus },
            '-' => .{ .punct = .minus },
            '*' => .{ .punct = .star },
            '/' => .{ .punct = .slash },
            '%' => .{ .punct = .percent },
            '^' => .{ .punct = .caret },
            '@' => .{ .punct = .at_sign },
            '(' => .{ .punct = .l_paren },
            ')' => .{ .punct = .r_paren },
            '{' => .{ .punct = .l_brace },
            '}' => .{ .punct = .r_brace },
            '[' => .{ .punct = .l_bracket },
            ']' => .{ .punct = .r_bracket },
            ',' => .{ .punct = .comma },
            ';' => .{ .punct = .semicolon },
            else => .none,
        };
    }

    fn next(self: *Lexer, sink: *Sink) std.mem.Allocator.Error!Token {
        if (self.spec_next) {
            self.spec_next = false;
            if (self.formatSpec()) |spec| return spec;
        }
        const before = self.index;
        self.skipWhitespace();
        // A string literal ends at its line, so every interpolation still open
        // there ends with it. Without this a later `}` would resume a literal
        // nobody is writing, and a later colon would begin a format spec.
        if (self.open > 0 and std.mem.indexOfScalar(u8, self.text[before..self.index], '\n') != null) {
            self.open = 0;
        }

        const start = self.index;
        const ch = self.peek() orelse return self.make(.eof, start);

        // Inside an interpolation a brace may be punctuation or may be the end
        // of the expression, and only the depth says which. Asked before
        // anything else, because `}` is otherwise an ordinary `r_brace` and a
        // struct literal written in an interpolation would close it early.
        if (self.open > 0) {
            const level = self.open - 1;
            switch (ch) {
                '{' => self.interpolation[level] += 1,
                '}' => {
                    if (self.resumesLiteral()) {
                        self.open -= 1;
                        self.index += 1;
                        return self.literalRun(sink, start, .brace);
                    }
                    self.interpolation[level] -= 1;
                },
                '(', '[' => self.grouping[level] += 1,
                ')', ']' => self.grouping[level] -|= 1,
                // Outside every group of the value, a colon ends the value
                // and its format spec follows.
                ':' => if (self.interpolation[level] == 0 and self.grouping[level] == 0) {
                    self.index += 1;
                    self.spec_next = true;
                    return self.make(.colon, start);
                },
                else => {},
            }
        }

        // Two-character tokens are checked before classification, which sees
        // one byte at a time.
        if (ch == '-' and self.peekAt(1) == '>') {
            self.index += 2;
            return self.make(.arrow, start);
        }

        // `..=` before `..` before `.`, so the longest spelling wins at every
        // length.
        if (ch == '.' and self.peekAt(1) == '.') {
            if (self.peekAt(2) == '=') {
                self.index += 3;
                return self.make(.dot_dot_equal, start);
            }
            self.index += 2;
            return self.make(.dot_dot, start);
        }

        // Doubled operators, checked before the `=`-suffixed ones below so that
        // `!=` stays one token rather than a `!` followed by an `=`.
        if (self.peekAt(1) == ch) {
            const doubled: ?token.Tag = switch (ch) {
                '&' => .ampersand_ampersand,
                '|' => .pipe_pipe,
                else => null,
            };
            if (doubled) |tag| {
                self.index += 2;
                return self.make(tag, start);
            }
        }

        // A comparison that ends in `=` is one token.
        if (ch == '=' and self.peekAt(1) == '>') {
            self.index += 2;
            return self.make(.fat_arrow, start);
        }

        // An operator followed by `=` is one token: a comparison, or a compound
        // assignment.
        if (self.peekAt(1) == '=') {
            const two: ?token.Tag = switch (ch) {
                '=' => .equal_equal,
                '!' => .bang_equal,
                '<' => .less_equal,
                '>' => .greater_equal,
                // An operator and an equals is one token, which is what keeps
                // `v += 1` from lexing as `v + (= 1)`.
                '+' => .plus_equal,
                '-' => .minus_equal,
                '*' => .star_equal,
                '/' => .slash_equal,
                '%' => .percent_equal,
                else => null,
            };
            if (two) |tag| {
                self.index += 2;
                return self.make(tag, start);
            }
        }

        if (ch == '/' and self.peekAt(1) == '/') {
            while (self.peek()) |c| {
                if (c == '\n') break;
                self.index += 1;
            }
            return self.make(.comment, start);
        }

        switch (classify(ch)) {
            .ident => {
                // `r` directly before a quote, or before hashes and a quote,
                // opens a raw literal. Anywhere else it is a name.
                if (ch == 'r') {
                    if (self.rawOpener()) |hashes| return self.rawLiteral(sink, start, hashes);
                }
                self.index += 1;
                while (self.peek()) |c| {
                    if (!isIdentContinue(c)) break;
                    self.index += 1;
                }
                const lexeme = self.text[start..self.index];
                return self.make(Tag.keywordFromLexeme(lexeme) orelse .identifier, start);
            },

            .digit => {
                while (self.peek()) |c| {
                    if (!std.ascii.isDigit(c)) break;
                    self.index += 1;
                }

                // A `.` joins the number only when a digit follows it. That
                // one byte of lookahead is what keeps `0..9` three tokens and
                // `1.foo` an access: a trailing point belongs to whatever
                // comes after the number, never to the number.
                var is_float = false;
                if (self.peek() == '.' and self.isDigitAt(1)) {
                    is_float = true;
                    self.index += 1;
                    while (self.peek()) |c| {
                        if (!std.ascii.isDigit(c)) break;
                        self.index += 1;
                    }
                }

                // An exponent joins on the same terms, one byte further out
                // when it carries a sign. `1e` is a number and a name, because
                // a bare integer promises nothing about what follows it; the
                // point is what commits the token to being a float, and after
                // that commitment a digitless exponent is a mistake in the
                // literal rather than a name beside it.
                if (self.peek()) |c| {
                    if (c == 'e' or c == 'E') {
                        const signed = self.peekAt(1) == '+' or self.peekAt(1) == '-';
                        const digits_at: u32 = if (signed) 2 else 1;
                        if (self.isDigitAt(digits_at)) {
                            is_float = true;
                            self.index += digits_at;
                            while (self.peek()) |d| {
                                if (!std.ascii.isDigit(d)) break;
                                self.index += 1;
                            }
                        } else if (is_float) {
                            // The lexer has no error path: the bytes still
                            // land in a token's span, because a formatter must
                            // print back a file that does not compile.
                            self.index += 1;
                            const t = self.make(.float_literal, start);
                            try sink.addError(
                                .s_float,
                                self.file,
                                t.span,
                                "float literal is unfinished",
                                "digits are required on both sides of the point, and in an exponent",
                            );
                            return t;
                        }
                    }
                }

                // A trailing point that begins neither a range nor an access
                // has no reading: nothing follows it that could own it, so it
                // is an unfinished float rather than a dot for later.
                if (!is_float and self.peek() == '.') {
                    const after = self.peekAt(1);
                    const continues = after == '.' or
                        (after != null and isIdentStart(after.?));
                    if (!continues) {
                        self.index += 1;
                        const t = self.make(.float_literal, start);
                        try sink.addError(
                            .s_float,
                            self.file,
                            t.span,
                            "float literal is unfinished",
                            "digits are required on both sides of the point, and in an exponent",
                        );
                        return t;
                    }
                }

                return self.make(if (is_float) .float_literal else .int_literal, start);
            },

            .string => {
                self.index += 1;
                return self.literalRun(sink, start, .quote);
            },

            .punct => |tag| {
                self.index += 1;
                return self.make(tag, start);
            },

            // A lone backslash is the first byte of an invalid run, which the
            // loop below carries on from the byte after it.
            .backslash => {
                if (self.peekAt(1) == @as(?u8, '\\')) {
                    if (self.open == 0) return self.stringLine(start);
                    // Inside an interpolation a line would run over the `}`
                    // and the quote that close it, so the two backslashes are
                    // refused on their own and the literal still closes.
                    self.index += 2;
                    const t = self.make(.invalid, start);
                    try sink.addError(
                        .s_string,
                        self.file,
                        t.span,
                        "a multi-line literal cannot begin inside an interpolation",
                        "an interpolation closes on its own line",
                    );
                    return t;
                }
                self.index += 1;
            },

            // `skipWhitespace` ran first, so the current byte is not whitespace.
            .whitespace => unreachable,

            .none => {},
        }

        // A maximal run of bytes that begin no token becomes one token and one
        // diagnostic. Reporting per byte would bury the real problem under a
        // diagnostic for every character of a mistyped line.
        while (self.peek()) |c| {
            // A lone backslash begins no token either; only `\\` ends the run.
            const lone_backslash = c == '\\' and self.peekAt(1) != @as(?u8, '\\');
            if (classify(c) != .none and !lone_backslash) break;
            self.index += 1;
        }
        const t = self.make(.invalid, start);
        try sink.addErrorFmt(
            .s_char,
            self.file,
            t.span,
            "not a valid token",
            "unexpected character '{c}'",
            .{ch},
        );
        return t;
    }
};

const TestCtx = struct {
    arena: std.heap.ArenaAllocator,
    source: Source,
    sink: Sink,
    interner: Interner,
    tokens: TokenList,

    fn deinit(self: *TestCtx) void {
        self.arena.deinit();
    }

    fn tags(self: *TestCtx) []const Tag {
        return self.tokens.slice().items(.tag);
    }

    fn spans(self: *TestCtx) []const Span {
        return self.tokens.slice().items(.span);
    }
};

fn lex(text: []const u8) !TestCtx {
    var ctx: TestCtx = .{
        .arena = std.heap.ArenaAllocator.init(testing.allocator),
        .source = .{ .path = "t.lin", .text = text },
        .sink = undefined,
        .interner = undefined,
        .tokens = undefined,
    };
    ctx.sink = Sink.init(ctx.arena.allocator());
    ctx.interner = .empty;
    ctx.tokens = try tokenize(ctx.arena.allocator(), &ctx.source, .from(0), &ctx.sink, &ctx.interner);
    return ctx;
}

/// The lexer is total: every byte sequence is a token stream, and that stream
/// reproduces its input exactly. Both halves are properties rather than
/// expected outputs, which is what lets a generator supply the input.
fn fuzzReconstruction(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [256]u8 = undefined;
    const len = smith.slice(&buf);
    const text = buf[0..len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "fuzz.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    // The token stream reconstructs its source byte for byte. Whitespace is
    // the gap between adjacent spans, so nothing may be lost or invented.
    var out: std.Io.Writer.Allocating = .init(gpa);
    try token.reconstruct(tokens.slice().items(.span), source.text, &out.writer);
    try std.testing.expectEqualStrings(text, out.written());
}

test "fuzz: lexing any input reconstructs it" {
    // Every input this property has ever failed on, replayed before any
    // new one is tried -- so a crash the fuzzer found once cannot come
    // back unnoticed, and a search starts where the last one got to.
    try std.testing.fuzz({}, fuzzReconstruction, .{ .corpus = @import("fuzz_corpus").lexer });
}

test "every input the fuzzer found for this still passes" {
    // Replayed here as well as handed to the fuzzer, because the two run at
    // different times: a search runs nightly and on a push, and this runs
    // whenever anyone builds. A regression that only fails in CI is one
    // somebody finds after they have moved on.
    for (@import("fuzz_corpus").lexer) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try fuzzReconstruction({}, &smith);
    }
}

test "the logical operators are one token each" {
    var a = try lex("! && ||");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{
        .bang, .ampersand_ampersand, .pipe_pipe, .eof,
    }, a.tags());
}

test "a lone pipe and a doubled pipe are distinct tokens" {
    var a = try lex("| ||");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .pipe, .pipe_pipe, .eof }, a.tags());
}

test "a two-character operator lexes as one token, its parts still alone" {
    var a = try lex("->");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .arrow, .eof }, a.tags());

    var b = try lex("- >");
    defer b.deinit();
    try testing.expectEqualSlices(Tag, &.{ .minus, .greater, .eof }, b.tags());

    var c = try lex("1-2");
    defer c.deinit();
    try testing.expectEqualSlices(Tag, &.{ .int_literal, .minus, .int_literal, .eof }, c.tags());

    var d = try lex("<= < == = != >=");
    defer d.deinit();
    try testing.expectEqualSlices(Tag, &.{
        .less_equal, .less,       .equal_equal,
        .equal,      .bang_equal, .greater_equal,
        .eof,
    }, d.tags());

    // `!` is a token of its own now that it negates a `Bool`, and `!=` still
    // wins over it because the doubled and `=`-suffixed forms are checked
    // before any single byte is classified.
    var e = try lex("! !=");
    defer e.deinit();
    try testing.expectEqualSlices(Tag, &.{ .bang, .bang_equal, .eof }, e.tags());
}

test "a colon and a type name lex" {
    // A primitive is an ordinary identifier: what makes `UInt8` a type is what
    // the resolver put in scope, and the lexer is told nothing of it.
    var ctx = try lex("x: UInt8");
    defer ctx.deinit();
    try testing.expectEqualSlices(Tag, &.{ .identifier, .colon, .identifier, .eof }, ctx.tags());
}

test "an entry point lexes" {
    var ctx = try lex("fn main() -> UInt8 { 1 }");
    defer ctx.deinit();
    try testing.expectEqualSlices(Tag, &.{
        .keyword_fn, .identifier, .l_paren,     .r_paren, .arrow,
        .identifier, .l_brace,    .int_literal, .r_brace, .eof,
    }, ctx.tags());
}

test "default is a name the lexer does not reserve" {
    try testing.expectEqual(@as(?Tag, null), Tag.keywordFromLexeme("default"));
    var ctx = try lex("fn default() -> Self");
    defer ctx.deinit();
    try testing.expectEqual(Tag.identifier, ctx.tags()[1]);
}

test "lexes a let binding" {
    var ctx = try lex("let x = 42;");
    defer ctx.deinit();

    try testing.expectEqualSlices(Tag, &.{
        .keyword_let, .identifier, .equal, .int_literal, .semicolon, .eof,
    }, ctx.tags());
    try testing.expect(!ctx.sink.hasErrors());
}

test "comments are tokens, whitespace is not" {
    var ctx = try lex("let // note\nx");
    defer ctx.deinit();

    try testing.expectEqualSlices(Tag, &.{
        .keyword_let, .comment, .identifier, .eof,
    }, ctx.tags());

    try testing.expectEqualStrings("// note", ctx.spans()[1].slice(ctx.source.text));
}

test "a run of invalid bytes is one token and one diagnostic" {
    var ctx = try lex("let ### x");
    defer ctx.deinit();

    try testing.expectEqualSlices(Tag, &.{
        .keyword_let, .invalid, .identifier, .eof,
    }, ctx.tags());
    try testing.expectEqual(@as(usize, 1), ctx.sink.items().len);
    try testing.expectEqual(@as(u32, 1), ctx.sink.error_count);
}

test "lexing never fails on arbitrary bytes" {
    var ctx = try lex("\x00\xff\xfe~`?@let");
    defer ctx.deinit();

    try testing.expectEqual(Tag.eof, ctx.tags()[ctx.tags().len - 1]);
}

test "unterminated string reports and does not hang" {
    var ctx = try lex("\"abc");
    defer ctx.deinit();

    try testing.expectEqualSlices(Tag, &.{ .invalid, .eof }, ctx.tags());
    try testing.expectEqual(Code.s_string, ctx.sink.items()[0].code.?);
}

test "a raw literal is one string literal token" {
    var a = try lex("r\"{x}\\\" r#\"a \"b\" c\"# r##\"x\"#y\"##");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .string_literal, .string_literal, .string_literal, .eof }, a.tags());
    try testing.expectEqual(@as(usize, 0), a.sink.items().len);
}

test "an r is a name unless a quote follows it or its hashes" {
    var a = try lex("r r1 rr\"x\" r #\"x\" r#x");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{
        .identifier, .identifier, .identifier,     .string_literal,
        .identifier, .invalid,    .string_literal, .identifier,
        .invalid,    .identifier, .eof,
    }, a.tags());
}

test "a raw literal inside an interpolation is one token" {
    // The `}` in `r"}"` is text, so the interpolation closes at the brace
    // after it.
    var a = try lex("\"{r\"}\"}\"");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .str_open, .string_literal, .str_close, .eof }, a.tags());
}

test "a colon outside the value's groups begins its format spec" {
    var a = try lex("\"{x: *>+08.2? }\"");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .str_open, .identifier, .colon, .format_spec, .str_close, .eof }, a.tags());
    try testing.expectEqualStrings("*>+08.2?", a.spans()[3].slice(a.source.text));

    // Inside parentheses and brackets a colon names an argument or a bound.
    var b = try lex("\"{f(n: [a][0]):>4}\"");
    defer b.deinit();
    try testing.expectEqualSlices(Tag, &.{
        .str_open, .identifier, .l_paren, .identifier, .colon, .l_bracket, .identifier, .r_bracket, .l_bracket, .int_literal, .r_bracket, .r_paren, .colon, .format_spec, .str_close, .eof,
    }, b.tags());
}

test "a colon with nothing after it has no format spec" {
    var a = try lex("\"{x: }\"");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .str_open, .identifier, .colon, .str_close, .eof }, a.tags());
}

test "a format spec stops where the literal would end" {
    var a = try lex("\"{x:>4\nlet");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .str_open, .identifier, .colon, .format_spec, .keyword_let, .eof }, a.tags());
}

test "an interpolation left open at a line break ends with its literal" {
    // The colon annotates and the brace closes a block: neither belongs to
    // the literal on the line above.
    var a = try lex("\"{x\nlet y: T = 1 }");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{
        .str_open, .identifier, .keyword_let, .identifier, .colon, .identifier, .equal, .int_literal, .r_brace, .eof,
    }, a.tags());
}

test "a raw literal opens with at most eight hashes" {
    var a = try lex("r########\"a\"######## r#########\"b\"######### x");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .string_literal, .invalid, .identifier, .eof }, a.tags());
    try testing.expectEqual(@as(usize, 1), a.sink.items().len);
    try testing.expectEqual(Code.s_string, a.sink.items()[0].code.?);
}

test "an unterminated raw literal reports and stops at its line" {
    var a = try lex("r#\"a\" b\nlet");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .invalid, .keyword_let, .eof }, a.tags());
    try testing.expectEqual(@as(usize, 1), a.sink.items().len);
}

test "each line of a multi-line literal is one token running to its line end" {
    var a = try lex("let t =\n    \\\\a \"{b}\" // c\n    \\\\\n\\\\x\r\nlet");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{
        .keyword_let, .identifier,  .equal,       .string_line,
        .string_line, .string_line, .keyword_let, .eof,
    }, a.tags());
    const text = a.source.text;
    try testing.expectEqualStrings("\\\\a \"{b}\" // c", a.spans()[3].slice(text));
    try testing.expectEqualStrings("\\\\", a.spans()[4].slice(text));
    // The carriage return is part of the line break, not of the text.
    try testing.expectEqualStrings("\\\\x", a.spans()[5].slice(text));
    try testing.expectEqual(@as(usize, 0), a.sink.items().len);
}

test "a lone backslash begins no token" {
    var a = try lex("x \\ y\\");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .identifier, .invalid, .identifier, .invalid, .eof }, a.tags());
    try testing.expectEqual(@as(usize, 2), a.sink.items().len);
}

test "a lone backslash stays inside one invalid run" {
    var a = try lex("$\\$ $\\\\x");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .invalid, .invalid, .string_line, .eof }, a.tags());
    try testing.expectEqualStrings("$\\$", a.spans()[0].slice(a.source.text));
    try testing.expectEqual(@as(usize, 2), a.sink.items().len);
}

test "two backslashes inside an interpolation are refused and the literal still closes" {
    var a = try lex("\"a{\\\\x}\" y");
    defer a.deinit();
    try testing.expectEqualSlices(Tag, &.{ .str_open, .invalid, .identifier, .str_close, .identifier, .eof }, a.tags());
    try testing.expectEqual(@as(usize, 1), a.sink.items().len);
}

test "spans are contiguous and ordered" {
    var ctx = try lex("let x = 1; // c\nlet y = 2;");
    defer ctx.deinit();

    const s = ctx.spans();
    for (s[0 .. s.len - 1], s[1..]) |a, b| {
        try testing.expect(a.end <= b.start);
    }
}

test "token stream reconstructs the source exactly" {
    const text = "let x = 42; // note\n\nlet  y   =  x*2;\n";
    var ctx = try lex(text);
    defer ctx.deinit();

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();

    try token.reconstruct(ctx.tokens.slice().items(.span), text, &out.writer);
    try testing.expectEqualStrings(text, out.written());
}

test "a question mark is its own token" {
    // One character that never begins a longer operator, so it classifies
    // directly rather than through the path that looks at the byte after it.
    const text = "f()?";
    var ctx = try lex(text);
    defer ctx.deinit();

    const tags = ctx.tokens.slice().items(.tag);
    try testing.expectEqual(token.Tag.question, tags[3]);

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try token.reconstruct(ctx.tokens.slice().items(.span), text, &out.writer);
    try testing.expectEqualStrings(text, out.written());
}

test "eof token is empty and at the end" {
    const text = "let x";
    var ctx = try lex(text);
    defer ctx.deinit();

    const eof = ctx.spans()[ctx.spans().len - 1];
    try testing.expectEqual(@as(u32, text.len), eof.start);
    try testing.expectEqual(@as(u32, 0), eof.len());
}

test "only identifiers carry a name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "t.lin", .text = "let total = 1;" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    const slice = tokens.slice();
    const tags = slice.items(.tag);
    const names = slice.items(.name);

    for (tags, names) |tag, name| {
        if (tag == .identifier) {
            try testing.expect(name != .none);
        } else {
            // A reserved word is told from an identifier by its tag, so it
            // needs no handle and interning one would put `let` in the table.
            try testing.expectEqual(StringId.none, name);
        }
    }
    try testing.expectEqual(@as(u32, 1), interner.count());
}

test "two occurrences of a name share one handle" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The two `x` tokens are different slices of the source, which is exactly
    // what makes comparing them by bytes the thing worth avoiding.
    const source: Source = .{ .path = "t.lin", .text = "let x = 1; x" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    const slice = tokens.slice();
    var found: [2]StringId = .{ .none, .none };
    var seen: usize = 0;
    for (slice.items(.tag), slice.items(.name)) |tag, name| {
        if (tag != .identifier) continue;
        found[seen] = name;
        seen += 1;
    }

    try testing.expectEqual(@as(usize, 2), seen);
    try testing.expectEqual(found[0], found[1]);
    try testing.expectEqual(@as(u32, 1), interner.count());
}
