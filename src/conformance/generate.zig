const std = @import("std");
const testing = std.testing;

const source_mod = @import("../support/source.zig");
const FileTable = source_mod.FileTable;
const Source = source_mod.Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const render = @import("../diagnostics/render.zig");
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const choices_mod = @import("choices.zig");
const Choices = choices_mod.Choices;
const scope_mod = @import("scope.zig");
const Ty = scope_mod.Ty;
const Binding = scope_mod.Binding;
const Scope = scope_mod.Scope;
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const resolveTree = @import("../sema/resolve.zig").resolveTree;
const typecheck = @import("../sema/typecheck.zig").typecheck;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;
const loader = @import("../driver/loader.zig");
const Program = @import("../syntax/program.zig").Program;
const transform = @import("transform.zig");

/// One generated enum: how many alternatives, and what each carries.
///
/// A payload carries a value of any type declared before it -- a scalar, a
/// structure, or an earlier enum. Naming only what came before is what keeps
/// the graph acyclic by construction.
const Enum = struct {
    count: u32,
    payload: [max_variants]?Ty = @splat(null),
};

/// The bound `max_variants` may take, so an enum's payloads are a fixed row.
const max_variants = 4;

/// One generated structure: how many parts, and what each is.
const Struct = struct {
    count: u32,
    field: [max_fields]Ty = @splat(.u8_),
};

/// The most fields a structure may have, so its parts are a fixed row.
const max_fields = 3;

/// How many structure updates may nest, each as the base of the one outside it.
const max_update_bases = 2;

/// Whether a whole number written on its own is a value of this type.
///
/// What a parameter may default to. A literal takes the type its position
/// wants, so a digit is a constant of any of the three at once -- and every
/// other type here is reached through a name the declaration cannot see, or
/// through a form the checker will not fold.
fn isWholeNumber(t: Ty) bool {
    return switch (t) {
        .u8_, .i8_, .i64_ => true,
        // A whole number is an integer literal, and nothing converts it: a
        // float parameter's default would need a float spelling, which this
        // question is not about.
        .f64_ => false,
        .bool_, .enum_, .struct_, .held, .array => false,
    };
}

const Func = struct {
    /// How a call spells it: the bare name, or the type's name and a dot
    /// where an `impl` gave it to one.
    name: []const u8,
    /// How the declaration spells it, which is the bare name either way.
    declared: []const u8,
    /// The type whose `impl` holds it, if any. A function is behaviour
    /// written about a type rather than a value of one, so nothing about the
    /// signature changes -- only where it is written and how it is reached.
    owner: ?Ty,
    params: []const Binding,
    /// What each parameter defaults to, aligned with `params` and null where
    /// it declares none.
    ///
    /// Beside the parameters rather than on a `Binding`, because a default is
    /// a fact about a parameter and a `Binding` is what the body has in scope:
    /// a local carries no default, and the body reads this list through
    /// neither.
    ///
    /// A whole number of the parameter's own type, so it is a constant
    /// expression by construction -- the value is worked out where the
    /// parameter is declared, and nothing a call writes can reach it.
    defaults: []const ?u8,
    ret: Ty,
};

/// Fills a choice stream from a seed, for a run that replays from one number.
pub fn choicesFromSeed(gpa: std.mem.Allocator, seed: u64, len: usize) ![]u8 {
    return choices_mod.fromSeed(gpa, seed, len);
}

pub const Options = struct {
    max_enums: u32 = 2,
    max_structs: u32 = 2,
    max_variants: u32 = 3,
    max_functions: u32 = 2,
    max_statements: u32 = 3,
    /// How deeply statements may nest.
    ///
    /// A loop is the only statement that nests -- a `while` and a walk over an
    /// array alike -- and this is what stops it.
    /// Termination may not rest on the choice stream: the stream wraps, so a
    /// period that kept choosing to nest would recurse forever -- which it
    /// did, on seed 322, the first time a loop body was made non-empty.
    max_nesting: u32 = 3,
    max_depth: u32 = 3,
    /// How many tuple groups `main` holds, each taking one literal and one
    /// call apart.
    max_tuples: u32 = 2,
};

/// A program the compiler accepts, built from a stream of choices.
///
/// Well-typed by construction: every expression is generated for the type its
/// position demands, so nothing is discarded for being rejected and the whole
/// stream produces programs worth compiling. A generator that filtered instead
/// would spend nearly all of its output on programs the checker refuses.
///
/// Every name it introduces begins with `_`, which declares a binding
/// deliberately unused without making it unreferenceable. That is what frees
/// generation from having to arrange a use for everything it declares --
/// [N-Unused] is an error, and satisfying it by construction would bias every
/// program towards the shapes that are easy to consume.
pub fn generate(gpa: std.mem.Allocator, bytes: []const u8, opts: Options) ![]const u8 {
    var g: Gen = .{
        .gpa = gpa,
        .choices = .{ .bytes = bytes },
        .side = .{ .bytes = bytes, .at = bytes.len -| 16 },
        .scope = .{ .gpa = gpa },
        .opts = opts,
    };
    defer g.deinit();
    return g.program();
}

/// A generated interpolation chooses each value's spec from this table. Every
/// spec is valid on a `UInt8`, and each entry records the format it parses to.
pub const interpolation_specs = [_]struct { text: []const u8, format: node.InterpolationFormat }{
    .{ .text = "", .format = .display },
    .{ .text = ":?", .format = .debug_only },
    .{ .text = ":>4", .format = .{ .alignment = .right, .width = 4 } },
    .{ .text = ":02", .format = .{ .zero = true, .width = 2 } },
    .{ .text = ":*^+6?", .format = .{ .fill = '*', .alignment = .center, .plus = true, .width = 6, .debug = true } },
    .{ .text = ":02x", .format = .{ .zero = true, .width = 2, .hex = .lower } },
    .{ .text = ":>3X", .format = .{ .alignment = .right, .width = 3, .hex = .upper } },
};

pub const InterpolationShape = struct {
    pieces: u32,
    /// Each entry indexes the spec its value was written with.
    specs: [8]u8,
};

pub const GeneratedInterpolation = struct {
    text: []const u8,
    shape: InterpolationShape,
};

/// A syntax-focused interpolation whose value formats vary independently.
/// The whole-program generator names no library declaration and cannot name `Str`,
/// `Display` or `Debug`, so this production is parsed rather than typechecked.
pub fn generateInterpolation(gpa: std.mem.Allocator, bytes: []const u8) !GeneratedInterpolation {
    var choices: Choices = .{ .bytes = bytes };
    const pieces = choices.between(1, 8);
    var specs = [_]u8{0} ** 8;

    var out: std.Io.Writer.Allocating = .init(gpa);
    try out.writer.writeAll("fn _formats(");
    for (0..pieces) |i| {
        if (i != 0) try out.writer.writeAll(", ");
        try out.writer.print("v{d}: UInt8", .{i});
    }
    try out.writer.writeAll(") {\n    let _text = \"");
    for (0..pieces) |i| {
        const chosen = choices.below(interpolation_specs.len);
        specs[i] = @intCast(chosen);
        try out.writer.print("{{v{d}{s}}}", .{ i, interpolation_specs[chosen].text });
    }
    try out.writer.writeAll("\"\n}\n");
    return .{ .text = out.written(), .shape = .{ .pieces = pieces, .specs = specs } };
}

const Error = std.mem.Allocator.Error || std.Io.Writer.Error;

/// Where a value is being written, which is what decides whether it moves.
const Position = enum { reading, consuming };

/// The most of each thing a drawn trait may have, which is what lets the shape
/// be a value rather than three allocations. An implementing type is a
/// structure, so how wide one may be is the width every structure is held to.
const max_ops = 2;
const max_impls = 3;

/// The trait a program declares, its implementations, and what each answers.
///
/// Drawn rather than written out, because a block that is the same bytes
/// however the choices fall is one program reported as however many seeds ran:
/// the machinery around a trait is reached the same way every time and the
/// arrangements it is reached with are not tested at all.
const TraitShape = struct {
    /// How many operations the trait declares.
    ops: u32,
    /// How many types implement it.
    impls: u32,
    /// How `Self` reaches every operation.
    ///
    /// One convention for the whole trait: a signature is what an
    /// implementation is held to, and the function written against the bound
    /// passes its parameter straight into the call, so all three have to agree.
    convention: SelfConvention,
    /// How many fields each implementing type holds.
    fields: [max_impls]u32,
    /// Which of its own fields each type answers each operation with.
    answers: [max_impls][max_ops]u32,
    /// What each implementation settles the trait's declared type to.
    ///
    /// One per implementation and not one per trait, because a name every
    /// implementation settles alike is a name substitution cannot get wrong:
    /// the one thing a settled reference asks of the compiler is that each
    /// instantiation answers with what *its own* argument settled, and two
    /// implementations settling one type make a wrong answer well-typed.
    items: [max_impls]ItemType,
    /// Which of its own fields each type answers the declared type with.
    item_answers: [max_impls]u32,
    /// Whether the implementation settling a `Bool` answers `true`, so the
    /// guard after the call is a question rather than a restatement.
    item_hits: [max_impls]bool,

    /// What the type built at every call site sets its fields to.
    ///
    /// A type's own tens digit, so no two types answer one operation with the
    /// same number whatever fields they answer with. That is the whole of what
    /// makes the answer say which body ran: two implementations returning one
    /// value would be dispatched wrongly and agree.
    fn value(self: TraitShape, ty: u32, field: u32) u32 {
        _ = self;
        return ty * 10 + field;
    }

    /// What a correct dispatch of an operation on a type produces.
    fn answer(self: TraitShape, ty: u32, op: u32) u32 {
        return self.value(ty, self.answers[ty][op]);
    }

    /// What the field a type answers its declared type with holds.
    fn itemField(self: TraitShape, ty: u32) u32 {
        return self.value(ty, self.item_answers[ty]);
    }

    /// What the body settling a `Bool` compares that field against: the value
    /// itself where the answer is `true`, and a number no field holds where it
    /// is `false`.
    fn itemAgainst(self: TraitShape, ty: u32) u32 {
        return self.itemField(ty) + @intFromBool(!self.item_hits[ty]);
    }
};

/// The independent syntax dimensions of one generated structural derive.
const StructuralShape = struct {
    group_entries: u32,
    generic_parameters: u32,
    inline_bounds: u32,
    trailing_predicates: u32,
    component_predicates: u32,
    bounds_per_predicate: u32,
    member_parameters: u32,
    bounds_per_member_parameter: u32,
    reverse_components: bool,
};

/// What an implementation settles the trait's declared type to.
///
/// Two, because one type would leave every instantiation answering alike --
/// the settled reference in the signature would be well-typed at the wrong
/// implementation's answer, and a generated program cannot say what it does
/// not distinguish.
const ItemType = enum {
    u8_,
    bool_,

    fn spelling(self: ItemType) []const u8 {
        return switch (self) {
            .u8_ => "UInt8",
            .bool_ => "Bool",
        };
    }
};

/// How a trait's operations take the value they are written about.
const SelfConvention = enum {
    read,
    /// The value is taken, so the call site builds one per call and the
    /// function written against the bound hands its own parameter on.
    sink,

    fn parameterPrefix(self: SelfConvention) []const u8 {
        return switch (self) {
            .read => "",
            .sink => "sink ",
        };
    }
};

