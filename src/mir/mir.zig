const std = @import("std");
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const FileId = @import("../support/source.zig").FileId;
const Table = @import("../support/table.zig").Table;
const types_mod = @import("../sema/types.zig");
const TypeId = types_mod.TypeId;
const Layout = types_mod.Layout;
const node = @import("../syntax/node.zig");

pub const BlockId = enum(u32) {
    _,

    pub fn at(i: u32) BlockId {
        return @enumFromInt(i);
    }

    pub fn index(self: BlockId) u32 {
        return @intFromEnum(self);
    }
};

pub const InstId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: u32) InstId {
        return @enumFromInt(i);
    }

    pub fn index(self: InstId) u32 {
        return @intFromEnum(self);
    }
};

/// Which function, within the module. A call names one of these rather than a
/// symbol, so the backend needs nothing from the frontend to emit it.
pub const FunctionId = enum(u32) {
    /// No function. What a module with no entry point names as its entry: a
    /// library has none to name, and a dump of a root that declared none has
    /// nothing to point at either.
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: u32) FunctionId {
        return @enumFromInt(i);
    }

    pub fn index(self: FunctionId) u32 {
        return @intFromEnum(self);
    }
};

/// A slot of storage. Every binding has one, and lowering allocates more of
/// its own -- a conditional needs a slot to carry a value between its arms --
/// so a binding's handle is not its slot's and the two are related by a table.
pub const LocalId = enum(u32) {
    _,

    pub fn at(i: u32) LocalId {
        return @enumFromInt(i);
    }

    pub fn index(self: LocalId) u32 {
        return @intFromEnum(self);
    }
};

/// What a trap reports. The backend passes this to the runtime, which turns it
/// into a message, so the two agree on a small integer rather than a string.
pub const TrapKind = enum(u8) {
    overflow,
    division_by_zero,
    conversion_out_of_range,
    /// Reserved. Numbering is part of the runtime interface, so a kind is
    /// added at the end and never renumbered; taking these now keeps a later
    /// addition from moving one that generated code already refers to.
    unreachable_reached,
    assertion_failed,
    panic,
    /// An index no element sits at. Appended, because the numbering is a
    /// runtime interface and a kind inserted anywhere else silently renumbers
    /// code already emitted.
    index_out_of_bounds,
    /// An offset that is not a multiple of the access's width. A different
    /// failure from an index out of bounds -- the value fits, and where it
    /// would sit is what is wrong -- so it carries its own message. Appended,
    /// for the reason above.
    misaligned_access,
    /// A NaN where an integer was asked for. Distinct from a value out of
    /// range, because a NaN is not a value the target failed to hold -- it is
    /// not a number at all, and a message about a range would describe
    /// something that never applied. Appended, because the numbering is a
    /// runtime interface.
    not_a_number,

    pub fn describe(self: TrapKind) []const u8 {
        return switch (self) {
            .overflow => "integer overflow",
            .division_by_zero => "division by zero",
            .conversion_out_of_range => "value out of range for its type",
            .unreachable_reached => "reached unreachable code",
            .assertion_failed => "assertion failed",
            .panic => "panic",
            .index_out_of_bounds => "index out of bounds",
            .misaligned_access => "misaligned access",
            .not_a_number => "not a number",
        };
    }
};

pub const Inst = struct {
    tag: Tag,
    result_role: ResultRole = .value,
    /// The type this instruction produces. Terminators produce nothing and
    /// carry `.unit`.
    ty: TypeId,
    /// Where it came from, so a trap can name a source location.
    span: Span,
    data: Data,

    pub const Tag = enum(u8) {
        // Values.
        constant,
        /// The address of a blob of bytes the module carries. `bytes` indexes
        /// the module's pool, which is keyed by the bytes themselves, so two
        /// literals spelling the same text name one blob.
        bytes_addr,
        /// The address of read-only data the module carries. `static` indexes
        /// the module's `statics`, and `ty` is that entry's type. A constant a
        /// program borrows is read from here, so nothing may write through it.
        static_addr,
        /// Exposes a managed storage address for a checked span descriptor.
        address_bits,

        // Memory.
        load,
        store,
        /// The managed address of a slot. Its result role keeps it distinct
        /// from an integer value, and its `ty` is what it points at.
        addr_of,
        /// Forms a readonly pointer value from checked managed storage.
        borrow,
        /// Projects the referent storage of a readonly pointer value.
        observe,
        /// A load through an address rather than from a named slot. The
        /// operand is the address.
        load_indirect,
        /// A store through an address. `lhs` is the address and `rhs` the
        /// value, so this reuses the binary payload rather than minting one.
        store_indirect,
        /// A load through a raw integer handle after lowering emitted the
        /// buffer operation's bounds and alignment checks.
        load_raw,
        /// A store through a raw integer handle after lowering emitted the
        /// buffer operation's bounds and alignment checks.
        store_raw,
        /// A checked heap address pointing at a concrete typed element.
        storage_addr,
        /// The address of a field within a value held in memory. `lhs` is the
        /// value's address and `rhs` a constant offset.
        ///
        /// Not an `add`. An offset within a value cannot leave it, so there is
        /// nothing to check, and routing it through the checked add would emit
        /// a test that can never fail.
        field_addr,
        /// Copies a value held in memory. `lhs` is the destination address and
        /// `rhs` the source; `ty` says how much to copy.
        ///
        /// Binding such a value is a copy rather than a move of a word. Two
        /// names sharing one buffer would make a later write through either
        /// visible through both, which no rule of the language allows.
        ///
        /// The source stays a live value afterwards: this is what an explicit
        /// `copy(e)` becomes, and nothing else. Every other transfer of an
        /// aggregate is a `move_value`.
        copy_value,
        /// Moves a value held in memory: the same blit as `copy_value`, with
        /// the same payload, after which the source holds nothing the program
        /// may read. The two are one instruction to the backend and two to a
        /// reader asking whether the source is still owned.
        move_value,

        // Arithmetic.

        add,
        sub,
        mul,
        div,
        /// What a truncating division leaves. Its sign follows the dividend,
        /// and it carries the same two failures division does: a zero divisor,
        /// and the one signed pair whose quotient has no representation.
        rem,
        neg,

        // Comparison. Yields a boolean, so nothing checks its range.
        cmp_eq,
        cmp_ne,
        cmp_lt,
        cmp_le,
        cmp_gt,
        cmp_ge,

        // Conversion between the two register classes. These exist because a
        // float and an integer are different encodings of a number, where the
        // integer conversions are one value re-tested -- so those are a
        // `check` and these are instructions.

        /// An integer becomes the nearest `Float64`. Defined for every input
        /// and may round; the operand's own type says whether its word is
        /// read signed.
        int_to_float,
        /// A `Float64` becomes the integer `ty` names, truncating toward
        /// zero. The backend guards it: a NaN and a value whose truncation
        /// the target cannot hold trap rather than convert, because there is
        /// no integer the result could honestly be.
        float_to_int,
        /// A checked runtime math operation over one or two Float64 values.
        float_math,

        // Verification.

        /// Verifies its operand and traps with the given kind if it fails.
        /// What is verified follows from the kind: a range test against `ty`,
        /// or a non-zero test for a divisor.
        ///
        /// This stays one instruction rather than a comparison and a branch
        /// because how a range test is written depends on the widest machine
        /// integer available, and a machine-independent representation cannot
        /// state that. The backend expands it.
        check,
        /// A call. Control returns to the instruction after it, so this is not
        /// a terminator and does not end its block.
        call,
        /// The code address of one concrete function.
        function_addr,
        /// A call through one structural callable value.
        call_indirect,

        // Control flow. Every block ends in exactly one of these.
        /// A direct call that cannot return control to this block.
        call_noreturn,
        /// An indirect call that cannot return control to this block.
        call_indirect_noreturn,
        ret,
        jump,
        branch,
        trap,

        pub fn isTerminator(self: Tag) bool {
            return switch (self) {
                .call_noreturn, .call_indirect_noreturn, .ret, .jump, .branch, .trap => true,
                else => false,
            };
        }

        pub fn payload(self: Tag) Payload {
            return switch (self) {
                .constant => .constant,
                .bytes_addr => .bytes,
                .static_addr => .static,
                .load, .addr_of => .local,
                .load_indirect, .borrow, .observe, .address_bits => .unary,
                .load_raw, .store_raw, .storage_addr => .raw_access,
                .store_indirect, .field_addr, .copy_value, .move_value => .binary,
                .store => .store,
                .add, .sub, .mul, .div, .rem => .binary,
                .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => .binary,
                .neg, .ret, .int_to_float, .float_to_int => .unary,
                .float_math => .float_math,
                .check => .check,
                .call => .call,
                .function_addr => .function,
                .call_indirect => .indirect_call,
                .call_noreturn => .call,
                .call_indirect_noreturn => .indirect_call,
                .jump => .target,
                .branch => .branch,
                .trap => .trap,
            };
        }
    };

    pub const Payload = enum { constant, bytes, static, local, store, unary, binary, float_math, raw_access, check, call, function, indirect_call, target, branch, trap };

    /// Named rather than anonymous so a consumer can spell the type it is
    /// handed and pass it on.
    pub const FloatMath = struct {
        operation: @import("../support/float_math.zig").Operation,
        lhs: InstId,
        rhs: InstId = .none,
    };

    pub const Check = struct { value: InstId, kind: TrapKind };
    pub const Trap = struct {
        kind: TrapKind,
        message: InstId = .none,
    };

    /// A raw memory operation and the checks that make its integer address safe
    /// to turn into a pointer. Held out of line so the instruction payload stays
    /// no wider than a scalar constant. `length` is the extent paired with the
    /// address's base; loads leave `value` as none, and byte accesses leave
    /// `alignment_check` as none because every byte offset is aligned.
    pub const RawAccess = struct {
        pub const extra_len = 6;

        address: InstId,
        length: InstId = .none,
        value: InstId = .none,
        overflow_check: InstId = .none,
        bounds_check: InstId = .none,
        alignment_check: InstId = .none,
    };

    /// Which function a call names, and where its arguments begin.
    pub const Call = struct { func: FunctionId, args: ExtraIndex };
    pub const IndirectCall = struct { callee: InstId, args: ExtraIndex };

    /// Discriminated by `tag`, and read only through `Mir`'s accessors.
    pub const Data = union {
        /// Wide enough for `UInt64`'s maximum as well as `Int64`'s minimum, matching
        /// how the checker folds.
        constant: i128,
        local: LocalId,
        store: struct { local: LocalId, value: InstId },
        unary: InstId,
        binary: struct { lhs: InstId, rhs: InstId },
        float_math: FloatMath,
        raw_access: ExtraIndex,
        check: Check,
        call: Call,
        function: FunctionId,
        indirect_call: IndirectCall,
        target: BlockId,
        branch: struct { cond: InstId, then_block: BlockId, else_block: BlockId },
        trap: Trap,
        /// Which blob of the module's pool, for `bytes_addr`.
        bytes: u32,
        /// Which entry of the module's `statics`, for `static_addr`.
        static: u32,
    };
};

