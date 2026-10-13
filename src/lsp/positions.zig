const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const ast_mod = @import("../syntax/ast.zig");
const Ast = ast_mod.Ast;
const FilePart = ast_mod.FilePart;
const Span = @import("../support/span.zig").Span;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const StmtId = node.StmtId;
const ExprId = node.ExprId;
const FileId = @import("../support/source.zig").FileId;
const Source = @import("../support/source.zig").Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const TokenRange = @import("../lexer/token.zig").TokenRange;
const TokenId = @import("../lexer/token.zig").TokenId;

/// Where a byte offset sits, carried forward rather than found again.
///
/// A position is a line and a count of code units along it, and finding one
/// from nothing reads the file from byte zero. So a caller with several
/// offsets in ascending order steps between them instead: the whole run costs
/// one pass over the file rather than one pass per offset, which is the
/// difference between linear and quadratic on a file with many of them.
///
/// How many code units a run of bytes is worth is asked of `lsp.offsets`,
/// which is what counts a `character` everywhere else in this server. Only the
/// stepping is here.
pub const Cursor = struct {
    text: []const u8,
    encoding: lsp.offsets.Encoding,
    at: usize = 0,
    line: u32 = 0,
    character: u32 = 0,

    /// Steps to `offset`, which must be at or after where the cursor already
    /// is.
    pub fn advanceTo(self: *Cursor, offset: usize) void {
        const step = self.text[self.at..offset];
        if (std.mem.lastIndexOfScalar(u8, step, '\n')) |last| {
            self.line += @intCast(std.mem.count(u8, step, "\n"));
            self.character = @intCast(self.width(step[last + 1 ..]));
        } else {
            self.character += @intCast(self.width(step));
        }
        self.at = offset;
    }

    fn width(self: *const Cursor, run: []const u8) usize {
        return widthOf(run, self.encoding);
    }

    pub fn position(self: *const Cursor) lsp.types.Position {
        return .{ .line = self.line, .character = self.character };
    }
};

/// The protocol position of every offset asked about, in the order asked.
///
/// The offsets need not be sorted and need not be distinct: a declaration's
/// extent encloses its members', so the offsets a document outline asks about
/// arrive interleaved rather than ascending. They are sorted here and the file
/// is walked once, because the alternative -- `lsp.offsets.indexToPosition`
/// per offset -- reads the file from byte zero each time, and a file of `n`
/// declarations then costs `n` passes over it. That is the shape a generated
/// module of thousands of declarations has.
///
/// Costs one pass over the file plus the sort: O(text + k log k) for `k`
/// offsets, and it holds one index and one position per offset. Nothing here
/// is sized by the program: a document's positions are a question about that
/// document.
pub fn positionsOf(
    gpa: std.mem.Allocator,
    text: []const u8,
    offsets: []const u32,
    encoding: lsp.offsets.Encoding,
) ![]const lsp.types.Position {
    const order = try gpa.alloc(u32, offsets.len);
    defer gpa.free(order);
    for (order, 0..) |*o, i| o.* = @intCast(i);

    std.mem.sortUnstable(u32, order, offsets, struct {
        fn less(all: []const u32, a: u32, b: u32) bool {
            return all[a] < all[b];
        }
    }.less);

    const out = try gpa.alloc(lsp.types.Position, offsets.len);
    errdefer gpa.free(out);

    var cursor: Cursor = .{ .text = text, .encoding = encoding };
    for (order) |i| {
        cursor.advanceTo(offsets[i]);
        out[i] = cursor.position();
    }
    return out;
}

test "every position is the one the protocol's own conversion finds" {
    const gpa = testing.allocator;

    // An em-dash is three bytes and one UTF-16 code unit, so a walk counting
    // bytes puts everything after it on the wrong column, and a file of ASCII
    // could not say so.
    const text = "fn main() -> UInt8 {\n    // \u{2014} here\n    0\n}\n";

    // Deliberately out of order and with a repeat: a document outline asks
    // about a declaration's extent and its name's, and the two interleave.
    // 31 is the byte after the em-dash, which is three bytes and one code
    // unit -- a cursor counting bytes puts everything after it to the right.
    const offsets = [_]u32{ 31, 3, 0, 3, @intCast(text.len - 2) };

    const found = try positionsOf(gpa, text, &offsets, .@"utf-16");
    defer gpa.free(found);

    for (offsets, found) |offset, position| {
        try testing.expectEqual(
            lsp.offsets.indexToPosition(text, offset, .@"utf-16"),
            position,
        );
    }
}

