const std = @import("std");
const testing = std.testing;

const Source = @import("../support/source.zig").Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const resolveTree = @import("../sema/resolve.zig").resolveTree;
const typecheck = @import("../sema/typecheck.zig").typecheck;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;
const lowerProgram = @import("../mir/lower.zig").lowerProgram;
const Expr = @import("../syntax/node.zig").Expr;
const node = @import("../syntax/node.zig");
const Decl = node.Decl;
const Ast = @import("../syntax/ast.zig").Ast;
const TokenId = @import("../lexer/token.zig").TokenId;
const types_mod = @import("../sema/types.zig");
const Typing = types_mod.Typing;
const TypeId = types_mod.TypeId;
const Inst = @import("../mir/mir.zig").Inst;
const generate = @import("generate.zig");
const loader = @import("../driver/loader.zig");
const Head = @import("../sema/resolve.zig").Head;
const accessGranted = @import("../sema/typecheck.zig").accessGranted;

/// Whether the generator reaches a construct, and why where it does not.
///
/// The corpus covers what someone thought to write down. The generator covers
/// what it was taught, and forgetting to teach it is silent: every property
/// built on generated programs keeps passing, over a language that quietly
/// stopped being the whole language.
///
/// So the two tables below are claims, and the tests check them against a real
/// run rather than against themselves. A tag added anywhere has to be
/// classified before the build succeeds, and a claim that stops being true
/// fails whichever way it moved.
pub const Reach = union(enum) {
    /// The generator produces it. Held to it: if it stops, that is the failure.
    generated,
    /// Nothing here could produce it, and the reason is a property of the
    /// generator or of lowering rather than an omission.
    impossible: []const u8,
    /// The generator does not produce it yet, named by what would close it.
    /// Listed rather than left out, because a gap nobody wrote down is a gap
    /// nobody closes -- and if the generator gains it, this stops being true
    /// and says so.
    ///
    missing: []const u8,
};

/// Which syntactic constructs a generated program contains.
///
/// An exhaustive switch, so a new node kind is a compile error here before it
/// is a hole in the corpus.
pub fn reachOfExpr(tag: Expr.Tag) Reach {
    return switch (tag) {
        .borrow, .dereference => .generated,
        .not,
        .logical_and,
        .logical_or,

        .block,
        .conditional,
        .while_,
        .assign,
        .add_assign,
        .sub_assign,
        .mul_assign,
        .div_assign,
        .rem_assign,
        .variant_ref,
        .struct_literal,
        // Reached through `Colour.Red`, which is a selection like any other.
        // That a struct's field is read by the same node means this says less
        // than it looks like: what it holds is that selections are generated,
        // and `struct_literal` is what says structures are.
        .field,
        .match_,
        .call,
        .int_literal,
        .bool_literal,
        // The tail of the generated `_nothing`, a function answering `()`.
        .unit_literal,
        .name_ref,
        .grouped,
        .negate,
        .marked,
        .loop_,
        .break_,
        .continue_,
        .return_,
        // Both forms of match. The lending one is written over the linear
        // type, which is the only place a program has a reason to observe a
        // value rather than take it apart.
        .match_read,
        // A destructuring `let`, which is the terminal consumer of a
        // structure: what it held becomes bindings of its own.
        .struct_pattern,
        // Aggregate field copies and symbolic generic copies retain explicit
        // duplication coverage; concrete scalar fields use snapshot reads.
        .copy_,
        .add,
        .sub,
        .mul,
        .div,
        .rem,
        .eq,
        .ne,
        .lt,
        .le,
        .gt,
        .ge,
        => .generated,

        // `Option` and `Result` are the library's own declarations, and the
        // generator writes none of them. Declaring one is no
        // route either: what `?` works over is settled nominally against the
        // prelude's two, so an enum of the same shape carrying the same
        // alternative names is refused by [T-Try] like any other type.
        .try_ => .{ .impossible = "the generator writes no library declaration, and [T-Try] admits the prelude's `Option` and `Result` and no lookalike" },
        .unwrap_else => .{ .impossible = "the generator writes no library declaration, and [T-LetElse] admits the prelude's `Option` and `Result` and no lookalike" },

        // One node kind for two positions: a covering match's arms are range
        // *patterns*, which this tag also names, and reach a generated
        // program that names no library declaration -- a pattern's bound is checked the
        // way a literal arm's is, asking nothing of the prelude. A range as a
        // *value* still would: it is a construction of `Range[T]`, identified
        // through the prelude the way `Option` and `Result` are, and nothing
        // this generator writes can name that declaration -- the same reason
        // `.str_literal` and `.interp` stay out of reach below. What is
        // generated is the pattern; the tag does not distinguish.
        .range => .generated,
        .float_literal => .generated,
        .str_literal => .{ .impossible = "the generator names no library declaration, so it cannot name `Str`" },
        .embed, .embed_bytes => .{ .impossible = "the generator writes a program and no file beside it, so nothing it writes can embed one" },
        .panic => .{ .impossible = "the generator names no library declaration, so it cannot type a panic message as `Str`" },
        // For the same reason, and one more: what an interpolation renders is
        // reached through `Display`, which the library declares.
        .interp => .{ .impossible = "the generator names no library declaration, so it cannot name `Str` or `Display`" },
        .array_literal, .index => .generated,
        .lambda => .generated,

        // A count back from an end is a value of the library's `FromEnd`, and
        // the generator names no library declaration -- the same reason
        // `.str_literal` and `.range` as a value stay out of reach.
        .from_end => .{ .impossible = "the generator names no library declaration, so it cannot name `FromEnd`" },

        // A pair literal, and the pattern that takes one apart. A tuple's type
        // is the library's `Tuple2`, so a generated program is loaded beside
        // the library and checked as the command line checks one.
        .tuple_literal, .tuple_pattern => .generated,

        // The argument a lambda's tuple-pattern parameter stands for. It is
        // written nowhere, and the generator writes no lambda with a pattern
        // parameter.
        .param_argument => .{ .impossible = "the generator writes every lambda parameter as a name, so none stands for a pattern" },

        // All three walks, over an array. What a walk yields there is settled
        // by the type -- the places are the language's own, and so are the
        // positions the lending forms run through -- so none of the three asks
        // anything of a library. A walk over anything else does: a `Sequence`
        // vends the iterator a consuming walk drives, and a `trav` is bound to
        // an `Iterator`, and both are declarations the prelude carries. So what
        // is generated is the walk over the one head that needs no prelude, and
        // a walk over a range stays out of reach for the reason a range as a
        // value does.
        .for_, .for_read, .for_inout => .generated,

        .reflection_root => .generated,

        // A generator of well-typed programs has nothing to build one from:
        // an error node is what the parser leaves where it could not read the
        // source, and every program here is written by the generator itself.
        .err => .{ .impossible = "the generator writes only programs that parse" },
    };
}

