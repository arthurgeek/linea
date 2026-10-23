const std = @import("std");
const testing = std.testing;
const Span = @import("../support/span.zig").Span;
const name_case = @import("../support/name_case.zig");
const StringId = @import("../support/interner.zig").StringId;

/// Index into a `TokenList`. A distinct type rather than a bare `u32`, so that
/// a token index cannot be passed where a node index is expected.
pub const TokenId = enum(u32) {
    /// No token. Used where a node has an optional token, such as a binding
    /// with no type annotation, so the row stays a fixed width.
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: u32) TokenId {
        return @enumFromInt(i);
    }

    pub fn index(self: TokenId) u32 {
        return @intFromEnum(self);
    }
};

/// A half-open range of tokens `[start, end)`.
pub const TokenRange = struct {
    start: TokenId,
    end: TokenId,

    /// No tokens at all, for a node that has no such run.
    pub const empty: TokenRange = .{ .start = TokenId.at(0), .end = TokenId.at(0) };

    pub fn len(self: TokenRange) u32 {
        return self.end.index() - self.start.index();
    }
};

// Makes every test build compile the tests `Tag` holds, including a build
// filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Tag;
}

pub const Tag = enum(u8) {
    eof,
    /// A run of bytes that begins no valid token. Lexing has no error path, so
    /// malformed input carries this tag and the stream continues.
    invalid,
    /// Trivia. Retained so the token stream reconstructs the source exactly.
    comment,

    identifier,
    int_literal,
    float_literal,
    string_literal,
    /// Marks one line of a multi-line literal, which runs from its `\\` to
    /// the end of its line. The parser gathers consecutive lines into one
    /// literal, and each line stays a token of its own so that the stream
    /// breaks at every line, as the source does.
    string_line,
    /// The pieces an interpolated literal lexes as: `"a{` is `str_open`, `}b{`
    /// is `str_mid`, and `}c"` is `str_close`. The expression between them is
    /// ordinary tokens in this same stream, so the run still tiles the file and
    /// the stream still reconstructs it.
    str_open,
    str_mid,
    str_close,
    /// A format spec token holds the text after an interpolation's colon, up
    /// to the `}` that closes it: `>8.2` in `"{price:>8.2}"`. It is one token
    /// because its characters are a spec's parts rather than operators; the
    /// parser decides what they mean.
    format_spec,

    keyword_defer,
    keyword_let,
    keyword_var,
    keyword_fn,
    keyword_import,
    keyword_use,
    keyword_as,
    keyword_pub,
    keyword_internal,
    keyword_export,
    keyword_opaque,
    keyword_linear,
    keyword_copyable,
    keyword_carrier,
    keyword_test,
    keyword_trap,
    keyword_phantom,
    keyword_sink,
    keyword_copy,
    keyword_borrow,
    keyword_borrows,
    keyword_carries,
    keyword_retains,
    keyword_panic,
    keyword_embed,
    keyword_embed_bytes,
    keyword_template,
    keyword_derive,
    keyword_reflect,
    keyword_impl,
    keyword_trait,
    /// `extern`. A declaration that names a symbol the runtime provides
    /// rather than carrying a body of its own.
    keyword_extern,
    keyword_for,
    keyword_true,
    keyword_false,
    keyword_if,
    keyword_else,
    keyword_while,
    keyword_loop,
    keyword_break,
    keyword_continue,
    keyword_read,
    keyword_inout,
    keyword_return,
    keyword_enum,
    keyword_struct,
    keyword_match,
    /// `where`, opening a refinement or declaration constraint clause.
    /// Reserved rather than contextual, unlike `type`: a clause may sit on its
    /// own line, and a word a statement could begin would leave the
    /// continuation ambiguous.
    keyword_where,
    /// `in`, inside a refinement clause: `where it in lo..=hi`.
    keyword_in,

    ampersand,
    /// `&&` and `||`. A single `&` marks an argument the callee writes back
    /// through; a single `|` delimits lambda parameters.
    ampersand_ampersand,
    pipe,
    pipe_pipe,
    /// `!`, which negates a `Bool`. Only ever prefix.
    bang,
    equal,
    // Comparison. Non-associative and looser than arithmetic, so a chain is a
    // syntax error rather than a comparison against a `Bool`.
    equal_equal,
    bang_equal,
    less,
    less_equal,
    greater,
    greater_equal,
    plus,
    minus,
    star,
    slash,
    /// `%`. The remainder of a truncating division, so `a % b` is
    /// `a - (a / b) * b` and its sign follows the dividend.
    percent,
    /// `+=`, `-=`, `*=` and `/=`. An operator and an equals, which update a
    /// place through itself rather than naming it twice.
    plus_equal,
    minus_equal,
    star_equal,
    slash_equal,
    percent_equal,
    arrow,
    fat_arrow,
    colon,
    dot,
    /// `..` and `..=`. A range's two ends, non-associative and looser than
    /// every operator that computes a value.
    dot_dot,
    dot_dot_equal,
    /// `?`, postfix. Early return over `Option` and `Result`.
    question,
    /// `^`, prefix, and only where an index is written. It counts back from a
    /// container's end, which is a value the container interprets rather than
    /// an operation on the number after it.
    caret,
    /// `@`, introducing a closed declaration attribute.
    at_sign,

    l_paren,
    r_paren,
    l_brace,
    r_brace,
    /// `[` and `]`. A type argument list, and an index once arrays exist --
    /// one shape, and which it is depends on what the head names.
    l_bracket,
    r_bracket,
    comma,
    semicolon,

    pub fn isTrivia(self: Tag) bool {
        return self == .comment;
    }

    /// How this token changes bracket depth: 1 opens, -1 closes, 0 neither.
    ///
    /// The one place delimiter pairs are enumerated. Three separate scanners
    /// used to spell this out with an `else` that meant "not a bracket", so a
    /// delimiter added to the language would have been miscounted by all three
    /// without any of them failing to compile.
    pub fn nesting(self: Tag) i2 {
        return switch (self) {
            .l_paren, .l_brace, .l_bracket => 1,
            .r_paren, .r_brace, .r_bracket => -1,
            else => 0,
        };
    }

    comptime {
        // What makes the `else` above safe: every tag whose name reads like a
        // delimiter must be accounted for. A `l_bracket` added for indexing
        // fails here rather than silently counting as "not a bracket".
        for (@typeInfo(Tag).@"enum".fields) |f| {
            const tag: Tag = @enumFromInt(f.value);
            const opens = f.name.len > 2 and f.name[0] == 'l' and f.name[1] == '_';
            const closes = f.name.len > 2 and f.name[0] == 'r' and f.name[1] == '_';
            if (opens and tag.nesting() != 1) {
                @compileError("delimiter " ++ f.name ++ " is not counted as opening one");
            }
            if (closes and tag.nesting() != -1) {
                @compileError("delimiter " ++ f.name ++ " is not counted as closing one");
            }
        }
    }

    /// Whether a line opening with this token, followed by `next` spelled
    /// `next_text`, continues the expression on the line above rather than
    /// beginning a statement: a `.` before a lowercase name, which selects an
    /// operation or a field of the value above. An operation and a field start
    /// with a lowercase letter, and no statement does, so such a line can mean
    /// nothing else: `numbers` / `.filter(p)` / `.fold(0, add)` is one chain.
    /// A `.` before a capitalised name or `{` names a variant or builds a
    /// literal, and begins a statement. A name with no case, `._1`, could be
    /// either, and begins a statement.
    ///
    /// The parser reads this to decide where a statement ends, and the
    /// formatter to keep a chain the author broke across lines as one; the two
    /// must agree, so the rule is here rather than in either of them.
    pub fn continuesTheLine(self: Tag, next: Tag, next_text: []const u8) bool {
        return self == .dot and next == .identifier and name_case.of(next_text) == .lower;
    }

    test continuesTheLine {
        try std.testing.expect(Tag.dot.continuesTheLine(.identifier, "map"));
        try std.testing.expect(Tag.dot.continuesTheLine(.identifier, "_first"));
        try std.testing.expect(!Tag.dot.continuesTheLine(.identifier, "_1"));
        try std.testing.expect(!Tag.dot.continuesTheLine(.identifier, "Ok"));
        try std.testing.expect(!Tag.dot.continuesTheLine(.l_brace, "{"));
        try std.testing.expect(!Tag.minus.continuesTheLine(.identifier, "x"));
    }

    /// Whether a line opening with this token, followed by `next` spelled
    /// `next_text`, could continue an expression as well as begin a
    /// statement.
    ///
    /// A newline before such a line decides between two readings that are
    /// both programs, which is what `[S-Continuation]` notes and what stops
    /// the formatter deleting the `;` that answers it. Those two live in
    /// different passes and must agree, so the rule is here rather than in
    /// either of them: a line one noted and the other did not would delete a
    /// separator the parser is still noting, and put the note back on every
    /// save.
    ///
    /// `-` always could. `(` could too, and is among them only before `)`. A
    /// function returning a tuple ends `let hi = ...` and then `(lo, hi)`, so
    /// noting every `(` would follow every such tail, while a call split
    /// before an argument that is not Unit leaves a value nothing uses, which
    /// `[T-Discard]` refuses. A call split before `()` leaves the unit value
    /// standing alone, which nothing refuses, and `let _ = launch` followed
    /// by `()` would compile without ever calling `launch`; no tail opens
    /// with `()`. `.` could only before a name that is not capitalised: `.Ok(0)` names a variant or a type's member, and `.{`
    /// builds a literal, and neither continues the line above. Within a body
    /// a line opening with `.` and a lowercase name does continue it
    /// (`continuesTheLine`), so the parser notes one only where the statement
    /// above ended anyway -- after a declaration's path, or after an
    /// expression ending in a block, which takes no selection -- and the
    /// formatter keeps a `;` written before one.
    /// `{` is not among them: a named literal keeps its brace on the
    /// head's line, so a brace after a newline starts a block.
    pub fn opensAContinuation(self: Tag, next: Tag, next_text: []const u8) bool {
        return switch (self) {
            .minus => true,
            .l_paren => next == .r_paren,
            .dot => switch (next) {
                .l_brace => false,
                .identifier => name_case.of(next_text) != .capital,
                else => true,
            },
            else => false,
        };
    }

    test opensAContinuation {
        try std.testing.expect(Tag.minus.opensAContinuation(.int_literal, "1"));
        try std.testing.expect(!Tag.l_paren.opensAContinuation(.identifier, "o"));
        try std.testing.expect(!Tag.l_paren.opensAContinuation(.l_paren, "("));
        try std.testing.expect(Tag.l_paren.opensAContinuation(.r_paren, ")"));
        try std.testing.expect(Tag.dot.opensAContinuation(.identifier, "map"));
        try std.testing.expect(Tag.dot.opensAContinuation(.identifier, "_"));
        try std.testing.expect(!Tag.dot.opensAContinuation(.identifier, "Ok"));
        try std.testing.expect(!Tag.dot.opensAContinuation(.l_brace, "{"));
        try std.testing.expect(!Tag.l_brace.opensAContinuation(.identifier, "x"));
    }

    /// Human-readable name for diagnostics.
    pub fn describe(self: Tag) []const u8 {
        return switch (self) {
            .eof => "end of file",
            .invalid => "invalid token",
            .comment => "comment",
            .identifier => "identifier",
            .int_literal => "integer literal",
            .float_literal => "float literal",
            .string_literal => "string literal",
            .string_line => "a line of a multi-line string literal",
            .str_open => "the start of an interpolated literal",
            .str_mid => "the middle of an interpolated literal",
            .str_close => "the end of an interpolated literal",
            .format_spec => "a format spec",
            .equal_equal => "`==`",
            .bang_equal => "`!=`",
            .less => "`<`",
            .less_equal => "`<=`",
            .greater => "`>`",
            .greater_equal => "`>=`",
            .ampersand => "`&`",
            .ampersand_ampersand => "`&&`",
            .pipe => "`|`",
            .pipe_pipe => "`||`",
            .bang => "`!`",
            .equal => "`=`",
            .plus => "`+`",
            .minus => "`-`",
            .star => "`*`",
            .slash => "`/`",
            .percent => "`%`",
            .plus_equal => "`+=`",
            .minus_equal => "`-=`",
            .star_equal => "`*=`",
            .slash_equal => "`/=`",
            .percent_equal => "`%=`",
            .arrow => "`->`",
            .fat_arrow => "`=>`",
            .colon => "`:`",
            .dot => "`.`",
            .dot_dot => "`..`",
            .dot_dot_equal => "`..=`",
            .question => "`?`",
            .caret => "`^`",
            .at_sign => "`@`",
            .l_paren => "`(`",
            .r_paren => "`)`",
            .l_brace => "`{`",
            .r_brace => "`}`",
            .l_bracket => "`[`",
            .r_bracket => "`]`",
            .comma => "`,`",
            .semicolon => "`;`",
            // Every reserved word, spelled from the tag that names it. A tag
            // reaching here that names no keyword fails the build, which is
            // what keeps this arm from standing for "described somehow".
            inline else => |t| t.spelledKeyword(),
        };
    }

    /// How a reserved word is written, read off the tag that names it.
    ///
    /// The one statement of a keyword's spelling: `keyword_let` is `let`, and
    /// a lexer that reads the word, a diagnostic that quotes it and a grammar
    /// that lists it all reach it here rather than each holding a copy.
    fn spelledKeyword(comptime self: Tag) []const u8 {
        const named = @tagName(self);
        if (comptime !std.mem.startsWith(u8, named, keyword_prefix)) {
            @compileError("token `" ++ named ++ "` is neither a keyword nor described");
        }
        return "`" ++ named[keyword_prefix.len..] ++ "`";
    }

    pub fn keywordFromLexeme(lexeme: []const u8) ?Tag {
        return reserved_words.get(lexeme);
    }
};

