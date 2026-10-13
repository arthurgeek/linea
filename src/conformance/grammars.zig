//! The editor grammars, checked against the compiler.
//!
//! A grammar is easy to write and easy to forget: a reserved word added to the
//! lexer leaves the grammar wrong, and nothing notices, because wrong
//! highlighting is not an error -- it is a word that quietly stopped being
//! coloured. These turn that silence into a failing build.
//!
//! The reserved-word table is imported rather than matched over. A gate that
//! searched `token.zig` for a pattern would report success the day the pattern
//! stopped matching, which is the failure being guarded against rather than a
//! detail of how it is guarded.

const std = @import("std");
const testing = std.testing;

const token = @import("../lexer/token.zig");
const lexer = @import("../lexer/lexer.zig");
const TypeId = @import("../sema/types.zig").TypeId;

/// The generated grammar, emitted into the build cache by a `tree-sitter
/// generate` step. Read rather than committed, so the gate cannot be checking a
/// file nobody regenerated.
const grammar_json = @embedFile("grammar_json");
const highlights = @embedFile("highlights_scm");
const sublime = @embedFile("sublime_syntax");

/// Query text with comment lines removed.
///
/// A gate a comment can satisfy is a gate that eventually will be: without
/// this, `; "fn" is captured below` counts as capturing `fn`.
fn withoutComments(
    gpa: std.mem.Allocator,
    text: []const u8,
    comment: u8,
) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        const code = if (std.mem.indexOfScalar(u8, line, comment)) |at| line[0..at] else line;
        try out.appendSlice(gpa, code);
        try out.append(gpa, '\n');
    }
    return out.toOwnedSlice(gpa);
}

fn quoted(buf: []u8, word: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "\"{s}\"", .{word});
}

/// Every word an editor grammar has to spell: the reserved ones, and the ones
/// the parser reads as a keyword where a position says so.
///
/// Both, because an editor colours what a reader sees rather than what the
/// lexer's table holds. A contextual word left out of this is a word no gate
/// below covers, which is how `type` came to be spelled three ways.
const every_word: []const []const u8 = token.reserved_words.keys() ++ token.contextual_words.all;

test "every reserved word is a terminal in the tree-sitter grammar" {
    for (every_word) |word| {
        var buf: [64]u8 = undefined;
        if (std.mem.indexOf(u8, grammar_json, try quoted(&buf, word)) == null) {
            std.debug.print("reserved word missing from grammar.js: {s}\n", .{word});
            return error.MissingFromTreeSitterGrammar;
        }
    }
}

test "callable editor nodes reuse the parameter concept" {
    try testing.expect(std.mem.indexOf(u8, grammar_json, "\"callable_type\"") != null);
    try testing.expect(std.mem.indexOf(u8, grammar_json, "\"lambda_expression\"") != null);
    try testing.expect(std.mem.indexOf(u8, grammar_json, "\"parameter\"") != null);
    try testing.expect(std.mem.indexOf(u8, grammar_json, "\"lambda_parameter\"") == null);
}

test "every reserved word has a highlight capture" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const code = try withoutComments(arena.allocator(), highlights, ';');
    const grammar = try std.json.parseFromSlice(std.json.Value, arena.allocator(), grammar_json, .{});
    defer grammar.deinit();

    words: for (every_word) |word| {
        var buf: [64]u8 = undefined;
        if (std.mem.indexOf(u8, code, try quoted(&buf, word)) != null) continue;
        // A string-only rule is a named leaf, not an anonymous word token.
        var rules = grammar.value.object.get("rules").?.object.iterator();
        while (rules.next()) |entry| {
            const rule = entry.value_ptr.object;
            if (!std.mem.eql(u8, rule.get("type").?.string, "STRING")) continue;
            if (!std.mem.eql(u8, rule.get("value").?.string, word)) continue;
            const node = try std.fmt.bufPrint(&buf, "({s})", .{entry.key_ptr.*});
            if (std.mem.indexOf(u8, code, node) != null) continue :words;
        }
        std.debug.print("reserved word has no highlight capture: {s}\n", .{word});
        return error.MissingHighlight;
    }
}

