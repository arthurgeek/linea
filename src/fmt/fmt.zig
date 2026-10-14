const DeclarationSelection = @import("../syntax/program.zig").DeclarationSelection;
const std = @import("std");
const testing = std.testing;

const Source = @import("../support/source.zig").Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const dumpAst = @import("../syntax/dump.zig").dumpAst;
const max_nesting = @import("../parser/parser.zig").max_nesting;
const Ast = @import("../syntax/ast.zig").Ast;
const DeclIndex = @import("../syntax/ast.zig").DeclIndex;
const FileId = @import("../support/source.zig").FileId;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const StmtId = node.StmtId;
const token = @import("../lexer/token.zig");
const Span = @import("../support/span.zig").Span;
const TokenId = token.TokenId;

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error;

const indent_width = 4;

/// Renders a parsed file as canonical Linea.
///
/// The tree gives structure and the token array gives text, kept in step by the
/// `token_range` every node carries. Nothing is measured: layout follows from
/// trailing commas and from whether an element can be rendered flat at all.
pub fn format(gpa: std.mem.Allocator, ast: *const Ast, w: *std.Io.Writer) Error!void {
    return formatNoted(gpa, ast, .none, DeclarationSelection.all(ast.declCount()), w);
}

/// What a later pass knows and the source does not say, as text, keyed by the
/// id of the node it belongs to.
///
/// Formatting is a question about syntax, so the printer asks no pass
/// anything: it is handed the answers already spelled. That is what keeps the
/// formatter free of the type checker, which matters because it has to run on
/// source that does not check.
pub const Notes = struct {
    /// The type a binding was inferred to have, by `StmtId`, where the source
    /// left the annotation out.
    bindings: []const []const u8 = &.{},
    /// Written where an expression says less than the checker settled: the
    /// type arguments a call instantiated its callee with, or the type a
    /// braced literal turned out to build. Keyed by `ExprId`; where the two
    /// meanings differ is decided by the expression's tag, and one expression
    /// has one tag.
    exprs: []const []const u8 = &.{},
    /// What a token stands for, written instead of the token's own text.
    /// Keyed by `TokenId`, which is what a written type and a name both come
    /// down to -- so one table covers a type parameter under an instantiation
    /// and the callee a call resolved to.
    tokens: []const []const u8 = &.{},
    /// The receiver of a call written in the postfix form, keyed by the
    /// call's `ExprId`, or none. Where a note writes such a call's callee as
    /// the operation it reaches, the receiver is written as its first
    /// argument, carrying the call's `&` where the call lends it.
    receivers: []const ExprId = &.{},
    /// Written instead of a declaration's name. An instantiation needs one,
    /// because several of them share the name they were instantiated from.
    name: []const u8 = "",
    /// Whether a declaration's type parameters are written. An instantiation
    /// has none left: that is what having been instantiated means.
    type_params: bool = true,
    /// Whether a written type's arguments are written. An instantiation is one
    /// type rather than a name and a list, so where it is named by a name of
    /// its own the brackets have nothing left to say.
    type_args: bool = true,

    /// Attached derive traits already materialized by the caller, keyed by
    /// `DeriveTraitId`. A nonempty mask reconstructs source, retaining hatch
    /// marker comments without copying regions that could restore omitted
    /// requests. Normal formatting uses an empty mask and respects hatches.
    omit_derive_traits: []const bool = &.{},

    /// Every note absent, which is what plain formatting asks for.
    pub const none: Notes = .{};

    fn at(list: []const []const u8, i: u32) []const u8 {
        return if (i < list.len) list[i] else "";
    }
};

/// Renders the file with a pass's annotations written into it.
///
/// The result is a reading of the program, not a source file: a note goes
/// wherever it reads best, including positions the grammar has no syntax for.
pub fn formatNoted(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    notes: Notes,
    /// Declarations belonging to the source being rendered.
    selection: DeclarationSelection,
    w: *std.Io.Writer,
) Error!void {
    var indexes = try Indexes.build(gpa, ast);
    defer indexes.deinit(gpa);
    return formatIndexed(gpa, ast, &indexes, notes, selection, w);
}

fn formatIndexed(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    indexes: *const Indexes,
    notes: Notes,
    selection: DeclarationSelection,
    w: *std.Io.Writer,
) Error!void {
    var p: Printer = .{
        .gpa = gpa,
        .ast = ast,
        .decls = &indexes.decls,
        .extents = &indexes.extents,
        .text = ast.parts[0].source,
        .file = ast.parts[0].file,
        .notes = notes,
        .selection = selection,
        .w = w,
    };
    defer p.chain_links.deinit(gpa);
    defer p.chain.deinit(gpa);
    try p.writeProgram();
}

/// What a comment means as a hatch marker.
pub const Marker = enum { off, on, none };

/// Whether two parsed trees match, ignoring where the tokens sit.
fn sameShape(gpa: std.mem.Allocator, before: *const Ast, after: *const Ast) !bool {
    if (!sameAttributes(before, after)) return false;
    const a = try shapeOf(gpa, before);
    defer gpa.free(a);
    const b = try shapeOf(gpa, after);
    defer gpa.free(b);
    return std.mem.eql(u8, a, b);
}

/// Attribute ownership and grouping are retained syntax, independent of the
/// normalized policies printed by the AST dump. Compare each declaration's
/// groups directly so moving or losing a derive request changes its shape.
fn sameAttributes(before: *const Ast, after: *const Ast) bool {
    if (before.declCount() != after.declCount()) return false;
    for (0..before.declCount()) |index| {
        const declaration = DeclId.at(@intCast(index));
        const left_groups = before.declAttributeGroups(declaration);
        const right_groups = after.declAttributeGroups(declaration);
        if (left_groups.len != right_groups.len) return false;
        for (left_groups, right_groups) |left, right| {
            var a = before.runOf(left.tokens);
            var b = after.runOf(right.tokens);
            while (nextAttributeShapeToken(&a)) |left_token| {
                const right_token = nextAttributeShapeToken(&b) orelse return false;
                if (before.tokenTag(left_token) != after.tokenTag(right_token) or
                    !std.mem.eql(u8, before.tokenText(left_token), after.tokenText(right_token))) return false;
            }
            if (nextAttributeShapeToken(&b) != null) return false;
        }
    }
    return true;
}

fn nextAttributeShapeToken(run: *Ast.TokenRun) ?TokenId {
    while (run.next()) |at| {
        if (run.ast.tokenTag(at) != .comma) return at;
    }
    return null;
}

fn shapeOf(gpa: std.mem.Allocator, ast: *const Ast) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    // The whole tree: this text is one file parsed on its own, so every
    // declaration in it is one the formatter is being asked about.
    dumpAst(&out.writer, ast, DeclarationSelection.all(ast.declCount())) catch return error.OutOfMemory;

    // `tokens N..M` says where a node sits, which formatting is allowed to
    // change. Everything else the dump prints is what the node *is*.
    var stripped: std.ArrayList(u8) = .empty;
    var rest = out.written();
    while (std.mem.indexOf(u8, rest, "tokens ")) |at| {
        try stripped.appendSlice(gpa, rest[0..at]);
        rest = rest[at + "tokens ".len ..];
        var i: usize = 0;
        while (i < rest.len and rest[i] != ' ' and rest[i] != '\n') i += 1;
        rest = rest[i..];
    }
    try stripped.appendSlice(gpa, rest);
    return stripped.toOwnedSlice(gpa);
}

/// One past the end of the region opened at `from`.
///
/// The whole rule, in one place: the region runs to the end of the line
/// holding the next `on` marker that owns its line, or to the end of the file
/// where nothing closes it -- and then far enough to cover any declaration it
/// would otherwise end in the middle of. The walk steps over a node beginning
/// inside a region, so a declaration straddling the end would be skipped whole
/// and everything past the copy would be lost.
///
/// Exported because the perturbation that checks the formatter must route
/// around exactly the text the formatter copies. Two answers to "where does
/// this region end" is two programs disagreeing about what is verbatim.
pub fn regionEnd(ast: *const Ast, extents: *const Extents, opened_at: TokenId) u32 {
    return regionSpan(ast, extents, opened_at).end;
}

/// Where a region ends, and where its author said it should.
///
/// The two differ when the region had to be extended over a node it would
/// otherwise have cut. That is not a detail: the `on` the author wrote then
/// does nothing, and everything to the end of the enclosing declaration stays
/// unformatted with no indication.
pub const Region = struct {
    end: u32,
    /// Where the closing marker's line ended, if one closed it.
    closed: ?u32,
};

/// Taken from the marker that opened the region, which is the only argument
/// that cannot disagree with itself.
///
/// A span is a byte offset into the file that produced it, and a tree may hold
/// several -- a module's own files, and the library beside them. Given text and
/// an offset, nothing says which file they belong to, and a node from another
/// one compares against them as though it were in this text. That is not merely
/// a wrong answer: a node whose offsets happen to lie past the region extends
/// it, which lets the next one extend it again, and the fixpoint below never
/// reaches one. So the file, its text and the offset all come from the one
/// token, and every node read here is held to that file.
/// Where every node of a tree begins and ends, and where every closing marker
/// sits, both in the order a region grows through them.
///
/// A region reaches past any node that begins inside it and ends past it, and
/// `regionSpan` found those by reading every declaration, statement and
/// expression of the program to a fixpoint -- and found its closing marker by
/// reading every token. Both ran once per marker, so a file of m markers paid m
/// times its own size.
///
/// Sorted by where they begin, the nodes a region can reach are a run of this,
/// and one walk of that run is the whole fixpoint: reaching only ever moves the
/// end forward, and a node admitted by a longer reach sits later in the order,
/// so a single pass that carries the furthest end it has seen settles it.
pub const Extents = struct {
    /// Nodes by where they begin, within a file.
    nodes: []Node,
    /// The `on` markers, by token, in order.
    closers: []TokenTag,

    const Node = struct {
        file: FileId,
        opens: u32,
        closes: u32,
    };

    const TokenTag = struct {
        file: FileId,
        at: TokenId,
        /// Where the marker's comment ends, which is where its line does.
        span_end: u32,
    };

    pub fn build(gpa: std.mem.Allocator, ast: *const Ast) !Extents {
        var nodes: std.ArrayList(Node) = .empty;
        errdefer nodes.deinit(gpa);

        const tags = ast.tokens.items(.tag);
        const spans = ast.tokens.items(.span);

        for (0..ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            try note(gpa, &nodes, tags, spans, ast.fileOfDecl(d), ast.declTokens(d));
        }
        for (0..ast.stmtCount()) |i| {
            const st = StmtId.at(@intCast(i));
            try note(gpa, &nodes, tags, spans, ast.fileOfStmt(st), ast.stmtTokens(st));
        }
        for (0..ast.exprCount()) |i| {
            const e = ExprId.at(@intCast(i));
            try note(gpa, &nodes, tags, spans, ast.fileOfExpr(e), ast.exprTokens(e));
        }

        std.mem.sortUnstable(Node, nodes.items, {}, opensBefore);

        var closers: std.ArrayList(TokenTag) = .empty;
        errdefer closers.deinit(gpa);
        for (tags, spans, 0..) |tag, span, i| {
            const at = TokenId.at(@intCast(i));
            const part = ast.partOf(at);
            if (tag != .comment or markerAt(part.source, span) != .on) continue;
            try closers.append(gpa, .{ .file = part.file, .at = at, .span_end = span.end });
        }

        return .{ .nodes = try nodes.toOwnedSlice(gpa), .closers = try closers.toOwnedSlice(gpa) };
    }

    /// A node's own extent, with the comments trailing it left out -- which is
    /// what `extendOver` trimmed, because a comment after a node is not part of
    /// what would be lost by skipping it.
    fn note(
        gpa: std.mem.Allocator,
        nodes: *std.ArrayList(Node),
        tags: []const token.Tag,
        spans: []const Span,
        file: FileId,
        range: token.TokenRange,
    ) !void {
        if (range.start.index() >= spans.len) return;
        var last = @min(range.end.index(), @as(u32, @intCast(tags.len)));
        while (last > range.start.index() and tags[last - 1] == .comment) last -= 1;
        if (last == range.start.index()) return;
        try nodes.append(gpa, .{
            .file = file,
            .opens = spans[range.start.index()].start,
            .closes = spans[last - 1].end,
        });
    }

    fn opensBefore(_: void, a: Node, b: Node) bool {
        const x = @intFromEnum(a.file);
        const y = @intFromEnum(b.file);
        return if (x == y) a.opens < b.opens else x < y;
    }

    pub fn deinit(self: *Extents, gpa: std.mem.Allocator) void {
        gpa.free(self.nodes);
        gpa.free(self.closers);
    }

    /// Where the first `on` marker after `from` in this file ends, or null.
    fn closerAfter(self: *const Extents, file: FileId, from: u32) ?u32 {
        for (self.closers) |c| {
            if (c.file != file) continue;
            if (c.span_end <= from) continue;
            return c.span_end;
        }
        return null;
    }

    /// How far a region opened at `from` reaches, having started at `to`.
    fn reach(self: *const Extents, file: FileId, text: []const u8, from: u32, start: u32) u32 {
        var to = start;
        var i: usize = self.lowerBound(file, from);
        while (i < self.nodes.len) : (i += 1) {
            const n = self.nodes[i];
            if (n.file != file) break;
            if (n.opens >= to) break;
            // Begins inside the region and ends past it. A node that began
            // before the region contains it rather than being cut by it, and is
            // left alone.
            if (to < n.closes) to = Printer.lineEnd(text, n.closes);
        }
        return to;
    }

    fn lowerBound(self: *const Extents, file: FileId, at: u32) usize {
        var lo: usize = 0;
        var hi: usize = self.nodes.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const n = self.nodes[mid];
            const before = if (n.file == file) n.opens < at else @intFromEnum(n.file) < @intFromEnum(file);
            if (before) lo = mid + 1 else hi = mid;
        }
        return lo;
    }
};

pub fn regionSpan(ast: *const Ast, extents: *const Extents, opened_at: TokenId) Region {
    const part = ast.partOf(opened_at);
    const text = part.source;
    const from = ast.tokens.items(.span)[opened_at.index()].end;

    const closed: ?u32 = if (extents.closerAfter(part.file, from)) |end|
        Printer.lineEnd(text, end)
    else
        null;

    // Extended over any node that begins inside the region and continues past
    // it. The walk steps over a node beginning inside a region, so such a node
    // would be skipped whole and everything of it the copy did not reach --
    // an `impl` member's body, a match arm, a declaration -- would be gone.
    //
    // Only that shape. A node containing the region entirely is not extended
    // over: the region sits inside it and ends where it says it does, which is
    // what stops a marker in an enum's payload swallowing the enum.
    const to = extents.reach(part.file, text, from, closed orelse @intCast(text.len));
    return .{ .end = to, .closed = closed };
}

/// Where a closing marker sat that its region had to reach past, if any.
///
/// Said out loud rather than left silent: the author wrote `on`, it did not
/// take effect, and everything to the end of the enclosing declaration stays
/// unformatted. The output is correct either way, so this is a remark and not
/// a refusal.
fn swallowedMarker(ast: *const Ast, extents: *const Extents) ?u32 {
    const tags = ast.tokens.items(.tag);
    const spans = ast.tokens.items(.span);
    for (tags, spans, 0..) |tag, span, i| {
        const at = TokenId.at(@intCast(i));
        if (tag != .comment or markerAt(ast.partOf(at).source, span) != .off) continue;
        const region = regionSpan(ast, extents, at);
        const closed = region.closed orelse continue;
        if (region.end > closed) return closed;
    }
    return null;
}

/// How far a region must reach to cover this node, or null where it need not.
///
/// A node beginning inside the region and ending past it is the shape that
/// loses source, because the walk skips a node that begins inside one.
fn extendOver(
    ast: *const Ast,
    text: []const u8,
    range: token.TokenRange,
    from: u32,
    to: u32,
) ?u32 {
    const tags = ast.tokens.items(.tag);
    const spans = ast.tokens.items(.span);
    if (range.start.index() >= spans.len) return null;

    var last = @min(range.end.index(), @as(u32, @intCast(tags.len)));
    while (last > range.start.index() and tags[last - 1] == .comment) last -= 1;
    if (last == range.start.index()) return null;

    const opens = spans[range.start.index()].start;
    const closes = spans[last - 1].end;
    // Begins inside the region and ends past it. A node that began before the
    // region contains it rather than being cut by it, and is left alone.
    if (from <= opens and opens < to and to < closes) return Printer.lineEnd(text, closes);
    return null;
}

/// A comment's text, without whatever trails it.
///
/// A comment token runs to the end of its line, so on CRLF source its text
/// ends in a carriage return. The formatter writes LF and no trailing
/// whitespace, so the trim happens where the text is written rather than
/// leaving every caller to remember.
fn writtenComment(text: []const u8, span: Span) []const u8 {
    return std.mem.trimEnd(u8, span.slice(text), " \t\r");
}

/// Whether only whitespace precedes this offset on its source line.
fn ownsLine(text: []const u8, at: u32) bool {
    for (text[Printer.lineStart(text, at)..at]) |ch| {
        if (ch != ' ' and ch != '\t') return false;
    }
    return true;
}

/// What a comment means as a hatch marker, in one place.
///
/// A marker is a marker only on a line of its own, so this asks both what the
/// comment says and where it sits. Anything that must route around a region --
/// the printer, and the perturbation that checks the printer -- asks this
/// rather than restating the vocabulary, because two statements of one rule is
/// how they come to disagree.
pub fn markerAt(text: []const u8, comment: Span) Marker {
    if (!ownsLine(text, comment.start)) return .none;
    return Printer.markerKind(comment.slice(text));
}

pub fn formatAlloc(gpa: std.mem.Allocator, ast: *const Ast) std.mem.Allocator.Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    format(gpa, ast, &out.writer) catch return error.OutOfMemory;
    return out.written();
}

/// One text laid out again, and what a caller must know before writing the
/// result anywhere.
pub const Formatting = struct {
    /// The canonical text, or null where the result must not be used.
    text: ?[]const u8,
    /// Where an `on` marker sits that does not close the region it appears
    /// in, or null where none does. Correct output, but not what the author
    /// asked for: their `on` did not take effect.
    swallowed_marker: ?u32 = null,
};

/// Formats one file's text, or refuses it.
///
/// fmt parses and stops. A file that does not typecheck still formats, which
/// is what makes format-on-save usable while a program is being written; a
/// file that does not parse is refused, because an error node has no faithful
/// printing and writing one would destroy source.
///
/// One routine, because there are three callers -- a path on the command
/// line, a buffer on standard input, and an editor asking a language server
/// to lay a document out. Each of them writes the result over somebody's
/// file, so a copy of this that forgot one of the refusals is a copy that
/// destroys source on the route it forgot.
///
/// The refusal is reported through the sink rather than returned as a string:
/// it names the tokens that would have moved, so it is a message that scales
/// with the input, and the sink is where such a message is cut.
///
/// Tokenises and parses each of the input and output once. Shape, comment and
/// token preservation checks share those trees and their lossless tokens.
pub fn formatSource(
    gpa: std.mem.Allocator,
    source: *const Source,
    file: FileId,
    sink: *Sink,
) !Formatting {
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, source, file, sink, &interner);
    var ast = try parse(gpa, source, file, tokens, sink);
    if (sink.hasErrors()) return .{ .text = null };

    var indexes = try Indexes.build(gpa, &ast);
    defer indexes.deinit(gpa);
    var out: std.Io.Writer.Allocating = .init(gpa);
    try formatIndexed(gpa, &ast, &indexes, .none, DeclarationSelection.all(ast.declCount()), &out.writer);
    const formatted = out.written();
    // Found before the refusal below, because a caller that reports it
    // reports it either way: a region that did not reopen is the author's
    // mistake whether or not the result was usable.
    const marker = swallowedMarker(&ast, &indexes.extents);

    if (try refusalReason(gpa, &ast, formatted)) |why| {
        try sink.add(.{
            .severity = .err,
            .message = try std.fmt.allocPrint(gpa, "refusing to format {s}: {s}", .{ source.path, why }),
        });
        return .{ .text = null, .swallowed_marker = marker };
    }
    return .{ .text = formatted, .swallowed_marker = marker };
}

/// Renders one declaration, with a pass's annotations written into it.
///
/// A monomorphised program writes one declaration several times, once per
/// instantiation, so this cannot be a walk of the file: it starts at the
/// declaration's own first token, which is what stops every comment above it
/// being flushed again with each copy.
/// What printing reads about the tree, rather than about the declaration.
///
/// Both are the whole program -- one groups every declaration by where it
/// sits, the other records where every node begins and ends and sorts them --
/// and neither depends on which declaration is being written. A monomorphised
/// program writes one declaration once per instantiation, so building them
/// inside the write made a dump cost the program for every item in it, sort
/// and all. Built once by whoever is doing the writing.
pub const Indexes = struct {
    decls: DeclIndex,
    extents: Extents,

    pub fn build(gpa: std.mem.Allocator, ast: *const Ast) !Indexes {
        var decls = try DeclIndex.build(gpa, ast);
        errdefer decls.deinit(gpa);
        const extents = try Extents.build(gpa, ast);
        return .{ .decls = decls, .extents = extents };
    }

    pub fn deinit(self: *Indexes, gpa: std.mem.Allocator) void {
        self.decls.deinit(gpa);
        self.extents.deinit(gpa);
    }
};

pub fn formatDecl(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    indexes: *const Indexes,
    notes: Notes,
    d: DeclId,
    w: *std.Io.Writer,
) Error!void {
    var p: Printer = .{
        .gpa = gpa,
        .ast = ast,
        .decls = &indexes.decls,
        .extents = &indexes.extents,
        .text = ast.parts[0].source,
        .file = ast.parts[0].file,
        .notes = notes,
        .cursor = ast.declTokens(d).start.index(),
        .w = w,
    };
    defer p.chain_links.deinit(gpa);
    defer p.chain.deinit(gpa);
    try p.writeDecl(d);
}

/// Renders one generated closure body as the concrete function lowering made.
pub fn formatClosure(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    indexes: *const Indexes,
    notes: Notes,
    body: ExprId,
    name: []const u8,
    params: anytype,
    param_names: []const []const u8,
    param_types: []const []const u8,
    param_defaults: []const ?[]const u8,
    result: []const u8,
    w: *std.Io.Writer,
) Error!void {
    try w.print("fn {s}(", .{name});
    for (params, 0..) |param, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("{s} {s}: {s}", .{ @tagName(param.convention), param_names[i], param_types[i] });
        if (param_defaults[i]) |default| try w.print(" = {s}", .{default});
    }
    // A closure returning `()` is written without a result.
    if (std.mem.eql(u8, result, "()")) try w.writeAll(") ") else try w.print(") -> {s} ", .{result});

    const part = ast.partOf(ast.exprTokens(body).start);
    var p: Printer = .{
        .gpa = gpa,
        .ast = ast,
        .decls = &indexes.decls,
        .extents = &indexes.extents,
        .text = part.source,
        .file = part.file,
        .notes = notes,
        .cursor = ast.exprTokens(body).start.index(),
        .w = w,
    };
    defer p.chain_links.deinit(gpa);
    defer p.chain.deinit(gpa);
    if (ast.exprTag(body) == .block) {
        p.at_line_start = false;
        try p.writeExpr(body);
        return;
    }

    try w.writeAll("{\n");
    p.indent = 1;
    try p.writeExpr(body);
    // A multi-line literal ends its own last line.
    if (!p.at_line_start) try p.newline();
    try w.writeAll("}");
}

