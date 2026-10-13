const std = @import("std");
const testing = std.testing;
const token = @import("../lexer/token.zig");
const TokenId = token.TokenId;
const TokenRange = token.TokenRange;

const none_index = std.math.maxInt(u32);

/// The greatest height of a tree the parser hands to later passes.
pub const max_tree_height: usize = 1000;

/// The fewest components a tuple holds. One parenthesised value is a group.
pub const min_tuple_arity: u32 = 2;

/// The most components a tuple holds. A product with more positional parts is
/// a struct with its names withheld. The prelude declares `Tuple2` through
/// `Tuple8` to match.
pub const max_tuple_arity: u32 = 8;

/// Whether `count` components make a tuple. The one statement of the bound:
/// the parser refuses a count outside it, and every later pass asks here
/// whether a node it holds is one the parser admitted.
pub fn isTupleArity(count: usize) bool {
    return count >= min_tuple_arity and count <= max_tuple_arity;
}

test "a tuple has two to eight components" {
    try std.testing.expect(!isTupleArity(0));
    try std.testing.expect(!isTupleArity(1));
    try std.testing.expect(isTupleArity(2));
    try std.testing.expect(isTupleArity(max_tuple_arity));
    try std.testing.expect(!isTupleArity(max_tuple_arity + 1));
}

/// Index into the expression table. A distinct type so a statement index or a
/// token index cannot be passed in its place.
pub const ExprId = enum(u32) {
    none = none_index,
    _,

    pub fn at(i: u32) ExprId {
        return @enumFromInt(i);
    }

    pub fn index(self: ExprId) u32 {
        return @intFromEnum(self);
    }
};

pub const StmtId = enum(u32) {
    none = none_index,
    _,

    pub fn at(i: u32) StmtId {
        return @enumFromInt(i);
    }

    pub fn index(self: StmtId) u32 {
        return @intFromEnum(self);
    }
};

/// Index into the block table. Blocks are only ever referenced by a `block`
/// expression, which always has one, so there is no absent case.
pub const BlockId = enum(u32) {
    _,

    pub fn at(i: u32) BlockId {
        return @enumFromInt(i);
    }

    pub fn index(self: BlockId) u32 {
        return @intFromEnum(self);
    }
};

/// A half-open range into `Ast.block_stmts`.
pub const StmtRange = struct {
    start: u32,
    end: u32,

    pub fn len(self: StmtRange) u32 {
        return self.end - self.start;
    }
};

/// An index into the tree's side array, where a node with more children than
/// a payload holds keeps them. Named rather than a bare `u32` so a reader can
/// tell it apart from an expression index.
pub const ExtraIndex = enum(u32) {
    _,

    pub fn at(i: u32) ExtraIndex {
        return @enumFromInt(i);
    }

    pub fn index(self: ExtraIndex) u32 {
        return @intFromEnum(self);
    }
};

/// An interpolation format records how one value embedded in text renders:
/// the trait it renders through and the layout its format spec asks for.
pub const InterpolationFormat = @import("format_spec.zig").Format;

/// An index into `Ast.interpolation_formats`.
pub const InterpolationFormatIndex = enum(u32) {
    none = none_index,
    _,

    pub fn at(i: u32) InterpolationFormatIndex {
        return @enumFromInt(i);
    }

    pub fn index(self: InterpolationFormatIndex) u32 {
        return @intFromEnum(self);
    }
};

/// Index into the declaration table.
pub const DeclId = enum(u32) {
    none = none_index,
    _,

    pub fn at(i: u32) DeclId {
        return @enumFromInt(i);
    }

    pub fn index(self: DeclId) u32 {
        return @intFromEnum(self);
    }
};

/// A half-open range into the parameter table.
/// A half-open run of declarations, which is what a module is within the
/// program's tree.
pub const DeclRange = struct {
    start: u32,
    end: u32,

    pub fn len(self: DeclRange) u32 {
        return self.end - self.start;
    }

    pub fn contains(self: DeclRange, d: DeclId) bool {
        return d.index() >= self.start and d.index() < self.end;
    }
};

pub const ParamRange = struct {
    start: u32,
    end: u32,

    pub fn len(self: ParamRange) u32 {
        return self.end - self.start;
    }
};

/// A named source observed or transferred into a closure environment.
pub const Capture = struct {
    name: TokenId,
    source: ExprId,
    convention: Convention,
    convention_token: TokenId,
    equals: TokenId,
};

/// How a callable reaches an argument or its captured environment.
pub const Convention = enum(u8) {
    /// A lend. The callee may inspect the argument but may not move from it,
    /// regardless of the argument's copying or settlement capabilities.
    read,
    /// May be moved from, and must be refilled before the callee returns.
    inout,
    /// The callee takes ownership. How a linear value is finally disposed of:
    /// the obligation to consume it passes with the argument.
    sink,
};

/// The part of a callable type that keys the implementations written for it:
/// its invocation and each parameter's convention, in order. Parameter types
/// and the result are what two implementations of one shape are told apart by
/// where their trait arguments differ, so they are not part of the key. The
/// resolver reads it off a written type and the checker off an interned one,
/// and both feed this one routine, so a written head and the type it settles
/// to reach one chain.
///
/// The key is exact: the parameter count in the low six bits, then the
/// invocation, then two bits per convention. A callable of more than
/// `max_shape_parameters` parameters has no shape, so no implementation is
/// keyed for one and none is found for one.
pub const CallableShape = enum(u128) {
    _,

    pub const max_shape_parameters = 60;

    pub const Builder = struct {
        count: u32 = 0,
        invocation: Convention,
        conventions: u128 = 0,

        pub fn begin(invocation: Convention) Builder {
            return .{ .invocation = invocation };
        }

        pub fn parameter(self: *Builder, convention: Convention) void {
            if (self.count < max_shape_parameters) {
                self.conventions |= @as(u128, @intFromEnum(convention)) << @intCast(2 * self.count);
            }
            self.count += 1;
        }

        /// The shape, or null where the callable has more parameters than a
        /// shape can name.
        pub fn finish(self: *const Builder) ?CallableShape {
            if (self.count > max_shape_parameters) return null;
            const header = (@as(u128, @intFromEnum(self.invocation)) << 6) | self.count;
            return @enumFromInt((self.conventions << 8) | header);
        }
    };
};

