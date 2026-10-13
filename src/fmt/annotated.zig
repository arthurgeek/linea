//! A program rendered back as Linea with what a later pass decided written
//! into it.
//!
//! Rendering Linea is this directory's job, and what to write is the deciding
//! pass's: the notes come from wherever the answer was settled, and nothing
//! here works one out. Neither output parses back -- a call's type arguments
//! have no syntax to be written in -- which is the point, because the
//! questions they answer are the ones the source cannot be read for.

const DeclarationSelection = @import("../syntax/program.zig").DeclarationSelection;

const std = @import("std");

const Ast = @import("../syntax/ast.zig").Ast;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const node = @import("../syntax/node.zig");
const types = @import("../sema/types.zig");
const Resolution = @import("../sema/resolve.zig").Resolution;
const BindingId = @import("../sema/ids.zig").BindingId;
const Typing = types.Typing;
const mir = @import("../mir/mir.zig");
const notes = @import("../mir/notes.zig");
const fmt = @import("fmt.zig");

/// `[u8, bool]`, as an instantiation's arguments are written.
///
/// One spelling, because a dump and a hover naming the same instantiation
/// differently is two answers to what a call became.
///
/// Owned by the caller: a dump holds every one it makes until the whole
/// program is written, and a server releases each answer as it is sent.
pub fn spellArgs(
    gpa: std.mem.Allocator,
    typing: *const Typing,
    args: []const types.TypeId,
) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("[");
    for (args, 0..) |a, i| {
        if (i > 0) try out.writer.writeAll(", ");
        switch (typing.get(a)) {
            .closure => {
                const name = try notes.closureTypeName(gpa, typing, a);
                defer gpa.free(name);
                try out.writer.writeAll(name);
            },
            else => try out.writer.writeAll(typing.nameOf(a)),
        }
    }
    try out.writer.writeAll("]");
    return out.toOwnedSlice();
}

/// What a type was instantiated from, if it is an instantiation at all.
fn argsOfType(typing: *const Typing, t: types.TypeId) ?[]const types.TypeId {
    return typing.argsOf(typing.instanceOf(t) orelse return null);
}

/// What a type was instantiated at, where the written head names the
/// declaration it came from.
///
/// `Option.Some` heads an `Option`, so the arguments belong on it.
/// `Account.open` heads an `Account` and returns something else, so they do
/// not -- writing them there would say the call built an `Account` of
/// something, which is not what happened.
fn instanceHeaded(
    ast: *const Ast,
    typing: *const Typing,
    head: node.ExprId,
    t: types.TypeId,
) ?[]const types.TypeId {
    const args = argsOfType(typing, t) orelse return null;
    const instance = typing.instanceOf(t).?;
    const from = ast.tokenText(ast.declName(instance.decl));
    const written = ast.tokenText(ast.exprMain(head));
    if (!std.mem.eql(u8, written, from)) return null;
    return args;
}

/// Writes one settled declaration under the name it goes by, separated from
/// the last.
///
/// The separator is here rather than at each caller because it is a property
/// of the output and not of what is being written: three loops each deciding
/// when to write a blank line is three chances to disagree about whether the
/// first one needs it.
fn writeMono(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    indexes: *const fmt.Indexes,
    w: *std.Io.Writer,
    d: node.DeclId,
    name: []const u8,
    tokens: []const []const u8,
    receivers: []const node.ExprId,
    wrote_one: *bool,
) !void {
    if (wrote_one.*) try w.writeAll("\n");
    wrote_one.* = true;
    try fmt.formatDecl(gpa, ast, indexes, .{
        .tokens = tokens,
        .receivers = receivers,
        .name = name,
        .type_params = false,
        .type_args = false,
    }, d, w);
}

