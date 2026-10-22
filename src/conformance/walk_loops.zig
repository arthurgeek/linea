//! Every walk in a file written out as the loop it stands for.
//!
//! A walk and the loop it is defined to be are two programs the compiler must
//! answer alike: accepted or refused by the same rules, and where accepted,
//! running to the same answer. The walk goes through the checker's and the
//! ownership pass's rules for `for`; the loop goes through the rules for
//! `loop`, `match`, `let` and the `next` call a reader would write by hand. A
//! rule that answers a walk one way and its loop another is one rule with two
//! implementations, and this is the rewrite that sets them side by side on
//! every program the corpus holds.

const std = @import("std");
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const FileTable = @import("../support/source.zig").FileTable;
const node = @import("../syntax/node.zig");
const ExprId = node.ExprId;
const resolve_mod = @import("../sema/resolve.zig");
const BindingId = resolve_mod.BindingId;
const TokenId = @import("../lexer/token.zig").TokenId;
const typecheck = @import("../sema/typecheck.zig").typecheck;
const loader = @import("../driver/loader.zig");
const Semantics = @import("transform.zig").Semantics;

/// The prefix of every name the written-out loops introduce. A program that
/// already spells it is left alone, so an introduced name shadows nothing and
/// nothing shadows it.
const held = "_walked";

/// Which loop a walk is written out as.
const Form = union(enum) {
    /// `for x in xs`: `var h = Sequence.iterate(xs)`, then a `loop` asking
    /// `Iterator.next(&h)` for each element until it answers `None`.
    sequence,
    /// `for x in &it`: a `loop` asking `Iterator.next(&it)` for each element,
    /// with the iterator left with its owner. Carries the binding the
    /// iterator's place is rooted in.
    lent: BindingId,
    /// `for x in array`, over scalar elements: the array taken whole, then each
    /// position read in order. The count is the array type's own.
    array: u32,
};

const Site = struct {
    walk: ExprId,
    at: Span,
    form: Form,
};

/// The walk `id` is, where it is one this can write out.
fn siteOf(semantics: Semantics, id: ExprId, text: []const u8) ?Site {
    const ast = semantics.ast;
    const typing = semantics.typing;
    if (id == ExprId.none or ast.exprTag(id) != .for_) return null;
    if (typing.exprType(id) != .unit) return null;

    const at = ast.exprExtent(id);
    if (at.end > text.len) return null;

    const f = ast.call(id);
    if (ast.exprTag(f.callee) == .marked) {
        const iterator = ast.unaryOperand(f.callee);
        // The walk evaluates its place once; the loop evaluates it on every
        // pass, so a place an index selects could name another iterator by
        // the next one.
        var steps = ast.placeSteps(iterator);
        while (steps.next()) |step| if (ast.exprTag(step) == .index) return null;
        const root = steps.at;
        if (ast.exprTag(root) != .name_ref) return null;
        const binding = semantics.res.targetOf(root);
        if (binding == BindingId.none) return null;
        return .{ .walk = id, .at = at, .form = .{ .lent = binding } };
    }

    const walked = typing.exprType(f.callee);
    if (walked == .poison) return null;
    return switch (typing.get(walked)) {
        .array => |a| if (a.count == 0 or !typing.isScalarSnapshot(a.element))
            null
        else
            .{ .walk = id, .at = at, .form = .{ .array = a.count } },
        else => .{ .walk = id, .at = at, .form = .sequence },
    };
}

