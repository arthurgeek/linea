const std = @import("std");
const tracy = @import("../support/tracy.zig");
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const diagnostic = @import("../diagnostics/diagnostic.zig");
const Label = diagnostic.Label;
const Sink = @import("../diagnostics/sink.zig").Sink;
const types_mod = @import("../sema/types.zig");
const TypeId = types_mod.TypeId;
const Layout = types_mod.Layout;

// Reached by the fuzz target at the end of this file and by nothing else, which
// is why they sit apart from what the pass consumes: the property is about what
// lowering hands this pass, so it has to run the passes that produce one.
const Source = @import("../support/source.zig").Source;
const Interner = @import("../support/interner.zig").Interner;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const resolveTree = @import("../sema/resolve.zig").resolveTree;
const typecheckTree = @import("../sema/typecheck.zig").typecheckTree;
const checkOwnershipTree = @import("../ownership/check.zig").checkTree;
const lowerTree = @import("lower.zig").lowerTree;
const generate = @import("../conformance/generate.zig");

const mir_mod = @import("mir.zig");
const Mir = mir_mod.Mir;
const Module = mir_mod.Module;
const InstId = mir_mod.InstId;
const BlockId = mir_mod.BlockId;
const LocalId = mir_mod.LocalId;
const FunctionId = mir_mod.FunctionId;
const storage_mod = @import("storage.zig");
const node = @import("../syntax/node.zig");

/// What every violation says about itself, once rather than at each site.
///
/// A user cannot provoke one of these: everything reaching here has already
/// been accepted by every rule the language states, so the program in front of
/// the reader is not what is wrong.
const defect_note = "report this as a compiler bug: the program is well formed and no code was generated";

/// Whether a module is what emitting it assumes, reporting whatever it is not.
///
/// The checks are all relative to the layout table and the type pool the module
/// carries. Nothing here works out how wide a slot is or where a field begins:
/// those are answered once, above, and restating either would make this a
/// second copy of the emitter that drifts from it silently -- the failure this
/// pass exists to prevent, one level down.
///
/// Allocates from the allocator it is handed, holds nothing between calls and
/// frees everything on the way out.
pub fn verify(
    gpa: std.mem.Allocator,
    module: *const Module,
    sink: *Sink,
) std.mem.Allocator.Error!bool {
    const zone = tracy.beginZone(@src(), "verify");
    defer zone.end();

    // Before any function is walked, because naming one in a message reads its
    // symbol: a table shorter than the function list would be a read past the
    // end from inside the pass that exists to catch reads past the end.
    if (module.names.len < module.functions.len) {
        try sink.add(.{
            .severity = .err,
            .message = try std.fmt.allocPrint(
                sink.arena,
                "compiler defect: the module holds {d} function(s) and {d} symbol(s)",
                .{ module.functions.len, module.names.len },
            ),
            .notes = &.{defect_note},
        });
        return false;
    }

    // Establish complete coverage before any function reads its definition flag.
    if (module.external.len != module.functions.len) {
        try sink.add(.{
            .severity = .err,
            .message = try std.fmt.allocPrint(
                sink.arena,
                "compiler defect: the module holds {d} function(s) and says where {d} of them are defined",
                .{ module.functions.len, module.external.len },
            ),
            .notes = &.{defect_note},
        });
        return false;
    }

    // O(type_count) once per module. Every later representation read is keyed
    // by a type handle, so exact coverage and exact derivation are established
    // before any function can index the table.
    const type_count = module.types.pool.len;
    if (module.layouts.len != type_count or module.representations.len() != type_count) {
        try sink.add(.{
            .severity = .err,
            .message = try std.fmt.allocPrint(
                sink.arena,
                "compiler defect: the module holds {d} type(s), {d} layout(s), and {d} representation(s) for them",
                .{ type_count, module.layouts.len, module.representations.len() },
            ),
            .notes = &.{defect_note},
        });
        return false;
    }

    var expected_representations = try mir_mod.deriveRepresentations(gpa, &module.types, module.layouts);
    defer expected_representations.deinit(gpa);
    var representations = module.representations.pairs();
    while (representations.next()) |row| {
        const want = expected_representations.get(row.id);
        if (std.meta.eql(row.value, want)) continue;
        try sink.add(.{
            .severity = .err,
            .message = try std.fmt.allocPrint(
                sink.arena,
                "compiler defect: type {d} has a representation that does not match its type and layout",
                .{row.id.index()},
            ),
            .notes = &.{defect_note},
        });
        return false;
    }

    if (!try verifyStatics(module, sink)) return false;

    // One symbol names one function. Emitting is what pairs the two, and
    // nothing between the checker and the assembler looked: two functions
    // under one name is a well-formed module by every other rule here, so the
    // program reached `cc` and died there -- reported as an I/O failure,
    // because a tool the compiler shells out to failing is the only thing that
    // status can mean. A module the backend must not emit has a status of its
    // own, and this is one.
    //
    // The list is the instantiations rather than the functions anyone wrote,
    // so its length is whatever monomorphisation produced and a generic module
    // reaches tens of thousands of them. A map keyed by the symbol answers in
    // one pass, and it is not a second answer to anything: whether two symbols
    // are equal is still `std.mem.eql`, asked once per name rather than once
    // per pair.
    //
    // The first `functions.len` entries and no further: the check above admits
    // a longer table, and an entry past the last function names nothing.
    const z_symbols = tracy.beginZone(@src(), "verify.symbols");
    const symbols = module.names[0..module.functions.len];

    var first: std.StringHashMapUnmanaged(usize) = .empty;
    defer first.deinit(gpa);
    try first.ensureTotalCapacity(gpa, @intCast(symbols.len));

    // The pair an all-pairs walk would have reached: least index, and least
    // partner for that index. A duplicate found late can still name an earlier
    // function, so the whole list is read before one is reported.
    var clash: ?struct { first: usize, again: usize } = null;
    for (symbols, 0..) |name, j| {
        const seen = first.getOrPutAssumeCapacity(name);
        if (!seen.found_existing) {
            seen.value_ptr.* = j;
            continue;
        }
        const i = seen.value_ptr.*;
        if (clash == null or i < clash.?.first) clash = .{ .first = i, .again = j };
    }

    if (clash) |at| {
        try sink.add(.{
            .severity = .err,
            .message = try std.fmt.allocPrint(
                sink.arena,
                "compiler defect: function {d} and function {d} are both named `{s}`",
                .{ at.first, at.again, symbols[at.first] },
            ),
            .notes = &.{defect_note},
        });
        return false;
    }

    var ok = true;
    z_symbols.end();

    const z_fns = tracy.beginZone(@src(), "verify.functions");
    defer z_fns.end();
    for (module.functions, 0..) |*f, i| {
        var v: Function = .{
            .gpa = gpa,
            .module = module,
            .sink = sink,
            .mir = f,
            .id = FunctionId.at(@intCast(i)),
        };
        if (!try v.verify()) ok = false;
    }
    if (!ok or module.zeroed_allocator == .none) return ok;
    const allocator = module.zeroed_allocator;
    const valid = valid: {
        if (allocator.index() >= module.functions.len or !module.isExternal(allocator)) break :valid false;
        const function = module.functionOf(allocator);
        const signature = module.types.get(function.signature).callable;
        if (signature.result != .u64 or signature.param_count != 2) break :valid false;
        for (module.types.callableParams(signature)) |param| {
            if (param.ty != .u64 or param.convention != .read or param.default != .absent) break :valid false;
        }
        break :valid true;
    };
    if (!valid) {
        try sink.add(.{
            .severity = .err,
            .message = "compiler defect: zeroed allocator metadata does not name an external two-word allocator",
            .notes = &.{defect_note},
        });
        return false;
    }
    return true;
}

/// Whether every static is data the backend can write as its type lays it out.
///
/// Each part is a scalar placed where a store of its type could be placed, so
/// a load or a borrow through the static reads what its type says is there.
/// Parts follow one another without overlapping, which is what lets the
/// backend write the zero bytes between them.
///
/// Coverage is not checked: bytes no part names are zero by design, which is
/// what padding, a part of no width and the payload bytes another variant
/// would use all are. So a layout that dropped a part, an enum's tag
/// included, reads as zero rather than being reported here; the corpus cases
/// that read every part of a constant back are what hold the layout walk to
/// writing each one.
///
/// **Bound:** one pass over each static's parts, and one member lookup per part.
fn verifyStatics(module: *const Module, sink: *Sink) std.mem.Allocator.Error!bool {
    const members: Members = .{ .module = module };
    for (module.statics, 0..) |entry, i| {
        if (!coversType(module, entry.ty)) return staticDefect(sink, "static {d} names type {d}, which the module does not describe", .{ i, entry.ty.index() });
        const size = module.layoutOf(entry.ty).size;
        var end: u64 = 0;
        for (entry.parts, 0..) |part, j| {
            if (!coversType(module, part.ty)) return staticDefect(sink, "static {d} part {d} names type {d}, which the module does not describe", .{ i, j, part.ty.index() });
            const width = module.layoutOf(part.ty).size;
            if (part.offset < end or @as(u64, part.offset) + width > size) {
                return staticDefect(sink, "static {d} part {d} covers {d} byte(s) at offset {d}, after byte {d} of {d}", .{ i, j, width, part.offset, end, size });
            }
            end = @as(u64, part.offset) + width;
            if (!members.isMember(entry.ty, part.offset, width)) {
                return staticDefect(sink, "static {d} part {d} at offset {d} is no part of `{s}`", .{ i, j, part.offset, module.types.nameOf(entry.ty) });
            }
            const fits = switch (module.representationOf(part.ty).storage) {
                .integer => |integer| switch (part.value) {
                    .constant => |value| fitsStorage(value, integer.signedness, integer.bits),
                    .bytes => |blob| integer.bits == 64 and blob < module.bytes.len,
                },
                .boolean => part.value == .constant and (part.value.constant == 0 or part.value.constant == 1),
                .enum_tag => part.value == .constant and part.value.constant >= 0 and part.value.constant <= std.math.maxInt(u32),
                else => false,
            };
            if (!fits) return staticDefect(sink, "static {d} part {d} holds a value `{s}` cannot store", .{ i, j, module.types.nameOf(part.ty) });
        }
    }
    return true;
}

fn fitsStorage(value: i128, signedness: mir_mod.Signedness, bits: u8) bool {
    const width: u7 = @intCast(bits);
    return switch (signedness) {
        .unsigned => value >= 0 and value < (@as(i128, 1) << width),
        .signed => value >= -(@as(i128, 1) << (width - 1)) and value < (@as(i128, 1) << (width - 1)),
    };
}

fn staticDefect(sink: *Sink, comptime fmt: []const u8, args: anytype) std.mem.Allocator.Error!bool {
    try sink.add(.{
        .severity = .err,
        .message = try std.fmt.allocPrint(sink.arena, "compiler defect: " ++ fmt, args),
        .notes = &.{defect_note},
    });
    return false;
}

/// Where an address came from, and how far into that object it points.
///
/// MIR admits exactly five provenances, so this is an exact domain rather than
/// an approximation of one: the language has no arrays and lowering emits every
/// field offset as a constant, so every address is the address of one object
/// plus a number known here.
///
/// It is a domain over *values*, never over syntax. A field at offset zero is
/// the address it is reached from and the emitter writes nothing for it, so a
/// place is what an instruction produces rather than what an instruction is.
const Place = union(enum) {
    /// Not an address, or one this pass cannot attribute.
    none,
    /// A slot in this frame.
    slot: At,
    /// An object reached through an indirect parameter, which belongs to a
    /// caller.
    lent: At,
    /// The aggregate a callee returned.
    returned: TypedAt,
    /// One concrete element in checked heap storage.
    heap: TypedAt,
    /// Read-only data the module carries. Nothing may write here.
    static: TypedAt,

    const At = struct { local: LocalId, off: u32 };
    const TypedAt = struct { ty: TypeId, off: u32 };

    /// The same object, further in. Saturating, because a constant this pass
    /// found out of range is already reported and must not wrap into one that
    /// looks in bounds.
    fn shifted(self: Place, by: u32) Place {
        return switch (self) {
            .none => .none,
            .slot => |p| .{ .slot = .{ .local = p.local, .off = p.off +| by } },
            .lent => |p| .{ .lent = .{ .local = p.local, .off = p.off +| by } },
            .returned => |p| .{ .returned = .{ .ty = p.ty, .off = p.off +| by } },
            .heap => |p| .{ .heap = .{ .ty = p.ty, .off = p.off +| by } },
            .static => |p| .{ .static = .{ .ty = p.ty, .off = p.off +| by } },
        };
    }

    fn offset(self: Place) u32 {
        return switch (self) {
            .none => 0,
            .slot, .lent => |p| p.off,
            .returned, .heap, .static => |p| p.off,
        };
    }

    fn isStatic(self: Place) bool {
        return switch (self) {
            .static => true,
            else => false,
        };
    }

    fn isSlot(self: Place) bool {
        return switch (self) {
            .slot => true,
            else => false,
        };
    }

    fn describe(self: Place) []const u8 {
        return switch (self) {
            .none => "an address of unknown provenance",
            .slot => "a slot in this frame",
            .lent => "an object a caller lent",
            .returned => "an aggregate a callee returned",
            .heap => "a checked heap element",
            .static => "read-only data the module carries",
        };
    }
};

/// How many computed index steps in a row an address records.
pub const max_computed_steps = 3;

/// One computed index step: the array it indexed sits `at` bytes into the
/// element the step before it chose (into `origin` for the first step),
/// holds `extent` bytes, and each of its elements is `elem` bytes.
pub const Step = struct { at: u32 = 0, extent: u32 = 0, elem: u32 = 0 };

/// What an address instruction was formed from, as one walk answers it for
/// every phase: the place its constant steps reach, how far a computed step
/// may have moved it inside that place, and the value a read through it reads
/// the dependencies of.
pub const Address = struct {
    /// The place the constant steps reach; `.none` where the address is not
    /// attributed.
    origin: Place = .none,
    /// The computed steps that moved the address, outermost first, and how
    /// many there are. Then `origin` stays at the array the first step
    /// indexed and the address is one of the set `origin + k0 * elem0 + at1 +
    /// k1 * elem1 + ... + inner`, which is not exact. A step past
    /// `max_computed_steps` is taken at element zero, which covers fewer
    /// bytes than ownership counts and so refuses nothing it does not.
    steps: [max_computed_steps]Step = [_]Step{.{}} ** max_computed_steps,
    depth: u8 = 0,
    /// The offset the constant steps after the last computed one reached
    /// inside its element.
    inner: u32 = 0,
    /// The slot or value whose dependencies a read through the address uses.
    carrier: Carrier = .none,
    /// A constant step that does not fit an offset, which the access rules
    /// report.
    malformed: bool = false,

    pub const Carrier = union(enum) { none, slot: LocalId, inst: InstId };

    /// Whether a computed step moved the address.
    pub fn computed(self: Address) bool {
        return self.depth != 0;
    }

    /// The exact place, which a computed address does not have.
    pub fn place(self: Address) Place {
        return if (self.computed()) .none else self.origin;
    }
};

/// The attribution of every value, in one forward pass: an operand is created
/// before the instruction that reads it, so a value's own handle is greater
/// than every handle it was computed from. A slot holding an address yields
/// that address rather than what is in it, which is how an indirect parameter
/// is read; a value too wide for a register comes back as the address of
/// storage the caller owns; the checked value carries on under the check's
/// own name; a computed step keeps the constant prefix and lands somewhere
/// inside the aggregate the base addresses.
pub fn attribute(module: *const Module, mir: *const Mir, out: []Address) void {
    @memset(out, .{});
    for (0..mir.insts.len) |i| {
        const id = InstId.at(@intCast(i));
        out[i] = switch (mir.tagOf(id)) {
            .addr_of => .{ .origin = .{ .slot = .{ .local = mir.localOf(id), .off = 0 } }, .carrier = .{ .slot = mir.localOf(id) } },
            .observe => .{ .origin = .{ .heap = .{ .ty = mir.typeOf(id), .off = 0 } }, .carrier = .{ .inst = mir.unaryOf(id) } },
            .storage_addr => .{ .origin = .{ .heap = .{ .ty = mir.typeOf(id), .off = 0 } }, .carrier = .{ .inst = id } },
            .static_addr => .{ .origin = .{ .static = .{ .ty = mir.typeOf(id), .off = 0 } }, .carrier = .{ .inst = id } },
            .load => blk: {
                const l = mir.localOf(id);
                if (mir.slotRoleOf(l) == .managed_address) break :blk .{ .origin = .{ .lent = .{ .local = l, .off = 0 } }, .carrier = .{ .slot = l } };
                break :blk .{ .carrier = .{ .inst = id } };
            },
            .field_addr => blk: {
                const p = mir.binaryOf(id);
                const base = out[p.lhs.index()];
                if (mir.tagOf(p.rhs) != .constant) {
                    const within = mir.typeOf(p.lhs);
                    if (!coversType(module, within) or !coversType(module, mir.typeOf(id))) break :blk .{ .carrier = base.carrier };
                    const step: Step = .{
                        .at = base.inner,
                        .extent = module.layoutOf(within).size,
                        .elem = module.layoutOf(mir.typeOf(id)).size,
                    };
                    var stepped = base;
                    if (base.depth == 0) {
                        stepped.steps[0] = .{ .extent = step.extent, .elem = step.elem };
                        stepped.depth = 1;
                    } else if (base.depth < max_computed_steps and step.elem != 0 and step.extent != 0) {
                        stepped.steps[base.depth] = step;
                        stepped.depth += 1;
                        stepped.inner = 0;
                    }
                    break :blk stepped;
                }
                const written = mir.constantOf(p.rhs);
                if (written < 0 or written > std.math.maxInt(u32)) break :blk .{ .carrier = base.carrier, .malformed = true };
                if (base.computed()) {
                    var stepped = base;
                    stepped.inner +|= @intCast(written);
                    break :blk stepped;
                }
                break :blk .{ .origin = base.origin.shifted(@intCast(written)), .carrier = base.carrier };
            },
            .call => blk: {
                const c = mir.callOf(id);
                // The module's answer, for the reason `escapes` takes it: a
                // check that computes the convention itself is a second
                // opinion about the one thing it is not entitled to have one
                // about.
                if (!coversType(module, module.functionOf(c.func).return_type)) break :blk .{ .carrier = .{ .inst = id } };
                if (!module.returnsIndirectly(c.func)) break :blk .{ .carrier = .{ .inst = id } };
                break :blk .{ .origin = .{ .returned = .{ .ty = module.functionOf(c.func).return_type, .off = 0 } }, .carrier = .{ .inst = id } };
            },
            .call_indirect => blk: {
                if (!module.indirectReturnsByAddress(mir, id)) break :blk .{ .carrier = .{ .inst = id } };
                break :blk .{ .origin = .{ .returned = .{ .ty = module.indirectSignatureOf(mir, id).result, .off = 0 } }, .carrier = .{ .inst = id } };
            },
            .check => out[mir.checkOf(id).value.index()],
            else => .{ .carrier = .{ .inst = id } },
        };
    }
}

/// Whether every table a type handle indexes holds an entry for it.
fn coversType(module: *const Module, t: TypeId) bool {
    const at = @intFromEnum(t);
    return at < module.layouts.len and
        at < module.representations.len() and
        at < module.types.pool.len;
}

