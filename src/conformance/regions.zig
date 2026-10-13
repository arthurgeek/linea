const std = @import("std");
const testing = std.testing;

const Source = @import("../support/source.zig").Source;
const Span = @import("../support/span.zig").Span;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const StmtId = node.StmtId;
const resolve_mod = @import("../sema/resolve.zig");
const resolveTree = resolve_mod.resolveTree;
const Resolution = resolve_mod.Resolution;
const BindingId = resolve_mod.BindingId;

/// A use that reaches a binding from outside the region the binding belongs to.
pub const Escape = struct {
    /// What the use is spelled, which is what makes the report readable.
    name: []const u8,
    use: Span,
    extent: Span,
};

/// Property: a use lies inside the region of source its binding belongs to.
///
/// This is not a rewrite of the program, and deliberately so. A rewrite driven
/// by resolution cannot contradict resolution — renaming a use that reached the
/// wrong binding just writes the wrong binding's new name, and the rewritten
/// program agrees with the original because the same mistake produced both.
///
/// What contradicts resolution is a second source for the same fact. A local's
/// region is the block its declaring statement sits in, and a parameter's is
/// its function; both are read from the shape of the tree. Which binding a use
/// reaches is read from the scope chain. The tree is not what goes wrong when
/// a scope fails to close, so the two disagree exactly when it does.
pub fn firstEscape(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    text: []const u8,
) !?Escape {
    var extent = try gpa.alloc(?Span, res.bindingCount());
    defer gpa.free(extent);
    @memset(extent, null);

    // A local belongs to the block holding its declaration, and only from that
    // declaration onwards: a block is entered before its statements run, so
    // being inside one is not yet enough to see everything it declares.
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .block) continue;

        const block = ast.exprSpan(id);
        for (ast.blockStmts(ast.blockOf(id))) |s| {
            if (ast.stmtTag(s) != .let_decl) continue;
            const b = res.bindingOf(s);
            if (b.index() >= res.bindingCount()) continue;
            extent[b.index()] = .{ .start = ast.stmtSpan(s).end, .end = block.end };
        }
    }

    // A binder belongs to its arm: from the pattern that introduces it to the
    // end of the body that may read it. Read from the arm's two spans, which
    // is a different source from the scope chain that decided where the arm
    // began and ended.
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (!ast.exprTag(id).isMatch()) continue;

        const m = ast.call(id);
        var a: usize = 0;
        while (a + 1 < m.args.len) : (a += 2) {
            const pattern = m.args[a];
            if (ast.exprTag(pattern) != .call) continue;

            const arm: Span = .{
                .start = ast.exprSpan(pattern).start,
                .end = ast.exprSpan(m.args[a + 1]).end,
            };
            for (ast.call(pattern).args) |binder| {
                const b = res.targetOf(binder);
                if (b.index() >= res.bindingCount()) continue;
                extent[b.index()] = arm;
            }
        }
    }

    // A parameter belongs to its callable body, which is the region a body may
    // not reach out of.
    for (0..res.bindingCount()) |i| {
        const b = BindingId.at(@intCast(i));
        if (res.kindOf(b) != .parameter) continue;
        extent[i] = switch (res.parameterOwner(b)) {
            .declaration => |owner| if (owner.index() < ast.declCount())
                ast.declSpan(owner)
            else
                null,
            .closure => |owner| blk: {
                const expression = res.closures.exprOf(owner);
                break :blk if (expression.index() < ast.exprCount()) ast.exprSpan(expression) else null;
            },
        };
    }

    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .name_ref) continue;

        const b = res.targetOf(id);
        if (b.index() >= res.bindingCount()) continue;
        const region = extent[b.index()] orelse continue;

        // The release a `defer let` schedules names its binding at the token
        // that declares it, which is before the region begins and is no use
        // anyone wrote.
        if (res.kindOf(b) == .local and ast.exprMain(id) == res.declaringToken(b)) continue;

        // A match pattern is spelled as a name and denotes no binding, so a
        // use is held to this only where it names what it resolved to.
        const use = ast.exprSpan(id);
        if (!std.mem.eql(u8, use.slice(text), nameOf(ast, res, b, text) orelse continue)) continue;

        if (use.start >= region.start and use.end <= region.end) continue;
        return .{ .name = use.slice(text), .use = use, .extent = region };
    }

    return null;
}

fn nameOf(ast: *const Ast, res: *const Resolution, b: BindingId, text: []const u8) ?[]const u8 {
    return switch (res.kindOf(b)) {
        .local, .parameter, .capture, .binder => ast.tokenSpan(res.declaringToken(b)).slice(text),
        // A declaration rather than a binding some region encloses: a constant
        // is reachable wherever its module is, exactly as a function is, so
        // there is no extent for a use of one to escape.
        .constant, .function, .declared_type, .builtin_type, .trait, .module, .associated_type, .type_parameter, .type_alias => null,
    };
}

fn expectNoEscape(gpa: std.mem.Allocator, text: []const u8) !void {
    const source: Source = .{ .path = "scopes.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);

    if (try firstEscape(gpa, &ast, &res.resolution, text)) |e| {
        std.debug.print(
            "\n=== program ===\n{s}\n=== `{s}` at {d}..{d} reaches a binding of {d}..{d} ===\n",
            .{ text, e.name, e.use.start, e.use.end, e.extent.start, e.extent.end },
        );
        return error.BindingEscapesItsRegion;
    }
}

test "a binding used within its block does not escape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectNoEscape(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1;
        \\    x
        \\}
        \\
    );
}

test "a shadowing binding and the one it shadows both stay in their blocks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The tail reaches the outer binding, whose region is the function body,
    // so it is inside it. The inner use reaches the inner binding, whose
    // region is the smaller block.
    try expectNoEscape(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let x: UInt8 = 1;
        \\    if true {
        \\        let x: UInt8 = 2;
        \\        let _ = x;
        \\    }
        \\    x
        \\}
        \\
    );
}

test "a parameter is used only within its function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectNoEscape(arena.allocator(),
        \\fn double(n: UInt8) -> UInt8 { n + n }
        \\
        \\fn main() -> UInt8 { double(3) }
        \\
    );
}

test "generated parameters do not enter the source region property" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectNoEscape(arena.allocator(),
        \\trait Value {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\template impl Value {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\struct Mark { value: UInt8 }
        \\derive Value for Mark
        \\fn main() -> UInt8 {
        \\    let mark: Mark = .{ value = 1 }
        \\    Value.value(mark)
        \\}
        \\
    );
}

test "a loop body's bindings stay inside it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectNoEscape(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    var i: UInt8 = 0;
        \\    var total: UInt8 = 0;
        \\    while i < 3 {
        \\        let step: UInt8 = 2;
        \\        total = total + step;
        \\        i = i + 1;
        \\    }
        \\    total
        \\}
        \\
    );
}

test "a binder stays inside the arm that binds it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectNoEscape(arena.allocator(),
        \\enum Shape { Circle(UInt8), Square }
        \\
        \\fn main() -> UInt8 {
        \\    let n: UInt8 = 9;
        \\    let _: UInt8 = match Shape.Square { Circle(n) => n, Square => 0 };
        \\    n
        \\}
        \\
    );
}

test "a match arm's body reaches bindings from outside the match" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try expectNoEscape(arena.allocator(),
        \\enum Shape { Circle, Square }
        \\
        \\fn main() -> UInt8 {
        \\    let base: UInt8 = 4;
        \\    let s: Shape = Shape.Circle;
        \\    match s { Circle => base, Square => 0 }
        \\}
        \\
    );
}