test "a callable shape tells apart invocation, arity and each parameter's convention" {
    const shape = struct {
        fn of(invocation: Convention, conventions: []const Convention) ?CallableShape {
            var builder: CallableShape.Builder = .begin(invocation);
            for (conventions) |convention| builder.parameter(convention);
            return builder.finish();
        }
    }.of;
    const all = [_]Convention{ .read, .inout, .sink };
    try testing.expectEqual(shape(.read, &.{ .inout, .read }), shape(.read, &.{ .inout, .read }));
    // Every pair of conventions, under every invocation, is a shape of its own.
    var seen: [3 * 9]?CallableShape = undefined;
    var count: usize = 0;
    for (all) |invocation| for (all) |first| for (all) |second| {
        const found = shape(invocation, &.{ first, second });
        for (seen[0..count]) |other| try testing.expect(other != found);
        seen[count] = found;
        count += 1;
    };
    try testing.expect(shape(.read, &.{.read}) != shape(.read, &.{ .read, .read }));
    try testing.expect(shape(.read, &.{}) != shape(.read, &.{.read}));
    try testing.expect(shape(.read, &.{ .inout, .read }) != shape(.read, &.{.inout}));
    const sixty: [60]Convention = @splat(.sink);
    try testing.expect(shape(.read, &sixty) != null);
    const many: [61]Convention = @splat(.read);
    try testing.expectEqual(@as(?CallableShape, null), shape(.read, &many));
}

/// One parameter. Small and fixed, so a plain struct in a flat table rather
/// than a node category of its own.
pub const Param = struct {
    /// The parameter's name. A lambda parameter written as a tuple pattern
    /// has none, so this is the pattern's opening parenthesis: a token that
    /// is not an identifier, which every pass already passes over as it does
    /// the stand-in a recovered parameter carries.
    name: TokenId,
    /// The `tuple_pattern` a lambda parameter takes its argument apart with,
    /// `ExprId.none` for a named parameter.
    pattern: ExprId = .none,
    /// The `param_argument` standing for a pattern parameter's argument, which
    /// the pattern takes apart as `let (a, b) = argument` would. The resolver
    /// points it at the parameter's binding, so every rule about a place
    /// reads the argument as it reads a named parameter. `ExprId.none` for a
    /// named parameter.
    argument: ExprId = .none,
    /// The declared type. A parameter is always annotated.
    written: TypeRef,
    convention: Convention,
    /// The constant a caller may omit the argument in favour of.
    /// `ExprId.none` for a parameter no call may skip.
    default: ExprId,
    /// Whether the parser read this parameter's name only to recover from a
    /// parameter it could not read -- `fn(UInt64)`, missing its `:`. The
    /// token is whatever stood where a name was expected, so it declares
    /// nothing a rule about names can hold to account: [N-Case],
    /// [N-Duplicate] and [N-Unused] each pass it over.
    recovered: bool = false,
};

/// A half-open range into the type-parameter table.
pub const TypeParamRange = struct {
    start: u32,
    end: u32,

    pub const empty: TypeParamRange = .{ .start = 0, .end = 0 };

    pub fn len(self: TypeParamRange) u32 {
        return self.end - self.start;
    }
};

/// A type a declaration is generic over, and what it requires of an argument.
///
/// The bounds are a range into a table of names and their arguments. Whether
/// each names a capability or a trait is a question about names, and the parser
/// does not answer questions about names -- it records the list and the
/// resolver classifies it, the same way `p.x` is recorded and then decided.
pub const TypeParam = struct {
    name: TokenId,
    bounds: BoundRange,
    /// Declared `phantom`: the parameter appears in no field and is read for
    /// identity alone. A flag rather than a side table, because it is a
    /// modifier on a thing the parser already builds.
    phantom: bool = false,
    /// The type written after `=`: the argument a written type omits for this
    /// parameter. Absent where `wasWritten` is false.
    default: TypeRef = .{ .name = .none },
};

/// A half-open range into the bound table.
pub const BoundRange = struct {
    start: u32,
    end: u32,

    pub const empty: BoundRange = .{ .start = 0, .end = 0 };

    pub fn len(self: BoundRange) u32 {
        return self.end - self.start;
    }
};

/// A half-open range into the trailing-predicate table.
pub const WherePredicateRange = struct {
    start: u32,
    end: u32,

    pub const empty: WherePredicateRange = .{ .start = 0, .end = 0 };

    pub fn len(self: WherePredicateRange) u32 {
        return self.end - self.start;
    }
};

/// One requirement in a trailing `where` clause.
///
/// The subject is a whole written type so a projected subject can use the same
/// record when it is admitted. Requirements use the existing bound table, so a
/// bound has one representation wherever it is written.
pub const WherePredicate = struct {
    subject: TypeRef,
    bounds: BoundRange,
};

/// One written reference to a trait.
///
/// `name` is the final component resolution and diagnostics point at. A dotted
/// spelling retains its complete token run in `path`; a bare name has no run.
/// Arguments belong to the trait reference in every position that accepts one.
pub const TraitRef = struct {
    name: TokenId = .none,
    path: TokenRange = .empty,
    args: TypeRefRange = .empty,
};

/// Index into the derive-trait table.
pub const DeriveTraitId = enum(u32) {
    none = none_index,
    _,

    pub fn at(i: u32) DeriveTraitId {
        return @enumFromInt(i);
    }

    pub fn index(self: DeriveTraitId) u32 {
        return @intFromEnum(self);
    }
};

/// A half-open range into the derive-trait table.
pub const DeriveTraitRange = struct {
    start: u32,
    end: u32,

    pub const empty: DeriveTraitRange = .{ .start = 0, .end = 0 };

    pub fn len(self: DeriveTraitRange) u32 {
        return self.end - self.start;
    }
};

/// One trait named by a single or grouped derive request.
pub const DeriveTrait = struct {
    ref: TraitRef,
    tokens: TokenRange,
};

pub const AttributeItemKind = enum(u8) { opaque_, linear, copyable, carrier, derive, unknown };

pub const AttributeItem = struct {
    kind: AttributeItemKind,
    name: TokenId,
    tokens: TokenRange,
    derive_traits: DeriveTraitRange = DeriveTraitRange.empty,
};

pub const AttributeItemRange = struct {
    start: u32,
    end: u32,

    pub const empty: AttributeItemRange = .{ .start = 0, .end = 0 };
    pub fn len(self: AttributeItemRange) u32 {
        return self.end - self.start;
    }
};

pub const AttributeGroup = struct {
    at: TokenId,
    open: TokenId = .none,
    close: TokenId = .none,
    items: AttributeItemRange,
    tokens: TokenRange,
};

pub const AttributeGroupRange = struct {
    start: u32,
    end: u32,

    pub const empty: AttributeGroupRange = .{ .start = 0, .end = 0 };
    pub fn len(self: AttributeGroupRange) u32 {
        return self.end - self.start;
    }
};

/// Index into the template-requirement table.
pub const TemplateRequirementId = enum(u32) {
    none = none_index,
    _,

    pub fn at(i: u32) TemplateRequirementId {
        return @enumFromInt(i);
    }

    pub fn index(self: TemplateRequirementId) u32 {
        return @intFromEnum(self);
    }
};

/// A half-open range into the template-requirement table.
pub const TemplateRequirementRange = struct {
    start: u32,
    end: u32,

    pub const empty: TemplateRequirementRange = .{ .start = 0, .end = 0 };

    pub fn len(self: TemplateRequirementRange) u32 {
        return self.end - self.start;
    }
};