/// The words the parser reads as keywords only where a position says so.
///
/// `type` begins a member of a trait or of an implementation, and is an
/// ordinary name everywhere else: reserving it would cost every program that
/// wanted the noun for a binding. It is still a word an editor colours and a
/// grammar spells, so it is written down here -- the parity gates read this
/// list beside the reserved one, and a word in neither is a word no gate
/// covers, which is what this one was.
pub const contextual_words = struct {
    /// `type Item` in a trait, and `type Item = UInt8` in an implementation.
    pub const declared_type = "type";

    /// `proj at(...) -> Elem` in a trait, and the same with a body in an
    /// implementation of it. A member position and nowhere else, for the reason
    /// `type` is: a projection is rare and the noun is not.
    pub const projection = "proj";

    /// `trav positions = 0..4` in an inherent implementation: the positions a
    /// lending walk runs through. A member position and nowhere else, for the
    /// reason `proj` is.
    pub const traversal = "trav";

    /// `where it in lo..=hi`. A refinement's own spelling of the value the
    /// clause is about, and the only one it accepts -- so a reader sees a
    /// keyword there, whatever the lexer's table holds.
    pub const refinement_value = "it";

    /// A stored-field target on an implementation or traversal.
    pub const delegation = "via";

    /// `default impl[T: Bound] Trait for T`, a fallback implementation. Only
    /// before `impl` at the start of a declaration, so a trait may still
    /// declare an operation named `default`.
    pub const default_implementation = "default";

    /// `alias Name = Type` at the top of a file: another name for a type that
    /// already exists. Only where a declaration begins and a name follows, so
    /// a program may still bind `alias` as a value.
    pub const type_alias = "alias";

    /// Every one of them, for a gate that must cover each.
    pub const all = [_][]const u8{ declared_type, projection, traversal, refinement_value, delegation, default_implementation, type_alias };
};