test "no offset asked about is left unanswered" {
    const gpa = testing.allocator;

    const found = try positionsOf(gpa, "a\nbb\nccc\n", &.{ 8, 0, 5 }, .@"utf-16");
    defer gpa.free(found);

    try testing.expectEqual(lsp.types.Position{ .line = 2, .character = 3 }, found[0]);
    try testing.expectEqual(lsp.types.Position{ .line = 0, .character = 0 }, found[1]);
    try testing.expectEqual(lsp.types.Position{ .line = 2, .character = 0 }, found[2]);
}

/// How wide a run of source is in the client's units.
///
/// Bytes where the run is not UTF-8, because counting code units through one
/// aborts on the first byte that begins no sequence. A file the compiler
/// refuses under [S-Encoding] is still a file an editor has open, and a server
/// that stops answering about a buffer someone is part-way through typing is
/// worse than one that answers approximately: the column is wrong on that line,
/// and the server is alive to be right about the next.
///
/// One place answers it, because a token's width and a cursor's advance are the
/// same question and two of them would have aborted in two different sessions.
pub fn widthOf(run: []const u8, encoding: lsp.offsets.Encoding) usize {
    if (!std.unicode.utf8ValidateSlice(run)) return run.len;
    return lsp.offsets.countCodeUnits(run, encoding);
}

/// The protocol range a byte span covers in a file's text.
///
/// Both ends in one walk, for the reason `positionsOf` exists at all: a range
/// found one end at a time reads the file from byte zero twice.
pub fn rangeOf(
    text: []const u8,
    span: Span,
    encoding: lsp.offsets.Encoding,
) lsp.types.Range {
    var cursor: Cursor = .{ .text = text, .encoding = encoding };
    cursor.advanceTo(span.start);
    const start = cursor.position();
    cursor.advanceTo(span.end);
    return .{ .start = start, .end = cursor.position() };
}

/// The last token of `file` ending at or before `offset`, or `.none` where
/// nothing was written before it.
///
/// What a cursor was written **after**, which is a different question from
/// what it was written **in** and is the one a half-finished construct asks:
/// `c.` selects, and its last token is the dot, so a cursor typed straight
/// after it sits outside every node the selection covers. `innermost` answers
/// the other question and would answer with whatever spans the gap.
///
/// Costs a binary search over the file's tokens. Token spans within a file
/// ascend and do not overlap, so the ones ending early are a prefix of them.
pub fn tokenBefore(ast: *const Ast, file: FileId, offset: u32) TokenId {
    const part = ast.partOfFile(file) orelse return TokenId.none;
    const spans = ast.tokens.items(.span);

    var lo = part.token_start;
    var hi = part.token_end;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (spans[mid].end <= offset) lo = mid + 1 else hi = mid;
    }
    if (lo == part.token_start) return TokenId.none;
    return TokenId.at(lo - 1);
}

/// What sits at a byte offset.
///
/// Whichever kind of node the tree recorded there. A cursor lands on a name
/// inside an expression inside a statement inside a declaration, and which of
/// those is innermost is a fact about where it was written rather than about
/// what the caller was hoping to find.
pub const Node = union(enum) {
    decl: DeclId,
    stmt: StmtId,
    expr: ExprId,
};

/// A node a cursor reached, and what was written around it.
///
/// The pair rather than the node alone, because a name is written inside the
/// thing it is part of and a reader pointing at one is often pointing at the
/// other: the callee of a call is where a cursor lands when it lands on the
/// call.
pub const Under = struct {
    node: Node,
    /// What encloses it, or null where nothing does.
    around: ?Node,
    /// The token the offset sits inside, or `.none` where it sits in the gap
    /// between two of them.
    ///
    /// Carried out of the lookup rather than found again: the search for the
    /// node is a search for the token, so a caller asking which token this is
    /// would be running that search a second time and could disagree with it.
    /// A declaration is reached this way -- what a name declares is a fact
    /// about the token it was written at, and the node covering it is the whole
    /// declaration.
    token: TokenId,
};

