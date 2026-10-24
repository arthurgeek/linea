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
const mir_mod = @import("mir.zig");
const Mir = mir_mod.Mir;
const Module = mir_mod.Module;
const InstId = mir_mod.InstId;
const BlockId = mir_mod.BlockId;
const lower = @import("lower.zig").lower;
const lowerTree = @import("lower.zig").lowerTree;
const checkOwnershipTree = @import("../ownership/check.zig").checkTree;

/// Shows the code that will be generated, before the backend erases what it
/// knows.
///
/// Emitted IR says what was produced; this says what was meant. The two
/// separate a lowering failure from an emission one, which the IR alone cannot
/// do because it carries neither types nor source locations. Output has no
/// stability guarantee.
/// The name is asked for by handle rather than walked beside the functions.
/// Two tables iterated in parallel assert that they are the same length, and
/// that assertion is deleted from a build compiled with safety off -- where the
/// shorter table would then be read past its end, yielding a `[]const u8` whose
/// pointer and length both come from past the allocation.
pub fn dumpModule(w: *std.Io.Writer, module: *const Module) std.Io.Writer.Error!void {
    for (module.statics, 0..) |entry, i| try dumpStatic(w, module, entry, i);
    for (module.functions, 0..) |*f, i| {
        try w.print("function {s}\n", .{module.nameOf(.at(@intCast(i)))});
        try dumpMir(w, module, f);
    }
}

/// A static's type, then each part: its offset, its type and what it holds.
/// A part holding a blob's address names the blob as `bytes_addr` does.
fn dumpStatic(w: *std.Io.Writer, module: *const Module, entry: mir_mod.Static, i: usize) std.Io.Writer.Error!void {
    try w.print("static s{d} {s}\n", .{ i, module.types.nameOf(entry.ty) });
    for (entry.parts) |part| {
        try w.print("  +{d} {s}", .{ part.offset, module.types.nameOf(part.ty) });
        switch (part.value) {
            .constant => |value| try w.print(" {d}\n", .{value}),
            .bytes => |blob| try w.print(" bytes{d}\n", .{blob}),
        }
    }
}

/// The module's own type table answers what a handle is. Without it every
/// declared type prints as `<compound>` -- `TypeId.nameOf` answers for the
/// builtins alone, which is what a diagnostic needs and not what a reader
/// asking which type a slot holds does.
pub fn dumpMir(
    w: *std.Io.Writer,
    module: *const Module,
    mir: *const Mir,
) std.Io.Writer.Error!void {
    for (mir.locals, 0..) |ty, i| {
        const local = mir_mod.LocalId.at(@intCast(i));
        try w.print("local ${d} {s}", .{ i, module.types.nameOf(ty) });
        try writeSlotRepresentation(w, module.slotRepresentationOf(mir, local));
        try w.writeByte('\n');
    }

    for (0..mir.blockCount()) |i| {
        const b = BlockId.at(@intCast(i));
        try w.print("@{d}:\n", .{i});
        for (mir.instsOf(b)) |id| try writeInst(w, module, mir, id);
        const t = mir.terminatorOf(b);
        if (t == InstId.none) {
            try w.writeAll("  <unterminated>\n");
        } else {
            try writeInst(w, module, mir, t);
        }
    }
}