const Printer = struct {
    gpa: std.mem.Allocator,
    ast: *const Ast,
    /// The declarations of the tree, by where they sit. A container's members
    /// are a run of it, where reading every declaration per container made
    /// printing cost the square of what the program declares.
    decls: *const DeclIndex,
    /// Where every node begins and ends, which is how far a hatch reaches.
    extents: *const Extents,
    /// The source the walk is currently reading.
    ///
    /// A span is a byte offset into the file that produced it, and a tree may
    /// hold several -- a module's own files, and the library beside them. So
    /// this follows the declaration being written rather than being chosen
    /// once, or a comment is copied out of whichever file happened to be
    /// first and the output is a mangling of two programs.
    text: []const u8,
    /// Which file `text` is. The identity, not the bytes: `copied_to` is an
    /// offset into one file and means nothing in another, so what decides to
    /// reset it has to be what decides which file this is -- which is the
    /// `FileId` a part carries, and is what `regionSpan` in this same module
    /// already compares.
    file: FileId,
    notes: Notes = .none,
    /// Source declarations this walk writes.
    selection: DeclarationSelection = .all(0),
    w: *std.Io.Writer,
    indent: u32 = 0,
    /// Indentation is written lazily, immediately before a line's first byte,
    /// so a line with nothing on it carries no trailing whitespace and needs no
    /// pass to strip any.
    /// Spaces written but not yet committed to a line. See `write`.
    pending_spaces: u32 = 0,
    at_line_start: bool = true,
    /// Whether the line just ended was itself empty, so that two things which
    /// each want to separate with a blank line do not stack them.
    at_blank_line: bool = false,
    /// The next token not yet considered for flushing.
    ///
    /// It only ever advances, so a comment is emitted at most once and the walk
    /// can assert at the end that none was skipped. That is why no side table
    /// records where comments belong: token order already says.
    cursor: u32 = 0,
    /// One past the last byte copied verbatim by the escape hatch. A node
    /// beginning before this has already been written as the author wrote it,
    /// so the walk steps over it rather than formatting it a second time.
    copied_to: u32 = 0,
    /// The links of the chain being written, outermost first, and whether
    /// the author broke it across lines. A broken chain is written one
    /// selection per line, each line opening with its `.` and indented once
    /// below the line the chain starts on; a chain written inside one of its
    /// calls' arguments is a chain of its own.
    chain: std.ArrayList(ExprId) = .empty,
    /// The same links as a set, so asking whether an expression is one is a
    /// lookup rather than a walk of a chain that may be long.
    chain_links: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    chain_broken: bool = false,
    /// The selection that makes the chain's first link, which stays on the
    /// root's line where the author wrote it there: `fs.read_file(path)` or
    /// `values.as_slice()` reads as one name.
    chain_first: ExprId = .none,
    chain_first_joined: bool = false,
    /// Whether the chain's links have taken their level of indentation yet.
    /// It is taken at the first break, so the line the chain starts on keeps
    /// the indentation it already had.
    chain_indented: bool = false,

    /// How many newlines separate two byte offsets. Whitespace is the gap
    /// between adjacent spans, so this is a scan of that gap and needs no line
    /// index.
    fn newlinesBetween(self: *const Printer, from: u32, to: u32) usize {
        if (to <= from) return 0;
        return std.mem.count(u8, self.text[from..to], "\n");
    }

    /// Where the last token the cursor passed ended.
    fn consumedEnd(self: *const Printer) u32 {
        if (self.cursor == 0) return 0;
        return self.ast.tokens.items(.span)[self.cursor - 1].end;
    }

    /// Emits every comment before `upto` and leaves the cursor there.
    ///
    /// A comment beginning on the same source line as the token before it
    /// trails the current output line; every other comment takes its own line
    /// at the current indentation. The author's column is discarded: a comment
    /// describes the code beside it, and once that code has moved the original
    /// column means nothing.
    fn flushCommentsBefore(self: *Printer, upto: TokenId) Error!void {
        const tags = self.ast.tokens.items(.tag);
        const spans = self.ast.tokens.items(.span);
        const limit = @min(upto.index(), @as(u32, @intCast(tags.len)));

        while (self.cursor < limit) : (self.cursor += 1) {
            if (tags[self.cursor] != .comment) continue;

            const span = spans[self.cursor];
            const gap = self.newlinesBetween(self.consumedEnd(), span.start);

            // A marker reaches the hatch only at a boundary -- a place a
            // statement could begin. Anywhere else the words are a comment,
            // which is what lets an unbalanced one need no diagnostic.
            if (markerAt(self.text, span) == .off and self.notes.omit_derive_traits.len == 0) {
                if (!self.at_line_start) try self.newline();
                if (gap > 1 and !self.at_blank_line) try self.newline();
                try self.writeRegion();
                // `writeRegion` left the cursor past the region, so the outer
                // loop's increment would step over the token after it.
                if (self.cursor >= limit) return;
                self.cursor -= 1;
                continue;
            }

            if (gap == 0 and !self.at_line_start) {
                try self.write(" ");
                try self.write(writtenComment(self.text, span));
                try self.newline();
                continue;
            }
            if (!self.at_line_start) try self.newline();
            if (gap > 1 and !self.at_blank_line) try self.newline();
            try self.write(writtenComment(self.text, span));
            try self.newline();
        }
    }

    const marker_off = "// linea fmt: off";
    // Kept beside the Printer's own use so the two cannot describe different
    // comments; `markerAt` is what anything outside this file asks.
    const marker_on = "// linea fmt: on";

    /// Whether a comment is a hatch marker. Trailing spaces are ignored so an
    /// invisible one at end of line cannot silently disable the hatch.
    fn markerKind(text: []const u8) Marker {
        const t = std.mem.trimEnd(u8, text, " \t\r");
        if (std.mem.eql(u8, t, marker_off)) return .off;
        if (std.mem.eql(u8, t, marker_on)) return .on;
        return .none;
    }

    /// Copies from the `off` marker's line through the line holding the
    /// matching `on`, byte for byte, and leaves the cursor past it.
    ///
    /// An unclosed region runs to end of file, so whole-file opt-out falls out
    /// rather than needing syntax of its own, and nothing here can be an error.
    fn writeRegion(self: *Printer) Error!void {
        const tags = self.ast.tokens.items(.tag);
        const spans = self.ast.tokens.items(.span);

        const from = lineStart(self.text, spans[self.cursor].start);

        const to = regionEnd(self.ast, self.extents, TokenId.at(self.cursor));

        // Written past the indentation machinery: the region carries its own
        // leading whitespace, which is what copying it byte for byte means.
        try self.w.writeAll(self.text[from..to]);
        // Written past the layer, so the layer's state is restored from what
        // was actually copied rather than assumed. Setting one of the three and
        // leaving the others stale is what put a second blank line after a
        // region that closes mid-file.
        self.at_line_start = to > 0 and self.text[to - 1] == '\n';
        self.at_blank_line = false;
        self.pending_spaces = 0;
        self.copied_to = to;

        while (self.cursor < tags.len and spans[self.cursor].start < to) : (self.cursor += 1) {}
    }

    /// Whether a node was already written verbatim by the hatch.
    fn alreadyCopied(self: *const Printer, start: TokenId) bool {
        const spans = self.ast.tokens.items(.span);
        if (start.index() >= spans.len) return false;
        return spans[start.index()].start < self.copied_to;
    }

    fn lineStart(text: []const u8, at: u32) u32 {
        if (std.mem.lastIndexOfScalar(u8, text[0..at], '\n')) |nl| return @intCast(nl + 1);
        return 0;
    }

    /// One past the newline ending the line `at` falls on, so the copied region
    /// is always a whole number of lines.
    fn lineEnd(text: []const u8, at: u32) u32 {
        if (std.mem.indexOfScalarPos(u8, text, at, '\n')) |nl| return @intCast(nl + 1);
        return @intCast(text.len);
    }

    /// Emits a comment the author left on the line just written, before that
    /// line ends. The cursor must already be past what was written, which is
    /// what `flushCommentsBefore(range.end)` establishes.
    fn flushTrailing(self: *Printer) Error!void {
        const tags = self.ast.tokens.items(.tag);
        const spans = self.ast.tokens.items(.span);
        while (self.cursor < tags.len and tags[self.cursor] == .comment) {
            if (self.newlinesBetween(self.consumedEnd(), spans[self.cursor].start) != 0) return;
            try self.write(" ");
            try self.write(writtenComment(self.text, spans[self.cursor]));
            self.cursor += 1;
        }
    }

    /// Ends a line, having first caught up to everything `written` covers and
    /// emitted any comment sitting on that line.
    fn endLine(self: *Printer, written: token.TokenRange) Error!void {
        try self.flushCommentsBefore(written.end);
        try self.flushTrailing();
        // A `//` runs to end of line, so emitting one has already ended it.
        if (!self.at_line_start) try self.newline();
    }

    /// The token just past what separates an element from the next: the comma,
    /// or the delimiter closing the list. Variants and fields carry no range of
    /// their own, so theirs is found by scanning from the name they start with.
    fn elementEnd(self: *const Printer, from: TokenId) TokenId {
        const tags = self.ast.tokens.items(.tag);
        var depth: u32 = 0;
        var i = from.index();
        while (i < tags.len) : (i += 1) {
            if (tags[i] == .comma and depth == 0) return TokenId.at(i + 1);
            switch (tags[i].nesting()) {
                1 => depth += 1,
                -1 => {
                    if (depth == 0) return TokenId.at(i);
                    depth -= 1;
                },
                else => {},
            }
        }
        return TokenId.at(@intCast(tags.len));
    }

    /// Whether a comment stands between what has been written and `upto`.
    fn commentBefore(self: *const Printer, upto: TokenId) bool {
        const tags = self.ast.tokens.items(.tag);
        const limit = @min(upto.index(), @as(u32, @intCast(tags.len)));
        var at = self.cursor;
        while (at < limit) : (at += 1) {
            if (tags[at] == .comment) return true;
        }
        return false;
    }

    /// Whether the author left a blank line before `upto`, once any comments in
    /// between have been emitted.
    fn blankBefore(self: *const Printer, upto: TokenId) bool {
        const spans = self.ast.tokens.items(.span);
        if (upto.index() >= spans.len) return false;
        return self.newlinesBetween(self.consumedEnd(), spans[upto.index()].start) > 1;
    }

    /// Whether the author left a blank line between `after` and the token
    /// that follows it.
    fn blankAfter(self: *const Printer, after: TokenId) bool {
        const spans = self.ast.tokens.items(.span);
        if (after.index() + 1 >= spans.len) return false;
        return self.newlinesBetween(spans[after.index()].end, spans[after.index() + 1].start) > 1;
    }

    /// Whether the hatch has copied the rest of the file.
    ///
    /// A region with no `on` ends at EOF, so the document is complete and the
    /// brace the walk would close it with is already inside the copied text.
    /// The walk skips that brace, and this stops the line-ending that would
    /// have followed it -- there is no line left to end.
    fn copiedToEnd(self: *const Printer) bool {
        return self.copied_to >= self.text.len;
    }

    /// Reads from the file a token belongs to, from here on.
    ///
    /// Crossing into another file resets what has been copied verbatim: the
    /// escape hatch records a byte offset, and an offset into one file says
    /// nothing about another.
    fn enterFileOf(self: *Printer, t: TokenId) Error!void {
        const part = self.ast.partOf(t);
        if (part.file == self.file) return;
        self.file = part.file;
        self.text = part.source;
        self.copied_to = 0;
    }

    /// A token's text, or what a pass settled it stands for.
    fn textOf(self: *const Printer, t: TokenId) []const u8 {
        const noted = Notes.at(self.notes.tokens, t.index());
        return if (noted.len > 0) noted else self.ast.tokenText(t);
    }

    fn write(self: *Printer, bytes: []const u8) Error!void {
        // Once the hatch has copied to the end of the file the document is
        // complete, and anything the walk still has queued is a second copy of
        // text that is not there twice. Muting only the line-ending left the
        // text itself to be appended after EOF.
        if (bytes.len == 0 or self.copiedToEnd()) return;

        // A trailing space is held rather than written, the way indentation is,
        // because whether it belongs is not known until something follows it.
        // Where a newline comes next -- an operator carrying an expression onto
        // the following line, with a comment flushed in between -- it is
        // dropped, and the line does not end in whitespace.
        const body = std.mem.trimEnd(u8, bytes, " ");
        if (body.len == 0) {
            self.pending_spaces += @intCast(bytes.len);
            return;
        }
        try self.writeVerbatim(body);
        self.pending_spaces = @intCast(bytes.len - body.len);
    }

    /// Writes bytes exactly, trailing spaces included, after the line's
    /// indentation and any spaces held for it. For text whose every byte is
    /// the program's, such as a line of a multi-line literal.
    fn writeVerbatim(self: *Printer, bytes: []const u8) Error!void {
        if (bytes.len == 0 or self.copiedToEnd()) return;
        if (self.at_line_start) {
            // The indentation places a line's first byte, so a space held for
            // it is dropped. One is held when a line ends early, as after a
            // multi-line literal, and the delimiter written next was to have
            // followed it on the same line.
            self.pending_spaces = 0;
            try self.w.splatByteAll(' ', self.indent * indent_width);
            self.at_line_start = false;
        }
        try self.w.splatByteAll(' ', self.pending_spaces);
        self.pending_spaces = 0;
        self.at_blank_line = false;
        try self.w.writeAll(bytes);
    }

    fn newline(self: *Printer) Error!void {
        if (self.copiedToEnd()) return;
        self.pending_spaces = 0;
        try self.w.writeByte('\n');
        self.at_blank_line = self.at_line_start;
        self.at_line_start = true;
    }

    fn writeProgram(self: *Printer) Error!void {
        var first = true;
        var previous_kind: node.Decl.Tag = .import_;
        var selected = self.selection.iterator();
        var last: ?DeclId = null;
        while (selected.next()) |d| {
            if (selected.skipped_modules or (last == null and d.index() != 0) or
                (last != null and d.index() != last.?.index() + 1))
                self.cursor = self.ast.partOf(self.ast.declTokens(d).start).token_start;
            last = d;
            // A member of an `impl` lies inside its block's extent and is
            // written there. Emitting it here as well would write it twice.
            if (self.ast.declOwner(d) != TokenId.none) continue;
            // One blank line between declarations, whatever the author wrote.
            // Vertical space is preserved where it groups statements; between
            // declarations it is structure rather than grouping.
            const at = self.ast.declTokens(d).start;
            // The separator comes before the comments, not after them: a
            // comment block describes the declaration below it, and a blank
            // line between the two would divide what belongs together.
            //
            // A declaration that is one line and lists -- an import, a
            // re-export, an alias -- sits with another of its own kind. A blank line
            // between declarations is structure, but a run of them is one
            // piece of structure rather than several, and spacing it out
            // makes the head of a file mostly empty. The prelude is where
            // that shows: it is a manifest, and a manifest is a list.
            //
            // Of its own kind, so a blank line still stands between the two
            // runs. What a module imports and what it publishes are two lists.
            //
            // One carrying a comment is not a bare entry. The comment
            // describes the declaration below it, and run against the entry
            // above it reads as describing that one instead -- so it takes the
            // separator, which is what puts the comment with what it is about.
            const kind = self.ast.declTag(d);
            const listed = (kind == .import_ or kind == .use_ or kind == .alias) and
                !self.commentBefore(at);
            // Not stacked on a blank line something else already left -- a
            // hatch region ending at top level is the way that happens.
            if (!first and !self.at_blank_line and
                !(listed and kind == previous_kind)) try self.newline();
            first = false;
            previous_kind = kind;
            // Before the flush, not after it: the comments above a declaration
            // are in that declaration's file, and slicing them out of the one
            // the walk was reading interleaves two programs.
            try self.enterFileOf(at);
            // Flushed before the check, because it is the flush that finds an
            // `off` marker and copies the region the check then reports.
            try self.flushCommentsBefore(at);
            if (self.alreadyCopied(at)) continue;
            try self.writeDecl(d);
        }

        if (last == null) switch (self.selection) {
            .range => {},
            .modules => |modules| {
                for (modules) |module| {
                    if (module.library) continue;
                    for (module.files) |file| {
                        const part = self.ast.partOfFile(file) orelse continue;
                        self.cursor = part.token_start;
                        try self.enterFileOf(.at(part.token_start));
                        try self.flushCommentsBefore(.at(part.token_end));
                    }
                }
                return;
            },
        };

        // Trailing comments belong to the run this walk wrote, which is not
        // always the whole token array: a compilation carries the library
        // beside the program, and its tokens are nobody's trailing comments.
        const tags = self.ast.tokens.items(.tag);
        const stop: u32 = if (last == null)
            @intCast(tags.len)
        else
            self.ast.declTokens(last.?).end.index();
        const end = TokenId.at(stop);
        for (tags[self.cursor..stop]) |t| {
            if (t != .comment) continue;
            // Comments after the last declaration. They belong to the file
            // rather than to anything in it, so they sit apart from it -- but
            // only where there is something to sit apart from: a file of
            // nothing but comments would otherwise open with a blank line.
            if (!first) try self.newline();
            break;
        }
        try self.flushCommentsBefore(end);

        // The cursor only advances, so reaching the end proves no comment was
        // skipped. Losslessness is a property of the walk rather than something
        // a test has to go looking for.
        for (tags[self.cursor..stop]) |t| std.debug.assert(t != .comment);
    }

    fn writeDecl(self: *Printer, d: DeclId) Error!void {
        try self.enterFileOf(self.ast.declTokens(d).start);
        try self.flushCommentsBefore(self.ast.declTokens(d).start);
        try self.writeAttributes(d);
        const name = self.ast.declName(d);
        if (name != .none and self.alreadyCopied(name)) return;
        switch (self.ast.declTag(d)) {
            .function => try self.writeCallable(d, "fn "),
            .projection => try self.writeCallable(d, "proj "),
            .traversal_ => try self.writeTraversal(d),
            .constant => try self.writeConstant(d),
            .enum_ => try self.writeEnum(d),
            .struct_ => try self.writeStruct(d),
            .import_ => try self.writeImport(d),
            .use_ => try self.writeUse(d),
            .impl_ => try self.writeImpl(d),
            .template_impl => try self.writeTemplateImpl(d),
            .derive_impl => try self.writeDeriveImpl(d),
            .trait_ => try self.writeTrait(d),
            .associated_type => try self.writeAssociatedType(d),
            .newtype => try self.writeNewtype(d),
            .alias => try self.writeAlias(d),
            // Already diagnosed; fmt refuses any file holding one.
            .err => unreachable,
        }
    }

    fn keepsDeriveTrait(self: *const Printer, index: u32) bool {
        return index >= self.notes.omit_derive_traits.len or !self.notes.omit_derive_traits[index];
    }

    fn retainedAttributeTraits(self: *const Printer, item: node.AttributeItem) usize {
        var count: usize = 0;
        for (item.derive_traits.start..item.derive_traits.end) |index| {
            if (self.keepsDeriveTrait(@intCast(index))) count += 1;
        }
        return count;
    }

    fn keepsAttribute(self: *const Printer, item: node.AttributeItem) bool {
        return item.kind != .derive or self.retainedAttributeTraits(item) != 0;
    }

    /// Written groups preserve their order and grouping. Only the caller's
    /// selected trait mask can remove a request during source materialization.
    fn writeAttributes(self: *Printer, d: DeclId) Error!void {
        for (self.ast.declAttributeGroups(d)) |group| {
            try self.flushCommentsBefore(group.at);
            if (self.alreadyCopied(group.at)) continue;
            const items = self.ast.attributeItems(group);
            var count: usize = 0;
            var blocked = false;
            for (items) |item| {
                if (!self.keepsAttribute(item)) continue;
                count += 1;
                if (item.kind == .derive) {
                    const open = self.firstAt(item.name, .l_paren);
                    blocked = blocked or self.hasTrailingComma(self.bracketRange(open));
                }
            }
            if (count == 0) {
                try self.endLine(group.tokens);
                continue;
            }
            try self.write("@");
            if (group.open == .none) {
                try self.writeAttribute(items[0]);
            } else {
                try self.flushCommentsBefore(group.open);
                const l = try self.openList(self.bracketRange(group.open), count, "(", ")", "", blocked);
                var emitted: usize = 0;
                for (items) |item| {
                    try self.flushCommentsBefore(item.name);
                    if (self.alreadyCopied(item.name)) continue;
                    if (!self.keepsAttribute(item)) {
                        try self.flushCommentsBefore(item.tokens.end);
                        continue;
                    }
                    try self.writeAttribute(item);
                    emitted += 1;
                    try self.afterElement(l, emitted == count, .{
                        .start = item.tokens.start,
                        .end = self.elementEnd(item.name),
                    });
                }
                try self.closeList(l, count);
            }
            try self.endLine(group.tokens);
        }
    }

    fn writeAttribute(self: *Printer, item: node.AttributeItem) Error!void {
        try self.flushCommentsBefore(item.name);
        if (self.alreadyCopied(item.name)) return;
        try self.write(self.ast.tokenText(item.name));
        if (item.kind != .derive) return;
        const count = self.retainedAttributeTraits(item);
        const open = self.firstAt(item.name, .l_paren);
        try self.flushCommentsBefore(open);
        const l = try self.openList(self.bracketRange(open), count, "(", ")", "", false);
        var emitted: usize = 0;
        for (item.derive_traits.start..item.derive_traits.end) |index| {
            const trait = self.ast.derive_traits[index];
            try self.flushCommentsBefore(trait.tokens.start);
            if (self.alreadyCopied(trait.ref.name)) continue;
            if (!self.keepsDeriveTrait(@intCast(index))) {
                try self.flushCommentsBefore(trait.tokens.end);
                continue;
            }
            try self.writeTraitRef(trait.ref);
            emitted += 1;
            try self.afterElement(l, emitted == count, .{
                .start = trait.tokens.start,
                .end = self.elementEnd(trait.ref.name),
            });
        }
        try self.closeList(l, count);
    }

    /// The elements and dots of a path, and nothing between them.
    ///
    /// A comment may sit inside one, and concatenating every token in the
    /// range wrote it into the middle of the path -- so the `//` swallowed the
    /// rest of the line and the declaration no longer parsed. It stays pending
    /// and is written where a pending comment goes, which is somewhere the
    /// program still means what it did.
    fn writePath(self: *Printer, path: token.TokenRange) Error!void {
        var run = self.ast.runOf(path);
        while (run.next()) |id| try self.write(self.ast.tokenText(id));
    }

    /// One past a declaration written on a single line, including the `;` the
    /// formatter drops.
    ///
    /// The cursor has to reach past the terminator for a comment after it to
    /// count as sitting on the line just written; stopping at the last token
    /// emitted left that comment pending, and it surfaced above the next
    /// declaration.
    fn pastTerminator(self: *const Printer, end: TokenId) TokenId {
        const tags = self.ast.tokens.items(.tag);
        if (end.index() >= tags.len or tags[end.index()] != .semicolon) return end;
        return TokenId.at(end.index() + 1);
    }

    /// `pub use m.Name;`. A re-export exists for another module to reach, so
    /// its visibility is the whole point of it and is written here.
    fn writeUse(self: *Printer, d: DeclId) Error!void {
        // A comment inside the path belongs to this declaration, so it is
        // written above it rather than left pending -- pending, it surfaced
        // above whatever came next and read as documenting that instead.
        const path = self.ast.declPath(d);
        try self.flushCommentsBefore(path.end);

        try self.writeModifiers(d);
        try self.write("use ");
        try self.writePath(path);
        try self.endLine(.{ .start = path.start, .end = self.pastTerminator(path.end) });
    }

    fn writeImport(self: *Printer, d: DeclId) Error!void {
        const path = self.ast.declPath(d);
        const alias = self.ast.declName(d);
        // An alias is recorded as the declaration's name; without one the name
        // is the last element of the path, which the path below already writes.
        const renamed = alias != TokenId.none and !self.inRange(alias, path);
        // Before everything the line writes, rather than before the path
        // alone. The alias sits past the path's end, so a comment between `as`
        // and it is inside the line and was first seen while ending one -- and
        // a comment first seen there is placed after the line it was written
        // inside, which moves it one declaration down every time the file is
        // formatted.
        try self.flushCommentsBefore(if (renamed) alias else path.end);

        try self.writeModifiers(d);
        try self.write("import ");
        try self.writePath(path);
        var written = path.end;
        if (renamed) {
            try self.write(" as ");
            try self.write(self.ast.tokenText(alias));
            written = TokenId.at(alias.index() + 1);
        }
        try self.endLine(.{ .start = path.start, .end = self.pastTerminator(written) });
    }

    fn inRange(_: *const Printer, t: TokenId, r: token.TokenRange) bool {
        return t.index() >= r.start.index() and t.index() < r.end.index();
    }

    fn writeEnum(self: *Printer, d: DeclId) Error!void {
        try self.writeModifiers(d);
        try self.write("enum ");
        try self.write(self.declName(d));
        try self.writeTypeParams(d);
        try self.writeWhereClause(d);
        if (!self.at_line_start) try self.write(" ");

        const variants = self.ast.declVariants(d);
        const l = try self.openList(self.ast.declTokens(d), variants.len, "{", "}", " ", false);
        for (variants, 0..) |v, i| {
            // A variant carries no expression, so nothing else flushes ahead
            // of it: without this a comment above one is written after it and
            // comes to describe the variant below.
            try self.flushCommentsBefore(v.name);
            if (self.alreadyCopied(v.name)) continue;
            try self.write(self.ast.tokenText(v.name));
            const carried = self.ast.variantFields(v);
            if (carried.len > 0) {
                // The payload is a comma-driven list too, so a variant written
                // across lines keeps its shape.
                const open = self.firstAt(v.name, .l_paren);
                const pl = try self.openList(self.bracketRange(open), carried.len, "(", ")", "", false);
                for (carried, 0..) |f, j| {
                    try self.flushCommentsBefore(f.written.at);
                    if (self.alreadyCopied(f.written.at)) continue;
                    try self.writeWrittenType(f.written);
                    try self.afterElement(pl, j + 1 == carried.len, .{
                        .start = f.written.at,
                        .end = if (f.type_end != .none) f.type_end else self.elementEnd(f.written.at),
                    });
                }
                try self.closeList(pl, carried.len);
            }
            try self.afterElement(l, i + 1 == variants.len, .{
                .start = v.name,
                .end = self.elementEnd(v.name),
            });
        }
        try self.closeList(l, variants.len);
        try self.newline();
    }

    fn writeStruct(self: *Printer, d: DeclId) Error!void {
        try self.writeModifiers(d);
        try self.write("struct ");
        try self.write(self.declName(d));
        try self.writeTypeParams(d);
        try self.writeWhereClause(d);
        if (!self.at_line_start) try self.write(" ");

        const fields = self.ast.declFields(d);
        const l = try self.openList(self.ast.declTokens(d), fields.len, "{", "}", " ", false);
        for (fields, 0..) |f, i| {
            // As for a variant: a field has no expression of its own, so this
            // is the only place a comment above it can be written first.
            try self.flushCommentsBefore(f.name);
            if (self.alreadyCopied(f.name)) continue;
            try self.write(self.ast.tokenText(f.name));
            try self.write(": ");
            try self.writeWrittenType(f.written);
            try self.afterElement(l, i + 1 == fields.len, .{
                .start = f.name,
                .end = self.elementEnd(f.name),
            });
        }
        try self.closeList(l, fields.len);
        try self.newline();
    }

    /// An `impl` groups what a type can do. Its members are separate
    /// declarations whose extent lies inside its own, which is how they are
    /// found: nesting is a fact about source position.
    fn writeImpl(self: *Printer, d: DeclId) Error!void {
        if (self.ast.declIsDefault(d)) try self.write("default ");
        try self.write("impl");
        // Against the keyword, the way a function's are: the parameters belong
        // to the implementation and not to the head they are applied to.
        try self.writeTypeParams(d);
        try self.write(" ");
        // The trait first where there is one: `impl Trait for Type` names what
        // is satisfied before what satisfies it.
        const t = self.ast.declTrait(d);
        if (t != TokenId.none) {
            try self.writeTraitRef(self.ast.declTraitRef(d));
            try self.write(" for ");
        }
        try self.writeWrittenType(self.ast.declHead(d));
        try self.writeWhereClause(d);
        if (self.ast.declVia(d) != .none) {
            try self.writeDelegation(d);
            return;
        }
        try self.writeMembers(d);
    }

    fn writeTemplateImpl(self: *Printer, d: DeclId) Error!void {
        try self.write("template impl");
        try self.writeTypeParams(d);
        try self.write(" ");
        try self.writeTraitRef(self.ast.declTraitRef(d));
        const requirements = self.ast.templateRequirements(d);
        if (requirements.len == 0) {
            try self.writeWhereClause(d);
        } else {
            try self.writeTemplateRequirements(d, requirements);
        }
        if (self.ast.declVia(d) != .none) {
            try self.writeDelegation(d);
            return;
        }
        try self.writeMembers(d);
    }

    fn writeTemplateRequirements(
        self: *Printer,
        d: DeclId,
        requirements: []const node.TemplateRequirement,
    ) Error!void {
        const where_at = self.ast.declWhereToken(d);
        try self.flushCommentsBefore(where_at);
        if (!self.at_line_start) try self.write(" ");

        const range = self.whereClauseRange(d);
        const trailing_comma = self.whereHasTrailingComma(range);
        const broken = trailing_comma or self.holdsComment(range) or
            self.newlinesBetween(
                self.ast.tokenSpan(where_at).end,
                self.ast.tokenSpan(requirements[requirements.len - 1].reflect).start,
            ) > 0;

        try self.write("where");
        if (broken) self.indent += 1;
        for (requirements, 0..) |requirement, i| {
            try self.flushCommentsBefore(requirement.reflect);
            if (self.alreadyCopied(requirement.reflect)) continue;

            if (broken) {
                if (!self.at_line_start) try self.newline();
            } else if (i == 0) {
                try self.write(" ");
            } else {
                try self.write(", ");
            }
            switch (requirement.kind) {
                .components => {
                    try self.write("reflect.components");
                    try self.writeBounds(self.ast.boundsIn(requirement.bounds));
                },
                .derived_supertraits => try self.write("reflect.supertraits: derived"),
                .target => {
                    try self.write("reflect.target: ");
                    try self.write(requirement.target_shape.spelling());
                },
            }

            if (!broken) continue;
            const last = i + 1 == requirements.len;
            if (!last or trailing_comma) try self.write(",");
            try self.endLine(.{
                .start = requirement.reflect,
                .end = if (last) range.end else requirements[i + 1].reflect,
            });
        }
        if (broken) self.indent -= 1;
    }

    fn writeDeriveImpl(self: *Printer, d: DeclId) Error!void {
        try self.write("derive");
        try self.writeTypeParams(d);
        try self.write(" ");
        const traits = self.ast.deriveTraits(d);
        if (self.ast.deriveIsGrouped(d)) {
            const open = self.ast.deriveGroupOpen(d);
            const close = self.ast.deriveGroupClose(d);
            const range: token.TokenRange = if (close == .none)
                .{ .start = open, .end = self.ast.declTokens(d).end }
            else
                .{ .start = open, .end = TokenId.at(close.index() + 1) };
            const l = try self.openList(range, traits.len, "(", ")", "", false);
            for (traits, 0..) |trait, i| {
                try self.flushCommentsBefore(trait.ref.name);
                if (self.alreadyCopied(trait.ref.name)) continue;
                try self.writeTraitRef(trait.ref);
                try self.afterElement(l, i + 1 == traits.len, .{
                    .start = trait.tokens.start,
                    .end = self.elementEnd(trait.ref.name),
                });
            }
            try self.closeList(l, traits.len);
        } else if (traits.len > 0) {
            try self.writeTraitRef(traits[0].ref);
        }
        try self.write(" for ");
        try self.writeWrittenType(self.ast.declHead(d));
        try self.writeWhereClause(d);
        try self.newline();
    }

    /// `trait Name { … }`. Its signatures are members owned by it, so the walk
    /// that writes an `impl`'s members writes these too.
    fn writeTrait(self: *Printer, d: DeclId) Error!void {
        try self.writeModifiers(d);
        try self.write("trait ");
        try self.write(self.ast.tokenText(self.ast.declName(d)));
        try self.writeTypeParams(d);
        try self.writeBounds(self.ast.declBounds(d));
        try self.writeWhereClause(d);
        try self.writeMembers(d);
    }

    /// `: A + B` after a name, and nothing where none was written.
    ///
    /// One writer for every position a bound is written in -- a type
    /// parameter, a trait's declared type, and a trait's own -- because a
    /// bound is one form and one reader parses all three. A second spelling of
    /// it here would be a form the parser accepts and the formatter rewrites.
    fn writeBounds(self: *Printer, bounds: []const node.TraitBound) Error!void {
        for (bounds, 0..) |b, i| {
            try self.write(if (i == 0) ": " else " + ");
            switch (b.kind) {
                .named => {
                    try self.writeTraitRef(b.named);
                },
                .callable => try self.writeWrittenType(self.ast.callableRef(b.callable)),
            }
        }
    }

    fn writeTraitRef(self: *Printer, ref: node.TraitRef) Error!void {
        if (ref.path.len() == 0) {
            try self.write(self.ast.tokenText(ref.name));
        } else {
            try self.writePath(ref.path);
        }
        try self.writeTypeArgs(ref.args, ref.name);
    }

    /// The braced list of declarations a container owns, one per line.
    ///
    /// An empty group stays flat, on the reading an empty field list already
    /// gets: a brace opening a line of its own says a member follows it, and a
    /// trait that promises something and declares nothing has none. A comment
    /// written inside is content the group is broken around.
    fn writeMembers(self: *Printer, d: DeclId) Error!void {
        const extent = self.ast.declTokens(d);
        if (self.holdsNoMember(d, extent) and !self.holdsComment(self.interiorOf(extent))) {
            if (!self.at_line_start) try self.write(" ");
            try self.write("{}");
            return self.newline();
        }

        if (!self.at_line_start) try self.write(" ");
        try self.write("{");
        try self.newline();
        self.indent += 1;
        var first = true;
        var above_is_dense = false;
        for (self.decls.within(extent)) |m| {
            if (m == d or self.ast.declOwner(m) == TokenId.none) continue;
            // Functions are separated from adjacent members before their
            // leading comments. Bodyless non-function members stay together.
            const is_dense = self.ast.declBody(m) == ExprId.none and
                self.ast.declTag(m) != .function;
            const dense = is_dense and above_is_dense;
            above_is_dense = is_dense;
            if (!first and !self.at_blank_line and !dense) try self.newline();
            try self.flushCommentsBefore(self.ast.declTokens(m).start);
            if (self.alreadyCopied(self.ast.declTokens(m).start)) {
                // A member the copy wrote is a member that was written, so the
                // one after it is separated from it. Left as the first, every
                // member after a hatch ran together with what the copy emitted.
                first = false;
                continue;
            }
            first = false;
            try self.writeDecl(m);
        }
        // A comment after the last member belongs to this `impl`. Without this
        // it is written after the brace and comes to describe whatever
        // declaration follows.
        const closer = TokenId.at(self.significantEnd(extent) - 1);
        try self.flushCommentsBefore(closer);
        self.indent -= 1;
        if (!self.alreadyCopied(closer)) try self.write("}");
        try self.newline();
    }

    /// Whether a container owns no declaration, asked of the same walk that
    /// writes them so the two cannot disagree about what a member is.
    fn holdsNoMember(self: *const Printer, d: DeclId, extent: token.TokenRange) bool {
        for (self.decls.within(extent)) |m| {
            if (m == d or self.ast.declOwner(m) == TokenId.none) continue;
            return false;
        }
        return true;
    }

    /// A constant preserves its optional written type.
    fn writeConstant(self: *Printer, d: DeclId) Error!void {
        try self.writeModifiers(d);
        try self.write("let ");
        try self.write(self.declName(d));
        if (self.ast.declReturnRef(d).wasWritten()) {
            try self.write(": ");
            try self.writeReturnType(d);
        }
        try self.write(" = ");
        try self.writeExpr(self.ast.declInit(d));
        try self.newline();
    }

    /// `trav positions = expression`, on one line.
    ///
    /// The optional receiver is an ordinary parameter list; the iterator's
    /// type comes from the expression a walk runs through.
    fn writeDelegation(self: *Printer, d: DeclId) Error!void {
        try self.flushCommentsBefore(self.ast.declVia(d));
        if (!self.at_line_start) try self.write(" ");
        try self.write("via");
        const target = self.ast.declDelegation(d);
        if (target != .none) {
            try self.flushCommentsBefore(target);
            if (!self.at_line_start) try self.write(" ");
            try self.write(self.ast.tokenText(target));
        }
        try self.endLine(self.bodylessRange(d));
    }

    fn writeTraversal(self: *Printer, d: DeclId) Error!void {
        try self.write("trav ");
        try self.write(self.declName(d));
        if (self.ast.declParams(d).len != 0) try self.writeParams(d);
        if (self.ast.declVia(d) != .none) {
            try self.writeDelegation(d);
            return;
        }
        try self.write(" = ");
        try self.writeExpr(self.ast.declInit(d));
        try self.newline();
    }

    /// `type Item`, and `type Item = UInt8` where something settles it.
    ///
    /// One line either way. What was settled is the type written on the
    /// declaration, so the absence of one is what tells the trait's side from
    /// the implementation's -- the same question the parser asked.
    fn writeAssociatedType(self: *Printer, d: DeclId) Error!void {
        try self.write("type ");
        try self.write(self.declName(d));
        try self.writeBounds(self.ast.declBounds(d));
        if (self.ast.declReturnRef(d).wasWritten()) {
            try self.write(" = ");
            try self.writeReturnType(d);
        }
        try self.newline();
    }

    /// `type Name = Base`, and `type Name = Base where it in lo..=hi`.
    ///
    /// The clause is its own unit: written on the head's line it takes one
    /// space on each side of `where`, and written on its own line it stays
    /// there, indented once under the head -- the grammar leaves room for the
    /// clause to grow without crowding the head, and the formatter honours
    /// whichever the author chose rather than collapsing one into the other.
    fn writeNewtype(self: *Printer, d: DeclId) Error!void {
        try self.writeModifiers(d);
        try self.write("type ");
        try self.write(self.declName(d));
        try self.write(" = ");
        try self.writeReturnType(d);

        if (self.ast.newtypeRefinement(d)) |r| {
            // The token just before `where` is the base type's last, however
            // many tokens the base took to write -- so this reads whether the
            // author's line break sits there without a second reader of what
            // a written type is.
            const prev = TokenId.at(r.at.index() - 1);
            const own_line = self.newlinesBetween(
                self.ast.tokenSpan(prev).end,
                self.ast.tokenSpan(r.at).start,
            ) > 0;
            if (own_line) {
                try self.newline();
                self.indent += 1;
                try self.write("where it in ");
            } else {
                try self.write(" where it in ");
            }
            try self.writeBound(r.lo());
            try self.write(if (r.inclusive) "..=" else "..");
            try self.writeBound(r.hi());
            if (own_line) self.indent -= 1;
        }
        try self.newline();
    }

    fn writeAlias(self: *Printer, d: DeclId) Error!void {
        try self.writeModifiers(d);
        try self.write("alias ");
        try self.write(self.declName(d));
        try self.writeTypeParams(d);
        try self.write(" = ");
        try self.writeReturnType(d);
        try self.newline();
    }

    /// One end of a refinement's range: the sign, where one was written, and
    /// the digits. A bound whose digits are absent was never read, and the
    /// clause it belongs to was already reported.
    fn writeBound(self: *Printer, b: node.Bound) Error!void {
        if (b.minus != TokenId.none) try self.write("-");
        if (b.digits != TokenId.none) try self.write(self.ast.tokenText(b.digits));
    }

    /// A function or a projection: the same header, told apart by the word it
    /// begins with. One printer, because the two write one grammar -- a second
    /// would print a parameter list two ways and agree until one of them was
    /// changed.
    fn writeCallable(self: *Printer, d: DeclId, word: []const u8) Error!void {
        try self.writeModifiers(d);
        // Before `fn`, which is where it was written and where the parser
        // reads it. Dropping it printed a declaration that no longer names a
        // symbol, and the formatted file stopped parsing.
        if (self.ast.declIsExtern(d)) try self.write("extern ");
        try self.write(word);
        try self.write(self.declName(d));
        try self.writeTypeParams(d);
        try self.writeParams(d);
        if (self.ast.declReturnRef(d).wasWritten()) {
            try self.write(" -> ");
            try self.writeReturnType(d);
        }
        try self.writeWhereClause(d);

        // A signature carries no body, so the line ends after its head and any
        // trailing clause. Nothing else distinguishes one: it is a function
        // declaration whose body is absent, which is what a trait declares.
        if (self.ast.declBody(d) == ExprId.none) {
            return self.endLine(self.bodylessRange(d));
        }

        if (!self.at_line_start) try self.write(" ");
        try self.writeBlock(self.ast.declBody(d));
        try self.newline();
    }

    fn writeContract(self: *Printer, contracts: []const node.Contract, start: usize) Error!usize {
        var i = start;
        const first = contracts[i];
        try self.write(@tagName(first.kind));
        try self.write("(");
        if (first.target.root != .none) {
            try self.write(".");
            try self.writePath(first.target.written);
            try self.write(": ");
        }
        if (first.kind == .retains) {
            try self.writePath(first.destination.written);
            try self.write(": ");
        }
        while (i < contracts.len and contracts[i].at == first.at) : (i += 1) {
            if (contracts[i].borrows_source) try self.write("borrow ");
            try self.writePath(contracts[i].source.written);
            if (i + 1 < contracts.len and contracts[i + 1].at == first.at) try self.write(", ");
        }
        try self.write(")");
        return i;
    }

    fn writeContracts(self: *Printer, contracts: []const node.Contract) Error!void {
        if (contracts.len == 0) return;
        const trailing_comma = contracts[contracts.len - 1].trailing_comma;
        const broken = trailing_comma != .none;
        try self.write(" where");
        if (broken) self.indent += 1;
        var i: usize = 0;
        while (i < contracts.len) {
            const at = contracts[i].at;
            try self.flushCommentsBefore(at);
            if (self.alreadyCopied(at)) {
                while (i < contracts.len and contracts[i].at == at) i += 1;
                continue;
            }
            if (broken) {
                if (!self.at_line_start) try self.newline();
            } else {
                try self.write(if (i == 0) " " else ", ");
            }
            i = try self.writeContract(contracts, i);
            if (broken) {
                try self.write(",");
                const end = if (i < contracts.len) contracts[i].at else TokenId.at(trailing_comma.index() + 1);
                try self.endLine(.{ .start = at, .end = end });
            }
        }
        if (broken) self.indent -= 1;
    }

    fn writeWhereClause(self: *Printer, d: DeclId) Error!void {
        const predicates = self.ast.declWherePredicates(d);
        const contracts = self.ast.declContracts(d);
        if (predicates.len == 0 and contracts.len == 0) return;

        const where_at = self.ast.declWhereToken(d);
        const previous = TokenId.at(where_at.index() - 1);
        const own_line = self.newlinesBetween(
            self.ast.tokenSpan(previous).end,
            self.ast.tokenSpan(where_at).start,
        ) > 0;
        try self.flushCommentsBefore(where_at);
        if (own_line and !self.at_line_start) try self.newline();
        if (!own_line and !self.at_line_start) try self.write(" ");

        const range = self.whereClauseRange(d);
        const trailing_comma = self.whereHasTrailingComma(range);
        const last_predicate = if (predicates.len == 0) TokenId.none else predicates[predicates.len - 1].subject.at;
        const last_contract = if (contracts.len == 0) TokenId.none else contracts[contracts.len - 1].at;
        const last_at = if (last_predicate == .none) last_contract else if (last_contract == .none) last_predicate else TokenId.at(@max(last_predicate.index(), last_contract.index()));
        const broken = trailing_comma or self.holdsComment(range) or
            self.newlinesBetween(
                self.ast.tokenSpan(where_at).end,
                self.ast.tokenSpan(last_at).start,
            ) > 0;

        try self.write("where");
        if (broken) self.indent += 1;
        var pi: usize = 0;
        var ci: usize = 0;
        var item: usize = 0;
        while (pi < predicates.len or ci < contracts.len) : (item += 1) {
            const is_contract = ci < contracts.len and (pi == predicates.len or contracts[ci].at.index() < predicates[pi].subject.at.index());
            const at = if (is_contract) contracts[ci].at else predicates[pi].subject.at;
            try self.flushCommentsBefore(at);
            if (self.alreadyCopied(at)) {
                if (is_contract) {
                    while (ci < contracts.len and contracts[ci].at == at) ci += 1;
                } else {
                    pi += 1;
                }
                continue;
            }
            if (broken) {
                if (!self.at_line_start) try self.newline();
            } else {
                try self.write(if (item == 0) " " else ", ");
            }
            if (is_contract) {
                ci = try self.writeContract(contracts, ci);
            } else {
                const predicate = predicates[pi];
                try self.writeWrittenType(predicate.subject);
                try self.writeBounds(self.ast.boundsIn(predicate.bounds));
                pi += 1;
            }
            if (!broken) continue;
            const last = pi == predicates.len and ci == contracts.len;
            if (!last or trailing_comma) try self.write(",");
            const next_at = if (pi == predicates.len) (if (ci == contracts.len) range.end else contracts[ci].at) else if (ci == contracts.len) predicates[pi].subject.at else TokenId.at(@min(predicates[pi].subject.at.index(), contracts[ci].at.index()));
            try self.endLine(.{ .start = at, .end = next_at });
        }
        if (broken) self.indent -= 1;
    }

    /// The where clause and any bodiless terminator, excluding a body.
    fn whereClauseRange(self: *const Printer, d: DeclId) token.TokenRange {
        const start = self.ast.declWhereToken(d);
        const tags = self.ast.tokens.items(.tag);
        const via = self.ast.declVia(d);
        const decl_end = if (via != .none) via.index() else self.ast.declTokens(d).end.index();
        var depth: u32 = 0;
        var i = start.index() + 1;
        while (i < decl_end and i < tags.len) : (i += 1) {
            if (depth == 0 and tags[i] == .l_brace) {
                return .{ .start = start, .end = TokenId.at(i) };
            }
            switch (tags[i].nesting()) {
                1 => depth += 1,
                -1 => if (depth > 0) {
                    depth -= 1;
                },
                else => {},
            }
        }
        const end = @min(decl_end, @as(u32, @intCast(tags.len)));
        return .{ .start = start, .end = self.sameLineCommentEnd(start, end) };
    }

    /// A bodyless declaration without comments that lead the next declaration.
    fn bodylessRange(self: *const Printer, d: DeclId) token.TokenRange {
        const range = self.ast.declTokens(d);
        const tags = self.ast.tokens.items(.tag);
        const spans = self.ast.tokens.items(.span);
        const end = @min(range.end.index(), @as(u32, @intCast(tags.len)));
        var comments = end;
        while (comments > range.start.index() and tags[comments - 1] == .comment) comments -= 1;
        if (comments == end or end >= tags.len or tags[end] == .eof or
            self.newlinesBetween(spans[end - 1].end, spans[end].start) > 1)
        {
            return .{ .start = range.start, .end = TokenId.at(end) };
        }
        return .{ .start = range.start, .end = self.sameLineCommentEnd(range.start, end) };
    }

    /// Excludes trailing comments except one sharing the preceding token's line.
    fn sameLineCommentEnd(self: *const Printer, start: TokenId, end: u32) TokenId {
        const tags = self.ast.tokens.items(.tag);
        var comments = end;
        while (comments > start.index() and tags[comments - 1] == .comment) comments -= 1;
        var own_end = comments;
        if (comments < end and comments > start.index()) {
            const spans = self.ast.tokens.items(.span);
            if (self.newlinesBetween(spans[comments - 1].end, spans[comments].start) == 0) {
                own_end += 1;
            }
        }
        return TokenId.at(own_end);
    }

    fn whereHasTrailingComma(self: *const Printer, range: token.TokenRange) bool {
        const tags = self.ast.tokens.items(.tag);
        var end = @min(range.end.index(), @as(u32, @intCast(tags.len)));
        while (end > range.start.index() and tags[end - 1] == .comment) end -= 1;
        if (end > range.start.index() and tags[end - 1] == .semicolon) end -= 1;
        return end > range.start.index() and tags[end - 1] == .comma;
    }

    /// The prefix a declaration was written with, in the order it is read.
    ///
    /// Every declaration form goes through this, including the ones the
    /// language refuses a modifier on: a modifier written where it says nothing
    /// is a diagnosed mistake rather than a token that stops existing, and the
    /// formatter reprints what was written. Rendering a word only where it is
    /// legal is how a file the language merely refuses becomes one the
    /// formatter cannot touch, since deleting a token makes the result a
    /// different program and the guard against that refuses the whole file.
    fn writeModifiers(self: *Printer, d: DeclId) Error!void {
        try self.writeVisibility(d);
        try self.writeIsExport(d);
        try self.writeIsTest(d);
    }

    /// Whether the declaration was written `test`, and whether that test was
    /// written to expect a trap. Reprinted wherever they were written,
    /// including on forms the language refuses, because the tokens still exist.
    fn writeIsTest(self: *Printer, d: DeclId) Error!void {
        if (!self.ast.declIsTest(d)) return;
        try self.write("test ");
        if (self.ast.declExpectsTrap(d)) try self.write("trap ");
    }

    /// How far a name reaches, where it reaches further than its own module.
    /// Opaque visibility is printed from its retained attribute syntax.
    fn writeVisibility(self: *Printer, d: DeclId) Error!void {
        try self.write(switch (self.ast.declVisibility(d)) {
            .private => "",
            .internal_ => "internal ",
            .pub_ => "pub ",
            .opaque_ => "",
        });
    }

    /// Whether the declaration was written `export`. Reprinted wherever it was
    /// written, including on the forms a later rule refuses it on, for the
    /// reason `writeIsTest` reprints `test`: the token exists in the source
    /// either way.
    fn writeIsExport(self: *Printer, d: DeclId) Error!void {
        try self.write(if (self.ast.declIsExport(d)) "export " else "");
    }

    fn writeReturnType(self: *Printer, d: DeclId) Error!void {
        // Array and unit types are written even though neither has a name.
        const ref = self.ast.declReturnRef(d);
        if (!ref.wasWritten()) return;
        // Between the arrow and the type, which is where it was written. It
        // marks the result rather than the declaration, so it is printed here
        // rather than with the modifiers.
        try self.writeWrittenType(ref);
    }

    /// `[T, E: Copyable + Weigh]`, the parameters a declaration introduces.
    ///
    /// A bound is written where the parameter is, so it travels with it: the
    /// list is the whole of what the declaration says about its parameters.
    /// A declaration's name, or the one an instantiation goes by.
    fn declName(self: *const Printer, d: DeclId) []const u8 {
        if (self.notes.name.len > 0) return self.notes.name;
        return self.ast.tokenText(self.ast.declName(d));
    }

    fn writeTypeParams(self: *Printer, d: DeclId) Error!void {
        if (!self.notes.type_params) return;
        const declared = self.ast.declTypeParams(d);
        if (declared.len == 0) return;

        const open = self.firstAt(self.ast.declTokens(d).start, .l_bracket);
        const l = try self.openList(self.bracketRange(open), declared.len, "[", "]", "", false);
        for (declared, 0..) |p, i| {
            // A comment written above a parameter belongs to that parameter.
            // Left pending, it surfaced at the next element's boundary instead
            // -- one slot later on every run, until it had walked out of the
            // brackets and into whatever followed.
            try self.flushCommentsBefore(p.name);

            // After the flush, because the flush is what copies a hatch: an
            // element the copy already wrote byte for byte would otherwise be
            // written a second time, putting it in the list twice.
            if (self.alreadyCopied(p.name)) continue;

            if (p.phantom) try self.write("phantom ");
            try self.write(self.ast.tokenText(p.name));
            try self.writeBounds(self.ast.boundsOf(p));
            if (p.default.wasWritten()) {
                try self.write(" = ");
                try self.writeWrittenType(p.default);
            }
            try self.afterElement(l, i + 1 == declared.len, .{
                .start = p.name,
                .end = self.elementEnd(p.name),
            });
        }
        try self.closeList(l, declared.len);
    }

    /// `[u8, Cell[T]]`, the arguments a written type carries.
    ///
    /// An argument is itself a written type, so this recurses: nesting is the
    /// only thing that distinguishes it from a flat list of names.
    /// A written type, in whichever form it was written. One printer, because
    /// a nested type and a top-level one are the same thing -- and a formatter
    /// that dropped a form would rewrite the programmer's source.
    fn writeWrittenType(self: *Printer, ref: node.TypeRef) Error!void {
        switch (ref.kind) {
            // `(A, B)`, laid out by its trailing comma as a parameter list
            // is, with a comment inside breaking it one component per line.
            .tuple => {
                const components = self.ast.typeArgs(ref.args);
                const l = try self.openList(self.bracketRange(ref.at), components.len, "(", ")", "", false);
                for (components, 0..) |component, i| {
                    try self.flushCommentsBefore(component.at);
                    if (self.alreadyCopied(component.at)) continue;
                    try self.writeWrittenType(component);
                    try self.afterElement(l, i + 1 == components.len, .{
                        .start = component.at,
                        .end = self.elementEnd(component.at),
                    });
                }
                try self.closeList(l, components.len);
            },
            .grouped => {
                try self.write("(");
                const args = self.ast.typeArgs(ref.args);
                if (args.len > 0) try self.writeWrittenType(args[0]);
                try self.write(")");
            },
            .borrow => {
                try self.write("borrow ");
                const args = self.ast.typeArgs(ref.args);
                if (args.len > 0) try self.writeWrittenType(args[0]);
            },
            .named => {
                // `()` is recorded as the token that opens it rather than as a
                // name, so its text is one paren and printing that leaves a
                // type that does not re-parse. Spelled out here, which is the
                // one place a written type is printed -- it used to be spelled
                // at the return, the only position that could hold one, and a
                // type argument became the second.
                if (ref.name != TokenId.none and self.ast.tokenTag(ref.name) == .l_paren) {
                    return self.write("()");
                }
                try self.write(self.textOf(ref.name));
                try self.writeTypeArgs(ref.args, ref.name);
            },
            .selection => {
                const settled = if (ref.name == .none) "" else Notes.at(self.notes.tokens, ref.name.index());
                if (settled.len > 0) return self.write(settled);
                try self.writeWrittenType(self.ast.selectionBase(ref));
                try self.write(".");
                try self.write(self.textOf(ref.name));
                try self.writeTypeArgs(ref.args, ref.name);
            },
            .array => {
                try self.write("[");
                const written = self.ast.typeArgs(ref.args);
                if (written.len != 0) try self.writeWrittenType(written[0]);
                try self.write("; ");
                if (ref.inferred_length != .none) {
                    try self.flushCommentsBefore(ref.inferred_length);
                    try self.write(self.textOf(ref.inferred_length));
                }
                if (ref.length != ExprId.none) try self.writeExpr(ref.length);
                try self.write("]");
            },
            .callable => {
                const callable = self.ast.callableType(ref);
                if (callable.invocation_token != .none) {
                    try self.write(@tagName(callable.invocation));
                    try self.write(" ");
                }
                const params = self.ast.params[callable.params.start..callable.params.end];
                const open = self.firstAt(ref.at, .l_paren);
                const l = try self.openList(self.bracketRange(open), params.len, "fn(", ")", "", false);
                for (params, 0..) |p, i| {
                    try self.flushCommentsBefore(p.name);
                    if (self.alreadyCopied(p.name)) continue;
                    switch (p.convention) {
                        .read => if (self.ast.paramSpellsConvention(p)) try self.write("read "),
                        .inout => try self.write("inout "),
                        .sink => try self.write("sink "),
                    }
                    try self.write(self.ast.tokenText(p.name));
                    try self.write(": ");
                    try self.writeWrittenType(p.written);
                    if (p.default != ExprId.none) {
                        try self.write(" = ");
                        try self.writeExpr(p.default);
                    }
                    try self.afterElement(l, i + 1 == params.len, .{
                        .start = p.name,
                        .end = self.elementEnd(p.name),
                    });
                }
                try self.closeList(l, params.len);
                if (callable.result.wasWritten()) {
                    try self.write(" -> ");
                    try self.writeWrittenType(callable.result);
                }
                try self.writeContracts(self.ast.contracts[callable.contracts.start..callable.contracts.end]);
            },
        }
    }

    /// The type arguments written after `after`, the name they apply to.
    fn writeTypeArgs(self: *Printer, args: node.TypeRefRange, after: TokenId) Error!void {
        if (!self.notes.type_args) return;
        const refs = self.ast.typeArgs(args);
        if (refs.len == 0) return;
        try self.writeTypeList(refs, self.firstAt(after, .l_bracket), false);
    }

    /// A bracketed list of written types opened at `open`. A trailing comma
    /// the author wrote is kept: the list stays on one line either way, and
    /// dropping a written token is a rewrite the formatter refuses to make.
    ///
    /// Before a call, where `comments_break` is set, a comment inside the
    /// brackets breaks the list one type per line, as it breaks a call's
    /// argument list, so the comment stays beside the type it was written by.
    /// A written type's arguments leave their comments to whatever follows.
    fn writeTypeList(self: *Printer, refs: []const node.TypeRef, open: TokenId, comments_break: bool) Error!void {
        const range = self.bracketRange(open);
        if (comments_break and self.holdsComment(self.interiorOf(range))) {
            const l = try self.openList(range, refs.len, "[", "]", "", true);
            for (refs, 0..) |r, i| {
                try self.flushCommentsBefore(r.at);
                try self.writeWrittenType(r);
                try self.afterElement(l, i + 1 == refs.len, .{ .start = r.at, .end = self.elementEnd(r.at) });
            }
            return self.closeList(l, refs.len);
        }
        const inside: token.TokenRange = .{ .start = TokenId.at(open.index() + 1), .end = TokenId.at(range.end.index() - 1) };
        try self.write("[");
        for (refs, 0..) |r, i| {
            if (i > 0) try self.write(", ");
            try self.writeWrittenType(r);
        }
        if (self.whereHasTrailingComma(inside)) try self.write(",");
        try self.write("]");
    }

    /// The range from a delimiter to its partner, inclusive.
    ///
    /// A parameter list and a variant's payload have no node of their own, so
    /// the range the layout rule reads has to be found from the bracket.
    fn bracketRange(self: *const Printer, open: TokenId) token.TokenRange {
        const tags = self.ast.tokens.items(.tag);
        var depth: u32 = 0;
        var i = open.index();
        while (i < tags.len) : (i += 1) {
            switch (tags[i].nesting()) {
                1 => depth += 1,
                -1 => {
                    // Cannot underflow: the scan starts on an opener, so depth
                    // is at least one before any closer is seen.
                    depth -= 1;
                    if (depth == 0) return .{ .start = open, .end = TokenId.at(i + 1) };
                },
                else => {},
            }
        }
        return .{ .start = open, .end = TokenId.at(@intCast(tags.len)) };
    }

    /// The first token with this tag at or after `from`.
    fn firstAt(self: *const Printer, from: TokenId, tag: token.Tag) TokenId {
        const tags = self.ast.tokens.items(.tag);
        var i = from.index();
        while (i < tags.len and tags[i] != tag) : (i += 1) {}
        return TokenId.at(@intCast(i));
    }

    fn writeParams(self: *Printer, d: DeclId) Error!void {
        const params = self.ast.declParams(d);
        // A parameter list is comma-driven like any other: the trailing comma
        // the author wrote breaks it, and deleting one would be a rewrite
        // rather than a layout choice.
        const open = self.firstAt(self.ast.declName(d), .l_paren);
        const l = try self.openList(self.bracketRange(open), params.len, "(", ")", "", false);
        for (params, 0..) |p, i| {
            try self.flushCommentsBefore(p.name);
            if (self.alreadyCopied(p.name)) continue;
            try self.writeParam(p, true);
            try self.afterElement(l, i + 1 == params.len, .{
                .start = p.name,
                .end = self.elementEnd(p.name),
            });
        }
        try self.closeList(l, params.len);
    }

    fn writeParam(self: *Printer, p: node.Param, require_annotation: bool) Error!void {
        switch (p.convention) {
            // `read` is what a parameter has unless it says otherwise, so
            // a parameter that says nothing already reads that way. Whether
            // the author wrote the word is a question about tokens rather
            // than about the convention, and fmt does not delete a word
            // someone chose to write -- dropping it would compile, which is
            // exactly what makes it the wrong kind of change.
            .read => if (self.ast.paramSpellsConvention(p)) try self.write("read "),
            .inout => try self.write("inout "),
            .sink => try self.write("sink "),
        }
        if (p.pattern != ExprId.none) try self.writeExpr(p.pattern) else try self.write(self.ast.tokenText(p.name));
        if (require_annotation or p.written.wasWritten()) {
            try self.write(": ");
            try self.writeWrittenType(p.written);
        }
        if (p.default != ExprId.none) {
            try self.write(" = ");
            try self.writeExpr(p.default);
        }
    }

    /// A block always breaks: one statement per line, closing brace on its own.
    /// An empty one stays flat, which is what lets an arm do nothing on a line.
    fn writeBlock(self: *Printer, e: ExprId) Error!void {
        const b = self.ast.blockOf(e);
        const stmts = self.ast.blockStmts(b);

        if (stmts.len == 0 and b.tail == ExprId.none) return self.write("{}");

        try self.write("{");
        try self.newline();
        self.indent += 1;
        var first = true;
        for (stmts, 0..) |s, i| {
            // The release a `defer let` schedules is written by the binding.
            if (self.ast.stmtTag(s) == .defer_release) continue;
            // A blank line the author put between statements is kept: grouping
            // inside a body is the one place vertical space carries meaning no
            // rule could reconstruct. One directly after `{` is dropped.
            try self.flushCommentsBefore(self.ast.stmtTokens(s).start);
            if (self.alreadyCopied(self.ast.stmtTokens(s).start)) continue;
            if (!first and !self.at_blank_line and
                self.blankBefore(self.ast.stmtTokens(s).start)) try self.newline();
            first = false;
            try self.writeStmt(s);
            // A separator the author wrote is kept where the line after it
            // opens with a token that could have continued this statement.
            // There the parser notes the ambiguity, and the `;` is the only
            // answer to it -- deleting one would leave a note nothing can
            // silence, and put it back on every save.
            if (self.separatorAnswersANote(stmts, i, b.tail)) try self.write(";");
            try self.endLine(self.ast.stmtTokens(s));
        }
        if (b.tail != ExprId.none) try self.flushCommentsBefore(self.ast.exprTokens(b.tail).start);
        if (b.tail != ExprId.none and !self.alreadyCopied(self.ast.exprTokens(b.tail).start)) {
            if (!first and self.blankBefore(self.ast.exprTokens(b.tail).start)) try self.newline();
            try self.writeExpr(b.tail);
            try self.endLine(self.ast.exprTokens(b.tail));
        }
        // Anything written between the last statement and the brace. A blank
        // line before `}` is dropped, so only comments reach here. The brace is
        // the range's last *significant* token: comments after the block lie
        // inside its range and belong to whatever follows, not in here.
        const closer = TokenId.at(self.significantEnd(self.ast.exprTokens(e)) - 1);
        try self.flushCommentsBefore(closer);
        self.indent -= 1;
        // An unclosed region runs to the end of the file, so the brace closing
        // this block is inside the text it copied. Writing a second one leaves
        // source that does not parse, in place, over source that did.
        if (!self.alreadyCopied(closer)) try self.write("}");
    }

    /// Whether the `;` after this statement is what silences `[S-Continuation]`.
    ///
    /// Both halves have to hold. The author must have written one -- the
    /// formatter deletes a separator but never invents one, so a note already
    /// in the source stays. And whatever follows must open a line the parser
    /// notes, as `Tag.opensAContinuation` decides: `-`, `()`, or `.` before
    /// anything but a capitalised name or `{`, each of which begins a
    /// statement and also continues an expression.
    fn separatorAnswersANote(
        self: *const Printer,
        stmts: []const StmtId,
        i: usize,
        tail: ExprId,
    ) bool {
        if (!self.followedBySemicolon(self.ast.stmtTokens(stmts[i]))) return false;
        var next = i + 1;
        while (next < stmts.len and self.ast.stmtTag(stmts[next]) == .defer_release) next += 1;
        if (next < stmts.len) {
            return self.opensWithContinuation(self.ast.stmtTokens(stmts[next]).start);
        }
        if (tail == ExprId.none) return false;
        return self.opensWithContinuation(self.ast.exprTokens(tail).start);
    }

    /// Whether a `;` terminated this statement.
    ///
    /// Where it sits depends on the statement. `parseLet` eats the separator
    /// and then takes its range, so a binding's range ends past its own `;`; a
    /// block's loop builds an expression statement's range from the expression,
    /// which ended before it. Reading only one of the two said every assignment
    /// carried no separator.
    fn followedBySemicolon(self: *const Printer, range: token.TokenRange) bool {
        const tags = self.ast.tokens.items(.tag);
        const end = self.significantEnd(range);
        if (end > range.start.index() and tags[end - 1] == .semicolon) return true;
        var i = end;
        while (i < tags.len and tags[i] == .comment) : (i += 1) {}
        return i < tags.len and tags[i] == .semicolon;
    }

    fn opensWithContinuation(self: *const Printer, at: TokenId) bool {
        const tags = self.ast.tokens.items(.tag);
        if (at.index() >= tags.len) return false;
        var next = at.index() + 1;
        while (next < tags.len and tags[next].isTrivia()) next += 1;
        if (next >= tags.len) return tags[at.index()].opensAContinuation(.eof, "");
        return tags[at.index()].opensAContinuation(tags[next], self.ast.tokenText(TokenId.at(@intCast(next))));
    }

    fn writeStmt(self: *Printer, s: StmtId) Error!void {
        try self.flushCommentsBefore(self.ast.stmtTokens(s).start);
        const d = self.ast.stmtData(s);
        switch (self.ast.stmtTag(s)) {
            .let_decl => {
                if (self.ast.stmtIsDeferredBinding(s)) try self.write("defer ");
                try self.write(if (self.ast.stmtIsMutable(s)) "var " else "let ");
                try self.write(self.ast.tokenText(d.name));
                if (d.annotation.wasWritten()) {
                    try self.write(": ");
                    try self.writeWrittenType(d.annotation);
                } else {
                    const inferred = Notes.at(self.notes.bindings, s.index());
                    if (inferred.len > 0) {
                        try self.write(": ");
                        try self.write(inferred);
                    }
                }
                try self.write(" = ");
                try self.writeExpr(d.init);
            },
            .let_destructure, .let_read_destructure => {
                if (self.ast.stmtTag(s) == .let_read_destructure) {
                    // A comment between `let` and `read` stays between them.
                    try self.write("let");
                    try self.flushCommentsBefore(self.firstAt(self.ast.stmtTokens(s).start, .keyword_read));
                    if (!self.at_line_start) try self.write(" ");
                    try self.write("read ");
                } else {
                    try self.write("let ");
                }
                try self.writeExpr(d.pattern);
                try self.write(" = ");
                try self.writeExpr(d.init);
            },
            // No separator, whatever the statement is. The printer follows
            // every statement with a newline, and a newline ends a statement --
            // so a `;` would say what the line break already says. Two
            // statements sharing a line do not survive formatting either way:
            // the printer gives each its own.
            .expr_stmt => try self.writeExpr(d.init),
            .defer_stmt => {
                // A `defer` the parser could not read an expression for
                // carries none, and the file still has to print: the frontend
                // returns a complete tree from source that is broken, and a
                // formatter reads such source most of the time it runs.
                if (d.init == ExprId.none) {
                    try self.write("defer");
                } else {
                    try self.write("defer ");
                    try self.writeExpr(d.init);
                }
            },
            // Written by the binding it follows, which `writeBlock` reaches
            // first and prints as `defer let`.
            .defer_release => unreachable,
            // Already diagnosed; fmt refuses any file holding one.
            .err => unreachable,
        }
    }

    /// A list's chosen layout, returned rather than held on the printer so a
    /// list nested inside another element cannot disturb its parent's.
    const List = struct {
        broken: bool,
        close: []const u8,
        /// What separates the delimiters from the elements when flat. A braced
        /// list reads with it and a parenthesised one without.
        pad: []const u8,
        /// The token that closes the list, so `closeList` can tell whether the
        /// hatch already copied it.
        closer: TokenId,
    };

    /// One past the last non-comment token in a range.
    ///
    /// A node's range ends at the next significant token, so a comment written
    /// after the node lies inside the node's own range. Anything reasoning
    /// about where a node really ends has to step back over those.
    fn significantEnd(self: *const Printer, r: token.TokenRange) u32 {
        const tags = self.ast.tokens.items(.tag);
        var i = @min(r.end.index(), @as(u32, @intCast(tags.len)));
        while (i > r.start.index() and tags[i - 1] == .comment) i -= 1;
        return i;
    }

    /// The tokens a list holds, without its own delimiters.
    ///
    /// Found by matching the delimiter that closes the run backwards rather
    /// than by taking the first one seen: `match S { x: 1 } { … }` opens a
    /// brace in its scrutinee, and a forward scan would take that one.
    fn interiorOf(self: *const Printer, range: token.TokenRange) token.TokenRange {
        const tags = self.ast.tokens.items(.tag);
        const first = range.start.index();
        const close = self.significantEnd(range) - 1;
        if (close <= first) return .{ .start = range.start, .end = range.start };

        var depth: u32 = 0;
        var i = close;
        while (true) : (i -= 1) {
            // Backwards, so a closer opens the count and an opener closes it.
            switch (tags[i].nesting()) {
                -1 => depth += 1,
                1 => {
                    depth -= 1;
                    if (depth == 0) {
                        return .{ .start = TokenId.at(i + 1), .end = TokenId.at(close) };
                    }
                },
                else => {},
            }
            if (i == first) break;
        }
        return .{ .start = range.start, .end = TokenId.at(close) };
    }

    /// Whether a run of tokens holds a comment, which runs to end of line and
    /// so cannot share one.
    fn holdsComment(self: *const Printer, range: token.TokenRange) bool {
        const tags = self.ast.tokens.items(.tag);
        var i = range.start.index();
        while (i < range.end.index()) : (i += 1) {
            if (tags[i] == .comment) return true;
        }
        return false;
    }

    /// Whether an expression holds a block with anything in it.
    ///
    /// Asked of the tree rather than of the tokens: a brace is not a block, and
    /// a struct literal writes one too. Counting braces would break every list
    /// holding a nested literal, which is the common way to write one.
    fn holdsNonEmptyBlock(self: *const Printer, e: ExprId) bool {
        if (e == ExprId.none) return false;
        const tag = self.ast.exprTag(e);
        if (tag == .block) {
            const b = self.ast.blockOf(e);
            return self.ast.blockStmts(b).len > 0 or b.tail != ExprId.none;
        }
        return switch (tag.payload()) {
            .none => false,
            .unary => self.holdsNonEmptyBlock(self.ast.unaryOperand(e)),
            .binary => blk: {
                const b = self.ast.binary(e);
                break :blk self.holdsNonEmptyBlock(b.lhs) or self.holdsNonEmptyBlock(b.rhs);
            },
            .conditional => blk: {
                const c = self.ast.conditional(e);
                break :blk self.holdsNonEmptyBlock(c.cond) or
                    self.holdsNonEmptyBlock(c.then) or
                    self.holdsNonEmptyBlock(c.otherwise);
            },
            .call => blk: {
                const c = self.ast.call(e);
                if (self.holdsNonEmptyBlock(c.callee)) break :blk true;
                for (c.args) |a| {
                    if (self.holdsNonEmptyBlock(a)) break :blk true;
                }
                break :blk false;
            },
            .interpolation => blk: {
                for (self.ast.interpolation(e).pieces) |piece| {
                    if (self.holdsNonEmptyBlock(piece)) break :blk true;
                }
                break :blk false;
            },
            .range => blk: {
                const ends = self.ast.rangeEnds(e);
                break :blk self.holdsNonEmptyBlock(ends.lhs) or self.holdsNonEmptyBlock(ends.rhs);
            },
            .lambda => blk: {
                const lambda = self.ast.lambda(e);
                for (lambda.captures) |capture| {
                    if (self.holdsNonEmptyBlock(capture.source)) break :blk true;
                }
                for (lambda.params) |p| {
                    if (self.holdsNonEmptyBlock(p.default)) break :blk true;
                }
                break :blk self.holdsNonEmptyBlock(lambda.body);
            },
            .block => unreachable,
        };
    }

    /// Whether the author asked for the broken form: a comma immediately
    /// before the delimiter that closes the run.
    fn hasTrailingComma(self: *const Printer, range: token.TokenRange) bool {
        const tags = self.ast.tokens.items(.tag);
        const end = self.significantEnd(range);
        if (end < 2 or end > tags.len) return false;
        return tags[end - 2] == .comma;
    }

    /// Opens a delimited list and decides its layout.
    ///
    /// The trailing comma decides, but only among layouts that are possible:
    /// an element that cannot be rendered flat forces the break whatever the
    /// commas say.
    fn openList(
        self: *Printer,
        range: token.TokenRange,
        count: usize,
        open: []const u8,
        close: []const u8,
        pad: []const u8,
        blocked: bool,
    ) Error!List {
        try self.write(open);
        const broken = count > 0 and
            (self.holdsComment(self.interiorOf(range)) or
                blocked or
                self.hasTrailingComma(range));
        if (broken) {
            try self.newline();
            self.indent += 1;
        } else if (count > 0) {
            try self.write(pad);
        }
        return .{
            .broken = broken,
            .close = close,
            .pad = pad,
            .closer = TokenId.at(self.significantEnd(range) - 1),
        };
    }

    /// Whenever a list breaks, its trailing comma is written -- including where
    /// the author omitted it. That is what makes the output a fixed point: the
    /// next run reads an ordinary comma-driven list and re-derives nothing
    /// about why it broke.
    fn afterElement(self: *Printer, l: List, last: bool, written: token.TokenRange) Error!void {
        if (l.broken) {
            try self.write(",");
            try self.endLine(written);
            return;
        }
        if (!last) try self.write(", ");
    }

    fn closeList(self: *Printer, l: List, count: usize) Error!void {
        try self.flushCommentsBefore(l.closer);
        // An unclosed hatch copies to the end of the file, so there is nothing
        // left for a closing delimiter to close -- writing one appended stray
        // text after the whole copied program.
        if (self.copied_to >= self.text.len) return;
        if (l.broken) {
            self.indent -= 1;
        } else if (count > 0) {
            try self.write(l.pad);
        }
        // A region running past the closer already copied it. Writing it again
        // produces a delimiter the source does not have.
        if (self.alreadyCopied(l.closer)) return;
        try self.write(l.close);
    }

    /// How a list's elements are written. Every one of these arrives through
    /// the same `call` payload, so the shape has to come from the tag.
    const Kind = enum {
        /// `f(a, b)` -- one expression per element, parenthesised.
        call,
        /// `match s { p => b, .. }` -- pattern and body, paired.
        match,
        /// `T { f = v, .. }` or `.{ f = v, .. }` -- field name and value,
        /// paired. A named literal carries its written type in the AST side table.
        literal,
        /// `S { f: b, .. }` -- field name and binder, paired.
        pattern,
        /// `[a, b, c]` -- one value each, and no callee. The type comes from
        /// context exactly as a braced literal's does.
        array,
        /// `(a, b)` -- a tuple literal or pattern, one component each and no
        /// callee.
        tuple,

        fn of(tag: node.Expr.Tag) Kind {
            return switch (tag) {
                .call => .call,
                .match_, .match_read => .match,
                .struct_literal => .literal,
                .struct_pattern => .pattern,
                .array_literal => .array,
                .tuple_literal, .tuple_pattern => .tuple,
                else => unreachable,
            };
        }

        /// How many entries one element occupies.
        fn stride(self: Kind) usize {
            return switch (self) {
                .call, .array, .tuple => 1,
                .match, .literal, .pattern => 2,
            };
        }
    };

    /// A call, a match, or a braced literal or pattern.
    fn writeList(self: *Printer, e: ExprId) Error!void {
        const tag = self.ast.exprTag(e);
        const kind = Kind.of(tag);
        const c = self.ast.call(e);
        const stride = kind.stride();

        const note = Notes.at(self.notes.exprs, e.index());
        const receiver = if (kind == .call) self.notedReceiver(e) else ExprId.none;

        switch (kind) {
            .call => {
                if (self.ast.callMarked(e) and receiver == ExprId.none) try self.write("&");
                try self.writeExpr(c.callee);
                // `Name?(e)` -- the unproven construction form -- keeps its
                // `?` here, the one place a call prints its callee back.
                if (self.ast.callFallible(e)) try self.write("?");
                try self.write(note);
            },
            .match => {
                try self.write(if (tag == .match_read) "match read " else "match ");
                try self.writeExpr(c.callee);
                try self.write(" ");
            },
            .literal => {
                if (self.ast.structLiteralHead(e)) |head| {
                    try self.writeWrittenType(head);
                    try self.write(note);
                    try self.write(" ");
                } else if (note.len > 0) {
                    // The type a contextual literal settled to, written as
                    // the named literal that builds it.
                    try self.write(note);
                    try self.write(" ");
                } else {
                    try self.write(".");
                }
            },
            .pattern => {
                if (c.callee != ExprId.none) {
                    try self.writeExpr(c.callee);
                    try self.write(" ");
                }
            },
            // Nothing before the bracket: the elements are the whole of it.
            .array, .tuple => {},
        }

        const parens = kind == .call or kind == .tuple;
        const brackets = kind == .array;
        // A literal's `..base` is one more element, written after its fields.
        const base = if (kind == .literal) self.ast.structLiteralBase(e) else null;
        const count = (c.args.len + stride - 1) / stride + @intFromBool(receiver != ExprId.none) + @intFromBool(base != null);
        var blocked = false;
        for (c.args) |a| {
            if (self.holdsNonEmptyBlock(a)) blocked = true;
        }
        if (base) |b| {
            if (self.holdsNonEmptyBlock(b)) blocked = true;
        }
        // A comment inside a braced literal's or pattern's head is written
        // after its opening brace, where only a broken list gives it a line of
        // its own. Breaking on the first run is what the second run would do.
        if (kind == .literal or kind == .pattern) {
            const range = self.ast.exprTokens(e);
            if (self.holdsComment(.{ .start = range.start, .end = self.interiorOf(range).start })) blocked = true;
        }
        const l = try self.openList(
            self.ast.exprTokens(e),
            count,
            if (parens) "(" else if (brackets) "[" else "{",
            if (parens) ")" else if (brackets) "]" else "}",
            if (parens or brackets) "" else " ",
            blocked,
        );

        if (receiver != ExprId.none) {
            if (self.ast.callMarked(e)) try self.write("&");
            try self.writeExpr(receiver);
            try self.afterElement(l, c.args.len == 0, self.ast.exprTokens(receiver));
        }
        const names = self.ast.callNames(e);
        var i: usize = 0;
        while (i < c.args.len) : (i += stride) {
            try self.flushCommentsBefore(self.ast.exprTokens(c.args[i]).start);
            if (self.alreadyCopied(self.ast.exprTokens(c.args[i]).start)) continue;
            // A blank line the author left between two elements of a broken
            // list groups them, and is kept as one; one after the opening
            // delimiter is dropped, as one after a block's `{` is.
            if (l.broken and (i > 0 or receiver != ExprId.none) and !self.at_blank_line and
                self.blankBefore(self.ast.exprTokens(c.args[i]).start)) try self.newline();
            try self.writeElement(kind, c.args, names, i);
            const last_part = self.ast.exprTokens(c.args[i + stride - 1]);
            try self.afterElement(l, i + stride >= c.args.len and base == null, .{
                .start = last_part.start,
                .end = self.elementEnd(last_part.end),
            });
        }
        if (base) |b| {
            const written = self.ast.exprTokens(b);
            try self.flushCommentsBefore(written.start);
            if (!self.alreadyCopied(written.start)) {
                try self.write("..");
                try self.writeExpr(b);
                try self.afterElement(l, true, .{ .start = written.start, .end = self.elementEnd(written.end) });
            }
        }
        try self.closeList(l, count);
    }

    /// Writes a multi-line literal with each `\\` line on an output line of
    /// its own.
    ///
    /// When the literal opens its line, as a statement or a broken list's
    /// element does, its lines are written at that line's depth. Otherwise
    /// they are written one level deeper than the line holding what precedes
    /// the literal, whatever indentation the author gave each, so the literal
    /// reads as one block. A comment between that token and the literal does
    /// not change the depth. The first line stays where the author put it,
    /// beside the token before it or on a line of its own, because it cannot
    /// always move: after `return`, a line break ends the statement.
    ///
    /// Each line is written byte for byte, trailing spaces included, since
    /// every byte after `\\` is text. A line runs to the end of its source
    /// line, so whatever follows the literal is on a later line, and the
    /// literal ends the line it finishes on.
    fn writeStringLines(self: *Printer, e: ExprId, began_line: bool) Error!void {
        const range = self.ast.exprTokens(e);
        const tags = self.ast.tokens.items(.tag);
        const spans = self.ast.tokens.items(.span);
        const own_line = self.newlinesBetween(self.consumedEnd(), spans[range.start.index()].start) > 0;
        const deeper = !began_line;
        if (deeper) self.indent += 1;

        var i = range.start.index();
        while (i < range.end.index()) : (i += 1) {
            if (tags[i] != .string_line) continue;
            if (!self.at_line_start and (i != range.start.index() or own_line)) try self.newline();
            try self.writeVerbatim(self.ast.tokenText(TokenId.at(i)));
        }
        try self.newline();

        if (deeper) self.indent -= 1;
    }

    /// The receiver a postfix call passes first, where a note writes the
    /// call's callee as the operation it reaches; none otherwise, including
    /// wherever the callee is written as the source spells it.
    fn notedReceiver(self: *const Printer, e: ExprId) ExprId {
        if (e.index() >= self.notes.receivers.len) return ExprId.none;
        const receiver = self.notes.receivers[e.index()];
        if (receiver == ExprId.none) return ExprId.none;
        const callee = self.ast.call(e).callee;
        if (Notes.at(self.notes.tokens, self.ast.exprMain(callee).index()).len == 0) return ExprId.none;
        return receiver;
    }

    fn writeElement(self: *Printer, kind: Kind, args: []const ExprId, names: []const TokenId, i: usize) Error!void {
        switch (kind) {
            // A name prints only where one was written -- the formatter never
            // inserts or drops one, it renders what the tree already holds.
            .call => {
                if (i < names.len and names[i] != TokenId.none) {
                    try self.write(self.ast.tokenText(names[i]));
                    try self.write(": ");
                }
                try self.writeExpr(args[i]);
            },
            .array, .tuple => try self.writeExpr(args[i]),
            .match => {
                try self.writeExpr(args[i]);
                try self.write(" => ");
                try self.writeExpr(args[i + 1]);
            },
            .literal => {
                try self.writeExpr(args[i]);
                if (self.ast.fieldIsShorthand(args[i], args[i + 1])) return;
                try self.write(" = ");
                try self.writeExpr(args[i + 1]);
            },
            // `{ f }` binds a field to its own name and is recorded as the
            // field twice -- the *same* token twice, where `{ f: f }` is two
            // tokens that happen to read alike. Token identity is what tells
            // the two apart, so neither is rewritten into the other.
            .pattern => {
                try self.writeExpr(args[i]);
                if (self.ast.fieldIsShorthand(args[i], args[i + 1])) return;
                try self.write(": ");
                try self.writeExpr(args[i + 1]);
            },
        }
    }

    fn binaryOp(tag: node.Expr.Tag) ?[]const u8 {
        return switch (tag) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .rem => "%",
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .logical_and => "&&",
            .logical_or => "||",
            else => null,
        };
    }

    /// How an assignment is spelled. Not in `binaryOp`, because these are not
    /// operators on values and nothing that asks about precedence should find
    /// them there -- only the printing shape is shared.
    fn assignmentOp(tag: node.Expr.Tag) []const u8 {
        return switch (tag) {
            .assign => "=",
            .add_assign => "+=",
            .sub_assign => "-=",
            .mul_assign => "*=",
            .div_assign => "/=",
            .rem_assign => "%=",
            else => unreachable,
        };
    }

    fn writeExpr(self: *Printer, e: ExprId) Error!void {
        // Whether the expression opens its line, asked before a comment
        // written ahead of it can move the output onto a line of its own.
        const began_line = self.at_line_start;
        try self.flushCommentsBefore(self.ast.exprTokens(e).start);
        const tag = self.ast.exprTag(e);

        // The outermost link of a chain decides how the whole chain is laid
        // out: one selection per line where the author broke it anywhere.
        if (self.isChainLink(e) and !self.inChain(e)) {
            const mark = self.chain.items.len;
            const outer_broken = self.chain_broken;
            const outer_first = self.chain_first;
            const outer_first_joined = self.chain_first_joined;
            const outer_indented = self.chain_indented;
            var broken = false;
            var first: ExprId = .none;
            var first_joined = true;
            var link: ?ExprId = e;
            while (link) |at| : (link = self.chainReceiver(at)) {
                try self.chain.append(self.gpa, at);
                try self.chain_links.put(self.gpa, at, {});
                const selection = if (self.ast.exprTag(at) == .call) self.ast.call(at).callee else at;
                if (selection != at) {
                    try self.chain.append(self.gpa, selection);
                    try self.chain_links.put(self.gpa, selection, {});
                }
                // A break after the `.` breaks the chain as one before it does,
                // and the chain is written with the `.` opening the line.
                if (self.chainSelection(at)) |dot| {
                    const breaks = self.opensItsLine(dot) or self.opensItsLine(TokenId.at(dot.index() + 1));
                    broken = broken or breaks;
                    first = selection;
                    first_joined = !breaks;
                }
            }
            self.chain_broken = broken;
            self.chain_first = first;
            self.chain_first_joined = first_joined;
            self.chain_indented = false;
            defer {
                if (self.chain_indented) self.indent -= 1;
                self.chain_broken = outer_broken;
                self.chain_first = outer_first;
                self.chain_first_joined = outer_first_joined;
                self.chain_indented = outer_indented;
                for (self.chain.items[mark..]) |link_at| _ = self.chain_links.remove(link_at);
                self.chain.shrinkRetainingCapacity(mark);
            }
            return self.writeExprIn(e, tag, began_line);
        }
        return self.writeExprIn(e, tag, began_line);
    }

    /// The `.` a link of a chain is selected through: a field selection's, or
    /// that of the selection an operation call names. Null for anything
    /// else.
    fn chainSelection(self: *const Printer, e: ExprId) ?TokenId {
        const selection = switch (self.ast.exprTag(e)) {
            .field => e,
            .call => blk: {
                const callee = self.ast.call(e).callee;
                if (callee == ExprId.none or self.ast.exprTag(callee) != .field) return null;
                break :blk callee;
            },
            else => return null,
        };
        const name = self.ast.exprMain(selection);
        if (name == TokenId.none) return null;
        // Comments are tokens, and one may sit between the `.` and the name.
        var at = name.index();
        while (at > 0) {
            at -= 1;
            switch (self.ast.tokenTag(TokenId.at(at))) {
                .comment => continue,
                .dot => return TokenId.at(at),
                else => return null,
            }
        }
        return null;
    }

    /// Whether `e` is a link of a chain: a selection, or a `?` applied to
    /// one, which stays on the line of the selection it follows.
    fn isChainLink(self: *const Printer, e: ExprId) bool {
        if (e == ExprId.none) return false;
        if (self.ast.exprTag(e) == .try_) return self.isChainLink(self.ast.unaryOperand(e));
        return self.chainSelection(e) != null;
    }

    fn inChain(self: *const Printer, e: ExprId) bool {
        return self.chain_links.contains(e);
    }

    /// The link of a chain that `e` selects from, or null where what it
    /// selects from is the chain's root.
    fn chainReceiver(self: *const Printer, e: ExprId) ?ExprId {
        const receiver = switch (self.ast.exprTag(e)) {
            .try_ => self.ast.unaryOperand(e),
            .field => self.ast.unaryOperand(e),
            .call => self.ast.unaryOperand(self.ast.call(e).callee),
            else => return null,
        };
        return if (self.isChainLink(receiver)) receiver else null;
    }

    /// Whether the author wrote a line break before `t`.
    fn opensItsLine(self: *const Printer, t: TokenId) bool {
        if (t.index() == 0) return false;
        const spans = self.ast.tokens.items(.span);
        return self.newlinesBetween(spans[t.index() - 1].end, spans[t.index()].start) > 0;
    }

    fn writeExprIn(self: *Printer, e: ExprId, tag: node.Expr.Tag, began_line: bool) Error!void {
        if (binaryOp(tag)) |op| {
            const b = self.ast.binary(e);
            try self.writeExpr(b.lhs);
            try self.write(" ");
            try self.write(op);
            try self.write(" ");
            try self.writeExpr(b.rhs);
            return;
        }
        switch (tag) {
            .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge => unreachable,
            .logical_and, .logical_or => unreachable,

            // Printed back as it was written: the pieces are alternating text and
            // value, and the text pieces carry their own delimiters -- `"a{`, `}b{`,
            // `}c"` -- so writing each piece in order reproduces the literal. A
            // value's format spec is the token just before the text that closes
            // its braces, and it is written back as it was spelled, with only
            // the spaces around it dropped.
            .interp => {
                const interpolation = self.ast.interpolation(e);
                for (interpolation.pieces, 0..) |piece, i| {
                    try self.writeExpr(piece);
                    if (i % 2 == 1 and i + 1 < interpolation.pieces.len) {
                        const closing = self.ast.exprTokens(interpolation.pieces[i + 1]).start;
                        if (closing.index() > 0) {
                            const spec = TokenId.at(closing.index() - 1);
                            if (self.ast.tokenTag(spec) == .format_spec) {
                                try self.write(":");
                                try self.write(self.ast.tokenText(spec));
                            }
                        }
                    }
                }
            },
            .array_literal, .tuple_literal, .tuple_pattern => try self.writeList(e),

            // Written nowhere: the parameter prints as its pattern.
            .param_argument => unreachable,

            .lambda => {
                const lambda = self.ast.lambda(e);
                if (lambda.invocation_token != .none) {
                    try self.write(@tagName(lambda.invocation));
                    try self.write(" ");
                }
                if (lambda.capture_open != .none and lambda.capture_close != .none) {
                    const captures: token.TokenRange = .{ .start = lambda.capture_open, .end = TokenId.at(lambda.capture_close.index() + 1) };
                    const list = try self.openList(captures, lambda.captures.len, "[", "]", "", false);
                    for (lambda.captures, 0..) |capture, i| {
                        const start = if (capture.convention_token != .none) capture.convention_token else capture.name;
                        try self.flushCommentsBefore(start);
                        if (self.alreadyCopied(start)) continue;
                        if (capture.convention_token != .none) {
                            try self.write(@tagName(capture.convention));
                            try self.write(" ");
                        }
                        try self.write(self.ast.tokenText(capture.name));
                        if (capture.equals != .none) {
                            try self.write(" = ");
                            try self.writeExpr(capture.source);
                        }
                        try self.afterElement(list, i + 1 == lambda.captures.len, .{
                            .start = start,
                            .end = self.elementEnd(start),
                        });
                    }
                    try self.closeList(list, lambda.captures.len);
                    try self.write(" ");
                }
                const pipes: token.TokenRange = .{ .start = lambda.open, .end = TokenId.at(lambda.close.index() + 1) };
                const l = try self.openList(pipes, lambda.params.len, "|", "|", "", false);
                for (lambda.params, 0..) |p, i| {
                    try self.flushCommentsBefore(p.name);
                    if (self.alreadyCopied(p.name)) continue;
                    try self.writeParam(p, false);
                    try self.afterElement(l, i + 1 == lambda.params.len, .{
                        .start = p.name,
                        .end = self.elementEnd(p.name),
                    });
                }
                try self.closeList(l, lambda.params.len);
                if (lambda.result_arrow != .none) {
                    try self.flushCommentsBefore(lambda.result_arrow);
                    try self.write(" ->");
                    if (lambda.result.wasWritten()) {
                        try self.write(" ");
                        try self.writeWrittenType(lambda.result);
                    }
                }
                try self.writeContracts(self.ast.contracts[lambda.contracts.start..lambda.contracts.end]);
                if (!self.at_line_start) try self.write(" ");
                try self.writeExpr(lambda.body);
            },

            // Contents that read only as types, such as `[A, B]` or
            // `[[T; 2]]` before a call, have no index to print.
            .index => {
                const b = self.ast.binary(e);
                try self.writeExpr(b.lhs);
                if (self.ast.exprTag(b.rhs) == .err) {
                    try self.writeTypeList(self.ast.typeArgs(self.ast.bracketTypes(e).?), self.ast.exprMain(e), true);
                } else {
                    try self.write("[");
                    try self.writeExpr(b.rhs);
                    try self.write("]");
                }
            },

            // `lo..hi` or `lo..=hi`, with no spaces around the operator: a
            // range reads as one token the way `a.b` does, not as arithmetic.
            .range => {
                const ends = self.ast.rangeEnds(e);
                try self.writeExpr(ends.lhs);
                try self.write(if (self.ast.rangeInclusive(e)) "..=" else "..");
                try self.writeExpr(ends.rhs);
            },

            .block => try self.writeBlock(e),

            .conditional => {
                const c = self.ast.conditional(e);
                try self.write("if ");
                try self.writeExpr(c.cond);
                try self.write(" ");
                try self.writeBlock(c.then);
                if (c.otherwise != ExprId.none) {
                    try self.write(" else ");
                    // `else if` was written on one line, so it comes back on
                    // one. The tree nests, and printing the nesting as a block
                    // holding a conditional would indent a staircase nobody
                    // wrote -- which is the same reason a redundant
                    // parenthesis is kept rather than dropped.
                    if (self.ast.exprTag(c.otherwise) == .conditional) {
                        try self.writeExpr(c.otherwise);
                    } else {
                        try self.writeBlock(c.otherwise);
                    }
                }
            },

            .while_ => {
                const b = self.ast.binary(e);
                try self.write("while ");
                try self.writeExpr(b.lhs);
                try self.write(" ");
                try self.writeBlock(b.rhs);
            },

            .loop_ => {
                try self.write("loop ");
                try self.writeBlock(self.ast.unaryOperand(e));
            },

            // `for x in xs { … }`, and the two forms that lend rather than
            // take. The word after `for` is what the tag says it is, so the
            // three print through one arm.
            .for_, .for_read, .for_inout => {
                const f = self.ast.call(e);
                try self.write(switch (tag) {
                    .for_read => "for read ",
                    .for_inout => "for inout ",
                    else => "for ",
                });
                try self.writeExpr(f.args[0]);
                try self.write(" in ");
                try self.writeExpr(f.callee);
                try self.write(" ");
                try self.writeBlock(f.args[1]);
            },

            .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => {
                const b = self.ast.binary(e);
                try self.writeExpr(b.lhs);
                try self.write(" ");
                try self.write(assignmentOp(tag));
                try self.write(" ");
                try self.writeExpr(b.rhs);
            },

            // Carries nothing, so it has no operand to reach for.
            .continue_ => try self.write("continue"),
            .unit_literal => try self.write("()"),

            .break_, .return_ => {
                try self.write(if (tag == .break_) "break" else "return");
                const v = self.ast.unaryOperand(e);
                if (v != ExprId.none) {
                    try self.write(" ");
                    try self.writeExpr(v);
                }
            },

            // `&x` at a call site, marking an argument the callee writes back
            // through. The marker binds to the argument, so nothing separates
            // them.
            .marked => {
                try self.write("&");
                try self.writeExpr(self.ast.unaryOperand(e));
            },

            .field => {
                // A note on a selection names the whole of what it selects --
                // the copy a call reaches carries whatever it was reached
                // through, so writing the path as well would say it twice.
                const noted = Notes.at(self.notes.tokens, self.ast.exprMain(e).index());
                if (noted.len > 0) return self.write(noted);

                try self.writeExpr(self.ast.unaryOperand(e));
                // A link of a broken chain opens its own line, and a comment
                // the author wrote between two links stays between them.
                if (self.chain_broken and self.inChain(e) and !(e == self.chain_first and self.chain_first_joined)) {
                    if (!self.chain_indented) {
                        self.chain_indented = true;
                        self.indent += 1;
                    }
                    try self.newline();
                    if (self.chainSelection(e)) |dot| {
                        try self.flushCommentsBefore(dot);
                        // A blank line the author left between two links is
                        // kept, before the `.` or after it, as one.
                        if (!self.at_blank_line and (self.blankBefore(dot) or self.blankAfter(dot))) try self.newline();
                        // A comment written after a trailing `.` belongs to
                        // the link it precedes, so it takes its own line above
                        // that link, where the `.` now opens it.
                        const name = self.ast.exprMain(e);
                        if (name.index() != dot.index() + 1) {
                            try self.flushCommentsBefore(name);
                            if (!self.at_blank_line and self.blankBefore(name)) try self.newline();
                        }
                    }
                }
                try self.write(".");
                try self.write(self.ast.tokenText(self.ast.exprMain(e)));
            },

            // `.Red` -- a variant reached where its type is already known, so
            // it names no type and carries no operand.
            .variant_ref => {
                try self.write(".");
                try self.write(self.ast.tokenText(self.ast.exprMain(e)));
            },

            .borrow => {
                try self.write("borrow ");
                try self.writeExpr(self.ast.unaryOperand(e));
            },

            .dereference => {
                try self.write("*");
                try self.writeExpr(self.ast.unaryOperand(e));
            },

            .copy_ => {
                try self.write("copy(");
                try self.writeExpr(self.ast.unaryOperand(e));
                try self.write(")");
            },

            .panic => {
                try self.write("panic(");
                try self.writeExpr(self.ast.unaryOperand(e));
                try self.write(")");
            },

            .try_ => {
                try self.writeExpr(self.ast.unaryOperand(e));
                try self.write("?");
            },

            // The formatter writes `else` on the initializer's line, as it
            // writes an `if`'s `else` after the closing brace.
            .unwrap_else => {
                const u = self.ast.unwrapElse(e);
                try self.writeExpr(u.operand);
                try self.write(" else ");
                if (u.binder != ExprId.none) {
                    try self.write("|");
                    try self.writeExpr(u.binder);
                    try self.write("| ");
                }
                try self.writeBlock(u.body);
            },

            .not => {
                try self.write("!");
                try self.writeExpr(self.ast.unaryOperand(e));
            },

            .negate => {
                try self.write("-");
                try self.writeExpr(self.ast.unaryOperand(e));
            },

            .from_end => {
                try self.write("^");
                try self.writeExpr(self.ast.unaryOperand(e));
            },

            // Kept rather than dropped: parentheses are a node precisely so
            // tooling does not rewrite what the programmer wrote.
            .grouped => {
                try self.write("(");
                try self.writeExpr(self.ast.unaryOperand(e));
                try self.write(")");
            },

            // A lexeme copied exactly as written: casing, leading zeros and the
            // bytes between a string's quotes are the author's.
            .int_literal, .float_literal, .str_literal, .bool_literal, .name_ref, .reflection_root => {
                if (tag == .str_literal and self.ast.tokenTag(self.ast.exprMain(e)) == .string_line) {
                    return self.writeStringLines(e, began_line);
                }
                try self.write(self.textOf(self.ast.exprMain(e)));
                // A name that heads a path to a variant is where that
                // instantiation reads: `Option[u8].Some`, not `Option.Some[u8]`.
                try self.write(Notes.at(self.notes.exprs, e.index()));
            },

            .call, .struct_literal, .struct_pattern, .match_, .match_read => {
                try self.writeList(e);
            },

            // Already diagnosed; fmt refuses any file holding one, so reaching
            // here means the driver's refusal was skipped.
            .err => unreachable,
        }
    }
};

