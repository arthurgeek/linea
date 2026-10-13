const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const positions = @import("positions.zig");
const annotated = @import("../fmt/annotated.zig");
const ast_mod = @import("../syntax/ast.zig");
const Ast = ast_mod.Ast;
const FilePart = ast_mod.FilePart;
const node = @import("../syntax/node.zig");
const StmtId = node.StmtId;
const ExprId = node.ExprId;
const Param = node.Param;
const TokenId = @import("../lexer/token.zig").TokenId;
const types_mod = @import("../sema/types.zig");
const typecheck = @import("../sema/typecheck.zig");
const Typing = types_mod.Typing;
const CallIndex = types_mod.CallIndex;
const FileId = @import("../support/source.zig").FileId;

/// The delimiters a receiver's hint carries.
///
/// Every other hint sits where the language writes punctuation, so it reads as
/// an annotation on what follows it. A receiver's sits between an expression
/// and a `.`, where the language writes nothing at all: a bare `read x` there
/// would read as source and a trailing colon would read as an annotation on the
/// receiver. These say *this is not what you wrote* at the one position where
/// nothing else does.
pub const open_hint = "\u{27e8}";
pub const close_hint = "\u{27e9}";

/// One parameter hint before it is a protocol message: the argument it is
/// about, the parameter it names, where its label goes, and what that label
/// says.
///
/// Which call and which parameter are carried because they are what a hint
/// claims: that this argument answers to that parameter, and so is taken or
/// lent as that parameter says. A reader of the label alone cannot check the
/// claim.
pub const Parameter = struct {
    call: ExprId,
    /// Which of the callee's parameters, by position.
    param: u32,
    argument: ExprId,
    /// Byte offset into the file the label sits at.
    at: u32,
    /// The parameter's declaration prefix with the type dropped, in a
    /// receiver's case wrapped in the hint's own delimiters.
    label: []const u8,
    /// Whether a gap follows the label. A hint that precedes what it describes
    /// needs one and a receiver's, which carries its own delimiters, does not.
    padded: bool,
};

/// Every parameter hint one file's calls earn.
///
/// A call site says nothing about whether it takes an argument or lends it:
/// the convention is on the parameter's declaration and nowhere else, so that
/// is where this reads it -- through the one lookup ownership reads to decide
/// the move. Nothing here infers a convention from an argument, and nothing
/// rebuilds a signature.
///
/// A call is hinted for as far as its arguments line up with that signature and
/// stops at the first position that does not, because a half-written call is
/// the ordinary state of a file an editor asks about. A callee that reaches no
/// declaration is hinted not at all: there is no signature to read, and a guess
/// would be the server answering a question the compiler did not.
///
/// Costs one walk of the file's own expressions, a constant-time lookup per
/// call and one pass over each call's written arguments, and holds one hint per
/// hinted argument. Whether an argument was written with a name is asked once
/// per hint and so is indexed rather than searched: that pass builds `named`,
/// and each hint then costs a lookup in it. Nothing here is sized by the
/// program: a module of two thousand files costs this what a module of one
/// does, because the run walked is the file's, the index answering about a
/// call is the analysis's, built once when the module was checked, and `named`
/// holds one call's arguments at a time.
pub fn parametersInFile(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    typing: *const Typing,
    calls: *const CallIndex,
    part: *const FilePart,
) ![]const Parameter {
    var out: std.ArrayList(Parameter) = .empty;
    defer out.deinit(gpa);

    // Held across the file's calls and cleared for each, so what it holds is
    // one call's arguments and the capacity is the largest call's rather than
    // an allocation per call.
    var named: Named = .empty;
    defer named.deinit(gpa);

    for (part.expr_start..part.expr_end) |i| {
        const id = ExprId.at(@intCast(i));
        // A hint names the parameter an argument fills, which the six other
        // tags sharing the call payload have none of. The tag says which it is.
        if (!ast.exprTag(id).namesArguments()) continue;
        // The release a `defer let` schedules is written nowhere, so no
        // argument of it has a place in the document to carry a hint.
        if (ast.callIsScheduledRelease(id)) continue;

        try namesWritten(gpa, ast, id, &named);
        if (calls.callOf(typing, id)) |normal| {
            const signature = switch (normal.target) {
                .declared => |decl| decl,
                .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => continue,
            };
            const params = ast.declParams(signature);
            for (normal.args, 0..) |argument, at| {
                if (at >= params.len) break;
                try appendParameterHint(gpa, ast, typing, calls, &named, &out, id, argument, @intCast(at), params[at]);
            }
            continue;
        }

        for (calls.recoveredArgsOf(typing, id)) |recovered| {
            const at = recovered.parameter orelse break;
            if (recovered.target == .none) break;
            const params = ast.declParams(recovered.target);
            if (at >= params.len) break;
            try appendParameterHint(gpa, ast, typing, calls, &named, &out, id, recovered.argument, at, params[at]);
        }
    }
    return out.toOwnedSlice(gpa);
}