/// Removes each lent walk whose body names the binding its iterator is rooted
/// in.
///
/// Which binding a name reaches is recorded against its expression, so the
/// names the file writes are indexed by their token once, and each lent walk
/// then reads its own body's tokens.
fn dropLentWalksNamingTheirIterator(
    gpa: std.mem.Allocator,
    semantics: Semantics,
    part: *const @import("../syntax/ast.zig").FilePart,
    sites: *std.ArrayList(Site),
) !void {
    const ast = semantics.ast;
    for (sites.items) |site| {
        if (site.form == .lent) break;
    } else return;

    var named: std.AutoHashMapUnmanaged(TokenId, BindingId) = .empty;
    defer named.deinit(gpa);
    for (part.expr_start..part.expr_end) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .name_ref) continue;
        const binding = semantics.res.targetOf(id);
        if (binding == BindingId.none) continue;
        try named.put(gpa, ast.exprTokens(id).start, binding);
    }

    var kept: usize = 0;
    for (sites.items) |site| {
        const drop = switch (site.form) {
            .lent => |iterator| mentions: {
                var run = ast.runOf(ast.exprTokens(ast.call(site.walk).args[1]));
                while (run.next()) |tok| {
                    if (named.get(tok) == iterator) break :mentions true;
                }
                break :mentions false;
            },
            else => false,
        };
        if (drop) continue;
        sites.items[kept] = site;
        kept += 1;
    }
    sites.items.len = kept;
}

/// Removes each walk whose head evaluates a temporary that what it walks
/// borrows.
///
/// A temporary lives until the end of its statement, and a walk is one
/// statement, so the view `[1, 2].as_slice()` walks is good for the whole walk.
/// Written out, the head is a statement of its own and the loop another, so no
/// loop gives that temporary the life the walk does.
///
/// The checker records every borrowed temporary in the program; the ones this
/// file holds are those in its own run of expressions, read once and sorted,
/// and each walk asks whether one begins inside its head.
fn dropWalksHoldingATemporary(
    gpa: std.mem.Allocator,
    semantics: Semantics,
    part: *const @import("../syntax/ast.zig").FilePart,
    sites: *std.ArrayList(Site),
) !void {
    const ast = semantics.ast;
    var starts: std.ArrayList(u32) = .empty;
    defer starts.deinit(gpa);
    var held_temporaries = semantics.typing.borrowed_temporaries.keyIterator();
    while (held_temporaries.next()) |id| {
        if (id.index() < part.expr_start or id.index() >= part.expr_end) continue;
        try starts.append(gpa, ast.exprExtent(id.*).start);
    }
    if (starts.items.len == 0) return;
    std.mem.sort(u32, starts.items, {}, std.sort.asc(u32));

    var kept: usize = 0;
    for (sites.items) |site| {
        const head = ast.exprExtent(ast.call(site.walk).callee);
        const first = std.sort.lowerBound(u32, starts.items, head.start, struct {
            fn order(key: u32, item: u32) std.math.Order {
                return std.math.order(key, item);
            }
        }.order);
        if (first < starts.items.len and starts.items[first] < head.end) continue;
        sites.items[kept] = site;
        kept += 1;
    }
    sites.items.len = kept;
}

/// Whether the module holding the file spells an introduced name anywhere, in
/// any of its files.
fn spellsHeld(semantics: Semantics) bool {
    const ast = semantics.ast;
    const module = semantics.res.moduleOfFile(semantics.file);
    for (ast.parts) |part| {
        if (semantics.res.moduleOfFile(part.file) != module) continue;
        if (std.mem.indexOf(u8, part.source, held) != null) return true;
    }
    return false;
}

/// Whether `Sequence` or `Iterator`, spelled where `at` is, could name
/// anything but the prelude's trait of that name: a declaration of the
/// module, in any of its files, a name a `use` brings in, or a local.
///
/// **Bound:** the bindings visible at `at`, which is the depth of its scopes
/// and what each declares.
fn traitsShadowedAt(
    gpa: std.mem.Allocator,
    semantics: Semantics,
    visible: *std.ArrayList(BindingId),
    at: ExprId,
) !bool {
    const ast = semantics.ast;
    const res = semantics.res;
    const sequence = resolve_mod.preludeDeclIn(ast, res.prelude, "Sequence") orelse return true;
    const iterator = resolve_mod.preludeDeclIn(ast, res.prelude, "Iterator") orelse return true;
    try res.visibleIn(gpa, res.scopeOfExpr(at), visible);
    for (visible.items) |binding| {
        const token = res.declaringToken(binding);
        if (token == TokenId.none or token.index() >= ast.tokenCount()) continue;
        const name = ast.tokenText(token);
        const prelude = if (std.mem.eql(u8, name, "Sequence"))
            sequence
        else if (std.mem.eql(u8, name, "Iterator"))
            iterator
        else
            continue;
        if (res.kindOf(binding) != .trait) return true;
        if (res.declaredBy(binding) != prelude) return true;
    }
    return false;
}