/// The four things formatting must do, checked together because a formatter
/// satisfying three of them is still wrong.
///
/// Nothing here is an expected output, so a generator can supply the input and
/// a case added tomorrow is a case for this too. Returns quietly on source the
/// compiler would refuse: a file fmt will not write says nothing about
/// formatting.
/// Why formatted output must not be written over its source, or null where it
/// may be.
///
/// `fmt` rewrites a file in place, so the walk being wrong destroys work that
/// existed. These are two of the properties the conformance suite already asks
/// of every corpus file -- does the output parse, and is it the same tokens --
/// asked once more at the only point where getting them wrong costs something
/// that cannot be recovered.
fn refusalReason(
    gpa: std.mem.Allocator,
    before: *const Ast,
    formatted: []const u8,
) !?[]const u8 {
    const source: Source = .{ .path = "fmt.lin", .text = formatted };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    if (sink.hasErrors()) return "the result would not parse";

    // The shape, not the spelling. Since a newline ends a statement, the same
    // tokens in the same order can be a different program -- `a` then `-b` is
    // two statements and `a - b` is one, and the token texts are identical. A
    // guard that compares only tokens is blind to every reflow that moves one
    // across a statement boundary, so it is the tree that has to match.
    //
    // Token ranges are stripped: dropping a `;` shifts every index after it
    // without changing what the tree says.
    if (!try sameShape(gpa, before, &ast)) return "the result would be a different program";

    // Comments are not nodes, so neither the tree nor the significant tokens
    // say anything about them -- and a comment dropped or reworded is source
    // destroyed just as surely as a token is. The one assertion in the printer
    // that would catch it is compiled out of a release build, which is the
    // build a released `fmt` is.
    const text = before.parts[0].source;
    const was = try commentTextOf(gpa, text, before.tokens);
    const now = try commentTextOf(gpa, formatted, ast.tokens);
    if (was.len != now.len) return "a comment would be dropped or invented";
    for (was, now) |x, y| {
        if (!std.mem.eql(u8, x, y)) return "a comment would be reworded";
    }

    const d = (try tokenDifferenceOf(gpa, text, before.tokens, formatted, ast.tokens)) orelse return null;
    return switch (d) {
        .changed => try std.fmt.allocPrint(gpa, "`{s}` would become `{s}`", .{ d.changed.from, d.changed.to }),
        .dropped => try std.fmt.allocPrint(gpa, "`{s}` would be dropped", .{d.dropped}),
        .invented => try std.fmt.allocPrint(gpa, "`{s}` would be invented", .{d.invented}),
    };
}

