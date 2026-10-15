const DeclarationSelection = @import("program.zig").DeclarationSelection;
const std = @import("std");
const testing = std.testing;

const Source = @import("../support/source.zig").Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const TokenId = @import("../lexer/token.zig").TokenId;
const writeEscaped = @import("../lexer/dump.zig").writeEscaped;
const Ast = @import("ast.zig").Ast;
const node = @import("node.zig");
const ExprId = node.ExprId;
const StmtId = node.StmtId;

/// Indented syntax rendering with token, statement and expression coordinates
/// relative to their source file. File sections distinguish repeated local IDs
/// when several files are selected; dependency placement does not change them.
pub fn dumpAst(w: *std.Io.Writer, ast: *const Ast, selection: DeclarationSelection) std.Io.Writer.Error!void {
    try w.print("program decls={d}\n", .{selection.count()});
    var count: usize = 0;
    var counting: SelectedFiles = .{ .ast = ast, .selection = selection };
    while (counting.next() != null) count += 1;
    var selected: SelectedFiles = .{ .ast = ast, .selection = selection };
    var ordinal: usize = 0;
    while (selected.next()) |file| : (ordinal += 1) {
        if (count > 1) try w.print("  file {d} \"{s}\"\n", .{ ordinal, std.fs.path.basename(file.part.path) });
        const offsets: Offsets = .{ .token = file.part.token_start, .stmt = file.part.stmt_start, .expr = file.part.expr_start };
        for (file.decls.start..file.decls.end) |i| try dumpDecl(w, ast, offsets, .at(@intCast(i)), if (count > 1) 2 else 1);
    }
}

const Offsets = struct { token: u32, stmt: u32, expr: u32 };

/// Modules and their files follow parse order. The cursor visits every part at
/// most once, including omitted library parts, without allocating an index.
const SelectedFiles = struct {
    ast: *const Ast,
    selection: DeclarationSelection,
    part: usize = 0,
    module: usize = 0,
    file: usize = 0,

    const Entry = struct { part: *const @import("ast.zig").FilePart, decls: node.DeclRange };

    fn next(self: *SelectedFiles) ?Entry {
        switch (self.selection) {
            .range => |range| {
                while (self.part < self.ast.parts.len) {
                    const part = &self.ast.parts[self.part];
                    self.part += 1;
                    const start = @max(part.decl_start, range.start);
                    const end = @min(part.decl_end, range.end);
                    if (start < end) return .{ .part = part, .decls = .{ .start = start, .end = end } };
                }
            },
            .modules => |modules| {
                while (self.module < modules.len) {
                    const module = modules[self.module];
                    if (module.library or self.file == module.files.len) {
                        self.module += 1;
                        self.file = 0;
                        continue;
                    }
                    const file = module.files[self.file];
                    self.file += 1;
                    while (self.part < self.ast.parts.len and self.ast.parts[self.part].file != file) self.part += 1;
                    std.debug.assert(self.part < self.ast.parts.len);
                    const part = &self.ast.parts[self.part];
                    self.part += 1;
                    return .{ .part = part, .decls = .{ .start = part.decl_start, .end = part.decl_end } };
                }
            },
        }
        return null;
    }
};