/// Which offsets of a type are parts of it, read from the module's own type
/// table. Shared by the per-function access checks and the check of each
/// static's parts, so one answer says what a part is.
const Members = struct {
    module: *const Module,

    /// Whether a run of bytes is a part of a type, or the whole of it.
    ///
    /// Reads the module's own pool for which parts exist and where, so the
    /// number compared against is the one the constant in the instruction was
    /// supposed to have been taken from.
    fn isMember(self: Members, declared: TypeId, off: u32, width: u32) bool {
        // A newtype has the same parts and offsets as its base.
        const container = self.module.types.erased(declared);
        const whole = self.module.layoutOf(container);
        if (off == 0 and width == whole.size) return true;

        // Not an aggregate: it has no parts, so the whole of it is the only
        // access there is.
        if (!whole.isAggregate()) return false;

        const types = &self.module.types;
        return switch (types.get(container)) {
            .struct_, .closure => blk: {
                // A run is placed at non-decreasing offsets, so the field that
                // could hold this access is the last one starting at or before
                // it -- found rather than walked, because this is asked once
                // per indirect access and a type may have as many fields as
                // someone writes.
                const count = types.fieldCount(container);
                var lo: u32 = 0;
                var hi: u32 = count;
                while (lo < hi) {
                    const mid = lo + (hi - lo) / 2;
                    if (types.fieldOffset(container, mid) <= off) lo = mid + 1 else hi = mid;
                }
                // Backwards over the ones sharing that offset: a part of no
                // width takes none, so several may begin where one does.
                var at = lo;
                while (at > 0) {
                    at -= 1;
                    const start = types.fieldOffset(container, at);
                    if (self.partHolds(types.fieldType(container, at), start, off, width)) {
                        break :blk true;
                    }
                    if (start != off) break;
                }
                break :blk false;
            },
            // Every element is the same shape at the same spacing, so an offset
            // is part of one exactly when it lands inside a stride and the
            // stride it lands in is one an element occupies.
            //
            // A run of whole elements is a part of an array as well, because a
            // range names one: `a[1..3]` is a single place of two elements, and
            // the copy or the write reaching it moves both at once. Admitted by
            // its shape rather than by a mark on the instruction, which widens
            // what this accepts by exactly the accesses that begin at an
            // element and end at one.
            //
            // What that costs, stated rather than left to be discovered. Where
            // the stride is one -- every `[UInt8; N]`, which is what the text
            // and rendering paths move -- both tests are vacuous and this
            // arrives at the extent check alone: any offset, any width, in
            // bounds, passes. An access of no width at an element boundary
            // passes too. So over a byte array this says the access is inside
            // the object and nothing further, and the sharpness is bought back
            // only by marking the access in MIR, which is the same trade the
            // three exemptions above are held to.
            .array => |a| blk: {
                const stride = types.strideOf(a.element);
                if (stride == 0 or a.count == 0) break :blk false;
                const which = off / stride;
                if (which >= a.count) break :blk false;
                if (self.partHolds(a.element, @intCast(which * stride), off, width)) break :blk true;
                break :blk off % stride == 0 and width % stride == 0 and
                    off + width <= a.count * stride;
            },
            .enum_ => blk: {
                // The tag occupies a full word at the front, and every variant
                // is overlaid behind it. Each variant's payload is one
                // non-decreasing placed run, so find the only field offset
                // that could contain the access instead of scanning every
                // payload for every indirect access. This costs one binary
                // search per variant, at most the language's 64 variants,
                // rather than fields-per-variant work per access.
                if (off == 0 and width == Layout.tag_width) break :blk true;
                for (0..types.variantCount(container)) |variant| {
                    const v: u32 = @intCast(variant);
                    const count = types.variantFieldCount(container, v);
                    var lo: u32 = 0;
                    var hi = count;
                    while (lo < hi) {
                        const mid = lo + (hi - lo) / 2;
                        if (types.variantFieldOffset(container, v, mid) <= off) lo = mid + 1 else hi = mid;
                    }
                    var field = lo;
                    while (field > 0) {
                        field -= 1;
                        const start = types.variantFieldOffset(container, v, field);
                        if (self.partHolds(
                            types.variantFieldType(container, v, field),
                            start,
                            off,
                            width,
                        )) break :blk true;
                        if (start != off) break;
                    }
                }
                break :blk false;
            },
            else => false,
        };
    }

    /// Whether an offset names this exact type, rather than only a part with
    /// the same width. Code-pointer field addresses need the stronger answer:
    /// every structural signature occupies one word, as do unrelated scalars.
    fn hasMemberOfType(self: Members, declared: TypeId, off: u32, want: TypeId) bool {
        const container = self.module.types.erased(declared);
        if (off == 0 and container == want) return true;
        if (off == 0) switch (self.module.types.get(container)) {
            .closure => |closure| if (closure.environment == want) return true,
            else => {},
        };
        if (!self.module.layoutOf(container).isAggregate()) return false;

        const types = &self.module.types;
        return switch (types.get(container)) {
            .struct_, .closure => blk: {
                const count = types.fieldCount(container);
                var lo: u32 = 0;
                var hi: u32 = count;
                while (lo < hi) {
                    const mid = lo + (hi - lo) / 2;
                    if (types.fieldOffset(container, mid) <= off) lo = mid + 1 else hi = mid;
                }
                var at = lo;
                while (at > 0) {
                    at -= 1;
                    const start = types.fieldOffset(container, at);
                    if (self.hasMemberOfType(types.fieldType(container, at), off - start, want)) break :blk true;
                    if (start != off) break;
                }
                break :blk false;
            },
            .array => |array| blk: {
                const stride = types.strideOf(array.element);
                if (stride == 0 or array.count == 0) break :blk false;
                const which = off / stride;
                if (which >= array.count) break :blk false;
                break :blk self.hasMemberOfType(array.element, off - @as(u32, @intCast(which * stride)), want);
            },
            .enum_ => blk: {
                // Each variant's trusted placement is non-decreasing and its
                // nonempty fields do not overlap. A code pointer occupies a
                // word, so only the last field starting at or before `off`
                // can contain it. Equal-offset empty fields precede a nonempty
                // field at that offset; trailing empty fields contain no word.
                // One binary search and recursive candidate per variant.
                for (0..types.variantCount(container)) |variant| {
                    const v: u32 = @intCast(variant);
                    var lo: u32 = 0;
                    var hi = types.variantFieldCount(container, v);
                    while (lo < hi) {
                        const mid = lo + (hi - lo) / 2;
                        if (types.variantFieldOffset(container, v, mid) <= off) lo = mid + 1 else hi = mid;
                    }
                    if (lo == 0) continue;
                    const field = lo - 1;
                    const start = types.variantFieldOffset(container, v, field);
                    if (self.hasMemberOfType(types.variantFieldType(container, v, field), off - start, want)) break :blk true;
                }
                break :blk false;
            },
            else => false,
        };
    }

    /// Whether one part accounts for an access: it is that part exactly, or it
    /// lies inside a part that has parts of its own.
    fn partHolds(
        self: Members,
        part: TypeId,
        at: u32,
        off: u32,
        width: u32,
    ) bool {
        if (!coversType(self.module, part)) return false;
        const l = self.module.layoutOf(part);
        if (off == at and width == l.size) return true;
        if (off < at or off - at >= l.size) return false;
        return self.isMember(part, off - at, width);
    }
};