pub const PropertyResult = union(enum) {
    not_applicable,
    checked: struct {
        formatted: []const u8,
    },
};

/// Returns the canonical text after every property agrees. Source that does not
/// parse has no formatting to hold to them, and a run needs to tell that from a
/// property that ran and agreed.
pub fn checkProperties(gpa: std.mem.Allocator, text: []const u8) !PropertyResult {
    return checkPropertiesReporting(gpa, text, null);
}

pub fn checkPropertiesReporting(
    gpa: std.mem.Allocator,
    text: []const u8,
    diagnostics: ?*std.Io.Writer,
) !PropertyResult {
    const source: Source = .{ .path = "fmt.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    if (sink.hasErrors()) return .not_applicable;

    const once = try formatAlloc(gpa, &ast);

    // 1. It re-parses. A formatter whose output the compiler rejects has
    //    destroyed the file, whatever else it got right.
    const again: Source = .{ .path = "fmt.lin", .text = once };
    var sink1 = Sink.init(gpa);
    var interner1: Interner = .empty;
    const tokens1 = try tokenize(gpa, &again, .from(0), &sink1, &interner1);
    var ast1 = try parse(gpa, &again, .from(0), tokens1, &sink1);
    if (sink1.hasErrors()) {
        try printDiagnostic(diagnostics, "formatted output does not parse:\n{s}\n", .{once});
        return error.FormattedOutputDoesNotParse;
    }

    // 2. The non-trivia token sequence is preserved, modulo trailing commas
    //    inserted into delimited lists.
    try expectSameTokensOf(gpa, text, ast.tokens, once, ast1.tokens, diagnostics);

    // 3. Idempotent.
    const twice = try formatAlloc(gpa, &ast1);
    try expectSameFormatting(once, twice, diagnostics);

    // 4. No comment dropped, duplicated or reworded.
    try expectSameCommentsOf(gpa, text, ast.tokens, once, ast1.tokens, diagnostics);
    return .{ .checked = .{ .formatted = once } };
}

/// Every significant token, as text and tag, in order.
const Tokens = struct {
    text: []const []const u8,
    tags: []const token.Tag,
};

fn significantTokens(gpa: std.mem.Allocator, text: []const u8) !Tokens {
    const source: Source = .{ .path = "fmt.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    return significantTokensOf(gpa, text, tokens.slice());
}

fn significantTokensOf(
    gpa: std.mem.Allocator,
    text: []const u8,
    tokens: token.TokenList.Slice,
) !Tokens {
    const tags = tokens.items(.tag);
    const spans = tokens.items(.span);

    var out_text: std.ArrayList([]const u8) = .empty;
    var out_tags: std.ArrayList(token.Tag) = .empty;
    for (tags, spans) |tag, span| {
        if (tag == .comment or tag == .eof) continue;
        try out_text.append(gpa, span.slice(text));
        try out_tags.append(gpa, tag);
    }
    return .{
        .text = try out_text.toOwnedSlice(gpa),
        .tags = try out_tags.toOwnedSlice(gpa),
    };
}

/// Where two token sequences first disagree, or null where they do not.
///
/// One walk, asked by the property that reports the disagreement and by the
/// driver that refuses to write over a file because of it.
pub const Difference = union(enum) {
    changed: struct { at: usize, from: []const u8, to: []const u8 },
    dropped: []const u8,
    invented: []const u8,
};

/// The input's tokens appear in the output, in order, unchanged, save for two
/// differences the language itself makes invisible.
///
/// The output may hold an extra comma before a closing delimiter, which fmt
/// writes whenever it breaks a list. The input may hold an extra semicolon
/// before a closing brace, which fmt drops: the parser eats that one without
/// recording it, so `{ e; }` and `{ e }` are one tree and one program, and
/// there is nothing in hand to write back.
///
/// The two allowances run in opposite directions and are kept that way
/// deliberately. Normalising both sides instead would forgive fmt deleting a
/// comma the author wrote or inventing a semicolon they did not, and a rule
/// that forgives either is not a preservation property.
fn tokenDifference(
    gpa: std.mem.Allocator,
    before: []const u8,
    after: []const u8,
) !?Difference {
    const a = try significantTokens(gpa, before);
    const b = try significantTokens(gpa, after);
    return differenceBetween(a, b);
}

fn tokenDifferenceOf(
    gpa: std.mem.Allocator,
    before_text: []const u8,
    before_tokens: token.TokenList.Slice,
    after_text: []const u8,
    after_tokens: token.TokenList.Slice,
) !?Difference {
    const a = try significantTokensOf(gpa, before_text, before_tokens);
    const b = try significantTokensOf(gpa, after_text, after_tokens);
    return differenceBetween(a, b);
}

fn differenceBetween(a: Tokens, b: Tokens) ?Difference {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.text.len and j < b.text.len) {
        if (std.mem.eql(u8, a.text[i], b.text[j])) {
            i += 1;
            j += 1;
            continue;
        }
        if (isInsertedComma(b, j)) {
            j += 1;
            continue;
        }
        if (isDroppedSemicolon(a, i)) {
            i += 1;
            continue;
        }
        return .{ .changed = .{ .at = i, .from = a.text[i], .to = b.text[j] } };
    }
    while (j < b.text.len and isInsertedComma(b, j)) j += 1;
    while (i < a.text.len and isDroppedSemicolon(a, i)) i += 1;

    if (i < a.text.len) return .{ .dropped = a.text[i] };
    if (j < b.text.len) return .{ .invented = b.text[j] };
    return null;
}

fn printDiagnostic(
    diagnostics: ?*std.Io.Writer,
    comptime format_string: []const u8,
    args: anytype,
) !void {
    if (diagnostics) |writer| {
        try writer.print(format_string, args);
    } else {
        std.debug.print(format_string, args);
    }
}

fn expectSameTokens(
    gpa: std.mem.Allocator,
    before: []const u8,
    after: []const u8,
    diagnostics: ?*std.Io.Writer,
) !void {
    const d = (try tokenDifference(gpa, before, after)) orelse return;
    return reportTokenDifference(d, diagnostics);
}

fn expectSameTokensOf(
    gpa: std.mem.Allocator,
    before_text: []const u8,
    before_tokens: token.TokenList.Slice,
    after_text: []const u8,
    after_tokens: token.TokenList.Slice,
    diagnostics: ?*std.Io.Writer,
) !void {
    const d = (try tokenDifferenceOf(
        gpa,
        before_text,
        before_tokens,
        after_text,
        after_tokens,
    )) orelse return;
    return reportTokenDifference(d, diagnostics);
}

fn reportTokenDifference(d: Difference, diagnostics: ?*std.Io.Writer) !void {
    switch (d) {
        .changed => |c| try printDiagnostic(
            diagnostics,
            "token {d} changed: '{s}' -> '{s}'\n",
            .{ c.at, c.from, c.to },
        ),
        .dropped => |t| try printDiagnostic(diagnostics, "token dropped: '{s}'\n", .{t}),
        .invented => |t| try printDiagnostic(diagnostics, "token invented: '{s}'\n", .{t}),
    }
    return error.TokenSequenceChanged;
}

fn expectSameFormatting(
    expected: []const u8,
    actual: []const u8,
    diagnostics: ?*std.Io.Writer,
) !void {
    const diff_index = std.mem.findDiff(u8, actual, expected) orelse return;
    const writer = diagnostics orelse return testing.expectEqualStrings(expected, actual);

    try writer.writeAll("\n====== expected this output: =========\n");
    try writeVisibleNewlines(writer, expected);
    try writer.writeAll("\n======== instead found this: =========\n");
    try writeVisibleNewlines(writer, actual);
    try writer.writeAll("\n======================================\n");

    var diff_line_number: usize = 1;
    for (expected[0..diff_index]) |value| {
        if (value == '\n') diff_line_number += 1;
    }
    try writer.print("First difference occurs on line {d}:\n", .{diff_line_number});
    try writer.writeAll("expected:\n");
    try writeIndicatorLine(writer, expected, diff_index);
    try writer.writeAll("found:\n");
    try writeIndicatorLine(writer, actual, diff_index);
    return error.TestExpectedEqual;
}

fn writeIndicatorLine(writer: *std.Io.Writer, source: []const u8, indicator_index: usize) !void {
    const line_begin_index = if (std.mem.lastIndexOfScalar(u8, source[0..indicator_index], '\n')) |line_begin|
        line_begin + 1
    else
        0;
    const line_end_index = if (std.mem.findScalar(u8, source[indicator_index..], '\n')) |line_end|
        indicator_index + line_end
    else
        source.len;

    try writeDiagnosticLine(writer, source[line_begin_index..line_end_index]);
    try writer.splatByteAll(' ', indicator_index - line_begin_index);
    if (indicator_index >= source.len) {
        try writer.writeAll("^ (end of string)\n");
    } else {
        try writer.print("^ ('\\x{x:0>2}')\n", .{source[indicator_index]});
    }
}

fn writeVisibleNewlines(writer: *std.Io.Writer, source: []const u8) !void {
    var i: usize = 0;
    while (std.mem.findScalar(u8, source[i..], '\n')) |newline| : (i += newline + 1) {
        try writeDiagnosticLine(writer, source[i..][0..newline]);
    }
    try writer.print("{s}\u{2403}\n", .{source[i..]});
}

fn writeDiagnosticLine(writer: *std.Io.Writer, line: []const u8) !void {
    if (line.len != 0) switch (line[line.len - 1]) {
        ' ', '\t' => return writer.print("{s}\u{23ce}\n", .{line}),
        else => {},
    };
    try writer.print("{s}\n", .{line});
}

/// A comma sitting immediately before a closing delimiter -- the one token fmt
/// is allowed to add.
fn isInsertedComma(t: Tokens, at: usize) bool {
    if (t.tags[at] != .comma) return false;
    if (at + 1 >= t.tags.len) return false;
    return t.tags[at + 1] == .r_brace or t.tags[at + 1] == .r_paren;
}

/// A semicolon -- the one token fmt is allowed to drop.
///
/// A newline ends a statement, and the printer gives every statement a line of
/// its own, so a `;` in the output would say what the line break already says.
/// None survives, including the one separating two statements written on a
/// line: they do not share a line afterwards.
///
/// Dropping one cannot change a program. The allowance stays on the input side
/// only, so the output may still never invent one.
fn isDroppedSemicolon(t: Tokens, at: usize) bool {
    return t.tags[at] == .semicolon;
}

fn commentText(gpa: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    const source: Source = .{ .path = "fmt.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    return commentTextOf(gpa, text, tokens.slice());
}

fn commentTextOf(
    gpa: std.mem.Allocator,
    text: []const u8,
    tokens: token.TokenList.Slice,
) ![]const []const u8 {
    const tags = tokens.items(.tag);
    const spans = tokens.items(.span);

    var out: std.ArrayList([]const u8) = .empty;
    for (tags, spans) |tag, span| {
        if (tag != .comment) continue;
        // Read the way the printer writes them, or the property accuses it
        // of rewording a comment it only trimmed.
        try out.append(gpa, writtenComment(text, span));
    }
    return out.toOwnedSlice(gpa);
}

fn expectSameComments(
    gpa: std.mem.Allocator,
    before: []const u8,
    after: []const u8,
    diagnostics: ?*std.Io.Writer,
) !void {
    const a = try commentText(gpa, before);
    const b = try commentText(gpa, after);
    return compareComments(a, b, diagnostics);
}

fn expectSameCommentsOf(
    gpa: std.mem.Allocator,
    before_text: []const u8,
    before_tokens: token.TokenList.Slice,
    after_text: []const u8,
    after_tokens: token.TokenList.Slice,
    diagnostics: ?*std.Io.Writer,
) !void {
    const a = try commentTextOf(gpa, before_text, before_tokens);
    const b = try commentTextOf(gpa, after_text, after_tokens);
    return compareComments(a, b, diagnostics);
}

fn compareComments(
    a: []const []const u8,
    b: []const []const u8,
    diagnostics: ?*std.Io.Writer,
) !void {
    if (a.len != b.len) {
        try printDiagnostic(diagnostics, "comment count changed: {d} -> {d}\n", .{ a.len, b.len });
        return error.CommentsChanged;
    }
    for (a, b) |x, y| {
        if (std.mem.eql(u8, x, y)) continue;
        try printDiagnostic(diagnostics, "comment changed: '{s}' -> '{s}'\n", .{ x, y });
        return error.CommentsChanged;
    }
}

test "the properties hold on a program using every construct" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    _ = try checkProperties(arena.allocator(),
        \\// A comment above a declaration.
        \\enum Step { Half, Whole, Exactly(UInt8) }
        \\
        \\struct Plan {
        \\    remaining: UInt8,
        \\    step: Step,
        \\}
        \\
        \\fn amount(s: Step) -> UInt8 {
        \\    match read s {
        \\        Half => 5, // trailing comment
        \\        Whole => { let a: UInt8 = 10; a },
        \\        Exactly(n) => copy(n),
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let plan: Plan = .{ remaining = 3, step = .Half };
        \\    let Plan { remaining, step } = plan;
        \\    amount(step) + remaining
        \\}
        \\
    );
}

test "formatter properties return applicability and canonical text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const malformed = try checkProperties(gpa, "( this does not parse");
    try testing.expect(malformed == .not_applicable);
    const result = try checkProperties(gpa, "fn main()->UInt8{0}");
    switch (result) {
        .not_applicable => return error.ExpectedCheckedFormatting,
        .checked => |checked| try testing.expectEqualStrings(
            "fn main() -> UInt8 {\n    0\n}\n",
            checked.formatted,
        ),
    }
}

test "formatter property diagnostics can be retained" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var diagnostics: std.Io.Writer.Allocating = .init(arena.allocator());

    try testing.expectError(
        error.TokenSequenceChanged,
        expectSameTokens(
            arena.allocator(),
            "fn one() -> UInt8 { 0 }\n",
            "fn two() -> UInt8 { 0 }\n",
            &diagnostics.writer,
        ),
    );
    try testing.expectEqualStrings(
        "token 1 changed: 'one' -> 'two'\n",
        diagnostics.written(),
    );

    var comments: std.Io.Writer.Allocating = .init(arena.allocator());
    try testing.expectError(
        error.CommentsChanged,
        expectSameComments(
            arena.allocator(),
            "// one\nfn main() -> UInt8 { 0 }\n",
            "// two\nfn main() -> UInt8 { 0 }\n",
            &comments.writer,
        ),
    );
    try testing.expectEqualStrings(
        "comment changed: '// one' -> '// two'\n",
        comments.written(),
    );

    var idempotence: std.Io.Writer.Allocating = .init(arena.allocator());
    try testing.expectError(
        error.TestExpectedEqual,
        expectSameFormatting("one", "two", &idempotence.writer),
    );
    try testing.expect(std.mem.indexOf(u8, idempotence.written(), "expected this output") != null);
    try testing.expect(std.mem.indexOf(u8, idempotence.written(), "First difference occurs on line 1") != null);

    var clean: std.Io.Writer.Allocating = .init(arena.allocator());
    const result = try checkPropertiesReporting(
        arena.allocator(),
        "fn main() -> UInt8 { 0 }\n",
        &clean.writer,
    );
    switch (result) {
        .not_applicable => return error.ExpectedCheckedFormatting,
        .checked => {},
    }
    try testing.expectEqual(@as(usize, 0), clean.written().len);
}

fn fuzzFormat(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [512]u8 = undefined;
    const len = smith.slice(&buf);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    _ = try checkProperties(arena.allocator(), buf[0..len]);
}

test "fuzz: formatting any input it accepts is a normal form" {
    // Every input this property has ever failed on, replayed before any new one
    // is tried, so a crash the fuzzer found once cannot come back unnoticed.
    try std.testing.fuzz({}, fuzzFormat, .{ .corpus = @import("fuzz_corpus").fmt });
}

test "every input the fuzzer found for fmt still passes" {
    // Replayed here as well as handed to the fuzzer, because the two run at
    // different times: a search runs nightly and on a push, and this runs
    // whenever anyone builds.
    for (@import("fuzz_corpus").fmt) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try fuzzFormat({}, &smith);
    }
}

