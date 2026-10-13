//! What every token of a declaration becomes once nothing is generic.
//!
//! Monomorphisation decides this: which instantiation a written type became,
//! which copy a call reaches, what `Self` stands for. A renderer that worked it
//! out for itself would be a second monomorphisation, agreeing with the real
//! one until the day it did not -- so the answers are built here, beside the
//! queue that made them, and handed to whoever is printing.
//!
//! The notes are an overlay on the token stream: an entry replaces the text of
//! one token and an empty one leaves it alone. Nothing here writes anything.

const std = @import("std");

const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const token = @import("../lexer/token.zig");
const types = @import("../sema/types.zig");
const Typing = types.Typing;
const mir = @import("mir.zig");

/// Names a closure type from the source identity and enclosing arguments that
/// form its semantic key. Symbols are physical names and are not that key.
pub fn closureTypeName(
    gpa: std.mem.Allocator,
    typing: *const Typing,
    ty: types.TypeId,
) ![]const u8 {
    std.debug.assert(typing.get(ty) == .closure);
    return typing.mangledName(gpa, ty);
}

/// The name a selection path starts from, where it starts from a name at all.
pub fn headOfPath(ast: *const Ast, e: node.ExprId) ?node.ExprId {
    if (ast.exprTag(e) != .field) return null;
    const of = ast.unaryOperand(e);
    return if (ast.exprTag(of) == .name_ref) of else null;
}

/// Settles everything a declaration writes that stands for something else.
///
/// One routine for every kind the dump prints, because a note that applied to
/// one and not another is how a rendering comes to disagree with itself: a
/// declaration taking no type parameters is settled by the same three passes
/// as one that does, and each is a no-op where there is nothing to settle.
pub fn settle(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    types_of: *const Typing,
    pool: ?*types.Typing.Builder,
    origin: mir.Origin,
    tokens: [][]const u8,
) !void {
    const d = origin.decl;
    // Only what this declaration covers. Every note below is written inside
    // its own extent and a dump writes one declaration at a time, so what sits
    // outside it is never read for this item -- and clearing the whole overlay
    // cost the program's tokens for every item rendered, which is what a
    // monomorphised dump has most of.
    const extent = ast.declTokens(d);
    const from = @min(extent.start.index(), tokens.len);
    const to = @min(extent.end.index(), tokens.len);
    @memset(tokens[from..to], "");

    const ctx: NameContext = .{
        .ast = ast,
        .types_of = types_of,
        .pool = pool,
        .origin = origin,
    };

    try noteTypes(gpa, ctx, extent, tokens);
}

/// Which types the monomorphised program holds, by handle.
///
/// A signature, a slot or an instruction naming a type is the program holding
/// one, and what it holds is made of the types its parts are -- so the set
/// closes over fields and payloads: a declaration written below writes its
/// parts, and a part names a type that has to be declared beside it.
///
/// Read from the lowered code rather than from the pool. The pool is an intern
/// table holding every type the compilation could reach -- the library's, and
/// the ones the checker minted while checking a body nothing calls, including
/// the instantiation a generic signature makes at its own parameters. A dump
/// built from it grows with what was available rather than with what the
/// program does, and says `Cell[T]` in a program where nothing is generic.
pub fn typesHeld(gpa: std.mem.Allocator, module: *const mir.Module) ![]bool {
    const held = try gpa.alloc(bool, module.types.pool.len);
    @memset(held, false);

    // The same set the emitter declares from, and then what those hold: a
    // dump printing a type the emitted code does not name would be describing
    // a different program.
    module.markNamedTypes(held);

    // To a fixpoint, because a part is itself made of parts.
    var moved = true;
    while (moved) {
        moved = false;
        for (held, 0..) |in, i| {
            if (!in) continue;
            const t: types.TypeId = @enumFromInt(@as(u32, @intCast(i)));
            for (0..module.types.fieldCount(t)) |k| {
                moved = mark(held, module.types.fieldType(t, @intCast(k))) or moved;
            }
            for (0..module.types.variantCount(t)) |v| {
                const at: u32 = @intCast(v);
                for (0..module.types.variantFieldCount(t, at)) |k| {
                    moved = mark(held, module.types.variantFieldType(t, at, @intCast(k))) or moved;
                }
            }
        }
    }
    return held;
}

/// Records that the program holds a type, and says whether that was news.
fn mark(held: []bool, t: types.TypeId) bool {
    if (held[@intFromEnum(t)]) return false;
    held[@intFromEnum(t)] = true;
    return true;
}