/// One template-only structural requirement.
pub const TemplateRequirement = struct {
    kind: Kind,
    reflect: TokenId,
    selector: TokenId,
    bounds: BoundRange = BoundRange.empty,
    target_shape: TargetShape = .struct_,

    pub const Kind = enum {
        components,
        derived_supertraits,
        target,
    };

    pub const TargetShape = enum {
        struct_,
        enum_,
        newtype,

        pub fn declaration(self: TargetShape) Decl.Tag {
            return switch (self) {
                .struct_ => .struct_,
                .enum_ => .enum_,
                .newtype => .newtype,
            };
        }

        pub fn spelling(self: TargetShape) []const u8 {
            return switch (self) {
                .struct_ => "struct",
                .enum_ => "enum",
                .newtype => "type",
            };
        }
    };
};

/// A bound: a named trait/capability promise or one structural call signature.
///
/// The arguments sit in the flat range every written type's arguments sit in,
/// so `Index[Range[UInt64]]` nests with nothing added and no second storage
/// for type arguments exists for the first to drift from.
pub const TraitBound = struct {
    kind: Kind = .named,
    named: TraitRef = .{},
    callable: CallableTypeId = .none,

    pub const Kind = enum { named, callable };
};

/// A half-open range into the variant table.
pub const VariantRange = struct {
    start: u32,
    end: u32,

    pub fn len(self: VariantRange) u32 {
        return self.end - self.start;
    }
};

/// A half-open range into the field table.
pub const FieldRange = struct {
    start: u32,
    end: u32,

    pub fn len(self: FieldRange) u32 {
        return self.end - self.start;
    }
};

/// One named or positional part of a type.
///
/// A structure's field is named; what a variant carries is not, so its name is
/// `.none`. One row serves both, because the two are laid out by one rule and
/// a second table would only let them drift.
/// A half-open range into the type-reference table.
pub const TypeRefRange = struct {
    start: u32,
    end: u32,

    pub const empty: TypeRefRange = .{ .start = 0, .end = 0 };

    pub fn len(self: TypeRefRange) u32 {
        return self.end - self.start;
    }
};

/// A bracket written directly before a call whose contents also read as a
/// list of types, beside the index reading the expression node holds. Which
/// reading applies depends on what the head names, so the parser records both.
pub const BracketTypes = struct {
    at: ExprId,
    args: TypeRefRange,
};

/// An entry in the written-type table.
pub const TypeRefId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: usize) TypeRefId {
        return @enumFromInt(@as(u32, @intCast(i)));
    }

    pub fn index(self: TypeRefId) usize {
        return @intFromEnum(self);
    }
};

/// An entry in the structural-callable-type table.
pub const CallableTypeId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: usize) CallableTypeId {
        return @enumFromInt(@as(u32, @intCast(i)));
    }

    pub fn index(self: CallableTypeId) usize {
        return @intFromEnum(self);
    }
};

/// The parameter and result types one structural callable type writes.
pub const ContractRange = struct {
    start: u32 = 0,
    end: u32 = 0,
};

pub const ContractStep = union(enum) {
    field: TokenId,
    dereference: TokenId,
};

pub const ContractStepRange = struct {
    start: u32 = 0,
    end: u32 = 0,
};

/// Written spelling and parser-settled root-out projections of a contract path.
pub const ContractPath = struct {
    written: TokenRange = .empty,
    root: TokenId = .none,
    steps: ContractStepRange = .{},

    pub const empty: ContractPath = .{};
};

/// One source edge in a written callable contract.
pub const Contract = struct {
    kind: enum { borrows, carries, retains },
    at: TokenId,
    source: ContractPath,
    target: ContractPath = .empty,
    destination: ContractPath = .empty,
    borrows_source: bool = false,
    /// Comma ending the contract list, recorded on its last source edge.
    trailing_comma: TokenId = .none,
};

pub const CallableType = struct {
    at: TokenId,
    invocation: Convention = .read,
    invocation_token: TokenId = .none,
    params: ParamRange,
    result: TypeRef,
    contracts: ContractRange = .{},
};

/// A written type. Nested types use flat TypeRefId or TypeRefRange children;
/// names remain tokens until resolution assigns declaration identities.
pub const TypeRef = struct {
    /// What was written. A tag rather than an absent name: an absent name
    /// leaves every reader compiling unchanged while meaning something new.
    kind: Kind = .named,
    /// Where it begins. Every written type occupies tokens and the first is a
    /// fact about it, which `name` is not: an array names nothing, and a
    /// reader that wants a position rather than a name had nothing to point
    /// at -- so a formatter walked backwards and a message pointed at line one.
    at: TokenId = .none,
    /// The type name or selected member; other forms may carry a delimiter.
    name: TokenId,
    /// The arguments written after the name. For an array, the one element
    /// type -- the children of a written type already sit in one flat range,
    /// which is what makes `[[UInt8; 2]; 3]` nest with nothing added.
    args: TypeRefRange = TypeRefRange.empty,
    /// How many elements, for an array. `.none` otherwise.
    ///
    /// An expression rather than a token, so `[T-ArraySize]` is asked of it by
    /// the constant-expression machinery that already exists. Read as a token
    /// it would need a second reader of the grammar.
    length: ExprId = ExprId.none,
    /// The `_` requesting a local literal's count. Mutually exclusive with
    /// `length`; this token is syntax, never a value expression or name use.
    inferred_length: TokenId = .none,
    /// The preceding written type of a member selection.
    base: TypeRefId = .none,
    /// The selection delimiter, retained when its member is incomplete.
    dot: TokenId = .none,
    /// The structural signature, for a callable type. `.none` otherwise.
    callable: CallableTypeId = .none,

    /// Whether anything was written at all.
    ///
    /// Asked instead of testing the name token, which an array leaves absent:
    /// a written type with no name is still a written type, and a reader that
    /// says otherwise decides there is no annotation on the one form that
    /// needs one most.
    pub fn wasWritten(self: TypeRef) bool {
        return switch (self.kind) {
            .named => self.name != TokenId.none,
            .selection => self.dot != .none,
            .array, .callable, .borrow, .grouped, .tuple => true,
        };
    }

    pub const Kind = enum {
        grouped,
        borrow,
        /// A name, and the arguments it was given.
        named,
        /// `[T; N]`: the element in `args`, the count in `length`.
        array,
        /// `fn(parameters) -> result`, held in the callable-type table.
        callable,
        /// A namespace member or associated type selected from `base`.
        /// `name` is the selected token; `args` apply to that member.
        selection,
        /// `(A, B)`: the components in `args`, in written order. `at` is the
        /// opening parenthesis and `name` is `.none`.
        tuple,
    };
};