/// One function's worth of checking. Per function rather than per module
/// because every table a check reads is the function's own.
const Function = struct {
    gpa: std.mem.Allocator,
    module: *const Module,
    sink: *Sink,
    mir: *const Mir,
    id: FunctionId,
    ok: bool = true,
    locations: []const Location = &.{},

    const Location = struct {
        block: u32 = std.math.maxInt(u32),
        order: u32 = std.math.maxInt(u32),
    };

    fn verify(self: *Function) std.mem.Allocator.Error!bool {
        // In this order, and each one gates the next. Type coverage is safe to
        // enumerate without following an operand, and it must precede the
        // representation comparisons made while references are checked.
        // Nothing below may index a table with a handle no earlier phase
        // established: a verifier that reads past an array is a defect in the
        // pass that reports defects.
        if (!try self.cover()) return false;
        if (!try self.references()) return false;
        if (!try self.verifySignature()) return false;

        const locations = try self.gpa.alloc(Location, self.mir.insts.len);
        defer self.gpa.free(locations);
        @memset(locations, .{});
        for (0..self.mir.blocks.len) |i| {
            const block = BlockId.at(@intCast(i));
            for (self.mir.instsOf(block), 0..) |id, order| locations[id.index()] = .{
                .block = @intCast(i),
                .order = @intCast(order),
            };
            const terminator = self.mir.terminatorOf(block);
            locations[terminator.index()] = .{
                .block = @intCast(i),
                .order = @intCast(self.mir.instsOf(block).len),
            };
        }
        self.locations = locations;
        defer self.locations = &.{};

        if (!try self.roles()) return false;

        const addresses = try self.gpa.alloc(Address, self.mir.insts.len);
        defer self.gpa.free(addresses);
        const places = try self.gpa.alloc(Place, self.mir.insts.len);
        defer self.gpa.free(places);
        try self.provenance(addresses, places);
        try self.accesses(places);
        try self.escapes(places);
        // An external function's body is a declaration-only stub and is never
        // emitted. Its poison result says no implementation exists here; the
        // callable signature carries the foreign declaration's result type.
        if (!self.module.isExternal(self.id)) {
            try self.liveValues();
            // Last, because it indexes what every phase above established:
            // every handle lands, every slot has a role, every call names a
            // function whose signature the module describes.
            if (self.ok and !try storage_mod.Phase.run(self.gpa, self.module, self.mir, self.id, addresses, self.sink)) self.ok = false;
        }
        return self.ok;
    }

    fn name(self: *const Function) []const u8 {
        return self.module.nameOf(self.id);
    }

    /// A violation, named where it is and pointed at where it came from.
    ///
    /// Without a rule code: every code is an index into the semantics
    /// document, a test refuses one the document does not define, and no
    /// program can provoke what is reported here. What identifies the failure
    /// is the function and the instruction, and what a reader needs is to be
    /// told plainly whose fault it is.
    fn report(
        self: *Function,
        span: Span,
        comptime fmt: []const u8,
        args: anytype,
    ) std.mem.Allocator.Error!void {
        const arena = self.sink.arena;
        const labels = try arena.alloc(Label, 1);
        labels[0] = .{
            .file = self.mir.file,
            .span = span,
            .message = "the code generated from here would not be what this says",
            .style = .primary,
        };
        try self.said(labels, fmt, args);
    }

    /// Where a violation with no instruction behind it is reported: the
    /// function's own shape, which has no span of its own to point at.
    fn reportFunction(
        self: *Function,
        comptime fmt: []const u8,
        args: anytype,
    ) std.mem.Allocator.Error!void {
        try self.said(&.{}, fmt, args);
    }

    fn said(
        self: *Function,
        labels: []const Label,
        comptime fmt: []const u8,
        args: anytype,
    ) std.mem.Allocator.Error!void {
        self.ok = false;
        const arena = self.sink.arena;
        const what = try std.fmt.allocPrint(arena, fmt, args);
        try self.sink.add(.{
            .severity = .err,
            .message = try std.fmt.allocPrint(
                arena,
                "compiler defect: in `{s}`, {s}",
                .{ self.name(), what },
            ),
            .labels = labels,
            .notes = &.{defect_note},
        });
    }

    // -- Phase one: every reference lands somewhere, and every block ends. --

    fn instInRange(self: *const Function, i: InstId) bool {
        return i != InstId.none and i.index() < self.mir.insts.len;
    }

    /// Checks that every handle a function holds names something, and that
    /// every block ends in exactly one terminator with none in the middle.
    ///
    /// This is what replaces the assertions the distributed build deletes.
    /// With them gone the emitter indexes an instruction array at the sentinel
    /// and prints whatever it finds.
    fn references(self: *Function) std.mem.Allocator.Error!bool {
        const mir = self.mir;

        if (mir.entry.index() >= mir.blocks.len) {
            try self.reportFunction(
                "control enters at block {d}, and the function has {d}",
                .{ mir.entry.index(), mir.blocks.len },
            );
            return false;
        }

        if (mir.param_count > mir.locals.len) {
            try self.reportFunction(
                "there are {d} parameter(s) and {d} slot(s) to hold them",
                .{ mir.param_count, mir.locals.len },
            );
            return false;
        }

        if (mir.slot_roles.len != mir.locals.len) {
            try self.reportFunction(
                "there are {d} slot(s) and {d} slot role(s)",
                .{ mir.locals.len, mir.slot_roles.len },
            );
            return false;
        }

        for (mir.blocks, 0..) |blk, i| {
            if (blk.start > blk.end or blk.end > mir.block_insts.len) {
                try self.reportFunction(
                    "block {d} spans {d}..{d} of {d} instruction slot(s)",
                    .{ i, blk.start, blk.end, mir.block_insts.len },
                );
                return false;
            }

            if (!self.instInRange(blk.terminator)) {
                try self.reportFunction("block {d} does not end", .{i});
                return false;
            }
            if (!mir.tagOf(blk.terminator).isTerminator()) {
                try self.reportFunction(
                    "block {d} ends in {s}, which does not end a block",
                    .{ i, @tagName(mir.tagOf(blk.terminator)) },
                );
                return false;
            }

            for (mir.block_insts[blk.start..blk.end]) |id| {
                if (!self.instInRange(id)) {
                    try self.reportFunction(
                        "block {d} holds instruction {d}, and the function has {d}",
                        .{ i, id.index(), mir.insts.len },
                    );
                    return false;
                }
                if (mir.tagOf(id).isTerminator()) {
                    try self.reportFunction(
                        "block {d} holds {s} before its end",
                        .{ i, @tagName(mir.tagOf(id)) },
                    );
                    return false;
                }
            }
        }

        for (0..mir.insts.len) |i| {
            if (!try self.operands(InstId.at(@intCast(i)))) return false;
        }
        return true;
    }

    fn operands(self: *Function, id: InstId) std.mem.Allocator.Error!bool {
        const mir = self.mir;
        const span = mir.spanOf(id);

        switch (mir.tagOf(id).payload()) {
            .constant => {},
            .trap => {
                const message = mir.trapOf(id).message;
                if (message != .none and !try self.operandInRange(id, message)) return false;
            },
            .bytes => if (!try self.bytesInRange(id, mir.bytesOf(id))) return false,
            .static => if (!try self.staticNamed(id, mir.staticOf(id))) return false,
            .local => if (!try self.localInRange(id, mir.localOf(id))) return false,
            .store => {
                const s = mir.storeOf(id);
                if (!try self.localInRange(id, s.local)) return false;
                if (!try self.operandInRange(id, s.value)) return false;
            },
            .unary => {
                const operand = mir.unaryOf(id);
                if (!try self.operandInRange(id, operand)) return false;
                switch (mir.tagOf(id)) {
                    .address_bits => {
                        if (mir.typeOf(id) != .u64 or mir.resultRoleOf(id) != .value or mir.resultRoleOf(operand) != .managed_address) {
                            try self.report(span, "%{d} requires a managed storage address and a UInt64 result", .{id.index()});
                            return false;
                        }
                    },
                    .borrow, .observe => |tag| {
                        const pointer = if (tag == .borrow) id else operand;
                        const address = if (tag == .borrow) operand else id;
                        const pointer_ty = self.module.types.get(mir.typeOf(pointer));
                        // A newtype is represented by its base, so the address
                        // a borrow of one observes is typed by that base.
                        if (pointer_ty != .borrow or self.module.types.erased(pointer_ty.borrow.referent) != mir.typeOf(address) or
                            mir.resultRoleOf(pointer) != .value or mir.resultRoleOf(address) != .managed_address)
                        {
                            try self.report(span, "%{d} has an invalid observation projection", .{id.index()});
                            return false;
                        }
                    },
                    .neg => if (!try self.sameComputation(id, operand)) return false,
                    .int_to_float => {
                        if (!isFloat(self.module.resultRepresentationOf(mir, id)) or
                            !isInteger(self.module.resultRepresentationOf(mir, operand)))
                        {
                            try self.report(span, "%{d} converts something other than an integer to Float64", .{id.index()});
                            return false;
                        }
                    },
                    .float_to_int => {
                        if (!isInteger(self.module.resultRepresentationOf(mir, id)) or
                            !isFloat(self.module.resultRepresentationOf(mir, operand)))
                        {
                            try self.report(span, "%{d} converts something other than Float64 to an integer", .{id.index()});
                            return false;
                        }
                    },
                    else => {},
                }
            },
            .float_math => {
                const math = mir.floatMathOf(id);
                if (!try self.operandInRange(id, math.lhs)) return false;
                if (mir.typeOf(id) != .f64 or mir.typeOf(math.lhs) != .f64 or
                    mir.resultRoleOf(id) != .value or mir.resultRoleOf(math.lhs) != .value)
                {
                    try self.report(span, "%{d} requires Float64 math operands and result values", .{id.index()});
                    return false;
                }
                if (math.operation.arity() == 1) {
                    if (math.rhs != .none) {
                        try self.report(span, "%{d} gives a unary math operation a second operand", .{id.index()});
                        return false;
                    }
                } else {
                    if (!try self.operandInRange(id, math.rhs)) return false;
                    if (mir.typeOf(math.rhs) != .f64 or mir.resultRoleOf(math.rhs) != .value) {
                        try self.report(span, "%{d} requires a Float64 exponent value", .{id.index()});
                        return false;
                    }
                }
            },
            .binary => {
                const p = mir.binaryOf(id);
                if (!try self.operandInRange(id, p.lhs)) return false;
                if (!try self.operandInRange(id, p.rhs)) return false;

                // Arithmetic and comparison take operands with matching
                // recorded result representations. A mismatched pair is
                // refused here while the report can name the instruction.
                switch (mir.tagOf(id)) {
                    .add, .sub, .mul, .div, .rem => {
                        const want = self.module.resultRepresentationOf(mir, id);
                        if (!sameResultType(self.module.resultRepresentationOf(mir, p.lhs), want) or
                            !sameResultType(self.module.resultRepresentationOf(mir, p.rhs), want))
                        {
                            try self.report(span, "%{d} mixes computation representations", .{id.index()});
                            return false;
                        }
                    },
                    .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => {
                        if (!sameResultType(
                            self.module.resultRepresentationOf(mir, p.lhs),
                            self.module.resultRepresentationOf(mir, p.rhs),
                        )) {
                            try self.report(span, "%{d} compares across computation representations", .{id.index()});
                            return false;
                        }
                        if (!isBoolean(self.module.resultRepresentationOf(mir, id))) {
                            try self.report(span, "%{d} comparison does not produce Boolean computation", .{id.index()});
                            return false;
                        }
                    },
                    else => {},
                }
            },
            .raw_access => {
                if (!mir.rawAccessDataInRange(id)) {
                    try self.report(span, "%{d} raw access metadata is out of range", .{id.index()});
                    return false;
                }
                const raw = mir.rawAccessOf(id);
                if (!try self.operandInRange(id, raw.address)) return false;
                if (raw.length != .none and !try self.operandInRange(id, raw.length)) return false;
                if (mir.tagOf(id) == .store_raw and !try self.operandInRange(id, raw.value)) return false;
                if (raw.overflow_check != .none and !try self.operandInRange(id, raw.overflow_check)) return false;
                if (raw.bounds_check != .none and !try self.operandInRange(id, raw.bounds_check)) return false;
                if (raw.alignment_check != .none and !try self.operandInRange(id, raw.alignment_check)) return false;
            },
            .check => {
                const c = mir.checkOf(id);
                if (!try self.operandInRange(id, c.value)) return false;
                const computation = self.module.resultRepresentationOf(mir, id);
                const operand = self.module.resultRepresentationOf(mir, c.value);
                const allowed = switch (c.kind) {
                    .division_by_zero, .overflow, .conversion_out_of_range => isInteger(computation) and isInteger(operand),
                    .index_out_of_bounds, .misaligned_access => isBoolean(computation) and isBoolean(operand),
                    .unreachable_reached, .assertion_failed, .panic, .not_a_number => false,
                };
                if (!allowed) {
                    try self.report(span, "%{d} checks a non-integer value for {s}", .{ id.index(), @tagName(c.kind) });
                    return false;
                }
            },
            .call => {
                const c = mir.insts.items(.data)[id.index()].call;
                const at = c.args.index();
                if (at >= mir.extra.len) {
                    try self.report(span, "%{d} keeps its arguments at {d} of {d}", .{
                        id.index(), at, mir.extra.len,
                    });
                    return false;
                }
                const n = mir.extra[at].index();
                if (at + 1 + n > mir.extra.len) {
                    try self.report(span, "%{d} passes {d} argument(s), and {d} follow", .{
                        id.index(), n, mir.extra.len - at - 1,
                    });
                    return false;
                }
                if (c.func.index() >= self.module.functions.len) {
                    try self.report(span, "%{d} calls function {d}, and the module has {d}", .{
                        id.index(), c.func.index(), self.module.functions.len,
                    });
                    return false;
                }
                if (!self.covers(self.module.functionOf(c.func).return_type)) {
                    try self.report(span, "%{d} call target result type is out of range", .{id.index()});
                    return false;
                }
                for (mir.extra[at + 1 ..][0..n]) |a| {
                    if (!try self.operandInRange(id, a)) return false;
                }
            },
            .function => {
                const function = mir.functionOf(id);
                if (function.index() >= self.module.functions.len) {
                    try self.report(span, "%{d} names function {d}, and the module has {d}", .{
                        id.index(), function.index(), self.module.functions.len,
                    });
                    return false;
                }
                if (self.module.representationOf(mir.typeOf(id)).computation != .code_pointer) {
                    try self.report(span, "%{d} does not produce a code pointer", .{id.index()});
                    return false;
                }
                if (!self.module.types.callableConverts(self.module.functionOf(function).signature, mir.typeOf(id))) {
                    try self.report(span, "%{d} signature differs from function {d}", .{ id.index(), function.index() });
                    return false;
                }
            },
            .indirect_call => {
                if (!mir.indirectCallDataInRange(id)) {
                    try self.report(span, "%{d} indirect call metadata is out of range", .{id.index()});
                    return false;
                }
                const call = mir.indirectCallOf(id);
                if (!try self.operandInRange(id, call.callee)) return false;
                if (!std.meta.eql(
                    self.module.resultRepresentationOf(mir, call.callee),
                    mir_mod.ResultRepresentation{ .computation = .code_pointer },
                )) {
                    try self.report(span, "%{d} callee is not a code pointer", .{id.index()});
                    return false;
                }
                const signature = switch (self.module.types.get(mir.typeOf(call.callee))) {
                    .callable => |signature| signature,
                    else => {
                        try self.report(span, "%{d} callee type is not a structural callable", .{id.index()});
                        return false;
                    },
                };
                if (!try self.indirectSignatureDataInRange(id, signature)) return false;
                for (call.args) |arg| {
                    if (!try self.operandInRange(id, arg)) return false;
                }
            },
            .target => if (!try self.blockInRange(id, mir.targetOf(id))) return false,
            .branch => {
                const br = mir.branchOf(id);
                if (!try self.operandInRange(id, br.cond)) return false;
                if (!try self.blockInRange(id, br.then_block)) return false;
                if (!try self.blockInRange(id, br.else_block)) return false;
            },
        }
        return try self.codePointers(id) and try self.dataPointers(id);
    }

    /// Code pointers enter MIR through `function_addr`; loads, calls, stores,
    /// arguments and returns only transport one already produced. Numeric and
    /// comparison operations cannot construct or inspect one as a number.
    fn codePointers(self: *Function, id: InstId) std.mem.Allocator.Error!bool {
        const mir = self.mir;
        const tag = mir.tagOf(id);
        const pointer_type = self.isCodePointerType(mir.typeOf(id));
        const produces_pointer = std.meta.eql(
            self.module.resultRepresentationOf(mir, id),
            mir_mod.ResultRepresentation{ .computation = .code_pointer },
        );
        switch (tag) {
            .constant, .bytes_addr => if (produces_pointer) {
                try self.report(mir.spanOf(id), "%{d} {s} cannot produce a code pointer", .{ id.index(), @tagName(tag) });
                return false;
            },
            .add, .sub, .mul, .div, .rem, .neg => if (produces_pointer) {
                try self.report(mir.spanOf(id), "%{d} cannot apply arithmetic to a code pointer", .{id.index()});
                return false;
            },
            .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => {
                const pair = mir.binaryOf(id);
                if (self.isCodePointerValue(pair.lhs) or self.isCodePointerValue(pair.rhs)) {
                    try self.report(mir.spanOf(id), "%{d} cannot compare code pointers", .{id.index()});
                    return false;
                }
            },
            .call => if (produces_pointer) {
                const result = self.module.functionOf(mir.callOf(id).func).return_type;
                if (mir.typeOf(id) != result) {
                    if (self.module.representationOf(result).computation == .code_pointer) {
                        try self.report(mir.spanOf(id), "%{d} call cannot change its code pointer signature", .{id.index()});
                    } else {
                        try self.report(mir.spanOf(id), "%{d} call cannot produce a code pointer from its result", .{id.index()});
                    }
                    return false;
                }
            },
            .addr_of => if (pointer_type and mir.typeOf(id) != mir.locals[mir.localOf(id).index()]) {
                try self.report(mir.spanOf(id), "%{d} takes a code pointer address of a different slot type", .{id.index()});
                return false;
            },
            .field_addr => if (pointer_type) {
                const pair = mir.binaryOf(id);
                if (mir.resultRoleOf(pair.lhs) != .managed_address) {
                    try self.report(mir.spanOf(id), "%{d} takes a code pointer field address through a non-address value", .{id.index()});
                    return false;
                }
                const offset = if (mir.tagOf(pair.rhs) == .constant)
                    mir.constantOf(pair.rhs)
                else
                    -1;
                const reaches = if (offset < 0)
                    self.indexesElementOfType(mir, mir.typeOf(pair.lhs), pair.rhs, mir.typeOf(id))
                else
                    offset <= std.math.maxInt(u32) and self.members().hasMemberOfType(mir.typeOf(pair.lhs), @intCast(offset), mir.typeOf(id));
                if (!reaches) {
                    try self.report(mir.spanOf(id), "%{d} takes a code pointer address of a different field type", .{id.index()});
                    return false;
                }
            },
            .load_indirect => if (produces_pointer) {
                const address = mir.unaryOf(id);
                if (mir.resultRoleOf(address) == .managed_address and mir.typeOf(address) != mir.typeOf(id)) {
                    try self.report(mir.spanOf(id), "%{d} loads a code pointer through an address of a different type", .{id.index()});
                    return false;
                }
            },
            .store_indirect => if (pointer_type) {
                const address = mir.binaryOf(id).lhs;
                if (mir.resultRoleOf(address) == .managed_address and mir.typeOf(address) != mir.typeOf(id)) {
                    try self.report(mir.spanOf(id), "%{d} stores a code pointer through an address of a different type", .{id.index()});
                    return false;
                }
            },
            .copy_value, .move_value => if (pointer_type) {
                const pair = mir.binaryOf(id);
                if (mir.resultRoleOf(pair.rhs) != .managed_address) {
                    try self.report(mir.spanOf(id), "%{d} copies a code pointer from a non-address value", .{id.index()});
                    return false;
                }
                if (mir.resultRoleOf(pair.lhs) != .managed_address) {
                    try self.report(mir.spanOf(id), "%{d} copies a code pointer into a non-address value", .{id.index()});
                    return false;
                }
                if (mir.typeOf(pair.rhs) != mir.typeOf(id)) {
                    try self.report(mir.spanOf(id), "%{d} copies a code pointer from an address of a different type", .{id.index()});
                    return false;
                }
                if (mir.typeOf(pair.lhs) != mir.typeOf(id)) {
                    try self.report(mir.spanOf(id), "%{d} copies a code pointer into an address of a different type", .{id.index()});
                    return false;
                }
            },

            // These either transport values, produce managed addresses or no
            // value, or enforce their own non-pointer computation class above.
            .load,
            .store,
            .load_raw,
            .store_raw,
            .storage_addr,
            .static_addr,
            .address_bits,
            .borrow,
            .observe,
            .int_to_float,
            .float_to_int,
            .float_math,
            .check,
            .function_addr,
            .call_indirect,
            .call_noreturn,
            .call_indirect_noreturn,
            .ret,
            .jump,
            .branch,
            .trap,
            => {},
        }
        return true;
    }

    /// Observation values are typed pointers. Only checked borrowing creates
    /// them; transport cannot change the observed type or inspect the address.
    fn dataPointers(self: *Function, id: InstId) std.mem.Allocator.Error!bool {
        const mir = self.mir;
        const tag = mir.tagOf(id);
        const is_pointer = self.module.representationOf(mir.typeOf(id)).computation == .data_pointer;
        if (is_pointer and mir.resultRoleOf(id) == .value) switch (tag) {
            .borrow, .load, .load_indirect, .load_raw, .call, .call_indirect => {},
            else => {
                try self.report(mir.spanOf(id), "%{d} cannot manufacture an observation pointer", .{id.index()});
                return false;
            },
        };
        switch (tag) {
            .load_indirect => if (is_pointer and mir.typeOf(mir.unaryOf(id)) != mir.typeOf(id)) {
                try self.report(mir.spanOf(id), "%{d} loads an observation through a different type", .{id.index()});
                return false;
            },
            .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => {
                const pair = mir.binaryOf(id);
                if (self.module.representationOf(mir.typeOf(pair.lhs)).computation == .data_pointer or
                    self.module.representationOf(mir.typeOf(pair.rhs)).computation == .data_pointer)
                {
                    try self.report(mir.spanOf(id), "%{d} cannot compare observation addresses", .{id.index()});
                    return false;
                }
            },
            else => {},
        }
        return true;
    }

    fn isTypedPointerType(self: *const Function, ty: TypeId) bool {
        return switch (self.module.representationOf(ty).computation) {
            .code_pointer, .data_pointer => true,
            else => false,
        };
    }

    fn isCodePointerValue(self: *const Function, id: InstId) bool {
        return std.meta.eql(
            self.module.resultRepresentationOf(self.mir, id),
            mir_mod.ResultRepresentation{ .computation = .code_pointer },
        );
    }

    fn isCodePointerType(self: *const Function, ty: TypeId) bool {
        return self.module.representationOf(ty).computation == .code_pointer;
    }

    fn indirectSignatureDataInRange(
        self: *Function,
        id: InstId,
        signature: types_mod.CallableSignature,
    ) std.mem.Allocator.Error!bool {
        const params_len = self.module.types.callable_params.len;
        if (signature.first_param > params_len or signature.param_count > params_len - signature.first_param) {
            try self.report(self.mir.spanOf(id), "%{d} indirect call signature metadata is out of range", .{id.index()});
            return false;
        }
        if (!self.covers(signature.result)) {
            try self.report(self.mir.spanOf(id), "%{d} indirect call signature result is out of range", .{id.index()});
            return false;
        }
        if (self.mir.indirectCallOf(id).args.len != signature.param_count) return true;
        for (self.module.types.callableParams(signature)) |param| {
            if (self.covers(param.ty)) continue;
            try self.report(self.mir.spanOf(id), "%{d} indirect call signature parameter type is out of range", .{id.index()});
            return false;
        }
        return true;
    }

    fn operandInRange(self: *Function, id: InstId, operand: InstId) std.mem.Allocator.Error!bool {
        if (self.instInRange(operand)) return true;
        try self.report(self.mir.spanOf(id), "%{d} reads %{d}, and the function has {d} instruction(s)", .{
            id.index(), operand.index(), self.mir.insts.len,
        });
        return false;
    }

    fn localInRange(self: *Function, id: InstId, local: LocalId) std.mem.Allocator.Error!bool {
        if (local.index() < self.mir.locals.len) return true;
        try self.report(self.mir.spanOf(id), "%{d} names slot ${d}, and the function has {d}", .{
            id.index(), local.index(), self.mir.locals.len,
        });
        return false;
    }

    fn isValueFor(self: *const Function, id: InstId, ty: TypeId) bool {
        const got = self.module.resultRepresentationOf(self.mir, id);
        const want: mir_mod.ResultRepresentation = .{
            .computation = self.module.representationOf(ty).computation,
        };
        return std.meta.eql(got, want);
    }

    fn sameComputation(self: *Function, id: InstId, operand: InstId) std.mem.Allocator.Error!bool {
        if (sameResultType(
            self.module.resultRepresentationOf(self.mir, id),
            self.module.resultRepresentationOf(self.mir, operand),
        )) return true;
        try self.report(self.mir.spanOf(id), "%{d} changes computation representation without a conversion", .{id.index()});
        return false;
    }

    fn indirectAddress(
        self: *Function,
        id: InstId,
        address: InstId,
        checked_raw: bool,
        how: []const u8,
    ) std.mem.Allocator.Error!bool {
        const mir = self.mir;
        const got = self.module.resultRepresentationOf(mir, address);
        if (checked_raw) {
            if (mir.resultRoleOf(address) == .value and mir.typeOf(address) == .u64) return true;
            try self.report(mir.spanOf(id), "%{d} {s} through a raw address that is not UInt64", .{ id.index(), how });
            return false;
        }
        if (got == .managed_address) return true;
        if (mir.resultRoleOf(address) == .value and mir.typeOf(address) == .u64) {
            try self.report(mir.spanOf(id), "%{d} {s} through an unchecked raw address", .{ id.index(), how });
        } else {
            try self.report(mir.spanOf(id), "%{d} {s} through a non-address value", .{ id.index(), how });
        }
        return false;
    }

    fn precedes(self: *const Function, before: InstId, after: InstId) bool {
        if (!self.instInRange(before) or !self.instInRange(after)) return false;
        const a = self.locations[before.index()];
        const b = self.locations[after.index()];
        return a.block != std.math.maxInt(u32) and a.block == b.block and a.order < b.order;
    }

    fn checkedRawAccess(self: *Function, id: InstId) std.mem.Allocator.Error!bool {
        const mir = self.mir;
        const raw = mir.rawAccessOf(id);
        const is_load = mir.tagOf(id) != .store_raw;
        const typed = mir.tagOf(id) == .storage_addr;
        const width: i128 = if (typed) self.layoutOf(mir.typeOf(id)).size else switch (mir.typeOf(id)) {
            .u64 => 8,
            .u8 => 1,
            else => return self.badRawAccess(id),
        };
        const alignment_bytes: i128 = if (typed) self.layoutOf(mir.typeOf(id)).alignment else width;
        if ((is_load and raw.value != .none) or
            (!is_load and !self.precedes(raw.value, id)) or
            !self.precedes(raw.address, id) or
            !self.precedes(raw.overflow_check, raw.bounds_check) or
            !self.precedes(raw.bounds_check, id) or
            (alignment_bytes > 1 and (!self.precedes(raw.bounds_check, raw.alignment_check) or
                !self.precedes(raw.alignment_check, id))) or
            (alignment_bytes == 1 and raw.alignment_check != .none))
        {
            return self.badRawAccess(id);
        }

        if (mir.tagOf(raw.address) != .add or mir.typeOf(raw.address) != .u64) return self.badRawAccess(id);
        const address = mir.binaryOf(raw.address);
        if (!self.precedes(address.lhs, raw.address) or !self.precedes(address.rhs, raw.address)) return self.badRawAccess(id);

        if (mir.tagOf(raw.overflow_check) != .check or mir.typeOf(raw.overflow_check) != .u64) return self.badRawAccess(id);
        const overflow = mir.checkOf(raw.overflow_check);
        if (overflow.kind != .overflow or mir.tagOf(overflow.value) != .add or
            !self.precedes(overflow.value, raw.overflow_check)) return self.badRawAccess(id);
        const end = mir.binaryOf(overflow.value);
        if (end.lhs != address.rhs or mir.tagOf(end.rhs) != .constant or
            mir.typeOf(end.rhs) != .u64 or mir.constantOf(end.rhs) != width or
            !self.precedes(end.lhs, overflow.value) or !self.precedes(end.rhs, overflow.value))
        {
            return self.badRawAccess(id);
        }

        if (mir.tagOf(raw.bounds_check) != .check or mir.typeOf(raw.bounds_check) != .bool_) return self.badRawAccess(id);
        const bounds = mir.checkOf(raw.bounds_check);
        if (bounds.kind != .index_out_of_bounds or mir.tagOf(bounds.value) != .cmp_le or
            !self.precedes(bounds.value, raw.bounds_check)) return self.badRawAccess(id);
        const fits = mir.binaryOf(bounds.value);
        if (raw.length == .none or fits.lhs != overflow.value or fits.rhs != raw.length or
            mir.typeOf(raw.length) != .u64 or
            !self.precedes(fits.lhs, bounds.value) or !self.precedes(fits.rhs, bounds.value)) return self.badRawAccess(id);

        if (alignment_bytes > 1) {
            if (mir.tagOf(raw.alignment_check) != .check or mir.typeOf(raw.alignment_check) != .bool_) return self.badRawAccess(id);
            const alignment = mir.checkOf(raw.alignment_check);
            if (alignment.kind != .misaligned_access or mir.tagOf(alignment.value) != .cmp_eq or
                !self.precedes(alignment.value, raw.alignment_check)) return self.badRawAccess(id);
            const aligned = mir.binaryOf(alignment.value);
            if (mir.tagOf(aligned.lhs) != .rem or mir.tagOf(aligned.rhs) != .constant or
                mir.typeOf(aligned.rhs) != .u64 or mir.constantOf(aligned.rhs) != 0 or
                !self.precedes(aligned.lhs, alignment.value) or !self.precedes(aligned.rhs, alignment.value))
            {
                return self.badRawAccess(id);
            }
            const remainder = mir.binaryOf(aligned.lhs);
            if (remainder.lhs != address.rhs or mir.tagOf(remainder.rhs) != .constant or
                mir.typeOf(remainder.rhs) != .u64 or mir.constantOf(remainder.rhs) != alignment_bytes or
                !self.precedes(remainder.lhs, aligned.lhs) or !self.precedes(remainder.rhs, aligned.lhs)) return self.badRawAccess(id);
        }

        if (!try self.indirectAddress(id, raw.address, true, if (mir.tagOf(id) == .load_raw) "reads" else "writes")) return false;
        return true;
    }

    fn badRawAccess(self: *Function, id: InstId) std.mem.Allocator.Error!bool {
        try self.report(self.mir.spanOf(id), "%{d} raw access does not carry its checks", .{id.index()});
        return false;
    }

    fn sameResultType(lhs: mir_mod.ResultRepresentation, rhs: mir_mod.ResultRepresentation) bool {
        return std.meta.eql(lhs, rhs);
    }

    fn isInteger(representation: mir_mod.ResultRepresentation) bool {
        return switch (representation) {
            .computation => |computation| switch (computation) {
                .integer => true,
                else => false,
            },
            else => false,
        };
    }

    fn isBoolean(representation: mir_mod.ResultRepresentation) bool {
        return switch (representation) {
            .computation => |computation| computation == .boolean,
            else => false,
        };
    }

    fn isFloat(representation: mir_mod.ResultRepresentation) bool {
        return switch (representation) {
            .computation => |computation| computation == .float64,
            else => false,
        };
    }

    /// A blob index the module does not hold would emit a reference to a
    /// symbol nothing defines, which the linker refuses -- but only after the
    /// backend has already written a module it had said was well formed.
    fn bytesInRange(self: *Function, id: InstId, at: u32) std.mem.Allocator.Error!bool {
        if (at < self.module.bytes.len) return true;
        try self.report(self.mir.spanOf(id), "%{d} names blob {d}, and the module has {d}", .{
            id.index(), at, self.module.bytes.len,
        });
        return false;
    }

    /// A static the module does not hold would emit a reference to a symbol
    /// nothing defines. One of another type would let a load or a borrow read
    /// its bytes as a type they were not laid out for.
    fn staticNamed(self: *Function, id: InstId, at: u32) std.mem.Allocator.Error!bool {
        if (at >= self.module.statics.len) {
            try self.report(self.mir.spanOf(id), "%{d} names static {d}, and the module has {d}", .{
                id.index(), at, self.module.statics.len,
            });
            return false;
        }
        if (self.module.statics[at].ty != self.mir.typeOf(id)) {
            try self.report(self.mir.spanOf(id), "%{d} addresses static {d} as `{s}`, and it holds `{s}`", .{
                id.index(), at, self.module.types.nameOf(self.mir.typeOf(id)), self.module.types.nameOf(self.module.statics[at].ty),
            });
            return false;
        }
        return true;
    }

    fn blockInRange(self: *Function, id: InstId, b: BlockId) std.mem.Allocator.Error!bool {
        if (b.index() < self.mir.blocks.len) return true;
        try self.report(self.mir.spanOf(id), "%{d} jumps to block {d}, and the function has {d}", .{
            id.index(), b.index(), self.mir.blocks.len,
        });
        return false;
    }

    // -- Phase two: the module describes every type its code reaches. --

    /// Checks that every handle reaching the backend names a type the module
    /// describes, in both tables that describe one.
    ///
    /// Complete today by ordering rather than by construction -- lowering
    /// allocates the layout table once the last instantiation has been interned
    /// -- and the ordering is a property of one loop in one file that no reader
    /// of a module can see. A pass interning a type after that line is the
    /// natural next change, and it would leave a handle past the end that
    /// nothing about the types involved would say anything about.
    fn cover(self: *Function) std.mem.Allocator.Error!bool {
        // The same enumeration the emitter marks from, so a position one of
        // them reaches is a position the other reaches. What differs is the
        // message, which is what the position is carried for.
        var named = self.mir.namedTypes();
        while (named.next()) |n| {
            const ok = switch (n.at) {
                .returned => try self.described(n.ty, "what it returns"),
                .slot => |k| try self.describedSlot(n.ty, k),
                .inst => |i| try self.describedInst(n.ty, i),
            };
            if (!ok) return false;
        }
        return true;
    }

    fn covers(self: *const Function, t: TypeId) bool {
        return coversType(self.module, t);
    }

    fn members(self: *const Function) Members {
        return .{ .module = self.module };
    }

    fn described(self: *Function, t: TypeId, what: []const u8) std.mem.Allocator.Error!bool {
        if (self.covers(t)) return true;
        try self.reportFunction(
            "{s} is type {d}, and the module describes {d}",
            .{ what, @intFromEnum(t), self.module.layouts.len },
        );
        return false;
    }

    fn describedSlot(self: *Function, t: TypeId, i: u32) std.mem.Allocator.Error!bool {
        if (!self.covers(t)) {
            try self.reportFunction(
                "slot ${d} holds type {d}, and the module describes {d}",
                .{ i, @intFromEnum(t), self.module.layouts.len },
            );
            return false;
        }
        if (self.module.representationOf(t).storage != .invalid) return true;
        try self.reportFunction("slot ${d} has an invalid storage representation", .{i});
        return false;
    }

    fn describedInst(self: *Function, t: TypeId, id: InstId) std.mem.Allocator.Error!bool {
        if (self.covers(t)) return true;
        try self.report(
            self.mir.spanOf(id),
            "%{d} produces type {d}, and the module describes {d}",
            .{ id.index(), @intFromEnum(t), self.module.layouts.len },
        );
        return false;
    }

    fn verifySignature(self: *Function) std.mem.Allocator.Error!bool {
        const signature_type = self.mir.signature;
        if (!self.covers(signature_type)) {
            try self.reportFunction("signature names type {d}, and the module describes {d}", .{
                signature_type.index(), self.module.types.pool.len,
            });
            return false;
        }
        const signature = switch (self.module.types.get(signature_type)) {
            .callable => |signature| signature,
            else => {
                try self.reportFunction("signature type {d} is not callable", .{signature_type.index()});
                return false;
            },
        };
        const first = signature.first_param;
        const count = signature.param_count;
        if (first > self.module.types.callable_params.len or count > self.module.types.callable_params.len - first) {
            try self.reportFunction("signature parameter run {d}..{d} exceeds {d}", .{
                first, first +| count, self.module.types.callable_params.len,
            });
            return false;
        }
        if (count != self.mir.param_count) {
            try self.reportFunction("signature declares {d} parameter(s), but its body has {d}", .{
                count, self.mir.param_count,
            });
            return false;
        }
        if (!self.covers(signature.result)) {
            try self.reportFunction("signature result type {d} is not described", .{signature.result.index()});
            return false;
        }
        if (!self.module.isExternal(self.id) and self.id != self.module.entry and
            self.module.types.erased(signature.result) != self.mir.return_type)
        {
            try self.reportFunction("signature result type differs from its body", .{});
            return false;
        }
        const params = self.module.types.callable_params[first..][0..count];
        for (params, 0..) |param, i| {
            if (!self.covers(param.ty)) {
                try self.reportFunction("signature parameter {d} type {d} is not described", .{ i, param.ty.index() });
                return false;
            }
            const local = LocalId.at(@intCast(i));
            const slot_ty = mir_mod.parameterSlotType(self.module.types.erased(param.ty));
            if (slot_ty != self.mir.locals[i]) {
                try self.reportFunction("signature parameter {d} type differs from its slot", .{i});
                return false;
            }
            const wants_address = self.module.parameterSlotRoleOf(param) == .managed_address;
            if ((self.mir.slotRoleOf(local) == .managed_address) != wants_address) {
                try self.reportFunction("signature parameter {d} convention differs from its slot", .{i});
                return false;
            }
            if (!wants_address and !std.meta.eql(
                self.module.representationOf(slot_ty).computation,
                self.module.representationOf(self.mir.locals[i]).computation,
            )) {
                try self.reportFunction("signature parameter {d} representation differs from its slot", .{i});
                return false;
            }
        }
        return true;
    }

    // -- Phase three: every instruction records the physical role it produces. --

    fn roles(self: *Function) std.mem.Allocator.Error!bool {
        const mir = self.mir;
        for (mir.slot_roles[mir.param_count..], mir.param_count..) |role, i| {
            if (role != .managed_address) continue;
            try self.reportFunction("managed address slot ${d} is not a parameter", .{i});
            return false;
        }
        for (0..mir.insts.len) |i| {
            const id = InstId.at(@intCast(i));
            const tag = mir.tagOf(id);
            const want: mir_mod.ResultRole = switch (tag) {
                .addr_of, .field_addr, .storage_addr, .observe, .static_addr => .managed_address,
                .load => if (mir.slotRoleOf(mir.localOf(id)) == .managed_address) .managed_address else .value,
                .load_indirect => if (self.module.representationOf(mir.typeOf(id)).computation == .indirect)
                    .managed_address
                else
                    .value,
                .load_raw => .value,
                .call => if (self.module.returnsIndirectly(mir.callOf(id).func)) .managed_address else .value,
                .call_indirect => if (self.module.indirectReturnsByAddress(self.mir, id)) .managed_address else .value,
                .store,
                .store_indirect,
                .store_raw,
                .copy_value,
                .move_value,
                .call_noreturn,
                .call_indirect_noreturn,
                .ret,
                .jump,
                .branch,
                .trap,
                => .none,
                .constant,
                .bytes_addr,
                .address_bits,
                .borrow,
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
                .function_addr,
                => .value,
            };
            const got = mir.resultRoleOf(id);
            if (got == want) {
                if ((tag == .copy_value or tag == .move_value) and self.module.layoutOf(mir.typeOf(id)).isAggregate()) {
                    const pair = mir.binaryOf(id);
                    if (mir.resultRoleOf(pair.lhs) != .managed_address or mir.resultRoleOf(pair.rhs) != .managed_address) {
                        try self.report(mir.spanOf(id), "%{d} copies an aggregate through a non-address value", .{id.index()});
                        return false;
                    }
                }
                if (tag == .trap and !try self.trapMessage(id)) return false;
                if ((tag == .load_raw or tag == .store_raw or tag == .storage_addr) and !try self.checkedRawAccess(id)) return false;
                if (got != .none and self.module.representationOf(mir.typeOf(id)).computation == .no_value) {
                    try self.report(mir.spanOf(id), "%{d} produces a value of type Never", .{id.index()});
                }
                if (got == .value and self.module.representationOf(mir.typeOf(id)).computation == .indirect) {
                    try self.report(mir.spanOf(id), "%{d} has an indirect computation representation", .{id.index()});
                    return false;
                }
                continue;
            }

            if (tag == .call_noreturn or tag == .call_indirect_noreturn) {
                try self.report(mir.spanOf(id), "%{d} noreturn call produces none but is marked as {s}", .{
                    id.index(), @tagName(got),
                });
            } else if (tag == .call or tag == .call_indirect) {
                if (tag == .call_indirect) {
                    try self.report(mir.spanOf(id), "%{d} indirect call result does not follow its signature", .{id.index()});
                } else {
                    try self.report(mir.spanOf(id), "%{d} call result does not follow its return convention", .{id.index()});
                }
            } else if (want == .managed_address) {
                try self.report(mir.spanOf(id), "%{d} produces an address but is marked as a {s}", .{
                    id.index(), @tagName(got),
                });
            } else if (got == .managed_address) {
                try self.report(mir.spanOf(id), "%{d} produces a value but is marked as an address", .{id.index()});
            } else {
                try self.report(mir.spanOf(id), "%{d} produces {s} but is marked as {s}", .{
                    id.index(), @tagName(want), @tagName(got),
                });
            }
            return false;
        }
        return true;
    }

    fn trapMessage(self: *Function, id: InstId) std.mem.Allocator.Error!bool {
        const trap = self.mir.trapOf(id);
        if (trap.kind != .panic) {
            if (trap.message == .none) return true;
            try self.report(self.mir.spanOf(id), "%{d} non-panic trap carries a message", .{id.index()});
            return false;
        }
        if (trap.message == .none) {
            try self.report(self.mir.spanOf(id), "%{d} panic trap carries no message", .{id.index()});
            return false;
        }
        if (!self.precedes(trap.message, id)) {
            try self.report(self.mir.spanOf(id), "%{d} panic message does not dominate its trap", .{id.index()});
            return false;
        }
        if (self.mir.typeOf(trap.message) != self.module.panic_message_type or
            self.mir.resultRoleOf(trap.message) == .none)
        {
            try self.report(self.mir.spanOf(id), "%{d} panic message is not the module's canonical Str value", .{id.index()});
            return false;
        }
        return true;
    }

    // -- Phase four: where every address came from. --

    fn layoutOf(self: *const Function, t: TypeId) Layout {
        return self.module.layoutOf(t);
    }

    /// The exact place of every value, from the one attribution walk, and the
    /// report for a constant step that fits no offset.
    fn provenance(self: *Function, addresses: []Address, places: []Place) std.mem.Allocator.Error!void {
        attribute(self.module, self.mir, addresses);
        for (addresses, places, 0..) |a, *place, i| {
            place.* = a.place();
            if (a.malformed) {
                const id = InstId.at(@intCast(i));
                try self.report(self.mir.spanOf(id), "%{d} reaches a part at offset {d}", .{
                    id.index(), self.mir.constantOf(self.mir.binaryOf(id).rhs),
                });
            }
        }
    }

    /// The type of the object a place points into, and how many bytes it has.
    ///
    /// A slot's extent is the slot rule's own answer, asked of `mir` rather
    /// than restated here: the bound an access is checked against and the width
    /// a slot is allocated with are one sentence, and two statements of it are
    /// two numbers someone has to keep equal.
    const Object = struct { ty: TypeId, extent: u32 };

    fn objectOf(self: *const Function, place: Place) ?Object {
        return switch (place) {
            .none => null,
            .slot => |p| blk: {
                const t = self.mir.locals[p.local.index()];
                break :blk Object{
                    .ty = t,
                    .extent = self.module.slotExtentOf(self.mir, p.local),
                };
            },
            // What the address points at, not the slot holding the address:
            // the callee's own type for the parameter says what is there.
            .lent => |p| blk: {
                const t = self.mir.locals[p.local.index()];
                break :blk Object{ .ty = t, .extent = self.layoutOf(t).size };
            },
            .returned, .heap, .static => |p| blk: {
                const t = p.ty;
                if (!self.covers(t)) break :blk null;
                break :blk Object{ .ty = t, .extent = self.layoutOf(t).size };
            },
        };
    }

    // -- Phase four: every access lands inside the object it names. --

    fn accesses(self: *Function, places: []const Place) std.mem.Allocator.Error!void {
        const mir = self.mir;

        for (0..mir.insts.len) |i| {
            const id = InstId.at(@intCast(i));
            const span = mir.spanOf(id);

            switch (mir.tagOf(id)) {
                // Scalar and address slots are accessed through their recorded
                // storage representation. Aggregate bytes have no scalar named
                // access; lowering reaches them through managed addresses.
                .load => {
                    try self.namedSlot(id, mir.localOf(id), "read", span);
                },
                .store => {
                    try self.namedSlot(id, mir.storeOf(id).local, "written", span);
                },

                .borrow, .address_bits => {
                    const address = mir.unaryOf(id);
                    try self.through(id, places[address.index()], mir.typeOf(address), "observes", span);
                },
                .load_indirect => {
                    try self.moves(id, mir.typeOf(id), "reads", span);
                    const address = mir.unaryOf(id);
                    try self.through(id, places[address.index()], mir.typeOf(id), "reads", span);
                },
                .store_indirect => {
                    const p = mir.binaryOf(id);
                    try self.moves(id, mir.typeOf(id), "writes", span);
                    try self.writable(id, places[p.lhs.index()], "writes", span);
                    try self.through(id, places[p.lhs.index()], mir.typeOf(id), "writes", span);
                },
                .load_raw => try self.moves(id, mir.typeOf(id), "reads", span),
                .store_raw => try self.moves(id, mir.typeOf(id), "writes", span),
                .copy_value, .move_value => {
                    const p = mir.binaryOf(id);
                    try self.writable(id, places[p.lhs.index()], "copies into", span);
                    try self.through(id, places[p.lhs.index()], mir.typeOf(id), "copies into", span);
                    try self.through(id, places[p.rhs.index()], mir.typeOf(id), "copies from", span);
                },

                // Every argument reaching an indirect parameter must name at
                // least as many bytes as the callee will reach through it.
                // Decidable because the module carries every callee.
                .call => try self.arguments(id, places, span),
                .call_indirect => try self.indirectArguments(id, places, span),
                .call_noreturn => try self.arguments(id, places, span),
                .call_indirect_noreturn => try self.indirectArguments(id, places, span),

                else => {},
            }

            // A slot aligned past every ceiling the pipeline states is refused: the
            // packing rules produce nothing above 16, the runtime allocator hands out
            // 8, and a demand exceeding what anything grants is caught here, where
            // the demand is, rather than quietly under-aligned downstream. Allocated at the greatest
            // alignment it does have, which puts every part of the value at an
            // address the layout table never named.
            if (mir.tagOf(id) == .addr_of) {
                const t = mir.locals[mir.localOf(id).index()];
                const l = self.layoutOf(t);
                if (l.isAggregate() and l.alignment > 16) {
                    try self.report(span, "%{d} names a slot wanting {d}-byte alignment", .{
                        id.index(), l.alignment,
                    });
                }
            }
        }
    }

    fn namedSlot(
        self: *Function,
        id: InstId,
        local: LocalId,
        how: []const u8,
        span: Span,
    ) std.mem.Allocator.Error!void {
        switch (self.module.slotRepresentationOf(self.mir, local)) {
            .managed_address => return,
            .storage => |storage| switch (storage) {
                .integer, .boolean, .float64, .enum_tag, .unit, .code_pointer, .data_pointer => return,
                .bytes => try self.report(span, "%{d} has aggregate slot ${d} {s} through a named access, and it holds {d} byte(s)", .{
                    id.index(), local.index(), how, self.module.slotExtentOf(self.mir, local),
                }),
                .no_value => try self.report(span, "%{d} has Never slot ${d} {s} through a named access", .{
                    id.index(), local.index(), how,
                }),
                // `slotExtentOf` reports this compiler defect before this
                // representation can reach the verifier's access rules.
                .invalid => unreachable,
            },
        }
    }

    fn loadedValue(self: *Function, id: InstId) std.mem.Allocator.Error!void {
        const local = self.mir.localOf(id);
        if (self.mir.typeOf(id) == self.mir.locals[local.index()]) return;
        try self.report(self.mir.spanOf(id), "%{d} loads a value of a different type from slot ${d}", .{
            id.index(), local.index(),
        });
    }

    /// Checks that an instruction whose whole content is moving bytes moves
    /// some.
    ///
    /// The machine has no zero-width load and no zero-width store, so a part
    /// occupying no storage is reached by no instruction at all -- which is
    /// lowering's rule, and the one place a width of nothing can appear. An
    /// instruction that asks for one is answered by whatever the backend does
    /// with a size it has no instruction for, and for a part at the end of its
    /// container that lands past the end of it.
    ///
    /// A blit is not this: copying no bytes is a copy of no bytes, which the
    /// machine does by doing nothing, and an aggregate with no parts is a value
    /// the language has.
    fn moves(
        self: *Function,
        id: InstId,
        ty: TypeId,
        how: []const u8,
        span: Span,
    ) std.mem.Allocator.Error!void {
        if (self.layoutOf(ty).size != 0) return;
        try self.report(span, "%{d} {s} a value of `{s}`, which occupies no storage", .{
            id.index(), how, self.module.types.nameOf(ty),
        });
    }

    /// Refuses a write into read-only data. The backend emits a static as a
    /// constant global, so a write there faults at run time rather than
    /// changing a value no rule lets a program change.
    fn writable(self: *Function, id: InstId, place: Place, how: []const u8, span: Span) std.mem.Allocator.Error!void {
        if (!place.isStatic()) return;
        try self.report(span, "%{d} {s} {s}", .{ id.index(), how, place.describe() });
    }

    fn through(
        self: *Function,
        id: InstId,
        place: Place,
        ty: TypeId,
        how: []const u8,
        span: Span,
    ) std.mem.Allocator.Error!void {
        // An address this pass cannot attribute is not checked and not
        // reported: what is unknown is where it came from, not that it is
        // wrong. Lowering produces three such shapes -- an index computed at
        // run time, the checked heap access, and rendering's writes through an
        // address a value carries -- and each carries its own guard, dynamic
        // or by construction. They are indistinguishable here, so holding them
        // to their guards means either marking the access in MIR or following
        // an address through memory; that is the widening this exemption
        // trades away, and it should be paid deliberately, not guessed at.
        const object = self.objectOf(place) orelse return;
        const width = self.layoutOf(ty).size;
        const off = place.offset();

        if (@as(u64, off) + width > object.extent) {
            try self.report(span, "%{d} {s} {d} byte(s) at offset {d} of {s}, which has {d}", .{
                id.index(), how, width, off, place.describe(), object.extent,
            });
            return;
        }

        // An offset within an object is a part's offset or the whole of it.
        // Which part is what MIR discards and should keep discarding: a field
        // index would let this recompute the same number from the same table
        // with the same function and compare it to itself.
        //
        // This is also the whole of what alignment needs here. A part's offset
        // is where the layout table placed it, and the table places every part
        // at its own alignment -- so an offset that is a member offset is an
        // aligned one, and a second test of it would be this pass asking the
        // table a question it just answered.
        if (!self.members().isMember(object.ty, off, width)) {
            try self.report(span, "%{d} {s} {d} byte(s) at offset {d}, which is no part of `{s}`", .{
                id.index(), how, width, off, self.module.types.nameOf(object.ty),
            });
        }
    }

    /// Whether a computed offset selects a whole element of an array whose
    /// element holds a code pointer of the wanted type at its start. The
    /// offset must be an index scaled by the element's stride, which is the
    /// only computed offset lowering produces; the index itself was checked
    /// against the array's length before the address was formed.
    fn indexesElementOfType(self: *const Function, mir: *const Mir, declared: TypeId, offset: InstId, want: TypeId) bool {
        const types = &self.module.types;
        const container = types.erased(declared);
        const array = switch (types.get(container)) {
            .array => |array| array,
            else => return false,
        };
        if (mir.tagOf(offset) != .mul) return false;
        const scale = mir.binaryOf(offset).rhs;
        if (mir.tagOf(scale) != .constant or mir.constantOf(scale) != types.strideOf(array.element)) return false;
        return self.members().hasMemberOfType(array.element, 0, want);
    }

    fn arguments(
        self: *Function,
        id: InstId,
        places: []const Place,
        span: Span,
    ) std.mem.Allocator.Error!void {
        const c = self.mir.callOf(id);
        const callee = self.module.functionOf(c.func);

        if (c.args.len != callee.param_count) {
            try self.report(span, "%{d} passes {d} argument(s) to a function taking {d}", .{
                id.index(), c.args.len, callee.param_count,
            });
            return;
        }

        const signature: ?types_mod.CallableSignature = switch (self.module.types.get(callee.signature)) {
            .callable => |signature| signature,
            else => null,
        };
        for (c.args, 0..) |a, i| {
            if (signature) |known| {
                const params = self.module.types.callableParams(known);
                if (i < params.len and params[i].convention == .inout) try self.writable(id, places[a.index()], "lends for writing", span);
            }
            if (!self.module.arrivesByAddress(callee, i)) continue;

            const wants = callee.locals[i];
            if (!self.covers(wants)) continue;
            const needed = self.layoutOf(wants).size;

            const place = places[a.index()];
            const object = self.objectOf(place) orelse continue;
            const off = place.offset();
            if (@as(u64, off) + needed <= object.extent) continue;

            try self.report(span, "%{d} lends {d} byte(s) at offset {d} of {s}, which has {d}", .{
                id.index(), needed, off, place.describe(), object.extent,
            });
        }
    }

    fn indirectArguments(
        self: *Function,
        id: InstId,
        places: []const Place,
        span: Span,
    ) std.mem.Allocator.Error!void {
        const call = self.mir.indirectCallOf(id);
        const params = self.module.types.callableParams(self.module.indirectSignatureOf(self.mir, id));
        if (call.args.len != params.len) return;
        for (call.args, params) |arg, param| {
            if (param.convention == .inout) try self.writable(id, places[arg.index()], "lends for writing", span);
            const arrives_by_address = self.module.parameterByAddress(param);
            if (!arrives_by_address) continue;
            const needed = self.layoutOf(param.ty).size;
            const place = places[arg.index()];
            const object = self.objectOf(place) orelse continue;
            const off = place.offset();
            if (@as(u64, off) + needed <= object.extent) continue;
            try self.report(span, "%{d} lends {d} byte(s) at offset {d} of {s}, which has {d}", .{
                id.index(), needed, off, place.describe(), object.extent,
            });
        }
    }

    // -- Phase five: no address of this frame outlives it. --

    /// Checks that a frame's own storage does not leave with a value.
    ///
    /// A function whose result is too wide for a register is handed the
    /// address of storage the *caller* owns and the backend copies the value out, so
    /// returning a slot's address is what a wide return type means. Returning
    /// one from a function that returns a register hands the caller the address
    /// of a frame that has ended -- which is not a crash but a wrong answer,
    /// read out of whatever the next call wrote there.
    ///
    /// The convention is asked of the module rather than read off the return
    /// type, because the emitter does not always take it from there. This
    /// pass exists to hold the emitter to what it will really do, and a check
    /// that computes the convention itself is a second opinion about the one
    /// thing it is not entitled to have one about. Reading `return_type`
    /// directly switched the check off for the entry point -- whose signature
    /// the emitter writes as a register whatever the type says -- so the one
    /// function where the two disagreed was the one function not checked.
    fn escapes(self: *Function, places: []const Place) std.mem.Allocator.Error!void {
        const mir = self.mir;
        const returns_indirectly = self.module.returnsIndirectly(self.id);

        for (0..mir.insts.len) |i| {
            const id = InstId.at(@intCast(i));
            switch (mir.tagOf(id)) {
                .ret => {
                    if (returns_indirectly) continue;
                    if (!places[mir.unaryOf(id).index()].isSlot()) continue;
                    try self.report(
                        mir.spanOf(id),
                        "%{d} returns the address of a slot in this frame, and the function returns `{s}`, which is held in a register",
                        .{ id.index(), self.module.types.nameOf(mir.return_type) },
                    );
                },
                .store_indirect, .store_raw => {
                    const value = if (mir.tagOf(id) == .store_raw) mir.rawAccessOf(id).value else mir.binaryOf(id).rhs;
                    if (!places[value.index()].isSlot()) continue;
                    try self.report(
                        mir.spanOf(id),
                        "%{d} writes the address of a slot in this frame through a pointer",
                        .{id.index()},
                    );
                },
                else => {},
            }
        }
    }

    // -- Phase six: every value control can reach has a physical representation. --

    /// Checks every instruction control can enter has a usable computation
    /// representation, then checks the consumers whose expected representation
    /// comes from another part of the module.
    ///
    /// Poison is laid out as a word, so a value carrying it fits every register
    /// the machine has and reads as whatever the parameter is -- an integer
    /// where the callee dereferences an address, or a number wider than the
    /// type receiving it. Nothing below here can tell the difference, and the
    /// program was accepted, so this is the last place a value the checker
    /// never typed can be stopped.
    ///
    /// Lowering may retain poison placeholders in disconnected blocks after a
    /// transfer, but those blocks are not emitted and are deliberately outside
    /// this walk. A reachable value with no bytes is represented as Unit or a
    /// managed aggregate address rather than poison.
    ///
    /// **Bound:** one walk of this function's blocks to find which control
    /// enters, and one of the instructions in those.
    fn liveValues(self: *Function) std.mem.Allocator.Error!void {
        const mir = self.mir;

        const entered = try self.gpa.alloc(bool, mir.blocks.len);
        defer self.gpa.free(entered);
        @memset(entered, false);

        // Every handle here was established by phase one, so a target names a
        // block and a terminator ends every one of them.
        var pending: std.ArrayList(BlockId) = .empty;
        defer pending.deinit(self.gpa);
        entered[mir.entry.index()] = true;
        try pending.append(self.gpa, mir.entry);
        while (pending.pop()) |b| {
            const t = mir.terminatorOf(b);
            for (mir.successorsOf(t)) |successor| {
                const target = successor orelse continue;
                try self.enters(entered, &pending, target);
            }
        }

        for (entered, 0..) |reached, i| {
            if (!reached) continue;
            const block = BlockId.at(@intCast(i));
            for (mir.instsOf(block)) |id| {
                if (mir.resultRoleOf(id) == .value and
                    self.module.representationOf(mir.typeOf(id)).computation == .invalid)
                {
                    try self.report(mir.spanOf(id), "%{d} has an invalid computation representation", .{id.index()});
                }
                switch (mir.tagOf(id)) {
                    .call => try self.typedArguments(id),
                    .call_indirect => try self.typedIndirectArguments(id),
                    .load => try self.loadedValue(id),
                    .load_indirect => _ = try self.indirectAddress(id, mir.unaryOf(id), false, "reads"),
                    .load_raw => _ = try self.indirectAddress(id, mir.rawAccessOf(id).address, true, "reads"),
                    .store => try self.storedValue(id),
                    .store_indirect => {
                        _ = try self.indirectAddress(id, mir.binaryOf(id).lhs, false, "writes");
                        try self.indirectStoredValue(id);
                    },
                    .store_raw => {
                        _ = try self.indirectAddress(id, mir.rawAccessOf(id).address, true, "writes");
                        try self.indirectStoredValue(id);
                    },
                    else => {},
                }
            }
            const terminator = mir.terminatorOf(block);
            switch (mir.tagOf(terminator)) {
                .branch => try self.branchCondition(terminator),
                .ret => try self.returnValue(terminator),
                .call_noreturn => try self.typedArguments(terminator),
                .call_indirect_noreturn => try self.typedIndirectArguments(terminator),
                else => {},
            }
        }
    }

    fn storedValue(self: *Function, id: InstId) std.mem.Allocator.Error!void {
        const s = self.mir.storeOf(id);
        if (self.mir.slotRoleOf(s.local) != .value) {
            try self.report(self.mir.spanOf(id), "%{d} stores a value into managed address slot ${d}", .{
                id.index(), s.local.index(),
            });
        } else if (self.mir.resultRoleOf(s.value) != .value or
            self.mir.typeOf(s.value) != self.mir.locals[s.local.index()])
        {
            try self.report(self.mir.spanOf(id), "%{d} stores a value of a different type into slot ${d}", .{
                id.index(), s.local.index(),
            });
        }
    }

    fn indirectStoredValue(self: *Function, id: InstId) std.mem.Allocator.Error!void {
        const value = if (self.mir.tagOf(id) == .store_raw) self.mir.rawAccessOf(id).value else self.mir.binaryOf(id).rhs;
        if (self.mir.resultRoleOf(value) == .value and self.mir.typeOf(value) == self.mir.typeOf(id)) return;
        try self.report(self.mir.spanOf(id), "%{d} stores a value of a different type through an address", .{id.index()});
    }

    fn branchCondition(self: *Function, id: InstId) std.mem.Allocator.Error!void {
        if (!self.isValueFor(self.mir.branchOf(id).cond, .bool_)) {
            try self.report(self.mir.spanOf(id), "%{d} branches on a non-Boolean value", .{id.index()});
        }
    }

    fn returnValue(self: *Function, id: InstId) std.mem.Allocator.Error!void {
        if (self.mir.return_type == .never) {
            try self.report(self.mir.spanOf(id), "%{d} Never-returning function returns normally", .{id.index()});
            return;
        }
        const value = self.mir.unaryOf(id);
        if (self.module.returnsIndirectly(self.id)) {
            if (self.mir.resultRoleOf(value) != .managed_address) {
                try self.report(self.mir.spanOf(id), "%{d} returns a value through an indirect return", .{id.index()});
            } else if (self.mir.typeOf(value) != self.mir.return_type) {
                try self.report(self.mir.spanOf(id), "%{d} returns an address of the wrong type", .{id.index()});
            }
            return;
        }

        if (self.mir.return_type == .unit and
            self.mir.resultRoleOf(value) == .value and
            self.mir.typeOf(value) == .unit) return;
        if (self.isCodePointerType(self.mir.return_type) and self.mir.typeOf(value) != self.mir.return_type) {
            try self.report(self.mir.spanOf(id), "%{d} returns a code pointer with a different signature", .{id.index()});
            return;
        }
        if (!self.isValueFor(value, self.mir.return_type)) {
            try self.report(self.mir.spanOf(id), "%{d} returns a value with the wrong computation representation", .{id.index()});
        }
    }

    fn enters(
        self: *Function,
        entered: []bool,
        pending: *std.ArrayList(BlockId),
        b: BlockId,
    ) std.mem.Allocator.Error!void {
        if (entered[b.index()]) return;
        entered[b.index()] = true;
        try pending.append(self.gpa, b);
    }

    fn typedArguments(self: *Function, id: InstId) std.mem.Allocator.Error!void {
        const c = self.mir.callOf(id);
        const callee = self.module.functionOf(c.func);
        const result_type = self.directResultType(c.func);
        const is_noreturn = self.mir.tagOf(id) == .call_noreturn;
        if (is_noreturn and result_type != .never) {
            try self.report(self.mir.spanOf(id), "%{d} noreturn call targets a function returning {s}", .{
                id.index(), self.module.types.nameOf(result_type),
            });
        } else if (!is_noreturn and result_type == .never) {
            try self.report(self.mir.spanOf(id), "%{d} ordinary call targets a Never-returning function", .{id.index()});
        } else if (!is_noreturn and self.mir.typeOf(id) != result_type) {
            try self.report(self.mir.spanOf(id), "%{d} call result type differs from its target", .{id.index()});
        }
        // A call passing the wrong number of them is `arguments`' to report,
        // and nothing here would add to it.
        if (c.args.len != callee.param_count) return;

        for (c.args, 0..) |a, i| {
            const wants = callee.locals[i];
            if (!self.covers(wants)) continue;
            const wants_address = self.module.arrivesByAddress(callee, i);
            const got = self.mir.resultRoleOf(a);
            if (got == .managed_address and !wants_address) {
                try self.report(
                    self.mir.spanOf(id),
                    "%{d} passes a managed address to value argument {d}",
                    .{ id.index(), i },
                );
                continue;
            }
            if (got != .managed_address and wants_address) {
                try self.report(
                    self.mir.spanOf(id),
                    "%{d} passes a value to managed address argument {d}",
                    .{ id.index(), i },
                );
                continue;
            }
            if (wants_address and self.mir.typeOf(a) != wants) {
                try self.report(
                    self.mir.spanOf(id),
                    "%{d} passes managed address argument {d} with the wrong type",
                    .{ id.index(), i },
                );
                continue;
            }
            if (!wants_address and self.isCodePointerType(wants) and self.mir.typeOf(a) != wants) {
                try self.report(
                    self.mir.spanOf(id),
                    "%{d} passes code pointer argument {d} with a different signature",
                    .{ id.index(), i },
                );
                continue;
            }
            if (!wants_address and !self.isValueFor(a, wants)) {
                try self.report(
                    self.mir.spanOf(id),
                    "%{d} passes argument {d} with the wrong computation representation",
                    .{ id.index(), i },
                );
                continue;
            }
        }
    }

    fn typedIndirectArguments(self: *Function, id: InstId) std.mem.Allocator.Error!void {
        const call = self.mir.indirectCallOf(id);
        const signature = self.module.indirectSignatureOf(self.mir, id);
        const params = self.module.types.callableParams(signature);
        if (call.args.len != params.len) {
            try self.report(self.mir.spanOf(id), "%{d} passes {d} argument(s) through a pointer taking {d}", .{
                id.index(), call.args.len, params.len,
            });
            return;
        }
        for (call.args, params, 0..) |arg, param, i| {
            const wants_address = self.module.parameterByAddress(param);
            const got_address = self.mir.resultRoleOf(arg) == .managed_address;
            if (wants_address != got_address) {
                if (param.convention == .inout) {
                    try self.report(self.mir.spanOf(id), "%{d} passes a value to inout argument {d}", .{ id.index(), i });
                } else {
                    try self.report(self.mir.spanOf(id), "%{d} passes an address to value argument {d}", .{ id.index(), i });
                }
                continue;
            }
            if (wants_address and self.mir.typeOf(arg) != self.module.types.erased(param.ty)) {
                try self.report(self.mir.spanOf(id), "%{d} managed argument {d} has the wrong type", .{ id.index(), i });
            } else if (!wants_address and self.isTypedPointerType(param.ty) and self.mir.typeOf(arg) != param.ty) {
                try self.report(self.mir.spanOf(id), "%{d} passes code pointer argument {d} with a different signature", .{
                    id.index(), i,
                });
            } else if (!wants_address and !self.isValueFor(arg, param.ty)) {
                try self.report(self.mir.spanOf(id), "%{d} argument {d} has the wrong computation representation", .{
                    id.index(), i,
                });
            }
        }

        const result_type = self.module.types.erased(signature.result);
        const is_noreturn = self.mir.tagOf(id) == .call_indirect_noreturn;
        if (is_noreturn and result_type != .never) {
            try self.report(self.mir.spanOf(id), "%{d} indirect noreturn call targets a signature returning {s}", .{
                id.index(), self.module.types.nameOf(result_type),
            });
        } else if (!is_noreturn and result_type == .never) {
            try self.report(self.mir.spanOf(id), "%{d} ordinary indirect call targets a Never-returning signature", .{id.index()});
        } else if (!is_noreturn) {
            const wants_role: mir_mod.ResultRole = if (self.module.returnsByAddress(signature.result)) .managed_address else .value;
            if (self.mir.resultRoleOf(id) != wants_role) {
                try self.report(self.mir.spanOf(id), "%{d} indirect call result does not follow its signature", .{id.index()});
            } else if (self.mir.typeOf(id) != result_type) {
                try self.report(self.mir.spanOf(id), "%{d} indirect call result has the wrong representation", .{id.index()});
            }
        }
    }

    fn directResultType(self: *const Function, id: FunctionId) TypeId {
        const callee = self.module.functionOf(id);
        if (!self.module.isExternal(id)) return callee.return_type;
        return self.module.types.erased(self.module.types.get(callee.signature).callable.result);
    }
};