/// Renders the program with its generics gone: one declaration per
/// instantiation, each concrete.
///
/// Monomorphisation is what the compiler actually does, and `dump-mir` is the
/// only place it shows -- in a different language. This is the same expansion
/// in the one it was written in, which is what makes a queue that will not
/// terminate legible as a function list that will not stop growing.
///
/// The set comes from lowering, which computed it: a declaration nothing
/// reaches is absent here, because after monomorphisation it does not exist.
/// That holds of a type as much as of a function -- a program declaring a type
/// it never holds a value of is a program the emitted code has no such type
/// in.
/// Neither the program nor the resolution is taken. What a written token
/// becomes is settled by the checker and recorded, so a dump that asked which
/// declaration a name reaches would be asking a question already answered --
/// which is how it came to answer differently.
pub fn dumpMono(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    program: *const ExpandedProgram,
    typing: *const Typing,
    module: *const mir.Module,
) !void {
    const ast = &program.ast;
    const tokens = try gpa.alloc([]const u8, ast.tokens.len);
    defer gpa.free(tokens);

    const held = try notes.typesHeld(gpa, module);
    defer gpa.free(held);

    // Reopened so a written type can be substituted through the instantiation
    // being rendered. The pool only grows, so asking it what a body's types
    // became cannot disturb what lowering already decided.
    var pool = try types.Typing.Builder.reopen(gpa, &module.types);
    defer pool.deinit();
    // The pool a lowered module carries is minted from the types alone, so it
    // answers nothing about implementations -- and a settled reference is
    // settled by reading them. Pointed at the checker's, which is where the
    // relation this dump is rendering was decided.
    pool.borrowTables(typing);

    // Once, and read by every item written below. What they hold is the tree,
    // which does not change as a dump walks it.
    var indexes = try fmt.Indexes.build(gpa, ast);
    defer indexes.deinit(gpa);

    var sites = try notes.Constructors.build(gpa, ast);
    defer sites.deinit(gpa);

    // A postfix call is written as the operation it reaches, so its receiver
    // is written inside the parentheses. Which calls those are is what the
    // checker recorded, once for the whole tree.
    const receivers = try gpa.alloc(node.ExprId, ast.exprCount());
    defer gpa.free(receivers);
    @memset(receivers, node.ExprId.none);
    for (typing.postfix) |postfix| {
        if (postfix.args.len > 0) receivers[postfix.call] = postfix.args[0];
    }

    // The types first, because a signature below names them. An instantiation
    // is one type rather than a name and a list, so it is written under a name
    // of its own -- which is the whole claim monomorphisation makes.
    var wrote_one = false;

    // A type taking no parameters has one copy rather than one per
    // instantiation, so nothing in the instance table stands for it -- and a
    // walk of that table alone named such a type in every signature below
    // without ever declaring it. It is given no arguments because it takes
    // none, which is the whole of how it differs from an instantiation.
    for (0..ast.declCount()) |i| {
        const d = node.DeclId.at(@intCast(i));
        switch (ast.declTag(d)) {
            .struct_, .enum_ => {},
            else => continue,
        }
        if (ast.declTypeParams(d).len > 0) continue;

        // Named by what names every reference to it, so the declaration and
        // its uses agree by construction. Its own spelling is not that name:
        // two modules may each declare a `Thing`, and this is the program with
        // nothing standing for anything else.
        const ty = module.types.typeOfDecl(d) orelse continue;
        if (!held[@intFromEnum(ty)]) continue;

        try notes.settle(gpa, ast, &module.types, &pool, .{ .decl = d }, tokens);
        try writeMono(gpa, ast, &indexes, w, d, try module.types.mangledName(gpa, ty), tokens, receivers, &wrote_one);
    }

    for (module.types.instances) |inst| {
        const d = inst.decl;
        const args = module.types.argsOf(inst);
        if (!held[@intFromEnum(inst.ty)]) continue;

        try notes.settle(gpa, ast, &module.types, &pool, .{ .decl = d, .args = args }, tokens);
        try writeMono(gpa, ast, &indexes, w, d, try module.types.mangledName(gpa, inst.ty), tokens, receivers, &wrote_one);
    }

    // Each function by its handle rather than by walking three tables side by
    // side: a parallel `for` asserts the three lengths agree, and that assertion
    // is a safety check, so the build with safety off reads the shortest table
    // past its end. The handle asks each table whether it covers this function,
    // and those checks are written out in the module and survive every build.
    for (0..module.functions.len) |i| {
        const id = mir.FunctionId.at(@intCast(i));
        const origin = module.originOf(id);

        try notes.settle(gpa, ast, &module.types, &pool, origin, tokens);

        // Only a body has these: a call names a callee and an expression
        // builds a value, and a type declaration does neither.
        const from = origin.decl;
        const extent = switch (origin.body) {
            .declaration, .closure_release, .erased_entry, .erased_settle, .built_in, .viewed => ast.declTokens(from),
            .closure => |closure| ast.exprTokens(typing.closureOf(closure).body),
            .constructor => |constructor| ast.exprTokens(constructor.expr),
        };
        try notes.noteCallees(ast, module, module.functionOf(id), tokens, extent);
        try notes.noteConstructors(gpa, ast, typing, &pool, origin, extent, tokens, &sites);

        switch (origin.body) {
            .closure_release, .erased_entry, .erased_settle, .built_in, .viewed => {
                if (wrote_one) try w.writeAll("\n");
                wrote_one = true;
                try w.print("generated MIR function {s}\n", .{module.nameOf(id)});
                const generated = module.functionOf(id);
                for (0..generated.blockCount()) |block| {
                    for (generated.instsOf(.at(@intCast(block)))) |instruction| {
                        if (generated.tagOf(instruction) != .call) continue;
                        const target = generated.callOf(instruction).func;
                        try w.print("callee @f{d} = {s}\n", .{ target.index(), module.nameOf(target) });
                    }
                }
                try @import("../mir/dump.zig").dumpMir(w, module, generated);
            },
            .declaration => try writeMono(gpa, ast, &indexes, w, from, module.nameOf(id), tokens, receivers, &wrote_one),
            .constructor => |constructor| {
                if (wrote_one) try w.writeAll("\n");
                wrote_one = true;
                const value = typing.call_index.functionValueOf(typing, constructor.expr).?;
                const signature_type = try origin.through(&pool, value.signature);
                const signature = pool.get(signature_type).callable;
                const parameter = pool.callableParams(signature)[0];
                try w.print("fn {s}(sink {s}: {s}) -> {s} {{\n    {s}.{s}({s})\n}}\n", .{
                    module.nameOf(id),             parameter.spelling,                                                           pool.nameOf(parameter.ty), pool.nameOf(signature.result),
                    pool.nameOf(signature.result), pool.view().variantName(signature.result, @intFromEnum(constructor.ordinal)), parameter.spelling,
                });
            },
            .closure => |closure| {
                if (wrote_one) try w.writeAll("\n");
                wrote_one = true;
                const descriptor = typing.closureOf(closure);
                // The symbol lowering gave the instance, which every call of
                // it in the dump also reads.
                const body_name = module.nameOf(id);
                const signature_type = try origin.through(&pool, descriptor.signature);
                const signature = pool.get(signature_type).callable;
                const params = pool.callableParams(signature);
                const param_types = try gpa.alloc([]const u8, params.len);
                defer gpa.free(param_types);
                for (params, param_types) |param, *name| name.* = pool.nameOf(param.ty);
                const param_defaults = try gpa.alloc(?[]const u8, params.len);
                @memset(param_defaults, null);
                defer {
                    for (param_defaults) |default| if (default) |text| gpa.free(text);
                    gpa.free(param_defaults);
                }
                for (params, param_defaults) |param, *default| switch (param.default) {
                    .absent => {},
                    .value => |value| default.* = try value.text(gpa, pool.constant_pool),
                };
                // The body names its parameters as the lambda does: a
                // parameter's name is not part of the signature's type.
                const written = ast.lambda(descriptor.expr).params;
                const param_names = try gpa.alloc([]const u8, params.len);
                defer gpa.free(param_names);
                for (param_names, 0..) |*spelled, at| spelled.* = if (at < written.len) ast.paramSpelling(written[at]) else "_";
                try fmt.formatClosure(
                    gpa,
                    ast,
                    &indexes,
                    .{ .tokens = tokens, .receivers = receivers },
                    descriptor.body,
                    body_name,
                    params,
                    param_names,
                    param_types,
                    param_defaults,
                    pool.nameOf(signature.result),
                    w,
                );
            },
        }
    }
}