pub const Field = struct {
    name: TokenId = .none,
    /// Which type the name names is a question about names, so the parser
    /// records what was written and the checker answers it -- the same division
    /// a parameter's annotation already makes.
    written: TypeRef,
    /// The last token the written type occupies: the closing bracket where it
    /// has arguments, the name itself where it has none.
    ///
    /// Recorded by the parser because the parser is what knows. Worked out
    /// afterwards it takes a second reader of the grammar -- one that has to
    /// match brackets, and that has to grow again every time the syntax of a
    /// type does.
    ///
    /// A parameter, a return type and a `let` annotation are written types too
    /// and carry no end. Nothing asks them for one, and a field nothing reads is
    /// weight in every node of a tree sized by the program -- so the end is
    /// recorded where it is asked for and nowhere else.
    type_end: TokenId = .none,
};

/// One alternative of an enum.
pub const Variant = struct {
    name: TokenId,
    /// What it carries. Empty where it carries nothing.
    fields: FieldRange = .{ .start = 0, .end = 0 },
};

/// How far outside its own module a declaration's name reaches.
///
/// Four states rather than two, because root reach and sealing are distinct
/// answers to the same question: whether what is written here is reachable from
/// outside, and if so how much of it. A boolean would need another field beside
/// it that could disagree with it.
pub const Visibility = enum(u8) {
    /// Reachable only from the module that declares it. The default: what a
    /// module exports is a decision, and a decision is written down.
    private,
    /// Reachable by name from modules loaded from the same root.
    internal_,
    /// Reachable by name from any module that imports this one.
    pub_,
    /// Reachable by name, with its representation sealed: outside the module
    /// nothing may build one, take one apart, or depend on what it holds.
    opaque_,
};

/// The declaration's policy; owned parts determine effective capabilities.
pub const OwnershipPolicy = enum(u8) {
    /// Move-only, with settlement inherited from owned parts.
    affine,
    /// Duplication is permitted when all owned parts permit it.
    copyable,
    /// Mandatory consumption even when no owned part requires it.
    linear,
};

/// Built-in positive capability bounds; unrestricted is the default promise.
pub const CapabilityRequirement = enum(u8) { unrestricted, discardable, copyable };

/// Where a declaration's code comes from; `Decl.origin` says what each means.
pub const Origin = enum { written, external, provided };