// -- Tests --
//
// Every violation is provoked from a hand-built `Mir`, because none of them is
// reachable from source: everything arriving at this pass has been accepted by
// every rule the language states. A verifier that has only ever passed is not
// evidence that it can fail.

const Builder = Mir.Builder;

/// A module of hand-built functions, carrying the checker's own answer for the
/// builtin types and whatever aggregate a case needs.
pub const Harness = struct {
    gpa: std.mem.Allocator,
    module: Module,
    arena: std.heap.ArenaAllocator,
    sink: Sink,

    /// Three declared types, and each is a shape a check needs.
    ///
    /// `Big` is wider than a register with a part at a non-zero offset;
    /// `Pair` is a narrow aggregate used to prove named scalar access is refused
    /// regardless of whether its byte extent could hold that access;
    /// `Maybe` carries a part with no bytes, which is where a width picked
    /// outside one, two, four and eight lands past the object.
    const all_fields = [_]types_mod.Field{
        .{ .name = "a", .ty = .i64 },
        .{ .name = "b", .ty = .i64 },
        .{ .name = "c", .ty = .i64 },
        .{ .name = "x", .ty = .u8 },
        .{ .name = "y", .ty = .u8 },
        .{ .name = "it", .ty = .unit },
        .{ .name = "first", .ty = nullary_callable },
        .{ .name = "second", .ty = other_callable },
        .{ .name = "before", .ty = empty },
        .{ .name = "first", .ty = nullary_callable },
        .{ .name = "between", .ty = empty },
        .{ .name = "second", .ty = callable },
        .{ .name = "after", .ty = empty },
        .{ .name = "pair", .ty = callback_pair },
        .{ .name = "pairs", .ty = callback_array },
        .{ .name = "tail", .ty = empty },
        .{ .name = "scalar", .ty = .u64 },
        .{ .name = "word", .ty = .u64 },
        .{ .name = "other", .ty = .u64 },
        .{ .name = "first", .ty = .u64 },
        .{ .name = "plain", .ty = plain },
    };

    const all_variants = [_]types_mod.Variant{
        .{ .name = "Nothing" },
        .{ .name = "Just", .first_field = 5, .field_count = 1 },
        .{ .name = "Flat", .first_field = 8, .field_count = 5 },
        .{ .name = "Nested", .first_field = 13, .field_count = 1 },
        .{ .name = "Array", .first_field = 14, .field_count = 2 },
        .{ .name = "Scalar", .first_field = 16, .field_count = 1 },
        .{ .name = "Empty" },
    };

    pub const big: TypeId = @enumFromInt(TypeId.builtins.len);
    const pair: TypeId = @enumFromInt(TypeId.builtins.len + 1);
    const maybe: TypeId = @enumFromInt(TypeId.builtins.len + 2);
    /// An aggregate occupying no storage, which a generic instantiated at the
    /// unit type produces and which the corpus holds a case for.
    const empty: TypeId = @enumFromInt(TypeId.builtins.len + 3);
    const callable: TypeId = @enumFromInt(TypeId.builtins.len + 4);
    const other_callable: TypeId = @enumFromInt(TypeId.builtins.len + 5);
    const inout_callable: TypeId = @enumFromInt(TypeId.builtins.len + 6);
    const nullary_callable: TypeId = @enumFromInt(TypeId.builtins.len + 7);
    const callable_alias: TypeId = @enumFromInt(TypeId.builtins.len + 8);
    const takes_callable: TypeId = @enumFromInt(TypeId.builtins.len + 9);
    const returns_callable: TypeId = @enumFromInt(TypeId.builtins.len + 10);
    const never_callable: TypeId = @enumFromInt(TypeId.builtins.len + 11);
    const callback_pair: TypeId = @enumFromInt(TypeId.builtins.len + 12);
    const callback_array: TypeId = @enumFromInt(TypeId.builtins.len + 13);
    const callback_enum: TypeId = @enumFromInt(TypeId.builtins.len + 14);
    const callable_array: TypeId = @enumFromInt(TypeId.builtins.len + 15);
    /// A borrow of `Big`, the type of a pointer value observing a `Big`.
    pub const big_borrow: TypeId = @enumFromInt(TypeId.builtins.len + 16);
    /// `Plain` is two words and holds no observation, as a value of an enum
    /// of scalars does; `Holder` is a word and then a `Plain`, and may hold
    /// one.
    pub const plain: TypeId = @enumFromInt(TypeId.builtins.len + 17);
    pub const holder: TypeId = @enumFromInt(TypeId.builtins.len + 18);

    /// What a synthesised signature says beyond what its slots imply: each
    /// parameter's convention, where the slot role's guess is not the one a
    /// case is about, and the clauses the storage phase reads.
    pub const Shape = struct {
        conventions: []const node.Convention = &.{},
        contracts: []const types_mod.CallableContract = &.{},
    };

    fn init(gpa: std.mem.Allocator, functions: []Mir) !Harness {
        return initShaped(gpa, functions, &.{});
    }

    /// As `init`, with a shape per leading function; functions past the end
    /// of `shapes` take the guessed one.
    pub fn initShaped(gpa: std.mem.Allocator, functions: []Mir, shapes: []const Shape) !Harness {
        var typing: types_mod.Typing = blk: {
            var missing_signatures: usize = 0;
            var missing_params: usize = 0;
            for (functions) |function| {
                if (function.signature != .poison) continue;
                missing_signatures += 1;
                missing_params += function.param_count;
            }

            const fixed_type_count = TypeId.builtins.len + 19;
            const pool = try gpa.alloc(types_mod.Type, fixed_type_count + missing_signatures);
            errdefer gpa.free(pool);
            @memcpy(pool[0..TypeId.builtins.len], &TypeId.builtins);
            pool[@intFromEnum(big)] = .{ .struct_ = .{ .name = "Big", .first_field = 0, .field_count = 3 } };
            pool[@intFromEnum(pair)] = .{ .struct_ = .{ .name = "Pair", .first_field = 3, .field_count = 2 } };
            pool[@intFromEnum(maybe)] = .{ .enum_ = .{ .name = "Maybe", .first_variant = 0, .variant_count = 2 } };
            pool[@intFromEnum(empty)] = .{ .struct_ = .{ .name = "Empty", .first_field = 0, .field_count = 0 } };
            pool[@intFromEnum(callable)] = .{ .callable = .{ .first_param = 0, .param_count = 1, .result = .u8, .name = "fn(read value: UInt8) -> UInt8" } };
            pool[@intFromEnum(other_callable)] = .{ .callable = .{ .first_param = 1, .param_count = 1, .result = .u8, .name = "fn(read value: UInt16) -> UInt8" } };
            pool[@intFromEnum(inout_callable)] = .{ .callable = .{ .first_param = 2, .param_count = 1, .result = .u8, .name = "fn(inout value: UInt8) -> UInt8" } };
            pool[@intFromEnum(nullary_callable)] = .{ .callable = .{ .first_param = 3, .param_count = 0, .result = .u8, .name = "fn() -> UInt8" } };
            pool[@intFromEnum(callable_alias)] = .{ .newtype = .{ .name = "CallableAlias", .base = nullary_callable } };
            pool[@intFromEnum(takes_callable)] = .{ .callable = .{ .first_param = 3, .param_count = 1, .result = .u8, .name = "fn(read f: fn(read value: UInt8) -> UInt8) -> UInt8" } };
            pool[@intFromEnum(returns_callable)] = .{ .callable = .{ .first_param = 4, .param_count = 0, .result = callable, .name = "fn() -> fn(read value: UInt8) -> UInt8" } };
            pool[@intFromEnum(never_callable)] = .{ .callable = .{ .first_param = 4, .param_count = 0, .result = .never, .name = "fn() -> Never" } };
            pool[@intFromEnum(callback_pair)] = .{ .struct_ = .{ .name = "CallbackPair", .first_field = 6, .field_count = 2 } };
            pool[@intFromEnum(callback_array)] = .{ .array = .{ .name = "[CallbackPair; 2]", .element = callback_pair, .count = 2 } };
            pool[@intFromEnum(callable_array)] = .{ .array = .{ .name = "[fn() -> UInt8; 2]", .element = nullary_callable, .count = 2 } };
            pool[@intFromEnum(big_borrow)] = .{ .borrow = .{ .referent = big, .name = "borrow Big" } };
            pool[@intFromEnum(plain)] = .{ .struct_ = .{ .name = "Plain", .first_field = 17, .field_count = 2 } };
            pool[@intFromEnum(holder)] = .{ .struct_ = .{ .name = "Holder", .first_field = 19, .field_count = 2 } };
            pool[@intFromEnum(callback_enum)] = .{ .enum_ = .{ .name = "Callbacks", .first_variant = 2, .variant_count = 5 } };
            const callable_params = [_]types_mod.CallableParam{
                .{ .spelling = "value", .convention = .read, .ty = .u8, .default = .absent },
                .{ .spelling = "value", .convention = .read, .ty = .u16, .default = .absent },
                .{ .spelling = "value", .convention = .inout, .ty = .u8, .default = .absent },
                .{ .spelling = "f", .convention = .read, .ty = callable, .default = .absent },
            };
            const all_callable_params = try gpa.alloc(types_mod.CallableParam, callable_params.len + missing_params);
            errdefer gpa.free(all_callable_params);
            @memcpy(all_callable_params[0..callable_params.len], &callable_params);
            var next_type = fixed_type_count;
            var next_param = callable_params.len;
            for (functions, 0..) |*function, index| {
                if (function.signature != .poison) continue;
                const shape: Shape = if (index < shapes.len) shapes[index] else .{};
                const signature: TypeId = @enumFromInt(@as(u32, @intCast(next_type)));
                pool[next_type] = .{ .callable = .{
                    .first_param = @intCast(next_param),
                    .param_count = function.param_count,
                    .result = function.return_type,
                    .name = "test signature",
                    .contracts = shape.contracts,
                } };
                for (0..function.param_count) |i| {
                    const local = LocalId.at(@intCast(i));
                    const guessed: node.Convention = if (function.slotRoleOf(local) == .managed_address) .inout else .read;
                    all_callable_params[next_param] = .{
                        .spelling = "parameter",
                        .convention = if (i < shape.conventions.len) shape.conventions[i] else guessed,
                        .ty = function.locals[i],
                        .default = .absent,
                    };
                    next_param += 1;
                }
                function.signature = signature;
                next_type += 1;
            }

            var variants: types_mod.VariantList = .empty;
            errdefer variants.deinit(gpa);
            try variants.ensureTotalCapacity(gpa, all_variants.len);
            for (all_variants) |variant| variants.appendAssumeCapacity(variant);

            var fields: types_mod.FieldList = .empty;
            errdefer fields.deinit(gpa);
            try fields.ensureTotalCapacity(gpa, all_fields.len);
            for (all_fields) |field| fields.appendAssumeCapacity(field);

            const expr_types = try gpa.alloc(TypeId, 0);
            errdefer gpa.free(expr_types);
            // Every fixture type but `Plain` may carry a dependency: the
            // table covers the whole pool, as a finished one does.
            const dependency_containment = try gpa.alloc(bool, pool.len);
            errdefer gpa.free(dependency_containment);
            @memset(dependency_containment, true);
            dependency_containment[@intFromEnum(plain)] = false;
            break :blk .{
                .binding_types = .empty,
                .decl_returns = .empty,
                .dependency_containment = dependency_containment,
                .pool = pool,
                .variants = .fromSlice(variants.toOwnedSlice()),
                .fields = .fromSlice(fields.toOwnedSlice()),
                .callable_params = all_callable_params,
                .expr_types = expr_types,
            };
        };
        errdefer typing.deinit(gpa);

        const layouts = try gpa.alloc(Layout, typing.pool.len);
        for (layouts, 0..) |*l, i| l.* = typing.layoutOf(@enumFromInt(@as(u32, @intCast(i))));
        const representations = try mir_mod.deriveRepresentations(gpa, &typing, layouts);

        const names = try gpa.alloc([]const u8, functions.len);
        for (names, 0..) |*n, i| n.* = try std.fmt.allocPrint(gpa, "f{d}", .{i});
        const external = try gpa.alloc(bool, functions.len);
        errdefer gpa.free(external);
        @memset(external, false);

        return .{
            .gpa = gpa,
            .arena = std.heap.ArenaAllocator.init(gpa),
            .sink = undefined,
            .module = .{
                .functions = functions,
                .bytes = &.{},
                .external = external,
                .names = names,
                .origins = try gpa.alloc(mir_mod.Origin, 0),
                .types = typing,
                .layouts = layouts,
                .representations = representations,
                .panic_message_type = big,
                .entry = FunctionId.at(0),
            },
        };
    }

    pub fn deinit(self: *Harness) void {
        self.module.deinit(self.gpa);
        self.arena.deinit();
    }

    /// Whether the module verifies, and what it said if it did not.
    pub fn run(self: *Harness) !struct { ok: bool, said: []const Diagnostic } {
        self.sink = Sink.init(self.arena.allocator());
        const ok = try verify(self.gpa, &self.module, &self.sink);
        return .{ .ok = ok, .said = self.sink.items() };
    }

    const Diagnostic = diagnostic.Diagnostic;
};