const Writer = struct {
    semantics: Semantics,
    text: []const u8,
    /// Ordered by where each walk begins, so the walks inside one follow it.
    sites: []const Site,
    /// The next site to write.
    next: usize = 0,
    /// How many walks have been written, which numbers the next one's names.
    written: u32 = 0,
    out: std.Io.Writer.Allocating,

    /// The text from `start` to `end`, each walk inside it written out.
    fn span(self: *Writer, start: u32, end: u32) std.Io.Writer.Error!void {
        var cursor = start;
        while (self.next < self.sites.len and self.sites[self.next].at.start < end) {
            const site = self.sites[self.next];
            self.next += 1;
            try self.out.writer.writeAll(self.text[cursor..site.at.start]);
            try self.walk(site);
            cursor = site.at.end;
        }
        try self.out.writer.writeAll(self.text[cursor..end]);
    }

    fn part(self: *Writer, id: ExprId) std.Io.Writer.Error!void {
        // By the extent rather than the span: a comment written after a part
        // sits inside its range, and carried into a line of the loop it would
        // comment out what follows.
        const at = self.semantics.ast.exprExtent(id);
        try self.span(at.start, at.end);
    }

    /// The `Some` arm of a written-out loop, which hands `body` the element.
    /// The loop's binder, a name or a tuple pattern, is the arm's payload
    /// pattern -- except a name that does not bind there: inside a pattern a
    /// capitalised name is a variant, so the arm binds the element and the
    /// body begins by naming it.
    fn arm(self: *Writer, binder: ExprId, body: ExprId, n: u32) std.Io.Writer.Error!void {
        const w = &self.out.writer;
        const ast = self.semantics.ast;
        if (ast.exprTag(binder) == .tuple_pattern or ast.partBinds(binder)) {
            try w.writeAll("Some(");
            try self.part(binder);
            try w.writeAll(") => ");
            return self.part(body);
        }
        try w.print("Some({s}{d}_item) => {{ let ", .{ held, n });
        try self.part(binder);
        try w.print(" = {s}{d}_item\n ", .{ held, n });
        try self.part(body);
        try w.writeAll(" }");
    }

    fn walk(self: *Writer, site: Site) std.Io.Writer.Error!void {
        const f = self.semantics.ast.call(site.walk);
        const n = self.written;
        self.written += 1;
        const w = &self.out.writer;
        switch (site.form) {
            .sequence => {
                try w.print("var {s}{d} = Sequence.iterate(", .{ held, n });
                try self.part(f.callee);
                try w.print(")\n    loop {{ match Iterator.next(&{s}{d}) {{ ", .{ held, n });
                try self.arm(f.args[0], f.args[1], n);
                try w.writeAll(", None => { break }, } }");
            },
            .lent => {
                try w.writeAll("loop { match Iterator.next(&");
                try self.part(self.semantics.ast.unaryOperand(f.callee));
                try w.writeAll(") { ");
                try self.arm(f.args[0], f.args[1], n);
                try w.writeAll(", None => { break }, } }");
            },
            .array => |count| {
                try w.print("let {s}{d} = ", .{ held, n });
                try self.part(f.callee);
                try w.print("\n    var {s}{d}_at: UInt64 = 0\n    while {s}{d}_at < {d} {{\n        let ", .{ held, n, held, n, count });
                try self.part(f.args[0]);
                try w.print(" = {s}{d}[{s}{d}_at]\n        {s}{d}_at += 1\n        ", .{ held, n, held, n, held, n });
                try self.part(f.args[1]);
                try w.writeAll("\n    }");
            },
        }
    }
};

