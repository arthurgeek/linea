const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const positions = @import("positions.zig");
const Node = positions.Node;
const annotated = @import("../fmt/annotated.zig");
const Ast = @import("../syntax/ast.zig").Ast;
const ExprId = @import("../syntax/node.zig").ExprId;
const resolve_mod = @import("../sema/resolve.zig");
const typecheck = @import("../sema/typecheck.zig");
const types_mod = @import("../sema/types.zig");
const Param = @import("../syntax/node.zig").Param;
const BindingId = resolve_mod.BindingId;
const FileId = @import("../support/source.zig").FileId;

/// What the compiler settled about what a cursor sits on, or null where
/// nothing there has a type.
///
/// A compiler fact and not documentation: the type, spelled the way the
/// checker spells it, and -- where the cursor sits on a generic call -- what
/// that call instantiated its callee to. No doc comment, no signature, no list
/// of what a type implements. That is a floor rather than an unfinished
/// feature: everything here is something the compiler decided, and a server
/// that rendered a declaration would be a second opinion about what one means.
///
/// Two things a cursor lands on have nothing the compiler decided, and both are
/// answered as nothing rather than as the entry sitting in the table. A name
/// that reaches a namespace holds unit there so a walk for an unsettled type
/// does not stop on it, and an expression already reported on holds the type
/// standing in for one the checker never settled. Reporting either would put a
/// sentence in an editor that no pass of this compiler agrees with.
///
/// Nothing here spells a type. `nameOf` is what a diagnostic and a dump are
/// spelled with, and a speller of this module's own would agree about `UInt8`
/// and disagree about an instantiation, which is the entry a reader most wants.
/// Which arguments a call was instantiated with is likewise read from where the
/// checker recorded it, through the index the analysis holds, rather than
/// worked out again from the argument types.
///
/// Costs one pass over the document's bytes to reach the cursor, a binary
/// search over the file's own tokens, a constant-time lookup per question, and
/// one pass over the file's bytes to place the range. The answer's length is
/// the instantiation's arguments and nothing else, so nothing here is sized by
/// what the program holds.
pub fn forPosition(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    position: lsp.types.Position,
    encoding: lsp.offsets.Encoding,
) !?lsp.types.Hover {
    const ast = &checked.program.ast;
    const typing = &checked.semantics.typing;
    const part = ast.partOfFile(file) orelse return null;

    const found = checked.cursors.atPosition(ast, part, position, encoding) orelse return null;

    // A written type is a token rather than an expression -- an annotation, a
    // return, a field's type, a type argument -- so no expression's entry says
    // what it became. The checker recorded that against the token that wrote
    // it, which is where this reads it: which instantiation a written type
    // settled to is a fixed point that ran, and nothing recovers it from the
    // source.
    if (typing.writtenType(@intFromEnum(found.token))) |settled| {
        return .{
            .contents = .{ .markup_content = .{
                .kind = .plaintext,
                .value = try gpa.dupe(u8, typing.nameOf(settled)),
            } },
            .range = positions.rangeOf(part.source, ast.tokenSpan(found.token), encoding),
        };
    }

    const reported: []const u8, const span = switch (found.node) {
        .expr => |written| blk: {
            var chain = checked.cursors.enclosing(ast, file, @intCast(lsp.offsets.positionToIndex(part.source, position, encoding)));
            _ = chain.next();
            const e = calledThrough(ast, written, &chain);
            if (reachesNoValue(checked, e) and typing.call_index.functionValueOf(typing, e) == null) return null;
            if (typing.exprType(e) == .poison) return null;
            break :blk .{ try saidOfExpr(gpa, checked, e), ast.exprSpan(e) };
        },

        // A statement that bound a name is the name's own node: `let total`
        // writes no expression the name is, so a cursor on it lands here and
        // the type is the binding's rather than any expression's.
        .stmt => |s| blk: {
            const b = checked.semantics.res.bindingOf(s);
            if (b == BindingId.none) return null;
            const of = typing.bindingType(b);
            if (of == .poison) return null;
            const labels = if (typing.binding_labels.get(b)) |range| ast.params[range.start..range.end] else null;
            break :blk .{ try described(gpa, typing, ast, of, labels), ast.stmtSpan(s) };
        },

        .decl => |declaration| blk: {
            // An alias's name is not the type it names, so it says which.
            if (ast.declTag(declaration) == .alias) {
                const named = typing.aliasedType(declaration);
                if (named == .poison) return null;
                // A function type is spelled with the labels the alias wrote.
                const written = ast.withoutTypeGroups(ast.declReturnRef(declaration));
                const labels: ?[]const Param = if (written.kind == .callable) labels: {
                    const range = ast.callableType(written).params;
                    break :labels ast.params[range.start..range.end];
                } else null;
                break :blk .{ try described(gpa, typing, ast, named, labels), ast.tokenSpan(ast.declName(declaration)) };
            }
            const ty = annotated.constantType(ast, typing, declaration) orelse return null;
            break :blk .{ try gpa.dupe(u8, typing.nameOf(ty)), ast.tokenSpan(ast.declName(declaration)) };
        },
    };

    return .{
        .contents = .{ .markup_content = .{ .kind = .plaintext, .value = reported } },
        .range = positions.rangeOf(part.source, span, encoding),
    };
}