fn dumpDecl(
    w: *std.Io.Writer,
    ast: *const Ast,
    offsets: Offsets,
    id: node.DeclId,
    depth: usize,
) std.Io.Writer.Error!void {
    const r = ast.declTokens(id);
    const tag = ast.declTag(id);
    try indent(w, depth);
    // Visibility appears only where something was written, so a program that
    // exports nothing prints what it always printed.
    const visibility = switch (ast.declVisibility(id)) {
        .private => "",
        .internal_ => "internal ",
        .pub_ => "pub ",
        .opaque_ => "opaque ",
    };
    // `export` appears only where it was written, so a declaration nothing
    // links against prints what it always printed.
    const is_export = if (ast.declIsExport(id)) "export " else "";
    // Print the declaration policy only when a modifier was written.
    const policy = switch (ast.declOwnershipPolicy(id)) {
        .affine => "",
        .copyable => "copyable ",
        .linear => "linear ",
    };
    const derive_form = if (tag == .derive_impl)
        (if (ast.deriveIsGrouped(id)) " grouped" else " single")
    else
        "";
    // A head written as a tuple or a callable type has no name token, so it is
    // printed as it was written; unit's head is the `(` that opens it.
    const tuple_head = (tag == .impl_ or tag == .derive_impl) and ast.declHead(id).kind == .tuple;
    const name = if (tag == .impl_ or tag == .derive_impl) ast.implHeadText(id) else ast.tokenText(ast.declName(id));
    try w.print("decl {s}{s}{s}{s}{s} \"{s}\" tokens {d}..{d}\n", .{
        visibility,
        is_export,
        policy,
        @tagName(tag),
        derive_form,
        name,
        r.start.index() - offsets.token,
        r.end.index() - offsets.token,
    });

    if (ast.declVia(id) != .none) {
        try indent(w, depth + 1);
        const target = ast.declDelegation(id);
        try w.print("via {s}\n", .{if (target == .none) "<missing>" else ast.tokenText(target)});
    }

    // The type a declaration was written inside. Printed on the member rather
    // than as a nesting, because the tree stores it that way: a member's id is
    // allocated while its type is still being read.
    if (ast.declOwner(id) != TokenId.none) {
        try indent(w, depth + 1);
        try w.print("in {s}\n", .{ast.tokenText(ast.declOwner(id))});
    }

    // The trait an implementation names, for the reason an import's path is
    // printed: an `impl Trait for Type` and an inherent `impl Type` are two
    // constructs, and the name alone renders them identically. Which of the
    // two it is decides where the member lives -- a trait implementation's
    // members belong to the trait -- so a tree printing only the owner drops
    // the half that answers it.
    if (tag == .derive_impl) {
        for (ast.deriveTraits(id)) |trait| {
            try indent(w, depth + 1);
            try w.writeAll("trait ");
            try dumpTraitRef(w, ast, trait.ref);
            try w.writeAll("\n");
        }
    } else if (ast.declTrait(id) != TokenId.none) {
        try indent(w, depth + 1);
        try w.writeAll("of trait ");
        try dumpTraitRef(w, ast, ast.declTraitRef(id));
        try w.writeAll("\n");
    }

    // What an implementation applied its head to. The name alone renders a
    // family and a single type identically, and which of the two it is decides
    // what every call through the implementation binds.
    if ((tag == .impl_ or tag == .derive_impl) and !tuple_head and ast.declHead(id).args.len() != 0) {
        try indent(w, depth + 1);
        try w.writeAll("head");
        try dumpTypeArgs(w, ast, ast.declHead(id).args);
        try w.writeAll("\n");
    }

    // An import's path is the whole of what it says, and its name is only the
    // last element or the alias -- so a tree that printed the name alone would
    // render two different imports identically.
    if (ast.declTag(id) == .import_) {
        try indent(w, depth + 1);
        try w.writeAll("path");
        var elements = ast.pathElements(id);
        while (elements.next()) |tok| try w.print(" {s}", .{ast.tokenText(tok)});
        try w.writeAll("\n");
    }

    for (ast.declVariants(id)) |v| {
        try indent(w, depth + 1);
        // The payload appears only where one was written, so an enum that
        // carries nothing prints what it always printed.
        const carried = ast.variantFields(v);
        if (carried.len == 0) {
            try w.print("variant \"{s}\"\n", .{ast.tokenText(v.name)});
        } else {
            try w.print("variant \"{s}\" :", .{ast.tokenText(v.name)});
            for (carried) |f| {
                try w.writeByte(' ');
                try dumpWrittenType(w, ast, f.written);
            }
            try w.writeAll("\n");
        }
    }

    for (ast.declTypeParams(id)) |t| {
        try indent(w, depth + 1);
        // The flag is part of what the node *is*: the formatter's
        // different-program guard reads this dump with spans stripped, and a
        // `phantom` it cannot see is a `phantom` a rewrite could drop.
        if (t.phantom) try w.writeAll("phantom ");
        try w.print("type param \"{s}\"", .{ast.tokenText(t.name)});
        for (ast.boundsOf(t), 0..) |b, i| {
            try w.writeAll(if (i == 0) " : " else " + ");
            try dumpBound(w, ast, b);
        }
        if (t.default.wasWritten()) {
            try w.writeAll(" = ");
            try dumpWrittenType(w, ast, t.default);
        }
        try w.writeAll("\n");
    }

    // What a declared type requires of whatever settles it. On its own line
    // rather than beside the name, because the name is printed by the header
    // every declaration shares.
    if (ast.declBounds(id).len != 0) {
        try indent(w, depth + 1);
        try w.writeAll("requires");
        for (ast.declBounds(id), 0..) |b, i| {
            try w.writeAll(if (i == 0) " " else " + ");
            try dumpBound(w, ast, b);
        }
        try w.writeAll("\n");
    }

    for (ast.declWherePredicates(id)) |predicate| {
        try indent(w, depth + 1);
        try w.writeAll("where ");
        try dumpWrittenType(w, ast, predicate.subject);
        for (ast.boundsIn(predicate.bounds), 0..) |b, i| {
            try w.writeAll(if (i == 0) " : " else " + ");
            try dumpBound(w, ast, b);
        }
        try w.writeAll("\n");
    }

    for (ast.templateRequirements(id)) |requirement| {
        try indent(w, depth + 1);
        switch (requirement.kind) {
            .components => {
                try w.writeAll("where reflect.components");
                for (ast.boundsIn(requirement.bounds), 0..) |b, i| {
                    try w.writeAll(if (i == 0) " : " else " + ");
                    try dumpBound(w, ast, b);
                }
            },
            .derived_supertraits => try w.writeAll("where reflect.supertraits : derived"),
            .target => try w.print("where reflect.target : {s}", .{requirement.target_shape.spelling()}),
        }
        try w.writeAll("\n");
    }

    for (ast.declFields(id)) |f| {
        try indent(w, depth + 1);
        try w.print("field \"{s}\" : ", .{ast.tokenText(f.name)});
        try dumpWrittenType(w, ast, f.written);
        try w.writeAll("\n");
    }

    for (ast.declParams(id)) |p| {
        try indent(w, depth + 1);
        try w.print("param {s} \"{s}\" : ", .{
            @tagName(p.convention),
            ast.tokenText(p.name),
        });
        try dumpWrittenType(w, ast, p.written);
        try w.writeAll("\n");
        // A default prints only where one was written, so the existing
        // goldens with no defaulted parameter stand unchanged.
        if (p.default != ExprId.none) {
            try dumpExpr(w, ast, offsets, p.default, depth + 2);
        }
    }

    // The type written on the declaration. What a function yields, and what a
    // constant holds -- printed under the word that says which, so a wrong
    // token here is visible rather than silent.
    if (ast.declReturnRef(id).wasWritten()) {
        try indent(w, depth + 1);
        const written = switch (ast.declTag(id)) {
            .constant => "holds",
            .associated_type => "settles",
            .newtype => "over",
            // An alias's written type is what its name stands for.
            .alias => "names",
            // A projection names a place rather than answering with a value,
            // so what is written after its arrow is what the place holds.
            .projection => "yields",
            else => "returns",
        };
        try w.print("{s} ", .{written});
        try dumpWrittenType(w, ast, ast.declReturnRef(id));
        try w.writeAll("\n");
    }

    // The refinement clause, as its own unit rather than folded into the base
    // it was written under: a reader checking what a newtype admits looks
    // here and not at the type it is written over. A bound the parser could
    // not read prints as nothing, which is what it holds.
    if (ast.newtypeRefinement(id)) |refinement| {
        try indent(w, depth + 1);
        try w.print("where it in {s}{s}{s}{s}{s}\n", .{
            if (refinement.lo_minus == TokenId.none) "" else "-",
            boundDigits(ast, refinement.lo_token),
            if (refinement.inclusive) "..=" else "..",
            if (refinement.hi_minus == TokenId.none) "" else "-",
            boundDigits(ast, refinement.hi_token),
        });
    }

    // What a constant is bound to. Without it two constants of one type and
    // different values print identically.
    if (ast.declInit(id) != ExprId.none) {
        try dumpExpr(w, ast, offsets, ast.declInit(id), depth + 1);
    }

    if (ast.declBody(id) != ExprId.none) {
        try dumpExpr(w, ast, offsets, ast.declBody(id), depth + 1);
    }
}

