const std = @import("std");
const testing = std.testing;

const source_mod = @import("../support/source.zig");
const Source = source_mod.Source;
const Span = @import("../support/span.zig").Span;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const TokenId = @import("../lexer/token.zig").TokenId;
const parse = @import("../parser/parser.zig").parse;
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const resolve = @import("../sema/resolve.zig");
const Reach = resolve.Reach;

/// What kind of thing a name a module exports stands for.
///
/// The parser's answer and not a second one: which form was written is settled
/// when the file is read, and a classification that looked at the name or at
/// what it holds would be a second parser agreeing on every file anyone tried.
///
/// Exhaustive, with no `else`, so a declaration form added to the language is
/// classified before the build succeeds.
pub const Kind = enum {
    function,
    constant,
    enum_,
    struct_,
    trait_,
    /// A `pub use`, which names a declaration in another module. What kind of
    /// thing that declaration is takes resolution to say, and this is built
    /// without it -- so the honest answer about a re-export is that it is one.
    re_export,
    /// A distinct nominal type over one base, `type Name = Base`.
    newtype,
    /// Another name for a written type, `alias Name = Type`.
    alias,
};

/// One name a module exports, as the file that wrote it spells it.
///
/// Owned by the caller: the strings are copied out of the source, because the
/// text a file was read from is released once it has been parsed and an entry
/// outlives it by design.
pub const Export = struct {
    name: []const u8,
    kind: Kind,
    reach: Reach,
    /// The declaration's own text up to what it holds. Nothing here was
    /// inferred -- it is a run of the source, so an entry can make no claim the
    /// program decides.
    header: []const u8,
};

/// Which declaration forms name something another module can reach.
///
/// `impl` declares no name of its own -- it groups what a type can do, and
/// each of its members is reached through the type rather than through an
/// `import`. An `import` binds a module inside the file that wrote it and
/// carries nothing onward. A declaration the parser gave up on has no name to
/// offer.
///
/// Exhaustive, with no `else`: a declaration form added to the language is
/// classified before the build succeeds.
fn kindOf(tag: node.Decl.Tag) ?Kind {
    return switch (tag) {
        .function => .function,
        .constant => .constant,
        .enum_ => .enum_,
        .struct_ => .struct_,
        .trait_ => .trait_,
        .use_ => .re_export,
        .newtype => .newtype,
        .alias => .alias,
        // A type a trait declares is reached through the trait rather than
        // through the module holding it, so there is nothing here for another
        // module to import. A projection is the same: it is a trait's member,
        // and a bracket reaches it through the trait. A traversal is reached by
        // a walk over the type and never by name.
        .impl_, .template_impl, .derive_impl, .import_, .associated_type, .projection, .traversal_, .err => null,
    };
}

/// The declaration's text up to what it holds.
///
/// Bounded by the first `{` or `=` inside the declaration, whichever comes
/// first: those are the two ways a declaration opens onto what it contains --
/// a function's body and a type's representation are braced, and a constant is
/// bound with `=`. Everything before that is what the author wrote to describe
/// the thing rather than to define it. A declaration with neither -- a trait's
/// signature, an `extern`, a re-export -- is a header entire.
///
/// The first token is never a candidate, because a declaration begins with the
/// keyword or the visibility that introduces it and never with a brace.
///
/// A span rather than anything rendered, so a header can make no claim the
/// source does not.
///
/// Costs one pass over the declaration's own tokens.
fn headerSpan(ast: *const Ast, d: DeclId) Span {
    const whole = ast.declSpan(d);
    const run = ast.declTokens(d);

    var i = run.start.index() + 1;
    while (i < run.end.index()) : (i += 1) {
        switch (ast.tokenTag(TokenId.at(i))) {
            .l_brace, .equal => return .{
                .start = whole.start,
                .end = ast.tokenSpan(TokenId.at(i - 1)).end,
            },
            else => {},
        }
    }
    return whole;
}