/// A top-level declaration. A fourth node category beside expressions,
/// statements and blocks, because a declaration is not an expression: it
/// introduces a name and has no value.
pub const Decl = struct {
    tag: Tag,
    /// The `fn` keyword.
    main_token: TokenId,
    token_range: TokenRange,
    name: TokenId,
    params: ParamRange,
    /// The types this declaration is generic over. Empty for one that is not.
    type_params: TypeParamRange = TypeParamRange.empty,
    /// What a declared type requires of whatever settles it. Empty for
    /// anything else, and for a declared type written without one.
    ///
    /// On the declaration rather than on a parameter of it, because a declared
    /// type is not generic: the bound is what the trait asks of every
    /// implementation, and the declaration is the thing every implementation
    /// answers.
    bounds: BoundRange = BoundRange.empty,
    /// The trailing requirements written after a callable result.
    where_predicates: WherePredicateRange = WherePredicateRange.empty,
    contracts: ContractRange = .{},
    /// The `where` keyword, retained so formatting preserves whether the
    /// clause begins on the callable head's line or its own.
    where_at: TokenId = TokenId.none,
    /// The type written on the declaration: what a function returns, and what
    /// a constant holds. `.none` where none could be parsed.
    ///
    /// One slot, because it answers one question -- which written type this
    /// declaration names -- and every reader of it asks that question. A
    /// second slot for a constant's type would be the same question with two
    /// answers, and the pass that read the wrong one would look right.
    returns: TypeRef,
    /// The body block, or `.none` where it could not be parsed. Meaningless
    /// for an enum.
    body: ExprId,
    /// What a constant is bound to. `ExprId.none` for every other
    /// declaration, which is what tells a constant from a function whose body
    /// happens to be one expression.
    init: ExprId = ExprId.none,
    /// An enum's alternatives. Empty for anything else.
    variants: VariantRange,
    /// A structure's fields. Empty for anything else.
    fields: FieldRange = .{ .start = 0, .end = 0 },
    /// The type this declaration belongs to -- the name written after `impl`
    /// -- or `.none` for one written at the top level of a file.
    ///
    /// A name rather than a handle, because an `impl` may sit in a different
    /// file from the type it names and the parser has no id for it. Which type
    /// it is, is a question about names, so the resolver answers it.
    owner: TokenId = TokenId.none,
    /// The trait an `impl` names, or an empty reference where it names only a
    /// type. Written rather than resolved because the parser cannot decide
    /// which declaration a bare or qualified name reaches.
    trait_ref: TraitRef = .{},
    /// Contextual delegation keyword and its direct stored-field target.
    delegation: struct {
        via: TokenId = .none,
        target: TokenId = .none,
    } = .{},
    /// The traits a derive request names. Empty for every other declaration.
    derive_traits: DeriveTraitRange = DeriveTraitRange.empty,
    derive_syntax: struct {
        /// Parentheses retained when the source used grouped derive syntax.
        group_open: TokenId = .none,
        group_close: TokenId = .none,
        /// Parser admission of the derive's constructor-uniform receiver shape.
        head_valid: bool = true,
    } = .{},
    /// Structural requirements written on a template implementation.
    template_requirements: TemplateRequirementRange = TemplateRequirementRange.empty,
    /// The arguments an `impl` wrote on its head: `impl[T] Show for Holder[T]`
    /// records `[T]` here, and `Holder` in `name`.
    ///
    /// Beside the name rather than in `returns`, which holds the written type
    /// a declaration names and is read of every declaration whatever its tag
    /// -- a mutation retyping return types, and the sweep that finds every
    /// written type in a program, both reach it without asking. A head parked
    /// there is a return type to each of them.
    head_args: TypeRefRange = TypeRefRange.empty,
    head_kind: TypeRef.Kind = .named,
    /// Where the declaration's code comes from: the body written with it, a
    /// symbol the runtime provides (`extern`), or a trait's operation written
    /// with a body, which every type implementing the trait offers and no
    /// implementation supplies.
    ///
    /// A field and not a tag. Nearly every reader of a declaration asks only
    /// whether it is a function, and a tag would make each of those name the
    /// other kinds too -- which is one rule with several spellings and a place
    /// to forget one. What actually differs is asked by a few passes, and each
    /// asks it here.
    origin: Origin = .written,
    /// Whether this function is a test: one the compiler writes the only call
    /// to, and which nothing that ships contains.
    ///
    /// A field beside `origin` and for its reason. What a test changes is who
    /// calls it and whether it is emitted, and everything else about the
    /// declaration is a function's -- so a tag of its own would make every
    /// reader that asks "is this a function" name two, which is one rule with
    /// two spellings and a place to forget the second.
    is_test: bool = false,
    /// Whether a test succeeds by reaching a runtime trap rather than by
    /// returning success. Meaningless for declarations that are not tests.
    expects_trap: bool = false,
    /// The written ownership policy. Meaningless for non-type declarations.
    ownership_policy: OwnershipPolicy = .affine,
    /// How far this declaration's name reaches. An `import` is always private:
    /// what a module imports is its own business, and re-export would make one
    /// module's namespace depend on another's imports.
    visibility: Visibility = .private,
    /// Whether a linker publishes this declaration.
    ///
    /// Beside `visibility` rather than inside it. How far a name reaches in
    /// Linea and whether the outside world may link against it are two
    /// questions, and `pub export` answers one of each -- so a fourth
    /// `Visibility` state could not spell what this has to spell.
    is_export: bool = false,
    /// The dotted path an `import` names, one identifier per element with the
    /// dots between them. Empty for anything else.
    ///
    /// Stored rather than rediscovered by walking out from the keyword: the
    /// parser had the run in hand, and a consumer that reconstructs it has to
    /// know which tokens end it -- which is the parser's question, asked again
    /// somewhere it can be answered differently.
    path: TokenRange = TokenRange.empty,
    /// Whether a newtype's `where it in lo..=hi` clause was written.
    /// Meaningless for every other tag. `refinement_lo`, `refinement_hi` and
    /// `refinement_inclusive` hold `.none`/a default where a malformed clause
    /// could not be fully read -- already diagnosed at the point it happened.
    has_refinement: bool = false,
    /// The `where` keyword, or `.none` where none was written. What the
    /// formatter measures a line break against to keep a clause written on
    /// its own line there.
    refinement_at: TokenId = TokenId.none,
    /// The refinement's lower bound, a literal token by the v0 rule, and the
    /// `-` written before it where the bound is negative.
    refinement_lo_minus: TokenId = TokenId.none,
    refinement_lo: TokenId = TokenId.none,
    /// The refinement's upper bound, on the same terms.
    refinement_hi_minus: TokenId = TokenId.none,
    refinement_hi: TokenId = TokenId.none,
    /// Whether the refinement's range is written `..=` rather than `..`.
    refinement_inclusive: bool = false,

    pub const Tag = enum(u8) {
        function,
        /// `pub let name: T = e`. Binds a name to a value, in a module or in
        /// an `impl`.
        ///
        /// Nothing runs where it is written, so what it is bound to is a
        /// constant expression. Its type is written or inferred from that
        /// initializer, independently of the binding's uses.
        constant,
        /// `enum Name { A, B }`. Declares a type rather than a value, so it
        /// has no body and no parameters.
        enum_,
        /// `struct Name { x: T }`. Declares a type as named parts, laid out in
        /// the order they were written.
        struct_,
        /// `import a.b;`, or `import a.b as c;`. Names a directory relative to
        /// the importing module's own, and binds the module it holds to a name
        /// in this file. Declares no code and has no body.
        import_,
        /// `pub use m.Name;`. Binds another module's public declaration under
        /// that name here, as an alias rather than a fresh identity: what it
        /// binds is the declaration itself, so no later pass can tell which
        /// spelling reached one.
        use_,
        /// `impl Name { .. }`. Declares no name of its own: it groups what a
        /// type can do, and each of those carries its own visibility.
        ///
        /// A declaration all the same, so that its extent is recorded --
        /// without one, a rewrite that moves declarations moves the members
        /// out of the block and leaves the block behind.
        impl_,
        /// `template impl Trait { .. }`. An impl-shaped structural recipe owned
        /// by the trait rather than an implementation row for a concrete type.
        template_impl,
        /// `derive Trait for Type`. A bodyless request for the trait's
        /// structural template to produce an implementation for the type.
        derive_impl,
        /// `trait Name { fn f(…) -> T }`. Declares a set of signatures and no
        /// representation, so its braces hold neither fields nor variants and
        /// no modifier describing one can reach it.
        ///
        /// Its signatures are declarations owned by it, exactly as an `impl`'s
        /// members are owned by the type they belong to.
        trait_,
        /// `type Item` inside a trait, and `type Item = UInt8` inside an
        /// implementation of it. Declares a type the implementation settles:
        /// what it settles to sits in `returns`, and is absent on the trait's
        /// side, which asks for it and says nothing about what it is.
        ///
        /// A member of whatever declared it, exactly as a signature is, so
        /// the walk that pairs an implementation with its trait pairs these
        /// without a second walk of its own.
        associated_type,
        /// `proj at(inout self: Self, i: I) -> Elem` inside a trait, and the
        /// same carrying a body inside an implementation of it. A member that
        /// yields a place rather than a value: what its braces hold is a path
        /// the call site becomes, not code the call site runs.
        ///
        /// Shaped exactly as a signature -- parameters, a written result, a
        /// body -- so the walks that pair an implementation with its trait,
        /// name its members and hold each to its signature reach it without a
        /// second reading of any of them. A tag rather than a flag, so a switch
        /// over what a member can be says what a projection is before it
        /// compiles.
        projection,
        /// `trav positions = 0..4` inside a type's own implementation. Names
        /// the positions a lending walk runs through: what it is bound to sits
        /// in `init`, exactly as a constant's initialiser does.
        ///
        /// A tag rather than a constant carrying a flag, because what a
        /// traversal is used for is not what a constant is used for -- nothing
        /// names it, a walk finds it -- and a switch over what a member can be
        /// says so before it compiles.
        traversal_,
        /// `type Name = Base`, and `type Name = Base where it in lo..=hi`.
        /// A distinct nominal type over one base: same representation, a
        /// different contract. No braces, because nothing new is
        /// represented -- a type's braces hold its representation and
        /// nothing else, and this declares none of its own.
        newtype,
        /// `alias Name = Type`, and `alias Name[T] = Type`. Another name for
        /// the written type rather than a type of its own: every use of the
        /// name is the type it names, so it declares no representation and
        /// no identity. What it names sits in `returns`.
        alias,
        /// A declaration the parser could not read. Already diagnosed.
        err,
    };
};

/// One end of a range written as a literal: the digits, and the `-` before
/// them where one was written.
///
/// Two tokens rather than one, because a signed base's bounds are mostly
/// negative and a minus is a token of its own. `digits` is `.none` where the
/// bound could not be read, which is already diagnosed where it was found.
pub const Bound = struct {
    minus: TokenId = TokenId.none,
    digits: TokenId = TokenId.none,
};

/// A newtype's refinement clause: `where it in lo..=hi`.
///
/// Token-level rather than an `ExprId`: the bounds are literals by the v0
/// rule, and fold at the declaration rather than through the constant-
/// expression machinery a general expression would route through.
pub const Refinement = struct {
    /// The `where` keyword. Where the clause begins, and what a formatter
    /// measures a line break against to keep an own-line clause on its own
    /// line.
    at: TokenId,
    lo_minus: TokenId,
    lo_token: TokenId,
    hi_minus: TokenId,
    hi_token: TokenId,
    /// Whether the range is written `..=` rather than `..`.
    inclusive: bool,

    /// The lower bound as one value, and the upper likewise.
    pub fn lo(self: Refinement) Bound {
        return .{ .minus = self.lo_minus, .digits = self.lo_token };
    }

    pub fn hi(self: Refinement) Bound {
        return .{ .minus = self.hi_minus, .digits = self.hi_token };
    }
};