test "emission requires external flags for every function" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{try pointerTarget(gpa, Harness.nullary_callable, null)});
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const external = h.module.external;
    defer h.module.external = external;
    h.module.external = &.{};
    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "says where 0 of them are defined");
}

fn pointerTarget(gpa: std.mem.Allocator, signature: TypeId, parameter: ?struct { ty: TypeId, role: mir_mod.SlotRole }) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = signature;
    b.return_type = .u8;
    if (parameter) |p| {
        _ = try b.addLocal(p.ty, p.role);
        b.param_count = 1;
    }
    const entry = try b.addBlock();
    const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    return b.finish(entry, .from(0));
}

fn indirectCaller(
    gpa: std.mem.Allocator,
    pointer_ty: TypeId,
    target: FunctionId,
    args: []const InstId,
    result_ty: TypeId,
    result_role: mir_mod.ResultRole,
) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const callee = try b.addFunctionAddr(entry, pointer_ty, Span.empty, target);
    const result = try b.addIndirectCall(entry, result_role, result_ty, Span.empty, callee, args);
    const returned = if (result_ty == .u8 and result_role == .value)
        result
    else
        try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = returned } });
    return b.finish(entry, .from(0));
}

fn neverTarget(gpa: std.mem.Allocator) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.never_callable;
    b.return_type = .never;
    const entry = try b.addBlock();
    _ = try b.setTerminator(entry, .{ .tag = .trap, .ty = .unit, .span = Span.empty, .data = .{ .trap = .{ .kind = .unreachable_reached } } });
    return b.finish(entry, .from(0));
}

fn noreturnCaller(gpa: std.mem.Allocator, indirect: bool, target: FunctionId, signature: TypeId) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    if (indirect) {
        const callee = try b.addFunctionAddr(entry, signature, Span.empty, target);
        _ = try b.setIndirectCallNoreturn(entry, Span.empty, callee, &.{});
    } else {
        _ = try b.setCallNoreturn(entry, Span.empty, target, &.{});
    }
    return b.finish(entry, .from(0));
}

test "an ordinary direct call cannot target Never" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    _ = try b.addCall(entry, .value, .never, Span.empty, FunctionId.at(1), &.{});
    const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{ try b.finish(entry, .from(0)), try neverTarget(gpa) });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "ordinary call targets a Never-returning function");
}

test "an external call follows its declared result type" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    _ = try b.addCall(entry, .value, .u16, Span.empty, FunctionId.at(1), &.{});
    const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    var target = try pointerTarget(gpa, Harness.nullary_callable, null);
    target.return_type = .poison;
    const functions = try gpa.dupe(Mir, &.{ try b.finish(entry, .from(0)), target });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    @constCast(h.module.external)[1] = true;

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "call result type differs from its target");
}

test "an ordinary indirect call cannot target Never" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const callee = try b.addFunctionAddr(entry, Harness.never_callable, Span.empty, FunctionId.at(1));
    _ = try b.addIndirectCall(entry, .value, .never, Span.empty, callee, &.{});
    const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{ try b.finish(entry, .from(0)), try neverTarget(gpa) });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "ordinary indirect call targets a Never-returning signature");
}

test "a direct noreturn call must target Never" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try noreturnCaller(gpa, false, FunctionId.at(1), Harness.nullary_callable),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "noreturn call targets a function returning UInt8");
}

test "an indirect noreturn call must target Never" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try noreturnCaller(gpa, true, FunctionId.at(1), Harness.nullary_callable),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "indirect noreturn call targets a signature returning UInt8");
}

test "a Never-returning function cannot return normally" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.never_callable;
    b.return_type = .never;
    const entry = try b.addBlock();
    const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "Never-returning function returns normally");
}

test "noreturn calls carry no result role" {
    const gpa = testing.allocator;
    for ([_]bool{ false, true }) |indirect| {
        var caller = try noreturnCaller(gpa, indirect, FunctionId.at(1), Harness.never_callable);
        const terminator = caller.terminatorOf(caller.entry);
        caller.insts.items(.result_role)[terminator.index()] = .value;
        const functions = try gpa.dupe(Mir, &.{ caller, try neverTarget(gpa) });
        var h = try Harness.init(gpa, functions);
        defer h.deinit();

        const checked = try h.run();
        try testing.expect(!checked.ok);
        try expectSaid(checked.said, "noreturn call produces none but is marked as value");
    }
}

fn trapFunction(gpa: std.mem.Allocator, kind: mir_mod.TrapKind, message_type: ?TypeId, message_elsewhere: bool) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const message_block = if (message_elsewhere) try b.addBlock() else entry;
    const message = if (message_type) |ty| blk: {
        if (ty == Harness.big) {
            const local = try b.addLocal(ty, .value);
            break :blk try b.addInst(message_block, .{
                .tag = .addr_of,
                .result_role = .managed_address,
                .ty = ty,
                .span = Span.empty,
                .data = .{ .local = local },
            });
        }
        break :blk try b.addInst(message_block, .{
            .tag = .constant,
            .ty = ty,
            .span = Span.empty,
            .data = .{ .constant = 0 },
        });
    } else InstId.none;
    if (message_elsewhere) {
        _ = try b.setTerminator(message_block, .{
            .tag = .trap,
            .ty = .unit,
            .span = Span.empty,
            .data = .{ .trap = .{ .kind = .overflow } },
        });
    }
    _ = try b.setTerminator(entry, .{
        .tag = .trap,
        .ty = .unit,
        .span = Span.empty,
        .data = .{ .trap = .{ .kind = kind, .message = message } },
    });
    return b.finish(entry, .from(0));
}