/// A refinement bound's digits, or nothing where the bound was never read.
fn boundDigits(ast: *const Ast, t: TokenId) []const u8 {
    if (t == TokenId.none) return "";
    return ast.tokenText(t);
}

/// The arguments a written type was given, inline and nested.
/// A written type, in whichever form it was written. One printer, because a
/// nested type and a top-level one are the same thing.
fn dumpWrittenType(
    w: *std.Io.Writer,
    ast: *const Ast,
    ref: node.TypeRef,
) std.Io.Writer.Error!void {
    switch (ref.kind) {
        .borrow, .grouped => {
            try w.writeAll(if (ref.kind == .borrow) "borrow " else "(");
            const args = ast.typeArgs(ref.args);
            if (args.len != 0) try dumpWrittenType(w, ast, args[0]);
            if (ref.kind == .grouped) try w.writeAll(")");
        },
        .named => {
            try w.print("{s}", .{if (ref.name == TokenId.none) "?" else ast.tokenText(ref.name)});
            try dumpTypeArgs(w, ast, ref.args);
        },
        .selection => {
            try dumpWrittenType(w, ast, ast.selectionBase(ref));
            try w.writeAll(".");
            try w.writeAll(if (ref.name == .none) "?" else ast.tokenText(ref.name));
            try dumpTypeArgs(w, ast, ref.args);
        },
        .array => {
            try w.writeAll("[");
            const written = ast.typeArgs(ref.args);
            if (written.len != 0) try dumpWrittenType(w, ast, written[0]);
            try w.writeAll("; ");
            // The length by its text, so a dump reads as the source does and
            // does not depend on the folding a later pass performs.
            if (ref.inferred_length != .none) {
                try w.writeAll(ast.tokenText(ref.inferred_length));
            } else if (ref.length != ExprId.none) {
                try w.print("{s}", .{ast.tokenText(ast.exprMain(ref.length))});
            }
            try w.writeAll("]");
        },
        .callable => try dumpCallableType(w, ast, ast.callableType(ref)),
        .tuple => {
            try w.writeAll("(");
            for (ast.typeArgs(ref.args), 0..) |component, i| {
                if (i != 0) try w.writeAll(", ");
                try dumpWrittenType(w, ast, component);
            }
            try w.writeAll(")");
        },
    }
}