fn appendParameterHint(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    typing: *const Typing,
    calls: *const CallIndex,
    named: *const Named,
    out: *std.ArrayList(Parameter),
    call: ExprId,
    argument: ExprId,
    at: u32,
    param: Param,
) !void {
    // A parameter the call omitted has no argument in this document to sit a
    // hint against: what fills it is written in the declaration.
    if (argument == ExprId.none) return;
    const tokens = ast.exprTokens(argument);
    if (tokens.len() == 0) return;

    const receiver = calls.postfixOf(typing, call) != null and at == 0;
    const anchor: ?u32 = if (receiver)
        receiverEnds(ast, call)
    else
        ast.tokenSpan(tokens.start).start;
    const goes = anchor orelse return;
    const label = try labelFor(gpa, ast, named, argument, param, receiver);
    if (label.len == 0) return;

    try out.append(gpa, .{
        .call = call,
        .param = at,
        .argument = argument,
        .at = goes,
        .label = label,
        .padded = !receiver,
    });
}

/// Where the receiver of a call written with a dot ends in the file, or null
/// where the tree recorded no tokens for it.
///
/// The argument such a call takes is the receiver with the parentheses around
/// it dropped -- that is the expression ownership decides the move for, and
/// what the hint is about. Where the hint goes is a question about the source
/// instead: written after that argument it lands inside `(a)`, and a delimiter
/// whose whole job is to say *this is not what you wrote* then says it about
/// the inside of a group the programmer did write.
///
/// So the tokens are the callee's operand, which is the receiver as it was
/// spelled. The callee is reached through `withoutGroups` because a whole
/// selection may be parenthesised too, which is the same reading the checker
/// settled the call through, and a method written with type arguments has its
/// selection in front of the brackets.
fn receiverEnds(ast: *const Ast, call: ExprId) ?u32 {
    const callee = typecheck.postfixSelection(ast, ast.call(call).callee);
    if (callee == ExprId.none) return null;
    const written = ast.unaryOperand(callee);
    if (written == ExprId.none) return null;

    const tokens = ast.exprTokens(written);
    if (tokens.len() == 0) return null;
    return ast.tokenSpan(TokenId.at(tokens.end.index() - 1)).end;
}