/// The innermost node covering a byte offset, in one lookup.
///
/// Built by a sweep rather than by a fill. Marking every token a node covers
/// costs the sum of every node's extent, and nodes nest -- a token deep in a
/// chain is covered by every one of its ancestors, so a balanced tree costs
/// n log n and a chain of operators costs n squared. A sweep over the tokens,
/// pushing nodes where they open and popping them where they close, leaves the
/// innermost one on top of the stack at every token and never looks at a
/// (node, token) pair twice.
///
/// The sweep is a stack, so it rests on extents nesting: a node's tokens are
/// either inside another's or outside them, never half of each. That holds
/// because every extent is a pair of cursor positions taken in one rule --
/// where the rule began and where it had reached -- and the cursor only ever
/// moves forward, so a rule's extent covers exactly the rules it called. What
/// would break it is a node built over tokens a node still open does not hold,
/// which `crossing` is the check for.
///
/// The tree is a parameter of every call rather than a field, because an
/// `Analysis` is returned by value and held in a cache: a pointer into its own
/// tree would name where the tree used to be.
pub const Index = struct {
    /// Every node that was written over at least one token, ordered so that an
    /// enclosing node comes before everything it encloses.
    entries: []const Entry,
    /// For each token, the entry of the innermost node covering it, or
    /// `nothing`.
    covering: []const u32,
    /// For each token, the entry of the innermost node covering the bytes
    /// between the token before it and it, or `nothing`. A cursor in
    /// whitespace sits inside whatever spans the gap, which is not what either
    /// neighbouring token sits inside.
    preceding: []const u32,
    /// How many marks the build wrote to fill `covering` and `preceding`.
    ///
    /// Recorded because the difference between this sweep and the fill it
    /// replaces is invisible in every other way. Both answer the same
    /// questions, both allocate the same tables, and both are the same number
    /// of milliseconds on a file of a few hundred bytes -- so what it took to
    /// fill them is the only thing a case can hold the build to.
    ///
    /// A count of the marks and not of the steps a loop took: a mark is the
    /// only way a token's answer is set, so this is a consequence of producing
    /// the tables rather than a claim about how they were produced. A sweep
    /// writes each of a token's two marks once; a build that marks every token
    /// every node covers writes one per (node, token) pair, and no shape of
    /// loop makes that fewer.
    marks: u64,

    /// No node covers this token, which is where a declaration has not begun
    /// or has already ended.
    pub const nothing = std.math.maxInt(u32);

    /// A node and the run of tokens it was written over.
    pub const Entry = struct {
        start: u32,
        end: u32,
        node: Node,
        /// The entry of the node written around this one, or `nothing` where
        /// nothing was. Filled by the sweep, which knows it for free: what
        /// encloses a node is whatever was open where the node opened.
        enclosing: u32 = nothing,
    };

    /// Costs O(tokens + nodes log nodes): one pass over the tokens, one push
    /// and one pop per node, and the sort that puts the nodes in nesting
    /// order, which is the only term above linear. Holds two words per token
    /// and one entry per node, both sized by the tree it is built from.
    pub fn build(gpa: std.mem.Allocator, ast: *const Ast) !Index {
        const tokens = ast.tokenCount();

        var found: std.ArrayList(Entry) = .empty;
        errdefer found.deinit(gpa);
        try found.ensureTotalCapacityPrecise(
            gpa,
            ast.declCount() + ast.stmtCount() + ast.exprCount(),
        );

        for (0..ast.declCount()) |i| {
            const id = DeclId.at(@intCast(i));
            extend(&found, ast.declTokens(id), .{ .decl = id }, tokens);
        }
        for (0..ast.stmtCount()) |i| {
            const id = StmtId.at(@intCast(i));
            extend(&found, ast.stmtTokens(id), .{ .stmt = id }, tokens);
        }
        for (0..ast.exprCount()) |i| {
            const id = ExprId.at(@intCast(i));
            extend(&found, ast.exprTokens(id), .{ .expr = id }, tokens);
        }

        const entries = try found.toOwnedSlice(gpa);
        errdefer gpa.free(entries);
        std.mem.sortUnstable(Entry, entries, {}, encloses);

        const covering = try gpa.alloc(u32, tokens);
        errdefer gpa.free(covering);
        const preceding = try gpa.alloc(u32, tokens);
        errdefer gpa.free(preceding);

        var marks: Marks = .{ .covering = covering, .preceding = preceding };

        // The nodes covering the token being swept, outermost first. As deep
        // as the tree nests and no deeper, which is a question about the file
        // rather than about the program.
        var open: std.ArrayList(u32) = .empty;
        defer open.deinit(gpa);

        var next: u32 = 0;
        for (0..tokens) |i| {
            const at_token: u32 = @intCast(i);

            // A node whose last token is behind this one covers neither this
            // token nor the gap in front of it: a span ends where its last
            // token ends.
            while (open.items.len > 0 and entries[open.getLast()].end <= at_token) {
                _ = open.pop();
            }
            marks.precede(i, if (open.items.len > 0) open.getLast() else nothing);

            // In nesting order, so the innermost of the nodes beginning here
            // is the one left on top.
            while (next < entries.len and entries[next].start == at_token) {
                entries[next].enclosing = if (open.items.len > 0) open.getLast() else nothing;
                try open.append(gpa, next);
                next += 1;
            }
            marks.cover(i, if (open.items.len > 0) open.getLast() else nothing);
        }

        return .{
            .entries = entries,
            .covering = covering,
            .preceding = preceding,
            .marks = marks.written,
        };
    }

    /// The two tables a build fills in, and how many marks it wrote.
    ///
    /// The tables are reached through this while a build runs, so setting a
    /// token's answer and counting that it was set are one operation. A count
    /// kept beside the loop counts what the loop says about itself, and says
    /// nothing about a loop written next to it.
    const Marks = struct {
        covering: []u32,
        preceding: []u32,
        written: u64 = 0,

        fn cover(self: *Marks, token: usize, entry: u32) void {
            self.covering[token] = entry;
            self.written += 1;
        }

        fn precede(self: *Marks, token: usize, entry: u32) void {
            self.preceding[token] = entry;
            self.written += 1;
        }
    };

    pub fn deinit(self: *Index, gpa: std.mem.Allocator) void {
        gpa.free(self.entries);
        gpa.free(self.covering);
        gpa.free(self.preceding);
        self.* = undefined;
    }

    /// The innermost node covering `offset` in `file`, or null where nothing
    /// was written there.
    ///
    /// Costs a binary search over the file's tokens and one array read:
    /// O(log tokens), and nothing proportional to what the answer encloses.
    /// That is the whole reason the index exists rather than each request
    /// walking the tree.
    pub fn at(self: *const Index, ast: *const Ast, file: FileId, offset: u32) ?Node {
        return (self.under(ast, file, offset) orelse return null).node;
    }

    /// The innermost node covering `offset`, with what was written around it.
    ///
    /// One lookup answers both, because a caller that asked for the node and
    /// then searched for its parent would be walking the tree again -- which is
    /// what this index exists to stop.
    pub fn under(self: *const Index, ast: *const Ast, file: FileId, offset: u32) ?Under {
        const found = self.innermost(ast, file, offset) orelse return null;
        return self.underOf(found.entry, found.token);
    }

    /// The entry of the innermost node covering an offset, and the token the
    /// offset sits inside.
    ///
    /// One search, because every question about where a cursor is starts with
    /// it: a second binary search written beside this one could land on a
    /// different token in the byte between two of them, and then two
    /// capabilities would disagree about where the same cursor is.
    fn innermost(
        self: *const Index,
        ast: *const Ast,
        file: FileId,
        offset: u32,
    ) ?struct { entry: u32, token: TokenId } {
        const part = ast.partOfFile(file) orelse return null;
        const spans = ast.tokens.items(.span);

        // One past the last token of this file beginning at or before the
        // offset. Token spans within a file ascend and do not overlap, so
        // there is at most one candidate and it is the one before this.
        var lo = part.token_start;
        var hi = part.token_end;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (spans[mid].start <= offset) lo = mid + 1 else hi = mid;
        }

        // A cursor immediately after a token is still completing that token.
        // Prefer an identifier ending at the boundary over punctuation that
        // begins there; the latter encloses the name but does not change which
        // name the client is completing.
        if (lo > part.token_start) {
            const last = lo - 1;
            const before = if (spans[last].start == offset and last > part.token_start) last - 1 else last;
            if (spans[before].end == offset and
                ast.tokenTag(TokenId.at(before)) == .identifier and
                self.covering[before] != nothing)
            {
                return .{ .entry = self.covering[before], .token = TokenId.none };
            }
        }
        if (lo > part.token_start and spans[lo - 1].contains(offset)) {
            return .{ .entry = self.covering[lo - 1], .token = TokenId.at(lo - 1) };
        }
        // Between two tokens, or before the first: what covers the gap is what
        // spans it, which is neither token's own innermost node.
        if (lo < part.token_end) return .{ .entry = self.preceding[lo], .token = TokenId.none };
        return null;
    }

    /// Every node covering an offset, innermost first.
    ///
    /// The chain the sweep already wrote down, walked rather than searched for:
    /// what encloses a node is whatever was open where that node opened, and a
    /// caller looking for the next node covering the offset would be walking
    /// the tree a second time and could disagree with this one.
    ///
    /// For a capability that has to answer about a point the tree records
    /// nothing useful at -- a cursor inside a call the parser never closed --
    /// and so has to look outward until something answers.
    ///
    /// Costs the binary search `under` costs, then one step per level of
    /// nesting: the depth of what was written around the offset, and nothing
    /// proportional to the program.
    pub fn enclosing(self: *const Index, ast: *const Ast, file: FileId, offset: u32) Enclosing {
        const found = self.innermost(ast, file, offset);
        return .{ .index = self, .at = if (found) |f| f.entry else nothing };
    }

    /// The declaration supplies the capability bounds used by method lookup.
    pub fn declarationAt(self: *const Index, ast: *const Ast, file: FileId, offset: u32) DeclId {
        var chain = self.enclosing(ast, file, offset);
        while (chain.next()) |n| switch (n) {
            .decl => |decl| return decl,
            .expr, .stmt => {},
        };
        return .none;
    }

    /// A walk outward from a node, one level at a time.
    pub const Enclosing = struct {
        index: *const Index,
        at: u32,

        pub fn next(self: *Enclosing) ?Node {
            if (self.at == nothing) return null;
            const held = self.index.entries[self.at];
            self.at = held.enclosing;
            return held.node;
        }
    };

    /// The innermost node a protocol position names, converted through the
    /// file's own text.
    ///
    /// One place converts a position to a node, because a capability that
    /// counted a `character` its own way would answer about a different byte
    /// than the one beside it does -- and only on a line holding something
    /// outside ASCII.
    ///
    /// Costs one pass over the file's bytes to reach the offset, then the
    /// binary search `under` costs.
    pub fn atPosition(
        self: *const Index,
        ast: *const Ast,
        part: *const FilePart,
        position: lsp.types.Position,
        encoding: lsp.offsets.Encoding,
    ) ?Under {
        const offset = lsp.offsets.positionToIndex(part.source, position, encoding);
        return self.under(ast, part.file, @intCast(offset));
    }

    fn underOf(self: *const Index, entry: u32, sits_in: TokenId) ?Under {
        if (entry == nothing) return null;
        const held = self.entries[entry];
        return .{
            .node = held.node,
            .around = if (held.enclosing == nothing) null else self.entries[held.enclosing].node,
            .token = sits_in,
        };
    }

    /// Two recorded extents that overlap without one holding the other.
    pub const Crossing = struct { outer: Entry, inner: Entry };

    /// The first pair of extents that cross, or null where every pair nests or
    /// is disjoint -- which is what the sweep assumes and what nothing else
    /// states.
    ///
    /// A crossing pair is not a wrong answer about which node covers a token:
    /// `covering` is written from the top of the stack and the top is right
    /// either way. It is a wrong `enclosing`. The outer node of a crossing pair
    /// is never popped, because the pop loop reads the top alone, so every node
    /// opened after it is recorded as sitting inside a node that had already
    /// ended -- and `enclosing` is what a cursor on a callee reads to reach the
    /// call it belongs to.
    ///
    /// Costs one pass over the entries, which are already in nesting order, and
    /// a stack as deep as they nest.
    pub fn crossing(self: *const Index, gpa: std.mem.Allocator) !?Crossing {
        var open: std.ArrayList(u32) = .empty;
        defer open.deinit(gpa);

        for (self.entries, 0..) |e, i| {
            // Everything that ended before this one began holds nothing here.
            while (open.items.len > 0 and self.entries[open.getLast()].end <= e.start) {
                _ = open.pop();
            }
            // The top alone, because a push happens only where the top holds
            // what is pushed: the ends on the stack descend, so a node the top
            // holds is held by every one below it.
            if (open.items.len > 0 and self.entries[open.getLast()].end < e.end) {
                return .{ .outer = self.entries[open.getLast()], .inner = e };
            }
            try open.append(gpa, @intCast(i));
        }
        return null;
    }

    /// Records a node's extent, unless it was written over no tokens at all --
    /// which a node the parser gave up on can be, and which covers no byte.
    fn extend(into: *std.ArrayList(Entry), r: TokenRange, of: Node, tokens: u32) void {
        if (r.len() == 0 or r.start.index() >= tokens) return;
        into.appendAssumeCapacity(.{
            .start = r.start.index(),
            .end = @min(r.end.index(), tokens),
            .node = of,
        });
    }

    /// Where a node begins, then how far it reaches, then which kind it is.
    ///
    /// Start ascending and end descending is a nesting order: an enclosing
    /// node begins no later and ends no earlier, so it sorts first. The rest
    /// settles nodes written over exactly the same tokens -- a declaration
    /// holds a statement holds an expression, and a node the parser built
    /// later holds the ones it was built from.
    fn encloses(_: void, a: Entry, b: Entry) bool {
        if (a.start != b.start) return a.start < b.start;
        if (a.end != b.end) return a.end > b.end;
        const ka = @intFromEnum(std.meta.activeTag(a.node));
        const kb = @intFromEnum(std.meta.activeTag(b.node));
        if (ka != kb) return ka < kb;
        return idOf(a.node) > idOf(b.node);
    }

    fn idOf(of: Node) u32 {
        return switch (of) {
            inline else => |id| id.index(),
        };
    }
};