const Gen = struct {
    gpa: std.mem.Allocator,
    choices: Choices,
    opts: Options,

    enums: std.ArrayList(Enum) = .empty,
    structs: std.ArrayList(Struct) = .empty,
    funcs: std.ArrayList(Func) = .empty,
    scope: Scope,
    /// What each instantiation of the generic structure was made at, indexed
    /// by the `held` a `Ty` carries. One entry per distinct argument.
    held: std.ArrayList(Ty) = .empty,
    /// How each instantiation is written, kept because a spelling outlives the
    /// call that asked for it and `spell` returns a borrowed slice.
    spellings: std.ArrayList([]const u8) = .empty,
    /// The trait the program declares, or null where it declares none.
    ///
    /// More than one implementation always, so a call through the bound is
    /// monomorphised once per implementing type and each must reach its own
    /// body. One would exercise the machinery and prove nothing about which
    /// body it picked.
    traits: ?TraitShape = null,
    /// The structural templates and grouped generic derive every generated
    /// program carries. Its dimensions are drawn without advancing the main
    /// stream, so adding this coverage does not re-phase existing productions.
    structural: ?StructuralShape = null,
    /// Whether the program declares a linear type.
    ///
    /// It is kept out of `Ty` so the general expression pool remains copyable.
    /// Linear values use dedicated constructions and settlement paths instead
    /// of the pool's arbitrary copies and unused bindings.
    linear: bool = false,
    /// Whether the program declares the generic types and functions.
    generic: bool = false,
    /// Whether the program declares a function answering the unit type.
    ///
    /// Kept out of `Ty` for a reason of its own: `()` is spellable as a return
    /// type and nowhere else, so no annotation can ask for one and no field or
    /// payload can be declared to hold one. A value of it exists only where
    /// inference put it, which is why it is written where it is written rather
    /// than chosen like a type.
    unit: bool = false,
    /// Whether the program declares a newtype over `UInt8`.
    ///
    /// Kept out of `Ty` for the same reason `linear` is: every type the
    /// selection machinery draws from is one whose representation it also
    /// picked, and a newtype's representation is its base's, chosen nowhere
    /// near a call to `aType`. So it is spelled where it is written, and a
    /// program that declares it always constructs one with a literal the
    /// refinement is written to accept -- proving the bound at the call
    /// rather than reaching for the fallible form nothing here needs yet.
    newtype: bool = false,
    /// Whether the program declares a type whose places a projection names.
    ///
    /// Kept out of `Ty` for the reason `linear` and `newtype` are: nothing
    /// about it is chosen the way an enum or a structure is, and what it is
    /// here to exercise is the member form rather than another layout.
    projected: bool = false,
    /// Names already marked `&` somewhere in the expression being written.
    ///
    /// Exclusivity is about one call's arguments and about everything they
    /// contain, so a mark inside a nested call still counts against the outer
    /// one -- `f(f(x, &p), &p)` names one place twice.
    marked: std.ArrayList([]const u8) = .empty,
    /// Whether what is being written sits in a position that takes the value.
    ///
    /// A move is universal, so naming a place where the value is taken moves
    /// it: the binding is gone afterwards and a part cannot be taken out of
    /// its whole at all. Both are [O-Move], and neither is anything the type
    /// checker would have said -- which is why the generator has to know
    /// where it is writing and not only what type is wanted.
    position: Position = .reading,
    next_name: u32 = 0,
    /// A second stream of decisions, read only while a tuple is written.
    ///
    /// Every other axis is drawn from `choices`, and a byte taken from it for
    /// tuples would re-phase all of them. It starts near the end of the same
    /// bytes, so one input still decides the whole program.
    side: Choices,
    /// What each tuple-returning function declares, by tuple index.
    tuple_returns: std.ArrayList([2]ItemType) = .empty,
    /// How many structure updates enclose the literal being written as their
    /// base.
    update_bases: u32 = 0,

    fn deinit(self: *Gen) void {
        self.tuple_returns.deinit(self.gpa);
        self.enums.deinit(self.gpa);
        self.held.deinit(self.gpa);
        for (self.spellings.items) |t| self.gpa.free(t);
        self.spellings.deinit(self.gpa);
        self.structs.deinit(self.gpa);
        self.marked.deinit(self.gpa);
        self.funcs.deinit(self.gpa);
        self.scope.deinit();
    }

    /// Sets the position for what is written next, returning the old one for
    /// the caller to restore.
    fn enter(self: *Gen, p: Position) Position {
        const was = self.position;
        self.position = p;
        return was;
    }

    fn name(self: *Gen, comptime prefix: []const u8) ![]const u8 {
        const n = self.next_name;
        self.next_name += 1;
        return std.fmt.allocPrint(self.gpa, "_" ++ prefix ++ "{d}", .{n});
    }

    fn program(self: *Gen) ![]const u8 {
        var out: std.Io.Writer.Allocating = .init(self.gpa);

        // A name bound to a value, and a second one naming the first. Nothing
        // runs where a constant is declared, so what one is worth comes out of
        // the initialiser alone: the second is what puts a constant expression
        // reaching through a name under a generated program, where a literal
        // on its own would only be folded where it stands.
        //
        // Written whatever the choices say, and so drawing nothing from them.
        // Every other axis this generator is sampled on is drawn from the same
        // stream, and a byte taken here would re-phase all of them -- a shape
        // that arrives loses one that was already reached.
        //
        // `pub`, because a constant is read from other declarations and from
        // other modules -- its type and its value are part of what a module
        // publishes.
        try out.writer.writeAll(
            \\pub let _k0: UInt8 = 7
            \\pub let _k1: UInt8 = _k0 + 1
            \\
            \\@copyable
            \\pub struct Pin { cell: borrow UInt8, tag: UInt8 }
            \\
            \\
        );

        // Declarations are emitted in one pass rather than all structures
        // then all enums, so a field may name an enum and a payload may carry
        // a structure. Each names only what came before it, which is what
        // keeps the graph acyclic by construction -- the generator never
        // writes what [T-InfiniteLayout] rejects, and never tests it, which is
        // the corpus's job.
        //
        // The order matters more than it looks: while structures came first, a
        // field could not name an enum at all, and the shapes a type can hold
        // were half the shapes the language allows.
        var so_far: std.ArrayList(Ty) = .empty;
        defer so_far.deinit(self.gpa);

        // One generic structure, declared before anything that could hold
        // one. A parameter with no bound is Linear, so `G` may hold anything
        // -- including the linear type below -- which is what puts
        // substitution-by-universe under a generated program rather than under
        // a written case.
        //
        // `pub`, because whether a body reaches it is a matter of what the
        // choices said and a declaration nothing names is [N-Unused]. A
        // reachable name satisfies that rule, the same way a library's exports
        // do.
        self.generic = self.choices.odds(2);
        if (self.generic) {
            // More shapes than the one that gets instantiated below. A branch
            // whose subject is generics had a generator that could write a
            // single-parameter, single-field struct and nothing else -- no
            // generic function, no bound, no second parameter, no generic
            // enum. These are declared rather than called, so they reach the
            // frontend, the ownership pass and every rewrite, and only `G` is
            // monomorphised. `pub` for the reason above.
            try out.writer.writeAll(
                \\@copyable pub struct G[T] { g: T }
                \\
                \\pub struct G2[A, B] { a: A, b: B }
                \\
                \\pub enum GE[T] {
                \\    Nothing,
                \\    Just(T),
                \\}
                \\
                \\pub fn gid[T](sink v: T) -> T {
                \\    v
                \\}
                \\
                \\pub fn gcopy[T: Copyable](v: T) -> T {
                \\    copy(v)
                \\}
                \\
                \\alias GA[T] = GE[T]
                \\
                \\fn _aliasedNothing() -> GE[UInt8] {
                \\    GA.Nothing
                \\}
                \\
            );
            // A phantom parameter, because every other parameter this block
            // writes is used and a generated program would otherwise never
            // hold the one kind that is not -- the declaration reaches the
            // frontend and every rewrite the way the shapes above do.
            try out.writer.writeAll(
                \\pub struct GP[phantom P] { n: UInt8 }
                \\
                \\
            );
            // An implementation generic over its head, so a generated program
            // holds one and every rewrite over the corpus reaches the position
            // at whatever size the flag asks for. Written for `GP`, whose
            // parameter carries nothing: the body reads a field of a settled
            // type, so the family answers for every member of itself and needs
            // no bound to say which.
            //
            // The only implementation of `GHeld` anywhere in a generated
            // program, and the only one of any trait for `GP`. A second would
            // put two families on one head, and which of two overlapping
            // families a call reaches is decided by which was written first --
            // so the program would mean one thing and its declarations
            // reversed another, and the rewrite that reverses them would read
            // as a compiler that disagrees with itself. The test below holds
            // that for every seed.
            //
            // The calls in `unitGroup` are what monomorphise it, at two
            // arguments, so the head is bound from a receiver rather than only
            // parsed.
            try out.writer.writeAll(
                \\pub trait GHeld {
                \\    fn held(v: Self) -> UInt8
                \\}
                \\
                \\impl[P] GHeld for GP[P] {
                \\    fn held(v: Self) -> UInt8 {
                \\        v.n
                \\    }
                \\}
                \\
                \\
            );
            const arg = self.aType(&.{});
            try so_far.append(self.gpa, try self.instantiate(arg));
        }

        const total = self.choices.below(self.opts.max_enums + self.opts.max_structs + 1);
        for (0..total) |_| {
            const room_for_enum = self.enums.items.len < @min(self.opts.max_enums, 2);
            const room_for_struct = self.structs.items.len < @min(self.opts.max_structs, 2);
            if (!room_for_enum and !room_for_struct) break;

            const write_enum = room_for_enum and (!room_for_struct or self.choices.odds(2));
            if (write_enum) {
                const e = self.enums.items.len;
                const count = self.choices.between(1, @min(self.opts.max_variants, max_variants));
                var def: Enum = .{ .count = count };
                for (0..count) |v| {
                    // Not every variant carries something: an enum where all
                    // of them do never produces the arm that binds nothing,
                    // and the two arms lower differently.
                    if (self.choices.odds(2)) def.payload[v] = self.aType(so_far.items);
                }
                try self.enums.append(self.gpa, def);

                try out.writer.print("@copyable enum E{d} {{", .{e});
                for (0..count) |v| {
                    try out.writer.print("{s} _V{d}", .{ if (v == 0) "" else ",", v });
                    if (def.payload[v]) |ty| try out.writer.print("({s})", .{self.spell(ty)});
                }
                try out.writer.writeAll(" }\n\n");
                try so_far.append(self.gpa, .{ .enum_ = @intCast(e) });
            } else {
                const i = self.structs.items.len;
                const count = self.choices.between(1, max_fields);
                var def: Struct = .{ .count = count };
                for (0..count) |f| def.field[f] = self.aType(so_far.items);
                try self.structs.append(self.gpa, def);

                try out.writer.print("@copyable struct S{d} {{", .{i});
                for (0..count) |f| {
                    try out.writer.print("{s} f{d}: {s}", .{ if (f == 0) "" else ",", f, self.spell(def.field[f]) });
                }
                try out.writer.writeAll(" }\n\n");
                try so_far.append(self.gpa, .{ .struct_ = @intCast(i) });
            }
        }

        // A linear type, declared last so that nothing already written could
        // have named it, and never added to `so_far` so that nothing later
        // can. [O-Universe] is therefore satisfied by construction rather
        // than by a rule the generator has to apply.
        //
        // Two functions come with it, and between them they are the only way
        // a generated program can dispose of one. `sink` takes it and the
        // consuming `match` takes it apart; `read` lends it and `match read`
        // observes it without taking. Both forms of arm appear: a binder from
        // a consuming match owns what it was given and is returned as it is,
        // and one from a lending match is a part of a value someone else
        // still holds, so handing it out is a `copy`.
        self.linear = self.choices.odds(2);
        if (self.linear) {
            try out.writer.writeAll(
                \\@linear enum L0 { _W0(UInt8), _W1 }
                \\
                \\fn _dispose(sink held: L0) -> UInt8 {
                \\    match held { _W0(carried) => carried, _W1 => 1 }
                \\}
                \\
                \\fn _peek(held: L0) -> UInt8 {
                \\    match read held { _W0(carried) => carried, _W1 => 2 }
                \\}
                \\
                \\fn _drop(sink held: L0) {
                \\    match held { _W0(_carried) => {}, _W1 => {} }
                \\}
                \\
                \\impl Release for L0 {
                \\    fn release(sink self: Self) {
                \\        _drop(self)
                \\    }
                \\}
                \\
                \\
            );

            // An instantiation at the linear type, disposed of by taking it
            // apart. Its universe is computed rather than declared, so this is
            // a `G` that must be consumed exactly once and a `G` at any other
            // argument is not -- one declaration, two obligations, and neither
            // written down.
            if (self.generic) {
                try out.writer.writeAll(
                    \\pub fn _unwrap(sink boxed: G[L0]) -> UInt8 {
                    \\    let G { g: held } = boxed;
                    \\    _dispose(held)
                    \\}
                    \\
                    \\
                );
            }
        }

        // A newtype over `UInt8`, declared with a refinement so the proof
        // machinery is exercised and not only the nominal distinction --
        // [T-Refine] is settled at every call this generator writes, which is
        // what lets each construct a literal directly instead of needing the
        // fallible form. Every destructuring form is reached: `let`,
        // `match`, and `let read`, which lends the base of a parameter it
        // reads rather than taking the value apart. The `read` form takes its
        // parameter through an alias, so a value of the newtype is passed
        // where the alias is written and the two are one type.
        self.newtype = self.choices.odds(2);
        if (self.newtype) {
            try out.writer.writeAll(
                \\@copyable type N0 = UInt8 where it in 0..=99
                \\
                \\alias A0 = N0
                \\
                \\fn _fromNewtype(sink held: N0) -> UInt8 {
                \\    let N0(n) = held
                \\    n
                \\}
                \\
                \\fn _fromNewtypeMatch(sink held: N0) -> UInt8 {
                \\    match held {
                \\        N0(n) => n,
                \\    }
                \\}
                \\
                \\fn _fromNewtypeRead(held: A0) -> UInt8 {
                \\    let read N0(n) = held
                \\    n
                \\}
                \\
                \\
            );
        }

        // A type whose places a member names, which is the one member form
        // that is a path rather than a body: `proj at` says which place each
        // position stands for, and what a reader writes to reach it is a
        // bracket.
        //
        // Declared against a trait of the program's own. A projection is
        // refused in an inherent `impl`, so a trait has to declare one for an
        // implementation to supply it -- and the trait a bracket is settled
        // through is the prelude's `Index`, which the generator does not
        // name. So what is generated is the declaration and its
        // rules: the body held to a place path, the pair of member kinds
        // matched across the implementation walk, and the associated type the
        // element is read through. What a bracket over such a type would
        // splice stays out of reach for the reason every other prelude name
        // does.
        //
        // Kept out of `Ty` and out of the pool the way the linear type is:
        // what is being exercised is the member form, and drawing the type
        // from the pool would make every generated program a different
        // question about layout instead.
        self.projected = self.choices.odds(2);
        if (self.projected) {
            try out.writer.writeAll(
                \\trait _Places {
                \\    type Elem
                \\    proj at(inout self: Self, i: UInt64) -> Elem
                \\}
                \\
                \\struct P0 { p: [UInt8; 4] }
                \\
                \\impl _Places for P0 {
                \\    type Elem = UInt8
                \\
                \\    proj at(inout self: P0, i: UInt64) -> UInt8 {
                \\        self.p[i]
                \\    }
                \\}
                \\
                \\
            );
        }

        const structural = self.drawStructural();
        self.structural = structural;
        try self.structuralDeclarations(&out.writer, structural);

        // A trait, the types that implement it, and one function per operation
        // written against the bound rather than against any of them. Declared
        // after the types above and holding none of them, for the reason the
        // linear group is: what is being exercised is the trait machinery, and
        // drawing the implementing types from the pool would make every
        // generated program a different question about layout instead.
        //
        // Every name here begins with `_`, so [N-Unused] is satisfied whatever
        // the entry body does with them -- and the body reaches them anyway,
        // because a trait nothing calls says nothing about dispatch.
        if (self.choices.odds(2)) {
            const shape = self.drawTrait();
            self.traits = shape;
            try self.traitDeclarations(&out.writer, shape);
        }

        // A function answering the unit type, which is the only way a program
        // can reach a value of no width.
        //
        // No choice this generator makes over types produces `()`, so a
        // function that returns it, writing no result, is the only route.
        // That is why nothing in the corpus instantiated a generic
        // at a type of no width, and why the layout, the store and the load of
        // a part occupying no bytes were reached by nothing.
        //
        // Its body ends with the unit value, `()`, so a generated program
        // also holds the literal that spells it.
        self.unit = self.choices.odds(2);
        if (self.unit) {
            try out.writer.writeAll(
                \\fn _nothing() {
                \\    ()
                \\}
                \\
                \\
            );
        }

        // Signatures first, so a body may call a function declared after it --
        // which is legal, and is a shape a generator that emitted bodies as it
        // went would never produce.
        const func_count = self.choices.below(self.opts.max_functions + 1);
        for (0..func_count) |_| {
            const n = try self.name("f");
            var params: std.ArrayList(Binding) = .empty;
            var writes_back = false;
            for (0..self.choices.below(3)) |_| {
                // `mutable` on a parameter is `inout`: the one the function
                // writes back through, which the call site marks with `&`.
                // At most one, so two arguments can never name one place and
                // [N-Aliased] has nothing to catch -- generating a program it
                // rejects would test the rejection rather than the feature.
                const inout = !writes_back and self.choices.odds(3);
                if (inout) writes_back = true;

                try params.append(self.gpa, .{
                    .name = try self.name("p"),
                    .ty = self.anyType(),
                    .mutable = inout,
                    .frozen = false,
                    .depth = 0,
                });
            }
            // What a call may leave out, drawn from the back.
            //
            // [S-Default] makes the defaulted parameters a suffix and admits
            // one on a `read` or `sink` parameter and never on `inout`, so
            // the walk starts at the end and stops at the first parameter
            // that cannot carry one or does not draw one -- which is what
            // makes the suffix a property of how this is written rather than
            // of what the stream said. Generated parameters are `read` or
            // `inout`, so `sink` defaults are covered by the corpus alone:
            // drawing them would add a convention to every parameter and
            // shift every recorded choice stream.
            // `inout` is where it stops soonest: what a call writes back
            // through is an obligation, and a value the call never wrote
            // cannot discharge it.
            const defaults = try self.gpa.alloc(?u8, params.items.len);
            @memset(defaults, null);
            var d = params.items.len;
            while (d > 0) : (d -= 1) {
                const p = params.items[d - 1];
                if (p.mutable or !isWholeNumber(p.ty)) break;
                if (!self.choices.odds(3)) break;
                defaults[d - 1] = @intCast(self.choices.below(10));
            }

            // Sometimes written about a type rather than beside it. An
            // `impl` is a namespace and not a scope: the member sees what a
            // top-level declaration sees, so only where it is written and how
            // it is reached differ.
            const owner: ?Ty = blk: {
                const declared = self.enums.items.len + self.structs.items.len;
                // Two in three rather than one in three: a member named
                // through a type is what the `unknown_member` mutation aims
                // at, and its share of a fixed-seed run fell to nothing when
                // the float forms shifted every draw after them.
                if (declared == 0 or self.choices.odds(3)) break :blk null;
                const pick = self.choices.below(@intCast(declared));
                break :blk if (pick < self.enums.items.len)
                    .{ .enum_ = @intCast(pick) }
                else
                    .{ .struct_ = @intCast(pick - self.enums.items.len) };
            };

            try self.funcs.append(self.gpa, .{
                .name = if (owner) |o|
                    try std.fmt.allocPrint(self.gpa, "{s}.{s}", .{ self.spell(o), n })
                else
                    n,
                .declared = n,
                .owner = owner,
                .params = try params.toOwnedSlice(self.gpa),
                .defaults = defaults,
                // A function may return an enum, so a value too wide for a
                // register crosses a call boundary in both directions.
                .ret = self.anyType(),
            });
        }

        for (self.funcs.items, 0..) |f, i| {
            // One `impl` block per member rather than one per type: a type may
            // have as many as it likes, and grouping them would say nothing
            // the language does not already allow.
            if (f.owner) |o| try out.writer.print("impl {s} {{\n", .{self.spell(o)});
            try out.writer.print("fn {s}(", .{f.declared});
            for (f.params, 0..) |p, j| {
                try out.writer.print("{s}{s}{s}: {s}", .{
                    if (j == 0) "" else ", ",
                    if (p.mutable) "inout " else "",
                    p.name,
                    self.spell(p.ty),
                });
                if (f.defaults[j]) |v| try out.writer.print(" = {d}", .{v});
            }
            try out.writer.print(") -> {s} ", .{self.spell(f.ret)});

            self.scope.clear();
            try self.scope.pushAll(f.params);
            // A function may call only one declared before it. Mutual
            // recursion would generate programs that do not end, and nothing
            // here would tell that apart from a compiler that hangs.
            try self.body(&out.writer, f.ret, @intCast(i), &.{}, false);
            if (f.owner != null) try out.writer.writeAll("\n}");
            try out.writer.writeAll("\n\n");
        }

        // Every declared type is named in `main`, which is the one function
        // certain to exist.
        var declared: std.ArrayList(Ty) = .empty;
        defer declared.deinit(self.gpa);
        for (0..self.enums.items.len) |e| {
            try declared.append(self.gpa, .{ .enum_ = @intCast(e) });
        }
        for (0..self.structs.items.len) |i| {
            try declared.append(self.gpa, .{ .struct_ = @intCast(i) });
        }

        try self.tupleFunctions(&out.writer);

        try out.writer.writeAll("fn main() -> UInt8 ");
        self.scope.clear();
        try self.body(&out.writer, .u8_, @intCast(self.funcs.items.len), declared.items, true);
        try out.writer.writeAll("\n");

        return out.written();
    }

    /// A linear value, created, lent, and disposed of.
    ///
    /// Written as one straight-line group rather than scattered, and that is
    /// the whole of how the generator keeps "consumed exactly once on every
    /// path" true by construction: there is no branch between the three
    /// lines, so no path can disagree about whether the value is still held.
    /// Teaching it to split the obligation across arms means teaching it to
    /// prove the arms agree, which is the checker's job and not a generator's.
    ///
    /// The binding is not pushed into scope. Nothing else may name it, so
    /// nothing else can consume it a second time or leave it held.
    ///
    /// `may_leave` says the group is written where a `return 0` is well typed,
    /// which is `main` and nowhere else the generator has a return type for.
    /// It is what lets the group take the one shape that cancels a schedule:
    /// the value given away on the path that leaves, and the schedule firing
    /// on the path that does not. That shape is still consumed exactly once on
    /// every path by construction -- the branch decides *where*, not whether --
    /// so it keeps the invariant the straight-line group has.
    fn linearGroup(self: *Gen, w: *std.Io.Writer, at: u32, may_leave: bool) Error!void {
        const held = try self.name("l");
        const lent = try self.name("n");
        const taken = try self.name("n");

        // Drawn before anything is written, because where the binding is made
        // depends on how the disposal is placed: a `defer let` is both.
        const carries = self.choices.odds(2);
        const value = if (carries) self.choices.below(10) else 0;
        const lends = self.choices.odds(2);
        // Two ways to place the same disposal: written where it runs, or
        // scheduled at the scope's end. The second is what reaches `defer`,
        // and it answers with `()` because a scheduled expression is evaluated
        // for its effect exactly as a statement's is. It is scheduled either by
        // a `defer` beside the binding or by the binding itself.
        const scheduled = self.choices.odds(2);
        const binds_the_schedule = scheduled and self.choices.odds(2);

        try indent(w, at);
        const keyword = if (binds_the_schedule) "defer let" else "let";
        if (carries) {
            try w.print("{s} {s}: L0 = L0._W0({d});\n", .{ keyword, held, value });
        } else {
            // The variant that carries nothing, so the arm binding no name is
            // reached as well as the one binding one.
            try w.print("{s} {s}: L0 = L0._W1;\n", .{ keyword, held });
        }

        // Lending first: a `read` argument observes the value, so the binding
        // is still held afterwards and the line below is what discharges it.
        if (lends) {
            try indent(w, at);
            try w.print("let {s}: UInt8 = _peek({s});\n", .{ lent, held });
        }

        if (!scheduled) {
            try indent(w, at);
            try w.print("let {s}: UInt8 = _dispose({s});\n", .{ taken, held });
            return;
        }

        if (!binds_the_schedule) {
            try indent(w, at);
            try w.print("defer _drop({s});\n", .{held});
        }
        if (!may_leave or !self.choices.odds(2)) return;

        // The value given away on the path that leaves, so the schedule is
        // cancelled there and fires on the path that does not. Nothing else
        // the generator writes reaches cancellation, and cancellation is the
        // whole of why no runtime flag is needed.
        try indent(w, at);
        try w.writeAll("if ");
        {
            const was = self.enter(.reading);
            defer self.position = was;
            try self.expr(w, .bool_, 1, 0, .yes);
        }
        try w.writeAll(" {\n");
        try indent(w, at + 1);
        try w.print("let {s}: UInt8 = _dispose({s});\n", .{ taken, held });
        try indent(w, at + 1);
        try w.writeAll("return 0;\n");
        try indent(w, at);
        try w.writeAll("}\n");
    }

    /// Draws a trait: how many operations it declares, how many types
    /// implement it, how `Self` reaches an operation, and what each
    /// implementation answers with.
    fn drawTrait(self: *Gen) TraitShape {
        var shape: TraitShape = .{
            .ops = 1 + self.choices.below(max_ops),
            .impls = 2 + self.choices.below(max_impls - 1),
            .convention = if (self.choices.odds(2)) .sink else .read,
            .fields = @splat(1),
            .answers = @splat(@splat(0)),
            .items = @splat(.u8_),
            .item_answers = @splat(0),
            .item_hits = @splat(true),
        };
        for (0..shape.impls) |i| {
            shape.fields[i] = 1 + self.choices.below(max_fields);
            for (0..shape.ops) |j| {
                shape.answers[i][j] = self.choices.below(shape.fields[i]);
            }
            // From what the shape already holds rather than from the stream.
            // The stream is one phase for the whole program, and every other
            // axis the generated corpus is sampled on -- an array indexed, a
            // covering match narrowed -- is drawn after this: a byte taken
            // here re-phases all of them, and a shape that arrives loses one
            // that was already reached. So the settling alternates by
            // position, which also puts both of them in every program that
            // declares the trait, and what each answers with is the field an
            // operation already answers with.
            shape.items[i] = if (i % 2 == 1) .bool_ else .u8_;
            shape.item_answers[i] = shape.answers[i][shape.ops - 1];
            shape.item_hits[i] = shape.fields[i] % 2 == 1;
        }
        return shape;
    }

    fn drawStructural(self: *Gen) StructuralShape {
        var choices: Choices = .{
            .bytes = self.choices.bytes,
            .at = self.choices.bytes.len -| 8,
        };
        return .{
            .group_entries = choices.between(1, 2),
            .generic_parameters = choices.between(1, 2),
            .inline_bounds = choices.between(2, 3),
            .trailing_predicates = choices.below(3),
            .component_predicates = choices.between(1, 2),
            .bounds_per_predicate = choices.between(1, 2),
            .member_parameters = choices.between(1, 2),
            .bounds_per_member_parameter = choices.between(1, 2),
            .reverse_components = choices.below(2) == 1,
        };
    }

    /// Writes marker and function templates, their explicit component
    /// evidence, and one grouped generic derive over a fixed product shape.
    fn structuralDeclarations(self: *Gen, w: *std.Io.Writer, shape: StructuralShape) Error!void {
        _ = self;
        try w.writeAll(
            \\trait _Need0 {
            \\    fn _value(self: Self) -> UInt8
            \\}
            \\
            \\impl _Need0 for Bool {
            \\    fn _value(self: Bool) -> UInt8 {
            \\        if self { 1 } else { 0 }
            \\    }
            \\}
            \\
            \\impl _Need0 for UInt8 {
            \\    fn _value(self: UInt8) -> UInt8 {
            \\        self
            \\    }
            \\}
            \\
            \\trait _Argument[phantom I] {}
            \\
            \\impl _Argument[UInt8] for Bool {}
            \\
            \\impl _Argument[UInt8] for UInt8 {}
            \\
            \\
        );
        for (1..4) |i| {
            try w.print("trait _Need{d} {{}}\n\n", .{i});
            try w.print("impl _Need{d} for UInt8 {{}}\n\n", .{i});
            try w.print("impl _Need{d} for Bool {{}}\n\n", .{i});
        }

        try w.writeAll("trait _Structural {\n    fn _structural[");
        for (0..shape.member_parameters) |i| {
            if (i != 0) try w.writeAll(", ");
            const parameter = @as(u8, 'A') + @as(u8, @intCast(i));
            try w.print("{c}: _Need0", .{parameter});
            if (shape.bounds_per_member_parameter == 2) try w.print(" + _Argument[{c}]", .{parameter});
        }
        try w.writeAll("](self: Self");
        for (0..shape.member_parameters) |i| {
            try w.print(", _member{d}: {c}", .{ i, @as(u8, 'A') + @as(u8, @intCast(i)) });
        }
        try w.writeAll(") -> UInt8\n}\n\ntemplate impl _Structural\nwhere\n");
        try w.writeAll(" ");
        for (0..shape.component_predicates) |predicate| {
            if (predicate != 0) try w.writeAll(", ");
            try w.writeAll("reflect.components: ");
            for (0..shape.bounds_per_predicate) |bound| {
                if (bound != 0) try w.writeAll(" + ");
                try w.writeAll(if (bound == 0) "_Need0" else "_Argument[UInt8]");
            }
        }
        try w.writeAll("\n{\n    fn _structural[");
        for (0..shape.member_parameters) |i| {
            if (i != 0) try w.writeAll(", ");
            const parameter = @as(u8, 'X') + @as(u8, @intCast(i));
            try w.print("{c}: _Need0", .{parameter});
            if (shape.bounds_per_member_parameter == 2) try w.print(" + _Argument[{c}]", .{parameter});
        }
        try w.writeAll("](_self: Self");
        for (0..shape.member_parameters) |i| {
            try w.print(", _member{d}: {c}", .{ i, @as(u8, 'X') + @as(u8, @intCast(i)) });
        }
        try w.writeAll(
            \\) -> UInt8 {
            \\        var total: UInt8 = 0
            \\        match read _self {
            \\            reflect.case => {
            \\                for component in reflect.components
        );
        if (shape.reverse_components) try w.writeAll(".reversed");
        try w.writeAll(
            \\ {
            \\                    total = total * 10 + component.of(_self)._value()
            \\                }
            \\            },
            \\        }
            \\        total
            \\    }
            \\}
            \\
            \\trait _StructuralMarker {}
            \\
            \\template impl _StructuralMarker {}
            \\
            \\struct _StructuralTarget[
        );
        for (0..shape.generic_parameters) |i| {
            try w.print("{s}{s}{c}", .{
                if (i == 0) "" else ", ",
                if (i == 0) "" else "phantom ",
                @as(u8, 'A') + @as(u8, @intCast(i)),
            });
        }
        try w.writeAll("] { first: A, second: Bool }\n\n");

        try w.writeAll("derive[");
        for (0..shape.generic_parameters) |i| {
            if (i != 0) try w.writeAll(", ");
            try w.print("{c}", .{@as(u8, 'A') + @as(u8, @intCast(i))});
            if (i == 0) {
                try w.writeAll(": _Need0 + _Argument[UInt8]");
                if (shape.inline_bounds == 3) try w.writeAll(" + _Need1");
            }
        }
        try w.writeAll("] (\n    _Structural,\n");
        if (shape.group_entries == 2) try w.writeAll("    _StructuralMarker,\n");
        try w.writeAll(") for _StructuralTarget[");
        for (0..shape.generic_parameters) |i| {
            try w.print("{s}{c}", .{ if (i == 0) "" else ", ", @as(u8, 'A') + @as(u8, @intCast(i)) });
        }
        try w.writeAll("]");
        if (shape.trailing_predicates != 0) {
            try w.writeAll(" where ");
            for (0..shape.trailing_predicates) |predicate| {
                if (predicate != 0) try w.writeAll(", ");
                const parameter = predicate % shape.generic_parameters;
                try w.print("{c}: _Need{d}", .{
                    @as(u8, 'A') + @as(u8, @intCast(parameter)),
                    predicate + 2,
                });
            }
        }
        try w.writeAll(
            \\
            \\
            \\fn _acceptStructuralMarker[T: _StructuralMarker](_value: T) -> UInt8 {
            \\    0
            \\}
            \\
            \\
        );
    }

    /// Writes the trait, the types that implement it, and one function per
    /// operation written against the bound.
    fn traitDeclarations(self: *Gen, w: *std.Io.Writer, shape: TraitShape) Error!void {
        _ = self;
        const conv = shape.convention.parameterPrefix();

        try w.writeAll("trait _Measure {\n");
        // A type the trait declares and every implementation settles, read in
        // the signature below as `Self.Item` and off the bound as `T.Item`.
        // The operations answering `UInt8` are left alone: what says which
        // body ran is the number one answers with, and a name settled two ways
        // has no one number to be.
        try w.writeAll("    type Item\n");
        for (0..shape.ops) |j| {
            try w.print("    fn of{d}({s}x: Self) -> UInt8\n", .{ j, conv });
        }
        try w.print("    fn item({s}x: Self) -> Self.Item\n", .{conv});
        try w.writeAll("}\n\n");

        for (0..shape.impls) |i| {
            try w.print("struct _M{d} {{", .{i});
            for (0..shape.fields[i]) |f| {
                try w.print("{s} f{d}: UInt8", .{ if (f == 0) "" else ",", f });
            }
            try w.writeAll(" }\n\n");
        }

        for (0..shape.impls) |i| {
            try w.print("impl _Measure for _M{d} {{\n", .{i});
            try w.print("    type Item = {s}\n\n", .{shape.items[i].spelling()});
            switch (shape.items[i]) {
                // The concrete field is a scalar snapshot.
                .u8_ => try w.print(
                    "    fn item({s}x: Self) -> Self.Item {{ x.f{d} }}\n",
                    .{ conv, shape.item_answers[i] },
                ),
                // A comparison rather than a field, because a `Bool` is what
                // this implementation settled and no field holds one -- which
                // is the point: the body answers the type its own settling
                // named and not the one another implementation named.
                .bool_ => try w.print(
                    "    fn item({s}x: Self) -> Self.Item {{ x.f{d} == {d} }}\n",
                    .{ conv, shape.item_answers[i], shape.itemAgainst(@intCast(i)) },
                ),
            }
            for (0..shape.ops) |j| {
                // Concrete numeric fields are read without moving their owner.
                try w.print("    fn of{d}({s}x: Self) -> UInt8 {{ x.f{d} }}\n", .{
                    j,
                    conv,
                    shape.answers[i][j],
                });
            }
            try w.writeAll("}\n\n");
        }

        // Written against the bound and answering what the bound declares, so
        // the return type is settled by the argument at each instantiation
        // rather than by anything written here.
        try w.print("fn _itemOf[T: _Measure]({s}v: T) -> T.Item {{\n", .{conv});
        try w.writeAll("    _Measure.item(v)\n");
        try w.writeAll("}\n\n");

        for (0..shape.ops) |j| {
            try w.print("fn _measured{d}[T: _Measure]({s}v: T) -> UInt8 {{\n", .{ j, conv });
            try w.print("    _Measure.of{d}(v)\n", .{j});
            try w.writeAll("}\n\n");
        }
    }

    /// Calls every operation on every implementing type, and makes the
    /// program's answer depend on each call having reached the right body.
    ///
    /// Reaches the trait both ways a trait operation is reached: through the
    /// bound, which monomorphises one body per implementing type, and written
    /// out on the trait itself.
    ///
    /// The comparison is what the two implementations are for. A call settles
    /// `Self` once, so a dispatch that always picked the first body would
    /// answer one of them correctly and every other one with a number from the
    /// wrong type -- and a program that bound the result to a name nothing
    /// reads would exit the same either way, which is a call made and nothing
    /// asked about it.
    fn traitGroup(self: *Gen, w: *std.Io.Writer, at: u32, shape: TraitShape) Error!void {
        var wrong: u32 = 1;
        for (0..shape.impls) |i| {
            for (0..shape.ops) |j| {
                const built = try self.name("t");
                const got = try self.name("t");

                // One value per call, because an operation that takes `Self`
                // consumes what it was handed and the next call needs its own.
                try indent(w, at);
                try w.print("let {s}: _M{d} = .{{", .{ built, i });
                for (0..shape.fields[i]) |f| {
                    try w.print("{s} f{d} = {d}", .{
                        if (f == 0) "" else ",",
                        f,
                        shape.value(@intCast(i), @intCast(f)),
                    });
                }
                try w.writeAll(" };\n");

                try indent(w, at);
                // Written out rather than through the bound, so the two
                // spellings of one call are both reached and a program answers
                // the same either way. Written out, an implementation and an
                // operation alternate between the trait's qualified call and
                // the receiver's postfix call, which is what puts a postfix
                // call under the rewrites.
                if (self.choices.odds(2)) {
                    if ((i + j) % 2 == 1) {
                        try w.print("let {s}: UInt8 = {s}.of{d}();\n", .{ got, built, j });
                    } else {
                        try w.print("let {s}: UInt8 = _Measure.of{d}({s});\n", .{ got, j, built });
                    }
                } else {
                    try w.print("let {s}: UInt8 = _measured{d}({s});\n", .{ got, j, built });
                }

                try indent(w, at);
                try w.print("if {s} != {d} {{ return {d}; }}\n", .{
                    got,
                    shape.answer(@intCast(i), @intCast(j)),
                    wrong,
                });
                wrong += 1;
            }

            // The declared type, reached the same two ways and named at the
            // binding: what `_itemOf` answers is settled by this argument, so
            // an annotation naming the other implementation's settling is a
            // program that does not check. Named apart from the calls above,
            // because what a `Bool` answers is not a number and the tens digit
            // is what says which body a number came from.
            const holds = try self.name("i");
            const item = try self.name("i");

            try indent(w, at);
            try w.print("let {s}: _M{d} = .{{", .{ holds, i });
            for (0..shape.fields[i]) |f| {
                try w.print("{s} f{d} = {d}", .{
                    if (f == 0) "" else ",",
                    f,
                    shape.value(@intCast(i), @intCast(f)),
                });
            }
            try w.writeAll(" };\n");

            // Both spellings of one call, by position rather than by a coin
            // for the reason the settling is: two implementations is the
            // fewest a trait here has, so both are reached in every program
            // that declares one.
            //
            // Offset by how many operations the trait declares, which is drawn
            // and is nothing the settling reads. Keyed on the position alone,
            // the bound-headed call would be made at the odd implementations
            // and only ever at the settling those carry -- so the one thing
            // this exists to reach would meet one of the two types and never
            // the other.
            try indent(w, at);
            if ((i + shape.ops) % 2 == 0) {
                try w.print("let {s}: {s} = _Measure.item({s});\n", .{
                    item,
                    shape.items[i].spelling(),
                    holds,
                });
            } else {
                try w.print("let {s}: {s} = _itemOf({s});\n", .{
                    item,
                    shape.items[i].spelling(),
                    holds,
                });
            }

            try indent(w, at);
            switch (shape.items[i]) {
                .u8_ => try w.print("if {s} != {d} {{ return {d}; }}\n", .{
                    item,
                    shape.itemField(@intCast(i)),
                    wrong,
                }),
                .bool_ => try w.print("if {s} != {s} {{ return {d}; }}\n", .{
                    item,
                    if (shape.item_hits[i]) "true" else "false",
                    wrong,
                }),
            }
            wrong += 1;
        }
    }

    /// The module's constants, read where a literal of their type would stand.
    ///
    /// Both of them, and in one expression: what distinguishes a constant from
    /// the literal it was written as is that a name reaches it, and the second
    /// constant's own initialiser reached the first -- so the value arriving
    /// here has crossed a name twice.
    ///
    /// The same bytes however the stream falls, so the group draws nothing
    /// from it and every axis drawn after keeps the phase it had.
    ///
    /// A borrow of the second reads it through its static storage, which is
    /// the one way a program reaches a constant's address.
    fn constantGroup(self: *Gen, w: *std.Io.Writer, at: u32) Error!void {
        const n = try self.name("k");
        const view = try self.name("constant_view");
        const read = try self.name("k");
        try indent(w, at);
        try w.print("let {s}: UInt8 = _k0 + _k1;\n", .{n});
        try indent(w, at);
        try w.print("let {s} = borrow _k1;\n", .{view});
        try indent(w, at);
        try w.print("let {s}: UInt8 = *{s};\n", .{ read, view });
    }

    /// One function per tuple group, each returning a pair of `ItemType`s.
    ///
    /// Written before `main`, which calls them, and drawn from the side stream
    /// so no other axis changes phase.
    fn tupleFunctions(self: *Gen, w: *std.Io.Writer) Error!void {
        std.mem.swap(Choices, &self.choices, &self.side);
        defer std.mem.swap(Choices, &self.choices, &self.side);

        for (0..self.opts.max_tuples) |k| {
            const returns: [2]ItemType = .{ self.itemType(), self.itemType() };
            try self.tuple_returns.append(self.gpa, returns);

            self.scope.clear();
            self.marked.clearRetainingCapacity();
            try w.print("fn _tuple{d}() -> ({s}, {s}) {{\n    ", .{ k, returns[0].spelling(), returns[1].spelling() });
            try self.tupleLiteral(w, returns, 0);
            try w.writeAll("\n}\n\n");
        }
    }

    fn itemType(self: *Gen) ItemType {
        return if (self.choices.odds(2)) .u8_ else .bool_;
    }

    /// A pair literal whose components are generated expressions of `types`.
    ///
    /// Each `UInt8` component is written as a conversion, because a tuple
    /// literal passes no expected type to its components and a bare literal
    /// there would settle to the default integer instead.
    fn tupleLiteral(self: *Gen, w: *std.Io.Writer, types: [2]ItemType, visible: u32) Error!void {
        const was = self.enter(.consuming);
        defer self.position = was;
        try w.writeAll("(");
        for (types, 0..) |ty, i| {
            if (i > 0) try w.writeAll(", ");
            switch (ty) {
                .u8_ => {
                    try w.writeAll("UInt8(");
                    try self.expr(w, .u8_, 1, visible, .yes);
                    try w.writeAll(")");
                },
                .bool_ => try self.expr(w, .bool_, 1, visible, .yes),
            }
        }
        try w.writeAll(")");
    }

    /// A pair literal taken apart by a pattern, and the pair a function
    /// returns taken apart by another, each binder then read once.
    ///
    /// A component is discarded with `_` only where it is `UInt8` or `Bool`,
    /// which every `ItemType` is: a linear component bound to `_` would be
    /// [O-Leak].
    fn tupleGroup(self: *Gen, w: *std.Io.Writer, at: u32, k: u32, visible: u32) Error!void {
        std.mem.swap(Choices, &self.choices, &self.side);
        defer std.mem.swap(Choices, &self.choices, &self.side);
        self.marked.clearRetainingCapacity();

        const literal: [2]ItemType = .{ self.itemType(), self.itemType() };
        try self.tupleDestructure(w, at, literal, visible, null);
        try self.tupleDestructure(w, at, self.tuple_returns.items[k], visible, k);
    }

    /// `let (a, b) = <pair>;` and a `let` per kept binder reading it back.
    /// The pair is the literal written here, or the call of `_tuple{k}`.
    fn tupleDestructure(self: *Gen, w: *std.Io.Writer, at: u32, types: [2]ItemType, visible: u32, call: ?u32) Error!void {
        var binders: [2][]const u8 = undefined;
        for (&binders) |*b| b.* = if (self.choices.odds(3)) "_" else try self.name("t");

        try indent(w, at);
        try w.print("let ({s}, {s}) = ", .{ binders[0], binders[1] });
        if (call) |k| {
            try w.print("_tuple{d}()", .{k});
        } else {
            try self.tupleLiteral(w, types, visible);
        }
        try w.writeAll(";\n");

        for (binders, types) |binder, ty| {
            if (std.mem.eql(u8, binder, "_")) continue;
            try indent(w, at);
            try w.print("let {s}: {s} = {s};\n", .{ try self.name("t"), ty.spelling(), binder });
        }
    }

    fn callableGroup(self: *Gen, w: *std.Io.Writer, at: u32) Error!void {
        const closure = try self.name("closure");
        const direct = try self.name("called");
        const pointer = try self.name("pointer");
        const indirect = try self.name("called");

        try indent(w, at);
        try w.print("let {s} = |value: UInt8| value;\n", .{closure});
        try indent(w, at);
        try w.print("let {s}: UInt8 = {s}(3);\n", .{ direct, closure });
        try indent(w, at);
        try w.print("let {s}: fn(read value: UInt8) -> UInt8 = |value: UInt8| value;\n", .{pointer});
        try indent(w, at);
        try w.print("let {s}: UInt8 = {s}(4);\n", .{ indirect, pointer });
    }

    fn observationGroup(self: *Gen, w: *std.Io.Writer, at: u32) Error!void {
        const owner = try self.name("observed_owner");
        const view = try self.name("view");
        const value = try self.name("observed_value");
        try indent(w, at);
        try w.print("let {s}: UInt8 = 7;\n", .{owner});
        try indent(w, at);
        try w.print("let {s} = borrow {s};\n", .{ view, owner });
        try indent(w, at);
        try w.print("let {s}: UInt8 = *{s};\n", .{ value, view });
    }

    /// A copy made through a borrow of a structure that holds a borrow, then a
    /// write to the structure, then a read of the copy.
    ///
    /// The copy is a value of its own: it holds the borrow stored in the
    /// structure and nothing of the borrow it was copied through, so the
    /// write leaves it readable.
    ///
    /// The same bytes however the stream falls, and names no generated one, so
    /// the group draws nothing and every axis drawn after keeps the phase it
    /// had.
    fn pinnedCopyGroup(w: *std.Io.Writer, at: u32) Error!void {
        const lines = [_][]const u8{
            "var _pin = Pin { cell = borrow _k1, tag = 1 };\n",
            "let _pin_view = borrow _pin;\n",
            "let _pin_copy = copy(*_pin_view);\n",
            "_pin.tag = 2;\n",
            "let _pinned: UInt8 = *_pin_copy.cell + _pin_copy.tag + _pin.tag;\n",
        };
        for (lines) |line| {
            try indent(w, at);
            try w.writeAll(line);
        }
    }

    /// A value of the unit type, and a generic holding one.
    ///
    /// The second line is what this exists for. A part of no width is still a
    /// part: it is placed by [L-Layout], it is written when the value holding
    /// it is built, and it is read when the value is taken apart -- and every
    /// one of those is arithmetic on a size that no other program in the suite
    /// ever makes zero.
    ///
    /// The enum's constructor rather than the generic function: a constructor
    /// lets inference settle the argument inside an ordinary function, where
    /// calling `gid` would monomorphise one and put the argument's spelling
    /// into the symbol it emits.
    fn unitGroup(self: *Gen, w: *std.Io.Writer, at: u32) Error!void {
        const nothing = try self.name("u");
        try indent(w, at);
        try w.print("let {s} = _nothing();\n", .{nothing});

        if (!self.generic) return;

        const boxed = try self.name("u");
        const seen = try self.name("u");
        const carried = try self.name("w");
        try indent(w, at);
        try w.print("let {s} = GE.Just(_nothing());\n", .{boxed});

        // Annotated, because a `match` with no expected type answers the type
        // an unannotated literal takes and the arms below are written as
        // literals.
        try indent(w, at);
        try w.print("let {s}: UInt8 = match {s} {{ Nothing => {d}, Just({s}) => {d} }};\n", .{
            seen,
            boxed,
            self.choices.below(10),
            carried,
            self.choices.below(10),
        });
    }

    /// A family instantiated at two arguments and asked the same question at
    /// each.
    ///
    /// `impl[P] GHeld for GP[P]` stands for every `GP` there is, and which
    /// member a call reaches is settled by the receiver -- so two arguments is
    /// the fewest that says the head was bound from one rather than assumed.
    /// What each call answers is a field of a settled type, which is what makes
    /// the answer a number this can compare.
    ///
    /// The same bytes however the stream falls, for the reason the constants
    /// are: the group draws nothing, so every axis drawn after it keeps the
    /// phase it had.
    fn familyGroup(self: *Gen, w: *std.Io.Writer, at: u32) Error!void {
        const first = try self.name("h");
        const second = try self.name("h");
        const answer = try self.name("h");

        try indent(w, at);
        try w.print("let {s}: GP[UInt8] = .{{ n = 7 }};\n", .{first});
        try indent(w, at);
        try w.print("let {s}: GP[Bool] = .{{ n = 9 }};\n", .{second});
        try indent(w, at);
        try w.print("let {s}: UInt8 = GHeld.held({s}) + GHeld.held({s});\n", .{
            answer,
            first,
            second,
        });
        try indent(w, at);
        try w.print("if {s} != 16 {{ return 251; }}\n", .{answer});
    }

    fn structuralGroup(self: *Gen, w: *std.Io.Writer, at: u32, shape: StructuralShape) Error!void {
        const value = try self.name("d");
        const answer = try self.name("d");
        try indent(w, at);
        try w.print("let {s}: _StructuralTarget[", .{value});
        for (0..shape.generic_parameters) |i| {
            try w.writeAll(if (i == 0) "UInt8" else ", UInt8");
        }
        try w.writeAll("] = .{ first = 2, second = true };\n");
        try indent(w, at);
        try w.print("let {s}: UInt8 = _Structural._structural({s}", .{ answer, value });
        for (0..shape.member_parameters) |_| try w.writeAll(", UInt8(0)");
        try w.writeAll(");\n");
        try indent(w, at);
        const expected: u32 = if (shape.reverse_components) 12 else 21;
        try w.print("if {s} != {d} {{ return 250; }}\n", .{ answer, expected });
        if (shape.group_entries == 2) {
            try indent(w, at);
            try w.print("let _ = _acceptStructuralMarker({s});\n", .{value});
        }
    }

    /// Constructs `N0` twice, from a literal the declared refinement is
    /// proven to accept, and destructures each through the form its
    /// declaration beside it did not yet reach -- `let` for one, `match`
    /// for the other, so both are exercised together rather than one always
    /// standing in for the pair.
    fn newtypeGroup(self: *Gen, w: *std.Io.Writer, at: u32) Error!void {
        const via_let = try self.name("m");
        try indent(w, at);
        try w.print("let {s}: N0 = N0({d});\n", .{ via_let, self.choices.below(100) });
        try indent(w, at);
        try w.print("let {s}: UInt8 = _fromNewtype({s});\n", .{ try self.name("m"), via_let });

        const via_match = try self.name("m");
        try indent(w, at);
        try w.print("let {s}: N0 = N0({d});\n", .{ via_match, self.choices.below(100) });
        try indent(w, at);
        try w.print("let {s}: UInt8 = _fromNewtypeMatch({s});\n", .{ try self.name("m"), via_match });

        // One value read apart through a `read` parameter and then taken
        // apart, so the owner a `let read` lent from is still whole afterwards.
        // Its literal is fixed rather than drawn, so the choices every later
        // construct draws are independent of this form.
        const via_read = try self.name("m");
        try indent(w, at);
        try w.print("let {s}: N0 = N0(42);\n", .{via_read});
        try indent(w, at);
        try w.print("let {s}: UInt8 = _fromNewtypeRead({s});\n", .{ try self.name("m"), via_read });
        try indent(w, at);
        try w.print("let {s}: UInt8 = _fromNewtype({s});\n", .{ try self.name("m"), via_read });
    }

    /// A `UInt8` it already writes, matched by two range arms that cover the
    /// type with no `_` -- the case the representation was chosen for.
    ///
    /// A range as a *value* is a construction of `Range[T]`, identified
    /// through the prelude the way `Option` and `Result` are;
    /// this generator names no library declaration, so nothing it writes can name
    /// that declaration -- the same reason `.str_literal` and `.interp` stay
    /// out of reach. A range *pattern* asks nothing of the prelude: its bound
    /// is checked the way a literal arm's is, which is what a covering match
    /// can reach on its own. Split at a drawn point so both spellings appear
    /// together, `..` on the low arm and `..=` on the high one.
    fn rangeGroup(self: *Gen, w: *std.Io.Writer, at: u32) Error!void {
        const scrutinee = try self.name("g");
        try indent(w, at);
        try w.print("let {s}: UInt8 = ", .{scrutinee});
        {
            const was = self.enter(.consuming);
            defer self.position = was;
            try self.leaf(w, .u8_, .yes);
        }
        try w.writeAll(";\n");

        const mid = self.choices.between(1, 255);
        const covered = try self.name("g");
        try indent(w, at);
        try w.print("let {s}: UInt8 = match {s} {{ 0..{d} => 1, {d}..=255 => 2 }};\n", .{
            covered,
            scrutinee,
            mid,
            mid,
        });
    }

    /// A walk over places the compiler itself carries, in all three forms.
    ///
    /// An array and not a range. A walk through `Sequence` reaches the
    /// prelude's declaration and a range as a value reaches `Range`, and this
    /// generator checks without a library -- but an array's places are the
    /// language's own: what a walk over one yields is settled by the type, and
    /// the lending forms find their positions and their projection in the
    /// compiler rather than in a `trav` and a `proj` somebody wrote. So the
    /// three loop forms are reachable here and a range walk is not, for the
    /// same reason a range value is not.
    ///
    /// The array is written here and never pushed into scope, which is what
    /// keeps every form legal by construction. A consuming walk takes it, so a
    /// later statement naming it would name what is gone; a lending one holds
    /// it lent for the whole body, so a statement inside that reached it would
    /// be the second reach into one value. Both are rules about what *else*
    /// names the value, and this generator tracks what is in scope rather than
    /// what it has consumed -- so nothing else may name it at all.
    ///
    /// The binder is in scope, because a walk whose body cannot read what it
    /// was handed exercises the loop and nothing about the element. It is
    /// assignable exactly where the walk lends writably, which is the one form
    /// whose binder is a place a write may reach.
    fn walkGroup(self: *Gen, w: *std.Io.Writer, visible: u32, at: u32) Error!void {
        const walked = self.anArray();
        const held = try self.name("w");
        const binder = try self.name("e");

        // The three forms, drawn evenly: each is its own rule about what the
        // binder is -- a value the walk hands over, a place it lends, or a
        // place it lends writably -- and a form drawn rarely is a form the
        // fixed-seed run can miss entirely.
        const writes = self.choices.below(3);
        const form: []const u8 = switch (writes) {
            0 => "",
            1 => "read ",
            else => "inout ",
        };

        try indent(w, at);
        // `var` where the walk writes through what it lends: a lend that
        // writes needs a place the program may write to, and a `let` is not
        // one.
        try w.print("{s} {s}: {s} = ", .{ if (writes == 2) "var" else "let", held, self.spell(walked) });
        {
            const was = self.enter(.consuming);
            defer self.position = was;
            try self.leaf(w, walked, .yes);
        }
        try w.writeAll(";\n");

        try indent(w, at);
        try w.print("for {s}{s} in {s} {{\n", .{ form, binder, held });

        const mark = self.scope.mark();
        try self.scope.push(.{
            .name = binder,
            .ty = walked.array.element(),
            .mutable = writes == 2,
            .frozen = false,
            .depth = at + 1,
        });
        // Non-empty until the bound and empty at it, exactly as the `while`
        // production is: the loop runs over what the array holds whatever the
        // stream says, so nesting is what has to stop rather than iteration.
        const inner = if (at < self.opts.max_nesting) self.choices.between(1, 3) else 0;
        for (0..inner) |_| {
            try self.statement(w, visible, at + 1, true);
        }
        self.scope.shrinkTo(mark);

        try indent(w, at);
        try w.writeAll("}\n");
    }

    /// The scalars, in a fixed order so a choice byte means the same thing
    /// whatever else the program declared.
    const scalars = [_]Ty{ .u8_, .i8_, .i64_, .bool_, .f64_ };

    /// What an integer comparison's operands may be. `Bool` compares only
    /// for equality and is exercised by the logical productions; a float
    /// comparison is its own production, drawn before this table is read.
    const comparable = [_]Ty{ .u8_, .i8_, .i64_ };

    fn anyType(self: *Gen) Ty {
        // An array among them, so a parameter, a binding and a return type all
        // reach one -- which is what puts the whole property machinery over
        // arrays rather than only the cases somebody wrote by hand.
        // One in sixteen, doubled from one in thirty-two when the float
        // forms joined the stream: every type the pool gains dilutes the
        // rest, and an array in scope is what the index expression and its
        // checked access are reached through -- at the old share a fixed
        // seed's four hundred programs could hold none at all.
        if (self.choices.odds(16)) return self.anArray();

        const n: u32 = @intCast(scalars.len + self.enums.items.len + self.structs.items.len);
        const pick = self.choices.below(n);
        if (pick < scalars.len) return scalars[pick];

        const declared = pick - @as(u32, @intCast(scalars.len));
        if (declared < self.enums.items.len) return .{ .enum_ = declared };
        return .{ .struct_ = declared - @as(u32, @intCast(self.enums.items.len)) };
    }

    /// An array of a scalar.
    ///
    /// At least one element: an empty one is a type with nothing to index and
    /// no element to say what it holds, which is its own case rather than
    /// something to meet by accident in a generated program.
    fn anArray(self: *Gen) Ty {
        const of: Ty.Scalar = switch (self.choices.below(4)) {
            0 => .u8_,
            1 => .i8_,
            2 => .i64_,
            else => .bool_,
        };
        return .{ .array = .{ .of = of, .count = 1 + self.choices.below(3) } };
    }

    /// A scalar, or any type already declared.
    ///
    /// Choosing from what came before is the whole of the acyclicity argument:
    /// a type can only hold something older than itself.
    fn aType(self: *Gen, declared: []const Ty) Ty {
        if (declared.len > 0 and self.choices.odds(3)) {
            return declared[self.choices.below(@intCast(declared.len))];
        }
        return if (self.choices.odds(3)) .bool_ else .u8_;
    }

    fn spell(self: *Gen, ty: Ty) []const u8 {
        return switch (ty) {
            .u8_ => "UInt8",
            .i8_ => "Int8",
            .i64_ => "Int64",
            .f64_ => "Float64",
            .bool_ => "Bool",
            // Two enums are as many as the options allow, so their spellings
            // are constants rather than another allocation per parameter.
            .enum_ => |i| if (i == 0) "E0" else "E1",
            .struct_ => |i| if (i == 0) "S0" else "S1",
            .held => |i| self.spellings.items[i],
            // Built rather than a constant: the count varies, so there is no
            // fixed set of spellings the way there is for two enums.
            .array => |a| std.fmt.allocPrint(
                self.gpa,
                "[{s}; {d}]",
                .{ self.spell(a.element()), a.count },
            ) catch @panic("OOM"),
        };
    }

    /// Declares the generic structure and records an instantiation of it.
    ///
    /// One declaration however many instantiations: what is being exercised is
    /// substitution, and a second generic type would repeat it rather than add
    /// to it.
    fn instantiate(self: *Gen, arg: Ty) !Ty {
        for (self.held.items, 0..) |a, i| {
            if (a.eql(arg)) return .{ .held = @intCast(i) };
        }
        const i = self.held.items.len;
        try self.held.append(self.gpa, arg);
        try self.spellings.append(self.gpa, try std.fmt.allocPrint(self.gpa, "G[{s}]", .{self.spell(arg)}));
        return .{ .held = @intCast(i) };
    }

    fn body(
        self: *Gen,
        w: *std.Io.Writer,
        ret: Ty,
        visible: u32,
        opens: []const Ty,
        is_entry: bool,
    ) Error!void {
        const mark = self.scope.mark();
        defer self.scope.shrinkTo(mark);

        try w.writeAll("{\n");

        // Once here for certain, so the linear type and the two functions
        // over it are named by something. `main` is the one body sure to
        // exist, and [N-Unused] holds a declaration nothing reaches to
        // account exactly as it holds a binding.
        if (is_entry and self.linear) try self.linearGroup(w, 1, true);
        if (is_entry) {
            if (self.traits) |shape| try self.traitGroup(w, 1, shape);
        }

        // And once for the unit type, for the same reason: `_nothing` is
        // declared only where this runs, and a declaration nothing reaches is
        // a program the compiler refuses.
        if (is_entry and self.unit) try self.unitGroup(w, 1);

        // And once for the family, which is what makes the implementation
        // generic over its head a thing a call reaches rather than a
        // declaration the program carries.
        if (is_entry and self.generic) try self.familyGroup(w, 1);

        if (is_entry) {
            if (self.structural) |shape| try self.structuralGroup(w, 1, shape);
        }

        // And once for the constants, which is what makes them a value a
        // program reads rather than a declaration it carries: a name standing
        // where a literal of its type would.
        if (is_entry) try self.constantGroup(w, 1);

        // Both static callable forms, in the one body every generated program
        // has. The first keeps its unique closure type and calls directly; the
        // second converts to a structural pointer and calls indirectly. Fixed
        // rather than drawn so every sampled run reaches both representation
        // tags without re-phasing the choices that generate the rest.
        if (is_entry) try self.callableGroup(w, 1);
        if (is_entry) try self.observationGroup(w, 1);
        if (is_entry) try pinnedCopyGroup(w, 1);
        if (is_entry) for (0..self.tuple_returns.items.len) |k| try self.tupleGroup(w, 1, @intCast(k), visible);

        // And once for the newtype, for the same reason: `_fromNewtype`,
        // `_fromNewtypeMatch` and `_fromNewtypeRead` are declared only where
        // this runs.
        if (is_entry and self.newtype) try self.newtypeGroup(w, 1);

        // A binding whose annotation names a type, so every declared type is
        // named by something. Without this a generated program could declare
        // an enum nothing mentions, and the only way to keep that accepted
        // would be to exempt the name -- which is what put [N-Unused] beyond
        // the generator's reach for as long as every name it wrote began with
        // an underscore.
        for (opens) |ty| {
            const n = try self.name("u");
            try indent(w, 1);
            // `var`, so every declared type has somewhere a parameter written
            // back through can write to. Without one, a function taking an
            // `inout` of a declared type was declared and never called.
            try w.print("var {s}: {s} = ", .{ n, self.spell(ty) });
            // A binding takes its initialiser, here as anywhere else. This
            // loop writes the same statement the `let` production does and
            // was the one place that did not say so, so a part named inside
            // one of these was written without the `copy` that lifts it out.
            {
                const was = self.enter(.consuming);
                defer self.position = was;
                try self.expr(w, ty, self.opts.max_depth, visible, .yes);
            }
            try w.writeAll(";\n");
            try self.scope.push(.{
                .name = n,
                .ty = ty,
                .mutable = true,
                .frozen = false,
                .depth = 1,
            });
        }

        for (0..self.choices.below(self.opts.max_statements + 1)) |_| {
            try self.statement(w, visible, 1, false);
        }

        // Leaving early, under a condition. Unconditionally would make
        // everything after it unreachable, and the generator would have to
        // stop emitting there -- a rule about what follows rather than about
        // `return`, and one this does not need to learn.
        if (self.choices.odds(4)) {
            try indent(w, 1);
            try w.writeAll("if ");
            try self.expr(w, .bool_, 1, visible, .yes);
            try w.writeAll(" { return ");
            {
                const was = self.enter(.consuming);
                defer self.position = was;
                try self.expr(w, ret, 1, visible, .yes);
            }
            try w.writeAll("; }\n");
        }

        try w.writeAll("    ");
        self.marked.clearRetainingCapacity();
        {
            const was = self.enter(.consuming);
            defer self.position = was;
            try self.expr(w, ret, self.opts.max_depth, visible, .yes);
        }
        try w.writeAll("\n}");
    }

    fn indent(w: *std.Io.Writer, depth: u32) Error!void {
        for (0..depth) |_| try w.writeAll("    ");
    }

    fn statement(self: *Gen, w: *std.Io.Writer, visible: u32, at: u32, in_loop: bool) Error!void {
        // Exclusivity holds within one expression. What the last statement
        // marked constrains nothing here.
        self.marked.clearRetainingCapacity();

        const assignable = try self.scope.assignableCount();

        // Which productions are available here rather than arithmetic on a
        // count: `continue` needs a loop to continue and an assignment needs
        // something it may assign, and a choice that lands on one that is not
        // available has to mean something rather than fall through to whatever
        // the last case happens to be.
        var available: [12]u8 = undefined;
        var count: usize = 0;
        for ([_]u8{ 0, 1, 2, 3, 4, 10, 11 }) |k| {
            available[count] = k;
            count += 1;
        }
        if (in_loop) {
            available[count] = 5;
            count += 1;
        }
        // A linear value, wherever a statement may go -- including inside a
        // loop, where it is created and disposed of on every iteration. That
        // is legal precisely because the binding is declared inside the loop:
        // [O-Loop] refuses moving one declared outside it, and this one never
        // is.
        if (self.linear) {
            available[count] = 7;
            count += 1;
        }
        // Taking a structure apart, which needs one to exist.
        if (self.structs.items.len > 0) {
            available[count] = 8;
            count += 1;
        }
        // A value of no width, wherever a statement may go -- so the part it
        // becomes is laid out beside whatever the surrounding block declared,
        // rather than always in the same frame.
        if (self.unit) {
            available[count] = 9;
            count += 1;
        }
        if (assignable > 0) {
            available[count] = 6;
            count += 1;
        }

        switch (available[self.choices.below(@intCast(count))]) {
            // A binding, which later expressions may read.
            0, 1 => {
                const ty = self.anyType();
                // Sometimes a name already in use further out, which is what
                // shadowing is. Only from strictly further in: two bindings of
                // one name in one block is a redeclaration, not a shadow.
                const n = self.scope.outerName(&self.choices, at) orelse try self.name("v");
                // Any type, not only `UInt8`. A parameter written back through
                // needs a binding of its own type to write to, and while only
                // `UInt8` bindings could be assigned, the aggregate case of
                // `inout` was reachable by nothing.
                const mutable = self.choices.odds(2);
                try indent(w, at);
                try w.print("{s} {s}: {s} = ", .{ if (mutable) "var" else "let", n, self.spell(ty) });
                {
                    const was = self.enter(.consuming);
                    defer self.position = was;
                    try self.expr(w, ty, self.opts.max_depth, visible, .yes);
                }
                try w.writeAll(";\n");
                try self.scope.push(.{
                    .name = n,
                    .ty = ty,
                    .mutable = mutable,
                    .frozen = false,
                    .depth = at,
                });
            },
            // A value computed and thrown away, which is what `_` is for. The
            // annotation is not decoration: an arm, a break site and a
            // comparison's right operand are all settled by whatever came
            // first, so a construct in a position that expects nothing settles
            // itself, and a literal reaching that position first defaults to
            // the integer type and takes everything after it with it.
            2 => {
                const ty = self.anyType();
                try indent(w, at);
                try w.print("let _: {s} = ", .{self.spell(ty)});
                {
                    const was = self.enter(.consuming);
                    defer self.position = was;
                    try self.expr(w, ty, self.opts.max_depth, visible, .yes);
                }
                try w.writeAll(";\n");
            },
            // A loop that ends. The counter is decremented before anything
            // else runs, so a `continue` in the body cannot skip it.
            3 => {
                const n = try self.name("c");
                try indent(w, at);
                try w.print("var {s}: UInt8 = {d};\n", .{ n, self.choices.between(1, 4) });
                try indent(w, at);
                try w.print("while {s} != 0 {{\n", .{n});

                const mark = self.scope.mark();
                try self.scope.push(.{
                    .name = n,
                    .ty = .u8_,
                    .mutable = true,
                    .frozen = true,
                    .depth = at,
                });
                try indent(w, at + 1);
                try w.print("{s} = {s} - 1;\n", .{ n, n });
                // Non-empty until the bound, so nesting is reached rather
                // than merely possible; empty at it, so recursion stops
                // whatever the stream says next.
                const inner = if (at < self.opts.max_nesting) self.choices.between(1, 3) else 0;
                for (0..inner) |_| {
                    try self.statement(w, visible, at + 1, true);
                }
                self.scope.shrinkTo(mark);

                try indent(w, at);
                try w.writeAll("}\n");

                // The counter outlives the loop, and is no longer what ends it.
                try self.scope.push(.{
                    .name = n,
                    .ty = .u8_,
                    .mutable = true,
                    .frozen = false,
                    .depth = at,
                });
            },
            // A `loop` yields through `break`, so unlike a `while` it has a
            // value -- and its type is the one its break sites agree on rather
            // than anything written down. One break site, on a path the
            // counter is walking towards, so the loop ends.
            4 => {
                const n = try self.name("c");
                const v = try self.name("v");
                const ty = scalars[self.choices.below(scalars.len)];

                try indent(w, at);
                try w.print("var {s}: UInt8 = {d};\n", .{ n, self.choices.between(1, 4) });
                try indent(w, at);
                try w.print("let {s}: {s} = loop {{\n", .{ v, self.spell(ty) });

                try indent(w, at + 1);
                try w.print("if {s} == 0 {{ break ", .{n});
                {
                    const was = self.enter(.consuming);
                    defer self.position = was;
                    try self.leaf(w, ty, .yes);
                }
                try w.writeAll("; }\n");

                try indent(w, at + 1);
                try w.print("{s} = {s} - 1;\n", .{ n, n });
                try indent(w, at);
                try w.writeAll("};\n");

                try self.scope.push(.{ .name = n, .ty = .u8_, .mutable = true, .frozen = false, .depth = at });
                try self.scope.push(.{ .name = v, .ty = ty, .mutable = false, .frozen = false, .depth = at });
            },
            // `continue` begins the next iteration. The enclosing loop
            // decrements before anything else runs, so skipping the rest of
            // the body cannot stop it ending.
            5 => {
                try indent(w, at);
                try w.writeAll("if ");
                {
                    const was = self.enter(.reading);
                    defer self.position = was;
                    try self.expr(w, .bool_, 1, visible, .yes);
                }
                try w.writeAll(" { continue; }\n");
            },
            7 => try self.linearGroup(w, at, false),
            9 => try self.unitGroup(w, at),
            10 => try self.rangeGroup(w, at),
            11 => try self.walkGroup(w, visible, at),
            // A destructuring `let`, which is the terminal consumer of a
            // structure: the value is taken apart and what it held becomes
            // bindings of its own. Every structure the generator wrote until
            // now was read through its fields, so the whole of this path --
            // the pattern, the binders it declares, and the loads that fill
            // them -- was reached by the corpus alone.
            8 => {
                const i = self.choices.below(@intCast(self.structs.items.len));
                const def = self.structs.items[i];

                try indent(w, at);
                try w.print("let {s} {{", .{self.spell(.{ .struct_ = i })});

                var binders: [max_fields][]const u8 = undefined;
                for (0..def.count) |f| {
                    binders[f] = try self.name("d");
                    try w.print("{s} f{d}: {s}", .{ if (f == 0) "" else ",", f, binders[f] });
                }
                try w.writeAll(" } = ");

                // The initialiser is taken, so it is built here rather than
                // named: a place named where the value is taken would be a
                // move, and the generator does not track what it has consumed.
                {
                    const was = self.enter(.consuming);
                    defer self.position = was;
                    try self.expr(w, .{ .struct_ = i }, self.opts.max_depth, visible, .yes);
                }
                try w.writeAll(";\n");

                // What the structure held is now bindings in their own right,
                // so everything below may read them.
                for (0..def.count) |f| {
                    try self.scope.push(.{
                        .name = binders[f],
                        .ty = def.field[f],
                        .mutable = false,
                        .frozen = false,
                        .depth = at,
                    });
                }
            },
            // Assignment, which only a `var` that ends no loop admits.
            //
            // The target is a place rather than a name: writing to a field
            // computes an address the way reading one does, and a generator
            // that only ever replaced whole bindings never asked for one.
            else => {
                const target = try self.scope.nthAssignable(self.choices.below(assignable));

                var places: std.ArrayList(Path) = .empty;
                defer places.deinit(self.gpa);
                try self.pathsIn(target.ty, target.name, target.name, 0, &places);
                const place = places.items[self.choices.below(@intCast(places.items.len))];

                // A compound assignment wherever the place is a number, which
                // is the only place one is legal. The operand is generated
                // exactly as a plain assignment's value is: what differs is the
                // operator, and that the place is read as well as written.
                // A minority of them, so that plain assignments -- whose value
                // is a consuming position, and the supply the mutations that
                // perturb one draw on -- stay the common case.
                const op: []const u8 = if (place.ty.isInt()) switch (self.choices.below(16)) {
                    0 => "+=",
                    1 => "-=",
                    2 => "*=",
                    3 => "/=",
                    4 => "%=",
                    else => "=",
                } else "=";

                try indent(w, at);
                try w.print("{s} {s} ", .{ place.text, op });
                {
                    // A plain assignment takes its value; a compound one reads
                    // its operand, because that is what an operand of an
                    // operator is. Writing `copy` into a reading position is
                    // [O-CopyRead], so the generator has to know which it is
                    // building.
                    const was = self.enter(if (op.len == 1) .consuming else .reading);
                    defer self.position = was;
                    try self.expr(w, place.ty, self.opts.max_depth, visible, .yes);
                }
                try w.writeAll(";\n");
            },
        }
    }

    fn expr(self: *Gen, w: *std.Io.Writer, want: Ty, depth: u32, visible: u32, typed: Typed) Error!void {
        if (depth == 0) return self.leaf(w, want, typed);

        // Every production below yields `want`, so the choice is free and the
        // program cannot be ill-typed by taking any of them.
        switch (self.choices.below(6)) {
            0 => return self.leaf(w, want, typed),
            1 => {
                try w.writeAll("if ");
                {
                    const was = self.enter(.reading);
                    defer self.position = was;
                    try self.expr(w, .bool_, depth - 1, visible, typed);
                }
                try w.writeAll(" { ");
                try self.expr(w, want, depth - 1, visible, typed);
                try w.writeAll(" } else { ");
                try self.expr(w, want, depth - 1, visible, typed);
                try w.writeAll(" }");
            },
            2 => {
                if (self.pickCall(want, visible)) |f| blk: {
                    // A parameter written back through needs somewhere to
                    // write: a binding that may be assigned and does not end a
                    // loop. Where there is none the call cannot be written at
                    // all, so this falls back rather than emitting one.
                    // [N-Aliased]: a place passed `&` may not overlap any
                    // other argument's, whether that one is marked too or
                    // merely reads it. The names are recorded before any other
                    // argument is written, so nothing below can reach for one.
                    const before = self.marked.items.len;
                    defer self.marked.shrinkRetainingCapacity(before);

                    var marked: [3][]const u8 = undefined;
                    for (f.params, 0..) |p, i| {
                        if (!p.mutable) continue;
                        marked[i] = (try self.mutableOfType(p.ty)) orelse break :blk;
                    }

                    // An argument is read, not taken: only a `sink` parameter
                    // consumes one, and none exists to generate yet. A call
                    // written inside a consuming position would otherwise
                    // hand that position's rule down to arguments that do not
                    // have it.
                    const was = self.enter(.reading);
                    defer self.position = was;

                    // What the call leaves out, taken off the end. Every
                    // parameter dropped declares a default, so the call is
                    // still complete -- and stopping at the first that
                    // declares none is what keeps the omission a suffix,
                    // which is the only shape [S-Default] leaves meaningful.
                    // An `inout` parameter is never among them: it carries no
                    // default to be dropped in favour of.
                    var given = f.params.len;
                    while (given > 0 and f.defaults[given - 1] != null and self.choices.odds(2)) {
                        given -= 1;
                    }

                    // Where the names begin. Positional arguments form a
                    // prefix and every argument after a named one is named,
                    // so this one number decides the whole spelling and
                    // [S-Args] holds by construction: nothing here can write
                    // a positional argument after a name, which is a program
                    // the compiler refuses rather than one it disagrees with.
                    //
                    // Nothing is drawn where a call passes nothing: a choice
                    // taken and thrown away still moves every choice after
                    // it, so a decision that cannot matter is not made.
                    const names_from = if (given > 0 and self.choices.odds(2))
                        self.choices.below(@intCast(given))
                    else
                        given;

                    try w.print("{s}(", .{f.name});
                    for (f.params[0..given], 0..) |p, i| {
                        if (i > 0) try w.writeAll(", ");
                        // A parameter's own name, which is the only spelling a
                        // call may use for it. An `inout` argument is named
                        // like any other: what a name says is which parameter
                        // takes the value, and that is a question a convention
                        // has no part in.
                        if (i >= names_from) try w.print("{s}: ", .{p.name});

                        if (p.mutable) {
                            try w.print("&{s}", .{marked[i]});
                        } else if (p.ty == .enum_ and self.choices.odds(2)) {
                            // A parameter always supplies its argument's type,
                            // so the enum need not be named here.
                            try self.buildVariant(w, p.ty.enum_, .from_context);
                        } else {
                            try self.expr(w, p.ty, depth - 1, visible, typed);
                        }
                    }
                    try w.writeAll(")");
                    return;
                }
                return self.expr(w, want, depth - 1, visible, typed);
            },
            3 => {
                if (self.enums.items.len == 0) return self.expr(w, want, depth - 1, visible, typed);
                const e = self.choices.below(@intCast(self.enums.items.len));
                const def = self.enums.items[e];

                try w.writeAll("match ");
                // A scrutinee is the one enum position with no type imposed on
                // it: what a `match` is over is read off the expression, not
                // handed to it. So the enum has to be named here.
                {
                    const was = self.enter(.consuming);
                    defer self.position = was;
                    try self.expr(w, .{ .enum_ = e }, depth - 1, visible, .no);
                }
                try w.writeAll(" { ");
                for (0..def.count) |v| {
                    if (v > 0) try w.writeAll(", ");

                    // A binder is a binding for the arm and nowhere else, so
                    // it is pushed before the body and dropped after -- which
                    // is what puts it in reach of a leaf, and what keeps the
                    // arm beside it from naming something that is not there.
                    const mark = self.scope.mark();
                    defer self.scope.shrinkTo(mark);

                    if (def.payload[v]) |ty| {
                        const b = try self.name("b");
                        try w.print("_V{d}({s}) => ", .{ v, b });
                        try self.scope.push(.{
                            .name = b,
                            .ty = ty,
                            .mutable = false,
                            .depth = depth,
                            .frozen = false,
                        });
                    } else {
                        try w.print("_V{d} => ", .{v});
                    }
                    try self.expr(w, want, depth - 1, visible, typed);
                }
                try w.writeAll(" }");
            },
            else => return self.operator(w, want, depth, visible, typed),
        }
    }

    /// An operator yielding `want`, or a leaf where no operator does.
    ///
    /// Operands are kept small and a divisor is a literal: an operation that
    /// traps is a defined answer and a legitimate one to check, but a program
    /// that traps on its first operation says nothing about everything after
    /// it.
    fn operator(self: *Gen, w: *std.Io.Writer, want: Ty, depth: u32, visible: u32, typed: Typed) Error!void {
        switch (want) {
            // Not an operator at all, so the position it sits in is its own.
            .enum_, .struct_, .held, .array => return self.leaf(w, want, typed),
            .f64_ => {
                const was = self.enter(.reading);
                defer self.position = was;

                // No `%`: the language refuses it over a float. Nothing here
                // avoids a zero divisor either, because a float division is
                // defined for every operand and traps on none.
                switch (self.choices.below(4)) {
                    0 => {
                        try w.writeAll("(");
                        try self.expr(w, want, depth - 1, visible, typed);
                        try w.writeAll(" + ");
                        try self.floatLiteral(w);
                        try w.writeAll(")");
                    },
                    1 => {
                        try w.writeAll("(");
                        try self.expr(w, want, depth - 1, visible, typed);
                        try w.writeAll(" / ");
                        try self.floatLiteral(w);
                        try w.writeAll(")");
                    },
                    2 => {
                        try w.writeAll("(");
                        try self.expr(w, want, depth - 1, visible, typed);
                        try w.writeAll(" * ");
                        try self.floatLiteral(w);
                        try w.writeAll(")");
                    },
                    else => {
                        try w.writeAll("-(");
                        try self.floatLiteral(w);
                        try w.writeAll(")");
                    },
                }
            },
            .u8_, .i8_, .i64_ => {
                // An operand is observed, whatever position the operation as
                // a whole sits in.
                const was = self.enter(.reading);
                defer self.position = was;

                // Negation only where the type has negative values to reach.
                // On an unsigned one it is a trap for every operand but zero,
                // which says nothing about anything after it.
                const productions: u32 = if (want.isSigned()) 5 else 4;
                switch (self.choices.below(productions)) {
                    0 => {
                        try w.writeAll("(");
                        try self.expr(w, want, depth - 1, visible, typed);
                        try w.writeAll(" + ");
                        try w.print("{d})", .{self.choices.below(4)});
                    },
                    1 => {
                        try w.writeAll("(");
                        try self.expr(w, want, depth - 1, visible, typed);
                        try w.print(" / {d})", .{self.choices.between(1, 9)});
                    },
                    2 => {
                        try w.writeAll("(");
                        try self.expr(w, want, depth - 1, visible, typed);
                        try w.print(" * {d})", .{self.choices.below(3)});
                    },
                    3 => {
                        // A divisor away from zero, for the reason division's
                        // is: a remainder by zero traps, and a program that
                        // traps on its first operation says nothing about
                        // everything after it.
                        try w.writeAll("(");
                        try self.expr(w, want, depth - 1, visible, typed);
                        try w.print(" % {d})", .{self.choices.between(1, 9)});
                    },
                    else => {
                        // A small operand, so the negation cannot reach the
                        // one value whose negation does not fit.
                        try w.writeAll("-(");
                        try w.print("{d})", .{self.choices.below(9)});
                    },
                }
            },
            .bool_ => {
                // A logical operator, where there is depth left for one and
                // nothing here is being consumed.
                //
                // Its operands sit where the whole expression sits -- `a && b`
                // produces `b`'s value on the path that reaches it, exactly as
                // an `if` arm does -- so they are generated before the reading
                // position below is entered, and only where that position is
                // already reading. Generating one under a consuming position
                // would put a binding in a consuming position twice.
                if (depth > 1 and self.position == .reading) {
                    switch (self.choices.below(6)) {
                        0 => {
                            try w.writeAll("(!");
                            try self.expr(w, .bool_, depth - 1, visible, typed);
                            try w.writeAll(")");
                            return;
                        },
                        1, 2 => {
                            const op = if (self.choices.odds(2)) "&&" else "||";
                            try w.writeAll("(");
                            try self.expr(w, .bool_, depth - 1, visible, typed);
                            try w.print(" {s} ", .{op});
                            try self.expr(w, .bool_, depth - 1, visible, typed);
                            try w.writeAll(")");
                            return;
                        },
                        else => {},
                    }
                }

                const was = self.enter(.reading);
                defer self.position = was;

                const op = switch (self.choices.below(6)) {
                    0 => "==",
                    1 => "!=",
                    2 => "<",
                    3 => "<=",
                    4 => ">",
                    else => ">=",
                };

                // A float comparison, a minority of them: the integer ones
                // are what reaches `settledInt` and the array index inside
                // it, so they stay the common case. A float literal settles
                // itself -- it defaults to `Float64` where nothing flows in
                // -- so the left operand needs no settling expression the
                // way an integer's does.
                if (self.choices.odds(5)) {
                    try w.writeAll("(");
                    try self.floatLiteral(w);
                    try w.print(" {s} ", .{op});
                    try self.expr(w, .f64_, depth - 1, visible, typed);
                    try w.writeAll(")");
                    return;
                }

                const of = comparable[self.choices.below(comparable.len)];
                try w.writeAll("(");
                try self.settledInt(w, of, depth - 1, visible);
                try w.print(" {s} ", .{op});
                try self.expr(w, of, depth - 1, visible, typed);
                try w.writeAll(")");
            },
        }
    }

    /// A float literal, in one of the spellings the lexer admits: a point,
    /// an exponent, or both. The exponent stays small so every value is
    /// finite, and a seventeen-digit fraction appears among them so the
    /// round-trip property has a literal whose spelling a short constant
    /// could not survive.
    fn floatLiteral(self: *Gen, w: *std.Io.Writer) Error!void {
        switch (self.choices.below(4)) {
            0 => try w.print("{d}.5", .{self.choices.below(4)}),
            1 => try w.print("{d}.25e{d}", .{ self.choices.below(4), self.choices.below(4) }),
            2 => try w.print("{d}E-{d}", .{ self.choices.between(1, 9), self.choices.between(1, 4) }),
            else => try w.print("0.{d}00000000000000{d}", .{
                self.choices.between(1, 9),
                self.choices.between(1, 9),
            }),
        }
    }

    /// An integer of a given type, settled by the expression itself.
    ///
    /// A literal has no type until something gives it one, and it defaults to
    /// the integer type where nothing does. Most positions supply an expected
    /// type — an annotation, a parameter, a return type — but the left operand
    /// of a comparison is what settles the right, so nothing supplies one
    /// there. A literal written in that position defaults, and whatever is on
    /// the other side is then a mismatch.
    fn settledInt(self: *Gen, w: *std.Io.Writer, want: Ty, depth: u32, visible: u32) Error!void {
        if (depth > 0 and self.choices.odds(3)) {
            try w.writeAll("(");
            try self.settledInt(w, want, depth - 1, visible);
            try w.print(" + {d})", .{self.choices.below(4)});
            return;
        }

        // An element of an array in scope, which is the only way a generated
        // program indexes one. The index is written down so the compiler
        // settles it: an index it cannot settle traps where no element sits,
        // and a generated program is well-typed by construction rather than
        // lucky.
        var arrays: u32 = 0;
        for (try self.scope.visible()) |b| {
            switch (b.ty) {
                .array => |a| if (a.element().eql(want) and !self.alreadyMarked(b.name)) {
                    arrays += 1;
                },
                else => {},
            }
        }
        // Taken whenever one is visible: an array in scope is rare enough --
        // one typed binding in thirty-two -- that declining half of the few
        // chances left the index expression under the sweep's notice once
        // the float forms shifted every draw after them.
        if (arrays > 0) {
            var nth = self.choices.below(arrays);
            for (try self.scope.visible()) |b| {
                const a = switch (b.ty) {
                    .array => |x| x,
                    else => continue,
                };
                if (!a.element().eql(want)) continue;
                if (self.alreadyMarked(b.name)) continue;
                if (nth == 0) return w.print("{s}[{d}]", .{ b.name, self.choices.below(a.count) });
                nth -= 1;
            }
        }

        var in_scope: u32 = 0;
        for (try self.scope.visible()) |b| {
            if (b.ty.eql(want)) in_scope += 1;
        }
        if (in_scope > 0 and self.choices.odds(2)) {
            var nth = self.choices.below(in_scope);
            for (try self.scope.visible()) |b| {
                if (!b.ty.eql(want)) continue;
                // A place another argument writes back through is not one this
                // argument may name, however it names it.
                if (self.alreadyMarked(b.name)) continue;
                if (nth == 0) return w.writeAll(b.name);
                nth -= 1;
            }
        }

        // A conversion settles it outright, and every literal the generator
        // writes is within range of every type it writes one for, so this
        // narrows nothing and cannot trap.
        try w.print("{s}({d})", .{ self.spell(want), self.choices.below(10) });
    }

    /// A place that may be written, for an argument passed back through.
    ///
    /// A path, not only a name: `&o.inner.y` is a place, and generating only
    /// bare names left the address of a field crossing a call reached by the
    /// corpus alone. The root is what is recorded as marked, because
    /// exclusivity is per root here -- the language compares paths by prefix,
    /// and refusing the whole root is the conservative side of that.
    fn mutableOfType(self: *Gen, want: Ty) Error!?[]const u8 {
        const place = (try self.pickPlace(want, .writable, 0)) orelse return null;
        try self.marked.append(self.gpa, place.root);
        return place.text;
    }

    /// Which bindings a place may be rooted at.
    const Roots = enum {
        /// Anything a name here can reach.
        readable,
        /// A `var` that ends no loop, which is what an argument written back
        /// through needs.
        writable,
    };

    /// One place of type `want`, chosen uniformly among those `roots` admits
    /// and reached by at least `least_depth` fields.
    ///
    /// Collected and then chosen from, in two passes: a stream of choices has
    /// to be told the range before it can answer, and the range is how many
    /// places there turned out to be.
    fn pickPlace(self: *Gen, want: Ty, roots: Roots, least_depth: u32) Error!?Path {
        var places: std.ArrayList(Path) = .empty;
        defer places.deinit(self.gpa);

        for (try self.scope.visible()) |b| {
            // A place another argument writes back through is not one anything
            // else may name, and naming a field of it still names it.
            if (self.alreadyMarked(b.name)) continue;
            if (roots == .writable and (!b.mutable or b.frozen)) continue;
            try self.pathsIn(b.ty, b.name, b.name, 0, &places);
        }

        var n: u32 = 0;
        for (places.items) |p| {
            if (fits(p, want, least_depth)) n += 1;
        }
        if (n == 0) return null;

        var nth = self.choices.below(n);
        for (places.items) |p| {
            if (!fits(p, want, least_depth)) continue;
            if (nth == 0) return p;
            nth -= 1;
        }
        return null;
    }

    fn fits(p: Path, want: Ty, least_depth: u32) bool {
        return p.depth >= least_depth and p.ty.eql(want);
    }

    /// A place: how it is written, what type it has, the name it is rooted
    /// at, and how many fields were selected to reach it.
    const Path = struct { text: []const u8, ty: Ty, root: []const u8, depth: u32 };

    /// Every place a value of `ty` offers: itself, and each field path into
    /// it, however deep.
    ///
    /// A structure may hold a structure, so a place is a chain rather than one
    /// step. Enumerating them costs nothing here -- the declarations are few
    /// and shallow by construction -- and it is what makes `o.inner.y`
    /// something the generator can reach.
    fn pathsIn(
        self: *Gen,
        ty: Ty,
        prefix: []const u8,
        root: []const u8,
        depth: u32,
        out: *std.ArrayList(Path),
    ) Error!void {
        try out.append(self.gpa, .{ .text = prefix, .ty = ty, .root = root, .depth = depth });

        const i = switch (ty) {
            .struct_ => |x| x,
            else => return,
        };
        const def = self.structs.items[i];
        for (0..def.count) |f| {
            const step = try std.fmt.allocPrint(self.gpa, "{s}.f{d}", .{ prefix, f });
            try self.pathsIn(def.field[f], step, root, depth + 1, out);
        }
    }

    fn alreadyMarked(self: *const Gen, candidate: []const u8) bool {
        for (self.marked.items) |m| {
            if (std.mem.eql(u8, m, candidate)) return true;
        }
        return false;
    }

    fn pickCall(self: *Gen, want: Ty, visible: u32) ?Func {
        var n: u32 = 0;
        for (self.funcs.items[0..@min(visible, self.funcs.items.len)]) |f| {
            if (f.ret.eql(want)) n += 1;
        }
        if (n == 0) return null;

        var want_nth = self.choices.below(n);
        for (self.funcs.items[0..@min(visible, self.funcs.items.len)]) |f| {
            if (!f.ret.eql(want)) continue;
            if (want_nth == 0) return f;
            want_nth -= 1;
        }
        unreachable;
    }

    /// How a variant names its enum.
    ///
    /// Both spellings mean the same value and are checked by different code,
    /// so a generator writing only one of them leaves the other exercised by
    /// nothing. `from_context` is written only where the position supplies the
    /// type, which is why it is a choice made at the site rather than here.
    const Spelling = enum { qualified, from_context };

    /// A value of an enum type: the variant, and what it carries.
    ///
    /// The payload is a literal rather than an expression, so this stays a
    /// leaf -- a construction that recursed would make depth mean something
    /// different here than everywhere else.
    fn buildVariant(self: *Gen, w: *std.Io.Writer, e: u32, how: Spelling) Error!void {
        const def = self.enums.items[e];
        const v = self.choices.below(def.count);

        switch (how) {
            .qualified => try w.print("E{d}._V{d}", .{ e, v }),
            .from_context => try w.print("._V{d}", .{v}),
        }
        // What a variant carries is a value like any other, so it is built
        // the way any other value of its type is. A payload that is itself a
        // declared type is the shape that hid a lowering bug for a stage, and
        // it is only reachable here because a payload is now built rather than
        // spelled out.
        const carried = def.payload[v] orelse return;
        const was = self.enter(.consuming);
        defer self.position = was;

        try w.writeAll("(");
        try self.leaf(w, carried, .no);
        try w.writeAll(")");
    }

    /// Whether the position being generated imposes a type on what goes in
    /// it. A variant may leave its enum unnamed only where something else
    /// says which enum it is.
    const Typed = enum { yes, no };

    /// A value of a structure type: every field given a value, in order.
    ///
    /// Its own type is never named. A leading `.` means the type is the one
    /// expected here, and the position this is generated for always supplies
    /// one -- which is what makes the form worth generating rather than merely
    /// legal.
    fn buildStruct(self: *Gen, w: *std.Io.Writer, i: u32) Error!void {
        // A field initialiser takes its value, whatever position the literal
        // itself sits in.
        const was = self.enter(.consuming);
        defer self.position = was;

        const def = self.structs.items[i];
        // Sometimes a literal writes only some fields and takes the rest from
        // a base. At least one field is left out, because a base supplying
        // nothing is refused, and every generated field owes nothing, so a
        // replaced one is never a leak.
        //
        // A base written as another literal of the type nests one update in
        // another. How deep is bounded here rather than left to the stream,
        // which wraps: a stream that kept choosing it never ended.
        const update = def.count >= 2 and self.update_bases < max_update_bases and self.choices.odds(4);
        const omitted = if (update) self.choices.below(def.count) else def.count;
        try w.writeAll(".{");
        var written: u32 = 0;
        for (0..def.count) |f| {
            if (update and (f == omitted or self.choices.odds(3))) continue;
            try w.print("{s} f{d} = ", .{ if (written == 0) "" else ",", f });
            try self.leaf(w, def.field[f], .yes);
            written += 1;
        }
        if (update) {
            try w.writeAll(if (written == 0) " .." else ", ..");
            // A copy of a field of the type exercises a place as a base, and a
            // literal of the type an update nested in an update. A field and
            // not a whole binding, because a copy of a binding nothing reads
            // again is refused as pointless.
            const place = if (self.choices.odds(2)) try self.pickPlace(.{ .struct_ = i }, .readable, 1) else null;
            if (place) |p| {
                try w.print("copy({s})", .{p.text});
            } else {
                self.update_bases += 1;
                defer self.update_bases -= 1;
                try self.buildStruct(w, i);
            }
        }
        try w.writeAll(" }");
    }

    /// A field path into a binding already in scope, where one reaches the
    /// type wanted.
    ///
    /// Reading a field is a different path from building one, and a generator
    /// that only ever built would leave the read reached by the corpus alone.
    /// The chain may be of any length, because a structure may hold one: the
    /// offsets of a nesting are decided at the second step and not the first.
    fn readField(self: *Gen, w: *std.Io.Writer, want: Ty) Error!bool {
        // At least one field, because a bare name is not a field read and
        // `leaf` writes those itself.
        const place = (try self.pickPlace(want, .readable, 1)) orelse return false;

        // Scalars snapshot the field. Aggregate fields retain explicit copying
        // when the surrounding position consumes the value. Enum payload rows
        // are bounded by max_variants, so classification takes constant time.
        const snapshot = switch (want) {
            .u8_, .i8_, .i64_, .f64_, .bool_ => true,
            .struct_, .held, .array => false,
            .enum_ => |e| no_payloads: {
                const def = self.enums.items[e];
                for (def.payload[0..def.count]) |payload| {
                    if (payload != null) break :no_payloads false;
                }
                break :no_payloads true;
            },
        };
        if (self.position == .consuming and !snapshot) {
            try w.print("copy({s})", .{place.text});
        } else {
            try w.writeAll(place.text);
        }
        return true;
    }

    /// A value of `want` needing nothing else: a name in scope, or a literal.
    fn leaf(self: *Gen, w: *std.Io.Writer, want: Ty, typed: Typed) Error!void {
        // A place with a conversion around it, where the conversion cannot
        // trap: every value of a narrow type fits `Int64`, so this is the one
        // shape that names a place under an operator without risking one.
        //
        // It is what catches an operator whose operand inherits the position
        // around it rather than reading. Nothing is taken here, so a rule that
        // thought otherwise refuses a program the generator says is fine.
        if (want.eql(.i64_) and self.choices.odds(3)) {
            if (try self.pickPlace(.u8_, .readable, 0)) |narrow| {
                return w.print("Int64({s})", .{narrow.text});
            }
        }

        // A conversion across the register classes, in both directions. The
        // float is a small literal, so its truncation is a value every
        // integer type holds and the conversion's guards pass rather than
        // trap -- a program that traps on its first operation says nothing
        // about everything after it. An unsigned source where a place
        // supplies one, so both signed and unsigned instruction selections
        // are reached.
        if (want.eql(.i64_) and self.choices.odds(4)) {
            try w.writeAll("Int64(");
            try self.floatLiteral(w);
            return w.writeAll(")");
        }
        if (want.eql(.f64_) and self.choices.odds(3)) {
            if (try self.pickPlace(.u8_, .readable, 0)) |narrow| {
                return w.print("Float64({s})", .{narrow.text});
            }
            return w.print("Float64({d})", .{self.choices.below(100)});
        }

        // A field of something already in scope, before a fresh value: a value
        // built here is reachable by construction, and one read back through a
        // field is what says the offset was right.
        if (self.choices.odds(3) and try self.readField(w, want)) return;

        var in_scope: u32 = 0;
        for (try self.scope.visible()) |b| {
            if (b.ty.eql(want)) in_scope += 1;
        }

        // A name written where the value is taken is a move, and what the
        // binding was is gone -- so every later statement that named it would
        // have to know, and the generator would be tracking what it has
        // consumed rather than what is in scope. A fresh value is written
        // instead, which is why no generated program moves a whole binding.
        if (self.position == .consuming) in_scope = 0;

        if (in_scope > 0 and self.choices.odds(2)) {
            var nth = self.choices.below(in_scope);
            for (try self.scope.visible()) |b| {
                if (!b.ty.eql(want)) continue;
                // A place another argument writes back through is not one this
                // argument may name, however it names it.
                if (self.alreadyMarked(b.name)) continue;
                if (nth != 0) {
                    nth -= 1;
                    continue;
                }
                // Sometimes parenthesised. Parentheses are a node in the tree
                // and mean nothing at all, so `(x)` must behave exactly as `x`
                // does -- which is what makes them worth generating: a walk
                // over places that stopped at one would find a different place
                // here, or none at all.
                if (self.choices.odds(4)) return w.print("({s})", .{b.name});
                return w.writeAll(b.name);
            }
        }

        return switch (want) {
            .u8_, .i8_, .i64_ => w.print("{d}", .{self.choices.below(10)}),
            .f64_ => self.floatLiteral(w),
            .bool_ => w.writeAll(if (self.choices.odds(2)) "true" else "false"),
            .enum_ => |e| self.buildVariant(
                w,
                e,
                if (typed == .yes and self.choices.odds(2)) .from_context else .qualified,
            ),
            .struct_ => |i| self.buildStruct(w, i),
            // Every element written out, because a literal has as many as its
            // type says and the generator is the thing that must not be wrong
            // about that.
            .array => |a| blk: {
                try w.writeAll("[");
                for (0..a.count) |i| {
                    if (i > 0) try w.writeAll(", ");
                    const was = self.enter(.consuming);
                    defer self.position = was;
                    try self.leaf(w, a.element(), typed);
                }
                break :blk w.writeAll("]");
            },
            // `.{ g = <argument> }`, which is the whole of what one holds.
            .held => |i| blk: {
                try w.writeAll(".{ g = ");
                const was = self.enter(.consuming);
                defer self.position = was;
                try self.expr(w, self.held.items[i], 0, 0, .yes);
                break :blk w.writeAll(" }");
            },
        };
    }
};