/// An index into a function's side array.
pub const ExtraIndex = enum(u32) {
    _,

    pub fn at(i: u32) ExtraIndex {
        return @enumFromInt(i);
    }

    pub fn index(self: ExtraIndex) u32 {
        return @intFromEnum(self);
    }
};

pub const Block = struct {
    /// Half-open range into `Mir.block_insts`.
    start: u32,
    end: u32,
    /// Every block has one, and `Mir.Builder.finish` refuses to produce a
    /// function where one does not. Storing it apart from the instruction range
    /// is what makes "a block ends in a terminator" a property of the shape
    /// rather than of the order instructions happen to be in.
    terminator: InstId,
};

pub const InstList = std.MultiArrayList(Inst);

/// A compilation unit's code: one `Mir` per function, in declaration order.
///
/// The functions are separate rather than one instruction stream with ranges,
/// because nothing reads across a function boundary and separate tables let
/// every existing per-function routine keep working unchanged.
/// Which declaration a function was lowered from, and what it was
/// instantiated with.
///
/// Monomorphisation is where a generic declaration stops existing, so this is
/// the only place the correspondence is known: after lowering there is no
/// generic function left to ask, and before it there is no answer, because
/// which instantiations exist is reachability.
pub const Origin = types_mod.Instantiation;

pub const Signedness = enum { signed, unsigned };

/// How an ordinary value is represented while it is computed.
pub const ComputationRepresentation = union(enum) {
    integer: Signedness,
    boolean,
    float64,
    enum_tag,
    indirect,
    code_pointer,
    data_pointer,
    unit,
    no_value,
    invalid,
};

/// How a value is represented when it occupies storage.
pub const StorageRepresentation = union(enum) {
    integer: struct { signedness: Signedness, bits: u8 },
    boolean,
    float64,
    enum_tag,
    bytes,
    code_pointer,
    data_pointer,
    unit,
    no_value,
    invalid,
};

pub const TypeRepresentation = struct {
    computation: ComputationRepresentation,
    storage: StorageRepresentation,
};

pub const TypeRepresentations = Table(TypeId, TypeRepresentation);

pub const ResultRole = enum { value, managed_address, none };
pub const SlotRole = enum { value, managed_address };

/// The physical slot type for one already-erased parameter type.
///
/// A `Never` parameter is representable even though no caller can produce its
/// argument. It follows the ordinary zero-sized convention by occupying a Unit
/// slot; its callable signature retains `Never`, so reading the binding still
/// terminates rather than loading this placeholder.
pub fn parameterSlotType(erased: TypeId) TypeId {
    return if (erased == .never) .unit else erased;
}

/// The role of the value a type's layout says is held: an aggregate is passed
/// and returned as the address of its bytes, everything else as the value. A
/// call's result, an indirect load's and a signature's return convention all
/// read this one answer.
pub fn valueRole(layout: Layout) ResultRole {
    return if (layout.isAggregate()) .managed_address else .value;
}

/// Whether a `read` parameter's argument is the place itself, lent where it
/// sits, rather than a value taken from it.
pub fn parameterBorrowsPlace(param: types_mod.CallableParam) bool {
    return param.convention == .read and param.stable_address;
}

/// The role of the slot a parameter arrives in. An `inout` parameter is an
/// address to write through; a `read` one is an address where it must stay
/// in place or is an aggregate, whose value is its address; everything else,
/// a `sink` included, arrives as the value. A body, a generated entry and the
/// verifier all read this one answer.
pub fn parameterSlotRole(param: types_mod.CallableParam, aggregate: bool) SlotRole {
    return switch (param.convention) {
        .inout => .managed_address,
        .read => if (parameterBorrowsPlace(param) or aggregate) .managed_address else .value,
        .sink => .value,
    };
}

/// Whether an argument for `param` is passed as an address: where its slot is
/// one, and for any aggregate, whose value is its address even when the
/// parameter takes it by `sink`. A call's arguments and a signature's
/// parameters both read this, and it reads the slot's role.
pub fn parameterArrivesByAddress(param: types_mod.CallableParam, aggregate: bool) bool {
    return aggregate or parameterSlotRole(param, aggregate) == .managed_address;
}

test "an argument arrives by address where its slot is one or it is an aggregate" {
    var param: types_mod.CallableParam = .{ .spelling = "value", .convention = .sink, .ty = .u8, .default = .absent };
    try std.testing.expect(!parameterArrivesByAddress(param, false));
    try std.testing.expect(parameterArrivesByAddress(param, true));
    param.convention = .inout;
    try std.testing.expect(parameterArrivesByAddress(param, false));
    param.convention = .read;
    param.stable_address = true;
    try std.testing.expect(parameterArrivesByAddress(param, false));
}

test "a parameter's slot is an address where it is written through, kept in place or an aggregate" {
    const read: types_mod.CallableParam = .{ .spelling = "value", .convention = .read, .ty = .u8, .default = .absent };
    try std.testing.expectEqual(SlotRole.value, parameterSlotRole(read, false));
    try std.testing.expectEqual(SlotRole.managed_address, parameterSlotRole(read, true));
    var stable = read;
    stable.stable_address = true;
    try std.testing.expectEqual(SlotRole.managed_address, parameterSlotRole(stable, false));
    var inout = read;
    inout.convention = .inout;
    try std.testing.expectEqual(SlotRole.managed_address, parameterSlotRole(inout, false));
    var sink = read;
    sink.convention = .sink;
    try std.testing.expectEqual(SlotRole.value, parameterSlotRole(sink, true));
}

pub const ResultRepresentation = union(enum) {
    none,
    computation: ComputationRepresentation,
    managed_address,
};

pub const SlotRepresentation = union(enum) {
    storage: StorageRepresentation,
    managed_address,
};

/// The one derivation of a type's computation and storage representations.
fn representationFor(
    typing: *const types_mod.Typing,
    layout: Layout,
    erased: TypeId,
) TypeRepresentation {
    if (erased.integerInfo()) |info| return .{
        .computation = .{ .integer = if (info.signed) .signed else .unsigned },
        .storage = .{ .integer = .{
            .signedness = if (info.signed) .signed else .unsigned,
            .bits = info.bits,
        } },
    };

    return switch (typing.get(erased)) {
        .boolean => .{ .computation = .boolean, .storage = .boolean },
        .float => .{ .computation = .float64, .storage = .float64 },
        .enum_ => if (layout.isAggregate())
            .{ .computation = .indirect, .storage = .bytes }
        else
            .{ .computation = .enum_tag, .storage = .enum_tag },
        .struct_, .array => .{ .computation = .indirect, .storage = .bytes },
        .closure => |closure| if (closure.environment == .unit)
            .{ .computation = .unit, .storage = .unit }
        else
            .{ .computation = .indirect, .storage = .bytes },
        .unit => .{ .computation = .unit, .storage = .unit },
        .never => .{ .computation = .no_value, .storage = .no_value },
        .callable => .{ .computation = .code_pointer, .storage = .code_pointer },
        .borrow => .{ .computation = .data_pointer, .storage = .data_pointer },
        .newtype, .integer => unreachable,
        // An open integer or open type left in the pool is one no recorded use
        // still names: every use was resolved before checking finished. Like a
        // parameter, it has no representation a value could have.
        .poison, .parameter, .open_integer, .open_type => .{ .computation = .invalid, .storage = .invalid },
    };
}