test "a panic trap requires a message" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try trapFunction(gpa, .panic, null, false)));
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "panic trap carries no message");
}

test "a panic trap requires the canonical Str message type" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try trapFunction(gpa, .panic, .u8, false)));
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "panic message is not the module's canonical Str value");
}

test "a panic message must dominate its trap" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try trapFunction(gpa, .panic, Harness.big, true)));
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "panic message does not dominate its trap");
}

test "a non-panic trap cannot carry a message" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try trapFunction(gpa, .overflow, .u8, false)));
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "non-panic trap carries a message");
}

fn pointerOperationCaller(gpa: std.mem.Allocator, tag: mir_mod.Inst.Tag) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const pointer = try b.addFunctionAddr(entry, Harness.nullary_callable, Span.empty, FunctionId.at(1));
    const operated = switch (tag.payload()) {
        .unary => try b.addInst(entry, .{
            .tag = tag,
            .ty = Harness.nullary_callable,
            .span = Span.empty,
            .data = .{ .unary = pointer },
        }),
        .binary => try b.addInst(entry, .{
            .tag = tag,
            .ty = switch (tag) {
                .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => .bool_,
                else => Harness.nullary_callable,
            },
            .span = Span.empty,
            .data = .{ .binary = .{ .lhs = pointer, .rhs = pointer } },
        }),
        else => unreachable,
    };
    const result = switch (tag) {
        .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => try b.addInst(entry, .{
            .tag = .constant,
            .ty = .u8,
            .span = Span.empty,
            .data = .{ .constant = 0 },
        }),
        else => try b.addIndirectCall(entry, .value, .u8, Span.empty, operated, &.{}),
    };
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    return b.finish(entry, .from(0));
}

fn expectPointerOperationsRejected(tags: []const mir_mod.Inst.Tag, message: []const u8) !void {
    const gpa = testing.allocator;
    for (tags) |tag| {
        const functions = try gpa.dupe(Mir, &.{
            try pointerOperationCaller(gpa, tag),
            try pointerTarget(gpa, Harness.nullary_callable, null),
        });
        var h = try Harness.init(gpa, functions);
        defer h.deinit();

        const result = try h.run();
        try testing.expect(!result.ok);
        try expectSaid(result.said, message);
    }
}

fn expectSaid(said: []const Harness.Diagnostic, needle: []const u8) !void {
    for (said) |d| {
        if (std.mem.indexOf(u8, d.message, needle) != null) return;
    }
    for (said) |d| std.debug.print("said: {s}\n", .{d.message});
    return error.NotReported;
}

fn checkedRawLoad(gpa: std.mem.Allocator, late_end: bool, load_value: bool, wrong_length: bool) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const base = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1024 } });
    const offset = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
    const width = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1 } });
    const end = try b.addInst(entry, .{ .tag = .add, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = offset, .rhs = width } } });
    const overflow = try b.addInst(entry, .{ .tag = .check, .ty = .u64, .span = Span.empty, .data = .{ .check = .{ .value = end, .kind = .overflow } } });
    const len = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 8 } });
    const other_len = if (wrong_length)
        try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 16 } })
    else
        len;
    const fits = try b.addInst(entry, .{ .tag = .cmp_le, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = end, .rhs = other_len } } });
    const bounds = try b.addInst(entry, .{ .tag = .check, .ty = .bool_, .span = Span.empty, .data = .{ .check = .{ .value = fits, .kind = .index_out_of_bounds } } });
    const address = try b.addInst(entry, .{ .tag = .add, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = base, .rhs = offset } } });
    const load = try b.addRawAccess(entry, .load_raw, .u8, Span.empty, .{
        .address = address,
        .length = len,
        .value = if (load_value) base else .none,
        .overflow_check = overflow,
        .bounds_check = bounds,
    });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = load } });

    const function = try b.finish(entry, .from(0));
    if (late_end) std.mem.swap(InstId, &@constCast(function.block_insts)[end.index()], &@constCast(function.block_insts)[overflow.index()]);
    return function;
}

test "a well formed function verifies" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const slot = try b.addLocal(.u8, .value);
    const entry = try b.addBlock();
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 3 } });
    _ = try b.addInst(entry, .{ .tag = .store, .ty = .u8, .span = Span.empty, .data = .{ .store = .{ .local = slot, .value = k } } });
    const v = try b.addInst(entry, .{ .tag = .load, .ty = .u8, .span = Span.empty, .data = .{ .local = slot } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = v } });

    const functions = try gpa.alloc(Mir, 1);
    functions[0] = try b.finish(entry, .from(0));
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(got.ok);
    try testing.expectEqual(@as(usize, 0), got.said.len);
}

test "a function address names an existing function" {
    const gpa = testing.allocator;
    const caller = try indirectCaller(gpa, Harness.callable, FunctionId.at(9), &.{}, .u8, .value);
    var h = try Harness.init(gpa, try oneFunction(gpa, caller));
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "names function 9");
}

test "a function address produces a code pointer" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    _ = try b.addFunctionAddr(entry, .u8, Span.empty, FunctionId.at(1));
    const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{ try b.finish(entry, .from(0)), try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }) });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "does not produce a code pointer");
}

test "a function address has the target signature" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try indirectCaller(gpa, Harness.callable, FunctionId.at(1), &.{}, .u8, .value),
        try pointerTarget(gpa, Harness.other_callable, .{ .ty = .u16, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "signature differs from function 1");
}

test "a function address accepts contextual callable labels" {
    const gpa = testing.allocator;
    var builder = Builder.init(gpa);
    defer builder.deinit();
    builder.signature = Harness.nullary_callable;
    builder.return_type = .u8;
    const entry = try builder.addBlock();
    _ = try builder.addFunctionAddr(entry, Harness.callable, Span.empty, FunctionId.at(1));
    const result = try builder.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try builder.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try builder.finish(entry, .from(0)),
        try pointerTarget(gpa, .poison, .{ .ty = .u8, .role = .value }),
    });
    var harness = try Harness.init(gpa, functions);
    defer harness.deinit();
    try testing.expect(Harness.callable != harness.module.functions[1].signature);
    const checked = try harness.run();
    try testing.expect(checked.ok);
}

test "a code pointer can be stored loaded and called" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const source = try b.addLocal(Harness.nullary_callable, .value);
    const destination = try b.addLocal(Harness.nullary_callable, .value);
    const entry = try b.addBlock();
    const pointer = try b.addFunctionAddr(entry, Harness.nullary_callable, Span.empty, FunctionId.at(1));
    _ = try b.addInst(entry, .{
        .tag = .store,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .store = .{ .local = source, .value = pointer } },
    });
    const source_address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .local = source },
    });
    const destination_address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .local = destination },
    });
    _ = try b.addInst(entry, .{
        .tag = .copy_value,
        .result_role = .none,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = destination_address, .rhs = source_address } },
    });
    const loaded = try b.addInst(entry, .{
        .tag = .load,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .local = destination },
    });
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, loaded, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(checked.ok);
    try testing.expectEqual(@as(usize, 0), checked.said.len);
}

test "a code pointer cannot be forged by a constant" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const pointer = try b.addInst(entry, .{
        .tag = .constant,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .constant = 0 },
    });
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "constant cannot produce a code pointer");
}

test "a code pointer cannot be forged by a byte address" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const pointer = try b.addInst(entry, .{
        .tag = .bytes_addr,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .bytes = 0 },
    });
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();
    const bytes = try gpa.alloc([]const u8, 1);
    bytes[0] = try gpa.dupe(u8, "bytes");
    h.module.bytes = bytes;

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "bytes_addr cannot produce a code pointer");
}

test "a direct call cannot forge a code pointer result" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const pointer = try b.addCall(
        entry,
        .value,
        Harness.nullary_callable,
        Span.empty,
        FunctionId.at(1),
        &.{},
    );
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "call cannot produce a code pointer from its result");
}

test "a direct call checks its callee result range before code pointer representation" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const result = try b.addCall(
        entry,
        .value,
        Harness.nullary_callable,
        Span.empty,
        FunctionId.at(1),
        &.{},
    );
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    var target = try pointerTarget(gpa, Harness.nullary_callable, null);
    target.return_type = @enumFromInt(std.math.maxInt(u32));
    const functions = try gpa.dupe(Mir, &.{ try b.finish(entry, .from(0)), target });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "call target result type is out of range");
}

test "a direct call result is its callee result type" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    _ = try b.addCall(entry, .value, .i64, Span.empty, FunctionId.at(1), &.{});
    const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "call result type differs from its target");
}

test "a direct call preserves the exact code pointer signature" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const pointer = try b.addCall(
        entry,
        .value,
        Harness.nullary_callable,
        Span.empty,
        FunctionId.at(1),
        &.{},
    );
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    var target = try pointerTarget(gpa, Harness.nullary_callable, null);
    target.return_type = Harness.callable;
    const functions = try gpa.dupe(Mir, &.{ try b.finish(entry, .from(0)), target });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "call cannot change its code pointer signature");
}

test "an address of cannot relabel storage as a code pointer" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const slot = try b.addLocal(.u64, .value);
    const entry = try b.addBlock();
    const address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .local = slot },
    });
    const pointer = try b.addInst(entry, .{
        .tag = .load_indirect,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .unary = address },
    });
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "takes a code pointer address of a different slot type");
}

test "a field address cannot relabel a field as a code pointer" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const slot = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const base = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = Harness.big,
        .span = Span.empty,
        .data = .{ .local = slot },
    });
    const offset = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
    const address = try b.addInst(entry, .{
        .tag = .field_addr,
        .result_role = .managed_address,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = base, .rhs = offset } },
    });
    const pointer = try b.addInst(entry, .{
        .tag = .load_indirect,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .unary = address },
    });
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "takes a code pointer address of a different field type");
}

test "an indexed element address holds a code pointer only when scaled by the element's stride" {
    const cases = [_]struct { stride: i128, ty: TypeId, accepted: bool }{
        .{ .stride = 8, .ty = Harness.nullary_callable, .accepted = true },
        .{ .stride = 4, .ty = Harness.nullary_callable, .accepted = false },
        .{ .stride = 8, .ty = Harness.callable, .accepted = false },
    };
    for (cases) |case| {
        const gpa = testing.allocator;
        var b = Builder.init(gpa);
        defer b.deinit();
        b.signature = Harness.nullary_callable;
        b.return_type = .u8;
        const slot = try b.addLocal(Harness.callable_array, .value);
        const entry = try b.addBlock();
        const base = try b.addInst(entry, .{
            .tag = .addr_of,
            .result_role = .managed_address,
            .ty = Harness.callable_array,
            .span = Span.empty,
            .data = .{ .local = slot },
        });
        const index = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1 } });
        const stride = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = case.stride } });
        const offset = try b.addInst(entry, .{ .tag = .mul, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = index, .rhs = stride } } });
        _ = try b.addInst(entry, .{
            .tag = .field_addr,
            .result_role = .managed_address,
            .ty = case.ty,
            .span = Span.empty,
            .data = .{ .binary = .{ .lhs = base, .rhs = offset } },
        });
        const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
        _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
        var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
        defer h.deinit();

        const checked = try h.run();
        try testing.expectEqual(case.accepted, checked.ok);
        if (!case.accepted) try expectSaid(checked.said, "takes a code pointer address of a different field type");
    }
}

test "enum field addresses preserve exact code pointer types across overlapping payloads" {
    const cases = [_]struct { offset: u32, ty: TypeId, accepted: bool }{
        .{ .offset = 8, .ty = Harness.nullary_callable, .accepted = true },
        .{ .offset = 16, .ty = Harness.callable, .accepted = true },
        .{ .offset = 16, .ty = Harness.other_callable, .accepted = true },
        .{ .offset = 24, .ty = Harness.nullary_callable, .accepted = true },
        .{ .offset = 32, .ty = Harness.other_callable, .accepted = true },
        .{ .offset = 16, .ty = Harness.nullary_callable, .accepted = false },
        .{ .offset = 8, .ty = Harness.inout_callable, .accepted = false },
        .{ .offset = 8, .ty = Harness.other_callable, .accepted = false },
        .{ .offset = 8, .ty = Harness.callable_alias, .accepted = false },
        .{ .offset = 0, .ty = Harness.nullary_callable, .accepted = false },
        .{ .offset = 9, .ty = Harness.nullary_callable, .accepted = false },
        .{ .offset = 40, .ty = Harness.nullary_callable, .accepted = false },
    };
    for (cases) |case| {
        const gpa = testing.allocator;
        var b = Builder.init(gpa);
        defer b.deinit();
        b.signature = Harness.nullary_callable;
        b.return_type = .u8;
        const slot = try b.addLocal(Harness.callback_enum, .value);
        const entry = try b.addBlock();
        const base = try b.addInst(entry, .{
            .tag = .addr_of,
            .result_role = .managed_address,
            .ty = Harness.callback_enum,
            .span = Span.empty,
            .data = .{ .local = slot },
        });
        const offset = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = case.offset } });
        _ = try b.addInst(entry, .{
            .tag = .field_addr,
            .result_role = .managed_address,
            .ty = case.ty,
            .span = Span.empty,
            .data = .{ .binary = .{ .lhs = base, .rhs = offset } },
        });
        const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
        _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
        var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
        defer h.deinit();

        const checked = try h.run();
        try testing.expectEqual(case.accepted, checked.ok);
        if (!case.accepted) try expectSaid(checked.said, "takes a code pointer address of a different field type");
    }
}

test "a field address cannot use a code pointer value as storage" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const base = try b.addFunctionAddr(entry, Harness.nullary_callable, Span.empty, FunctionId.at(1));
    const offset = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
    const address = try b.addInst(entry, .{
        .tag = .field_addr,
        .result_role = .managed_address,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = base, .rhs = offset } },
    });
    const pointer = try b.addInst(entry, .{
        .tag = .load_indirect,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .unary = address },
    });
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "takes a code pointer field address through a non-address value");
}

test "an indirect store cannot write a code pointer through another type" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const slot = try b.addLocal(.u64, .value);
    const entry = try b.addBlock();
    const address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = .u64,
        .span = Span.empty,
        .data = .{ .local = slot },
    });
    const pointer = try b.addFunctionAddr(entry, Harness.nullary_callable, Span.empty, FunctionId.at(1));
    _ = try b.addInst(entry, .{
        .tag = .store_indirect,
        .result_role = .none,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = address, .rhs = pointer } },
    });
    const result = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "stores a code pointer through an address of a different type");
}

test "a memory copy cannot forge a code pointer from another type" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const source = try b.addLocal(.u64, .value);
    const destination = try b.addLocal(Harness.nullary_callable, .value);
    const entry = try b.addBlock();
    const source_address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = .u64,
        .span = Span.empty,
        .data = .{ .local = source },
    });
    const destination_address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .local = destination },
    });
    _ = try b.addInst(entry, .{
        .tag = .copy_value,
        .result_role = .none,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = destination_address, .rhs = source_address } },
    });
    const pointer = try b.addInst(entry, .{
        .tag = .load,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .local = destination },
    });
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "copies a code pointer from an address of a different type");
}

test "a memory copy reads a code pointer from storage rather than a value" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const destination = try b.addLocal(Harness.nullary_callable, .value);
    const entry = try b.addBlock();
    const source = try b.addFunctionAddr(entry, Harness.nullary_callable, Span.empty, FunctionId.at(1));
    const destination_address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .local = destination },
    });
    _ = try b.addInst(entry, .{
        .tag = .copy_value,
        .result_role = .none,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = destination_address, .rhs = source } },
    });
    const pointer = try b.addInst(entry, .{
        .tag = .load,
        .ty = Harness.nullary_callable,
        .span = Span.empty,
        .data = .{ .local = destination },
    });
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, pointer, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "copies a code pointer from a non-address value");
}

test "a direct call cannot pass a different code pointer signature" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const pointer = try b.addFunctionAddr(entry, Harness.nullary_callable, Span.empty, FunctionId.at(2));
    const result = try b.addCall(entry, .value, .u8, Span.empty, FunctionId.at(1), &.{pointer});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.takes_callable, .{ .ty = Harness.callable, .role = .value }),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "passes code pointer argument 0 with a different signature");
}

test "an indirect call cannot pass a different code pointer signature" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const callee = try b.addFunctionAddr(entry, Harness.takes_callable, Span.empty, FunctionId.at(1));
    const pointer = try b.addFunctionAddr(entry, Harness.nullary_callable, Span.empty, FunctionId.at(2));
    const result = try b.addIndirectCall(entry, .value, .u8, Span.empty, callee, &.{pointer});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = result } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.takes_callable, .{ .ty = Harness.callable, .role = .value }),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "passes code pointer argument 0 with a different signature");
}

test "a return cannot change a code pointer signature" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.returns_callable;
    b.return_type = Harness.callable;
    const entry = try b.addBlock();
    const pointer = try b.addFunctionAddr(entry, Harness.nullary_callable, Span.empty, FunctionId.at(1));
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = pointer } });
    const functions = try gpa.dupe(Mir, &.{
        try b.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const checked = try h.run();
    try testing.expect(!checked.ok);
    try expectSaid(checked.said, "returns a code pointer with a different signature");
}

test "binary arithmetic cannot operate on code pointers" {
    try expectPointerOperationsRejected(&.{ .add, .sub, .mul }, "cannot apply arithmetic to a code pointer");
}

test "division and remainder cannot operate on code pointers" {
    try expectPointerOperationsRejected(&.{ .div, .rem }, "cannot apply arithmetic to a code pointer");
}

test "negation cannot operate on a code pointer" {
    try expectPointerOperationsRejected(&.{.neg}, "cannot apply arithmetic to a code pointer");
}

test "callable equality is not a code pointer operation" {
    try expectPointerOperationsRejected(&.{ .cmp_eq, .cmp_ne }, "cannot compare code pointers");
}

test "code pointers cannot be ordered" {
    try expectPointerOperationsRejected(&.{ .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge }, "cannot compare code pointers");
}

test "a function signature cannot outrun its parameter slots" {
    const gpa = testing.allocator;
    var function = try pointerTarget(gpa, Harness.callable, null);
    function.param_count = 1;
    var h = try Harness.init(gpa, try oneFunction(gpa, function));
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "there are 1 parameter(s) and 0 slot(s)");
}

test "a function signature result is the body result type" {
    const gpa = testing.allocator;
    var function = try pointerTarget(gpa, Harness.nullary_callable, null);
    function.return_type = .u16;
    const functions = try gpa.dupe(Mir, &.{
        try pointerTarget(gpa, Harness.nullary_callable, null),
        function,
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "signature result type differs from its body");
}

test "a function signature managed parameter is the body parameter type" {
    const gpa = testing.allocator;
    const function = try pointerTarget(gpa, Harness.inout_callable, .{ .ty = .u16, .role = .managed_address });
    var h = try Harness.init(gpa, try oneFunction(gpa, function));
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "signature parameter 0 type differs from its slot");
}

test "an indirect call requires a code pointer callee" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const entry = try b.addBlock();
    const callee = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    const call = try b.addIndirectCall(entry, .value, .u8, Span.empty, callee, &.{});
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });
    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "callee is not a code pointer");
}

test "an indirect call requires a structural callable type" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.signature = Harness.nullary_callable;
    b.return_type = .u8;
    const slot = try b.addLocal(Harness.callable_alias, .value);
    const entry = try b.addBlock();
    const callee = try b.addInst(entry, .{ .tag = .load, .ty = Harness.callable_alias, .span = Span.empty, .data = .{ .local = slot } });
    _ = try b.addIndirectCall(entry, .value, .u8, Span.empty, callee, &.{});
    const returned = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = returned } });
    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "callee type is not a structural callable");
}

test "an indirect call passes the signature argument count" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try indirectCaller(gpa, Harness.callable, FunctionId.at(1), &.{}, .u8, .value),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "passes 0 argument(s) through a pointer taking 1");
}

test "an indirect call keeps its argument metadata in range" {
    const gpa = testing.allocator;
    const caller = try indirectCaller(gpa, Harness.nullary_callable, FunctionId.at(1), &.{}, .u8, .value);
    @constCast(caller.extra)[0] = InstId.at(1);
    const functions = try gpa.dupe(Mir, &.{
        caller,
        try pointerTarget(gpa, Harness.nullary_callable, null),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "indirect call metadata is out of range");
}

test "an indirect call keeps its signature parameter extent in range" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try indirectCaller(gpa, Harness.callable, FunctionId.at(1), &.{}, .u8, .value),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    @constCast(h.module.types.pool)[Harness.callable.index()].callable.first_param = std.math.maxInt(u32);

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "indirect call signature metadata is out of range");
}

test "an indirect call keeps its signature result type in range" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try indirectCaller(gpa, Harness.callable, FunctionId.at(1), &.{}, .u8, .value),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    @constCast(h.module.types.pool)[Harness.callable.index()].callable.result = @enumFromInt(std.math.maxInt(u32));

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "indirect call signature result is out of range");
}

test "an indirect call keeps its signature parameter type in range" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try indirectCaller(gpa, Harness.callable, FunctionId.at(1), &.{InstId.at(0)}, .u8, .value),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    @constCast(h.module.types.callable_params)[0].ty = @enumFromInt(std.math.maxInt(u32));

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "indirect call signature parameter type is out of range");
}

test "an indirect call with the wrong arity does not traverse parameter types" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try indirectCaller(gpa, Harness.callable, FunctionId.at(1), &.{}, .u8, .value),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    @constCast(h.module.types.callable_params)[0].ty = @enumFromInt(std.math.maxInt(u32));

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "passes 0 argument(s) through a pointer taking 1");
}

test "an indirect call follows the parameter convention" {
    const gpa = testing.allocator;
    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.signature = Harness.nullary_callable;
    caller.return_type = .u8;
    const entry = try caller.addBlock();
    const callee = try caller.addFunctionAddr(entry, Harness.inout_callable, Span.empty, FunctionId.at(1));
    const value = try caller.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 1 } });
    const call = try caller.addIndirectCall(entry, .value, .u8, Span.empty, callee, &.{value});
    _ = try caller.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });
    const functions = try gpa.dupe(Mir, &.{
        try caller.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.inout_callable, .{ .ty = .u8, .role = .managed_address }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "passes a value to inout argument 0");
}

test "an indirect call follows the parameter representation" {
    const gpa = testing.allocator;
    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.signature = Harness.nullary_callable;
    caller.return_type = .u8;
    const entry = try caller.addBlock();
    const callee = try caller.addFunctionAddr(entry, Harness.callable, Span.empty, FunctionId.at(1));
    const value = try caller.addInst(entry, .{ .tag = .constant, .ty = .f64, .span = Span.empty, .data = .{ .constant = 0 } });
    const call = try caller.addIndirectCall(entry, .value, .u8, Span.empty, callee, &.{value});
    _ = try caller.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });
    const functions = try gpa.dupe(Mir, &.{
        try caller.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "argument 0 has the wrong computation representation");
}