/// A generated program loaded beside the library and checked as a program is.
///
/// A tuple's type is the library's `Tuple2` to `Tuple8`, so a tree resolved and
/// checked on its own text, with no library, refuses every generated tuple as
/// [T-Literal]. What a generated program means is what `loader.checkProgram`
/// says of it, and this is the one place the generator's consumers ask.
pub const Loaded = struct {
    table: FileTable,
    sink: Sink,
    interner: Interner,
    program: Program,
    semantics: loader.Semantics,
};

/// Loads and checks `files`, entered at `entry`, as a program, through `library`
/// where one is held and from the embedded sources otherwise. Allocates from
/// `gpa` and never frees: the caller supplies an arena or a compilation's
/// lifetime.
pub fn checkLoaded(
    gpa: std.mem.Allocator,
    entry: []const u8,
    files: []const loader.InMemoryFile,
    library: ?*const loader.CheckedLibrary,
) !*Loaded {
    const loaded = try gpa.create(Loaded);
    loaded.table = .empty;
    loaded.sink = Sink.init(gpa);
    loaded.interner = .empty;
    loaded.program = if (library) |checked|
        try checked.loadFromMemory(gpa, &loaded.table, &loaded.sink, &loaded.interner, entry, files, .program, .borrow)
    else
        try loader.loadFromMemory(gpa, &loaded.table, &loaded.sink, &loaded.interner, entry, files, .program, true, .borrow);
    try loaded.table.buildMaps(gpa);
    loaded.semantics = if (library) |checked|
        try checked.checkProgram(gpa, gpa, &loaded.program, &loaded.interner, &loaded.sink, .program)
    else
        try loader.checkProgram(gpa, gpa, &loaded.program, &loaded.interner, &loaded.sink, .program);
    return loaded;
}