pub fn deriveRepresentations(
    gpa: std.mem.Allocator,
    typing: *const types_mod.Typing,
    layouts: []const Layout,
) std.mem.Allocator.Error!TypeRepresentations {
    var out = try TypeRepresentations.of(
        gpa,
        typing.pool.len,
        .{ .computation = .invalid, .storage = .invalid },
    );
    errdefer out.deinit(gpa);

    const erased = try gpa.alloc(?TypeId, typing.pool.len);
    defer gpa.free(erased);
    @memset(erased, null);

    var path: std.ArrayList(TypeId) = .empty;
    defer path.deinit(gpa);
    for (0..typing.pool.len) |i| {
        const ty = TypeId.at(@intCast(i));
        if (erased[i] != null) continue;

        path.clearRetainingCapacity();
        var at = ty;
        while (erased[at.index()] == null and typing.get(at) == .newtype) {
            try path.append(gpa, at);
            at = typing.get(at).newtype.base;
        }

        const base = erased[at.index()] orelse at;
        erased[at.index()] = base;
        while (path.pop()) |part| erased[part.index()] = base;
    }

    for (0..typing.pool.len) |i| {
        const ty = TypeId.at(@intCast(i));
        out.set(ty, representationFor(typing, layouts[i], erased[i].?));
    }
    return out;
}

/// A constant's value at one type, held as read-only data the module carries.
///
/// A borrow of a constant observes this storage, which lasts as long as the
/// program, and a read of an aggregate constant copies out of it. The value is
/// laid out once, when lowering first reaches the constant at this type.
pub const Static = struct {
    /// The type whose layout arranges the bytes.
    ty: TypeId,
    /// The scalar parts, in increasing offset order. Bytes no part covers,
    /// such as padding, are zero.
    parts: []const StaticPart,
};

/// One scalar written into a static, as a store of `ty` at `offset` writes it.
pub const StaticPart = struct {
    offset: u32,
    /// A type stored as a scalar. Its storage representation decides how many
    /// bytes the part occupies and how the value is encoded in them.
    ty: TypeId,
    value: Value,

    pub const Value = union(enum) {
        /// An integer, a truth value as 0 or 1, or an enum tag.
        constant: i128,
        /// The address of a blob of the module's `bytes`, as an integer. A
        /// `Str` constant holds one for the text it views.
        bytes: u32,
    };
};