/// Which declaration forms a generated program contains.
///
/// The third axis, and the one modules made necessary: a form can be absent
/// because nothing generates it rather than because nothing uses it, and the
/// two look identical from a green run.
pub fn reachOfDecl(tag: Decl.Tag) Reach {
    return switch (tag) {
        .function, .enum_, .struct_ => .generated,

        // What a type can do. A generated function is sometimes written about
        // a type rather than beside it, which changes where it is declared and
        // how a call reaches it and nothing else -- an `impl` is a namespace
        // and not a scope.
        .impl_ => .generated,

        .template_impl, .derive_impl => .generated,

        // The generator writes one module, so there is nothing to import and
        // no second directory for a path to name. Closing this means teaching
        // it to emit a directory tree, which is a change to what a generated
        // program *is* rather than to what it contains.
        .import_ => .{ .impossible = "the generator writes one module" },

        // A re-export needs a module to re-export from, so it needs the same
        // second directory an import does.
        .use_ => .{ .impossible = "the generator writes one module" },

        // A name bound to a value, worked out where it is declared because
        // nothing runs there. Generated as a pair with the second naming the
        // first, so a constant expression that reaches through a name is
        // written as well as one that is a literal, and the entry reads both
        // -- a constant nothing names is a declaration and not a value.
        .constant => .generated,

        // A set of operations a type satisfies. Generated with two
        // implementations and a function written against the bound, so a call
        // through it is monomorphised into two and each must reach its own
        // body -- one implementation would exercise the machinery without
        // saying which body it picked.
        .trait_ => .generated,

        // A type a trait declares and its implementations settle. Generated
        // with the trait: each implementation settles it its own way, a
        // signature answers `Self.Item`, and a function written against the
        // bound answers `T.Item` -- so every instantiation is settled by its
        // own argument, and one settled by another's does not check.
        .associated_type => .generated,

        // A member that yields a place: a type with an indexable field, a
        // trait of the program's own declaring the member, and an
        // implementation whose body is the path into that field. A projection
        // is refused in an inherent `impl`, so the trait is what makes the
        // declaration writable at all.
        //
        // Declared and not spliced, and the difference is the prelude. Which
        // projection a bracket reaches is settled through `Index`, which the
        // generator does not name -- so what a generated
        // program exercises is the declaration and every rule about its shape,
        // and what a bracket over such a type expands into is reached by the
        // written cases. A generated program does write brackets, and every one
        // of them is over an array, whose row the compiler provides and whose
        // bracket is settled without expanding anything.
        .projection => .generated,

        // The positions a lending walk runs through. Out of reach for the
        // reason a projection is and one more: what it is bound to is an
        // iterator, and an iterator is `Iterator`, which the library declares.
        .traversal_ => .{ .impossible = "the generator names no library declaration, so it cannot name `Iterator`" },

        // A distinct nominal type over one base. Declared refined, over
        // `UInt8`, with a literal proven at every construction and both
        // destructuring forms reached -- kept out of the general type
        // selection the way the linear type is, since its representation is
        // its base's and nothing about it is chosen the way an enum or a
        // structure is.
        .newtype => .generated,

        // Another name for a type, declared beside the newtype and written
        // where one of its values is passed.
        .alias => .generated,

        .err => .{ .impossible = "the generator writes only programs that parse" },
    };
}

/// Records what every declared type in a program holds.
///
/// Read from the type pool rather than the tree, because what a payload *is*
/// is a question about types -- the syntax for carrying a structure and for
/// carrying an enum is the same syntax.
/// What a type was instantiated at, or null where it is not an instantiation.
fn instantiationOf(typing: *const Typing, t: TypeId) ?[]const TypeId {
    return typing.argsOf(typing.instanceOf(t) orelse return null);
}