/// `checkLoaded` for a generated program, which is one file at `path`.
pub fn checkLoadedText(
    gpa: std.mem.Allocator,
    path: []const u8,
    text: []const u8,
    library: ?*const loader.CheckedLibrary,
) !*Loaded {
    const files = try gpa.dupe(loader.InMemoryFile, &.{.{ .path = path, .text = text }});
    return checkLoaded(gpa, path, files, library);
}

test "checkLoaded accepts a tuple program and refuses an ill-typed one" {
    var library = try loader.CheckedLibrary.init(testing.allocator);
    defer library.deinit();
    const held_by: [2]?*const loader.CheckedLibrary = .{ library, null };
    const cases = [_]struct { text: []const u8, accepted: bool }{
        .{ .text = "fn main() -> UInt8 {\n    let pair = (UInt8(1), true)\n    let (n, _) = pair\n    n\n}\n", .accepted = true },
        .{ .text = "fn main() -> UInt8 {\n    (UInt8(1), true)\n}\n", .accepted = false },
    };
    for (cases) |c| {
        for (held_by) |held| {
            var arena = std.heap.ArenaAllocator.init(testing.allocator);
            defer arena.deinit();
            const files = [_]loader.InMemoryFile{.{ .path = "main.lin", .text = c.text }};
            const loaded = try checkLoaded(arena.allocator(), "main.lin", &files, held);
            try testing.expectEqual(c.accepted, !loaded.sink.hasErrors());
        }
    }
}