/// A type as a description of one value: a function spelled with the labels
/// `labels` a call through the value uses, and every other type, or a
/// function nothing labelled, by its own spelling.
fn described(gpa: std.mem.Allocator, typing: *const types_mod.Typing, ast: *const Ast, ty: types_mod.TypeId, labels: ?[]const Param) ![]const u8 {
    if (typing.get(ty) == .callable) if (labels) |params| {
        if (params.len == typing.callableParams(typing.get(ty).callable).len) {
            const names = try gpa.alloc([]const u8, params.len);
            defer gpa.free(names);
            for (params, names) |param, *spelled| spelled.* = ast.paramSpelling(param);
            return typing.spellCallable(gpa, ty, names);
        }
    };
    return gpa.dupe(u8, typing.nameOf(ty));
}

/// Whether a name reaches something that carries no value to report a type of.
///
/// The checker records unit for the qualifier of a path through one so that a
/// walk looking for a type it failed to settle does not stop there. That is
/// bookkeeping and not an answer, so what the resolver decided the name
/// reaches is what decides this here, rather than the placeholder -- and which
/// kinds those are comes from the predicate the checker's own bookkeeping
/// reads, so the two cannot disagree about a kind added later.
fn reachesNoValue(checked: *const Analysis, e: ExprId) bool {
    const res = &checked.semantics.res;
    const b = res.targetOf(e);
    if (b == BindingId.none) return false;
    return resolve_mod.carriesNoValue(res.kindOf(b));
}

/// The call an expression is the callee of, or the expression itself.
///
/// A cursor on `ident` in `ident(n)` is a cursor on that call. The callee names
/// a declaration rather than a value, so it has no type of its own to report --
/// and what a reader points at when pointing at a call is its name.
///
/// A name written with type arguments, `parse[UInt16]()`, sits inside the
/// bracket that is the call's callee, so the call is one level further out.
fn calledThrough(ast: *const Ast, e: ExprId, chain: *positions.Index.Enclosing) ExprId {
    var callee = e;
    var outer = enclosingExpr(chain) orelse return e;
    if (ast.exprTag(outer) == .index and ast.bracketTypes(outer) != null and ast.binary(outer).lhs == e) {
        callee = outer;
        outer = enclosingExpr(chain) orelse return e;
    }
    if (ast.exprTag(outer) != .call) return e;
    if (ast.call(outer).callee != callee) return e;
    return outer;
}

fn enclosingExpr(chain: *positions.Index.Enclosing) ?ExprId {
    return switch (chain.next() orelse return null) {
        .expr => |x| x,
        .decl, .stmt => null,
    };
}