test "a tuple type prints as written and a tuple literal prints its components" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "t.lin", .text = "let p: (A, B) = (1, 2)" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var b = Ast.Builder.init(gpa);
    try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(4), .name = TokenId.at(4) });
    try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(6), .name = TokenId.at(6) });
    const first = try b.addExpr(.{
        .tag = .int_literal,
        .main_token = TokenId.at(10),
        .token_range = .{ .start = TokenId.at(10), .end = TokenId.at(11) },
        .data = .{ .none = {} },
    });
    const second = try b.addExpr(.{
        .tag = .int_literal,
        .main_token = TokenId.at(12),
        .token_range = .{ .start = TokenId.at(12), .end = TokenId.at(13) },
        .data = .{ .none = {} },
    });
    const pair = try b.addCall(TokenId.at(9), .{ .start = TokenId.at(9), .end = TokenId.at(14) }, ExprId.none, &.{ first, second }, &.{});
    b.retag(pair, .tuple_literal);
    const decl = try b.addStmt(.{
        .tag = .let_decl,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(14) },
        .data = .{
            .name = TokenId.at(1),
            .annotation = .{ .kind = .tuple, .at = TokenId.at(3), .name = .none, .args = .{ .start = 0, .end = 2 } },
            .init = pair,
        },
    });
    const blk = try b.addBlock(&.{decl}, ExprId.none);
    const root = try b.addExpr(.{
        .tag = .block,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(14) },
        .data = .{ .block = blk },
    });
    _ = try b.addDecl(.{
        .tag = .function,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(14) },
        .name = TokenId.at(0),
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = TokenId.none },
        .body = root,
        .variants = .{ .start = 0, .end = 0 },
    });

    var ast = try b.finishOne(source.path, source.text, .from(0), tokens);

    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpAst(&out.writer, &ast, DeclarationSelection.all(ast.declCount()));

    try testing.expectEqualStrings(
        \\program decls=1
        \\  decl function "let" tokens 0..14
        \\    expr %3 block tokens 0..14
        \\      stmt %0 let_decl tokens 0..14 "p" : (A, B)
        \\        expr %2 tuple_literal tokens 9..14
        \\          expr %0 int_literal tokens 10..11 "1"
        \\          expr %1 int_literal tokens 12..13 "2"
        \\
    , out.written());
}

test "an implementation and a derive on a tuple head are named by the tuple" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "t.lin", .text = "impl (UInt8, Bool) {}\nderive Debug for (UInt8, Bool)" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var b = Ast.Builder.init(gpa);
    try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(2), .name = TokenId.at(2) });
    try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(4), .name = TokenId.at(4) });
    _ = try b.addDecl(.{
        .tag = .impl_,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(8) },
        .name = TokenId.at(1),
        .head_args = .{ .start = 0, .end = 2 },
        .head_kind = .tuple,
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = TokenId.none },
        .body = .none,
        .variants = .{ .start = 0, .end = 0 },
    });
    try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(12), .name = TokenId.at(12) });
    try b.addTypeRef(.{ .kind = .named, .at = TokenId.at(14), .name = TokenId.at(14) });
    _ = try b.addDecl(.{
        .tag = .derive_impl,
        .main_token = TokenId.at(8),
        .token_range = .{ .start = TokenId.at(8), .end = TokenId.at(16) },
        .name = TokenId.at(11),
        .head_args = .{ .start = 2, .end = 4 },
        .head_kind = .tuple,
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = TokenId.none },
        .body = .none,
        .variants = .{ .start = 0, .end = 0 },
    });

    var ast = try b.finishOne(source.path, source.text, .from(0), tokens);

    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpAst(&out.writer, &ast, DeclarationSelection.all(ast.declCount()));

    try testing.expectEqualStrings(
        \\program decls=2
        \\  decl impl_ "(UInt8, Bool)" tokens 0..8
        \\  decl derive_impl single "(UInt8, Bool)" tokens 8..16
        \\
    , out.written());
}