fn expectAccepted(gpa: std.mem.Allocator, library: *const loader.CheckedLibrary, text: []const u8) !void {
    _ = try checkAccepted(gpa, library, text);
}

/// Checks a generated program beside the library and returns what checking
/// it produced; a program the checker refused is printed with what it said,
/// and is an error.
pub fn checkAccepted(gpa: std.mem.Allocator, library: *const loader.CheckedLibrary, text: []const u8) !*Loaded {
    const loaded = try checkLoadedText(gpa, "generated.lin", text, library);
    if (!loaded.sink.hasErrors()) return loaded;

    var out: std.Io.Writer.Allocating = .init(gpa);
    try render.renderAll(&out.writer, &loaded.table, &loaded.sink, .{ .color = .never });
    std.debug.print("\n=== generated ===\n{s}\n=== but rejected ===\n{s}\n", .{ text, out.written() });
    return error.GeneratedProgramRejected;
}

test "generated interpolation varies every format independently" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Each seed spells a different run of choices, and together they give
    // every value every spec.
    for (0..interpolation_specs.len * interpolation_specs.len) |seed| {
        var bytes: [9]u8 = undefined;
        bytes[0] = 7;
        for (0..8) |i| bytes[i + 1] = @intCast((seed + i * (seed / interpolation_specs.len + 1)) % interpolation_specs.len);
        const generated = try generateInterpolation(gpa, &bytes);
        try testing.expectEqual(@as(u32, 8), generated.shape.pieces);
        try testing.expectEqualSlices(u8, bytes[1..], &generated.shape.specs);

        const source: Source = .{ .path = "interpolation.lin", .text = generated.text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        try testing.expectEqual(@as(usize, 0), sink.items().len);

        var found: ?ExprId = null;
        for (0..ast.exprCount()) |raw| {
            const id = ExprId.at(@intCast(raw));
            if (ast.exprTag(id) == .interp) found = id;
        }
        const interpolation = ast.interpolation(found orelse return error.InterpolationNotGenerated);
        try testing.expectEqual(@as(usize, 8), interpolation.formats.len);
        for (interpolation.formats, generated.shape.specs) |format, chosen| {
            try testing.expectEqual(interpolation_specs[chosen].format.bits(), format.bits());
        }
    }
}