/// A tree of one file, for a case that needs a real one.
const Tree = struct {
    arena: std.heap.ArenaAllocator,
    ast: Ast,
    text: []const u8,
    /// Whether the parser reported anything, which is how a case says whether
    /// the tree it is reading is one error recovery built.
    reported: bool,

    fn deinit(self: *Tree) void {
        self.arena.deinit();
    }
};

/// A tree of one file, whatever the parser made of it. The frontend never
/// fails, so this returns one for text that is not a program at all.
fn parsedTree(gpa: std.mem.Allocator, text: []const u8) !Tree {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    const source: Source = .{ .path = "cursor.lin", .text = text };
    var sink = Sink.init(a);
    var interner: Interner = .empty;
    const tokens = try tokenize(a, &source, .from(0), &sink, &interner);
    const ast = try parse(a, &source, .from(0), tokens, &sink);

    return .{ .arena = arena, .ast = ast, .text = text, .reported = sink.hasErrors() };
}

fn treeOf(gpa: std.mem.Allocator, text: []const u8) !Tree {
    var tree = try parsedTree(gpa, text);
    errdefer tree.deinit();
    try testing.expect(!tree.reported);
    return tree;
}

/// The source a cursor's node was written as, whatever kind of node it is.
fn textAt(tree: *const Tree, index: *const Index, offset: usize) ?[]const u8 {
    const found = index.at(&tree.ast, .from(0), @intCast(offset)) orelse return null;
    const span = switch (found) {
        .decl => |d| tree.ast.declSpan(d),
        .stmt => |s| tree.ast.stmtSpan(s),
        .expr => |e| tree.ast.exprSpan(e),
    };
    return span.slice(tree.text);
}

