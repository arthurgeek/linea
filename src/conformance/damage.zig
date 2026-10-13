const std = @import("std");
const testing = std.testing;

const types_mod = @import("../sema/types.zig");
const Layout = types_mod.Layout;
const TypeId = types_mod.TypeId;

const mir_mod = @import("../mir/mir.zig");
const Module = mir_mod.Module;
const Mir = mir_mod.Mir;
const InstId = mir_mod.InstId;
const FunctionId = mir_mod.FunctionId;

test "representation damage must be refused" {
    try testing.expectEqual(Damage.Oracle.must_refuse, Damage.result_role.oracle());
    try testing.expectEqual(Damage.Oracle.must_refuse, Damage.type_representation.oracle());
    try testing.expectEqual(Damage.Oracle.machine, Damage.field_offset.oracle());
    try testing.expectEqual(Damage.Oracle.machine, Damage.slot_width.oracle());
}

/// A change to a module the backend is about to emit, built to change what the
/// program does.
///
/// The mutations in `mutate.zig` are the same idea one level up: a change built
/// to be ill-formed, paired with the rule that must refuse it. The rule is what
/// makes silence a failure there, and no rule can play that part here — every
/// module reaching the backend has already satisfied every rule the language
/// states, and whether what is left is malformed is exactly the question the
/// verifier answers. Asking it to adjudicate its own answer proves nothing.
///
/// **So the oracle is the machine.** The undamaged module is built and run, the
/// damaged one is handed to the same backend, and the two answers are compared:
///
///   - the backend refused it — the verifier objected, which is the whole of
///     what this asks for, and there is nothing to run;
///   - it emitted, and the program answers what it answered — the damage was
///     inert, and saying nothing about it was right;
///   - it emitted, and the answer moved — the meaning of the program changed
///     and nothing objected, which is a miss;
///   - it emitted, and the toolchain refused the result — the verifier let
///     through what the next tool would not take.
///
/// Nobody has to decide in advance what "malformed" means, which is what keeps
/// this from being the verifier restated.
///
/// **What is damaged, and what deliberately is not.** Both of these move an
/// access outside the object it names, which is what the verifier reasons over
/// and what the language's no-undefined-behaviour rule turns on below MIR.
/// Three other candidates were weighed and left out:
///
///   - **a terminator's target.** A jump to another real block changes what a
///     program computes and leaves a perfectly well-formed module: no address
///     moved. The verifier is right to say nothing, so the property would
///     report a miss that is not one.
///   - **a constant.** It changes meaning and tests nothing about memory. The
///     verifier reads a constant only where one is an offset, which is what
///     `field_offset` damages already.
///   - **an access width.** It cannot be moved without landing on a real part
///     of the container — a memory-safe module that answers differently, which
///     the verifier is right to accept — unless the damage first works out
///     which widths are parts of what, and that is the verifier's own
///     arithmetic written a second time.
pub const Damage = enum {
    /// Pushes one field address past every object in the module.
    field_offset,
    /// Narrows one slot below the value it holds.
    slot_width,
    /// Marks an ordinary constant as a managed address.
    result_role,
    /// Changes the canonical UInt8 storage representation to Float64.
    type_representation,

    pub const Oracle = enum { machine, must_refuse };

    pub fn oracle(self: Damage) Oracle {
        return switch (self) {
            .field_offset, .slot_width => .machine,
            .result_role, .type_representation => .must_refuse,
        };
    }

    /// What the damage asserts, for a failure to read as a sentence.
    pub fn why(self: Damage) []const u8 {
        return switch (self) {
            .field_offset => "an address pushed past every object is refused before it is emitted",
            .slot_width => "a slot too small for the value in it is refused before it is emitted",
            .result_role => "an incorrect instruction result role is refused before it is emitted",
            .type_representation => "an incorrect type representation is refused before it is emitted",
        };
    }

    /// Damages a private module, retaining the one changed value for restoration.
    /// The caller restores it before applying another damage or releasing storage.
    pub fn apply(self: Damage, module: *Module) ?Undo {
        return switch (self) {
            .field_offset => fieldOffset(module),
            .slot_width => slotWidth(module),
            .result_role => resultRole(module),
            .type_representation => typeRepresentation(module),
        };
    }
};

fn Edit(comptime T: type) type {
    return struct {
        destination: *T,
        original: T,

        fn replace(destination: *T, replacement: T) @This() {
            const edit: @This() = .{ .destination = destination, .original = destination.* };
            destination.* = replacement;
            return edit;
        }
    };
}