const StructuralReceipt = struct {
    group_entries: u32,
    generic_parameters: u32,
    inline_bounds: u32,
    trailing_predicates: u32,
    component_predicates: u32,
    bounds_per_predicate: u32,
    member_parameters: u32,
    bounds_per_member_parameter: u32,
    reverse_components: bool,
};

fn structuralReceipt(gpa: std.mem.Allocator, text: []const u8) !?StructuralReceipt {
    const source: Source = .{ .path = "generated.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);

    var derive: ?DeclId = null;
    var function_template: ?DeclId = null;
    var template_member: ?DeclId = null;
    var template_count: u32 = 0;
    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        switch (ast.declTag(d)) {
            .derive_impl => derive = d,
            .template_impl => {
                template_count += 1;
                if (ast.templateRequirements(d).len != 0) function_template = d;
            },
            .function => if (std.mem.eql(u8, ast.tokenText(ast.declName(d)), "_structural")) {
                template_member = d;
            },
            else => {},
        }
    }

    const d = derive orelse return null;
    const template = function_template orelse return null;
    const member = template_member orelse return null;
    try testing.expectEqual(@as(u32, 2), template_count);
    try testing.expect(ast.deriveIsGrouped(d));
    try testing.expect(std.mem.indexOf(u8, text, "reflect.case") != null);
    try testing.expect(std.mem.indexOf(u8, text, "reflect.components") != null);
    try testing.expect(std.mem.indexOf(u8, text, "component.of") != null);

    var inline_bounds: u32 = 0;
    for (ast.declTypeParams(d)) |param| inline_bounds += @intCast(ast.boundsOf(param).len);

    const requirements = ast.templateRequirements(template);
    const bounds_per_predicate: u32 = @intCast(ast.boundsIn(requirements[0].bounds).len);
    for (requirements) |requirement| {
        try testing.expectEqual(bounds_per_predicate, ast.boundsIn(requirement.bounds).len);
    }

    const member_parameters = ast.declTypeParams(member);
    const bounds_per_member_parameter: u32 = @intCast(ast.boundsOf(member_parameters[0]).len);
    for (member_parameters) |parameter| {
        try testing.expectEqual(bounds_per_member_parameter, ast.boundsOf(parameter).len);
    }

    return .{
        .group_entries = @intCast(ast.deriveTraits(d).len),
        .generic_parameters = @intCast(ast.declTypeParams(d).len),
        .inline_bounds = inline_bounds,
        .trailing_predicates = @intCast(ast.declWherePredicates(d).len),
        .component_predicates = @intCast(requirements.len),
        .bounds_per_predicate = bounds_per_predicate,
        .member_parameters = @intCast(member_parameters.len),
        .bounds_per_member_parameter = bounds_per_member_parameter,
        .reverse_components = std.mem.indexOf(u8, text, "reflect.components.reversed") != null,
    };
}