fn writeInst(
    w: *std.Io.Writer,
    module: *const Module,
    mir: *const Mir,
    id: InstId,
) std.Io.Writer.Error!void {
    const tag = mir.tagOf(id);
    const ty = mir.typeOf(id);

    if (tag == .function_addr or tag == .foreign_function_addr) {
        try w.print("  %{d} = {s} @f{d} : {s}\n", .{
            id.index(),
            @tagName(tag),
            mir.functionOf(id).index(),
            module.types.nameOf(ty),
        });
        return;
    }
    if (tag == .call_indirect or tag == .call_indirect_noreturn) {
        const call = mir.indirectCallOf(id);
        if (tag == .call_indirect) {
            try w.print("  %{d} = call_indirect %{d}(", .{ id.index(), call.callee.index() });
        } else {
            try w.print("  call_indirect_noreturn %{d}(", .{call.callee.index()});
        }
        for (call.args, 0..) |arg, i| {
            if (i > 0) try w.writeAll(", ");
            try w.print("%{d}", .{arg.index()});
        }
        if (tag == .call_indirect) {
            try w.print(") : {s}\n", .{module.types.nameOf(ty)});
        } else {
            try w.writeAll(")\n");
        }
        return;
    }

    // A terminator produces nothing and is typed by nothing, so it is written
    // bare. A store produces nothing either, but its type is what decides how
    // many bytes it moves -- so it is written where the name would be, rather
    // than left out along with the name.
    if (tag.isTerminator()) {
        try w.print("  {s}", .{@tagName(tag)});
    } else if (tag == .store or tag == .store_indirect or tag == .store_raw or tag == .copy_value or tag == .move_value) {
        try w.print("  {s} {s}", .{ @tagName(tag), module.types.nameOf(ty) });
    } else {
        try w.print("  %{d} = {s} {s}", .{ id.index(), @tagName(tag), module.types.nameOf(ty) });
        try writeResultRepresentation(w, module.resultRepresentationOf(mir, id));
    }

    switch (tag) {
        .constant => try w.print(" {d}", .{mir.constantOf(id)}),
        .bytes_addr => try w.print(" bytes{d}", .{mir.bytesOf(id)}),
        .static_addr => try w.print(" s{d}", .{mir.staticOf(id)}),
        .load, .addr_of => try w.print(" ${d}", .{mir.localOf(id).index()}),
        .load_indirect, .borrow, .observe, .address_bits => try w.print(" %{d}", .{mir.unaryOf(id).index()}),
        .load_raw, .storage_addr => try w.print(" %{d}", .{mir.rawAccessOf(id).address.index()}),
        .store_raw => {
            const raw = mir.rawAccessOf(id);
            try w.print(" %{d}, %{d}", .{ raw.address.index(), raw.value.index() });
        },
        .store_indirect, .field_addr, .copy_value, .move_value => {
            const p2 = mir.binaryOf(id);
            try w.print(" %{d}, %{d}", .{ p2.lhs.index(), p2.rhs.index() });
        },
        .store => {
            const s = mir.storeOf(id);
            try w.print(" ${d} %{d}", .{ s.local.index(), s.value.index() });
        },
        .add, .sub, .mul, .div, .rem, .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => {
            const p = mir.binaryOf(id);
            try w.print(" %{d}, %{d}", .{ p.lhs.index(), p.rhs.index() });
        },
        .float_math => {
            const math = mir.floatMathOf(id);
            try w.print(" {s} %{d}", .{ @tagName(math.operation), math.lhs.index() });
            if (math.operation.arity() == 2) try w.print(", %{d}", .{math.rhs.index()});
        },
        .neg, .int_to_float, .float_to_int, .float_extend, .float_truncate => try w.print(" %{d}", .{mir.unaryOf(id).index()}),
        .check => {
            const c = mir.checkOf(id);
            try w.print(" %{d} ({s})", .{ c.value.index(), @tagName(c.kind) });
        },
        .ret => try w.print(" %{d}", .{mir.unaryOf(id).index()}),
        .jump => try w.print(" @{d}", .{mir.targetOf(id).index()}),
        .branch => {
            const br = mir.branchOf(id);
            try w.print(" %{d}, @{d}, @{d}", .{
                br.cond.index(), br.then_block.index(), br.else_block.index(),
            });
        },
        .trap => {
            const trap = mir.trapOf(id);
            try w.print(" {s}", .{@tagName(trap.kind)});
            if (trap.message != .none) try w.print(" %{d}", .{trap.message.index()});
        },
        .call, .call_noreturn => {
            const c = mir.callOf(id);
            try w.print(" @f{d}(", .{c.func.index()});
            for (c.args, 0..) |a, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("%{d}", .{a.index()});
            }
            try w.writeAll(")");
        },
        .function_addr, .foreign_function_addr, .call_indirect, .call_indirect_noreturn => unreachable,
    }

    try w.writeByte('\n');
}

/// The integer type a tag is computed and stored in: as wide as its layout.
const tag_register = std.fmt.comptimePrint("i{d}", .{@import("../sema/types.zig").Layout.tag_width * 8});

fn writeResultRepresentation(w: *std.Io.Writer, representation: mir_mod.ResultRepresentation) std.Io.Writer.Error!void {
    switch (representation) {
        .none => {},
        .managed_address => try w.writeAll(" managed-address"),
        .computation => |computation| {
            try w.writeAll(" value computation=");
            try w.writeAll(switch (computation) {
                .integer, .unit => "i64",
                .enum_tag => tag_register,
                .boolean => "i1",
                .float => |bits| if (bits == 32) "f32" else "f64",
                .indirect => "indirect",
                .code_pointer, .data_pointer => "ptr",
                .no_value => "no-value",
                .invalid => "invalid",
            });
        },
    }
}

fn writeSlotRepresentation(w: *std.Io.Writer, representation: mir_mod.SlotRepresentation) std.Io.Writer.Error!void {
    switch (representation) {
        .managed_address => try w.writeAll(" managed-address"),
        .storage => |storage| {
            try w.writeAll(" value storage=");
            switch (storage) {
                .integer => |integer| try w.print("i{d}", .{integer.bits}),
                .boolean => try w.writeAll("i8(bool)"),
                .float => |bits| try w.print("f{d}", .{bits}),
                .enum_tag => try w.writeAll(tag_register),
                .unit => try w.writeAll("i64"),
                .bytes => try w.writeAll("bytes"),
                .code_pointer, .data_pointer => try w.writeAll("ptr"),
                .no_value => try w.writeAll("no-value"),
                .invalid => try w.writeAll("invalid"),
            }
        },
    }
}