/// The original value of the single location a damage changes. Its storage
/// belongs to the private module and must outlive this edit.
pub const Undo = union(enum) {
    constant: Edit(i128),
    ty: Edit(TypeId),
    role: Edit(mir_mod.ResultRole),
    representation: struct {
        table: *mir_mod.TypeRepresentations,
        original: mir_mod.TypeRepresentation,
    },

    pub fn restore(self: Undo) void {
        switch (self) {
            .representation => |edit| edit.table.set(.u8, edit.original),
            inline .constant, .ty, .role => |edit| edit.destination.* = edit.original,
        }
    }
};

/// How far past its object an access is pushed, and why it is this far.
///
/// Past every object in any module here, so the access provably leaves whatever
/// it named — which is what makes silence about it a miss rather than a
/// judgement call. And far enough to be a page nothing mapped, so a program
/// emitted from a module nobody objected to faults rather than quietly reading
/// its neighbour: the oracle answers instead of shrugging.
const beyond: u32 = 1 << 30;

/// Whether `beyond` is past every object this module describes.
///
/// A type may be as wide as an offset can record, so a module holding one wider
/// than this is one the constant says nothing about. Nothing is damaged there
/// rather than something being damaged on a claim that does not hold.
fn reaches(module: *const Module) bool {
    for (module.layouts) |l| {
        if (l.size >= beyond) return false;
    }
    return true;
}

/// Moves the first field address in the module past every object.
///
/// The offset is a constant instruction, so this rewrites that instruction. One
/// shared by something other than an address moves that too, which changes more
/// than intended and never less: the address is out of bounds either way.
fn fieldOffset(module: *Module) ?Undo {
    if (!reaches(module)) return null;

    for (module.functions) |*f| {
        for (0..f.insts.len) |i| {
            const id = InstId.at(@intCast(i));
            if (f.tagOf(id) != .field_addr) continue;

            const off = f.binaryOf(id).rhs;
            if (f.tagOf(off) != .constant) continue;
            if (f.constantOf(off) == beyond) continue;

            return .{ .constant = Edit(i128).replace(&f.insts.items(.data)[off.index()].constant, beyond) };
        }
    }
    return null;
}

/// Retypes the first slot holding an aggregate wider than a machine word to a
/// word.
///
/// The slot rule gives an aggregate a slot as wide as the value and everything
/// else a word, so this is the slot losing every byte past the first eight —
/// while the code that fills it goes on writing the whole value.
fn slotWidth(module: *Module) ?Undo {
    for (module.functions) |*f| {
        for (f.locals, 0..) |t, i| {
            const l = module.layoutOf(t);
            if (!l.isAggregate() or l.size <= Layout.word) continue;

            // The one write into a finished representation, and it is the point
            // of the file: what is being built is a module that is wrong.
            return .{ .ty = Edit(TypeId).replace(&@constCast(f.locals)[i], .u64) };
        }
    }
    return null;
}

fn resultRole(module: *Module) ?Undo {
    for (module.functions) |*f| {
        for (0..f.insts.len) |i| {
            const id = InstId.at(@intCast(i));
            if (f.tagOf(id) != .constant or f.resultRoleOf(id) != .value) continue;
            return .{ .role = Edit(mir_mod.ResultRole).replace(&f.insts.items(.result_role)[i], .managed_address) };
        }
    }
    return null;
}

fn typeRepresentation(module: *Module) ?Undo {
    if (TypeId.u8.index() >= module.representations.len()) return null;
    var row = module.representations.get(.u8);
    if (row.storage == .float64) return null;
    const undo: Undo = .{ .representation = .{ .table = &module.representations, .original = row } };
    row.storage = .float64;
    module.representations.set(.u8, row);
    return undo;
}

/// A module of no code, carrying whatever layouts a case wants to describe.
fn moduleDescribing(functions: []Mir, names: [][]const u8, layouts: []const Layout) Module {
    return .{
        .functions = functions,
        .bytes = &.{},
        .external = &.{},
        .names = names,
        .origins = &.{},
        .layouts = layouts,
        .entry = .at(0),
    };
}

test "damage that finds nowhere to land says so" {
    // A module with no code at all: no field address to move, and no slot to
    // narrow. Both answer null rather than reporting a site they did not
    // change, which is what stops a run counting a damage it never made.
    var none: [0]Mir = .{};
    var unnamed: [0][]const u8 = .{};
    var module = moduleDescribing(&none, &unnamed, &.{});

    for (std.enums.values(Damage)) |d| {
        try testing.expect(d.apply(&module) == null);
    }
}