test "generated structural derives vary every independent dimension" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var group_entries = [_]bool{false} ** 3;
    var generic_parameters = [_]bool{false} ** 3;
    var inline_bounds = [_]bool{false} ** 4;
    var trailing_predicates = [_]bool{false} ** 3;
    var component_predicates = [_]bool{false} ** 3;
    var bounds_per_predicate = [_]bool{false} ** 3;
    var member_parameters = [_]bool{false} ** 3;
    var bounds_per_member_parameter = [_]bool{false} ** 3;
    var reverse_components = [_]bool{false} ** 2;

    for (0..64) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const receipt = (try structuralReceipt(gpa, try generate(gpa, bytes, .{}))) orelse
            return error.StructuralDeriveNotGenerated;
        group_entries[receipt.group_entries] = true;
        generic_parameters[receipt.generic_parameters] = true;
        inline_bounds[receipt.inline_bounds] = true;
        trailing_predicates[receipt.trailing_predicates] = true;
        component_predicates[receipt.component_predicates] = true;
        bounds_per_predicate[receipt.bounds_per_predicate] = true;
        member_parameters[receipt.member_parameters] = true;
        bounds_per_member_parameter[receipt.bounds_per_member_parameter] = true;
        reverse_components[@intFromBool(receipt.reverse_components)] = true;
    }

    try testing.expect(group_entries[1] and group_entries[2]);
    try testing.expect(generic_parameters[1] and generic_parameters[2]);
    try testing.expect(inline_bounds[2] and inline_bounds[3]);
    try testing.expect(trailing_predicates[0] and trailing_predicates[1] and trailing_predicates[2]);
    try testing.expect(component_predicates[1] and component_predicates[2]);
    try testing.expect(bounds_per_predicate[1] and bounds_per_predicate[2]);
    try testing.expect(member_parameters[1] and member_parameters[2]);
    try testing.expect(bounds_per_member_parameter[1] and bounds_per_member_parameter[2]);
    try testing.expect(reverse_components[0] and reverse_components[1]);
}

test "some generated program shadows a name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Shadowing is what makes a scope rule observable, so a generator that
    // never produced it would leave every scope property trivially satisfied.
    var shadowed: u32 = 0;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});

        var at: usize = 0;
        var names: std.ArrayList([]const u8) = .empty;
        while (std.mem.indexOfPos(u8, text, at, ": ")) |i| {
            at = i + 2;
            const decl = std.mem.lastIndexOfScalar(u8, text[0..i], ' ') orelse continue;
            const n = text[decl + 1 .. i];
            for (names.items) |seen| {
                if (std.mem.eql(u8, seen, n)) shadowed += 1;
            }
            try names.append(gpa, n);
        }
    }

    try testing.expect(shadowed > 0);
}

test "generation is decided by its choices" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const bytes = try choicesFromSeed(gpa, 7, 64);
    try testing.expectEqualStrings(
        try generate(gpa, bytes, .{}),
        try generate(gpa, bytes, .{}),
    );
}

test "an empty choice stream still yields a program" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text = try generate(gpa, "", .{});
    try testing.expect(std.mem.indexOf(u8, text, "fn main() -> UInt8") != null);
    var library = try loader.CheckedLibrary.init(testing.allocator);
    defer library.deinit();
    try expectAccepted(gpa, library, text);
}

/// Which spellings of a variant reference a program contains.
///
/// Both spellings end in `._V`, so a needle cannot tell them apart: what
/// precedes it is the whole difference. An enum's name ends in a digit, so a
/// digit before the dot is the qualified form and anything else is the form
/// that takes its enum from the position it sits in.
const Spellings = struct {
    qualified: bool = false,
    from_context: bool = false,

    fn of(text: []const u8) Spellings {
        var seen: Spellings = .{};
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, text, at, "._V")) |i| {
            at = i + 3;
            if (i > 0 and std.ascii.isDigit(text[i - 1])) {
                seen.qualified = true;
            } else {
                seen.from_context = true;
            }
        }
        return seen;
    }
};

/// How many of `n` seeds produce a program containing `needle`.
fn seedsContaining(gpa: std.mem.Allocator, n: usize, needle: []const u8) !u32 {
    var found: u32 = 0;
    for (0..n) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        if (std.mem.indexOf(u8, try generate(gpa, bytes, .{}), needle) != null) found += 1;
    }
    return found;
}

test "a stream that keeps choosing a structure update still ends" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Constant and two-byte repeating streams, which wrap onto the same
    // decisions forever: one that keeps choosing to build an update's base as
    // another update of the same structure has to end anyway.
    for (0..256) |a| {
        for ([_]u8{ 0, 1, 2, 3, 4, 8, 12, 16 }) |b| {
            var bytes: [64]u8 = undefined;
            for (&bytes, 0..) |*byte, i| byte.* = if (i % 2 == 0) @intCast(a) else b;
            _ = try generate(arena.allocator(), &bytes, .{});
        }
    }
}

test "some generated program declares a generic type and instantiates it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Substitution under a program nobody wrote. A written case fixes the
    // argument the author thought of; these vary it across seeds, and the
    // rewrites hold each one to answering the same.
    try testing.expect(try seedsContaining(gpa, 200, "@copyable pub struct G[T]") > 0);

    // A generic alias heads a path, so its parameters are settled by the type
    // expected where the variant is written.
    try testing.expect(try seedsContaining(gpa, 200, "alias GA[T] = GE[T]") > 0);

    // At a Linear argument, which is the case the universe is computed for:
    // one declaration, and an obligation that arrives with the argument rather
    // than with the type.
    try testing.expect(try seedsContaining(gpa, 200, "G[L0]") > 0);

    // And at something else, so the two are told apart. A generic type that
    // only ever appeared at one argument would exercise instantiation and not
    // substitution.
    try testing.expect(try seedsContaining(gpa, 200, "G[UInt8]") +
        try seedsContaining(gpa, 200, "G[Bool]") +
        try seedsContaining(gpa, 200, "G[Int64]") +
        try seedsContaining(gpa, 200, "G[E0]") +
        try seedsContaining(gpa, 200, "G[S0]") > 0);
}

/// The trait block of a program, or null where it declares no trait.
///
/// Read back out of the source rather than kept beside it, so the test speaks
/// about what a seed produces and not about what the drawing intended.
fn traitBlockOf(text: []const u8) ?[]const u8 {
    const from = std.mem.indexOf(u8, text, "trait _Measure {") orelse return null;
    const marker = "fn _measured";
    const last = std.mem.lastIndexOf(u8, text, marker).?;
    const to = std.mem.indexOfPos(u8, text, last, "\n}\n").? + 3;
    return text[from..to];
}

test "the trait a generated program declares is not one fixed program" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // What a block written out as a string literal cannot do. Every seed
    // reaching one arrangement of the machinery is a property counted once per
    // seed and asked once in total, and a dispatch defect lives in the
    // arrangement -- how many operations a trait declares, how many types
    // implement it, and how `Self` reaches a body.
    var blocks: std.ArrayList([]const u8) = .empty;
    var conventions: std.EnumSet(SelfConvention) = .initEmpty();
    var ops: std.EnumSet(enum { one, two }) = .initEmpty();
    var impls: std.EnumSet(enum { two, three }) = .initEmpty();
    // Which settlings the call written against the bound is instantiated at,
    // over the seeds a default run makes. That call is what the declared type
    // exists here to reach, and a settling it never meets is one nothing
    // substitutes into.
    var through_the_bound: std.EnumSet(ItemType) = .initEmpty();

    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});
        const block = traitBlockOf(text) orelse continue;

        var novel = true;
        for (blocks.items) |b| {
            if (std.mem.eql(u8, b, block)) novel = false;
        }
        if (novel) try blocks.append(gpa, block);

        // The declared type, in every program that declares the trait: one
        // implementation settles it to a `UInt8` and the next to a `Bool`, and
        // a function written against the bound answers what the argument
        // settled. A name every implementation settled alike would be one a
        // substitution answering from the wrong implementation gets right.
        try testing.expect(std.mem.indexOf(u8, block, "    type Item\n") != null);
        try testing.expect(std.mem.indexOf(u8, block, "type Item = UInt8") != null);
        try testing.expect(std.mem.indexOf(u8, block, "type Item = Bool") != null);
        try testing.expect(std.mem.indexOf(u8, block, "-> T.Item") != null);

        if (seed < 32) {
            if (std.mem.indexOf(u8, text, ": UInt8 = _itemOf(") != null) through_the_bound.insert(.u8_);
            if (std.mem.indexOf(u8, text, ": Bool = _itemOf(") != null) through_the_bound.insert(.bool_);
        }

        conventions.insert(if (std.mem.indexOf(u8, block, "sink x: Self") != null) .sink else .read);
        ops.insert(if (std.mem.indexOf(u8, block, "fn of1(") != null) .two else .one);
        impls.insert(if (std.mem.indexOf(u8, block, "struct _M2 ") != null) .three else .two);
    }

    // Every axis reached both ways, named one at a time so a drawing that
    // stopped varying says which choice it stopped making rather than only
    // that the count fell.
    try testing.expectEqual(2, conventions.count());
    try testing.expectEqual(2, ops.count());
    try testing.expectEqual(2, impls.count());

    // And the settlings the bound-headed call is instantiated at, both of them
    // inside the seeds a default run uses: which spelling a call takes and
    // which type an implementation settles are derived from different things,
    // and a derivation keying both on the same one would leave this at one.
    try testing.expectEqual(2, through_the_bound.count());

    // And the arrangements themselves, which is more than the axes multiply
    // out to on their own: what each implementation answers with varies too,
    // and that is what decides whether a wrong dispatch shows.
    try testing.expect(blocks.items.len > 8);
}

test "a generated trait call is checked against the body it must have reached" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A call whose result nothing reads says the machinery ran and nothing
    // about which body it picked: the program exits the same whichever
    // implementation answered, so no rewrite of it can disagree with the
    // original. Every call is compared against the number the right body
    // returns, and the tens digit of that number is the implementing type --
    // so a dispatch that reached another type's body answers with a number
    // from it and the program stops with a status of its own.
    var calls: u32 = 0;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});
        if (traitBlockOf(text) == null) continue;

        // Every call, in the order the entry makes them, with the type it was
        // handed and the number the guard after it demands.
        var built: ?u32 = null;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            const body = std.mem.trim(u8, line, " ");
            if (!std.mem.startsWith(u8, body, "let _t") and !std.mem.startsWith(u8, body, "if _t")) continue;
            if (std.mem.indexOf(u8, body, ": _M")) |i| {
                built = try std.fmt.parseInt(u32, body[i + 4 .. i + 5], 10);
                continue;
            }
            if (!std.mem.startsWith(u8, body, "if _t")) continue;

            const ty = built orelse continue;
            const from = std.mem.indexOf(u8, body, "!= ").? + 3;
            const to = std.mem.indexOfScalarPos(u8, body, from, ' ').?;
            const wanted = try std.fmt.parseInt(u32, body[from..to], 10);

            // The number the right body returns, and no other body can: a
            // value's tens digit is the type it was built as, so a call that
            // reached another implementation answers from another decade and
            // the program stops with a status of its own. Two implementations
            // answering alike would be dispatched wrongly and agree.
            try testing.expectEqual(ty, wanted / 10);
            built = null;
            calls += 1;
        }
    }
    try testing.expect(calls > 0);
}

test "no generated program writes two implementations of one trait for one head" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Which of two families answering for one receiver a call reaches is
    // decided by which was written first, so a program holding a pair means
    // one thing and its declarations reversed another. Every rewrite the
    // harness applies rests on the opposite, and a generated program is one
    // the harness rewrites without anything to compare against -- so a
    // generator that made the shape would produce a failure reading as a
    // compiler bug.
    //
    // Asked through the routine the rewrite passes such a program over by, so
    // the two sides of the sentence cannot come apart.
    for (0..64) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});
        const source: Source = .{ .path = "generated.lin", .text = text };

        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var res = try resolveTree(gpa, &ast, &sink);

        try testing.expect(!try transform.twoImplementationsForOneHead(gpa, &ast, &res.resolution));
    }
}

test "some generated program writes behaviour about a type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // An `impl` is a namespace and not a scope, so what it changes is where a
    // declaration is written and how a call reaches it. Both were reached by
    // the corpus alone while every generated function sat at the top level.
    try testing.expect(try seedsContaining(gpa, 200, "impl S") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "impl E") > 0);

    // And the qualified call that reaches one.
    var qualified = false;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, text, at, "._f")) |i| {
            at = i + 3;
            qualified = true;
        }
    }
    try testing.expect(qualified);
}

test "some generated program takes a structure apart" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Every structure the generator wrote was read through its fields, so the
    // destructuring path -- the pattern, the binders it declares, and the
    // loads that fill them -- was reached by the corpus alone.
    var found = false;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});
        if (std.mem.indexOf(u8, text, "let S0 {") != null) found = true;
        if (std.mem.indexOf(u8, text, "let S1 {") != null) found = true;
    }
    try testing.expect(found);
}