fn noteNestings(typing: *const Typing, seen: *Seen) void {
    for (0..typing.pool.len) |i| {
        const t: TypeId = @enumFromInt(@as(u32, @intCast(i)));
        switch (typing.get(t)) {
            .struct_ => {
                var only_scalars = true;
                for (0..typing.fieldCount(t)) |f| {
                    switch (typing.get(typing.fieldType(t, @intCast(f)))) {
                        .struct_ => {
                            seen.nestings.insert(.struct_in_struct);
                            only_scalars = false;
                        },
                        .enum_ => {
                            seen.nestings.insert(.enum_in_struct);
                            only_scalars = false;
                        },
                        else => {},
                    }
                    if (instantiationOf(typing, typing.fieldType(t, @intCast(f))) != null) {
                        seen.nestings.insert(.generic_in_struct);
                        only_scalars = false;
                    }
                }
                if (instantiationOf(typing, t)) |args| {
                    // An instantiation is an ordinary structure in the pool,
                    // which is the point -- nothing downstream has a case for
                    // one. So what it was instantiated at is asked of the
                    // table that recorded it rather than of the type.
                    var linear = false;
                    for (args) |a| {
                        if (typing.mustConsume(a)) linear = true;
                    }
                    seen.nestings.insert(if (linear) .generic_of_linear else .generic_of_free);
                } else if (only_scalars) seen.nestings.insert(.struct_of_scalars);
            },
            .enum_ => {
                var carries = false;
                for (0..typing.variantCount(t)) |v| {
                    for (0..typing.variantFieldCount(t, @intCast(v))) |f| {
                        carries = true;
                        switch (typing.get(typing.variantFieldType(t, @intCast(v), @intCast(f)))) {
                            .struct_ => seen.nestings.insert(.struct_in_enum),
                            .enum_ => seen.nestings.insert(.enum_in_enum),
                            else => seen.nestings.insert(.scalar_in_enum),
                        }
                    }
                }
                if (!carries) seen.nestings.insert(.enum_of_tags);
            },
            else => {},
        }
    }
}

/// What a type holds, as a pair of shapes.
///
/// The axis the others could not have: a tag axis says every construct appears
/// somewhere, and says nothing about two of them appearing *together*. A
/// structure used as a variant's payload is exactly that -- `struct_literal`
/// and `field` were both generated and the combination never was, and a
/// lowering that stored the payload's address rather than its bytes sat
/// unnoticed behind two green ticks.
pub const Nesting = enum {
    /// A structure whose fields are all scalars.
    struct_of_scalars,
    /// A structure holding another structure.
    struct_in_struct,
    /// A structure holding an enum.
    enum_in_struct,
    /// An enum whose variants carry nothing.
    enum_of_tags,
    /// An enum carrying scalars.
    scalar_in_enum,
    /// An enum carrying a structure. What the payload bug lived in.
    struct_in_enum,
    /// An enum carrying an enum.
    enum_in_enum,
    /// An instantiation at an argument that owes nothing.
    generic_of_free,
    /// An instantiation at a Linear argument, which is the shape the universe
    /// is computed for: the same declaration owes something here and nothing
    /// above, and neither is written down.
    generic_of_linear,
    /// A structure holding an instantiation, so substitution has to have
    /// happened before a layout can be taken.
    generic_in_struct,
};

pub fn reachOfNesting(tag: Nesting) Reach {
    return switch (tag) {
        .struct_of_scalars,
        .struct_in_struct,
        .enum_of_tags,
        .scalar_in_enum,
        .struct_in_enum,
        .enum_in_enum,
        .enum_in_struct,
        .generic_of_free,
        .generic_of_linear,
        .generic_in_struct,
        => .generated,

        // Each is a shape the generator can already describe -- it writes
        // structures and it writes enums, and nothing stops it putting one
        // inside the other. It does not, and a lowering that handled a payload
        // of one width and not another sat behind two green ticks because both
        // constructs appeared, separately.
    };
}

/// What a generated program writes in a position no tag names: how a call
/// spells the arguments it passes, how a parameter is declared, and what an
/// implementation applies its head to.
///
/// The fifth axis, and the one named arguments made necessary: a name written
/// before an argument and a default written after a parameter's type are both
/// fields on nodes that already existed, so `call` and `function` were called
/// generated throughout while neither field had ever been written. Nothing on
/// a tag axis could have said so, and an implementation's own parameters are
/// the same shape of omission on `impl_`.
pub const Spelling = enum {
    /// An argument filling the parameter its position reaches.
    positional_argument,
    /// An argument saying which parameter it fills.
    named_argument,
    /// A name written before a place the callee writes back through. The
    /// combination rather than either half: a name says which parameter takes
    /// the value and a convention says what the callee does with it, and a
    /// pass reading one off the other is wrong only where both appear.
    named_marked_argument,
    /// A parameter carrying a default a call may omit.
    declared_default,
    /// A call that omitted one, which is what puts a hole in the list every
    /// pass below reads.
    omitted_default,
    /// An implementation declaring type parameters of its own, with a head
    /// that applies them. The pair rather than either half: the parameters are
    /// a run and the head's arguments are a field, both on a node whose tag
    /// was already generated, and neither says on its own that a family was
    /// written.
    generic_head,
    /// A structure literal that writes some of its fields and takes the rest
    /// from a base, `.{ f0 = v, ..base }`. A field on a node whose tag was
    /// already generated, so no tag axis could say it was ever written.
    struct_update,
};