/// What every tag naming a reserved word is named with.
const keyword_prefix = "keyword_";

/// How many of `Tag`'s tags name a reserved word.
const keyword_count = blk: {
    var found: usize = 0;
    for (@typeInfo(Tag).@"enum".fields) |f| {
        if (std.mem.startsWith(u8, f.name, keyword_prefix)) found += 1;
    }
    break :blk found;
};

/// The reserved words, derived from the tags that name them.
///
/// A word is its tag's name without the prefix, so declaring `keyword_yield`
/// is the whole of adding one: nothing else states the spelling, and there is
/// no second list to fall out of step. A table written beside the tags could
/// omit an entry and compile, and the word would lex as an identifier for as
/// long as nobody wrote a program using it.
///
/// A primitive type is not among them: `UInt8` is a name the resolver puts in
/// every scope, so it lexes as an identifier and a conversion is a call.
///
/// Public because the editor grammars are checked against it: a gate that
/// enumerates this cannot fall out of step with the lexer the way one matching
/// a pattern over this file could, since a pattern that stops matching reports
/// success.
pub const reserved_words = std.StaticStringMap(Tag).initComptime(blk: {
    var pairs: [keyword_count]struct { []const u8, Tag } = undefined;
    var next: usize = 0;
    for (@typeInfo(Tag).@"enum".fields) |f| {
        if (!std.mem.startsWith(u8, f.name, keyword_prefix)) continue;
        pairs[next] = .{ f.name[keyword_prefix.len..], @field(Tag, f.name) };
        next += 1;
    }
    break :blk pairs;
});