/// What one hint says, and the empty string where it has nothing to say.
///
/// The parameter's declaration prefix with the type dropped, so there is no
/// notation to learn: a reader who knows how to declare a parameter already
/// knows how to read one of these. A parameter carrying no convention word
/// shows none, because the grammar has none to show and inventing one would put
/// a keyword in an editor that a programmer cannot type.
///
/// Where the argument is a variable of the parameter's own name the name goes
/// and the convention stays. The usual rule elsewhere drops the whole hint,
/// which removes the ownership fact exactly where a call reads most naturally
/// and a move is easiest to miss. What is dropped is the half a reader can
/// already see.
///
/// A call that writes the name itself is the same rule: `discard(account: x)`
/// keeps `sink` and drops `account:`, because the programmer wrote that half
/// and a server repeating it says nothing the line does not.
fn labelFor(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    named: *const Named,
    argument: ExprId,
    param: Param,
    receiver: bool,
) ![]const u8 {
    const word: []const u8 = switch (param.convention) {
        .read => if (ast.paramSpellsConvention(param)) "read" else "",
        .inout => "inout",
        .sink => "sink",
    };
    // The tree question first and the index second, because nearly every call
    // in a program names nothing and a tag comparison settles it.
    const shown = !namesItsParameter(ast, argument, param.name) and
        !named.contains(argument);
    const name: []const u8 = if (shown) ast.tokenText(param.name) else "";

    if (word.len == 0 and name.len == 0) return "";
    if (receiver) return std.fmt.allocPrint(gpa, "{s}{s}{s}{s}{s}", .{
        open_hint,
        word,
        if (word.len > 0 and name.len > 0) " " else "",
        name,
        close_hint,
    });
    if (name.len == 0) return gpa.dupe(u8, word);
    return std.fmt.allocPrint(gpa, "{s}{s}{s}:", .{
        word,
        if (word.len > 0) " " else "",
        name,
    });
}

/// Which of one call's arguments the programmer wrote a name in front of, keyed
/// by the argument's own id.
///
/// A fact about the call's own text and nothing more. Which parameter a written
/// name filled is the checker's answer, read through the normalized call; this does
/// not ask it, so there is no pairing here to disagree with that one.
const Named = std.AutoHashMapUnmanaged(ExprId, void);

/// Fills `into` with the arguments the call named, replacing whatever it held.
///
/// Built once per call and asked once per hint, because that is the shape of
/// the question: every hinted argument asks it, so it is an index rather than a
/// search of the argument list apiece.
///
/// A postfix call's receiver is not among the tree's arguments and is never
/// named, so it is absent from this and reads as unnamed with no case of its
/// own.
///
/// **Bound:** one pass over the call's written argument count -- what the
/// programmer spelled, which an over-supplied call makes larger than the
/// callee's arity and which the frontend accepts and reports rather than
/// refusing. Nothing here is sized by the file, the module or the program.
fn namesWritten(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    call: ExprId,
    into: *Named,
) !void {
    into.clearRetainingCapacity();
    const args = ast.call(call).args;
    for (ast.callNames(call), 0..) |name, k| {
        if (name == TokenId.none) continue;
        if (k >= args.len) break;
        try into.put(gpa, args[k], {});
    }
}

/// Whether the argument is a variable of the parameter's own name.
///
/// Asked of the tree and of interned names, never of rendered text: two names
/// are the same name because the resolver interned them to one id.
fn namesItsParameter(ast: *const Ast, argument: ExprId, name: TokenId) bool {
    // `&p` marks that the argument will be mutated rather than being an
    // argument of its own, so what is passed is still the variable and its
    // name is still what a reader sees.
    const written = if (ast.exprTag(argument) == .marked)
        ast.unaryOperand(argument)
    else
        argument;
    if (written == ExprId.none) return false;
    if (ast.exprTag(written) != .name_ref) return false;
    return ast.tokenName(ast.exprMain(written)) == ast.tokenName(name);
}