pub fn reachOfSpelling(tag: Spelling) Reach {
    return switch (tag) {
        .positional_argument,
        .named_argument,
        .named_marked_argument,
        .declared_default,
        .omitted_default,
        .generic_head,
        .struct_update,
        => .generated,
    };
}

/// What each generated call and parameter list spells.
///
/// The names come off the tree and the omissions come off what the checker
/// matched: a hole in the declaration-ordered list is what says a call left a
/// parameter out, and counting arguments against parameters here would be a
/// second matcher answering a question the checker already answered.
fn noteSpellings(ast: *const Ast, typing: *const Typing, seen: *Seen) void {
    for (0..ast.exprCount()) |i| {
        const id: node.ExprId = @enumFromInt(@as(u32, @intCast(i)));
        if (ast.exprTag(id) == .struct_literal and ast.structLiteralBase(id) != null) seen.spellings.insert(.struct_update);
        // A call and none of the six other tags sharing its payload: a name is
        // a fact about a call's own syntax, and the others hold runs of their
        // own that no argument spells. The tag says which it is.
        if (!ast.exprTag(id).namesArguments()) continue;
        for (ast.callNames(id), ast.call(id).args) |n, a| {
            if (n == TokenId.none) {
                seen.spellings.insert(.positional_argument);
                continue;
            }
            seen.spellings.insert(.named_argument);
            if (ast.exprTag(a) == .marked) seen.spellings.insert(.named_marked_argument);
        }
    }

    for (0..ast.declCount()) |i| {
        const d: node.DeclId = @enumFromInt(@as(u32, @intCast(i)));
        for (ast.declParams(d)) |p| {
            if (p.default != node.ExprId.none) seen.spellings.insert(.declared_default);
        }
        if (ast.declTag(d) == .impl_ and
            ast.declTypeParams(d).len != 0 and
            ast.declHead(d).args.len() != 0)
        {
            seen.spellings.insert(.generic_head);
        }
    }

    for (typing.calls) |call| {
        for (call.args) |a| {
            if (a == node.ExprId.none) seen.spellings.insert(.omitted_default);
        }
    }
}

/// Which parameter conventions a generated program uses.
///
/// A fourth axis, and the one ownership made necessary: a convention is not a
/// node and not an instruction, so neither of the others could have said that
/// nothing generated ever writes one.
pub fn reachOfConvention(tag: node.Convention) Reach {
    return switch (tag) {
        .read, .inout => .generated,

        // How a linear value is finally disposed of, which is the only thing
        // that discharges the obligation one carries.
        .sink => .generated,
    };
}

const TypeTag = std.meta.Tag(types_mod.Type);

/// Which semantic type variants a generated program reaches.
pub fn reachOfType(tag: TypeTag) Reach {
    return switch (tag) {
        .borrow => .generated,
        .integer,
        .boolean,
        .float,
        .unit,
        .parameter,
        .enum_,
        .struct_,
        .newtype,
        .array,
        .callable,
        .closure,
        .never,
        => .generated,
        .poison => .{ .impossible = "generated programs are well typed by construction" },
        .open_integer => .{ .impossible = "an open integer is settled before checking finishes" },
        .open_type => .{ .impossible = "an open type is settled before checking finishes" },
    };
}

/// Which instructions lowering a generated program produces.
///
/// The second axis, and the one that catches a feature with no syntax of its
/// own: a payload is spelled with the call and variant nodes that already
/// existed, so nothing about the tree changed when it arrived -- but two
/// instructions did.
pub fn reachOfInst(tag: Inst.Tag) Reach {
    return switch (tag) {
        .borrow, .observe => .generated,
        // A generated program borrows one of its module constants.
        .static_addr => .generated,
        // Emitted only by a string literal, whose type is the library's. The
        // generator names no library declaration, so it cannot write `Str`.
        .bytes_addr => .{ .impossible = "the generator names no library declaration, so it cannot name `Str`" },
        .address_bits => .{ .impossible = "the generator names no library declaration, so it cannot construct a checked array view" },
        .load_raw, .store_raw, .storage_addr => .{ .impossible = "the generator names no library declaration, so it cannot name private storage operations" },
        .constant,
        .load,
        .store,
        .addr_of,
        .load_indirect,
        .store_indirect,
        .field_addr,
        .copy_value,
        .move_value,
        .add,
        .sub,
        .mul,
        .div,
        .rem,
        .cmp_eq,
        .cmp_ne,
        .cmp_lt,
        .cmp_le,
        .cmp_gt,
        .cmp_ge,
        .check,
        .call,
        .neg,
        .ret,
        .jump,
        .branch,
        .trap,
        => .generated,

        .int_to_float, .float_to_int => .generated,
        .float_math => .{ .impossible = "generated programs declare no trusted scalar math primitives" },

        .function_addr, .call_indirect => .generated,
        .foreign_function_addr => .{ .impossible = "generated programs declare no `extern`, so they pass C no callback" },

        // The generator has no uninhabited expression with which to call a
        // Never-returning function, directly or through a code pointer.
        .call_noreturn, .call_indirect_noreturn => .{
            .impossible = "generated programs produce no Never-returning callable",
        },
    };
}