/// What one expression is told about: its type, and the instantiation where
/// the expression is a call that made one.
///
/// `ident[UInt8] -> UInt8` is the callee as it was written, the arguments the
/// call settled, and what it gives back; a call giving back `()` has no arrow,
/// as its signature has none. The arrow is the language's own, so there is no
/// notation to learn, and the arguments are spelled where an
/// instantiation is spelled everywhere else -- the same text `dump-inferred`
/// writes over the same call.
fn saidOfExpr(gpa: std.mem.Allocator, checked: *const Analysis, e: ExprId) ![]const u8 {
    const ast = &checked.program.ast;
    const typing = &checked.semantics.typing;
    const ty = typing.exprType(e);
    const of = typing.nameOf(ty);

    // A value holding a function is described with the labels a call
    // through it names, as the checker reads them.
    if (typing.get(ty) == .callable) {
        const sources: typecheck.LabelSources = .{
            .ast = ast,
            .res = &checked.semantics.res,
            .typing = typing.*,
            .binding_types = &typing.binding_types,
            .field_names = &typing.field_names,
            .binding_labels = &typing.binding_labels,
        };
        return described(gpa, typing, ast, ty, sources.ofCallee(e));
    }

    if (ast.exprTag(e) == .call) {
        if (typing.call_index.callOf(typing, e)) |call| {
            const args = call.selection.own_args;
            if (args.len == 0) return gpa.dupe(u8, of);
            const spelled = try annotated.spellArgs(gpa, typing, args);
            defer gpa.free(spelled);
            // A call to a function returning `()` is shown as its signature
            // is written: without a result.
            if (ty == .unit) return std.fmt.allocPrint(gpa, "{s}{s}", .{
                ast.exprText(typecheck.calleeName(ast, call)),
                spelled,
            });
            return std.fmt.allocPrint(gpa, "{s}{s} -> {s}", .{
                ast.exprText(typecheck.calleeName(ast, call)),
                spelled,
                of,
            });
        }
    }
    return gpa.dupe(u8, of);
}

const widening_program =
    \\fn add(a: UInt8, b: UInt8) -> UInt16 {
    \\    UInt16(a) + UInt16(b)
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let written: UInt16 = 1
    \\    let inferred = add(2, 3)
    \\    UInt8(written + inferred)
    \\}
    \\
;

const generic_program =
    \\fn ident[T: Copyable](a: T) -> T {
    \\    copy(a)
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let n: UInt8 = 3
    \\    let same: UInt8 = ident(n)
    \\    let flag: Bool = ident(true)
    \\
    \\    if flag {
    \\        same
    \\    } else {
    \\        0
    \\    }
    \\}
    \\
;

const trait_program =
    \\struct Account {
    \\    balance: UInt8,
    \\}
    \\
    \\trait Measure {
    \\    fn of(x: Self, since: UInt8) -> UInt8
    \\}
    \\
    \\impl Measure for Account {
    \\    fn of(x: Self, since: UInt8) -> UInt8 {
    \\        x.balance + since
    \\    }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let a: Account = .{ balance = 1 }
    \\    Measure.of(a, 4)
    \\}
    \\
;

fn at(text: []const u8, offset: usize) lsp.types.Position {
    return lsp.offsets.indexToPosition(text, offset, .@"utf-16");
}

/// What one cursor is told about a checked module, with the answer released.
fn told(gpa: std.mem.Allocator, checked: *const Analysis, text: []const u8, offset: usize) ![]const u8 {
    const found = try forPosition(gpa, checked, checked.program.primaryFile(), at(text, offset), .@"utf-16") orelse
        return gpa.dupe(u8, "");
    defer gpa.free(found.contents.markup_content.value);
    return gpa.dupe(u8, found.contents.markup_content.value);
}

/// What one cursor is told about a program the compiler accepts.
fn said(gpa: std.mem.Allocator, text: []const u8, offset: usize) ![]const u8 {
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    return told(gpa, &checked, text, offset);
}