/// What naming a written type takes: the instantiation being rendered, and the
/// pool to spell a type from.
const NameContext = struct {
    ast: *const Ast,
    types_of: *const Typing,
    /// Where a written type is substituted through the instantiation being
    /// rendered. Null where the caller holds no pool, which leaves the written
    /// types unnoted rather than noted wrongly.
    pool: ?*types.Typing.Builder,
    /// The declaration this rendering is one copy of, and what it was
    /// instantiated with.
    origin: mir.Origin,
};

/// Points every written generic type at the name its instantiation goes by.
///
/// A signature says `Pair[A, B]` and there is no `Pair` once nothing is
/// generic -- there is a `Pair.u8.bool` and a `Pair.bool.u8`. Which one a
/// written type became is decided by what its arguments became, which the
/// notes already say.
fn noteTypes(
    gpa: std.mem.Allocator,
    ctx: NameContext,
    extent: token.TokenRange,
    tokens: [][]const u8,
) !void {
    const pool = ctx.pool orelse return;

    var t = extent.start.index();
    while (t < extent.end.index()) : (t += 1) {
        if (tokens[t].len > 0) continue;

        // What the checker settled this token to, rather than what follows it
        // in the source. Which instantiation a written type became is the
        // fixed point the checker ran, and an argument written as one of the
        // declaration's own parameters was settled before any name was built
        // from it -- neither is in the source to be read.
        const written = ctx.types_of.writtenType(@intCast(t)) orelse continue;
        if (written == .poison) continue;

        // Through the instantiation being rendered, for the reason a
        // constructor is: this is one copy of a generic body, and the type
        // written `Cell[T]` in it is `Cell[u8]` here.
        const built = try ctx.origin.through(pool, written);
        const view = pool.view();
        const spelled = try view.mangledName(gpa, built);

        // Only where the name it goes by is not the name it was written as.
        // A note that repeats the token says nothing and costs a comparison
        // everywhere it is read.
        if (std.mem.eql(u8, spelled, ctx.ast.tokenText(token.TokenId.at(@intCast(t))))) {
            gpa.free(spelled);
            continue;
        }
        tokens[t] = spelled;
    }
}

/// Every expression that could name the type it builds, in token order.
///
/// Built once and read per item written. The walk was every expression in the
/// program, narrowed to the one declaration being rendered -- so a dump paid
/// the program for each of the items it writes, and a monomorphised program is
/// mostly items. Sorted by the token the head sits at, because that is what
/// the narrowing compared.
pub const Constructors = struct {
    at: []const u32,
    expr: []const node.ExprId,
    head: []const node.ExprId,

    const Site = struct { at: u32, expr: node.ExprId, head: node.ExprId };

    pub fn build(gpa: std.mem.Allocator, ast: *const Ast) !Constructors {
        var found: std.ArrayList(Site) = .empty;
        defer found.deinit(gpa);

        for (0..ast.exprCount()) |i| {
            const id = node.ExprId.at(@intCast(i));
            const head = switch (ast.exprTag(id)) {
                .call => headOfPath(ast, ast.call(id).callee) orelse continue,
                .field => headOfPath(ast, id) orelse continue,
                else => continue,
            };
            try found.append(gpa, .{
                .at = @intCast(ast.exprMain(head).index()),
                .expr = id,
                .head = head,
            });
        }

        std.mem.sort(Site, found.items, {}, struct {
            fn less(_: void, a: Site, b: Site) bool {
                return a.at < b.at;
            }
        }.less);

        const at = try gpa.alloc(u32, found.items.len);
        errdefer gpa.free(at);
        const expr = try gpa.alloc(node.ExprId, found.items.len);
        errdefer gpa.free(expr);
        const head = try gpa.alloc(node.ExprId, found.items.len);
        errdefer gpa.free(head);
        for (found.items, 0..) |site, k| {
            at[k] = site.at;
            expr[k] = site.expr;
            head[k] = site.head;
        }
        return .{ .at = at, .expr = expr, .head = head };
    }

    pub fn deinit(self: *Constructors, gpa: std.mem.Allocator) void {
        gpa.free(self.at);
        gpa.free(self.expr);
        gpa.free(self.head);
    }

    fn lowerBound(self: *const Constructors, token_at: u32) usize {
        var lo: usize = 0;
        var hi: usize = self.at.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.at[mid] < token_at) lo = mid + 1 else hi = mid;
        }
        return lo;
    }
};