test "a note is written where the source said nothing" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "fmt.lin", .text = "fn main() -> UInt8 {\n    let x = 1\n    x\n}\n" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(!sink.hasErrors());

    // The one `let` is the file's only statement, so its note is the first
    // entry; the array is short on purpose, since a note table need not cover
    // every id.
    var out: std.Io.Writer.Allocating = .init(gpa);
    try formatNoted(gpa, &ast, .{ .bindings = &.{"UInt8"} }, DeclarationSelection.all(ast.declCount()), &out.writer);
    try testing.expectEqualStrings("fn main() -> UInt8 {\n    let x: UInt8 = 1\n    x\n}\n", out.written());

    // The same tree with no notes is the source, which is what keeps plain
    // formatting a normal form rather than a reading of one.
    var plain: std.Io.Writer.Allocating = .init(gpa);
    try format(gpa, &ast, &plain.writer);
    try testing.expectEqualStrings(source.text, plain.written());
}

/// Formats source text, asserting it parses cleanly first.
///
/// The whole printer is specified as text in and text out, so every test below
/// reads as the rule it checks rather than as a walk over a tree.
fn check(gpa: std.mem.Allocator, input: []const u8, want: []const u8) !void {
    const source: Source = .{ .path = "fmt.lin", .text = input };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(!sink.hasErrors());
    try testing.expectEqualStrings(want, try formatAlloc(gpa, &ast));
}