/// Every walk in the file written out as the loop it stands for, or null where
/// the file holds none this can write out.
///
/// Three forms are written out:
///
/// - `for x in xs` over a `Sequence`: the iterator `Sequence.iterate` vends,
///   asked `Iterator.next` for one element at a time until it answers `None`.
/// - `for x in &it`: `Iterator.next(&it)` asked the same way, the iterator
///   staying with its owner.
/// - `for x in array` over scalar elements: the array bound whole, then each
///   position read by index in order. A scalar read is a snapshot, so reading
///   a position is what moving its element out is for these elements.
///
/// A tuple pattern binder cannot sit in the `Some` arm's payload, so the arm
/// binds the element and its body begins with the `let` that takes the element
/// apart.
///
/// Each is left alone where the loop it stands for is not a program the
/// language gives the same meaning:
///
/// - A walk that carries a value -- a `break e` makes it an `Option[E]` -- or
///   one the checker could not type. The written-out loop yields nothing, and a
///   walk typed as poison already has a diagnostic the loop would not repeat.
/// - A walk that is not a statement or the Unit tail of a block -- a match
///   arm's value, a lambda's expression body -- since the loop introduces a
///   binding before it, and only a block has room for one.
/// - A walk over `reflect.components` in a derive template, which is unrolled
///   once per component where the template is expanded rather than run as a
///   loop, so there is no loop for it to stand for.
/// - A consuming walk over an array of non-scalar elements. It moves each
///   element out of its place, and no expression moves an element out of an
///   index: a projection cannot give up what it reaches.
/// - A walk whose head evaluates a temporary that what it walks borrows, as
///   `[1, 2].as_slice()` does. The walk is one statement, so the temporary
///   lives as long as the walk; the loop begins with a statement of its own
///   that the temporary ends with.
/// - A walk over a sequence, or a lent walk, where `Sequence` or `Iterator`
///   reaches something other than the prelude's trait -- a declaration in any
///   file of the module, or a `use` -- which the loop's calls would name
///   instead.
/// - A lent walk whose iterator place is selected by an index. The walk
///   evaluates the place once; the loop evaluates it on every pass.
/// - A lent walk whose body names the iterator's root binding. The walk lends
///   the iterator for its whole extent ([O-Lent]); the loop lends it only
///   across each call to `next`, so the loop accepts reads the walk refuses.
/// - `for read` and `for inout`. Their binder is a place inside what is
///   walked, and no binding form names a lent place with a plain binder:
///   `let read` and `match read` take patterns, not names, and nothing binds a
///   place `inout`. The positions come from a traversal the walk finds through
///   the type rather than by a name the loop could call, and [O-Lent] treats
///   the walk's binder as every position, where an indexed place is one.
///
/// Walks nest, so each is written out with its head and body written out
/// first. Every introduced binding gets its own number.
///
/// **Bound:** one pass over the file's own expressions to find the walks, a
/// sort of the walks found, and one pass over the file's text to write them.
/// The checker's borrowed temporaries are read once and sorted, and each walk
/// searches them for its head. Each walk but an array's reads the bindings
/// visible where it is, to ask what `Sequence` and `Iterator` reach. Where the file holds a lent walk, one more pass
/// over its expressions indexes the names, and each lent walk reads the tokens
/// of its own body once -- so
/// nested lent walks cost their nesting depth times the innermost body, a
/// depth the source spells rather than one the program's size sets.
pub fn writeOut(gpa: std.mem.Allocator, semantics: Semantics, text: []const u8) !?[]const u8 {
    const ast = semantics.ast;
    const part = ast.partOfFile(semantics.file) orelse return null;
    if (spellsHeld(semantics)) return null;

    var sites: std.ArrayList(Site) = .empty;
    defer sites.deinit(gpa);
    for (part.expr_start..part.expr_end) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .block) continue;
        const b = ast.blockOf(id);
        for (ast.blockStmts(b)) |s| {
            if (ast.stmtTag(s) != .expr_stmt) continue;
            if (siteOf(semantics, ast.stmtData(s).init, text)) |site| try sites.append(gpa, site);
        }
        if (b.tail != ExprId.none) {
            if (siteOf(semantics, b.tail, text)) |site| try sites.append(gpa, site);
        }
    }
    try dropLentWalksNamingTheirIterator(gpa, semantics, part, &sites);
    try dropWalksHoldingATemporary(gpa, semantics, part, &sites);
    if (sites.items.len == 0) return null;

    // Every loop but the array's names the prelude's traits, so each such
    // walk asks what those names reach where it is.
    {
        var visible: std.ArrayList(BindingId) = .empty;
        defer visible.deinit(gpa);
        var kept: usize = 0;
        for (sites.items) |site| {
            if (site.form != .array and try traitsShadowedAt(gpa, semantics, &visible, site.walk)) continue;
            sites.items[kept] = site;
            kept += 1;
        }
        sites.items.len = kept;
        if (kept == 0) return null;
    }

    std.mem.sort(Site, sites.items, {}, struct {
        fn before(_: void, a: Site, b: Site) bool {
            return a.at.start < b.at.start;
        }
    }.before);

    var writer: Writer = .{ .semantics = semantics, .text = text, .sites = sites.items, .out = .init(gpa) };
    try writer.span(0, @intCast(text.len));
    return writer.out.written();
}