/// One function whose body is `n` statements: the shape of a generated module
/// that is one enormous function.
fn longFunction(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("fn main() -> UInt8 {\n    let v0: UInt8 = 1\n");
    for (1..n) |i| try w.print("    let v{d}: UInt8 = v{d} + 1\n", .{ i, i - 1 });
    try w.print("    v{d}\n}}\n", .{n - 1});
    return out.toOwnedSlice();
}

/// One expression of `n` operands, which nests `n` deep. The shape that makes
/// the sum of every node's extent quadratic in the size of the file.
fn deepExpression(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("fn f(a: UInt8) -> UInt8 {\n    a");
    for (1..n) |_| try w.writeAll(" + a");
    try w.writeAll("\n}\n");
    return out.toOwnedSlice();
}

/// The sum of every recorded node's extent, which is how many marks a build
/// that marked each token every node covers would write.
fn extentSum(index: *const Index) u64 {
    var total: u64 = 0;
    for (index.entries) |e| total += e.end - e.start;
    return total;
}

test "the index marks each token once, not once per node covering it" {
    const gpa = testing.allocator;

    const shapes = [_][]const u8{
        try longFunction(gpa, 4000),
        try deepExpression(gpa, 1000),
    };
    defer for (shapes) |s| gpa.free(s);

    for (shapes) |text| {
        var tree = try treeOf(gpa, text);
        defer tree.deinit();

        var index = try Index.build(gpa, &tree.ast);
        defer index.deinit(gpa);

        try testing.expect(index.entries.len > 1000);
        try testing.expectEqual(@as(usize, tree.ast.tokenCount()), index.covering.len);

        // Two marks per token, each written once: one saying what covers the
        // token and one saying what covers the gap in front of it. Marking
        // every token a node covers writes the sum of the extents instead,
        // which on both of these shapes is more -- so the number above is not
        // one a build filling every (node, token) pair could also report.
        try testing.expectEqual(2 * @as(u64, tree.ast.tokenCount()), index.marks);
        try testing.expect(extentSum(&index) > index.marks);
    }
}