/// The checked type of a constant initializer, without reconstructing its
/// annotation or following aliases again. Invalid declarations have no hint.
pub fn constantType(ast: *const Ast, typing: *const Typing, declaration: node.DeclId) ?types.TypeId {
    if (ast.declTag(declaration) != .constant) return null;
    const initializer = ast.declInit(declaration);
    if (initializer == .none) return null;
    const ty = typing.exprType(initializer);
    return if (ty == .poison) null else ty;
}

/// What the checker settled each `let` in `from..to` to, and the empty string
/// where the source wrote the type itself.
///
/// One routine, because two things ask it at different times: a dump renders
/// the whole program with the answers written in, and a language server shows
/// one file's as hints. A second walk would agree about every binding anyone
/// wrote down and disagree about one nobody did -- and this walk has two
/// places where that is easy, since "was a type written" is not "does the
/// written type have a name", and an initialiser the parser could not read is
/// no expression to ask the type of.
///
/// The range is what the caller is asking about, so the answer costs that and
/// not the program: the dump asks for the whole module and a server asks for
/// one file's run of it, on every keystroke and every scroll. Entry `i` of the
/// result is statement `from + i`.
pub fn bindingTypes(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    typing: *const Typing,
    from: u32,
    to: u32,
) ![][]const u8 {
    const bindings = try gpa.alloc([]const u8, to - from);
    errdefer gpa.free(bindings);
    @memset(bindings, "");

    for (from..to) |i| {
        const id = node.StmtId.at(@intCast(i));
        if (ast.stmtTag(id) != .let_decl) continue;
        const d = ast.stmtData(id);
        // Asked of the written type rather than of its name, which an array
        // leaves absent: `let xs: [UInt8; 2]` is annotated, and a reader
        // looking for a name would decide it is not.
        if (d.annotation.wasWritten()) continue;
        // A binding whose initialiser the parser could not read has no
        // expression to take a type from. The dump is only ever asked about a
        // program that checked; a server is asked about every keystroke on the
        // way to one.
        if (d.init == node.ExprId.none) continue;
        // An unsettled binding is left unhinted, as hover and completion leave
        // it: its type is what stands in for an expression already reported.
        const binding = res.bindingOf(id);
        if (binding == BindingId.none) continue;
        bindings[i - from] = typing.settledName(typing.bindingType(binding)) orelse continue;
    }

    return bindings;
}