/// What one file is worth showing inline: the type of every binding whose type
/// the source did not write, and what every call does with its arguments.
///
/// Nothing here spells a type. What the checker settled a binding to, written
/// out, is what `dump-inferred` prints and what the formatter is handed as a
/// note; this asks for the same table and shows one file's worth of it. A
/// speller of its own would agree about `UInt8` and disagree about an array,
/// which is the entry a reader most wants.
///
/// A type hint goes where the annotation would have been written -- straight
/// after the bound name -- so accepting one is an insertion and not a rewrite.
///
/// The two are distinct protocol kinds, which is how an editor turns one off
/// without the other; there is no switch of this server's own, because that
/// would be inventing a control the client already has.
///
/// `range` is what the client asked about, and hints outside it are not sent:
/// a client asks about the part of the document it is showing.
///
/// Costs one pass over the file's statements, one over the file's expressions,
/// one over the file's bytes, and one label per hint, plus the sort that puts
/// the two kinds into document order. Which statements and which expressions
/// are the file's is the run the tree recorded when it parsed it, so what is
/// walked and what is held are both the document's -- a table of the program's
/// statements would be the library's as well, allocated afresh on every scroll.
/// The pass over the bytes is what `positionsOf` costs however many hints ask
/// about it.
/// Lists each `for` binder and each `else` binder in this file, with the type
/// the checker settled it to.
///
/// Neither takes an annotation -- there is no `for x: T in xs` and no
/// `else |e: E|` -- so a dump that writes types into source has nothing it
/// could write, and says nothing. A hint is not source, so it can say what the
/// binder holds, which is a binding in a body whose type is never written
/// down.
///
/// Sized by this file's expressions rather than the program's, because a
/// server asks per file on every scroll.
fn bindersInFile(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    typing: *const Typing,
    part: *const FilePart,
) ![]const Binder {
    var out: std.ArrayList(Binder) = .empty;
    errdefer {
        for (out.items) |b| gpa.free(b.label);
        out.deinit(gpa);
    }

    for (part.expr_start..part.expr_end) |i| {
        const id = ExprId.at(@intCast(i));
        const binder = switch (ast.exprTag(id)) {
            .for_, .for_read, .for_inout => ast.call(id).args[0],
            .unwrap_else => ast.unwrapElse(id).binder,
            else => continue,
        };
        if (binder == ExprId.none) continue;
        if (ast.exprTag(binder) != .name_ref) continue;

        const name = typing.settledName(typing.exprType(binder)) orelse continue;
        if (name.len == 0) continue;

        try out.append(gpa, .{
            .at = ast.tokenSpan(ast.exprMain(binder)).end,
            .label = try std.fmt.allocPrint(gpa, ": {s}", .{name}),
        });
    }

    return out.toOwnedSlice(gpa);
}

/// Holds one binder's hint: the offset it is written at and its label.
const Binder = struct {
    at: u32,
    label: []const u8,
};