pub const Module = struct {
    functions: []Mir,
    /// Whether each function is defined elsewhere, one flag per function.
    ///
    /// An `extern` is called like any other function and defined by nothing
    /// here, so the backend emits the call and not the body. Carried beside
    /// the names rather than asked of the tree, because the backend has no
    /// tree.
    external: []const bool,
    /// The canonical zeroed allocator, retained as an ordinary nullable call.
    zeroed_allocator: FunctionId = .none,
    /// What each of them is published as, or an empty name where nothing
    /// outside reaches it.
    ///
    /// The name rather than a flag beside one: whether something outside
    /// reaches a function and what it is called out there are one question,
    /// and a flag with a name beside it is two places that can disagree about
    /// a symbol the linker reads once.
    ///
    /// Empty throughout a program: the one symbol anything outside calls is
    /// the entry wrapper, and every other body has all its callers in hand. A
    /// library is the case that is not true of -- it exists to be called from
    /// outside -- so what it publishes has to survive an optimiser that would
    /// otherwise see a body nothing references.
    exported_as: []const []const u8 = &.{},
    /// Every distinct blob of bytes the module's code names, in the order they
    /// were first reached. Interned by content: a literal written twice is one
    /// blob, and a generic body emitted per instantiation names the same one
    /// each time.
    ///
    /// Nothing can observe the sharing. What indexes this is an address inside
    /// an `opaque` structure, so no program reads it and none can tell two
    /// blobs apart by identity.
    bytes: []const []const u8,
    /// The read-only data `static_addr` names, in the order lowering first
    /// reached each one. One entry per constant and type that a function
    /// reads, so a constant read nowhere is not emitted.
    statics: []const Static = &.{},
    /// What each function is called in the emitted code.
    ///
    /// Spelled in the alphabet `support/symbol.zig` states, and owned by the module: the
    /// only producer is lowering, which mints one per instantiation and hands
    /// it over.
    names: [][]const u8,
    /// Where each function came from, indexed alongside `functions`.
    origins: []const Origin,
    /// The type table this module's code refers to, as lowering left it.
    ///
    /// Lowering interns instantiations the checker never saw, so the pool a
    /// module's handles index is not the one the checker finished with.
    /// `layouts` is derived from this; carrying the table itself is what
    /// lets a reader ask what a handle *is* rather than only how wide it is.
    types: types_mod.Typing = .{
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
        .binding_types = .empty,
        .decl_returns = .empty,
    },
    /// How every type is computed and stored, indexed by `TypeId`.
    representations: TypeRepresentations = .empty,
    /// How wide each type is, indexed by `TypeId`.
    ///
    /// A table travelling with the module rather than recomputed by a backend.
    /// It answers arrangement; `representations` answers how those bytes cross
    /// computation and storage boundaries. Neither consumer derives either
    /// answer from the type pool.
    layouts: []const Layout,
    /// The exact prelude `Str` type a panic message must carry.
    panic_message_type: TypeId = .poison,
    /// Which one the runtime calls, or `.none` where nothing does.
    ///
    /// A library has no entry point and may not declare one, so there is no
    /// function to wrap and the module holds none. Sentinel rather than the
    /// first function, because an index that is always valid is one every
    /// reader believes: the wrapper called whatever happened to be lowered
    /// first, and emitted a call to it with the arity of `main`.
    entry: FunctionId,

    /// The one place a table this module owns is reached by the handle keying
    /// it, so each table's cover is checked once rather than wherever someone
    /// happens to index.
    ///
    /// Every one of those covers holds by ordering in lowering rather than by
    /// construction here, and the ordering is a property of code a reader of a
    /// module cannot see. So the check is written out rather than left to
    /// indexing: the distributed build is compiled with safety off, where the
    /// bounds check indexing would carry is deleted, and a read past the end
    /// returns whatever follows the allocation as if the module held it. An
    /// invariant enforced only in a build nobody runs is not enforced, so
    /// these hold in every build.
    ///
    /// The panic names the handle and the extent, because the two numbers are
    /// what says which side of the boundary the defect is on: a handle just
    /// past a plausible length is a pass that appended after the table was
    /// built, and a wild one is a handle read from the wrong payload.
    fn entryOf(
        comptime T: type,
        table: []const T,
        kind: []const u8,
        holding: []const u8,
        i: u32,
    ) *const T {
        if (i >= table.len) std.debug.panic(
            "compiler defect: {s} {d} has no {s}, and the table holds {d}",
            .{ kind, i, holding, table.len },
        );
        return &table[i];
    }

    /// The arrangement of a type. The one way `layouts` is read.
    ///
    /// The table is as long as the pool the module carries: lowering allocates
    /// it from the pool it finished with, once the last instantiation has been
    /// interned. A pass interning a type after the table is allocated leaves a
    /// handle past the end, and nothing about the types involved would say so.
    ///
    /// Answering "a scalar in a register" for an uncovered handle would be
    /// worse than the panic: it gives a twenty-four-byte structure an
    /// eight-byte slot and writes sixteen bytes past it, turning a crash into
    /// a miscompile. Reading past the table is worse again -- a layout
    /// assembled from arbitrary bytes decides a slot's width, a load's width
    /// and a blit's size.
    pub fn layoutOf(self: *const Module, ty: TypeId) Layout {
        return entryOf(Layout, self.layouts, "type", "layout", @intFromEnum(ty)).*;
    }

    pub fn representationOf(self: *const Module, ty: TypeId) TypeRepresentation {
        return self.representations.get(ty);
    }

    pub fn resultRepresentationOf(self: *const Module, mir: *const Mir, id: InstId) ResultRepresentation {
        return switch (mir.resultRoleOf(id)) {
            .none => .none,
            .managed_address => .managed_address,
            .value => .{ .computation = self.representationOf(mir.typeOf(id)).computation },
        };
    }

    pub fn slotRepresentationOf(self: *const Module, mir: *const Mir, local: LocalId) SlotRepresentation {
        return switch (mir.slotRoleOf(local)) {
            .managed_address => .managed_address,
            .value => .{ .storage = self.representationOf(mir.locals[local.index()]).storage },
        };
    }

    /// How much storage a local needs: as much as the widest single access made
    /// to its recorded physical representation.
    ///
    /// Stated here rather than in a backend because this is also the extent the
    /// verifier bounds accesses against. Both consumers reach the answer in
    /// O(1): the local role and type representation are indexed tables, and only
    /// aggregate bytes consult the indexed canonical layout.
    pub fn slotExtentOf(self: *const Module, mir: *const Mir, local: LocalId) u32 {
        return switch (self.slotRepresentationOf(mir, local)) {
            .managed_address => Layout.word,
            .storage => |storage| switch (storage) {
                .integer => |integer| @as(u32, integer.bits) / 8,
                .boolean => 1,
                .enum_tag => Layout.tag_width,
                .float64, .unit, .code_pointer, .data_pointer => Layout.word,
                .bytes => self.layoutOf(mir.locals[local.index()]).size,
                .no_value => std.debug.panic("compiler defect: a Never value cannot occupy a slot", .{}),
                .invalid => std.debug.panic(
                    "compiler defect: slot ${d} has an invalid storage representation",
                    .{local.index()},
                ),
            },
        };
    }

    /// The alignment paired with `slotExtentOf`, from the same recorded slot
    /// representation and canonical aggregate layout.
    pub fn slotAlignmentOf(self: *const Module, mir: *const Mir, local: LocalId) u32 {
        return switch (self.slotRepresentationOf(mir, local)) {
            .managed_address => Layout.word,
            .storage => |storage| switch (storage) {
                .integer => |integer| @as(u32, integer.bits) / 8,
                .boolean => 1,
                .enum_tag => Layout.tag_width,
                .float64, .unit, .code_pointer, .data_pointer => Layout.word,
                .bytes => self.layoutOf(mir.locals[local.index()]).alignment,
                .no_value => std.debug.panic("compiler defect: a Never value cannot occupy a slot", .{}),
                .invalid => std.debug.panic(
                    "compiler defect: slot ${d} has an invalid storage representation",
                    .{local.index()},
                ),
            },
        };
    }

    /// What a handle was lowered to. The one way `functions` is reached by
    /// handle; a pass wanting all of them iterates the field.
    ///
    /// The table is as long as the queue of instantiations, because lowering's
    /// drain loop runs to exhaustion while claiming a handle appends behind
    /// the cursor. That is a property of one loop in one file, and a caller
    /// resolving a call's callee -- to ask what it returns, and so which
    /// convention the call uses -- has no way to see it.
    pub fn functionOf(self: *const Module, f: FunctionId) *const Mir {
        return entryOf(Mir, self.functions, "function", "lowered body", f.index());
    }

    /// Marks every type the emitted code names, for each function.
    ///
    /// Three arrays and one question: a signature names its return type, a
    /// slot names what it holds, and an instruction names what it produces.
    /// Callers walked the three separately -- the emitter deciding what to
    /// declare, the dump deciding what to print -- so a fourth place a
    /// function names a type is added to whichever scan its author was looking
    /// at. Update one and not the other and the dump names a type it never
    /// declares, or the emitted file references a `:t` it never defined.
    ///
    /// Marks rather than answers, because both callers want the whole set and
    /// one of them closes over it afterwards.
    pub fn markNamedTypes(self: *const Module, held: []bool) void {
        for (self.functions) |*f| {
            var named = f.namedTypes();
            while (named.next()) |n| held[@intFromEnum(n.ty)] = true;
        }
    }

    /// Whether the callee reaches argument `i` through the address it is
    /// handed, and therefore how many bytes the caller must lend.
    ///
    /// Two ways that happens and one question. A parameter written back
    /// through holds an address whatever its type; one too wide for a register
    /// arrives as an address the callee copies out of. Either way the callee
    /// reads the parameter's own width out of memory the caller owns.
    ///
    /// A slot role answers the first alone -- it is not the same question as
    /// holding an address is not the same question as being held in memory.
    /// The emitter asked both and the check holding a caller to it asked one,
    /// so the check was off for exactly the parameters the emitter copies.
    pub fn arrivesByAddress(self: *const Module, f: *const Mir, i: usize) bool {
        if (i >= f.param_count) return false;
        if (f.slotRoleOf(LocalId.at(@intCast(i))) == .managed_address) return true;
        return self.layoutOf(f.locals[i]).isAggregate();
    }

    /// Whether a function hands its result back through storage the caller
    /// owns, rather than in a register.
    ///
    /// Stated here because two passes must agree on it and neither may be the
    /// one that decides: the backend writes the convention into the emitted
    /// signature, and the verifier holds the emitted code to it. Asking a
    /// return type twice is two answers that drift, and this is exactly where
    /// they had: the entry point returns a word whatever its type says, so a
    /// verifier reading only `return_type` switched its frame-escape check off
    /// for the one function whose convention the emitter overrides.
    ///
    /// The entry point is the exception, and it is not a property of its type.
    /// The runtime calls it and reads a byte, so its result is a register no
    /// matter how wide the type would otherwise be -- which is why the question
    /// takes a handle rather than a type.
    pub fn returnsIndirectly(self: *const Module, f: FunctionId) bool {
        if (f == self.entry) return false;
        return self.returnsByAddress(self.functionOf(f).return_type);
    }

    /// Whether a callable whose result is `result` hands it back through
    /// storage the caller owns. A signature has no handle, so an indirect call
    /// asks it by type; a function asks `returnsIndirectly`, which is this
    /// with the entry point's exception.
    pub fn returnsByAddress(self: *const Module, result: TypeId) bool {
        return valueRole(self.layoutOf(result)) == .managed_address;
    }

    /// Whether an argument for `param` is passed as an address, by its
    /// declared type: `parameterArrivesByAddress` read from the layouts this
    /// module holds. A call through a callable value reads it from the
    /// signature, because it has no function to ask.
    pub fn parameterByAddress(self: *const Module, param: types_mod.CallableParam) bool {
        return parameterArrivesByAddress(param, self.layoutOf(param.ty).isAggregate());
    }

    /// The role of the slot `param` arrives in, by its declared type.
    pub fn parameterSlotRoleOf(self: *const Module, param: types_mod.CallableParam) SlotRole {
        return parameterSlotRole(param, self.layoutOf(param.ty).isAggregate());
    }

    /// The signature an indirect call goes through: the callable type of the
    /// value it calls.
    pub fn indirectSignatureOf(self: *const Module, f: *const Mir, id: InstId) types_mod.CallableSignature {
        return self.types.get(f.typeOf(f.indirectCallOf(id).callee)).callable;
    }

    /// Whether an indirect call's result comes back through caller storage.
    pub fn indirectReturnsByAddress(self: *const Module, f: *const Mir, id: InstId) bool {
        return self.returnsByAddress(self.indirectSignatureOf(f, id).result);
    }

    /// What the outside world links against for this function, or null where
    /// nothing does.
    ///
    /// Null everywhere in a program, so nothing about how one is emitted
    /// changes there.
    pub fn exportedNameOf(self: *const Module, f: FunctionId) ?[]const u8 {
        if (self.exported_as.len == 0) return null;
        const name = entryOf([]const u8, self.exported_as, "function", "export", f.index()).*;
        return if (name.len == 0) null else name;
    }

    /// Whether this function is defined somewhere this compiler did not read.
    pub fn isExternal(self: *const Module, f: FunctionId) bool {
        return self.external[f.index()];
    }

    /// The symbol lowering recorded for this function.
    pub fn nameOf(self: *const Module, f: FunctionId) []const u8 {
        return entryOf([]const u8, self.names, "function", "symbol", f.index()).*;
    }

    /// Which declaration a handle was lowered from, and at which arguments. The
    /// one way `origins` is read.
    ///
    /// Covered by the same drain loop `functionOf` names. What follows a read
    /// past the end is a `decl` that indexes the syntax tree and an `args` whose
    /// pointer and length are read from past the allocation, so an uncovered
    /// handle renders some other declaration under this one's name rather than
    /// stopping.
    pub fn originOf(self: *const Module, f: FunctionId) Origin {
        return entryOf(Origin, self.origins, "function", "origin", f.index()).*;
    }

    pub fn deinit(self: *Module, gpa: std.mem.Allocator) void {
        for (self.functions) |*f| f.deinit(gpa);
        gpa.free(self.functions);
        for (self.bytes) |blob| gpa.free(blob);
        gpa.free(self.bytes);
        for (self.statics) |entry| gpa.free(entry.parts);
        gpa.free(self.statics);
        // The symbols themselves, not just the array holding them: lowering
        // spells each one and hands it over, and nothing else refers to it.
        for (self.names) |n| gpa.free(n);
        gpa.free(self.names);
        gpa.free(self.external);
        // The published names too, for the reason the symbols above are freed:
        // lowering spells each one and hands it over. An unexported function
        // holds an empty name, which was never allocated.
        for (self.exported_as) |n| if (n.len > 0) gpa.free(n);
        gpa.free(self.exported_as);
        for (self.origins) |o| {
            gpa.free(o.args);
            gpa.free(o.impl_args);
        }
        gpa.free(self.origins);
        self.representations.deinit(gpa);
        self.types.deinit(gpa);
        gpa.free(self.layouts);
        self.* = undefined;
    }
};