/// Three dense columns once stored in a `TokenList`. The lexeme is derived,
/// not stored: it is `span.slice(source.text)`.
///
/// `name` is the exception to that rule, and is derivable in the same way. It
/// is stored because deriving it costs a hash of the bytes, and the point of a
/// handle is to pay that once per occurrence rather than once per comparison.
/// A column the parser's tag loop never reads costs that loop nothing.
pub const Token = struct {
    tag: Tag,
    span: Span,
    /// The interned identifier, or `.none` for every token that is not one.
    /// Reserved words are not identifiers: they are told apart by tag.
    name: StringId = .none,
};

pub const TokenList = std.MultiArrayList(Token);

/// Writes the source back out from its tokens.
///
/// Comments are tokens and whitespace is the gap between adjacent spans, so
/// emitting each gap followed by its token reproduces the input byte for byte.
/// The conformance suite asserts that; a formatter rewriting one region and
/// copying the rest depends on it.
pub fn reconstruct(
    spans: []const Span,
    source: []const u8,
    w: *std.Io.Writer,
) std.Io.Writer.Error!void {
    var prev_end: u32 = 0;
    for (spans) |s| {
        try w.writeAll(source[prev_end..s.start]);
        try w.writeAll(s.slice(source));
        prev_end = s.end;
    }
    try w.writeAll(source[prev_end..]);
}