test "an indirect call follows a managed parameter type" {
    const gpa = testing.allocator;
    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.signature = Harness.nullary_callable;
    caller.return_type = .u8;
    _ = try caller.addLocal(.u16, .value);
    const entry = try caller.addBlock();
    const callee = try caller.addFunctionAddr(entry, Harness.inout_callable, Span.empty, FunctionId.at(1));
    const address = try caller.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = .u16,
        .span = Span.empty,
        .data = .{ .local = .at(0) },
    });
    const call = try caller.addIndirectCall(entry, .value, .u8, Span.empty, callee, &.{address});
    _ = try caller.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });
    const functions = try gpa.dupe(Mir, &.{
        try caller.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.inout_callable, .{ .ty = .u8, .role = .managed_address }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "managed argument 0 has the wrong type");
}

test "an indirect call follows the result role" {
    const gpa = testing.allocator;
    const functions = try gpa.dupe(Mir, &.{
        try indirectCaller(gpa, Harness.callable, FunctionId.at(1), &.{InstId.at(0)}, .u8, .managed_address),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "indirect call result does not follow its signature");
}

test "an indirect call follows the result representation" {
    const gpa = testing.allocator;
    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.signature = Harness.nullary_callable;
    caller.return_type = .u8;
    const entry = try caller.addBlock();
    const callee = try caller.addFunctionAddr(entry, Harness.callable, Span.empty, FunctionId.at(1));
    const value = try caller.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try caller.addIndirectCall(entry, .value, .f64, Span.empty, callee, &.{value});
    const returned = try caller.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try caller.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = returned } });
    const functions = try gpa.dupe(Mir, &.{
        try caller.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "indirect call result has the wrong representation");
}

test "an indirect call preserves the exact code pointer result type" {
    const gpa = testing.allocator;
    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.signature = Harness.nullary_callable;
    caller.return_type = .u8;
    const caller_entry = try caller.addBlock();
    const producer_addr = try caller.addFunctionAddr(caller_entry, Harness.returns_callable, Span.empty, FunctionId.at(1));
    const relabelled = try caller.addIndirectCall(caller_entry, .value, Harness.other_callable, Span.empty, producer_addr, &.{});
    const arg = try caller.addInst(caller_entry, .{ .tag = .constant, .ty = .u16, .span = Span.empty, .data = .{ .constant = 0 } });
    const call = try caller.addIndirectCall(caller_entry, .value, .u8, Span.empty, relabelled, &.{arg});
    _ = try caller.setTerminator(caller_entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });

    var producer = Builder.init(gpa);
    defer producer.deinit();
    producer.signature = Harness.returns_callable;
    producer.return_type = Harness.callable;
    const producer_entry = try producer.addBlock();
    const produced = try producer.addFunctionAddr(producer_entry, Harness.callable, Span.empty, FunctionId.at(2));
    _ = try producer.setTerminator(producer_entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = produced } });

    const functions = try gpa.dupe(Mir, &.{
        try caller.finish(caller_entry, .from(0)),
        try producer.finish(producer_entry, .from(1)),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .value }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "indirect call result has the wrong representation");
}

test "a non-capturing generated body has no environment parameter" {
    const gpa = testing.allocator;
    var function = try pointerTarget(gpa, Harness.nullary_callable, .{ .ty = .u8, .role = .value });
    function.param_count = 1;
    var h = try Harness.init(gpa, try oneFunction(gpa, function));
    defer h.deinit();

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "signature declares 0 parameter(s), but its body has 1");
}

test "a value result cannot carry an indirect computation representation" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    _ = try b.addInst(entry, .{ .tag = .constant, .ty = Harness.big, .span = Span.empty, .data = .{ .constant = 0 } });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "has an indirect computation representation");
}

test "a check accepts only the computation its trap kind handles" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const float = try b.addInst(entry, .{ .tag = .constant, .ty = .f64, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.addInst(entry, .{
        .tag = .check,
        .ty = .f64,
        .span = Span.empty,
        .data = .{ .check = .{ .value = float, .kind = .overflow } },
    });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "checks a non-integer value for overflow");
}

test "an uncovered arithmetic type is reported before representation lookup" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const lhs = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 1 } });
    const rhs = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 2 } });
    _ = try b.addInst(entry, .{
        .tag = .add,
        .ty = TypeId.at(TypeId.builtins.len + 40),
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = lhs, .rhs = rhs } },
    });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "produces type");
}

test "a comparison result must have Boolean computation representation" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const lhs = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 1 } });
    const rhs = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 2 } });
    const comparison = try b.addInst(entry, .{
        .tag = .cmp_lt,
        .ty = .u8,
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = lhs, .rhs = rhs } },
    });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = comparison } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "comparison does not produce Boolean computation");
}

test "integer arithmetic operands retain exact signedness" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .i8;
    const entry = try b.addBlock();
    const lhs = try b.addInst(entry, .{ .tag = .constant, .ty = .i8, .span = Span.empty, .data = .{ .constant = 1 } });
    const rhs = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 2 } });
    const sum = try b.addInst(entry, .{ .tag = .add, .ty = .i8, .span = Span.empty, .data = .{ .binary = .{ .lhs = lhs, .rhs = rhs } } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = sum } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "mixes computation representations");
}

test "comparison operands retain exact signedness" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .bool_;
    const entry = try b.addBlock();
    const lhs = try b.addInst(entry, .{ .tag = .constant, .ty = .i8, .span = Span.empty, .data = .{ .constant = 1 } });
    const rhs = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 2 } });
    const comparison = try b.addInst(entry, .{ .tag = .cmp_lt, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = lhs, .rhs = rhs } } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = comparison } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "compares across computation representations");
}

test "an indirect return address denotes the declared return type" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = Harness.big;
    const slot = try b.addLocal(.u8, .value);
    const entry = try b.addBlock();
    const address = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .local = slot } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = address } });

    var h = try Harness.init(gpa, try behindTheEntry(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "returns an address of the wrong type");
}

test "a managed argument address denotes the parameter type" {
    const gpa = testing.allocator;

    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .u8;
    callee.param_count = 1;
    _ = try callee.addLocal(.u8, .managed_address);
    const cb = try callee.addBlock();
    const zero = try callee.addInst(cb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const slot = try caller.addLocal(.u64, .value);
    const eb = try caller.addBlock();
    const address = try caller.addInst(eb, .{ .tag = .addr_of, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .local = slot } });
    _ = try caller.addCall(eb, .value, .u8, Span.empty, FunctionId.at(1), &.{address});
    const answer = try caller.addInst(eb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = answer } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "passes managed address argument 0 with the wrong type");
}

test "a managed address local must arrive as a parameter" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    _ = try b.addLocal(.u8, .managed_address);
    const entry = try b.addBlock();
    _ = try b.addInst(entry, .{ .tag = .load, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .local = LocalId.at(0) } });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "managed address slot $0 is not a parameter");
}

test "an indirect load rejects a non-address value" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const boolean = try b.addInst(entry, .{ .tag = .constant, .ty = .bool_, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .u8, .span = Span.empty, .data = .{ .unary = boolean } });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "reads through a non-address value");
}

test "an indirect load rejects an unchecked raw address" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const raw = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .u8, .span = Span.empty, .data = .{ .unary = raw } });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "reads through an unchecked raw address");
}

test "a raw access metadata run is bounded by the function" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    _ = try b.addInst(entry, .{
        .tag = .load_raw,
        .ty = .u8,
        .span = Span.empty,
        .data = .{ .raw_access = mir_mod.ExtraIndex.at(std.math.maxInt(u32)) },
    });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "raw access metadata is out of range");
}

test "a raw load records its checked access shape" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const raw = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addRawAccess(entry, .load_raw, .u8, Span.empty, .{ .address = raw });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "raw access does not carry its checks");
}

test "a raw load's checks are defined before they are used" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try checkedRawLoad(gpa, true, false, false)));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "raw access does not carry its checks");
}

test "a raw load records the length its bounds check uses" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try checkedRawLoad(gpa, false, false, true)));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "raw access does not carry its checks");
}

test "a raw load carries no stored value" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try checkedRawLoad(gpa, false, true, false)));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "raw access does not carry its checks");
}

test "the MIR builder preserves the result role its producer supplied" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    const slot = try b.addLocal(.u8, .value);
    const entry = try b.addBlock();
    const address = try b.addInst(entry, .{
        .tag = .addr_of,
        .result_role = .value,
        .ty = .u8,
        .span = Span.empty,
        .data = .{ .local = slot },
    });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var mir = try b.finish(entry, .from(0));
    defer mir.deinit(gpa);
    try testing.expectEqual(mir_mod.ResultRole.value, mir.resultRoleOf(address));
}

fn simpleFunction(gpa: std.mem.Allocator) !Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const value = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });
    return b.finish(entry, .from(0));
}

test "an incomplete representation table is reported" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try simpleFunction(gpa)));
    defer h.deinit();

    const old = h.module.representations.entries;
    h.module.representations.entries = try gpa.dupe(mir_mod.TypeRepresentation, old[0 .. old.len - 1]);
    gpa.free(old);

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "representation(s) for");
}

test "an extra representation entry is reported" {
    const gpa = testing.allocator;
    var h = try Harness.init(gpa, try oneFunction(gpa, try simpleFunction(gpa)));
    defer h.deinit();

    const old = h.module.representations.entries;
    const extra = try gpa.alloc(mir_mod.TypeRepresentation, old.len + 1);
    @memcpy(extra[0..old.len], old);
    extra[old.len] = old[0];
    h.module.representations.entries = extra;
    gpa.free(old);

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "representation(s) for");
}

test "a managed address cannot fill a value argument" {
    const gpa = testing.allocator;

    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .u64;
    callee.param_count = 1;
    _ = try callee.addLocal(.u64, .value);
    const cb = try callee.addBlock();
    const p = try callee.addInst(cb, .{ .tag = .load, .ty = .u64, .span = Span.empty, .data = .{ .local = LocalId.at(0) } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = p } });

    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const slot = try caller.addLocal(.u64, .value);
    const eb = try caller.addBlock();
    const address = try caller.addInst(eb, .{ .tag = .addr_of, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .local = slot } });
    _ = try caller.addCall(eb, .value, .u64, Span.empty, FunctionId.at(1), &.{address});
    const zero = try caller.addInst(eb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "passes a managed address to value argument 0");
}

test "a raw integer cannot fill a managed address argument" {
    const gpa = testing.allocator;

    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .u64;
    callee.param_count = 1;
    _ = try callee.addLocal(.u64, .managed_address);
    const cb = try callee.addBlock();
    const p = try callee.addInst(cb, .{ .tag = .load, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .local = LocalId.at(0) } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = p } });

    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const eb = try caller.addBlock();
    const raw = try caller.addInst(eb, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try caller.addCall(eb, .value, .u64, Span.empty, FunctionId.at(1), &.{raw});
    const zero = try caller.addInst(eb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));
    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "passes a value to managed address argument 0");
}

test "a branch condition uses boolean computation representation" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const yes = try b.addBlock();
    const no = try b.addBlock();
    const condition = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.setTerminator(entry, .{ .tag = .branch, .ty = .unit, .span = Span.empty, .data = .{ .branch = .{ .cond = condition, .then_block = yes, .else_block = no } } });
    const zero = try b.addInst(yes, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(yes, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });
    _ = try b.setTerminator(no, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "branches on a non-Boolean value");
}

test "a store agrees with its slot storage representation" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const slot = try b.addLocal(.u8, .value);
    const entry = try b.addBlock();
    const wide = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store, .ty = .u8, .span = Span.empty, .data = .{ .store = .{ .local = slot, .value = wide } } });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "stores a value of a different type into slot $0");
}

test "a load agrees with its slot storage representation" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const slot = try b.addLocal(.u8, .value);
    const entry = try b.addBlock();
    _ = try b.addInst(entry, .{ .tag = .load, .ty = .bool_, .span = Span.empty, .data = .{ .local = slot } });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "loads a value of a different type from slot $0");
}

test "an indirect store agrees with its value type" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const slot = try b.addLocal(.u8, .value);
    const entry = try b.addBlock();
    const address = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .local = slot } });
    const boolean = try b.addInst(entry, .{ .tag = .constant, .ty = .bool_, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u8, .span = Span.empty, .data = .{ .binary = .{ .lhs = address, .rhs = boolean } } });
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "stores a value of a different type through an address");
}

test "an indirect return is a managed address" {
    const gpa = testing.allocator;

    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = Harness.big;
    const cb = try callee.addBlock();
    const value = try callee.addInst(cb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });

    const functions = try behindTheEntry(gpa, try callee.finish(cb, .from(0)));
    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "returns a value through an indirect return");
}

test "an address producer marked as a value is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const slot = try b.addLocal(.u8, .value);
    const entry = try b.addBlock();
    const address = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .local = slot } });
    const value = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });

    var mir = try b.finish(entry, .from(0));
    mir.insts.items(.result_role)[address.index()] = .value;
    var h = try Harness.init(gpa, try oneFunction(gpa, mir));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "produces an address but is marked as a value");
}

test "a value producer marked as an address is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const value = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });

    var mir = try b.finish(entry, .from(0));
    mir.insts.items(.result_role)[value.index()] = .managed_address;
    var h = try Harness.init(gpa, try oneFunction(gpa, mir));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "produces a value but is marked as an address");
}

test "a call passing an argument with the wrong computation representation is reported" {
    const gpa = testing.allocator;

    // The callee takes a word.
    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .i64;
    callee.param_count = 1;
    _ = try callee.addLocal(.i64, .value);
    const cb = try callee.addBlock();
    const p = try callee.addInst(cb, .{ .tag = .load, .ty = .i64, .span = Span.empty, .data = .{ .local = LocalId.at(0) } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = p } });

    // The caller hands it a double.
    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const eb = try caller.addBlock();
    const d = try caller.addInst(eb, .{ .tag = .constant, .ty = .f64, .span = Span.empty, .data = .{ .constant = 0 } });
    const call = try caller.addCall(eb, .value, .i64, Span.empty, FunctionId.at(1), &.{d});
    const zero = try caller.addInst(eb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = call;
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));

    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "passes argument 0 with the wrong computation representation");
}

test "a return with the wrong computation representation is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .f64;
    const entry = try b.addBlock();
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });

    var h = try Harness.init(gpa, try behindTheEntry(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "returns a value with the wrong computation representation");
}

/// A function building a `Big` in a slot and returning its address, which is
/// the shape every aggregate case starts from.
fn aggregateInASlot(b: *Builder, returns: TypeId, offset: i128, width: TypeId) !BlockId {
    b.return_type = returns;
    const slot = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const base = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = slot } });
    const off = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = offset } });
    const at = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = base, .rhs = off } } });
    const value = try b.addInst(entry, .{ .tag = .constant, .ty = width, .span = Span.empty, .data = .{ .constant = 1 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = width, .span = Span.empty, .data = .{ .binary = .{ .lhs = at, .rhs = value } } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = base } });
    return entry;
}

test "a call result role follows its return convention" {
    const gpa = testing.allocator;

    var callee = Builder.init(gpa);
    defer callee.deinit();
    const callee_entry = try aggregateInASlot(&callee, Harness.big, 0, .i64);

    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const caller_entry = try caller.addBlock();
    const call = try caller.addCall(caller_entry, .value, Harness.big, Span.empty, FunctionId.at(1), &.{});
    const value = try caller.addInst(caller_entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try caller.setTerminator(caller_entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(caller_entry, .from(0));
    functions[1] = try callee.finish(callee_entry, .from(0));
    functions[0].insts.items(.result_role)[call.index()] = .value;

    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "call result does not follow its return convention");
}

/// A function that loads a `UInt64` through the address of static zero and
/// returns it narrowed to a byte, and a module holding `statics`.
fn readsStatic(gpa: std.mem.Allocator, address_ty: TypeId, statics: []const mir_mod.Static) !Harness {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u64;
    const entry = try b.addBlock();
    const at = try b.addInst(entry, .{ .tag = .static_addr, .result_role = .managed_address, .ty = address_ty, .span = Span.empty, .data = .{ .static = 0 } });
    const value = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .u64, .span = Span.empty, .data = .{ .unary = at } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });
    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    errdefer h.deinit();
    const owned = try gpa.alloc(mir_mod.Static, statics.len);
    for (owned, statics) |*to, from| to.* = .{ .ty = from.ty, .parts = try gpa.dupe(mir_mod.StaticPart, from.parts) };
    h.module.statics = owned;
    return h;
}

test "a load through a static's address verifies" {
    var h = try readsStatic(testing.allocator, .u64, &.{.{ .ty = .u64, .parts = &.{.{ .offset = 0, .ty = .u64, .value = .{ .constant = 7 } }} }});
    defer h.deinit();
    const got = try h.run();
    try testing.expect(got.ok);
}

test "a static address names a static the module holds" {
    var h = try readsStatic(testing.allocator, .u64, &.{});
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "names static 0, and the module has 0");
}

test "a static address has the static's own type" {
    var h = try readsStatic(testing.allocator, .u64, &.{.{ .ty = Harness.big, .parts = &.{} }});
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "addresses static 0 as `UInt64`, and it holds `Big`");
}

test "a static's parts follow one another inside it" {
    var h = try readsStatic(testing.allocator, .u64, &.{
        .{ .ty = .u64, .parts = &.{} },
        .{ .ty = Harness.big, .parts = &.{
            .{ .offset = 8, .ty = .i64, .value = .{ .constant = 1 } },
            .{ .offset = 0, .ty = .i64, .value = .{ .constant = 2 } },
        } },
    });
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "static 1 part 1 covers 8 byte(s) at offset 0, after byte 16 of 24");
}

test "a static's part sits where a part of its type sits" {
    var h = try readsStatic(testing.allocator, .u64, &.{
        .{ .ty = .u64, .parts = &.{} },
        .{ .ty = Harness.big, .parts = &.{.{ .offset = 8, .ty = .u16, .value = .{ .constant = 1 } }} },
    });
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "static 1 part 0 at offset 8 is no part of `Big`");
}

test "a static's part holds a value its type stores" {
    var h = try readsStatic(testing.allocator, .u64, &.{.{ .ty = Harness.pair, .parts = &.{
        .{ .offset = 0, .ty = .u8, .value = .{ .constant = 256 } },
        .{ .offset = 1, .ty = .u8, .value = .{ .bytes = 0 } },
    } }});
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "static 0 part 0 holds a value `UInt8` cannot store");
}

test "a store cannot write into a static" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const at = try b.addInst(entry, .{ .tag = .static_addr, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .static = 0 } });
    const value = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 9 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u8, .span = Span.empty, .data = .{ .binary = .{ .lhs = at, .rhs = value } } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = value } });
    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();
    const statics = try gpa.alloc(mir_mod.Static, 1);
    statics[0] = .{ .ty = .u8, .parts = try gpa.dupe(mir_mod.StaticPart, &.{.{ .offset = 0, .ty = .u8, .value = .{ .constant = 1 } }}) };
    h.module.statics = statics;

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "writes read-only data the module carries");
}

test "a static cannot be lent to a parameter written through" {
    const gpa = testing.allocator;

    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .u8;
    callee.param_count = 1;
    _ = try callee.addLocal(.u8, .managed_address);
    const cb = try callee.addBlock();
    const zero = try callee.addInst(cb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const eb = try caller.addBlock();
    const at = try caller.addInst(eb, .{ .tag = .static_addr, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .static = 0 } });
    const answer = try caller.addCall(eb, .value, .u8, Span.empty, FunctionId.at(1), &.{at});
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = answer } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));
    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    const statics = try gpa.alloc(mir_mod.Static, 1);
    statics[0] = .{ .ty = .u8, .parts = try gpa.dupe(mir_mod.StaticPart, &.{.{ .offset = 0, .ty = .u8, .value = .{ .constant = 1 } }}) };
    h.module.statics = statics;

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "lends for writing read-only data the module carries");
}

fn oneFunction(gpa: std.mem.Allocator, mir: Mir) ![]Mir {
    const functions = try gpa.alloc(Mir, 1);
    functions[0] = mir;
    return functions;
}

/// A module whose subject is an ordinary function rather than the entry point.
///
/// Function zero is the one the runtime calls, and the entry point's return
/// convention is not its return type's -- so a case about what a wide return
/// type means has to be about a function that is not it, or it is a case about
/// the exception instead.
fn behindTheEntry(gpa: std.mem.Allocator, mir: Mir) ![]Mir {
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try b.finish(entry, .from(0));
    functions[1] = mir;
    return functions;
}

test "a store past the end of an aggregate is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    // The last field begins at 16 and the structure is 24 bytes, so a store at
    // 24 lands one field past the end.
    const entry = try aggregateInASlot(&b, Harness.big, 24, .i64);

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "8 byte(s) at offset 24 of a slot in this frame, which has 24");
}

test "a store at an offset no part begins at is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    // In bounds and still wrong: the fields begin at 0, 8 and 16, so four
    // bytes into the second one is not a part of anything.
    const entry = try aggregateInASlot(&b, Harness.big, 12, .u32);

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "no part of `Big`");
}

test "a store of the wrong width at a real part is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    // The offset is a field's, and the width is not that field's.
    const entry = try aggregateInASlot(&b, Harness.big, 8, .u32);

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "no part of `Big`");
}

test "an access part way into a part is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    // In bounds, and neither the start of a part nor the whole of one: four
    // bytes into the first field, which is also where an eight-byte value
    // would be misaligned.
    const entry = try aggregateInASlot(&b, Harness.big, 4, .i64);

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "no part of `Big`");
}

test "a slot wanting an alignment the machine has no directive for is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    const entry = try aggregateInASlot(&b, Harness.big, 8, .i64);

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    // Injected into the table the whole pass reads, because no type the
    // language can declare wants more than a word: four, eight and sixteen are
    // the whole vocabulary, and below a rounded-down directive every part of
    // the value sits at an address the table never named.
    @constCast(h.module.layouts)[@intFromEnum(Harness.big)].alignment = 32;

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "names a slot wanting 32-byte alignment");
}

test "returning a slot from a function that returns a register is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    // The shape B.3 produced: the body writes an aggregate into a slot and
    // returns its address, while the signature says a machine word.
    const entry = try aggregateInASlot(&b, .u8, 8, .i64);

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "returns the address of a slot in this frame");
}

test "returning a slot from a function that returns an aggregate is what a wide return means" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    const entry = try aggregateInASlot(&b, Harness.big, 8, .i64);

    var h = try Harness.init(gpa, try behindTheEntry(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(got.ok);
}

test "the entry point returns a register, so a slot escaping it is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    // The body of the case above, unchanged, in the one position where the
    // emitter overrides the return type: the entry point is written `export
    // function w` whatever it says it returns, so the address of this frame is
    // narrowed to a word and handed to the runtime as an exit status.
    //
    // Nothing in the source language reaches this now that the entry point's
    // signature is checked. It is verified anyway, because a check that holds
    // only because another pass rejects the input is a check resting on
    // something it cannot see -- and this pass exists to hold the emitter to
    // what it will really do.
    const entry = try aggregateInASlot(&b, Harness.big, 8, .i64);

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "returns the address of a slot in this frame");
}