fn dumpBound(w: *std.Io.Writer, ast: *const Ast, bound: node.TraitBound) std.Io.Writer.Error!void {
    switch (bound.kind) {
        .named => {
            try dumpTraitRef(w, ast, bound.named);
        },
        .callable => try dumpCallableType(w, ast, ast.callableTypeById(bound.callable)),
    }
}

fn dumpTraitRef(w: *std.Io.Writer, ast: *const Ast, ref: node.TraitRef) std.Io.Writer.Error!void {
    if (ref.path.len() == 0) {
        try w.print("{s}", .{ast.tokenText(ref.name)});
    } else {
        var run = ast.runOf(ref.path);
        while (run.next()) |id| try w.print("{s}", .{ast.tokenText(id)});
    }
    try dumpTypeArgs(w, ast, ref.args);
}

fn dumpCallableType(w: *std.Io.Writer, ast: *const Ast, callable: node.CallableType) std.Io.Writer.Error!void {
    if (callable.invocation_token != .none) try w.print("{s} ", .{@tagName(callable.invocation)});
    try w.writeAll("fn(");
    for (ast.params[callable.params.start..callable.params.end], 0..) |param, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("{s} {s}: ", .{ @tagName(param.convention), ast.tokenText(param.name) });
        try dumpWrittenType(w, ast, param.written);
        if (param.default != ExprId.none) {
            try w.writeAll(" = ");
            var run = ast.runOf(ast.exprTokens(param.default));
            var first = true;
            while (run.next()) |token| {
                if (!first) try w.writeByte(' ');
                first = false;
                try w.writeAll(ast.tokenText(token));
            }
        }
    }
    try w.writeByte(')');
    if (callable.result.wasWritten()) {
        try w.writeAll(" -> ");
        try dumpWrittenType(w, ast, callable.result);
    }
}

fn dumpTypeArgs(
    w: *std.Io.Writer,
    ast: *const Ast,
    args: node.TypeRefRange,
) std.Io.Writer.Error!void {
    if (args.len() == 0) return;
    try w.writeAll("[");
    for (ast.typeArgs(args), 0..) |a, i| {
        if (i > 0) try w.writeAll(", ");
        try dumpWrittenType(w, ast, a);
    }
    try w.writeAll("]");
}

fn indent(w: *std.Io.Writer, depth: usize) std.Io.Writer.Error!void {
    try w.splatByteAll(' ', depth * 2);
}

fn dumpStmt(
    w: *std.Io.Writer,
    ast: *const Ast,
    offsets: Offsets,
    id: StmtId,
    depth: usize,
) std.Io.Writer.Error!void {
    const r = ast.stmtTokens(id);
    try indent(w, depth);
    try w.print("stmt %{d} {s} tokens {d}..{d}", .{
        id.index() - offsets.stmt, @tagName(ast.stmtTag(id)), r.start.index() - offsets.token, r.end.index() - offsets.token,
    });

    switch (ast.stmtTag(id)) {
        // The scheduled expression prints below it, as a statement's does.
        // Where it *runs* is the ownership graph's answer and not the tree's,
        // so nothing about the schedule appears here.
        .defer_stmt, .defer_release => {
            try w.writeByte('\n');
            // A `defer` the parser could not read an expression for carries
            // none, and the tree still has to dump: the frontend returns a
            // complete tree from source that is broken.
            const d = ast.stmtData(id);
            if (d.init != ExprId.none) try dumpExpr(w, ast, offsets, d.init, depth + 1);
        },
        .let_destructure, .let_read_destructure => {
            const d = ast.stmtData(id);
            try dumpExpr(w, ast, offsets, d.pattern, depth + 1);
            try dumpExpr(w, ast, offsets, d.init, depth + 1);
        },
        .let_decl => {
            const d = ast.stmtData(id);
            // The name slot holds whatever token stood where a name belonged,
            // so printing it unconditionally would read as a binding named `=`.
            if (ast.tokenTag(d.name) == .identifier) {
                try w.print(" \"{s}\"", .{ast.tokenText(d.name)});
            } else {
                try w.writeAll(" <missing name>");
            }
            // The annotation, where one was written. A contextual `.{ … }`
            // literal names no type, so for such a binding this is the only
            // thing in the tree saying which type is built.
            if (d.annotation.wasWritten()) {
                try w.writeAll(" : ");
                try dumpWrittenType(w, ast, d.annotation);
            }
            try w.writeByte('\n');
            if (d.init != ExprId.none) try dumpExpr(w, ast, offsets, d.init, depth + 1);
        },
        .expr_stmt => {
            try w.writeByte('\n');
            try dumpExpr(w, ast, offsets, ast.stmtData(id).init, depth + 1);
        },
        .err => try w.writeByte('\n'),
    }
}