/// Whether a grammar's text spells a word as a member of an alternation.
///
/// Anchored to an alternation group rather than searched for anywhere, so an
/// incidental substring in a scope name cannot mask a short word like `as` or
/// `if` -- `storage.type.linea` contains neither, but a looser check over a
/// file full of scope names would find almost anything.
///
/// One routine over both grammars, because both spell a set of words the same
/// way: a Sublime `match` and a tree-sitter `#match?` are each a regex with an
/// alternation in it, and a second reader would be a second answer to what
/// "the grammar spells this word" means.
fn inAlternation(code: []const u8, word: []const u8) !bool {
    var buf: [64]u8 = undefined;
    const opens = try std.fmt.bufPrint(&buf, "({s}|", .{word});
    if (std.mem.indexOf(u8, code, opens) != null) return true;

    var buf2: [64]u8 = undefined;
    const middle = try std.fmt.bufPrint(&buf2, "|{s}|", .{word});
    if (std.mem.indexOf(u8, code, middle) != null) return true;

    var buf3: [64]u8 = undefined;
    const closes = try std.fmt.bufPrint(&buf3, "|{s})", .{word});
    if (std.mem.indexOf(u8, code, closes) != null) return true;

    var buf4: [64]u8 = undefined;
    const alone = try std.fmt.bufPrint(&buf4, "({s})", .{word});
    return std.mem.indexOf(u8, code, alone) != null;
}

test "the Sublime grammar enters code inside an interpolation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const code = try withoutComments(arena.allocator(), sublime, '#');

    try testing.expect(std.mem.indexOf(u8, code, "- match: '\\{\\{'") != null);
    try testing.expect(std.mem.indexOf(u8, code, "push: interpolation") != null);
    try testing.expect(std.mem.indexOf(u8, code, "- clear_scopes: 1") != null);
    try testing.expect(std.mem.indexOf(u8, code, "- match: '(:)(\\s*)([^}\"\\n]+)'") != null);
    try testing.expect(std.mem.indexOf(u8, code, "- include: main") != null);
}

test "every grammar bounds a raw literal's hashes where the lexer does" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const bound = lexer.max_raw_hashes;

    // Sublime opens a raw literal on at most `bound` hashes and closes it on
    // the same count through a back-reference. Read without stripping
    // comments: the pattern itself holds a `#`, and a comment line holds no
    // `- match:`.
    const opens = try std.fmt.allocPrint(gpa, "- match: '\\br(#{{0,{d}}})\"'", .{bound});
    try testing.expect(std.mem.indexOf(u8, sublime, opens) != null);
    try testing.expect(std.mem.indexOf(u8, sublime, "- match: '\"\\1'") != null);

    // tree-sitter spells one expression per count, so the largest it spells
    // is the bound and the next one is absent.
    const most = try std.fmt.allocPrint(gpa, "r#{{{d}}}\\\"", .{bound});
    const beyond = try std.fmt.allocPrint(gpa, "r#{{{d}}}\\\"", .{bound + 1});
    try testing.expect(std.mem.indexOf(u8, grammar_json, most) != null);
    try testing.expect(std.mem.indexOf(u8, grammar_json, beyond) == null);
}

test "every grammar reads a multi-line literal's line from its `\\\\` to the end of the line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // tree-sitter must read the line as one token: the two backslashes, then
    // any bytes up to a line break, as the lexer's `string_line` does.
    const grammar = try std.json.parseFromSlice(std.json.Value, arena.allocator(), grammar_json, .{});
    const rule = grammar.value.object.get("rules").?.object.get("_string_line") orelse return error.NoStringLineRule;
    try testing.expectEqualStrings("TOKEN", rule.object.get("type").?.string);
    const members = rule.object.get("content").?.object.get("members").?.array.items;
    try testing.expectEqual(@as(usize, 2), members.len);
    try testing.expectEqualStrings("\\\\", members[0].object.get("value").?.string);
    try testing.expectEqualStrings("[^\\n]*", members[1].object.get("value").?.string);

    // Sublime must match the same line to its end.
    try testing.expect(std.mem.indexOf(u8, sublime, "- match: '(\\\\\\\\).*$'") != null);
}