pub const Expr = struct {
    tag: Tag,
    /// The token that best identifies this node in a diagnostic: the operator,
    /// the literal, the identifier, the opening delimiter.
    main_token: TokenId,
    /// Full extent, so a diagnostic underline and a cursor hit-test are both
    /// direct lookups.
    token_range: TokenRange,
    data: Data,
    /// Source markers on a call; other expression tags leave both unset.
    call_flags: CallFlags = .{},

    pub const CallFlags = packed struct(u8) {
        fallible: bool = false,
        marked: bool = false,
        _: u6 = 0,
    };

    pub const Tag = enum(u8) {
        block,
        /// `if c { … } else { … }`. An expression: both arms agree on a type,
        /// and a missing `else` is an arm of type Unit.
        conditional,
        /// `while c { … }`. An expression of type Unit whatever its body: it
        /// may run zero times, so there is no value it could produce. `lhs` is
        /// the condition and `rhs` the body.
        while_,
        /// `x = e`. An expression of type Unit. `lhs` names the binding
        /// assigned and `rhs` is the value; returning the value instead would
        /// admit `f(x = 3)`, which reads as a comparison.
        assign,
        /// `p += e`, and the three like it. An expression of type Unit, whose
        /// `lhs` is a place rather than a value: it is evaluated to a location,
        /// and the read and the write both happen through that one location.
        ///
        /// Four tags rather than one carrying the operator, though the operator
        /// is recoverable from `main_token`. A tag is what an exhaustive switch
        /// counts, so four is what makes every pass say what it does with them;
        /// and a tag is where the category lives, which is what keeps these
        /// four from reading as settings of a construct that could also hold a
        /// short-circuiting one.
        add_assign,
        sub_assign,
        mul_assign,
        div_assign,
        rem_assign,
        /// `"a{x}b"`. A value holding the text around its interpolations and
        /// the values inside them, rendered in order by an implementation the
        /// compiler supplies.
        ///
        /// Its pieces alternate text and value in one run -- `text, value,
        /// text, … text` -- always odd and always beginning and ending with
        /// text, so no index needs remembering which kind it holds. Held in
        /// the run a call's arguments use, because it is the same shape.
        ///
        /// A construct rather than a rewrite: it carries evaluation order,
        /// which is the argument [ADR 0067] makes for compound assignment, and
        /// the tree holds what was written so the formatter prints it back.
        interp,
        /// `loop { … }`. Ends only through `break`, so its type is the one its
        /// break sites agree on. The operand is the body.
        loop_,
        /// `break` or `break e`, leaving the nearest enclosing loop of either
        /// kind. The operand is the value, or `.none` for a bare `break`,
        /// which yields Unit.
        break_,
        /// `continue`, beginning the next iteration of the nearest enclosing
        /// loop of either kind.
        continue_,
        /// `return` or `return e`, leaving the function. The operand is the
        /// value, or `.none`, which yields Unit.
        return_,
        /// `&p` at a call site. Not address-of and not a reference: it marks
        /// that the argument will be mutated, so a reader of the call sees
        /// which arguments can change without opening the callee.
        marked,
        /// `p.x`, or `Colour.Red`. The same shape and two different things,
        /// told apart by what the left side names rather than by the grammar:
        /// a type on the left selects a variant, a value on the left selects a
        /// field. `main_token` is the name after the `.`; the operand is what
        /// it is being selected from.
        field,
        /// `T { x = 1 }` or `.{ x = 1, ..base }`. The names and the values sit
        /// in the side array in pairs, which is the arrangement a match's arms
        /// already use. The callee slot holds the `..base` expression, or
        /// `.none` where the literal writes every field.
        struct_literal,
        /// `[a, b, c]`, whose type is the one expected here. Call-shaped: the
        /// elements sit in the side array a call's arguments use, and there is
        /// no callee.
        array_literal,
        /// `a[i]`. The head sits inline and the index is its one argument,
        /// which is the arrangement a binary operator already uses.
        index,
        /// `^k`, written where an index is. A value that counts back from a
        /// container's end, and the operand is what it counts back by.
        ///
        /// A node rather than a rewrite into the structure it stands for, for
        /// the reason `grouped` is one: a tree holding the structure could not
        /// be printed back as what someone wrote.
        from_end,
        /// `lo..hi` or `lo..=hi`. Non-associative and looser than every
        /// operator that computes a value, so an end is a whole computation.
        ///
        /// Its own tag rather than a binary shape: `inclusive` is not a
        /// second operand, and a binary node has nowhere to put it.
        range,
        /// `Colour.Red`, or `.Red` where the type comes from context. The
        /// operand is the enum's name, or `.none` for the second form: a
        /// leading `.` means the type is the one expected here.
        variant_ref,
        /// `match e { P => body, ... }`. The scrutinee sits inline and the
        /// arms sit in the side array as pattern-and-body pairs, which is the
        /// arrangement a call already uses for its arguments.
        match_,
        /// `match read k { .. }`. Observes the scrutinee instead of taking it
        /// apart, and binds each leaf as a lend.
        ///
        /// A tag of its own rather than a flag beside `match_`, because the
        /// two differ in what they do to the value and every pass that cares
        /// has to switch on it anyway. Everything that does not care asks
        /// `isMatch`.
        match_read,
        /// `for x in xs { … }`. Walks a sequence, taking it: the sequence sits
        /// inline where a call's callee does, and the side array holds the
        /// binder and the body, in that order.
        ///
        /// Call-shaped rather than a payload of its own, for the reason a
        /// `match`'s arms are: three indices do not fit two, and the run a
        /// call already has is where the third goes.
        for_,
        /// `for read x in xs { … }`. Observes the sequence instead of taking
        /// it, and binds each element as a lend.
        for_read,
        /// `for inout x in xs { … }`. Observes the sequence and binds each
        /// element as a lend the body may write through.
        ///
        /// Three tags rather than one carrying a convention, for the reason
        /// `match_read` is a tag beside `match_`: the three differ in what
        /// they do to the value, and each pass switches on the convention it
        /// needs.
        for_inout,
        /// `S { f: p, .. }`. A struct taken apart, in a `match` arm or in a
        /// destructuring `let`.
        ///
        /// Call-shaped: the optional callee names the type; an inferred-type
        /// destructuring `let` has none. The arguments alternate field name
        /// and sub-pattern, as a structure literal's do. One shape
        /// for one idea, so the field logic is written once.
        struct_pattern,
        /// `(a, b)`, a tuple built from its components.
        ///
        /// Call-shaped with no callee: the arguments are the components in
        /// written order. A node of its own beside `grouped`, so `(x)` and
        /// `(x, y)` print back as written.
        tuple_literal,
        /// `(a, b)` taking a tuple apart, in a destructuring `let`.
        ///
        /// Call-shaped with no callee: the arguments are the binders, a name
        /// or `_` each, in written order.
        tuple_pattern,
        /// `copy(p)`. The only duplication in the language.
        ///
        /// A value independent of `p` -- one such that no later operation on
        /// either is observable through the other. Deliberately not stated in
        /// terms of bytes: today an aggregate copy is a blit and the two
        /// coincide, and a representation could make them diverge without the
        /// language changing meaning.
        copy_,
        borrow,
        /// `*reference` selects exactly one readonly referent place.
        dereference,
        /// `panic(message)`. Evaluates one `Str` message, reports it at this
        /// expression's location, and has no continuation.
        panic,
        /// `e?`. Yields what a successful `Option` or `Result` carries, and
        /// returns the unsuccessful one from the enclosing function.
        ///
        /// A node rather than an expansion, for the reason `logical_and` is
        /// one: a tree holding the branch and the return could not be printed
        /// back as what someone wrote. The operand is the expression the `?`
        /// follows.
        try_,
        /// `e else |error| { … }`, a binding's initializer.
        /// Yields what a successful `Option` or `Result` carries, and runs the
        /// block on a failure: the block either does not complete or yields
        /// the success type in the value's place.
        ///
        /// Call-shaped, for the reason a `for` is: the operand sits where a
        /// callee does, and the run holds the binder, where one is written,
        /// then the block. See `Ast.unwrapElse`.
        ///
        /// A node rather than an expansion into a `match`, for the reason
        /// `try_` is one: a tree holding the arms could not be printed back as
        /// what someone wrote.
        unwrap_else,
        /// `f(a, b)`. The callee sits inline and the arguments sit in the
        /// tree's side array, because a payload holds two indices and a call
        /// has as many as it has arguments.
        call,
        /// `|x: T| body`. The parameter run and optional `move` token are held
        /// out of line, and the body is a separate callable body.
        lambda,
        int_literal,
        float_literal,
        /// `"hello"`. A view of bytes the compiler emits into the binary, so
        /// its type is the library's `Str` and its storage outlives everything.
        str_literal,
        bool_literal,
        /// `()`, the one value of the unit type.
        unit_literal,
        name_ref,
        /// The argument of a lambda parameter written as a tuple pattern,
        /// which `Param.argument` holds. It is written nowhere, so it has no
        /// token of its own: its range is the pattern's, and its main token
        /// is the pattern's opening parenthesis.
        param_argument,
        /// `reflect`, the reserved root of source-only structural-template
        /// operations. Selections and calls above it retain their ordinary
        /// field and call shapes until resolver-integrated expansion erases it.
        reflection_root,
        grouped,
        negate,
        /// `!e`. The only unary operator over `Bool`.
        not,
        /// `a && b` and `a || b`.
        ///
        /// Each holds what was written. What they *mean* is a conditional --
        /// `a && b` is `if a { b } else { false }` -- and lowering is where
        /// they become one. The tree keeps the surface form for the same
        /// reason `grouped` is a node: a tree holding the conditional could
        /// not be printed back as what someone wrote.
        logical_and,
        logical_or,
        add,
        sub,
        mul,
        div,
        /// `a % b`. What a truncating division leaves, so the sign follows the
        /// dividend and `a % b` is exactly `a - (a / b) * b`. Its own tag
        /// rather than a spelling of that subtraction, for the reason `/=` is
        /// not `= … / …`: one operator, evaluated once, and a divisor of zero
        /// is the same check either way.
        rem,
        // Comparison. Yields `Bool` rather than the operand type, which is why
        // these are their own tags rather than a flag on a binary node.
        eq,
        ne,
        lt,
        le,
        gt,
        ge,
        /// A region the parser could not parse. Already diagnosed; consumers
        /// treat its value as poisoned and report nothing further about it.
        err,

        /// Whether this is either form of `match`, for the passes that treat
        /// them alike -- which is all of them but ownership.
        pub fn isMatch(self: Tag) bool {
            return self == .match_ or self == .match_read;
        }

        pub fn payload(self: Tag) Payload {
            return switch (self) {
                .block => .block,
                .conditional => .conditional,
                .call, .match_, .match_read, .struct_literal, .struct_pattern, .array_literal, .unwrap_else => .call,
                .tuple_literal, .tuple_pattern => .call,
                .interp => .interpolation,
                .lambda => .lambda,
                .for_, .for_read, .for_inout => .call,
                .copy_, .panic, .borrow, .dereference => .unary,
                .int_literal, .float_literal, .str_literal, .bool_literal, .unit_literal, .name_ref, .param_argument, .reflection_root, .err, .continue_ => .none,
                .grouped, .negate, .not, .loop_, .break_, .return_, .marked, .variant_ref, .field, .try_ => .unary,
                .from_end => .unary,
                .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge, .index => .binary,
                .logical_and, .logical_or => .binary,
                .while_, .assign => .binary,
                .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => .binary,
                .range => .range,
            };
        }

        /// Whether an argument of this tag's run may name what it fills.
        ///
        /// Several tags share the call payload and one of them is a call, so
        /// every reader of `Ast.callNames` has to decide which. Exhaustive
        /// rather than a comparison, so a tag added later reusing the payload
        /// answers the question here before it compiles anywhere -- the answer
        /// is a fact about the tag, and a reader deciding it again is a copy
        /// that can disagree.
        pub fn namesArguments(self: Tag) bool {
            return switch (self) {
                .call => true,
                .match_, .match_read, .struct_literal, .struct_pattern, .array_literal, .interp, .unwrap_else => false,
                .tuple_literal, .tuple_pattern => false,
                .for_, .for_read, .for_inout => false,
                .block, .conditional, .borrow, .dereference, .copy_, .panic, .grouped, .negate, .not, .from_end, .lambda => false,
                .loop_, .break_, .return_, .marked, .variant_ref, .field, .try_ => false,
                .int_literal, .float_literal, .str_literal, .bool_literal, .unit_literal, .name_ref, .param_argument, .reflection_root, .err, .continue_ => false,
                .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge, .index => false,
                .logical_and, .logical_or, .while_, .assign => false,
                .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => false,
                .range => false,
            };
        }

        test "a tuple literal and pattern are call-shaped and name no arguments" {
            try std.testing.expectEqual(Expr.Payload.call, Expr.Tag.tuple_literal.payload());
            try std.testing.expectEqual(Expr.Payload.call, Expr.Tag.tuple_pattern.payload());
            try std.testing.expect(!Expr.Tag.tuple_literal.namesArguments());
            try std.testing.expect((TypeRef{ .kind = .tuple, .name = .none }).wasWritten());
        }

        /// The arithmetic a compound assignment performs, and null for every
        /// other tag.
        ///
        /// One place says which. Lowering picks an instruction by it and the
        /// checker names a rule by it, and two switches that each know
        /// `add_assign` means `add` are two chances to stop agreeing.
        pub fn compounds(self: Tag) ?Tag {
            return switch (self) {
                .add_assign => .add,
                .sub_assign => .sub,
                .mul_assign => .mul,
                .div_assign => .div,
                .rem_assign => .rem,
                else => null,
            };
        }
    };

    pub const Payload = enum { none, unary, binary, conditional, call, interpolation, block, range, lambda };

    /// Discriminated by `tag`. Never read directly: `Ast` exposes an accessor
    /// per variant that checks the tag first.
    pub const Data = union {
        none: void,
        unary: struct { operand: ExprId },
        binary: struct { lhs: ExprId, rhs: ExprId },
        /// A conditional. The condition sits inline; the two arms sit in the
        /// tree's side array, because a payload holds two indices and this
        /// needs three. `otherwise` is `.none` where no `else` was written,
        /// which the checker reads as an arm of type Unit rather than an
        /// absent one.
        conditional: struct { cond: ExprId, arms: ExtraIndex },
        /// A call. `args` indexes the side array, where the argument count is
        /// stored first and the arguments follow it. Where an argument names
        /// the parameter it fills, the name sits at the same index in the
        /// tree's parallel names array; see `Ast.callNames`.
        call: struct { callee: ExprId, args: ExtraIndex },
        interpolation: struct {
            pieces: ExtraIndex,
            formats: InterpolationFormatIndex,
        },
        lambda: struct { body: ExprId, extra: ExtraIndex },
        block: BlockId,
        /// `lo` sits inline; the side array holds `hi` and `inclusive`, the
        /// flag stored as `ExprId.at(0)` or `ExprId.at(1)` the way a call's
        /// argument count already borrows the same type for a bare number.
        range: struct { lhs: ExprId, extra: ExtraIndex },
    };
};