test "a walk over a sequence is written out as the loop that drives its iterator" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try writeOutText(gpa,
        \\fn main() -> UInt8 {
        \\    let xs: Range[UInt8] = 0..4
        \\    var total: UInt8 = 0
        \\    for x in xs {
        \\        total += x
        \\    }
        \\    total
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "var _walked0 = Sequence.iterate(xs)") != null);
    try testing.expect(std.mem.indexOf(u8, got, "Iterator.next(&_walked0)") != null);
    // The body is carried across whole, binder and all: the two programs
    // differ in the loop and nothing else.
    try testing.expect(std.mem.indexOf(u8, got, "Some(x) => {\n        total += x\n    }") != null);
    try testing.expect(try checks(gpa, got));
}

test "a lent walk is written out as the loop that calls next through the lend" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try writeOutText(gpa,
        \\fn main() -> UInt8 {
        \\    var pending = 0..UInt8(4)
        \\    var total: UInt8 = 0
        \\    for x in &pending {
        \\        total += x
        \\    }
        \\    total
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "loop { match Iterator.next(&pending) { Some(x) =>") != null);
    try testing.expect(std.mem.indexOf(u8, got, "Sequence.iterate") == null);
    try testing.expect(try checks(gpa, got));
}

test "a walk with a tuple binder is written out as a loop that takes the element apart" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try writeOutText(gpa,
        \\struct Pairs {
        \\    next: UInt8,
        \\}
        \\
        \\impl Iterator for Pairs {
        \\    type Item = (UInt8, UInt8)
        \\
        \\    fn next(inout self: Pairs) -> Option[(UInt8, UInt8)] {
        \\        if self.next == 3 {
        \\            return .None
        \\        }
        \\        self.next += 1
        \\        .Some((self.next, self.next * 2))
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    var pairs = Pairs { next = 0 }
        \\    var total: UInt8 = 0
        \\    for (a, b) in &pairs {
        \\        total += a + b
        \\    }
        \\    total
        \\}
        \\
    )).?;

    // The loop's tuple pattern is the arm's payload pattern.
    try testing.expect(std.mem.indexOf(u8, got, "Some((a, b)) => ") != null);
    try testing.expect(try checks(gpa, got));
}

test "a lent walk whose body names its iterator is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The walk holds `pending` for its whole extent and refuses the read; the
    // loop holds it only across `next`, so the two are not the same program.
    try testing.expectEqual(@as(?[]const u8, null), try writeOutText(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    var pending = 0..UInt8(4)
        \\    var total: UInt8 = 0
        \\    for x in &pending {
        \\        total += x
        \\        let _seen = copy(pending)
        \\    }
        \\    total
        \\}
        \\
    ));
}

test "a lent walk over an indexed place is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The walk evaluates `pending[0]` once; the loop would evaluate it on
    // every pass.
    try testing.expectEqual(@as(?[]const u8, null), try writeOutText(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    var pending = [0..UInt8(4)]
        \\    var total: UInt8 = 0
        \\    for x in &pending[0] {
        \\        total += x
        \\    }
        \\    total
        \\}
        \\
    ));
}