test "a defer let is one statement and keeps its comments, its separator and its else" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    _ = try checkProperties(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    // above
        \\    defer   let a: Lamp = open()  // beside
        \\    defer var b = 1;
        \\    defer let c = find() else |_| { return 1 }
        \\    defer let d = open()?;
        \\    -1
        \\}
        \\
    );
    try check(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    // above
        \\    defer   let a: Lamp = open()  // beside
        \\    defer var b = 1;
        \\    defer let c = find() else |_| { return 1 }
        \\    0
        \\}
        \\
    ,
        \\fn main() -> UInt8 {
        \\    // above
        \\    defer let a: Lamp = open() // beside
        \\    defer var b = 1
        \\    defer let c = find() else |_| {
        \\        return 1
        \\    }
        \\    0
        \\}
        \\
    );
}

test "imports sit together, one per line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `;` separates two that share a line, and nothing else needs it. A blank
    // line between declarations is structure; a list of imports is one piece
    // of structure rather than several.
    try check(arena.allocator(), "import a; import b.c as d\nimport e;\nfn main() -> UInt8 { 0 }",
        \\import a
        \\import b.c as d
        \\import e
        \\
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\
    );
}

test "formatter spacing separates function signatures and keeps associated types together" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const want =
        \\trait Transform {
        \\    type Input
        \\    type Output
        \\
        \\    fn first(self: Self) -> Input
        \\
        \\    // Produces the output.
        \\    fn second(self: Self) -> Output
        \\}
        \\
    ;
    try check(arena.allocator(),
        \\trait Transform {
        \\type Input
        \\type Output
        \\fn first(self: Self) -> Input
        \\// Produces the output.
        \\fn second(self: Self) -> Output
        \\}
        \\
    , want);
    try check(arena.allocator(), want, want);
}

test "formatter spacing separates function bodies and import use groups" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const want =
        \\import a
        \\import b
        \\
        \\use a.A
        \\use b.B
        \\
        \\fn first() -> () {}
        \\
        \\fn second() -> () {}
        \\
        \\impl A {
        \\    fn first(self: Self) -> () {}
        \\
        \\    fn second(self: Self) -> () {}
        \\}
        \\
    ;
    try check(arena.allocator(), "import a\n\n\nimport b\nuse a.A\nuse b.B\nfn first() -> () {}\nfn second() -> () {}\nimpl A { fn first(self: Self) -> () {}\nfn second(self: Self) -> () {} }\n", want);
    try check(arena.allocator(), want, want);
}