test "every reserved word appears in the Sublime syntax" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const code = try withoutComments(arena.allocator(), sublime, '#');

    for (every_word) |word| {
        if (!try inAlternation(code, word)) {
            std.debug.print("reserved word missing from the Sublime syntax: {s}\n", .{word});
            return error.MissingFromSublimeSyntax;
        }
    }
}

/// The lines of a grammar that say what a builtin type is spelled.
///
/// A scope on one line and the pattern it scopes on another is how both files
/// are written, so what is collected is the pattern beside every line naming
/// the builtin-type scope -- the alternation itself, and nothing else in a
/// file that is mostly scope names. Narrowed to that pattern rather than run
/// over the whole file, because a type name written anywhere else in either
/// grammar would satisfy a looser check while colouring nothing.
fn builtinTypeMatches(
    gpa: std.mem.Allocator,
    text: []const u8,
    scope: []const u8,
) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var previous: []const u8 = "";
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, scope) != null) {
            try out.appendSlice(gpa, previous);
            try out.append(gpa, '\n');
            try out.appendSlice(gpa, line);
            try out.append(gpa, '\n');
        }
        previous = line;
    }
    return out.toOwnedSlice(gpa);
}

test "every primitive the compiler names is a builtin type in both grammars" {
    // The names come off `TypeId.primitives`, spelled by the `nameOf` the
    // resolver seeds its bindings with. A grammar's list of primitives is
    // otherwise a copy of the compiler's, and a copy drifts silently in the
    // one direction nothing can report: `Float64` landed, neither grammar
    // gained it, and a reader saw a plain identifier where every other
    // primitive was coloured.
    //
    // Both grammars in one gate, for the reason the reserved words are held to
    // both: a primitive coloured by one highlighter and not the other is the
    // same drift with one more place to hide.
    //
    // A spelling gate, and only that. It says every primitive is written in the
    // pattern; it cannot say the pattern paints anything, because a query is
    // matched in order and a narrower rule written above the general one it
    // refines is overwritten by it. What the tree-sitter side actually paints
    // is asserted by the highlight fixture the build runs `tree-sitter test`
    // over.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const sublime_code = try withoutComments(gpa, sublime, '#');
    const in_sublime = try builtinTypeMatches(gpa, sublime_code, "storage.type.builtin.linea");

    // A capture and the predicate narrowing it are two lines of one pattern,
    // and the capture is named on both -- so the pattern is what sits beside
    // itself here, which is what this needs.
    const highlight_code = try withoutComments(gpa, highlights, ';');
    const in_highlights = try builtinTypeMatches(gpa, highlight_code, "@type.builtin");

    for (TypeId.primitives) |t| {
        const name = t.nameOf();
        if (!try inAlternation(in_sublime, name)) {
            std.debug.print("primitive missing from the Sublime syntax: {s}\n", .{name});
            return error.MissingFromSublimeSyntax;
        }
        if (!try inAlternation(in_highlights, name)) {
            std.debug.print("primitive has no builtin-type highlight: {s}\n", .{name});
            return error.MissingHighlight;
        }
    }
}

test "the two grammars carry the same reserved words" {
    // Lexical parity, and only lexical. It says nothing about the two engines
    // having equivalent capabilities and cannot: syntect matches regexes in a
    // context stack and tree-sitter builds a tree, so each will always express
    // something the other cannot. The words are what a reader loses when they
    // drift, and the words are what is checked.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const code = try withoutComments(arena.allocator(), sublime, '#');

    for (every_word) |word| {
        var buf: [64]u8 = undefined;
        const in_ts = std.mem.indexOf(u8, grammar_json, try quoted(&buf, word)) != null;
        if (in_ts != try inAlternation(code, word)) {
            std.debug.print("grammars disagree about: {s}\n", .{word});
            return error.GrammarsDisagree;
        }
    }
}