/// What one cursor is told about a program the compiler rejects, which is the
/// ordinary state of a file being typed into.
fn saidOfRejected(gpa: std.mem.Allocator, text: []const u8, offset: usize) ![]const u8 {
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    try testing.expect(checked.sink.hasErrors());
    return told(gpa, &checked, text, offset);
}

test "bindings and expressions say the type the checker settled" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = widening_program }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const offsets = [_]usize{
        std.mem.indexOf(u8, widening_program, "written:").? + 2,
        std.mem.indexOf(u8, widening_program, "inferred =").? + 2,
        std.mem.indexOf(u8, widening_program, "add(2, 3)").? + 1,
        std.mem.indexOf(u8, widening_program, "written + inferred").? + 8,
    };
    for (offsets) |offset| {
        const value = try told(gpa, &checked, widening_program, offset);
        defer gpa.free(value);
        try testing.expectEqualStrings("UInt16", value);
    }
}

test "a type written without a defaulted argument says the default it took" {
    const gpa = testing.allocator;
    const text =
        \\struct Crate[T, K = UInt8] {
        \\    value: T,
        \\    tag: K,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let crate: Crate[UInt16] = .{ value = 1, tag = 2 }
        \\    crate.tag
        \\}
        \\
    ;
    const told_type = try said(gpa, text, std.mem.indexOf(u8, text, "crate:").? + 2);
    defer gpa.free(told_type);
    try testing.expectEqualStrings("Crate[UInt16, UInt8]", told_type);
}

test "a generic call says what it instantiated to" {
    const gpa = testing.allocator;

    const of_number = try said(gpa, generic_program, std.mem.indexOf(u8, generic_program, "ident(n)").? + 2);
    defer gpa.free(of_number);
    try testing.expectEqualStrings("ident[UInt8] -> UInt8", of_number);

    const of_bool = try said(gpa, generic_program, std.mem.indexOf(u8, generic_program, "ident(true)").? + 2);
    defer gpa.free(of_bool);
    try testing.expectEqualStrings("ident[Bool] -> Bool", of_bool);
}

test "a call naming its type arguments says what it instantiated to" {
    const gpa = testing.allocator;
    const text =
        \\struct Shelf {
        \\    width: UInt8,
        \\}
        \\
        \\impl Shelf {
        \\    fn widened[T](self: Shelf, sink extra: T) -> T {
        \\        if self.width == 0 {
        \\            return extra
        \\        }
        \\        extra
        \\    }
        \\}
        \\
        \\fn ident[T](sink v: T) -> T {
        \\    v
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let shelf: Shelf = .{ width = 1 }
        \\    ident[UInt8](3) + shelf.widened[UInt8](4)
        \\}
        \\
    ;
    const free = try said(gpa, text, std.mem.indexOf(u8, text, "ident[UInt8](3)").? + 2);
    defer gpa.free(free);
    try testing.expectEqualStrings("ident[UInt8] -> UInt8", free);

    const method = try said(gpa, text, std.mem.indexOf(u8, text, "widened[UInt8](4)").? + 2);
    defer gpa.free(method);
    try testing.expectEqualStrings("shelf.widened[UInt8] -> UInt8", method);
}

test "a selected function reference says its structural signature" {
    const gpa = testing.allocator;
    const text =
        \\fn identity[T: Copyable](value: T) -> T { copy(value) }
        \\fn main() -> UInt8 {
        \\    let selected: fn(read value: UInt8) -> UInt8 = identity
        \\    selected(6)
        \\}
        \\
    ;
    const selected = try said(gpa, text, std.mem.indexOf(u8, text, "= identity").? + 3);
    defer gpa.free(selected);
    try testing.expectEqualStrings("fn(read value: UInt8) -> UInt8", selected);
}