test "formatter spacing collapses nested gaps without separating control flow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const want =
        \\fn main() -> UInt8 {
        \\    var value: UInt8 = 0
        \\
        \\    // Advance once.
        \\    while value < 1 {
        \\        value = value + 1
        \\    }
        \\    if value == 1 {
        \\        value = 2
        \\    }
        \\
        \\    value
        \\}
        \\
    ;
    try check(arena.allocator(), "fn main() -> UInt8 {\n\n\nvar value: UInt8 = 0\n\n\n\n// Advance once.\nwhile value < 1 {\n\nvalue = value + 1\n\n}\nif value == 1 { value = 2 }\n\n\n\nvalue\n\n}\n", want);
    try check(arena.allocator(), want, want);
}

test "formatter spacing preserves blank lines inside disabled regions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source =
        \\trait Steps {
        \\    // linea fmt: off
        \\    fn first(self:Self)->()
        \\
        \\
        \\    fn second(self:Self)->()
        \\    // linea fmt: on
        \\
        \\    fn third(self: Self) -> ()
        \\}
        \\
    ;
    try check(arena.allocator(), source, source);
}

test "default implementation formatting preserves its modifier" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(
        arena.allocator(),
        "default   impl[T:Hash] Key for T{type Query=T}\n",
        "default impl[T: Hash] Key for T {\n    type Query = T\n}\n",
    );
}

test "default implementation formatting retains comments and constraints" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const want =
        \\// Supply the ordinary query shape.
        \\default impl[T: Hash] Key for T where T: Copyable {
        \\    type Query = T
        \\
        \\    // Compare the complete value.
        \\    fn matches(self: T, query: T) -> Bool {
        \\        self == query
        \\    }
        \\}
        \\
    ;
    try check(arena.allocator(),
        \\// Supply the ordinary query shape.
        \\default   impl[T:Hash] Key for T where T:Copyable {
        \\type Query=T
        \\// Compare the complete value.
        \\fn matches(self:T,query:T)->Bool{self==query}
        \\}
    , want);
    try check(arena.allocator(), want, want);
}

test "a structural template formats as an impl-shaped declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(
        arena.allocator(),
        "trait Marker {}\ntemplate   impl Marker { }\n",
        "trait Marker {}\n\ntemplate impl Marker {}\n",
    );
}

test "formatter writes structural reflection" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\trait Fold{fn fold(self:Self)->UInt8}
        \\template impl Fold{fn fold(self:Self)->UInt8{match read self{reflect.case=>{var total:UInt8=0
        \\for component in reflect.components.reversed{total=total+component.of(self)}
        \\total}}}}
        \\
    ,
        \\trait Fold {
        \\    fn fold(self: Self) -> UInt8
        \\}
        \\
        \\template impl Fold {
        \\    fn fold(self: Self) -> UInt8 {
        \\        match read self {
        \\            reflect.case => {
        \\                var total: UInt8 = 0
        \\                for component in reflect.components.reversed {
        \\                    total = total + component.of(self)
        \\                }
        \\                total
        \\            },
        \\        }
        \\    }
        \\}
        \\
    );
}

test "a derive request formats as a bodyless impl-space declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(
        arena.allocator(),
        "derive   Debug   for   Mark;\n",
        "derive Debug for Mark\n",
    );
}

test "a derive request on a tuple target prints the tuple" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(
        arena.allocator(),
        "derive[A, B]   Debug   for   (A,B);\n",
        "derive[A, B] Debug for (A, B)\n",
    );
}

test "formatter preserves grouped derive and template component requirement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\template impl Inspect where reflect.components:Inspect+Lookup[UInt64]{}
        \\derive[T:Inspect](Inspect,)for Box[T] where T:Lookup[UInt64]
        \\
    ,
        \\template impl Inspect where reflect.components: Inspect + Lookup[UInt64] {}
        \\
        \\derive[T: Inspect] (
        \\    Inspect,
        \\) for Box[T] where T: Lookup[UInt64]
        \\
    );
}

test "formatter writes derived structural supertraits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\template impl Law where reflect.components:Base,reflect.supertraits:derived,{}
        \\
    ,
        \\template impl Law where
        \\    reflect.components: Base,
        \\    reflect.supertraits: derived,
        \\{}
        \\
    );
}

test "formatter preserves a trailing template requirement comma and comment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\template impl Inspect where reflect.components:Inspect, // every component
        \\{}
        \\
    ,
        \\template impl Inspect where
        \\    reflect.components: Inspect, // every component
        \\{}
        \\
    );
}

test "formatter keeps grouped derive comments with their traits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\derive(Inspect, // exact trait
        \\Lookup, // lookup trait
        \\)for Box
        \\
    ,
        \\derive (
        \\    Inspect, // exact trait
        \\    Lookup, // lookup trait
        \\) for Box
        \\
    );
}

test "a function body is one statement per line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main()->UInt8{let x=1;x}",
        \\fn main() -> UInt8 {
        \\    let x = 1
        \\    x
        \\}
        \\
    );
}

test "a bodyless declaration leaves leading comment spacing for the next declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const source =
        \\extern fn provided()->UInt8
        \\
        \\// What the result represents.
        \\
        \\pub struct Result{value:UInt8}
        \\
    ;
    const want =
        \\extern fn provided() -> UInt8
        \\
        \\// What the result represents.
        \\
        \\pub struct Result { value: UInt8 }
        \\
    ;
    try check(arena.allocator(), source, want);
}

test "internal visibility is formatted at top level and in an impl" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\internal fn make(value:UInt8)->Token{.{value=value}}
        \\internal struct Token{value:UInt8}
        \\internal let zero:UInt8=0
        \\struct Box{value:UInt8}
        \\impl Box{internal fn value(self:Box)->UInt8{self.value}}
    ,
        \\internal fn make(value: UInt8) -> Token {
        \\    .{ value = value }
        \\}
        \\
        \\internal struct Token { value: UInt8 }
        \\
        \\internal let zero: UInt8 = 0
        \\
        \\struct Box { value: UInt8 }
        \\
        \\impl Box {
        \\    internal fn value(self: Box) -> UInt8 {
        \\        self.value
        \\    }
        \\}
        \\
    );
}

test "an if is broken even when both arms are one expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { if true { 1 } else { 2 } }",
        \\fn main() -> UInt8 {
        \\    if true {
        \\        1
        \\    } else {
        \\        2
        \\    }
        \\}
        \\
    );
}

test "an empty block stays flat" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn nothing() -> () {\n}\nfn main() -> UInt8 { nothing(); 1 }",
        \\fn nothing() -> () {}
        \\
        \\fn main() -> UInt8 {
        \\    nothing()
        \\    1
        \\}
        \\
    );
}

test "the unit value prints as `()` and an empty block as written" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn done() -> Result[(), UInt8] { let unit = ( ); keep(unit, {}); wrap(( )) }",
        \\fn done() -> Result[(), UInt8] {
        \\    let unit = ()
        \\    keep(unit, {})
        \\    wrap(())
        \\}
        \\
    );
}

test "a file ends in exactly one newline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { 1 }\n\n\n\n",
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
    );
}

test "a convention the author wrote is kept, and one they omitted is not invented" {
    // `read` is the default, so dropping it would compile -- which is exactly
    // what makes deleting it the wrong kind of change. fmt writes back what is
    // there, and nothing that is not.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn take(read a:UInt8,b:UInt8,inout c:UInt8)->() { c = a; c = b; }",
        \\fn take(read a: UInt8, b: UInt8, inout c: UInt8) -> () {
        \\    c = a
        \\    c = b
        \\}
        \\
    );
}

test "binary operators are spaced and parentheses are kept" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { (1+2)*3 }",
        \\fn main() -> UInt8 {
        \\    (1 + 2) * 3
        \\}
        \\
    );
}

test "logical operators are spaced, and `!` binds to its operand" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { if !true&&false||true { 1 } else { 0 } }",
        \\fn main() -> UInt8 {
        \\    if !true && false || true {
        \\        1
        \\    } else {
        \\        0
        \\    }
        \\}
        \\
    );
}

test "parentheses around a logical operator are kept" {
    // `!(a && b)` means something `!a && b` does not, and the parentheses are
    // the only thing saying so.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { if !(true && false) { 1 } else { 0 } }",
        \\fn main() -> UInt8 {
        \\    if !(true && false) {
        \\        1
        \\    } else {
        \\        0
        \\    }
        \\}
        \\
    );
}

test "a literal is copied exactly as written" {
    // Leading zeros are the author's. A formatter that rewrote a constant
    // could change what a program computes through a bug nobody would look for.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { 007 }",
        \\fn main() -> UInt8 {
        \\    007
        \\}
        \\
    );
}

test "a while loop breaks its body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { var i=0; while i<3 { i=i+1; } i }",
        \\fn main() -> UInt8 {
        \\    var i = 0
        \\    while i < 3 {
        \\        i = i + 1
        \\    }
        \\    i
        \\}
        \\
    );
}

test "a conversion is the type name applied to a value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { UInt8( 300 - 44 ) }",
        \\fn main() -> UInt8 {
        \\    UInt8(300 - 44)
        \\}
        \\
    );
}

test "a negation and a copy bind to their operand" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { let n: Int64 = - 3; let m: Int64 = copy( n ); UInt8(0) }",
        \\fn main() -> UInt8 {
        \\    let n: Int64 = -3
        \\    let m: Int64 = copy(n)
        \\    UInt8(0)
        \\}
        \\
    );
}

test "a list without a trailing comma is flat" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "enum Step { Half, Whole }\nfn main() -> UInt8 { 1 }\n",
        \\enum Step { Half, Whole }
        \\
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
    );
}

test "a type argument list keeps a written trailing comma" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn pick[A, B](sink a: A, sink _b: B) -> A { a }\nfn main() -> UInt8 { let r: Result[UInt8, Bool,] = .Ok(pick[UInt8, Bool,](1, true)); r.unwrap_or(0) }\n",
        \\fn pick[A, B](sink a: A, sink _b: B) -> A {
        \\    a
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let r: Result[UInt8, Bool,] = .Ok(pick[UInt8, Bool,](1, true))
        \\    r.unwrap_or(0)
        \\}
        \\
    );
}

test "a comment inside type arguments before a call stays inside the brackets" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn empty[T]() -> Option[T] { .None }\nfn main() -> UInt8 {\n    let _a = empty[ // why\n        UInt8,\n    ]()\n    0\n}\n",
        \\fn empty[T]() -> Option[T] {
        \\    .None
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _a = empty[
        \\        // why
        \\        UInt8,
        \\    ]()
        \\    0
        \\}
        \\
    );
}

test "type arguments before a call print as they were written" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn empty[T]() -> Option[T] { .None }\nfn main() -> UInt8 { let _a = empty[UInt8](); let _b = empty[[UInt8;2]](); let _c = empty[fn() -> UInt8](); 0 }\n",
        \\fn empty[T]() -> Option[T] {
        \\    .None
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let _a = empty[UInt8]()
        \\    let _b = empty[[UInt8; 2]]()
        \\    let _c = empty[fn() -> UInt8]()
        \\    0
        \\}
        \\
    );
}

test "a trailing comma breaks the list one element per line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "enum Step { Half, Whole, }\nfn main() -> UInt8 { 1 }\n",
        \\enum Step {
        \\    Half,
        \\    Whole,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
    );
}

test "a trailing-comma generic list finds its outer bracket after a callable bound" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\trait Give[phantom T] {}
        \\fn take[
        \\    F: Give[fn(read value: UInt8) -> UInt8],
        \\](_value: F) -> () {}
        \\fn main() -> UInt8 { 0 }
        \\
    ,
        \\trait Give[phantom T] {}
        \\
        \\fn take[
        \\    F: Give[fn(read value: UInt8) -> UInt8],
        \\](_value: F) -> () {}
        \\
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\
    );
}

test "general trailing where clauses stay flat on every declaration kind" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\struct Box[T]where T:Copyable{value:T}
        \\enum Maybe[T]where T:Copyable{None,Some(T)}
        \\trait Convert[T]where T:Copyable{fn convert(value:T)->T}
        \\fn main()->UInt8{0}
        \\
    ,
        \\struct Box[T] where T: Copyable { value: T }
        \\
        \\enum Maybe[T] where T: Copyable { None, Some(T) }
        \\
        \\trait Convert[T] where T: Copyable {
        \\    fn convert(value: T) -> T
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\
    );
}

test "general trailing where clauses preserve multiline layout commas and comments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The semicolon is the formatter's one permitted dropped token. The
    // following comment and signature pin the clause's actual boundary.
    try check(arena.allocator(),
        \\trait Convert[A, B]
        \\where
        \\    A: Copyable, // first requirement
        \\    B: Copyable,
        \\{
        \\    fn checked(value: A) -> B
        \\    where
        \\        A: Copyable,
        \\        B: Copyable; // checked requirement
        \\
        \\    // The second operation remains a declaration of the trait.
        \\    fn convert(value: A) -> B
        \\    where
        \\        A: Copyable,
        \\        B: Copyable,
        \\}
        \\fn main() -> UInt8 { 0 }
        \\
    ,
        \\trait Convert[A, B]
        \\where
        \\    A: Copyable, // first requirement
        \\    B: Copyable,
        \\{
        \\    fn checked(value: A) -> B
        \\    where
        \\        A: Copyable,
        \\        B: Copyable // checked requirement
        \\
        \\    // The second operation remains a declaration of the trait.
        \\    fn convert(value: A) -> B
        \\    where
        \\        A: Copyable,
        \\        B: Copyable,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\
    );
}

test "a list broken without a trailing comma is collapsed" {
    // Newlines are not the marker; the comma is. Treating an existing newline
    // as significant would make layout depend on history rather than on a
    // character anyone can see.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "enum Step {\n    Half,\n    Whole\n}\nfn main() -> UInt8 { 1 }\n",
        \\enum Step { Half, Whole }
        \\
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
    );
}

test "a call's arguments follow the same rule without padding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn add(a: UInt8, b: UInt8) -> UInt8 { a + b }\nfn main() -> UInt8 { add( 1 , 2 ) }\n",
        \\fn add(a: UInt8, b: UInt8) -> UInt8 {
        \\    a + b
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    add(1, 2)
        \\}
        \\
    );
}

test "a non-empty block arm forces the list to break and gains a comma" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\enum Colour { Red, Blue }
        \\fn weigh(c: Colour) -> UInt8 { match read c { Red => { let b: UInt8 = 2; b * 3 }, Blue => 1 } }
        \\fn main() -> UInt8 { weigh(.Red) }
        \\
    ,
        \\enum Colour { Red, Blue }
        \\
        \\fn weigh(c: Colour) -> UInt8 {
        \\    match read c {
        \\        Red => {
        \\            let b: UInt8 = 2
        \\            b * 3
        \\        },
        \\        Blue => 1,
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    weigh(.Red)
        \\}
        \\
    );
}

test "an empty block arm stays flat" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\enum Colour { Red }
        \\fn ignore(c: Colour) -> () { match c { Red => {} } }
        \\fn main() -> UInt8 { ignore(.Red); 1 }
        \\
    ,
        \\enum Colour { Red }
        \\
        \\fn ignore(c: Colour) -> () {
        \\    match c { Red => {} }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    ignore(.Red)
        \\    1
        \\}
        \\
    );
}

test "a struct's fields break when the author gave a trailing comma" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "struct Plan { remaining: UInt8, step: UInt8, }\nfn main() -> UInt8 { 1 }\n",
        \\struct Plan {
        \\    remaining: UInt8,
        \\    step: UInt8,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
    );
}

test "no line ends in whitespace, whatever interrupts it" {
    // Lazy indentation keeps an empty line empty, but the hazard is a line
    // whose last write was a space -- an operator continuing onto the next
    // line, with a comment flushed in between.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 {\n    let x: UInt8 = 1 +\n        // c\n        2\n    x\n}\n",
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1 +
        \\    // c
        \\    2
        \\    x
        \\}
        \\
    );
}

test "a carriage return does not survive into the output" {
    // The formatter writes LF and nothing else. A comment token runs to the
    // newline, so on CRLF source its text ends in a CR -- which is copied
    // through unless the text is trimmed where it is written.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const gpa = arena.allocator();
    const text = "fn main() -> UInt8 {\r\n    // c\r\n    0\r\n}\r\n";
    const source: Source = .{ .path = "fmt.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(!sink.hasErrors());
    try testing.expect(std.mem.indexOfScalar(u8, try formatAlloc(gpa, &ast), '\r') == null);
}

test "a comment on the same line as the code before it trails that line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 {\n    let a = 1;   // trails\n    a\n}\n",
        \\fn main() -> UInt8 {
        \\    let a = 1 // trails
        \\    a
        \\}
        \\
    );
}

test "a comment on its own line is re-indented to structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 {\n// under-indented\n    1\n}\n",
        \\fn main() -> UInt8 {
        \\    // under-indented
        \\    1
        \\}
        \\
    );
}

test "a comment above a declaration stays above it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "// what this does\nfn main() -> UInt8 { 1 }\n",
        \\// what this does
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
    );
}

test "a comment forces a flat list to break and the comma is inserted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "enum Step { Half, // cheap\n            Whole }\nfn main() -> UInt8 { 1 }\n",
        \\enum Step {
        \\    Half, // cheap
        \\    Whole,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
    );
}

test "a run of blank lines collapses to one and block edges are trimmed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn a() -> UInt8 {\n\n    1\n\n}\n\n\n\nfn b() -> UInt8 { 2 }\n",
        \\fn a() -> UInt8 {
        \\    1
        \\}
        \\
        \\fn b() -> UInt8 {
        \\    2
        \\}
        \\
    );
}

test "a blank line the author put between statements is kept" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 {\n    let a = 1;\n\n    let b = 2;\n    a + b\n}\n",
        \\fn main() -> UInt8 {
        \\    let a = 1
        \\
        \\    let b = 2
        \\    a + b
        \\}
        \\
    );
}

test "a comment after the last declaration is not lost" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { 1 }\n// trailing thought\n",
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
        \\// trailing thought
        \\
    );
}

test "an off region is copied byte for byte" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    // linea fmt: off
        \\    let   a   =   1;
        \\    // linea fmt: on
        \\    let   b   =   2;
        \\    a + b
        \\}
        \\
    ,
        \\fn main() -> UInt8 {
        \\    // linea fmt: off
        \\    let   a   =   1;
        \\    // linea fmt: on
        \\    let b = 2
        \\    a + b
        \\}
        \\
    );
}

test "an unclosed off region runs to end of file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src =
        \\// linea fmt: off
        \\fn main( ) -> UInt8 {   1   }
        \\
    ;
    try check(arena.allocator(), src, src);
}

test "an off region ends at the first on, so markers do not nest" {
    // There is no nesting to forbid: an inner `off` lies inside the verbatim
    // span and is text like everything else there. Worth pinning, because the
    // alternative reading -- that regions stack and need two `on` markers to
    // close -- is what a reader might assume.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    // linea fmt: off
        \\    let   a   =   1;
        \\    // linea fmt: off
        \\    let   b   =   2;
        \\    // linea fmt: on
        \\    let   c   =   3;
        \\    a + b + c
        \\}
        \\
    ,
        \\fn main() -> UInt8 {
        \\    // linea fmt: off
        \\    let   a   =   1;
        \\    // linea fmt: off
        \\    let   b   =   2;
        \\    // linea fmt: on
        \\    let c = 3
        \\    a + b + c
        \\}
        \\
    );
}

test "deep nesting formats without quadratic behaviour" {
    // As deep as a program may nest. The printer recurses per node exactly as
    // the parser does, and the parser rejects anything deeper, so the printer
    // is never handed a tree it cannot print -- a bound stated as a rule
    // rather than found by running out of stack.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const depth = max_nesting - 1;
    var src: std.ArrayList(u8) = .empty;
    try src.appendSlice(gpa, "fn main() -> UInt8 {\n    ");
    try src.appendNTimes(gpa, '(', depth);
    try src.append(gpa, '1');
    try src.appendNTimes(gpa, ')', depth);
    try src.appendSlice(gpa, "\n}\n");

    var want: std.ArrayList(u8) = .empty;
    try want.appendSlice(gpa, "fn main() -> UInt8 {\n    ");
    try want.appendNTimes(gpa, '(', depth);
    try want.append(gpa, '1');
    try want.appendNTimes(gpa, ')', depth);
    try want.appendSlice(gpa, "\n}\n");

    try check(gpa, src.items, want.items);
}

test "a file holding nothing but comments is left as it is" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "// one\n// two\n",
        \\// one
        \\// two
        \\
    );
}

test "a stray on marker is an ordinary comment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 {\n    // linea fmt: on\n    1\n}\n",
        \\fn main() -> UInt8 {
        \\    // linea fmt: on
        \\    1
        \\}
        \\
    );
}

test "a marker that is not on its own line is an ordinary comment" {
    // A boundary is where a statement could begin. Anywhere else the words are
    // a comment, which is what keeps the hatch free of a diagnostic.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 {\n    let a  =  1; // linea fmt: off\n    a\n}\n",
        \\fn main() -> UInt8 {
        \\    let a = 1 // linea fmt: off
        \\    a
        \\}
        \\
    );
}

test "a semicolon before the closing brace is dropped" {
    // The parser eats it without recording it, so `{ e; }` and `{ e }` are one
    // tree and one program. Writing it back would mean inventing which of the
    // two the author wrote, and dropping it cannot change meaning because the
    // language already draws no distinction.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try check(arena.allocator(), "fn main() -> UInt8 { 1; }",
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\
    );
}

test "a defer the parser read no expression for still formats" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The frontend never fails, so the tree a broken file yields is one the
    // printer has to walk. `defer` with nothing after it is the one statement
    // whose expression the parser can come away without, and a formatter and a
    // language server read source that is broken most of the time.
    const source: Source = .{ .path = "fmt.lin", .text = "fn main() -> UInt8 {\n    defer\n}\n" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(sink.hasErrors());

    var out: std.Io.Writer.Allocating = .init(gpa);
    try format(gpa, &ast, &out.writer);
}

test "a traversal receiver survives formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(arena.allocator(), "impl Grid{trav positions(self:Self)=UInt64(0)..copy(self.len)}",
        \\impl Grid {
        \\    trav positions(self: Self) = UInt64(0)..copy(self.len)
        \\}
        \\
    );
}

test "borrow values and source contracts survive formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(arena.allocator(), "fn observe(x:UInt8)->borrow UInt8 where borrows(x){borrow x}",
        \\fn observe(x: UInt8) -> borrow UInt8 where borrows(x) {
        \\    borrow x
        \\}
        \\
    );
    try check(arena.allocator(), "fn forward(x:borrow UInt8)->borrow UInt8 where carries(x){copy(x)}",
        \\fn forward(x: borrow UInt8) -> borrow UInt8 where carries(x) {
        \\    copy(x)
        \\}
        \\
    );
    try check(arena.allocator(), "fn save(inout dst:Holder,src:UInt8)->() where retains(dst:borrow src){dst.value=borrow src}",
        \\fn save(inout dst: Holder, src: UInt8) -> () where retains(dst: borrow src) {
        \\    dst.value = borrow src
        \\}
        \\
    );
}

test "borrow contracts distinguish a grouped callable result" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(
        arena.allocator(),
        "fn outer(source: Str) -> (fn(read value: Str) -> Str where carries(value)) where carries(source) { panic(source) }\n",
        "fn outer(source: Str) -> (fn(read value: Str) -> Str where carries(value)) where carries(source) {\n    panic(source)\n}\n",
    );
}

test "borrow empty carries clause preserves explicit independence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(
        arena.allocator(),
        "fn independent(source: Data) -> Data where carries() { source }\n",
        "fn independent(source: Data) -> Data where carries() {\n    source\n}\n",
    );
}

test "borrow result targets preserve branch and field paths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(
        arena.allocator(),
        "fn select(a: Data, b: Data) -> Result[Data, Error] where carries(.Ok.field: a, b), borrows(.Err: a.field) { panic(a) }\n",
        "fn select(a: Data, b: Data) -> Result[Data, Error] where carries(.Ok.field: a, b), borrows(.Err: a.field) {\n    panic(a)\n}\n",
    );
}