pub fn forFile(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    file: FileId,
    range: lsp.types.Range,
    encoding: lsp.offsets.Encoding,
) ![]const lsp.types.InlayHint {
    const ast = &checked.program.ast;
    const part = ast.partOfFile(file) orelse return &.{};

    const bindings = try annotated.bindingTypes(
        gpa,
        ast,
        &checked.semantics.res,
        &checked.semantics.typing,
        part.stmt_start,
        part.stmt_end,
    );
    defer gpa.free(bindings);

    const params = try parametersInFile(
        gpa,
        ast,
        &checked.semantics.typing,
        &checked.semantics.typing.call_index,
        part,
    );
    defer {
        for (params) |p| gpa.free(p.label);
        gpa.free(params);
    }

    const binders = try bindersInFile(gpa, ast, &checked.semantics.typing, part);
    defer {
        for (binders) |b| gpa.free(b.label);
        gpa.free(binders);
    }

    var constants: std.ArrayList(Binder) = .empty;
    defer {
        for (constants.items) |constant| gpa.free(constant.label);
        constants.deinit(gpa);
    }
    for (part.decl_start..part.decl_end) |i| {
        const declaration = node.DeclId.at(@intCast(i));
        if (ast.declReturnRef(declaration).wasWritten()) continue;
        const ty = annotated.constantType(ast, &checked.semantics.typing, declaration) orelse continue;
        const label = try std.fmt.allocPrint(gpa, ": {s}", .{checked.semantics.typing.nameOf(ty)});
        errdefer gpa.free(label);
        try constants.append(gpa, .{
            .at = ast.tokenSpan(ast.declName(declaration)).end,
            .label = label,
        });
    }

    var found: std.ArrayList(StmtId) = .empty;
    defer found.deinit(gpa);
    var offsets: std.ArrayList(u32) = .empty;
    defer offsets.deinit(gpa);

    for (bindings, 0..) |written, i| {
        if (written.len == 0) continue;
        const id = StmtId.at(@intCast(part.stmt_start + i));
        try found.append(gpa, id);
        try offsets.append(gpa, ast.tokenSpan(ast.stmtData(id).name).end);
    }
    for (params) |p| try offsets.append(gpa, p.at);
    for (binders) |b| try offsets.append(gpa, b.at);
    for (constants.items) |constant| try offsets.append(gpa, constant.at);

    const at = try positions.positionsOf(gpa, part.source, offsets.items, encoding);
    defer gpa.free(at);

    var out: std.ArrayList(lsp.types.InlayHint) = .empty;
    for (found.items, at[0..found.items.len]) |id, position| {
        if (!within(range, position)) continue;
        try out.append(gpa, .{
            .position = position,
            .label = .{ .string = try std.fmt.allocPrint(
                gpa,
                ": {s}",
                .{bindings[id.index() - part.stmt_start]},
            ) },
            .kind = .Type,
        });
    }
    for (params, at[found.items.len..][0..params.len]) |p, position| {
        if (!within(range, position)) continue;
        try out.append(gpa, .{
            .position = position,
            .label = .{ .string = try gpa.dupe(u8, p.label) },
            .kind = .Parameter,
            .paddingRight = if (p.padded) true else null,
        });
    }
    for (binders, at[found.items.len + params.len ..][0..binders.len]) |b, position| {
        if (!within(range, position)) continue;
        try out.append(gpa, .{
            .position = position,
            .label = .{ .string = try gpa.dupe(u8, b.label) },
            .kind = .Type,
        });
    }

    for (constants.items, at[found.items.len + params.len + binders.len ..]) |constant, position| {
        if (!within(range, position)) continue;
        try out.append(gpa, .{
            .position = position,
            .label = .{ .string = try gpa.dupe(u8, constant.label) },
            .kind = .Type,
        });
    }

    // Document order, because the two kinds are gathered a kind at a time and
    // a reader reads a file top to bottom. A stable sort, so hints that share a
    // position keep the order they were gathered in rather than one the sort
    // picked.
    std.mem.sort(lsp.types.InlayHint, out.items, {}, struct {
        fn less(_: void, a: lsp.types.InlayHint, b: lsp.types.InlayHint) bool {
            return before(a.position, b.position);
        }
    }.less);
    return out.toOwnedSlice(gpa);
}

/// Whether a position sits inside the range a client asked about, which is
/// ordered by line and then by how far along it the position is.
fn within(range: lsp.types.Range, position: lsp.types.Position) bool {
    return !before(position, range.start) and !before(range.end, position);
}

fn before(a: lsp.types.Position, b: lsp.types.Position) bool {
    if (a.line != b.line) return a.line < b.line;
    return a.character < b.character;
}

const whole: lsp.types.Range = .{
    .start = .{ .line = 0, .character = 0 },
    .end = .{ .line = std.math.maxInt(u32), .character = 0 },
};

fn free(gpa: std.mem.Allocator, found: []const lsp.types.InlayHint) void {
    for (found) |h| gpa.free(h.label.string);
    gpa.free(found);
}

test "a hint stands where no type was written, and nowhere else" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
        \\fn main() -> UInt8 {
        \\    let a: UInt8 = 1
        \\    let b = a
        \\    let xs: [UInt8; 2] = [b, 3]
        \\    xs[0]
        \\}
        \\
        },
    }, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, whole, .@"utf-16");
    defer free(gpa, found);

    // `b` alone. `a` carries a written type, and so does `xs` -- whose
    // written type has no name at all, which is the annotation a reader
    // looking for one would miss.
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings(": UInt8", found[0].label.string);
    try testing.expectEqual(lsp.types.Position{ .line = 2, .character = 9 }, found[0].position);
}