/// What one file makes reachable outside its module, read from its text alone.
///
/// Lex and parse, and nothing after them. What a module exports is syntactic
/// -- a declaration its own module marks as reaching outside it -- so no
/// resolution, no checking and no assembled program is involved, and a file
/// that does not parse still contributes every declaration the parser
/// recovered.
///
/// Private declarations are omitted. Internal declarations carry root reach;
/// public and opaque declarations carry public reach, with opacity remaining a
/// separate representation rule.
///
/// Top-level declarations only. An `impl`'s and a trait's members are
/// declarations in their own right with their own visibility, and each is
/// reached through the type or trait that owns it rather than by importing the
/// module -- so a name offered for one is a name no `import` can bring into
/// scope.
///
/// In the order the declarations were written, which is the order the parser
/// recorded them in once the members are dropped: a declaration holding others
/// is recorded after them, and they are the ones filtered out here.
///
/// Diagnostics are discarded. Nothing here reports: a workspace is usually
/// half-written somewhere, and a broken file is a file with fewer exports
/// rather than an error anybody is told about.
///
/// Costs one lex and one parse of the file, and one pass over its
/// declarations, each of which reads its own tokens once. Declarations kept
/// here do not overlap, so those passes together read the file's tokens once
/// more. Linear in the file's bytes.
///
/// The caller owns the result, whose strings are copied out of `text` -- an
/// entry outlives the buffer a file was read into, by design.
pub fn exportsOf(
    gpa: std.mem.Allocator,
    path: []const u8,
    text: []const u8,
) ![]const Export {
    // The diagnostics nothing reads, released with the parse that produced
    // them. A sink takes an arena because a diagnostic's text is formatted
    // into it, and there is no one here to format for.
    var discarded = std.heap.ArenaAllocator.init(gpa);
    defer discarded.deinit();

    var sink = Sink.init(discarded.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    const source: Source = .{ .path = path, .text = text };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    defer ast.deinit(gpa);

    var found: std.ArrayList(Export) = .empty;
    errdefer {
        for (found.items) |e| {
            gpa.free(e.name);
            gpa.free(e.header);
        }
        found.deinit(gpa);
    }

    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declVisibility(d) == .private) continue;
        if (ast.declOwner(d) != TokenId.none) continue;
        if (ast.declName(d) == TokenId.none) continue;
        const kind = kindOf(ast.declTag(d)) orelse continue;

        const name = try gpa.dupe(u8, ast.tokenText(ast.declName(d)));
        errdefer gpa.free(name);
        const header = try gpa.dupe(u8, headerSpan(&ast, d).slice(text));
        errdefer gpa.free(header);
        try found.append(gpa, .{
            .name = name,
            .kind = kind,
            .reach = resolve.reachForVisibility(ast.declVisibility(d)),
            .header = header,
        });
    }

    return found.toOwnedSlice(gpa);
}

/// Releases what `exportsOf` returned, which owns its strings.
pub fn free(gpa: std.mem.Allocator, found: []const Export) void {
    for (found) |e| {
        gpa.free(e.name);
        gpa.free(e.header);
    }
    gpa.free(found);
}

test "export storage is released on allocation failure" {
    const check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const found = try exportsOf(gpa, "vault/main.lin", "pub fn open() -> UInt8 { 1 }\n");
            defer free(gpa, found);
            try testing.expectEqual(@as(usize, 1), found.len);
            try testing.expectEqualStrings("open", found[0].name);
        }
    };
    try testing.checkAllAllocationFailures(testing.allocator, check.run, .{});
}

test "a `pub` declaration is exported and a private one beside it is not" {
    const gpa = testing.allocator;
    const text =
        \\pub fn open() -> UInt8 { 1 }
        \\
        \\fn shut() -> UInt8 { 2 }
        \\
    ;

    const found = try exportsOf(gpa, "vault/main.lin", text);
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("open", found[0].name);
    try testing.expectEqual(Kind.function, found[0].kind);
    try testing.expectEqual(Reach.public, found[0].reach);
}

test "an internal declaration is indexed with root reach" {
    const gpa = testing.allocator;
    const found = try exportsOf(gpa, "vault/main.lin", "internal fn shared() -> UInt8 { 1 }\n");
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("shared", found[0].name);
    try testing.expectEqual(Reach.root, found[0].reach);
}