test "constant inference preserves omitted and explicit annotations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(arena.allocator(), "let answer=7\nlet explicit:UInt8=2\n", "let answer = 7\n\nlet explicit: UInt8 = 2\n");
}

test "record shorthand survives formatting beside explicit fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(arena.allocator(), "fn make()->Entry{.{key,value=value}}",
        \\fn make() -> Entry {
        \\    .{ key, value = value }
        \\}
        \\
    );
}

test "transparent observation projections and contract groups survive formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(arena.allocator(), "fn inspect(view:borrow Holder)->UInt8 where carries(*view.item,(*view).item,**view){*view.item+(*view).value}",
        \\fn inspect(view: borrow Holder) -> UInt8 where carries(*view.item, (*view).item, **view) {
        \\    *view.item + (*view).value
        \\}
        \\
    );
}

test "omitted test signatures survive formatting twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\test fn succeeds() {}
        \\
        \\test fn returns() {
        \\    return
        \\}
        \\
        \\test fn custom() -> Result[(), Failure] {
        \\    return .Ok(())
        \\}
        \\
        \\test trap fn traps() {
        \\    panic("expected")
        \\}
        \\
    ;
    try check(arena.allocator(), "test fn succeeds(){}\ntest fn returns(){return}\ntest fn custom()->Result[(),Failure]{return .Ok(())}\ntest trap fn traps(){panic(\"expected\")}\n", written);
    try check(arena.allocator(), written, written);
}

test "inferred destructure preserves shorthand aliases and empty patterns when formatted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(arena.allocator(), "fn take()->(){let{field,other:renamed}=value;let{}=empty}",
        \\fn take() -> () {
        \\    let { field, other: renamed } = value
        \\    let {} = empty
        \\}
        \\
    );
}

test "borrowed let keeps its read marker when formatted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\fn take() -> () {
        \\    let read Label(raw) = label
        \\    let read Point { x, y: _ } = point
        \\    let read {} = empty
        \\}
        \\
    ;
    try check(arena.allocator(), "fn take()->(){let read Label(raw)=label;let read Point{x,y:_}=point;let read{}=empty}", written);
    try check(arena.allocator(), written, written);
}

test "a comment between let and read stays between them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\fn take() -> () {
        \\    let // observe the point
        \\    read Point { x } = point
        \\}
        \\
    ;
    try check(arena.allocator(),
        \\fn take() -> () {
        \\    let // observe the point
        \\        read Point { x } = point
        \\}
    , written);
    try check(arena.allocator(), written, written);
}

test "a comment in a braced literal's head settles in one pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\fn main() -> () {
        \\    let c = Cell[UInt8] {
        \\        // element type
        \\        value = 1,
        \\    }
        \\    let d: Cell[UInt8] = .{
        \\        // contextual
        \\        value = 2,
        \\    }
        \\}
        \\
    ;
    try check(arena.allocator(),
        \\fn main() -> () {
        \\    let c = Cell[ // element type
        \\        UInt8] { value = 1 }
        \\    let d: Cell[UInt8] = . // contextual
        \\    { value = 2 }
        \\}
    , written);
    try check(arena.allocator(), written, written);
}

test "explicit read capture lists preserve aliases and format twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\fn main() -> UInt8 {
        \\    let threshold = UInt8(3)
        \\    let above = read [read limit = threshold] |item: UInt8| item > limit
        \\    if above(4) {
        \\        0
        \\    } else {
        \\        1
        \\    }
        \\}
        \\
    ;
    try check(arena.allocator(), "fn main()->UInt8{let threshold=UInt8(3);let above=read[read limit=threshold]|item:UInt8|item>limit;if above(4){0}else{1}}", written);
    try check(arena.allocator(), written, written);
}

test "explicit read capture mode with an empty list formats twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\fn main() -> UInt8 {
        \\    let answer = read [] || UInt8(3)
        \\    answer()
        \\}
        \\
    ;
    try check(arena.allocator(), written, written);
}

test "capture defaults preserve omitted modes and aliases when formatted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\fn main() -> UInt8 {
        \\    let number = UInt8(3)
        \\    let sum = [number, other = number] || number + other
        \\    sum()
        \\}
        \\
    ;
    try check(arena.allocator(), "fn main()->UInt8{let number=UInt8(3);let sum=[number,other=number]||number+other;sum()}", written);
    try check(arena.allocator(), written, written);
}

test "mutable invocation and callable bounds preserve their conventions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\fn invoke[F: inout fn() -> UInt8](inout callback: F) -> UInt8 {
        \\    &callback() + 1
        \\}
        \\
    ;
    try check(arena.allocator(), "fn invoke[F:inout fn()->UInt8](inout callback:F)->UInt8{&callback()+1}", written);
    try check(arena.allocator(), written, written);
}

test "lambda result annotations format after the arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source = "fn main()->UInt8{let f=[owner]|value:borrow UInt8|->borrow UInt8 where carries(value), borrows(owner) value;0}";
    const formatted =
        \\fn main() -> UInt8 {
        \\    let f = [owner] |value: borrow UInt8| -> borrow UInt8 where carries(value), borrows(owner) value
        \\    0
        \\}
        \\
    ;
    try check(arena.allocator(), source, formatted);
    try check(arena.allocator(), formatted, formatted);
}

test "lambda result annotations format inferred result contracts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source = "fn main()->UInt8{let f=[number]||->where borrows(number){borrow number};0}";
    const formatted =
        \\fn main() -> UInt8 {
        \\    let f = [number] || -> where borrows(number) {
        \\        borrow number
        \\    }
        \\    0
        \\}
        \\
    ;
    try check(arena.allocator(), source, formatted);
    try check(arena.allocator(), formatted, formatted);
}

test "where contract lists preserve source order across predicates and contracts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source = "fn observe[T](value:T)->borrow T where borrows(value),T:Copyable,carries(value){borrow value}";
    const formatted =
        \\fn observe[T](value: T) -> borrow T where borrows(value), T: Copyable, carries(value) {
        \\    borrow value
        \\}
        \\
    ;
    try check(arena.allocator(), source, formatted);
    try check(arena.allocator(), formatted, formatted);
}

test "empty capture lists preserve formatter off regions before their closer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const written =
        \\fn main() -> UInt8 {
        \\    let answer = [
        \\    // linea fmt: off
        \\    ] || UInt8(3)
        \\    answer()
        \\}
        \\
    ;
    try check(arena.allocator(), written, written);
}

test "source contract trailing commas preserve nested callable boundaries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source =
        \\fn main() -> UInt8 {
        \\    let braced = || -> where carries(), { 7 }
        \\    let expression = || -> UInt8 where carries(), 8
        \\    let typed: (fn() -> UInt8 where carries(),) = || 9
        \\    let factory = || -> fn() -> UInt8 where carries(), || 10
        \\    if braced() == 7 && expression() == 8 && typed() == 9 && factory()() == 10 {
        \\        0
        \\    } else {
        \\        1
        \\    }
        \\}
        \\
        \\fn invoke(callback: fn() -> UInt8 where carries(), value: UInt8) -> UInt8 { callback() + value }
        \\
    ;
    const result = try checkProperties(arena.allocator(), source);
    try testing.expect(result == .checked);
}

test "bare match arm jumps preserve their comma boundary" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source = "fn main() -> () { loop { match item { None => break, Some(_) => continue, } } match item { None => return, Some(_) => {}, } }";
    try testing.expect(try checkProperties(arena.allocator(), source) == .checked);
}

test "source contract trailing commas preserve generic parameter separators" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source =
        \\struct Holder { callback: fn() -> UInt8 where carries(), }
        \\fn fold_one[
        \\    A,
        \\    T,
        \\    F: fn(sink accumulator: A, sink item: T) -> A where carries(accumulator, item),
        \\](inout accumulator: A, sink item: T, combine: F) -> () where retains(accumulator: item, combine) {
        \\    accumulator = combine(accumulator, item)
        \\}
        \\fn apply(callback: fn(value: UInt8) -> UInt8 where carries(value),) -> UInt8 { callback(7) }
        \\
    ;
    const result = try checkProperties(arena.allocator(), source);
    try testing.expect(result == .checked);
}

test "declaration selection renders noncontiguous source modules" {
    const program_mod = @import("../syntax/program.zig");
    const Modules = @import("../parser/parser.zig").Modules;
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink: Sink = .init(gpa);
    var interner: Interner = .empty;
    var trees = Modules.init(gpa, &sink, &interner);
    defer trees.deinit();
    const texts = [_][]const u8{
        "// excluded first\nfn library() -> UInt8 { 0 }\n",
        "// selected first\nfn main() -> UInt8 { 1 }\n",
        "// excluded middle\n",
        "// selected last\nfn child() -> UInt8 { 3 }\n",
    };
    var modules: [texts.len]program_mod.Module = undefined;
    for (texts, 0..) |text, i| {
        const range = try trees.add(&.{.{ .file = .from(i), .source = .{ .path = "selection.lin", .text = text } }});
        modules[i] = .{ .name = "selection", .dir = "selection", .files = &.{}, .decls = range, .imports = &.{}, .library = i % 2 == 0 };
    }
    const ast = try trees.finish();
    const program: program_mod.Program = .{ .modules = &modules, .primary = .from(1), .ast = ast };
    try testing.expect(!sink.hasErrors());
    var out: std.Io.Writer.Allocating = .init(gpa);
    try formatNoted(gpa, &ast, .none, program.ownDeclarations(), &out.writer);
    try testing.expectEqualStrings("// selected first\nfn main() -> UInt8 {\n    1\n}\n\n// selected last\nfn child() -> UInt8 {\n    3\n}\n", out.written());
}

test "empty declaration selection excludes library comments" {
    const program_mod = @import("../syntax/program.zig");
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink: Sink = .init(gpa);
    var interner: Interner = .empty;
    const source: Source = .{ .path = "comments.lin", .text = "// source comment\n" };
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    const ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var modules = [_]program_mod.Module{.{ .name = "comments", .dir = "comments", .files = &.{.from(0)}, .decls = .{ .start = 0, .end = 0 }, .imports = &.{}, .library = true }};
    const program: program_mod.Program = .{ .modules = &modules, .ast = ast };
    var excluded: std.Io.Writer.Allocating = .init(gpa);
    try formatNoted(gpa, &ast, .none, program.ownDeclarations(), &excluded.writer);
    try testing.expectEqualStrings("", excluded.written());
    modules[0].library = false;
    var selected: std.Io.Writer.Allocating = .init(gpa);
    try formatNoted(gpa, &ast, .none, program.ownDeclarations(), &selected.writer);
    try testing.expectEqualStrings(source.text, selected.written());
    var standalone: std.Io.Writer.Allocating = .init(gpa);
    try format(gpa, &ast, &standalone.writer);
    try testing.expectEqualStrings(source.text, standalone.written());
}

test "field delegation formatting preserves contextual targets" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(arena.allocator(), "impl[T] index.Index[UInt64] for Board[T] where T:Copyable via scores;\nimpl Board{trav positions via via}",
        \\impl[T] index.Index[UInt64] for Board[T] where T: Copyable via scores
        \\
        \\impl Board {
        \\    trav positions via via
        \\}
        \\
    );
}

test "field delegation formatting retains comments and is idempotent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "fmt.lin", .text =
        \\impl[T] Index[UInt64] for Board[T] where T: Copyable, // bound
        \\via // field
        \\scores // delegated
        \\impl Board { trav positions via scores // positions
        \\}
    };
    var sink = Sink.init(gpa);
    var names: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(!sink.hasErrors());
    const formatted = try formatAlloc(gpa, &ast);
    for ([_][]const u8{ "// bound", "// field", "// delegated", "// positions" }) |comment| {
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, formatted, comment));
    }
    try check(gpa, formatted, formatted);
}

test "formatter preserves written selection bases and groups" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const want =
        \\fn select[T](_value: module.Box[T].Item) -> (Box[T]).Item.Next {
        \\    panic("unused")
        \\}
        \\
    ;
    try check(arena.allocator(), "fn select[T](_value:module.Box [T] . Item)->(Box[T]).Item.Next{panic(\"unused\")}", want);
    try check(arena.allocator(), want, want);
}

test "declaration attributes retain written groups without repeating policies" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try check(arena.allocator(), "@linear\n struct Resource {value:UInt8}\n",
        \\@linear
        \\struct Resource { value: UInt8 }
        \\
    );
    try check(arena.allocator(), "@( opaque ,linear,derive(Debug,Release))struct Resource {value:UInt8}\n",
        \\@(opaque, linear, derive(Debug, Release))
        \\struct Resource { value: UInt8 }
        \\
    );
    try check(arena.allocator(), "@copyable type Count=UInt8\n",
        \\@copyable
        \\type Count = UInt8
        \\
    );
    try check(arena.allocator(), "@copyable\n// representation\n@derive(Debug)pub enum Flag{Off,On}\n",
        \\@copyable
        \\// representation
        \\@derive(Debug)
        \\pub enum Flag { Off, On }
        \\
    );
}

test "declaration attributes preserve nested list comments and trailing commas" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "fmt.lin", .text =
        \\@(copyable, // policy
        \\derive(Debug, // first trait
        \\Release,), // request
        \\)
        \\// representation
        \\struct Item{value:UInt8}
    };
    var sink = Sink.init(gpa);
    const result = try formatSource(gpa, &source, .from(0), &sink);
    try testing.expect(!sink.hasErrors());
    const formatted = result.text orelse return error.TestUnexpectedResult;
    for ([_][]const u8{ "// policy", "// first trait", "// request", "// representation" }) |comment| {
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, formatted, comment));
    }
    try testing.expect(std.mem.indexOf(u8, formatted, "    derive(\n") != null);
    try check(gpa, formatted, formatted);
}

test "declaration attributes omit only selected derive traits and preserve comments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "fmt.lin", .text =
        \\@(copyable, derive(First, Second))
        \\@derive(Third) // completed request
        \\@(derive(Fourth), // completed group
        \\)
        \\struct Item { value: UInt8 }
    };
    var sink = Sink.init(gpa);
    var names: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &names);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    try testing.expect(!sink.hasErrors());
    try testing.expectEqual(@as(usize, 4), ast.derive_traits.len);
    var out: std.Io.Writer.Allocating = .init(gpa);
    try formatNoted(gpa, &ast, .{ .omit_derive_traits = &.{ true, false, true, true } }, DeclarationSelection.all(ast.declCount()), &out.writer);
    const formatted = out.written();
    try testing.expect(std.mem.indexOf(u8, formatted, "@(copyable, derive(Second))") != null);
    for ([_][]const u8{ "First", "Third", "Fourth", "@derive", "@(derive" }) |removed| {
        try testing.expect(std.mem.indexOf(u8, formatted, removed) == null);
    }
    for ([_][]const u8{ "// completed request", "// completed group" }) |comment| {
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, formatted, comment));
    }
    try check(gpa, formatted, formatted);
}

test "declaration attributes refuse malformed input without rewriting it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    for ([_][]const u8{ "@() struct Item {}", "@derive() struct Item {}", "@linear", "@(linear struct Item {}" }) |text| {
        const source: Source = .{ .path = "fmt.lin", .text = text };
        var sink = Sink.init(gpa);
        const result = try formatSource(gpa, &source, .from(0), &sink);
        try testing.expect(sink.hasErrors());
        try testing.expect(result.text == null);
    }
}

test "declaration attributes participate in the formatter structural guard" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const cases = [_]struct { before: []const u8, after: []const u8, equal: bool }{
        .{ .before = "@derive(Score) struct Item {}", .after = "struct Item {}", .equal = false },
        .{ .before = "@derive(Score) struct Item {}", .after = "@derive(Other) struct Item {}", .equal = false },
        .{ .before = "@derive(Score) struct One {} struct Two {}", .after = "struct One {} @derive(Score) struct Two {}", .equal = false },
        .{ .before = "@(copyable, derive(Score)) struct Item {}", .after = "@copyable @derive(Score) struct Item {}", .equal = false },
        .{ .before = "@(copyable, derive(Score)) struct Item {}", .after = "@(copyable, // policy\n derive(Score,),)\nstruct Item {}", .equal = true },
    };
    for (cases) |case| {
        const before_source: Source = .{ .path = "fmt.lin", .text = case.before };
        const after_source: Source = .{ .path = "fmt.lin", .text = case.after };
        var sink = Sink.init(gpa);
        var names: Interner = .empty;
        const before_tokens = try tokenize(gpa, &before_source, .from(0), &sink, &names);
        var before = try parse(gpa, &before_source, .from(0), before_tokens, &sink);
        const after_tokens = try tokenize(gpa, &after_source, .from(0), &sink, &names);
        var after = try parse(gpa, &after_source, .from(0), after_tokens, &sink);
        try testing.expect(!sink.hasErrors());
        try testing.expectEqual(case.equal, try sameShape(gpa, &before, &after));
    }
}

test "declaration attributes preserve formatting hatches before and inside groups" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    try check(gpa,
        \\// linea fmt: off
        \\@linear   struct  Kept{value:UInt8}
        \\// linea fmt: on
        \\struct Next{value:UInt8}
        \\
    ,
        \\// linea fmt: off
        \\@linear   struct  Kept{value:UInt8}
        \\// linea fmt: on
        \\
        \\struct Next { value: UInt8 }
        \\
    );
    const input =
        \\@(linear,
        \\    // linea fmt: off
        \\  derive(Debug))
        \\struct  Kept{value:UInt8}
        \\// linea fmt: on
        \\struct Next{value:UInt8}
        \\
    ;
    const expected =
        \\@(
        \\    linear,
        \\    // linea fmt: off
        \\  derive(Debug))
        \\struct  Kept{value:UInt8}
        \\// linea fmt: on
        \\
        \\struct Next { value: UInt8 }
        \\
    ;
    try check(gpa, input, expected);
    try check(gpa, expected, expected);
    const source: Source = .{ .path = "fmt.lin", .text = input };
    var sink = Sink.init(gpa);
    const result = try formatSource(gpa, &source, .from(0), &sink);
    try testing.expect(!sink.hasErrors());
    try testing.expectEqualStrings(expected, result.text orelse return error.TestUnexpectedResult);
}

test "a tuple is laid out by its trailing comma" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const flat =
        \\alias Pair = (UInt8, Str)
        \\
        \\fn split(pairs: Option[(UInt8, (Str, Bool))]) -> (UInt8, ()) {
        \\    let (a, _) = (1, (2))
        \\    let read (b, c) = place
        \\    ((a), ())
        \\}
        \\
    ;
    try check(gpa,
        \\alias Pair=(UInt8,Str)
        \\fn split(pairs:Option[(UInt8,(Str,Bool))])->(UInt8,()){
        \\let (a,_)=(1,(2))
        \\let read (b,c)=place
        \\((a),())
        \\}
        \\
    , flat);
    try check(gpa, flat, flat);

    const broken =
        \\fn main() -> UInt8 {
        \\    let pair: (
        \\        UInt8,
        \\        UInt8,
        \\    ) = (
        \\        3,
        \\        4,
        \\    )
        \\    let (
        \\        c,
        \\        d,
        \\    ) = pair
        \\    c + d
        \\}
        \\
    ;
    try check(gpa,
        \\fn main() -> UInt8 {
        \\    let pair: (UInt8, UInt8,) = (3, 4,)
        \\    let (c, d,) = pair
        \\    c + d
        \\}
        \\
    , broken);
    try check(gpa, broken, broken);

    // A callable type's result and an implementation's head are written types
    // like any other, and follow the same rule.
    const heads =
        \\impl First for (UInt8, Str) {}
        \\
        \\fn apply(g: fn(p: (UInt8, UInt8)) -> (
        \\    UInt8,
        \\    UInt8,
        \\)) -> (UInt8, UInt8) {
        \\    g((1, 2))
        \\}
        \\
    ;
    try check(gpa,
        \\impl First for (UInt8,Str) {}
        \\fn apply(g: fn(p: (UInt8, UInt8)) -> (UInt8, UInt8,)) -> (UInt8, UInt8) { g((1, 2)) }
        \\
    , heads);
    try check(gpa, heads, heads);

    // A list broken across lines without a trailing comma is collapsed.
    try check(gpa,
        \\fn main() -> UInt8 {
        \\    let (c,
        \\        d) = (3,
        \\        4)
        \\    c + d
        \\}
        \\
    ,
        \\fn main() -> UInt8 {
        \\    let (c, d) = (3, 4)
        \\    c + d
        \\}
        \\
    );
}

test "a tuple pattern is printed in a match arm and a for binder, by the comma rule" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const flat =
        \\fn walk(pairs: [(UInt8, UInt8); 2]) -> UInt8 {
        \\    for (i, _) in pairs {}
        \\    for read (a, b) in pairs {}
        \\    match pair {
        \\        (a, _) => a,
        \\    }
        \\}
        \\
    ;
    try check(gpa,
        \\fn walk(pairs:[(UInt8,UInt8);2])->UInt8{
        \\for (i,_) in pairs{}
        \\for read (a,b) in pairs{}
        \\match pair{(a,_)=>a,}
        \\}
        \\
    , flat);
    try check(gpa, flat, flat);

    const broken =
        \\fn walk(pairs: [(UInt8, UInt8); 2]) -> UInt8 {
        \\    for (
        \\        i,
        \\        x,
        \\    ) in pairs {}
        \\    match pair {
        \\        (
        \\            a,
        \\            b,
        \\        ) => a,
        \\    }
        \\}
        \\
    ;
    try check(gpa, broken, broken);
}

test "a lambda parameter's tuple pattern is printed where its name goes, by the comma rule" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const flat =
        \\fn main() -> UInt8 {
        \\    let a = |sink (i, x), n: UInt8| i
        \\    let b = |(left, _): (UInt8, UInt8)| left
        \\    let c = |inout (first, second)| first
        \\}
        \\
    ;
    try check(gpa,
        \\fn main()->UInt8{
        \\let a=|sink (i,x),n:UInt8|i
        \\let b=|(left,_):(UInt8,UInt8)|left
        \\let c=|inout (first,second)|first
        \\}
        \\
    , flat);
    try check(gpa, flat, flat);

    const broken =
        \\fn main() -> UInt8 {
        \\    let a = |sink (
        \\        i,
        \\        x,
        \\    ), n: UInt8| i
        \\}
        \\
    ;
    try check(gpa, broken, broken);
}

test "a comment inside a tuple breaks it one component per line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const want =
        \\fn main() -> UInt8 {
        \\    let pair: (
        \\        UInt8, // the count
        \\        Str,
        \\    ) = (
        \\        3, // three of them
        \\        "x",
        \\    )
        \\    let (
        \\        n, // the count again
        \\        _,
        \\    ) = pair
        \\    n
        \\}
        \\
    ;
    try check(gpa,
        \\fn main() -> UInt8 {
        \\    let pair: (UInt8, // the count
        \\        Str) = (3, // three of them
        \\        "x")
        \\    let (n, // the count again
        \\        _) = pair
        \\    n
        \\}
        \\
    , want);
    try check(gpa, want, want);
}

test "a tuple ending in a lambda or holding a broken chain is a normal form" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const want =
        \\fn main() -> UInt8 {
        \\    let (base, step) = (
        \\        UInt8(2),
        \\        |sink x: UInt8| {
        \\            let doubled = x * 2
        \\            doubled + 1
        \\        },
        \\    )
        \\    let (total, count) = (readings.as_slice()
        \\        .map(|sink reading| *reading)
        \\        .fold(0, |sink sum, sink reading| sum + reading), UInt8(3))
        \\    step(base) + total - count
        \\}
        \\
    ;
    const input =
        \\fn main() -> UInt8 {
        \\    let (base, step) = (UInt8(2), |sink x: UInt8| {
        \\        let doubled = x * 2
        \\        doubled + 1
        \\    })
        \\    let (total, count) = (readings.as_slice().map(|sink reading| *reading)
        \\        .fold(0, |sink sum, sink reading| sum + reading), UInt8(3))
        \\    step(base) + total - count
        \\}
        \\
    ;
    try check(gpa, input, want);
    try check(gpa, want, want);
    for ([_][]const u8{ input, want }) |text| {
        const result = try checkProperties(gpa, text);
        try testing.expectEqualStrings(want, result.checked.formatted);
    }
}