test "an offset past every object is past the widest one" {
    var none: [0]Mir = .{};
    var unnamed: [0][]const u8 = .{};

    // The constant is a claim about the module it is used in, and the claim is
    // checked rather than assumed.
    var ordinary = moduleDescribing(&none, &unnamed, &.{
        .{ .size = 8, .alignment = 8 },
        .{ .size = 24, .alignment = 8, .indirect = true },
    });
    try testing.expect(reaches(&ordinary));

    // A module describing a type as wide as an offset can record is one the
    // constant does not hold for, and nothing is damaged there rather than
    // something being damaged on a claim that has stopped being true.
    var vast = moduleDescribing(&none, &unnamed, &.{
        .{ .size = beyond, .alignment = 8, .indirect = true },
    });
    try testing.expect(!reaches(&vast));
    try testing.expect(Damage.field_offset.apply(&vast) == null);
}

test "damage restoration isolates every variant on a reused module" {
    const gpa = testing.allocator;
    var insts: mir_mod.InstList = .empty;
    defer insts.deinit(gpa);
    const instructions = [_]mir_mod.Inst{
        .{ .tag = .constant, .ty = .u8, .span = .{ .start = 0, .end = 0 }, .data = .{ .constant = 7 } },
        .{ .tag = .field_addr, .ty = .u8, .span = .{ .start = 0, .end = 0 }, .data = .{ .binary = .{ .lhs = .at(0), .rhs = .at(0) } } },
        .{ .tag = .function_addr, .ty = .u8, .span = .{ .start = 0, .end = 0 }, .data = .{ .function = .at(0) } },
        .{ .tag = .call_indirect, .ty = .u8, .span = .{ .start = 0, .end = 0 }, .data = .{ .indirect_call = .{ .callee = .at(2), .args = .at(0) } } },
    };
    for (instructions) |inst| try insts.append(gpa, inst);
    var locals = [_]TypeId{.u8};
    var extra = [_]InstId{.at(0)};
    const function: Mir = .{
        .insts = insts.slice(),
        .block_insts = &.{},
        .blocks = &.{},
        .locals = &locals,
        .entry = .at(0),
        .extra = &extra,
        .call_sites = &.{},
        .param_count = 0,
        .slot_roles = &.{.value},
        .file = .from(0),
        .return_type = .u8,
        .signature = .u8,
    };
    var functions = [_]Mir{ function, function };
    functions[1].signature = .u64;
    var names = [_][]const u8{ "first", "second" };
    const count = TypeId.u8.index() + 1;
    const layouts = try gpa.alloc(Layout, count);
    defer gpa.free(layouts);
    @memset(layouts, .{ .size = 24, .alignment = 8, .indirect = true });
    var module = moduleDescribing(&functions, &names, layouts);
    module.representations = try mir_mod.TypeRepresentations.of(gpa, count, .{
        .computation = .{ .integer = .unsigned },
        .storage = .{ .integer = .{ .signedness = .unsigned, .bits = 8 } },
    });
    defer module.representations.deinit(gpa);
    const Snapshot = struct {
        constant: i128,
        local: TypeId,
        role: mir_mod.ResultRole,
        representation: mir_mod.TypeRepresentation,
        target: FunctionId,
        signature: TypeId,
        callee: InstId,
        extent: InstId,
        fn of(m: *const Module) @This() {
            const f = &m.functions[0];
            return .{
                .constant = f.insts.items(.data)[0].constant,
                .local = f.locals[0],
                .role = f.insts.items(.result_role)[0],
                .representation = m.representations.get(.u8),
                .target = f.insts.items(.data)[2].function,
                .signature = f.insts.items(.ty)[2],
                .callee = f.insts.items(.data)[3].indirect_call.callee,
                .extent = f.extra[0],
            };
        }
    };
    const baseline = Snapshot.of(&module);
    for (std.enums.values(Damage)) |damage| {
        const applied = damage.apply(&module) orelse return error.DamageNotApplied;
        const damaged = Snapshot.of(&module);
        try testing.expect(!std.meta.eql(baseline, damaged));
        applied.restore();
        try testing.expectEqualDeep(baseline, Snapshot.of(&module));
        {
            const again = damage.apply(&module) orelse return error.DamageNotApplied;
            defer again.restore();
            try testing.expectEqualDeep(damaged, Snapshot.of(&module));
        }
        try testing.expectEqualDeep(baseline, Snapshot.of(&module));
    }
}