/// Machine-independent code for one function: explicit blocks, explicit
/// temporaries, explicit checks. The first representation whose control flow is
/// explicit, which is what distinguishes it from everything above it.
/// Where a function names a type, and which position it is.
///
/// Positions rather than a flat list, because the two readers want different
/// things from the same walk: the emitter marks each type as held, and the
/// verifier says which position was undescribed. A message is what differs;
/// the enumeration is not.
pub const NamedType = struct {
    ty: TypeId,
    at: union(enum) {
        returned,
        slot: u32,
        inst: InstId,
    },
};

/// Every position a function names a type at.
///
/// One enumeration, because "where does a function name a type" is one
/// question. It was walked twice -- once to mark what the emitted module
/// declares, once to check every type is described -- and a position added to
/// one walk and not the other is either a type the backend declares that
/// nothing verified, or one the verifier demands that nothing emits.
pub const NamedTypes = struct {
    f: *const Mir,
    at: u32 = 0,

    pub fn next(self: *NamedTypes) ?NamedType {
        const locals = self.f.locals.len;
        const i = self.at;
        self.at += 1;

        if (i == 0) return .{ .ty = self.f.return_type, .at = .returned };
        if (i == 1) return .{ .ty = self.f.signature, .at = .returned };
        if (i <= locals + 1) {
            const k: u32 = @intCast(i - 2);
            return .{ .ty = self.f.locals[k], .at = .{ .slot = k } };
        }

        const k = i - 2 - locals;
        const tys = self.f.insts.items(.ty);
        if (k >= tys.len) return null;
        return .{ .ty = tys[k], .at = .{ .inst = InstId.at(@intCast(k)) } };
    }
};