/// Which statement kinds a generated program contains.
///
/// An exhaustive switch, so a statement kind added anywhere is classified here
/// before the build succeeds. That matters more for statements than it looks:
/// only three passes switch exhaustively over one, and the three that decide
/// meaning -- the resolver, the checker and lowering -- did not, so a kind they
/// ignored compiled and did nothing. This is what makes the next one visible.
pub fn reachOfStmt(tag: node.Stmt.Tag) Reach {
    return switch (tag) {
        .let_decl, .let_destructure, .let_read_destructure, .expr_stmt => .generated,
        .defer_stmt, .defer_release => .generated,
        // A generator of well-typed programs has nothing to build one from.
        .err => .{ .impossible = "the generator writes only programs that parse" },
    };
}

const Seen = struct {
    exprs: std.EnumSet(Expr.Tag),
    stmts: std.EnumSet(node.Stmt.Tag),
    decls: std.EnumSet(Decl.Tag),
    conventions: std.EnumSet(node.Convention),
    types: std.EnumSet(TypeTag),
    nestings: std.EnumSet(Nesting),
    spellings: std.EnumSet(Spelling),
    insts: std.EnumSet(Inst.Tag),
};

/// What a run of the generator reaches, across every axis at once so the whole
/// pipeline runs once per program rather than once per axis.
fn sweep(backing: std.mem.Allocator, seeds: usize) !Seen {
    var seen: Seen = .{
        .exprs = .initEmpty(),
        .stmts = .initEmpty(),
        .decls = .initEmpty(),
        .conventions = .initEmpty(),
        .types = .initEmpty(),
        .nestings = .initEmpty(),
        .spellings = .initEmpty(),
        .insts = .initEmpty(),
    };

    const library = try loader.CheckedLibrary.init(backing);
    defer library.deinit();
    for (0..seeds) |seed| {
        // One program's compilation is released before the next is built; the
        // checked library beside it is large enough that holding four hundred
        // of them exhausts memory.
        var arena = std.heap.ArenaAllocator.init(backing);
        defer arena.deinit();
        const gpa = arena.allocator();
        const bytes = try generate.choicesFromSeed(gpa, seed, 64);
        const text = try generate.generate(gpa, bytes, .{});

        const source: Source = .{ .path = "generated.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var res = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &res, &sink);

        for (0..ast.exprCount()) |i| {
            seen.exprs.insert(ast.exprTag(@enumFromInt(@as(u32, @intCast(i)))));
        }
        for (0..ast.stmtCount()) |i| {
            seen.stmts.insert(ast.stmtTag(@enumFromInt(@as(u32, @intCast(i)))));
        }
        for (0..ast.declCount()) |i| {
            const d: node.DeclId = @enumFromInt(@as(u32, @intCast(i)));
            seen.decls.insert(ast.declTag(d));
            for (ast.declParams(d)) |p| seen.conventions.insert(p.convention);
        }
        noteNestings(&typing, &seen);
        for (typing.expr_types) |ty| {
            if (ty != .poison) seen.types.insert(std.meta.activeTag(typing.pool[ty.index()]));
        }
        var binding_types = typing.binding_types.pairs();
        while (binding_types.next()) |pair| {
            if (pair.value != .poison) {
                seen.types.insert(std.meta.activeTag(typing.pool[pair.value.index()]));
            }
        }
        noteSpellings(&ast, &typing, &seen);

        // Lowered from the program loaded beside the library, because a tuple's
        // type is the library's. The tree above is of the program's own text,
        // which is what the tags and types are read from.
        // Every generated program is accepted: the property the generator
        // exists for, since a program the checker refuses tests its error
        // paths and nothing past them.
        const loaded = try generate.checkAccepted(gpa, library, text);
        const semantics = &loaded.semantics;
        var module = (try lowerProgram(gpa, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, &loaded.sink, .program)) orelse return error.SourceRejected;
        defer module.deinit(gpa);
        for (module.functions) |f| {
            for (f.insts.items(.tag)) |t| seen.insts.insert(t);
        }
    }
    return seen;
}

/// Holds one axis to its table, in both directions.
fn hold(
    comptime Tag: type,
    reachOf: fn (Tag) Reach,
    seen: std.EnumSet(Tag),
    axis: []const u8,
) !void {
    var failed = false;
    for (std.enums.values(Tag)) |tag| {
        const present = seen.contains(tag);
        switch (reachOf(tag)) {
            .generated => if (!present) {
                std.debug.print(
                    "{s}: `{s}` is called generated and no generated program has one\n",
                    .{ axis, @tagName(tag) },
                );
                failed = true;
            },
            // A claim that has stopped being true. The generator gained it,
            // which is good news the table has to be told about, or the next
            // gap hides behind a note that is already wrong.
            .impossible => |why| if (present) {
                std.debug.print(
                    "{s}: `{s}` is produced, and the table calls it impossible -- \"{s}\"\n",
                    .{ axis, @tagName(tag), why },
                );
                failed = true;
            },
            .missing => |why| if (present) {
                std.debug.print(
                    "{s}: `{s}` is produced, and the table still waits on {s}\n",
                    .{ axis, @tagName(tag), why },
                );
                failed = true;
            },
        }
    }
    if (failed) return error.CoverageTableIsWrong;
}

test "every construct the table calls generated is generated" {
    const seen = try sweep(testing.allocator, 400);
    try hold(Expr.Tag, reachOfExpr, seen.exprs, "syntax");
    try hold(node.Stmt.Tag, reachOfStmt, seen.stmts, "statements");
    try hold(Decl.Tag, reachOfDecl, seen.decls, "declarations");
    try hold(node.Convention, reachOfConvention, seen.conventions, "conventions");
    try hold(TypeTag, reachOfType, seen.types, "semantic types");
    try hold(Nesting, reachOfNesting, seen.nestings, "nesting");
    try hold(Spelling, reachOfSpelling, seen.spellings, "spellings");
    try hold(Inst.Tag, reachOfInst, seen.insts, "instructions");
}

test "every construct is classified" {
    // The switches are exhaustive, so this fails to compile rather than fails
    // to run when a tag is added without an answer. Reaching it at all is the
    // assertion; what it returns is checked above.
    for (std.enums.values(Expr.Tag)) |t| _ = reachOfExpr(t);
    for (std.enums.values(node.Stmt.Tag)) |t| _ = reachOfStmt(t);
    for (std.enums.values(Decl.Tag)) |t| _ = reachOfDecl(t);
    for (std.enums.values(node.Convention)) |t| _ = reachOfConvention(t);
    for (std.enums.values(TypeTag)) |t| _ = reachOfType(t);
    for (std.enums.values(Nesting)) |t| _ = reachOfNesting(t);
    for (std.enums.values(Spelling)) |t| _ = reachOfSpelling(t);
    for (std.enums.values(Inst.Tag)) |t| _ = reachOfInst(t);
}

test "callable source and MIR forms are generated" {
    try testing.expectEqual(Reach.generated, reachOfExpr(.lambda));
    try testing.expectEqual(Reach.generated, reachOfInst(.function_addr));
    try testing.expectEqual(Reach.generated, reachOfInst(.call_indirect));
}

test "borrow source and MIR forms are generated" {
    const seen = try sweep(testing.allocator, 1);
    try testing.expect(seen.exprs.contains(.borrow));
    try testing.expect(seen.exprs.contains(.dereference));
    try testing.expect(seen.types.contains(.borrow));
    try testing.expect(seen.insts.contains(.borrow));
    try testing.expect(seen.insts.contains(.observe));
}

test "an allocation is generated by nothing" {
    // A gap with no tag to sit on: allocation is reached through calls to
    // `Buffer`, which the library declares, and the generator names no
    // library declaration -- so no generated program allocates.
    // Deliberately: generated programs are well-typed by construction and
    // would leak by construction, and a generator that balances an
    // allocation against a disposal is what would close this.
    //
    // What is watched is `.str_literal`'s classification and nothing more --
    // allocation is plain calls, and no tag of its own can be watched. The
    // entry flips when generated programs contain a `Str` literal, which a
    // generator handed the library would produce; one taught the `mem`
    // module alone, or an allocation form of its own, would allocate with
    // this test still green. The watch is a canary for the shared premise
    // that the generator names no library declaration, not a fence around
    // allocation.
    switch (reachOfExpr(.str_literal)) {
        .impossible => {},
        .generated, .missing => return error.TestUnexpectedResult,
    }
}

/// Where a written `impl` header can name a head the implementation relation
/// holds a row for.
///
/// The relation is one relation, and the compiler puts rows in it that no
/// header wrote. Which of those a program could have written is the question
/// behind every "two implementations of one trait for one type" report: a
/// collision nothing can spell is a branch no case reaches.
///
/// Exhaustive, so a head kind added to the relation is a compile error here
/// before it is a claim nobody re-read.
fn writable(h: std.meta.Tag(Head)) enum { anywhere, where_the_trait_is_declared, never } {
    return switch (h) {
        // A name, and a header is names.
        .declared => .anywhere,
        // Primitive names and the parameter/observation families have no
        // declaring module. [M-Impl] requires the trait's module.
        .builtin, .parameter, .borrow_, .default_ => .where_the_trait_is_declared,
        // `impl Trait for fn(..) -> R`: [M-Impl] allows it only in the trait's
        // own module.
        .callable_ => .where_the_trait_is_declared,
        // A form rather than a name: `impl Index[UInt64] for [UInt8; 4]` does
        // not parse, so the constructor the compiler implements for cannot be
        // written down at all.
        .array => .never,
    };
}

test "an array's provided implementation collides with nothing writable" {
    // The row the compiler provides for arrays is a row coherence compares
    // written headers against, and no header can name that head -- so the
    // branch reporting the collision is unreachable from any program. Recorded
    // rather than cased: a case claiming to be about duplication while pinning
    // a parse error would be a case that lies.
    try testing.expectEqual(.never, writable(.array));

    // The other provided head is a primitive, which is writable exactly where
    // the trait is declared. A conformance program is never that module for a
    // prelude trait, and a trait of its own is a different trait, so that
    // collision is out of reach for the same distance and a different reason.
    try testing.expectEqual(.where_the_trait_is_declared, writable(.builtin));
    try testing.expectEqual(.where_the_trait_is_declared, writable(.parameter));
    try testing.expectEqual(.where_the_trait_is_declared, writable(.borrow_));
}

test "observations and callable signatures do not contain their referenced types inline" {
    // Observation referents and callable signatures are reached through
    // addresses. They do not impose by-value containment on those types.
    for (std.enums.values(std.meta.Tag(types_mod.Type))) |t| {
        const by_value = switch (t) {
            .integer,
            .open_integer,
            .open_type,
            .boolean,
            .float,
            .poison,
            .unit,
            .never,
            .parameter,
            .enum_,
            .struct_,
            .newtype,
            .array,
            => true,
            // Observations address referents; callables address code with
            // parameter and result types. Neither contains those types inline.
            .borrow, .callable, .closure => false,
        };
        try testing.expectEqual(t != .borrow and t != .callable and t != .closure, by_value);
    }
}

test "a projection's ceiling has something above it to declare" {
    // `Index` declares `inout` on its receiver, which reads as the most an
    // implementation could ever ask for -- and it is not. `sink` grants
    // strictly more, so a ceiling above the trait's is a shape a program can
    // write, and `a_projection_does_not_sink_its_receiver` is the case that
    // refuses it. What makes that case writable is this order and nothing
    // else, so the order is what is held here: flatten it and the case stops
    // being about a ceiling while still passing.
    try testing.expect(accessGranted(.sink) > accessGranted(.inout));
    try testing.expect(accessGranted(.inout) > accessGranted(.read));
}

test "a gap says what would close it" {
    for (std.enums.values(Expr.Tag)) |t| switch (reachOfExpr(t)) {
        .generated => {},
        .impossible => |why| try testing.expect(why.len > 0),
        .missing => |why| try testing.expect(why.len > 0),
    };
    for (std.enums.values(Decl.Tag)) |t| switch (reachOfDecl(t)) {
        .generated => {},
        .impossible => |why| try testing.expect(why.len > 0),
        .missing => |why| try testing.expect(why.len > 0),
    };
    for (std.enums.values(Inst.Tag)) |t| switch (reachOfInst(t)) {
        .generated => {},
        .impossible => |why| try testing.expect(why.len > 0),
        .missing => |why| try testing.expect(why.len > 0),
    };
    // Every axis `hold` is asked about, not the three it was first written
    // for. An axis reaching the run and not this test is one where a gap may
    // be recorded with nothing said about what closes it, which is the silence
    // the whole table exists to refuse.
    for (std.enums.values(node.Stmt.Tag)) |t| switch (reachOfStmt(t)) {
        .generated => {},
        .impossible => |why| try testing.expect(why.len > 0),
        .missing => |why| try testing.expect(why.len > 0),
    };
    for (std.enums.values(Nesting)) |t| switch (reachOfNesting(t)) {
        .generated => {},
        .impossible => |why| try testing.expect(why.len > 0),
        .missing => |why| try testing.expect(why.len > 0),
    };
    for (std.enums.values(node.Convention)) |t| switch (reachOfConvention(t)) {
        .generated => {},
        .impossible => |why| try testing.expect(why.len > 0),
        .missing => |why| try testing.expect(why.len > 0),
    };
    for (std.enums.values(TypeTag)) |t| switch (reachOfType(t)) {
        .generated => {},
        .impossible => |why| try testing.expect(why.len > 0),
        .missing => |why| try testing.expect(why.len > 0),
    };
    for (std.enums.values(Spelling)) |t| switch (reachOfSpelling(t)) {
        .generated => {},
        .impossible => |why| try testing.expect(why.len > 0),
        .missing => |why| try testing.expect(why.len > 0),
    };
}

/// The gaps that have been looked at and written down, with what each waits
/// on. Recorded, not approved: an entry is a note that someone read the hole
/// and knows what closes it, and it is expected to leave.
///
/// A list rather than a count, so that acknowledging one gap does not
/// acknowledge the next: a construct that starts waiting and is not written
/// here fails the test below, and one written here that stops waiting fails it
/// too. Both directions matter — a stale entry is a gap nobody will close.
///
/// One list across every axis, so a name is enough to record a gap and the
/// axis it sits on is read off the tables rather than written twice.
///
/// The list stays because the next construct to arrive will wait on
/// something, and a gap nobody wrote down is a gap nobody closes. Emptying it
/// is the outcome, not the end of the mechanism: the test below fails just as
/// loudly for a gap that opens as for an entry that goes stale.
const recorded_gaps = [_][]const u8{};

/// What holding one axis's gaps to the recorded list found.
const Gaps = struct {
    /// A gap nobody wrote down, or an entry that has stopped being true.
    /// Either leaves the list saying something that is not so, and the second
    /// hides the next gap behind a note that is already wrong.
    wrong: bool = false,
    /// How many recorded gaps this axis said out loud.
    said: u32 = 0,
};

/// Holds one axis's gaps to the recorded list, in both directions, and says
/// what is still waiting.
///
/// One routine over every axis rather than a loop each: the same three
/// questions are asked of all of them, and an axis added to one loop and
/// forgotten in another reports on the axes someone remembered and stays quiet
/// about the rest -- which is the shape of the omission this whole file exists
/// to make loud.
///
/// A mismatch is said out loud before it fails. An acknowledged gap passes in
/// silence: the list above is the durable reminder, while stdout is reserved by
/// Zig's test protocol and stderr makes the build runner treat a passing test as
/// failed.
fn gapsOf(
    comptime Tag: type,
    comptime reachOf: fn (Tag) Reach,
    axis: []const u8,
    recorded: []const []const u8,
    w: *std.Io.Writer,
) !Gaps {
    var found: Gaps = .{};
    for (std.enums.values(Tag)) |t| {
        const why = switch (reachOf(t)) {
            .missing => |w2| w2,
            else => continue,
        };
        if (!named(recorded, @tagName(t))) {
            try w.print("{s}: `{s}` waits on something nobody wrote down\n", .{ axis, @tagName(t) });
            found.wrong = true;
            continue;
        }
        try w.print("conformance: {s}: `{s}` is generated by nothing -- {s}\n", .{ axis, @tagName(t), why });
        found.said += 1;
    }

    for (recorded) |name| {
        for (std.enums.values(Tag)) |t| {
            if (!std.mem.eql(u8, @tagName(t), name)) continue;
            if (reachOf(t) == .missing) continue;
            try w.print("{s}: `{s}` is generated, and is still listed as a gap\n", .{ axis, name });
            found.wrong = true;
        }
    }
    return found;
}

test "a gap is either closed or written down" {
    // An instruction is held harder than the rest: lowering emits what it
    // emits, so a tag nothing produces is a hole in what the generator can
    // reach rather than a construct waiting on syntax somebody has to write.
    for (std.enums.values(Inst.Tag)) |t| switch (reachOfInst(t)) {
        .missing => |why| {
            std.debug.print("instructions: `{s}` still waits on {s}\n", .{ @tagName(t), why });
            return error.SomethingIsUngenerated;
        },
        else => {},
    };

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var said: std.Io.Writer.Allocating = .init(arena.allocator());

    // Every axis a recorded gap can name, so an entry cannot be written down
    // on one and go unreported on another.
    var wrong = false;
    inline for (.{
        .{ Expr.Tag, reachOfExpr, "syntax" },
        .{ node.Stmt.Tag, reachOfStmt, "statements" },
        .{ Decl.Tag, reachOfDecl, "declarations" },
        .{ node.Convention, reachOfConvention, "conventions" },
        .{ TypeTag, reachOfType, "semantic types" },
        .{ Nesting, reachOfNesting, "nesting" },
        .{ Spelling, reachOfSpelling, "spellings" },
    }) |axis| {
        const found = try gapsOf(axis[0], axis[1], axis[2], recorded_gaps[0..], &said.writer);
        if (found.wrong) wrong = true;
    }

    if (wrong and said.written().len > 0) std.debug.print("{s}", .{said.written()});
    if (wrong) return error.CoverageTableIsWrong;
}

test "a recorded gap is reported, and one that closed fails" {
    // The loop above runs over an empty list, so nothing in it can fail today
    // and a run says nothing about whether it works. Here it is, over a table
    // written for the purpose: what a real axis will do the day it has a gap.
    const Fabricated = enum { written_down, nobody_wrote_it_down, already_closed };
    const reach = struct {
        fn of(t: Fabricated) Reach {
            return switch (t) {
                .written_down => .{ .missing = "a construct the generator has not been taught" },
                .nobody_wrote_it_down => .{ .missing = "something nobody recorded" },
                .already_closed => .generated,
            };
        }
    }.of;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A gap on the list is said out loud, by name and with what closes it, and
    // passes. Read out of what was written rather than off a count: a loop
    // that reported the wrong gap would count the same.
    var one: std.Io.Writer.Allocating = .init(gpa);
    const both = try gapsOf(Fabricated, reach, "an axis", &.{ "written_down", "nobody_wrote_it_down" }, &one.writer);
    try testing.expect(!both.wrong);
    try testing.expectEqual(@as(u32, 2), both.said);
    try testing.expect(std.mem.indexOf(u8, one.written(), "`written_down` is generated by nothing") != null);
    try testing.expect(std.mem.indexOf(u8, one.written(), "the generator has not been taught") != null);

    // A gap nobody wrote down fails.
    var unrecorded: std.Io.Writer.Allocating = .init(gpa);
    try testing.expect((try gapsOf(Fabricated, reach, "an axis", &.{"written_down"}, &unrecorded.writer)).wrong);
    try testing.expect(std.mem.indexOf(
        u8,
        unrecorded.written(),
        "`nobody_wrote_it_down` waits on something nobody wrote down",
    ) != null);

    // And so does an entry that has stopped being true, which would otherwise
    // hide the next gap behind a note that is already wrong.
    var stale: std.Io.Writer.Allocating = .init(gpa);
    try testing.expect((try gapsOf(Fabricated, reach, "an axis", &.{
        "written_down",
        "nobody_wrote_it_down",
        "already_closed",
    }, &stale.writer)).wrong);
    try testing.expect(std.mem.indexOf(
        u8,
        stale.written(),
        "`already_closed` is generated, and is still listed as a gap",
    ) != null);
}

fn named(names: []const []const u8, wanted: []const u8) bool {
    for (names) |n| {
        if (std.mem.eql(u8, n, wanted)) return true;
    }
    return false;
}