test "a walk where a local names Sequence is left alone and the others are not" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Each walk asks what `Sequence` reaches where it is: in `second` it is
    // the local, so only the walk in `first` is written out.
    const got = (try writeOutText(gpa,
        \\fn first() -> UInt8 {
        \\    var total: UInt8 = 0
        \\    for x in 0..UInt8(3) {
        \\        total += x
        \\    }
        \\    total
        \\}
        \\
        \\fn second() -> UInt8 {
        \\    let Sequence: UInt8 = 1
        \\    var total: UInt8 = Sequence
        \\    for x in 0..UInt8(3) {
        \\        total += x
        \\    }
        \\    total
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    first() + second()
        \\}
        \\
    )).?;
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got, "Sequence.iterate("));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got, "for x in"));
}

test "a sibling file declaring Sequence leaves a module's walks alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // `Sequence` in `main.lin` reaches the sibling's struct, so the loop's
    // `Sequence.iterate` would not be the prelude's.
    try testing.expectEqual(@as(?[]const u8, null), try writeOutModule(arena.allocator(), &.{
        .{ .path = "m/main.lin", .text =
        \\fn main() -> UInt8 {
        \\    var total: UInt8 = 0
        \\    for x in 0..UInt8(3) {
        \\        total += x
        \\    }
        \\    total
        \\}
        \\
        },
        .{ .path = "m/sequence.lin", .text =
        \\struct Sequence {}
        \\
        },
    }));
}

test "a sibling file spelling an introduced name leaves a module's walks alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(?[]const u8, null), try writeOutModule(arena.allocator(), &.{
        .{ .path = "m/main.lin", .text =
        \\fn main() -> UInt8 {
        \\    var total: UInt8 = _walked0()
        \\    for x in 0..UInt8(3) {
        \\        total += x
        \\    }
        \\    total
        \\}
        \\
        },
        .{ .path = "m/held.lin", .text =
        \\fn _walked0() -> UInt8 { 0 }
        \\
        },
    }));
}

test "a walk over a view of a temporary is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The array lives until the end of the walk's statement. Written out, it
    // would end with the statement that builds the iterator.
    try testing.expectEqual(@as(?[]const u8, null), try writeOutText(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    var walked: UInt8 = 0
        \\    for value in [UInt8(1), UInt8(2)].as_slice() {
        \\        walked += *value
        \\    }
        \\    walked
        \\}
        \\
    ));
}

test "a walk over a range its body settles is written out" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // `total += i` settles the range at `UInt64` in the loop as in the walk:
    // the `match` on what `next` hands back leaves the item's type open.
    const got = (try writeOutText(gpa,
        \\fn main() -> UInt8 {
        \\    let r = 0..3
        \\    var total: UInt64 = 0
        \\    for i in r {
        \\        total += i
        \\    }
        \\    UInt8(total - 3)
        \\}
        \\
    )).?;
    try testing.expect(try checks(gpa, got));
}

test "a walk in a file declaring its own Sequence is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The loop's `Sequence.iterate` would name this trait, not the prelude's.
    try testing.expectEqual(@as(?[]const u8, null), try writeOutText(arena.allocator(),
        \\trait Sequence {
        \\    fn count(self: Self) -> UInt8
        \\}
        \\
        \\impl Sequence for UInt8 {
        \\    fn count(self: UInt8) -> UInt8 { self }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    var total: UInt8 = 0
        \\    for x in 0..UInt8(3) {
        \\        total += x
        \\    }
        \\    total + Sequence.count(UInt8(1))
        \\}
        \\
    ));
}

test "a walk over scalars in an array reads each position in order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try writeOutText(gpa,
        \\fn main() -> UInt8 {
        \\    let xs: [UInt8; 3] = [1, 2, 4]
        \\    var total: UInt8 = 0
        \\    for x in xs {
        \\        total += x
        \\    }
        \\    total
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "let _walked0 = xs") != null);
    try testing.expect(std.mem.indexOf(u8, got, "while _walked0_at < 3 {") != null);
    try testing.expect(std.mem.indexOf(u8, got, "let x = _walked0[_walked0_at]") != null);
    try testing.expect(try checks(gpa, got));
}