test "every declaration form a module can export carries the kind it was written as" {
    const gpa = testing.allocator;
    const text =
        \\pub let limit: UInt8 = 9
        \\
        \\pub struct Account {
        \\    balance: UInt8,
        \\}
        \\
        \\pub enum Colour {
        \\    Red,
        \\}
        \\
        \\pub trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\
        \\pub fn size() -> UInt8 { 1 }
        \\
    ;

    const found = try exportsOf(gpa, "vault/main.lin", text);
    defer free(gpa, found);

    // In the order they were written, so a `trait` stands where it sits rather
    // than after the signatures it holds.
    const expected = [_]struct { name: []const u8, kind: Kind }{
        .{ .name = "limit", .kind = .constant },
        .{ .name = "Account", .kind = .struct_ },
        .{ .name = "Colour", .kind = .enum_ },
        .{ .name = "Measure", .kind = .trait_ },
        .{ .name = "size", .kind = .function },
    };
    try testing.expectEqual(expected.len, found.len);
    for (expected, found) |want, got| {
        try testing.expectEqualStrings(want.name, got.name);
        try testing.expectEqual(want.kind, got.kind);
    }
}

test "a type sealed with `opaque` is exported, because its name still crosses the boundary" {
    const gpa = testing.allocator;
    const text = "@opaque\nstruct Account { id: UInt8 }\n";

    const found = try exportsOf(gpa, "vault/main.lin", text);
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("Account", found[0].name);
    try testing.expectEqual(Kind.struct_, found[0].kind);
}

test "a `pub use` exports the last element of the path it names" {
    const gpa = testing.allocator;
    const text =
        \\import ledger;
        \\
        \\pub use ledger.Coins;
        \\
        \\use ledger.Tally;
        \\
    ;

    const found = try exportsOf(gpa, "vault/main.lin", text);
    defer free(gpa, found);

    // The `import` binds a module inside this file and the bare `use` is
    // private, so one of the three carries a name onward.
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("Coins", found[0].name);
    try testing.expectEqual(Kind.re_export, found[0].kind);
}

test "a member of an `impl` is not a name the module exports" {
    const gpa = testing.allocator;
    const text =
        \\pub struct Account {
        \\    balance: UInt8,
        \\}
        \\
        \\impl Account {
        \\    pub fn size(self: Self) -> UInt8 { self.balance }
        \\}
        \\
    ;

    const found = try exportsOf(gpa, "vault/main.lin", text);
    defer free(gpa, found);

    // `size` is reached through the type, never through an `import`.
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("Account", found[0].name);
}

test "a declaration that does not parse does not take the file's others with it" {
    const gpa = testing.allocator;
    const text =
        \\pub fn open() -> UInt8 { 1 }
        \\
        \\pub fn ) -> { {
        \\
    ;

    const found = try exportsOf(gpa, "vault/main.lin", text);
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("open", found[0].name);
}

test "a file that exports nothing offers nothing" {
    const gpa = testing.allocator;
    const text = "fn main() -> UInt8 { 0 }\n";

    const found = try exportsOf(gpa, "vault/main.lin", text);
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 0), found.len);
}

test "an export's header is the text that was written" {
    const gpa = testing.allocator;
    const text =
        \\pub fn size(a: Coins) -> UInt8 {
        \\    a.n
        \\}
        \\
        \\pub struct Coins {
        \\    n: UInt8,
        \\}
        \\
        \\pub let limit: UInt8 = 9
        \\
        \\pub trait Measure {
        \\    fn of(x: Self) -> UInt8
        \\}
        \\
    ;

    const found = try exportsOf(gpa, "vault/main.lin", text);
    defer free(gpa, found);

    // Cut out of the source rather than typed out, so what this asserts is
    // that the header is a run of the file and not a rendering of it.
    const expected = [_][]const u8{
        text[0..std.mem.indexOf(u8, text, " {\n    a.n").?],
        text[std.mem.indexOf(u8, text, "pub struct").?..std.mem.indexOf(u8, text, " {\n    n:").?],
        text[std.mem.indexOf(u8, text, "pub let").?..std.mem.indexOf(u8, text, " = 9").?],
        text[std.mem.indexOf(u8, text, "pub trait").?..std.mem.indexOf(u8, text, " {\n    fn of").?],
    };
    try testing.expectEqual(expected.len, found.len);
    for (expected, found) |want, got| {
        try testing.expectEqualStrings(want, got.header);
        // And it is text this file holds, at the offset it was taken from.
        try testing.expect(std.mem.indexOf(u8, text, got.header) != null);
    }
}