fn dumpExpr(
    w: *std.Io.Writer,
    ast: *const Ast,
    offsets: Offsets,
    id: ExprId,
    depth: usize,
) std.Io.Writer.Error!void {
    const tag = ast.exprTag(id);
    const r = ast.exprTokens(id);

    try indent(w, depth);
    try w.print("expr %{d} {s} tokens {d}..{d}", .{
        id.index() - offsets.expr, @tagName(tag), r.start.index() - offsets.token, r.end.index() - offsets.token,
    });

    switch (tag) {
        .int_literal, .float_literal, .str_literal, .bool_literal, .name_ref, .param_argument, .reflection_root => {
            // A multi-line literal is spelled by every line it spans, with the
            // layout between them, so its spelling is escaped to stay on the
            // dump's one line.
            if (tag == .str_literal and ast.tokenTag(ast.exprMain(id)) == .string_line) {
                try w.writeAll(" \"");
                try writeEscaped(w, ast.exprText(id));
                try w.writeAll("\"\n");
            } else {
                try w.print(" \"{s}\"\n", .{ast.tokenText(ast.exprMain(id))});
            }
        },
        .err, .continue_, .unit_literal => try w.writeByte('\n'),
        // A bare `break` carries no operand, so it prints as a leaf.
        // What is selected is a name rather than a node, so it prints beside
        // the tag and the operand prints below it.
        .field => {
            try w.print(" \"{s}\"\n", .{ast.tokenText(ast.exprMain(id))});
            try dumpExpr(w, ast, offsets, ast.unaryOperand(id), depth + 1);
        },
        .loop_, .break_, .return_, .variant_ref => {
            try w.writeByte('\n');
            const operand = ast.unaryOperand(id);
            if (operand != ExprId.none) try dumpExpr(w, ast, offsets, operand, depth + 1);
        },
        .interp => {
            try w.writeByte('\n');
            const interpolation = ast.interpolation(id);
            for (interpolation.pieces, 0..) |piece, i| {
                if (i % 2 == 1) {
                    try indent(w, depth + 1);
                    const format = interpolation.formats[i / 2];
                    try w.print("format {s}", .{if (format.debug) "debug" else "display"});
                    if (format.laysOut()) try w.print(" {f}", .{format});
                    try w.writeByte('\n');
                }
                try dumpExpr(w, ast, offsets, piece, depth + 1);
            }
        },
        .call, .match_, .match_read, .for_, .for_read, .for_inout, .struct_literal, .struct_pattern, .array_literal, .tuple_literal, .tuple_pattern => {
            if (ast.exprTag(id) == .call and ast.callMarked(id)) try w.writeAll(" marked");
            if (ast.structLiteralHead(id)) |head| {
                try w.writeAll(" type=");
                try dumpWrittenType(w, ast, head);
            }
            try w.writeByte('\n');
            const c = ast.call(id);
            // A structure literal's base is written last, so it is dumped last.
            const base = if (ast.exprTag(id) == .struct_literal) ast.structLiteralBase(id) else null;
            if (c.callee != ExprId.none and base == null) try dumpExpr(w, ast, offsets, c.callee, depth + 1);
            const names = ast.callNames(id);
            for (c.args, 0..) |a, i| {
                // A name prints only where one was written, so the 30
                // existing goldens with no named argument stand unchanged.
                if (i < names.len and names[i] != TokenId.none) {
                    try indent(w, depth + 1);
                    try w.print("name \"{s}\"\n", .{ast.tokenText(names[i])});
                }
                try dumpExpr(w, ast, offsets, a, depth + 1);
            }
            if (base) |written| {
                try indent(w, depth + 1);
                try w.writeAll("base\n");
                try dumpExpr(w, ast, offsets, written, depth + 2);
            }
        },
        .lambda => {
            const lambda = ast.lambda(id);
            try w.print(" params={d}", .{lambda.params.len});
            if (lambda.captures.len != 0 or lambda.invocation_token != .none)
                try w.print(" invocation={s} captures={d}", .{ @tagName(lambda.invocation), lambda.captures.len });
            if (lambda.result.wasWritten()) {
                try w.writeAll(" -> ");
                try dumpWrittenType(w, ast, lambda.result);
            }
            try w.writeByte('\n');
            for (lambda.captures) |capture| {
                try indent(w, depth + 1);
                try w.print("capture {s} \"{s}\"\n", .{ @tagName(capture.convention), ast.tokenText(capture.name) });
                try dumpExpr(w, ast, offsets, capture.source, depth + 2);
            }
            for (lambda.params) |p| {
                try indent(w, depth + 1);
                if (p.pattern != ExprId.none)
                    try w.print("param {s} pattern", .{@tagName(p.convention)})
                else
                    try w.print("param {s} \"{s}\"", .{ @tagName(p.convention), ast.tokenText(p.name) });
                if (p.written.wasWritten()) {
                    try w.writeAll(" : ");
                    try dumpWrittenType(w, ast, p.written);
                }
                try w.writeByte('\n');
                if (p.pattern != ExprId.none) try dumpExpr(w, ast, offsets, p.pattern, depth + 2);
                if (p.default != ExprId.none) try dumpExpr(w, ast, offsets, p.default, depth + 2);
            }
            try dumpExpr(w, ast, offsets, lambda.body, depth + 1);
        },
        .conditional => {
            try w.writeByte('\n');
            const c = ast.conditional(id);
            try dumpExpr(w, ast, offsets, c.cond, depth + 1);
            try dumpExpr(w, ast, offsets, c.then, depth + 1);
            if (c.otherwise != ExprId.none) try dumpExpr(w, ast, offsets, c.otherwise, depth + 1);
        },
        .unwrap_else => {
            try w.writeByte('\n');
            const u = ast.unwrapElse(id);
            try dumpExpr(w, ast, offsets, u.operand, depth + 1);
            if (u.binder != ExprId.none) try dumpExpr(w, ast, offsets, u.binder, depth + 1);
            try dumpExpr(w, ast, offsets, u.body, depth + 1);
        },
        .grouped, .negate, .not, .marked, .borrow, .dereference, .copy_, .panic, .try_, .from_end => {
            try w.writeByte('\n');
            try dumpExpr(w, ast, offsets, ast.unaryOperand(id), depth + 1);
        },
        // A while prints its condition then its body, an assignment its target
        // then its value, so all three read in the order they are written.
        .index, .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge, .while_, .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign, .logical_and, .logical_or => {
            try w.writeByte('\n');
            const bin = ast.binary(id);
            try dumpExpr(w, ast, offsets, bin.lhs, depth + 1);
            try dumpExpr(w, ast, offsets, bin.rhs, depth + 1);
        },
        .range => {
            try w.print(" inclusive={}\n", .{ast.rangeInclusive(id)});
            const ends = ast.rangeEnds(id);
            try dumpExpr(w, ast, offsets, ends.lhs, depth + 1);
            try dumpExpr(w, ast, offsets, ends.rhs, depth + 1);
        },
        .block => {
            const blk = ast.blockOf(id);
            try w.writeByte('\n');
            for (ast.blockStmts(blk)) |s| try dumpStmt(w, ast, offsets, s, depth + 1);
            if (blk.tail != ExprId.none) try dumpExpr(w, ast, offsets, blk.tail, depth + 1);
        },
    }
}

