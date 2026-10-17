const std = @import("std");
const tracy = @import("../support/tracy.zig");
const testing = std.testing;

const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const OwnershipPolicy = node.OwnershipPolicy;

/// Effective permissions, ordered by increasing restrictions.
pub const Capability = enum(u8) {
    copyable,
    affine,
    linear,
};

pub const CapabilityRequirement = node.CapabilityRequirement;

fn assumedCapability(requirement: CapabilityRequirement) Capability {
    return switch (requirement) {
        .unrestricted => .linear,
        .discardable => .affine,
        .copyable => .copyable,
    };
}

fn meetsCapability(requirement: CapabilityRequirement, actual: Capability) bool {
    return @intFromEnum(actual) <= @intFromEnum(assumedCapability(requirement));
}
const TraitBound = node.TraitBound;
const Convention = node.Convention;
const TokenId = @import("../lexer/token.zig").TokenId;
const StringId = @import("../support/interner.zig").StringId;
const Loc = @import("../support/span.zig").Loc;
const Table = @import("../support/table.zig").Table;
const ids = @import("ids.zig");
/// What each declaration was written to return.
pub const Returns = Table(DeclId, TypeId);
pub const Signatures = Table(DeclId, TypeId);
/// The type of each binding.
pub const BindingTypes = Table(ids.BindingId, TypeId);
const Chain = @import("../support/chain.zig").Chain;

/// A format spec lays a value out through one of three routines, chosen by
/// the value's type.
pub const LayoutShape = enum { integer, float, general };

/// The name every interpolation's type goes by.
///
/// Unspellable on purpose: an identifier holds no brace, so no program can
/// declare a type this name reaches, and asking whether a type is one of these
/// cannot collide with something a program wrote. It is also what a diagnostic
/// naming the type prints, which is the honest answer -- the type has no name
/// of its own because nobody wrote one.
///
/// Spelled once, here beside the predicate that reads it: the pass that mints
/// such a type and the passes that recognise one are three readers of a name
/// they all have to agree about.
pub const interpolation_type_name = "{interpolation";

/// An integer namespace property evaluated from the canonical type range.
pub const IntegerEndpoint = enum {
    min,
    max,

    pub fn fromName(name: []const u8) ?IntegerEndpoint {
        return std.meta.stringToEnum(IntegerEndpoint, name);
    }

    pub fn value(self: IntegerEndpoint, receiver: TypeId) ?i128 {
        const range = receiver.bounds() orelse return null;
        return switch (self) {
            .min => range.min,
            .max => range.max,
        };
    }
};

/// A checked property whose receiver may await type substitution.
pub const IntegerProperty = struct {
    receiver: TypeId,
    endpoint: IntegerEndpoint,
};

/// A handle into the type pool.
///
/// Builtin types occupy reserved indices, so the checker names a type instead
/// of interning a descriptor to find one, and interned entries begin after
/// them — adding a compound type later fills the tail without moving anything.
/// A `TypeId` means the same thing in every pass that holds it, because the
/// pool is interned and immutable once the checker returns it.
pub const TypeId = enum(u32) {
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    bool_,
    /// A type that could not be determined, from a region already diagnosed.
    poison,
    /// The type of a body with no value. Internal until the language exposes
    /// one, which is why it is not called `void`.
    unit,
    /// Reserved after `poison` and `unit` rather than beside the other
    /// numerals, so every handle that existed before it kept its index.
    /// Compound types still shift by one -- they begin where the builtins
    /// end -- but a shift in reserved handles would move meaning, not just
    /// the index-derived names the emitted IR gives aggregates.
    f64,
    never,
    _,

    pub fn at(i: u32) TypeId {
        return @enumFromInt(i);
    }

    pub fn index(self: TypeId) u32 {
        return @intFromEnum(self);
    }

    /// The type a literal takes where nothing constrains it. Named rather
    /// than spelled: the language has one name per width, and this is which of
    /// them an unannotated literal means.
    pub const literal_default: TypeId = .i64;

    /// The descriptors the reserved handles stand for, in handle order.
    pub const builtins = [_]Type{
        .{ .integer = .{ .signed = true, .bits = 8 } },
        .{ .integer = .{ .signed = true, .bits = 16 } },
        .{ .integer = .{ .signed = true, .bits = 32 } },
        .{ .integer = .{ .signed = true, .bits = 64 } },
        .{ .integer = .{ .signed = false, .bits = 8 } },
        .{ .integer = .{ .signed = false, .bits = 16 } },
        .{ .integer = .{ .signed = false, .bits = 32 } },
        .{ .integer = .{ .signed = false, .bits = 64 } },
        .boolean,
        .poison,
        .unit,
        .float,
        .never,
    };

    /// The primitives a program can name, in handle order. The resolver seeds
    /// one binding per entry, spelling each with `nameOf`.
    pub const primitives = [_]TypeId{ .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .bool_, .f64, .never };

    /// Every integer type, read off the primitives so the two cannot differ.
    pub const integers = blk: {
        var count: usize = 0;
        for (primitives) |t| if (t.integerInfo() != null) {
            count += 1;
        };
        var out: [count]TypeId = undefined;
        var next: usize = 0;
        for (primitives) |t| if (t.integerInfo() != null) {
            out[next] = t;
            next += 1;
        };
        break :blk out;
    };

    /// The signedness and width of an integer type, or null when the handle
    /// names something else.
    ///
    /// Reads the reserved descriptors rather than the pool, so a consumer that
    /// holds only a `TypeId` -- the backend, which must know how wide a value
    /// is without knowing what a type is -- does not need the whole typing.
    /// The pool is seeded from the same array, so the two cannot disagree.
    pub fn integerInfo(self: TypeId) ?struct { signed: bool, bits: u8 } {
        const i = @intFromEnum(self);
        if (i >= builtins.len) return null;
        return switch (builtins[i]) {
            .integer => |info| .{ .signed = info.signed, .bits = info.bits },
            else => null,
        };
    }

    /// The width this type crosses a foreign boundary in, or null where it may
    /// not cross at all.
    ///
    /// One question with one answer, asked by the checker to refuse a
    /// signature and by the backend to print one. Two predicates here would
    /// disagree somewhere, and the disagreement is a type the checker accepts
    /// and the backend cannot emit -- which is a compiler crash on source a
    /// programmer was told was fine.
    ///
    /// An integer's width and its signedness are the whole of its
    /// representation, so both sides of a boundary already agree about it.
    /// Nothing else does: where a structure's fields sit is the compiler's to
    /// decide, a float carries a representation this language does not fix
    /// across an ABI, and a linear value cannot cross code ownership never
    /// read.
    pub fn foreignWidth(self: TypeId) ?u8 {
        const info = self.integerInfo() orelse return null;
        return switch (info.bits) {
            8, 16, 32, 64 => info.bits,
            else => null,
        };
    }

    /// The values a type can represent.
    ///
    /// Wide enough for `UInt64`'s maximum and `Int64`'s minimum together, which is
    /// why folding is done in `i128` rather than in the operand type.
    pub const Bounds = struct { min: i128, max: i128 };

    /// The range of an integer type, or null when the handle names something
    /// else. Every consumer that needs to know what a type holds -- the
    /// checker folding a constant, the backend emitting a range test -- reads
    /// it from here, so a new width is added in one place.
    pub fn bounds(self: TypeId) ?Bounds {
        const info = self.integerInfo() orelse return null;
        return boundsOf(info.signed, info.bits);
    }

    pub fn boundsOf(signed: bool, bits: u8) Bounds {
        if (!signed) return .{ .min = 0, .max = (@as(i128, 1) << @intCast(bits)) - 1 };
        return .{
            .min = -(@as(i128, 1) << @intCast(bits - 1)),
            .max = (@as(i128, 1) << @intCast(bits - 1)) - 1,
        };
    }

    /// How a type is spelled in a diagnostic. Every message naming a type needs
    /// this, and without it each site would switch over the tag.
    pub fn nameOf(self: TypeId) []const u8 {
        return switch (self) {
            .i8 => "Int8",
            .i16 => "Int16",
            .i32 => "Int32",
            .i64 => "Int64",
            .u8 => "UInt8",
            .u16 => "UInt16",
            .u32 => "UInt32",
            .u64 => "UInt64",
            .bool_ => "Bool",
            .f64 => "Float64",
            .never => "Never",
            .poison => "<unknown>",
            .unit => "()",
            _ => "<compound>",
        };
    }
};

/// A refined newtype's folded, inclusive bounds. Named rather than anonymous
/// so `Typing.refinementOf` and `Builder.refinementOf` return one type: two
/// structurally identical anonymous ones are still two types to Zig, which
/// is exactly the kind of second implementation this compiler's own
/// discipline refuses.
pub const Refinement = struct { lo: i128, hi: i128 };

pub const Type = union(enum) {
    /// A pointer-valued read-only observation; dependencies are ownership facts.
    borrow: struct { referent: TypeId, name: []const u8 },
    integer: struct { signed: bool, bits: u8 },
    /// Two values and no order. A closed domain, which is what lets a match on
    /// one be total without a catch-all.
    boolean,
    /// A binary64 floating point number.
    ///
    /// Its own kind rather than an integer carrying a flag, because every
    /// routine that asks "is this an integer, how wide, how signed" must get
    /// an answer meaning *no* rather than one meaning *unsigned 64*.
    float,
    poison,
    unit,
    never,
    /// An integer literal's type while its uses have not yet chosen one.
    /// The index names a variable in the checker's open-type table. No
    /// recorded type holds one once checking returns, but the entries stay in
    /// the pool, so a pass that walks every pool type still meets them.
    open_integer: u32,
    /// A type parameter a function value leaves unselected, while the value's
    /// later uses have not yet said what it is. The index names a variable in
    /// the same table open integers use, and like them no recorded type holds
    /// one once checking returns.
    open_type: u32,
    /// A type the program declared. Its variants sit in a side array, because
    /// a descriptor is a fixed row and a variant list is not.
    enum_: struct {
        name: []const u8,
        first_variant: u32,
        variant_count: u32,
        /// Total payload fields across the variants. Recorded when fields are
        /// filled so questions asked per expression do not rescan the enum.
        payload_field_count: u32 = 0,
        ownership_policy: OwnershipPolicy = .affine,
    },
    /// A type a declaration is generic over, standing for whatever an
    /// instantiation supplies.
    ///
    /// It has no layout, and asking for one is a compiler bug rather than a
    /// diagnosis: lowering only ever sees an instantiation, so a parameter
    /// never reaches the backend.
    ///
    /// The owning declaration is part of its identity, so one declaration's
    /// `T` is never another's.
    parameter: struct {
        name: []const u8,
        owner: u32,
        index: u32,
        /// The capability promised by the parameter's normalized bounds.
        requirement: CapabilityRequirement = .unrestricted,
        integer: bool = false,
        /// Whether its bounds promise `Owned`: every admitted argument carries
        /// no dependency, so the parameter seeds none.
        owned: bool = false,
        /// The traits its bounds name, by declaration, and the arguments each
        /// was written with.
        ///
        /// Beside the capability rather than left in the tree, because the two
        /// are halves of one promise and every reader of one wants the other:
        /// a bound is discharged by an implementation existing *or* by a
        /// promise already made about the parameter, and the reader that
        /// decides which implementation answers for a receiver has no tree to
        /// read the second from. Read from here, both halves answer alike.
        ///
        /// The arguments are part of the promise: `C: Lookup[UInt64]` admits
        /// an implementation of `Lookup` at `UInt64` and nothing else, so a
        /// call through the bound is discharged at those arguments and no
        /// other.
        traits: []const BoundTrait = &.{},
        /// The exact structural signatures this parameter promises, in the
        /// order they were written.
        callables: []const TypeId = &.{},
    },
    /// `[T; N]`: N elements of one type, laid out end to end.
    ///
    /// The count is part of the identity, so `[UInt8; 2]` and `[UInt8; 3]` are
    /// different types and neither stands for the other. Nothing is stored
    /// beside the elements -- a length in the value would be a second answer to
    /// a question the type already settles.
    array: struct {
        element: TypeId,
        count: u32,
        /// How it is written. Minted where the type is, for the reason an
        /// instantiation's is: a diagnostic naming two arrays has to tell them
        /// apart, and `<compound>` on both sides of a mismatch says nothing
        /// about which length was wanted.
        name: []const u8 = "",
    },
    /// A structural function value, identified by its complete signature.
    callable: CallableSignature,
    /// One lambda source identity, distinct even where two signatures match.
    closure: ClosureType,
    /// A nominal type with named parts, laid out in field order. Source
    /// records and compiler-produced environments share this field table.
    struct_: struct {
        name: []const u8,
        first_field: u32,
        field_count: u32,
        ownership_policy: OwnershipPolicy = .affine,
    },
    /// A distinct nominal type over one base: same representation, a
    /// different contract. Layout, width and every other question about how
    /// the value is arranged delegate to `base` -- a newtype represents
    /// nothing of its own, so there is nothing for those questions to answer
    /// here instead.
    newtype: struct {
        name: []const u8,
        base: TypeId,
        /// The refinement's folded bounds, inclusive on both ends. Meaningless
        /// where `refined` is false.
        lo: i128 = 0,
        hi: i128 = 0,
        /// Whether a `where it in lo..=hi` clause was declared. An unrefined
        /// newtype admits every value its base does.
        refined: bool = false,
        ownership_policy: OwnershipPolicy = .affine,
    },
};

/// One named part of a structure.
pub const Field = struct {
    name: []const u8,
    ty: TypeId,
};

pub const FieldList = std.MultiArrayList(Field);

fn ReadOnlyColumns(comptime Row: type) type {
    const List = std.MultiArrayList(Row);
    const field_count = std.meta.fields(Row).len;

    return struct {
        ptrs: [field_count][*]const u8 = undefined,
        len: usize = 0,
        capacity: usize = 0,

        const Self = @This();

        pub const empty: Self = .{};

        pub fn fromSlice(slice: List.Slice) Self {
            var ptrs: [field_count][*]const u8 = undefined;
            for (slice.ptrs, &ptrs) |from, *to| to.* = from;
            return .{ .ptrs = ptrs, .len = slice.len, .capacity = slice.capacity };
        }

        pub fn items(self: Self, comptime field: List.Field) []const @FieldType(Row, @tagName(field)) {
            const Element = @FieldType(Row, @tagName(field));
            if (self.capacity == 0) return &[_]Element{};
            const bytes = self.ptrs[@intFromEnum(field)];
            const elements: [*]const Element = if (@sizeOf(Element) == 0)
                undefined
            else
                @ptrCast(@alignCast(bytes));
            return elements[0..self.len];
        }

        fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            var ptrs: [field_count][*]u8 = undefined;
            for (self.ptrs, &ptrs) |from, *to| to.* = @constCast(from);
            var slice: List.Slice = .{
                .ptrs = ptrs,
                .len = self.len,
                .capacity = self.capacity,
            };
            slice.deinit(gpa);
            self.* = undefined;
        }
    };
}

pub const FieldColumns = ReadOnlyColumns(Field);

/// One alternative of an enum.
pub const Variant = struct {
    name: []const u8,
    /// What the variant carries, as a run in the same table a structure's
    /// fields live in -- so a variant and a structure are arranged by one
    /// piece of code rather than by two that could disagree.
    first_field: u32 = 0,
    field_count: u32 = 0,
};

pub const VariantList = std.MultiArrayList(Variant);
pub const VariantColumns = ReadOnlyColumns(Variant);

/// How a value is arranged in memory.
///
/// A tag occupies a full word rather than the bits it needs. That costs seven
/// bytes per value and buys two things: a payload begins already aligned, and
/// the tag is read by the same load a machine word uses, so a `match` over an
/// enum that carries something tests exactly what a `match` over one that
/// carries nothing tests.
pub const Layout = struct {
    size: u32,
    alignment: u32,
    /// Whether values of this type live in memory rather than in a register.
    ///
    /// Deliberately not "wider than a word". A two-byte structure fits a
    /// register and still has to live in memory, because a part is reached
    /// through an address and a register does not have one.
    indirect: bool = false,
    /// Whether the type is wider than [L-Size] allows, in which case `size` is
    /// the widest a layout can record rather than the type's own width.
    ///
    /// A width is worked out in a wider integer and stops at the limit, so a
    /// type too wide to record is a fact this carries rather than a wrapped
    /// size nothing can tell from a real one.
    ///
    /// Carried rather than settled at one point in the pipeline, because more
    /// than one pool decides widths: lowering interns the instantiations a
    /// generic body reaches, which the checker never saw. Each pool is asked
    /// about the types it minted before its widths are handed on, and the
    /// stopped size is what makes that question answerable rather than a
    /// wrapped number indistinguishable from a real one.
    too_wide: bool = false,

    /// The width of a value the machine holds in a register.
    pub const word: u32 = 8;

    /// The width of an enum's tag, which sits at offset zero and is followed
    /// by the payload. A full word rather than the bits it needs.
    pub const tag_width: u32 = word;

    /// What an access to a tag is typed by: an unsigned integer exactly
    /// `tag_width` wide.
    pub const tag_type: TypeId = .u64;

    /// The greatest width a type may have.
    ///
    /// A part's offset is recorded in the same width a size is, so a type
    /// wider than this has no offset to place its parts at. Read off that
    /// width rather than written down, so the number the semantics state and
    /// the arithmetic that enforces it cannot drift.
    pub const max_size: u64 = std.math.maxInt(@FieldType(Layout, "size"));

    /// Whether a value of this type lives in memory rather than a register.
    ///
    /// This is the whole of what the rest of the compiler asks about layout.
    /// A fieldless enum answers no and is a tag in a register, which is why
    /// nothing about it changed when payloads arrived.
    pub fn isAggregate(self: Layout) bool {
        return self.indirect;
    }

    /// One past the greatest width recorded, which every running offset stops
    /// at.
    ///
    /// Stopping rather than wrapping is what lets a type too wide to record
    /// tell itself apart from one that fits: past here the exact width no
    /// longer matters, because [L-Size] refuses the type either way.
    const stop: u64 = max_size + 1;

    /// The next offset at or after `at` that `alignment` allows.
    ///
    /// Works in a wider integer than a layout records, because a run is added
    /// up before it is known to fit: an addition that wrapped would give a
    /// slot smaller than the value it holds, and one that trapped would fail
    /// the frontend on source a diagnostic is owed for.
    pub fn alignUp(at: u64, alignment: u32) u64 {
        const rem = at % alignment;
        return if (rem == 0) at else at + (alignment - rem);
    }

    /// A width narrowed to what a layout records, and whether it fitted.
    ///
    /// One place decides that, so a structure and an enum cannot answer it
    /// differently.
    fn recorded(width: u64, alignment: u32, indirect: bool) Layout {
        return .{
            .size = @intCast(@min(width, max_size)),
            .alignment = alignment,
            .indirect = indirect,
            .too_wide = width > max_size,
        };
    }

    /// What a value the machine holds in a register is laid out as.
    pub const scalar: Layout = .{ .size = word, .alignment = word };
};

const StampedLayout = struct {
    value: Layout = .scalar,
    generation: u32 = 0,
};

/// The arrangement of a type, read from a pool and its side arrays rather than
/// from a `Typing`, so the checker can ask mid-build and the module's layout
/// table can be filled from the finished one. Both go through here, which is
/// what stops the two answers from differing.
///
/// A builtin is its own width, which is where the recursion bottoms out.
/// Everything else is a run of parts placed at their own alignment, and a type
/// holding another inherits its alignment -- which is the whole of why nesting
/// needs no case of its own.
const Arrangement = struct {
    pool: []const Type,
    fields: FieldColumns,
    variants: VariantColumns,
    /// What each pool entry was already laid out as, filled the first time it
    /// is asked for.
    ///
    /// A type reached k times in a tree was laid out k times, so one query
    /// cost the size of the fully expanded tree -- exponential in nesting
    /// depth for a linear number of declarations, and a thirty-line file took
    /// minutes.
    ///
    /// Written through even where the arrangement is read through a `*const`:
    /// what is recorded is the answer this same data already gives, so a
    /// reader that consults it and a reader that does not cannot disagree. A
    /// builder invalidates the whole table whenever a part is written, which is
    /// the only mutation that can change what a type is laid out as. Empty
    /// means every query recomputes, which is what a typing built by hand
    /// gets.
    laid_out: []StampedLayout = &.{},
    /// Which generation each answer was worked out in is stored beside it.
    ///
    /// Writing a part invalidates every layout, and clearing the table to say
    /// so cost the pool once per write -- so filling a type's fields cost the
    /// pool times its own field count, and a module of many instantiations paid
    /// that for each. The generation moves instead, and an answer stamped with
    /// an older one is not an answer.
    placed_at: []u32 = &.{},
    /// Which generation is current. Never zero, so a table that was never
    /// written holds no answer.
    generation: u32 = 1,
    /// Where each part begins within its own run, by the part's index in
    /// `fields`, and whether the run holding it has been placed.
    ///
    /// `offsetIn` walked a run from its start for every part asked about, so
    /// naming F parts of one type cost F squared. This is the same answer
    /// `laid_out` already gives one level up, applied to the running sum
    /// rather than to each part's layout: a run is placed once, whole, the
    /// first time any part of it is asked for.
    ///
    /// Empty means every query walks, which is what a typing built by hand
    /// gets -- the same bargain `laid_out` strikes.
    offsets: []u32 = &.{},

    fn layoutOf(self: Arrangement, t: TypeId) Layout {
        const at = @intFromEnum(t);
        if (at < self.laid_out.len) {
            const cached = self.laid_out[at];
            if (cached.generation == self.generation) return cached.value;
        }
        const made = self.compute(t);
        if (at < self.laid_out.len) {
            self.laid_out[at] = .{ .value = made, .generation = self.generation };
        }
        return made;
    }

    /// Places a run of parts from `start`, returning the size and alignment of
    /// the whole. One function for a structure's fields and for what a variant
    /// carries, so the two cannot be arranged by different rules.
    fn placeRun(self: Arrangement, first: u32, count: u32, start: u64) struct { size: u64, alignment: u32 } {
        var at = start;
        var alignment: u32 = 1;

        const field_types = self.fields.items(.ty);
        for (field_types[first..][0..count]) |ty| {
            const l = self.layoutOf(ty);
            at = @min(Layout.alignUp(at, l.alignment) + l.size, Layout.stop);
            alignment = @max(alignment, l.alignment);
        }

        // Rounded up, so an array of these would be laid out correctly by the
        // same rule that laid out one.
        return .{ .size = @min(Layout.alignUp(at, alignment), Layout.stop), .alignment = alignment };
    }

    /// Where one part of a run begins.
    ///
    /// The run is named by where it starts in `fields` rather than passed as a
    /// slice, because that is what keys the table: a part belongs to one run,
    /// and a run is placed from one `start`.
    fn offsetIn(self: Arrangement, first: u32, count: u32, want: u32, start: u64) u32 {
        if (count == 0) return @intCast(@min(start, Layout.max_size));

        if (first + count <= self.placed_at.len) {
            if (self.placed_at[first] != self.generation) self.place(first, count, start);
            return self.offsets[first + want];
        }

        var at: u64 = start;
        const field_types = self.fields.items(.ty);
        for (field_types[first..][0..count], 0..) |ty, i| {
            const l = self.layoutOf(ty);
            at = @min(Layout.alignUp(at, l.alignment), Layout.stop);
            if (i == want) break;
            at = @min(at + l.size, Layout.stop);
        }
        return @intCast(@min(at, Layout.max_size));
    }

    /// Places a whole run, so that asking for one part answers for all of them.
    ///
    /// The same arithmetic `offsetIn` walks, run to the end rather than to a
    /// wanted index -- one statement of where a part begins, not two.
    fn place(self: Arrangement, first: u32, count: u32, start: u64) void {
        var at: u64 = start;
        const field_types = self.fields.items(.ty);
        for (field_types[first..][0..count], 0..) |ty, i| {
            const l = self.layoutOf(ty);
            at = @min(Layout.alignUp(at, l.alignment), Layout.stop);
            self.offsets[first + i] = @intCast(@min(at, Layout.max_size));
            at = @min(at + l.size, Layout.stop);
        }
        self.placed_at[first] = self.generation;
    }

    fn compute(self: Arrangement, t: TypeId) Layout {
        const pool = self.pool;
        return switch (pool[@intFromEnum(t)]) {
            .integer => |i| .{ .size = i.bits / 8, .alignment = i.bits / 8 },
            // Every recorded use is resolved before checking finishes, so an
            // open integer left in the pool is reached only by passes that
            // scan every type. It lays out as the type it would fall back to.
            .open_integer => .{ .size = 8, .alignment = 8 },
            // Nothing is laid out at an unselected parameter, and one left in
            // the pool is reached only by a scan of every type.
            .open_type => .{ .size = 0, .alignment = 1 },
            .boolean => .{ .size = 1, .alignment = 1 },
            .float => .{ .size = 8, .alignment = 8 },
            // No value, so nothing to place and nothing to align.
            .unit, .never => .{ .size = 0, .alignment = 1 },
            // Already reported. A word keeps every later arithmetic in range.
            .poison => .scalar,

            // A parameter has no layout of its own -- it stands for whatever an
            // instantiation supplies. A word is a placeholder so the table stays
            // indexable by `TypeId`, and nothing reads it: lowering emits code for
            // instantiations, so no instruction is ever typed by a parameter.
            .parameter => .scalar,

            // Structural callable values hold code pointers; observations
            // hold data pointers.
            .callable, .borrow => .scalar,
            .closure => |closure| self.layoutOf(closure.environment),

            .struct_ => |x| blk: {
                const run = self.placeRun(x.first_field, x.field_count, 0);
                break :blk Layout.recorded(run.size, run.alignment, true);
            },

            // N elements end to end, so the whole is N strides wide and aligned
            // as one element is. The stride rather than the size, because an
            // element has to begin aligned wherever it sits -- which is what
            // makes an index a multiply.
            .array => |a| blk: {
                // Through the memo, as `placeRun` reaches a field's. Calling
                // `compute` here laid the element out once per array holding
                // it, and an array of an array of a structure paid that at
                // every level -- the cost this table exists to stop.
                const of = self.layoutOf(a.element);
                const stride = Layout.alignUp(of.size, of.alignment);
                const size = @min(stride *| a.count, Layout.stop);
                break :blk Layout.recorded(@intCast(size), of.alignment, true);
            },

            .enum_ => |e| blk: {
                // The tag occupies a full word, which ADR 0028 chose deliberately:
                // a payload then begins already aligned, and the tag is read by
                // the same load a machine word uses.
                var size: u64 = Layout.tag_width;
                var alignment: u32 = Layout.tag_width;
                var carries = false;
                const variant_first_fields = self.variants.items(.first_field);
                const variant_field_counts = self.variants.items(.field_count);

                // Every variant shares one arrangement, so the whole is as wide as
                // the widest needs and the others leave the rest unused.
                for (e.first_variant..e.first_variant + e.variant_count) |variant_at| {
                    const field_count = variant_field_counts[variant_at];
                    if (field_count == 0) continue;
                    carries = true;

                    const run = self.placeRun(
                        variant_first_fields[variant_at],
                        field_count,
                        Layout.tag_width,
                    );
                    size = @max(size, run.size);
                    alignment = @max(alignment, run.alignment);
                }

                // A fieldless enum is a tag, and a tag is a value in a register.
                // That is what keeps every program using one lowering exactly as
                // it did before payloads existed.
                break :blk Layout.recorded(Layout.alignUp(size, alignment), alignment, carries);
            },

            // A newtype represents nothing of its own: its values are its
            // base's, byte for byte, so its layout is the base's layout.
            .newtype => |n| self.layoutOf(n.base),
        };
    }
};

/// A cycle among the types reached by traversing inline parts.
///
/// The rule is about layout rather than about recursion, and the difference is
/// what lasts: a type that reaches itself through a pointer is well formed,
/// because the outer size stops needing the inner one. What never is, is a
/// cycle among the parts a value holds inline -- computing such a size
/// requires that size.
pub const Cycle = struct {
    /// The types on the cycle, in the order they were reached. The first is
    /// what the last reaches again.
    path: []const TypeId,
};

/// The first cycle among inline parts, or null where the graph is acyclic.
///
/// A walk that remembered every type it had ever seen would call a type held
/// twice a cycle. What makes one is being reached again *from within its own
/// traversal*, so the mark says which of the two a type is: on the path being
/// walked now, or finished and known acyclic.
fn firstCycleIn(
    gpa: std.mem.Allocator,
    pool: []const Type,
    fields: FieldColumns,
    variants: VariantColumns,
) !?Cycle {
    const Mark = enum { unseen, on_path, done };
    const marks = try gpa.alloc(Mark, pool.len);
    defer gpa.free(marks);
    @memset(marks, .unseen);

    var path: std.ArrayList(TypeId) = .empty;
    defer path.deinit(gpa);

    const field_types = fields.items(.ty);
    const variant_first_fields = variants.items(.first_field);
    const variant_field_counts = variants.items(.field_count);

    for (0..pool.len) |i| {
        if (try walkFrom(
            gpa,
            pool,
            field_types,
            variant_first_fields,
            variant_field_counts,
            @enumFromInt(@as(u32, @intCast(i))),
            marks,
            &path,
        )) {
            return .{ .path = try gpa.dupe(TypeId, path.items) };
        }
    }
    return null;
}

fn walkFrom(
    gpa: std.mem.Allocator,
    pool: []const Type,
    field_types: []const TypeId,
    variant_first_fields: []const u32,
    variant_field_counts: []const u32,
    t: TypeId,
    marks: anytype,
    path: *std.ArrayList(TypeId),
) !bool {
    const i = @intFromEnum(t);
    switch (marks[i]) {
        .done => return false,
        // Reached from within its own traversal, so the path from here back to
        // it is the cycle.
        .on_path => {
            const at = std.mem.indexOfScalar(TypeId, path.items, t).?;
            path.replaceRangeAssumeCapacity(0, at, &.{});
            return true;
        },
        .unseen => {},
    }

    marks[i] = .on_path;
    try path.append(gpa, t);

    var reported = false;
    switch (pool[i]) {
        .borrow => {},
        // An array reaches its element, so a type holding an array of itself
        // is as infinite as one holding itself, and is found the same way.
        .array => |a| {
            if (try walkFrom(gpa, pool, field_types, variant_first_fields, variant_field_counts, a.element, marks, path)) {
                reported = true;
            }
        },
        .struct_ => |x| for (field_types[x.first_field..][0..x.field_count]) |field_type| {
            if (try walkFrom(gpa, pool, field_types, variant_first_fields, variant_field_counts, field_type, marks, path)) {
                reported = true;
                break;
            }
        },
        .enum_ => |e| outer: for (e.first_variant..e.first_variant + e.variant_count) |variant_at| {
            const first_field = variant_first_fields[variant_at];
            const field_count = variant_field_counts[variant_at];
            for (field_types[first_field..][0..field_count]) |field_type| {
                if (try walkFrom(gpa, pool, field_types, variant_first_fields, variant_field_counts, field_type, marks, path)) {
                    reported = true;
                    break :outer;
                }
            }
        },
        // A newtype reaches its base exactly as an array reaches its
        // element: a type declared over itself is as infinite as one holding
        // itself, and layout would recurse forever without this.
        .newtype => |n| {
            if (try walkFrom(gpa, pool, field_types, variant_first_fields, variant_field_counts, n.base, marks, path)) {
                reported = true;
            }
        },
        // Every kind that holds nothing, named rather than fallen through: a
        // kind added later holds something or it does not, and deciding that
        // is what this walk is. Left as a fall-through, a new kind would be
        // acyclic by default and laid out by whoever asked for its size
        // first.
        .closure => |closure| reported = try walkFrom(gpa, pool, field_types, variant_first_fields, variant_field_counts, closure.environment, marks, path),
        .integer, .open_integer, .open_type, .boolean, .float, .poison, .unit, .never, .parameter, .callable => {},
    }
    if (reported) return true;

    _ = path.pop();
    marks[i] = .done;
    return false;
}

/// Whether a callable parameter supplies a folded value when omitted.
pub const CallableDefault = union(enum) {
    absent,
    value: ConstantValue,

    pub fn eql(a: CallableDefault, b: CallableDefault) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .absent => true,
            .value => |value| value.eql(b.value),
        };
    }
};

/// Incremental reverse edges propagate capabilities once per owned-part edge.
/// Field replacement invalidates the graph before the next query.
const CapabilityFacts = struct {
    const none = std.math.maxInt(u32);
    const Edge = struct { owner: TypeId, child: TypeId, next: u32 };
    values: std.ArrayList(Capability) = .empty,
    seeds: std.ArrayList(Capability) = .empty,
    first_parts: std.ArrayList(u32) = .empty,
    part_counts: std.ArrayList(u32) = .empty,
    known_noncopyable: std.ArrayList(bool) = .empty,
    heads: std.ArrayList(u32) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    queue: std.ArrayList(TypeId) = .empty,
    scanned: usize = 0,
    dirty: bool = false,

    fn invalidate(self: *CapabilityFacts, owner: TypeId) void {
        if (owner.index() < self.scanned) self.dirty = true;
    }

    fn deinit(self: *CapabilityFacts, gpa: std.mem.Allocator) void {
        self.values.deinit(gpa);
        self.seeds.deinit(gpa);
        self.first_parts.deinit(gpa);
        self.part_counts.deinit(gpa);
        self.known_noncopyable.deinit(gpa);
        self.heads.deinit(gpa);
        self.edges.deinit(gpa);
        self.queue.deinit(gpa);
        self.* = .{};
    }

    fn strengthen(self: *CapabilityFacts, gpa: std.mem.Allocator, owner: TypeId, capability: Capability) !void {
        if (@intFromEnum(self.values.items[owner.index()]) >= @intFromEnum(capability)) return;
        try self.queue.append(gpa, owner);
        self.values.items[owner.index()] = capability;
    }

    fn seed(self: *CapabilityFacts, gpa: std.mem.Allocator, ty: TypeId, capability: Capability) !void {
        self.seeds.items[ty.index()] = capability;
        try self.strengthen(gpa, ty, capability);
    }

    fn edge(self: *CapabilityFacts, gpa: std.mem.Allocator, owner: TypeId, child: TypeId) !void {
        const at: u32 = @intCast(self.edges.items.len);
        try self.edges.append(gpa, .{ .owner = owner, .child = child, .next = self.heads.items[child.index()] });
        self.heads.items[child.index()] = at;
        try self.strengthen(gpa, owner, self.values.items[child.index()]);
        if (self.known_noncopyable.items[child.index()]) try self.markNoncopyable(gpa, owner);
    }

    fn markNoncopyable(self: *CapabilityFacts, gpa: std.mem.Allocator, owner: TypeId) !void {
        if (self.known_noncopyable.items[owner.index()]) return;
        try self.queue.append(gpa, owner);
        self.known_noncopyable.items[owner.index()] = true;
    }

    fn policyCapability(policy: OwnershipPolicy) Capability {
        return switch (policy) {
            .affine => .affine,
            .copyable => .copyable,
            .linear => .linear,
        };
    }

    /// Each type strengthens at most twice and becomes known noncopyable
    /// once: O(types + parts) between representation replacements.
    fn update(self: *CapabilityFacts, builder: *Typing.Builder) !void {
        if (!self.dirty and self.scanned == builder.pool.items.len and self.queue.items.len == 0) return;
        const gpa = builder.gpa;
        if (self.dirty) {
            builder.scoped_capability_facts.deinit(gpa);
            builder.prepared_implementations.clear();
            self.seeds.clearRetainingCapacity();
            self.first_parts.clearRetainingCapacity();
            self.part_counts.clearRetainingCapacity();
            self.values.clearRetainingCapacity();
            self.known_noncopyable.clearRetainingCapacity();
            self.heads.clearRetainingCapacity();
            self.edges.clearRetainingCapacity();
            self.queue.clearRetainingCapacity();
            self.scanned = 0;
            self.dirty = false;
        }
        const count = builder.pool.items.len;
        try self.values.appendNTimes(gpa, .copyable, count - self.values.items.len);
        try self.seeds.appendNTimes(gpa, .copyable, count - self.seeds.items.len);
        try self.first_parts.appendNTimes(gpa, 0, count - self.first_parts.items.len);
        try self.part_counts.appendNTimes(gpa, 0, count - self.part_counts.items.len);
        try self.known_noncopyable.appendNTimes(gpa, false, count - self.known_noncopyable.items.len);
        try self.heads.appendNTimes(gpa, none, count - self.heads.items.len);
        const view = builder.view();
        while (self.scanned < count) : (self.scanned += 1) {
            const ty: TypeId = @enumFromInt(@as(u32, @intCast(self.scanned)));
            self.first_parts.items[ty.index()] = @intCast(self.edges.items.len);
            switch (builder.get(ty)) {
                .parameter => |parameter| try self.seed(gpa, ty, assumedCapability(parameter.requirement)),
                .struct_ => |record| {
                    try self.seed(gpa, ty, policyCapability(record.ownership_policy));
                    if (record.ownership_policy != .copyable) try self.markNoncopyable(gpa, ty);
                    for (builder.fields.items(.ty)[record.first_field..][0..record.field_count]) |field|
                        try self.edge(gpa, ty, field);
                },
                .enum_ => |sum| {
                    try self.seed(gpa, ty, policyCapability(sum.ownership_policy));
                    if (sum.ownership_policy != .copyable) try self.markNoncopyable(gpa, ty);
                    for (sum.first_variant..sum.first_variant + sum.variant_count) |variant| {
                        const first = builder.variants.items(.first_field)[variant];
                        const len = builder.variants.items(.field_count)[variant];
                        for (builder.fields.items(.ty)[first..][0..len]) |field| try self.edge(gpa, ty, field);
                    }
                },
                .newtype => |nominal| {
                    try self.seed(gpa, ty, policyCapability(nominal.ownership_policy));
                    if (nominal.ownership_policy != .copyable) try self.markNoncopyable(gpa, ty);
                    try self.edge(gpa, ty, nominal.base);
                },
                .array => |array| if (array.count != 0) {
                    try self.edge(gpa, ty, array.element);
                },
                .closure => |closure| try self.edge(gpa, ty, closure.environment),
                .borrow, .callable, .integer, .open_integer, .open_type, .boolean, .float, .unit, .never, .poison => {},
            }
            if (builder.certified_storage != .none and view.declOfType(ty) == builder.certified_storage) {
                if (view.instanceOf(ty)) |instance| {
                    const arguments = view.argsOf(instance);
                    if (arguments.len != 0) try self.edge(gpa, ty, arguments[0]);
                } else if (builder.parameters.get(Typing.Builder.parameterKey(builder.certified_storage.index(), 0))) |element| {
                    try self.edge(gpa, ty, @enumFromInt(element));
                }
            }
            self.part_counts.items[ty.index()] = @intCast(self.edges.items.len - self.first_parts.items[ty.index()]);
        }
        var next: usize = 0;
        while (next < self.queue.items.len) : (next += 1) {
            const child = self.queue.items[next];
            var at = self.heads.items[child.index()];
            while (at != none) {
                const dependent = self.edges.items[at];
                try self.strengthen(gpa, dependent.owner, self.values.items[child.index()]);
                if (self.known_noncopyable.items[child.index()]) try self.markNoncopyable(gpa, dependent.owner);
                at = dependent.next;
            }
        }
        self.queue.clearRetainingCapacity();
    }
};

const ScopedCapabilityKey = struct { scope: DeclId, ty: TypeId };
const ScopedCapabilityMap = std.AutoHashMapUnmanaged(ScopedCapabilityKey, Capability);

/// A sparse product of lexical capability contexts and the canonical owned-part
/// graph. Each reached pair strengthens at most twice. Cycles begin at their
/// policy seeds, never at an unscoped result containing self-supported debt.
const ScopedCapabilityFacts = struct {
    const none = std.math.maxInt(u32);
    const Node = struct { ceiling: Capability, head: u32 = none };
    const Edge = struct { owner: ScopedCapabilityKey, next: u32 };
    values: ScopedCapabilityMap = .empty,
    ceilings: ScopedCapabilityMap = .empty,
    scopes: std.AutoHashMapUnmanaged(DeclId, void) = .empty,
    nodes: std.AutoHashMapUnmanaged(ScopedCapabilityKey, Node) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    pending: std.ArrayList(ScopedCapabilityKey) = .empty,
    queue: std.ArrayList(ScopedCapabilityKey) = .empty,

    fn deinit(self: *ScopedCapabilityFacts, gpa: std.mem.Allocator) void {
        self.values.deinit(gpa);
        self.ceilings.deinit(gpa);
        self.scopes.deinit(gpa);
        self.nodes.deinit(gpa);
        self.edges.deinit(gpa);
        self.pending.deinit(gpa);
        self.queue.deinit(gpa);
        self.* = .{};
    }

    fn prepareScope(self: *ScopedCapabilityFacts, builder: *Typing.Builder, scope: DeclId) !void {
        if (self.scopes.contains(scope)) return;
        const constraints = builder.contextual_constraints;
        for ([_]DeclId{ scope, constraints.parentOf(scope) }) |owner| {
            for (constraints.run(owner)) |constraint| {
                const ceiling = assumedCapability(constraint.demand.requirement);
                if (ceiling == .linear) continue;
                const entry = try self.ceilings.getOrPut(builder.gpa, .{ .scope = scope, .ty = constraint.subject });
                entry.value_ptr.* = if (entry.found_existing)
                    @enumFromInt(@min(@intFromEnum(entry.value_ptr.*), @intFromEnum(ceiling)))
                else
                    ceiling;
            }
        }
        try self.scopes.put(builder.gpa, scope, {});
    }

    fn ensure(self: *ScopedCapabilityFacts, builder: *Typing.Builder, key: ScopedCapabilityKey) !void {
        if (self.values.contains(key)) return;
        const ceiling = self.ceilings.get(key) orelse .linear;
        const seed: Capability = @enumFromInt(@min(@intFromEnum(ceiling), @intFromEnum(builder.capability_facts.seeds.items[key.ty.index()])));
        try self.pending.append(builder.gpa, key);
        try self.nodes.put(builder.gpa, key, .{ .ceiling = ceiling });
        try self.values.put(builder.gpa, key, seed);
        try self.queue.append(builder.gpa, key);
    }

    fn strengthen(self: *ScopedCapabilityFacts, gpa: std.mem.Allocator, key: ScopedCapabilityKey, incoming: Capability) !void {
        const ceiling = self.nodes.get(key).?.ceiling;
        const next: Capability = @enumFromInt(@min(@intFromEnum(ceiling), @intFromEnum(incoming)));
        const value = self.values.getPtr(key).?;
        if (@intFromEnum(value.*) >= @intFromEnum(next)) return;
        try self.queue.append(gpa, key);
        value.* = next;
    }

    fn prepare(self: *ScopedCapabilityFacts, builder: *Typing.Builder, scope: DeclId, ty: TypeId) !void {
        try self.prepareScope(builder, scope);
        try self.ensure(builder, .{ .scope = scope, .ty = ty });
        var at: usize = 0;
        while (at < self.pending.items.len) : (at += 1) {
            const owner = self.pending.items[at];
            const first = builder.capability_facts.first_parts.items[owner.ty.index()];
            const count = builder.capability_facts.part_counts.items[owner.ty.index()];
            for (builder.capability_facts.edges.items[first..][0..count]) |part| {
                const child: ScopedCapabilityKey = .{ .scope = scope, .ty = part.child };
                try self.ensure(builder, child);
                // Reopened frozen rows cannot change while types only append.
                // They supply a value without needing a mutable reverse edge.
                if (self.nodes.get(child)) |found_node| {
                    const index: u32 = @intCast(self.edges.items.len);
                    try self.edges.append(builder.gpa, .{ .owner = owner, .next = found_node.head });
                    self.nodes.getPtr(child).?.head = index;
                }
                try self.strengthen(builder.gpa, owner, self.values.get(child).?);
            }
        }
        at = 0;
        while (at < self.queue.items.len) : (at += 1) {
            const child = self.queue.items[at];
            var edge = self.nodes.get(child).?.head;
            while (edge != none) {
                const dependent = self.edges.items[edge];
                try self.strengthen(builder.gpa, dependent.owner, self.values.get(child).?);
                edge = dependent.next;
            }
        }
        self.pending.clearRetainingCapacity();
        self.queue.clearRetainingCapacity();
    }
};

const BorrowContainment = struct {
    /// `raw_carriers` answers whether a value of the type may carry a
    /// dependency: whether it can reach an observation, a view, raw storage or
    /// a type parameter not bounded `Owned`. It is the one answer contract
    /// inference, ownership, storage lowering and the `Owned` bound read.
    /// `writers` answers whether a value of the type may hold something that
    /// can write through a place lent `inout`: a closure, a function value,
    /// or a type parameter an instantiation could make one. It follows fields,
    /// observed referents and every type argument, phantom ones included, so
    /// a container that erases what it stores is still counted.
    const Mode = enum { raw_carriers, writers };
    const none = std.math.maxInt(u32);
    const Edge = struct { owner: TypeId, next: u32 };
    values: std.ArrayList(bool) = .empty,
    heads: std.ArrayList(u32) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    queue: std.ArrayList(TypeId) = .empty,
    scanned: usize = 0,
    dirty: bool = false,
    coverage: DependencyCoverage = .{},

    fn invalidate(self: *BorrowContainment, owner: TypeId) void {
        if (owner.index() < self.scanned) {
            if (!self.dirty) self.coverage.capable_children.clearRetainingCapacity();
            self.dirty = true;
        }
    }

    fn deinit(self: *BorrowContainment, gpa: std.mem.Allocator) void {
        self.values.deinit(gpa);
        self.heads.deinit(gpa);
        self.edges.deinit(gpa);
        self.queue.deinit(gpa);
        self.coverage.deinit(gpa);
        self.* = .{};
    }

    fn mark(self: *BorrowContainment, gpa: std.mem.Allocator, ty: TypeId) !void {
        if (self.values.items[@intFromEnum(ty)]) return;
        try self.queue.append(gpa, ty);
        self.values.items[@intFromEnum(ty)] = true;
    }

    fn edge(self: *BorrowContainment, gpa: std.mem.Allocator, owner: TypeId, child: TypeId) !void {
        const at: u32 = @intCast(self.edges.items.len);
        try self.edges.append(gpa, .{ .owner = owner, .next = self.heads.items[@intFromEnum(child)] });
        self.heads.items[@intFromEnum(child)] = at;
        if (self.values.items[@intFromEnum(child)]) try self.mark(gpa, owner);
    }

    /// One step from a type to a part whose dependencies it holds.
    pub const Step = union(enum) {
        /// A structure's field, a closure environment's capture included.
        field: []const u8,
        /// A payload of the named variant.
        variant: []const u8,
        /// An element of a fixed array, or an observation's referent.
        element,
        /// A newtype's base.
        base,
        /// A closure's environment.
        environment,
        /// The elements certified storage holds.
        stored,
        /// A type argument, which a writer may be.
        argument,
    };

    /// Every part `ty` holds whose dependencies `ty` holds too, in `mode`,
    /// handed to `visit.child(step, part)`. The containment table is built
    /// over these edges and a witness path is found over them, so the two
    /// cannot disagree about what a type contains.
    fn eachChild(builder: *Typing.Builder, ty: TypeId, mode: Mode, visit: anytype) std.mem.Allocator.Error!void {
        const view = builder.view();
        const typed_storage = builder.certified_storage != .none and
            view.declOfType(ty) == builder.certified_storage and view.instanceOf(ty) != null;
        switch (builder.get(ty)) {
            .closure => |closure| try visit.child(.environment, closure.environment),
            .borrow => |observation| if (mode == .writers) try visit.child(.element, observation.referent),
            .parameter => {},
            .array => |array| if (array.count != 0) {
                try visit.child(.element, array.element);
            },
            .newtype => |newtype| try visit.child(.base, newtype.base),
            .struct_ => |record| {
                const names = builder.fields.items(.name)[record.first_field..][0..record.field_count];
                for (builder.fields.items(.ty)[record.first_field..][0..record.field_count], names, 0..) |field, name, index| {
                    // Certified storage's optional backing owner erases its
                    // elements. Its logical T and separate allocator field
                    // describe their dependencies without that raw erasure.
                    if (typed_storage and index == 0 and mode != .writers) continue;
                    try visit.child(.{ .field = name }, field);
                }
            },
            .enum_ => |sum| {
                for (sum.first_variant..sum.first_variant + sum.variant_count) |variant| {
                    const first = builder.variants.items(.first_field)[variant];
                    const len = builder.variants.items(.field_count)[variant];
                    const name = builder.variants.items(.name)[variant];
                    for (builder.fields.items(.ty)[first..][0..len]) |field| try visit.child(.{ .variant = name }, field);
                }
            },
            else => {},
        }
        if (mode == .writers) {
            if (view.instanceOf(ty)) |instance| for (view.argsOf(instance)) |argument| try visit.child(.argument, argument);
        } else if (builder.certified_storage != .none and view.declOfType(ty) == builder.certified_storage) {
            if (view.instanceOf(ty)) |instance| {
                const arguments = view.argsOf(instance);
                if (arguments.len != 0) try visit.child(.stored, arguments[0]);
            }
        }
    }

    /// Records each part a type holds as an edge back to that type.
    const Edges = struct {
        containment: *BorrowContainment,
        gpa: std.mem.Allocator,
        owner: TypeId,

        fn child(edges: Edges, _: Step, part: TypeId) std.mem.Allocator.Error!void {
            try edges.containment.edge(edges.gpa, edges.owner, part);
        }
    };

    fn update(self: *BorrowContainment, builder: *Typing.Builder, mode: Mode) !void {
        const gpa = builder.gpa;
        if (self.dirty) {
            self.values.clearRetainingCapacity();
            self.heads.clearRetainingCapacity();
            self.edges.clearRetainingCapacity();
            self.queue.clearRetainingCapacity();
            self.scanned = 0;
            self.dirty = false;
        }
        const count = builder.pool.items.len;
        try self.values.appendNTimes(gpa, false, count - self.values.items.len);
        try self.heads.appendNTimes(gpa, none, count - self.heads.items.len);
        const view = builder.view();
        while (self.scanned < count) : (self.scanned += 1) {
            const ty: TypeId = @enumFromInt(@as(u32, @intCast(self.scanned)));
            try eachChild(builder, ty, mode, Edges{ .containment = self, .gpa = gpa, .owner = ty });
            switch (mode) {
                .writers => switch (builder.get(ty)) {
                    .closure, .callable, .parameter, .open_type => try self.mark(gpa, ty),
                    else => {},
                },
                else => if (view.directDependencySeed(ty)) try self.mark(gpa, ty),
            }
        }
        var next: usize = 0;
        while (next < self.queue.items.len) : (next += 1) {
            var at = self.heads.items[@intFromEnum(self.queue.items[next])];
            while (at != none) {
                const dependent = self.edges.items[at];
                try self.mark(gpa, dependent.owner);
                at = dependent.next;
            }
        }
        self.queue.clearRetainingCapacity();
    }
};

pub const ContainmentStep = BorrowContainment.Step;

/// A path from a type to a part that holds a dependency directly: an
/// observation, a view, raw storage, or a type parameter that may be one.
pub const DependencyWitness = struct {
    steps: []const ContainmentStep,
    /// The type each step reaches: `parts[i]` is the part `steps[i]` selects.
    parts: []const TypeId,
    seed: TypeId,

    pub fn deinit(self: DependencyWitness, gpa: std.mem.Allocator) void {
        gpa.free(self.steps);
        gpa.free(self.parts);
    }
};

pub const PathSelector = union(enum) { field: StringId, observed };

fn sameSelectors(a: []const PathSelector, b: []const PathSelector) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (!std.meta.eql(x, y)) return false;
    return true;
}

fn hashSelectors(h: *std.hash.Wyhash, selectors: []const PathSelector) void {
    for (selectors) |selector| {
        const tag: u8 = @intFromEnum(selector);
        h.update(std.mem.asBytes(&tag));
        if (selector == .field) h.update(std.mem.asBytes(&selector.field));
    }
}

pub const ContractRoot = union(enum) {
    parameter: u32,
    capture: struct { closure: ids.ClosureId, field: FieldOrdinal },
    /// External dependencies carried by an opaque callable environment.
    callee,

    fn hash(self: ContractRoot, h: *std.hash.Wyhash) void {
        const tag: u8 = @intFromEnum(self);
        h.update(std.mem.asBytes(&tag));
        switch (self) {
            .callee => {},
            .parameter => |index| h.update(std.mem.asBytes(&index)),
            .capture => |capture| {
                h.update(std.mem.asBytes(&capture.closure));
                h.update(std.mem.asBytes(&capture.field));
            },
        }
    }

    fn mangled(self: ContractRoot, gpa: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .callee => gpa.dupe(u8, "callee:"),
            .parameter => |index| std.fmt.allocPrint(gpa, "{d}:", .{index}),
            .capture => |capture| std.fmt.allocPrint(gpa, "c{d}.{d}:", .{ capture.closure.index(), capture.field.index() }),
        };
    }
};

pub const ContractPath = struct {
    root: ContractRoot,
    fields: []const PathSelector = &.{},
    spelling: []const u8 = "",
};

pub const ResultSelector = union(enum) {
    field: struct { name: StringId, index: u32 },
    payload: struct { variant: VariantOrdinal, index: u32 },
};

pub fn sameResultSelectors(a: []const ResultSelector, b: []const ResultSelector) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (!std.meta.eql(x, y)) return false;
    return true;
}

pub const CallableContract = struct {
    kind: enum { borrows, carries, retains },
    source: ContractPath,
    target: []const ResultSelector = &.{},
    target_spelling: []const u8 = "",
    destination: ?ContractPath = null,
    borrows_source: bool = false,
};

/// What a signature written without a clause carries its result from.
pub const InferredSource = union(enum) {
    /// No parameter can reach the result, so it depends on nothing.
    none,
    /// One parameter can: the result borrows its place where `place` is set
    /// and carries its dependencies otherwise.
    one: struct { parameter: u32, place: bool, by_carrier: bool = false },
    /// Several parameters can, and the signature must say which.
    ambiguous,
};

/// The source a signature without a clause carries its result from: the one
/// parameter that lends the result's place or forwards dependencies into it.
/// A result that carries nothing needs none. Where several parameters can,
/// the one carrier among them settles the choice, unless a parameter other
/// than the carrier lends the place the result observes: a result typed as a
/// borrow of a parameter's type names its own provenance, and a carrier never
/// overrides it. A result that observes the carrier's own place borrows it.
/// Otherwise the source is undecided.
///
/// **Bound:** one pass over the signature's parameters.
pub fn inferredSource(builder: *Typing.Builder, params: []const CallableParam, result: TypeId, carrier: ?u32) !InferredSource {
    if (!try builder.mayCarryDependencies(result)) return .none;
    var found: InferredSource = .none;
    var ambiguous = false;
    var carrier_eligible = false;
    var other_place_lent = false;
    for (params, 0..) |parameter, index| {
        const place = lendsPlace(builder, parameter, result);
        if (!place and !try builder.mayCarryDependencies(parameter.ty)) continue;
        const is_carrier = carrier != null and carrier.? == index;
        if (is_carrier) carrier_eligible = true;
        if (place and !is_carrier) other_place_lent = true;
        if (found != .none) ambiguous = true else found = .{ .one = .{ .parameter = @intCast(index), .place = place } };
    }
    if (!ambiguous) return found;
    if (carrier) |index| if (carrier_eligible and !other_place_lent) {
        // A result that observes the carrier's own place says so.
        return .{ .one = .{ .parameter = index, .place = lendsPlace(builder, params[index], result), .by_carrier = true } };
    };
    return .ambiguous;
}

/// Whether `parameter` lends the place a borrowed `result` observes.
fn lendsPlace(builder: *Typing.Builder, parameter: CallableParam, result: TypeId) bool {
    return builder.get(result) == .borrow and builder.get(result).borrow.referent == parameter.ty and suppliesEscapingPlace(parameter.convention);
}

/// Whether `parameter` is one of the sources `inferredSource` weighs for
/// `result`; a diagnostic that lists the candidates asks this rather than
/// deciding eligibility again.
pub fn isEligibleSource(builder: *Typing.Builder, parameter: CallableParam, result: TypeId) !bool {
    return lendsPlace(builder, parameter, result) or try builder.mayCarryDependencies(parameter.ty);
}

/// A source a clause names: the parameter's spelling, and whether the clause
/// is `borrows`, for a result that observes the parameter's place, or
/// `carries`, for one that keeps what the parameter already observes.
pub const ClauseSource = struct { spelling: []const u8, borrows: bool };

/// Whether a parameter passed by `convention` can supply the place an
/// escaping observation observes. A consumed parameter ends with the
/// function, so nothing may observe it past the return: `borrows` cannot name
/// it, and only what it already carries may leave. The one rule for refusing
/// such a clause and for every report that suggests one.
pub fn suppliesEscapingPlace(convention: Convention) bool {
    return convention != .sink;
}

/// Whether the clause naming `parameter` as a source of `result` is
/// `borrows`: the parameter can supply an escaping place, and it lends the
/// place the result observes or may hold storage of its own a view of it
/// would point into and holds no view. A parameter that holds a view, such as
/// a `Str` or a struct with one, may hand on what it observes: `carries` says
/// that and holds a caller to no more, which is what the body's [O-Escapes]
/// names for such a body too.
pub fn borrowsFrom(builder: *Typing.Builder, gpa: std.mem.Allocator, parameter: CallableParam, result: TypeId) !bool {
    if (!suppliesEscapingPlace(parameter.convention)) return false;
    if (lendsPlace(builder, parameter, result)) return true;
    const pool = builder.view();
    return try pool.mayHoldStorage(gpa, parameter.ty) and !try pool.holdsView(gpa, parameter.ty);
}

/// The `where` clause naming `sources`, the `borrows` sources first:
/// `where borrows(first, second)`, `where carries(left)`, or
/// `where borrows(first), carries(second)`. Every report that names the
/// clause a signature lacks spells it here, so a signature the checker could
/// not infer and a body the ownership pass refused are given one answer.
pub fn sourceClause(arena: std.mem.Allocator, sources: []const ClauseSource) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "where ");
    var groups: usize = 0;
    for ([_]bool{ true, false }) |borrows| {
        var listed: usize = 0;
        for (sources) |source| {
            if (source.borrows != borrows) continue;
            if (listed == 0) {
                if (groups > 0) try out.appendSlice(arena, ", ");
                try out.appendSlice(arena, if (borrows) "borrows(" else "carries(");
                groups += 1;
            } else try out.appendSlice(arena, ", ");
            try out.appendSlice(arena, source.spelling);
            listed += 1;
        }
        if (listed > 0) try out.append(arena, ')');
    }
    return out.items;
}

/// A retention a clause names: what the `inout` parameter `destination`
/// keeps from `source`, and whether it keeps an observation of `source`'s
/// place.
pub const ClauseRetention = struct { destination: []const u8, source: []const u8, borrows: bool };

/// The whole `where` clause a signature needs once it also says what
/// `added` and `retained` name: every contract in `written` (the clause the
/// declaration wrote, or the contract it inferred where `keep` is not null,
/// keeping only the parameters `keep` lists), with the new sources and
/// retentions beside them. The plain sources group as `sourceClause` writes
/// them, `where borrows(a, b), carries(c)`, and any other contract follows as
/// it is written. Every report that names a clause to write names this one,
/// so writing it never drops a contract another report needs.
pub fn wholeClause(
    arena: std.mem.Allocator,
    written: []const CallableContract,
    names: []const []const u8,
    keep: ?[]const u32,
    added: []const ClauseSource,
    retained: []const ClauseRetention,
) std.mem.Allocator.Error![]const u8 {
    var sources: std.ArrayList(ClauseSource) = .empty;
    var rest: std.ArrayList(u8) = .empty;
    var rests: usize = 0;
    var kept_retentions: std.ArrayList(ClauseRetention) = .empty;
    for (written) |contract| {
        const at: ?u32 = switch (contract.source.root) {
            .parameter => |index| if (index < names.len) index else null,
            else => null,
        };
        const plain = at != null and contract.kind != .retains and contract.target.len == 0 and contract.source.fields.len == 0 and !contract.borrows_source;
        if (plain) {
            if (keep) |listed| if (std.mem.indexOfScalar(u32, listed, at.?) == null) continue;
            try addClauseSource(arena, &sources, .{ .spelling = names[at.?], .borrows = contract.kind == .borrows });
            continue;
        }
        // An inferred contract keeps only plain sources; anything else was
        // written, and is kept whatever `keep` says.
        if (keep != null) continue;
        if (contract.kind == .retains) if (contract.destination) |dest| if (at != null and dest.fields.len == 0 and contract.source.fields.len == 0) {
            switch (dest.root) {
                .parameter => |d| if (d < names.len) {
                    try kept_retentions.append(arena, .{ .destination = names[d], .source = names[at.?], .borrows = contract.borrows_source });
                    continue;
                },
                else => {},
            }
        };
        var one: std.ArrayList(u8) = .empty;
        try appendContractText(arena, &one, &.{contract}, names, false);
        try rest.print(arena, "{s}{s}", .{ if (rests == 0) "" else ", ", one.items[" where ".len..] });
        rests += 1;
    }
    for (added) |source| try addClauseSource(arena, &sources, source);
    for (retained) |retention| {
        for (kept_retentions.items) |*existing| {
            if (std.mem.eql(u8, existing.destination, retention.destination) and std.mem.eql(u8, existing.source, retention.source)) {
                existing.borrows = existing.borrows or retention.borrows;
                break;
            }
        } else try kept_retentions.append(arena, retention);
    }
    var out: std.ArrayList(u8) = .empty;
    if (sources.items.len > 0) try out.appendSlice(arena, try sourceClause(arena, sources.items));
    if (rests > 0) try out.print(arena, "{s}{s}", .{ if (out.items.len == 0) "where " else ", ", rest.items });
    for (kept_retentions.items) |retention| try out.print(arena, "{s}retains({s}: {s}{s})", .{
        if (out.items.len == 0) "where " else ", ",
        retention.destination,
        if (retention.borrows) "borrow " else "",
        retention.source,
    });
    if (out.items.len == 0) try out.appendSlice(arena, "where carries()");
    return out.items;
}

/// Adds `source` to a clause's plain sources, once: a source named both ways
/// is named `borrows`, which keeps what `carries` keeps too.
fn addClauseSource(arena: std.mem.Allocator, sources: *std.ArrayList(ClauseSource), source: ClauseSource) std.mem.Allocator.Error!void {
    for (sources.items) |*existing| if (std.mem.eql(u8, existing.spelling, source.spelling)) {
        existing.borrows = existing.borrows or source.borrows;
        return;
    };
    try sources.append(arena, source);
}

test wholeClause {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const names: []const []const u8 = &.{ "seen", "a", "b" };
    // The returned source and the retention each keep the other.
    try testing.expectEqualStrings("where borrows(a, b), retains(seen: borrow b)", try wholeClause(a, &.{
        .{ .kind = .retains, .source = .{ .root = .{ .parameter = 2 } }, .destination = .{ .root = .{ .parameter = 0 } }, .borrows_source = true },
        .{ .kind = .borrows, .source = .{ .root = .{ .parameter = 1 } } },
    }, names, null, &.{.{ .spelling = "b", .borrows = true }}, &.{}));
    try testing.expectEqualStrings("where borrows(b), retains(seen: borrow b)", try wholeClause(a, &.{
        .{ .kind = .borrows, .source = .{ .root = .{ .parameter = 2 } } },
    }, names, null, &.{}, &.{.{ .destination = "seen", .source = "b", .borrows = true }}));
    // An inferred contract keeps only the sources listed.
    try testing.expectEqualStrings("where borrows(b)", try wholeClause(a, &.{
        .{ .kind = .carries, .source = .{ .root = .{ .parameter = 1 } } },
    }, names, &.{}, &.{.{ .spelling = "b", .borrows = true }}, &.{}));
}

test sourceClause {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("where borrows(first, second)", try sourceClause(a, &.{ .{ .spelling = "first", .borrows = true }, .{ .spelling = "second", .borrows = true } }));
    try testing.expectEqualStrings("where carries(left)", try sourceClause(a, &.{.{ .spelling = "left", .borrows = false }}));
    try testing.expectEqualStrings("where borrows(first), carries(second)", try sourceClause(a, &.{ .{ .spelling = "second", .borrows = false }, .{ .spelling = "first", .borrows = true } }));
}

test inferredSource {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();
    const observed = try b.borrowOf(.u8);
    const lent: CallableParam = .{ .spelling = "lent", .convention = .read, .ty = .u8, .default = .absent };
    const carried: CallableParam = .{ .spelling = "carried", .convention = .read, .ty = observed, .default = .absent };
    const count: CallableParam = .{ .spelling = "count", .convention = .read, .ty = .u64, .default = .absent };

    try testing.expectEqual(InferredSource.none, try inferredSource(&b, &.{carried}, .u8, null));
    try testing.expectEqual(InferredSource.none, try inferredSource(&b, &.{count}, observed, null));
    try testing.expectEqual(InferredSource{ .one = .{ .parameter = 0, .place = true } }, try inferredSource(&b, &.{lent}, observed, null));
    try testing.expectEqual(InferredSource{ .one = .{ .parameter = 1, .place = false } }, try inferredSource(&b, &.{ count, carried }, observed, null));
    try testing.expectEqual(InferredSource.ambiguous, try inferredSource(&b, &.{ lent, carried }, observed, null));
    // A carrier never overrides a lent place.
    try testing.expectEqual(InferredSource.ambiguous, try inferredSource(&b, &.{ lent, carried }, observed, 1));
    // The carrier may itself be the place the result observes.
    try testing.expectEqual(
        InferredSource{ .one = .{ .parameter = 0, .place = true, .by_carrier = true } },
        try inferredSource(&b, &.{ lent, carried }, observed, 0),
    );
    // A single eligible source is that source, carrier or not.
    try testing.expectEqual(
        InferredSource{ .one = .{ .parameter = 1, .place = false } },
        try inferredSource(&b, &.{ count, carried }, observed, 1),
    );
    // Dependencies alone tie, and the carrier settles them.
    const other: CallableParam = .{ .spelling = "other", .convention = .read, .ty = observed, .default = .absent };
    try testing.expectEqual(InferredSource.ambiguous, try inferredSource(&b, &.{ other, carried }, observed, null));
    try testing.expectEqual(
        InferredSource{ .one = .{ .parameter = 1, .place = false, .by_carrier = true } },
        try inferredSource(&b, &.{ other, carried }, observed, 1),
    );
    try testing.expectEqual(InferredSource.none, try inferredSource(&b, &.{carried}, .u8, 0));
}

fn sameContractPath(a: ContractPath, b: ContractPath) bool {
    return std.meta.eql(a.root, b.root) and sameSelectors(a.fields, b.fields);
}

fn dependencyFreeScalar(pool: anytype, ty: TypeId) bool {
    return switch (pool.get(ty)) {
        .integer, .open_integer, .float, .boolean, .unit, .never => true,
        .newtype => |named| dependencyFreeScalar(pool, named.base),
        else => false,
    };
}

pub fn sameContracts(a: []const CallableContract, b: []const CallableContract) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x.kind != y.kind or x.borrows_source != y.borrows_source or !sameContractPath(x.source, y.source) or !sameResultSelectors(x.target, y.target)) return false;
        if ((x.destination == null) != (y.destination == null)) return false;
        if (x.destination) |destination| if (!sameContractPath(destination, y.destination.?)) return false;
    }
    return true;
}

fn pathWithin(path: ContractPath, root: ContractPath) bool {
    return std.meta.eql(path.root, root.root) and path.fields.len >= root.fields.len and
        sameSelectors(path.fields[0..root.fields.len], root.fields);
}

fn calleeCovers(effect: CallableContract, promise: CallableContract) bool {
    if (promise.source.root != .callee or promise.kind != .carries or promise.borrows_source or
        promise.destination != null or promise.source.fields.len != 0) return false;
    if (effect.kind == .retains or effect.destination != null or effect.borrows_source) return false;
    if (effect.source.root != .capture and effect.source.root != .callee) return false;
    if (effect.source.root == .callee and effect.kind != .carries) return false;
    return effect.target.len >= promise.target.len and sameResultSelectors(effect.target[0..promise.target.len], promise.target);
}

/// Whether a callable contract names a dependency, which is whether it belongs
/// in the signature's key: a result that is a scalar carries nothing, and
/// neither does a source parameter that is one. `result` and `source_parameter`
/// are the types the signature holds there, or null where they are not known
/// yet -- a type waiting on an implementation's parameters -- and an unknown
/// one is assumed to depend on something.
///
/// One rule for interning a signature and for matching one against a written
/// demand, so a contract dropped from the key is dropped from the comparison.
fn contractNamesDependency(pool: anytype, contract: CallableContract, result: ?TypeId, source_parameter: ?TypeId) bool {
    if (contract.kind == .carries and result != null and dependencyFreeScalar(pool, result.?)) return false;
    return contract.kind == .borrows or contract.borrows_source or
        switch (contract.source.root) {
            .parameter => !(source_parameter != null and dependencyFreeScalar(pool, source_parameter.?)),
            .capture, .callee => true,
        };
}

test "contractNamesDependency drops what carries nothing and keeps what may depend" {
    var builder = try Typing.Builder.init(testing.allocator);
    defer builder.deinit();
    const carries: CallableContract = .{ .kind = .carries, .source = .{ .root = .{ .parameter = 0 } } };
    // A scalar result carries nothing, and so does a scalar source.
    try testing.expect(!contractNamesDependency(&builder, carries, .u8, null));
    try testing.expect(!contractNamesDependency(&builder, carries, null, .u8));
    // A type not known yet is assumed to depend on something.
    try testing.expect(contractNamesDependency(&builder, carries, null, null));
    const callable = try builder.internCallable(&.{}, .u8, &.{}, .read);
    try testing.expect(contractNamesDependency(&builder, carries, callable, callable));
    const borrows: CallableContract = .{ .kind = .borrows, .source = .{ .root = .{ .parameter = 0 } } };
    try testing.expect(contractNamesDependency(&builder, borrows, .u8, .u8));
    const through_callee: CallableContract = .{ .kind = .retains, .source = .{ .root = .callee } };
    try testing.expect(contractNamesDependency(&builder, through_callee, .u8, .u8));
}

/// Result sources are upper bounds; retention effects remain exact when a
/// concrete callable satisfies a generic requirement.
pub fn callableContractsSatisfy(actual: []const CallableContract, promised: []const CallableContract) bool {
    if (!contractsWithin(actual, promised)) return false;
    var next: usize = 0;
    for (actual) |effect| {
        if (effect.kind != .retains) continue;
        while (next < promised.len and promised[next].kind != .retains) next += 1;
        if (next == promised.len or !sameContracts(&.{effect}, &.{promised[next]})) return false;
        next += 1;
    }
    while (next < promised.len and promised[next].kind != .retains) next += 1;
    return next == promised.len;
}

/// A body may use fewer sources and narrower fields than its public signature.
/// Place-retaining effects require a place promise; carried-only effects fit
/// either promise because observing a place includes its contained dependencies.
pub fn contractsWithin(actual: []const CallableContract, promised: []const CallableContract) bool {
    if (sameContracts(actual, promised)) return true;
    for (actual) |effect| {
        var covered = false;
        for (promised) |promise| {
            if (calleeCovers(effect, promise)) {
                covered = true;
                break;
            }
            if ((effect.kind == .retains) != (promise.kind == .retains)) continue;
            if (!pathWithin(effect.source, promise.source)) continue;
            if (effect.target.len < promise.target.len or !sameResultSelectors(effect.target[0..promise.target.len], promise.target)) continue;
            if (effect.kind == .borrows and promise.kind != .borrows) continue;
            if (effect.borrows_source and !promise.borrows_source) continue;
            if (effect.destination) |destination| {
                if (!pathWithin(destination, promise.destination orelse continue)) continue;
            }
            covered = true;
            break;
        }
        if (!covered) return false;
    }
    return true;
}

/// Inclusive array positions covered by one dependency path.
pub const ArrayCoverageRange = struct { first: u32, last: u32 };

/// Coverage of an ambient dependency by paths into its physical components.
/// Cache child counts per analysis; group suffixes once per traversed step.
pub const DependencyCoverage = struct {
    capable_children: std.AutoHashMapUnmanaged(TypeId, ?u32) = .empty,

    pub fn deinit(self: *DependencyCoverage, gpa: std.mem.Allocator) void {
        self.capable_children.deinit(gpa);
    }

    fn capableChildren(self: *DependencyCoverage, gpa: std.mem.Allocator, pool: *const Typing, ty: TypeId) !?u32 {
        if (self.capable_children.get(ty)) |count| return count;
        var count: u32 = 0;
        switch (pool.get(ty)) {
            .struct_ => for (0..pool.fieldCount(ty)) |index| {
                if (pool.mayCarryDependencies(pool.fieldType(ty, @intCast(index)))) count += 1;
            },
            .enum_ => for (0..pool.variantCount(ty)) |variant| {
                for (0..pool.variantFieldCount(ty, @intCast(variant))) |index| {
                    if (pool.mayCarryDependencies(pool.variantFieldType(ty, @intCast(variant), @intCast(index)))) count += 1;
                }
            },
            .array => |array| {
                count = if (pool.mayCarryDependencies(array.element)) array.count else 0;
            },
            else => {
                try self.capable_children.put(gpa, ty, null);
                return null;
            },
        }
        try self.capable_children.put(gpa, ty, count);
        return count;
    }

    pub fn covers(self: *DependencyCoverage, comptime Path: type, gpa: std.mem.Allocator, pool: *const Typing, ty: TypeId, paths: []const Path, context: anytype) std.mem.Allocator.Error!bool {
        for (paths) |path| if (context.isRoot(path)) return true;
        if (!pool.mayCarryDependencies(ty)) return true;
        if (pool.hasDirectDependencies(ty) or paths.len == 0) return false;
        const needed = try self.capableChildren(gpa, pool, ty) orelse return false;
        const PathHead = @TypeOf(context.head(@as(Path, undefined)));
        var groups: std.AutoHashMapUnmanaged(PathHead, std.ArrayList(Path)) = .empty;
        defer {
            var lists = groups.valueIterator();
            while (lists.next()) |list| list.deinit(gpa);
            groups.deinit(gpa);
        }
        for (paths) |path| {
            const group = try groups.getOrPut(gpa, context.head(path));
            if (!group.found_existing) group.value_ptr.* = .empty;
            try group.value_ptr.append(gpa, context.tail(path));
        }
        var covered: u32 = 0;
        const shape = pool.get(ty);
        var ranges: std.ArrayList(ArrayCoverageRange) = .empty;
        defer ranges.deinit(gpa);
        var children = groups.iterator();
        while (children.next()) |child| {
            const child_ty = context.childType(ty, child.key_ptr.*) orelse continue;
            if (!pool.mayCarryDependencies(child_ty)) continue;
            if (try self.covers(Path, gpa, pool, child_ty, child.value_ptr.items, context)) {
                if (shape == .array) {
                    const range = context.arrayRange(child.key_ptr.*, shape.array.count) orelse continue;
                    if (range.first > range.last or range.last >= shape.array.count) continue;
                    try ranges.append(gpa, range);
                } else covered += 1;
            }
        }
        if (shape == .array) {
            // Count the union: distinct path groups may describe overlapping slots.
            std.mem.sortUnstable(ArrayCoverageRange, ranges.items, {}, struct {
                fn less(_: void, a: ArrayCoverageRange, b: ArrayCoverageRange) bool {
                    return a.first < b.first or (a.first == b.first and a.last < b.last);
                }
            }.less);
            var end: u32 = 0;
            for (ranges.items) |range| {
                const after = range.last + 1;
                if (after <= end) continue;
                covered += after - @max(end, range.first);
                end = after;
            }
        }
        return covered == needed;
    }
};

/// A contract path as text. A parameter is spelled by `names` where they
/// are given, the names of the declaration the contract was written on, and
/// by its position otherwise: a signature's parameter names are not part of
/// its type, so a type's own spelling of them would be whichever declaration
/// wrote it first.
fn appendContractPath(gpa: std.mem.Allocator, out: anytype, path: ContractPath, names: ?[]const []const u8, mangled: bool) !void {
    switch (path.root) {
        .parameter => |index| {
            const rest = if (std.mem.indexOfScalar(u8, path.spelling, '.')) |dot| path.spelling[dot..] else "";
            if (mangled) {
                const position = try path.root.mangled(gpa);
                defer gpa.free(position);
                try out.appendSlice(gpa, position);
            } else if (names != null and index < names.?.len) {
                try out.appendSlice(gpa, names.?[index]);
            } else {
                const position = try std.fmt.allocPrint(gpa, "#{d}", .{index + 1});
                defer gpa.free(position);
                try out.appendSlice(gpa, position);
            }
            try out.appendSlice(gpa, rest);
        },
        .capture, .callee => {
            if (mangled) {
                const position = try path.root.mangled(gpa);
                defer gpa.free(position);
                try out.appendSlice(gpa, position);
            }
            try out.appendSlice(gpa, path.spelling);
        },
    }
}

fn appendContractText(gpa: std.mem.Allocator, out: anytype, contracts: []const CallableContract, names: ?[]const []const u8, mangled: bool) !void {
    for (contracts, 0..) |contract, index| {
        if (!mangled) try out.appendSlice(gpa, if (index == 0) " where " else ", ");
        try out.appendSlice(gpa, @tagName(contract.kind));
        try out.append(gpa, '(');
        if (contract.target.len != 0) {
            try out.appendSlice(gpa, contract.target_spelling);
            try out.appendSlice(gpa, if (mangled) ":" else ": ");
        }
        if (contract.destination) |dest| {
            try appendContractPath(gpa, out, dest, names, mangled);
            try out.appendSlice(gpa, if (mangled) ":" else ": ");
        }
        if (contract.borrows_source) try out.appendSlice(gpa, if (mangled) "borrow:" else "borrow ");
        try appendContractPath(gpa, out, contract.source, names, mangled);
        try out.append(gpa, ')');
    }
}

/// A signature's contracts as its `where` clause is written on the
/// declaration whose parameters are `names`, with `carries()` standing for a
/// signature that carries nothing.
pub fn contractClause(gpa: std.mem.Allocator, contracts: []const CallableContract, names: []const []const u8) ![]u8 {
    if (contracts.len == 0) return gpa.dupe(u8, "where carries()");
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try appendContractText(gpa, &out, contracts, names, false);
    // The clause text begins with the space that separates it from a result.
    return gpa.dupe(u8, out.items[1..]);
}

test contractClause {
    const gpa = testing.allocator;
    const none = try contractClause(gpa, &.{}, &.{});
    defer gpa.free(none);
    try testing.expectEqualStrings("where carries()", none);

    const two = try contractClause(gpa, &.{
        .{ .kind = .carries, .source = .{ .root = .{ .parameter = 1 }, .spelling = "request" }, .target_spelling = ".Ok", .target = &.{.{ .payload = .{ .variant = @enumFromInt(0), .index = 0 } }} },
        .{ .kind = .borrows, .source = .{ .root = .{ .parameter = 0 }, .spelling = "other" } },
    }, &.{ "self", "request" });
    defer gpa.free(two);
    try testing.expectEqualStrings("where carries(.Ok: request), borrows(self)", two);

    const positional = try contractClause(gpa, &.{
        .{ .kind = .carries, .source = .{ .root = .{ .parameter = 1 }, .spelling = "request.body" } },
    }, &.{});
    defer gpa.free(positional);
    try testing.expectEqualStrings("where carries(#2.body)", positional);
}

pub fn freeContractPath(gpa: std.mem.Allocator, path: ContractPath) void {
    gpa.free(path.fields);
    gpa.free(path.spelling);
}

fn duplicateContractPath(gpa: std.mem.Allocator, path: ContractPath) !ContractPath {
    const fields = try gpa.dupe(PathSelector, path.fields);
    errdefer gpa.free(fields);
    return .{ .root = path.root, .fields = fields, .spelling = try gpa.dupe(u8, path.spelling) };
}

pub fn freeContracts(gpa: std.mem.Allocator, contracts: []const CallableContract) void {
    for (contracts) |contract| {
        freeContractPath(gpa, contract.source);
        gpa.free(contract.target);
        gpa.free(contract.target_spelling);
        if (contract.destination) |destination| freeContractPath(gpa, destination);
    }
    gpa.free(contracts);
}

fn duplicateContracts(gpa: std.mem.Allocator, contracts: []const CallableContract) ![]const CallableContract {
    const result = try gpa.alloc(CallableContract, contracts.len);
    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |contract| {
            freeContractPath(gpa, contract.source);
            gpa.free(contract.target);
            gpa.free(contract.target_spelling);
            if (contract.destination) |destination| freeContractPath(gpa, destination);
        }
        gpa.free(result);
    }
    for (contracts, result) |contract, *out| {
        const source = try duplicateContractPath(gpa, contract.source);
        errdefer freeContractPath(gpa, source);
        const target = try gpa.dupe(ResultSelector, contract.target);
        errdefer gpa.free(target);
        const target_spelling = try gpa.dupe(u8, contract.target_spelling);
        errdefer gpa.free(target_spelling);
        const destination: ?ContractPath = if (contract.destination) |dest| try duplicateContractPath(gpa, dest) else null;
        out.* = .{ .kind = contract.kind, .source = source, .target = target, .target_spelling = target_spelling, .destination = destination, .borrows_source = contract.borrows_source };
        initialized += 1;
    }
    return result;
}

pub const CallableParam = struct {
    /// How the parameter is spelled in contracts written on the signature
    /// this parameter was first interned with. Not part of the type, and not
    /// the label a call names: those come from the declaration.
    spelling: []const u8,
    convention: Convention,
    ty: TypeId,
    default: CallableDefault,
    stable_address: bool = false,

    /// Positional metadata shared by contextual conversion and bound matching.
    /// Types are compared by the caller after any required substitution.
    fn samePosition(a: CallableParam, b: CallableParam) bool {
        return a.convention == b.convention and a.stable_address == b.stable_address and
            a.default.eql(b.default);
    }
};

pub fn invocationCompatible(actual: Convention, wanted: Convention) bool {
    return actual == wanted or (actual == .read and wanted == .inout);
}

/// Whether two parameter lists are one by position. A parameter's name is a
/// label a call may use, not part of the type.
fn callableParamsMatch(a: []const CallableParam, b: []const CallableParam) bool {
    if (a.len != b.len) return false;
    for (a, b) |first, second| {
        if (first.ty != second.ty or !first.samePosition(second)) return false;
    }
    return true;
}

/// A signature as text. With `names`, the parameters and the contracts naming
/// them are spelled as a declaration writes them, which is a type a program
/// can write; without, by position, which is the type itself, since a
/// parameter's name is not part of it.
fn renderCallable(
    gpa: std.mem.Allocator,
    rendered: *TypeDisplay,
    pool: Typing,
    params: []const CallableParam,
    result: TypeId,
    contracts: []const CallableContract,
    invocation: Convention,
    independent: bool,
    names: ?[]const []const u8,
) !void {
    if (invocation != .read) {
        try rendered.appendSlice(gpa, @tagName(invocation));
        try rendered.append(gpa, ' ');
    }
    try rendered.appendSlice(gpa, "fn(");
    for (params, 0..) |param, i| {
        if (i > 0) try rendered.appendSlice(gpa, ", ");
        try rendered.appendSlice(gpa, @tagName(param.convention));
        try rendered.append(gpa, ' ');
        if (names) |spelled| if (i < spelled.len) {
            try rendered.appendSlice(gpa, spelled[i]);
            try rendered.appendSlice(gpa, ": ");
        };
        try rendered.appendSlice(gpa, pool.nameOf(param.ty));
        switch (param.default) {
            .absent => {},
            .value => |value| {
                const folded = try value.text(gpa, &pool.constant_pool);
                defer gpa.free(folded);
                try rendered.appendSlice(gpa, " = ");
                try rendered.appendSlice(gpa, folded);
            },
        }
    }
    try rendered.append(gpa, ')');
    // A callable returning `()` is written without a result, so it is shown
    // without one.
    if (result != .unit) {
        try rendered.appendSlice(gpa, " -> ");
        try rendered.appendSlice(gpa, pool.nameOf(result));
    }
    try appendContractText(gpa, rendered, contracts, names, false);
    if (independent) try rendered.appendSlice(gpa, " where carries()");
}

/// One exact structural callable signature and its parameter run.
pub const CallableSignature = struct {
    invocation: Convention = .read,
    /// Whether the signature promises an independent result its text must
    /// spell as `where carries()`, decided once where it is interned.
    independent: bool = false,
    contracts: []const CallableContract = &.{},
    first_param: u32,
    param_count: u32,
    result: TypeId,
    name: []const u8,
};

/// A lambda source identity applied to its enclosing type arguments.
pub const ClosureType = struct {
    closure: ids.ClosureId,
    environment: TypeId = .unit,
    /// Prepared for a reachable body after its source signature is final.
    body_signature: TypeId = .poison,
    first_arg: u32,
    arg_count: u32,
    impl_arg_count: u32 = 0,
    self_ty: TypeId = .poison,
};

fn closureTypeHash(closure: ids.ClosureId, args: []const TypeId, impl_args: []const TypeId, self_ty: TypeId) u64 {
    var h = std.hash.Wyhash.init(@intFromEnum(closure));
    h.update(std.mem.asBytes(&args.len));
    h.update(std.mem.sliceAsBytes(args));
    h.update(std.mem.sliceAsBytes(impl_args));
    h.update(std.mem.asBytes(&self_ty));
    return h.final();
}

pub const ClosureRelease = struct { trait: DeclId, member: DeclId };

pub const ClosureDescriptor = struct {
    /// Environment fields initialized by consuming captures, in source order.
    owned_fields: []const FieldOrdinal = &.{},
    environment: TypeId = .unit,
    invocation: node.Convention = .read,
    enclosing: DeclId,
    /// What the closure type's `impl_args` and `self_ty` bind in `enclosing`.
    parameters: BodyParameters = .{},
    expr: ExprId,
    body: ExprId,
    signature: TypeId,
    /// Whether the body changes a name it uses without capturing: assigns
    /// it or lends it to be changed. Such a name needs a capture the closure
    /// owns, since no capture changes the enclosing binding.
    uncaptured_changed: bool = false,
    /// Whether inference found several sources for a result written without
    /// a clause. The body then has no contract to be checked against.
    contract_declined: bool = false,
    /// The parameter whose carrier type supplied the contract of a lambda that
    /// wrote no clause.
    default_carrier: ?u32 = null,
};

/// A call written in the postfix form, and the receiver its source spells.
///
/// `a.of()` is `Measure.of(a)`, and the tree holds the first: the formatter
/// needs the spelling the programmer chose, so nothing rewrites it. Semantic
/// consumers read `NormalizedCall`; this keeps the receiver-first source shape
/// only for tools that map that answer back onto tokens.
///
/// The whole source-shaped list rather than the receiver alone, so a rewrite
/// can preserve every written argument while moving the receiver inside the
/// parentheses.
///
/// The target and parameter-order arguments are semantic facts and live in the
/// call's `NormalizedCall`; this record survives only so source tools can map
/// the receiver back to the spelling before the dot.
pub const Postfix = struct { call: u32, args: []const ExprId };

pub const array_view_name = "as_slice";

/// An array's `length()` reports the count its type holds, so no body runs.
/// Constant folding reads the same name, so a length is one call everywhere.
pub const array_length_name = @import("constfold.zig").array_length_name;

/// The callable body one checked call reaches.
pub const CallTarget = union(enum) {
    closure_recovery,
    array_view,
    array_length,
    declared: DeclId,
    closure: ids.ClosureId,
    indirect: ExprId,
    generic_callable: TypeId,
    /// A call through a `mem.Closure`, whose callee expression is the closure.
    erased: ExprId,

    /// Whether the callee expression is itself an operand of the call, a
    /// value the call reads or takes, rather than a name that selects a
    /// declaration or an operation of the language.
    pub fn calleeIsValue(self: CallTarget) bool {
        return switch (self) {
            .declared, .closure_recovery, .array_view, .array_length => false,
            .closure, .indirect, .generic_callable, .erased => true,
        };
    }
};

test "CallTarget.calleeIsValue" {
    try testing.expect(!(CallTarget{ .declared = DeclId.at(0) }).calleeIsValue());
    try testing.expect(!@as(CallTarget, .array_view).calleeIsValue());
    try testing.expect((CallTarget{ .indirect = ExprId.at(0) }).calleeIsValue());
    try testing.expect((CallTarget{ .erased = ExprId.at(0) }).calleeIsValue());
}

/// Generic and implementation settlement belonging to one call target.
pub const CallSelection = struct {
    own_args: []const TypeId = &.{},
    implementation: ?CallImpl = null,
    impl_args: []const TypeId = &.{},
};

pub const TypeSelection = struct {
    base: TypeId,
    member: TokenId,
    declaration: DeclId = .none,
    /// The declaration whose scope the written type was read in, which is the
    /// scope an editor's lookup through `base` is answered in.
    owner: DeclId = .none,
    /// Whether the member was settled to the definition an implementation
    /// headed by a bare parameter gives it, `I.Iter` as `I`, rather than to a
    /// stand-in awaiting an instantiation.
    head_definition: bool = false,
};

pub const FieldOrdinal = enum(u32) {
    _,
    pub fn index(self: FieldOrdinal) u32 {
        return @intFromEnum(self);
    }
};

pub const FieldIdentity = struct {
    receiver: TypeId,
    field: FieldOrdinal,
};

pub const PlaceProjection = struct {
    base: ExprId,
    observations: u32,
    receiver: TypeId,
    field: ?FieldOrdinal = null,
};

pub const ReceiverAdjustment = struct {
    observations: u32,
    receiver: TypeId,
    selection: enum { static, implementation } = .static,
};

/// One complete checked call, including parameter-order arguments.
pub const NormalizedCall = struct {
    callee_convention: Convention = .read,
    at: ExprId,
    target: CallTarget,
    signature: TypeId,
    args: []const ExprId,
    selection: CallSelection = .{},
    /// Whether the callee was written with brackets naming the call's type
    /// arguments, `parse[UInt16]`, rather than as the name alone.
    written_type_arguments: bool = false,
    /// Checked referent forwarding in parameter order; null leaves the argument unchanged.
    /// Concrete instantiation substitutes the recorded receiver type.
    receiver_adjustments: []const ?ReceiverAdjustment = &.{},

    /// The convention the parameter at `index` receives its argument with.
    /// `types` is the `Typing` or the builder the signature is interned in.
    pub fn argumentConvention(self: NormalizedCall, types: anytype, index: usize) Convention {
        const params = types.callableParams(types.get(self.signature).callable);
        return if (index < params.len) params[index].convention else .read;
    }

    pub fn deinit(self: NormalizedCall, gpa: std.mem.Allocator) void {
        gpa.free(self.args);
        gpa.free(self.receiver_adjustments);
        if (self.selection.own_args.len > 0) gpa.free(self.selection.own_args);
        if (self.selection.impl_args.len > 0) gpa.free(self.selection.impl_args);
        if (self.selection.implementation) |implementation| {
            if (implementation.args.len > 0) gpa.free(implementation.args);
        }
    }
};

/// One written argument of a resolved call that checking rejected.
///
/// A matched argument retains the slot and convention the checker found.
/// Unmatched input has no slot and is read during ownership recovery, which is
/// represented by its `read` convention rather than decided by that pass.
pub const RecoveredCallArg = struct {
    call: ExprId,
    argument: ExprId,
    target: DeclId = .none,
    parameter: ?u32,
    convention: Convention,
};

/// The target of a resolved call that checking rejected.
///
/// Kept apart from the argument rows because a call with no written arguments
/// still has a callee, and evaluating that callee may consume or read values.
pub const RecoveredCall = struct {
    callee_convention: Convention = .read,
    at: ExprId,
    target: CallTarget,
};

/// The concrete body selected for one contextual function value.
pub const FunctionTarget = union(enum) {
    declared: DeclId,
    closure: ids.ClosureId,
    constructor: ConstructorBody,
};

/// Identity among accepted constructor callable sites, independent of AST size.
pub const ConstructorId = enum(u32) { _ };

/// A qualified constructor's generated body, specialized in its source context.
pub const ConstructorBody = struct {
    id: ConstructorId,
    expr: ExprId,
    enclosing: DeclId,
    ordinal: VariantOrdinal,
};

/// A function named as a value of one exact structural callable signature.
/// The callable type a function value was received by, and whether that
/// type is written in the library, where the program cannot change it.
pub const FixedFunction = struct { signature: TypeId, in_library: bool };

pub const FunctionValue = struct {
    at: ExprId,
    target: FunctionTarget,
    signature: TypeId,
    /// For a closure target, the closure's own type, whose arguments key the
    /// instance the value holds; `signature` is the callable it converts to.
    closure_type: TypeId = .poison,
    type_args: []const TypeId = &.{},
    /// The head the value's body is found through, recorded as a call to the
    /// same declaration records it: the receiver a member of a generic
    /// inherent implementation was selected for, or the trait and `Self` a
    /// trait's operation was settled at. Null for a target that names its
    /// body outright.
    implementation: ?CallImpl = null,

    pub fn deinit(self: FunctionValue, gpa: std.mem.Allocator) void {
        if (self.type_args.len > 0) gpa.free(self.type_args);
        if (self.implementation) |implementation| {
            if (implementation.args.len > 0) gpa.free(implementation.args);
        }
    }
};

/// One written argument name and the parameter slot it filled.
///
/// A name written in a call is a reference to a parameter, the way a callee is
/// a reference to a function: renaming the parameter has to rewrite it, and a
/// reader asking where a parameter is written has to be shown it. The matcher
/// is the one place that pairs a name with a parameter, so the pairing it made
/// is recorded here and every consumer reads it. Matching spellings again would
/// be a second matcher, and it would disagree wherever two parameters of two
/// declarations share a name -- which is nearly always.
///
/// `param` is the declaring token where the callable body is source-visible.
/// An indirect structural call has no body token at the call, so `call` and
/// `slot` retain the normalised relation for tooling to follow through the
/// callee binding and its recorded contextual conversion.
///
/// One row per written name, so the table is sized by the arguments that name
/// something and not by the program: a call written positionally records
/// nothing.
pub const Named = struct {
    name: TokenId,
    param: TokenId,
    call: ExprId,
    slot: u32,
};

/// One implementation, by the trait it is of and the type it is for.
///
/// The pair coherence makes unique, computed once from the declarations and
/// read wherever an implementation is wanted -- discharging a bound before
/// instantiation, and finding a body after it. Recomputing it per lookup meant
/// resolving every `impl`'s trait and head type at every bound and every call.
///
/// One row per `impl` the program writes, whether or not it names a trait. An
/// inherent `impl` names a head the same way, and `Self` inside it and the
/// parameters that head applies are read off the head -- so leaving it out left
/// the head of an inherent `impl` with no answer at all, and a second reader
/// working it out beside this one is two answers to which head encloses a
/// declaration.
pub const Implementation = struct {
    array_element_member: DeclId = .none,
    /// The trait's declaration, not its spelling: two modules may each declare
    /// a `Measure`, and an implementation of one is not one of the other.
    /// `no_trait` for an inherent `impl`, which names none.
    trait: u32,
    /// What the implementation supplied for the trait's parameters. Part of
    /// the key: `TryFrom[Int64] for UInt8` and `TryFrom[UInt8] for UInt8` are two
    /// implementations of one trait for one type, and neither is the other.
    args: []const TypeId = &.{},
    /// What the head names, which is what every type this implementation could
    /// answer for reaches it by.
    head: Head,
    /// What the head applies, position by position, which is what tells the
    /// members of the family this implementation answers for from the rest.
    /// Empty for a head applying nothing, which is the whole of its own family.
    valid_key: bool = true,
    /// Projected requirements checked after the receiver binds the head.
    predicates: []const Predicate = &.{},
    ty: TypeId,
    /// The declaration this row was written by, or `.none` where the compiler
    /// provides it.
    decl: DeclId,
    /// Whether this ordinary row came from a source derive request.
    derived: bool = false,
    /// Whether the compiler provides it rather than a source declaring it.
    ambient: bool = false,
    /// Is true when this row the compiler provides for arrays answers through
    /// the array's `Slice` view: it applies where the view's implementation
    /// does, and a selection of it runs the view's members.
    viewed: bool = false,
    /// How many parameters the implementation declares of its own, which is
    /// what a receiver binds and what its trait's arguments are substituted
    /// through. Not the head's arity: a head naming fewer than the
    /// implementation declares is a program that is reported and still walked.
    parameters: u32 = 0,

    /// What `trait` holds for an inherent `impl`. No declaration has this
    /// index, so a lookup for a trait the program declares passes such a row
    /// over without a test of its own.
    pub const no_trait: u32 = std.math.maxInt(u32);

    /// What `decl` holds for an implementation the compiler provides. A
    /// primitive's comparison has no Linea body -- one written with `<` would
    /// be `Comparable.less` calling itself -- and a marker has no members at
    /// all, so there is no declaration for either to name.
    ///
    /// Whether the compiler provides this implementation rather than a source
    /// declaring it. Lowering answers such a row with an instruction, so it
    /// must tell one from a written implementation it would emit a call to.
    ///
    /// A field rather than a declaration that does not exist. This was a number
    /// one below `DeclId.none`, which was honest while `decl` was a number and
    /// became a lie when it became a `DeclId`: a value the type says names a
    /// declaration, standing for there being none, and admitted anywhere a real
    /// one is. `resolve.zig` already carries `ambient: bool` beside a binding
    /// for the same fact.
    pub fn isAmbient(self: Implementation) bool {
        return self.ambient;
    }

    /// Whether this implementation answers a trait, rather than naming a head
    /// alone.
    pub fn ofATrait(self: Implementation) bool {
        return self.trait != no_trait;
    }
};

/// Each implementation binder has one injective position in its complete key.
/// Admission and argument-height transfer read the same positions.
pub const ImplementationParameters = struct {
    origins: []?Origin,
    steps: std.ArrayList(Step) = .empty,

    pub const Root = union(enum) { receiver, argument: u32 };
    pub const Step = union(enum) {
        argument: struct { head: Head, index: u32 },
        borrow_,
        array,
        callable_parameter: u32,
        callable_result,

        /// Extract a typed structural child without deciding applicability.
        pub fn child(self: Step, pool: anytype, ty: TypeId) ?TypeId {
            return switch (self) {
                .argument => |position| if (pool.instanceOf(ty)) |instance| blk: {
                    if (!pool.headOf(ty).same(position.head)) break :blk null;
                    const args = pool.argsOf(instance);
                    break :blk if (position.index < args.len) args[position.index] else null;
                } else null,
                .borrow_ => if (pool.get(ty) == .borrow) pool.get(ty).borrow.referent else null,
                .array => if (pool.get(ty) == .array) pool.get(ty).array.element else null,
                .callable_parameter => |index| if (pool.get(ty) == .callable) blk: {
                    const params = pool.callableParams(pool.get(ty).callable);
                    break :blk if (index < params.len) params[index].ty else null;
                } else null,
                .callable_result => if (pool.get(ty) == .callable) pool.get(ty).callable.result else null,
            };
        }
    };
    pub const Origin = struct { root: Root, first: u32, count: u32 };

    pub fn deinit(self: *ImplementationParameters, gpa: std.mem.Allocator) void {
        gpa.free(self.origins);
        self.steps.deinit(gpa);
    }

    pub fn path(self: *const ImplementationParameters, origin: Origin) []const Step {
        return self.steps.items[origin.first..][0..origin.count];
    }

    pub fn init(gpa: std.mem.Allocator, pool: anytype, implementation: Implementation) std.mem.Allocator.Error!ImplementationParameters {
        var result: ImplementationParameters = .{ .origins = try gpa.alloc(?Origin, implementation.parameters) };
        errdefer result.deinit(gpa);
        @memset(result.origins, null);
        var walk: Walker(@TypeOf(pool)) = .{ .gpa = gpa, .pool = pool, .owner = implementation.decl.index(), .result = &result };
        defer walk.seen.deinit(gpa);
        defer walk.path.deinit(gpa);
        try walk.visit(implementation.ty, .receiver);
        for (implementation.args, 0..) |argument, index| try walk.visit(argument, .{ .argument = @intCast(index) });
        return result;
    }

    fn Walker(comptime Pool: type) type {
        return struct {
            gpa: std.mem.Allocator,
            pool: Pool,
            owner: u32,
            result: *ImplementationParameters,
            path: std.ArrayList(Step) = .empty,
            seen: std.AutoHashMapUnmanaged(TypeId, void) = .empty,

            fn child(self: *@This(), ty: TypeId, root: Root, step: Step) std.mem.Allocator.Error!void {
                try self.path.append(self.gpa, step);
                defer _ = self.path.pop();
                try self.visit(ty, root);
            }

            fn visit(self: *@This(), ty: TypeId, root: Root) std.mem.Allocator.Error!void {
                if (self.pool.standinOf(ty) != null) return;
                const seen = try self.seen.getOrPut(self.gpa, ty);
                if (seen.found_existing) return;
                if (self.pool.get(ty) == .parameter) {
                    const parameter = self.pool.get(ty).parameter;
                    if (parameter.owner != self.owner or parameter.index >= self.result.origins.len) return;
                    const first = std.math.cast(u32, self.result.steps.items.len) orelse return error.OutOfMemory;
                    const count = std.math.cast(u32, self.path.items.len) orelse return error.OutOfMemory;
                    try self.result.steps.appendSlice(self.gpa, self.path.items);
                    self.result.origins[parameter.index] = .{ .root = root, .first = first, .count = count };
                    return;
                }
                if (self.pool.instanceOf(ty)) |instance| {
                    for (self.pool.argsOf(instance), 0..) |argument, index| try self.child(argument, root, .{ .argument = .{ .head = self.pool.headOf(ty), .index = @intCast(index) } });
                    return;
                }
                switch (self.pool.get(ty)) {
                    .borrow => |observation| try self.child(observation.referent, root, .borrow_),
                    .array => |array| try self.child(array.element, root, .array),
                    .callable => |signature| {
                        for (self.pool.callableParams(signature), 0..) |parameter, index| try self.child(parameter.ty, root, .{ .callable_parameter = @intCast(index) });
                        try self.child(signature.result, root, .callable_result);
                    },
                    else => {},
                }
            }
        };
    }
};

/// One interpolation substitution minted, and where its pieces sit.
///
/// Beside the pool rather than in it, for the reason an instantiation's
/// arguments are: what identifies the type is the run of pieces, and a pool
/// entry holds a name.
pub const Interpolated = struct {
    ty: TypeId,
    first_piece: u32,
    piece_count: u32,
    first_format: u32,
    format_count: u32,
};

const not_an_interpolation = std.math.maxInt(u32);

/// A trait a bound admits, and the arguments it was written with.
///
/// Read together because a bound admits exactly the trait at those arguments:
/// `Lookup[UInt64]` is discharged by an implementation at `UInt64`, and not by
/// one at anything else. A trait admitted because another one requires it
/// carries the arguments that requirement was written at, settled by whatever
/// the bound reaching it supplied -- `trait Fancy: Lookup[UInt64]` admits
/// `Lookup` at `UInt64`, so a body bounded on `Fancy` may hand its parameter
/// to one bounded `Lookup[UInt64]` and to nothing else.
pub const BoundTrait = struct {
    trait: u32,
    args: []const TypeId = &.{},
    /// The bound as it was written, kept so a reader holding one written bound
    /// finds the entry that bound made rather than the first entry naming its
    /// trait. A parameter may carry the same trait at several arguments, so
    /// the trait alone does not pick an entry out.
    written: TraitBound = .{},
};

/// Frees a run of admitted traits and the arguments each one owns.
///
/// One routine for every place a list of these is freed, so an entry's own
/// allocation is never the one a caller forgot: `owned_bounds` and
/// `declared_traits` both hold lists of these and both free them on every
/// path that ends without handing them to a `Typing`, and so does a caller
/// that read `traitsBounding` for a question with no `Typing` to store the
/// answer in.
pub fn freeBoundTraits(gpa: std.mem.Allocator, traits: []const BoundTrait) void {
    for (traits) |t| if (t.args.len > 0) gpa.free(t.args);
    if (traits.len > 0) gpa.free(traits);
}

/// What an implementation's parameter demands of whatever binds it.
///
/// The bounds written on it, read once where the declarations are: a trait is
/// its declaration rather than its spelling, and the capability is what the same
/// routine every other bound list is read through says it is.
pub const Demand = struct {
    /// The traits an implementation exists for, by declaration, and the
    /// arguments each was written with.
    traits: []const BoundTrait = &.{},
    /// The exact structural callable signatures the argument must carry.
    callables: []const TypeId = &.{},
    /// The capability the bounds demand. `Linear` imposes no restriction.
    requirement: CapabilityRequirement = .unrestricted,
    integer: bool = false,
    /// Whether the argument must carry no dependency.
    owned: bool = false,
};

/// A demand a bound refusal reported unmet: what `ty` was told it lacks.
///
/// A trait is kept with the arguments the bound settled it at, because that
/// is what the refusal said: `Board` refused for `Lookup[Bool]` was told
/// nothing about `Lookup[UInt8]`. A callable bound is the exact signature the
/// type must carry. A bound on `Integer` records nothing: it promises
/// `Equatable`, `Comparable` and copying besides, which its refusal does not
/// name, and an implementation that fails on those is reported.
pub const RefusedDemand = struct {
    ty: TypeId,
    lacks: Lacks,

    pub const Lacks = union(enum) {
        capability: CapabilityRequirement,
        trait: struct { decl: DeclId, args: []const TypeId },
        callable: TypeId,
    };

    /// Hashes and compares a demand by its contents, so a trait demand
    /// matches whatever slice its arguments are read from.
    pub const Context = struct {
        pub fn hash(_: Context, demand: RefusedDemand) u64 {
            var h = std.hash.Wyhash.init(@intFromEnum(demand.ty));
            const tag: u8 = @intFromEnum(std.meta.activeTag(demand.lacks));
            h.update(std.mem.asBytes(&tag));
            switch (demand.lacks) {
                .capability => |requirement| {
                    const value: u8 = @intFromEnum(requirement);
                    h.update(std.mem.asBytes(&value));
                },
                .trait => |trait| {
                    const decl: u32 = @intFromEnum(trait.decl);
                    h.update(std.mem.asBytes(&decl));
                    h.update(std.mem.sliceAsBytes(trait.args));
                },
                .callable => |signature| {
                    const value: u32 = @intFromEnum(signature);
                    h.update(std.mem.asBytes(&value));
                },
            }
            return h.final();
        }

        pub fn eql(_: Context, a: RefusedDemand, b: RefusedDemand) bool {
            if (a.ty != b.ty or std.meta.activeTag(a.lacks) != std.meta.activeTag(b.lacks)) return false;
            return switch (a.lacks) {
                .capability => |requirement| requirement == b.lacks.capability,
                .trait => |trait| trait.decl == b.lacks.trait.decl and std.mem.eql(TypeId, trait.args, b.lacks.trait.args),
                .callable => |signature| signature == b.lacks.callable,
            };
        }
    };
};

test "a refused demand is keyed by its contents" {
    const context: RefusedDemand.Context = .{};
    const held: TypeId = @enumFromInt(7);
    const first = [_]TypeId{ @enumFromInt(1), @enumFromInt(2) };
    const second = [_]TypeId{ @enumFromInt(1), @enumFromInt(2) };
    const other = [_]TypeId{ @enumFromInt(1), @enumFromInt(3) };
    const at_first: RefusedDemand = .{ .ty = held, .lacks = .{ .trait = .{ .decl = DeclId.at(4), .args = &first } } };
    const at_second: RefusedDemand = .{ .ty = held, .lacks = .{ .trait = .{ .decl = DeclId.at(4), .args = &second } } };
    const at_other: RefusedDemand = .{ .ty = held, .lacks = .{ .trait = .{ .decl = DeclId.at(4), .args = &other } } };
    try testing.expect(context.eql(at_first, at_second));
    try testing.expectEqual(context.hash(at_first), context.hash(at_second));
    try testing.expect(!context.eql(at_first, at_other));
    try testing.expect(!context.eql(at_first, .{ .ty = held, .lacks = .{ .trait = .{ .decl = DeclId.at(5), .args = &first } } }));

    const copyable: RefusedDemand = .{ .ty = held, .lacks = .{ .capability = .copyable } };
    try testing.expect(context.eql(copyable, .{ .ty = held, .lacks = .{ .capability = .copyable } }));
    try testing.expect(!context.eql(copyable, .{ .ty = held, .lacks = .{ .capability = .discardable } }));
    try testing.expect(!context.eql(copyable, .{ .ty = @enumFromInt(8), .lacks = .{ .capability = .copyable } }));
    try testing.expect(!context.eql(copyable, .{ .ty = held, .lacks = .{ .callable = @enumFromInt(9) } }));
    try testing.expect(context.eql(.{ .ty = held, .lacks = .{ .callable = @enumFromInt(9) } }, .{ .ty = held, .lacks = .{ .callable = @enumFromInt(9) } }));
}

/// The demands the bound refusals of one check reported, keyed by contents.
pub const RefusedDemands = std.HashMapUnmanaged(RefusedDemand, void, RefusedDemand.Context, std.hash_map.default_max_load_percentage);

/// Records a trait requirement that an implementation writes and a receiver's
/// arguments fail: `Labelled[T]` requires `T: Equatable`, and `Token` does not.
pub const UnmetRequirement = struct {
    /// Holds the implementation's head, written in its own parameters.
    head: TypeId,
    /// Holds the requirement's subject, written in the implementation's parameters.
    subject: TypeId,
    /// Holds the subject after the receiver's arguments are substituted.
    argument: TypeId,
    trait: DeclId,
    args: []const TypeId,
    /// Set where the unmet requirement is a capability the subject lacks
    /// rather than a trait, in which case `trait` is none.
    capability: ?CapabilityRequirement = null,
};

/// One non-parameter implementation constraint and what its subject must meet.
pub const Predicate = struct {
    subject: TypeId,
    demand: Demand,
};

/// What an implementation is found by.
///
/// A head applied to arguments stands for a family, and no one type is it:
/// `Option[Str]` and `Option[Key]` are two types naming one constructor. So the
/// declaration is what both sides of the lookup agree on, and a type that
/// applies nothing is its own head because it is the whole of the family it
/// belongs to.
pub const Head = union(enum) {
    /// A receiver parameter binds any type admitted by the implementation's
    /// predicates. Its remaining parameters bind from the trait arguments.
    parameter,
    default_,
    /// The declaration a head applies arguments to. Every type that could
    /// answer to it is an instantiation of that declaration, so all of them
    /// reach one chain.
    applied: DeclId,
    /// A head that applies no arguments: a builtin, or a declaration taking
    /// none. It answers for that one type.
    whole: TypeId,
    /// The array constructor, which is a family the way a declaration applying
    /// arguments is: `[UInt8; 3]` and `[Key; 9]` are two types naming it, and
    /// no interned type is the family itself. No declaration names it -- an
    /// array is written as a form and not as a name -- so it is its own head
    /// rather than a `.applied` over one.
    array,
    borrow_,
    /// A callable type is a family of its shape: every function and closure
    /// value whose invocation and parameter conventions are these reaches one
    /// chain, and which of them an implementation answers for is decided by
    /// matching the written signature against the type.
    callable_: node.CallableShape,

    /// Whether two heads name the same thing. A declaration and a type are two
    /// spaces of `u32`, so the tag is part of the answer.
    pub fn same(self: Head, other: Head) bool {
        return switch (self) {
            .applied => |d| other == .applied and other.applied == d,
            .whole => |t| other == .whole and other.whole == t,
            .array => other == .array,
            .borrow_ => other == .borrow_,
            .callable_ => |shape| other == .callable_ and other.callable_ == shape,
            .parameter => other == .parameter,
            .default_ => other == .default_,
        };
    }
};

const TypeArgumentsContext = struct {
    pub fn hash(_: TypeArgumentsContext, args: []const TypeId) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(args));
    }
    pub fn eql(_: TypeArgumentsContext, a: []const TypeId, b: []const TypeId) bool {
        return std.mem.eql(TypeId, a, b);
    }
};

const ReceiverImplementationKey = struct { implementation: ImplementationId, receiver: TypeId };

const ReceiverImplementation = union(enum) {
    absent,
    /// The receiver matches, but trait arguments must settle remaining parameters.
    open,
    settled: []const TypeId,
};

const PreparedImplementationKey = struct {
    scope: DeclId,
    receiver: TypeId,
    implementation: ImplementationId,
    args: []const TypeId,

    const Context = struct {
        pub fn hash(_: Context, key_: PreparedImplementationKey) u64 {
            var h = std.hash.Wyhash.init(@intFromEnum(key_.scope));
            h.update(std.mem.asBytes(&key_.receiver));
            h.update(std.mem.asBytes(&key_.implementation));
            h.update(std.mem.sliceAsBytes(key_.args));
            return h.final();
        }
        pub fn eql(_: Context, a: PreparedImplementationKey, b: PreparedImplementationKey) bool {
            return a.scope == b.scope and a.receiver == b.receiver and a.implementation == b.implementation and std.mem.eql(TypeId, a.args, b.args);
        }
    };
};

/// Full-key applicability retains declaration-ordered substitutions. Keys and
/// successful argument vectors are owned until the semantic table is cleared.
const ImplementationCandidate = struct {
    header_matches: bool = false,
    arguments: ?[]const TypeId = null,
};

/// An operation asked about for a receiver type, in one function's scope.
const SettlingResultKey = struct { owner: DeclId, receiver: TypeId, operation: DeclId };

const PreparedImplementations = struct {
    argument_arena: ?std.heap.ArenaAllocator = null,
    arguments: std.HashMapUnmanaged([]const TypeId, void, TypeArgumentsContext, std.hash_map.default_max_load_percentage) = .empty,
    answers: std.HashMapUnmanaged(PreparedImplementationKey, ImplementationCandidate, PreparedImplementationKey.Context, std.hash_map.default_max_load_percentage) = .empty,
    roots: std.AutoHashMapUnmanaged(ScopedCapabilityKey, void) = .empty,
    /// Receivers whose own head's rows are prepared, where `roots` also holds
    /// those prepared through every blanket and default row besides.
    head_roots: std.AutoHashMapUnmanaged(ScopedCapabilityKey, void) = .empty,
    receiver_args: std.AutoHashMapUnmanaged(ReceiverImplementationKey, ReceiverImplementation) = .empty,
    /// Whether an operation's result still owes, for a receiver type in a
    /// function's scope, with the receiver's block arguments substituted.
    settling_results: std.AutoHashMapUnmanaged(SettlingResultKey, bool) = .empty,

    fn deinit(self: *PreparedImplementations, gpa: std.mem.Allocator) void {
        self.clear();
        self.answers.deinit(gpa);
        self.roots.deinit(gpa);
        self.head_roots.deinit(gpa);
        self.receiver_args.deinit(gpa);
        self.settling_results.deinit(gpa);
        self.arguments.deinit(gpa);
        if (self.argument_arena) |*arena| arena.deinit();
        self.* = .{};
    }

    fn clear(self: *PreparedImplementations) void {
        self.answers.clearRetainingCapacity();
        self.roots.clearRetainingCapacity();
        self.head_roots.clearRetainingCapacity();
        self.receiver_args.clearRetainingCapacity();
        self.settling_results.clearRetainingCapacity();
    }

    fn retainArguments(self: *PreparedImplementations, gpa: std.mem.Allocator, args: []const TypeId) ![]const TypeId {
        if (self.arguments.getKey(args)) |retained| return retained;
        if (self.argument_arena == null) self.argument_arena = std.heap.ArenaAllocator.init(gpa);
        const retained = try self.argument_arena.?.allocator().dupe(TypeId, args);
        try self.arguments.put(gpa, retained, {});
        return retained;
    }

    fn record(self: *PreparedImplementations, gpa: std.mem.Allocator, key_: PreparedImplementationKey, candidate: ImplementationCandidate) !ImplementationCandidate {
        const key_args = try self.retainArguments(gpa, key_.args);
        const selected: ImplementationCandidate = .{
            .header_matches = candidate.header_matches,
            .arguments = if (candidate.arguments) |values| try self.retainArguments(gpa, values) else null,
        };
        var owned_key = key_;
        owned_key.args = key_args;
        try self.answers.put(gpa, owned_key, selected);
        return selected;
    }

    fn clone(self: *const PreparedImplementations, gpa: std.mem.Allocator) !PreparedImplementations {
        var result: PreparedImplementations = .{};
        errdefer result.deinit(gpa);
        var it = self.answers.iterator();
        while (it.next()) |entry| _ = try result.record(gpa, entry.key_ptr.*, entry.value_ptr.*);
        result.roots = try self.roots.clone(gpa);
        result.head_roots = try self.head_roots.clone(gpa);
        var receivers = self.receiver_args.iterator();
        while (receivers.next()) |entry| {
            const args: ReceiverImplementation = switch (entry.value_ptr.*) {
                .settled => |values| .{ .settled = try result.retainArguments(gpa, values) },
                else => entry.value_ptr.*,
            };
            try result.receiver_args.put(gpa, entry.key_ptr.*, args);
        }
        result.settling_results = try self.settling_results.clone(gpa);
        return result;
    }
};

/// Which implementation answers each trait and type.
///
/// Finding one walked every implementation the program declares, once per call
/// that goes through a trait, so a module of many `impl` blocks paid the
/// product. The chain covers the same list and is walked in the same order, so
/// the implementation it stops at is the one the walk stopped at.
///
/// Keyed by the trait and the head but not by the arguments, because the
/// arguments are part of the answer rather than of the question: `TryFrom[Int64]
/// for UInt8` and `TryFrom[UInt8] for UInt8` share a key and are told apart on
/// the chain, which coherence keeps short.
///
/// By the head rather than by the type, because an implementation whose head
/// applies arguments answers for a family and no interned type is that family.
/// Every member of it names one declaration, so the declaration is what puts
/// them all on one chain -- and which members the implementation answers for is
/// then decided by walking that chain, which is where a question about one
/// implementation belongs.
///
/// Every lookup receives the row order and trait/head keys used by `build`.
/// The checker installs and transfers the list and index together; pool views
/// borrow both. An unbuilt index is paired only with an empty list.
pub const ImplIndex = struct {
    by_head: Chain(.newest_first) = .empty,
    by_trait: Chain(.newest_first) = .empty,
    chained: Chain(.newest_first) = .empty,

    /// Hashed, and verified by every walk: a head is a declaration or a type,
    /// two spaces of `u32` that do not both fit beside a trait in one word. A
    /// collision therefore lengthens a chain and never answers.
    fn key(trait: u32, head: Head) u64 {
        var h: std.hash.Wyhash = .init(trait);
        switch (head) {
            .applied => |d| {
                h.update("applied");
                h.update(std.mem.asBytes(&d));
            },
            .whole => |t| {
                const id: u32 = @intFromEnum(t);
                h.update("whole");
                h.update(std.mem.asBytes(&id));
            },
            .array => h.update("array"),
            .borrow_ => h.update("borrow"),
            .callable_ => |shape| {
                h.update("callable");
                h.update(std.mem.asBytes(&shape));
            },
            .parameter => h.update("parameter"),
            .default_ => h.update("default"),
        }
        return h.final();
    }

    pub fn build(gpa: std.mem.Allocator, impls: []const Implementation) !ImplIndex {
        var chained: Chain(.newest_first) = .empty;
        errdefer chained.deinit(gpa);

        var by_head: Chain(.newest_first) = .empty;
        errdefer by_head.deinit(gpa);
        var by_trait: Chain(.newest_first) = .empty;
        errdefer by_trait.deinit(gpa);

        // Backwards, so the entry left at the head of each chain is the first
        // one recorded and a walk of the chain runs in the order of the list.
        var at: usize = impls.len;
        while (at > 0) {
            at -= 1;
            try chained.note(gpa, key(impls[at].trait, impls[at].head), @intCast(at));
            try by_head.note(gpa, key(0, impls[at].head), @intCast(at));
            try by_trait.note(gpa, impls[at].trait, @intCast(at));
        }

        return .{ .chained = chained, .by_head = by_head, .by_trait = by_trait };
    }

    pub fn deinit(self: *ImplIndex, gpa: std.mem.Allocator) void {
        self.chained.deinit(gpa);
        self.by_head.deinit(gpa);
        self.by_trait.deinit(gpa);
    }

    /// Every implementation this index holds under `trait` and `head`,
    /// however many hashed to the same chain -- a caller walking this re-
    /// verifies each candidate against `trait` and `head` itself, the same
    /// way `answersFor` does, so a collision lengthens the walk and never
    /// answers wrongly.
    ///
    /// Exposed rather than `key` itself: a caller outside this index asks for
    /// a chain's members, never for the hash that finds one, and the second
    /// would let two readers of the same key disagree about how it is made.
    pub fn membersOf(self: *const ImplIndex, trait: u32, head: Head) Chain(.newest_first).Walk {
        return self.chained.walk(key(trait, head));
    }

    /// Structural candidates only: callers decide complete-key matching,
    /// predicates, and whether ordinary headers reserve a default's receiver.
    ///
    /// A parameter head binds any type its predicates admit, so it is searched
    /// beside the receiver's own head rather than gated on the receiver.
    pub fn candidates(self: *const ImplIndex, impls: []const Implementation, trait: u32, head: Head, defaults: bool) CandidateIterator {
        var heads: [3]Head = undefined;
        heads[0] = head;
        var count: u8 = 1;
        if (head != .parameter) {
            heads[count] = .parameter;
            count += 1;
        }
        if (defaults and head != .default_) {
            heads[count] = .default_;
            count += 1;
        }
        return .{ .index = self, .impls = impls, .trait = trait, .heads = heads, .count = count, .run = self.membersOf(trait, heads[0]) };
    }

    pub const CandidateIterator = struct {
        index: *const ImplIndex,
        impls: []const Implementation,
        trait: u32,
        heads: [3]Head,
        count: u8,
        at: u8 = 0,
        run: Chain(.newest_first).Walk,

        pub fn next(self: *CandidateIterator) ?u32 {
            while (self.at < self.count) {
                while (self.run.next()) |row_index| {
                    const row = self.impls[row_index];
                    if (row.trait == self.trait and row.head.same(self.heads[self.at]) and row.valid_key) return row_index;
                }
                self.at += 1;
                if (self.at < self.count) self.run = self.index.membersOf(self.trait, self.heads[self.at]);
            }
            return null;
        }
    };

    pub fn membersOfTrait(self: *const ImplIndex, trait: u32) Chain(.newest_first).Walk {
        return self.by_trait.walk(trait);
    }

    /// Every implementation recorded under `head`, of any trait and of none, in
    /// the order of the list. A caller re-verifies each row's head itself, the
    /// way `candidates` does, so a collision lengthens the walk and never
    /// answers.
    ///
    /// **Bound:** the rows whose head hashes to this one, which is what one
    /// type's family implements and nothing about the rest of the program.
    pub fn membersOfHead(self: *const ImplIndex, head: Head) Chain(.newest_first).Walk {
        return self.by_head.walk(key(0, head));
    }

    test "the rows under a head are every implementation for it, in order" {
        const gpa = testing.allocator;
        const door: TypeId = @enumFromInt(40);
        const wall: TypeId = @enumFromInt(41);
        const implementations = [_]Implementation{
            .{ .trait = 7, .head = .{ .whole = door }, .ty = door, .decl = .at(1) },
            .{ .trait = 8, .head = .{ .whole = wall }, .ty = wall, .decl = .at(2) },
            .{ .trait = Implementation.no_trait, .head = .{ .whole = door }, .ty = door, .decl = .at(3) },
            .{ .trait = 9, .head = .{ .whole = door }, .ty = door, .decl = .at(4) },
        };
        var index = try ImplIndex.build(gpa, &implementations);
        defer index.deinit(gpa);

        var seen: std.ArrayList(u32) = .empty;
        defer seen.deinit(gpa);
        var rows = index.membersOfHead(.{ .whole = door });
        while (rows.next()) |at| {
            if (implementations[at].head.same(.{ .whole = door })) try seen.append(gpa, at);
        }
        try testing.expectEqualSlices(u32, &.{ 0, 2, 3 }, seen.items);
    }

    /// Member discovery may defer a trait-key parameter to the call's arguments
    /// or result context. This is not evidence that a trait bound is satisfied.
    ///
    /// Both a parameter head and the receiver's own head can leave one open:
    /// `impl[P] Watch[P] for Tally` covers `Tally` at every `P`, so the receiver
    /// fixes the implementation and the call fixes `P`, as a qualified call
    /// `Watch.observe(&tally, event)` does.
    ///
    /// **Bound:** the rows under the receiver's head and the parameter-headed
    /// rows of the one trait.
    pub fn hasOpenReceiver(self: *const ImplIndex, pool: anytype, impls: []const Implementation, trait: u32, held: TypeId, scope: DeclId) !bool {
        var rows = self.candidates(impls, trait, pool.headOf(held), false);
        while (rows.next()) |at| {
            const row = impls[at];
            if (!receiverDomainAdmits(pool, scope, row, held)) continue;
            if (try pool.receiverImplementation(@enumFromInt(at), held) == .open) return true;
        }
        return false;
    }

    fn receiverDomainAdmits(pool: anytype, scope: DeclId, im: Implementation, held: TypeId) bool {
        return im.head != .parameter or !pool.isIntegerWithin(im.decl, im.ty) or pool.isIntegerWithin(scope, held);
    }

    /// What one lookup has already decided about a trait and a type.
    ///
    /// A head position holding one of the implementation's own parameters
    /// discharges that parameter's bounds by asking this index again, about
    /// whatever the receiver applied there. So a parameter carrying `k` bounds
    /// asks `k` questions one level down, each of which asks `k` more: a
    /// receiver `d` levels deep costs `k^d` questions about `d` distinct types,
    /// which is a program the language permits that no machine finishes.
    ///
    /// The trait and the type together are the whole of the question, so they
    /// are the key and each pair is decided once. Made by the lookup that needs
    /// it and freed when that returns: it records what the implementations and
    /// the pool say, and both move while the pass runs.
    const Decided = struct {
        gpa: std.mem.Allocator,
        scope: DeclId = .none,
        seen: std.AutoHashMapUnmanaged(u64, bool) = .empty,
        active: std.HashMapUnmanaged(PreparedImplementationKey, bool, PreparedImplementationKey.Context, std.hash_map.default_max_load_percentage) = .empty,
        prerequisite_sizes: std.AutoHashMapUnmanaged(ImplementationId, u128) = .empty,
        measure_seen: std.AutoHashMapUnmanaged(TypeId, void) = .empty,
        measure_sizes: std.AutoHashMapUnmanaged(TypeId, u32) = .empty,
        recursive_refusals: usize = 0,
        /// Holds the keys still being decided that a cycle reached back to,
        /// whether it was assumed or refused. An answer is recorded only once
        /// none it rests on is open.
        assumed: std.ArrayList(PreparedImplementationKey) = .empty,
        /// Holds the keys being decided, outermost first, each marked with
        /// whether it is a derived implementation.
        frames: std.ArrayList(Frame) = .empty,
        measure_work: std.ArrayList(TypeId) = .empty,
        /// Demands this lookup takes as met although the type fails them:
        /// the ones a bound refusal already reported. Set only by a lookup
        /// asking whether a missing implementation follows from those
        /// refusals, and such a lookup records no answer, since its answers
        /// hold only under the grants.
        granted: ?*const RefusedDemands = null,

        /// Whether `demand` is one this lookup takes as met.
        fn grants(self: *const Decided, demand: RefusedDemand) bool {
            const granted = self.granted orelse return false;
            return granted.contains(demand);
        }

        /// Sum each key root's distinct type nodes. Shared subterms count once
        /// per root, so an unchanged trait argument cannot hide receiver shrink.
        /// Type IDs are u32 and a slice has at most usize roots; u128 holds the
        /// sum without expanding shared DAGs or overflowing either domain.
        fn keySize(self: *Decided, pool: anytype, held: TypeId, args: []const TypeId) !u128 {
            var total: u128 = try self.rootSize(pool, held);
            for (args) |arg| total += try self.rootSize(pool, arg);
            return total;
        }

        fn rootSize(self: *Decided, pool: anytype, root: TypeId) !u32 {
            if (self.measure_sizes.get(root)) |size| return size;
            self.measure_seen.clearRetainingCapacity();
            self.measure_work.clearRetainingCapacity();
            try self.measure_work.append(self.gpa, root);
            while (self.measure_work.pop()) |ty| {
                const entry = try self.measure_seen.getOrPut(self.gpa, ty);
                if (entry.found_existing) continue;
                try self.measure_work.appendSlice(self.gpa, pool.appliedTo(ty));
                switch (pool.get(ty)) {
                    .borrow => |value| try self.measure_work.append(self.gpa, value.referent),
                    .array => |value| try self.measure_work.append(self.gpa, value.element),
                    .callable => |value| {
                        try self.measure_work.append(self.gpa, value.result);
                        for (pool.callableParams(value)) |parameter| try self.measure_work.append(self.gpa, parameter.ty);
                    },
                    else => {},
                }
            }
            const size = self.measure_seen.count();
            try self.measure_sizes.put(self.gpa, root, size);
            return size;
        }

        /// A trait is a declaration and a type is an interned index, two
        /// spaces of `u32` that sit side by side in one word.
        fn about(trait: u32, held: TypeId) u64 {
            return (@as(u64, trait) << 32) | @intFromEnum(held);
        }

        const Frame = struct {
            key: PreparedImplementationKey,
            derived: bool,
        };

        /// Says whether the cycle closing at `closing` passes through a derived
        /// implementation, that is, whether some frame from `closing`'s own to
        /// the innermost is derived.
        ///
        /// **Bound:** the frames of one lookup, which its nesting depth sizes.
        fn cycleIsDerived(self: *const Decided, closing: PreparedImplementationKey) bool {
            var at = self.frames.items.len;
            while (at > 0) {
                at -= 1;
                const frame = self.frames.items[at];
                if (frame.derived) return true;
                if (PreparedImplementationKey.Context.eql(.{}, frame.key, closing)) return false;
            }
            return false;
        }

        fn deinit(self: *Decided) void {
            self.frames.deinit(self.gpa);
            self.assumed.deinit(self.gpa);
            self.seen.deinit(self.gpa);
            self.active.deinit(self.gpa);
            self.prerequisite_sizes.deinit(self.gpa);
            self.measure_seen.deinit(self.gpa);
            self.measure_sizes.deinit(self.gpa);
            self.measure_work.deinit(self.gpa);
        }
    };

    /// Whether `trait` is implemented for `held` at all, whatever the
    /// implementation supplied for the trait's own parameters.
    ///
    /// The question a bound asks, where `find` is the one a call asks: a bound
    /// is discharged by an implementation existing, and a call wants the one
    /// whose arguments match. Both are answered off this index, so neither
    /// walks the list -- which is what the index is for, and asking one of them
    /// with a walk is how a module of many `impl` blocks pays the product twice.
    ///
    /// **Bound:** the implementations of one trait for one head, which coherence
    /// holds to one per set of trait arguments, times the pairs of a trait and a
    /// type the discharge below reaches -- which the table it carries holds to
    /// the traits the program declares times the types nested inside `held`.
    pub fn any(
        self: *const ImplIndex,
        gpa: std.mem.Allocator,
        impls: []const Implementation,
        pool: anytype,
        trait: u32,
        held: TypeId,
        scope: DeclId,
        observations: enum { forward, direct },
    ) std.mem.Allocator.Error!bool {
        var decided: Decided = .{ .gpa = gpa, .scope = scope };
        defer decided.deinit();
        return self.anyOnce(impls, pool, &decided, trait, held, observations == .forward);
    }

    /// Complete applicable keys discoverable from a receiver and its promises.
    /// Argument rows borrow prepared typing, so the receiver's lookups must
    /// have been prepared (`Builder.prepareLookupWithin`); applicability uses
    /// ordinary find. Returns whether an applicable row leaves its trait
    /// arguments open, which is a family of keys no list can hold.
    pub fn keys(self: *const ImplIndex, gpa: std.mem.Allocator, impls: []const Implementation, pool: *const Typing, trait: DeclId, held: TypeId, scope: DeclId, out: *std.ArrayList([]const TypeId)) !bool {
        var bounds: std.ArrayList(BoundTrait) = .empty;
        defer bounds.deinit(gpa);
        try pool.appendBoundsWithin(gpa, scope, held, &bounds);
        for (bounds.items) |bound| {
            if (bound.trait == trait.index()) try appendKey(gpa, out, bound.args);
        }
        var open = false;
        var rows = self.candidates(impls, trait.index(), pool.headOf(held), true);
        while (rows.next()) |at| {
            if (!receiverDomainAdmits(pool, scope, impls[at], held)) continue;
            const args = switch (try pool.receiverImplementation(@enumFromInt(at), held)) {
                .settled => |args| args,
                .open => {
                    open = true;
                    continue;
                },
                else => continue,
            };
            if (try self.find(gpa, impls, pool, trait.index(), args, held, scope) != null) try appendKey(gpa, out, args);
        }
        return open;
    }

    fn appendKey(gpa: std.mem.Allocator, out: *std.ArrayList([]const TypeId), args: []const TypeId) !void {
        for (out.items) |present| if (std.mem.eql(TypeId, present, args)) return;
        try out.append(gpa, args);
    }

    /// The type a lookup answers for `held`: an integer literal's type is read
    /// through what its variable settled on, whether a concrete integer or a
    /// type parameter. A closure's environment keeps the literal's handle
    /// until the check finishes, so this is where its capture is read.
    fn settledHeld(pool: anytype, held: TypeId) TypeId {
        const table = pool.open_types orelse return held;
        return switch (pool.get(held)) {
            .open_integer => |v| table.resolved(v),
            else => held,
        };
    }

    /// The types an integer literal whose type no use has settled may still
    /// become, or null where `held` is not such a literal. A trait holds for
    /// the literal exactly when it holds for every one of them, since it will
    /// be one of them; `selectOnce` answers it that way for both lookups.
    fn openIntegerCandidates(pool: anytype, held: TypeId) ?[]const TypeId {
        return if (pool.get(held) == .open_integer) &TypeId.integers else null;
    }

    /// `any`, against what this lookup has already decided.
    fn anyOnce(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        trait: u32,
        held: TypeId,
        observations: bool,
    ) std.mem.Allocator.Error!bool {
        return self.selectOnce(impls, pool, decided, .any, trait, {}, held, observations);
    }

    /// What a lookup answers with: whether some implementation answers at all,
    /// or the choice that does and the arguments it was asked at.
    const Selection = enum { any, find };

    fn Answer(comptime mode: Selection) type {
        return switch (mode) {
            .any => bool,
            .find => ?ImplementationChoice,
        };
    }

    /// The one ladder both lookups climb, in the order a selection is decided:
    /// the open integer's candidates, an ordinary implementation, a closure's
    /// release, a bound, the observed referent, and the trait's default.
    ///
    /// `.any` asks it of any arguments, answers a bool and remembers what it
    /// decided for the trait and type, which is why a repeated nested
    /// environment is looked at once. `.find` asks it at `args` and answers
    /// the choice. What differs is how each rung's success is spelled, and the
    /// rungs themselves are written once.
    ///
    /// `forward` lets the ladder continue through an observation to the type it
    /// observes; a `.find` always does, and `.any` is told.
    fn selectOnce(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        comptime mode: Selection,
        trait: u32,
        args: if (mode == .find) []const TypeId else void,
        held: TypeId,
        forward: bool,
    ) std.mem.Allocator.Error!Answer(mode) {
        const settled = settledHeld(pool, held);
        if (settled != held) return self.selectOnce(impls, pool, decided, mode, trait, args, settled, forward);
        // A trait holds for an unsettled integer literal exactly when it holds
        // for every type it may become. The choice a `.find` returns is the
        // fallback type's; which implementation runs is selected again once
        // the literal's type is settled.
        if (openIntegerCandidates(pool, held)) |integers| {
            var fallback: Answer(mode) = if (mode == .any) true else null;
            for (integers) |integer| {
                const answer = try self.selectOnce(impls, pool, decided, mode, trait, args, integer, forward);
                switch (mode) {
                    .any => if (!answer) return false,
                    .find => {
                        const choice = answer orelse return null;
                        if (integer == TypeId.literal_default) fallback = choice;
                    },
                }
            }
            return fallback;
        }

        const about = Decided.about(trait, held);
        if (mode == .any) if (decided.seen.get(about)) |already| return already;
        const before = decided.recursive_refusals;
        const assumed_before = decided.assumed.items.len;

        const asked: ?[]const TypeId = if (mode == .find) args else null;
        const default_args: []const TypeId = if (mode == .find) args else &.{};
        // A closure's release takes no trait arguments.
        const takes_none = mode == .any or args.len == 0;

        const answer: Answer(mode) = walked: {
            const ordinary = try self.ordinarySelection(impls, pool, decided, trait, asked, held);
            if (ordinary.choice) |choice| break :walked if (mode == .any) true else choice;
            if (takes_none and try self.closureReleases(impls, pool, decided, trait, held))
                break :walked if (mode == .any) true else .{ .supplier = .closure_release, .receiver = held };
            if (pool.boundsCarryWithin(decided.scope, held, trait, asked))
                break :walked if (mode == .any) true else .{ .supplier = .bound, .receiver = held };
            if (forward) if (pool.observationReferent(DeclId.at(trait), held)) |referent| {
                const through = try self.selectOnce(impls, pool, decided, mode, trait, args, referent, true);
                switch (mode) {
                    .any => if (through) break :walked true,
                    .find => if (through) |found| {
                        var choice = found;
                        choice.observations += 1;
                        break :walked choice;
                    },
                }
            };
            const by_default = try self.defaultSelection(impls, pool, decided, trait, default_args, held, ordinary.blocks_default);
            break :walked if (mode == .any) by_default != null else by_default;
        };

        if (mode == .any and decided.assumed.items.len == assumed_before and
            (answer or decided.recursive_refusals == before))
            try decided.seen.put(decided.gpa, about, answer);
        return answer;
    }

    test "selectOnce answers a bool or a choice from one ladder" {
        const gpa = testing.allocator;
        var builder = try Typing.Builder.init(gpa);
        defer builder.deinit();
        const implementations = [_]Implementation{
            .{ .trait = 1, .args = &.{.u8}, .head = .{ .whole = .u16 }, .ty = .u16, .decl = DeclId.at(1) },
        };
        var index = try ImplIndex.build(gpa, &implementations);
        defer index.deinit(gpa);
        builder.implementations = &implementations;
        builder.impl_index = index;
        var decided: Decided = .{ .gpa = gpa, .scope = .none };
        defer decided.deinit();
        try testing.expect(try index.selectOnce(&implementations, &builder, &decided, .any, 1, {}, .u16, false));
        try testing.expect(!try index.selectOnce(&implementations, &builder, &decided, .any, 1, {}, .u32, false));
        const choice = try index.selectOnce(&implementations, &builder, &decided, .find, 1, &.{.u8}, .u16, true);
        try testing.expect(choice != null);
        try testing.expect(try index.selectOnce(&implementations, &builder, &decided, .find, 1, &.{.u16}, .u16, true) == null);
    }

    /// Release is conditional on consuming capture slots, not their representation.
    /// One shared rule serves trait availability and concrete supplier selection.
    /// Recursive obligations reuse this lookup's memo table, so a repeated nested
    /// environment is checked once per trait/type pair. A structural function
    /// value is a code pointer that owns nothing, so it always releases.
    fn closureReleases(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        trait: u32,
        held: TypeId,
    ) std.mem.Allocator.Error!bool {
        const release = pool.closure_release orelse return false;
        if (release.trait.index() != trait) return false;
        const closure = switch (pool.get(held)) {
            .closure => |closure| closure,
            .callable => return true,
            else => return false,
        };
        const descriptor = pool.closureOf(closure.closure);
        for (descriptor.owned_fields) |field| {
            const ty = pool.fieldType(closure.environment, field.index());
            if (!try self.anyOnce(impls, pool, decided, trait, ty, false)) return false;
        }
        return true;
    }

    /// The implementation of `trait` at `args` for `held`, or null.
    pub fn find(
        self: *const ImplIndex,
        gpa: std.mem.Allocator,
        impls: []const Implementation,
        pool: anytype,
        trait: u32,
        args: []const TypeId,
        held: TypeId,
        scope: DeclId,
    ) std.mem.Allocator.Error!?ImplementationChoice {
        var decided: Decided = .{ .gpa = gpa, .scope = scope };
        defer decided.deinit();

        return self.findOnce(impls, pool, &decided, trait, args, held);
    }

    /// Whether an implementation of `trait` at `args` answers for `held` once
    /// every demand in `granted` is taken as met, by the lookup `find` makes
    /// with the grants consulted wherever a requirement fails. Nothing the
    /// lookup decides is recorded, since it holds only under the grants.
    ///
    /// **Bound:** the candidates `find` walks for the same question, walked
    /// once for every requirement that reaches them: a granted lookup reads
    /// no prepared answer, so a subterm of `held` that several requirements
    /// share is decided once per requirement rather than once, and the cost
    /// is exponential in the depth of such sharing where `find`'s is linear.
    /// Asked only while reporting a missing implementation, and that report
    /// spells `held` at the same cost.
    pub fn appliesGranted(
        self: *const ImplIndex,
        gpa: std.mem.Allocator,
        impls: []const Implementation,
        pool: *Typing.Builder,
        trait: u32,
        args: []const TypeId,
        held: TypeId,
        scope: DeclId,
        granted: *const RefusedDemands,
    ) std.mem.Allocator.Error!bool {
        var decided: Decided = .{ .gpa = gpa, .scope = scope, .granted = granted };
        defer decided.deinit();
        return try self.findOnce(impls, pool, &decided, trait, args, held) != null;
    }

    test "a granted lookup accepts an implementation that fails only on what was granted" {
        const gpa = testing.allocator;
        var builder = try Typing.Builder.init(gpa);
        defer builder.deinit();
        const ticket = try builder.addStruct("Ticket", .linear, &.{});
        const lookup: u32 = 2;
        // `Ticket` is linear and implements no `Lookup`, so the implementation
        // fails its capability requirement and its trait requirement at `UInt8`.
        const implementations = [_]Implementation{.{
            .trait = 1,
            .head = .{ .whole = ticket },
            .ty = ticket,
            .decl = DeclId.at(1),
            .predicates = &.{.{ .subject = ticket, .demand = .{
                .requirement = .copyable,
                .traits = &.{.{ .trait = lookup, .args = &.{.u8} }},
            } }},
        }};
        var index = try ImplIndex.build(gpa, &implementations);
        defer index.deinit(gpa);
        builder.implementations = &implementations;
        builder.impl_index = index;
        try testing.expect(try index.find(gpa, &implementations, &builder, 1, &.{}, ticket, .none) == null);

        var granted: RefusedDemands = .empty;
        defer granted.deinit(gpa);
        try granted.put(gpa, .{ .ty = ticket, .lacks = .{ .capability = .copyable } }, {});
        try granted.put(gpa, .{ .ty = ticket, .lacks = .{ .trait = .{ .decl = DeclId.at(lookup), .args = &.{.u16} } } }, {});
        // The trait is granted at `UInt16` only, and the requirement asks for `UInt8`.
        try testing.expect(!try index.appliesGranted(gpa, &implementations, &builder, 1, &.{}, ticket, .none, &granted));
        try granted.put(gpa, .{ .ty = ticket, .lacks = .{ .trait = .{ .decl = DeclId.at(lookup), .args = &.{.u8} } } }, {});
        try testing.expect(try index.appliesGranted(gpa, &implementations, &builder, 1, &.{}, ticket, .none, &granted));
        // Selection is unchanged by what a granted lookup accepted.
        try testing.expect(try index.find(gpa, &implementations, &builder, 1, &.{}, ticket, .none) == null);
    }

    fn findOnce(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        trait: u32,
        args: []const TypeId,
        held: TypeId,
    ) std.mem.Allocator.Error!?ImplementationChoice {
        return self.selectOnce(impls, pool, decided, .find, trait, args, held, true);
    }

    const OrdinarySelection = struct {
        choice: ?ImplementationChoice = null,
        blocks_default: bool = false,
    };

    /// Header matches reserve their receiver before bounds are discharged.
    /// An open receiver's constructor reserves the whole family, because later
    /// substitution may make a presently different ordinary header match.
    fn ordinarySelection(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        trait: u32,
        args: ?[]const TypeId,
        held: TypeId,
    ) std.mem.Allocator.Error!OrdinarySelection {
        var result: OrdinarySelection = .{};
        var run = self.candidates(impls, trait, pool.headOf(held), false);
        while (run.next()) |at| {
            if (!receiverDomainAdmits(pool, decided.scope, impls[at], held)) continue;
            const arguments = if (args) |given| @as(?[]const TypeId, given) else try pool.receiverTraitArguments(@enumFromInt(at), held);
            const candidate: ImplementationCandidate = if (arguments) |given|
                try pool.implementationCandidate(self, impls, decided, at, given, held)
            else
                .{};
            result.blocks_default = result.blocks_default or candidate.header_matches;
            if (!result.blocks_default and self.defaultImplementation(impls, trait) != null)
                result.blocks_default = !isGround(pool, held);
            if (candidate.arguments) |bindings| {
                result.choice = .{ .supplier = .{ .declared = @enumFromInt(at) }, .receiver = held, .impl_args = bindings };
                return result;
            }
        }
        return result;
    }

    fn defaultImplementation(self: *const ImplIndex, impls: []const Implementation, trait: u32) ?u32 {
        var run = self.chained.walk(key(trait, .default_));
        while (run.next()) |at| {
            const row = impls[at];
            if (row.trait == trait and row.head == .default_ and row.valid_key) return at;
        }
        return null;
    }

    fn defaultSelection(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        trait: u32,
        args: []const TypeId,
        held: TypeId,
        blocked: bool,
    ) std.mem.Allocator.Error!?ImplementationChoice {
        if (blocked or args.len != 0 or held == .poison or pool.get(held) == .parameter or pool.standinOf(held) != null) return null;
        const at = self.defaultImplementation(impls, trait) orelse return null;
        if (pool.headOf(held) != .applied and !isGround(pool, held)) return null;
        if (try self.answersFor(impls, pool, decided, trait, at, args, held)) |bindings|
            return .{ .supplier = .{ .declared = @enumFromInt(at) }, .receiver = held, .impl_args = bindings };
        return null;
    }

    /// A parameter or settled reference after one implementation head has
    /// bound all of its parameters. Null where resolving it would need to mint
    /// a constructed type; callable comparison handles those structurally.
    ///
    /// A settled reference reuses this index and the supplied-member table, so
    /// checking a dependent callable bound selects no implementation beside
    /// the lookup every other settled reference uses.
    fn directlySubstituted(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        ty: TypeId,
        owner: u32,
        bindings: []const TypeId,
    ) std.mem.Allocator.Error!?TypeId {
        if (pool.standinOf(ty)) |standin| {
            const held = try self.directlySubstituted(
                impls,
                pool,
                decided,
                standin.held,
                owner,
                bindings,
            ) orelse return null;

            const raw_args = pool.standinArgsOf(standin);
            const args = try decided.gpa.alloc(TypeId, raw_args.len);
            defer decided.gpa.free(args);
            for (raw_args, args) |raw, *arg| {
                arg.* = try self.directlySubstituted(
                    impls,
                    pool,
                    decided,
                    raw,
                    owner,
                    bindings,
                ) orelse return null;
            }

            const at = try self.findOnce(impls, pool, decided, standin.trait, args, held) orelse return null;
            const implementation = impls[(at.declaredImplementation() orelse return null).index()];
            const written = pool.settledTypeWritten(implementation, standin.member) orelse return null;
            if (implementation.parameters == 0) return written;

            // A constructed type that still mentions the implementation's
            // parameters would need minting to substitute them, which this
            // reader never does; leaving it as written would hand the caller
            // another implementation's parameters.
            if (pool.get(written) != .parameter and !isGround(pool, written)) return null;
            const inner = at.impl_args;
            return self.directlySubstituted(
                impls,
                pool,
                decided,
                written,
                implementation.decl.index(),
                inner,
            );
        }

        return switch (pool.get(ty)) {
            .parameter => |parameter| if (parameter.owner == owner and parameter.index < bindings.len)
                bindings[parameter.index]
            else
                ty,
            else => ty,
        };
    }

    /// Whether `actual` is `written` after one implementation receiver binds
    /// `owner`'s parameters. Constructed types are compared recursively rather
    /// than interned, so a mutable Builder and a finished Typing read one
    /// answer without either scanning the pool or manufacturing an editor-only
    /// type.
    fn typeMatchesSubstitution(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        unsettled_actual: TypeId,
        written: TypeId,
        owner: u32,
        bindings: []const TypeId,
    ) std.mem.Allocator.Error!bool {
        // A closure keeps the integer literal a parameter of it was minted
        // with until the check finishes, so what that literal settled on is
        // what the parameter is compared as, as a lookup reads a held literal.
        const actual = settledHeld(pool, unsettled_actual);
        if (pool.standinOf(written)) |want| {
            if (pool.standinOf(actual)) |got| {
                if (got.trait != want.trait or got.member != want.member) return false;
                if (!try self.typeMatchesSubstitution(
                    impls,
                    pool,
                    decided,
                    got.held,
                    want.held,
                    owner,
                    bindings,
                )) return false;
                const got_args = pool.standinArgsOf(got);
                const want_args = pool.standinArgsOf(want);
                if (got_args.len != want_args.len) return false;
                for (got_args, want_args) |got_arg, want_arg| {
                    if (!try self.typeMatchesSubstitution(
                        impls,
                        pool,
                        decided,
                        got_arg,
                        want_arg,
                        owner,
                        bindings,
                    )) return false;
                }
                return true;
            }

            const held = try self.directlySubstituted(
                impls,
                pool,
                decided,
                want.held,
                owner,
                bindings,
            ) orelse return false;
            const raw_args = pool.standinArgsOf(want);
            const args = try decided.gpa.alloc(TypeId, raw_args.len);
            defer decided.gpa.free(args);
            for (raw_args, args) |raw, *arg| {
                arg.* = try self.directlySubstituted(
                    impls,
                    pool,
                    decided,
                    raw,
                    owner,
                    bindings,
                ) orelse return false;
            }

            const at = try self.findOnce(impls, pool, decided, want.trait, args, held) orelse return false;
            const implementation = impls[(at.declaredImplementation() orelse return false).index()];
            const settled = pool.settledTypeWritten(implementation, want.member) orelse return false;
            const inner = at.impl_args;
            return self.typeMatchesSubstitution(
                impls,
                pool,
                decided,
                actual,
                settled,
                implementation.decl.index(),
                inner,
            );
        }

        const direct = try self.directlySubstituted(
            impls,
            pool,
            decided,
            written,
            owner,
            bindings,
        ) orelse return false;
        if (direct != written) return actual == direct;
        if (actual == written) return true;

        const actual_instance = pool.instanceOf(actual);
        const written_instance = pool.instanceOf(written);
        if (actual_instance != null or written_instance != null) {
            const got = actual_instance orelse return false;
            const want = written_instance orelse return false;
            if (got.decl != want.decl) return false;
            const got_args = pool.argsOf(got);
            const want_args = pool.argsOf(want);
            if (got_args.len != want_args.len) return false;
            for (got_args, want_args) |got_arg, want_arg| {
                if (!try self.typeMatchesSubstitution(
                    impls,
                    pool,
                    decided,
                    got_arg,
                    want_arg,
                    owner,
                    bindings,
                )) return false;
            }
            return true;
        }

        return switch (pool.get(written)) {
            .borrow => |want| switch (pool.get(actual)) {
                .borrow => |got| self.typeMatchesSubstitution(impls, pool, decided, got.referent, want.referent, owner, bindings),
                else => false,
            },
            .array => |want| switch (pool.get(actual)) {
                .array => |got| got.count == want.count and try self.typeMatchesSubstitution(
                    impls,
                    pool,
                    decided,
                    got.element,
                    want.element,
                    owner,
                    bindings,
                ),
                else => false,
            },
            .callable => self.callableSignatureMatches(
                impls,
                pool,
                decided,
                actual,
                written,
                owner,
                bindings,
                false,
            ),
            .closure => |want| switch (pool.get(actual)) {
                .closure => |got| blk: {
                    if (got.closure != want.closure) break :blk false;
                    const got_args = pool.closureArgs(got);
                    const want_args = pool.closureArgs(want);
                    if (got_args.len != want_args.len) break :blk false;
                    for (got_args, want_args) |got_arg, want_arg| {
                        if (!try self.typeMatchesSubstitution(
                            impls,
                            pool,
                            decided,
                            got_arg,
                            want_arg,
                            owner,
                            bindings,
                        )) break :blk false;
                    }
                    const got_impl = pool.closureImplArgs(got);
                    const want_impl = pool.closureImplArgs(want);
                    if (got_impl.len != want_impl.len) break :blk false;
                    for (got_impl, want_impl) |got_arg, want_arg| {
                        if (!try self.typeMatchesSubstitution(impls, pool, decided, got_arg, want_arg, owner, bindings)) break :blk false;
                    }
                    if (!try self.typeMatchesSubstitution(impls, pool, decided, got.self_ty, want.self_ty, owner, bindings)) break :blk false;
                    break :blk true;
                },
                else => false,
            },
            else => false,
        };
    }

    fn callableContractsMatch(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        actual: CallableSignature,
        wanted: CallableSignature,
        owner: u32,
        bindings: []const TypeId,
        demand: bool,
    ) std.mem.Allocator.Error!bool {
        var effective: std.ArrayList(CallableContract) = .empty;
        defer effective.deinit(decided.gpa);
        const parameters = pool.callableParams(wanted);
        const result = try self.directlySubstituted(impls, pool, decided, wanted.result, owner, bindings);
        for (wanted.contracts) |contract| {
            const source: ?TypeId = switch (contract.source.root) {
                .parameter => |index| try self.directlySubstituted(impls, pool, decided, parameters[index].ty, owner, bindings),
                .capture, .callee => null,
            };
            if (!contractNamesDependency(pool, contract, result, source)) continue;
            try effective.append(decided.gpa, contract);
        }
        return if (demand) callableContractsSatisfy(actual.contracts, effective.items) else sameContracts(actual.contracts, effective.items);
    }

    /// Compare a substituted signature exactly, or satisfy its callable demand
    /// with positional implementation binders and compatible invocation effects.
    fn callableSignatureMatches(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        actual: TypeId,
        written: TypeId,
        owner: u32,
        bindings: []const TypeId,
        demand: bool,
    ) std.mem.Allocator.Error!bool {
        const got = switch (pool.get(actual)) {
            .callable => |signature| signature,
            else => return false,
        };
        const want = switch (pool.get(written)) {
            .callable => |signature| signature,
            else => return false,
        };
        if (if (demand) !invocationCompatible(got.invocation, want.invocation) else got.invocation != want.invocation) return false;
        const got_params = pool.callableParams(got);
        const want_params = pool.callableParams(want);
        if (got_params.len != want_params.len or !try self.callableContractsMatch(impls, pool, decided, got, want, owner, bindings, demand)) return false;
        for (got_params, want_params) |got_param, want_param| {
            if (!got_param.samePosition(want_param) or
                !try self.typeMatchesSubstitution(
                    impls,
                    pool,
                    decided,
                    got_param.ty,
                    want_param.ty,
                    owner,
                    bindings,
                )) return false;
        }
        return self.typeMatchesSubstitution(
            impls,
            pool,
            decided,
            got.result,
            want.result,
            owner,
            bindings,
        );
    }

    /// Whether a concrete type meets one callable demand after the receiver
    /// has bound every parameter the demand may mention.
    fn meetsCallableDemand(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        given: TypeId,
        required: TypeId,
        owner: u32,
        bindings: []const TypeId,
    ) std.mem.Allocator.Error!bool {
        const settled = try pool.substitute(required, owner, bindings);
        if (pool.carriesCallableBoundWithin(decided.scope, given, settled)) return true;
        switch (pool.get(given)) {
            .callable => if (try self.callableSignatureMatches(
                impls,
                pool,
                decided,
                given,
                required,
                owner,
                bindings,
                true,
            )) return true,
            .closure => |closure| if (try self.callableSignatureMatches(
                impls,
                pool,
                decided,
                try pool.closureSignature(closure),
                required,
                owner,
                bindings,
                true,
            )) return true,
            else => {},
        }

        for (pool.callableBoundsOn(given)) |held| {
            if (try self.callableSignatureMatches(
                impls,
                pool,
                decided,
                held,
                required,
                owner,
                bindings,
                true,
            )) return true;
        }
        return false;
    }

    /// Match the receiver and trait arguments before evaluating constraints.
    /// Projection inputs do not recover parameters; they are compared only
    /// after every structurally recoverable parameter has a binding.
    ///
    /// Also what holds an inherent block's head, and then a member's first
    /// parameter, to a postfix receiver: `bindings` carries what the head
    /// bound into the parameter's match, so `fn get(self: Box[T])` inside
    /// `impl[T] Box[T]` takes the box the head admitted and nothing else.
    pub fn bindKey(pool: anytype, actual: TypeId, written: TypeId, owner: u32, bindings: []TypeId) bool {
        if (actual == .poison or written == .poison) return false;
        if (pool.standinOf(written) != null) return true;
        if (pool.get(written) == .parameter) {
            const parameter = pool.get(written).parameter;
            if (parameter.owner == owner) {
                if (parameter.index >= bindings.len) return false;
                const slot = &bindings[parameter.index];
                if (slot.* == .poison) slot.* = actual;
                return slot.* == actual;
            }
        }
        const want_instance = pool.instanceOf(written);
        const got_instance = pool.instanceOf(actual);
        if (want_instance != null or got_instance != null) {
            const want = want_instance orelse return false;
            const got = got_instance orelse return false;
            if (want.decl != got.decl) return false;
            const wanted = pool.argsOf(want);
            const given = pool.argsOf(got);
            if (wanted.len != given.len) return false;
            for (given, wanted) |got_arg, want_arg| {
                if (!bindKey(pool, got_arg, want_arg, owner, bindings)) return false;
            }
            return true;
        }
        return switch (pool.get(written)) {
            .borrow => |want| switch (pool.get(actual)) {
                .borrow => |got| bindKey(pool, got.referent, want.referent, owner, bindings),
                else => false,
            },
            .array => |want| switch (pool.get(actual)) {
                .array => |got| got.count == want.count and bindKey(pool, got.element, want.element, owner, bindings),
                else => false,
            },
            .callable => |want| switch (pool.get(actual)) {
                .callable => |got| blk: {
                    if (got.invocation != want.invocation) break :blk false;
                    const wanted = pool.callableParams(want);
                    const given = pool.callableParams(got);
                    if (wanted.len != given.len) break :blk false;
                    for (given, wanted) |got_parameter, want_parameter| {
                        if (!bindKey(pool, got_parameter.ty, want_parameter.ty, owner, bindings)) break :blk false;
                    }
                    break :blk bindKey(pool, got.result, want.result, owner, bindings);
                },
                else => false,
            },
            else => actual == written,
        };
    }

    test "bindKey: a head binds the block's parameters and holds a member's first parameter to them" {
        const gpa = testing.allocator;
        var b = try Typing.Builder.init(gpa);
        defer b.deinit();

        const box_decl: DeclId = @enumFromInt(1);
        const field = try b.addParameter("F", box_decl.index(), 0, .unrestricted, &.{});
        const template = try b.addStruct("Box", .copyable, &.{.{ .name = "item", .ty = field }});
        const impl_decl: DeclId = @enumFromInt(2);
        const t = try b.addParameter("T", impl_decl.index(), 0, .unrestricted, &.{});
        const box_t = try b.instantiate(template, box_decl, &.{t});
        const box_u8 = try b.instantiate(template, box_decl, &.{.u8});
        const box_bool = try b.instantiate(template, box_decl, &.{.bool_});

        // `impl[T] Box[T]` admits a `Box[Bool]` and binds `T`; a member whose
        // first parameter is `Box[T]` then takes that same box and no other.
        var bindings = [_]TypeId{.poison};
        try testing.expect(bindKey(&b, box_bool, box_t, impl_decl.index(), &bindings));
        try testing.expectEqual(TypeId.bool_, bindings[0]);
        try testing.expect(bindKey(&b, box_bool, box_t, impl_decl.index(), &bindings));
        try testing.expect(!bindKey(&b, box_u8, box_t, impl_decl.index(), &bindings));

        // `impl Box[UInt8]` has no parameter to bind: it admits its own
        // instantiation and refuses another.
        var none: [0]TypeId = .{};
        try testing.expect(bindKey(&b, box_u8, box_u8, impl_decl.index(), &none));
        try testing.expect(!bindKey(&b, box_bool, box_u8, impl_decl.index(), &none));
        try testing.expect(bindKey(&b, .u8, .u8, impl_decl.index(), &none));
        try testing.expect(!bindKey(&b, .bool_, .u8, impl_decl.index(), &none));
    }

    fn answersFor(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        trait: u32,
        at: u32,
        args: []const TypeId,
        held: TypeId,
    ) std.mem.Allocator.Error!?[]const TypeId {
        if (impls[at].trait != trait) return null;
        return pool.implementationApplies(self, impls, decided, at, args, held);
    }

    /// Binds an implementation's own parameters from the receiver it is asked
    /// about and, where given, the trait arguments it is asked at. The one
    /// reading of how a header meets a receiver: the array constructor's
    /// compiler-provided row has no written head to bind.
    ///
    /// `bindings` starts out all poison; one still poison afterwards is a
    /// parameter the header leaves open.
    fn bindHeader(pool: anytype, im: Implementation, args: ?[]const TypeId, held: TypeId, bindings: []TypeId) bool {
        if (!(im.isAmbient() and im.head == .array) and !bindKey(pool, held, im.ty, im.decl.index(), bindings)) return false;
        if (args) |given| for (given, im.args) |actual, wanted| {
            if (!bindKey(pool, actual, wanted, im.decl.index(), bindings)) return false;
        };
        return true;
    }

    test "bindHeader binds a header to the receiver and the trait arguments it is asked at" {
        var builder = try Typing.Builder.init(testing.allocator);
        defer builder.deinit();
        const im: Implementation = .{ .trait = 1, .args = &.{.u8}, .head = .{ .whole = .u16 }, .ty = .u16, .decl = DeclId.at(1) };
        var none: [0]TypeId = .{};
        try testing.expect(bindHeader(&builder, im, null, .u16, &none));
        try testing.expect(!bindHeader(&builder, im, null, .u32, &none));
        try testing.expect(bindHeader(&builder, im, &.{.u8}, .u16, &none));
        try testing.expect(!bindHeader(&builder, im, &.{.u32}, .u16, &none));
    }

    /// Whether an implementation's header matches a receiver at `args` once
    /// every parameter is bound, with what it bound left in `bindings`.
    ///
    /// Binding is structural and so is not the whole of it: a header written
    /// through a projection or a callable matches only after its own
    /// parameters are substituted, which `typeMatchesSubstitution` compares.
    /// The lookups and the reports that name an implementation as the culprit
    /// both ask this, so neither names one the lookup would not select.
    fn matchHeader(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        im: Implementation,
        args: []const TypeId,
        held: TypeId,
        bindings: []TypeId,
    ) std.mem.Allocator.Error!bool {
        if (!bindHeader(pool, im, args, held, bindings)) return false;
        for (bindings) |bound| if (bound == .poison) return false;
        if (!(im.isAmbient() and im.head == .array) and !try self.typeMatchesSubstitution(impls, pool, decided, held, im.ty, im.decl.index(), bindings)) return false;
        for (args, im.args) |given, wanted| {
            if (!try self.typeMatchesSubstitution(impls, pool, decided, given, wanted, im.decl.index(), bindings)) return false;
        }
        return true;
    }

    test "matchHeader agrees with the lookup on which receivers and arguments a header matches" {
        const gpa = testing.allocator;
        var builder = try Typing.Builder.init(gpa);
        defer builder.deinit();
        const implementations = [_]Implementation{
            .{ .trait = 1, .args = &.{.u8}, .head = .{ .whole = .u16 }, .ty = .u16, .decl = DeclId.at(1) },
        };
        var index = try ImplIndex.build(gpa, &implementations);
        defer index.deinit(gpa);
        builder.implementations = &implementations;
        builder.impl_index = index;
        var decided: Decided = .{ .gpa = gpa, .scope = .none };
        defer decided.deinit();
        var none: [0]TypeId = .{};
        try testing.expect(try index.matchHeader(&implementations, &builder, &decided, implementations[0], &.{.u8}, .u16, &none));
        try testing.expect(!try index.matchHeader(&implementations, &builder, &decided, implementations[0], &.{.u8}, .u32, &none));
        try testing.expect(!try index.matchHeader(&implementations, &builder, &decided, implementations[0], &.{.u16}, .u16, &none));
        try testing.expect(try index.find(gpa, &implementations, &builder, 1, &.{.u8}, .u16, .none) != null);
        try testing.expect(try index.find(gpa, &implementations, &builder, 1, &.{.u16}, .u16, .none) == null);
    }

    /// Retains the structural answer when requirements reject a matching head.
    /// A successful substitution is owned by the caller.
    fn checkCandidate(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: *Typing.Builder,
        decided: *Decided,
        at: u32,
        args: []const TypeId,
        held: TypeId,
        key_: PreparedImplementationKey,
    ) std.mem.Allocator.Error!ImplementationCandidate {
        const im = impls[at];
        if (!im.valid_key or im.args.len != args.len or held == .poison) return .{};
        if (im.head != .parameter and im.head != .default_ and !im.head.same(pool.headOf(held))) return .{};
        if (!receiverDomainAdmits(pool, decided.scope, im, held)) return .{};
        const bindings = try decided.gpa.alloc(TypeId, im.parameters);
        errdefer decided.gpa.free(bindings);
        @memset(bindings, .poison);
        var header_matches = false;
        const matched = blk: {
            if (!try self.matchHeader(impls, pool, decided, im, args, held, bindings)) break :blk false;
            header_matches = true;
            // A recursive bound may fail, but its matching ordinary header
            // still blocks a default.
            decided.active.getPtr(key_).?.* = true;
            const previous_size = decided.prerequisite_sizes.get(@enumFromInt(at));
            if (im.predicates.len > 0) {
                const size = try decided.keySize(pool, held, args);
                if (previous_size) |previous| if (size >= previous) {
                    decided.recursive_refusals += 1;
                    break :blk false;
                };
                try decided.prerequisite_sizes.put(decided.gpa, @enumFromInt(at), size);
            }
            defer if (im.predicates.len > 0) {
                if (previous_size) |previous|
                    decided.prerequisite_sizes.getPtr(@enumFromInt(at)).?.* = previous
                else
                    _ = decided.prerequisite_sizes.remove(@enumFromInt(at));
            };
            for (im.predicates) |predicate| {
                const direct = try self.directlySubstituted(impls, pool, decided, predicate.subject, im.decl.index(), bindings);
                const subject = try pool.substitute(direct orelse predicate.subject, im.decl.index(), bindings);
                if (!try self.meetsDemand(impls, pool, decided, im, bindings, subject, predicate.demand)) break :blk false;
            }
            // A viewed array row applies exactly where the view's own
            // implementation does, so the two cannot disagree.
            if (im.viewed) {
                const view = try pool.arrayViewOf(held) orelse break :blk false;
                if (try self.findOnce(impls, pool, decided, im.trait, args, view) == null) break :blk false;
            }
            break :blk true;
        };
        if (matched) return .{ .header_matches = true, .arguments = bindings };
        decided.gpa.free(bindings);
        return .{ .header_matches = header_matches };
    }

    fn meetsDemand(
        self: *const ImplIndex,
        impls: []const Implementation,
        pool: anytype,
        decided: *Decided,
        im: Implementation,
        bindings: []const TypeId,
        given: TypeId,
        demand: Demand,
    ) std.mem.Allocator.Error!bool {
        const within = decided.scope;
        if (!try pool.meetsCapabilityWithin(within, given, demand.requirement) and
            !decided.grants(.{ .ty = given, .lacks = .{ .capability = demand.requirement } })) return false;
        if (demand.integer and !pool.isIntegerWithin(within, given)) return false;
        if (demand.owned and try pool.mayCarryDependencies(given)) return false;
        for (demand.traits) |required| {
            const args = try decided.gpa.alloc(TypeId, required.args.len);
            defer decided.gpa.free(args);
            for (required.args, args) |written, *argument| argument.* = try pool.substitute(written, im.decl.index(), bindings);
            if (decided.grants(.{ .ty = given, .lacks = .{ .trait = .{ .decl = DeclId.at(required.trait), .args = args } } })) continue;
            if (try self.findOnce(impls, pool, decided, required.trait, args, given) == null) return false;
        }
        for (demand.callables) |required| {
            if (try self.meetsCallableDemand(
                impls,
                pool,
                decided,
                given,
                required,
                im.decl.index(),
                bindings,
            )) continue;
            const settled = try pool.substitute(required, im.decl.index(), bindings);
            if (!decided.grants(.{ .ty = given, .lacks = .{ .callable = settled } })) return false;
        }
        return true;
    }

    /// Whether an implementation covers a type: the head, the arguments it
    /// applies, and the bounds its parameters demand.
    ///
    /// This is the question `find` asks of every row it walks past, and it is
    /// public because a member reached any other way still has to belong to an
    /// implementation that answers for the type. A traversal is found through
    /// the type it is declared on rather than through a trait, so the row that
    /// declares it is tested here instead -- and without this an
    /// `impl Pair[UInt8]` supplies an order for a `Pair[Int64]`, which is a
    /// member reached from an implementation that does not cover it.
    pub fn covers(
        self: *const ImplIndex,
        gpa: std.mem.Allocator,
        impls: []const Implementation,
        pool: anytype,
        at: u32,
        held: TypeId,
        scope: DeclId,
    ) std.mem.Allocator.Error!bool {
        var decided: Decided = .{ .gpa = gpa, .scope = scope };
        defer decided.deinit();
        const args = try pool.receiverTraitArguments(@enumFromInt(at), held) orelse return false;
        return try self.answersFor(impls, pool, &decided, impls[at].trait, at, args, held) != null;
    }
};

// Makes every test build compile the tests `ImplIndex` holds, including a build
// filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = ImplIndex;
}

/// The place an implementation's projection names, once for the
/// implementation.
///
/// A projection's body is a path rooted at its receiver, so what a bracket
/// means is that path with two slots filled: the base fills the receiver and
/// the index expression fills the index parameter. The path is a fact about the
/// implementation rather than about any site that reaches it, so it is worked
/// out where the implementation is and every site names this record.
/// A checked forwarding projection, optionally preceded by a stored-field step.
/// A null backing expansion denotes built-in array indexing.
pub const DelegatedProjection = struct {
    field_name: ?StringId = null,
    owner: ?DeclId = null,
    deferred_trait: ?DeclId = null,
    field: ?u32 = null,
    field_type: TypeId,
    key_type: TypeId,
    backing: ?u32 = null,
    backing_args: []const TypeId = &.{},
};

pub const Expansion = struct {
    writable: bool = true,
    requires_write: bool = false,
    delegation: ?DelegatedProjection = null,
    impl_args: []const TypeId = &.{},
    /// The projection supplying the trait's, by declaration. What the mode
    /// ceiling is read from.
    member: DeclId,
    /// The body's path: the expression a site becomes.
    path: ExprId,
    /// The receiver's binding, which the base of the bracket fills.
    receiver: u32,
    /// The index parameter's binding, which the index expression fills, or
    /// `no_binding` where the path names no index at all.
    index: u32,

    /// What `index` holds for a path that reaches its element by field
    /// selection alone, so no site expression fills a slot.
    pub const no_binding = std.math.maxInt(u32);
};

/// The conversion a `?` applies to a failure whose error type differs from
/// the enclosing function's: the library's `From` trait, its `from`
/// operation, and the two error types as the checker saw them. The
/// implementation is selected per instance, with `source` as the trait
/// argument and `target` as the receiver after substitution, since inside a
/// generic body either may be a parameter.
pub const TryConversion = struct {
    trait: DeclId,
    member: DeclId,
    source: TypeId,
    target: TypeId,
};

/// A lending walk and the traversal it runs through.
///
/// Keyed by the loop, because which traversal a walk found is a fact about that
/// walk: the checker searched the type for one and held the positions it yields
/// to the projection's index, and lowering emits the expression it settled on.
/// A second search below here would be free to find a different one.
pub const TraversalPositions = union(enum) {
    expression: ExprId,
    array: struct {
        key: TypeId,
        count: u32,
        iterator: TypeId,
    },
};

pub const Traversal = struct {
    positions: TraversalPositions = .{ .expression = .none },
    impl_args: []const TypeId = &.{},
    /// The loop, by expression.
    at: u32,
    /// The `trav` member, by declaration. What lowering reads the positions
    /// expression off.
    decl: DeclId,
};

/// A bracket that names a place through an implementation rather than an
/// array, and the expansion it becomes.
///
/// Keyed by the bracket, because what one site means is a fact about that site:
/// the same implementation is reached from every bracket over the type, and
/// each fills its slots with its own two expressions.
pub const Projected = struct {
    requires_write: bool = false,
    impl_args: []const TypeId = &.{},
    /// The bracket, by expression.
    at: u32,
    /// Which entry of `Typing.expansions` it becomes.
    expansion: u32,
};

/// A bracket whose index is a range, and where the run of elements it names
/// begins.
///
/// The bounds settled where the place was formed, and this is what they
/// settled to. Recorded rather than folded again below: the checker's fold
/// table is what says whether a bound settles at all, so a reader working the
/// offset out from the tree would be a second answer to the question the
/// place's own type was built from -- and it would be the narrower of the two,
/// which is a program accepted for a place nothing can emit.
pub const RangePlace = struct {
    /// The bracket, by expression.
    at: u32,
    /// The index of the first element the place names.
    first: u32,
};

/// One signature a trait declares, and the `impl` member supplying it.
///
/// The pair the checker settles when it discharges an implementation against
/// its trait. A member sits in no namespace, so it is found by the name it
/// shares with the signature inside the implementation's token extent -- which
/// makes the spelling the whole of the relation unless the pair is written
/// down.
pub const Supplied = struct {
    /// The implementation.
    impl: DeclId,
    /// The signature.
    sig: DeclId,
    /// The member supplying it.
    member: DeclId,
};

/// Which member supplies each signature, asked from either side.
///
/// Two askers and two questions. Lowering has an implementation and a signature
/// and wants the body a call runs; a rename has one declaration of the pair and
/// wants every declaration the language obliges to share its spelling. Both are
/// lookups: the first walked every declaration the program holds once per call
/// through a trait, and a module of many `impl` blocks paid the product.
pub const SupplyIndex = struct {
    /// The member each implementation supplies a signature with, keyed by the
    /// two together -- a signature is supplied once per implementation, and the
    /// implementation is what tells those apart.
    member_of: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    /// Where each signature's run in `by_sig` begins, by declaration.
    sig_starts: []const u32 = &.{},
    /// The members supplying each signature, grouped by it and in the order
    /// they were recorded.
    by_sig: []const u32 = &.{},
    /// The signature each member supplies, by declaration, or `absent`.
    sig_of: []const u32 = &.{},

    pub const absent = std.math.maxInt(u32);

    fn key(impl: u32, sig: u32) u64 {
        return (@as(u64, impl) << 32) | sig;
    }

    /// **Bound:** `O(declarations + pairs)`. One pass over the pairs to count,
    /// one over the declarations to place the runs, one over the pairs to fill
    /// them. The two tables sized by declarations are one table each for the
    /// program, in the way `decl_returns` is.
    pub fn build(
        gpa: std.mem.Allocator,
        decl_count: usize,
        supplied: []const Supplied,
    ) !SupplyIndex {
        var member_of: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        errdefer member_of.deinit(gpa);
        try member_of.ensureTotalCapacity(gpa, @intCast(supplied.len));

        const sig_starts = try gpa.alloc(u32, decl_count + 1);
        errdefer gpa.free(sig_starts);
        @memset(sig_starts, 0);

        const sig_of = try gpa.alloc(u32, decl_count);
        errdefer gpa.free(sig_of);
        @memset(sig_of, absent);

        for (supplied) |s| {
            member_of.putAssumeCapacity(key(s.impl.index(), s.sig.index()), s.member.index());
            sig_starts[s.sig.index() + 1] += 1;
            sig_of[s.member.index()] = s.sig.index();
        }
        for (1..decl_count + 1) |i| sig_starts[i] += sig_starts[i - 1];

        const by_sig = try gpa.alloc(u32, supplied.len);
        errdefer gpa.free(by_sig);

        const cursor = try gpa.alloc(u32, decl_count);
        defer gpa.free(cursor);
        @memcpy(cursor, sig_starts[0..decl_count]);

        for (supplied) |s| {
            by_sig[cursor[s.sig.index()]] = s.member.index();
            cursor[s.sig.index()] += 1;
        }

        return .{
            .member_of = member_of,
            .sig_starts = sig_starts,
            .by_sig = by_sig,
            .sig_of = sig_of,
        };
    }

    pub fn deinit(self: *SupplyIndex, gpa: std.mem.Allocator) void {
        self.member_of.deinit(gpa);
        gpa.free(self.sig_starts);
        gpa.free(self.by_sig);
        gpa.free(self.sig_of);
    }

    /// The member of one implementation supplying one signature, or null where
    /// it supplies none.
    /// Three declarations, three types. Spelled as numbers these were three
    /// arguments any two of which could be swapped silently -- and a swap
    /// answers `null`, which every caller reads as "this implementation
    /// supplies nothing" rather than as "you asked wrong".
    pub fn memberOf(self: *const SupplyIndex, impl: DeclId, sig: DeclId) ?DeclId {
        const at = self.member_of.get(key(impl.index(), sig.index())) orelse return null;
        return DeclId.at(at);
    }

    /// The signature a member supplies, or null where this declaration supplies
    /// none.
    pub fn signatureOf(self: *const SupplyIndex, member: DeclId) ?DeclId {
        if (member.index() >= self.sig_of.len) return null;
        const sig = self.sig_of[member.index()];
        return if (sig == absent) null else DeclId.at(sig);
    }

    /// Every member supplying one signature, in the order they were recorded.
    pub fn membersOf(self: *const SupplyIndex, sig: DeclId) []const u32 {
        const at = sig.index();
        if (at + 1 >= self.sig_starts.len) return &.{};
        return self.by_sig[self.sig_starts[at]..self.sig_starts[at + 1]];
    }
};

/// What each defaulted parameter is worth, by the declaration and the position
/// that declares it.
///
/// A default has no evaluation site: nothing runs where a parameter is
/// declared, and a call that omits the parameter receives the value rather than
/// an expression to run. So the checker folds it once, where it is written and
/// with the declaration's own names in scope, and records the value here.
/// Every call omitting the parameter reads this, which is what makes writing
/// the constant out and leaving it off one program.
///
/// Keyed by the pair, because a position numbers nothing without the
/// declaration that declares it. Sized by the defaults a program writes -- a
/// declaration with none records nothing, which is nearly all of them.
pub const Defaults = struct {
    values: std.AutoHashMapUnmanaged(u64, ConstantValue) = .empty,

    fn key(decl: u32, param: u32) u64 {
        return (@as(u64, decl) << 32) | param;
    }

    pub fn note(
        self: *Defaults,
        gpa: std.mem.Allocator,
        decl: u32,
        param: u32,
        value: ConstantValue,
    ) !void {
        try self.values.put(gpa, key(decl, param), value);
    }

    pub fn get(self: *const Defaults, decl: u32, param: u32) ?ConstantValue {
        return self.values.get(key(decl, param));
    }

    pub fn deinit(self: *Defaults, gpa: std.mem.Allocator) void {
        self.values.deinit(gpa);
    }
};

/// A settled reference whose implementation is not named yet: the key one is
/// found by, and the member it would be read off.
///
/// `W.Item` written where `W` is a bounded parameter, and `Self.Item` read at a
/// call inside a generic body, are the same thing said two ways -- a type that
/// is a function of an implementation nothing has chosen. Both are recorded as
/// the whole key coherence uses, because any part of it may be the parameter
/// that the instantiation settles: the head where a bound named the trait, and
/// a trait argument where the call did.
///
/// Kept beside the pool rather than as a variant of `Type`, so that everything
/// a type parameter obliges a settled reference obliges too, through the one
/// rule that already says it. What a pool entry is, is that it stands for a
/// type an instantiation supplies; what this adds is which type that is, which
/// is a fact about the entry and is keyed by it.
pub const Standin = struct {
    /// The trait's declaration, which is what the bound named or the call went
    /// through.
    trait: u32,
    /// The declared type of that trait, by declaration.
    member: DeclId,
    /// What the implementation is for: `W` inside the body, and whatever the
    /// instantiation settles `W` to after it.
    held: TypeId,
    /// What the trait's own parameters are settled to, as a run in
    /// `standin_args`.
    first_arg: u32 = 0,
    arg_count: u32 = 0,
    /// The pool entry standing for it.
    ty: TypeId,
    /// How the member is spelled, which is the second half of the entry's
    /// name. Borrowed source text, like a declared type's name.
    named: []const u8,
};

/// One complete bound promise active while a declaration is checked.
pub const ContextualConstraint = struct {
    subject: TypeId,
    demand: Demand,
};

/// Contextual promises, stored once with one enclosing-scope link per declaration.
pub const ContextualConstraints = struct {
    capability_scopes: []const DeclId = &.{},

    starts: []const u32 = &.{},
    parents: []const DeclId = &.{},
    items: []const ContextualConstraint = &.{},

    fn lookupScope(self: *const ContextualConstraints, owner: DeclId) DeclId {
        return if (self.run(owner).len != 0 or self.run(self.parentOf(owner)).len != 0) owner else .none;
    }

    pub fn activeCapabilityScope(self: *const ContextualConstraints, owner: DeclId) DeclId {
        if (owner == .none or self.items.len == 0) return .none;
        std.debug.assert(owner.index() < self.capability_scopes.len);
        return self.capability_scopes[owner.index()];
    }

    fn run(self: *const ContextualConstraints, owner: DeclId) []const ContextualConstraint {
        if (owner == .none or owner.index() + 1 >= self.starts.len) return &.{};
        return self.items[self.starts[owner.index()]..self.starts[owner.index() + 1]];
    }

    /// The declaration whose bounds `owner` is checked under besides its
    /// own: the `impl` or trait that encloses it, or none.
    pub fn parentOf(self: *const ContextualConstraints, owner: DeclId) DeclId {
        if (owner == .none or owner.index() >= self.parents.len) return .none;
        return self.parents[owner.index()];
    }

    test "a declaration's parent is the block that encloses it" {
        const block = DeclId.at(0);
        const member = DeclId.at(1);
        const constraints: ContextualConstraints = .{ .parents = &.{ .none, block } };
        try testing.expectEqual(DeclId.none, constraints.parentOf(block));
        try testing.expectEqual(block, constraints.parentOf(member));
        try testing.expectEqual(DeclId.none, constraints.parentOf(DeclId.at(2)));
        try testing.expectEqual(DeclId.none, constraints.parentOf(.none));
    }

    pub fn boundsCarry(
        self: *const ContextualConstraints,
        owner: DeclId,
        subject: TypeId,
        trait: u32,
        args: ?[]const TypeId,
    ) bool {
        const owners = [_]DeclId{ owner, self.parentOf(owner) };
        for (owners) |scope| {
            for (self.run(scope)) |constraint| {
                if (constraint.subject != subject) continue;
                for (constraint.demand.traits) |held| {
                    if (held.trait != trait) continue;
                    if (args == null or std.mem.eql(TypeId, held.args, args.?)) return true;
                }
            }
        }
        return false;
    }

    /// Appends the arguments of every contextual bound naming `trait` on
    /// `subject`, from the same two scopes `boundsCarry` reads.
    pub fn boundArguments(
        self: *const ContextualConstraints,
        gpa: std.mem.Allocator,
        owner: DeclId,
        subject: TypeId,
        trait: u32,
        out: *std.ArrayList([]const TypeId),
    ) std.mem.Allocator.Error!void {
        const owners = [_]DeclId{ owner, self.parentOf(owner) };
        for (owners) |scope| {
            for (self.run(scope)) |constraint| {
                if (constraint.subject != subject) continue;
                for (constraint.demand.traits) |held| {
                    if (held.trait == trait) try out.append(gpa, held.args);
                }
            }
        }
    }

    pub fn requiresInteger(self: *const ContextualConstraints, owner: DeclId, subject: TypeId) bool {
        const owners = [_]DeclId{ owner, self.parentOf(owner) };
        for (owners) |scope| {
            for (self.run(scope)) |constraint| {
                if (constraint.subject == subject and constraint.demand.integer) return true;
            }
        }
        return false;
    }

    pub fn carriesCallable(self: *const ContextualConstraints, typing: *const Typing, owner: DeclId, subject: TypeId, signature: TypeId) bool {
        const owners = [_]DeclId{ owner, self.parentOf(owner) };
        for (owners) |scope| {
            for (self.run(scope)) |constraint| {
                if (constraint.subject != subject) continue;
                for (constraint.demand.callables) |held| if (typing.callableSatisfies(held, signature)) return true;
            }
        }
        return false;
    }

    pub fn singleCallable(self: *const ContextualConstraints, owner: DeclId, subject: TypeId) ?TypeId {
        var found: ?TypeId = null;
        const owners = [_]DeclId{ owner, self.parentOf(owner) };
        for (owners) |scope| {
            for (self.run(scope)) |constraint| {
                if (constraint.subject != subject) continue;
                for (constraint.demand.callables) |held| {
                    if (found) |known| {
                        if (known != held) return null;
                    } else {
                        found = held;
                    }
                }
            }
        }
        return found;
    }

    pub fn deinit(self: *ContextualConstraints, gpa: std.mem.Allocator) void {
        gpa.free(self.capability_scopes);
        for (self.items) |constraint| {
            freeBoundTraits(gpa, constraint.demand.traits);
            if (constraint.demand.callables.len > 0) gpa.free(constraint.demand.callables);
        }
        gpa.free(self.starts);
        gpa.free(self.parents);
        gpa.free(self.items);
        self.* = .{};
    }
};

/// One call reaching a trait's signature: the trait it goes through, and what
/// its `Self` settled to.
///
/// A signature has no body, so the callee a call names is not the declaration
/// it reaches. The type rather than that declaration, because a call inside a
/// generic body settles `Self` to a type parameter: which implementation runs
/// is not known until the body is instantiated, and is resolved where every
/// other such question is, from the arguments the instantiation was made with.
///
/// The trait is its declaration, which is what makes the pair a key: a type may
/// implement several traits, so the type alone does not say which
/// implementation a call meant -- and two modules may each declare one of that
/// name, so the spelling does not say which trait.
pub const CallImpl = struct {
    call: u32,
    /// The trait the call goes through, or `Implementation.no_trait` where it
    /// names a member of an inherent implementation outright.
    trait: u32,
    /// What the call settled the trait's parameters to. Part of what picks the
    /// implementation, so lowering reads it rather than settling it again.
    args: []const TypeId = &.{},
    self_ty: TypeId,

    /// Whether this call reaches its body through a trait.
    pub fn ofATrait(self: CallImpl) bool {
        return self.trait != Implementation.no_trait;
    }
};

/// Where each site's records sit in the tables the checker left.
///
/// The checker writes one list per question, in the order it walked, and a
/// consumer asks them one site at a time -- so a scan is every call in the
/// program read for every call asked about, and a body of `n` calls costs `n`
/// squared. Every table is keyed by expression, so one pass over each turns
/// every later question into a single step. A bracket that routes through an
/// implementation is such a site: it is not a call, but what the checker
/// recorded for it is keyed the same way and found through the same index,
/// because a second finder is a second chance to stop at a different record.
///
/// One index rather than one per consumer: lowering asks what a call
/// instantiated to in order to emit it, and a server asks the same thing in
/// order to say it, and two lookups that walk the same list are two chances to
/// stop at different records.
///
/// The first record for an expression wins, which is the one a scan reached.
/// Nothing here decides anything: it is the checker's own answer, found
/// faster. The locator costs one word per expression; fixed records are stored
/// only for expressions that carry at least one indexed answer.
pub const CallIndex = struct {
    /// Position in `records` per expression, or `absent`.
    locator: []const u32 = &.{},
    /// One row for each expression carrying at least one indexed answer.
    records: []const Record = &.{},

    const absent = std.math.maxInt(u32);

    const Record = struct {
        calls: u32 = absent,
        recovered_first: u32 = absent,
        recovered_count: u32 = 0,
        recovered_calls: u32 = absent,
        postfix: u32 = absent,
        projected: u32 = absent,
        traversals: u32 = absent,
        range_places: u32 = absent,
        function_values: u32 = absent,
    };

    comptime {
        std.debug.assert(@sizeOf(Record) == 36);
        std.debug.assert(@alignOf(Record) == 4);
    }

    pub fn build(gpa: std.mem.Allocator, exprs: u32, typing: *const Typing) !CallIndex {
        const locator = try gpa.alloc(u32, exprs);
        errdefer gpa.free(locator);
        @memset(locator, absent);

        var records: std.ArrayList(Record) = .empty;
        errdefer records.deinit(gpa);

        for (typing.calls, 0..) |rec, i| {
            const at = try recordFor(gpa, locator, &records, rec.at.index()) orelse continue;
            if (records.items[at].calls == absent) records.items[at].calls = @intCast(i);
        }
        for (typing.recovered_call_args, 0..) |rec, i| {
            const at = try recordFor(gpa, locator, &records, rec.call.index()) orelse continue;
            if (records.items[at].recovered_first == absent) records.items[at].recovered_first = @intCast(i);
            records.items[at].recovered_count += 1;
        }
        for (typing.recovered_calls, 0..) |rec, i| {
            const at = try recordFor(gpa, locator, &records, rec.at.index()) orelse continue;
            if (records.items[at].recovered_calls == absent) records.items[at].recovered_calls = @intCast(i);
        }
        for (typing.postfix, 0..) |rec, i| {
            const at = try recordFor(gpa, locator, &records, rec.call) orelse continue;
            if (records.items[at].postfix == absent) records.items[at].postfix = @intCast(i);
        }
        for (typing.projected, 0..) |rec, i| {
            const at = try recordFor(gpa, locator, &records, rec.at) orelse continue;
            if (records.items[at].projected == absent) records.items[at].projected = @intCast(i);
        }
        for (typing.traversals, 0..) |rec, i| {
            const at = try recordFor(gpa, locator, &records, rec.at) orelse continue;
            if (records.items[at].traversals == absent) records.items[at].traversals = @intCast(i);
        }
        for (typing.range_places, 0..) |rec, i| {
            const at = try recordFor(gpa, locator, &records, rec.at) orelse continue;
            if (records.items[at].range_places == absent) records.items[at].range_places = @intCast(i);
        }
        for (typing.function_values, 0..) |rec, i| {
            const at = try recordFor(gpa, locator, &records, rec.at.index()) orelse continue;
            if (records.items[at].function_values == absent) records.items[at].function_values = @intCast(i);
        }

        return .{
            .locator = locator,
            .records = try records.toOwnedSlice(gpa),
        };
    }

    pub fn deinit(self: *CallIndex, gpa: std.mem.Allocator) void {
        gpa.free(self.records);
        gpa.free(self.locator);
        self.* = undefined;
    }

    /// The complete semantic answer for one call, or null where this expression
    /// is not an accepted call to an existing callable declaration.
    pub fn callOf(self: *const CallIndex, typing: *const Typing, id: ExprId) ?NormalizedCall {
        const record = self.recordOf(id) orelse return null;
        return typing.calls[present(record.calls) orelse return null];
    }

    pub fn recoveredArgsOf(self: *const CallIndex, typing: *const Typing, id: ExprId) []const RecoveredCallArg {
        const record = self.recordOf(id) orelse return &.{};
        const first = present(record.recovered_first) orelse return &.{};
        return typing.recovered_call_args[first..][0..record.recovered_count];
    }

    pub fn recoveredCallOf(self: *const CallIndex, typing: *const Typing, id: ExprId) ?RecoveredCall {
        const record = self.recordOf(id) orelse return null;
        return typing.recovered_calls[present(record.recovered_calls) orelse return null];
    }

    pub fn functionValueOf(self: *const CallIndex, typing: *const Typing, id: ExprId) ?FunctionValue {
        const record = self.recordOf(id) orelse return null;
        return typing.function_values[present(record.function_values) orelse return null];
    }

    /// The source record for a postfix spelling, or null where the call was
    /// written out. Semantic target and argument questions use `callOf`.
    pub fn postfixOf(self: *const CallIndex, typing: *const Typing, id: ExprId) ?Postfix {
        const record = self.recordOf(id) orelse return null;
        return typing.postfix[present(record.postfix) orelse return null];
    }

    /// What a bracket expands into, or null where it indexes an array.
    ///
    /// The one answer to whether a bracket routes. Lowering asks it to emit the
    /// path, and the checker asks it to hold a write to the mode the
    /// implementation grants; a reader that decided for itself by looking at
    /// the base's type would be a second routing rule, and the two would
    /// disagree wherever a type was refused after the first had already said
    /// yes.
    pub fn projectionOf(self: *const CallIndex, typing: *const Typing, id: ExprId) ?Expansion {
        const record = self.recordOf(id) orelse return null;
        const row = typing.projected[present(record.projected) orelse return null];
        var expansion = typing.expansions[row.expansion];
        expansion.impl_args = row.impl_args;
        expansion.requires_write = row.requires_write;
        return expansion;
    }

    /// The `trav` member a lending walk runs through, or null where the walk is
    /// over places the compiler carries.
    ///
    /// The one answer to which traversal a walk found. The checker searched for
    /// it and held what it yields to the projection's index; lowering emits the
    /// expression this names rather than searching again, because a second
    /// search would be free to find another.
    pub fn traversalPlan(self: *const CallIndex, typing: *const Typing, id: ExprId) ?Traversal {
        const record = self.recordOf(id) orelse return null;
        return typing.traversals[present(record.traversals) orelse return null];
    }

    /// Where the run of elements a bracket names begins, or null where the
    /// bracket names one element.
    ///
    /// The one answer to whether a bracket is a range place. The checker
    /// settled the bounds to build the place's type, so this is that same
    /// settlement read back rather than the tree folded a second time by a
    /// reader that folds less of it.
    pub fn rangePlaceOf(self: *const CallIndex, typing: *const Typing, id: ExprId) ?RangePlace {
        const record = self.recordOf(id) orelse return null;
        return typing.range_places[present(record.range_places) orelse return null];
    }

    fn recordFor(
        gpa: std.mem.Allocator,
        locator: []u32,
        records: *std.ArrayList(Record),
        key: u32,
    ) !?u32 {
        if (key >= locator.len) return null;
        if (locator[key] != absent) return locator[key];
        const at: u32 = @intCast(records.items.len);
        try records.append(gpa, .{});
        locator[key] = at;
        return at;
    }

    fn recordOf(self: *const CallIndex, id: ExprId) ?*const Record {
        if (id.index() >= self.locator.len) return null;
        const found = self.locator[id.index()];
        return if (found == absent) null else &self.records[found];
    }

    fn present(found: u32) ?u32 {
        return if (found == absent) null else found;
    }
};

/// A declared type, and where it was declared.
///
/// The module is held rather than looked up because a mangled name must
/// distinguish two modules that declare one name, and the pool is asked for
/// that name in places that hold no program.
pub const Template = struct {
    decl: DeclId,
    module: u32,
    ty: TypeId,
};

/// One instantiation, and what it was instantiated from.
pub const Instance = struct {
    decl: DeclId,
    first_arg: u32,
    arg_count: u32,
    ty: TypeId,
};

/// One copy of one declaration: which declaration, and what this copy makes of
/// every type parameter standing in its types.
///
/// Two lists, because two declarations may declare a parameter one body reads.
/// A function's own are settled by the call reaching it; those of an
/// implementation generic over its head are bound by the receiver, and a member
/// of one reads both -- `fn fmt[W: Writer](read self: Option[T], inout w: W)`
/// holds one of each. Substitution is keyed by the declaration a parameter
/// belongs to, so the two are applied in turn rather than merged into a list
/// nothing owns.
///
/// One record, because every reading of an instantiated body asks the same
/// question: monomorphisation, the operator check that runs per instantiation,
/// and the dumps that render a body as one copy of itself.
pub const BodyOrigin = union(enum) {
    declaration: DeclId,
    closure: ids.ClosureId,
    closure_release: TypeId,
    constructor: ConstructorBody,
    /// The entry an erased closure is called through for one stored callable.
    erased_entry: ErasedEntry,
    /// The release an erased closure runs on one stored callable type.
    erased_settle: TypeId,
    /// A body for an operation the compiler provides, where a function value
    /// holds it: the trait member and the type it runs for.
    built_in: OperationAt,
    /// A body for an operation an array answers through its slice view,
    /// where a function value holds it: it views each array argument and
    /// calls the slice's implementation.
    viewed: OperationAt,
};

/// A trait operation at one type that answers it, as a body of its own.
pub const OperationAt = struct {
    trait: DeclId,
    member: DeclId,
    receiver: TypeId,
};

/// A stored callable type, and the signature an erased closure calls it as.
pub const ErasedEntry = struct {
    callable: TypeId,
    signature: TypeId,
};

/// What an instance of a body binds besides the body's own type parameters.
///
/// A member of an implementation generic over its head is written in that
/// implementation's parameters, and a trait's provided operation in the
/// trait's parameters and in its own symbolic `Self`, which sits after its own
/// parameters. An instance key's `impl_args` stand for the first and its
/// `self_ty` for the second. A closure is read under the declaration that
/// encloses it, so its type records these for its enclosing declaration and
/// its environment and signature are read through the same substitution its
/// body is.
pub const BodyParameters = struct {
    /// The declaration whose parameters `impl_args` stand for: the
    /// implementation enclosing the body, or the trait providing it. `.none`
    /// where it has neither.
    owner: DeclId = .none,
    /// Whether the body is a trait's provided operation, whose symbolic
    /// `Self` follows its own parameters.
    provided: bool = false,

    /// The substitution one instance of a body written in `decl` reads its
    /// types under. It is not the instance's key: a closure's body is read
    /// under its enclosing declaration, a provided operation's `Self`
    /// included, while its key holds only what its type is instantiated over.
    /// The arguments are allocated from `gpa` and the caller's; `impl_args`
    /// stays borrowed.
    pub fn instantiation(
        self: BodyParameters,
        gpa: std.mem.Allocator,
        body: BodyOrigin,
        decl: DeclId,
        args: []const TypeId,
        self_ty: TypeId,
        impl_args: []const TypeId,
    ) std.mem.Allocator.Error!Instantiation {
        const out = try gpa.alloc(TypeId, args.len + @intFromBool(self.provided));
        @memcpy(out[0..args.len], args);
        if (self.provided) out[args.len] = self_ty;
        return .{
            .body = body,
            .decl = decl,
            .args = out,
            .self_ty = self_ty,
            .impl = if (self_ty == .poison) .none else self.owner,
            .impl_args = impl_args,
        };
    }

    /// The substitution a member's own text is read under where a delegation
    /// or a traversal splices it in at `receiver`: the member's parameters,
    /// bound by the receiver its enclosing implementation was matched
    /// against. A member enclosed by nothing binds no receiver.
    pub fn splicedAt(
        self: BodyParameters,
        gpa: std.mem.Allocator,
        member: DeclId,
        receiver: TypeId,
        impl_args: []const TypeId,
    ) std.mem.Allocator.Error!Instantiation {
        return self.instantiation(gpa, .{ .declaration = member }, member, &.{}, if (self.owner == .none) .poison else receiver, impl_args);
    }
};

test "BodyParameters places a provided operation's Self after its own arguments" {
    const own = [_]TypeId{.u8};
    const impl_args = [_]TypeId{.bool_};
    const provided: BodyParameters = .{ .owner = DeclId.at(3), .provided = true };
    const at = try provided.instantiation(testing.allocator, .{ .declaration = DeclId.at(7) }, DeclId.at(7), &own, .u16, &impl_args);
    defer testing.allocator.free(at.args);
    try testing.expectEqualSlices(TypeId, &.{ .u8, .u16 }, at.args);
    try testing.expectEqual(DeclId.at(3), at.impl);
    try testing.expectEqual(TypeId.u16, at.self_ty);

    const member: BodyParameters = .{ .owner = DeclId.at(4) };
    const in_member = try member.instantiation(testing.allocator, .{ .declaration = DeclId.at(8) }, DeclId.at(8), &own, .u16, &impl_args);
    defer testing.allocator.free(in_member.args);
    try testing.expectEqualSlices(TypeId, &own, in_member.args);
    try testing.expectEqual(DeclId.at(4), in_member.impl);

    const unbound = try member.instantiation(testing.allocator, .{ .declaration = DeclId.at(8) }, DeclId.at(8), &own, .poison, &impl_args);
    defer testing.allocator.free(unbound.args);
    try testing.expectEqual(DeclId.none, unbound.impl);
}

test "BodyParameters binds a spliced member's receiver only where an implementation encloses it" {
    const impl_args = [_]TypeId{.u8};
    const member: BodyParameters = .{ .owner = DeclId.at(4) };
    const spliced = try member.splicedAt(testing.allocator, DeclId.at(8), .u16, &impl_args);
    defer testing.allocator.free(spliced.args);
    try testing.expectEqual(TypeId.u16, spliced.self_ty);
    try testing.expectEqual(DeclId.at(4), spliced.impl);
    try testing.expectEqualSlices(TypeId, &impl_args, spliced.impl_args);
    try testing.expectEqual(@as(usize, 0), spliced.args.len);

    const free: BodyParameters = .{};
    const alone = try free.splicedAt(testing.allocator, DeclId.at(9), .u16, &.{});
    defer testing.allocator.free(alone.args);
    try testing.expectEqual(TypeId.poison, alone.self_ty);
    try testing.expectEqual(DeclId.none, alone.impl);
}

pub const Instantiation = struct {
    /// The source body emitted. `decl` below remains the generic substitution
    /// owner, which for a closure is its enclosing declaration.
    body: BodyOrigin = .{ .declaration = .none },
    decl: DeclId,
    args: []const TypeId = &.{},
    /// The concrete receiver key for an enclosing implementation.
    self_ty: TypeId = .poison,
    /// The implementation enclosing the declaration, and what a receiver bound
    /// its parameters to. `.none` where the body sits in no implementation, and
    /// that is what says so: zero is a declaration like any other, so the
    /// absence has to be in the type rather than in a companion field a reader
    /// has to know to consult.
    impl: DeclId = .none,
    impl_args: []const TypeId = &.{},

    /// A type this copy carries, with its arguments in it.
    pub fn through(
        self: Instantiation,
        pool: *Typing.Builder,
        t: TypeId,
    ) std.mem.Allocator.Error!TypeId {
        const own = try pool.substitute(t, self.decl.index(), self.args);
        if (self.impl == .none) return own;
        return pool.substitute(own, self.impl.index(), self.impl_args);
    }
};

/// A literal's checked semantic value. Floating-point rounding belongs to
/// checking; conversion to an instruction's bit representation belongs to MIR.
pub const LiteralValue = union(enum) {
    integer: i128,
    float: f64,
};

pub const ImplementationId = enum(u32) {
    _,

    pub fn index(self: ImplementationId) usize {
        return @intFromEnum(self);
    }
};

const SelectionKey = struct {
    scope: DeclId = .none,
    trait: DeclId,
    args: []const TypeId,
    receiver: TypeId,

    const Context = struct {
        pub fn hash(_: Context, key: SelectionKey) u64 {
            var h = std.hash.Wyhash.init(@intFromEnum(key.trait));
            h.update(std.mem.asBytes(&key.scope));
            const receiver: u32 = @intFromEnum(key.receiver);
            h.update(std.mem.asBytes(&receiver));
            h.update(std.mem.sliceAsBytes(key.args));
            return h.final();
        }

        pub fn eql(_: Context, a: SelectionKey, b: SelectionKey) bool {
            return a.scope == b.scope and a.trait == b.trait and a.receiver == b.receiver and std.mem.eql(TypeId, a.args, b.args);
        }
    };
};

pub const ImplementationSupplier = union(enum) {
    declared: ImplementationId,
    bound,
    closure_release,
};

pub const ImplementationChoice = struct {
    supplier: ImplementationSupplier,
    receiver: TypeId,
    impl_args: []const TypeId = &.{},
    /// The trait's arguments the choice answers for: the selection's own key,
    /// so a trait's provided operation runs at the `K` of `Scale[K]` it was
    /// reached through. Set where the choice is recorded, and owned by that
    /// record.
    trait_args: []const TypeId = &.{},
    observations: u32 = 0,
    /// Names the `Slice` view that the array the observations reach answers
    /// through, and is `.poison` where it answers for itself. The supplier is then the view's
    /// implementation, and a call passes the view of each whole-`Self`
    /// argument to it.
    view: TypeId = .poison,

    /// Returns the type the supplying implementation runs for: the view where
    /// the receiver answers through one, and the receiver otherwise.
    pub fn implementedFor(self: ImplementationChoice) TypeId {
        return if (self.view != .poison) self.view else self.receiver;
    }

    pub fn declaredImplementation(self: ImplementationChoice) ?ImplementationId {
        return switch (self.supplier) {
            .declared => |implementation| implementation,
            .bound, .closure_release => null,
        };
    }
};

const Selections = std.HashMapUnmanaged(SelectionKey, ?ImplementationChoice, SelectionKey.Context, std.hash_map.default_max_load_percentage);

/// Concrete implementation answers retained with the type IDs that key them.
/// A missing key is unanswered; a present null records that no row answers it.
pub const ImplementationSelections = struct {
    rows: Selections = .empty,

    pub fn lookup(self: *const ImplementationSelections, trait: DeclId, args: []const TypeId, receiver: TypeId) ??ImplementationId {
        const row = self.rows.get(.{ .trait = trait, .args = args, .receiver = receiver }) orelse return null;
        return @as(?ImplementationId, if (row) |choice| choice.declaredImplementation() else null);
    }

    pub fn receiverOf(self: *const ImplementationSelections, trait: DeclId, args: []const TypeId, receiver: TypeId) ?TypeId {
        return (self.choiceOf(trait, args, receiver) orelse return null).receiver;
    }

    pub fn choiceOf(self: *const ImplementationSelections, trait: DeclId, args: []const TypeId, receiver: TypeId) ?ImplementationChoice {
        return self.rows.get(.{ .trait = trait, .args = args, .receiver = receiver }) orelse null;
    }

    fn record(self: *ImplementationSelections, gpa: std.mem.Allocator, scope: DeclId, trait: DeclId, args: []const TypeId, receiver: TypeId, choice: ?ImplementationChoice) !?ImplementationChoice {
        var retained = choice;
        if (retained) |*value| value.impl_args = try gpa.dupe(TypeId, value.impl_args);
        errdefer if (retained) |value| gpa.free(value.impl_args);
        const entry = try self.rows.getOrPut(gpa, .{ .scope = scope, .trait = trait, .args = args, .receiver = receiver });
        if (entry.found_existing) {
            if (entry.value_ptr.*) |value| gpa.free(value.impl_args);
        } else {
            // The lookup borrowed the caller's arguments; the row keeps its own.
            entry.key_ptr.args = gpa.dupe(TypeId, args) catch |err| {
                self.rows.removeByPtr(entry.key_ptr);
                return err;
            };
        }
        if (retained) |*value| value.trait_args = entry.key_ptr.args;
        entry.value_ptr.* = retained;
        return retained;
    }

    fn clone(self: *const ImplementationSelections, gpa: std.mem.Allocator) !ImplementationSelections {
        var out: ImplementationSelections = .{};
        errdefer out.deinit(gpa);
        var it = self.rows.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            _ = try out.record(gpa, key.scope, key.trait, key.args, key.receiver, entry.value_ptr.*);
        }
        return out;
    }

    fn deinit(self: *ImplementationSelections, gpa: std.mem.Allocator) void {
        var entries = self.rows.iterator();
        while (entries.next()) |entry| {
            gpa.free(entry.key_ptr.args);
            if (entry.value_ptr.*) |value| gpa.free(value.impl_args);
        }
        self.rows.deinit(gpa);
        self.* = .{};
    }
};

/// A variant's position within its enum, preserved by generic substitution.
pub const VariantOrdinal = enum(u32) { _ };

pub const VariantIdentity = struct {
    receiver: TypeId,
    ordinal: VariantOrdinal,
};

/// A context-dependent variant reference or enum match arm. Payload disposal
/// describes what a match arm leaves unnamed; references discard no payload.
pub const VariantUse = struct {
    ordinal: VariantOrdinal,
    drops_payload: bool = false,
};

/// The position within its enum of the variant the expression `id` selects.
/// `qualified` holds the selections the resolver settled from the written
/// path, such as `Colour.Red`, and `contextual` the ones the checker settled
/// from the surrounding type, such as `.Red` and a pattern's variant. Every
/// reader asks here, so none can disagree about which table answers.
pub fn variantOrdinalOf(
    qualified: *const std.AutoHashMapUnmanaged(ExprId, VariantOrdinal),
    contextual: *const std.AutoHashMapUnmanaged(ExprId, VariantUse),
    id: ExprId,
) ?u32 {
    if (qualified.get(id)) |ordinal| return @intFromEnum(ordinal);
    const use = contextual.get(id) orelse return null;
    return @intFromEnum(use.ordinal);
}

test variantOrdinalOf {
    const gpa = testing.allocator;
    var qualified: std.AutoHashMapUnmanaged(ExprId, VariantOrdinal) = .empty;
    defer qualified.deinit(gpa);
    var contextual: std.AutoHashMapUnmanaged(ExprId, VariantUse) = .empty;
    defer contextual.deinit(gpa);
    try qualified.put(gpa, ExprId.at(1), @enumFromInt(4));
    try contextual.put(gpa, ExprId.at(2), .{ .ordinal = @enumFromInt(7) });
    try testing.expectEqual(@as(?u32, 4), variantOrdinalOf(&qualified, &contextual, ExprId.at(1)));
    try testing.expectEqual(@as(?u32, 7), variantOrdinalOf(&qualified, &contextual, ExprId.at(2)));
    try testing.expectEqual(@as(?u32, null), variantOrdinalOf(&qualified, &contextual, ExprId.at(3)));
}

pub const constants = @import("constants.zig");
const OpenTypes = @import("open_types.zig").OpenTypes;
pub const ConstantMaterializationKey = struct { value: constants.ConstantId, ty: TypeId };
pub const ConstantMaterialization = struct { fields: []const FieldOrdinal = &.{}, variant: ?VariantOrdinal = null };
pub const ConstantMaterializations = std.AutoHashMapUnmanaged(ConstantMaterializationKey, ConstantMaterialization);

pub const ConstantValue = @import("constfold.zig").CheckedValue;

/// Diagnostic names bound expanded DAG text; semantic keys and symbol
/// spelling continue to use the complete structural type.
const TypeDisplay = struct {
    const byte_limit = 2048;
    const ellipsis = "…";
    text: std.ArrayList(u8) = .empty,
    shortened: bool = false,

    fn appendSlice(self: *TypeDisplay, gpa: std.mem.Allocator, text: []const u8) !void {
        if (self.shortened) return;
        const available = byte_limit - ellipsis.len - self.text.items.len;
        if (text.len <= available) {
            try self.text.appendSlice(gpa, text);
            return;
        }
        var end = available;
        while (end > 0 and text[end] & 0xc0 == 0x80) : (end -= 1) {}
        try self.text.appendSlice(gpa, text[0..end]);
        self.shortened = true;
    }

    fn append(self: *TypeDisplay, gpa: std.mem.Allocator, byte: u8) !void {
        try self.appendSlice(gpa, &.{byte});
    }

    fn finish(self: *TypeDisplay, gpa: std.mem.Allocator) ![]u8 {
        if (self.shortened) try self.text.appendSlice(gpa, ellipsis);
        return self.text.toOwnedSlice(gpa);
    }
};

/// What an interpolation literal does with the value piece it was written
/// with, decided once where the literal is checked.
pub const PiecePosition = enum {
    /// A place that cannot be copied, or a value that must be settled, is
    /// observed: the literal holds a `borrow` of it.
    borrowed,
    /// A value that can be copied is held as a copy; a place it names stays
    /// the program's.
    copied,
    /// A computed value nothing else owns is built into the literal.
    moved,
};

/// What the type checker produces: the pool of types, and the type of each
/// expression. Named `Typing` rather than `Types` because only the first of
/// those is types.
pub const Typing = struct {
    capabilities: []const Capability = &.{},
    scoped_capabilities: ScopedCapabilityMap = .empty,
    prepared_implementations: PreparedImplementations = .{},
    field_name_spellings: std.AutoHashMapUnmanaged(StringId, []const u8) = .empty,
    implementation_selections: ImplementationSelections = .{},
    /// Checked numeric literals, scalar range ends, and negated integer literals.
    literal_values: std.AutoHashMapUnmanaged(ExprId, LiteralValue) = .empty,
    conversion_targets: std.AutoHashMapUnmanaged(ExprId, TypeId) = .empty,
    integer_properties: std.AutoHashMapUnmanaged(ExprId, IntegerProperty) = .empty,
    /// Resolved field and index types, independent of contextual type
    /// mismatches. Rejected selection steps have no entry.
    selected_places: std.AutoHashMapUnmanaged(ExprId, TypeId) = .empty,
    place_projections: std.AutoHashMapUnmanaged(ExprId, PlaceProjection) = .empty,
    implicit_test_successes: std.AutoHashMapUnmanaged(ExprId, TypeId) = .empty,
    /// Every `?` that converts its error through `From`. A `?` absent here
    /// returns its operand's error unchanged.
    try_conversions: std.AutoHashMapUnmanaged(ExprId, TryConversion) = .empty,
    field_names: std.AutoHashMapUnmanaged(TokenId, FieldIdentity) = .empty,
    /// The parameters a call through each local or capture holding a
    /// callable names its arguments by, where something declared them.
    binding_labels: std.AutoHashMapUnmanaged(ids.BindingId, node.ParamRange) = .empty,
    /// Associated selection facts keyed by the written dot, including recovery.
    type_selections: std.AutoHashMapUnmanaged(TokenId, TypeSelection) = .empty,
    contract_variants: std.AutoHashMapUnmanaged(TokenId, VariantIdentity) = .empty,
    readonly_places: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    carried_places: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// Every borrowed value that is not a place: an argument to a parameter
    /// whose place the result borrows, or an interpolated value that must be
    /// settled and so cannot be held by the literal. Each is evaluated into a
    /// temporary. Lowering gives it a slot and ownership ends it with its
    /// statement. A constant is a place and is never one.
    borrowed_temporaries: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// What each value piece of an interpolation literal does with what it
    /// names. A piece the checker refused is absent.
    interpolation_positions: std.AutoHashMapUnmanaged(ExprId, PiecePosition) = .empty,
    /// Expressions the checker built no value for, because it refused them:
    /// an unresolvable head, a sealed type, a field the type lacks, a value
    /// that does not fit. An expression whose value was built and merely
    /// does not fit its context is absent, though its recorded type is
    /// poison too.
    refused: std.AutoHashMapUnmanaged(ExprId, void) = .empty,
    /// The whole number each accepted bracket's index operand folds to, keyed
    /// by the operand, or by the count under a `^`. An operand that folds to
    /// nothing, or to a negative number, is absent.
    folded_indices: std.AutoHashMapUnmanaged(ExprId, u64) = .empty,
    dependency_containment: []const bool = &.{},
    writer_containment: []const bool = &.{},
    observation_traits: []const bool = &.{},
    /// Checked values of accepted module and implementation constants. Binding
    /// and expression types retain their nominal identity.
    /// One row per constant, regardless of how many references reach it.
    constant_values: std.AutoHashMapUnmanaged(ids.BindingId, ConstantValue) = .empty,
    constant_texts: []const []const u8 = &.{},
    constant_pool: constants.Pool = .{},
    constant_materializations: ConstantMaterializations = .empty,
    /// Frozen expression records indexed once over the expanded AST. Type-pool
    /// views carry no expression index; later passes borrow the checked Typing.
    call_index: CallIndex = .{},
    /// Interned; each distinct type appears exactly once.
    pool: []const Type,
    /// Every enum's variants, concatenated; each descriptor holds a range.
    variants: VariantColumns,
    /// Every structure's fields, and what each variant carries, concatenated.
    fields: FieldColumns,
    /// Interpolation records and their compact piece and format runs. The
    /// lookup is keyed by `TypeId`; format storage has one row per embedded
    /// value rather than one per field or per type.
    interpolations: []const Interpolated = &.{},
    interpolation_pieces: []const TypeId = &.{},
    interpolation_formats: []const node.InterpolationFormat = &.{},
    /// Whether each embedded value is borrowed rather than held, in the rows
    /// of `interpolation_formats`. The checker decides it once per piece.
    interpolation_borrows: []const bool = &.{},
    interpolation_of: []const u32 = &.{},
    /// Every structural callable's parameters, concatenated; each descriptor
    /// holds a range so growing the table never invalidates a pool entry.
    callable_params: []const CallableParam = &.{},
    closure_args: []const TypeId = &.{},
    closures: []const ClosureDescriptor = &.{},
    closure_release: ?ClosureRelease = null,
    /// The checker's open-type table while a check is under way, so a lookup
    /// reads an integer literal's type through what it settled on. Null in a
    /// finished typing, where no recorded type holds an open integer.
    open_types: ?*OpenTypes = null,
    /// Private storage declarations resolved once for this compilation.
    raw_accesses: @import("intrinsics.zig").RawAccesses = .{},
    /// The prelude's `Tuple2` through `Tuple8`, by arity, or `.none` where it
    /// publishes none. An instantiation of one is spelled `(A, B)`, and a
    /// builder reopened from this pool spells the instances it mints the same
    /// way, so a symbol and a report name one tuple alike before and after
    /// monomorphisation.
    tuple_decls: [node.max_tuple_arity - 1]DeclId = [_]DeclId{DeclId.none} ** (node.max_tuple_arity - 1),
    /// Trusted scalar math declarations with fully validated signatures.
    float_math: @import("intrinsics.zig").FloatMath = .{},
    expr_types: []const TypeId,
    /// The aggregate a literal was constructing even when an operand made the
    /// literal itself `Never`.
    construction_types: []const TypeId = &.{},
    /// One complete semantic row per accepted call to an existing callable.
    calls: []const NormalizedCall = &.{},
    /// Written argument facts retained only for resolved calls checking refused.
    recovered_call_args: []const RecoveredCallArg = &.{},
    /// Call-level targets retained for those same rejected calls.
    recovered_calls: []const RecoveredCall = &.{},
    /// Contextual conversions from a source body to one structural code pointer.
    function_values: []const FunctionValue = &.{},
    /// Every implementation the program declares, by trait and type, paired
    /// with the index built from this list in the same order.
    implementations: []const Implementation = &.{},
    impl_index: ImplIndex = .{},
    /// Which implementation each declaration sits inside, as a row of
    /// `implementations`, or `no_implementation`.
    ///
    /// A member is written inside an `impl` and carries no handle to it, so a
    /// reader that wanted the pair walked every implementation's extent -- once
    /// per member for the checker and once more for lowering, which is the same
    /// walk done twice over one program. Filled where the implementations are
    /// collected, and read by whoever holds the typing.
    impl_of_decl: []const u32 = &.{},
    /// Generated members whose bodies semantic recovery did not type-check.
    suppressed_generated_bodies: []const DeclId = &.{},
    /// Which member of an implementation supplies each signature its trait
    /// declares.
    ///
    /// The pair the checker settles when it discharges an implementation,
    /// recorded rather than left to be matched again: a member is named by the
    /// signature it supplies, so every reader that found it by that name was a
    /// second implementation of one relation.
    supply_index: SupplyIndex = .{},
    /// Every bracket that names a place through an implementation, and the
    /// expansion each becomes. Empty for a program whose brackets are all over
    /// arrays.
    projected: []const Projected = &.{},
    /// Every lending walk over a type that declares a traversal, and the `trav`
    /// member each found. Empty for a program whose lending walks are all over
    /// arrays, whose positions the compiler carries.
    traversals: []const Traversal = &.{},
    traversal_positions: std.AutoHashMapUnmanaged(DeclId, TraversalPositions) = .empty,
    /// The path each of those implementations' projections names, one entry
    /// per implementation however many brackets reach it.
    expansions: []const Expansion = &.{},
    expansion_of_impl: std.AutoHashMapUnmanaged(DeclId, u32) = .empty,
    /// For each `extern` declaration that repeats a symbol an earlier one
    /// declared, that earlier declaration. Every declaration of one symbol
    /// names one runtime function, so they share one instance.
    extern_symbols: std.AutoHashMapUnmanaged(DeclId, DeclId) = .empty,
    /// Every bracket whose index is a range, and where the run of elements each
    /// names begins.
    range_places: []const RangePlace = &.{},
    /// Source spelling data for calls written in postfix form.
    postfix: []const Postfix = &.{},
    /// Which parameter each written argument name named, in the order the names
    /// were written.
    named: []const Named = &.{},
    /// Contract root tokens paired with the parameter tokens that typing matched.
    /// Structural callable parameters need not declare resolver bindings.
    contract_parameters: std.AutoHashMapUnmanaged(TokenId, TokenId) = .empty,
    /// Declarations whose result contract was left undecided: inference found
    /// several sources, or the trait signature a member adopts from did. The
    /// ambiguity is reported, and the body is not checked against a contract.
    declined_contracts: std.AutoHashMapUnmanaged(DeclId, void) = .empty,
    /// Each implementation member written without a clause, with the trait
    /// signature whose contract it adopts.
    adopted_contracts: std.AutoHashMapUnmanaged(DeclId, DeclId) = .empty,
    /// Each function a written callable type or a callable bound received as
    /// a value, with that type, whether or not the function fit it: the
    /// function answers to that type's signature, so its own cannot gain a
    /// clause the type does not have.
    fixed_functions: std.AutoHashMapUnmanaged(DeclId, FixedFunction) = .empty,
    /// Each function that wrote no clause and took its contract from its one
    /// carrier parameter, with that parameter's position.
    defaulted_contracts: std.AutoHashMapUnmanaged(DeclId, u32) = .empty,
    /// The type each `alias` names, keyed by the alias. Read by tooling
    /// that shows what an alias stands for; every written use of one was
    /// already answered with this type where it was checked.
    aliased: std.AutoHashMapUnmanaged(DeclId, TypeId) = .empty,
    /// What each defaulted parameter is worth, folded once where it is
    /// declared and spliced into every call that omits it.
    defaults: Defaults = .{},
    /// The pool's own bookkeeping: which declaration each declared type came
    /// from, and what each instantiation was made of. Carried because the pool
    /// is an intern table rather than a finished representation -- lowering
    /// substitutes concrete arguments into a declaration the checker already
    /// proved well-formed, and needs both to do it.
    templates: []const Template = &.{},
    /// Where each type's entry in `templates` sits, by `TypeId`, or
    /// `not_a_template`. The other direction from `templateOf`, which searches
    /// by declaration: a symbol is mangled from a type and asks which
    /// declaration it came from, once per type named, and the list grows with
    /// the declared types -- so a walk was those two multiplied.
    template_of: []const u32 = &.{},
    /// What each module is called where a symbol carries it, by module id.
    ///
    /// The path a reader writes, dotted: `std.text`, with each byte of a
    /// directory name that no identifier holds escaped as `$` and two hex
    /// digits, so `my-lib` is `my$2dlib` and the one directory `a.b` is
    /// `a$2eb`, apart from the two directories `a/b`. A program's own
    /// directory `std/mem` is `$73td.mem`, apart from the library's
    /// `std.mem`. Filled by the pass that holds the program, because a type
    /// pool does not -- and a path rather than the module's index, because an
    /// index says which module was loaded first. Adding an import renumbered
    /// every symbol below it, which is a name nobody can predict and an
    /// emitted module the outcome cache had never seen.
    module_paths: []const []const u8 = &.{},
    instances: []const Instance = &.{},
    instance_args: []const TypeId = &.{},
    /// Where each type's entry in `instances` sits, by `TypeId`, or `not_an
    /// _instance`. Shorter than the pool wherever the types minted after the
    /// last instantiation are: a type past the end is one no instantiation
    /// named, which is the same answer the table gives.
    instance_of: []const u32 = &.{},
    /// The spellings minted for instantiations, which this pool frees. A pool
    /// reopened from another shares its entries and owns none of its names.
    owned_names: []const []const u8 = &.{},
    owned_contracts: []const []const CallableContract = &.{},
    /// The bound lists the pool's parameters point at, owned for the reason the
    /// names are: a parameter carries the traits its bounds name, and nothing
    /// outside the pool holds that list.
    owned_bounds: []const []const BoundTrait = &.{},
    owned_callable_bounds: []const []const TypeId = &.{},
    /// What `^k` is a value of, or `.poison` where no library declares one.
    ///
    /// The checker settles which declaration the prelude's `FromEnd` is and
    /// interns it; lowering reads that answer here rather than asking what a
    /// type is named, so what a bracket was checked as and what it is emitted
    /// as cannot come apart.
    from_end: TypeId = .poison,
    /// The type of each binding, indexed by `BindingId`.
    ///
    /// Kept rather than discarded. Lowering has to know how wide a slot is,
    /// and a parameter's annotation is a token: reading a declared type back
    /// out of one would make the backend answer a question about names that
    /// the checker had already answered.
    binding_types: BindingTypes,
    /// What each function was written to return, indexed by declaration.
    ///
    /// Kept for the reason `binding_types` is kept and for the same reader. A
    /// declared return type is named by a token, and which type that names is a
    /// question this pass answered; working it out again below would be a
    /// second answer to it.
    ///
    /// The type of the *body* is not the same question and is not a substitute
    /// for it. A body whose value leaves only through `return` has a block type
    /// that is not what the function yields, and a value too wide for a
    /// register is then handed back by the convention for one that is not.
    decl_returns: Returns,
    /// Each function declaration's exact structural signature before substitution.
    decl_signatures: Signatures = .empty,
    /// The capability each declared type's bounds demand, indexed by
    /// declaration, and Linear for every declaration that is not one.
    ///
    /// A projection stands for whatever an implementation settled, and a
    /// capability bound is discharged where the settling happens -- so the
    /// bound is what every settling the projection can stand for has in
    /// common, and what the projection itself owes. Read from here rather
    /// than from the bounds again, because a projection is interned once and
    /// its capability is settled where it is minted.
    declared_requirements: []const CapabilityRequirement = &.{},
    /// The traits each declared type's bounds name, by declaration. The other
    /// half of the same promise, read from here for the same reason.
    declared_traits: []const []const BoundTrait = &.{},
    /// The structural callable signatures each declared type promises.
    declared_callables: []const []const TypeId = &.{},
    /// Capability promises active only while their declaring generic body is
    /// checked, indexed first by declaration and then by subject type.
    contextual_constraints: ContextualConstraints = .{},
    /// What each pool entry was already laid out as. Empty means every query
    /// recomputes, which is what a typing built by hand gets.
    laid_out: []StampedLayout = &.{},
    /// `Arrangement.offsets` and its companions, sized with `fields`, and the
    /// generation their stamps are read against.
    offsets: []u32 = &.{},
    placed_at: []u32 = &.{},
    generation: u32 = 1,
    /// Each run's parts in name order, and whether that order has been worked
    /// out. Sized with `fields`, like the offsets beside it.
    by_name: []u32 = &.{},
    sorted: []bool = &.{},
    /// Context-dependent variants and enum arms keyed by expanded expression
    /// IDs. Storage is O(V) for V uses; lookup is expected O(1). Qualified
    /// references remain in Resolution, which settled them before checking.
    variant_uses: std.AutoHashMapUnmanaged(ExprId, VariantUse) = .empty,
    /// What each written type reference settled to, keyed by the token that
    /// wrote it. `.poison` where that token wrote no type, which is also what
    /// a refused one settles to -- neither has a name worth printing.
    written_types: []const TypeId = &.{},
    /// Every settled reference awaiting an instantiation, and the run of trait
    /// arguments each one's key holds.
    ///
    /// Carried because substitution is what settles one, and substitution runs
    /// again in lowering: a body checked once holds these, and each
    /// instantiation replaces them with what the implementation it names
    /// settled.
    standins: []const Standin = &.{},
    standin_args: []const TypeId = &.{},
    /// Which entry of `standins` each type is, by `TypeId`, or `not_a_standin`.
    /// Shorter than the pool wherever types were minted after the last standin
    /// was; a type past the end is one no settled reference stands for, which
    /// is the same answer the table gives.
    standin_of: []const u32 = &.{},

    /// Whether this arm's pattern names none of what the variant it selects
    /// carries.
    pub fn dropsPayload(self: *const Typing, pattern: ExprId) bool {
        const arm = self.variant_uses.get(pattern) orelse return false;
        return arm.drops_payload;
    }

    /// The type a written reference settled to, or null where that token
    /// wrote none.
    ///
    /// Read rather than worked out again. Which instantiation a written type
    /// became is the fixed point the checker ran, and an argument written as
    /// one of the declaration's own parameters was settled before any name was
    /// built from it -- neither is recoverable from the source alone.
    pub fn writtenType(self: *const Typing, at: u32) ?TypeId {
        if (at >= self.written_types.len) return null;
        const ty = self.written_types[at];
        return if (ty == .poison) null else ty;
    }

    /// The arrays a layout is read from, with the answers already given.
    fn arrangement(self: *const Typing) Arrangement {
        return .{
            .pool = self.pool,
            .fields = self.fields,
            .variants = self.variants,
            .laid_out = self.laid_out,
            .offsets = self.offsets,
            .placed_at = self.placed_at,
            .generation = self.generation,
        };
    }

    pub fn integerProperty(self: *const Typing, expression: ExprId) ?IntegerProperty {
        return self.integer_properties.get(expression);
    }

    /// Choose the library routine a format spec lays a value of this type out
    /// through: the one for integers, the one for Float64, or the one that
    /// pads any value's rendered text.
    ///
    /// The routine gives one answer to two askers at two times. The checker asks inside a
    /// generic body, where a parameter bounded by `Integer` is an integer, to
    /// refuse number parts on a value that is not a number; discovery and
    /// lowering ask once the type is concrete, to choose the routine.
    pub fn layoutShape(self: *const Typing, owner: DeclId, t: TypeId) LayoutShape {
        if (t == .f64) return .float;
        if (self.isIntegerWithin(owner, t)) return .integer;
        return .general;
    }

    test "a value's type chooses how a format spec lays it out" {
        const gpa = testing.allocator;
        var building = try Typing.Builder.init(gpa);
        defer building.deinit();
        const plain = try building.addParameter("T", 7, 0, .unrestricted, &.{});
        const counted = try building.addParameter("N", 7, 1, .unrestricted, &.{});
        building.pool.items[@intFromEnum(counted)].parameter.integer = true;
        const literal = try building.openInteger(0);

        const view = building.view();
        try testing.expectEqual(LayoutShape.integer, view.layoutShape(DeclId.none, .u8));
        try testing.expectEqual(LayoutShape.integer, view.layoutShape(DeclId.none, .i64));
        try testing.expectEqual(LayoutShape.integer, view.layoutShape(DeclId.none, literal));
        try testing.expectEqual(LayoutShape.integer, view.layoutShape(DeclId.at(7), counted));
        try testing.expectEqual(LayoutShape.float, view.layoutShape(DeclId.none, .f64));
        try testing.expectEqual(LayoutShape.general, view.layoutShape(DeclId.none, .bool_));
        try testing.expectEqual(LayoutShape.general, view.layoutShape(DeclId.at(7), plain));
    }

    pub fn isIntegerWithin(self: *const Typing, owner: DeclId, t: TypeId) bool {
        if (t.integerInfo() != null) return true;
        // An integer literal whose type no use has settled yet is an integer
        // whichever type it settles on.
        if (self.get(t) == .open_integer) return true;
        if (self.get(t) == .parameter and self.get(t).parameter.integer) return true;
        return self.contextual_constraints.requiresInteger(owner, t);
    }

    pub fn conversionTarget(self: *const Typing, expression: ExprId) ?TypeId {
        return self.conversion_targets.get(expression);
    }

    pub fn literalValue(self: *const Typing, expression: ExprId) ?LiteralValue {
        return self.literal_values.get(expression);
    }

    pub fn constantValue(self: *const Typing, binding: ids.BindingId) ?ConstantValue {
        return self.constant_values.get(binding);
    }

    /// The slot a settled index names in an array of `count` elements, or null
    /// where no element sits there. `value` counts from the front, or back from
    /// the end when `from_end`, where the last element is count 1. The checker,
    /// lowering and ownership all ask here, so one rule decides what an
    /// in-range constant is.
    pub fn elementSlot(count: u64, value: u64, from_end: bool) ?u64 {
        if (from_end) return if (value >= 1 and value <= count) count - value else null;
        return if (value < count) value else null;
    }

    test elementSlot {
        try testing.expectEqual(@as(?u64, 1), elementSlot(3, 1, false));
        try testing.expectEqual(@as(?u64, null), elementSlot(3, 3, false));
        try testing.expectEqual(@as(?u64, 2), elementSlot(3, 1, true));
        try testing.expectEqual(@as(?u64, 0), elementSlot(3, 3, true));
        try testing.expectEqual(@as(?u64, null), elementSlot(3, 0, true));
        try testing.expectEqual(@as(?u64, null), elementSlot(3, 4, true));
        try testing.expectEqual(@as(?u64, null), elementSlot(0, 0, false));
    }

    /// The number a bracket's index operand folds to, as the checker settled
    /// it, or null where it settled none. Ownership and lowering ask here
    /// instead of folding the operand again.
    pub fn foldedIndex(self: *const Typing, operand: ExprId) ?u64 {
        return self.folded_indices.get(operand);
    }

    test foldedIndex {
        const gpa = testing.allocator;
        var typing: Typing = .{
            .binding_types = .empty,
            .decl_returns = .empty,
            .pool = &.{},
            .variants = .empty,
            .fields = .empty,
            .expr_types = &.{},
            .calls = &.{},
        };
        defer typing.folded_indices.deinit(gpa);
        try typing.folded_indices.put(gpa, ExprId.at(3), 7);
        try testing.expectEqual(@as(?u64, 7), typing.foldedIndex(ExprId.at(3)));
        try testing.expectEqual(@as(?u64, null), typing.foldedIndex(ExprId.at(4)));
    }

    pub fn deinit(self: *Typing, gpa: std.mem.Allocator) void {
        self.field_name_spellings.deinit(gpa);
        self.implementation_selections.deinit(gpa);
        self.literal_values.deinit(gpa);
        self.conversion_targets.deinit(gpa);
        self.integer_properties.deinit(gpa);
        self.selected_places.deinit(gpa);
        self.place_projections.deinit(gpa);
        self.implicit_test_successes.deinit(gpa);
        self.try_conversions.deinit(gpa);
        self.field_names.deinit(gpa);
        self.binding_labels.deinit(gpa);
        self.type_selections.deinit(gpa);
        self.contract_variants.deinit(gpa);
        self.readonly_places.deinit(gpa);
        self.carried_places.deinit(gpa);
        self.borrowed_temporaries.deinit(gpa);
        self.interpolation_positions.deinit(gpa);
        self.refused.deinit(gpa);
        self.folded_indices.deinit(gpa);
        gpa.free(self.dependency_containment);
        gpa.free(self.writer_containment);

        gpa.free(self.observation_traits);
        self.constant_values.deinit(gpa);
        self.constant_pool.deinit(gpa);
        var materializations = self.constant_materializations.valueIterator();
        while (materializations.next()) |plan| gpa.free(plan.fields);
        self.constant_materializations.deinit(gpa);
        for (self.constant_texts) |bytes| gpa.free(bytes);
        gpa.free(self.constant_texts);
        self.call_index.deinit(gpa);
        gpa.free(self.laid_out);
        gpa.free(self.offsets);
        gpa.free(self.placed_at);
        gpa.free(self.by_name);
        gpa.free(self.sorted);
        gpa.free(self.pool);
        self.variants.deinit(gpa);
        self.fields.deinit(gpa);
        gpa.free(self.interpolations);
        gpa.free(self.interpolation_pieces);
        gpa.free(self.interpolation_formats);
        gpa.free(self.interpolation_borrows);
        gpa.free(self.interpolation_of);
        gpa.free(self.callable_params);
        gpa.free(self.closure_args);
        for (self.closures) |closure| gpa.free(closure.owned_fields);
        gpa.free(self.closures);
        gpa.free(self.expr_types);
        gpa.free(self.construction_types);
        for (self.calls) |call| call.deinit(gpa);
        gpa.free(self.calls);
        gpa.free(self.recovered_call_args);
        gpa.free(self.recovered_calls);
        for (self.function_values) |value| value.deinit(gpa);
        gpa.free(self.function_values);
        for (self.implementations) |i| {
            if (i.args.len > 0) gpa.free(i.args);
            for (i.predicates) |predicate| {
                freeBoundTraits(gpa, predicate.demand.traits);
                if (predicate.demand.callables.len > 0) gpa.free(predicate.demand.callables);
            }
            if (i.predicates.len > 0) gpa.free(i.predicates);
        }
        gpa.free(self.implementations);
        gpa.free(self.impl_of_decl);
        gpa.free(self.suppressed_generated_bodies);
        self.impl_index.deinit(gpa);
        self.supply_index.deinit(gpa);
        for (self.projected) |row| gpa.free(row.impl_args);
        gpa.free(self.projected);
        for (self.traversals) |row| gpa.free(row.impl_args);
        gpa.free(self.traversals);
        self.traversal_positions.deinit(gpa);
        for (self.expansions) |row| if (row.delegation) |delegation| gpa.free(delegation.backing_args);
        gpa.free(self.expansions);
        self.expansion_of_impl.deinit(gpa);
        self.extern_symbols.deinit(gpa);
        gpa.free(self.range_places);
        for (self.postfix) |p| gpa.free(p.args);
        gpa.free(self.postfix);
        gpa.free(self.named);
        self.contract_parameters.deinit(gpa);
        self.declined_contracts.deinit(gpa);
        self.adopted_contracts.deinit(gpa);
        self.fixed_functions.deinit(gpa);
        self.defaulted_contracts.deinit(gpa);
        self.aliased.deinit(gpa);
        self.defaults.deinit(gpa);
        gpa.free(self.templates);
        gpa.free(self.template_of);
        gpa.free(self.instances);
        gpa.free(self.instance_args);
        gpa.free(self.instance_of);
        for (self.owned_names) |n| gpa.free(n);
        gpa.free(self.owned_names);
        for (self.owned_contracts) |contracts| freeContracts(gpa, contracts);
        gpa.free(self.owned_contracts);
        // Freed here and nowhere else, as the tables a reopened builder borrows
        // are: `borrowTables` hands on the pointer and a view is never released,
        // so the pool this was filled for is the one owner there is.
        for (self.module_paths) |m| gpa.free(m);
        gpa.free(self.module_paths);
        for (self.owned_bounds) |b| freeBoundTraits(gpa, b);
        gpa.free(self.owned_bounds);
        for (self.owned_callable_bounds) |b| gpa.free(b);
        gpa.free(self.owned_callable_bounds);
        self.binding_types.deinit(gpa);
        self.decl_returns.deinit(gpa);
        self.decl_signatures.deinit(gpa);
        gpa.free(self.declared_requirements);
        gpa.free(self.capabilities);
        self.scoped_capabilities.deinit(gpa);
        self.prepared_implementations.deinit(gpa);
        for (self.declared_traits) |t| freeBoundTraits(gpa, t);
        gpa.free(self.declared_traits);
        for (self.declared_callables) |c| if (c.len > 0) gpa.free(c);
        gpa.free(self.declared_callables);
        self.contextual_constraints.deinit(gpa);
        gpa.free(self.written_types);
        self.variant_uses.deinit(gpa);
        gpa.free(self.standins);
        gpa.free(self.standin_args);
        gpa.free(self.standin_of);

        self.* = undefined;
    }

    /// How a type is spelled in a diagnostic.
    ///
    /// A declared type's name lives in the pool, so this is the spelling a
    /// message uses wherever one is to hand. `TypeId.nameOf` answers for the
    /// builtins alone, and says `<compound>` for anything else.
    pub fn nameOf(self: *const Typing, t: TypeId) []const u8 {
        return switch (self.get(t)) {
            .enum_ => |e| e.name,
            .struct_ => |x| x.name,
            .newtype => |n| n.name,
            .array => |a| a.name,
            .callable => |c| c.name,
            .borrow => |b| b.name,
            .closure => "<closure>",
            .parameter => |p| p.name,
            // Named by the type it falls back to when no use settles it.
            .open_integer => TypeId.literal_default.nameOf(),
            // A type its uses have not chosen yet, written as a hole.
            .open_type => "_",
            else => t.nameOf(),
        };
    }

    /// Follow checked containment selectors in the actual instantiated result.
    pub fn contractTargetType(self: *const Typing, result: TypeId, target: []const ResultSelector) TypeId {
        var ty = result;
        for (target) |selector| switch (selector) {
            .field => |field| ty = self.fieldType(ty, field.index),
            .payload => |payload| ty = self.variantFieldType(ty, @intFromEnum(payload.variant), payload.index),
        };
        return ty;
    }

    pub fn callableParams(self: *const Typing, signature: CallableSignature) []const CallableParam {
        return self.callable_params[signature.first_param..][0..signature.param_count];
    }

    pub fn closureArgs(self: *const Typing, closure: ClosureType) []const TypeId {
        return self.closure_args[closure.first_arg..][0..closure.arg_count];
    }

    pub fn closureImplArgs(self: *const Typing, closure: ClosureType) []const TypeId {
        return self.closure_args[closure.first_arg + closure.arg_count ..][0..closure.impl_arg_count];
    }

    pub fn closureOf(self: *const Typing, closure: ids.ClosureId) ClosureDescriptor {
        return self.closures[closure.index()];
    }

    pub fn declSignature(self: *const Typing, decl: DeclId) TypeId {
        return self.decl_signatures.get(decl);
    }

    /// The type a newtype was declared over. Meaningless for anything else.
    pub fn baseOf(self: *const Typing, t: TypeId) TypeId {
        return self.get(t).newtype.base;
    }

    /// What a type is representationally: a newtype's base, and every other
    /// type itself.
    ///
    /// A newtype is a contract over a representation, and the contract is the
    /// checker's alone -- everything that arranges bytes reads the
    /// representation. The backend classifies a handle it is given, and one it
    /// cannot classify makes it guess: an unsigned load for a signed base, an
    /// unsigned division, an overflow guard elided entirely. So lowering
    /// erases the name and MIR carries none.
    ///
    /// Repeats, because a newtype may be written over another. A cycle is
    /// reported where the base is resolved and broken to poison there, so
    /// this terminates on every pool a program reaches lowering with.
    pub fn erased(self: *const Typing, t: TypeId) TypeId {
        var at = t;
        while (self.get(at) == .newtype) at = self.get(at).newtype.base;
        return at;
    }

    /// Whether a newtype's `where it in lo..=hi` clause was declared.
    pub fn isRefined(self: *const Typing, t: TypeId) bool {
        return self.get(t).newtype.refined;
    }

    /// A refined newtype's folded, inclusive bounds. Meaningless where
    /// `isRefined` answers false.
    pub fn refinementOf(self: *const Typing, t: TypeId) Refinement {
        const n = self.get(t).newtype;
        return .{ .lo = n.lo, .hi = n.hi };
    }

    /// Appends the module a type belongs to, where that is not the root.
    ///
    /// A declared name is only unique within its module, so the module joins
    /// it. Without this two modules declaring one name mangle alike, and one
    /// generic instantiated at both emits two functions under a single symbol.
    ///
    /// The path itself, dotted, so a type reads as the module a programmer
    /// names: `std.text.Str`. A type spelled this way is still one reading: a
    /// module path is followed by exactly one type name and then brackets, so
    /// the last unbracketed component is the type and everything before it
    /// the route. The root's route is empty, so its types are bare.
    ///
    /// A function's symbol does not use this for its own route: it ends the
    /// route with a separator, the root's empty one included, because there a
    /// name follows an owner and a route of dotted identifiers alike, and
    /// without the separator the two read the same.
    pub fn appendModule(
        self: *const Typing,
        gpa: std.mem.Allocator,
        out: *std.ArrayList(u8),
        module: u32,
    ) std.mem.Allocator.Error!void {
        if (module >= self.module_paths.len) return;
        const path = self.module_paths[module];
        if (path.len == 0) return;
        try out.appendSlice(gpa, path);
        try out.append(gpa, '.');
    }

    /// Appends what an instantiation was made with: how many arguments, and
    /// then each of them mangled.
    ///
    /// Bracketed, and separated by a comma, which is how a reader writes them.
    ///
    /// A count came first while the separator was a dot, because a dot appears
    /// inside a component already -- a module path carries one, and so does a
    /// nested instantiation -- so it could not say where one argument ended and
    /// the next began: `g.X.Y` was both `g[X, Y]` and `g[X[Y]]`.
    ///
    /// A bracket says it instead, by nesting, which is the property a dot does
    /// not have. The three shapes a count was needed to tell apart are three
    /// spellings: `g[X,Y]` is one list of two, `g[X][Y]` is two lists of one --
    /// which an inherent implementation generic over its head writes -- and
    /// `g[X[Y]]` is one list holding one nested argument. Each list keeps its
    /// own pair, so no two of them agree.
    ///
    /// No space after the comma. A symbol holding whitespace is one every tool
    /// reading a symbol table in columns has to be careful with, and the space
    /// buys nothing a bracket has not already said.
    ///
    /// One routine, because a type's name and a function's symbol are the same
    /// question asked of different heads. Two that agreed by construction is
    /// how the trait slot and the argument slot came to be one slot.
    pub fn appendArguments(
        self: *const Typing,
        gpa: std.mem.Allocator,
        out: *std.ArrayList(u8),
        args: []const TypeId,
    ) std.mem.Allocator.Error!void {
        if (args.len == 0) return;

        try out.append(gpa, '[');
        for (args, 0..) |a, i| {
            if (i > 0) try out.append(gpa, ',');
            try self.appendMangled(gpa, out, a);
        }
        try out.append(gpa, ']');
    }

    /// What a type is called where a symbol carries it.
    ///
    /// Injective, which is the whole of what is asked of it: two types with one
    /// name are two definitions of one symbol, which the assembler answers for
    /// and the module verifier catches first. So a type is spelled by its
    /// structure and never by a prefix of its written name -- stopping at the
    /// first `[` made `Option[Str]` and `Option[Bool]` one name wherever the
    /// type was not an instantiation the pool could take apart, and made every
    /// array the empty string.
    pub fn mangledName(
        self: *const Typing,
        gpa: std.mem.Allocator,
        t: TypeId,
    ) std.mem.Allocator.Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try self.appendMangled(gpa, &out, t);
        return out.toOwnedSlice(gpa);
    }

    /// Work is proportional to the exact emitted spelling; stack space is
    /// proportional to the depth of its structural type.
    fn appendMangled(
        self: *const Typing,
        gpa: std.mem.Allocator,
        out: *std.ArrayList(u8),
        t: TypeId,
    ) std.mem.Allocator.Error!void {
        // An array is the one constructed type that is not an instantiation, so
        // there are no arguments to read off it: its name spells the element
        // and the length and nothing a reader can take apart. Both are written
        // here instead, the way the source writes them -- `[UInt8;2]` is what a
        // program says, minus the space a symbol has no use for.
        //
        // The brackets are what say this is an element and not a name, so no
        // component of digits and a letter is needed to announce it: nothing
        // else in a symbol opens a bracket without a name in front of it.
        switch (self.get(t)) {
            .borrow => |observation| {
                try out.appendSlice(gpa, "borrow(");
                try self.appendMangled(gpa, out, observation.referent);
                try out.append(gpa, ')');
                return;
            },
            .array => |a| {
                try out.append(gpa, '[');
                try self.appendMangled(gpa, out, a.element);
                const count = try std.fmt.allocPrint(gpa, ";{d}]", .{a.count});
                defer gpa.free(count);
                try out.appendSlice(gpa, count);
                return;
            },
            .callable => |signature| {
                if (signature.invocation != .read) {
                    try out.appendSlice(gpa, @tagName(signature.invocation));
                    try out.append(gpa, ' ');
                }
                try out.appendSlice(gpa, "fn(");
                for (self.callableParams(signature), 0..) |param, i| {
                    if (i > 0) try out.append(gpa, ',');
                    try out.appendSlice(gpa, @tagName(param.convention));
                    if (param.stable_address) try out.appendSlice(gpa, "@address");
                    try out.append(gpa, ':');
                    try self.appendMangled(gpa, out, param.ty);
                    switch (param.default) {
                        .absent => try out.appendSlice(gpa, ":none"),
                        .value => |value| {
                            const folded = try value.encoding(gpa, &self.constant_pool);
                            try out.appendSlice(gpa, ":value:");
                            defer gpa.free(folded);
                            try out.appendSlice(gpa, folded);
                        },
                    }
                }
                try out.appendSlice(gpa, ")->");

                try self.appendMangled(gpa, out, signature.result);
                try appendContractText(gpa, out, signature.contracts, null, true);
                return;
            },
            .closure => |closure| {
                const source = try std.fmt.allocPrint(gpa, "closure{d}[", .{@intFromEnum(closure.closure)});
                defer gpa.free(source);
                try out.appendSlice(gpa, source);
                for (self.closureArgs(closure), 0..) |arg, i| {
                    if (i > 0) try out.append(gpa, ',');
                    try self.appendMangled(gpa, out, arg);
                }
                try out.append(gpa, ']');
                if (closure.self_ty != .poison or closure.impl_arg_count != 0) {
                    try out.appendSlice(gpa, ":impl[");
                    for (self.closureImplArgs(closure), 0..) |arg, i| {
                        if (i > 0) try out.append(gpa, ',');
                        try self.appendMangled(gpa, out, arg);
                    }
                    try out.appendSlice(gpa, "]:");
                    try self.appendMangled(gpa, out, closure.self_ty);
                }
                return;
            },
            // Spelled by name below, which is injective for these because each
            // carries a name of its own or is a builtin with one spelling. A
            // kind added later decides here whether its name alone can tell
            // two of its values' types apart -- falling through by default is
            // how two instantiations would collapse to one symbol.
            .integer, .open_integer, .open_type, .boolean, .float, .poison, .unit, .never, .enum_, .struct_, .newtype, .parameter => {},
        }

        // An interpolation's type is the other one whose name embeds the whole
        // of another type: it is named by what it holds, spelled the way a
        // reader writes it, so the name carries a bracket and a comma per level
        // and each of those is three bytes once escaped. A symbol has a length
        // an assembler will take, and that spelling reaches it at a depth
        // nothing in the source marks -- so a program that checks clean stops
        // being one that builds.
        //
        // Written from the values instead, through the routine every other
        // structural name goes through. `0i` is a component no identifier can
        // be, exactly as an array's count is, so it says what follows is what a
        // literal held rather than a name. Injective for the reason the name is:
        // the values, their formats and whether each is borrowed are the whole
        // of what an interpolation's type is interned on, so two of them
        // differing here are two types.
        if (self.isInterpolation(t)) {
            try out.appendSlice(gpa, "0i");
            return self.appendInterpolated(gpa, out, t);
        }

        if (self.standinOf(t)) |standin| {
            // Source declaration identities distinguish associated members;
            // pool insertion order and abbreviated display names do not.
            const identity = try std.fmt.allocPrint(gpa, "0s{d}:{d}(", .{ standin.trait, standin.member.index() });
            defer gpa.free(identity);
            try out.appendSlice(gpa, identity);
            try self.appendMangled(gpa, out, standin.held);
            try out.append(gpa, ')');
            return self.appendArguments(gpa, out, self.standinArgsOf(standin));
        }

        if (self.moduleOfType(t)) |mi| try self.appendModule(gpa, out, mi);

        if (self.instanceOf(t)) |inst| {
            const template = self.typeOfDecl(inst.decl).?;
            try out.appendSlice(gpa, self.nameOf(template));
            return self.appendArguments(gpa, out, self.argsOf(inst));
        }

        const spelled = self.nameOf(t);

        // Everything else is the whole of its own name. A literal's type is
        // named by what it holds and interned on that name, so two of them are
        // two names -- and the name holds braces and spaces, which the one
        // escape a symbol goes through turns into bytes an assembler takes.
        try out.appendSlice(gpa, spelled);
    }

    /// Appends each value's format and mode, then what the literal held:
    /// every second field of the type minted for it, which are the values
    /// between braces.
    ///
    /// The text around them is a `Str` wherever it sits and says nothing about
    /// which type this is. The formats, the modes and the value types are what
    /// such a type is interned on, so together they tell two of them apart. A
    /// borrowed value is marked `b` after its format: its field is `borrow T`,
    /// which is also the field of a held `borrow T` value.
    ///
    /// **Bound:** the fields this one type declares, which is the pieces the
    /// literal was written in.
    fn appendInterpolated(
        self: *const Typing,
        gpa: std.mem.Allocator,
        out: *std.ArrayList(u8),
        t: TypeId,
    ) std.mem.Allocator.Error!void {
        const count = self.fieldCount(t);
        for (self.interpolationFormats(t), self.interpolationBorrowsAll(t)) |format, borrowed| {
            try out.append(gpa, if (format.debug) 'g' else 'd');
            // A layout is spelled as the format's bits, which have a fixed
            // width, so the mode's letter cannot be read as part of it.
            if (format.laysOut()) try out.print(gpa, "l{x:0>16}", .{format.bits()});
            if (borrowed) try out.append(gpa, 'b');
        }

        var held: std.ArrayList(TypeId) = .empty;
        defer held.deinit(gpa);
        try held.ensureTotalCapacity(gpa, count / 2);

        var at: u32 = 1;
        while (at < count) : (at += 2) held.appendAssumeCapacity(self.fieldType(t, at));

        return self.appendArguments(gpa, out, held.items);
    }

    /// What a declaration written inside an implementation is a member of, or
    /// null where none encloses it.
    ///
    /// **Bound:** one step. The table is filled once, where the
    /// implementations are collected.
    pub fn implementationOf(self: *const Typing, d: DeclId) ?Implementation {
        return self.implementations[(self.implementationIdOf(d) orelse return null).index()];
    }

    pub fn implementationIdOf(self: *const Typing, d: DeclId) ?ImplementationId {
        std.debug.assert(self.implementations.len == 0 or self.impl_of_decl.len != 0);
        if (d.index() >= self.impl_of_decl.len) return null;
        const at = self.impl_of_decl[d.index()];
        return if (at == no_implementation) null else @enumFromInt(at);
    }

    /// What `impl_of_decl` holds for a declaration no implementation encloses.
    pub const no_implementation = std.math.maxInt(u32);

    /// A type that no declaration declares, in `template_of`.
    pub const not_a_template = std.math.maxInt(u32);

    /// Whether `decl` is one of the prelude's tuple declarations, whose
    /// instances are spelled as tuples.
    ///
    /// **Bound:** the seven arities a tuple may have.
    pub fn isTupleDecl(self: *const Typing, decl: DeclId) bool {
        if (decl == DeclId.none) return false;
        for (self.tuple_decls) |tuple| if (tuple == decl) return true;
        return false;
    }

    test "only a declaration the prelude published as a tuple is one" {
        const gpa = testing.allocator;
        var builder = try Typing.Builder.init(gpa);
        defer builder.deinit();
        builder.tuple_decls[0] = DeclId.at(3);
        var typing = try builder.finish(.empty);
        defer typing.deinit(gpa);
        try testing.expect(typing.isTupleDecl(DeclId.at(3)));
        try testing.expect(!typing.isTupleDecl(DeclId.at(4)));
        try testing.expect(!typing.isTupleDecl(DeclId.none));
    }

    /// Which declaration a type came from: the one that declared it, or the
    /// one an instantiation was made from.
    ///
    /// The reverse of `typeOfDecl` over the same table, so the two directions
    /// cannot disagree about what the table says. An instantiation answers
    /// through the declaration its template came from, which is what makes
    /// `Cell[UInt8]` and `Cell[Bool]` two types of one declaration.
    ///
    /// Poison came from no declaration and must not match one: it is the type
    /// every un-settled expression carries, so a scan comparing it would
    /// return whichever declaration failed first.
    pub fn declOfType(self: *const Typing, t: TypeId) ?DeclId {
        if (t == .poison) return null;
        if (self.instanceOf(t)) |i| return i.decl;
        // A typing that knows of declared types knows which entry declares
        // each: the two tables are filled together, and one without the other
        // answers "no declaration declared it" for every type the program
        // wrote.
        std.debug.assert(self.templates.len == 0 or self.template_of.len != 0);
        const at_id = @intFromEnum(t);
        if (at_id >= self.template_of.len) return null;
        const at = self.template_of[at_id];
        if (at == not_a_template) return null;
        return self.templates[at].decl;
    }

    pub fn observationReferent(self: *const Typing, trait: DeclId, held: TypeId) ?TypeId {
        if (trait.index() >= self.observation_traits.len or !self.observation_traits[trait.index()]) return null;
        return if (self.get(held) == .borrow) self.get(held).borrow.referent else null;
    }

    /// The head a type reaches implementations through.
    ///
    /// One routine and two askers: an implementation is recorded under the head
    /// its own written head names, and a type is looked up under this. A second
    /// reading of what a head is would be an implementation entered where
    /// nothing looks for it.
    ///
    /// **Bound:** one step. An instantiation says which declaration it came
    /// from and an array says it is one; nothing else belongs to a family.
    pub fn headOf(self: *const Typing, t: TypeId) Head {
        if (self.instanceOf(t)) |i| return .{ .applied = i.decl };
        // Every array is a member of one family whatever it holds and however
        // long it is, for the reason every instantiation of a declaration is:
        // what the compiler implements, it implements for the constructor, and
        // a head naming one type would answer for one length of one element.
        switch (self.get(t)) {
            .array => return .array,
            .borrow => return .borrow_,
            // Each of these is its own head: a nominal type not made by
            // applying anything is reached whole, and a builtin likewise. A
            // kind added later says here whether its values share one family
            // or each stand alone -- which is a coherence decision, not a
            // default to inherit.
            .callable => |signature| {
                var shape: node.CallableShape.Builder = .begin(signature.invocation);
                for (self.callableParams(signature)) |parameter| shape.parameter(parameter.convention);
                if (shape.finish()) |exact| return .{ .callable_ = exact };
            },
            .integer, .open_integer, .open_type, .boolean, .float, .poison, .unit, .never, .enum_, .struct_, .newtype, .parameter, .closure => {},
        }
        return .{ .whole = t };
    }

    /// Whether a type still names a type nothing has settled, such as the `_`
    /// a generic function's value carries until a use says what its parameters
    /// are.
    ///
    /// **Bound:** the type's own parts, once each.
    pub fn mentionsOpenType(self: *const Typing, t: TypeId) bool {
        switch (self.get(t)) {
            .open_type, .open_integer => return true,
            .callable => |signature| {
                for (self.callableParams(signature)) |parameter| if (self.mentionsOpenType(parameter.ty)) return true;
                return self.mentionsOpenType(signature.result);
            },
            .array => |array| return self.mentionsOpenType(array.element),
            .borrow => |observation| return self.mentionsOpenType(observation.referent),
            else => {},
        }
        for (self.appliedTo(t)) |argument| if (self.mentionsOpenType(argument)) return true;
        return false;
    }

    /// What a type applies to its head, in the order it applies them, and
    /// nothing where it applies nothing.
    ///
    /// Beside `headOf` and read with it: a head and what it is applied to are
    /// the two halves of what a type reaches an implementation by, and a
    /// caller pairing them itself would be a second reading of the first.
    ///
    /// **Bound:** one step, the same index `instanceOf` is.
    pub fn appliedTo(self: *const Typing, t: TypeId) []const TypeId {
        if (self.get(t) == .borrow) return (&self.pool[t.index()].borrow.referent)[0..1];
        return self.argsOf(self.instanceOf(t) orelse return &.{});
    }

    pub fn moduleOfType(self: *const Typing, t: TypeId) ?u32 {
        return self.moduleOfDecl(self.declOfType(t) orelse return null);
    }

    /// Which module a type declaration sits in, or null where the declaration
    /// declares no type.
    pub fn moduleOfDecl(self: *const Typing, decl: DeclId) ?u32 {
        return (self.templateOf(decl) orelse return null).module;
    }

    /// The template a declaration declares, or null where it declares none.
    ///
    /// The one search over `templates`, because "what does this declaration
    /// declare" and "which module is it in" are one question asked of one row.
    /// Both were a walk, and both are asked per symbol emitted and per part
    /// substituted -- so each was the declared types times the program.
    /// `noteTemplate` keeps the list in declaration order for this.
    fn templateOf(self: *const Typing, decl: DeclId) ?*const Template {
        return lookupTemplate(self.templates, decl);
    }

    fn lookupTemplate(templates: []const Template, decl: DeclId) ?*const Template {
        var lo: usize = 0;
        var hi: usize = templates.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (templates[mid].decl.index() < decl.index()) lo = mid + 1 else hi = mid;
        }
        if (lo < templates.len and templates[lo].decl == decl) return &templates[lo];
        return null;
    }

    /// The type a declaration declares, or null where it declares none.
    ///
    /// The template for a generic one: a declaration stands for a family, and
    /// which member of it is meant is a question about a use rather than about
    /// the declaration.
    pub fn typeOfDecl(self: *const Typing, decl: DeclId) ?TypeId {
        return (self.templateOf(decl) orelse return null).ty;
    }

    /// The type an alias names, or poison where it names none.
    pub fn aliasedType(self: *const Typing, alias: DeclId) TypeId {
        return self.aliased.get(alias) orelse .poison;
    }

    /// A type that is not an instantiation, in `instance_of`.
    pub const not_an_instance = std.math.maxInt(u32);

    /// The instantiation a type is, or null where it is not one.
    ///
    /// An index rather than a walk of `instances`: every query that misses
    /// read the whole list, a miss is the common case since most types are not
    /// instantiations, and the list grows with the program -- so the pool cost
    /// the number of instantiations times the number of questions asked of it.
    pub fn instanceOf(self: *const Typing, t: TypeId) ?Instance {
        return lookupInstance(self.instance_of, self.instances, t);
    }

    fn lookupInstance(instance_of: []const u32, instances: []const Instance, t: TypeId) ?Instance {
        const at_id = @intFromEnum(t);
        if (at_id >= instance_of.len) return null;
        const at = instance_of[at_id];
        if (at == not_an_instance) return null;
        return instances[at];
    }

    /// What an instantiation was given, as a slice of the pool's own list.
    ///
    /// Beside `instanceOf`, because every caller of that goes on to want this
    /// and each was slicing `instance_args` by hand -- four of them, spelling
    /// the same two-field arithmetic, none able to be wrong in an interesting
    /// way and all of them a place for the representation to leak.
    pub fn argsOf(self: *const Typing, i: Instance) []const TypeId {
        return self.instance_args[i.first_arg..][0..i.arg_count];
    }

    /// A type no settled reference stands for, in `standin_of`.
    pub const not_a_standin = std.math.maxInt(u32);

    /// The key a pool entry stands for, or null where it stands for a
    /// parameter a declaration wrote.
    ///
    /// The same shape `instanceOf` has and for the same reason: a settled
    /// reference is interned as the parameter it behaves like, so what tells
    /// the two apart is a row keyed by the entry rather than a variant of it.
    /// Read after the pass that minted it has ended -- which is what lets a
    /// reader outside the checker say which bound a reference was read
    /// through.
    pub fn standinOf(self: *const Typing, t: TypeId) ?Standin {
        const at_id = @intFromEnum(t);
        if (at_id >= self.standin_of.len) return null;
        const at = self.standin_of[at_id];
        if (at == not_a_standin) return null;
        return self.standins[at];
    }

    pub fn standinArgsOf(self: *const Typing, s: Standin) []const TypeId {
        return self.standin_args[s.first_arg..][0..s.arg_count];
    }

    /// The type an implementation member wrote to settle one trait signature.
    /// Substitution through the implementation head is the caller's question.
    pub fn settledTypeWritten(self: *const Typing, impl: Implementation, sig: DeclId) ?TypeId {
        const member = self.supply_index.memberOf(impl.decl, sig) orelse return null;
        const settled = self.decl_returns.get(member);
        return if (settled == .poison) null else settled;
    }

    /// How far apart two of these sit. The size rounded up to the alignment,
    /// which is what an element has to be for the next one to begin aligned.
    pub fn strideOf(self: *const Typing, t: TypeId) u64 {
        const l = self.layoutOf(t);
        return Layout.alignUp(l.size, l.alignment);
    }

    /// Whether a type carries `trait` as a bound rather than by implementing it.
    ///
    /// A bound is a promise about whatever settles what carries it, so a body
    /// may call through one with no implementation in sight: the promise is
    /// discharged where the argument is supplied, or where the implementation
    /// a projection is read through settles the declared type. A type that is
    /// no parameter carries no promise -- what it answers is what it
    /// implements.
    ///
    /// One reading, because every asker of it is asking the same thing: a call
    /// checking a bound, and the lookup deciding which implementation answers
    /// for a receiver. A copy that knew only about implementations refused a
    /// bounded generic handing its parameter to another bounded generic, which
    /// is the whole of what a bound is for.
    ///
    /// `args` is the arguments the asker needs the trait discharged at, or
    /// `null` where there are none in hand to ask it at -- a call through a
    /// trait settling `Self`, what an editor may offer after a dot, and an
    /// operator's demand for a trait the language rather than a bound names
    /// all ask this way, before anything has settled what to discharge at.
    /// `null` answers whether the trait is carried at all, whatever the
    /// arguments; given, a promise counts only where it was made at exactly
    /// those -- `C: Lookup[UInt64]` carries `Lookup` at `UInt64` and answers
    /// nothing for `Lookup` asked of anything else, including asked with no
    /// arguments in hand.
    pub fn boundsCarry(self: *const Typing, t: TypeId, trait: u32, args: ?[]const TypeId) bool {
        const p = switch (self.get(t)) {
            .parameter => |p| p,
            else => return false,
        };
        for (p.traits) |named| {
            if (named.trait != trait) continue;
            if (args == null or std.mem.eql(TypeId, named.args, args.?)) return true;
        }
        return false;
    }

    pub fn boundsCarryWithin(self: *const Typing, owner: DeclId, t: TypeId, trait: u32, args: ?[]const TypeId) bool {
        return self.boundsCarry(t, trait, args) or self.contextual_constraints.boundsCarry(owner, t, trait, args);
    }

    /// Appends the arguments of every bound naming `trait` that
    /// `boundsCarryWithin` would consult for `t`: its own parameter bounds and
    /// the contextual promises active in `owner`.
    pub fn boundArgumentsWithin(
        self: *const Typing,
        gpa: std.mem.Allocator,
        owner: DeclId,
        t: TypeId,
        trait: u32,
        out: *std.ArrayList([]const TypeId),
    ) std.mem.Allocator.Error!void {
        for (self.boundsOn(t)) |named| {
            if (named.trait == trait) try out.append(gpa, named.args);
        }
        try self.contextual_constraints.boundArguments(gpa, owner, t, trait, out);
    }

    /// Every bound a parameter carries, as the traits and arguments they were
    /// interned at; empty for anything that is not a parameter.
    ///
    /// Read rather than re-derived: `t`'s bounds were interned once, when the
    /// declaration that wrote them was, and a type argument checked against
    /// one is checked against exactly what that reading settled -- not a
    /// second reading of the tokens that wrote it. Whole rather than one entry
    /// per trait, because a parameter may carry one trait at several
    /// arguments and picking an entry out is the caller's written bound to
    /// match, not this table's to guess.
    /// Enumerate normalized promises on this exact subject in one scope.
    /// Returned argument slices borrow the immutable typing.
    pub fn appendBoundsWithin(self: *const Typing, gpa: std.mem.Allocator, owner: DeclId, subject: TypeId, out: *std.ArrayList(BoundTrait)) !void {
        try out.appendSlice(gpa, self.boundsOn(subject));
        var scope = owner;
        while (scope != .none) : (scope = self.contextual_constraints.parentOf(scope)) {
            for (self.contextual_constraints.run(scope)) |constraint| {
                if (constraint.subject == subject) try out.appendSlice(gpa, constraint.demand.traits);
            }
        }
    }

    pub fn boundsOn(self: *const Typing, t: TypeId) []const BoundTrait {
        return switch (self.get(t)) {
            .parameter => |p| p.traits,
            else => &.{},
        };
    }

    pub fn typeSelection(self: *const Typing, dot: TokenId) ?TypeSelection {
        return self.type_selections.get(dot);
    }

    pub fn fieldSelection(self: *const Typing, token: TokenId) ?FieldIdentity {
        return self.field_names.get(token);
    }

    pub fn placeProjection(self: *const Typing, expression: ExprId) ?PlaceProjection {
        return self.place_projections.get(expression);
    }

    pub fn observedReceiver(self: *const Typing, held: TypeId) ReceiverAdjustment {
        var result: ReceiverAdjustment = .{ .observations = 0, .receiver = held };
        while (self.get(result.receiver) == .borrow) {
            result.receiver = self.get(result.receiver).borrow.referent;
            result.observations += 1;
        }
        return result;
    }

    pub fn arrayViewReceiver(self: *const Typing, held: TypeId) ?ReceiverAdjustment {
        if (self.raw_accesses.slice == .none) return null;
        const adjustment = self.observedReceiver(held);
        return if (self.get(adjustment.receiver) == .array) adjustment else null;
    }

    pub fn callableBoundsOn(self: *const Typing, t: TypeId) []const TypeId {
        return switch (self.get(t)) {
            .parameter => |p| p.callables,
            else => &.{},
        };
    }

    pub fn callableSatisfies(self: *const Typing, actual: TypeId, wanted: TypeId) bool {
        return self.callableMatches(actual, wanted, true);
    }

    /// A contextual code pointer changes outer parameter labels, and may
    /// promise more carried dependencies than the function has: `carries` is
    /// an upper bound, fitted by the same relation a callable bound uses.
    /// Invocation and retention stay exact.
    pub fn callableConverts(self: *const Typing, actual: TypeId, wanted: TypeId) bool {
        return self.callableMatches(actual, wanted, false);
    }

    fn callableMatches(self: *const Typing, actual: TypeId, wanted: TypeId, demand: bool) bool {
        if (actual == wanted) return true;
        const got = switch (self.get(actual)) {
            .callable => |signature| signature,
            else => return false,
        };
        const want = switch (self.get(wanted)) {
            .callable => |signature| signature,
            else => return false,
        };
        return (if (demand) invocationCompatible(got.invocation, want.invocation) else got.invocation == want.invocation) and
            got.result == want.result and
            callableContractsSatisfy(got.contracts, want.contracts) and
            callableParamsMatch(self.callableParams(got), self.callableParams(want));
    }

    pub fn carriesCallableBound(self: *const Typing, t: TypeId, signature: TypeId) bool {
        for (self.callableBoundsOn(t)) |held| if (self.callableSatisfies(held, signature)) return true;
        return false;
    }

    pub fn carriesCallableBoundWithin(self: *const Typing, owner: DeclId, t: TypeId, signature: TypeId) bool {
        return self.carriesCallableBound(t, signature) or self.contextual_constraints.carriesCallable(self, owner, t, signature);
    }

    /// Whether dependencies may originate at this value rather than only in
    /// its physical fields. Private storage certificates participate here so
    /// consumers cannot mistake erased storage for an independent scalar.
    pub fn hasDirectDependencies(self: *const Typing, t: TypeId) bool {
        return self.directDependencySeed(t);
    }

    fn directDependencySeed(self: *const Typing, t: TypeId) bool {
        switch (self.get(t)) {
            .borrow => return true,
            // An instantiation may supply any type, so a parameter carries
            // unless its bounds admit only types that carry nothing: `Owned`,
            // or the integer family, all of which are Owned.
            .parameter => |p| return !(p.owned or p.integer),
            else => {},
        }
        const declaration = self.declOfType(t) orelse return false;
        if (self.raw_accesses.slice != .none and declaration == self.raw_accesses.slice) return true;
        if (self.raw_accesses.buffer != .none and declaration == self.raw_accesses.buffer) return true;
        return self.raw_accesses.storage != .none and declaration == self.raw_accesses.storage and self.instanceOf(t) == null;
    }

    /// Whether a value of `t` may hold storage of its own, a buffer somewhere
    /// in its fields, payloads or elements, which a view of it would point
    /// into. A view and a scalar hold none; a type parameter may be anything
    /// its bounds admit, so it may unless they make it copyable, which no
    /// value holding storage is.
    ///
    /// **Bound:** each distinct type reached once.
    pub fn mayHoldStorage(self: *const Typing, gpa: std.mem.Allocator, t: TypeId) std.mem.Allocator.Error!bool {
        var seen: std.AutoHashMapUnmanaged(TypeId, void) = .empty;
        defer seen.deinit(gpa);
        return self.holdsStorageWalk(gpa, &seen, t);
    }

    fn holdsStorageWalk(self: *const Typing, gpa: std.mem.Allocator, seen: *std.AutoHashMapUnmanaged(TypeId, void), t: TypeId) std.mem.Allocator.Error!bool {
        if ((try seen.getOrPut(gpa, t)).found_existing) return false;
        switch (self.get(t)) {
            .borrow => return false,
            .parameter => |p| return p.requirement != .copyable,
            .array => |a| return self.holdsStorageWalk(gpa, seen, a.element),
            .struct_, .closure => {
                if (self.declOfType(t)) |declaration| {
                    if (self.raw_accesses.buffer != .none and declaration == self.raw_accesses.buffer) return true;
                    if (self.raw_accesses.storage != .none and declaration == self.raw_accesses.storage) return true;
                    if (self.raw_accesses.slice != .none and declaration == self.raw_accesses.slice) return false;
                }
                for (0..self.fieldCount(t)) |i| if (try self.holdsStorageWalk(gpa, seen, self.fieldType(t, @intCast(i)))) return true;
                return false;
            },
            .enum_ => {
                for (0..self.variantCount(t)) |v| for (0..self.variantFieldCount(t, @intCast(v))) |f| {
                    if (try self.holdsStorageWalk(gpa, seen, self.variantFieldType(t, @intCast(v), @intCast(f)))) return true;
                };
                return false;
            },
            .newtype => |named| return self.holdsStorageWalk(gpa, seen, named.base),
            else => return false,
        }
    }

    /// Whether a value of `t` holds a view somewhere in its fields, payloads
    /// or elements: an observation, or a slice of storage it does not own. A
    /// type parameter is not known to.
    ///
    /// **Bound:** each distinct type reached once.
    pub fn holdsView(self: *const Typing, gpa: std.mem.Allocator, t: TypeId) std.mem.Allocator.Error!bool {
        var seen: std.AutoHashMapUnmanaged(TypeId, void) = .empty;
        defer seen.deinit(gpa);
        return self.holdsViewWalk(gpa, &seen, t);
    }

    fn holdsViewWalk(self: *const Typing, gpa: std.mem.Allocator, seen: *std.AutoHashMapUnmanaged(TypeId, void), t: TypeId) std.mem.Allocator.Error!bool {
        if ((try seen.getOrPut(gpa, t)).found_existing) return false;
        switch (self.get(t)) {
            .borrow => return true,
            .array => |a| return self.holdsViewWalk(gpa, seen, a.element),
            .struct_, .closure => {
                if (self.declOfType(t)) |declaration| {
                    if (self.raw_accesses.slice != .none and declaration == self.raw_accesses.slice) return true;
                    if (self.raw_accesses.buffer != .none and declaration == self.raw_accesses.buffer) return false;
                    if (self.raw_accesses.storage != .none and declaration == self.raw_accesses.storage) return false;
                }
                for (0..self.fieldCount(t)) |i| if (try self.holdsViewWalk(gpa, seen, self.fieldType(t, @intCast(i)))) return true;
                return false;
            },
            .enum_ => {
                for (0..self.variantCount(t)) |v| for (0..self.variantFieldCount(t, @intCast(v))) |f| {
                    if (try self.holdsViewWalk(gpa, seen, self.variantFieldType(t, @intCast(v), @intCast(f)))) return true;
                };
                return false;
            },
            .newtype => |named| return self.holdsViewWalk(gpa, seen, named.base),
            else => return false,
        }
    }

    pub fn mayCarryDependencies(self: *const Typing, t: TypeId) bool {
        const index = @intFromEnum(t);
        std.debug.assert(index < self.dependency_containment.len);
        return self.dependency_containment[index];
    }

    /// Whether a value of `t` may hold a closure, a function value or a type
    /// parameter: something that could write through a place lent `inout`.
    pub fn mayHoldWriter(self: *const Typing, t: TypeId) bool {
        const index = @intFromEnum(t);
        std.debug.assert(index < self.writer_containment.len);
        return self.writer_containment[index];
    }

    test "an Owned or Integer parameter carries nothing, and a carrier names its path" {
        const gpa = testing.allocator;
        var builder = try Builder.init(gpa);
        defer builder.deinit();
        const plain = try builder.addParameter("T", 0, 0, .unrestricted, &.{});
        const owned = try builder.addParameter("U", 0, 1, .unrestricted, &.{});
        builder.pool.items[@intFromEnum(owned)].parameter.owned = true;
        const counted = try builder.addParameter("N", 0, 2, .unrestricted, &.{});
        builder.pool.items[@intFromEnum(counted)].parameter.integer = true;
        const number = try builder.borrowOf(.u8);
        const reading = try builder.addStruct("Reading", .affine, &.{.{ .name = "celsius", .ty = .i64 }});
        const label = try builder.addStruct("Label", .affine, &.{ .{ .name = "count", .ty = .u8 }, .{ .name = "first", .ty = number } });
        const shelf = try builder.addStruct("Shelf", .affine, &.{.{ .name = "label", .ty = label }});

        try testing.expect(try builder.mayCarryDependencies(plain));
        try testing.expect(!try builder.mayCarryDependencies(owned));
        try testing.expect(!try builder.mayCarryDependencies(counted));
        try testing.expect(try builder.dependencyWitness(gpa, reading) == null);

        const witness = (try builder.dependencyWitness(gpa, shelf)).?;
        defer witness.deinit(gpa);
        try testing.expectEqual(number, witness.seed);
        try testing.expectEqual(@as(usize, 2), witness.steps.len);
        try testing.expectEqualStrings("label", witness.steps[0].field);
        try testing.expectEqualStrings("first", witness.steps[1].field);
        try testing.expectEqual(label, witness.parts[0]);
        try testing.expectEqual(number, witness.parts[1]);

        const itself = (try builder.dependencyWitness(gpa, plain)).?;
        defer itself.deinit(gpa);
        try testing.expectEqual(plain, itself.seed);
        try testing.expectEqual(@as(usize, 0), itself.steps.len);
    }

    test "a type holds a writer when a closure, function or type parameter can reach it" {
        const gpa = testing.allocator;
        var builder = try Builder.init(gpa);
        defer builder.deinit();
        const number = try builder.borrowOf(.u8);
        const readings = try builder.addStruct("Readings", .affine, &.{.{ .name = "first", .ty = number }});
        const callback = try builder.internCallable(&.{}, .unit, &.{}, .read);
        const task = try builder.addStruct("Task", .affine, &.{.{ .name = "run", .ty = callback }});
        const parameter = try builder.addParameter("T", 0, 0, .unrestricted, &.{});
        const observed = try builder.borrowOf(parameter);
        var typing = try builder.finish(.empty);
        defer typing.deinit(gpa);
        try testing.expect(!typing.mayHoldWriter(readings));
        try testing.expect(typing.mayHoldWriter(task));
        try testing.expect(typing.mayHoldWriter(observed));
    }

    pub fn capabilityOf(self: *const Typing, t: TypeId) Capability {
        return self.capabilities[t.index()];
    }

    pub fn capabilityOfWithin(self: *const Typing, owner: DeclId, t: TypeId) Capability {
        // Rejected or unrecorded expressions carry no ownership obligation.
        // Their recovery capability does not depend on a declaration's bounds.
        if (t == .poison) return self.capabilityOf(t);
        const scope = self.contextual_constraints.activeCapabilityScope(owner);
        if (scope == .none) return self.capabilityOf(t);
        return self.scoped_capabilities.get(.{ .scope = scope, .ty = t }) orelse
            @panic("scoped capability was not prepared before the immutable typing handoff");
    }

    /// Authored scalar types whose value positions read an independent snapshot.
    /// Nominal wrappers and symbolic parameters retain explicit copy semantics.
    pub fn isScalarSnapshot(self: *const Typing, t: TypeId) bool {
        return switch (self.get(t)) {
            .integer, .open_integer, .boolean, .float => true,
            .enum_ => |e| e.ownership_policy == .copyable and e.payload_field_count == 0,
            else => false,
        };
    }

    pub fn mayCopy(self: *const Typing, t: TypeId) bool {
        return self.capabilityOf(t) == .copyable;
    }
    pub fn mustConsume(self: *const Typing, t: TypeId) bool {
        return self.capabilityOf(t) == .linear;
    }
    pub fn mayDiscard(self: *const Typing, t: TypeId) bool {
        return !self.mustConsume(t);
    }
    pub fn mayCopyWithin(self: *const Typing, owner: DeclId, t: TypeId) bool {
        return self.capabilityOfWithin(owner, t) == .copyable;
    }
    pub fn mustConsumeWithin(self: *const Typing, owner: DeclId, t: TypeId) bool {
        return self.capabilityOfWithin(owner, t) == .linear;
    }
    pub fn mayDiscardWithin(self: *const Typing, owner: DeclId, t: TypeId) bool {
        return !self.mustConsumeWithin(owner, t);
    }

    pub fn implementationArgumentsWithin(self: *const Typing, owner: DeclId, implementation: ImplementationId, args: []const TypeId, receiver: TypeId) ?[]const TypeId {
        return (self.prepared_implementations.answers.get(.{
            .scope = self.contextual_constraints.lookupScope(owner),
            .receiver = receiver,
            .implementation = implementation,
            .args = args,
        }) orelse return null).arguments;
    }

    fn implementationApplies(self: *const Typing, _: *const ImplIndex, _: []const Implementation, decided: *ImplIndex.Decided, at: u32, args: []const TypeId, held: TypeId) std.mem.Allocator.Error!?[]const TypeId {
        return self.implementationArgumentsWithin(decided.scope, @enumFromInt(at), args, held);
    }

    fn implementationCandidate(self: *const Typing, _: *const ImplIndex, _: []const Implementation, decided: *ImplIndex.Decided, at: u32, args: []const TypeId, held: TypeId) !ImplementationCandidate {
        return self.prepared_implementations.answers.get(.{
            .scope = self.contextual_constraints.lookupScope(decided.scope),
            .receiver = held,
            .implementation = @enumFromInt(at),
            .args = args,
        }) orelse .{};
    }

    pub fn receiverTraitArguments(self: *const Typing, implementation: ImplementationId, receiver: TypeId) !?[]const TypeId {
        return switch (try self.receiverImplementation(implementation, receiver)) {
            .settled => |args| args,
            else => null,
        };
    }

    pub fn receiverImplementation(self: *const Typing, implementation: ImplementationId, receiver: TypeId) !ReceiverImplementation {
        return self.prepared_implementations.receiver_args.get(.{ .implementation = implementation, .receiver = receiver }) orelse .absent;
    }

    /// Whether calling `operation` on a value of `receiver` in `owner` leaves
    /// a result that still owes, as `Builder.prepareSettlingResult` decided
    /// it. Null where it decided nothing: the operation's block does not apply
    /// to the receiver, or it was never asked.
    pub fn settlingResultOwes(self: *const Typing, owner: DeclId, receiver: TypeId, operation: DeclId) ?bool {
        return self.prepared_implementations.settling_results.get(.{ .owner = owner, .receiver = receiver, .operation = operation });
    }

    test "an operation never asked about has no settling answer" {
        var builder = try Builder.init(testing.allocator);
        defer builder.deinit();
        const ticket = try builder.addStruct("Ticket", .linear, &.{});
        try testing.expectEqual(@as(?bool, null), builder.view().settlingResultOwes(.none, ticket, DeclId.at(0)));
    }

    pub fn variantCount(self: *const Typing, t: TypeId) u32 {
        return switch (self.get(t)) {
            .enum_ => |e| e.variant_count,
            else => 0,
        };
    }

    pub fn variantName(self: *const Typing, t: TypeId, i: u32) []const u8 {
        const e = self.get(t).enum_;
        return self.variants.items(.name)[e.first_variant + i];
    }

    /// Which alternative a name selects, or null when the type has none by
    /// that name.
    pub fn variantIndexOf(self: *const Typing, t: TypeId, name: []const u8) ?u32 {
        for (0..self.variantCount(t)) |i| {
            if (std.mem.eql(u8, self.variantName(t, @intCast(i)), name)) return @intCast(i);
        }
        return null;
    }

    /// Whether a type is one the compiler minted for an interpolation.
    ///
    /// By the prefix of its name, which holds a brace. Each literal's type is
    /// numbered after that prefix, because two sharing a name gave one symbol
    /// to two instantiations.
    pub fn isInterpolation(self: *const Typing, t: TypeId) bool {
        return interpolationWithin(self.pool, self.interpolation_of, t);
    }

    fn interpolationWithin(pool: []const Type, interpolation_of: []const u32, t: TypeId) bool {
        if (@intFromEnum(t) < interpolation_of.len and
            interpolation_of[@intFromEnum(t)] != not_an_interpolation)
        {
            return true;
        }
        return switch (pool[t.index()]) {
            .struct_ => |s| std.mem.startsWith(u8, s.name, interpolation_type_name),
            else => false,
        };
    }

    /// The selected format of each value an interpolation holds.
    pub fn interpolationFormats(self: *const Typing, t: TypeId) []const node.InterpolationFormat {
        if (@intFromEnum(t) >= self.interpolation_of.len) return &.{};
        const at = self.interpolation_of[@intFromEnum(t)];
        if (at == not_an_interpolation) return &.{};
        const record = self.interpolations[at];
        return self.interpolation_formats[record.first_format..][0..record.format_count];
    }

    /// Whether each embedded value of an interpolation is borrowed, as the
    /// checker recorded it, in the order of `interpolationFormats`.
    pub fn interpolationBorrowsAll(self: *const Typing, t: TypeId) []const bool {
        if (@intFromEnum(t) >= self.interpolation_of.len) return &.{};
        const at = self.interpolation_of[@intFromEnum(t)];
        if (at == not_an_interpolation) return &.{};
        const record = self.interpolations[at];
        return self.interpolation_borrows[record.first_format..][0..record.format_count];
    }

    /// Whether the checker refused the expression: it built no value, so
    /// nothing runs there. A value that was built and only fails to fit the
    /// type its context expects is not refused.
    pub fn isRefused(self: *const Typing, id: ExprId) bool {
        return self.refused.contains(id);
    }

    test isRefused {
        const gpa = testing.allocator;
        var typing: Typing = .{
            .binding_types = .empty,
            .decl_returns = .empty,
            .pool = &.{},
            .variants = .empty,
            .fields = .empty,
            .expr_types = &.{},
            .calls = &.{},
        };
        defer typing.refused.deinit(gpa);
        try typing.refused.put(gpa, ExprId.at(3), {});
        try testing.expect(typing.isRefused(ExprId.at(3)));
        try testing.expect(!typing.isRefused(ExprId.at(4)));
    }

    /// What the literal does with a value piece, or null where the checker
    /// refused the literal.
    pub fn interpolationPosition(self: *const Typing, piece: ExprId) ?PiecePosition {
        return self.interpolation_positions.get(piece);
    }

    test interpolationPosition {
        const gpa = testing.allocator;
        var typing: Typing = .{
            .binding_types = .empty,
            .decl_returns = .empty,
            .pool = &.{},
            .variants = .empty,
            .fields = .empty,
            .expr_types = &.{},
            .calls = &.{},
        };
        defer typing.interpolation_positions.deinit(gpa);
        try typing.interpolation_positions.put(gpa, ExprId.at(3), .moved);
        try typing.interpolation_positions.put(gpa, ExprId.at(5), .borrowed);

        try testing.expectEqual(@as(?PiecePosition, .moved), typing.interpolationPosition(ExprId.at(3)));
        try testing.expectEqual(@as(?PiecePosition, .borrowed), typing.interpolationPosition(ExprId.at(5)));
        try testing.expectEqual(@as(?PiecePosition, null), typing.interpolationPosition(ExprId.at(4)));
    }

    /// Whether an interpolation borrows its piece `i` rather than holding it,
    /// as the checker recorded it. A place that cannot be copied is borrowed,
    /// and so is a computed value that must be settled; every Copyable value,
    /// a `borrow T` value included, and any other computed value are held.
    /// Text pieces are always held.
    pub fn interpolationBorrows(self: *const Typing, t: TypeId, i: u32) bool {
        if (i % 2 == 0) return false;
        const borrows = self.interpolationBorrowsAll(t);
        return i / 2 < borrows.len and borrows[i / 2];
    }

    /// The type an interpolation renders at piece `i`: the referent of a
    /// borrowed piece's field, and a held piece's field itself.
    pub fn interpolationValue(self: *const Typing, t: TypeId, i: u32) TypeId {
        const field = self.fieldType(t, i);
        return if (self.interpolationBorrows(t, i)) self.get(field).borrow.referent else field;
    }

    /// The ways `holdingDifference` found two interpolations to differ.
    pub const HoldingDifference = struct {
        /// A piece one literal borrows and the other holds as a computed
        /// value of the same type.
        computed: bool = false,
        /// A piece one literal borrows as a `T` variable and the other holds
        /// as a copied `borrow T` value.
        observation: bool = false,
    };

    /// How two interpolations with the same formats differ where every
    /// other value is the same: in pieces that render one type, but one
    /// literal borrows while the other holds a computed value, or in pieces
    /// with one field, where one literal borrows a `T` variable and the other
    /// holds a copy of a `borrow T` value. Null where they differ in anything
    /// else, or not at all.
    pub fn holdingDifference(self: *const Typing, a: TypeId, b: TypeId) ?HoldingDifference {
        if (a == b or !self.isInterpolation(a) or !self.isInterpolation(b)) return null;
        const count = self.fieldCount(a);
        if (count != self.fieldCount(b)) return null;
        const formats_a = self.interpolationFormats(a);
        const formats_b = self.interpolationFormats(b);
        if (formats_a.len != formats_b.len) return null;
        for (formats_a, formats_b) |x, y| if (!x.eql(y)) return null;
        var difference: HoldingDifference = .{};
        var i: u32 = 1;
        while (i < count) : (i += 2) {
            if (self.interpolationBorrows(a, i) == self.interpolationBorrows(b, i)) {
                if (self.fieldType(a, i) != self.fieldType(b, i)) return null;
            } else if (self.interpolationValue(a, i) == self.interpolationValue(b, i)) {
                difference.computed = true;
            } else if (self.fieldType(a, i) == self.fieldType(b, i)) {
                difference.observation = true;
            } else return null;
        }
        return difference;
    }

    test "two interpolations differing only in holding are told apart" {
        var builder = try Builder.init(testing.allocator);
        defer builder.deinit();
        const name = try builder.addStruct("Name", .affine, &.{});
        const observed = try builder.borrowOf(name);
        const borrowed = try builder.internInterpolation(&.{
            .{ .name = "0", .ty = .i64 },
            .{ .name = "1", .ty = observed },
            .{ .name = "2", .ty = .i64 },
        }, &.{.display}, &.{true});
        const held = try builder.internInterpolation(&.{
            .{ .name = "0", .ty = .i64 },
            .{ .name = "1", .ty = name },
            .{ .name = "2", .ty = .i64 },
        }, &.{.display}, &.{false});
        const copied = try builder.internInterpolation(&.{
            .{ .name = "0", .ty = .i64 },
            .{ .name = "1", .ty = observed },
            .{ .name = "2", .ty = .i64 },
        }, &.{.display}, &.{false});
        const other = try builder.internInterpolation(&.{
            .{ .name = "0", .ty = .i64 },
            .{ .name = "1", .ty = .u8 },
            .{ .name = "2", .ty = .i64 },
        }, &.{.display}, &.{false});
        const view = builder.view();
        try testing.expectEqual(HoldingDifference{ .computed = true }, view.holdingDifference(borrowed, held).?);
        try testing.expectEqual(HoldingDifference{ .observation = true }, view.holdingDifference(borrowed, copied).?);
        try testing.expectEqual(@as(?HoldingDifference, null), view.holdingDifference(held, copied));
        try testing.expectEqual(@as(?HoldingDifference, null), view.holdingDifference(borrowed, other));
        try testing.expectEqual(@as(?HoldingDifference, null), view.holdingDifference(held, held));
    }

    test "an interpolation renders what its borrowed piece observes" {
        var builder = try Builder.init(testing.allocator);
        defer builder.deinit();
        const score = try builder.addStruct("Score", .affine, &.{});
        const observed = try builder.borrowOf(score);
        const held = [_]Field{
            .{ .name = "0", .ty = .i64 },
            .{ .name = "1", .ty = observed },
            .{ .name = "2", .ty = .i64 },
            .{ .name = "3", .ty = .u8 },
            .{ .name = "4", .ty = .i64 },
        };
        const literal = try builder.internInterpolation(&held, &.{ .display, .display }, &.{ true, false });
        // The same fields holding a `borrow Score` value are another type,
        // with another name and another symbol.
        const copied = try builder.internInterpolation(&held, &.{ .display, .display }, &.{ false, false });
        try testing.expect(literal != copied);
        const view = builder.view();
        try testing.expectEqualStrings("{interpolation borrow Score, UInt8}", view.nameOf(literal));
        try testing.expectEqualStrings("{interpolation copy borrow Score, UInt8}", view.nameOf(copied));
        const literal_symbol = try view.mangledName(testing.allocator, literal);
        defer testing.allocator.free(literal_symbol);
        const copied_symbol = try view.mangledName(testing.allocator, copied);
        defer testing.allocator.free(copied_symbol);
        try testing.expect(!std.mem.eql(u8, literal_symbol, copied_symbol));
        try testing.expectEqual(score, view.interpolationValue(literal, 1));
        try testing.expectEqual(TypeId.u8, view.interpolationValue(literal, 3));
        try testing.expect(view.interpolationBorrows(literal, 1));
        try testing.expect(!view.interpolationBorrows(literal, 3));
        try testing.expectEqual(observed, view.interpolationValue(copied, 1));
        try testing.expect(!view.interpolationBorrows(copied, 1));
    }

    /// Which alternative of an `Option` or a `Result` is the successful one.
    ///
    /// `Some` and `Ok` are one position under two names, and so are `None` and
    /// `Err`. One routine for both carriers, and one for both readers: the
    /// checker asks it to say what `?` yields, and lowering asks it to say
    /// which tag `?` tests. The two asking separately is the shape that drifts
    /// the first time a variant is written in another order.
    ///
    /// A question about what a type holds and about nothing else, so it sits
    /// with the representation rather than with either pass that reads it.
    pub fn successVariantOf(self: *const Typing, t: TypeId) ?u32 {
        return self.variantIndexOf(t, "Some") orelse self.variantIndexOf(t, "Ok");
    }

    /// Which alternative is the one `?` returns from the enclosing function.
    pub fn failureVariantOf(self: *const Typing, t: TypeId) ?u32 {
        return self.variantIndexOf(t, "None") orelse self.variantIndexOf(t, "Err");
    }

    /// How many values a variant carries.
    pub fn variantFieldCount(self: *const Typing, t: TypeId, i: u32) u32 {
        const e = self.get(t).enum_;
        return self.variants.items(.field_count)[e.first_variant + i];
    }

    pub fn variantFieldType(self: *const Typing, t: TypeId, i: u32, f: u32) TypeId {
        const e = self.get(t).enum_;
        const first_field = self.variants.items(.first_field)[e.first_variant + i];
        return self.fields.items(.ty)[first_field + f];
    }

    /// Where one of a variant's values begins: past the tag, then placed like
    /// any other run.
    pub fn variantFieldOffset(self: *const Typing, t: TypeId, i: u32, f: u32) u32 {
        const e = self.get(t).enum_;
        const variant_at = e.first_variant + i;
        const first = self.variants.items(.first_field)[variant_at];
        const count = self.variants.items(.field_count)[variant_at];
        if (self.placedOffset(first, count, f)) |offset| return offset;
        return self.arrangement().offsetIn(
            first,
            count,
            f,
            Layout.tag_width,
        );
    }

    pub fn layoutOf(self: *const Typing, t: TypeId) Layout {
        return self.arrangement().layoutOf(t);
    }

    pub fn fieldCount(self: *const Typing, t: TypeId) u32 {
        return switch (self.get(t)) {
            .struct_ => |x| x.field_count,
            .closure => |closure| self.fieldCount(closure.environment),
            else => 0,
        };
    }

    pub fn fieldName(self: *const Typing, t: TypeId, i: u32) []const u8 {
        if (self.get(t) == .closure) return self.fieldName(self.get(t).closure.environment, i);
        const x = self.get(t).struct_;
        return self.fields.items(.name)[x.first_field + i];
    }

    pub fn fieldType(self: *const Typing, t: TypeId, i: u32) TypeId {
        if (self.get(t) == .closure) return self.fieldType(self.get(t).closure.environment, i);
        const x = self.get(t).struct_;
        return self.fields.items(.ty)[x.first_field + i];
    }

    /// Resolves a normalized field-name ID through the same field lookup as
    /// source expressions. Spellings are registered once per distinct name.
    pub fn fieldIndexByName(self: *const Typing, t: TypeId, name: StringId) ?u32 {
        if (self.get(t) == .closure) return self.fieldIndexByName(self.get(t).closure.environment, name);
        const spelling = self.field_name_spellings.get(name) orelse return null;
        return (self.lookupField(t, spelling) orelse return null).index;
    }

    /// Which part a name selects, with everything a caller needs to reach it.
    ///
    /// One lookup rather than one per caller: reading a field and writing one
    /// asked the same question in two places, and two loops over the same
    /// table are two chances to disagree about which part a name means.
    pub fn lookupField(self: *const Typing, t: TypeId, name: []const u8) ?struct {
        index: u32,
        ty: TypeId,
        offset: u32,
    } {
        const shape = switch (self.get(t)) {
            .struct_ => |x| x,
            else => return null,
        };
        const at = self.fieldNamed(shape.first_field, shape.field_count, name) orelse return null;
        return .{
            .index = at,
            .ty = self.fields.items(.ty)[shape.first_field + at],
            .offset = self.fieldOffset(t, at),
        };
    }

    pub const TextFields = struct {
        pub const Part = struct { ty: TypeId, offset: u32 };
        at: Part,
        len: Part,
    };

    /// Resolve the stored byte span once for text construction and runtime ABI.
    /// Offsets are relative to the complete descriptor: a `Str`'s, through its
    /// `bytes` slice, or a byte slice's own, which is what `embed_bytes` and a
    /// constant holding it lay out over the same pool of bytes.
    pub fn textFields(self: *const Typing, t: TypeId) ?TextFields {
        const bytes = self.lookupField(t, "bytes") orelse return self.spanFields(t, 0);
        return self.spanFields(bytes.ty, bytes.offset);
    }

    fn spanFields(self: *const Typing, slice: TypeId, base: u32) ?TextFields {
        const at = self.lookupField(slice, "at") orelse return null;
        const len = self.lookupField(slice, "len") orelse return null;
        return .{
            .at = .{ .ty = at.ty, .offset = base + at.offset },
            .len = .{ .ty = len.ty, .offset = base + len.offset },
        };
    }

    /// Which part of a run carries a name, or null where none does.
    ///
    /// A run is ordered by name once, the first time one of its parts is asked
    /// for, and searched after that: reading the run for every part named cost
    /// the square of its width, which is what a literal naming every field of
    /// a wide type asks for.
    ///
    /// A part's name never changes once its run is appended -- only its type is
    /// written later -- so the order outlives the writes that drop the layouts
    /// beside it.
    fn fieldNamed(self: *const Typing, first: u32, count: u32, name: []const u8) ?u32 {
        if (count == 0) return null;
        const names = self.fields.items(.name);

        if (first + count <= self.sorted.len) {
            if (!self.sorted[first]) self.orderByName(first, count);
            const order = self.by_name[first..][0..count];

            var lo: usize = 0;
            var hi: usize = order.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                if (std.mem.lessThan(u8, names[first + order[mid]], name)) {
                    lo = mid + 1;
                } else hi = mid;
            }
            if (lo < order.len and std.mem.eql(u8, names[first + order[lo]], name)) {
                return order[lo];
            }
            return null;
        }

        for (names[first..][0..count], 0..) |field_name, i| {
            if (std.mem.eql(u8, field_name, name)) return @intCast(i);
        }
        return null;
    }

    /// Ties are broken by position, so that two parts spelled alike answer with
    /// the earlier one -- which is what reading the run gave.
    const ByName = struct {
        names: []const []const u8,

        fn before(self: ByName, a: u32, b: u32) bool {
            return switch (std.mem.order(u8, self.names[a], self.names[b])) {
                .lt => true,
                .gt => false,
                .eq => a < b,
            };
        }
    };

    fn orderByName(self: *const Typing, first: u32, count: u32) void {
        const order = self.by_name[first..][0..count];
        for (order, 0..) |*at, i| at.* = @intCast(i);
        const names = self.fields.items(.name)[first..][0..count];
        std.mem.sortUnstable(u32, order, ByName{ .names = names }, ByName.before);
        self.sorted[first] = true;
    }

    /// Where a field begins, which is the one thing lowering needs and the
    /// backend never sees -- an offset reaches it baked into an instruction.
    pub fn fieldOffset(self: *const Typing, t: TypeId, i: u32) u32 {
        return switch (self.get(t)) {
            .struct_ => |x| self.placedOffset(x.first_field, x.field_count, i) orelse
                self.arrangement().offsetIn(x.first_field, x.field_count, i, 0),
            // Zero because none of these has a field to place, and every
            // caller asks only after settling that the type is a structure.
            // Named rather than defaulted: for a kind added later, zero is
            // "every field starts where the value does", which is an answer a
            // program can act on -- so the addition decides here before the
            // build succeeds.
            .closure => |closure| self.fieldOffset(closure.environment, i),
            .integer, .open_integer, .open_type, .boolean, .float, .poison, .unit, .never, .enum_, .parameter, .array, .newtype, .callable, .borrow => 0,
        };
    }

    fn placedOffset(self: *const Typing, first: u32, count: u32, want: u32) ?u32 {
        if (count == 0 or first + count > self.placed_at.len or
            self.placed_at[first] != self.generation)
        {
            return null;
        }
        return self.offsets[first + want];
    }

    pub fn exprType(self: *const Typing, id: ExprId) TypeId {
        return self.expr_types[id.index()];
    }

    pub fn constructionType(self: *const Typing, id: ExprId) TypeId {
        if (id.index() >= self.construction_types.len) return .poison;
        return self.construction_types[id.index()];
    }

    /// What a declaration was written to return, before substitution. Poison
    /// where the annotation was not readable, which is already reported.
    pub fn declReturn(self: *const Typing, decl: DeclId) TypeId {
        return self.decl_returns.get(decl);
    }

    /// A structural signature spelled with the parameter names `names`, as
    /// a declaration writes them; the caller owns the text.
    pub fn spellCallable(self: *const Typing, gpa: std.mem.Allocator, ty: TypeId, names: []const []const u8) ![]u8 {
        const signature = self.get(ty).callable;
        var rendered: TypeDisplay = .{};
        errdefer rendered.text.deinit(gpa);
        try renderCallable(gpa, &rendered, self.*, self.callableParams(signature), signature.result, signature.contracts, signature.invocation, signature.independent, names);
        return rendered.finish(gpa);
    }

    test "a view spells a signature with names and keeps its contracts' positions" {
        const gpa = testing.allocator;
        var b = try Builder.init(gpa);
        defer b.deinit();
        const signature = try b.internCallable(&.{.{ .spelling = "", .convention = .read, .ty = .u8, .default = .absent }}, .u8, &.{}, .read);
        const spelled = try b.view().spellCallable(gpa, signature, &.{"value"});
        defer gpa.free(spelled);
        try testing.expectEqualStrings("fn(read value: UInt8) -> UInt8", spelled);
    }

    /// A type as the checker spells it, or null where it settled none: an
    /// expression already reported on is left with the type that stands in for
    /// one, and an editor or a dump showing that would say something no pass
    /// agrees with.
    pub fn settledName(self: *const Typing, t: TypeId) ?[]const u8 {
        if (t == .poison) return null;
        return self.nameOf(t);
    }

    test "settledName names a settled type and none for the stand-in of an unsettled one" {
        var builder = try Typing.Builder.init(testing.allocator);
        defer builder.deinit();
        var typing = try builder.finish(.empty);
        defer typing.deinit(testing.allocator);
        try testing.expectEqualStrings("UInt8", typing.settledName(.u8).?);
        try testing.expect(typing.settledName(.poison) == null);
    }

    pub fn bindingType(self: *const Typing, b: ids.BindingId) TypeId {
        return self.binding_types.get(b);
    }

    pub fn get(self: *const Typing, t: TypeId) Type {
        return self.pool[@intFromEnum(t)];
    }

    /// Whether a type can represent a value. Takes an `i128` so one signature
    /// covers both `Int64`'s minimum and `UInt64`'s maximum, which is why the
    /// checker folds constants into `i128` rather than the operand type.
    pub fn holds(self: *const Typing, t: TypeId, value: i128) bool {
        return switch (self.get(t)) {
            .integer => |i| blk: {
                const b = TypeId.boundsOf(i.signed, i.bits);
                break :blk value >= b.min and value <= b.max;
            },
            // Not a numeric domain: no integer is a bool.
            .boolean => false,
            // An integer value never inhabits a float, because nothing
            // converts implicitly -- `1.0 + 1` is a mismatch, not a promotion.
            .float => false,
            // Poison holds anything, so an already-reported expression never
            // produces a second range diagnostic. An open integer holds
            // anything for now: its values are checked when its type settles.
            .poison, .open_integer => true,
            .unit, .never, .open_type => false,
            // Not a numeric domain either: an enum's values are its variants,
            // and a structure's are whatever its parts hold. A parameter has
            // no domain of its own at all -- it stands for one.
            .enum_, .struct_, .parameter, .array, .callable, .closure, .borrow => false,
            // A refined newtype's domain is its own bounds, not its base's --
            // that is what the clause narrows. An unrefined one admits
            // exactly what its base does, which is what "unrefined" means.
            .newtype => |n| if (n.refined) value >= n.lo and value <= n.hi else self.holds(n.base, value),
        };
    }

    /// Accumulates types while checking. The checker owns one and discards it.
    pub const Builder = struct {
        const ArrayKey = struct { element: TypeId, count: u32 };

        gpa: std.mem.Allocator,
        constant_pool: *const constants.Pool = &.{},
        /// Whether the pool is finished. Sealed, every growth path below is a
        /// named defect: the pass that completes the set seals it, so a later
        /// pass reaching for a type the set does not hold fails at the reach
        /// rather than quietly extending a table another pass answered from.
        /// Reading -- an intern that finds its type, a lookup, a view -- works
        /// sealed or not, because reading grows nothing.
        sealed: bool = false,
        /// Selection can be retained once implementation heads and requirements
        /// are complete. Header construction still asks the evolving relation.
        implementations_settled: bool = false,
        implementation_selections: ImplementationSelections = .{},
        /// Which implementation relates each trait to each type. Borrowed from
        /// the typing this builder was reopened from and never freed here: a
        /// builder appends types, and coherence was settled before it existed.
        ///
        /// Carried so that a view answers this the way the finished typing
        /// does. It did not, so every reader reaching the pool through a
        /// builder -- which is every reader after the checker -- saw no
        /// implementations at all and had to work the relation out again.
        implementations: []const Implementation = &.{},
        contextual_constraints: ContextualConstraints = .{},
        /// And which of them each declaration sits inside, carried for the
        /// same reason and borrowed the same way.
        impl_of_decl: []const u32 = &.{},
        /// Borrowed together with `implementations`, using the same row order.
        /// Settling a projected member reads this index to select its supplier.
        impl_index: ImplIndex = .{},
        /// Which member of an implementation supplies which signature, and
        /// what each declaration was settled to -- the other two steps of that
        /// same reading, borrowed for the same reason.
        supply: SupplyIndex = .{},
        /// Borrowed from the checker, which owns it: readable, so this pass
        /// cannot write into another's answer or free memory it was lent.
        decl_returns: Returns.Reading = .empty,
        /// While the checker settles implementations' associated types, the
        /// members it has not settled yet, borrowed from it. A settled
        /// reference the checker reads (`reading_reference`) reads none of
        /// them: `settledBy` records in `unsettled_read` the one it was asked
        /// for, so the definition reading it waits for it. A member read while
        /// a type's fields are laid out is not a definition's reference and
        /// reads what has been settled so far.
        unsettled_members: ?*const std.AutoHashMapUnmanaged(DeclId, void) = null,
        unsettled_read: DeclId = .none,
        reading_reference: bool = false,
        /// `Typing.declared_requirements`, borrowed for the same reason: minting
        /// a projection is a reading of what its declaration was bounded by.
        declared_requirements: []const CapabilityRequirement = &.{},
        /// `Typing.declared_traits`, borrowed for the reason beside it: the two
        /// halves of what a declared type's bounds promise are read together.
        declared_traits: []const []const BoundTrait = &.{},
        declared_callables: []const []const TypeId = &.{},
        pool: std.ArrayList(Type) = .empty,
        variants: VariantList = .empty,
        fields: FieldList = .empty,
        callable_params: std.ArrayList(CallableParam) = .empty,
        /// Which callable entries carry each exact structural signature.
        ///
        /// Declaration signatures can be as numerous as declarations, so each
        /// lookup is confined to the candidates carrying its hash rather than
        /// the whole type pool. Hash collisions remain exact because every
        /// candidate's complete parameter run is compared before reuse.
        interned_callables: Chain(.newest_first) = .empty,
        interned_arrays: std.AutoHashMapUnmanaged(ArrayKey, TypeId) = .empty,
        borrowed_types: std.AutoHashMapUnmanaged(TypeId, TypeId) = .empty,
        capability_facts: CapabilityFacts = .{},
        scoped_capability_facts: ScopedCapabilityFacts = .{},
        prepared_implementations: PreparedImplementations = .{},
        dependency_facts: BorrowContainment = .{},
        writer_facts: BorrowContainment = .{},
        certified_storage: DeclId = .none,
        certified_buffer: DeclId = .none,
        certified_slice: DeclId = .none,
        /// `mem.ClosureEntry`: its instance at a callable type is the entry
        /// signature an erased closure is called through.
        certified_closure_entry: DeclId = .none,
        /// `Typing.tuple_decls`: the declarations whose instances are spelled
        /// as tuples.
        tuple_decls: [node.max_tuple_arity - 1]DeclId = [_]DeclId{DeclId.none} ** (node.max_tuple_arity - 1),
        observation_traits: []const bool = &.{},
        closure_args: std.ArrayList(TypeId) = .empty,
        interned_closures: Chain(.newest_first) = .empty,
        empty_capture_record: TypeId = .poison,
        /// The exact source signature of each closure identity, borrowed from
        /// the checker or a finished typing so implementation lookup answers
        /// callable bounds identically in both phases.
        closure_descriptors: []const ClosureDescriptor = &.{},
        closure_release: ?ClosureRelease = null,
        /// The checker's open-type table, lent for the duration of a check.
        open_types: ?*OpenTypes = null,
        /// What a symbol calls each module, borrowed from the pool being
        /// reopened. Lowering spells symbols from a view of this builder, so a
        /// table the view did not carry left every symbol unqualified.
        module_paths: []const []const u8 = &.{},
        expr_types: std.ArrayList(TypeId) = .empty,
        construction_types: std.ArrayList(TypeId) = .empty,
        /// Which declaration each declared type came from, so substitution can
        /// find the template to instantiate a second time.
        templates: std.ArrayList(Template) = .empty,
        /// `Typing.template_of`, grown as templates are noted.
        template_of: std.ArrayList(u32) = .empty,
        /// Every instantiation already interned, keyed by the declaration and
        /// the arguments it was given.
        instances: std.ArrayList(Instance) = .empty,
        /// `Typing.instance_of`, grown as instantiations are minted.
        instance_of: std.ArrayList(u32) = .empty,
        /// Whether every instantiation has been filled from its template since
        /// the templates were last written to.
        ///
        /// An instantiation minted before its template held anything holds
        /// nothing either, so a reader asking what one holds before the refill
        /// gets an answer that is empty rather than wrong -- which is the kind
        /// of answer a case cannot distinguish from a correct one. Asserted
        /// where such a reader runs, so the order is a build failure rather
        /// than a type nobody can explain.
        /// Which entries of `instances` carry each `(decl, args)` pair the pool
        /// interns on.
        minted: Chain(.newest_first) = .empty,
        /// The interpolations substitution minted, and the pieces each holds.
        /// Grown as they are minted rather than sized with the pool, which is
        /// what keeps them the size of the literals a program substitutes into.
        interpolations: std.ArrayList(Interpolated) = .empty,
        interpolation_pieces: std.ArrayList(TypeId) = .empty,
        interpolation_formats: std.ArrayList(node.InterpolationFormat) = .empty,
        interpolation_borrows: std.ArrayList(bool) = .empty,
        interpolation_of: std.ArrayList(u32) = .empty,
        interned_interpolations: Chain(.newest_first) = .empty,
        /// Where each `(owner, index)` type parameter sits in the pool.
        ///
        /// A scan found one, so interning a declaration's parameters read the
        /// whole pool once per parameter -- the product a module of many
        /// generic declarations pays, and the pool holds every type in the
        /// program rather than every parameter. The pair is exact rather than
        /// hashed from a slice, so this needs no chain the way `minted` does.
        parameters: std.AutoHashMapUnmanaged(u64, u32) = .empty,
        /// Every settled reference awaiting an instantiation, the runs of trait
        /// arguments their keys hold, and which entry each type is.
        standins: std.ArrayList(Standin) = .empty,
        standin_args: std.ArrayList(TypeId) = .empty,
        standin_of: std.ArrayList(u32) = .empty,
        /// Which entries of `standins` carry each key, so one written twice is
        /// one type. Keyed by the whole of it -- trait, arguments, head and
        /// member -- because that is what decides when two of them are one:
        /// `W.Item` and `V.Item` are two types, and `W.Item` written twice is
        /// one.
        awaiting: Chain(.newest_first) = .empty,
        /// The spellings this builder minted for instantiations. A declared
        /// type's name is source text and is borrowed; an instantiation's is
        /// built, so someone has to give it back.
        owned_names: std.ArrayList([]const u8) = .empty,
        owned_contracts: std.ArrayList([]const CallableContract) = .empty,
        owned_bounds: std.ArrayList([]const BoundTrait) = .empty,
        owned_callable_bounds: std.ArrayList([]const TypeId) = .empty,
        /// Storage for the instances' argument lists.
        instance_args: std.ArrayList(TypeId) = .empty,
        /// What each pool entry was already laid out as, one entry per pool
        /// entry, emptied whenever a type's parts change.
        ///
        /// A type reached k times in a tree was laid out k times, so one query
        /// cost the size of the fully expanded tree -- exponential in nesting
        /// depth for a linear number of declarations, and a thirty-line file
        /// took minutes. Appending a type cannot change what another is laid
        /// out as, so a new entry arrives with the type it describes; writing
        /// a part can change every type above it, so the whole table is invalidated.
        laid_out: std.ArrayList(StampedLayout) = .empty,
        /// Whether each pool type has an open integer anywhere inside it:
        /// 0 not yet asked, 1 no, 2 yes. A type never changes once interned,
        /// so the answer is kept for every later question.
        open_mentions: std.ArrayList(u8) = .empty,
        /// Whether each pool type is ground, and whether it holds anything
        /// nothing settled: 0 not yet asked, 1 no, 2 yes. Types are shared
        /// between the types built from them, so a walk that reads a type once
        /// per path rather than once is exponential in how deep they nest. Kept
        /// for every later question, because a type never changes once interned.
        ground_memo: std.ArrayList(u8) = .empty,
        unsettled_memo: std.ArrayList(u8) = .empty,
        /// `Arrangement.offsets` and its companion, grown with `fields`.
        offsets: std.ArrayList(u32) = .empty,
        placed_at: std.ArrayList(u32) = .empty,
        /// Which generation the stamps above are read against. Bumped where a
        /// part is written, which is the whole of the invalidation.
        generation: u32 = 1,
        by_name: std.ArrayList(u32) = .empty,
        sorted: std.ArrayList(bool) = .empty,

        /// Whether the complete-template refill has run.
        refilled: bool = false,

        /// Records that a declared type came from a declaration.
        ///
        /// In declaration order, and that is load-bearing twice over. It is
        /// what lets `templateOf` search the list rather than walk it, and it
        /// is what makes the first entry `template_of` keeps the one a walk in
        /// declaration order would have stopped at. One pass over the
        /// declarations interns the head types, ascending, and a declaration
        /// declares at most one type -- so the list is sorted and has no
        /// repeats. Asserted rather than assumed, because a caller added later
        /// would otherwise turn both of those into wrong answers instead of
        /// slow ones, and the assert is gone in a release build.
        pub fn noteTemplate(self: *Builder, decl: DeclId, module: u32, ty: TypeId) !void {
            if (self.templates.items.len > 0) {
                std.debug.assert(self.templates.items[self.templates.items.len - 1].decl.index() < decl.index());
            }
            const at: u32 = @intCast(self.templates.items.len);
            try self.templates.append(self.gpa, .{ .decl = decl, .module = module, .ty = ty });
            try self.noteAt(&self.template_of, ty, at, Typing.not_a_template);
        }

        /// The type a declaration declares, or null where it declares none.
        /// The finished typing answers this too, so a routine reading it works
        /// against a pool being built and against one that is done.
        pub fn typeOfDecl(self: *const Builder, decl: DeclId) ?TypeId {
            return (lookupTemplate(self.templates.items, decl) orelse return null).ty;
        }

        pub fn argsOf(self: *const Builder, i: Instance) []const TypeId {
            return self.instance_args.items[i.first_arg..][0..i.arg_count];
        }

        pub fn callableParams(self: *const Builder, signature: CallableSignature) []const CallableParam {
            return self.callable_params.items[signature.first_param..][0..signature.param_count];
        }

        pub fn closureArgs(self: *const Builder, closure: ClosureType) []const TypeId {
            return self.closure_args.items[closure.first_arg..][0..closure.arg_count];
        }

        pub fn closureImplArgs(self: *const Builder, closure: ClosureType) []const TypeId {
            return self.closure_args.items[closure.first_arg + closure.arg_count ..][0..closure.impl_arg_count];
        }

        pub fn closureOf(self: *const Builder, closure: ids.ClosureId) ClosureDescriptor {
            return self.closure_descriptors[closure.index()];
        }

        pub fn closureSignature(self: *Builder, closure: ClosureType) !TypeId {
            const descriptor = self.closureOf(closure.closure);
            if (descriptor.enclosing == .none) return descriptor.signature;
            const own = try self.gpa.dupe(TypeId, self.closureArgs(closure));
            defer self.gpa.free(own);
            const implementation_args = try self.gpa.dupe(TypeId, self.closureImplArgs(closure));
            defer self.gpa.free(implementation_args);
            const at = try descriptor.parameters.instantiation(self.gpa, .{ .closure = closure.closure }, descriptor.enclosing, own, closure.self_ty, implementation_args);
            defer self.gpa.free(at.args);
            return at.through(self, descriptor.signature);
        }

        pub fn prepareClosureBodySignature(self: *Builder, ty: TypeId) !void {
            const closure = self.get(ty).closure;
            if (closure.body_signature != .poison) return;
            const source = try self.closureSignature(closure);
            var body = source;
            if (closure.environment != .unit) {
                const signature = self.get(source).callable;
                const written = self.callableParams(signature);
                const params = try self.gpa.alloc(CallableParam, written.len + 1);
                defer self.gpa.free(params);
                @memcpy(params[0..written.len], written);
                params[written.len] = .{
                    .spelling = "$environment",
                    .convention = self.closureOf(closure.closure).invocation,
                    .ty = closure.environment,
                    .default = .absent,
                    .stable_address = true,
                };
                body = try self.internCallable(params, signature.result, signature.contracts, signature.invocation);
            }
            self.pool.items[ty.index()].closure.body_signature = body;
        }

        fn specializedClosureEnvironment(self: *Builder, closure: ids.ClosureId, args: []const TypeId, impl_args: []const TypeId, self_ty: TypeId, key: u64) !TypeId {
            if (closure.index() >= self.closure_descriptors.len) return .unit;
            const descriptor = self.closureOf(closure);
            if (descriptor.environment == .unit) return .unit;
            const shape = self.get(descriptor.environment).struct_;
            const fields = try self.gpa.alloc(Field, shape.field_count);
            defer self.gpa.free(fields);
            for (fields, 0..) |*field, i| field.* = .{
                .name = self.fields.items(.name)[shape.first_field + i],
                .ty = self.fields.items(.ty)[shape.first_field + i],
            };
            var changed = false;
            if (descriptor.enclosing != .none) {
                const at = try descriptor.parameters.instantiation(self.gpa, .{ .closure = closure }, descriptor.enclosing, args, self_ty, impl_args);
                defer self.gpa.free(at.args);
                for (fields) |*field| {
                    const before = field.ty;
                    field.ty = try at.through(self, field.ty);
                    changed = changed or before != field.ty;
                }
            }
            if (!changed) return descriptor.environment;
            const name = try std.fmt.allocPrint(self.gpa, "captures.{d}.{x}", .{ closure.index(), key });
            self.owned_names.append(self.gpa, name) catch |err| {
                self.gpa.free(name);
                return err;
            };
            return self.addStruct(name, .copyable, fields);
        }

        pub fn internClosure(self: *Builder, closure: ids.ClosureId, args: []const TypeId, impl_args: []const TypeId, self_ty: TypeId) !TypeId {
            const key = closureTypeHash(closure, args, impl_args, self_ty);
            var run = self.interned_closures.walk(key);
            while (run.next()) |raw| {
                const id = TypeId.at(raw);
                const held = self.get(id).closure;
                if (held.closure == closure and held.self_ty == self_ty and std.mem.eql(TypeId, self.closureArgs(held), args) and std.mem.eql(TypeId, self.closureImplArgs(held), impl_args)) return id;
            }

            const owned_args = try self.gpa.dupe(TypeId, args);
            defer self.gpa.free(owned_args);
            const owned_impl_args = try self.gpa.dupe(TypeId, impl_args);
            defer self.gpa.free(owned_impl_args);
            const environment = try self.specializedClosureEnvironment(closure, owned_args, owned_impl_args, self_ty, key);
            const first: u32 = @intCast(self.closure_args.items.len);
            try self.closure_args.appendSlice(self.gpa, owned_args);
            errdefer self.closure_args.shrinkRetainingCapacity(first);
            try self.closure_args.appendSlice(self.gpa, owned_impl_args);
            const id = try self.appendFresh(.{ .closure = .{
                .closure = closure,
                .environment = environment,
                .first_arg = first,
                .arg_count = @intCast(args.len),
                .impl_arg_count = @intCast(impl_args.len),
                .self_ty = self_ty,
            } });
            try self.interned_closures.note(self.gpa, key, @intFromEnum(id));
            return id;
        }

        /// The declaration and arguments an instantiation came from, or null
        /// where the type is not one.
        pub fn instanceOf(self: *const Builder, t: TypeId) ?Instance {
            return lookupInstance(self.instance_of.items, self.instances.items, t);
        }

        /// The head a type reaches implementations through. The finished typing
        /// answers this too, so a lookup made while the pool is open finds what
        /// one made after it closes finds.
        pub fn headOf(self: *const Builder, t: TypeId) Head {
            return self.view().headOf(t);
        }

        /// What a type applies to its head, read through the same routine the
        /// finished typing answers with, and for the same reason `headOf` is.
        pub fn appliedTo(self: *const Builder, t: TypeId) []const TypeId {
            return self.view().appliedTo(t);
        }

        /// An interpolation with every piece substituted, interned on both
        /// what it holds and how each value renders.
        fn substituteInterpolation(
            self: *Builder,
            ty: TypeId,
            substitution: *TypeSubstitution,
        ) std.mem.Allocator.Error!TypeId {
            const shape = self.pool.items[@intFromEnum(ty)].struct_;
            const count = shape.field_count;

            const held = try self.gpa.alloc(Field, count);
            defer self.gpa.free(held);

            var moved = false;
            for (0..count) |i| {
                const field_at = shape.first_field + i;
                const field_name = self.fields.items(.name)[field_at];
                const was = self.fields.items(.ty)[field_at];
                const now = try substitution.apply(self, was);
                if (now != was) moved = true;
                held[i] = .{ .name = field_name, .ty = now };
            }
            if (!moved) return ty;

            const source_formats = self.interpolationFormats(ty);
            const formats = try self.gpa.dupe(node.InterpolationFormat, source_formats);
            defer self.gpa.free(formats);
            const borrows = try self.gpa.dupe(bool, self.view().interpolationBorrowsAll(ty));
            defer self.gpa.free(borrows);
            return self.internInterpolation(held, formats, borrows);
        }

        /// Mints or reuses one interpolation identified by its field types, the
        /// selected format of each embedded value, and whether each embedded
        /// value is borrowed. A borrowed value's field is `borrow T`.
        pub fn internInterpolation(
            self: *Builder,
            held: []const Field,
            formats: []const node.InterpolationFormat,
            borrows: []const bool,
        ) std.mem.Allocator.Error!TypeId {
            std.debug.assert(held.len % 2 == 1);
            std.debug.assert(formats.len == held.len / 2);
            std.debug.assert(borrows.len == formats.len);
            if (self.interpolationAt(held, formats, borrows)) |already| return already;

            var spelled: TypeDisplay = .{};
            defer spelled.text.deinit(self.gpa);
            try spelled.appendSlice(self.gpa, interpolation_type_name);
            var written: usize = 0;
            for (held, 0..) |field, i| {
                if (i % 2 == 0) continue;
                try spelled.appendSlice(self.gpa, if (written == 0) " " else ", ");
                // A borrowed value is spelled `borrow T` after its field, and
                // a held `borrow T` value as `copy borrow T`, so the two names
                // differ as the two types do.
                if (!borrows[written] and self.get(field.ty) == .borrow) try spelled.appendSlice(self.gpa, "copy ");
                try spelled.appendSlice(self.gpa, self.nameOf(field.ty));
                if (!formats[written].eql(.display)) {
                    var spec: [32]u8 = undefined;
                    var w: std.Io.Writer = .fixed(&spec);
                    w.print(":{f}", .{formats[written]}) catch unreachable;
                    try spelled.appendSlice(self.gpa, w.buffered());
                }
                written += 1;
            }
            try spelled.append(self.gpa, '}');

            const name = try spelled.finish(self.gpa);
            self.owned_names.append(self.gpa, name) catch |err| {
                self.gpa.free(name);
                return err;
            };

            const made = try self.addStruct(name, .copyable, held);
            const at: u32 = @intCast(self.interpolations.items.len);
            const first_piece: u32 = @intCast(self.interpolation_pieces.items.len);
            const first_format: u32 = @intCast(self.interpolation_formats.items.len);
            try self.interpolation_pieces.ensureUnusedCapacity(self.gpa, held.len);
            try self.interpolation_formats.ensureUnusedCapacity(self.gpa, formats.len);
            try self.interpolation_borrows.ensureUnusedCapacity(self.gpa, borrows.len);
            try self.interpolations.ensureUnusedCapacity(self.gpa, 1);
            for (held) |field| self.interpolation_pieces.appendAssumeCapacity(field.ty);
            self.interpolation_formats.appendSliceAssumeCapacity(formats);
            self.interpolation_borrows.appendSliceAssumeCapacity(borrows);
            self.interpolations.appendAssumeCapacity(.{
                .ty = made,
                .first_piece = first_piece,
                .piece_count = @intCast(held.len),
                .first_format = first_format,
                .format_count = @intCast(formats.len),
            });
            const mapped = self.interpolation_of.items.len;
            try self.interpolation_of.resize(self.gpa, self.pool.items.len);
            @memset(self.interpolation_of.items[mapped..], not_an_interpolation);
            self.interpolation_of.items[@intFromEnum(made)] = at;
            try self.interned_interpolations.note(self.gpa, interpolationKey(held, formats, borrows), at);
            return made;
        }

        /// Where an interpolation with exactly these pieces and modes was
        /// already minted.
        fn interpolationAt(
            self: *const Builder,
            held: []const Field,
            formats: []const node.InterpolationFormat,
            borrows: []const bool,
        ) ?TypeId {
            var run = self.interned_interpolations.walk(interpolationKey(held, formats, borrows));
            while (run.next()) |at| {
                const one = self.interpolations.items[at];
                if (one.piece_count != held.len or one.format_count != formats.len) continue;
                const pieces = self.interpolation_pieces.items[one.first_piece..][0..one.piece_count];
                const recorded_formats = self.interpolation_formats.items[one.first_format..][0..one.format_count];
                var same = true;
                for (recorded_formats, formats) |recorded, format| {
                    if (!recorded.eql(format)) same = false;
                }
                if (!std.mem.eql(bool, self.interpolation_borrows.items[one.first_format..][0..one.format_count], borrows)) same = false;
                for (pieces, held) |piece, field| {
                    if (piece != field.ty) {
                        same = false;
                        break;
                    }
                }
                if (same) return one.ty;
            }
            return null;
        }

        fn interpolationKey(held: anytype, formats: []const node.InterpolationFormat, borrows: []const bool) u64 {
            var h = std.hash.Wyhash.init(0);
            for (held) |part| {
                const ty: TypeId = if (@TypeOf(part) == Field) part.ty else part;
                const id: u32 = @intFromEnum(ty);
                h.update(std.mem.asBytes(&id));
            }
            for (formats) |format| {
                const raw = format.bits();
                h.update(std.mem.asBytes(&raw));
            }
            h.update(std.mem.sliceAsBytes(borrows));
            return h.final();
        }

        /// The chain key for the pair the pool interns an instantiation on.
        fn mintedKey(decl: u32, args: []const TypeId) u64 {
            var h = std.hash.Wyhash.init(decl);
            for (args) |a| {
                const id: u32 = @intFromEnum(a);
                h.update(std.mem.asBytes(&id));
            }
            return h.final();
        }

        /// Where `(decl, args)` was already minted, or null.
        ///
        /// Interning compared the pair against every instantiation already
        /// minted, so building a pool of I of them cost I squared -- and
        /// grouping by declaration would not have helped, since one generic
        /// instantiated many times is the shape that gets large. `Mono.idFor`
        /// in lowering records the same lesson for functions.
        ///
        /// The chain holds indices into `instances` and nothing else, so it is
        /// a way to reach the answer rather than a second copy of it. Every
        /// candidate it offers is still compared on the pair itself, which is
        /// what makes a collision cost a comparison rather than a wrong type.
        fn mintedAt(self: *const Builder, decl: DeclId, args: []const TypeId) ?u32 {
            var run = self.minted.walk(mintedKey(decl.index(), args));
            while (run.next()) |at| {
                const i = self.instances.items[at];
                if (i.decl == decl and
                    i.arg_count == args.len and
                    std.mem.eql(TypeId, self.argsOf(i), args)) return at;
            }
            return null;
        }

        /// Puts a newly minted instantiation at the head of its chain.
        fn noteMinted(self: *Builder, at: u32, decl: u32, args: []const TypeId) !void {
            try self.minted.note(self.gpa, mintedKey(decl, args), at);
        }

        /// Records which entry of a list beside the pool a type is the subject
        /// of: which instantiation it is, which declaration declares it, which
        /// settled reference it stands for.
        ///
        /// One routine, because the tables answer one question about three
        /// lists and the answer is one policy. **The first entry wins**, so a
        /// type two entries name answers with the earlier one -- which is what
        /// a walk of the list in order answers, and each of these tables
        /// stands in for such a walk.
        ///
        /// The table reaches only as far as the last type noted, and `absent`
        /// is what a lookup reads for a type inside it that no entry names.
        /// Grown rather than sized with the pool, so it stays the size of what
        /// the program wrote rather than of every type the checker interned.
        fn noteAt(
            self: *Builder,
            table: *std.ArrayList(u32),
            t: TypeId,
            at: u32,
            absent: u32,
        ) !void {
            const id = @intFromEnum(t);
            if (id >= table.items.len) {
                try table.appendNTimes(self.gpa, absent, id + 1 - table.items.len);
            }
            if (table.items[id] == absent) table.items[id] = at;
        }

        /// Replaces `decl`'s parameters with `args`, everywhere in `ty`.
        ///
        /// A field may be an instantiation of its own -- `Outer[T]` holding an
        /// `Inner[T]` -- so this recurses through arguments and instantiates
        /// again where any of them moved. A type mentioning none of `decl`'s
        /// parameters comes back unchanged, which is what keeps a concrete
        /// field from being copied per instantiation.
        pub fn substitute(
            self: *Builder,
            ty: TypeId,
            decl: u32,
            args: []const TypeId,
        ) std.mem.Allocator.Error!TypeId {
            return self.substituteWithin(.none, ty, decl, args);
        }

        /// `substitute`, with a member projected from a type that still holds
        /// a parameter read in `owner`'s scope, so what `owner`'s own `where`
        /// clauses prove about that parameter selects the implementation.
        pub fn substituteWithin(
            self: *Builder,
            owner: DeclId,
            ty: TypeId,
            decl: u32,
            args: []const TypeId,
        ) std.mem.Allocator.Error!TypeId {
            if (self.substitutionLeaf(ty, decl, args)) |answer| return answer;
            const held = try self.gpa.dupe(TypeId, args);
            defer self.gpa.free(held);
            var substitution: TypeSubstitution = .{ .decl = decl, .args = held, .within = owner };
            defer substitution.memo.deinit(self.gpa);
            return substitution.apply(self, ty);
        }

        /// Leaves cannot grow the pool, so they need neither a stable copy
        /// of the replacement vector nor a structural traversal memo.
        fn substitutionLeaf(self: *const Builder, ty: TypeId, decl: u32, args: []const TypeId) ?TypeId {
            return switch (self.get(ty)) {
                .parameter => |parameter| if (self.standinOf(ty) != null)
                    null
                else if (parameter.owner != decl)
                    ty
                else if (parameter.index < args.len)
                    args[parameter.index]
                else
                    .poison,
                .integer, .open_integer, .open_type, .boolean, .float, .poison, .unit, .never => ty,
                .struct_ => if (self.isInterpolation(ty) or self.instanceOf(ty) != null) null else ty,
                .enum_, .newtype => if (self.instanceOf(ty) != null) null else ty,
                .borrow, .array, .callable, .closure => null,
            };
        }

        /// Memoized only for this immutable replacement key. Pool growth may
        /// intern answers, but a later query sees its own declaration state.
        const TypeSubstitution = struct {
            decl: u32,
            args: []const TypeId,
            /// Open integers to replace with what they settled on, when set.
            open: ?*OpenTypes = null,
            /// The declaration whose `where` clauses a projected member is
            /// selected under, or none.
            within: DeclId = .none,
            memo: std.AutoHashMapUnmanaged(TypeId, TypeId) = .empty,

            fn apply(self: *TypeSubstitution, builder: *Builder, ty: TypeId) std.mem.Allocator.Error!TypeId {
                if (self.open) |table| switch (builder.get(ty)) {
                    .open_integer, .open_type => |v| return table.resolved(v),
                    else => if (!try builder.mentionsOpen(ty)) return ty,
                };
                if (builder.substitutionLeaf(ty, self.decl, self.args)) |answer| return answer;
                if (self.memo.get(ty)) |answer| return answer;
                const answer = try builder.substituteOne(ty, self);
                try self.memo.put(builder.gpa, ty, answer);
                return answer;
            }
        };

        fn substituteOne(self: *Builder, ty: TypeId, substitution: *TypeSubstitution) std.mem.Allocator.Error!TypeId {
            switch (self.pool.items[@intFromEnum(ty)]) {
                .borrow => |b| return self.borrowOf(try substitution.apply(self, b.referent)),
                .parameter => return self.substituteStandin(self.standinOf(ty).?, substitution),
                // The length is written down and substitution cannot touch it,
                // so only the element moves -- and an array of a parameter is
                // the one constructed type that is not an instantiation, so it
                // is not reached by the template machinery below.
                .array => |a| {
                    const to = try substitution.apply(self, a.element);
                    if (to == a.element) return ty;
                    return self.arrayOf(to, a.count);
                },
                .callable => |signature| {
                    const params = self.callableParams(signature);
                    const replaced = try self.gpa.dupe(CallableParam, params);
                    defer self.gpa.free(replaced);
                    var moved = false;
                    for (replaced) |*param| {
                        const to = try substitution.apply(self, param.ty);
                        if (to != param.ty) moved = true;
                        param.ty = to;
                    }
                    const result = try substitution.apply(self, signature.result);
                    if (!moved and result == signature.result) return ty;
                    return self.internCallable(replaced, result, signature.contracts, signature.invocation);
                },
                .closure => |closure| {
                    const held = try self.gpa.dupe(TypeId, self.closureArgs(closure));
                    defer self.gpa.free(held);
                    const original_impl = try self.gpa.dupe(TypeId, self.closureImplArgs(closure));
                    defer self.gpa.free(original_impl);
                    const replaced = try self.gpa.alloc(TypeId, held.len);
                    defer self.gpa.free(replaced);
                    var moved = false;
                    for (held, 0..) |arg, i| {
                        replaced[i] = try substitution.apply(self, arg);
                        moved = moved or replaced[i] != arg;
                    }
                    const impl_args = try self.gpa.alloc(TypeId, original_impl.len);
                    defer self.gpa.free(impl_args);
                    for (original_impl, impl_args) |arg, *replacement| {
                        replacement.* = try substitution.apply(self, arg);
                        moved = moved or replacement.* != arg;
                    }
                    const receiver = try substitution.apply(self, closure.self_ty);
                    moved = moved or receiver != closure.self_ty;
                    return if (moved) self.internClosure(closure.closure, replaced, impl_args, receiver) else ty;
                },
                // Interpolations carry structural child types without a
                // nominal instance key; other nominal children use that key.
                .struct_ => if (self.isInterpolation(ty)) {
                    return self.substituteInterpolation(ty, substitution);
                },
                .enum_, .newtype => {},
                .integer, .open_integer, .open_type, .boolean, .float, .poison, .unit, .never => unreachable,
            }

            const origin = self.instanceOf(ty) orelse return ty;

            // Copied, not borrowed. `argsOf` is a slice into the arguments
            // list, and the recursion below interns -- which appends to that
            // list and may move it, leaving the loop reading through a pointer
            // to freed memory. It survives today only because this pass is
            // handed an arena that never releases the old buffer.
            const inner = try self.gpa.dupe(TypeId, self.argsOf(origin));
            defer self.gpa.free(inner);

            const mapped = try self.gpa.alloc(TypeId, inner.len);
            defer self.gpa.free(mapped);

            var moved = false;
            for (inner, 0..) |a, k| {
                mapped[k] = try substitution.apply(self, a);
                if (mapped[k] != a) moved = true;
            }
            if (!moved) return ty;

            const template = self.typeOfDecl(origin.decl) orelse return ty;
            return self.instantiate(template, origin.decl, mapped);
        }

        /// Replaces `decl`'s parameters inside a settled reference's key, and
        /// settles the reference where that leaves a key with no parameter in
        /// it.
        ///
        /// A key mentioning none of `decl`'s parameters comes back unchanged,
        /// which is what keeps one settled reference from becoming a second
        /// entry per instantiation of a declaration it says nothing about.
        fn substituteStandin(
            self: *Builder,
            s: Standin,
            substitution: *TypeSubstitution,
        ) std.mem.Allocator.Error!TypeId {
            // Copied, not borrowed, for the reason an instantiation's are:
            // the recursion below mints, which appends to the arguments list
            // and may move it out from under a held slice.
            const inner = try self.gpa.dupe(TypeId, self.standinArgsOf(s));
            defer self.gpa.free(inner);

            var moved = false;
            const held = try substitution.apply(self, s.held);
            if (held != s.held) moved = true;
            for (inner) |*a| {
                const to = try substitution.apply(self, a.*);
                if (to != a.*) moved = true;
                a.* = to;
            }
            if (!moved) return s.ty;
            return (try self.settledAtWithin(substitution.within, s.trait, inner, held, s.member, s.named)).ty;
        }

        /// `Cell[UInt8]`, as a substituted type is spelled in a diagnostic.
        ///
        /// Substitution builds a type nobody wrote, so there is no source text
        /// to quote: without this the result carries the name of the type it
        /// came from and a message reads `expected Cell[T], found Cell[T]`.
        pub fn spellInstance(
            self: *const Builder,
            head: []const u8,
            args: []const TypeId,
        ) std.mem.Allocator.Error![]const u8 {
            var out: TypeDisplay = .{};
            errdefer out.text.deinit(self.gpa);
            try out.appendSlice(self.gpa, head);
            // A name applied to nothing is written bare. A pair of empty
            // brackets is a spelling the grammar has no place for, so a
            // reader shown one is shown something they cannot write.
            if (args.len > 0) {
                try out.appendSlice(self.gpa, "[");
                for (args, 0..) |a, i| {
                    if (i > 0) try out.appendSlice(self.gpa, ", ");
                    try out.appendSlice(self.gpa, self.nameOf(a));
                }
                try out.appendSlice(self.gpa, "]");
            }
            return out.finish(self.gpa);
        }

        /// `Typing.isTupleDecl`, asked of a pool still being built.
        pub fn isTupleDecl(self: *const Builder, decl: DeclId) bool {
            return self.view().isTupleDecl(decl);
        }

        test "a builder answers which declarations are tuples as its view does" {
            const gpa = testing.allocator;
            var b = try Typing.Builder.init(gpa);
            defer b.deinit();
            try testing.expect(!b.isTupleDecl(DeclId.at(3)));
            b.tuple_decls[0] = DeclId.at(3);
            try testing.expect(b.isTupleDecl(DeclId.at(3)));
            try testing.expect(!b.isTupleDecl(DeclId.at(4)));
        }

        /// `(UInt8, Str)`, as an instance of a tuple declaration is spelled.
        ///
        /// The canonical spelling of a tuple type is its components in
        /// parentheses rather than the declaration's name applied to them, so
        /// a report, a hover and a dump say what the program writes. Each
        /// component keeps its own delimiters, which is what tells
        /// `(A, (B, C))` from `((A, B), C)`.
        pub fn spellTuple(
            self: *const Builder,
            args: []const TypeId,
        ) std.mem.Allocator.Error![]const u8 {
            var out: TypeDisplay = .{};
            errdefer out.text.deinit(self.gpa);
            try out.appendSlice(self.gpa, "(");
            for (args, 0..) |a, i| {
                if (i > 0) try out.appendSlice(self.gpa, ", ");
                try out.appendSlice(self.gpa, self.nameOf(a));
            }
            try out.appendSlice(self.gpa, ")");
            return out.finish(self.gpa);
        }

        test "a tuple is spelled by its components, each with its own delimiters" {
            const gpa = testing.allocator;
            var b = try Typing.Builder.init(gpa);
            defer b.deinit();
            const pair = try b.spellTuple(&.{ .u8, .bool_ });
            defer gpa.free(pair);
            try testing.expectEqualStrings("(UInt8, Bool)", pair);
            const inner = try b.addStruct("(Str, Bool)", .affine, &.{});
            const nested = try b.spellTuple(&.{ .i64, inner });
            defer gpa.free(nested);
            try testing.expectEqualStrings("(Int64, (Str, Bool))", nested);
        }

        /// The signature an erased closure may be called as: a `fn` or `inout
        /// fn` type. A `sink fn` would consume the closure on its first call,
        /// and any other type is not callable, so both answer null.
        pub fn erasedSignature(self: *const Builder, ty: TypeId) ?CallableSignature {
            return switch (self.get(ty)) {
                .callable => |signature| if (signature.invocation == .sink) null else signature,
                else => null,
            };
        }

        test "a closure is called as a read or inout callable type" {
            const gpa = testing.allocator;
            var b = try Typing.Builder.init(gpa);
            defer b.deinit();
            try testing.expect(b.erasedSignature(try b.internCallable(&.{}, .u8, &.{}, .read)) != null);
            try testing.expect(b.erasedSignature(try b.internCallable(&.{}, .u8, &.{}, .inout)) != null);
            try testing.expect(b.erasedSignature(try b.internCallable(&.{}, .u8, &.{}, .sink)) == null);
            try testing.expect(b.erasedSignature(.u64) == null);
        }

        /// The signature an erased closure at the callable type `callable` is
        /// entered through: the callable's parameters, then the address and
        /// length of the stored callable's bytes. Null where `callable` is not
        /// a `fn` or `inout fn` type, which leaves `ClosureEntry` an ordinary
        /// instance -- the case inside a body generic over the callable.
        pub fn closureEntrySignature(self: *Builder, callable: TypeId) std.mem.Allocator.Error!?TypeId {
            const signature = self.erasedSignature(callable) orelse return null;
            const held = self.callableParams(signature);
            const params = try self.gpa.alloc(CallableParam, held.len + 2);
            defer self.gpa.free(params);
            @memcpy(params[0..held.len], held);
            params[held.len] = .{ .spelling = "at", .convention = .read, .ty = .u64, .default = .absent };
            params[held.len + 1] = .{ .spelling = "len", .convention = .read, .ty = .u64, .default = .absent };
            return try self.internCallable(params, signature.result, signature.contracts, .read);
        }

        test "an entry signature appends the stored callable's address and length" {
            const gpa = testing.allocator;
            var b = try Typing.Builder.init(gpa);
            defer b.deinit();
            const value: CallableParam = .{ .spelling = "value", .convention = .inout, .ty = .u8, .default = .absent };
            const callable = try b.internCallable(&.{value}, .u16, &.{}, .inout);
            const entry = (try b.closureEntrySignature(callable)).?;
            const signature = b.get(entry).callable;
            try testing.expectEqual(Convention.read, signature.invocation);
            try testing.expectEqual(TypeId.u16, signature.result);
            const params = b.callableParams(signature);
            try testing.expectEqual(@as(usize, 3), params.len);
            try testing.expectEqual(Convention.inout, params[0].convention);
            try testing.expectEqualStrings("at", params[1].spelling);
            try testing.expectEqual(TypeId.u64, params[2].ty);
            // A number and a consuming callable have no entry signature.
            try testing.expectEqual(@as(?TypeId, null), try b.closureEntrySignature(.u8));
            const consuming = try b.internCallable(&.{}, .u8, &.{}, .sink);
            try testing.expectEqual(@as(?TypeId, null), try b.closureEntrySignature(consuming));
        }

        /// The type `Name[args]` names, interned so it is one handle wherever
        /// it is written.
        ///
        /// An instantiation is an ordinary declared type: its fields are the
        /// template's with parameters replaced, so layout, matching and field
        /// lookup need no case for it. That is what monomorphisation is, and
        /// doing it here means nothing downstream has to know.
        /// The instantiation of `template` at `args`, minting it if the pool
        /// has not seen this pair before.
        ///
        /// The name is spelled here rather than passed in. It is a function of
        /// the same `(decl, args)` the pool interns on, so a caller supplying
        /// it is a fourth argument three others already determine -- and one
        /// the pool cannot check. A caller that spelled the head from the
        /// token at the use site named `Self[UInt8]` a `Self.1.UInt8`, which is a
        /// name no declaration has: two `impl` blocks minted one symbol, the
        /// assembler refused the program under an I/O status, and which
        /// spelling won depended on whichever site interned the pair first --
        /// so an unrelated declaration elsewhere decided a function's symbol.
        pub fn instantiate(
            self: *Builder,
            template: TypeId,
            decl: DeclId,
            args: []const TypeId,
        ) std.mem.Allocator.Error!TypeId {
            if (decl == self.certified_closure_entry and args.len == 1) {
                if (try self.closureEntrySignature(args[0])) |entry| return entry;
            }
            if (self.mintedAt(decl, args)) |i| return self.instances.items[i].ty;

            // Only once the pool is known not to hold it, so nothing is minted
            // to be freed again. A tuple declaration's instance is spelled as
            // the tuple syntax that names it, `(A, B)`, rather than as
            // `Tuple2[A, B]`.
            const name = if (self.isTupleDecl(decl))
                try self.spellTuple(args)
            else
                try self.spellInstance(self.nameOf(template), args);
            self.owned_names.append(self.gpa, name) catch |err| {
                self.gpa.free(name);
                return err;
            };

            const first_arg: u32 = @intCast(self.instance_args.items.len);
            try self.instance_args.appendSlice(self.gpa, args);

            const made = switch (self.pool.items[@intFromEnum(template)]) {
                .struct_ => |x| blk: {
                    const run = try self.gpa.alloc(Field, x.field_count);
                    defer self.gpa.free(run);
                    const field_names = self.fields.items(.name);
                    for (0..x.field_count) |k| {
                        run[k] = .{ .name = field_names[x.first_field + k], .ty = .poison };
                    }
                    break :blk try self.addStruct(name, x.ownership_policy, run);
                },
                .enum_ => |e| blk: {
                    const run = try self.gpa.alloc(Variant, e.variant_count);
                    defer self.gpa.free(run);
                    const variant_names = self.variants.items(.name);
                    for (0..e.variant_count) |k| {
                        run[k] = .{ .name = variant_names[e.first_variant + k] };
                    }
                    break :blk try self.addEnum(name, e.ownership_policy, run);
                },
                else => return template,
            };

            // Recorded before the parts are filled in, so a type holding
            // itself through an argument finds the entry rather than looping.
            // Where the cycle is one the declaration wrote, it was refused
            // before anything was minted and this keeps the refusal from
            // becoming a hang; where an implementation's settlement closed it,
            // this is what leaves a type to report the cycle against instead
            // of a walk with no end.
            try self.instances.append(self.gpa, .{
                .decl = decl,
                .first_arg = first_arg,
                .arg_count = @intCast(args.len),
                .ty = made,
            });
            const at: u32 = @intCast(self.instances.items.len - 1);
            try self.noteAt(&self.instance_of, made, at, Typing.not_an_instance);
            try self.noteMinted(at, decl.index(), args);

            try self.fillInstance(template, made, decl.index(), args);

            return made;
        }

        /// Fills every instantiation again, from templates that are complete.
        ///
        /// A field may name a generic type declared further down, for the
        /// reason a call may name a function declared further down. But an
        /// instantiation copies its template's parts, and a template read
        /// before its own fields were filled copies nothing -- so the instance
        /// was laid out as if it were empty, and a program reading a field of
        /// one answered with whatever a zero-sized value holds. No diagnostic:
        /// the type existed, it was simply the wrong shape.
        ///
        /// One pass is enough. An instance's parts come from its template
        /// rather than from another instance, and a nested argument is
        /// refilled by this same walk.
        pub fn refillInstances(self: *Builder) std.mem.Allocator.Error!void {
            const zone = tracy.beginZone(@src(), "types.refill");
            defer zone.end();

            self.refilled = true;

            var i: usize = 0;
            while (i < self.instances.items.len) : (i += 1) {
                const inst = self.instances.items[i];
                const template = self.typeOfDecl(inst.decl) orelse continue;
                const args = try self.gpa.dupe(TypeId, self.argsOf(inst));
                defer self.gpa.free(args);
                try self.fillInstance(template, inst.ty, inst.decl.index(), args);
            }

            self.capability_facts.dirty = true;
            try self.capability_facts.update(self);
        }

        /// Fills an instantiation's parts by substituting the template's.
        fn fillInstance(
            self: *Builder,
            template: TypeId,
            made: TypeId,
            decl: u32,
            args: []const TypeId,
        ) std.mem.Allocator.Error!void {
            switch (self.pool.items[@intFromEnum(template)]) {
                .struct_ => |x| {
                    for (0..x.field_count) |k| {
                        const from = self.fields.items(.ty)[x.first_field + k];
                        const to = try self.substitute(from, decl, args);
                        self.setFieldType(made, @intCast(k), to);
                    }
                },
                .enum_ => |e| {
                    for (0..e.variant_count) |k| {
                        const variant_at = e.first_variant + k;
                        const first_field = self.variants.items(.first_field)[variant_at];
                        const field_count = self.variants.items(.field_count)[variant_at];
                        if (field_count == 0) continue;

                        const run = try self.gpa.alloc(Field, field_count);
                        defer self.gpa.free(run);
                        for (0..field_count) |j| {
                            const field_at = first_field + j;
                            const field_name = self.fields.items(.name)[field_at];
                            const from = self.fields.items(.ty)[field_at];
                            const to = try self.substitute(from, decl, args);
                            run[j] = .{
                                .name = field_name,
                                .ty = to,
                            };
                        }
                        const first = try self.addFields(run);
                        self.setVariantFields(made, @intCast(k), first, field_count);
                    }
                },
                else => {},
            }
        }

        /// Enters a declared enum, returning its handle.
        ///
        /// The handle lands beyond every reserved one, so a switch written
        /// over the builtins still covers them and only its `else` sees this.
        pub fn addEnum(
            self: *Builder,
            name: []const u8,
            ownership_policy: OwnershipPolicy,
            variants: []const Variant,
        ) !TypeId {
            self.grows();
            const first_index = self.variants.len;
            const first: u32 = @intCast(first_index);
            try self.variants.resize(self.gpa, first_index + variants.len);
            const columns = self.variants.slice();
            for (variants, first_index..) |variant, i| columns.items(.name)[i] = variant.name;
            for (variants, first_index..) |variant, i| columns.items(.first_field)[i] = variant.first_field;
            for (variants, first_index..) |variant, i| columns.items(.field_count)[i] = variant.field_count;
            var payload_field_count: u32 = 0;
            for (variants) |v| payload_field_count += v.field_count;

            const id: TypeId = @enumFromInt(@as(u32, @intCast(self.pool.items.len)));
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, .{ .enum_ = .{
                .name = name,
                .first_variant = first,
                .variant_count = @intCast(variants.len),
                .payload_field_count = payload_field_count,
                .ownership_policy = ownership_policy,
            } });
            return id;
        }

        /// Appends a run of fields, returning where it begins. Enums are
        /// entered before any payload is read, so what a variant carries is
        /// filled in afterwards -- which is what lets a payload name a type
        /// declared further down.
        pub fn addFields(self: *Builder, fields: []const Field) !u32 {
            self.grows();
            const first_index = self.fields.len;
            const first: u32 = @intCast(first_index);
            try self.fields.resize(self.gpa, first_index + fields.len);
            const columns = self.fields.slice();
            for (fields, first_index..) |field, i| columns.items(.name)[i] = field.name;
            for (fields, first_index..) |field, i| columns.items(.ty)[i] = field.ty;
            try self.growOffsets();
            return first;
        }

        pub fn setVariantFields(self: *Builder, t: TypeId, i: u32, first: u32, count: u32) void {
            self.capability_facts.invalidate(t);
            self.dependency_facts.invalidate(t);
            self.writer_facts.invalidate(t);

            const e = &self.pool.items[@intFromEnum(t)].enum_;
            const variant_at = e.first_variant + i;
            const old = self.variants.items(.field_count)[variant_at];
            self.variants.items(.first_field)[variant_at] = first;
            self.variants.items(.field_count)[variant_at] = count;
            e.payload_field_count = e.payload_field_count - old + count;
            self.forgetLayouts();
        }

        /// Drops every layout already worked out.
        ///
        /// Writing a part changes what the type holding it is laid out as, and
        /// what every type above that one is laid out as, and nothing here
        /// knows which those are. Called from the three writers rather than
        /// from their callers, so a writer added later cannot forget.
        fn forgetLayouts(self: *Builder) void {
            const next = self.generation +% 1;
            if (next != 0) {
                self.generation = next;
                return;
            }
            for (self.laid_out.items) |*cached| cached.generation = 0;
            @memset(self.placed_at.items, 0);
            self.generation = 1;
        }

        /// Keeps the offsets table the same length as `fields`.
        ///
        /// One call after each append rather than a length carried alongside:
        /// the table is only ever read through `Arrangement`, which requires
        /// the run it is asked about to fit, and a table shorter than `fields`
        /// simply sends that run down the walking path.
        fn growOffsets(self: *Builder) !void {
            const from = self.placed_at.items.len;
            const want = self.fields.len;
            if (want <= from) return;

            try self.offsets.resize(self.gpa, want);
            try self.placed_at.resize(self.gpa, want);
            try self.by_name.resize(self.gpa, want);
            try self.sorted.resize(self.gpa, want);
            // A part's name is fixed once its run is appended, so an order
            // already worked out stays true and only the new tail is cleared.
            @memset(self.sorted.items[from..], false);
            // Only what was added, and to a generation no stamp can match.
            @memset(self.placed_at.items[from..], 0);
        }

        pub fn variantFieldCount(self: *const Builder, t: TypeId, i: u32) u32 {
            return self.view().variantFieldCount(t, i);
        }

        pub fn variantFieldType(self: *const Builder, t: TypeId, i: u32, f: u32) TypeId {
            return self.view().variantFieldType(t, i, f);
        }

        pub fn setVariantFieldType(self: *Builder, t: TypeId, i: u32, f: u32, ty: TypeId) void {
            const e = self.pool.items[@intFromEnum(t)].enum_;
            const first_field = self.variants.items(.first_field)[e.first_variant + i];
            // Signature checking revisits fields after their shapes settle.
            // An unchanged edge leaves every derived fact valid.
            if (self.fields.items(.ty)[first_field + f] == ty) return;
            self.capability_facts.invalidate(t);
            self.dependency_facts.invalidate(t);
            self.writer_facts.invalidate(t);

            self.fields.items(.ty)[first_field + f] = ty;
            self.forgetLayouts();
        }

        /// The first cycle among inline parts, or null. Asked once, after every
        /// type is entered and before any layout is, because asking for the
        /// layout of a type on a cycle does not return.
        pub fn firstCycle(self: *const Builder, gpa: std.mem.Allocator) !?Cycle {
            return firstCycleIn(
                gpa,
                self.pool.items,
                .fromSlice(self.fields.slice()),
                .fromSlice(self.variants.slice()),
            );
        }

        /// The first type at or after `from` whose width crosses what [L-Size]
        /// allows, or null where none does.
        ///
        /// Asked of a range rather than of the whole pool: a pool that another
        /// pass reopened and extended already had its earlier types asked
        /// about, and a second report of the same type would name one mistake
        /// twice.
        pub fn nextOversized(self: *const Builder, from: u32) ?TypeId {
            for (from..self.pool.items.len) |i| {
                const t: TypeId = @enumFromInt(@as(u32, @intCast(i)));
                if (self.crossesSizeLimit(t)) return t;
            }
            return null;
        }

        /// Whether this is the type at which a width crosses what [L-Size]
        /// allows: too wide itself, and holding nothing that already is.
        ///
        /// A type holding one too wide is too wide as well, so reporting every
        /// one of them would name a whole chain for a single mistake. Where
        /// the width crosses is the part a reader has to shrink.
        pub fn crossesSizeLimit(self: *const Builder, t: TypeId) bool {
            if (!self.layoutOf(t).too_wide) return false;

            for (0..self.fieldCount(t)) |i| {
                if (self.layoutOf(self.fieldType(t, @intCast(i))).too_wide) return false;
            }
            for (0..self.variantCount(t)) |v| {
                for (0..self.variantFieldCount(t, @intCast(v))) |f| {
                    const p = self.variantFieldType(t, @intCast(v), @intCast(f));
                    if (self.layoutOf(p).too_wide) return false;
                }
            }
            return true;
        }

        pub fn fieldCount(self: *const Builder, t: TypeId) u32 {
            return self.view().fieldCount(t);
        }

        /// Which part a name selects, mid-build. The finished typing answers
        /// the same question the same way; two loops over one table are two
        /// chances to disagree about which part a name means.
        pub fn lookupField(self: *const Builder, t: TypeId, name: []const u8) ?struct {
            index: u32,
            ty: TypeId,
        } {
            // The same index the finished pool searches. Not `Typing`'s own
            // `lookupField`, which also settles the offset: a part's layout is
            // still being written while the checker asks, and this asks only
            // which part carries the name.
            const pool = self.view();
            const first = switch (pool.get(t)) {
                .struct_ => |x| x.first_field,
                else => return null,
            };
            const at = pool.fieldNamed(first, self.fieldCount(t), name) orelse return null;
            return .{ .index = at, .ty = self.fieldType(t, at) };
        }

        pub fn fieldName(self: *const Builder, t: TypeId, i: u32) []const u8 {
            return self.view().fieldName(t, i);
        }

        pub fn fieldType(self: *const Builder, t: TypeId, i: u32) TypeId {
            return self.view().fieldType(t, i);
        }

        /// Breaks an edge, which is what a reported cycle needs: every later
        /// pass asks for a layout, and one that cannot terminate would not stop
        /// being asked just because it was diagnosed.
        pub fn setFieldType(self: *Builder, t: TypeId, i: u32, ty: TypeId) void {
            self.capability_facts.invalidate(t);
            self.dependency_facts.invalidate(t);
            self.writer_facts.invalidate(t);

            const x = self.pool.items[@intFromEnum(t)].struct_;
            self.fields.items(.ty)[x.first_field + i] = ty;
            self.forgetLayouts();
        }

        /// Enters a declared newtype, returning its handle.
        ///
        /// Entered with `base` possibly still `.poison`: a newtype's base may
        /// name a type declared further down, the same reason a structure's
        /// fields are entered unresolved -- `setNewtypeBase` fills it in once
        /// every declared type is in the pool.
        pub fn addNewtype(
            self: *Builder,
            name: []const u8,
            ownership_policy: OwnershipPolicy,
            base: TypeId,
            refined: bool,
            lo: i128,
            hi: i128,
        ) !TypeId {
            self.grows();
            const id: TypeId = @enumFromInt(@as(u32, @intCast(self.pool.items.len)));
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, .{ .newtype = .{
                .name = name,
                .base = base,
                .lo = lo,
                .hi = hi,
                .refined = refined,
                .ownership_policy = ownership_policy,
            } });
            return id;
        }

        pub fn setNewtypeBase(self: *Builder, t: TypeId, base: TypeId) void {
            self.capability_facts.invalidate(t);
            self.dependency_facts.invalidate(t);
            self.writer_facts.invalidate(t);

            self.pool.items[@intFromEnum(t)].newtype.base = base;
            self.forgetLayouts();
        }

        pub fn baseOf(self: *const Builder, t: TypeId) TypeId {
            return self.view().baseOf(t);
        }

        pub fn erased(self: *const Builder, t: TypeId) TypeId {
            return self.view().erased(t);
        }

        pub fn isRefined(self: *const Builder, t: TypeId) bool {
            return self.view().isRefined(t);
        }

        pub fn refinementOf(self: *const Builder, t: TypeId) Refinement {
            return self.view().refinementOf(t);
        }

        pub fn layoutOf(self: *const Builder, t: TypeId) Layout {
            return self.view().layoutOf(t);
        }

        pub fn captureRecord(self: *Builder, closure: ClosureType) !TypeId {
            if (closure.environment != .unit) return closure.environment;
            if (self.empty_capture_record == .poison)
                self.empty_capture_record = try self.addStruct("captures.empty", .copyable, &.{});
            return self.empty_capture_record;
        }

        /// Adds one nominal structure and its fields.
        pub fn addStruct(
            self: *Builder,
            name: []const u8,
            ownership_policy: OwnershipPolicy,
            fields: []const Field,
        ) !TypeId {
            self.grows();
            const first_index = self.fields.len;
            const first: u32 = @intCast(first_index);
            try self.fields.resize(self.gpa, first_index + fields.len);
            const columns = self.fields.slice();
            for (fields, first_index..) |field, i| columns.items(.name)[i] = field.name;
            for (fields, first_index..) |field, i| columns.items(.ty)[i] = field.ty;
            try self.growOffsets();

            const id: TypeId = @enumFromInt(@as(u32, @intCast(self.pool.items.len)));
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, .{ .struct_ = .{
                .name = name,
                .first_field = first,
                .field_count = @intCast(fields.len),
                .ownership_policy = ownership_policy,
            } });
            return id;
        }

        pub fn init(gpa: std.mem.Allocator) !Builder {
            var b: Builder = .{ .gpa = gpa };
            // A partly-filled builder is nobody's to release: the caller is
            // handed a value, not a pointer, so a failure after the first
            // append strands everything before it.
            errdefer b.deinit();
            try b.pool.appendSlice(gpa, &TypeId.builtins);
            try b.laid_out.appendNTimes(gpa, .{}, TypeId.builtins.len);
            return b;
        }

        pub fn deinit(self: *Builder) void {
            self.open_mentions.deinit(self.gpa);
            self.ground_memo.deinit(self.gpa);
            self.unsettled_memo.deinit(self.gpa);
            self.implementation_selections.deinit(self.gpa);
            self.variants.deinit(self.gpa);
            self.fields.deinit(self.gpa);
            self.callable_params.deinit(self.gpa);
            self.interned_callables.deinit(self.gpa);
            self.interned_arrays.deinit(self.gpa);
            self.capability_facts.deinit(self.gpa);
            self.scoped_capability_facts.deinit(self.gpa);
            self.prepared_implementations.deinit(self.gpa);
            self.dependency_facts.deinit(self.gpa);
            self.writer_facts.deinit(self.gpa);

            self.borrowed_types.deinit(self.gpa);
            self.borrowed_types = .empty;
            self.closure_args.deinit(self.gpa);
            self.interned_closures.deinit(self.gpa);
            self.pool.deinit(self.gpa);
            self.expr_types.deinit(self.gpa);
            self.construction_types.deinit(self.gpa);
            self.templates.deinit(self.gpa);
            self.template_of.deinit(self.gpa);
            for (self.owned_names.items) |n| self.gpa.free(n);
            self.owned_names.deinit(self.gpa);
            for (self.owned_contracts.items) |contracts| freeContracts(self.gpa, contracts);
            self.owned_contracts.deinit(self.gpa);
            for (self.owned_bounds.items) |b| freeBoundTraits(self.gpa, b);
            self.owned_bounds.deinit(self.gpa);
            for (self.owned_callable_bounds.items) |b| self.gpa.free(b);
            self.owned_callable_bounds.deinit(self.gpa);
            self.instances.deinit(self.gpa);
            self.instance_of.deinit(self.gpa);
            self.minted.deinit(self.gpa);
            self.interpolations.deinit(self.gpa);
            self.interpolation_pieces.deinit(self.gpa);
            self.interpolation_formats.deinit(self.gpa);
            self.interpolation_borrows.deinit(self.gpa);
            self.interpolation_of.deinit(self.gpa);
            self.interned_interpolations.deinit(self.gpa);
            self.parameters.deinit(self.gpa);
            self.standins.deinit(self.gpa);
            self.standin_args.deinit(self.gpa);
            self.standin_of.deinit(self.gpa);
            self.awaiting.deinit(self.gpa);
            self.instance_args.deinit(self.gpa);
            self.laid_out.deinit(self.gpa);
            self.offsets.deinit(self.gpa);
            self.placed_at.deinit(self.gpa);
            self.by_name.deinit(self.gpa);
            self.sorted.deinit(self.gpa);
            self.* = undefined;
        }

        pub fn mayCarryDependencies(self: *Builder, t: TypeId) !bool {
            try self.dependency_facts.update(self, .raw_carriers);
            return self.dependency_facts.values.items[@intFromEnum(t)];
        }

        /// Records that `t`, a type parameter or the stand-in for an
        /// associated type read through one, admits only `Owned` types, so it
        /// seeds no dependency. Answers already computed are dropped.
        pub fn promiseOwned(self: *Builder, t: TypeId) void {
            self.pool.items[@intFromEnum(t)].parameter.owned = true;
            self.dependency_facts.invalidate(t);
        }

        /// Why a value of `t` may carry a dependency: the parts walked from
        /// `t` to a type that holds one directly, over the edges the
        /// containment table is built from. Null where `t` carries nothing.
        /// The steps are allocated from `gpa` and owned by the caller.
        ///
        /// **Bound:** each type reachable from `t` is entered once.
        pub fn dependencyWitness(self: *Builder, gpa: std.mem.Allocator, t: TypeId) !?DependencyWitness {
            if (!try self.mayCarryDependencies(t)) return null;
            var search: WitnessSearch = .{ .builder = self, .gpa = gpa };
            defer search.visited.deinit(gpa);
            defer search.steps.deinit(gpa);
            defer search.parts.deinit(gpa);
            const seed = try search.from(t) orelse return null;
            const steps = try search.steps.toOwnedSlice(gpa);
            errdefer gpa.free(steps);
            return .{ .steps = steps, .parts = try search.parts.toOwnedSlice(gpa), .seed = seed };
        }

        const WitnessSearch = struct {
            builder: *Builder,
            gpa: std.mem.Allocator,
            visited: std.AutoHashMapUnmanaged(TypeId, void) = .empty,
            steps: std.ArrayList(ContainmentStep) = .empty,
            parts: std.ArrayList(TypeId) = .empty,
            found: ?TypeId = null,

            /// The seed reached from `ty`, with `steps` holding the path to it.
            fn from(search: *WitnessSearch, ty: TypeId) std.mem.Allocator.Error!?TypeId {
                if ((try search.visited.getOrPut(search.gpa, ty)).found_existing) return null;
                if (search.builder.view().directDependencySeed(ty)) return ty;
                try BorrowContainment.eachChild(search.builder, ty, .raw_carriers, search);
                return search.found;
            }

            fn child(search: *WitnessSearch, step: ContainmentStep, part: TypeId) std.mem.Allocator.Error!void {
                if (search.found != null) return;
                if (!search.builder.dependency_facts.values.items[@intFromEnum(part)]) return;
                try search.steps.append(search.gpa, step);
                try search.parts.append(search.gpa, part);
                if (try search.from(part)) |seed| {
                    search.found = seed;
                    return;
                }
                _ = search.steps.pop();
                _ = search.parts.pop();
            }
        };

        /// A callable requirement's signature: `signature`, whose result may
        /// also carry what the callable itself carries. A callback meeting a
        /// generic bound or kept in an erased closure is called with its
        /// environment, so a result built from a capture is one the caller
        /// sees depend on the callable. Unchanged where the result can carry
        /// nothing or the signature already says so.
        pub fn carriedByCallee(self: *Builder, callable: TypeId) !TypeId {
            const signature = switch (self.get(callable)) {
                .callable => |signature| signature,
                else => return callable,
            };
            for (signature.contracts) |contract| {
                if (contract.source.root == .callee) return callable;
            }
            if (!try self.mayCarryDependencies(signature.result)) return callable;
            var contracts: std.ArrayList(CallableContract) = .empty;
            defer contracts.deinit(self.gpa);
            try contracts.appendSlice(self.gpa, signature.contracts);
            try contracts.append(self.gpa, .{ .kind = .carries, .source = .{ .root = .callee, .spelling = "callee" } });
            const params = try self.gpa.dupe(CallableParam, self.callableParams(signature));
            defer self.gpa.free(params);
            return self.internCallable(params, signature.result, contracts.items, signature.invocation);
        }

        test "a callable requirement's result carries its callee" {
            const gpa = testing.allocator;
            var b = try Typing.Builder.init(gpa);
            defer b.deinit();
            const observation = try b.borrowOf(.u8);
            const observing = try b.internCallable(&.{}, observation, &.{}, .read);
            const carried = try b.carriedByCallee(observing);
            try testing.expect(carried != observing);
            const contracts = b.get(carried).callable.contracts;
            try testing.expectEqual(@as(usize, 1), contracts.len);
            try testing.expect(contracts[0].source.root == .callee);
            // Asking again changes nothing, and a number carries nothing.
            try testing.expectEqual(carried, try b.carriedByCallee(carried));
            const number = try b.internCallable(&.{}, .u8, &.{}, .read);
            try testing.expectEqual(number, try b.carriedByCallee(number));
        }

        pub fn borrowOf(self: *Builder, referent: TypeId) !TypeId {
            if (self.borrowed_types.get(referent)) |existing| return existing;
            self.grows();
            var rendered: TypeDisplay = .{};
            defer rendered.text.deinit(self.gpa);
            try rendered.appendSlice(self.gpa, "borrow ");
            try rendered.appendSlice(self.gpa, self.nameOf(referent));
            const name = try rendered.finish(self.gpa);
            self.owned_names.append(self.gpa, name) catch |err| {
                self.gpa.free(name);
                return err;
            };
            const id: TypeId = @enumFromInt(@as(u32, @intCast(self.pool.items.len)));
            try self.pool.ensureUnusedCapacity(self.gpa, 1);
            try self.laid_out.ensureUnusedCapacity(self.gpa, 1);
            try self.borrowed_types.put(self.gpa, referent, id);
            self.pool.appendAssumeCapacity(.{ .borrow = .{ .referent = referent, .name = name } });
            self.laid_out.appendAssumeCapacity(.{});
            return id;
        }

        /// Expected O(1) lookup per structural array key, independent of the
        /// number of nominal types entered before its first occurrence.
        pub fn arrayOf(self: *Builder, element: TypeId, count: u32) !TypeId {
            const key: ArrayKey = .{ .element = element, .count = count };
            if (self.interned_arrays.get(key)) |existing| return existing;

            self.grows();
            try self.interned_arrays.ensureUnusedCapacity(self.gpa, 1);
            var rendered: TypeDisplay = .{};
            defer rendered.text.deinit(self.gpa);
            try rendered.append(self.gpa, '[');
            try rendered.appendSlice(self.gpa, self.nameOf(element));
            var extent_buffer: [16]u8 = undefined;
            const extent = std.fmt.bufPrint(&extent_buffer, "; {d}]", .{count}) catch unreachable;
            try rendered.appendSlice(self.gpa, extent);
            const name = try rendered.finish(self.gpa);
            self.owned_names.append(self.gpa, name) catch |err| {
                self.gpa.free(name);
                return err;
            };

            const i: u32 = @intCast(self.pool.items.len);
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, .{
                .array = .{ .element = element, .count = count, .name = name },
            });
            const id: TypeId = @enumFromInt(i);
            self.interned_arrays.putAssumeCapacity(key, id);
            return id;
        }

        pub fn seal(self: *Builder) void {
            self.sealed = true;
        }

        /// Every growth path passes here, so a sealed pool refuses in one
        /// spelling wherever growth was attempted.
        fn grows(self: *const Builder) void {
            if (self.sealed) @panic("compiler defect: the pool is finished, and nothing after instantiation may mint a type");
        }

        /// The type standing for open-integer variable `v`. Each variable is
        /// created once, so nothing can already hold it.
        pub fn openInteger(self: *Builder, v: u32) !TypeId {
            return self.appendFresh(.{ .open_integer = v });
        }

        /// The type standing for open-type variable `v`, created once like an
        /// open integer's.
        pub fn openType(self: *Builder, v: u32) !TypeId {
            return self.appendFresh(.{ .open_type = v });
        }

        test "an open type is mentioned by what holds it and resolves to what it settled on" {
            const gpa = testing.allocator;
            var b = try Builder.init(gpa);
            defer b.deinit();
            var table: OpenTypes = .{};
            defer table.deinit(gpa);
            const v = try table.createType(gpa);
            const open = try b.openType(v);
            table.name(v, open);
            const held = try b.borrowOf(open);
            try testing.expect(try b.mentionsOpen(held));
            try testing.expectEqual(held, try b.resolveOpen(held, &table));
            _ = table.settle(v, .u8, null);
            try testing.expectEqual(try b.borrowOf(.u8), try b.resolveOpen(held, &table));
        }

        /// Adds a type a hashed index has already shown is absent. `intern`
        /// scans the whole pool, which a kind minted once per source site
        /// cannot afford.
        fn appendFresh(self: *Builder, t: Type) !TypeId {
            self.grows();
            const i: u32 = @intCast(self.pool.items.len);
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, t);
            return @enumFromInt(i);
        }

        /// Whether `ty` has an open integer or open type anywhere inside it.
        pub fn mentionsOpen(self: *Builder, ty: TypeId) std.mem.Allocator.Error!bool {
            const at = @intFromEnum(ty);
            if (at >= self.open_mentions.items.len) try self.open_mentions.appendNTimes(self.gpa, 0, at + 1 - self.open_mentions.items.len);
            switch (self.open_mentions.items[at]) {
                1 => return false,
                2 => return true,
                else => {},
            }
            const answer = try self.mentionsOpenOnce(ty);
            self.open_mentions.items[at] = if (answer) 2 else 1;
            return answer;
        }

        /// What a memo table holds for `ty`, or 0 where it has not been asked.
        fn memoOf(self: *Builder, table: *std.ArrayList(u8), ty: TypeId) std.mem.Allocator.Error!u8 {
            const at = @intFromEnum(ty);
            if (at >= table.items.len) try table.appendNTimes(self.gpa, 0, at + 1 - table.items.len);
            return table.items[at];
        }

        /// Whether a run of types leaves nothing for unification to move, or to
        /// fail to decide: no parameter, and no settled reference.
        ///
        /// The two kinds `unifyWitness` treats as open, read off the same pool
        /// it reads -- a parameter is what a substitution binds, and a settled
        /// reference is what nothing at a declaration can prove distinct from
        /// anything. Every other type stands for itself, so unifying two ground
        /// runs degenerates to comparing them, which is what lets a caller
        /// answer such a pair by equality rather than by unifying it.
        ///
        /// **Bound:** one visit per distinct type in the run, and none for a
        /// type already asked about.
        pub fn allGround(self: *Builder, run: []const TypeId) std.mem.Allocator.Error!bool {
            for (run) |t| if (!try self.isGroundMemo(t)) return false;
            return true;
        }

        fn isGroundMemo(self: *Builder, t: TypeId) std.mem.Allocator.Error!bool {
            switch (try self.memoOf(&self.ground_memo, t)) {
                1 => return true,
                2 => return false,
                else => {},
            }
            const answer = try self.isGroundOnce(t);
            self.ground_memo.items[@intFromEnum(t)] = if (answer) 1 else 2;
            return answer;
        }

        fn isGroundOnce(self: *Builder, t: TypeId) std.mem.Allocator.Error!bool {
            if (self.standinOf(t) != null) return false;
            switch (self.get(t)) {
                .parameter => return false,
                .array => |a| return self.isGroundMemo(a.element),
                .borrow => |b| return self.isGroundMemo(b.referent),
                .callable => |signature| {
                    for (self.callableParams(signature)) |param| {
                        if (!try self.isGroundMemo(param.ty)) return false;
                    }
                    return self.isGroundMemo(signature.result);
                },
                else => {},
            }
            const instance = self.instanceOf(t) orelse return true;
            const held = try self.gpa.dupe(TypeId, self.argsOf(instance));
            defer self.gpa.free(held);
            return self.allGround(held);
        }

        /// Whether a run of types holds anything nothing settled.
        ///
        /// Such a type stands for no family and is equal to nothing, including
        /// another of its kind: two of them called equal make one key for what
        /// may be two types, and called distinct they admit two
        /// implementations of what may be one. A caller comparing
        /// implementations passes over one carrying any, which is what the
        /// program was already refused for where it was written.
        ///
        /// **Bound:** one visit per distinct type in the run, and none for a
        /// type already asked about.
        pub fn anyUnsettled(self: *Builder, run: []const TypeId) std.mem.Allocator.Error!bool {
            for (run) |t| if (try self.isUnsettledMemo(t)) return true;
            return false;
        }

        fn isUnsettledMemo(self: *Builder, t: TypeId) std.mem.Allocator.Error!bool {
            switch (try self.memoOf(&self.unsettled_memo, t)) {
                1 => return false,
                2 => return true,
                else => {},
            }
            const answer = try self.isUnsettledOnce(t);
            self.unsettled_memo.items[@intFromEnum(t)] = if (answer) 2 else 1;
            return answer;
        }

        fn isUnsettledOnce(self: *Builder, t: TypeId) std.mem.Allocator.Error!bool {
            if (t == .poison) return true;
            if (self.standinOf(t) != null) return false;
            switch (self.get(t)) {
                .array => |a| return self.isUnsettledMemo(a.element),
                .borrow => |b| return self.isUnsettledMemo(b.referent),
                .callable => |signature| {
                    for (self.callableParams(signature)) |param| {
                        if (try self.isUnsettledMemo(param.ty)) return true;
                    }
                    return self.isUnsettledMemo(signature.result);
                },
                else => {},
            }
            const instance = self.instanceOf(t) orelse return false;
            // Copied, not borrowed: the memo tables grow while the arguments
            // are read, and a pool that moves would leave the slice dangling.
            const held = try self.gpa.dupe(TypeId, self.argsOf(instance));
            defer self.gpa.free(held);
            return self.anyUnsettled(held);
        }

        fn mentionsOpenOnce(self: *Builder, ty: TypeId) std.mem.Allocator.Error!bool {
            switch (self.get(ty)) {
                .open_integer, .open_type => return true,
                else => {},
            }
            // A settled reference waiting on an open receiver resolves once the
            // receiver does, though its parts name no other type.
            if (self.standinOf(ty)) |standin| {
                if (try self.mentionsOpen(standin.held)) return true;
                for (self.standinArgsOf(standin)) |argument| if (try self.mentionsOpen(argument)) return true;
                return false;
            }
            const Found = struct {
                builder: *Builder,
                found: bool = false,
                pub fn part(found: *@This(), t: TypeId) std.mem.Allocator.Error!void {
                    if (!found.found and try found.builder.mentionsOpen(t)) found.found = true;
                }
            };
            var found: Found = .{ .builder = self };
            try self.visitParts(ty, &found);
            return found.found;
        }

        /// Calls `visitor.part` with each type `ty` is built from, in a fixed
        /// order. Every walk that must reach the integer literal types inside
        /// a type goes through here, and every kind is named, so a new kind
        /// does not compile until it says what it holds.
        pub fn visitParts(self: *Builder, ty: TypeId, visitor: anytype) std.mem.Allocator.Error!void {
            switch (self.get(ty)) {
                .integer, .boolean, .float, .poison, .unit, .never, .open_integer, .open_type, .parameter => {},
                .borrow => |b| try visitor.part(b.referent),
                .array => |a| try visitor.part(a.element),
                .callable => |signature| {
                    for (self.callableParams(signature)) |param| try visitor.part(param.ty);
                    try visitor.part(signature.result);
                },
                .closure => |closure| {
                    for (self.closureArgs(closure)) |argument| try visitor.part(argument);
                    for (self.closureImplArgs(closure)) |argument| try visitor.part(argument);
                    if (closure.self_ty != .poison) try visitor.part(closure.self_ty);
                },
                // An interpolation's type is the types of the values it holds.
                .struct_ => if (self.isInterpolation(ty)) {
                    var field: u32 = 0;
                    while (field < self.fieldCount(ty)) : (field += 1) try visitor.part(self.fieldType(ty, field));
                } else for (self.appliedTo(ty)) |argument| try visitor.part(argument),
                .enum_, .newtype => for (self.appliedTo(ty)) |argument| try visitor.part(argument),
            }
        }

        /// `ty` with every settled open integer and open type inside it replaced by the
        /// type it settled on. An unsettled one stays open.
        pub fn resolveOpen(self: *Builder, ty: TypeId, table: *OpenTypes) std.mem.Allocator.Error!TypeId {
            if (!try self.mentionsOpen(ty)) return ty;
            var substitution: TypeSubstitution = .{ .decl = std.math.maxInt(u32), .args = &.{}, .open = table };
            defer substitution.memo.deinit(self.gpa);
            return substitution.apply(self, ty);
        }

        pub fn intern(self: *Builder, t: Type) !TypeId {
            if (t == .array) return self.arrayOf(t.array.element, t.array.count);
            for (self.pool.items, 0..) |existing, i| {
                if (std.meta.eql(existing, t)) return @enumFromInt(i);
            }
            self.grows();
            const i: u32 = @intCast(self.pool.items.len);
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, t);
            return @enumFromInt(i);
        }

        fn contractHasDependencies(self: *const Builder, params: []const CallableParam, result: TypeId, contract: CallableContract) bool {
            const source: ?TypeId = switch (contract.source.root) {
                .parameter => |index| params[index].ty,
                .capture, .callee => null,
            };
            return contractNamesDependency(self, contract, result, source);
        }

        /// Whether a signature's contracts must be spelled for its text to
        /// read back as the same type: an empty list reads back as empty only
        /// where a clause-less signature infers nothing.
        fn spellsIndependence(self: *Builder, params: []const CallableParam, result: TypeId, contracts: []const CallableContract) !bool {
            if (contracts.len != 0) return false;
            return switch (try inferredSource(self, params, result, null)) {
                .none => false,
                .ambiguous => true,
                .one => |source| self.contractHasDependencies(params, result, .{
                    .kind = if (source.place) .borrows else .carries,
                    .source = .{ .root = .{ .parameter = source.parameter } },
                }),
            };
        }

        /// A structural signature spelled with parameter names, as the
        /// declaration whose parameters are `names` writes it: a type a
        /// program can write in place of the one it holds. The caller owns
        /// the text.
        pub fn spellCallable(self: *Builder, ty: TypeId, names: []const []const u8) ![]u8 {
            return self.view().spellCallable(self.gpa, ty, names);
        }

        test "a signature is spelled with the names a declaration gives it" {
            const gpa = testing.allocator;
            var b = try Builder.init(gpa);
            defer b.deinit();
            const signature = try b.internCallable(&.{.{ .spelling = "", .convention = .read, .ty = .u8, .default = .absent }}, .u8, &.{}, .read);
            try testing.expectEqualStrings("fn(read UInt8) -> UInt8", b.nameOf(signature));
            const spelled = try b.spellCallable(signature, &.{"value"});
            defer gpa.free(spelled);
            try testing.expectEqualStrings("fn(read value: UInt8) -> UInt8", spelled);
        }

        /// Interns one exact structural signature. Conventions, types,
        /// stable-address requirements, default presence and folded values
        /// belong to the key, in declaration order; parameter names do not.
        /// The names stored are those of the first signature interned, kept
        /// for spelling the type in a message. A call reads the labels it
        /// names arguments by from where its callee was declared.
        pub fn internCallable(self: *Builder, params: []const CallableParam, result: TypeId, declared_contracts: []const CallableContract, invocation: Convention) !TypeId {
            var effective: std.ArrayList(CallableContract) = .empty;
            defer effective.deinit(self.gpa);
            const contracts = filtered: {
                for (declared_contracts, 0..) |contract, i| {
                    if (self.contractHasDependencies(params, result, contract)) continue;
                    try effective.appendSlice(self.gpa, declared_contracts[0..i]);
                    for (declared_contracts[i + 1 ..]) |remaining| {
                        if (self.contractHasDependencies(params, result, remaining)) try effective.append(self.gpa, remaining);
                    }
                    break :filtered effective.items;
                }
                break :filtered declared_contracts;
            };
            const key = callableKey(params, result, contracts, invocation);
            var candidates = self.interned_callables.walk(key);
            while (candidates.next()) |i| {
                const signature = self.pool.items[i].callable;
                if (signature.invocation != invocation or signature.result != result or signature.param_count != params.len or !sameContracts(signature.contracts, contracts)) continue;
                const held = self.callable_params.items[signature.first_param..][0..signature.param_count];
                if (callableParamsMatch(held, params)) return @enumFromInt(i);
            }

            self.grows();
            const independent = try self.spellsIndependence(params, result, contracts);
            var rendered: TypeDisplay = .{};
            errdefer rendered.text.deinit(self.gpa);
            try renderCallable(self.gpa, &rendered, self.view(), params, result, contracts, invocation, independent, null);
            const name = try rendered.finish(self.gpa);
            self.owned_names.append(self.gpa, name) catch |err| {
                self.gpa.free(name);
                return err;
            };

            const stored_contracts = try duplicateContracts(self.gpa, contracts);
            self.owned_contracts.append(self.gpa, stored_contracts) catch |err| {
                freeContracts(self.gpa, stored_contracts);
                return err;
            };
            const first: u32 = @intCast(self.callable_params.items.len);
            const stored = self.callable_params.items;
            const stored_start = @intFromPtr(stored.ptr);
            const params_start = @intFromPtr(params.ptr);
            const stored_end = @intFromPtr(stored.ptr + stored.len);
            const stored_offset: ?usize = offset: {
                if (params.len == 0 or params_start < stored_start or params_start >= stored_end) break :offset null;
                const byte_offset = params_start - stored_start;
                if (byte_offset % @sizeOf(CallableParam) != 0) break :offset null;
                const item_offset = byte_offset / @sizeOf(CallableParam);
                if (params.len > stored.len - item_offset) break :offset null;
                break :offset item_offset;
            };
            try self.callable_params.ensureUnusedCapacity(self.gpa, params.len);
            // Rebase builder-owned slices after growth instead of reading freed storage.
            const stable_params = if (stored_offset) |offset|
                self.callable_params.items[offset..][0..params.len]
            else
                params;
            self.callable_params.appendSliceAssumeCapacity(stable_params);
            const id: TypeId = @enumFromInt(@as(u32, @intCast(self.pool.items.len)));
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, .{ .callable = .{
                .invocation = invocation,
                .independent = independent,
                .contracts = stored_contracts,
                .first_param = first,
                .param_count = @intCast(params.len),
                .result = result,
                .name = name,
            } });
            try self.interned_callables.note(self.gpa, key, @intFromEnum(id));
            return id;
        }

        fn callableKey(params: []const CallableParam, result: TypeId, contracts: []const CallableContract, invocation: Convention) u64 {
            var h: std.hash.Wyhash = .init(@intFromEnum(result));
            const invocation_tag: u8 = @intFromEnum(invocation);
            h.update(std.mem.asBytes(&invocation_tag));
            for (params) |param| {
                const convention: u8 = @intFromEnum(param.convention);
                const ty: u32 = @intFromEnum(param.ty);
                const default_tag: u8 = @intFromEnum(std.meta.activeTag(param.default));
                h.update(std.mem.asBytes(&convention));
                h.update(std.mem.asBytes(&param.stable_address));
                h.update(std.mem.asBytes(&ty));
                h.update(std.mem.asBytes(&default_tag));
                switch (param.default) {
                    .absent => {},
                    .value => |value| value.hash(&h),
                }
            }
            for (contracts) |contract| {
                const kind: u8 = @intFromEnum(contract.kind);
                h.update(std.mem.asBytes(&kind));
                h.update(std.mem.asBytes(&contract.borrows_source));
                contract.source.root.hash(&h);
                hashSelectors(&h, contract.source.fields);
                for (contract.target) |selector| {
                    const tag: u8 = @intFromEnum(selector);
                    h.update(std.mem.asBytes(&tag));
                    switch (selector) {
                        .field => |field| {
                            h.update(std.mem.asBytes(&field.name));
                            h.update(std.mem.asBytes(&field.index));
                        },
                        .payload => |payload| {
                            h.update(std.mem.asBytes(&payload.variant));
                            h.update(std.mem.asBytes(&payload.index));
                        },
                    }
                }
                if (contract.destination) |destination| {
                    destination.root.hash(&h);
                    hashSelectors(&h, destination.fields);
                }
            }
            return h.final();
        }

        pub fn setExprCount(self: *Builder, n: u32) !void {
            try self.expr_types.appendNTimes(self.gpa, .poison, n);
            try self.construction_types.appendNTimes(self.gpa, .poison, n);
        }

        /// Whether a type can hold a value, using the pool as it stands. The
        /// checker needs this mid-build, and going through here keeps it from
        /// knowing how the pool is stored.
        pub fn holds(self: *const Builder, t: TypeId, value: i128) bool {
            return self.view().holds(t, value);
        }

        /// The pool as it stands, for the structural questions a `Typing`
        /// answers: what a type's fields and variants are.
        ///
        /// Only what the pool itself holds. An expression's type and a
        /// binding's are the checker's answers about one program, and the
        /// pool is a table of types rather than a record of that program.
        ///
        /// No settled reference stands in it, and none is wanted: settling one
        /// is substitution, which is a builder's, and the entry a view does
        /// see is a parameter of the pool -- which is what it obliges as. A
        /// view is never reopened from, either; `reopen` takes a pool `finish`
        /// handed over, and that one carries the records and rebuilds the
        /// chain over them.
        pub fn view(self: *const Builder) Typing {
            return .{
                .constant_pool = self.constant_pool.*,
                .raw_accesses = .{ .storage = self.certified_storage, .buffer = self.certified_buffer, .slice = self.certified_slice, .closure_entry_type = self.certified_closure_entry },
                .tuple_decls = self.tuple_decls,
                .implementation_selections = self.implementation_selections,
                .closure_release = self.closure_release,
                .open_types = self.open_types,
                .binding_types = .empty,
                // The entries this pass was lent, in the owning shape the
                // reading below expects. Safe only because a view is a
                // temporary nobody frees -- which is what `view` is for, and
                // the one place this crosses back.
                .decl_returns = .{ .entries = @constCast(self.decl_returns.entries) },
                .pool = self.pool.items,
                .capabilities = self.capability_facts.values.items,
                .dependency_containment = self.dependency_facts.values.items,
                .scoped_capabilities = self.scoped_capability_facts.values,
                .prepared_implementations = self.prepared_implementations,
                .variants = .fromSlice(self.variants.slice()),
                .fields = .fromSlice(self.fields.slice()),
                .interpolations = self.interpolations.items,
                .interpolation_pieces = self.interpolation_pieces.items,
                .interpolation_formats = self.interpolation_formats.items,
                .interpolation_borrows = self.interpolation_borrows.items,
                .interpolation_of = self.interpolation_of.items,
                .callable_params = self.callable_params.items,
                .closure_args = self.closure_args.items,
                .closures = self.closure_descriptors,
                .templates = self.templates.items,
                .template_of = self.template_of.items,
                .module_paths = self.module_paths,
                .instances = self.instances.items,
                .instance_args = self.instance_args.items,
                .instance_of = self.instance_of.items,
                // A settled reference is interned as the parameter it behaves
                // like, so these are what tell the two apart. Carried by the
                // view as well as by the finished pool, so `standinOf` answers
                // the same during the pass that mints them as after it -- a
                // reader that had to ask a second way while the pool was open
                // is the copy that comes to disagree.
                .standins = self.standins.items,
                .standin_args = self.standin_args.items,
                .standin_of = self.standin_of.items,
                .expr_types = &.{},
                .laid_out = self.laid_out.items,
                .offsets = self.offsets.items,
                .placed_at = self.placed_at.items,
                .generation = self.generation,
                .by_name = self.by_name.items,
                .sorted = self.sorted.items,
                .observation_traits = self.observation_traits,
                .implementations = self.implementations,
                .contextual_constraints = self.contextual_constraints,
                .impl_of_decl = self.impl_of_decl,
                .impl_index = self.impl_index,
                .supply_index = self.supply,
            };
        }

        /// How a type is spelled in a diagnostic, using the pool as it stands.
        pub fn nameOf(self: *const Builder, t: TypeId) []const u8 {
            return self.view().nameOf(t);
        }

        /// What a parameter of the pool is interned under: the declaration
        /// that introduced it and its position within that declaration.
        fn parameterKey(owner: u32, index: u32) u64 {
            return (@as(u64, owner) << 32) | index;
        }

        /// The parameter `index` of declaration `owner`, where it was interned.
        pub fn internedParameter(self: *const Builder, owner: u32, index: u32) ?TypeId {
            return if (self.parameters.get(parameterKey(owner, index))) |at| @enumFromInt(at) else null;
        }

        test internedParameter {
            var building = try Builder.init(testing.allocator);
            defer building.deinit();
            try testing.expectEqual(@as(?TypeId, null), building.internedParameter(7, 1));
            const interned = try building.addParameter("Self", 7, 1, .unrestricted, &.{});
            try testing.expectEqual(@as(?TypeId, interned), building.internedParameter(7, 1));
            try testing.expectEqual(@as(?TypeId, null), building.internedParameter(7, 0));
        }

        /// Interns a type parameter, which is identified by the declaration
        /// that introduced it as well as by its position: one declaration's
        /// `T` is never another's.
        pub fn addParameter(
            self: *Builder,
            name: []const u8,
            owner: u32,
            index: u32,
            requirement: CapabilityRequirement,
            /// Taken over here, so a caller that computed one need not know
            /// whether this parameter was already interned.
            traits: []const BoundTrait,
        ) !TypeId {
            self.owned_bounds.append(self.gpa, traits) catch |err| {
                freeBoundTraits(self.gpa, traits);
                return err;
            };
            const key = parameterKey(owner, index);
            if (self.parameters.get(key)) |at| return @enumFromInt(at);

            const id: TypeId = @enumFromInt(@as(u32, @intCast(self.pool.items.len)));
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, .{ .parameter = .{
                .name = name,
                .owner = owner,
                .index = index,
                .requirement = requirement,
                .traits = traits,
            } });
            // Last, so nothing records where a parameter is until it is there.
            try self.parameters.put(self.gpa, key, @intFromEnum(id));
            return id;
        }

        /// Records what a parameter's bounds admit, once every parameter a
        /// bound's arguments could name is in the pool.
        ///
        /// Separate from `addParameter` because the two are settled at
        /// different times and only one of them can be: a parameter's capability
        /// is read off the bounds alone, while what they admit is read off the
        /// arguments, and an argument may name a parameter of a trait no loop
        /// has reached yet. Taken over here, exactly as `addParameter` takes
        /// over what it is handed.
        pub fn setBoundTraits(
            self: *Builder,
            t: TypeId,
            traits: []const BoundTrait,
        ) std.mem.Allocator.Error!void {
            self.owned_bounds.append(self.gpa, traits) catch |err| {
                freeBoundTraits(self.gpa, traits);
                return err;
            };
            self.prepared_implementations.clear();
            switch (self.pool.items[@intFromEnum(t)]) {
                .parameter => |*p| p.traits = traits,
                else => {},
            }
        }

        pub fn setCallableBounds(self: *Builder, t: TypeId, signatures: []const TypeId) std.mem.Allocator.Error!void {
            if (signatures.len > 0) {
                self.owned_callable_bounds.append(self.gpa, signatures) catch |err| {
                    self.gpa.free(signatures);
                    return err;
                };
            }
            self.prepared_implementations.clear();
            switch (self.pool.items[@intFromEnum(t)]) {
                .parameter => |*p| p.callables = signatures,
                else => unreachable,
            }
        }

        pub fn callableBoundsOn(self: *const Builder, t: TypeId) []const TypeId {
            return self.view().callableBoundsOn(t);
        }

        pub fn carriesCallableBound(self: *const Builder, t: TypeId, signature: TypeId) bool {
            return self.view().carriesCallableBound(t, signature);
        }

        /// The chain key a settled reference awaiting an instantiation is
        /// interned on: the whole key an implementation is found by, and the
        /// member read off it.
        fn standinKey(trait: u32, args: []const TypeId, held: TypeId, member: u32) u64 {
            var h = std.hash.Wyhash.init(trait);
            h.update(std.mem.asBytes(&member));
            const id: u32 = @intFromEnum(held);
            h.update(std.mem.asBytes(&id));
            for (args) |a| {
                const arg: u32 = @intFromEnum(a);
                h.update(std.mem.asBytes(&arg));
            }
            return h.final();
        }

        /// Where this key was already minted, or null.
        ///
        /// Every candidate the chain offers is compared on the key itself, so
        /// a collision costs a comparison rather than a wrong type.
        fn standinAt(self: *const Builder, trait: u32, args: []const TypeId, held: TypeId, member: DeclId) ?u32 {
            var run = self.awaiting.walk(standinKey(trait, args, held, member.index()));
            while (run.next()) |at| {
                const s = self.standins.items[at];
                if (s.trait != trait or s.member != member or s.held != held) continue;
                if (s.arg_count != args.len) continue;
                if (!std.mem.eql(TypeId, self.standin_args.items[s.first_arg..][0..s.arg_count], args)) continue;
                return at;
            }
            return null;
        }

        /// What `W.Item` stands for while a body is checked once.
        ///
        /// A parameter of the pool, because that is already what stands for a
        /// type known only at instantiation: no layout, nothing assumed of its
        /// shape, pessimistically Linear, and an operation reaches it only
        /// where something promised the operation. A second kind of unknown
        /// would be every one of those rules written twice.
        ///
        /// The key beside it is what tells this entry from a declared
        /// parameter, and what substitution reads to settle it. Interned on
        /// that key, which is what decides when two of them are one type:
        /// `W.Item` and `V.Item` stand for different types where `W` and `V`
        /// are different parameters, and for one wherever the key is one.
        ///
        /// **Bound:** one chain walk over the standins already minted for this
        /// key, and one name minted the first time the key is written.
        pub fn addSettledStandin(
            self: *Builder,
            trait: u32,
            args: []const TypeId,
            held: TypeId,
            member: DeclId,
            named: []const u8,
        ) std.mem.Allocator.Error!TypeId {
            if (self.standinAt(trait, args, held, member)) |at| return self.standins.items[at].ty;

            // Only once the pool is known not to hold it, for the reason an
            // instantiation's name is spelled there: nothing is minted to be
            // freed again.
            var rendered: TypeDisplay = .{};
            defer rendered.text.deinit(self.gpa);
            try rendered.appendSlice(self.gpa, self.nameOf(held));
            try rendered.append(self.gpa, '.');
            try rendered.appendSlice(self.gpa, named);
            const spelled = try rendered.finish(self.gpa);
            self.owned_names.append(self.gpa, spelled) catch |err| {
                self.gpa.free(spelled);
                return err;
            };

            // A pool entry of its own rather than one `addParameter` interned:
            // what identifies it is the key beside it, and the `(owner,
            // position)` pair that table is keyed by names a position no
            // declaration wrote.
            //
            // An unresolved associated type grants only its declared
            // capabilities; no arbitrary implementing type stands in for it.
            const id: TypeId = @enumFromInt(@as(u32, @intCast(self.pool.items.len)));
            try self.laid_out.append(self.gpa, .{});
            try self.pool.append(self.gpa, .{ .parameter = .{
                .name = spelled,
                .owner = member.index(),
                .index = @intFromEnum(held),
                .requirement = self.requirementDeclaredFor(member.index()),
                .traits = self.traitsDeclaredFor(member.index()),
                .callables = self.callablesDeclaredFor(member.index()),
            } });

            const first_arg: u32 = @intCast(self.standin_args.items.len);
            try self.standin_args.appendSlice(self.gpa, args);
            const at: u32 = @intCast(self.standins.items.len);
            try self.standins.append(self.gpa, .{
                .trait = trait,
                .member = member,
                .held = held,
                .first_arg = first_arg,
                .arg_count = @intCast(args.len),
                .ty = id,
                .named = named,
            });
            // A type past the table's end is one no settled reference stands
            // for, which is the answer such a type wants. The first entry
            // winning decides nothing here: `id` is the pool entry appended
            // just above and no standin can already name it, so the entry
            // noted is the entry read back.
            try self.noteAt(&self.standin_of, id, at, Typing.not_a_standin);
            std.debug.assert(self.standin_of.items[@intFromEnum(id)] == at);
            // Last, so nothing reaches the entry until every table describing
            // it is filled.
            try self.awaiting.note(self.gpa, standinKey(trait, args, held, member.index()), at);
            return id;
        }

        /// The capability promised by an associated type declaration.
        /// Missing entries grant no permission to duplicate or discard.
        pub fn requirementDeclaredFor(self: *const Builder, member: u32) CapabilityRequirement {
            if (member >= self.declared_requirements.len) return .unrestricted;
            return self.declared_requirements[member];
        }

        /// The traits a declared type's bounds name, by declaration. Empty past
        /// the end of the table, which is what a declaration nothing was
        /// written about promises: nothing.
        pub fn traitsDeclaredFor(self: *const Builder, member: u32) []const BoundTrait {
            if (member >= self.declared_traits.len) return &.{};
            return self.declared_traits[member];
        }

        pub fn callablesDeclaredFor(self: *const Builder, member: u32) []const TypeId {
            if (member >= self.declared_callables.len) return &.{};
            return self.declared_callables[member];
        }

        /// The settled reference a type stands for, or null where it stands for
        /// none.
        pub fn standinOf(self: *const Builder, t: TypeId) ?Standin {
            const at_id = @intFromEnum(t);
            if (at_id >= self.standin_of.items.len) return null;
            const at = self.standin_of.items[at_id];
            if (at == Typing.not_a_standin) return null;
            return self.standins.items[at];
        }

        /// What a settled reference's key supplies for its trait's parameters.
        pub fn standinArgsOf(self: *const Builder, s: Standin) []const TypeId {
            return self.standin_args.items[s.first_arg..][0..s.arg_count];
        }

        pub fn settledTypeWritten(self: *const Builder, impl: Implementation, sig: DeclId) ?TypeId {
            const member = self.supply.memberOf(impl.decl, sig) orelse return null;
            const settled = self.decl_returns.get(member);
            return if (settled == .poison) null else settled;
        }

        /// Whether the key an implementation is found by holds a type that is
        /// not known yet: a type parameter an instantiation supplies, or an
        /// open type a function value's uses have not settled.
        ///
        /// Neither names an implementation, so a key holding one has none to
        /// reach until it is known. Asked by everything that reads such a key
        /// -- the call checking that an implementation exists, and the settled
        /// reference read through the one the call reaches -- so the readers
        /// agree about which keys have an answer.
        ///
        /// **Bound:** one lookup per part of the key, which is `Self` and the
        /// trait's parameters.
        pub fn awaitsTypes(self: *const Builder, held: TypeId, args: []const TypeId) bool {
            if (self.awaits(held)) return true;
            for (args) |a| if (self.awaits(a)) return true;
            return false;
        }

        fn awaits(self: *const Builder, t: TypeId) bool {
            return switch (self.get(t)) {
                .parameter, .open_type => true,
                else => false,
            };
        }

        /// What an implementation settles a declared type to, for one receiver.
        ///
        /// The pairing the checker recorded, and the type that member wrote.
        /// Both are answers already in hand: searching the implementation's
        /// members for a name would be a second reading of the relation the
        /// pairing is, and one no rename could move.
        ///
        /// The member writes that type in the implementation's own parameters,
        /// so the receiver is what fills them -- `impl[T] Index[T] for Pair[T]`
        /// binds `Elem` to `T`, and a `Pair[UInt8]` settles it to `UInt8`.
        /// Substituted here rather than at each reader, because every reader
        /// wants the same answer and one that forgot would hand a bare
        /// parameter to whatever it fed: a comparison against a written type,
        /// or the backend.
        ///
        /// **Bound:** one lookup, the head's arity, and one substitution over
        /// the settled type.
        pub fn settledBy(
            self: *Builder,
            impl: Implementation,
            sig: DeclId,
            impl_args: []const TypeId,
        ) std.mem.Allocator.Error!?TypeId {
            const member = self.supply.memberOf(impl.decl, sig) orelse return null;
            // `memberOf` answers with a number, so the identifier is put back
            // here: the table takes one, and this is where the two meet.
            //
            // Unguarded deliberately. A `member` past the end means the supply
            // index and the tree disagree about how many declarations exist,
            // which is this compiler being wrong rather than the program; the
            // table says so and names both halves, where returning null here
            // said "this implementation supplies no return type" and dropped
            // the member out of overloading with nothing reported.
            if (self.unsettled_members) |waiting| if (self.reading_reference and waiting.contains(member)) {
                self.unsettled_read = member;
                return null;
            };
            const settled = self.decl_returns.get(member);
            if (settled == .poison) return null;
            if (impl.parameters == 0) return settled;

            return try self.substitute(settled, impl.decl.index(), impl_args);
        }

        /// Settles a concrete trait key once, carrying the answer with the pool
        /// through checking and instantiation. A sealed emission pool only reads.
        /// Storage follows distinct keys and their argument lists; lookup costs
        /// O(A) hashing for A arguments plus expected constant map work.
        pub fn observationReferent(self: *const Builder, trait: DeclId, held: TypeId) ?TypeId {
            return self.view().observationReferent(trait, held);
        }

        pub fn implementationChoice(self: *Builder, trait: DeclId, args: []const TypeId, receiver: TypeId) std.mem.Allocator.Error!?ImplementationChoice {
            return self.implementationChoiceWithin(.none, trait, args, receiver);
        }

        /// Declaration-local promises participate in the same receiver lookup.
        /// Their answers stay local; discovery records concrete global choices.
        pub fn implementationChoiceWithin(self: *Builder, owner: DeclId, trait: DeclId, args: []const TypeId, receiver: TypeId) std.mem.Allocator.Error!?ImplementationChoice {
            if (trait == .none) return null;
            const scope = self.contextual_constraints.lookupScope(owner);
            if (self.implementations_settled) if (self.implementation_selections.rows.get(.{ .scope = scope, .trait = trait, .args = args, .receiver = receiver })) |choice| {
                return choice;
            };
            if (self.sealed) @panic("compiler defect: implementation selection was not settled before emission");
            const found = try self.impl_index.find(self.gpa, self.implementations, self, trait.index(), args, receiver, scope);
            const selected = try self.throughArrayView(owner, trait, args, found);
            return self.implementation_selections.record(self.gpa, scope, trait, args, receiver, selected);
        }

        /// Rewrites a selection of a viewed array row as the view's
        /// implementation it runs. The row applies only where that
        /// implementation does, so the second lookup answers.
        fn throughArrayView(self: *Builder, owner: DeclId, trait: DeclId, args: []const TypeId, found: ?ImplementationChoice) std.mem.Allocator.Error!?ImplementationChoice {
            const choice = found orelse return null;
            const id = choice.declaredImplementation() orelse return choice;
            if (!self.implementations[id.index()].viewed) return choice;
            const array_view = try self.arrayViewOf(choice.receiver) orelse
                @panic("compiler defect: a viewed array row applied without a view");
            var through = try self.implementationChoiceWithin(owner, trait, args, array_view) orelse
                @panic("compiler defect: a viewed array row applied without its view's implementation");
            through.receiver = choice.receiver;
            through.observations = choice.observations;
            through.view = array_view;
            return through;
        }

        /// Returns the `Slice` that views an array's elements. It returns null
        /// for a type that is not an array or a program without the view.
        pub fn arrayViewOf(self: *Builder, held: TypeId) std.mem.Allocator.Error!?TypeId {
            const array = switch (self.get(held)) {
                .array => |array| array,
                else => return null,
            };
            if (self.certified_slice == .none) return null;
            const template = self.typeOfDecl(self.certified_slice) orelse return null;
            return try self.instantiate(template, self.certified_slice, &.{array.element});
        }

        pub fn implementationRow(self: *Builder, trait: DeclId, args: []const TypeId, receiver: TypeId) std.mem.Allocator.Error!?Implementation {
            const choice = try self.implementationChoice(trait, args, receiver) orelse return null;
            const selected = choice.declaredImplementation() orelse return null;
            return self.implementations[selected.index()];
        }

        /// Finds the first trait requirement that keeps an implementation whose
        /// head and trait arguments match `receiver` from answering `trait`, so
        /// a diagnostic can say why the type does not implement it. An
        /// implementation for every type, `impl[I: Iterator] Sequence for I`,
        /// matches every receiver and is asked too, unless its head is held
        /// to integers.
        /// Requirements are read in declaration order and each is asked of
        /// the ordinary lookup, so the answer agrees with selection. A
        /// subject's traits are read before the capability it must have.
        /// The result's `args` are allocated from the builder's allocator and
        /// owned by the caller.
        ///
        /// **Bound:** the candidates of one trait for the receiver's head and
        /// for every head, and the requirements each of them writes.
        pub fn unmetRequirement(self: *Builder, trait: DeclId, args: []const TypeId, receiver: TypeId) std.mem.Allocator.Error!?UnmetRequirement {
            if (trait == .none or receiver == .poison) return null;
            const head = self.headOf(receiver);
            if (head == .parameter or head == .default_) return null;
            var decided: ImplIndex.Decided = .{ .gpa = self.gpa };
            defer decided.deinit();
            var rows = self.impl_index.candidates(self.implementations, trait.index(), head, false);
            while (rows.next()) |at| {
                const im = self.implementations[at];
                if (!im.valid_key or im.isAmbient() or im.args.len != args.len) continue;
                if (!im.head.same(head) and !im.head.same(.parameter)) continue;
                // A head held to integers answers for integers alone, which the
                // receiver is not where it reached here, so none of its
                // requirements is why.
                if (!ImplIndex.receiverDomainAdmits(self, .none, im, receiver)) continue;
                const bindings = try self.gpa.alloc(TypeId, im.parameters);
                defer self.gpa.free(bindings);
                @memset(bindings, .poison);
                if (!try self.impl_index.matchHeader(self.implementations, self, &decided, im, args, receiver, bindings)) continue;
                // A requirement whose subject holds the receiver itself fails
                // because the receiver does, so one that does not is the
                // explanation, where there is one.
                var through_receiver: ?UnmetRequirement = null;
                errdefer if (through_receiver) |unmet| self.gpa.free(unmet.args);
                for (im.predicates) |predicate| {
                    const subject = try self.substitute(predicate.subject, im.decl.index(), bindings);
                    for (predicate.demand.traits) |required| {
                        const required_args = try self.gpa.alloc(TypeId, required.args.len);
                        var handed_off = false;
                        defer if (!handed_off) self.gpa.free(required_args);
                        for (required.args, required_args) |written, *argument| argument.* = try self.substitute(written, im.decl.index(), bindings);
                        if (try self.implementationChoice(DeclId.at(required.trait), required_args, subject) != null) continue;
                        const unmet: UnmetRequirement = .{
                            .head = im.ty,
                            .subject = predicate.subject,
                            .argument = subject,
                            .trait = DeclId.at(required.trait),
                            .args = required_args,
                        };
                        if (self.holdsType(subject, receiver)) {
                            if (through_receiver == null) {
                                handed_off = true;
                                through_receiver = unmet;
                            }
                            continue;
                        }
                        if (through_receiver) |earlier| self.gpa.free(earlier.args);
                        handed_off = true;
                        return unmet;
                    }
                    if (!try self.meetsCapabilityWithin(.none, subject, predicate.demand.requirement)) {
                        const unmet: UnmetRequirement = .{
                            .head = im.ty,
                            .subject = predicate.subject,
                            .argument = subject,
                            .trait = .none,
                            .args = &.{},
                            .capability = predicate.demand.requirement,
                        };
                        if (!self.holdsType(subject, receiver)) {
                            if (through_receiver) |earlier| self.gpa.free(earlier.args);
                            return unmet;
                        }
                        if (through_receiver == null) through_receiver = unmet;
                    }
                }
                if (through_receiver) |unmet| return unmet;
            }
            return null;
        }

        /// Whether `receiver` lacks `trait` at `args` only for demands a bound
        /// refusal already reported: no implementation answers, and one does
        /// once every demand in `refused` is taken as met. The second lookup
        /// is the ordinary one with the grants consulted at each requirement
        /// it fails, of whatever kind, and through every requirement's own
        /// lookup in turn, so what it accepts differs from what selection
        /// accepts by the grants alone.
        ///
        /// Where no implementation answers even then, the refusals do not
        /// explain the missing implementation, and the caller reports it.
        ///
        /// **Bound:** one lookup of `trait` for `receiver` served from the
        /// settled selections, then the granted lookup, at the cost
        /// `appliesGranted` states; asked only while reporting.
        pub fn explainedByRefusal(
            self: *Builder,
            owner: DeclId,
            trait: DeclId,
            args: []const TypeId,
            receiver: TypeId,
            refused: *const RefusedDemands,
        ) std.mem.Allocator.Error!bool {
            if (trait == .none or receiver == .poison or refused.count() == 0) return false;
            if (try self.implementationChoiceWithin(owner, trait, args, receiver) != null) return false;
            const scope = self.contextual_constraints.lookupScope(owner);
            return self.impl_index.appliesGranted(self.gpa, self.implementations, self, trait.index(), args, receiver, scope, refused);
        }

        test "a refusal explains a missing implementation only where it fails on what was refused" {
            const gpa = testing.allocator;
            var builder = try Typing.Builder.init(gpa);
            defer builder.deinit();
            const owner = DeclId.at(0);
            const trait = DeclId.at(1);
            const parameter = try builder.addParameter("T", 0, 0, .unrestricted, &.{});
            const ticket = try builder.addStruct("Ticket", .linear, &.{});
            const plain = try builder.addStruct("Plain", .copyable, &.{});
            // `Ticket` fails its implementation's `Copyable` requirement; `Plain`
            // has an implementation with nothing to fail.
            const implementations = [_]Implementation{
                .{
                    .trait = 1,
                    .head = .{ .whole = ticket },
                    .ty = ticket,
                    .decl = trait,
                    .predicates = &.{.{ .subject = ticket, .demand = .{ .requirement = .copyable } }},
                },
                .{ .trait = 1, .head = .{ .whole = plain }, .ty = plain, .decl = trait },
            };
            var index = try ImplIndex.build(gpa, &implementations);
            defer index.deinit(gpa);
            builder.implementations = &implementations;
            builder.impl_index = index;
            const constraints: ContextualConstraints = .{
                .starts = &.{ 0, 1 },
                .parents = &.{.none},
                .capability_scopes = &.{owner},
                .items = &.{.{ .subject = parameter, .demand = .{ .requirement = .copyable } }},
            };
            builder.setContextualConstraints(constraints);
            defer builder.setContextualConstraints(.{});

            var refused: RefusedDemands = .empty;
            defer refused.deinit(gpa);
            try testing.expect(!try builder.explainedByRefusal(owner, trait, &.{}, ticket, &refused));
            try refused.put(gpa, .{ .ty = ticket, .lacks = .{ .capability = .discardable } }, {});
            try testing.expect(!try builder.explainedByRefusal(owner, trait, &.{}, ticket, &refused));
            try refused.put(gpa, .{ .ty = ticket, .lacks = .{ .capability = .copyable } }, {});
            try testing.expect(try builder.explainedByRefusal(owner, trait, &.{}, ticket, &refused));
            // What implements the trait lacks nothing for a refusal to explain.
            try testing.expect(!try builder.explainedByRefusal(owner, trait, &.{}, plain, &refused));
            try testing.expect(!try builder.explainedByRefusal(owner, .none, &.{}, ticket, &refused));
        }

        /// Says whether `inner` occurs within `outer`, `outer` itself included.
        fn holdsType(self: *const Builder, outer: TypeId, inner: TypeId) bool {
            if (outer == inner) return true;
            switch (self.get(outer)) {
                .array => |a| return self.holdsType(a.element, inner),
                .borrow => |b| return self.holdsType(b.referent, inner),
                .callable => |signature| {
                    for (self.callableParams(signature)) |param| {
                        if (self.holdsType(param.ty, inner)) return true;
                    }
                    return self.holdsType(signature.result, inner);
                },
                else => {
                    const instance = self.instanceOf(outer) orelse return false;
                    for (self.argsOf(instance)) |argument| {
                        if (self.holdsType(argument, inner)) return true;
                    }
                    return false;
                },
            }
        }

        /// Discovery records the concrete supplier; a sealed emission pool reads
        /// that same selection. A null projection is built-in array indexing.
        pub fn projectionFor(
            self: *Builder,
            typing: *const Typing,
            trait: DeclId,
            key: TypeId,
            receiver: TypeId,
        ) std.mem.Allocator.Error!?Expansion {
            const choice = try self.implementationChoice(trait, &.{key}, receiver) orelse
                @panic("compiler defect: checked Index bound has no concrete supplier");
            const selected = choice.declaredImplementation() orelse
                @panic("compiler defect: a concrete Index key still names a bound");
            const implementation = self.implementations[selected.index()];
            if (implementation.isAmbient()) {
                std.debug.assert(self.get(receiver) == .array);
                return null;
            }
            const row = typing.expansion_of_impl.get(implementation.decl) orelse
                @panic("compiler defect: Index implementation has no checked projection");
            var result = typing.expansions[row];
            result.impl_args = choice.impl_args;
            return result;
        }

        /// What a settled reference's key names, once the key is a key.
        ///
        /// The one lookup a call and a bound already go through: coherence
        /// makes at most one implementation answer a trait, its arguments and
        /// a type, so the entry the index reaches is the answer. Where any part
        /// of the key is still a parameter there is nothing to look up, and the
        /// reference stands for itself until the instantiation supplies it.
        ///
        /// Poison where the key names no implementation, which is a call the
        /// bound admitted and the instantiation does not answer -- reported
        /// where the instantiation is made rather than here, which holds no
        /// program to point at.
        ///
        /// **Bound:** one selection lookup, solving an unanswered key only in
        /// an open pool, followed by the member lookup and substitution.
        pub fn settledAt(
            self: *Builder,
            trait: u32,
            args: []const TypeId,
            held: TypeId,
            member: DeclId,
            named: []const u8,
        ) std.mem.Allocator.Error!TypeId {
            return (try self.settledAtWithin(.none, trait, args, held, member, named)).ty;
        }

        /// What `settledAtWithin` read a member as, and which answer it gave.
        pub const SettledMember = struct {
            ty: TypeId,
            /// Whether the key still held a parameter and the implementation
            /// headed by a bare parameter answered it with its own
            /// definition, rather than a stand-in awaiting an instantiation.
            head_definition: bool = false,
        };

        /// `settledAt`, with the implementation chosen in `owner`'s scope, so
        /// what `owner`'s own `where` clauses prove about a type parameter
        /// counts: a checker reading a type written inside a declaration asks
        /// here, where instantiation, whose keys hold no parameters, asks
        /// `settledAt`.
        pub fn settledAtWithin(
            self: *Builder,
            owner: DeclId,
            trait: u32,
            args: []const TypeId,
            held: TypeId,
            member: DeclId,
            named: []const u8,
        ) std.mem.Allocator.Error!SettledMember {
            if (self.awaitsTypes(held, args)) {
                if (try self.settledThroughParameterHead(owner, trait, args, held, member)) |settled| return .{ .ty = settled, .head_definition = settled != .poison };
                return .{ .ty = try self.addSettledStandin(trait, args, held, member, named) };
            }
            const choice = try self.implementationChoiceWithin(owner, DeclId.at(trait), args, held) orelse return .{ .ty = .poison };
            const implementation = choice.declaredImplementation() orelse
                return .{ .ty = try self.addSettledStandin(trait, args, held, member, named) };
            const row = self.implementations[implementation.index()];
            if (row.array_element_member == member and member != .none) {
                return .{ .ty = self.get(held).array.element };
            }
            return .{ .ty = try self.settledBy(row, member, choice.impl_args) orelse .poison };
        }

        /// What `member` settles to for a key still holding a type parameter,
        /// where the implementation answering it is headed by a bare
        /// parameter, `impl[I: Iterator] Sequence for I`, and the parameter's
        /// bounds select it. A parameter head admits no other implementation
        /// of the trait beside it that the parameter could reach -- coherence
        /// refuses the overlap, and one held to integers applies only to a
        /// parameter bounded by `Integer` -- so whatever settles the parameter
        /// reaches the same implementation. The member is then that
        /// implementation's definition, `I` for `I.Iter`, rather than a key
        /// awaiting an instantiation. Null where the trait has no parameter head or the
        /// key's bounds do not select one.
        ///
        /// **Bound:** one bucket walk over the trait's parameter heads, with one
        /// applicability question for the key per row the bucket holds.
        fn settledThroughParameterHead(self: *Builder, owner: DeclId, trait: u32, args: []const TypeId, held: TypeId, member: DeclId) std.mem.Allocator.Error!?TypeId {
            // Asked of the parameter head's own row rather than of selection,
            // which prefers a bound on the parameter that names the trait
            // itself: under `I: Iterator + Sequence` the bound answers
            // `Sequence`, and it still stands for the one implementation the
            // parameter head is, so `I.Iter` is `I` there as well.
            var rows = self.impl_index.membersOf(trait, .parameter);
            while (rows.next()) |at| {
                const row = self.implementations[at];
                if (row.trait != trait or !row.head.same(.parameter) or !row.valid_key) continue;
                const bound = try self.implementationArgumentsWithin(owner, @enumFromInt(at), args, held) orelse continue;
                return try self.settledBy(row, member, bound);
            }
            return null;
        }

        /// The descriptor a handle stands for, so a caller can ask what kind
        /// of type it has rather than inferring it from what answers.
        pub fn get(self: *const Builder, t: TypeId) Type {
            return self.pool.items[@intFromEnum(t)];
        }

        pub fn knownNoncopyable(self: *Builder, t: TypeId) !bool {
            try self.capability_facts.update(self);
            return self.capability_facts.known_noncopyable.items[t.index()];
        }

        pub fn capabilityView(self: *Builder) !Typing {
            try self.capability_facts.update(self);
            return self.view();
        }

        pub fn dependencyView(self: *Builder) !Typing {
            try self.dependency_facts.update(self, .raw_carriers);
            return self.view();
        }

        pub fn coversDependencyPaths(self: *Builder, comptime Path: type, ty: TypeId, paths: []const Path, context: anytype) !bool {
            const pool = try self.dependencyView();
            return self.dependency_facts.coverage.covers(Path, self.gpa, &pool, ty, paths, context);
        }

        pub fn capabilityOf(self: *Builder, t: TypeId) !Capability {
            try self.capability_facts.update(self);
            return self.capability_facts.values.items[t.index()];
        }

        pub fn prepareCapabilityWithin(self: *Builder, owner: DeclId, t: TypeId) !void {
            try self.capability_facts.update(self);
            const scope = self.contextual_constraints.activeCapabilityScope(owner);
            if (scope != .none) try self.scoped_capability_facts.prepare(self, scope, t);
        }

        pub fn prepareTraitLookupWithin(self: *Builder, owner: DeclId, trait: DeclId, t: TypeId) !void {
            try self.prepareCapabilityWithin(owner, t);
            if (t == .poison) return;
            _ = try self.impl_index.any(self.gpa, self.implementations, self, trait.index(), t, self.contextual_constraints.lookupScope(owner), .forward);
        }

        pub fn prepareLookupWithin(self: *Builder, owner: DeclId, t: TypeId) !void {
            try self.capability_facts.update(self);
            const capability_scope = self.contextual_constraints.activeCapabilityScope(owner);
            if (capability_scope != .none) try self.scoped_capability_facts.prepare(self, capability_scope, t);
            if (t == .poison) return;
            const scope = self.contextual_constraints.lookupScope(owner);
            var held = t;
            while (true) {
                const root: ScopedCapabilityKey = .{ .scope = scope, .ty = held };
                if (self.prepared_implementations.roots.contains(root)) break;
                {
                    var decided: ImplIndex.Decided = .{ .gpa = self.gpa, .scope = scope };
                    defer decided.deinit();
                    for ([_]Head{ self.headOf(held), .parameter, .default_ }) |head| try self.prepareRowsUnder(&decided, head, held);
                    // Immutable member lookup needs the selected supplier's nested
                    // implementation evidence as well as the receiver's own rows.
                    if (self.closure_release) |release|
                        _ = try self.impl_index.closureReleases(self.implementations, self, &decided, release.trait.index(), held);
                    try self.prepared_implementations.roots.put(self.gpa, root, {});
                }
                held = switch (self.get(held)) {
                    .borrow => |observation| observation.referent,
                    else => break,
                };
            }
        }

        /// Prepares, for a lookup from `owner`, whether each implementation
        /// written for `t`'s own head applies to `t`, and nothing else: no
        /// blanket or default implementation and no observation's referent.
        ///
        /// For a reader that asks only about the rows under a type's head,
        /// such as a report naming what settles a value. Once per
        /// (lookup scope, type), and each time the rows under that one head,
        /// each with its applicability decided once and remembered; a blanket
        /// row, which any type could reach, is never walked here, so the cost
        /// is sized by what the type's family implements.
        pub fn prepareHeadLookupWithin(self: *Builder, owner: DeclId, t: TypeId) !void {
            try self.prepareCapabilityWithin(owner, t);
            if (t == .poison) return;
            const scope = self.contextual_constraints.lookupScope(owner);
            const root: ScopedCapabilityKey = .{ .scope = scope, .ty = t };
            if (self.prepared_implementations.roots.contains(root)) return;
            if (self.prepared_implementations.head_roots.contains(root)) return;
            var decided: ImplIndex.Decided = .{ .gpa = self.gpa, .scope = scope };
            defer decided.deinit();
            try self.prepareRowsUnder(&decided, self.headOf(t), t);
            try self.prepared_implementations.head_roots.put(self.gpa, root, {});
        }

        test "a head lookup prepares the rows under the type's head and no blanket row" {
            const gpa = testing.allocator;
            var builder = try Builder.init(gpa);
            defer builder.deinit();
            const ticket = try builder.addStruct("Ticket", .linear, &.{});
            const parameter = try builder.addParameter("T", 0, 0, .unrestricted, &.{});
            const implementations = [_]Implementation{
                .{ .trait = 1, .head = .{ .whole = ticket }, .ty = ticket, .decl = .at(1) },
                .{ .trait = 2, .head = .parameter, .ty = parameter, .decl = .at(2), .parameters = 1 },
            };
            var index = try ImplIndex.build(gpa, &implementations);
            defer index.deinit(gpa);
            builder.implementations = &implementations;
            builder.impl_index = index;

            try builder.prepareHeadLookupWithin(.none, ticket);
            const pool = builder.view();
            const own = try pool.receiverTraitArguments(@enumFromInt(0), ticket);
            try testing.expect(own != null);
            try testing.expect(pool.implementationArgumentsWithin(.none, @enumFromInt(0), own.?, ticket) != null);
            // The blanket row was never asked about, where a full lookup would
            // have recorded an answer for it.
            try testing.expect(pool.prepared_implementations.receiver_args.get(.{ .implementation = @enumFromInt(0), .receiver = ticket }) != null);
            try testing.expect(pool.prepared_implementations.receiver_args.get(.{ .implementation = @enumFromInt(1), .receiver = ticket }) == null);
        }

        /// Decides whether calling `operation`, a member of an implementation,
        /// on a value of `receiver` in `owner` leaves a result that still owes:
        /// `returns`, the result its signature writes, with the arguments the
        /// implementation binds for `receiver` substituted, asked in `owner`'s
        /// scope. Records nothing where the implementation does not apply to
        /// `receiver`. The implementation's applicability is read through the
        /// lookup `prepareHeadLookupWithin` prepared for `receiver`, so that
        /// comes first. Once per (owner, receiver, operation).
        pub fn prepareSettlingResult(self: *Builder, owner: DeclId, receiver: TypeId, operation: DeclId, returns: TypeId) !void {
            const key_: SettlingResultKey = .{ .owner = owner, .receiver = receiver, .operation = operation };
            if (self.prepared_implementations.settling_results.contains(key_)) return;
            if (returns == .poison or operation.index() >= self.impl_of_decl.len) return;
            const at = self.impl_of_decl[operation.index()];
            if (at == Typing.no_implementation) return;
            const implementation: ImplementationId = @enumFromInt(at);
            const args = try self.receiverTraitArguments(implementation, receiver) orelse return;
            const bindings = try self.implementationArgumentsWithin(owner, implementation, args, receiver) orelse return;
            const result = try self.substitute(returns, self.implementations[at].decl.index(), bindings);
            const owes = try self.mustConsumeWithin(owner, result);
            try self.prepared_implementations.settling_results.put(self.gpa, key_, owes);
        }

        /// Decides whether calling `sig`, a signature of the trait `row`
        /// implements, on a value of `receiver` in `owner` leaves a result
        /// that still owes: the result the member supplying `sig` writes, with
        /// the selected implementation's arguments substituted, asked in
        /// `owner`'s scope. The implementation is the one
        /// `implementationChoiceWithin` selects for the trait arguments `row`
        /// binds for `receiver`, the lookup a call makes, so a blanket
        /// implementation answers where it is the one a call would run.
        ///
        /// Where `row` matches `receiver` but leaves the trait's arguments to
        /// the call, as `impl[T, U: From[T]] Into[U] for T` does, no
        /// implementation can be selected without the call, so the result is
        /// recorded as owing and the operation is never named as settling.
        /// Records nothing where `row` does not match `receiver`, where no
        /// declared implementation answers, or where the one that does
        /// supplies no member for `sig`. Once per (owner, receiver, sig): the
        /// first row that decides it answers.
        pub fn prepareTraitSettlingResult(self: *Builder, owner: DeclId, receiver: TypeId, row: ImplementationId, sig: DeclId) !void {
            const key_: SettlingResultKey = .{ .owner = owner, .receiver = receiver, .operation = sig };
            if (self.prepared_implementations.settling_results.contains(key_)) return;
            if (receiver == .poison) return;
            const args = switch (try self.receiverImplementation(row, receiver)) {
                .settled => |args| args,
                .open => return self.prepared_implementations.settling_results.put(self.gpa, key_, true),
                .absent => return,
            };
            const trait = DeclId.at(self.implementations[row.index()].trait);
            const choice = try self.implementationChoiceWithin(owner, trait, args, receiver) orelse return;
            const implementation = choice.declaredImplementation() orelse return;
            const result = try self.settledBy(self.implementations[implementation.index()], sig, choice.impl_args) orelse return;
            const owes = try self.mustConsumeWithin(owner, result);
            try self.prepared_implementations.settling_results.put(self.gpa, key_, owes);
        }

        test "a trait's settling result is the selected implementation's, substituted" {
            const gpa = testing.allocator;
            var builder = try Builder.init(gpa);
            defer builder.deinit();
            const trait = DeclId.at(1);
            const sig = DeclId.at(2);
            const blanket = DeclId.at(3);
            const member = DeclId.at(4);
            const turn = DeclId.at(5);
            const turn_sig = DeclId.at(6);
            const open_blanket = DeclId.at(7);
            const ticket = try builder.addStruct("Ticket", .linear, &.{});
            const coin = try builder.addStruct("Coin", .affine, &.{});
            const parameter = try builder.addParameter("I", @intCast(blanket.index()), 0, .unrestricted, &.{});
            const from = try builder.addParameter("T", @intCast(open_blanket.index()), 0, .unrestricted, &.{});
            const to = try builder.addParameter("U", @intCast(open_blanket.index()), 1, .unrestricted, &.{});
            // `impl[I] Hand for I { fn hand(sink self: Self) -> I }`: the
            // member answers its receiver, whatever the trait's signature
            // says. `impl[T, U] Turn[U] for T` leaves `U` to the call.
            const implementations = [_]Implementation{
                .{ .trait = @intCast(trait.index()), .head = .parameter, .ty = parameter, .decl = blanket, .parameters = 1 },
                .{ .trait = @intCast(turn.index()), .head = .parameter, .ty = from, .args = &.{to}, .decl = open_blanket, .parameters = 2 },
            };
            var index = try ImplIndex.build(gpa, &implementations);
            defer index.deinit(gpa);
            builder.implementations = &implementations;
            builder.impl_index = index;
            var supply = try SupplyIndex.build(gpa, 8, &.{.{ .impl = blanket, .sig = sig, .member = member }});
            defer supply.deinit(gpa);
            builder.supply = supply;
            const returns = [_]TypeId{ .poison, .poison, .poison, .poison, parameter, .poison, .poison, .poison };
            builder.decl_returns = .{ .entries = &returns };

            for ([_]TypeId{ ticket, coin }) |receiver| try builder.prepareTraitSettlingResult(.none, receiver, @enumFromInt(0), sig);
            const pool = builder.view();
            try testing.expectEqual(@as(?bool, true), pool.settlingResultOwes(.none, ticket, sig));
            try testing.expectEqual(@as(?bool, false), pool.settlingResultOwes(.none, coin, sig));
            // A signature no implementation supplies a member for is never decided.
            try builder.prepareTraitSettlingResult(.none, ticket, @enumFromInt(0), member);
            try testing.expectEqual(@as(?bool, null), builder.view().settlingResultOwes(.none, ticket, member));
            // A row leaving the trait's arguments to the call selects nothing,
            // so its operation is recorded as owing.
            try builder.prepareTraitSettlingResult(.none, coin, @enumFromInt(1), turn_sig);
            try testing.expectEqual(@as(?bool, true), builder.view().settlingResultOwes(.none, coin, turn_sig));
        }

        test "a settling result substitutes the receiver's block arguments" {
            const gpa = testing.allocator;
            var builder = try Builder.init(gpa);
            defer builder.deinit();
            const box_decl = DeclId.at(1);
            const block = DeclId.at(2);
            const take = DeclId.at(3);
            const template = try builder.addStruct("Box", .linear, &.{});
            try builder.noteTemplate(box_decl, 0, template);
            const parameter = try builder.addParameter("T", @intCast(block.index()), 0, .unrestricted, &.{});
            const boxed = try builder.instantiate(template, box_decl, &.{parameter});
            const implementations = [_]Implementation{
                .{ .trait = Implementation.no_trait, .head = .{ .applied = box_decl }, .ty = boxed, .decl = block, .parameters = 1 },
            };
            var index = try ImplIndex.build(gpa, &implementations);
            defer index.deinit(gpa);
            builder.implementations = &implementations;
            builder.impl_index = index;
            const impl_of_decl = [_]u32{ Typing.no_implementation, Typing.no_implementation, Typing.no_implementation, 0 };
            builder.impl_of_decl = &impl_of_decl;

            const ticket = try builder.addStruct("Ticket", .linear, &.{});
            const of_scalar = try builder.instantiate(template, box_decl, &.{.u8});
            const of_ticket = try builder.instantiate(template, box_decl, &.{ticket});
            for ([_]TypeId{ of_scalar, of_ticket }) |receiver| {
                try builder.prepareHeadLookupWithin(.none, receiver);
                try builder.prepareSettlingResult(.none, receiver, take, parameter);
            }
            const pool = builder.view();
            try testing.expectEqual(@as(?bool, false), pool.settlingResultOwes(.none, of_scalar, take));
            try testing.expectEqual(@as(?bool, true), pool.settlingResultOwes(.none, of_ticket, take));
            // A declaration no implementation encloses is never decided.
            try builder.prepareSettlingResult(.none, of_scalar, box_decl, parameter);
            try testing.expectEqual(@as(?bool, null), builder.view().settlingResultOwes(.none, of_scalar, box_decl));
        }

        /// Decides, and so prepares, whether each implementation recorded
        /// under `head` applies to `held`.
        fn prepareRowsUnder(self: *Builder, decided: *ImplIndex.Decided, head: Head, held: TypeId) !void {
            var candidates = self.impl_index.membersOfHead(head);
            while (candidates.next()) |at| {
                if (!self.implementations[at].head.same(head)) continue;
                const args = try self.receiverTraitArguments(@enumFromInt(at), held) orelse continue;
                _ = try self.implementationApplies(&self.impl_index, self.implementations, decided, at, args, held);
            }
        }

        pub fn implementationArgumentsWithin(self: *Builder, owner: DeclId, implementation: ImplementationId, args: []const TypeId, receiver: TypeId) !?[]const TypeId {
            var decided: ImplIndex.Decided = .{ .gpa = self.gpa, .scope = self.contextual_constraints.lookupScope(owner) };
            defer decided.deinit();
            return self.implementationApplies(&self.impl_index, self.implementations, &decided, @intCast(implementation.index()), args, receiver);
        }

        pub fn implementationArguments(self: *Builder, implementation: ImplementationId, args: []const TypeId, receiver: TypeId) !?[]const TypeId {
            return self.implementationArgumentsWithin(.none, implementation, args, receiver);
        }

        fn implementationApplies(self: *Builder, index: *const ImplIndex, impls: []const Implementation, decided: *ImplIndex.Decided, at: u32, args: []const TypeId, held: TypeId) std.mem.Allocator.Error!?[]const TypeId {
            return (try self.implementationCandidate(index, impls, decided, at, args, held)).arguments;
        }

        fn implementationCandidate(self: *Builder, index: *const ImplIndex, impls: []const Implementation, decided: *ImplIndex.Decided, at: u32, args: []const TypeId, held: TypeId) std.mem.Allocator.Error!ImplementationCandidate {
            const key_: PreparedImplementationKey = .{ .scope = self.contextual_constraints.lookupScope(decided.scope), .receiver = held, .implementation = @enumFromInt(at), .args = args };
            // An answer under grants is neither read from the record nor
            // written to it: the record holds what applies, and a granted
            // lookup asks what would apply.
            if (decided.granted == null) if (self.prepared_implementations.answers.get(key_)) |answer| {
                if (answer.arguments != null) if (decided.prerequisite_sizes.get(@enumFromInt(at))) |previous| {
                    if (try decided.keySize(self, held, args) >= previous) {
                        decided.recursive_refusals += 1;
                        return .{ .header_matches = answer.header_matches };
                    }
                };
                return answer;
            };
            if (self.sealed) @panic("implementation applicability was not prepared before emission");
            if (decided.active.get(key_)) |header_matches| {
                // A question that reaches back to itself is a cycle. One that
                // passes through a derived implementation is assumed to hold:
                // a derived body recurses through the fields of a finite
                // value, so the assumption holds exactly when the requirements
                // outside the cycle do. Any other cycle is refused. Either way
                // the answer rests on this key, so nothing decided under it is
                // recorded until the key itself is settled.
                try decided.assumed.append(self.gpa, key_);
                if (header_matches and decided.cycleIsDerived(key_)) {
                    if (try self.coinductiveArguments(impls, decided, impls[at], args, held)) |bindings| {
                        return .{ .header_matches = true, .arguments = bindings };
                    }
                }
                return .{ .header_matches = header_matches };
            }
            try decided.active.put(self.gpa, key_, false);
            defer _ = decided.active.remove(key_);
            try decided.frames.append(self.gpa, .{ .key = key_, .derived = impls[at].derived });
            defer _ = decided.frames.pop();
            const before = decided.recursive_refusals;
            const independent = decided.prerequisite_sizes.count() == 0;
            const assumed_before = decided.assumed.items.len;
            const answer = try index.checkCandidate(impls, self, decided, at, args, held, key_);
            defer if (answer.arguments) |values| self.gpa.free(values);
            // A refusal caused by an enclosing obligation's measure must not
            // poison a later independent query for this same key.
            if (!independent and answer.arguments == null and decided.recursive_refusals != before) return answer;
            // Assumptions about this key are settled by its own answer. One
            // about an enclosing key is not settled yet, so an answer resting
            // on it is returned without being recorded.
            var kept = assumed_before;
            for (decided.assumed.items[assumed_before..]) |assumed| {
                if (PreparedImplementationKey.Context.eql(.{}, assumed, key_)) continue;
                decided.assumed.items[kept] = assumed;
                kept += 1;
            }
            decided.assumed.items.len = kept;
            if (kept != assumed_before or decided.granted != null) return .{
                .header_matches = answer.header_matches,
                .arguments = if (answer.arguments) |values| try self.prepared_implementations.retainArguments(self.gpa, values) else null,
            };
            return self.prepared_implementations.record(self.gpa, key_, answer);
        }

        /// Returns the bindings an implementation's head gives a receiver it is
        /// already deciding, retained with the lookup's other answers.
        fn coinductiveArguments(self: *Builder, impls: []const Implementation, decided: *ImplIndex.Decided, im: Implementation, args: []const TypeId, held: TypeId) std.mem.Allocator.Error!?[]const TypeId {
            const bindings = try self.gpa.alloc(TypeId, im.parameters);
            defer self.gpa.free(bindings);
            @memset(bindings, .poison);
            if (!try self.impl_index.matchHeader(impls, self, decided, im, args, held, bindings)) return null;
            return try self.prepared_implementations.retainArguments(self.gpa, bindings);
        }

        pub fn receiverTraitArguments(self: *Builder, implementation: ImplementationId, receiver: TypeId) !?[]const TypeId {
            return switch (try self.receiverImplementation(implementation, receiver)) {
                .settled => |args| args,
                else => null,
            };
        }

        fn receiverImplementation(self: *Builder, implementation: ImplementationId, receiver: TypeId) !ReceiverImplementation {
            const key_: ReceiverImplementationKey = .{ .implementation = implementation, .receiver = receiver };
            if (self.prepared_implementations.receiver_args.get(key_)) |answer| return answer;
            if (self.sealed) @panic("receiver implementation discovery was not prepared before emission");
            const im = self.implementations[implementation.index()];
            const bindings = try self.gpa.alloc(TypeId, im.parameters);
            defer self.gpa.free(bindings);
            @memset(bindings, .poison);
            const args: ReceiverImplementation = blk: {
                if (!im.valid_key or receiver == .poison) break :blk .absent;
                if (!ImplIndex.bindHeader(self, im, null, receiver, bindings)) break :blk .absent;
                for (bindings) |bound| if (bound == .poison) break :blk .open;
                const out = try self.gpa.alloc(TypeId, im.args.len);
                errdefer self.gpa.free(out);
                for (im.args, out) |written, *argument| argument.* = try self.substitute(written, im.decl.index(), bindings);
                break :blk .{ .settled = out };
            };
            defer if (args == .settled) self.gpa.free(args.settled);
            const retained: ReceiverImplementation = if (args == .settled)
                .{ .settled = try self.prepared_implementations.retainArguments(self.gpa, args.settled) }
            else
                args;
            try self.prepared_implementations.receiver_args.put(self.gpa, key_, retained);
            return retained;
        }

        pub fn capabilityOfWithin(self: *Builder, owner: DeclId, t: TypeId) !Capability {
            try self.prepareCapabilityWithin(owner, t);
            return self.view().capabilityOfWithin(owner, t);
        }

        pub fn invalidateImplementationLookup(self: *Builder) void {
            self.prepared_implementations.clear();
        }

        pub fn setContextualConstraints(self: *Builder, constraints: ContextualConstraints) void {
            self.scoped_capability_facts.deinit(self.gpa);
            self.contextual_constraints = constraints;
            self.prepared_implementations.clear();
        }

        pub fn isScalarSnapshot(self: *const Builder, t: TypeId) bool {
            return self.view().isScalarSnapshot(t);
        }

        pub fn mayCopy(self: *Builder, t: TypeId) !bool {
            return try self.capabilityOf(t) == .copyable;
        }
        pub fn mustConsume(self: *Builder, t: TypeId) !bool {
            return try self.capabilityOf(t) == .linear;
        }
        pub fn mayDiscard(self: *Builder, t: TypeId) !bool {
            return !try self.mustConsume(t);
        }
        pub fn mayCopyWithin(self: *Builder, owner: DeclId, t: TypeId) !bool {
            return try self.capabilityOfWithin(owner, t) == .copyable;
        }
        pub fn mustConsumeWithin(self: *Builder, owner: DeclId, t: TypeId) !bool {
            return try self.capabilityOfWithin(owner, t) == .linear;
        }
        pub fn mayDiscardWithin(self: *Builder, owner: DeclId, t: TypeId) !bool {
            return !try self.mustConsumeWithin(owner, t);
        }

        pub fn isIntegerWithin(self: *const Builder, owner: DeclId, t: TypeId) bool {
            return self.view().isIntegerWithin(owner, t);
        }

        pub fn meetsCapabilityWithin(self: *Builder, owner: DeclId, t: TypeId, requirement: CapabilityRequirement) std.mem.Allocator.Error!bool {
            return meetsCapability(requirement, try self.capabilityOfWithin(owner, t));
        }

        /// Whether a type is the one a literal mints, answered while the pool
        /// is open by the routine that answers once it is closed.
        pub fn isInterpolation(self: *const Builder, t: TypeId) bool {
            return interpolationWithin(self.pool.items, self.interpolation_of.items, t);
        }

        pub fn interpolationFormats(self: *const Builder, t: TypeId) []const node.InterpolationFormat {
            return self.view().interpolationFormats(t);
        }

        /// Whether a type carries `trait` as a bound, at `args` or at all
        /// where `args` is `null`, answered while the pool is open by the
        /// routine that answers once it is closed.
        pub fn boundsCarry(self: *const Builder, t: TypeId, trait: u32, args: ?[]const TypeId) bool {
            return self.view().boundsCarry(t, trait, args);
        }

        pub fn boundsCarryWithin(self: *const Builder, owner: DeclId, t: TypeId, trait: u32, args: ?[]const TypeId) bool {
            return self.view().boundsCarryWithin(owner, t, trait, args);
        }

        pub fn boundArgumentsWithin(self: *const Builder, owner: DeclId, t: TypeId, trait: u32, out: *std.ArrayList([]const TypeId)) std.mem.Allocator.Error!void {
            return self.view().boundArgumentsWithin(self.gpa, owner, t, trait, out);
        }

        pub fn carriesCallableBoundWithin(self: *const Builder, owner: DeclId, t: TypeId, signature: TypeId) bool {
            return self.view().carriesCallableBoundWithin(owner, t, signature);
        }

        /// The bounds a parameter carries, answered while the pool is open by
        /// the routine that answers once it is closed.
        pub fn boundsOn(self: *const Builder, t: TypeId) []const BoundTrait {
            return self.view().boundsOn(t);
        }

        pub fn variantCount(self: *const Builder, t: TypeId) u32 {
            return self.view().variantCount(t);
        }

        pub fn variantIndexOf(self: *const Builder, t: TypeId, name: []const u8) ?u32 {
            return self.view().variantIndexOf(t, name);
        }

        pub fn setExpr(self: *Builder, id: ExprId, t: TypeId) void {
            self.expr_types.items[id.index()] = t;
        }

        pub fn setConstruction(self: *Builder, id: ExprId, t: TypeId) void {
            self.construction_types.items[id.index()] = t;
        }

        /// What was recorded for an expression, or poison where nothing was.
        pub fn exprType(self: *const Builder, id: ExprId) TypeId {
            if (id.index() >= self.expr_types.items.len) return .poison;
            return self.expr_types.items[id.index()];
        }

        pub fn finish(self: *Builder, binding_types: BindingTypes) !Typing {
            try self.capability_facts.update(self);
            try self.dependency_facts.update(self, .raw_carriers);
            try self.writer_facts.update(self, .writers);
            const mapped = self.interpolation_of.items.len;
            try self.interpolation_of.resize(self.gpa, self.pool.items.len);
            @memset(self.interpolation_of.items[mapped..], not_an_interpolation);

            // Dropped first, and dropped rather than handed over: the chain is
            // how a builder finds a pair it has already minted, and a finished
            // pool mints nothing. Emptied as well as freed, so a `deinit` after
            // a `finish` that failed part-way frees it once.
            self.minted.deinit(self.gpa);
            self.minted = .empty;
            self.parameters.deinit(self.gpa);
            self.parameters = .empty;
            // The chain over the standins goes the same way and for the same
            // reason; the records themselves are handed over, because
            // substitution settles one in the pass after this too.
            self.awaiting.deinit(self.gpa);
            self.awaiting = .empty;
            self.interned_callables.deinit(self.gpa);
            self.interned_arrays.deinit(self.gpa);
            self.interned_arrays = .empty;
            self.borrowed_types.deinit(self.gpa);
            self.borrowed_types = .empty;
            self.interned_callables = .empty;
            self.interned_closures.deinit(self.gpa);
            self.interned_closures = .empty;

            // One handover at a time, each owned from the moment it is taken.
            // As one struct literal, a field that fails leaves every field
            // before it moved out of the builder and into nothing.
            const pool = try self.pool.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(pool);

            var variants = VariantColumns.fromSlice(self.variants.toOwnedSlice());
            errdefer variants.deinit(self.gpa);

            var fields = FieldColumns.fromSlice(self.fields.toOwnedSlice());
            errdefer fields.deinit(self.gpa);

            const callable_params = try self.callable_params.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(callable_params);

            const closure_args = try self.closure_args.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(closure_args);

            const expr_types = try self.expr_types.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(expr_types);

            const construction_types = try self.construction_types.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(construction_types);

            const interpolations = try self.interpolations.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(interpolations);

            const interpolation_pieces = try self.interpolation_pieces.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(interpolation_pieces);

            const interpolation_formats = try self.interpolation_formats.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(interpolation_formats);

            const interpolation_borrows = try self.interpolation_borrows.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(interpolation_borrows);

            const interpolation_of = try self.interpolation_of.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(interpolation_of);

            const templates = try self.templates.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(templates);

            const template_of = try self.template_of.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(template_of);

            const instances = try self.instances.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(instances);

            const instance_args = try self.instance_args.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(instance_args);

            const instance_of = try self.instance_of.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(instance_of);

            // The spellings are the one handover that owns what it holds, so
            // it needs the one errdefer that frees the entries too: taken out
            // of the builder and not yet in a typing, a later failure leaves
            // them belonging to nobody.
            const owned_bounds = try self.owned_bounds.toOwnedSlice(self.gpa);
            errdefer {
                for (owned_bounds) |b| freeBoundTraits(self.gpa, b);
                self.gpa.free(owned_bounds);
            }
            const owned_callable_bounds = try self.owned_callable_bounds.toOwnedSlice(self.gpa);
            errdefer {
                for (owned_callable_bounds) |b| self.gpa.free(b);
                self.gpa.free(owned_callable_bounds);
            }

            var scoped_capabilities = self.scoped_capability_facts.values;
            self.scoped_capability_facts.values = .empty;
            self.scoped_capability_facts.deinit(self.gpa);
            errdefer scoped_capabilities.deinit(self.gpa);
            var prepared_implementations = self.prepared_implementations;
            self.prepared_implementations = .{};
            errdefer prepared_implementations.deinit(self.gpa);
            const capabilities = try self.capability_facts.values.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(capabilities);
            self.capability_facts.deinit(self.gpa);
            const dependency_containment = try self.dependency_facts.values.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(dependency_containment);
            self.dependency_facts.deinit(self.gpa);
            const writer_containment = try self.writer_facts.values.toOwnedSlice(self.gpa);
            self.writer_facts.deinit(self.gpa);
            errdefer self.gpa.free(writer_containment);

            const owned_contracts = try self.owned_contracts.toOwnedSlice(self.gpa);
            errdefer {
                for (owned_contracts) |contracts| freeContracts(self.gpa, contracts);
                self.gpa.free(owned_contracts);
            }
            const owned_names = try self.owned_names.toOwnedSlice(self.gpa);
            errdefer {
                for (owned_names) |n| self.gpa.free(n);
                self.gpa.free(owned_names);
            }

            const laid_out = try self.laid_out.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(laid_out);
            // Only the checker asks which types hold an open integer.
            self.open_mentions.deinit(self.gpa);
            self.open_mentions = .empty;
            self.ground_memo.deinit(self.gpa);
            self.ground_memo = .empty;
            self.unsettled_memo.deinit(self.gpa);
            self.unsettled_memo = .empty;

            const offsets = try self.offsets.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(offsets);

            const placed_at = try self.placed_at.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(placed_at);

            const by_name = try self.by_name.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(by_name);

            const sorted = try self.sorted.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(sorted);

            const standins = try self.standins.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(standins);

            const standin_args = try self.standin_args.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(standin_args);

            const standin_of = try self.standin_of.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(standin_of);

            var constant_pool = try self.constant_pool.clone(self.gpa);
            errdefer constant_pool.deinit(self.gpa);

            const implementation_selections = self.implementation_selections;
            self.implementation_selections = .{};

            return .{
                .constant_pool = constant_pool,
                .implementation_selections = implementation_selections,
                .closure_release = self.closure_release,
                .tuple_decls = self.tuple_decls,
                // Empty here and filled by the checker, which allocated it and
                // owns it. This pass only ever borrowed it to read.
                .decl_returns = .empty,
                .pool = pool,
                .capabilities = capabilities,
                .scoped_capabilities = scoped_capabilities,
                .prepared_implementations = prepared_implementations,
                .variants = variants,
                .fields = fields,
                .callable_params = callable_params,
                .closure_args = closure_args,
                .expr_types = expr_types,
                .construction_types = construction_types,
                .interpolations = interpolations,
                .interpolation_pieces = interpolation_pieces,
                .interpolation_formats = interpolation_formats,
                .interpolation_borrows = interpolation_borrows,
                .interpolation_of = interpolation_of,
                .templates = templates,
                .template_of = template_of,
                .instances = instances,
                .instance_args = instance_args,
                .instance_of = instance_of,
                .owned_names = owned_names,
                .owned_contracts = owned_contracts,
                .dependency_containment = dependency_containment,
                .writer_containment = writer_containment,
                .owned_bounds = owned_bounds,
                .owned_callable_bounds = owned_callable_bounds,
                .binding_types = binding_types,
                .laid_out = laid_out,
                .offsets = offsets,
                .placed_at = placed_at,
                .generation = self.generation,
                .by_name = by_name,
                .sorted = sorted,
                .standins = standins,
                .standin_args = standin_args,
                .standin_of = standin_of,
            };
        }

        /// The tables a pool reads and does not own: which implementation
        /// answers a trait and a type, which of them each declaration sits
        /// inside, which member supplies each signature, and what each
        /// declaration settled.
        ///
        /// Named as one set because settling a settled reference is a reading
        /// of all of them, and a pool holding some is a pool that answers with
        /// poison rather than with a refusal. A builder reopened from a pool
        /// that carries none -- one a later pass finished, which mints a
        /// typing from the types alone -- is pointed at the one that does.
        pub fn borrowTables(self: *Builder, t: *const Typing) void {
            self.constant_pool = &t.constant_pool;
            self.observation_traits = t.observation_traits;
            self.implementations = t.implementations;
            self.setContextualConstraints(t.contextual_constraints);
            self.impl_of_decl = t.impl_of_decl;
            self.impl_index = t.impl_index;
            self.supply = t.supply_index;
            self.decl_returns = t.decl_returns.reading();
            self.declared_requirements = t.declared_requirements;
            self.declared_traits = t.declared_traits;
            self.declared_callables = t.declared_callables;
            self.closure_descriptors = t.closures;
            self.closure_release = t.closure_release;
            self.module_paths = t.module_paths;
        }

        /// A builder holding everything a finished pool holds, so a later pass
        /// can intern into it.
        ///
        /// Appending is all that happens: every handle the checker issued
        /// still means what it meant, because an index into a list that only
        /// grows never moves. That is the whole of what makes the pool safe to
        /// hand on rather than freeze.
        pub fn reopen(gpa: std.mem.Allocator, t: *const Typing) !Builder {
            var b: Builder = .{ .gpa = gpa };
            // A partly-filled builder is nobody's to release: the caller is
            // handed a value, not a pointer, so a failure here strands
            // everything appended before it.
            errdefer b.deinit();
            // Owned spellings and bound runs are deliberately not copied.
            // The entries are shared with `t`, which still frees its own
            // spellings and its own bound lists; this builder owns only what it
            // goes on to mint.
            b.borrowTables(t);
            b.scoped_capability_facts.values = try t.scoped_capabilities.clone(gpa);
            b.prepared_implementations = try t.prepared_implementations.clone(gpa);
            b.certified_storage = t.raw_accesses.storage;
            b.certified_buffer = t.raw_accesses.buffer;
            b.certified_slice = t.raw_accesses.slice;
            b.certified_closure_entry = t.raw_accesses.closure_entry_type;
            b.tuple_decls = t.tuple_decls;
            b.implementations_settled = true;
            b.implementation_selections = try t.implementation_selections.clone(gpa);
            try b.pool.appendSlice(gpa, t.pool);
            for (t.pool, 0..) |entry, i| {
                if (entry == .array) try b.interned_arrays.put(gpa, .{ .element = entry.array.element, .count = entry.array.count }, @enumFromInt(@as(u32, @intCast(i))));
                if (entry == .borrow) try b.borrowed_types.put(gpa, entry.borrow.referent, @enumFromInt(@as(u32, @intCast(i))));
                // Associated projections have their own interning key. Only
                // ordinary parameters participate in declaration/position lookup.
                if (entry == .parameter and t.standinOf(@enumFromInt(i)) == null) {
                    try b.parameters.put(gpa, parameterKey(entry.parameter.owner, entry.parameter.index), @intCast(i));
                }
            }
            try b.laid_out.appendNTimes(gpa, .{}, t.pool.len);
            try b.variants.resize(gpa, t.variants.len);
            const variant_columns = b.variants.slice();
            @memcpy(variant_columns.items(.name), t.variants.items(.name));
            @memcpy(variant_columns.items(.first_field), t.variants.items(.first_field));
            @memcpy(variant_columns.items(.field_count), t.variants.items(.field_count));
            try b.fields.resize(gpa, t.fields.len);
            const field_columns = b.fields.slice();
            const field_names = t.fields.items(.name);
            const field_types = t.fields.items(.ty);
            @memcpy(field_columns.items(.name), field_names);
            @memcpy(field_columns.items(.ty), field_types);
            try b.callable_params.appendSlice(gpa, t.callable_params);
            try b.closure_args.appendSlice(gpa, t.closure_args);
            // Callable and closure positions share the type ID domain, but
            // each chain ends at its own last represented position.
            var callable_count: u32 = 0;
            var callable_end: usize = 0;
            var closure_count: u32 = 0;
            var closure_end: usize = 0;
            for (t.pool, 0..) |entry, i| switch (entry) {
                .callable => {
                    callable_count += 1;
                    callable_end = i + 1;
                },
                .closure => {
                    closure_count += 1;
                    closure_end = i + 1;
                },
                else => {},
            };
            try b.interned_callables.reserve(gpa, callable_count, callable_end);
            try b.interned_closures.reserve(gpa, closure_count, closure_end);
            for (t.pool, 0..) |entry, i| switch (entry) {
                .callable => |signature| try b.interned_callables.note(
                    gpa,
                    callableKey(t.callableParams(signature), signature.result, signature.contracts, signature.invocation),
                    @intCast(i),
                ),
                .closure => |closure| {
                    try b.interned_closures.note(gpa, closureTypeHash(closure.closure, t.closureArgs(closure), t.closureImplArgs(closure), closure.self_ty), @intCast(i));
                },
                else => {},
            };
            try b.growOffsets();
            try b.templates.appendSlice(gpa, t.templates);
            try b.template_of.appendSlice(gpa, t.template_of);
            try b.instances.appendSlice(gpa, t.instances);
            try b.instance_args.appendSlice(gpa, t.instance_args);
            try b.instance_of.appendSlice(gpa, t.instance_of);
            try b.standins.appendSlice(gpa, t.standins);
            try b.standin_args.appendSlice(gpa, t.standin_args);
            try b.standin_of.appendSlice(gpa, t.standin_of);
            try b.interpolations.appendSlice(gpa, t.interpolations);
            try b.interpolation_pieces.appendSlice(gpa, t.interpolation_pieces);
            try b.interpolation_formats.appendSlice(gpa, t.interpolation_formats);
            try b.interpolation_borrows.appendSlice(gpa, t.interpolation_borrows);
            try b.interpolation_of.appendSlice(gpa, t.interpolation_of);
            // The chains are the builder's own bookkeeping and are not carried
            // in a finished pool, so they are rebuilt from what was copied in.
            // Without them a key already minted is minted a second time, and
            // one settled reference becomes two types that never agree.
            try b.interned_interpolations.reserve(gpa, @intCast(t.interpolations.len), t.interpolations.len);
            try b.minted.reserve(gpa, @intCast(t.instances.len), t.instances.len);
            try b.awaiting.reserve(gpa, @intCast(t.standins.len), t.standins.len);
            for (t.interpolations, 0..) |record, at| {
                const held = t.interpolation_pieces[record.first_piece..][0..record.piece_count];
                const formats = t.interpolation_formats[record.first_format..][0..record.format_count];
                const borrows = t.interpolation_borrows[record.first_format..][0..record.format_count];
                try b.interned_interpolations.note(gpa, interpolationKey(held, formats, borrows), @intCast(at));
            }
            for (t.instances, 0..) |i, at| {
                try b.noteMinted(@intCast(at), i.decl.index(), t.instance_args[i.first_arg..][0..i.arg_count]);
            }
            for (t.standins, 0..) |s, at| {
                const args = t.standin_args[s.first_arg..][0..s.arg_count];
                try b.awaiting.note(gpa, standinKey(s.trait, args, s.held, s.member.index()), @intCast(at));
            }
            return b;
        }
    };
};

// Makes every test build compile the tests `Typing` and `Typing.Builder`
// hold, including a build filtered to one of them, which would otherwise never
// look inside them.
comptime {
    _ = Typing;
    _ = Typing.Builder;
    _ = ContextualConstraints;
}

/// One pair still to be matched, either fresh from the caller's lists or
/// pushed by unifying a constructed type's arguments.
const UnifyPair = struct { x: TypeId, y: TypeId };

/// Where a parameter's binding is recorded during one call to `unifyWitness`.
///
/// Keyed by the parameter's own `TypeId` rather than by `(owner, index)`: a
/// parameter is already interned on that pair, so its handle already carries
/// the identity that matters and a second key would only restate it.
const Substitution = std.AutoHashMapUnmanaged(TypeId, TypeId);

/// Follows `t` through `subst` to the type nothing further binds it to.
///
/// A parameter is bound at most once -- `unifyWitness` never rewrites an entry once
/// made -- so this walks a chain rather than a cycle, and the chain is no
/// longer than the bindings `unifyWitness` has made so far.
fn resolveBound(subst: *const Substitution, t: TypeId) TypeId {
    var cur = t;
    while (subst.get(cur)) |next| cur = next;
    return cur;
}

/// Whether `p` -- a parameter, unbound at the point this is asked -- appears
/// anywhere inside `t` once every binding `unifyWitness` has made so far is followed.
///
/// The one recursive walk in the whole function, and it is what stops a
/// binding from ever closing a cycle: every Linea type is finite, so a
/// substitution that would make `p` equal to a type containing `p` has no
/// solution, and this is what answers that instead of `unifyWitness` looping while
/// trying to compare the two sides forever.
///
fn occursIn(typing: *const Typing.Builder, subst: *const Substitution, p: TypeId, t: TypeId) bool {
    const r = resolveBound(subst, t);
    if (r == p) return true;
    switch (typing.get(r)) {
        // The one constructed type an instantiation never wraps -- an array's
        // element is reached directly, the same way `substitute` reaches it.
        .array => |a| return occursIn(typing, subst, p, a.element),
        .borrow => |b| return occursIn(typing, subst, p, b.referent),
        .callable => |signature| {
            for (typing.callableParams(signature)) |param| {
                if (occursIn(typing, subst, p, param.ty)) return true;
            }
            return occursIn(typing, subst, p, signature.result);
        },
        else => {
            const inst = typing.instanceOf(r) orelse return false;
            for (typing.argsOf(inst)) |arg| {
                if (occursIn(typing, subst, p, arg)) return true;
            }
            return false;
        },
    }
}

pub const Groundness = struct {
    values: std.AutoHashMapUnmanaged(TypeId, bool) = .empty,

    pub fn deinit(self: *Groundness, gpa: std.mem.Allocator) void {
        self.values.deinit(gpa);
    }

    pub fn check(self: *Groundness, gpa: std.mem.Allocator, typing: anytype, ty: TypeId) std.mem.Allocator.Error!bool {
        return ground(typing, ty, .{ .memo = self, .gpa = gpa });
    }
};

const GroundMemo = struct { memo: *Groundness, gpa: std.mem.Allocator };

/// Whether a type is ground, read off any pool and remembered nowhere, which
/// is what a retained pool allows. The checker asks `Builder.allGround`
/// instead, which keeps its answers.
fn isGround(typing: anytype, t: TypeId) bool {
    return ground(typing, t, null) catch unreachable;
}

fn ground(typing: anytype, t: TypeId, memo: ?GroundMemo) std.mem.Allocator.Error!bool {
    if (memo) |state| if (state.memo.values.get(t)) |known| return known;
    const result = value: {
        if (typing.standinOf(t) != null) break :value false;
        switch (typing.get(t)) {
            .parameter => break :value false,
            .array => |a| break :value try ground(typing, a.element, memo),
            .borrow => |b| break :value try ground(typing, b.referent, memo),
            .callable => |signature| {
                for (typing.callableParams(signature)) |param| {
                    if (!try ground(typing, param.ty, memo)) break :value false;
                }
                break :value try ground(typing, signature.result, memo);
            },
            else => {},
        }
        if (typing.instanceOf(t)) |instance| {
            for (typing.argsOf(instance)) |arg| if (!try ground(typing, arg, memo)) break :value false;
        }
        break :value true;
    };
    if (memo) |state| try state.memo.values.put(state.gpa, t, result);
    return result;
}

/// A substitution making two implementation heads and their trait arguments
/// coincide, returned as the resolved types of `a`. Returns null when no such
/// substitution exists. The caller owns the returned slice.
///
/// Parameters are keyed by their interned identity, including their declaring
/// owner. Both lists share one substitution, so a head's bindings constrain its
/// trait arguments. An occurs check prevents recursive types. Associated-type
/// standins remain opaque: overlap cannot be ruled out from an unsettled type.
///
/// The worklist follows the two type expressions, and each parameter binds at
/// most once. Occurs checks cost their combined size per parameter. Resolving
/// the witness interns only constructed types whose arguments changed.
pub fn unifyWitness(
    gpa: std.mem.Allocator,
    pool: *Typing.Builder,
    a: []const TypeId,
    b: []const TypeId,
) std.mem.Allocator.Error!?[]TypeId {
    var subst: Substitution = .empty;
    defer subst.deinit(gpa);
    if (a.len != b.len) return null;

    var worklist: std.ArrayList(UnifyPair) = .empty;
    defer worklist.deinit(gpa);

    for (a, b) |x, y| try worklist.append(gpa, .{ .x = x, .y = y });

    while (worklist.pop()) |pair| {
        const x = resolveBound(&subst, pair.x);
        const y = resolveBound(&subst, pair.y);
        if (x == y) continue;

        // A settled reference is opaque: nothing at the declaration knows
        // what an implementation will settle it to, so nothing here can prove
        // it differs from the other side, whatever the other side is --
        // another settled reference, a parameter, or a ground type. Coherence
        // refuses what it cannot prove distinct, so the pair is treated as
        // satisfied without binding either side: binding one would claim a
        // fact about what the reference resolves to that nothing here
        // establishes, and the two declarations' own parameters stay exactly
        // as free as they were.
        if (pool.standinOf(x) != null or pool.standinOf(y) != null) continue;

        const tx = pool.get(x);
        const ty_ = pool.get(y);

        if (tx == .parameter) {
            if (occursIn(pool, &subst, x, y)) return null;
            try subst.put(gpa, x, y);
            continue;
        }
        if (ty_ == .parameter) {
            if (occursIn(pool, &subst, y, x)) return null;
            try subst.put(gpa, y, x);
            continue;
        }

        if (tx == .borrow and ty_ == .borrow) {
            try worklist.append(gpa, .{ .x = tx.borrow.referent, .y = ty_.borrow.referent });
            continue;
        }

        if (tx == .array and ty_ == .array) {
            if (tx.array.count != ty_.array.count) return null;
            try worklist.append(gpa, .{ .x = tx.array.element, .y = ty_.array.element });
            continue;
        }

        if (tx == .callable and ty_ == .callable) {
            const x_params = pool.callableParams(tx.callable);
            const y_params = pool.callableParams(ty_.callable);
            if (tx.callable.invocation != ty_.callable.invocation or x_params.len != y_params.len or !sameContracts(tx.callable.contracts, ty_.callable.contracts)) return null;
            for (x_params, y_params) |x_param, y_param| {
                if (x_param.convention != y_param.convention or
                    x_param.stable_address != y_param.stable_address or
                    !x_param.default.eql(y_param.default)) return null;
                try worklist.append(gpa, .{ .x = x_param.ty, .y = y_param.ty });
            }
            try worklist.append(gpa, .{ .x = tx.callable.result, .y = ty_.callable.result });
            continue;
        }

        const ix = pool.instanceOf(x) orelse return null;
        const iy = pool.instanceOf(y) orelse return null;
        if (ix.decl != iy.decl) return null;

        const argsx = pool.argsOf(ix);
        const argsy = pool.argsOf(iy);
        if (argsx.len != argsy.len) return null;
        for (argsx, argsy) |ex, ey| try worklist.append(gpa, .{ .x = ex, .y = ey });
    }

    const out = try gpa.alloc(TypeId, a.len);
    errdefer gpa.free(out);
    for (a, out) |t, *slot| slot.* = try resolveDeep(gpa, pool, &subst, t);
    return out;
}

/// `t`, with every parameter `subst` binds replaced by what it resolved to --
/// recursively, so a parameter under a constructor is replaced exactly as one
/// standing alone is. A parameter nothing bound comes back as itself, which is
/// what two implementations of one shape colliding at every member reports
/// as: there is no narrower instantiation to name.
///
/// Mints through `instantiate` and `arrayOf` only where resolving an argument
/// actually changed it, so a witness that needs no rebuilding -- the common
/// case, a `t` with no parameter left unbound anywhere inside it -- costs one
/// walk down to a leaf and nothing minted.
fn resolveDeep(
    gpa: std.mem.Allocator,
    pool: *Typing.Builder,
    subst: *const Substitution,
    t: TypeId,
) std.mem.Allocator.Error!TypeId {
    const r = resolveBound(subst, t);

    switch (pool.get(r)) {
        .borrow => |b| return pool.borrowOf(try resolveDeep(gpa, pool, subst, b.referent)),
        .array => |a| {
            const elem = try resolveDeep(gpa, pool, subst, a.element);
            return if (elem == a.element) r else pool.arrayOf(elem, a.count);
        },
        .callable => |signature| {
            const params = pool.callableParams(signature);
            const mapped = try gpa.dupe(CallableParam, params);
            defer gpa.free(mapped);
            var moved = false;
            for (mapped) |*param| {
                const ty = try resolveDeep(gpa, pool, subst, param.ty);
                if (ty != param.ty) moved = true;
                param.ty = ty;
            }
            const result = try resolveDeep(gpa, pool, subst, signature.result);
            if (!moved and result == signature.result) return r;
            return pool.internCallable(mapped, result, signature.contracts, signature.invocation);
        },
        else => {},
    }

    const inst = pool.instanceOf(r) orelse return r;
    // Recursive resolution interns types, which can move the pool's argument
    // list. Keep this instantiation's arguments in the caller's storage.
    const mapped = try gpa.dupe(TypeId, pool.argsOf(inst));
    defer gpa.free(mapped);

    var moved = false;
    for (mapped) |*slot| {
        const arg = slot.*;
        slot.* = try resolveDeep(gpa, pool, subst, arg);
        if (slot.* != arg) moved = true;
    }
    if (!moved) return r;

    const template = pool.typeOfDecl(inst.decl) orelse return r;
    return pool.instantiate(template, inst.decl, mapped);
}

test "unify: a parameter takes a settled type" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    const t1 = try b.addParameter("T", 1, 0, .unrestricted, &.{});
    const witness = (try unifyWitness(gpa, &b, &.{t1}, &.{.u8})).?;
    defer gpa.free(witness);
    try testing.expectEqualSlices(TypeId, &.{.u8}, witness);
}

test "unify: one parameter cannot be two types" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    // Pair[T, T] against Pair[Bool, UInt8]: the second field demands
    // `T = Bool` from the left, `T = UInt8` from the right, and one
    // parameter cannot settle to both.
    const pair_decl: DeclId = @enumFromInt(1);
    const field = try b.addParameter("F", pair_decl.index(), 0, .unrestricted, &.{});
    const template = try b.addStruct("Pair", .copyable, &.{
        .{ .name = "a", .ty = field },
        .{ .name = "b", .ty = field },
    });

    const impl_decl: DeclId = @enumFromInt(2);
    const t = try b.addParameter("T", impl_decl.index(), 0, .unrestricted, &.{});
    const pair_tt = try b.instantiate(template, pair_decl, &.{ t, t });
    const pair_bool_u8 = try b.instantiate(template, pair_decl, &.{ .bool_, .u8 });

    try testing.expect(try unifyWitness(gpa, &b, &.{pair_tt}, &.{pair_bool_u8}) == null);
}

test "unify: two declarations' parameters are independent" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    // Holder[T], Give[T] against Holder[T], Give[Bool]: both sides spell the
    // impl's own parameter `T`, the same way a programmer would write
    // `impl[T] Give[T] for Holder[T]` twice -- but the two `T`s are owned by
    // two different declarations, so they are two variables and are never
    // identified with each other by sharing a spelling. Both settle to Bool
    // independently.
    const holder_decl: DeclId = @enumFromInt(1);
    const field = try b.addParameter("F", holder_decl.index(), 0, .unrestricted, &.{});
    const template = try b.addStruct("Holder", .copyable, &.{.{ .name = "value", .ty = field }});

    try b.noteTemplate(holder_decl, 0, template);

    const impl_a: u32 = 2;
    const impl_b: u32 = 3;
    const t1 = try b.addParameter("T", impl_a, 0, .unrestricted, &.{});
    const t2 = try b.addParameter("T", impl_b, 0, .unrestricted, &.{});
    // One spelling, two owners: the pool already treats them as different
    // handles before `unifyWitness` is asked anything.
    try testing.expect(t1 != t2);
    const holder_t1 = try b.instantiate(template, holder_decl, &.{t1});
    const holder_t2 = try b.instantiate(template, holder_decl, &.{t2});
    const holder_bool = try b.instantiate(template, holder_decl, &.{.bool_});

    const witness = (try unifyWitness(
        gpa,
        &b,
        &.{ holder_t1, t1 },
        &.{ holder_t2, .bool_ },
    )).?;
    defer gpa.free(witness);
    try testing.expectEqualSlices(TypeId, &.{ holder_bool, .bool_ }, witness);
}

test "unify: the head can settle what the arguments then contradict" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    // Holder[T1], Give[T1] against Holder[UInt8], Give[Bool]: the head binds
    // `T1 := UInt8`, and the argument then demands `T1 = Bool`, which
    // conflicts -- unifying the arguments alone, without the head's binding
    // in scope, would miss this.
    const holder_decl: DeclId = @enumFromInt(1);
    const field = try b.addParameter("F", holder_decl.index(), 0, .unrestricted, &.{});
    const template = try b.addStruct("Holder", .copyable, &.{.{ .name = "value", .ty = field }});

    const impl_a: u32 = 2;
    const t1 = try b.addParameter("T1", impl_a, 0, .unrestricted, &.{});
    const holder_t1 = try b.instantiate(template, holder_decl, &.{t1});
    const holder_u8 = try b.instantiate(template, holder_decl, &.{.u8});

    try testing.expect(try unifyWitness(
        gpa,
        &b,
        &.{ holder_t1, t1 },
        &.{ holder_u8, .bool_ },
    ) == null);
}

test "unify: a type cannot contain itself" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    // T1 against Box[T1]: the occurs check answers false rather than
    // recursing forever comparing one side against the other, which is what
    // this test also fixes -- the case terminates.
    const box_decl: DeclId = @enumFromInt(1);
    const field = try b.addParameter("F", box_decl.index(), 0, .unrestricted, &.{});
    const template = try b.addStruct("Box", .copyable, &.{.{ .name = "value", .ty = field }});

    const impl_a: u32 = 2;
    const t1 = try b.addParameter("T1", impl_a, 0, .unrestricted, &.{});
    const box_t1 = try b.instantiate(template, box_decl, &.{t1});

    try testing.expect(try unifyWitness(gpa, &b, &.{t1}, &.{box_t1}) == null);
}

test "unify: ground types unify only by being equal" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    const witness = (try unifyWitness(gpa, &b, &.{.u8}, &.{.u8})).?;
    defer gpa.free(witness);
    try testing.expectEqualSlices(TypeId, &.{.u8}, witness);
    try testing.expect(try unifyWitness(gpa, &b, &.{.u8}, &.{.bool_}) == null);
}

test "unify: different constructors never unify" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    const holder_decl: DeclId = @enumFromInt(1);
    const holder_field = try b.addParameter("F", holder_decl.index(), 0, .unrestricted, &.{});
    const holder_template = try b.addStruct("Holder", .copyable, &.{.{ .name = "value", .ty = holder_field }});

    const box_decl: DeclId = @enumFromInt(2);
    const box_field = try b.addParameter("F", box_decl.index(), 0, .unrestricted, &.{});
    const box_template = try b.addStruct("Box", .copyable, &.{.{ .name = "value", .ty = box_field }});

    const impl_a: u32 = 3;
    const t = try b.addParameter("T", impl_a, 0, .unrestricted, &.{});
    const holder_t = try b.instantiate(holder_template, holder_decl, &.{t});
    const box_t = try b.instantiate(box_template, box_decl, &.{t});

    try testing.expect(try unifyWitness(gpa, &b, &.{holder_t}, &.{box_t}) == null);
}

test "unify: mismatched arity never unifies" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    try testing.expect(try unifyWitness(gpa, &b, &.{.u8}, &.{ .u8, .u8 }) == null);
}

test "a call recorded twice is answered by the record a scan would reach" {
    const gpa = testing.allocator;

    const typing: Typing = .{
        .binding_types = .empty,
        .decl_returns = .empty,
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
        .calls = &.{
            .{ .at = ExprId.at(1), .target = .{ .declared = DeclId.at(7) }, .signature = .u8, .args = &.{} },
            .{ .at = ExprId.at(1), .target = .{ .declared = DeclId.at(9) }, .signature = .u8, .args = &.{} },
        },
    };

    var index = try CallIndex.build(gpa, 4, &typing);
    defer index.deinit(gpa);

    try testing.expectEqual(CallTarget{ .declared = DeclId.at(7) }, index.callOf(&typing, ExprId.at(1)).?.target);
    try testing.expectEqual(@as(?NormalizedCall, null), index.callOf(&typing, ExprId.at(0)));
}

test "call index allocates records only for occupied expressions" {
    const gpa = testing.allocator;

    const typing: Typing = .{
        .binding_types = .empty,
        .decl_returns = .empty,
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
        .calls = &.{.{
            .at = ExprId.at(1),
            .target = .{ .declared = DeclId.at(7) },
            .signature = .u8,
            .args = &.{},
        }},
    };

    var index = try CallIndex.build(gpa, 4, &typing);
    defer index.deinit(gpa);

    try testing.expectEqual(@as(usize, 4), index.locator.len);
    try testing.expectEqual(@as(usize, 1), index.records.len);
    try testing.expectEqual(@as(usize, 36), @sizeOf(CallIndex.Record));
    try testing.expectEqual(CallTarget{ .declared = DeclId.at(7) }, index.callOf(&typing, ExprId.at(1)).?.target);
    try testing.expectEqual(@as(?NormalizedCall, null), index.callOf(&typing, ExprId.at(0)));
}

test "an empty call index allocates no records" {
    const typing: Typing = .{
        .binding_types = .empty,
        .decl_returns = .empty,
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
    };

    var index = try CallIndex.build(testing.allocator, 4, &typing);
    defer index.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 4), index.locator.len);
    try testing.expectEqual(@as(usize, 0), index.records.len);
    try testing.expectEqual(@as(?NormalizedCall, null), index.callOf(&typing, ExprId.at(0)));
    try testing.expectEqual(@as(usize, 0), index.recoveredArgsOf(&typing, ExprId.at(0)).len);
    try testing.expectEqual(@as(?FunctionValue, null), index.functionValueOf(&typing, ExprId.at(4)));
}

test "call index accessors recover forged typing rows" {
    const typing: Typing = .{
        .binding_types = .empty,
        .decl_returns = .empty,
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
        .calls = &.{
            .{ .at = ExprId.at(1), .target = .{ .declared = DeclId.at(7) }, .signature = .u8, .args = &.{} },
            .{ .at = ExprId.at(1), .target = .{ .declared = DeclId.at(99) }, .signature = .u8, .args = &.{} },
        },
        .recovered_call_args = &.{
            .{ .call = ExprId.at(1), .argument = ExprId.at(2), .parameter = null, .convention = .read },
            .{ .call = ExprId.at(1), .argument = ExprId.at(3), .parameter = null, .convention = .sink },
        },
        .recovered_calls = &.{.{ .at = ExprId.at(2), .target = .{ .declared = DeclId.at(9) } }},
        .postfix = &.{.{ .call = 3, .args = &.{} }},
        .projected = &.{.{ .at = 4, .expansion = 0 }},
        .expansions = &.{.{ .member = DeclId.at(10), .path = .none, .receiver = 0, .index = Expansion.no_binding }},
        .traversals = &.{.{ .at = 5, .decl = DeclId.at(11) }},
        .range_places = &.{.{ .at = 6, .first = 13 }},
        .function_values = &.{.{ .at = ExprId.at(7), .target = .{ .declared = DeclId.at(15) }, .signature = .u8 }},
    };

    var index = try CallIndex.build(testing.allocator, 8, &typing);
    defer index.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 7), index.records.len);
    try testing.expectEqual(DeclId.at(7), index.callOf(&typing, ExprId.at(1)).?.target.declared);
    const recovered = index.recoveredArgsOf(&typing, ExprId.at(1));
    try testing.expectEqual(@as(usize, 2), recovered.len);
    try testing.expectEqual(ExprId.at(2), recovered[0].argument);
    try testing.expectEqual(ExprId.at(3), recovered[1].argument);
    try testing.expectEqual(DeclId.at(9), index.recoveredCallOf(&typing, ExprId.at(2)).?.target.declared);
    try testing.expectEqual(@as(u32, 3), index.postfixOf(&typing, ExprId.at(3)).?.call);
    try testing.expectEqual(DeclId.at(10), index.projectionOf(&typing, ExprId.at(4)).?.member);
    try testing.expectEqual(DeclId.at(11), index.traversalPlan(&typing, ExprId.at(5)).?.decl);
    try testing.expectEqual(@as(u32, 13), index.rangePlaceOf(&typing, ExprId.at(6)).?.first);
    try testing.expectEqual(DeclId.at(15), index.functionValueOf(&typing, ExprId.at(7)).?.target.declared);
    try testing.expectEqual(@as(?Postfix, null), index.postfixOf(&typing, ExprId.at(8)));
}

fn buildSparseCallIndex(gpa: std.mem.Allocator) !void {
    const typing: Typing = .{
        .binding_types = .empty,
        .decl_returns = .empty,
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
        .calls = &.{
            .{ .at = ExprId.at(1), .target = .{ .declared = DeclId.at(7) }, .signature = .u8, .args = &.{} },
            .{ .at = ExprId.at(1), .target = .{ .declared = DeclId.at(9) }, .signature = .u8, .args = &.{} },
            .{ .at = ExprId.at(9), .target = .{ .declared = DeclId.at(11) }, .signature = .u8, .args = &.{} },
        },
        .recovered_call_args = &.{
            .{ .call = ExprId.at(1), .argument = ExprId.at(2), .parameter = null, .convention = .read },
            .{ .call = ExprId.at(1), .argument = ExprId.at(3), .parameter = null, .convention = .sink },
        },
    };

    var index = try CallIndex.build(gpa, 4, &typing);
    defer index.deinit(gpa);

    try testing.expectEqual(@as(usize, 1), index.records.len);
    try testing.expectEqual(@as(usize, 2), index.recoveredArgsOf(&typing, ExprId.at(1)).len);
    try testing.expectEqual(DeclId.at(7), index.callOf(&typing, ExprId.at(1)).?.target.declared);
    try testing.expectEqual(@as(?NormalizedCall, null), index.callOf(&typing, ExprId.at(9)));
}

test "call index construction handles every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, buildSparseCallIndex, .{});
}

fn buildGrowingCallIndex(gpa: std.mem.Allocator) !void {
    var calls: [20]NormalizedCall = undefined;
    for (&calls, 0..) |*call, i| call.* = .{
        .at = ExprId.at(@intCast(i)),
        .target = .{ .declared = DeclId.at(@intCast(i)) },
        .signature = .u8,
        .args = &.{},
    };
    const typing: Typing = .{
        .binding_types = .empty,
        .decl_returns = .empty,
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
        .calls = &calls,
    };

    var index = try CallIndex.build(gpa, @intCast(calls.len), &typing);
    defer index.deinit(gpa);

    try testing.expectEqual(calls.len, index.records.len);
    try testing.expectEqual(DeclId.at(0), index.callOf(&typing, ExprId.at(0)).?.target.declared);
    try testing.expectEqual(DeclId.at(@intCast(calls.len - 1)), index.callOf(&typing, ExprId.at(@intCast(calls.len - 1))).?.target.declared);
}

test "call index record growth handles every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, buildGrowingCallIndex, .{});
}

test "builtin handles name themselves" {
    try testing.expectEqual(TypeId.i64, TypeId.literal_default);
    try testing.expect(TypeId.u8 != TypeId.i8);
    try testing.expectEqualStrings("UInt8", TypeId.u8.nameOf());
    try testing.expectEqualStrings("Int64", TypeId.i64.nameOf());
}

test "every primitive is spelled and no other handle is one" {
    for (TypeId.primitives) |t| {
        try testing.expect(t.nameOf().len > 0);
        try testing.expect(t != .poison and t != .unit);
    }
    try testing.expectEqual(@as(usize, 11), TypeId.primitives.len);
}

test "a builtin describes itself" {
    var b = try Typing.Builder.init(testing.allocator);
    defer b.deinit();
    var t = try b.finish(.empty);
    defer t.deinit(testing.allocator);

    const unsigned = t.get(.u8).integer;
    try testing.expect(!unsigned.signed);
    try testing.expectEqual(@as(u8, 8), unsigned.bits);

    const signed = t.get(.i64).integer;
    try testing.expect(signed.signed);
    try testing.expectEqual(@as(u8, 64), signed.bits);
}

test "semantic fields and variants are stored by column" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    const field_name = "value";
    const field_type = TypeId.u8;
    const field_at = b.fields.len;
    _ = try b.addStruct("Box", .copyable, &.{.{ .name = field_name, .ty = field_type }});

    const first_field: u32 = @intCast(b.fields.len);
    _ = try b.addFields(&.{.{ .name = "payload", .ty = .u16 }});
    const field_count: u32 = 1;
    const variant_name = "Some";
    const variant_at = b.variants.len;
    _ = try b.addEnum("Maybe", .copyable, &.{.{
        .name = variant_name,
        .first_field = first_field,
        .field_count = field_count,
    }});

    var typing = try b.finish(.empty);
    defer typing.deinit(gpa);

    try testing.expectEqual(field_name, typing.fields.items(.name)[field_at]);
    try testing.expectEqual(field_type, typing.fields.items(.ty)[field_at]);
    try testing.expectEqual(variant_name, typing.variants.items(.name)[variant_at]);
    try testing.expectEqual(first_field, typing.variants.items(.first_field)[variant_at]);
    try testing.expectEqual(field_count, typing.variants.items(.field_count)[variant_at]);
}

test "finished semantic columns expose const elements" {
    const Fields = @FieldType(Typing, "fields");
    const Variants = @FieldType(Typing, "variants");
    comptime {
        if (@TypeOf(Fields.empty.items(.name)) != []const []const u8 or
            @TypeOf(Fields.empty.items(.ty)) != []const TypeId or
            @TypeOf(Variants.empty.items(.name)) != []const []const u8 or
            @TypeOf(Variants.empty.items(.first_field)) != []const u32 or
            @TypeOf(Variants.empty.items(.field_count)) != []const u32)
        {
            @compileError("finished semantic columns must expose const elements");
        }
    }
}

test "interning a builtin yields its reserved handle" {
    var b = try Typing.Builder.init(testing.allocator);
    defer b.deinit();

    const a = try b.intern(.{ .integer = .{ .signed = false, .bits = 8 } });
    const c = try b.intern(.{ .integer = .{ .signed = false, .bits = 8 } });
    try testing.expectEqual(a, c);
    try testing.expectEqual(TypeId.u8, a);
}

test "range bounds are exact at the edges" {
    var b = try Typing.Builder.init(testing.allocator);
    defer b.deinit();
    var t = try b.finish(.empty);
    defer t.deinit(testing.allocator);

    try testing.expect(t.holds(.u8, 0) and t.holds(.u8, 255));
    try testing.expect(!t.holds(.u8, -1) and !t.holds(.u8, 256));

    try testing.expect(t.holds(.i8, -128) and t.holds(.i8, 127));
    try testing.expect(!t.holds(.i8, -129) and !t.holds(.i8, 128));

    try testing.expect(t.holds(.i64, std.math.minInt(i64)));
    try testing.expect(t.holds(.i64, std.math.maxInt(i64)));
    try testing.expect(!t.holds(.i64, @as(i128, std.math.maxInt(i64)) + 1));

    try testing.expect(t.holds(.u64, std.math.maxInt(u64)));
    try testing.expect(!t.holds(.u64, -1));
}

test "poison holds anything, so it never reports a second time" {
    var b = try Typing.Builder.init(testing.allocator);
    defer b.deinit();
    var t = try b.finish(.empty);
    defer t.deinit(testing.allocator);

    try testing.expect(t.holds(.poison, 0));
    try testing.expect(t.holds(.poison, std.math.maxInt(i64)));
    try testing.expect(t.holds(.poison, -1));
}

test "a declared type gets a handle beyond the builtins" {
    var b = try Typing.Builder.init(testing.allocator);
    defer b.deinit();

    const shape = try b.addEnum("Shape", .copyable, &.{ .{ .name = "Circle" }, .{ .name = "Square" } });
    // Beyond every reserved handle, so a switch over builtins still works and
    // only its `else` sees this.
    try testing.expect(@intFromEnum(shape) >= TypeId.builtins.len);
    try testing.expect(shape != TypeId.u8);
}

test "a builtin keeps the handle it always had" {
    // Every existing switch over TypeId depends on this staying true.
    try testing.expect(TypeId.u8.bounds() != null);
    try testing.expectEqualStrings("UInt8", TypeId.u8.nameOf());
}

test "stamped layout representation" {
    const empty: StampedLayout = .{};
    try testing.expectEqual(@as(u32, 0), empty.generation);
    try testing.expectEqual(@as(usize, 16), @sizeOf(StampedLayout));
    try testing.expect(@sizeOf(StampedLayout) < @sizeOf(?Layout) + @sizeOf(u32));
}

test "empty and short stamped layout caches are misses" {
    var typing: Typing = .{
        .binding_types = .empty,
        .decl_returns = .empty,
        .pool = &TypeId.builtins,
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
    };
    try testing.expectEqual(@as(u32, 1), typing.layoutOf(.u8).size);

    var short = [_]StampedLayout{.{}};
    typing.laid_out = &short;
    try testing.expectEqual(@as(u32, 8), typing.layoutOf(.f64).size);
    try testing.expectEqual(@as(u32, 0), short[0].generation);
}

test "layout is a tag and the widest payload" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = try Typing.Builder.init(arena.allocator());
    const shape = try b.addEnum("Shape", .copyable, &.{
        .{ .name = "Circle" },
        .{ .name = "Point" },
    });
    b.setVariantFields(shape, 0, try b.addFields(&.{.{ .name = "r", .ty = .u8 }}), 1);
    try b.setExprCount(0);
    var typing = try b.finish(.empty);

    const l = typing.layoutOf(shape);
    try testing.expectEqual(@as(u32, 8), typing.variantFieldOffset(shape, 0, 0));
    try testing.expect(l.size >= 9);
    try testing.expectEqual(@as(u32, 1), typing.variantFieldCount(shape, 0));
    try testing.expectEqual(@as(u32, 0), typing.variantFieldCount(shape, 1));
    try testing.expectEqual(TypeId.u8, typing.variantFieldType(shape, 0, 0));
}

test "a fieldless enum stays a value in a register" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = try Typing.Builder.init(arena.allocator());
    const colour = try b.addEnum("Colour", .copyable, &.{ .{ .name = "Red" }, .{ .name = "Green" } });
    const shape = try b.addEnum("Shape", .copyable, &.{.{ .name = "Circle" }});
    b.setVariantFields(shape, 0, try b.addFields(&.{.{ .name = "r", .ty = .u64 }}), 1);
    try b.setExprCount(0);
    var typing = try b.finish(.empty);

    // What makes fieldless enums unaffected by payloads arriving: nothing
    // about them became an aggregate, so they lower exactly as before.
    try testing.expect(!typing.layoutOf(colour).isAggregate());
    try testing.expectEqual(@as(u32, 8), typing.layoutOf(colour).size);
    try testing.expect(typing.layoutOf(shape).isAggregate());

    // A builtin is a register value whatever its width.
    try testing.expect(!typing.layoutOf(.u8).isAggregate());
    try testing.expect(!typing.layoutOf(.bool_).isAggregate());
}

test "the builder answers layout with the same rule the finished typing does" {
    // The checker asks mid-build and lowering asks afterwards; two answers
    // that could differ is a class of bug worth making unreachable.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = try Typing.Builder.init(arena.allocator());
    const shape = try b.addEnum("Shape", .copyable, &.{ .{ .name = "Circle" }, .{ .name = "Square" } });
    try testing.expect(!b.layoutOf(shape).isAggregate());

    // A payload filled in after the enum was entered changes the answer, so an
    // answer already worked out has to go: the first read here is what puts
    // one in the table, and the second is what proves it was dropped.
    b.setVariantFields(shape, 1, try b.addFields(&.{.{ .name = "n", .ty = .u8 }}), 1);
    try testing.expect(b.layoutOf(shape).isAggregate());
    try testing.expectEqual(TypeId.u8, b.variantFieldType(shape, 1, 0));

    const mid_build = b.layoutOf(shape);
    try b.setExprCount(0);
    var typing = try b.finish(.empty);
    try testing.expectEqual(mid_build.size, typing.layoutOf(shape).size);
    try testing.expectEqual(mid_build.alignment, typing.layoutOf(shape).alignment);
}

test "a stamped layout already worked out is dropped when a field is written" {
    // The sibling of the payload case, for a structure's fields. Two writers
    // and one table: a writer that forgot to drop what the table holds would
    // answer for the type as it was rather than as it is.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = try Typing.Builder.init(arena.allocator());
    const inner = try b.addStruct("Inner", .copyable, &.{.{ .name = "v", .ty = .u8 }});
    const outer = try b.addStruct("Outer", .copyable, &.{.{ .name = "i", .ty = .poison }});

    // A field the checker has not resolved yet is a word wide, which is what
    // keeps the arithmetic above it in range.
    try testing.expectEqual(@as(u32, Layout.word), b.layoutOf(outer).size);
    const before = b.generation;
    try testing.expectEqual(before, b.laid_out.items[outer.index()].generation);

    b.setFieldType(outer, 0, inner);
    try testing.expect(b.generation != before);
    try testing.expectEqual(before, b.laid_out.items[outer.index()].generation);
    try testing.expectEqual(@as(u32, 1), b.layoutOf(outer).size);
    try testing.expectEqual(@as(u32, 1), b.layoutOf(outer).alignment);
    try testing.expectEqual(b.generation, b.laid_out.items[outer.index()].generation);
    try testing.expectEqual(@as(u32, 1), b.laid_out.items[outer.index()].value.size);
}

test "layout generation wrap does not revive cached answers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = try Typing.Builder.init(arena.allocator());
    const pair = try b.addStruct("Pair", .copyable, &.{
        .{ .name = "first", .ty = .u8 },
        .{ .name = "second", .ty = .u8 },
    });
    const first_field = b.pool.items[pair.index()].struct_.first_field;

    try testing.expectEqual(@as(u32, 1), b.generation);
    try testing.expectEqual(@as(u32, 2), b.layoutOf(pair).size);
    try testing.expectEqual(@as(u32, 1), b.view().fieldOffset(pair, 1));
    try testing.expectEqual(@as(u32, 1), b.laid_out.items[pair.index()].generation);
    try testing.expectEqual(@as(u32, 1), b.placed_at.items[first_field]);

    b.generation = std.math.maxInt(u32);
    b.setFieldType(pair, 0, .u64);

    try testing.expectEqual(@as(u32, 1), b.generation);
    try testing.expectEqual(@as(u32, 0), b.laid_out.items[pair.index()].generation);
    try testing.expectEqual(@as(u32, 0), b.placed_at.items[first_field]);
    try testing.expectEqual(@as(u32, 16), b.layoutOf(pair).size);
    try testing.expectEqual(@as(u32, 8), b.layoutOf(pair).alignment);
    try testing.expectEqual(@as(u32, 8), b.view().fieldOffset(pair, 1));
}

fn expectLayoutCacheMatchesPool(b: *const Typing.Builder) !void {
    try testing.expectEqual(b.pool.items.len, b.laid_out.items.len);
}

test "stamped layout cache matches every pool growth path" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();
    try expectLayoutCacheMatchesPool(&b);

    _ = try b.addEnum("E", .copyable, &.{.{ .name = "Only" }});
    try expectLayoutCacheMatchesPool(&b);
    _ = try b.addNewtype("N", .copyable, .u8, false, 0, 0);
    try expectLayoutCacheMatchesPool(&b);
    _ = try b.addStruct("S", .copyable, &.{.{ .name = "value", .ty = .u8 }});
    try expectLayoutCacheMatchesPool(&b);

    const array = try b.arrayOf(.u8, 3);
    try expectLayoutCacheMatchesPool(&b);
    const before_array_hit = b.pool.items.len;
    try testing.expectEqual(array, try b.arrayOf(.u8, 3));
    try testing.expectEqual(before_array_hit, b.pool.items.len);
    try expectLayoutCacheMatchesPool(&b);

    const integer = try b.intern(.{ .integer = .{ .signed = true, .bits = 32 } });
    try expectLayoutCacheMatchesPool(&b);
    const before_intern_hit = b.pool.items.len;
    try testing.expectEqual(integer, try b.intern(.{ .integer = .{ .signed = true, .bits = 32 } }));
    try testing.expectEqual(before_intern_hit, b.pool.items.len);
    try expectLayoutCacheMatchesPool(&b);

    const callable = try b.internCallable(&.{}, .u8, &.{}, .read);
    try expectLayoutCacheMatchesPool(&b);
    const before_callable_hit = b.pool.items.len;
    try testing.expectEqual(callable, try b.internCallable(&.{}, .u8, &.{}, .read));
    try testing.expectEqual(before_callable_hit, b.pool.items.len);
    try expectLayoutCacheMatchesPool(&b);

    const closure = try b.internClosure(ids.ClosureId.at(0), &.{.u8}, &.{}, .poison);
    try expectLayoutCacheMatchesPool(&b);
    const before_closure_hit = b.pool.items.len;
    try testing.expectEqual(closure, try b.internClosure(ids.ClosureId.at(0), &.{.u8}, &.{}, .poison));
    try testing.expectEqual(before_closure_hit, b.pool.items.len);
    try expectLayoutCacheMatchesPool(&b);

    const parameter = try b.addParameter("T", 40, 0, .unrestricted, &.{});
    try expectLayoutCacheMatchesPool(&b);
    const before_parameter_hit = b.pool.items.len;
    try testing.expectEqual(parameter, try b.addParameter("T", 40, 0, .unrestricted, &.{}));
    try testing.expectEqual(before_parameter_hit, b.pool.items.len);
    try expectLayoutCacheMatchesPool(&b);

    const standin = try b.addSettledStandin(7, &.{}, parameter, DeclId.at(41), "Item");
    try expectLayoutCacheMatchesPool(&b);
    const before_standin_hit = b.pool.items.len;
    try testing.expectEqual(standin, try b.addSettledStandin(7, &.{}, parameter, DeclId.at(41), "Item"));
    try testing.expectEqual(before_standin_hit, b.pool.items.len);
    try expectLayoutCacheMatchesPool(&b);
}

test "reopened stamped layouts start empty" {
    const gpa = testing.allocator;
    var building = try Typing.Builder.init(gpa);
    defer building.deinit();
    const pair = try building.addStruct("Pair", .copyable, &.{
        .{ .name = "first", .ty = .u8 },
        .{ .name = "second", .ty = .u8 },
    });
    try testing.expectEqual(@as(u32, 2), building.layoutOf(pair).size);
    try building.setExprCount(0);

    var finished = try building.finish(.empty);
    defer finished.deinit(gpa);
    try testing.expectEqual(finished.generation, finished.laid_out[pair.index()].generation);

    var reopened = try Typing.Builder.reopen(gpa, &finished);
    defer reopened.deinit();
    try testing.expectEqual(reopened.pool.items.len, reopened.laid_out.items.len);
    for (reopened.laid_out.items) |cached| {
        try testing.expectEqual(@as(u32, 0), cached.generation);
        try testing.expectEqual(Layout.scalar, cached.value);
    }

    try testing.expectEqual(@as(u32, 2), reopened.layoutOf(pair).size);
    try testing.expectEqual(reopened.generation, reopened.laid_out.items[pair.index()].generation);
}

fn exerciseStampedLayoutAllocations(gpa: std.mem.Allocator) !void {
    var building = try Typing.Builder.init(gpa);
    defer building.deinit();
    const inner = try building.addStruct("Inner", .copyable, &.{.{ .name = "value", .ty = .u8 }});
    const outer = try building.addStruct("Outer", .copyable, &.{.{ .name = "inner", .ty = inner }});
    try testing.expectEqual(building.pool.items.len, building.laid_out.items.len);
    try testing.expectEqual(@as(u32, 1), building.layoutOf(outer).size);
    const callable = try building.internCallable(&.{}, .u8, &.{}, .read);
    const closure = try building.internClosure(ids.ClosureId.at(0), &.{.u8}, &.{}, .poison);
    try building.setExprCount(0);

    var finished = try building.finish(.empty);
    defer finished.deinit(gpa);
    var reopened = try Typing.Builder.reopen(gpa, &finished);
    defer reopened.deinit();
    try testing.expectEqual(callable, try reopened.internCallable(&.{}, .u8, &.{}, .read));
    try testing.expectEqual(closure, try reopened.internClosure(ids.ClosureId.at(0), &.{.u8}, &.{}, .poison));
    try testing.expectEqual(reopened.pool.items.len, reopened.laid_out.items.len);
    try testing.expectEqual(@as(u32, 1), reopened.layoutOf(outer).size);
}

test "stamped layout lifecycle handles every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, exerciseStampedLayoutAllocations, .{});
}

test "a width past what a layout records is stopped rather than wrapped" {
    // Wrapping gives a slot smaller than the value it holds, and trapping
    // fails the frontend on source a diagnostic is owed for. Stopping at the
    // limit is what leaves one answer for both builds to report.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = try Typing.Builder.init(arena.allocator());

    // Eight of the level below at each step, so the tenth is past the limit
    // and the ninth is not: what the rule refuses is reached by nesting rather
    // than by any one declaration being large.
    var levels: [11]TypeId = undefined;
    var part: TypeId = .u64;
    for (&levels) |*l| {
        var run: [8]Field = undefined;
        for (&run) |*f| f.* = .{ .name = "p", .ty = part };
        l.* = try b.addStruct("L", .copyable, &run);
        part = l.*;
    }

    try testing.expect(!b.layoutOf(levels[8]).too_wide);
    try testing.expectEqual(@as(u32, 1 << 30), b.layoutOf(levels[8]).size);

    try testing.expect(b.layoutOf(levels[9]).too_wide);
    try testing.expectEqual(@as(u32, @intCast(Layout.max_size)), b.layoutOf(levels[9]).size);
    try testing.expect(b.layoutOf(levels[10]).too_wide);

    // One mistake is one diagnostic: the level the width crosses at is named,
    // and the levels holding it are not.
    try testing.expect(b.crossesSizeLimit(levels[9]));
    try testing.expect(!b.crossesSizeLimit(levels[8]));
    try testing.expect(!b.crossesSizeLimit(levels[10]));
}

test "what an enum carries is held to the limit the enum is" {
    // A variant's run is placed by the function a structure's fields are, from
    // the word the tag occupies. So a payload too wide to record makes the
    // enum too wide to record, and that falls out rather than needing a case
    // of its own.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = try Typing.Builder.init(arena.allocator());

    var part: TypeId = .u64;
    for (0..9) |_| {
        var run: [8]Field = undefined;
        for (&run) |*f| f.* = .{ .name = "p", .ty = part };
        part = try b.addStruct("L", .copyable, &run);
    }
    try testing.expectEqual(@as(u32, 1 << 30), b.layoutOf(part).size);

    const wide = try b.addEnum("Wide", .copyable, &.{ .{ .name = "Four" }, .{ .name = "Nothing" } });
    b.setVariantFields(wide, 0, try b.addFields(&.{
        .{ .name = "", .ty = part },
        .{ .name = "", .ty = part },
        .{ .name = "", .ty = part },
        .{ .name = "", .ty = part },
    }), 4);

    try testing.expect(b.layoutOf(wide).too_wide);
    try testing.expect(b.crossesSizeLimit(wide));
}

test "a declared type has no range, and is named from the pool" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var b = try Typing.Builder.init(gpa);
    const shape = try b.addEnum("Shape", .copyable, &.{ .{ .name = "Circle" }, .{ .name = "Point" } });
    try b.setExprCount(0);
    var typing = try b.finish(.empty);

    // Not an integer, so nothing about ranges applies to it.
    try testing.expect(shape.bounds() == null);
    try testing.expect(!typing.holds(shape, 0));

    // The name lives in the pool, because a handle alone cannot spell it.
    try testing.expectEqualStrings("Shape", typing.nameOf(shape));
    try testing.expectEqual(@as(u32, 2), typing.variantCount(shape));
    try testing.expectEqualStrings("Point", typing.variantName(shape, 1));

    // A builtin is still spelled the same way through the pool.
    try testing.expectEqualStrings("UInt8", typing.nameOf(.u8));
}

test "a field's offset satisfies its own alignment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var b = try Typing.Builder.init(arena.allocator());
    const mixed = try b.addStruct("Mixed", .copyable, &.{
        .{ .name = "a", .ty = .u8 },
        .{ .name = "b", .ty = .u64 },
    });
    try b.setExprCount(0);
    var t = try b.finish(.empty);

    try testing.expectEqual(@as(u32, 0), t.fieldOffset(mixed, 0));
    try testing.expectEqual(@as(u32, 8), t.fieldOffset(mixed, 1));
    try testing.expectEqual(@as(u32, 16), t.layoutOf(mixed).size);
    try testing.expectEqual(@as(u32, 8), t.layoutOf(mixed).alignment);
}

test "a structure inherits the alignment of the structures it holds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The failure this exists for: computing alignment from a type's own
    // fields but not from the alignment of the structures among them places
    // every later field one byte early.
    var b = try Typing.Builder.init(arena.allocator());
    const a = try b.addStruct("A", .copyable, &.{.{ .name = "x", .ty = .u8 }});
    const inner = try b.addStruct("B", .copyable, &.{
        .{ .name = "a", .ty = a },
        .{ .name = "y", .ty = .u64 },
    });
    const c = try b.addStruct("C", .copyable, &.{
        .{ .name = "flag", .ty = .u8 },
        .{ .name = "b", .ty = inner },
    });
    try b.setExprCount(0);
    var t = try b.finish(.empty);

    try testing.expectEqual(@as(u32, 1), t.layoutOf(a).size);
    try testing.expectEqual(@as(u32, 8), t.layoutOf(inner).alignment);
    try testing.expectEqual(@as(u32, 16), t.layoutOf(inner).size);
    try testing.expectEqual(@as(u32, 8), t.fieldOffset(c, 1));
    try testing.expectEqual(@as(u32, 24), t.layoutOf(c).size);
}

test "the layout invariants hold for every type in the pool" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Asserted over the pool rather than over an example, so a type entered by
    // any other means is held to them too.
    var b = try Typing.Builder.init(arena.allocator());
    const p = try b.addStruct("Mixed", .copyable, &.{
        .{ .name = "a", .ty = .u8 },
        .{ .name = "b", .ty = .u64 },
        .{ .name = "c", .ty = .u8 },
    });
    _ = try b.addStruct("Holder", .copyable, &.{.{ .name = "m", .ty = p }});
    const e = try b.addEnum("E", .copyable, &.{ .{ .name = "A" }, .{ .name = "B" } });
    b.setVariantFields(e, 0, try b.addFields(&.{.{ .name = "n", .ty = .u8 }}), 1);
    try b.setExprCount(0);
    var t = try b.finish(.empty);

    for (0..t.pool.len) |i| {
        const ty: TypeId = @enumFromInt(@as(u32, @intCast(i)));
        const l = t.layoutOf(ty);

        try testing.expect(l.alignment > 0);
        try testing.expectEqual(@as(u32, 0), l.size % l.alignment);

        var end: u32 = 0;
        for (0..t.fieldCount(ty)) |f| {
            const at = t.fieldOffset(ty, @intCast(f));
            const fl = t.layoutOf(t.fieldType(ty, @intCast(f)));
            try testing.expectEqual(@as(u32, 0), at % fl.alignment);
            // No overlap, and declaration order preserved.
            try testing.expect(at >= end);
            end = at + fl.size;
        }
        try testing.expect(end <= l.size);
    }
}

test "a value with parts lives in memory however small it is" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Not "wider than a word": a two-byte structure fits a register and still
    // has to live in memory, because a field is reached through an address and
    // a register has none.
    var b = try Typing.Builder.init(arena.allocator());
    const point = try b.addStruct("Point", .copyable, &.{
        .{ .name = "x", .ty = .u8 },
        .{ .name = "y", .ty = .u8 },
    });
    const colour = try b.addEnum("Colour", .copyable, &.{ .{ .name = "Red" }, .{ .name = "Green" } });
    try b.setExprCount(0);
    var t = try b.finish(.empty);

    try testing.expectEqual(@as(u32, 2), t.layoutOf(point).size);
    try testing.expect(t.layoutOf(point).isAggregate());

    // A fieldless enum is still a tag in a register, which is what kept every
    // program that uses one lowering exactly as it did.
    try testing.expect(!t.layoutOf(colour).isAggregate());
    try testing.expect(!t.layoutOf(.u8).isAggregate());
}

test "a type that holds itself is a cycle" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var b = try Typing.Builder.init(gpa);
    const list = try b.addEnum("List", .copyable, &.{ .{ .name = "Cons" }, .{ .name = "Nil" } });
    b.setVariantFields(list, 0, try b.addFields(&.{.{ .name = "head", .ty = list }}), 1);

    const c = (try b.firstCycle(gpa)).?;
    try testing.expectEqual(@as(usize, 1), c.path.len);
    try testing.expectEqual(list, c.path[0]);
}

test "a cycle through other types names every type on it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var b = try Typing.Builder.init(gpa);
    const a = try b.addStruct("A", .copyable, &.{.{ .name = "b", .ty = .poison }});
    const bb = try b.addStruct("B", .copyable, &.{.{ .name = "c", .ty = .poison }});
    const cc = try b.addStruct("C", .copyable, &.{.{ .name = "a", .ty = .poison }});
    b.setFieldType(a, 0, bb);
    b.setFieldType(bb, 0, cc);
    b.setFieldType(cc, 0, a);

    const cycle = (try b.firstCycle(gpa)).?;
    try testing.expectEqual(@as(usize, 3), cycle.path.len);
    // A reader has to know which edge to break, so every type on the cycle is
    // named rather than only the one that closed it.
    for ([_]TypeId{ a, bb, cc }) |t| {
        var found = false;
        for (cycle.path) |p| {
            if (p == t) found = true;
        }
        try testing.expect(found);
    }
}

test "a type held twice but not cyclically is not a cycle" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The test that decides the implementation. Sharing is not a cycle, and a
    // walk that remembered every type it had ever seen rather than the ones on
    // the path it is currently walking would reject this.
    var b = try Typing.Builder.init(gpa);
    const p = try b.addStruct("P", .copyable, &.{.{ .name = "x", .ty = .u8 }});
    _ = try b.addStruct("Q", .copyable, &.{
        .{ .name = "a", .ty = p },
        .{ .name = "b", .ty = p },
    });

    try testing.expect(try b.firstCycle(gpa) == null);
}

test "a diamond is not a cycle either" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Reached by two different paths and still acyclic, which is the same
    // mistake one step further out.
    var b = try Typing.Builder.init(gpa);
    const leaf = try b.addStruct("Leaf", .copyable, &.{.{ .name = "x", .ty = .u8 }});
    const l = try b.addStruct("L", .copyable, &.{.{ .name = "n", .ty = leaf }});
    const r = try b.addStruct("R", .copyable, &.{.{ .name = "n", .ty = leaf }});
    _ = try b.addStruct("Top", .copyable, &.{ .{ .name = "l", .ty = l }, .{ .name = "r", .ty = r } });

    try testing.expect(try b.firstCycle(gpa) == null);
}

test "a variant's fields are placed past the tag, each at its own alignment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var b = try Typing.Builder.init(gpa);
    const shape = try b.addEnum("Shape", .copyable, &.{ .{ .name = "Rect" }, .{ .name = "Square" } });
    const first = try b.addFields(&.{
        .{ .name = "w", .ty = .u8 },
        .{ .name = "h", .ty = .u8 },
    });
    b.setVariantFields(shape, 0, first, 2);
    try b.setExprCount(0);
    var t = try b.finish(.empty);

    // The tag keeps its word, so the first field begins at eight and the
    // second beside it rather than a word further on.
    try testing.expectEqual(@as(u32, 8), t.variantFieldOffset(shape, 0, 0));
    try testing.expectEqual(@as(u32, 9), t.variantFieldOffset(shape, 0, 1));
    try testing.expectEqual(@as(u32, 16), t.layoutOf(shape).size);
    try testing.expect(t.layoutOf(shape).isAggregate());
}

test "an enum is as wide as its widest variant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Every variant shares one arrangement, so the size is what the widest
    // needs and the others leave unused.
    var b = try Typing.Builder.init(gpa);
    const e = try b.addEnum("E", .copyable, &.{ .{ .name = "Small" }, .{ .name = "Big" } });
    const small = try b.addFields(&.{.{ .name = "a", .ty = .u8 }});
    const big = try b.addFields(&.{ .{ .name = "a", .ty = .u64 }, .{ .name = "b", .ty = .u64 } });
    b.setVariantFields(e, 0, small, 1);
    b.setVariantFields(e, 1, big, 2);
    try b.setExprCount(0);
    var t = try b.finish(.empty);

    try testing.expectEqual(@as(u32, 24), t.layoutOf(e).size);
    try testing.expectEqual(@as(u32, 8), t.variantFieldOffset(e, 1, 0));
    try testing.expectEqual(@as(u32, 16), t.variantFieldOffset(e, 1, 1));
}

test "callable type identity includes every signature component but parameter names" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    const base = [_]CallableParam{.{
        .spelling = "value",
        .convention = .read,
        .ty = .u8,
        .default = .{ .value = .{ .integer = 2 } },
    }};
    const first = try b.internCallable(&base, .u8, &.{}, .read);
    try testing.expectEqual(first, try b.internCallable(&base, .u8, &.{}, .read));
    try testing.expectEqualStrings("fn(read UInt8 = 2) -> UInt8", b.view().nameOf(first));
    const mangled = try b.view().mangledName(gpa, first);
    defer gpa.free(mangled);
    try testing.expectEqualStrings("fn(read:UInt8:value:2)->UInt8", mangled);

    // A parameter's name is a label, not part of the type.
    var changed = base;
    changed[0].spelling = "other";
    try testing.expectEqual(first, try b.internCallable(&changed, .u8, &.{}, .read));
    changed = base;
    changed[0].convention = .sink;
    try testing.expect(first != try b.internCallable(&changed, .u8, &.{}, .read));
    changed = base;
    changed[0].ty = .u16;
    try testing.expect(first != try b.internCallable(&changed, .u8, &.{}, .read));
    changed = base;
    changed[0].default = .absent;
    try testing.expect(first != try b.internCallable(&changed, .u8, &.{}, .read));
    changed = base;
    changed[0].default = .{ .value = .{ .integer = 3 } };
    try testing.expect(first != try b.internCallable(&changed, .u8, &.{}, .read));
    try testing.expect(first != try b.internCallable(&base, .u16, &.{}, .read));
    try testing.expect(first != try b.internCallable(&.{}, .u8, &.{}, .read));
}

test "callable parameter names do not separate types, and conversion keeps positional contracts" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const declared = [_]CallableParam{.{
        .spelling = "number",
        .convention = .read,
        .ty = .u8,
        .default = .{ .value = .{ .integer = 2 } },
    }};
    const actual = try builder.internCallable(&declared, .u8, &.{}, .read);
    var contextual = declared;
    contextual[0].spelling = "item";
    const wanted = try builder.internCallable(&contextual, .u8, &.{}, .read);
    try testing.expectEqual(actual, wanted);
    try testing.expect(builder.view().callableConverts(actual, wanted));
    try testing.expect(builder.view().callableSatisfies(actual, wanted));
    const mutable = try builder.internCallable(&contextual, .u8, &.{}, .inout);
    try testing.expect(builder.view().callableSatisfies(actual, mutable));
    try testing.expect(!builder.view().callableConverts(actual, mutable));

    for (0..5) |change| {
        var different = contextual;
        switch (change) {
            0 => different[0].convention = .sink,
            1 => different[0].stable_address = true,
            2 => different[0].ty = .u16,
            3 => different[0].default = .absent,
            4 => different[0].default = .{ .value = .{ .integer = 3 } },
            else => unreachable,
        }
        const incompatible = try builder.internCallable(&different, .u8, &.{}, .read);
        try testing.expect(!builder.view().callableConverts(actual, incompatible));
        try testing.expect(!builder.view().callableSatisfies(actual, incompatible));
    }
    const result_mismatch = try builder.internCallable(&contextual, .u16, &.{}, .read);
    try testing.expect(!builder.view().callableConverts(actual, result_mismatch));
    try testing.expect(!builder.view().callableSatisfies(actual, result_mismatch));

    // A nested signature naming its parameters differently is the same type
    // too, so the outer signatures are one.
    var outer = declared;
    outer[0].ty = actual;
    outer[0].default = .absent;
    const nested_actual = try builder.internCallable(&outer, actual, &.{}, .read);
    outer[0].spelling = contextual[0].spelling;
    outer[0].ty = wanted;
    try testing.expectEqual(nested_actual, try builder.internCallable(&outer, actual, &.{}, .read));
}

test "callable interning grows safely from its own parameter storage" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    const expected = [_]CallableParam{
        .{ .spelling = "first", .convention = .read, .ty = .u8, .default = .absent },
        .{ .spelling = "second", .convention = .inout, .ty = .u16, .default = .{ .value = .{ .integer = 3 } } },
        .{ .spelling = "third", .convention = .sink, .ty = .i64, .default = .absent },
        .{ .spelling = "fourth", .convention = .read, .ty = .bool_, .default = .{ .value = .{ .truth = true } } },
    };
    try b.callable_params.ensureTotalCapacityPrecise(gpa, expected.len);
    try b.callable_params.appendSlice(gpa, &expected);
    try testing.expectEqual(expected.len, b.callable_params.capacity);

    const borrowed = b.callable_params.items;
    const frozen = try b.internCallable(borrowed, .u16, &.{}, .read);
    const signature = b.get(frozen).callable;
    const actual = b.callableParams(signature);
    try testing.expectEqual(TypeId.u16, signature.result);
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| {
        try testing.expectEqualStrings(want.spelling, got.spelling);
        try testing.expectEqual(want.convention, got.convention);
        try testing.expectEqual(want.ty, got.ty);
        try testing.expect(want.default.eql(got.default));
    }
    try testing.expectEqual(frozen, try b.internCallable(actual, .u16, &.{}, .read));
}

test "callable type operations reach parameter and result types" {
    const gpa = testing.allocator;
    var b = try Typing.Builder.init(gpa);
    defer b.deinit();

    const owner = DeclId.at(41);
    const parameter = try b.addParameter("T", owner.index(), 0, .unrestricted, &.{});
    const generic = try b.internCallable(&.{.{
        .spelling = "value",
        .convention = .read,
        .ty = parameter,
        .default = .absent,
    }}, parameter, &.{}, .read);
    const concrete = try b.internCallable(&.{.{
        .spelling = "value",
        .convention = .read,
        .ty = .u8,
        .default = .absent,
    }}, .u8, &.{}, .read);

    try testing.expectEqual(concrete, try b.substitute(generic, owner.index(), &.{.u8}));
    try testing.expect(!try b.allGround(&.{generic}));
    try testing.expect(try b.allGround(&.{concrete}));

    const witness = (try unifyWitness(gpa, &b, &.{generic}, &.{concrete})).?;
    defer gpa.free(witness);
    try testing.expectEqualSlices(TypeId, &.{concrete}, witness);
}

test "a sealed pool answers what it holds and refuses to grow only on growth" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var b = try Typing.Builder.init(gpa);
    const before = try b.intern(.{ .integer = .{ .signed = true, .bits = 32 } });

    b.seal();
    try testing.expect(b.sealed);

    // Reading grows nothing, so a sealed pool still answers it: interning a
    // type already present is a lookup wearing an interner's name.
    const again = try b.intern(.{ .integer = .{ .signed = true, .bits = 32 } });
    try testing.expectEqual(before, again);
    // The growth branch itself is one @panic whose execution no test can
    // observe and survive; what is asserted is the seam every consumer holds:
    // the flag, and that reads are unimpeded past it.
}

test "reopening a finished pool preserves materialized interpolations" {
    const gpa = testing.allocator;
    const owner = DeclId.at(41);

    var building = try Typing.Builder.init(gpa);
    defer building.deinit();
    const parameter = try building.addParameter("T", owner.index(), 0, .copyable, &.{});
    const held = [_]Field{
        .{ .name = "before", .ty = .i64 },
        .{ .name = "value", .ty = parameter },
        .{ .name = "after", .ty = .i64 },
    };
    const written_display = try building.internInterpolation(&held, &.{.display}, &.{false});
    const written_debug = try building.internInterpolation(&held, &.{.debug_only}, &.{false});
    try testing.expect(written_display != written_debug);

    const instance: Instantiation = .{ .decl = owner, .args = &.{.u8} };
    const materialized_display = try instance.through(&building, written_display);
    const materialized_debug = try instance.through(&building, written_debug);
    try testing.expect(materialized_display != materialized_debug);

    var finished = try building.finish(.empty);
    defer finished.deinit(gpa);
    try testing.expectEqual(node.InterpolationFormat.display.bits(), finished.interpolationFormats(materialized_display)[0].bits());
    try testing.expectEqual(node.InterpolationFormat.debug_only.bits(), finished.interpolationFormats(materialized_debug)[0].bits());
    const display_name = try finished.mangledName(gpa, materialized_display);
    defer gpa.free(display_name);
    const debug_name = try finished.mangledName(gpa, materialized_debug);
    defer gpa.free(debug_name);
    try testing.expect(!std.mem.eql(u8, display_name, debug_name));

    var reopened = try Typing.Builder.reopen(gpa, &finished);
    defer reopened.deinit();
    reopened.seal();

    // These are lookups in the completed pool. A lost type or format index
    // tries to add either interpolation again, which the seal refuses.
    try testing.expectEqual(materialized_display, try instance.through(&reopened, written_display));
    try testing.expectEqual(materialized_debug, try instance.through(&reopened, written_debug));
    try testing.expectEqual(node.InterpolationFormat.display.bits(), reopened.interpolationFormats(materialized_display)[0].bits());
    try testing.expectEqual(node.InterpolationFormat.debug_only.bits(), reopened.interpolationFormats(materialized_debug)[0].bits());
}

test "affine scoped capabilities recompute cyclic owned parts from policy seeds" {
    try testing.checkAllAllocationFailures(testing.allocator, exerciseScopedCapabilities, .{});
}

fn exerciseScopedCapabilities(gpa: std.mem.Allocator) !void {
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const owner = DeclId.at(0);
    const parameter = try builder.addParameter("T", 0, 0, .unrestricted, &.{});
    const record = try builder.addStruct("Node", .copyable, &.{
        .{ .name = "next", .ty = .poison },
        .{ .name = "value", .ty = parameter },
    });
    // Owned-part cycles also occur through certified logical storage. Their
    // fixed point must not retain debt supported only by the previous result.
    builder.setFieldType(record, 0, record);
    try testing.expectEqual(Capability.linear, try builder.capabilityOf(record));
    const constraints: ContextualConstraints = .{
        .starts = &.{ 0, 1 },
        .parents = &.{.none},
        .capability_scopes = &.{owner},
        .items = &.{.{ .subject = parameter, .demand = .{ .requirement = .discardable } }},
    };
    builder.setContextualConstraints(constraints);
    try testing.expectEqual(Capability.affine, try builder.capabilityOfWithin(owner, record));
    try testing.expectEqual(Capability.linear, try builder.capabilityOf(record));

    const observation = try builder.borrowOf(record);
    try builder.prepareLookupWithin(owner, observation);
    var view = builder.view();
    try testing.expectEqual(Capability.copyable, view.capabilityOfWithin(owner, observation));
    try testing.expectEqual(Capability.affine, view.capabilityOfWithin(owner, record));
    const empty = try builder.arrayOf(record, 0);
    try builder.prepareLookupWithin(owner, empty);
    try testing.expectEqual(Capability.copyable, builder.view().capabilityOfWithin(owner, empty));

    const ticket = try builder.addStruct("Ticket", .linear, &.{});
    builder.setFieldType(record, 1, ticket);
    try testing.expectEqual(Capability.linear, try builder.capabilityOfWithin(owner, record));
    builder.setFieldType(record, 1, parameter);
    try testing.expectEqual(Capability.affine, try builder.capabilityOfWithin(owner, record));
    builder.setContextualConstraints(.{
        .starts = &.{ 0, 1 },
        .parents = &.{.none},
        .capability_scopes = &.{owner},
        .items = &.{.{ .subject = parameter, .demand = .{ .requirement = .copyable } }},
    });
    try testing.expectEqual(Capability.copyable, try builder.capabilityOfWithin(owner, record));
}

test "affine scoped capabilities survive freezing and reopening" {
    try testing.checkAllAllocationFailures(testing.allocator, exerciseScopedCapabilityHandoff, .{});
}

fn exerciseScopedCapabilityHandoff(gpa: std.mem.Allocator) !void {
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const owner = DeclId.at(0);
    const parameter = try builder.addParameter("T", 0, 0, .unrestricted, &.{});
    const record = try builder.addStruct("Box", .copyable, &.{.{ .name = "value", .ty = parameter }});
    const constraints: ContextualConstraints = .{
        .starts = &.{ 0, 1 },
        .parents = &.{.none},
        .capability_scopes = &.{owner},
        .items = &.{.{ .subject = parameter, .demand = .{ .requirement = .discardable } }},
    };
    builder.setContextualConstraints(constraints);
    try builder.prepareLookupWithin(owner, record);
    var typing = try builder.finish(.empty);
    defer typing.deinit(gpa);
    // The checker transfers its context table separately from the type pool.
    // This fixture borrows that table until the finished pool is released.
    typing.contextual_constraints = constraints;
    defer typing.contextual_constraints = .{};
    try testing.expectEqual(Capability.affine, typing.capabilityOfWithin(owner, record));
    var reopened = try Typing.Builder.reopen(gpa, &typing);
    defer reopened.deinit();
    const wrapper = try reopened.addStruct("Wrapper", .copyable, &.{.{ .name = "box", .ty = record }});
    try testing.expectEqual(Capability.affine, try reopened.capabilityOfWithin(owner, wrapper));
    try testing.expectEqual(Capability.affine, reopened.view().capabilityOfWithin(owner, record));
    try testing.expectEqual(Capability.linear, try reopened.capabilityOf(wrapper));
}

test "poison capability remains usable under scoped recovery" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const owner = DeclId.at(0);
    const parameter = try builder.addParameter("T", 0, 0, .unrestricted, &.{});
    const constraints: ContextualConstraints = .{
        .starts = &.{ 0, 1 },
        .parents = &.{.none},
        .capability_scopes = &.{owner},
        .items = &.{.{ .subject = parameter, .demand = .{ .requirement = .copyable } }},
    };
    builder.setContextualConstraints(constraints);
    try builder.prepareCapabilityWithin(owner, parameter);
    var typing = try builder.finish(.empty);
    defer typing.deinit(gpa);
    typing.contextual_constraints = constraints;
    defer typing.contextual_constraints = .{};
    try testing.expectEqual(Capability.copyable, typing.capabilityOfWithin(owner, .poison));
}

test "affine prepared applicability survives freezing and invalidates changed evidence" {
    try testing.checkAllAllocationFailures(testing.allocator, exercisePreparedApplicability, .{});
}

fn exercisePreparedApplicability(gpa: std.mem.Allocator) !void {
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const owner = DeclId.at(0);
    const trait = DeclId.at(1);
    const parameter = try builder.addParameter("T", 0, 0, .unrestricted, &.{});
    const record = try builder.addStruct("Box", .copyable, &.{.{ .name = "value", .ty = parameter }});
    const ticket = try builder.addStruct("Ticket", .linear, &.{});
    const implementations = [_]Implementation{.{
        .trait = 1,
        .head = .{ .whole = record },
        .ty = record,
        .decl = trait,
        .predicates = &.{.{ .subject = record, .demand = .{ .requirement = .copyable } }},
    }};
    var index = try ImplIndex.build(gpa, &implementations);
    defer index.deinit(gpa);
    builder.implementations = &implementations;
    builder.impl_index = index;
    const constraints: ContextualConstraints = .{
        .starts = &.{ 0, 1 },
        .parents = &.{.none},
        .capability_scopes = &.{owner},
        .items = &.{.{ .subject = parameter, .demand = .{ .requirement = .copyable } }},
    };
    builder.setContextualConstraints(constraints);
    try builder.prepareLookupWithin(owner, .poison);
    try testing.expectEqual(Capability.copyable, builder.view().capabilityOfWithin(owner, .poison));
    try builder.prepareLookupWithin(owner, record);
    try testing.expect(try index.any(gpa, &implementations, &builder.view(), 1, record, owner, .forward));
    try builder.prepareLookupWithin(.none, record);
    try testing.expect(!try index.any(gpa, &implementations, &builder.view(), 1, record, .none, .forward));

    builder.setFieldType(record, 0, ticket);
    try builder.prepareLookupWithin(owner, record);
    try testing.expect(!try index.any(gpa, &implementations, &builder.view(), 1, record, owner, .forward));
    builder.setFieldType(record, 0, parameter);
    try builder.prepareLookupWithin(owner, record);
    try testing.expect(try index.any(gpa, &implementations, &builder.view(), 1, record, owner, .forward));
    builder.setContextualConstraints(.{});
    try builder.prepareLookupWithin(owner, record);
    try testing.expect(!try index.any(gpa, &implementations, &builder.view(), 1, record, owner, .forward));
    builder.setContextualConstraints(constraints);
    try builder.prepareLookupWithin(owner, record);

    var typing = try builder.finish(.empty);
    defer typing.deinit(gpa);
    typing.contextual_constraints = constraints;
    defer typing.contextual_constraints = .{};
    try testing.expect(try index.any(gpa, &implementations, &typing, 1, record, owner, .forward));
    var reopened = try Typing.Builder.reopen(gpa, &typing);
    defer reopened.deinit();
    reopened.implementations = &implementations;
    reopened.impl_index = index;
    try reopened.prepareLookupWithin(owner, record);
    try testing.expect(try index.any(gpa, &implementations, &reopened.view(), 1, record, owner, .forward));
    reopened.setFieldType(record, 0, ticket);
    try reopened.prepareLookupWithin(owner, record);
    try testing.expect(!try index.any(gpa, &implementations, &reopened.view(), 1, record, owner, .forward));
    try testing.expect(try index.any(gpa, &implementations, &typing, 1, record, owner, .forward));
}

test "implementation selection replacement retains keys through growth" {
    const Case = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var selections: ImplementationSelections = .{};
            defer selections.deinit(gpa);
            const trait = DeclId.at(0);
            const arguments = [_]TypeId{.u8};
            _ = try selections.record(gpa, .none, trait, &arguments, .u16, .{
                .supplier = .{ .declared = @enumFromInt(0) },
                .receiver = .u16,
                .impl_args = &.{.u8},
            });
            _ = try selections.record(gpa, .none, trait, &arguments, .u16, .{
                .supplier = .{ .declared = @enumFromInt(1) },
                .receiver = .u16,
                .impl_args = &.{.u32},
            });
            // Additional independent keys force several map growth steps.
            for (1..40) |index| {
                _ = try selections.record(gpa, .none, DeclId.at(@intCast(index)), &arguments, .u16, null);
            }
            const selected = selections.choiceOf(trait, &arguments, .u16).?;
            try testing.expectEqual(@as(ImplementationId, @enumFromInt(1)), selected.declaredImplementation().?);
            try testing.expectEqualSlices(TypeId, &.{.u32}, selected.impl_args);
            var cloned = try selections.clone(gpa);
            defer cloned.deinit(gpa);
            _ = try selections.record(gpa, .none, trait, &arguments, .u16, null);
            try testing.expect(selections.lookup(trait, &arguments, .u16).? == null);
            try testing.expectEqualSlices(TypeId, &.{.u32}, cloned.choiceOf(trait, &arguments, .u16).?.impl_args);
        }
    };
    try Case.run(testing.allocator);
    try testing.checkAllAllocationFailures(testing.allocator, Case.run, .{});
}

test "unchanged callable payload fields preserve derived facts" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const callable = try builder.internCallable(&.{}, .u8, &.{}, .read);
    const observation = try builder.borrowOf(.u8);
    const callbacks = try builder.addEnum("Callbacks", .copyable, &.{.{ .name = "Held" }});
    builder.setVariantFields(callbacks, 0, try builder.addFields(&.{.{ .name = "value", .ty = callable }}), 1);
    _ = try builder.capabilityOf(callbacks);
    try testing.expect(!try builder.mayCarryDependencies(callbacks));
    const generation = builder.generation;
    builder.setVariantFieldType(callbacks, 0, 0, callable);
    try testing.expect(!builder.capability_facts.dirty);
    try testing.expect(!builder.dependency_facts.dirty);
    try testing.expectEqual(generation, builder.generation);

    builder.setVariantFieldType(callbacks, 0, 0, observation);
    try testing.expect(builder.generation != generation);
    try testing.expect(try builder.mayCarryDependencies(callbacks));
}

test "unchanged enum payloads preserve layout generation" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const value = try builder.addEnum("Payload", .linear, &.{.{ .name = "Held" }});
    builder.setVariantFields(value, 0, try builder.addFields(&.{.{ .name = "value", .ty = .u8 }}), 1);
    const generation = builder.generation;
    builder.setVariantFieldType(value, 0, 0, .u8);
    try testing.expectEqual(generation, builder.generation);
    builder.setVariantFieldType(value, 0, 0, .u16);
    try testing.expect(builder.generation != generation);
    try testing.expectEqual(TypeId.u16, builder.variantFieldType(value, 0, 0));
}

test "callable invocation modes participate in identity and bound satisfaction" {
    var builder = try Typing.Builder.init(testing.allocator);
    defer builder.deinit();
    const read = try builder.internCallable(&.{}, .u8, &.{}, .read);
    const inout = try builder.internCallable(&.{}, .u8, &.{}, .inout);
    const sink = try builder.internCallable(&.{}, .u8, &.{}, .sink);
    const view = builder.view();
    try testing.expect(read != inout and read != sink and inout != sink);
    try testing.expect(view.callableSatisfies(read, inout));
    try testing.expect(!view.callableSatisfies(inout, read));
    try testing.expect(!view.callableSatisfies(sink, read));
    try testing.expect(!view.callableSatisfies(sink, inout));
    try testing.expect(!view.callableSatisfies(read, sink));
    try testing.expect(view.callableSatisfies(sink, sink));
}

test "conditional closure Release distinguishes consuming and read capture slots" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const release = DeclId.at(0);
    builder.closure_release = .{ .trait = release, .member = DeclId.at(1) };
    const implementations = [_]Implementation{.{ .trait = release.index(), .head = .{ .whole = .u8 }, .ty = .u8, .decl = DeclId.at(3) }};
    var index = try ImplIndex.build(gpa, &implementations);
    defer index.deinit(gpa);
    builder.impl_index = index;
    builder.implementations = &implementations;
    const observed = try builder.borrowOf(.u8);
    const environment = try builder.addStruct("Environment", .copyable, &.{.{ .name = "value", .ty = observed }});
    const signature = try builder.internCallable(&.{}, .unit, &.{}, .read);
    var descriptors = [_]ClosureDescriptor{
        .{ .environment = environment, .enclosing = .none, .expr = .none, .body = .none, .signature = signature },
        .{ .environment = environment, .owned_fields = &.{@enumFromInt(0)}, .enclosing = .none, .expr = .none, .body = .none, .signature = signature },
        .{ .enclosing = .none, .expr = .none, .body = .none, .signature = signature },
        .{ .owned_fields = &.{@enumFromInt(0)}, .enclosing = .none, .expr = .none, .body = .none, .signature = signature },
    };
    builder.closure_descriptors = &descriptors;
    const reading = try builder.internClosure(@enumFromInt(0), &.{}, &.{}, .poison);
    const consuming = try builder.internClosure(@enumFromInt(1), &.{}, &.{}, .poison);
    descriptors[2].environment = try builder.addStruct("Nested", .copyable, &.{.{ .name = "callback", .ty = reading }});
    descriptors[2].owned_fields = &.{@enumFromInt(0)};
    const nested = try builder.internClosure(@enumFromInt(2), &.{}, &.{}, .poison);
    descriptors[3].environment = try builder.addStruct("Owned", .copyable, &.{.{ .name = "value", .ty = .u8 }});
    const owned = try builder.internClosure(@enumFromInt(3), &.{}, &.{}, .poison);
    try builder.prepareLookupWithin(.none, owned);
    const prepared = builder.view();
    try testing.expect(try index.any(gpa, &implementations, &prepared, release.index(), owned, .none, .direct));
    for ([_]TypeId{ reading, consuming, nested }, [_]bool{ true, false, true }) |closure, expected| {
        try testing.expectEqual(expected, try builder.impl_index.any(gpa, &implementations, &builder, release.index(), closure, .none, .direct));
        const choice = try builder.implementationChoice(release, &.{}, closure);
        try testing.expectEqual(expected, choice != null);
        if (choice) |selected| {
            try testing.expect(selected.supplier == .closure_release);
            try testing.expectEqual(closure, selected.receiver);
            try testing.expect(selected.declaredImplementation() == null);
        }
    }
    try testing.expect(!try builder.impl_index.any(gpa, &implementations, &builder, 2, reading, .none, .direct));
}

test "captured contracts preserve source identity in signatures and promises" {
    var builder = try Typing.Builder.init(testing.allocator);
    defer builder.deinit();
    const result = try builder.borrowOf(.u8);
    const params = [_]CallableParam{.{ .spelling = "value", .ty = result, .convention = .read, .default = .absent }};
    const first: CallableContract = .{ .kind = .carries, .source = .{ .root = .{ .capture = .{ .closure = @enumFromInt(0), .field = @enumFromInt(0) } }, .spelling = "value" } };
    var second = first;
    second.source.root.capture.closure = @enumFromInt(1);
    var parameter = first;
    parameter.source.root = .{ .parameter = 0 };
    const one = try builder.internCallable(&params, result, &.{first}, .read);
    const two = try builder.internCallable(&params, result, &.{second}, .read);
    const three = try builder.internCallable(&params, result, &.{parameter}, .read);
    try testing.expect(one != two and one != three and two != three);
    try testing.expect(contractsWithin(&.{first}, &.{first}));
    try testing.expect(!contractsWithin(&.{first}, &.{second}));
    try testing.expect(!contractsWithin(&.{first}, &.{parameter}));
}

test "generic callee contracts admit external results without hiding retention" {
    const capture: CallableContract = .{ .kind = .borrows, .source = .{ .root = .{ .capture = .{ .closure = @enumFromInt(0), .field = @enumFromInt(0) } } } };
    const environment: CallableContract = .{ .kind = .carries, .source = .{ .root = .callee } };
    const input: CallableContract = .{ .kind = .carries, .source = .{ .root = .{ .parameter = 0 } } };
    try testing.expect(callableContractsSatisfy(&.{capture}, &.{ input, environment }));
    try testing.expect(callableContractsSatisfy(&.{}, &.{environment}));
    try testing.expect(!sameContracts(&.{capture}, &.{environment}));
    try testing.expect(!callableContractsSatisfy(&.{capture}, &.{}));
    var retention = capture;
    retention.kind = .retains;
    retention.destination = .{ .root = .{ .parameter = 0 } };
    try testing.expect(!callableContractsSatisfy(&.{retention}, &.{environment}));
    try testing.expect(!callableContractsSatisfy(&.{}, &.{retention}));
    try testing.expect(callableContractsSatisfy(&.{retention}, &.{retention}));
    var self_borrow = environment;
    self_borrow.kind = .borrows;
    try testing.expect(!callableContractsSatisfy(&.{self_borrow}, &.{environment}));
}

test "array interning preserves structural handles across reopened pools" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const nominal = try builder.addStruct("Element", .copyable, &.{.{ .name = "value", .ty = .u8 }});
    const first = try builder.arrayOf(nominal, 2);
    const other_element = try builder.arrayOf(.u8, 2);
    const other_count = try builder.arrayOf(nominal, 3);
    try testing.expect(first != other_element);
    try testing.expect(first != other_count);
    try testing.expectEqual(first.index() + 1, other_element.index());
    try testing.expectEqual(other_element.index() + 1, other_count.index());
    const count = builder.pool.items.len;
    try testing.expectEqual(first, try builder.arrayOf(nominal, 2));
    try testing.expectEqual(first, try builder.intern(builder.get(first)));
    try testing.expectEqual(count, builder.pool.items.len);
    try builder.setExprCount(0);
    var finished = try builder.finish(.empty);
    defer finished.deinit(gpa);
    var reopened = try Typing.Builder.reopen(gpa, &finished);
    defer reopened.deinit();
    try testing.expectEqual(first, try reopened.arrayOf(nominal, 2));
    try testing.expectEqual(other_element, try reopened.arrayOf(.u8, 2));
    try testing.expectEqual(other_count, try reopened.arrayOf(nominal, 3));
    try testing.expectEqual(count, reopened.pool.items.len);
    const added = try reopened.arrayOf(nominal, 4);
    try testing.expectEqual(count, added.index());
    try testing.expectEqual(added, try reopened.arrayOf(nominal, 4));
    try testing.expectEqualStrings("[Element; 2]", finished.nameOf(first));
}

test "dependency coverage counts the union of array intervals" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const element = try builder.borrowOf(.u8);
    const array = try builder.arrayOf(element, 5);
    try builder.setExprCount(0);
    var pool = try builder.finish(.empty);
    defer pool.deinit(gpa);
    var coverage: DependencyCoverage = .{};
    defer coverage.deinit(gpa);
    const Paths = struct {
        pool: *const Typing,

        pub fn isRoot(_: @This(), path: []const ArrayCoverageRange) bool {
            return path.len == 0;
        }
        pub fn head(_: @This(), path: []const ArrayCoverageRange) ArrayCoverageRange {
            return path[0];
        }
        pub fn tail(_: @This(), path: []const ArrayCoverageRange) []const ArrayCoverageRange {
            return path[1..];
        }
        pub fn arrayRange(_: @This(), range: ArrayCoverageRange, _: u32) ?ArrayCoverageRange {
            return range;
        }
        pub fn childType(self: @This(), ty: TypeId, _: ArrayCoverageRange) ?TypeId {
            return switch (self.pool.get(ty)) {
                .array => |shape| shape.element,
                else => null,
            };
        }
    };
    const context: Paths = .{ .pool = &pool };
    const full = [_][]const ArrayCoverageRange{
        &.{.{ .first = 0, .last = 2 }},
        &.{.{ .first = 2, .last = 4 }},
    };
    try testing.expect(try coverage.covers([]const ArrayCoverageRange, gpa, &pool, array, &full, context));
    const overlap_with_gap = [_][]const ArrayCoverageRange{
        &.{.{ .first = 0, .last = 1 }},
        &.{.{ .first = 1, .last = 3 }},
    };
    try testing.expect(!try coverage.covers([]const ArrayCoverageRange, gpa, &pool, array, &overlap_with_gap, context));
    const adjacent = [_][]const ArrayCoverageRange{
        &.{.{ .first = 0, .last = 1 }},
        &.{.{ .first = 2, .last = 4 }},
    };
    try testing.expect(try coverage.covers([]const ArrayCoverageRange, gpa, &pool, array, &adjacent, context));
    const one_slot = [_][]const ArrayCoverageRange{&.{.{ .first = 0, .last = 0 }}};
    try testing.expect(!try coverage.covers([]const ArrayCoverageRange, gpa, &pool, array, &one_slot, context));
    const whole = [_][]const ArrayCoverageRange{&.{.{ .first = 0, .last = 4 }}};
    try testing.expect(try coverage.covers([]const ArrayCoverageRange, gpa, &pool, array, &whole, context));
}

test "shared type DAG substitution bounds allocation work per query" {
    var counted = testing.FailingAllocator.init(testing.allocator, .{});
    const gpa = counted.allocator();
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const declaration = DeclId.at(1);
    const template = try builder.addStruct("Pair", .copyable, &.{});
    try builder.noteTemplate(declaration, 0, template);
    const owner: u32 = 2;
    const parameter = try builder.addParameter("T", owner, 0, .unrestricted, &.{});
    const depth = 12;
    var shared = parameter;
    for (0..depth) |_| shared = try builder.instantiate(template, declaration, &.{ shared, shared });

    const before = counted.allocations;
    try testing.expectEqual(shared, try builder.substitute(shared, owner + 1, &.{.u8}));
    // Each distinct node needs bounded scratch; duplicated child edges do not
    // justify another traversal or another allocation subtree.
    try testing.expect(counted.allocations - before < depth * 64);
    const first = try builder.substitute(shared, owner, &.{.u8});
    const second = try builder.substitute(shared, owner, &.{.u16});
    try testing.expect(first != second);
    try testing.expectEqual(first, try builder.substitute(shared, owner, &.{.u8}));
    for ([_]TypeId{ first, second }, [_]TypeId{ .u8, .u16 }) |root, leaf| {
        var current = root;
        for (0..depth) |_| {
            const children = builder.appliedTo(current);
            try testing.expectEqual(@as(usize, 2), children.len);
            try testing.expectEqual(children[0], children[1]);
            current = children[0];
        }
        try testing.expectEqual(leaf, current);
    }

    var finished = try builder.finish(.empty);
    defer finished.deinit(gpa);
    var reopened = try Typing.Builder.reopen(gpa, &finished);
    defer reopened.deinit();
    reopened.seal();
    try testing.expectEqual(second, try reopened.substitute(shared, owner, &.{.u16}));
    try testing.expectEqual(first, try reopened.substitute(shared, owner, &.{.u8}));
}

test "deep nominal mangling allocates in proportion to its exact spelling" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const declaration = DeclId.at(1);
    const template = try builder.addStruct("Layer", .copyable, &.{});
    try builder.noteTemplate(declaration, 0, template);
    const depth = 128;
    var nested: TypeId = .u8;
    for (0..depth) |_| nested = try builder.instantiate(template, declaration, &.{nested});
    var counted = testing.FailingAllocator.init(gpa, .{});
    const symbol = try builder.view().mangledName(counted.allocator(), nested);
    defer counted.allocator().free(symbol);
    const expected = ("Layer[" ** depth) ++ "UInt8" ++ ("]" ** depth);
    try testing.expectEqualStrings(expected, symbol);
    // Geometric buffer growth needs only bounded work per emitted byte.
    try testing.expect(counted.allocated_bytes <= symbol.len * 8 + 128);
}

test "bounded type displays preserve exact instance identity and symbols" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const declaration = DeclId.at(1);
    const template = try builder.addStruct("Pair", .copyable, &.{});
    try builder.noteTemplate(declaration, 0, template);
    var shared: TypeId = .u8;
    for (0..12) |_| shared = try builder.instantiate(template, declaration, &.{ shared, shared });
    const first = try builder.instantiate(template, declaration, &.{ shared, .u8 });
    const second = try builder.instantiate(template, declaration, &.{ shared, .u16 });
    try testing.expect(first != second);
    try testing.expect(builder.nameOf(first).len <= TypeDisplay.byte_limit);
    try testing.expect(std.mem.indexOf(u8, builder.nameOf(first), TypeDisplay.ellipsis) != null);
    try testing.expectEqualStrings(builder.nameOf(first), builder.nameOf(second));
    const first_symbol = try builder.view().mangledName(gpa, first);
    defer gpa.free(first_symbol);
    const second_symbol = try builder.view().mangledName(gpa, second);
    defer gpa.free(second_symbol);
    try testing.expect(!std.mem.eql(u8, first_symbol, second_symbol));
    try testing.expect(std.mem.endsWith(u8, first_symbol, ",UInt8]"));
    try testing.expect(std.mem.endsWith(u8, second_symbol, ",UInt16]"));
    try testing.expect(std.mem.indexOf(u8, first_symbol, TypeDisplay.ellipsis) == null);
}

test "bounded type displays end at a UTF8 boundary" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    var head: [TypeDisplay.byte_limit]u8 = @splat('a');
    const available = TypeDisplay.byte_limit - TypeDisplay.ellipsis.len;
    @memcpy(head[available - 1 ..][0..3], "€");
    const rendered = try builder.spellInstance(&head, &.{});
    defer gpa.free(rendered);
    try testing.expect(rendered.len <= TypeDisplay.byte_limit);
    try testing.expect(std.unicode.utf8ValidateSlice(rendered));
    try testing.expect(std.mem.endsWith(u8, rendered, TypeDisplay.ellipsis));
}

test "bounded type displays preserve long nominal symbol heads" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    var first_head: [TypeDisplay.byte_limit + 64]u8 = @splat('a');
    var second_head = first_head;
    first_head[first_head.len - 1] = 'A';
    second_head[second_head.len - 1] = 'B';
    const first_template = try builder.addStruct(&first_head, .copyable, &.{});
    const second_template = try builder.addStruct(&second_head, .copyable, &.{});
    try builder.noteTemplate(.at(1), 0, first_template);
    try builder.noteTemplate(.at(2), 0, second_template);
    const first = try builder.instantiate(first_template, .at(1), &.{.u8});
    const second = try builder.instantiate(second_template, .at(2), &.{.u8});
    try testing.expectEqualStrings(builder.nameOf(first), builder.nameOf(second));
    const first_symbol = try builder.view().mangledName(gpa, first);
    defer gpa.free(first_symbol);
    const second_symbol = try builder.view().mangledName(gpa, second);
    defer gpa.free(second_symbol);
    try testing.expectEqualStrings(&first_head, first_symbol[0..first_head.len]);
    try testing.expectEqualStrings(&second_head, second_symbol[0..second_head.len]);
    try testing.expectEqualStrings("[UInt8]", first_symbol[first_head.len..]);
    try testing.expectEqualStrings("[UInt8]", second_symbol[second_head.len..]);
    try testing.expect(!std.mem.eql(u8, first_symbol, second_symbol));
}

test "bounded structural type displays keep callable and interpolation DAGs compact" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    var callable: TypeId = .u8;
    var interpolation: TypeId = .u8;
    for (0..12) |_| {
        callable = try builder.internCallable(&.{.{
            .spelling = "value",
            .convention = .read,
            .ty = callable,
            .default = .absent,
        }}, callable, &.{}, .read);
        try testing.expect(builder.nameOf(callable).len <= TypeDisplay.byte_limit);
        interpolation = try builder.internInterpolation(&.{
            .{ .name = "before", .ty = .i64 },
            .{ .name = "first", .ty = interpolation },
            .{ .name = "between", .ty = .i64 },
            .{ .name = "second", .ty = interpolation },
            .{ .name = "after", .ty = .i64 },
        }, &.{ .display, .display }, &.{ false, false });
        try testing.expect(builder.nameOf(interpolation).len <= TypeDisplay.byte_limit);
    }
    const borrowed = try builder.borrowOf(callable);
    const array = try builder.arrayOf(interpolation, 4);
    const projected = try builder.addSettledStandin(7, &.{}, array, .at(8), "Item");
    for ([_]TypeId{ callable, interpolation, borrowed, array, projected }) |ty| {
        try testing.expect(builder.nameOf(ty).len <= TypeDisplay.byte_limit);
        try testing.expect(std.unicode.utf8ValidateSlice(builder.nameOf(ty)));
    }
}

test "bounded structural type displays preserve exact callable and projection symbols" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const pair = try builder.addStruct("Pair", .copyable, &.{});
    try builder.noteTemplate(.at(1), 0, pair);
    var shared: TypeId = .u8;
    for (0..10) |_| shared = try builder.instantiate(pair, .at(1), &.{ shared, shared });
    const first = try builder.instantiate(pair, .at(1), &.{ shared, .u8 });
    const second = try builder.instantiate(pair, .at(1), &.{ shared, .u16 });
    const params = [_]CallableParam{.{
        .spelling = "value",
        .convention = .read,
        .ty = shared,
        .default = .absent,
    }};
    const first_callable = try builder.internCallable(&params, first, &.{}, .read);
    const second_callable = try builder.internCallable(&params, second, &.{}, .read);
    const first_projection = try builder.addSettledStandin(7, &.{.u8}, first, .at(8), "Item");
    const second_projection = try builder.addSettledStandin(7, &.{.u8}, second, .at(8), "Item");
    const changed_argument = try builder.addSettledStandin(7, &.{.u16}, first, .at(8), "Item");
    const changed_member = try builder.addSettledStandin(9, &.{.u8}, first, .at(10), "Item");
    for ([_][2]TypeId{
        .{ first_callable, second_callable },
        .{ first_projection, second_projection },
        .{ first_projection, changed_argument },
        .{ first_projection, changed_member },
    }) |types| {
        try testing.expect(types[0] != types[1]);
        try testing.expectEqualStrings(builder.nameOf(types[0]), builder.nameOf(types[1]));
        const first_symbol = try builder.view().mangledName(gpa, types[0]);
        defer gpa.free(first_symbol);
        const second_symbol = try builder.view().mangledName(gpa, types[1]);
        defer gpa.free(second_symbol);
        try testing.expect(!std.mem.eql(u8, first_symbol, second_symbol));
        try testing.expect(std.mem.indexOf(u8, first_symbol, TypeDisplay.ellipsis) == null);
        try testing.expect(std.mem.indexOf(u8, second_symbol, TypeDisplay.ellipsis) == null);
    }
}

test "leaf type substitution does not copy a wide replacement vector" {
    var counted = testing.FailingAllocator.init(testing.allocator, .{});
    const gpa = counted.allocator();
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const width = 512;
    const owner: u32 = 7;
    var parameters: [width]TypeId = undefined;
    var replacements: [width]TypeId = undefined;
    for (&parameters, &replacements, 0..) |*parameter, *replacement, index| {
        parameter.* = try builder.addParameter("T", owner, @intCast(index), .unrestricted, &.{});
        replacement.* = if (index % 2 == 0) .u8 else .u16;
    }
    const declared = try builder.addStruct("Concrete", .copyable, &.{});
    const allocated = counted.allocated_bytes;
    for (parameters, replacements) |parameter, replacement| {
        try testing.expectEqual(replacement, try builder.substitute(parameter, owner, &replacements));
        try testing.expectEqual(parameter, try builder.substitute(parameter, owner + 1, &replacements));
        try testing.expectEqual(TypeId.u8, try builder.substitute(.u8, owner, &replacements));
        try testing.expectEqual(declared, try builder.substitute(declared, owner, &replacements));
    }
    try testing.expectEqual(TypeId.poison, try builder.substitute(parameters[width - 1], owner, replacements[0..1]));
    try testing.expectEqual(allocated, counted.allocated_bytes);
}