test "extents that cross are what the sweep hands out a dead ancestor for" {
    const gpa = testing.allocator;

    // A = tokens 0..10 and B = 5..15, which no tree records and which the pop
    // loop cannot recover from: at token 10 the top of the stack is B, so A is
    // never popped and everything opened after it is recorded as sitting
    // inside it.
    const crossed = [_]Index.Entry{
        .{ .start = 0, .end = 10, .node = .{ .stmt = StmtId.at(0) } },
        .{ .start = 5, .end = 15, .node = .{ .expr = ExprId.at(0) } },
    };
    const index: Index = .{ .entries = &crossed, .covering = &.{}, .preceding = &.{}, .marks = 0 };

    const found = (try index.crossing(gpa)).?;
    try testing.expectEqual(@as(u32, 10), found.outer.end);
    try testing.expectEqual(@as(u32, 15), found.inner.end);

    // And a pair that nests is not one, which is what the sweep is built for.
    const nested = [_]Index.Entry{
        .{ .start = 0, .end = 15, .node = .{ .stmt = StmtId.at(0) } },
        .{ .start = 5, .end = 10, .node = .{ .expr = ExprId.at(0) } },
    };
    const holds: Index = .{ .entries = &nested, .covering = &.{}, .preceding = &.{}, .marks = 0 };
    try testing.expectEqual(@as(?Index.Crossing, null), try holds.crossing(gpa));
}