test "TokenId round-trips through its index" {
    const id = TokenId.at(7);
    try testing.expectEqual(@as(u32, 7), id.index());
}

test "TokenRange is half-open" {
    const r: TokenRange = .{ .start = TokenId.at(2), .end = TokenId.at(5) };
    try testing.expectEqual(@as(u32, 3), r.len());
}

test "every reserved word resolves to the tag it is listed under" {
    // The editor grammars are checked against this table rather than against a
    // pattern matched over this file, so it has to be public and every entry
    // has to resolve. No count is asserted: the parity gates prove the set is
    // covered, and a number here would fail as noise the day a word is added.
    try testing.expect(reserved_words.keys().len > 0);
    for (reserved_words.keys(), reserved_words.values()) |word, tag| {
        try testing.expectEqual(tag, Tag.keywordFromLexeme(word).?);
    }
}

test "every tag naming a keyword lexes and describes as that word" {
    // The tags are what the table is built from, and these are its two
    // readers: a word the lexer does not recognise, or one a diagnostic
    // quotes as some other word, is a keyword the derivation did not reach.
    inline for (@typeInfo(Tag).@"enum".fields) |f| {
        if (comptime !std.mem.startsWith(u8, f.name, keyword_prefix)) continue;
        const tag: Tag = @field(Tag, f.name);
        const word = f.name[keyword_prefix.len..];
        try testing.expectEqual(tag, Tag.keywordFromLexeme(word).?);
        try testing.expectEqualStrings("`" ++ word ++ "`", tag.describe());
    }
}

test "only comments are trivia" {
    try testing.expect(Tag.comment.isTrivia());
    try testing.expect(!Tag.identifier.isTrivia());
    try testing.expect(!Tag.eof.isTrivia());
    try testing.expect(!Tag.invalid.isTrivia());
}

test "a primitive type name is not a reserved word" {
    try testing.expectEqual(Tag.keyword_fn, Tag.keywordFromLexeme("fn").?);
    try testing.expect(Tag.keywordFromLexeme("UInt8") == null);
    try testing.expect(Tag.keywordFromLexeme("Int64") == null);
    try testing.expect(Tag.keywordFromLexeme("Bool") == null);
}

test "keyword lookup recognises let and rejects others" {
    try testing.expectEqual(Tag.keyword_let, Tag.keywordFromLexeme("let").?);
    try testing.expect(Tag.keywordFromLexeme("lets") == null);
    try testing.expect(Tag.keywordFromLexeme("x") == null);
}

test "TokenList stores tags and spans in separate columns" {
    var list: TokenList = .empty;
    defer list.deinit(testing.allocator);

    try list.append(testing.allocator, .{ .tag = .keyword_let, .span = .{ .start = 0, .end = 3 } });
    try list.append(testing.allocator, .{ .tag = .identifier, .span = .{ .start = 4, .end = 5 } });

    const slice = list.slice();
    try testing.expectEqual(Tag.keyword_let, slice.items(.tag)[0]);
    try testing.expectEqual(@as(u32, 5), slice.items(.span)[1].end);
}