pub const Mir = struct {
    insts: InstList.Slice,
    /// The instructions of every block, concatenated; each block holds a range.
    block_insts: []const InstId,
    blocks: []const Block,
    /// The type of each local, indexed by `LocalId`.
    locals: []const TypeId,
    entry: BlockId,
    /// Runs held out of line. A call stores its count then its arguments; a raw
    /// access stores the six fields of `Inst.RawAccess` in declaration order.
    extra: []const InstId,
    /// How many of the leading slots are parameters. A parameter arrives in a
    /// slot like a binding does, so the body reads one the same way, and the
    /// backend needs to know which slots to fill on entry.
    param_count: u32,
    /// What every local's slot holds, indexed alongside `locals`.
    slot_roles: []const SlotRole,
    /// The file the function was written in.
    ///
    /// A function's body cannot span files, so this is a property of the
    /// function rather than of each instruction -- which is what keeps a span
    /// four bytes and still lets a trap in one file of a module name that file
    /// rather than the module's first.
    file: FileId,
    /// What the function yields.
    ///
    /// Held per function rather than looked up from the tree, because a value
    /// too wide for a register is returned by a different convention and the
    /// backend has to know which one at both ends of a call.
    return_type: TypeId,
    /// The exact substituted structural callable signature of this body.
    signature: TypeId,
    /// Which call instruction each written call expression lowered to. A
    /// reader pairing source calls with their callees reads this rather than
    /// matching spans, which a spliced body gives to every instruction it
    /// holds.
    call_sites: []const CallSite,

    pub const CallSite = struct { expr: node.ExprId, call: InstId };

    pub fn deinit(self: *Mir, gpa: std.mem.Allocator) void {
        gpa.free(self.call_sites);
        self.insts.deinit(gpa);
        gpa.free(self.block_insts);
        gpa.free(self.blocks);
        gpa.free(self.locals);
        gpa.free(self.slot_roles);
        gpa.free(self.extra);
        self.* = undefined;
    }

    /// Checks that an instruction's tag names the payload about to be read.
    ///
    /// `Inst.Data` is a plain union: which member holds a value is decided by
    /// `tag` and by nothing stored beside it, so reading the wrong member does
    /// not fail -- it reinterprets one payload's bytes as another's. A
    /// `constant` read as a `store` yields a `LocalId` built from the low bits
    /// of an integer literal, which then indexes the local table; a `branch`
    /// read as a `call` yields an index into the side array holding the
    /// arguments, and the length found there decides how long a slice of it a
    /// caller is handed.
    ///
    /// So it is checked in every build. The distributed build is compiled with
    /// safety off, where both the assertion that would name the mismatch and
    /// the bounds check that would catch what the misread id goes on to do are
    /// deleted -- leaving an out-of-range slot number in the emitted code, or a
    /// slice of arbitrary length over the side array.
    ///
    /// The question asked is which member, not which tag: two tags sharing a
    /// payload are interchangeable here and a reader that accepted only one of
    /// them would be stating the union's shape a second time.
    fn expectPayload(self: *const Mir, i: InstId, p: Inst.Payload) void {
        const tag = self.tagOf(i);
        if (tag.payload() != p) std.debug.panic(
            "compiler defect: instruction {d} is {s}, read as {s}",
            .{ i.index(), @tagName(tag), @tagName(p) },
        );
    }

    /// The function a call names, and its arguments.
    pub fn callOf(self: *const Mir, i: InstId) struct { func: FunctionId, args: []const InstId } {
        self.expectPayload(i, .call);
        const c = self.insts.items(.data)[i.index()].call;
        const at = c.args.index();
        const n = self.extra[at].index();
        return .{ .func = c.func, .args = self.extra[at + 1 ..][0..n] };
    }

    pub fn functionOf(self: *const Mir, i: InstId) FunctionId {
        self.expectPayload(i, .function);
        return self.insts.items(.data)[i.index()].function;
    }

    pub fn indirectCallOf(self: *const Mir, i: InstId) struct { callee: InstId, args: []const InstId } {
        self.expectPayload(i, .indirect_call);
        const call = self.insts.items(.data)[i.index()].indirect_call;
        const at = call.args.index();
        const n = self.extra[at].index();
        return .{ .callee = call.callee, .args = self.extra[at + 1 ..][0..n] };
    }

    pub fn indirectCallDataInRange(self: *const Mir, i: InstId) bool {
        self.expectPayload(i, .indirect_call);
        const at = self.insts.items(.data)[i.index()].indirect_call.args.index();
        if (at >= self.extra.len) return false;
        const n = self.extra[at].index();
        return n <= self.extra.len - at - 1;
    }

    /// Every position this function names a type at. See `NamedTypes`.
    pub fn namedTypes(self: *const Mir) NamedTypes {
        return .{ .f = self };
    }

    pub fn blockCount(self: *const Mir) u32 {
        return @intCast(self.blocks.len);
    }

    pub fn instsOf(self: *const Mir, b: BlockId) []const InstId {
        const blk = self.blocks[b.index()];
        return self.block_insts[blk.start..blk.end];
    }

    pub fn terminatorOf(self: *const Mir, b: BlockId) InstId {
        return self.blocks[b.index()].terminator;
    }

    pub fn tagOf(self: *const Mir, i: InstId) Inst.Tag {
        return self.insts.items(.tag)[i.index()];
    }

    pub fn typeOf(self: *const Mir, i: InstId) TypeId {
        return self.insts.items(.ty)[i.index()];
    }

    pub fn resultRoleOf(self: *const Mir, i: InstId) ResultRole {
        return self.insts.items(.result_role)[i.index()];
    }

    pub fn slotRoleOf(self: *const Mir, local: LocalId) SlotRole {
        return self.slot_roles[local.index()];
    }

    pub fn spanOf(self: *const Mir, i: InstId) Span {
        return self.insts.items(.span)[i.index()];
    }

    pub fn constantOf(self: *const Mir, i: InstId) i128 {
        self.expectPayload(i, .constant);
        return self.insts.items(.data)[i.index()].constant;
    }

    /// The value of a float constant. The payload holds one integer whatever
    /// the type; which reading applies is the instruction's own type's to
    /// say, and this is the reading `Float64` names -- the bits of a double.
    pub fn floatConstantOf(self: *const Mir, i: InstId) f64 {
        self.expectPayload(i, .constant);
        const bits: u64 = @intCast(self.insts.items(.data)[i.index()].constant);
        return @bitCast(bits);
    }

    /// Which blob of the module's pool a `bytes_addr` names.
    pub fn bytesOf(self: *const Mir, i: InstId) u32 {
        self.expectPayload(i, .bytes);
        return self.insts.items(.data)[i.index()].bytes;
    }

    /// Which entry of the module's `statics` a `static_addr` names.
    pub fn staticOf(self: *const Mir, i: InstId) u32 {
        self.expectPayload(i, .static);
        return self.insts.items(.data)[i.index()].static;
    }

    test staticOf {
        var b = Mir.Builder.init(testing.allocator);
        defer b.deinit();
        const entry = try b.addBlock();
        const at = try b.addInst(entry, .{ .tag = .static_addr, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .static = 2 } });
        _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = at } });
        var mir = try b.finish(entry, .from(0));
        defer mir.deinit(testing.allocator);
        try testing.expectEqual(@as(u32, 2), mir.staticOf(at));
    }

    pub fn localOf(self: *const Mir, i: InstId) LocalId {
        self.expectPayload(i, .local);
        return self.insts.items(.data)[i.index()].local;
    }

    pub fn storeOf(self: *const Mir, i: InstId) struct { local: LocalId, value: InstId } {
        self.expectPayload(i, .store);
        const d = self.insts.items(.data)[i.index()].store;
        return .{ .local = d.local, .value = d.value };
    }

    pub fn unaryOf(self: *const Mir, i: InstId) InstId {
        self.expectPayload(i, .unary);
        return self.insts.items(.data)[i.index()].unary;
    }

    pub fn binaryOf(self: *const Mir, i: InstId) struct { lhs: InstId, rhs: InstId } {
        self.expectPayload(i, .binary);
        const d = self.insts.items(.data)[i.index()].binary;
        return .{ .lhs = d.lhs, .rhs = d.rhs };
    }

    pub fn floatMathOf(self: *const Mir, i: InstId) Inst.FloatMath {
        self.expectPayload(i, .float_math);
        return self.insts.items(.data)[i.index()].float_math;
    }

    pub fn rawAccessOf(self: *const Mir, i: InstId) Inst.RawAccess {
        self.expectPayload(i, .raw_access);
        const at = self.insts.items(.data)[i.index()].raw_access.index();
        const fields = self.extra[at..][0..Inst.RawAccess.extra_len];
        return .{
            .address = fields[0],
            .length = fields[1],
            .value = fields[2],
            .overflow_check = fields[3],
            .bounds_check = fields[4],
            .alignment_check = fields[5],
        };
    }

    pub fn rawAccessDataInRange(self: *const Mir, i: InstId) bool {
        self.expectPayload(i, .raw_access);
        const at = self.insts.items(.data)[i.index()].raw_access.index();
        return at <= self.extra.len and self.extra.len - at >= Inst.RawAccess.extra_len;
    }

    pub fn checkOf(self: *const Mir, i: InstId) Inst.Check {
        self.expectPayload(i, .check);
        return self.insts.items(.data)[i.index()].check;
    }

    pub fn targetOf(self: *const Mir, i: InstId) BlockId {
        self.expectPayload(i, .target);
        return self.insts.items(.data)[i.index()].target;
    }

    pub fn branchOf(self: *const Mir, i: InstId) struct { cond: InstId, then_block: BlockId, else_block: BlockId } {
        self.expectPayload(i, .branch);
        const d = self.insts.items(.data)[i.index()].branch;
        return .{ .cond = d.cond, .then_block = d.then_block, .else_block = d.else_block };
    }

    pub fn trapOf(self: *const Mir, i: InstId) Inst.Trap {
        self.expectPayload(i, .trap);
        return self.insts.items(.data)[i.index()].trap;
    }

    /// The blocks a terminator hands control to: none, one, or two.
    ///
    /// Every walk that follows edges reads this rather than keeping a copy of
    /// what each tag means -- two walks holding a copy each is how a terminator
    /// added later reaches one of them and not the other. Exhaustive over every
    /// tag, so the addition is a compile error here before it is a wrong walk
    /// anywhere.
    pub fn successorsOf(self: *const Mir, t: InstId) [2]?BlockId {
        return switch (self.tagOf(t)) {
            .jump => .{ self.targetOf(t), null },
            .branch => blk: {
                const b = self.branchOf(t);
                break :blk .{ b.then_block, b.else_block };
            },
            .call_noreturn, .call_indirect_noreturn, .ret, .trap => .{ null, null },
            // Not terminators; a walk asking about one is a defect.
            .constant,
            .bytes_addr,
            .static_addr,
            .address_bits,
            .load,
            .store,
            .addr_of,
            .borrow,
            .observe,
            .load_indirect,
            .store_indirect,
            .load_raw,
            .store_raw,
            .storage_addr,
            .field_addr,
            .copy_value,
            .move_value,
            .add,
            .sub,
            .mul,
            .div,
            .rem,
            .neg,
            .cmp_eq,
            .cmp_ne,
            .cmp_lt,
            .cmp_le,
            .cmp_gt,
            .cmp_ge,
            .int_to_float,
            .float_to_int,
            .float_math,
            .check,
            .call,
            .function_addr,
            .call_indirect,
            => |tag| std.debug.panic("compiler defect: {s} is not a terminator", .{@tagName(tag)}),
        };
    }

    /// Accumulates blocks and instructions while lowering. Blocks are filled
    /// out of order, because a check splits the block it is in, so each keeps
    /// its own list until the whole function is flattened.
    pub const Builder = struct {
        gpa: std.mem.Allocator,
        insts: InstList = .empty,
        /// Which block holds each instruction, parallel to `insts`, and
        /// `no_block` for a terminator, which a block names rather than holds.
        ///
        /// A vector per block recorded the same thing and cost a second append
        /// for every instruction built -- an index into it, then a capacity
        /// check and a store in the vector it found. A body of any size is
        /// millions of instructions and tens of blocks, so what was paid per
        /// instruction was paid to describe something there is almost none of.
        /// The order within a block is the order they were built in, which is
        /// the order they sit here.
        block_of: std.ArrayList(u32) = .empty,
        terminators: std.ArrayList(InstId) = .empty,
        extra: std.ArrayList(InstId) = .empty,
        call_sites: std.ArrayList(Mir.CallSite) = .empty,
        param_count: u32 = 0,
        return_type: TypeId = .unit,
        signature: TypeId = .poison,
        locals: std.ArrayList(TypeId) = .empty,
        slot_roles: std.ArrayList(SlotRole) = .empty,
        /// While set, every instruction built takes this span. A body spliced in
        /// from another declaration may come from another file, and a function
        /// holds one file, so its instructions carry the site that spliced it.
        located_at: ?Span = null,

        pub fn init(gpa: std.mem.Allocator) Builder {
            return .{ .gpa = gpa };
        }

        pub fn deinit(self: *Builder) void {
            self.insts.deinit(self.gpa);
            self.block_of.deinit(self.gpa);
            self.terminators.deinit(self.gpa);
            self.extra.deinit(self.gpa);
            self.call_sites.deinit(self.gpa);
            self.locals.deinit(self.gpa);
            self.slot_roles.deinit(self.gpa);
            self.* = undefined;
        }

        /// A block is its terminator's slot: one per block, appended here and
        /// filled by `setTerminator`, so the count of them is the count of
        /// blocks.
        pub fn addBlock(self: *Builder) !BlockId {
            const i: u32 = @intCast(self.terminators.items.len);
            try self.terminators.append(self.gpa, .none);
            return BlockId.at(i);
        }

        pub fn addLocal(self: *Builder, ty: TypeId, role: SlotRole) !LocalId {
            const i: u32 = @intCast(self.locals.items.len);
            try self.locals.append(self.gpa, ty);
            errdefer _ = self.locals.pop();
            try self.slot_roles.append(self.gpa, role);
            return LocalId.at(i);
        }

        pub fn slotRoleOf(self: *const Builder, local: LocalId) SlotRole {
            return self.slot_roles.items[local.index()];
        }

        pub fn addInst(self: *Builder, b: BlockId, inst: Inst) !InstId {
            std.debug.assert(!inst.tag.isTerminator());
            var recorded = inst;
            recorded.result_role = switch (inst.tag) {
                .store, .store_indirect, .store_raw, .copy_value, .move_value => .none,
                else => inst.result_role,
            };
            return self.push(recorded, b.index());
        }

        pub fn setTerminator(self: *Builder, b: BlockId, inst: Inst) !InstId {
            std.debug.assert(inst.tag.isTerminator());
            var recorded = inst;
            recorded.result_role = .none;
            const id = try self.push(recorded, no_block);
            self.terminators.items[b.index()] = id;
            return id;
        }

        /// A call, with its arguments held out of line. The count comes first
        /// so a reader of the side array knows how far the run goes.
        pub fn addCall(
            self: *Builder,
            b: BlockId,
            role: ResultRole,
            ty: TypeId,
            span: Span,
            func: FunctionId,
            args: []const InstId,
        ) !InstId {
            const start: u32 = @intCast(self.extra.items.len);
            try self.extra.append(self.gpa, InstId.at(@intCast(args.len)));
            try self.extra.appendSlice(self.gpa, args);
            return self.addInst(b, .{
                .tag = .call,
                .result_role = role,
                .ty = ty,
                .span = span,
                .data = .{ .call = .{ .func = func, .args = ExtraIndex.at(start) } },
            });
        }

        /// Records that the written call `expr` lowered to the call instruction
        /// `call`.
        pub fn recordCallSite(self: *Builder, expr: node.ExprId, call: InstId) !void {
            try self.call_sites.append(self.gpa, .{ .expr = expr, .call = call });
        }

        pub fn addFunctionAddr(
            self: *Builder,
            b: BlockId,
            ty: TypeId,
            span: Span,
            function: FunctionId,
        ) !InstId {
            return self.addInst(b, .{
                .tag = .function_addr,
                .ty = ty,
                .span = span,
                .data = .{ .function = function },
            });
        }

        pub fn addIndirectCall(
            self: *Builder,
            b: BlockId,
            role: ResultRole,
            ty: TypeId,
            span: Span,
            callee: InstId,
            args: []const InstId,
        ) !InstId {
            const start: u32 = @intCast(self.extra.items.len);
            try self.extra.append(self.gpa, InstId.at(@intCast(args.len)));
            try self.extra.appendSlice(self.gpa, args);
            return self.addInst(b, .{
                .tag = .call_indirect,
                .result_role = role,
                .ty = ty,
                .span = span,
                .data = .{ .indirect_call = .{ .callee = callee, .args = ExtraIndex.at(start) } },
            });
        }

        pub fn setCallNoreturn(
            self: *Builder,
            b: BlockId,
            span: Span,
            func: FunctionId,
            args: []const InstId,
        ) !InstId {
            const start: u32 = @intCast(self.extra.items.len);
            try self.extra.append(self.gpa, InstId.at(@intCast(args.len)));
            try self.extra.appendSlice(self.gpa, args);
            return self.setTerminator(b, .{
                .tag = .call_noreturn,
                .ty = .unit,
                .span = span,
                .data = .{ .call = .{ .func = func, .args = ExtraIndex.at(start) } },
            });
        }

        pub fn setIndirectCallNoreturn(
            self: *Builder,
            b: BlockId,
            span: Span,
            callee: InstId,
            args: []const InstId,
        ) !InstId {
            const start: u32 = @intCast(self.extra.items.len);
            try self.extra.append(self.gpa, InstId.at(@intCast(args.len)));
            try self.extra.appendSlice(self.gpa, args);
            return self.setTerminator(b, .{
                .tag = .call_indirect_noreturn,
                .ty = .unit,
                .span = span,
                .data = .{ .indirect_call = .{ .callee = callee, .args = ExtraIndex.at(start) } },
            });
        }

        pub fn addRawAccess(
            self: *Builder,
            b: BlockId,
            tag: Inst.Tag,
            ty: TypeId,
            span: Span,
            raw: Inst.RawAccess,
        ) !InstId {
            std.debug.assert(tag == .load_raw or tag == .store_raw or tag == .storage_addr);
            const start: u32 = @intCast(self.extra.items.len);
            try self.extra.appendSlice(self.gpa, &.{
                raw.address,
                raw.length,
                raw.value,
                raw.overflow_check,
                raw.bounds_check,
                raw.alignment_check,
            });
            return self.addInst(b, .{
                .tag = tag,
                .result_role = if (tag == .storage_addr) .managed_address else .value,
                .ty = ty,
                .span = span,
                .data = .{ .raw_access = ExtraIndex.at(start) },
            });
        }

        pub fn hasTerminator(self: *const Builder, b: BlockId) bool {
            return self.terminators.items[b.index()] != InstId.none;
        }

        /// What no block holds. A terminator is named by its block rather
        /// than listed in it, so it takes a slot here and no place in a run.
        const no_block = std.math.maxInt(u32);

        fn push(self: *Builder, inst: Inst, block: u32) !InstId {
            const i: u32 = @intCast(self.insts.len);
            var located = inst;
            if (self.located_at) |span| located.span = span;
            try self.insts.append(self.gpa, located);
            try self.block_of.append(self.gpa, block);
            return InstId.at(i);
        }

        /// A block left without a terminator, which is a defect in whatever
        /// built the function rather than anything a program can provoke.
        pub const Unfinished = error{UnterminatedBlock};

        pub fn finish(self: *Builder, entry: BlockId, file: FileId) (Unfinished || std.mem.Allocator.Error)!Mir {
            const count = self.terminators.items.len;

            // Checked before anything is laid out, because this is where the
            // invariant is established: past this point a `Mir` is what every
            // reader assumes it is. `.none` copied through leaves the backend
            // indexing an instruction array at `0xFFFFFFFF`, and an assertion
            // would say so only in the builds that are not distributed.
            for (self.terminators.items) |t| {
                if (t == InstId.none) return error.UnterminatedBlock;
            }

            // Counted, then scattered. Each block's run is where its
            // instructions go, and walking `block_of` in order puts them in
            // the order they were built -- which is the order a block holds
            // them in, so nothing has to be sorted to say so.
            const starts = try self.gpa.alloc(u32, count + 1);
            defer self.gpa.free(starts);
            @memset(starts, 0);
            for (self.block_of.items) |b| {
                if (b != no_block) starts[b + 1] += 1;
            }
            for (1..count + 1) |i| starts[i] += starts[i - 1];

            const flat = try self.gpa.alloc(InstId, starts[count]);
            errdefer self.gpa.free(flat);

            const at = try self.gpa.alloc(u32, count);
            defer self.gpa.free(at);
            @memcpy(at, starts[0..count]);

            for (self.block_of.items, 0..) |b, i| {
                if (b == no_block) continue;
                flat[at[b]] = InstId.at(@intCast(i));
                at[b] += 1;
            }

            const blocks = try self.gpa.alloc(Block, count);
            errdefer self.gpa.free(blocks);
            for (0..count) |i| blocks[i] = .{
                .start = starts[i],
                .end = starts[i + 1],
                .terminator = self.terminators.items[i],
            };

            // One handover at a time, each owned from the moment it is taken.
            // Written as one struct literal, a field that fails leaves every
            // field before it already moved out of the builder and into
            // nothing: the builder no longer frees them and no `Mir` exists to.
            const extra = try self.extra.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(extra);

            var insts = self.insts.toOwnedSlice();
            errdefer insts.deinit(self.gpa);

            const block_insts = flat;

            const locals = try self.locals.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(locals);

            const slot_roles = try self.slot_roles.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(slot_roles);

            const call_sites = try self.call_sites.toOwnedSlice(self.gpa);
            errdefer self.gpa.free(call_sites);

            const done: Mir = .{
                .file = file,
                .extra = extra,
                .param_count = self.param_count,
                .signature = self.signature,
                .slot_roles = slot_roles,
                .return_type = self.return_type,
                .insts = insts,
                .block_insts = block_insts,
                .blocks = blocks,
                .locals = locals,
                .entry = entry,
                .call_sites = call_sites,
            };

            // What flattening consumed rather than handed on. A builder is
            // released by the caller only where this fails, so a builder that
            // succeeded has to release the working lists itself -- everything
            // above is either given away or copied out by here.
            self.block_of.deinit(self.gpa);
            self.terminators.deinit(self.gpa);
            self.block_of = .empty;
            self.terminators = .empty;

            return done;
        }
    };
};