/// Renders the program as Linea with what the checker settled written in.
///
/// A reading rather than a source file: a call's type arguments have no syntax
/// to be written in, so the output does not parse back. That is the point --
/// the questions this answers are the ones the source cannot be read for, and
/// which instantiation a call reached is the first of them.
pub fn dumpInferred(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    ast: *const Ast,
    res: *const Resolution,
    typing: *const Typing,
    selection: DeclarationSelection,
) !void {
    // The whole module, which is what `fmt.Notes.bindings` is keyed by: this
    // renders every declaration the program wrote.
    const bindings = try bindingTypes(gpa, ast, res, typing, 0, ast.stmtCount());
    defer gpa.free(bindings);

    var owned_names: std.ArrayList([]const u8) = .empty;
    defer {
        for (owned_names.items) |name| gpa.free(name);
        owned_names.deinit(gpa);
    }
    for (0..ast.stmtCount()) |i| {
        if (bindings[i].len == 0) continue;
        const stmt = node.StmtId.at(@intCast(i));
        const init = ast.stmtData(stmt).init;
        if (init == node.ExprId.none) continue;
        const ty = typing.exprType(init);
        switch (typing.get(ty)) {
            .closure => {},
            else => continue,
        }
        const name = try notes.closureTypeName(gpa, typing, ty);
        try owned_names.append(gpa, name);
        bindings[i] = name;
    }

    const exprs = try gpa.alloc([]const u8, ast.exprCount());
    defer gpa.free(exprs);
    @memset(exprs, "");

    // Source expressions read the same frozen index as ownership and lowering.
    const calls = &typing.call_index;

    for (0..ast.exprCount()) |i| {
        const id = node.ExprId.at(@intCast(i));
        switch (ast.exprTag(id)) {
            .struct_literal => if (ast.structLiteralHead(id) == null) {
                exprs[i] = typing.nameOf(typing.expr_types[i]);
            },

            // Two questions in two places, asked separately because a call can
            // answer both: what settled the callee's own type parameters sits
            // on the call, and what settled `Self` sits on the type or trait
            // heading its path. An operation declaring parameters of its own
            // and reached through a trait has each, and offering them as
            // alternatives left the second unwritten exactly there.
            .call => {
                // Type arguments the call names in its brackets are already
                // written in the source.
                if (calls.callOf(typing, id)) |call| {
                    if (call.selection.own_args.len > 0 and !call.written_type_arguments) {
                        exprs[i] = try spellArgs(gpa, typing, call.selection.own_args);
                    }
                }
                if (notes.headOfPath(ast, ast.call(id).callee)) |head| {
                    // A call through a trait settles `Self`, and the trait is
                    // what heads its path -- so what it settled is written
                    // there, where an instantiation's arguments are. Without
                    // it the call is the tokens it was written with, and which
                    // implementation it runs is the question this dump exists
                    // to answer.
                    //
                    // A type parameter where the call is inside a generic body,
                    // which is the answer rather than a missing one: `Self` is
                    // whatever settles the parameter, and the body is checked
                    // once for all of them.
                    const implementation = if (calls.callOf(typing, id)) |call|
                        call.selection.implementation
                    else
                        null;
                    if (implementation) |held| {
                        exprs[head.index()] = try spellArgs(gpa, typing, &.{held.self_ty});
                    } else if (instanceHeaded(ast, typing, head, typing.expr_types[i])) |args| {
                        // A constructor, not a call through a type.
                        // `Option.Some` builds an `Option` and `Account.open`
                        // builds whatever it returns, so the head is only the
                        // instantiation's when it names the declaration the
                        // instantiation came from.
                        exprs[head.index()] = try spellArgs(gpa, typing, args);
                    }
                }
            },

            // `Option[u8].None`, which carries nothing and so is no call.
            .field => {
                if (notes.headOfPath(ast, id)) |head| {
                    if (instanceHeaded(ast, typing, head, typing.expr_types[i])) |args| {
                        exprs[head.index()] = try spellArgs(gpa, typing, args);
                    }
                }
            },
            else => {},
        }
    }

    // An inferred array length is written as the count the checker settled,
    // so `[Point; _]` reads as the type the binding has.
    const tokens = try gpa.alloc([]const u8, ast.tokenCount());
    defer gpa.free(tokens);
    @memset(tokens, "");
    for (0..ast.stmtCount()) |i| {
        const stmt = node.StmtId.at(@intCast(i));
        if (ast.stmtTag(stmt) != .let_decl) continue;
        const d = ast.stmtData(stmt);
        if (!d.annotation.wasWritten() or d.init == node.ExprId.none) continue;
        try noteInferredLengths(gpa, ast, typing, d.annotation, typing.exprType(d.init), tokens, &owned_names);
    }
    for (0..ast.declCount()) |i| {
        const decl = node.DeclId.at(@intCast(i));
        if (ast.declTag(decl) != .constant) continue;
        const initializer = ast.declInit(decl);
        if (!ast.declReturnRef(decl).wasWritten() or initializer == node.ExprId.none) continue;
        try noteInferredLengths(gpa, ast, typing, ast.declReturnRef(decl), typing.exprType(initializer), tokens, &owned_names);
    }

    try fmt.formatNoted(gpa, ast, .{ .bindings = bindings, .exprs = exprs, .tokens = tokens }, selection, w);
}

/// Notes the count each `_` in a written array type settled to, reading the
/// written type and the settled one level by level.
fn noteInferredLengths(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    typing: *const Typing,
    written: node.TypeRef,
    settled: types.TypeId,
    tokens: [][]const u8,
    owned: *std.ArrayList([]const u8),
) !void {
    const ref = ast.withoutTypeGroups(written);
    if (ref.kind != .array) return;
    const array = switch (typing.get(settled)) {
        .array => |a| a,
        else => return,
    };
    if (ref.inferred_length != .none) {
        const count = try std.fmt.allocPrint(gpa, "{d}", .{array.count});
        try owned.append(gpa, count);
        tokens[ref.inferred_length.index()] = count;
    }
    const elements = ast.typeArgs(ref.args);
    if (elements.len != 0) try noteInferredLengths(gpa, ast, typing, elements[0], array.element, tokens, owned);
}