/// Points each constructor at the type it builds.
///
/// `Maybe.Some(..)` names the declaration, and once nothing is generic there
/// is no `Maybe` -- there is a `Maybe.bool` and a `Maybe.u8`. Which one this
/// builds is what the expression's type says, read through the instantiation
/// being rendered rather than through the one the checker was looking at.
pub fn noteConstructors(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    typing: *const Typing,
    pool: *types.Typing.Builder,
    origin: mir.Origin,
    extent: token.TokenRange,
    tokens: [][]const u8,
    sites: *const Constructors,
) !void {
    var k = sites.lowerBound(@intCast(extent.start.index()));
    while (k < sites.at.len and sites.at[k] < extent.end.index()) : (k += 1) {
        const id = sites.expr[k];
        const head = sites.head[k];
        const at = sites.at[k];

        const built = try origin.through(pool, typing.expr_types[id.index()]);
        const view = pool.view();
        const inst = view.instanceOf(built) orelse continue;

        // Only where the head names the declaration the type came from:
        // `Maybe.Some` builds a `Maybe` and `Account.open` builds whatever it
        // returns.
        const from = inst.decl;
        if (!std.mem.eql(u8, ast.tokenText(ast.exprMain(head)), ast.tokenText(ast.declName(from)))) continue;

        tokens[at] = try view.mangledName(gpa, built);
    }
}

/// Points each call in a body at the copy it reaches.
///
/// Which one that is was decided when the body was lowered, so it is read back
/// off the call instruction rather than worked out again: the rule that says
/// which instantiations exist lives in one place, and this is not it. Lowering
/// recorded which instruction each written call became, which is what pairs
/// the two; a span cannot, because a spliced body gives its instructions one
/// span between them.
pub fn noteCallees(
    ast: *const Ast,
    module: *const mir.Module,
    f: *const mir.Mir,
    tokens: [][]const u8,
    extent: token.TokenRange,
) !void {
    for (f.call_sites) |site| {
        // The callee's own main token, which for a path is the name it
        // selects -- so the note replaces the whole path rather than its last
        // element.
        const main = ast.exprMain(ast.call(site.expr).callee);
        if (main.index() < extent.start.index() or main.index() >= extent.end.index()) continue;
        tokens[main.index()] = module.nameOf(f.callOf(site.call).func);
    }
}

test "a written call is noted with its own callee when other calls share its span" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const Source = @import("../support/source.zig").Source;
    const source: Source = .{ .path = "notes.lin", .text = "fn main() {\n    first()\n    second()\n}\n" };
    var interner: @import("../support/interner.zig").Interner = .empty;
    var sink = @import("../diagnostics/sink.zig").Sink.init(gpa);
    const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
    const tree = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);

    var calls: [2]node.ExprId = undefined;
    var found: usize = 0;
    for (0..tree.exprCount()) |i| {
        const id = node.ExprId.at(@intCast(i));
        if (tree.exprTag(id) != .call) continue;
        calls[found] = id;
        found += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), found);

    // Both instructions carry the first call's span, as the instructions of a
    // spliced body all carry its splice site's.
    const shared = tree.exprSpan(calls[0]);
    var b = mir.Mir.Builder.init(gpa);
    const entry = try b.addBlock();
    const first = try b.addCall(entry, .value, .unit, shared, mir.FunctionId.at(1), &.{});
    const second = try b.addCall(entry, .value, .unit, shared, mir.FunctionId.at(2), &.{});
    try b.recordCallSite(calls[0], first);
    try b.recordCallSite(calls[1], second);
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .unit, .span = shared, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = shared, .data = .{ .unary = zero } });
    const body = try b.finish(entry, .from(0));

    const names = try gpa.dupe([]const u8, &.{ "main", "first_body", "second_body" });
    const module: mir.Module = .{
        .functions = try gpa.dupe(mir.Mir, &.{ body, body, body }),
        .external = &.{ false, false, false },
        .bytes = &.{},
        .names = names,
        .origins = &.{},
        .representations = undefined,
        .layouts = &.{},
        .entry = .at(0),
    };

    const noted = try gpa.alloc([]const u8, tokens.len);
    @memset(noted, "");
    try noteCallees(&tree, &module, &module.functions[0], noted, .{ .start = @enumFromInt(0), .end = @enumFromInt(tokens.len) });

    var named: [2][]const u8 = undefined;
    for (calls, 0..) |call, i| named[i] = noted[tree.exprMain(tree.call(call).callee).index()];
    try std.testing.expectEqualStrings("first_body", named[0]);
    try std.testing.expectEqualStrings("second_body", named[1]);
}