pub const Stmt = struct {
    tag: Tag,
    main_token: TokenId,
    token_range: TokenRange,
    data: Data,

    pub const Tag = enum(u8) {
        let_decl,
        /// `let S { f: p, .. } = e;` -- the terminal consumer of a struct.
        ///
        /// A statement rather than an expression, and the only form whose
        /// binders are shallow: a plain name or `_`, never a nested pattern.
        /// A `match` arm's struct pattern recurses; this one takes a value
        /// apart and binds what it holds.
        let_destructure,
        /// `let read S { f: p, .. } = place` or `let read N(n) = place`.
        /// Observes a stable place instead of taking it apart, and binds each
        /// part as a lend of that place.
        ///
        /// A tag of its own rather than a flag beside `let_destructure`, for
        /// the reason `match_read` is a tag beside `match_`: the two differ in
        /// what they do to the value, and every pass that cares has to switch
        /// on it anyway. Everything that does not care asks `isDestructure`.
        let_read_destructure,
        /// An expression evaluated for its effect. Its value must be Unit:
        /// anything else would be a value the program computed and discarded.
        expr_stmt,
        /// `defer e`. Schedules `e` to run at every exit from the enclosing
        /// scope, last scheduled first.
        ///
        /// The expression is the programmer's, and the compiler decides only
        /// where it runs -- so nothing here is a disposal the program did not
        /// write. Evaluated for its effect, as `expr_stmt` is, and so its value
        /// must be Unit for the same reason.
        defer_stmt,
        /// The release a `defer let` schedules, placed directly after the
        /// binding's `let_decl` so that `defer let x = e` reads to every pass
        /// as `let x = e` followed by `defer x.release()`.
        ///
        /// `init` is a `call` whose only argument is a `name_ref` at the
        /// binding's name token. The token range reaches from `defer` to that
        /// name, so a diagnostic underlines `defer let x` and nothing in the
        /// initialiser lies inside the schedule. The call is checked as the
        /// postfix call `x.release()`. Nothing in the source spells the
        /// operation's name, so its callee is a `name_ref` at the `defer`
        /// keyword that resolves to nothing. The formatter prints the pair as
        /// the one `defer let` it was written as.
        defer_release,
        /// See `Expr.Tag.err`.
        err,

        /// Whether this is either form of destructuring `let`, for the passes
        /// that treat them alike.
        pub fn isDestructure(self: Tag) bool {
            return self == .let_destructure or self == .let_read_destructure;
        }
    };

    pub const Data = struct {
        /// The bound name. Meaningless when `tag` is `err`.
        name: TokenId,
        /// The declared type, or `.none` when the binding carries no
        /// annotation and its type comes from context.
        annotation: TypeRef,
        /// The initialiser, or `.none` when it could not be parsed.
        init: ExprId,
        /// The pattern a destructuring `let` takes its value apart with, or
        /// `.none`. Shares its shape and its field logic with a `match` arm's
        /// struct pattern, so the two are one world rather than two.
        pattern: ExprId = ExprId.none,
    };
};