test "a walk over an array of non-scalars is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Each element moves out of its place, and no index expression moves one.
    try testing.expectEqual(@as(?[]const u8, null), try writeOutText(arena.allocator(),
        \\struct Tally { n: UInt8 }
        \\
        \\fn main() -> UInt8 {
        \\    var total: UInt8 = 0
        \\    for t in [Tally { n: 1 }, Tally { n: 2 }] {
        \\        let Tally { n } = t
        \\        total += n
        \\    }
        \\    total
        \\}
        \\
    ));
}

test "nested walks are each written out" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const got = (try writeOutText(gpa,
        \\fn main() -> UInt8 {
        \\    var total: UInt8 = 0
        \\    for x in 0..UInt8(3) {
        \\        for y in 0..x {
        \\            total += y
        \\        }
        \\    }
        \\    total
        \\}
        \\
    )).?;

    try testing.expect(std.mem.indexOf(u8, got, "for ") == null);
    try testing.expect(std.mem.indexOf(u8, got, "Iterator.next(&_walked0)") != null);
    try testing.expect(std.mem.indexOf(u8, got, "Iterator.next(&_walked1)") != null);
    try testing.expect(try checks(gpa, got));
}

test "a walk that carries a value is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // What this walk answers is `Option[UInt8]`, settled by its `break` site.
    // The loop written out answers nothing.
    try testing.expectEqual(@as(?[]const u8, null), try writeOutText(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let found = for x in 0..9 {
        \\        if x == 5 { break x }
        \\    }
        \\    match found {
        \\        Some(v) => v,
        \\        None => 0,
        \\    }
        \\}
        \\
    ));
}

test "a lending walk is left alone" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // No binding form names a lent place with a plain binder, so `for inout`
    // has no loop to be written out as.
    try testing.expectEqual(@as(?[]const u8, null), try writeOutText(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    var xs = [UInt8(1), 2, 3]
        \\    for inout x in xs {
        \\        x += 1
        \\    }
        \\    xs[0]
        \\}
        \\
    ));
}

/// What `writeOut` makes of `text`, read with the library as a case is.
fn writeOutText(gpa: std.mem.Allocator, text: []const u8) !?[]const u8 {
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var table: FileTable = .empty;
    const one = [_]loader.InMemoryFile{.{ .path = "walks.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "walks.lin", &one, .program, true, .borrow);
    const resolved = try resolve_mod.resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var res = resolved.resolution;
    defer res.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &res, &sink);
    defer typing.deinit(gpa);
    return writeOut(gpa, .{
        .ast = &expanded.ast,
        .program = &program,
        .res = &res,
        .typing = &typing,
        .file = program.primaryFile(),
    }, text);
}

/// Whether `text` resolves and checks with no error.
fn checks(gpa: std.mem.Allocator, text: []const u8) !bool {
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var table: FileTable = .empty;
    const one = [_]loader.InMemoryFile{.{ .path = "walked.lin", .text = text }};
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "walked.lin", &one, .program, true, .borrow);
    const resolved = try resolve_mod.resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var res = resolved.resolution;
    defer res.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &res, &sink);
    defer typing.deinit(gpa);
    return !sink.hasErrors();
}

/// What `writeOut` makes of a module's first file, the module loaded whole.
fn writeOutModule(gpa: std.mem.Allocator, files: []const loader.InMemoryFile) !?[]const u8 {
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var table: FileTable = .empty;
    var program = try loader.loadFromMemory(gpa, &table, &sink, &interner, "m", files, .program, true, .borrow);
    const resolved = try resolve_mod.resolve(gpa, &program, &interner, &sink, .program);
    var expanded = resolved.expanded;
    defer expanded.deinit(gpa);
    var res = resolved.resolution;
    defer res.deinit(gpa);
    var typing = try typecheck(gpa, &expanded, &res, &sink);
    defer typing.deinit(gpa);
    const file = for (expanded.ast.parts) |part| {
        if (std.mem.eql(u8, part.path, files[0].path)) break part.file;
    } else return error.TestUnexpectedResult;
    return writeOut(gpa, .{
        .ast = &expanded.ast,
        .program = &program,
        .res = &res,
        .typing = &typing,
        .file = file,
    }, files[0].text);
}