fn dumpToString(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    const source: Source = .{ .path = "t.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    defer res.deinit(gpa);
    var typing = try typecheckTree(gpa, &res, &sink);
    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer disposals.deinit(gpa);
    const mir = (try lowerTree(gpa, &res, &typing, &disposals, &sink, .program)) orelse return error.SourceRejected;

    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpModule(&out.writer, &mir);
    return out.written();
}

test "an operation is shown with its type and its check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try dumpToString(arena.allocator(), "fn main() -> UInt8 { 1 + 2 }");
    try testing.expectEqualStrings(
        \\function ;main
        \\@0:
        \\  %0 = constant UInt8 value computation=i64 1
        \\  %1 = constant UInt8 value computation=i64 2
        \\  %2 = add UInt8 value computation=i64 %0, %1
        \\  %3 = check UInt8 value computation=i64 %2 (overflow)
        \\  ret %3
        \\
    , got);
}

test "a binding is shown as a local, a store and a load" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try dumpToString(arena.allocator(), "fn main() -> UInt8 { let x: UInt8 = 4; x }");
    try testing.expectEqualStrings(
        \\function ;main
        \\local $0 UInt8 value storage=i8
        \\@0:
        \\  %0 = constant UInt8 value computation=i64 4
        \\  store UInt8 $0 %0
        \\  %2 = load UInt8 value computation=i64 $0
        \\  ret %2
        \\
    , got);
}

test "callable operations put their semantic type after their operands" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try dumpToString(arena.allocator(),
        \\fn main() -> UInt8 {
        \\    let increment: fn(read value: UInt8) -> UInt8 = |value| value + 1
        \\    increment(4)
        \\}
    );
    try testing.expect(std.mem.indexOf(
        u8,
        got,
        "%0 = function_addr @f1 : fn(read UInt8) -> UInt8",
    ) != null);
    try testing.expect(std.mem.indexOf(
        u8,
        got,
        "%4 = call_indirect %2(%3) : UInt8",
    ) != null);
}

test "every instruction appears exactly once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const source: Source = .{ .path = "t.lin", .text = "fn main() -> UInt8 { let x: UInt8 = 4; x * 2 + 1 }" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    defer res.deinit(gpa);
    var typing = try typecheckTree(gpa, &res, &sink);
    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer disposals.deinit(gpa);
    const mir = (try lowerTree(gpa, &res, &typing, &disposals, &sink, .program)) orelse return error.SourceRejected;

    var out: std.Io.Writer.Allocating = .init(gpa);
    try dumpModule(&out.writer, &mir);

    // One line per instruction, plus one per local and one per block header.
    const f = &mir.functions[0];
    // One line per instruction, per local and per block header, plus the
    // function's own header line.
    const lines = std.mem.count(u8, out.written(), "\n");
    try testing.expectEqual(f.insts.len + f.locals.len + f.blockCount() + 1, lines);
}

test "a while is a header that tests, a body that returns to it, and an exit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // The back edge is the first edge that is not forward: @2 ends by jumping
    // to @1, which is the block that tested the condition.
    const got = try dumpToString(
        arena.allocator(),
        "fn main() -> UInt8 { var i: UInt8 = 0; while i < 2 { i = i + 1; } i }",
    );
    try testing.expect(std.mem.indexOf(u8, got, "branch") != null);
    try testing.expect(std.mem.indexOf(u8, got, "jump @1") != null);
}

test "a copy is shown with the type that decides how many bytes it moves" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const got = try dumpToString(arena.allocator(),
        \\struct Pair {
        \\    a: UInt64,
        \\    b: UInt64,
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let p: Pair = .{ a = 1, b = 2 }
        \\    let q = p
        \\    match q {
        \\        Pair { a: _a, b: _b } => 0,
        \\    }
        \\}
    );

    // The width of a blit is its type's size, and the dump said neither which
    // type nor that there was one -- so two blits of different aggregates read
    // as the same instruction.
    try testing.expect(std.mem.indexOf(u8, got, "move_value Pair") != null);
    try testing.expect(std.mem.indexOf(u8, got, "local $0 Pair value storage=bytes") != null);
    try testing.expect(std.mem.indexOf(u8, got, "addr_of Pair managed-address") != null);
    try testing.expect(std.mem.indexOf(u8, got, "<compound>") == null);
}