/// The grammar block of `docs/linea-semantics.md`, which is the one the
/// document writes out rather than the prose around it.
///
/// Found by its first production rather than by counting fences, so a fenced
/// example added above it does not silently move which block is read.
fn writtenGrammar() []const u8 {
    const semantics = @embedFile("semantics");
    const from = std.mem.indexOf(u8, semantics, "file         ::=") orelse return "";
    const rest = semantics[from..];
    const to = std.mem.indexOf(u8, rest, "\n```") orelse return rest;
    return rest[0..to];
}

test "every reserved word is spelled in the written grammar" {
    // A word the lexer reserves and the grammar never spells is a word a
    // program may not use for a name and the document never says why. Held in
    // this direction only: the grammar spells `_`, which is a pattern and not a
    // word anything reserves.
    //
    // The editor grammars are already held to this table, and the document was
    // not -- so `trait` and `for` reached the lexer, both editor grammars and
    // the compiler while the grammar here still described a language without
    // them.
    const grammar = writtenGrammar();
    try testing.expect(grammar.len > 0);

    var missing: usize = 0;
    for (reserved_words.keys()) |word| {
        var buf: [32]u8 = undefined;
        const quoted = try std.fmt.bufPrint(&buf, "\"{s}\"", .{word});
        if (std.mem.indexOf(u8, grammar, quoted) != null) continue;
        std.debug.print("`{s}` is reserved and the written grammar never spells it\n", .{word});
        missing += 1;
    }
    if (missing > 0) return error.GrammarIsBehindTheLexer;
}

test "every comma-separated list in the written grammar admits a trailing comma" {
    // The trailing comma is the explode marker: writing one is how a
    // programmer tells the formatter to break a list one element per line, and
    // the formatter honours it in every list the parser accepts one in. So a
    // production spelling `("," X)*` and not `","?` describes a language whose
    // own corpus it cannot derive -- four of them did, and eight files under
    // `tests/` were underivable from the document that defines them.
    //
    // Structural rather than a substring search: it reads the shape of each
    // production, which is what the two gates beside it do not do.
    const grammar = writtenGrammar();
    try testing.expect(grammar.len > 0);

    var bad: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, grammar, at, "(\",\"")) |found| {
        // Past the `("," X)*` group: the repetition closes with `)*`, and what
        // follows it either admits the trailing comma or does not.
        const close = std.mem.indexOfPos(u8, grammar, found, ")*") orelse break;
        at = close + 2;
        const rest = grammar[at..];
        if (std.mem.startsWith(u8, rest, " \",\"?")) continue;

        // The line it sits on, for a message that names the production.
        const line_start = if (std.mem.lastIndexOfScalar(u8, grammar[0..found], '\n')) |n| n + 1 else 0;
        const line_end = std.mem.indexOfScalarPos(u8, grammar, found, '\n') orelse grammar.len;
        std.debug.print(
            "a comma-separated list admits no trailing comma: {s}\n",
            .{grammar[line_start..line_end]},
        );
        bad += 1;
    }
    if (bad > 0) return error.GrammarCannotDeriveTheCorpus;
}

test "the written grammar spells no statement terminator" {
    // The document says so a few lines below it: what separates two statements
    // is the line break, and `;` separates two that share a line. The one in an
    // array type separates its element type from its length instead. Any other
    // production spelling one contradicts the paragraph explaining it, and a
    // reader following the grammar writes a separator the formatter then
    // deletes.
    const grammar = writtenGrammar();
    try testing.expect(grammar.len > 0);

    var lines = std.mem.splitScalar(u8, grammar, '\n');
    while (lines.next()) |line| {
        const at = std.mem.indexOf(u8, line, "\";\"") orelse continue;
        const defines = std.mem.indexOf(u8, line, "::=") orelse 0;
        const production = std.mem.trim(u8, line[0..defines], " ");
        if (std.mem.eql(u8, production, "array_type") and
            std.mem.indexOf(u8, line[at + 3 ..], "\";\"") == null)
        {
            continue;
        }
        std.debug.print("a production spells a statement terminator: {s}\n", .{line});
        return error.GrammarSpellsATerminator;
    }
}