test "a hint outside the range asked about is not sent" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
        \\fn main() -> UInt8 {
        \\    let a = 1
        \\    let b = 2
        \\    a + b
        \\}
        \\
        },
    }, "main.lin");
    defer checked.deinit();

    const both = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, whole, .@"utf-16");
    defer free(gpa, both);
    try testing.expectEqual(@as(usize, 2), both.len);

    const second = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, .{
        .start = .{ .line = 2, .character = 0 },
        .end = .{ .line = 3, .character = 0 },
    }, .@"utf-16");
    defer free(gpa, second);

    try testing.expectEqual(@as(usize, 1), second.len);
    try testing.expectEqual(@as(u32, 2), second[0].position.line);
}

test "a receiver's hint sits after the receiver as it was written" {
    const gpa = testing.allocator;

    // The argument the call takes is the receiver with its parentheses
    // dropped, which is what ownership reads. Where the hint goes is a
    // question about the source: a hint at the end of that argument sits
    // inside the parentheses and reads as an annotation on what is in them.
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
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
        \\    let a: Account = .{ balance = 7 }
        \\    (a).of(2)
        \\}
        \\
        },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, whole, .@"utf-16");
    defer free(gpa, found);

    // `(a)⟨x⟩.of(since: 2)`: the receiver's, then the one inside the
    // parentheses of the call.
    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqualStrings(open_hint ++ "x" ++ close_hint, found[0].label.string);
    try testing.expectEqual(lsp.types.Position{ .line = 16, .character = 7 }, found[0].position);
}

test "a rejected call is hinted through its matched prefix" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text =
        \\fn total(a: UInt8, b: UInt8) -> UInt8 { a + b }
        \\fn main() -> UInt8 { total(1) + total(1, 2, 3) }
        \\
        },
    }, "main.lin");
    defer checked.deinit();

    const found = try forFile(gpa, &checked, checked.fileNamed("main.lin").?, whole, .@"utf-16");
    defer free(gpa, found);

    try testing.expectEqual(@as(usize, 3), found.len);
    try testing.expectEqualStrings("a:", found[0].label.string);
    try testing.expectEqualStrings("a:", found[1].label.string);
    try testing.expectEqualStrings("b:", found[2].label.string);
}

test "a file of a module is hinted by its own bindings" {
    const gpa = testing.allocator;

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 {\n    let m = helper()\n    m\n}\n" },
        .{ .path = "app/helper.lin", .text = "fn helper() -> UInt8 {\n    let h = 1\n    h\n}\n" },
    }, "app");
    defer checked.deinit();

    var wanted: FileId = checked.fileNamed("app/main.lin").?;
    for (0..checked.table.count()) |i| {
        const f: FileId = .from(@intCast(i));
        if (std.mem.eql(u8, checked.table.get(f).path, "app/helper.lin")) wanted = f;
    }

    const found = try forFile(gpa, &checked, wanted, whole, .@"utf-16");
    defer free(gpa, found);

    // One hint, on `h`, positioned in *that* file rather than wherever the
    // binding sits in the module's stream.
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqual(@as(u32, 1), found[0].position.line);
}

test "inferred constants receive type hints without repeating annotations" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{.{
        .path = "app/main.lin",
        .text = "let answer = UInt8(42)\nlet annotated: UInt8 = answer\nfn main() -> UInt8 { annotated }\n",
    }}, "app");
    defer checked.deinit();
    const found = try forFile(gpa, &checked, checked.fileNamed("app/main.lin").?, whole, .@"utf-16");
    defer free(gpa, found);
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings(": UInt8", found[0].label.string);
    try testing.expectEqual(@as(u32, 0), found[0].position.line);
}