test "renders a program with a binding and a tail" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "t.lin", .text = "let x = 1; x" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var b = Ast.Builder.init(gpa);
    const one = try b.addExpr(.{
        .tag = .int_literal,
        .main_token = TokenId.at(3),
        .token_range = .{ .start = TokenId.at(3), .end = TokenId.at(4) },
        .data = .{ .none = {} },
    });
    const decl = try b.addStmt(.{
        .tag = .let_decl,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(5) },
        .data = .{ .name = TokenId.at(1), .annotation = .{ .name = .none }, .init = one },
    });
    const tail = try b.addExpr(.{
        .tag = .name_ref,
        .main_token = TokenId.at(5),
        .token_range = .{ .start = TokenId.at(5), .end = TokenId.at(6) },
        .data = .{ .none = {} },
    });
    const blk = try b.addBlock(&.{decl}, tail);
    const root = try b.addExpr(.{
        .tag = .block,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(6) },
        .data = .{ .block = blk },
    });
    // A program is a list of declarations, so a tree built by hand needs one
    // for its body to belong to.
    _ = try b.addDecl(.{
        .tag = .function,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(6) },
        .name = TokenId.at(0),
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = TokenId.none },
        .body = root,
        .variants = .{ .start = 0, .end = 0 },
    });

    var ast = try b.finishOne(source.path, source.text, .from(0), tokens);

    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpAst(&out.writer, &ast, DeclarationSelection.all(ast.declCount()));

    try testing.expectEqualStrings(
        \\program decls=1
        \\  decl function "let" tokens 0..6
        \\    expr %2 block tokens 0..6
        \\      stmt %0 let_decl tokens 0..5 "x"
        \\        expr %0 int_literal tokens 3..4 "1"
        \\      expr %1 name_ref tokens 5..6 "x"
        \\
    , out.written());
}