test "no tree records an extent crossing another, however it was recovered" {
    const gpa = testing.allocator;

    // Every shape of recovery this parser has: a rule that gave up mid-list, a
    // delimiter never closed, one closed that never opened, a name where a
    // pattern goes, and the one place the cursor is moved backwards -- an arm
    // pattern read as a name and re-read as a struct.
    const shapes = [_][]const u8{
        "fn main() -> UInt8 {\n    match v {\n        S { f } => 1,\n    }\n}\n",
        "fn main() -> UInt8 {\n    match v {\n        S { f => 1,\n",
        "fn main() -> UInt8 {\n    let x: UInt8 = (1 +\n",
        "fn f(a: UInt8,",
        "}\nfn main() -> UInt8 { 1 }\n",
        "struct S {\n    a: ,\n    b: UInt8,\n}\n",
        "impl S {\n    fn one() -> UInt8 {\n",
        "fn main() -> UInt8 {\n    if {\n    } else\n}\n",
        "###\nfn main() -> UInt8 { 1 }\n",
        "",
    };

    for (shapes) |text| {
        var tree = try parsedTree(gpa, text);
        defer tree.deinit();

        var index = try Index.build(gpa, &tree.ast);
        defer index.deinit(gpa);

        try testing.expectEqual(@as(?Index.Crossing, null), try index.crossing(gpa));
    }
}