test "no instruction payload variant exceeds its widest scalar value" {
    inline for (@typeInfo(Inst.Data).@"union".fields) |field| {
        try testing.expect(@sizeOf(field.type) <= @sizeOf(i128));
    }
}

test "a builder located at a site gives every instruction that site" {
    var b = Mir.Builder.init(testing.allocator);
    defer b.deinit();
    const entry = try b.addBlock();
    const own: Span = .{ .start = 40, .end = 44 };
    const site: Span = .{ .start = 3, .end = 9 };
    const before = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = own, .data = .{ .constant = 1 } });
    b.located_at = site;
    const inside = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = own, .data = .{ .constant = 2 } });
    const call = try b.addCall(entry, .value, .u8, own, FunctionId.at(0), &.{inside});
    b.located_at = null;
    const ret = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = own, .data = .{ .unary = call } });
    var m = try b.finish(entry, .from(0));
    defer m.deinit(testing.allocator);
    try testing.expectEqual(own, m.spanOf(before));
    try testing.expectEqual(site, m.spanOf(inside));
    try testing.expectEqual(site, m.spanOf(call));
    try testing.expectEqual(own, m.spanOf(ret));
}

test "result and slot roles survive builder finish" {
    var b = Mir.Builder.init(testing.allocator);
    defer b.deinit();

    const value_slot = try b.addLocal(.u8, .value);
    const address_slot = try b.addLocal(.u8, .managed_address);
    const entry = try b.addBlock();
    const value = try b.addInst(entry, .{
        .tag = .constant,
        .result_role = .value,
        .ty = .u8,
        .span = Span.empty,
        .data = .{ .constant = 1 },
    });
    const address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = .u8,
        .span = Span.empty,
        .data = .{ .local = value_slot },
    });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });

    var mir = try b.finish(entry, .from(0));
    defer mir.deinit(testing.allocator);

    try testing.expectEqual(SlotRole.value, mir.slotRoleOf(value_slot));
    try testing.expectEqual(SlotRole.managed_address, mir.slotRoleOf(address_slot));
    try testing.expectEqual(ResultRole.value, mir.resultRoleOf(value));
    try testing.expectEqual(ResultRole.managed_address, mir.resultRoleOf(address));
    try testing.expectEqual(ResultRole.none, mir.resultRoleOf(mir.terminatorOf(entry)));
}