test "a function value is described with the labels its calls use" {
    const gpa = testing.allocator;
    const text =
        \\fn add_one(value: UInt8) -> UInt8 { value + 1 }
        \\fn add_two(amount: UInt8) -> UInt8 { amount + 2 }
        \\fn main() -> UInt8 {
        \\    let step: fn(read by: UInt8) -> UInt8 = add_one
        \\    let joined = if true { add_one } else { add_two }
        \\    step(1) + joined(2)
        \\}
        \\
    ;
    const labelled = try said(gpa, text, std.mem.indexOf(u8, text, "let step").? + 4);
    defer gpa.free(labelled);
    try testing.expectEqualStrings("fn(read by: UInt8) -> UInt8", labelled);
    const positional = try said(gpa, text, std.mem.indexOf(u8, text, "let joined").? + 4);
    defer gpa.free(positional);
    try testing.expectEqualStrings("fn(read UInt8) -> UInt8", positional);
}

const written_program =
    \\struct Point {
    \\    x: UInt8,
    \\}
    \\
    \\struct Cell[T] {
    \\    v: T,
    \\}
    \\
    \\fn zero() -> Point {
    \\    .{ x = 0 }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let held: Cell[Point] = .{ v = zero() }
    \\    held.v.x
    \\}
    \\
;

test "a written type says what it settled to" {
    const gpa = testing.allocator;

    // A return type is a written type and not an expression, and the type it
    // settled to is the one the checker recorded against the token that wrote
    // it.
    const returned = try said(gpa, written_program, std.mem.indexOf(u8, written_program, "-> Point").? + 4);
    defer gpa.free(returned);
    try testing.expectEqualStrings("Point", returned);

    // The instantiation, spelled the way the checker spells it -- which is
    // what a reader most wants and what a speller of this module's own would
    // get wrong.
    const held = try said(gpa, written_program, std.mem.indexOf(u8, written_program, "Cell[Point]").? + 1);
    defer gpa.free(held);
    try testing.expectEqualStrings("Cell[Point]", held);
}

const alias_program =
    \\alias Pricing = fn(cents: UInt64) -> UInt64
    \\
    \\fn fee(cents: UInt64) -> UInt64 {
    \\    cents + 499
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    let rule: Pricing = fee
    \\    UInt8(rule(1) - 500)
    \\}
    \\
;

test "an alias says the type it names, where it is declared and where it is written" {
    const gpa = testing.allocator;

    // The declaration spells the function type with the labels it wrote.
    const declared = try said(gpa, alias_program, std.mem.indexOf(u8, alias_program, "Pricing").? + 1);
    defer gpa.free(declared);
    try testing.expectEqualStrings("fn(read cents: UInt64) -> UInt64", declared);

    // A written use says what it settled to, which is the type itself.
    const written = try said(gpa, alias_program, std.mem.indexOf(u8, alias_program, ": Pricing").? + 3);
    defer gpa.free(written);
    try testing.expectEqualStrings("fn(read UInt64) -> UInt64", written);
}

const generic_alias_head_program =
    \\struct Cell[T] {
    \\    value: T,
    \\}
    \\
    \\impl[T] Cell[T] {
    \\    fn wrap(sink value: T) -> Cell[T] {
    \\        .{ value = value }
    \\    }
    \\}
    \\
    \\alias Slot[T] = Cell[T]
    \\
    \\fn main() -> UInt8 {
    \\    let held: Slot[UInt8] = Slot.wrap(3)
    \\    let Cell { value } = held
    \\    value
    \\}
    \\
;

test "a generic alias heading a path says the type it names with its own parameters open" {
    const gpa = testing.allocator;

    const head = try said(gpa, generic_alias_head_program, std.mem.indexOf(u8, generic_alias_head_program, "Slot.wrap").? + 1);
    defer gpa.free(head);
    try testing.expectEqualStrings("Cell[T]", head);
}

test "a cursor on a declaration itself is told nothing" {
    const gpa = testing.allocator;

    // The `fn` that opens a declaration is not an expression and names no
    // binding, so there is no type to report.
    const keyword = try said(gpa, widening_program, 1);
    defer gpa.free(keyword);
    try testing.expectEqualStrings("", keyword);
}