test "a program with no tail says so" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "t.lin", .text = "" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);

    var b = Ast.Builder.init(gpa);
    const blk = try b.addBlock(&.{}, ExprId.none);
    const root = try b.addExpr(.{
        .tag = .block,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(0) },
        .data = .{ .block = blk },
    });
    _ = try b.addDecl(.{
        .tag = .function,
        .main_token = TokenId.at(0),
        .token_range = .{ .start = TokenId.at(0), .end = TokenId.at(0) },
        .name = TokenId.at(0),
        .params = .{ .start = 0, .end = 0 },
        .returns = .{ .name = TokenId.none },
        .body = root,
        .variants = .{ .start = 0, .end = 0 },
    });

    var ast = try b.finishOne(source.path, source.text, .from(0), tokens);

    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpAst(&out.writer, &ast, DeclarationSelection.all(ast.declCount()));

    try testing.expectEqualStrings(
        \\program decls=1
        \\  decl function "" tokens 0..0
        \\    expr %0 block tokens 0..0
        \\
    , out.written());
}

fn dumpWithLibraryOrder(gpa: std.mem.Allocator, files: []const Source, library_first: bool) ![]const u8 {
    const parser = @import("../parser/parser.zig");
    const program_mod = @import("program.zig");
    const FileId = @import("../support/source.zig").FileId;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    var parsed = parser.Modules.init(gpa, &sink, &interner);
    var modules: std.ArrayList(program_mod.Module) = .empty;
    for (0..files.len + 1) |i| {
        const is_library = i == @as(usize, if (library_first) 0 else 1);
        const file = FileId.from(i);
        const source: Source = if (is_library)
            .{ .path = "/embedded/std/prelude.lin", .text = "fn library(x: UInt8) -> UInt8 { let held = x; held }" }
        else
            files[if (library_first) i - 1 else if (i == 0) 0 else i - 1];
        const decls = try parsed.add(&.{.{ .file = file, .source = source }});
        const module_files = try gpa.dupe(FileId, &.{file});
        try modules.append(gpa, .{ .name = "", .dir = "", .files = module_files, .decls = decls, .imports = &.{}, .library = is_library });
    }
    const ast = try parsed.finish();
    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpAst(&out.writer, &ast, .{ .modules = modules.items });
    return out.written();
}

test "AST dump file coordinates do not depend on library placement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const inputs = [_][]const u8{
        "fn main() -> UInt8 { let value = 3; value }",
        "fn broken() -> UInt8 { let value = ; value }",
    };
    for (inputs) |text| {
        const files = [_]Source{.{ .path = "/project/main.lin", .text = text }};
        const ordinary = try dumpWithLibraryOrder(gpa, &files, false);
        const prefixed = try dumpWithLibraryOrder(gpa, &files, true);
        try testing.expectEqualStrings(ordinary, prefixed);
        try testing.expect(std.mem.indexOf(u8, prefixed, "file 0") == null);
        try testing.expect(std.mem.indexOf(u8, prefixed, "tokens 0..") != null);
    }
}

test "AST dump file coordinates identify selected files including empty files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const files = [_]Source{
        .{ .path = "/project/main.lin", .text = "fn main() -> UInt8 { let value = 3; value }" },
        .{ .path = "/project/empty.lin", .text = "// no declarations\n" },
        .{ .path = "/project/child/main.lin", .text = "fn child() -> UInt8 { let value = 4; value }" },
    };
    const ordinary = try dumpWithLibraryOrder(gpa, &files, false);
    const prefixed = try dumpWithLibraryOrder(gpa, &files, true);
    try testing.expectEqualStrings(ordinary, prefixed);
    try testing.expect(std.mem.indexOf(u8, prefixed, "file 0 \"main.lin\"\n") != null);
    try testing.expect(std.mem.indexOf(u8, prefixed, "file 1 \"empty.lin\"\n") != null);
    try testing.expect(std.mem.indexOf(u8, prefixed, "file 2 \"main.lin\"\n") != null);
    try testing.expect(std.mem.indexOf(u8, prefixed, "/project") == null);
    try testing.expect(std.mem.indexOf(u8, prefixed, "prelude.lin") == null);
}

test "AST dump identifies delegation targets and missing fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const files = [_]Source{.{ .path = "/project/main.lin", .text =
        \\impl Index[UInt64] for Board via scores
        \\impl Board { trav positions via readings }
        \\impl Index[FromEnd] for Board via
    }};
    const ordinary = try dumpWithLibraryOrder(gpa, &files, false);
    const prefixed = try dumpWithLibraryOrder(gpa, &files, true);
    try testing.expectEqualStrings(ordinary, prefixed);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, prefixed, "    via scores\n"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, prefixed, "    via readings\n"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, prefixed, "    via <missing>\n"));
}