test "some generated program builds a structure from a base" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Both bases are written: a copy of a place, and a literal nested as the
    // base of another.
    var copied = false;
    var nested = false;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});
        if (std.mem.indexOf(u8, text, "..copy(") != null) copied = true;
        if (std.mem.indexOf(u8, text, "...{") != null) nested = true;
    }
    try testing.expect(copied and nested);
}

test "some generated program reads a newtype apart with a borrowed let" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expect(try seedsContaining(gpa, 200, "let read N0(n) = held") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "_fromNewtypeRead(") > 0);
}

test "some generated program declares a linear type and disposes of it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Ownership shipped with every one of its rules exercised by the corpus
    // alone, which is a corpus of the cases someone remembered to write. A
    // generated program that mints a linear value and disposes of it is what
    // holds the other direction: the pass may not refuse a program that gets
    // it right, whatever shape the program is.
    try testing.expect(try seedsContaining(gpa, 200, "@linear enum L0") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "sink held") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "match read held") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "_dispose(") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "_peek(") > 0);

    // And not every program, so the shapes without one stay reachable too.
    try testing.expect(try seedsContaining(gpa, 200, "@linear enum L0") < 200);
}

test "some generated program instantiates a generic at the unit type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The one type no choice over types can produce: `()` is spellable as a
    // return type and nowhere else, so a generator picking from a pool of
    // types will never reach it however many programs it is asked for. Nothing
    // in the corpus instantiated a generic at it either, which left the layout
    // of a part occupying no bytes -- and the store and the load the backend
    // emits for one -- reached by no program at all.
    try testing.expect(try seedsContaining(gpa, 200, "fn _nothing()") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "GE.Just(_nothing())") > 0);

    // And not every program, so the shapes without one stay reachable too.
    try testing.expect(try seedsContaining(gpa, 200, "fn _nothing()") < 200);
}

test "some generated program declares a variant that carries a value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A generator that stopped producing this would leave layout, the copy at
    // a binding and the aggregate return exercised by the corpus alone, and
    // the corpus is what someone remembered to write.
    try testing.expect(try seedsContaining(gpa, 200, "(UInt8)") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "(Bool)") > 0);
}

test "some generated program binds what a variant carries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Declaring a payload and reading one are different paths: the second is
    // the load through the address, and only a pattern that binds reaches it.
    try testing.expect(try seedsContaining(gpa, 200, "_b") > 0);
}

test "some generated program names a variant through context" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // `.V` and `E.V` mean the same value and are checked by different code.
    // Generating only the qualified form left the other one reached by a
    // single corpus case, which asserted that it fails.
    var found = false;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        if (Spellings.of(try generate(gpa, bytes, .{})).from_context) found = true;
    }
    try testing.expect(found);
}

test "some generated program names a type only in annotations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The shape that makes [N-Unused] reachable. A type declared here is
    // named without a leading underscore, so nothing exempts it, and the only
    // thing keeping such a program accepted is the compiler counting an
    // annotation as a use. A generator that stopped producing this would put
    // that rule back beyond its reach.
    var found: u32 = 0;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});

        if (std.mem.indexOf(u8, text, "enum E0 ") == null) continue;
        if (std.mem.indexOf(u8, text, "E0._V") != null) continue;
        if (std.mem.indexOf(u8, text, ": E0") == null) continue;
        found += 1;
    }
    try testing.expect(found > 0);
}

test "a generated type is not exempt from the unused rule" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Bindings stay exempt deliberately -- arranging a use for every one of
    // them would bias every program towards the shapes easiest to consume.
    // A type is different: the generator names one in `main` whatever else it
    // does, so it can afford a name the rule applies to.
    try testing.expect(try seedsContaining(gpa, 200, "enum _E") == 0);
    try testing.expect(try seedsContaining(gpa, 200, "enum E") > 0);
}

/// The deepest chain of conditionals nested one inside another's arm.
///
/// Read from the tree rather than counted in the text: an `if` inside an arm
/// and an `if` in the statement beside it read alike as characters and are
/// different programs.
fn conditionalDepth(ast: *const Ast, id: ExprId) u32 {
    if (id == ExprId.none) return 0;
    return switch (ast.exprTag(id)) {
        // Holds expressions and no conditional the generator writes, because
        // the generator writes no interpolation at all.
        .interp => 0,
        .conditional => blk: {
            const c = ast.conditional(id);
            break :blk 1 + @max(conditionalDepth(ast, c.then), conditionalDepth(ast, c.otherwise));
        },

        // A logical operator means a conditional but does not nest an arm
        // inside another's, which is what this measures -- so it contributes
        // its operands' depth without adding a level of its own.
        .logical_and, .logical_or => blk: {
            const b = ast.binary(id);
            break :blk @max(conditionalDepth(ast, b.lhs), conditionalDepth(ast, b.rhs));
        },
        .not => conditionalDepth(ast, ast.unaryOperand(id)),
        .lambda => blk: {
            const lambda = ast.lambda(id);
            var best = conditionalDepth(ast, lambda.body);
            for (lambda.captures) |capture| best = @max(best, conditionalDepth(ast, capture.source));
            for (lambda.params) |param| best = @max(best, conditionalDepth(ast, param.default));
            break :blk best;
        },
        // The sequence and the body, which is where a conditional could sit.
        // The binder is a name and holds none.
        .for_, .for_read, .for_inout => blk: {
            const f = ast.call(id);
            break :blk @max(conditionalDepth(ast, f.callee), conditionalDepth(ast, f.args[1]));
        },
        .block => blk: {
            const inner = ast.blockOf(id);
            var best: u32 = 0;
            for (ast.blockStmts(inner)) |st| {
                best = @max(best, conditionalDepth(ast, ast.stmtData(st).init));
            }
            break :blk @max(best, conditionalDepth(ast, inner.tail));
        },
        .grouped, .negate, .loop_, .break_, .return_, .marked, .variant_ref, .field, .copy_, .borrow, .dereference, .panic, .try_, .from_end => conditionalDepth(ast, ast.unaryOperand(id)),
        // A pattern names fields and binders. There is no expression under it
        // to nest a conditional in, so the answer is zero rather than a case
        // that cannot happen -- a total function here is what keeps a shape
        // the generator learns to write from crashing the property that reads
        // its output.
        .struct_pattern, .tuple_pattern => 0,
        .call, .match_, .match_read, .struct_literal, .array_literal, .tuple_literal, .unwrap_else => blk: {
            const c = ast.call(id);
            var best = conditionalDepth(ast, c.callee);
            for (c.args) |a| best = @max(best, conditionalDepth(ast, a));
            break :blk best;
        },
        .index, .while_, .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign, .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge => blk: {
            const b = ast.binary(id);
            break :blk @max(conditionalDepth(ast, b.lhs), conditionalDepth(ast, b.rhs));
        },
        .int_literal, .float_literal, .str_literal, .embed, .embed_bytes, .bool_literal, .unit_literal, .name_ref, .param_argument, .reflection_root, .continue_, .err => 0,
        // A generated range's ends are literals, so nothing nests inside one
        // for this to find.
        .range => 0,
    };
}

fn deepestConditional(gpa: std.mem.Allocator, text: []const u8) !u32 {
    const source: Source = .{ .path = "generated.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);

    var best: u32 = 0;
    for (0..ast.declCount()) |i| {
        const d: @import("../syntax/node.zig").DeclId = .at(@intCast(i));
        best = @max(best, conditionalDepth(&ast, ast.declBody(d)));
    }
    return best;
}

test "some generated program nests conditionals three deep" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // An arm is where a type is settled by whatever came first, so an arm
    // inside an arm is where that rule composes with itself. One level says
    // nothing about that.
    var deepest: u32 = 0;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        deepest = @max(deepest, try deepestConditional(gpa, try generate(gpa, bytes, .{})));
    }
    try testing.expect(deepest >= 3);
}

/// Whether one name is declared twice over, the second further in than the
/// first. Indentation is nesting here, because the generator writes it that way.
fn shadowedTwoDeep(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var names: [64][]const u8 = undefined;
    var indents: [64]usize = undefined;
    var n: usize = 0;

    while (lines.next()) |line| {
        const bare = std.mem.trimStart(u8, line, " ");
        const keyword: []const u8 = if (std.mem.startsWith(u8, bare, "let ")) "let " else if (std.mem.startsWith(u8, bare, "var ")) "var " else continue;
        const rest = bare[keyword.len..];
        const end = std.mem.indexOfAny(u8, rest, ": ") orelse continue;
        if (n == names.len) break;
        names[n] = rest[0..end];
        indents[n] = line.len - bare.len;
        n += 1;
    }

    for (names[0..n], 0..) |a, i| {
        var seen: usize = 0;
        var last: usize = 0;
        for (names[i..n], indents[i..n]) |b, indent| {
            if (!std.mem.eql(u8, a, b)) continue;
            if (seen > 0 and indent <= last) continue;
            last = indent;
            seen += 1;
        }
        if (seen >= 2) return true;
    }
    return false;
}

test "some generated program shadows one name inside another's scope" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Two levels, which is what makes a scope rule observable at all: a name
    // means the inner binding until the block ends and the outer one after.
    //
    // Three levels is what proves closing one scope reveals what the middle
    // one hid rather than what the outermost holds, and it is asserted here at
    // two rather than three deliberately. Three occurs in about one seed in
    // four hundred, so a test for it passes or fails on which seeds happen to
    // land there -- it broke twice on changes that had nothing to do with
    // scoping, because every added choice reshuffles the stream. What would
    // make it worth asserting is a generator that builds the chain on purpose
    // rather than reaching it by coincidence.
    var found = false;
    for (0..500) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        if (shadowedTwoDeep(try generate(gpa, bytes, .{}))) found = true;
    }
    try testing.expect(found);
}
test "some generated program writes both spellings of a variant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Both in one program, not merely both across the corpus: the two are
    // checked by different code, and a program holding each is what makes a
    // rewrite between them meaningful later.
    var found = false;
    for (0..200) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const seen = Spellings.of(try generate(gpa, bytes, .{}));
        if (seen.qualified and seen.from_context) found = true;
    }
    try testing.expect(found);
}

test "some generated program declares a structure, builds one, and reads a field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Three separate paths: a declaration is laid out, a literal writes every
    // field at its own offset, and a read takes one back. A generator that
    // only built would leave the offset it read from untested.
    try testing.expect(try seedsContaining(gpa, 200, "struct S") > 0);
    try testing.expect(try seedsContaining(gpa, 200, ".{ f") > 0);
    try testing.expect(try seedsContaining(gpa, 200, ".f0") > 0);
}

test "some generated structure holds another" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Nesting is where alignment is inherited and where an offset summed from
    // the wrong base hides, so a generator that only ever wrote flat
    // structures would leave both to the corpus.
    try testing.expect(try seedsContaining(gpa, 400, ": S0") > 0);
}

test "some generated program reaches a place through more than one field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A place is a name followed by any chain of fields, and the second step
    // is where an offset summed from the wrong base shows. A generator taking
    // one step reached only the shape a flat structure already had.
    var found = false;
    for (0..400) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, text, at, ".f")) |i| {
            at = i + 2;
            // `.f0.f`; literal field labels have no leading dot and cannot be
            // mistaken for a member-access chain.
            if (i + 4 < text.len and std.ascii.isDigit(text[i + 2]) and
                text[i + 3] == '.' and text[i + 4] == 'f') found = true;
        }
    }
    try testing.expect(found);
}

test "some generated program names a place under something transparent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Two shapes that put a place somewhere a rule has to look through.
    //
    // Parentheses mean nothing at all, so `(x)` must behave exactly as `x`
    // does -- a walk over places that stopped at one would find a different
    // place, or none. A widening conversion is the opposite: it *is* an
    // operator, so it reads its operand however the expression around it is
    // used, and it is the only one the generator can write over a place
    // without risking a trap.
    //
    // Neither was generated, and between them they are what turns two rules
    // from "a case someone thought to write" into "the property fails".
    var parenthesised = false;
    var converted = false;
    for (0..400) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});

        var at: usize = 0;
        while (std.mem.indexOfPos(u8, text, at, "(_")) |i| {
            at = i + 2;
            // `(_v0)` and not `(_v0 + 1)` or a call's argument list: a name,
            // then the closing parenthesis and nothing else.
            var j = i + 1;
            while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or text[j] == '_')) : (j += 1) {}
            if (j < text.len and text[j] == ')' and (i == 0 or text[i - 1] != '4')) parenthesised = true;
        }

        if (std.mem.indexOf(u8, text, "Int64(_") != null) converted = true;
    }
    try testing.expect(parenthesised);
    try testing.expect(converted);
}

test "some generated program writes through a place that is not a whole binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Assigning to a field and passing one `&` are the two ways a program
    // writes into part of a value, and both compute the field's address
    // rather than the binding's.
    //
    // A thousand seeds for the second of them, where every other shape here is
    // held over four hundred. A marked field path needs a call with an `inout`
    // parameter of a type some structure in scope holds a field of, and that
    // conjunction is met by six seeds in a thousand -- so the window is the
    // sample this density needs, and it moves whenever a production is added
    // and the stream re-phases.
    var assigned = false;
    var marked = false;
    for (0..1000) |seed| {
        const bytes = try choicesFromSeed(gpa, seed, 64);
        const text = try generate(gpa, bytes, .{});

        var at: usize = 0;
        while (std.mem.indexOfPos(u8, text, at, " = ")) |i| {
            at = i + 3;
            // A `let` or `var` names a fresh binding, never a place.
            const line = std.mem.lastIndexOfScalar(u8, text[0..i], '\n') orelse 0;
            if (std.mem.indexOf(u8, text[line..i], ".f") != null and
                std.mem.indexOf(u8, text[line..i], "let ") == null and
                std.mem.indexOf(u8, text[line..i], "var ") == null) assigned = true;
        }

        at = 0;
        while (std.mem.indexOfPos(u8, text, at, "&")) |i| {
            at = i + 1;
            var j = i + 1;
            while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or
                text[j] == '_' or text[j] == '.')) : (j += 1)
            {}
            if (std.mem.indexOfScalar(u8, text[i..j], '.') != null) marked = true;
        }
    }
    try testing.expect(assigned);
    try testing.expect(marked);
}

test "some generated program uses a signed type, and negates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Signed types are where the checked arithmetic has a negative edge to
    // run out of, where a conversion has a sign to test, and where a narrow
    // load sign-extends rather than zero-extends. None of it was reached by a
    // generated program while every value the generator built was a `UInt8`.
    try testing.expect(try seedsContaining(gpa, 200, "Int8") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "Int64") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "-(") > 0);
}

test "some generated program loops, breaks, continues and returns early" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A `loop` is the only construct whose type comes from its break sites
    // rather than from anything written down, so `[T-Loop]` was checked by
    // nothing generated. `continue` and an early `return` are the two ways a
    // body stops running its remaining statements.
    try testing.expect(try seedsContaining(gpa, 200, "loop {") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "break ") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "continue;") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "return ") > 0);
}

test "some generated program walks an array in each of the three forms" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Each form separately, because each is its own rule about the binder: a
    // value the walk hands over, a place it lends, and a place it lends
    // writably. A needle over `for ` alone would be met by any one of them and
    // would report the other two as covered -- and so is ` in _w`, which every
    // form spells: `for read _e4 in _w3` answers it as readily as the taking
    // form does. The consuming form is the one with nothing between `for` and
    // its binder, which is what this asks.
    try testing.expect(try seedsContaining(gpa, 200, "for _e") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "for read ") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "for inout ") > 0);
}

test "some generated program declares a projection" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The one member form whose body is a path rather than code, and the trait
    // that makes it declarable: an inherent `impl` refuses a projection, so a
    // program reaching the member form is a program that wrote both.
    try testing.expect(try seedsContaining(gpa, 200, "proj at(") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "trait _Places {") > 0);

    // And not every program, so the shapes drawn beside it are still reached:
    // a group written unconditionally would put its declarations in front of
    // every other axis this generator is sampled on.
    try testing.expect(try seedsContaining(gpa, 200, "proj at(") < 200);
}

test "a generated program takes tuples apart by position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const bytes = try choicesFromSeed(gpa, 0, 64);
    const text = try generate(gpa, bytes, .{ .max_tuples = 2 });
    try testing.expect(std.mem.indexOf(u8, text, "let (") != null);
    try testing.expect(std.mem.indexOf(u8, text, "-> (") != null);

    // None where the options ask for none.
    const none = try generate(gpa, bytes, .{ .max_tuples = 0 });
    try testing.expect(std.mem.indexOf(u8, none, "let (") == null);
    try testing.expect(std.mem.indexOf(u8, none, "-> (") == null);
}

test "some generated program writes back through a parameter" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Declaring one and marking the argument are different things, and a
    // generator that declared `inout` without ever calling such a function
    // would leave the marker -- and the exclusivity rule behind it -- reached
    // by nothing.
    try testing.expect(try seedsContaining(gpa, 200, "inout ") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "(&") > 0);
}

test "some generated program cancels a schedule" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A `defer` beside a disposal on the path that leaves is the only shape
    // that cancels one, and cancellation is the whole of why a schedule needs
    // no runtime flag. While the generator wrote `defer` and nothing else, it
    // reached the syntax and never the decision: over four hundred seeds, no
    // generated program cancelled anything.
    try testing.expect(try seedsContaining(gpa, 200, "defer _drop(") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "defer let _l") > 0);
    try testing.expect(try seedsContaining(gpa, 200, "        return 0;\n    }\n") > 0);
}

test "a generated program with an array formats and re-parses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The generator draws arrays now, so the formatter meets them in every
    // position a type appears in rather than only the ones a case wrote down.
    try testing.expect(try seedsContaining(gpa, 200, "; 1]") + try seedsContaining(gpa, 200, "; 2]") > 0);
}

test "generated newtypes admit the arithmetic rejection mutation" {
    const mutation = @import("mutate.zig");
    var applied: u32 = 0;
    const seeds = 32;
    for (0..seeds) |seed| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        // That these programs are accepted is held by the coverage sweep,
        // which checks the first four hundred seeds beside the library.
        const text = try generate(gpa, try choicesFromSeed(gpa, seed, 64), .{});

        // The newtype mutation reads the program's own text, so it is applied
        // to a tree of that text alone; a tuple there has no library to be
        // typed by, and the mutation has nothing to say about one.
        const source: Source = .{ .path = "generated.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var res = try resolveTree(gpa, &ast, &sink);
        const typing = try typecheckTree(gpa, &res, &sink);
        if (try mutation.Mutation.summed_newtype.apply(gpa, &ast, &res.resolution, &typing, text)) |broken| {
            applied += 1;
            try testing.expect(mutation.asClaimed(try mutation.verdictOf(gpa, broken, .program), .summed_newtype));
        }
    }
    try testing.expect(applied * 100 >= mutation.Mutation.summed_newtype.generatedFloor() * seeds);
}