test "a cursor on a namespace is told nothing" {
    const gpa = testing.allocator;

    // A trait is not a value and no value has one for its type -- the checker
    // says so itself with [N-Not-A-Value]. What sits in the table for the
    // qualifier of a path is bookkeeping that keeps the poison check honest,
    // and reporting it would tell a reader that a trait is unit.
    const trait = try said(gpa, trait_program, std.mem.indexOf(u8, trait_program, "Measure.of").? + 1);
    defer gpa.free(trait);
    try testing.expectEqualStrings("", trait);
}

test "a call written with a dot says what the call written out says" {
    const gpa = testing.allocator;

    // Two spellings of one call. What a reader points at when pointing at
    // either is the call, so the answer is the call's type both times -- a
    // cursor on the callee of the dotted one reaching the selection instead
    // would report what a field access is worth.
    const text =
        \\struct Account {
        \\    balance: UInt8,
        \\}
        \\
        \\trait Measure {
        \\    fn of(x: Self, since: UInt8) -> UInt8
        \\}
        \\
        \\impl Measure for Account {
        \\    fn of(x: Self, since: UInt8) -> UInt8 {
        \\        x.balance + since
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ balance = 1 }
        \\    let b: Account = .{ balance = 2 }
        \\    Measure.of(a, 4) + b.of(1)
        \\}
        \\
    ;
    const dotted = try said(gpa, text, std.mem.indexOf(u8, text, "b.of(1)").? + 2);
    defer gpa.free(dotted);
    const written = try said(gpa, text, std.mem.indexOf(u8, text, "Measure.of(a, 4)").? + 8);
    defer gpa.free(written);

    try testing.expectEqualStrings("UInt8", written);
    try testing.expectEqualStrings(written, dotted);
}

test "a cursor on what has no settled type is told nothing" {
    const gpa = testing.allocator;

    // A type the checker could not settle, which is what an expression already
    // reported on is left with. There is nothing the compiler decided to say.
    const text = "fn main() -> UInt8 {\n    let n: UInt8 = true\n    n\n}\n";
    const broken = try saidOfRejected(gpa, text, std.mem.indexOf(u8, text, "true").? + 1);
    defer gpa.free(broken);
    try testing.expectEqualStrings("", broken);
}

test "inferred constants show their declaration type" {
    const gpa = testing.allocator;
    const text = "let answer = UInt8(42)\nfn main() -> UInt8 { answer }\n";
    const found = try said(gpa, text, 5);
    defer gpa.free(found);
    try testing.expectEqualStrings("UInt8", found);
}

test "intrinsic integer properties report concrete and symbolic types" {
    const gpa = testing.allocator;
    const text = "fn limit[T: Integer](_value: T) -> T { T.max }\nfn main() -> UInt8 { limit(UInt8.min) }\n";
    const concrete = try said(gpa, text, std.mem.indexOf(u8, text, "UInt8.min").? + "UInt8.".len);
    defer gpa.free(concrete);
    try testing.expectEqualStrings("UInt8", concrete);
    const symbolic = try said(gpa, text, std.mem.indexOf(u8, text, "T.max").? + "T.".len);
    defer gpa.free(symbolic);
    try testing.expectEqualStrings("T", symbolic);
}

test "inferred array lengths expose concrete types in hover" {
    const gpa = testing.allocator;
    const text =
        \\fn main() -> UInt8 {
        \\    let values: [UInt8; _] = [1, 2]
        \\    let grid: [[UInt8; _]; _] = [[1, 2], [3, 4]]
        \\    values[0] + grid[1][0]
        \\}
    ;
    const values = try said(gpa, text, std.mem.indexOf(u8, text, "values:").?);
    defer gpa.free(values);
    try testing.expectEqualStrings("[UInt8; 2]", values);
    const grid = try said(gpa, text, std.mem.indexOf(u8, text, "grid:").?);
    defer gpa.free(grid);
    try testing.expectEqualStrings("[[UInt8; 2]; 2]", grid);
}