test "a copy sized from the wrong end is reported at the narrow end" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    // Two slots, one of them a scalar, and a copy of the whole structure into
    // it. This is the assignment whose width came from the right-hand side:
    // the destination is eight bytes and twenty-four are written.
    const wide = try b.addLocal(Harness.big, .value);
    const narrow = try b.addLocal(.u64, .value);
    const entry = try b.addBlock();
    const src = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = wide } });
    const dst = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .local = narrow } });
    _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = dst, .rhs = src } } });
    const v = try b.addInst(entry, .{ .tag = .load, .ty = .u64, .span = Span.empty, .data = .{ .local = narrow } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = v } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "copies into 24 byte(s) at offset 0");
}

test "a call lending less than the callee reaches is reported" {
    const gpa = testing.allocator;

    // The callee takes an aggregate by address and reads its last field.
    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .i64;
    callee.param_count = 1;
    _ = try callee.addLocal(Harness.big, .managed_address);
    const cb = try callee.addBlock();
    const p = try callee.addInst(cb, .{ .tag = .load, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = LocalId.at(0) } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = p } });

    // The caller lends a UInt64 scalar slot, whose storage extent is eight.
    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const slot = try caller.addLocal(.u64, .value);
    const eb = try caller.addBlock();
    const at = try caller.addInst(eb, .{ .tag = .addr_of, .result_role = .managed_address, .ty = .u64, .span = Span.empty, .data = .{ .local = slot } });
    const call = try caller.addCall(eb, .value, .i64, Span.empty, FunctionId.at(1), &.{at});
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));

    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "lends 24 byte(s) at offset 0 of a slot in this frame, which has 8");
}

test "an indirect call lending a read parameter kept in place less than it reaches is reported" {
    const gpa = testing.allocator;
    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.signature = Harness.nullary_callable;
    caller.return_type = .u8;
    _ = try caller.addLocal(.u8, .value);
    const entry = try caller.addBlock();
    const callee = try caller.addFunctionAddr(entry, Harness.callable, Span.empty, FunctionId.at(1));
    const slot = try caller.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .local = .at(0) } });
    // One byte past the slot's single byte: the parameter reaches a byte the
    // slot does not have.
    const past = try caller.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1 } });
    const lent = try caller.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = .u8, .span = Span.empty, .data = .{ .binary = .{ .lhs = slot, .rhs = past } } });
    const call = try caller.addIndirectCall(entry, .value, .u8, Span.empty, callee, &.{lent});
    _ = try caller.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });
    const functions = try gpa.dupe(Mir, &.{
        try caller.finish(entry, .from(0)),
        try pointerTarget(gpa, Harness.callable, .{ .ty = .u8, .role = .managed_address }),
    });
    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    // The callable's `read` parameter is kept in place, so it arrives by
    // address although a byte is not an aggregate.
    @constCast(h.module.types.callable_params)[0].stable_address = true;

    const result = try h.run();
    try testing.expect(!result.ok);
    try expectSaid(result.said, "lends 1 byte(s) at offset 1");
}

test "an access through a lent address is bounded by what the parameter names" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .i64;
    b.param_count = 1;
    _ = try b.addLocal(Harness.big, .managed_address);
    const entry = try b.addBlock();
    const at = try b.addInst(entry, .{ .tag = .load, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = LocalId.at(0) } });
    const off = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 24 } });
    const part = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = at, .rhs = off } } });
    const v = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .i64, .span = Span.empty, .data = .{ .unary = part } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = v } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "reads 8 byte(s) at offset 24 of an object a caller lent, which has 24");
}

test "a type with no layout entry is reported rather than treated as a register" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    // A handle past everything the module describes, which is what a pass
    // interning a type after the table was built would leave behind.
    const v = try b.addInst(entry, .{
        .tag = .constant,
        .ty = @enumFromInt(TypeId.builtins.len + 40),
        .span = Span.empty,
        .data = .{ .constant = 0 },
    });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = v } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "and the module describes");
}

test "an aggregate slot is not accessed by name" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    // Aggregate storage is canonical bytes reached through an address. Even
    // though this structure has a non-zero extent, no scalar named `store` may
    // reinterpret those bytes as one computation value.
    const slot = try b.addLocal(Harness.pair, .value);
    const entry = try b.addBlock();
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.addInst(entry, .{ .tag = .store, .ty = Harness.pair, .span = Span.empty, .data = .{ .store = .{ .local = slot, .value = k } } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "aggregate slot $0 written through a named access, and it holds 2 byte(s)");
}

test "a call passing a value of no type where bytes are read is reported" {
    const gpa = testing.allocator;

    // What a default the checker never typed lowers to: a constant carrying
    // poison, handed to a parameter the callee reads through.
    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .i64;
    callee.param_count = 1;
    _ = try callee.addLocal(Harness.big, .managed_address);
    const cb = try callee.addBlock();
    const p = try callee.addInst(cb, .{ .tag = .load, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = LocalId.at(0) } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = p } });

    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const eb = try caller.addBlock();
    const v = try caller.addInst(eb, .{ .tag = .constant, .ty = .poison, .span = Span.empty, .data = .{ .constant = 1 } });
    const call = try caller.addCall(eb, .value, .i64, Span.empty, FunctionId.at(1), &.{v});
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));

    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "has an invalid computation representation");
}

test "a reachable value of no type is rejected even where a parameter holds none" {
    const gpa = testing.allocator;

    // What lowering does emit, and what the check above must not report: a
    // value with no bytes is produced rather than read, and the parameter it
    // fills has none for the callee to reach.
    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .u8;
    callee.param_count = 1;
    _ = try callee.addLocal(Harness.empty, .value);
    const cb = try callee.addBlock();
    const k = try callee.addInst(cb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });

    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const eb = try caller.addBlock();
    const v = try caller.addInst(eb, .{ .tag = .constant, .ty = .poison, .span = Span.empty, .data = .{ .constant = 0 } });
    const call = try caller.addCall(eb, .value, .u8, Span.empty, FunctionId.at(1), &.{v});
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));

    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "has an invalid computation representation");
}

test "a call in a block control never enters is not asked what it passes" {
    const gpa = testing.allocator;

    // What an argument that leaves the function lowers to: the call is emitted
    // after the `ret`, into a block nothing jumps to, and its arguments are the
    // placeholders lowering had for values that were never produced.
    var callee = Builder.init(gpa);
    defer callee.deinit();
    callee.return_type = .i64;
    callee.param_count = 1;
    _ = try callee.addLocal(Harness.big, .managed_address);
    const cb = try callee.addBlock();
    const p = try callee.addInst(cb, .{ .tag = .constant, .ty = .i64, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = p } });

    var caller = Builder.init(gpa);
    defer caller.deinit();
    caller.return_type = .u8;
    const eb = try caller.addBlock();
    const k = try caller.addInst(eb, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try caller.setTerminator(eb, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });

    const dead = try caller.addBlock();
    const v = try caller.addInst(dead, .{ .tag = .constant, .ty = .poison, .span = Span.empty, .data = .{ .constant = 1 } });
    const call = try caller.addCall(dead, .value, .i64, Span.empty, FunctionId.at(1), &.{v});
    _ = try caller.setTerminator(dead, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = call } });

    const functions = try gpa.alloc(Mir, 2);
    functions[0] = try caller.finish(eb, .from(0));
    functions[1] = try callee.finish(cb, .from(0));

    var h = try Harness.init(gpa, functions);
    defer h.deinit();

    try testing.expect((try h.run()).ok);
}

test "an invalid local representation is rejected" {
    const gpa = testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    _ = try b.addLocal(.poison, .value);
    const entry = try b.addBlock();
    const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();
    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "slot $0 has an invalid storage representation");
}

test "a part with no bytes is not stored at a nonzero width" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    // The defect a `Maybe[()]` produced. The payload carries nothing and sits
    // at offset eight of an eight-byte object, so a store of any width at all
    // is past the end. The malformed instruction writes a UInt64's eight-byte
    // storage width there.
    const slot = try b.addLocal(Harness.maybe, .value);
    const entry = try b.addBlock();
    const base = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.maybe, .span = Span.empty, .data = .{ .local = slot } });
    const off = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 8 } });
    const at = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = Harness.maybe, .span = Span.empty, .data = .{ .binary = .{ .lhs = base, .rhs = off } } });
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.addInst(entry, .{ .tag = .store_indirect, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = at, .rhs = k } } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "writes 8 byte(s) at offset 8 of a slot in this frame, which has 8");
}

test "an aggregate occupying no storage is copied by a blit of no bytes" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    // What lowering does emit for a value with no bytes, and what the check
    // above must not report. Copying none of them is a copy the machine makes
    // by doing nothing, where a load or a store of none is an instruction that
    // does not exist -- so the two are not the same question, and a check that
    // conflated them would report every empty aggregate the corpus holds.
    const slot = try b.addLocal(Harness.empty, .value);
    const other = try b.addLocal(Harness.empty, .value);
    const entry = try b.addBlock();
    const dst = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.empty, .span = Span.empty, .data = .{ .local = slot } });
    const src = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.empty, .span = Span.empty, .data = .{ .local = other } });
    _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.empty, .span = Span.empty, .data = .{ .binary = .{ .lhs = dst, .rhs = src } } });
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(got.ok);
}

test "a block ending in something that is not a terminator is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const k = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = k } });

    const mir = try b.finish(entry, .from(0));
    // What `finish` refuses to build and what a later pass could still write:
    // the block's end is an ordinary instruction.
    const blocks = @constCast(mir.blocks);
    blocks[0].terminator = k;

    var h = try Harness.init(gpa, try oneFunction(gpa, mir));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "which does not end a block");
}

test "a jump to a block that does not exist is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    _ = try b.setTerminator(entry, .{ .tag = .jump, .ty = .unit, .span = Span.empty, .data = .{ .target = BlockId.at(7) } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "jumps to block 7");
}

test "an instruction reading one that does not exist is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = InstId.at(9) } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "reads %9");
}

test "two functions under one symbol are refused before they are emitted" {
    const gpa = testing.allocator;

    // Two functions that are each fine. What is wrong is the pair, which is
    // why no per-function check could see it.
    const functions = try gpa.alloc(Mir, 2);
    for (functions) |*f| {
        var b = Builder.init(gpa);
        defer b.deinit();
        b.return_type = .u8;
        const entry = try b.addBlock();
        const v = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 1 } });
        _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = v } });
        f.* = try b.finish(entry, .from(0));
    }

    var h = try Harness.init(gpa, functions);
    defer h.deinit();
    // The harness numbers symbols apart, which is what a module the compiler
    // built looks like. This is the module it must not build. Two equal
    // strings rather than one shared pointer, because that is what lowering
    // produces: each symbol is spelled on its own and two can come out alike.
    gpa.free(h.module.names[1]);
    h.module.names[1] = try gpa.dupe(u8, h.module.names[0]);

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "are both named");
}

test "a slot named by no local is reported" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const entry = try b.addBlock();
    const v = try b.addInst(entry, .{ .tag = .load, .ty = .u8, .span = Span.empty, .data = .{ .local = LocalId.at(4) } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = v } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "names slot $4");
}

test "a place reached through a field address carries the offset it was given" {
    const gpa = testing.allocator;

    var b = Builder.init(gpa);
    defer b.deinit();
    b.return_type = .u8;
    const slot = try b.addLocal(Harness.big, .value);
    const entry = try b.addBlock();
    const base = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = slot } });
    const o1 = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 8 } });
    const a1 = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = base, .rhs = o1 } } });
    // Twice, so the domain has to add rather than replace: 8 and 16 together
    // are past the end, and either alone is not.
    const o2 = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 16 } });
    const a2 = try b.addInst(entry, .{ .tag = .field_addr, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = a1, .rhs = o2 } } });
    const v = try b.addInst(entry, .{ .tag = .load_indirect, .ty = .i64, .span = Span.empty, .data = .{ .unary = a2 } });
    _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = v } });

    var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
    defer h.deinit();

    const got = try h.run();
    try testing.expect(!got.ok);
    try expectSaid(got.said, "at offset 24 of a slot in this frame, which has 24");
}

/// Property: every module the compiler produces from a program it accepted
/// satisfies what emitting it assumes.
///
/// A false positive is the worst answer this pass can give. A violation is
/// reported without a rule code and under an exit status of its own, so a
/// legal program that trips one does not merely fail to compile -- it is told
/// it met a compiler defect, and no source-level rule names anything to fix.
/// The whole corpus is a standing check of this, but only over programs
/// somebody wrote, and the shapes nobody writes are where the arithmetic here
/// is least exercised.
///
/// The oracle costs nothing: the checker has already decided whether the
/// program is legal, so the only judgement in the loop is one the compiler
/// makes twice and must make the same way both times.
///
/// **The bytes are the generator's choice stream rather than source text.**
/// That is what the stream is for -- it is read one byte per decision so a
/// fuzzer can steer it, and every stream is a well-typed program by
/// construction, so every input reaches this pass. Random *source* does not:
/// the frontend refuses it, lowering never runs, and a target fed that way
/// would assert nothing while looking like it asserted something.
fn fuzzVerified(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [64]u8 = undefined;
    const len = smith.slice(&buf);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Without tuples: this target checks the text on its own, with no library
    // beside it, and a tuple's type is the library's, so every program holding
    // one would be refused before anything is verified.
    const text = try generate.generate(gpa, buf[0..len], .{ .max_tuples = 0 });
    const source: Source = .{ .path = "generated.lin", .text = text };

    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &res, &sink);
    var cancelled = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer cancelled.deinit(gpa);

    // Whether the generator and the compiler agree about the language is the
    // conformance runner's question and it fails the run there. Here a program
    // the compiler refused has no code to verify, and asking about it would be
    // this target failing for somebody else's defect.
    if (sink.hasErrors()) return;

    const module = (try lowerTree(gpa, &res, &typing, &cancelled, &sink, .program)) orelse return error.SourceRejected;

    // Lowering is where monomorphisation happens, so it reports rules of its
    // own -- a width settled only once an instantiation exists. Same reason.
    if (sink.hasErrors()) return;

    if (try verify(gpa, &module, &sink)) return;

    std.debug.print("{s}\n", .{text});
    for (sink.items()) |d| std.debug.print("{s}\n", .{d.message});
    return error.AWellFormedModuleWasRefused;
}

test "fuzz: a module lowered from a program the compiler accepted verifies" {
    // Every input this property has ever failed on, replayed before any new one
    // is tried, so a defect the fuzzer found once cannot come back unnoticed.
    try std.testing.fuzz({}, fuzzVerified, .{ .corpus = @import("fuzz_corpus").verify });
}

test "every input the fuzzer found for the verifier still passes" {
    // Replayed here as well as handed to the fuzzer, because the two run at
    // different times: a search runs nightly and on a push, and this runs
    // whenever anyone builds.
    for (@import("fuzz_corpus").verify) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try fuzzVerified({}, &smith);
    }
}

test "typed storage address requires bounds for its concrete element" {
    const gpa = testing.allocator;
    const tag = mir_mod.Inst.Tag.storage_addr;
    for ([_]TypeId{ .u8, .unit, Harness.empty, .u64 }) |element| {
        var function = try checkedRawLoad(gpa, false, false, false);
        function.return_type = .u64;
        const terminator = function.blocks[0].terminator;
        const access = function.unaryOf(terminator);
        function.insts.items(.tag)[access.index()] = tag;
        function.insts.items(.result_role)[access.index()] = .managed_address;
        function.insts.items(.ty)[access.index()] = element;
        function.insts.items(.data)[terminator.index()].unary = InstId.at(0);
        var h = try Harness.init(gpa, try oneFunction(gpa, function));
        defer h.deinit();
        const got = try h.run();
        try testing.expectEqual(element == .u8, got.ok);
        if (element != .u8) try expectSaid(got.said, "raw access does not carry its checks");
    }
}

test "typed storage address separates element extent from alignment" {
    const gpa = testing.allocator;
    for ([_]u32{ 8, 24 }) |alignment_bytes| {
        var b = Builder.init(gpa);
        defer b.deinit();
        b.return_type = .u64;
        const entry = try b.addBlock();
        const base = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 1024 } });
        const offset = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
        const width = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 24 } });
        const end = try b.addInst(entry, .{ .tag = .add, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = offset, .rhs = width } } });
        const overflow = try b.addInst(entry, .{ .tag = .check, .ty = .u64, .span = Span.empty, .data = .{ .check = .{ .value = end, .kind = .overflow } } });
        const fits = try b.addInst(entry, .{ .tag = .cmp_le, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = end, .rhs = width } } });
        const bounds = try b.addInst(entry, .{ .tag = .check, .ty = .bool_, .span = Span.empty, .data = .{ .check = .{ .value = fits, .kind = .index_out_of_bounds } } });
        const align_value = try b.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = alignment_bytes } });
        const rem = try b.addInst(entry, .{ .tag = .rem, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = offset, .rhs = align_value } } });
        const aligned = try b.addInst(entry, .{ .tag = .cmp_eq, .ty = .bool_, .span = Span.empty, .data = .{ .binary = .{ .lhs = rem, .rhs = offset } } });
        const alignment = try b.addInst(entry, .{ .tag = .check, .ty = .bool_, .span = Span.empty, .data = .{ .check = .{ .value = aligned, .kind = .misaligned_access } } });
        const address = try b.addInst(entry, .{ .tag = .add, .ty = .u64, .span = Span.empty, .data = .{ .binary = .{ .lhs = base, .rhs = offset } } });
        const storage = try b.addRawAccess(entry, .storage_addr, Harness.big, Span.empty, .{
            .address = address,
            .length = width,
            .overflow_check = overflow,
            .bounds_check = bounds,
            .alignment_check = alignment,
        });
        const destination = try b.addLocal(Harness.big, .value);
        const destination_address = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = destination } });
        _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{ .lhs = destination_address, .rhs = storage } } });
        _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = offset } });
        var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
        defer h.deinit();
        const got = try h.run();
        try testing.expectEqual(alignment_bytes == 8, got.ok);
        if (alignment_bytes != 8) try expectSaid(got.said, "raw access does not carry its checks");
    }
}

test "aggregate copies reject scalar operands" {
    const gpa = testing.allocator;
    for ([_]bool{ false, true }) |scalar_source| {
        var b = Builder.init(gpa);
        defer b.deinit();
        b.return_type = .u8;
        const slot = try b.addLocal(Harness.big, .value);
        const entry = try b.addBlock();
        const address = try b.addInst(entry, .{ .tag = .addr_of, .result_role = .managed_address, .ty = Harness.big, .span = Span.empty, .data = .{ .local = slot } });
        const scalar = try b.addInst(entry, .{ .tag = .constant, .ty = .unit, .span = Span.empty, .data = .{ .constant = 0 } });
        _ = try b.addInst(entry, .{ .tag = .copy_value, .ty = Harness.big, .span = Span.empty, .data = .{ .binary = .{
            .lhs = if (scalar_source) address else scalar,
            .rhs = if (scalar_source) scalar else address,
        } } });
        const status = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
        _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = status } });
        var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
        defer h.deinit();
        const got = try h.run();
        try testing.expect(!got.ok);
        try expectSaid(got.said, "copies an aggregate through a non-address value");
    }
}

test "array view address bits require a managed source and UInt64 result" {
    const gpa = testing.allocator;
    for ([_]bool{ false, true }) |managed| {
        for ([_]TypeId{ .u8, .u64 }) |result| {
            var b = Builder.init(gpa);
            defer b.deinit();
            b.return_type = result;
            const block = try b.addBlock();
            const slot = try b.addLocal(.u64, .value);
            const initial = try b.addInst(block, .{ .tag = .constant, .ty = .u64, .span = Span.empty, .data = .{ .constant = 0 } });
            _ = try b.addInst(block, .{ .tag = .store, .ty = .u64, .span = Span.empty, .data = .{ .store = .{ .local = slot, .value = initial } } });
            const address = if (managed) try b.addInst(block, .{ .tag = .addr_of, .ty = .u64, .result_role = .managed_address, .span = Span.empty, .data = .{ .local = slot } }) else initial;
            const bits = try b.addInst(block, .{ .tag = .address_bits, .ty = result, .span = Span.empty, .data = .{ .unary = address } });
            _ = try b.setTerminator(block, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = bits } });
            var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(block, .from(0))));
            defer h.deinit();
            const got = try h.run();
            try testing.expectEqual(managed and result == .u64, got.ok);
            if (!got.ok) try expectSaid(got.said, "requires a managed storage address and a UInt64 result");
        }
    }
}

test "float math verifies complete operand and result shapes" {
    const Operation = @import("../support/float_math.zig").Operation;
    const cases = [_]struct {
        operation: Operation = .sqrt,
        lhs: TypeId = .f64,
        rhs: ?TypeId = null,
        result: TypeId = .f64,
        invalid_lhs: bool = false,
        valid: bool = false,
    }{
        .{ .valid = true },
        .{ .operation = .pow, .rhs = .f64, .valid = true },
        .{ .lhs = .u64 },
        .{ .result = .u64 },
        .{ .rhs = .f64 },
        .{ .operation = .pow },
        .{ .operation = .pow, .rhs = .u64 },
        .{ .invalid_lhs = true },
    };
    for (cases) |case| {
        const gpa = testing.allocator;
        var b = Builder.init(gpa);
        defer b.deinit();
        b.return_type = .u8;
        const entry = try b.addBlock();
        const lhs = try b.addInst(entry, .{ .tag = .constant, .ty = case.lhs, .span = Span.empty, .data = .{ .constant = 0 } });
        const rhs = if (case.rhs) |ty| try b.addInst(entry, .{ .tag = .constant, .ty = ty, .span = Span.empty, .data = .{ .constant = 0 } }) else .none;
        _ = try b.addInst(entry, .{ .tag = .float_math, .ty = case.result, .span = Span.empty, .data = .{ .float_math = .{
            .operation = case.operation,
            .lhs = if (case.invalid_lhs) InstId.at(100) else lhs,
            .rhs = rhs,
        } } });
        const zero = try b.addInst(entry, .{ .tag = .constant, .ty = .u8, .span = Span.empty, .data = .{ .constant = 0 } });
        _ = try b.setTerminator(entry, .{ .tag = .ret, .ty = .unit, .span = Span.empty, .data = .{ .unary = zero } });
        var h = try Harness.init(gpa, try oneFunction(gpa, try b.finish(entry, .from(0))));
        defer h.deinit();
        const got = try h.run();
        try testing.expectEqual(case.valid, got.ok);
    }
}