test "a built block reports its instructions and its terminator" {
    var b = Mir.Builder.init(testing.allocator);
    defer b.deinit();

    const blk = try b.addBlock();
    const c = try b.addInst(blk, .{
        .tag = .constant,
        .ty = .u8,
        .span = Span.empty,
        .data = .{ .constant = 7 },
    });
    _ = try b.setTerminator(blk, .{
        .tag = .ret,
        .ty = .unit,
        .span = Span.empty,
        .data = .{ .unary = c },
    });

    var mir = try b.finish(blk, .from(0));
    defer mir.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), mir.instsOf(blk).len);
    try testing.expectEqual(Inst.Tag.ret, mir.tagOf(mir.terminatorOf(blk)));
    try testing.expectEqual(@as(i128, 7), mir.constantOf(mir.instsOf(blk)[0]));
}

test "blocks keep their own instructions when filled out of order" {
    var b = Mir.Builder.init(testing.allocator);
    defer b.deinit();

    const first = try b.addBlock();
    const second = try b.addBlock();

    // Interleaved, as a check splitting a block produces.
    const a = try b.addInst(first, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 1 } });
    const c = try b.addInst(second, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 2 } });
    _ = try b.addInst(first, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 3 } });

    _ = try b.setTerminator(first, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = second } });
    _ = try b.setTerminator(second, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = c } });

    var mir = try b.finish(first, .from(0));
    defer mir.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), mir.instsOf(first).len);
    try testing.expectEqual(@as(usize, 1), mir.instsOf(second).len);
    try testing.expectEqual(a, mir.instsOf(first)[0]);
    try testing.expectEqual(second, mir.targetOf(mir.terminatorOf(first)));
}

test "a block without a terminator is visible as unfinished" {
    var b = Mir.Builder.init(testing.allocator);
    defer b.deinit();

    const blk = try b.addBlock();
    try testing.expect(!b.hasTerminator(blk));
    _ = try b.setTerminator(blk, .{ .tag = .trap, .ty = .unit, .span = Span.empty, .data = .{ .trap = .{ .kind = .overflow } } });
    try testing.expect(b.hasTerminator(blk));
}

test "locals carry their type" {
    var b = Mir.Builder.init(testing.allocator);
    defer b.deinit();

    const x = try b.addLocal(.u8, .value);
    const y = try b.addLocal(.i64, .value);
    const blk = try b.addBlock();
    _ = try b.setTerminator(blk, .{ .tag = .trap, .ty = .unit, .span = Span.empty, .data = .{ .trap = .{ .kind = .overflow } } });

    var mir = try b.finish(blk, .from(0));
    defer mir.deinit(testing.allocator);

    try testing.expectEqual(TypeId.u8, mir.locals[x.index()]);
    try testing.expectEqual(TypeId.i64, mir.locals[y.index()]);
}

test "a block left without a terminator does not become a function" {
    var b = Mir.Builder.init(testing.allocator);
    defer b.deinit();

    const entry = try b.addBlock();
    const stranded = try b.addBlock();
    _ = try b.setTerminator(entry, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = stranded } });

    try testing.expectError(error.UnterminatedBlock, b.finish(entry, .from(0)));
}

test "storage types decide slot extent and alignment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var b = Mir.Builder.init(gpa);
    defer b.deinit();
    const entry = try b.addBlock();
    const byte = try b.addLocal(.u8, .value);
    const half = try b.addLocal(.u16, .value);
    const boolean = try b.addLocal(.bool_, .value);
    const float = try b.addLocal(.f64, .value);
    const address = try b.addLocal(.u16, .managed_address);
    const unit = try b.addLocal(.unit, .value);
    const aggregate_ty = TypeId.at(@intCast(TypeId.builtins.len));
    const enum_ty = TypeId.at(@intCast(TypeId.builtins.len + 1));
    const aggregate = try b.addLocal(aggregate_ty, .value);
    const enum_tag = try b.addLocal(enum_ty, .value);
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .unit, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    const mir = try b.finish(entry, .from(0));
    const count = TypeId.builtins.len + 2;
    var representations = try TypeRepresentations.of(gpa, count, .{ .computation = .invalid, .storage = .invalid });
    representations.set(.u8, .{ .computation = .{ .integer = .unsigned }, .storage = .{ .integer = .{ .signedness = .unsigned, .bits = 8 } } });
    representations.set(.u16, .{ .computation = .{ .integer = .unsigned }, .storage = .{ .integer = .{ .signedness = .unsigned, .bits = 16 } } });
    representations.set(.bool_, .{ .computation = .boolean, .storage = .boolean });
    representations.set(.f64, .{ .computation = .float64, .storage = .float64 });
    representations.set(.unit, .{ .computation = .unit, .storage = .unit });
    representations.set(aggregate_ty, .{ .computation = .indirect, .storage = .bytes });
    representations.set(enum_ty, .{ .computation = .enum_tag, .storage = .enum_tag });
    const layouts = try gpa.alloc(Layout, count);
    @memset(layouts, Layout.scalar);
    layouts[aggregate_ty.index()] = .{ .size = 24, .alignment = 8, .indirect = true };

    const module: Module = .{
        .functions = try gpa.dupe(Mir, &.{mir}),
        .external = &.{false},
        .bytes = &.{},
        .names = &.{},
        .origins = &.{},
        .representations = representations,
        .layouts = layouts,
        .entry = .at(0),
    };
    const f = &module.functions[0];

    try testing.expectEqual(@as(u32, 1), module.slotExtentOf(f, byte));
    try testing.expectEqual(@as(u32, 1), module.slotAlignmentOf(f, byte));
    try testing.expectEqual(@as(u32, 2), module.slotExtentOf(f, half));
    try testing.expectEqual(@as(u32, 2), module.slotAlignmentOf(f, half));
    try testing.expectEqual(@as(u32, 1), module.slotExtentOf(f, boolean));
    try testing.expectEqual(@as(u32, 1), module.slotAlignmentOf(f, boolean));
    try testing.expectEqual(@as(u32, 8), module.slotExtentOf(f, float));
    try testing.expectEqual(@as(u32, 8), module.slotAlignmentOf(f, float));
    try testing.expectEqual(@as(u32, Layout.word), module.slotExtentOf(f, address));
    try testing.expectEqual(@as(u32, Layout.word), module.slotAlignmentOf(f, address));
    try testing.expectEqual(@as(u32, Layout.word), module.slotExtentOf(f, unit));
    try testing.expectEqual(@as(u32, Layout.word), module.slotAlignmentOf(f, unit));
    try testing.expectEqual(@as(u32, 24), module.slotExtentOf(f, aggregate));
    try testing.expectEqual(@as(u32, 8), module.slotAlignmentOf(f, aggregate));
    try testing.expectEqual(@as(u32, 8), module.slotExtentOf(f, enum_tag));
    try testing.expectEqual(@as(u32, 8), module.slotAlignmentOf(f, enum_tag));
}

test "a module frees what it owns, and a hand-built one owns the same things" {
    const gpa = testing.allocator;

    var b = Mir.Builder.init(gpa);
    defer b.deinit();
    const entry = try b.addBlock();
    const v = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = v } });

    // What lowering hands over, built by hand: the symbol is the module's and
    // so is the layout table. A constructor that lent either a static instead
    // would have `deinit` free storage it does not own, which is a fault the
    // allocator behind this test reports and an arena hides.
    const functions = try gpa.alloc(Mir, 1);
    functions[0] = try b.finish(entry, .from(0));
    const names = try gpa.alloc([]const u8, 1);
    names[0] = try gpa.dupe(u8, "main");

    const statics = try gpa.alloc(Static, 1);
    statics[0] = .{ .ty = .u8, .parts = try gpa.dupe(StaticPart, &.{.{ .offset = 0, .ty = .u8, .value = .{ .constant = 7 } }}) };

    var module: Module = .{
        .functions = functions,
        .bytes = &.{},
        .statics = statics,
        .external = try gpa.dupe(bool, &.{false}),
        .names = names,
        .origins = &.{},
        .layouts = try gpa.dupe(Layout, &.{Layout.scalar}),
        .entry = FunctionId.at(0),
    };
    module.deinit(gpa);
}

comptime {
    _ = Mir;
}