/// An em-dash, which is three bytes, sits in the comment: a client counting
/// UTF-16 code units can name a byte in the middle of one.
const cursor_program = "fn one() -> UInt8 { 1 }\n" ++
    "\n" ++
    "fn add(a: UInt8, b: UInt8) -> UInt8 { a + b }\n" ++
    "\n" ++
    "fn main() -> UInt8 {\n" ++
    "    // add \u{2014} one\n" ++
    "    let total: UInt8 = add( one(), 2 )\n" ++
    "    total\n" ++
    "}\n";

test "a cursor on a name reaches the name" {
    const gpa = testing.allocator;
    var tree = try treeOf(gpa, cursor_program);
    defer tree.deinit();
    var index = try Index.build(gpa, &tree.ast);
    defer index.deinit(gpa);

    const at = std.mem.lastIndexOf(u8, cursor_program, "total").?;
    try testing.expectEqualStrings("total", textAt(&tree, &index, at + 2).?);
}

test "a cursor inside a nested call reaches the innermost call" {
    const gpa = testing.allocator;
    var tree = try treeOf(gpa, cursor_program);
    defer tree.deinit();
    var index = try Index.build(gpa, &tree.ast);
    defer index.deinit(gpa);

    const call = std.mem.indexOf(u8, cursor_program, "one(), 2").?;
    try testing.expectEqualStrings("one", textAt(&tree, &index, call + 1).?);
    try testing.expectEqualStrings("one()", textAt(&tree, &index, call + 4).?);
}

test "a cursor between two tokens reaches what encloses the gap" {
    const gpa = testing.allocator;
    var tree = try treeOf(gpa, cursor_program);
    defer tree.deinit();
    var index = try Index.build(gpa, &tree.ast);
    defer index.deinit(gpa);

    const gap = std.mem.indexOf(u8, cursor_program, "add( one").? + 4;
    try testing.expectEqualStrings("add( one(), 2 )", textAt(&tree, &index, gap).?);
}

test "a cursor past the end of the file reaches nothing" {
    const gpa = testing.allocator;
    var tree = try treeOf(gpa, cursor_program);
    defer tree.deinit();
    var index = try Index.build(gpa, &tree.ast);
    defer index.deinit(gpa);

    try testing.expectEqual(@as(?[]const u8, null), textAt(&tree, &index, cursor_program.len));
    try testing.expectEqual(@as(?[]const u8, null), textAt(&tree, &index, cursor_program.len + 16));
}

test "a cursor inside a character reaches what its first byte reaches" {
    const gpa = testing.allocator;
    var tree = try treeOf(gpa, cursor_program);
    defer tree.deinit();
    var index = try Index.build(gpa, &tree.ast);
    defer index.deinit(gpa);

    // An em-dash is three bytes, and a client counting UTF-16 code units can
    // name a byte in the middle of one.
    const dash = std.mem.indexOf(u8, cursor_program, "\u{2014}").?;
    const first = textAt(&tree, &index, dash).?;
    try testing.expectEqualStrings(first, textAt(&tree, &index, dash + 1).?);
    try testing.expectEqualStrings(first, textAt(&tree, &index, dash + 2).?);
}