/// The variable-length part of a block, held out of line because a statement
/// list does not fit an expression's fixed payload.
pub const Block = struct {
    stmts: StmtRange,
    /// The trailing expression whose value is the block's value, or `.none`.
    tail: ExprId,
};

test "a declaration stores one written trait reference" {
    try testing.expect(@hasField(Decl, "trait_ref"));
    if (@hasField(Decl, "trait_ref")) {
        try testing.expect(@FieldType(Decl, "trait_ref") == TraitRef);
    }
    try testing.expect(!@hasField(Decl, "trait_name"));
    try testing.expect(!@hasField(Decl, "trait_args"));
}

test "ids round-trip and none is distinguishable" {
    try testing.expectEqual(@as(u32, 3), ExprId.at(3).index());
    try testing.expectEqual(@as(u32, 7), StmtId.at(7).index());
    try testing.expect(ExprId.at(3) != ExprId.none);
    try testing.expect(StmtId.none != StmtId.at(0));
}

test "StmtRange length" {
    const r: StmtRange = .{ .start = 2, .end = 6 };
    try testing.expectEqual(@as(u32, 4), r.len());
    try testing.expect((StmtRange{ .start = 1, .end = 1 }).len() == 0);
}

test "no expression payload variant exceeds two indices" {
    // Asserting on the variants rather than the union, because safe build
    // modes add a hidden tag that catches reading the wrong one.
    inline for (@typeInfo(Expr.Data).@"union".fields) |f| {
        try testing.expect(@sizeOf(f.type) <= 8);
    }
}

test "a call is the one tag whose arguments name what they fill" {
    // The tags sharing the call payload hold runs of their own, and only
    // a call's run is arguments. Asserted over every tag rather than those,
    // so a tag added anywhere has an answer here.
    for (std.enums.values(Expr.Tag)) |tag| {
        try testing.expectEqual(tag == .call, tag.namesArguments());
    }
}

// Makes every test build compile the tests `Expr.Tag` holds, including a build
// filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Expr.Tag;
}
