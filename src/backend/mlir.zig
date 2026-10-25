//! Prints MLIR.
//!
//! Emission is a function from a module to text a caller writes somewhere, so
//! the module stays immutable, the pass stays a function, and what the backend
//! produced can be compared against a golden. MLIR offers a library that would
//! build a module instead, and taking it would mean a long-lived mutable
//! object between MIR and the machine that this compiler neither owns nor
//! controls.
//!
//! What is printed is `func`, `cf` and `arith`, with `llvm` where those three
//! have nothing to say -- a frame slot, an overflow intrinsic, a call to a
//! runtime symbol. Above the LLVM dialect, because emitting that directly would
//! reduce translation to a copy and give up the conversions that are the whole
//! reason for this backend.
//!
//! An exhaustive instruction switch covers every MIR operation. Emission may
//! forward a terminal aggregate call into the caller's result storage, eliding
//! its temporary copy and empty return join without changing the MIR.

const std = @import("std");
const tracy = @import("../support/tracy.zig");
const testing = std.testing;

const source_mod = @import("../support/source.zig");
const FileTable = source_mod.FileTable;
const FileId = source_mod.FileId;
const SourceMap = source_mod.SourceMap;
const mir_mod = @import("../mir/mir.zig");
const verify = @import("../mir/verify.zig").verify;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Mir = mir_mod.Mir;
const Module = mir_mod.Module;
const FunctionId = mir_mod.FunctionId;
const InstId = mir_mod.InstId;
const BlockId = mir_mod.BlockId;
const TrapKind = mir_mod.TrapKind;
const types_mod = @import("../sema/types.zig");
const TypeId = types_mod.TypeId;
const Span = @import("../support/span.zig").Span;

const FloatMathOperation = @import("../support/float_math.zig").Operation;
const runtime_symbols = @import("../support/runtime_symbols.zig");
const symbol_names = @import("../support/symbol.zig");

/// The names a trap expansion gives the constants holding its line and its
/// column. Public because the conformance comparator classifies these by name
/// -- their values are position, not code, and a rewritten program's traps
/// report other lines -- and one spelling shared is what keeps the emitter and
/// the comparator one implementation of that rule rather than two that drift.
/// Nothing else in this file may mint a name with either prefix.
pub const trap_file_name = "tf";
pub const panic_file_name = "pf";
pub const trap_line_name = "tl";
pub const trap_col_name = "tc";

/// The version of the contract between generated code and the runtime. The
/// symbol it builds is resolved by the linker on every program, so a program
/// built against the wrong runtime refuses to link rather than running with
/// halves that disagree. It stays 1 until the runtime ships separately from the
/// compiler.
const runtime_abi = 1;

/// The width the C runtime exchanges a status in. Named once: the wrapper's
/// result, the entry's, and the narrowing between them have to agree, and
/// three spellings of one width is three places to be wrong.
const runtime_int = mlirType(.i32);

/// The register type every integer is computed in, and the width of an
/// address: this backend targets 64-bit pointers, stated here as the invariant
/// it is rather than left as a consequence of two spellings agreeing. A
/// narrower target is a different decision, recorded before it exists.
///
///
/// Not the width its type names. `[T-Overflow]` is enforced by a `check`
/// instruction that range-tests a result, so the arithmetic before it happens
/// at full width and the narrowing is the check's business. Printing `i8` for a
/// `UInt8` add would move where overflow happens into the arithmetic, which is
/// a second answer to a question the module already answers -- and the two
/// would disagree exactly on the program that overflows.
const int_type = "i64";

comptime {
    // A tag is computed and stored in the register type, so that type is as
    // wide as the layout gives the tag.
    const register_bits = std.fmt.parseInt(u32, int_type[1..], 10) catch unreachable;
    if (register_bits != types_mod.Layout.tag_width * 8) @compileError("the register type is not as wide as an enum tag");
}

/// The MLIR type of an IEEE 754 binary float of `bits` bits.
fn floatType(bits: u8) []const u8 {
    return switch (bits) {
        32 => "f32",
        64 => "f64",
        else => std.debug.panic("compiler defect: a float is {d} bits wide", .{bits}),
    };
}

/// The bit pattern MLIR spells a float constant with, at the constant's own
/// width. `value` is exact at that width: a `Float32` constant is carried as
/// the double holding the same value.
fn floatConstantBits(value: f64, bits: u8) u64 {
    return switch (bits) {
        32 => @as(u32, @bitCast(@as(f32, @floatCast(value)))),
        64 => @bitCast(value),
        else => std.debug.panic("compiler defect: a float is {d} bits wide", .{bits}),
    };
}

/// The positive quiet NaN of a float of `bits` bits: the exponent all ones
/// and only the top fraction bit set.
fn canonicalNanBits(bits: u8) u64 {
    return switch (bits) {
        32 => 0x7FC00000,
        64 => 0x7FF8000000000000,
        else => std.debug.panic("compiler defect: a float is {d} bits wide", .{bits}),
    };
}

/// The SSA names one canonicalisation writes: `result` is defined from `raw`,
/// through `unordered` and `quiet`.
const CanonicalNames = struct {
    result: []const u8,
    raw: []const u8,
    unordered: []const u8,
    quiet: []const u8,
};

/// Writes `%result` as `%raw` with every NaN made the positive quiet NaN,
/// ending each line with the source location `here` gives, or with none.
/// Every float a program holds passes through it once, where it is made:
/// by arithmetic, a conversion or a math call, or by C. LLVM leaves which NaN
/// an arithmetic operation produces to the target and to constant folding
/// (x86's is negative, AArch64's positive), C may build any NaN, and a NaN's
/// bits are observable through `to_bits`, so without it a program's result
/// would depend on where and how it was built. A select is not arithmetic, so
/// it keeps the bits it chooses, and folding it can only produce the
/// canonical NaN.
fn writeCanonicalNan(w: *std.Io.Writer, names: CanonicalNames, bits: u8, here: ?FunctionEmitter.Here) std.Io.Writer.Error!void {
    const t = floatType(bits);
    try w.print("    %{s} = arith.cmpf uno, %{s}, %{s} : {s}", .{ names.unordered, names.raw, names.raw, t });
    try endLine(w, here);
    try w.print("    %{s} = arith.constant 0x{X} : {s}", .{ names.quiet, canonicalNanBits(bits), t });
    try endLine(w, here);
    try w.print("    %{s} = arith.select %{s}, %{s}, %{s} : {s}", .{ names.result, names.unordered, names.quiet, names.raw, t });
    try endLine(w, here);
}

fn endLine(w: *std.Io.Writer, here: ?FunctionEmitter.Here) std.Io.Writer.Error!void {
    if (here) |at| try at.emitter.here(at.span) else try w.writeAll("\n");
}

/// Writes the float C left at `address` back canonicalised, where `ty` is a
/// float: C wrote it through an `inout` parameter, or a C caller handed it to
/// an entry by address. `tag` keeps the names apart.
fn writeCanonicalNanAt(w: *std.Io.Writer, module: *const Module, ty: TypeId, address: []const u8, tag: []const u8, here: ?FunctionEmitter.Here) std.Io.Writer.Error!void {
    const bits = floatBitsOf(module.representationOf(ty).computation) orelse return;
    const t = floatType(bits);
    var buffers: [4][32]u8 = undefined;
    const names: CanonicalNames = .{
        .raw = std.fmt.bufPrint(&buffers[0], "{s}l", .{tag}) catch unreachable,
        .unordered = std.fmt.bufPrint(&buffers[1], "{s}u", .{tag}) catch unreachable,
        .quiet = std.fmt.bufPrint(&buffers[2], "{s}q", .{tag}) catch unreachable,
        .result = std.fmt.bufPrint(&buffers[3], "{s}c", .{tag}) catch unreachable,
    };
    try w.print("    %{s} = llvm.load {s} : !llvm.ptr -> {s}", .{ names.raw, address, t });
    try endLine(w, here);
    try writeCanonicalNan(w, names, bits, here);
    try w.print("    llvm.store %{s}, {s} : {s}, !llvm.ptr", .{ names.result, address, t });
    try endLine(w, here);
}

/// The width of a float computation, or null for any other.
fn floatBitsOf(computation: mir_mod.ComputationRepresentation) ?u8 {
    return switch (computation) {
        .float => |bits| bits,
        else => null,
    };
}

/// Answers whether anything was written. A refusal has already said why,
/// through the sink.
///
/// The module is verified here, inside the function emitting is a precondition
/// of: a check placed in a caller is discharged by everyone who remembers, and
/// this function's callers are several rather than one.
pub fn emit(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    module: *const Module,
    table: *FileTable,
    sink: *Sink,
) (std.mem.Allocator.Error || std.Io.Writer.Error)!bool {
    const zone = tracy.beginZone(@src(), "emit.mlir");
    defer zone.end();

    {
        const z = tracy.beginZone(@src(), "emit.mlir.verify");
        defer z.end();
        if (!try verify(gpa, module, sink)) return false;
    }

    // A type alias is declared outside the module it is used in.
    for (module.statics, 0..) |entry, i| try writeStaticType(w, module, entry, i);
    try w.writeAll("module {\n");
    if (module.zeroed_allocator != .none) {
        try w.writeAll("  func.func private @llvm.is.constant.i1(i1) -> i1\n");
        try w.writeAll("  func.func private @llvm.assume(i1)\n");
    }

    // A relocation against the runtime's version symbol, pinned by
    // `llvm.used`. It is never read at run time; its only job is to make a
    // version mismatch a link failure. The pin is load-bearing and was found
    // by its absence: an internal global nothing references is dropped at code
    // generation even unoptimised, and it takes the undefined reference -- the
    // whole point of the data -- with it. Assembly text needed no pin, because
    // an assembler emits what is written; a code generator keeps what is used.
    try w.print(
        "  llvm.mlir.global external @linea_runtime_abi_{d}() {{addr_space = 0 : i32}} : i64\n",
        .{runtime_abi},
    );
    try w.writeAll("  llvm.mlir.global internal @linea_abi() {addr_space = 0 : i32} : !llvm.ptr {\n");
    try w.print("    %a = llvm.mlir.addressof @linea_runtime_abi_{d} : !llvm.ptr\n", .{runtime_abi});
    try w.writeAll("    llvm.return %a : !llvm.ptr\n");
    try w.writeAll("  }\n");
    try w.writeAll("  llvm.mlir.global appending @llvm.used() {addr_space = 0 : i32, section = \"llvm.metadata\"} : !llvm.array<1 x ptr> {\n");
    try w.writeAll("    %a = llvm.mlir.addressof @linea_abi : !llvm.ptr\n");
    try w.writeAll("    %u = llvm.mlir.undef : !llvm.array<1 x ptr>\n");
    try w.writeAll("    %v = llvm.insertvalue %a, %u[0] : !llvm.array<1 x ptr>\n");
    try w.writeAll("    llvm.return %v : !llvm.array<1 x ptr>\n");
    try w.writeAll("  }\n");

    // File symbols follow first use in the emitted function sequence, so
    // unrelated source-table entries cannot change generated code. Distinct
    // files keep distinct symbols even when their diagnostic paths are equal.
    const file_symbols = try gpa.alloc(?u32, table.count());
    defer gpa.free(file_symbols);
    @memset(file_symbols, null);
    var next_file_symbol: u32 = 0;
    for (module.functions) |*f| {
        if (f.file.index() >= file_symbols.len) continue;
        if (file_symbols[f.file.index()] != null) continue;
        const ordinal = next_file_symbol;
        next_file_symbol += 1;
        file_symbols[f.file.index()] = ordinal;
        const path = table.get(f.file).path;
        try w.print("  llvm.mlir.global internal constant @linea_file{d}(\"", .{ordinal});
        try writeMlirString(w, path);
        try w.print("\\00\") : !llvm.array<{d} x i8>\n", .{path.len + 1});
    }

    // The blobs a literal names. No terminating zero: a `Str` carries its
    // length, nothing hands one to C as a C string, and leaving it off is what
    // would let two blobs share a tail later.
    for (module.bytes, 0..) |b, i| {
        try w.print("  llvm.mlir.global internal constant @linea_str{d}(\"", .{i});
        try writeMlirString(w, b);
        try w.print("\") : !llvm.array<{d} x i8>\n", .{b.len});
    }

    for (module.statics, 0..) |entry, i| try writeStatic(w, module, entry, i);

    // What the runtime provides, declared: MLIR refuses a call to a name the
    // module does not hold, where an assembler would have left an unknown
    // symbol for the linker.
    try declareOwned(w, runtime_symbols.set_args_signature);
    // `noreturn` states interprocedurally what every call site already says
    // locally with `llvm.unreachable`: the trap does not come back. Without
    // it the optimiser must plan a continuation after every trap call it
    // considers moving code around.
    try declareOwned(w, runtime_symbols.trap_signature);
    try declareOwned(w, runtime_symbols.panic_signature);

    // Runtime declarations follow the checked operations present in this module.
    var math_operations: [FloatMathOperation.count]bool = @splat(false);
    for (module.functions) |*function| {
        for (function.insts.items(.tag), function.insts.items(.data)) |tag, data| {
            if (tag == .float_math) math_operations[@intFromEnum(data.float_math.operation)] = true;
        }
    }
    for (math_operations, runtime_symbols.math_functions) |used, signature| {
        if (used) try declareOwned(w, signature);
    }

    // A declaration per external, because MLIR refuses a call to a name the
    // module does not hold. The body is the linker's to find; writing one here
    // would put this compiler's invention under a name the runtime already
    // answers to.
    for (module.functions, 0..) |*f, i| {
        const id = FunctionId.at(@intCast(i));
        if (!module.isExternal(id)) continue;
        try w.writeAll("  func.func private @");
        try writeSymbol(w, module, id);
        try w.writeAll("(");
        const indirect = module.returnsIndirectly(id);
        if (indirect) try w.writeAll("!llvm.ptr");
        for (0..f.param_count) |pi| {
            if (pi > 0 or indirect) try w.writeAll(", ");
            try w.writeAll(paramTypeOf(module, id, f, pi));
            if (!module.arrivesByAddress(f, pi)) try writeForeignExtension(w, module, f.locals[pi]);
        }
        try w.writeAll(")");
        // The callable signature records the declared result even though an
        // external has no local body. Verification holds every call to it.
        const answered = module.types.erased(module.types.get(f.signature).callable.result);
        if (resultTypeOf(module, id, answered)) |t| {
            if (foreignExtension(module, answered)) |extension| {
                try w.print(" -> ({s} {s})", .{ t, extension });
            } else {
                try w.print(" -> {s}", .{t});
            }
        }
        if (answered == .never) try w.writeAll(" attributes {passthrough = [\"noreturn\"]}");
        try w.writeAll("\n");
    }

    for (module.functions, 0..) |*f, i| {
        const id = FunctionId.at(@intCast(i));
        if (module.isExternal(id)) continue;
        try emitFunction(gpa, w, module, f, try table.buildMap(gpa, f.file), table.get(f.file).path, id, file_symbols[f.file.index()].?);
    }

    // Only where something is to be entered. A library holds no entry point, so
    // there is nothing for the runtime to call and no wrapper that could call
    // it -- and an object without one is exactly what a library is.
    if (module.entry != .none) try emitEntryWrapper(w, module);

    // What a library is entered through instead: one thunk per export, after
    // every body, so a reader meets a symbol only once its callee is defined.
    for (module.functions, 0..) |*f, i| {
        const id = FunctionId.at(@intCast(i));
        if (module.isExternal(id)) continue;
        const name = module.exportedNameOf(id) orelse continue;
        try emitForeignEntry(w, module, f, id, .{ .exported = name });
    }

    // One C-callable entry per function passed to C as a callback, found in
    // one scan of the instructions.
    const called_back = try gpa.alloc(bool, module.functions.len);
    defer gpa.free(called_back);
    @memset(called_back, false);
    for (module.functions, 0..) |*f, i| {
        if (module.isExternal(FunctionId.at(@intCast(i)))) continue;
        for (0..f.insts.len) |at| {
            const inst = InstId.at(@intCast(at));
            if (f.tagOf(inst) == .foreign_function_addr) called_back[f.functionOf(inst).index()] = true;
        }
    }
    for (module.functions, called_back, 0..) |*f, wanted, i| {
        if (!wanted) continue;
        try emitForeignEntry(w, module, f, FunctionId.at(@intCast(i)), .called_back);
    }

    try w.writeAll("}\n");
    return true;
}

/// The MLIR type a runtime signature's scalar is passed as.
fn mlirType(scalar: runtime_symbols.Scalar) []const u8 {
    return switch (scalar) {
        .u8 => "i8",
        .i32, .u32 => "i32",
        .i64, .u64 => "i64",
        .f32 => "f32",
        .f64 => "f64",
        .ptr => "!llvm.ptr",
        .unit => unreachable,
    };
}

/// A declaration of a symbol the compiler owns, printed from its signature so
/// the widths the runtime is held to are the widths the module declares.
fn declareOwned(w: *std.Io.Writer, signature: runtime_symbols.Signature) std.Io.Writer.Error!void {
    try w.print("  func.func private @{s}(", .{signature.symbol});
    try writeParameterTypes(w, signature);
    try w.writeAll(")");
    if (signature.result != .unit) try w.print(" -> {s}", .{mlirType(signature.result)});
    if (signature.noreturn) try w.writeAll(" attributes {passthrough = [\"noreturn\"]}");
    try w.writeAll("\n");
}

fn writeParameterTypes(w: *std.Io.Writer, signature: runtime_symbols.Signature) std.Io.Writer.Error!void {
    for (signature.parameters, 0..) |parameter, i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll(mlirType(parameter.scalar));
    }
}

/// The type of a call to a symbol the compiler owns: `(parameters) -> result`.
fn writeOwnedCallType(w: *std.Io.Writer, signature: runtime_symbols.Signature) std.Io.Writer.Error!void {
    try w.writeAll(" : (");
    try writeParameterTypes(w, signature);
    try w.writeAll(") -> ");
    if (signature.result == .unit) try w.writeAll("()") else try w.writeAll(mlirType(signature.result));
}

test "owned runtime symbols are declared and called with their table's widths" {
    var buffer: [512]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffer);
    try declareOwned(&out, runtime_symbols.trap_signature);
    try testing.expectEqualStrings(
        "  func.func private @linea_trap(i32, !llvm.ptr, i32, i32) attributes {passthrough = [\"noreturn\"]}\n",
        out.buffered(),
    );
    out = .fixed(&buffer);
    try declareOwned(&out, runtime_symbols.math_functions[@intFromEnum(FloatMathOperation.pow)]);
    try testing.expectEqualStrings("  func.func private @linea_math_pow(f64, f64) -> f64\n", out.buffered());
    out = .fixed(&buffer);
    try writeOwnedCallType(&out, runtime_symbols.panic_signature);
    try testing.expectEqualStrings(" : (i64, i64, !llvm.ptr, i32, i32) -> ()", out.buffered());

    // The widths the emitter spells for a trap's line and column and for a
    // panic's message extent are the table's.
    const trap = runtime_symbols.trap_signature.parameters;
    try testing.expectEqualStrings(runtime_int, mlirType(trap[0].scalar));
    try testing.expectEqualStrings(runtime_int, mlirType(trap[2].scalar));
    try testing.expectEqualStrings(runtime_int, mlirType(trap[3].scalar));
    const panic = runtime_symbols.panic_signature.parameters;
    try testing.expectEqualStrings(int_type, mlirType(panic[0].scalar));
    try testing.expectEqualStrings(int_type, mlirType(panic[1].scalar));
    try testing.expectEqualStrings(runtime_int, mlirType(panic[3].scalar));
}

/// The symbol the C runtime calls, which is not the entry point the program
/// wrote.
///
/// It takes what a C `main` is passed, hands both to the runtime, and calls the
/// written entry. Emitted wherever a module has one to call, rather than only
/// where a program reads its arguments: a second shape for how a program starts
/// would be a second answer to one question. A module with no entry point has
/// nothing to wrap, and a library never has one.
fn emitEntryWrapper(w: *std.Io.Writer, module: *const Module) std.Io.Writer.Error!void {
    const entry = runtime_symbols.entry_signature;
    try w.print("  func.func @{s}(%argc: {s}, %argv: {s}) -> {s} {{\n", .{
        entry.symbol, mlirType(entry.parameters[0].scalar), mlirType(entry.parameters[1].scalar), mlirType(entry.result),
    });
    try w.print("    func.call @{s}(%argc, %argv)", .{runtime_symbols.set_args});
    try writeOwnedCallType(w, runtime_symbols.set_args_signature);
    try w.writeAll("\n");
    try w.writeAll("    %status = func.call @");
    try writeSymbol(w, module, module.entry);
    try w.print("() : () -> {s}\n", .{int_type});
    // The status narrows to the runtime's width here and nowhere else -- the
    // one place a 64-bit computation meets a 32-bit interface.
    try w.print("    %status32 = arith.trunci %status : {s} to {s}\n", .{ int_type, mlirType(entry.result) });
    try w.print("    func.return %status32 : {s}\n", .{mlirType(entry.result)});
    try w.writeAll("  }\n");
}

/// The width one exported parameter or answer crosses the boundary in.
///
/// The type a value crosses the C boundary as: its storage representation,
/// which for an integer is the declared width rather than the width the body
/// computes in. That width is an implementation choice about where overflow is
/// caught, and publishing it would make this module's calling convention
/// something every caller has to match forever.
///
/// Only an integer, a `Float64` or a newtype over one reaches here: the
/// checker refused every other type ([T-Extern], [T-Export]), so another
/// representation is a compiler defect rather than a signature to print.
fn foreignTypeOf(module: *const Module, ty: TypeId) []const u8 {
    const representation = module.representationOf(ty).storage;
    if (representation != .code_pointer and !types_mod.crossesForeign(&module.types, ty))
        std.debug.panic("compiler defect: a type the checker refused crosses the foreign boundary", .{});
    return switch (representation) {
        .integer => |integer| switch (integer.bits) {
            8 => "i8",
            16 => "i16",
            32 => "i32",
            64 => "i64",
            else => std.debug.panic("compiler defect: a {d}-bit integer crosses the foreign boundary", .{integer.bits}),
        },
        .float => |bits| if (bits == 64) "f64" else std.debug.panic("compiler defect: a {d}-bit float crosses the foreign boundary", .{bits}),
        // A callback crosses as the address of its C-callable entry.
        .code_pointer => "!llvm.ptr",
        else => std.debug.panic("compiler defect: this type does not cross the foreign boundary", .{}),
    };
}

/// The extension a C caller or callee expects of an integer narrower than 32
/// bits, or null for a wider one.
///
/// Both supported C ABIs (AArch64 and x86-64 SysV) leave the register bits
/// above an `int8_t` or `int16_t` to whoever produces the value: the caller for
/// an argument, the callee for a result. Clang compiles C against that promise,
/// so C reads `(int)value` as the whole register. Marking the declaration makes
/// LLVM extend by the declared type's signedness on every call through it and
/// in every thunk that answers one.
fn foreignExtension(module: *const Module, ty: TypeId) ?[]const u8 {
    return switch (module.representationOf(ty).storage) {
        .integer => |integer| if (integer.bits >= 32)
            null
        else if (integer.signedness == .signed)
            "{llvm.signext}"
        else
            "{llvm.zeroext}",
        else => null,
    };
}

/// Whether a value's foreign type differs from the type the body computes it
/// in, so a boundary narrows it going out and widens it coming in. Only an
/// integer narrower than the computation width does.
fn adaptsAtBoundary(module: *const Module, ty: TypeId) bool {
    return !std.mem.eql(u8, foreignTypeOf(module, ty), computationType(module.representationOf(ty).computation));
}

/// How a narrow integer is widened to the computation width: by its declared
/// signedness, so an unsigned type widens with zeroes and a signed one with
/// its sign.
fn widening(module: *const Module, ty: TypeId) []const u8 {
    return switch (module.representationOf(ty).storage) {
        .integer => |integer| if (integer.signedness == .signed) "extsi" else "extui",
        else => std.debug.panic("compiler defect: a non-integer is widened at the foreign boundary", .{}),
    };
}

fn writeForeignExtension(w: *std.Io.Writer, module: *const Module, ty: TypeId) std.Io.Writer.Error!void {
    if (foreignExtension(module, ty)) |extension| try w.print(" {s}", .{extension});
}

/// Which C-callable entry to a body is being written: the symbol an export
/// publishes, or the private entry a callback passed to C is called through.
const ForeignEntry = union(enum) {
    exported: []const u8,
    called_back,
};

/// Writes the name of a callback's C-callable entry.
fn writeCalledBackName(w: *std.Io.Writer, module: *const Module, id: FunctionId) std.Io.Writer.Error!void {
    try w.writeByte('@');
    try writeSymbolName(w, module.nameOf(id), symbol_names.callback_prefix);
}

/// The function type of a body's C-callable entry, as `func.constant` names it.
fn writeForeignEntryType(w: *std.Io.Writer, module: *const Module, mir: *const Mir) std.Io.Writer.Error!void {
    try w.writeAll("(");
    for (0..mir.param_count) |i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll(if (module.arrivesByAddress(mir, i)) "!llvm.ptr" else foreignTypeOf(module, mir.locals[i]));
    }
    try w.writeAll(") -> ");
    if (mir.return_type == .unit) try w.writeAll("()") else try w.writeAll(foreignTypeOf(module, mir.return_type));
}

/// A C-callable entry to a body: the symbol the outside world links against
/// for an export, and the private entry C calls a callback through.
///
/// It takes the declared types' widths, widens each to the convention the body
/// was compiled for, calls it, and narrows the answer back. The narrowing
/// drops nothing: the body has already trapped if its result lies outside the
/// type it answers, so every bit above that width is a copy of the sign.
///
/// Always emitted, including where the two widths coincide and the conversions
/// are empty. A thunk elided when they happen to match would make the
/// published ABI a function of whether an optimisation fired, and the outside
/// world would be linking against whichever body the module happened to lower.
///
/// The body stays internal behind it, so a library has the shape a program
/// already has: bodies with every caller in hand, and a wrapper that is the one
/// symbol anything outside names.
fn emitForeignEntry(
    w: *std.Io.Writer,
    module: *const Module,
    mir: *const Mir,
    id: FunctionId,
    entry: ForeignEntry,
) std.Io.Writer.Error!void {
    // What the thunk itself answers: the declared type, or nothing where that
    // is Unit, because a C function returning void sets no register.
    const answers = mir.return_type != .unit;

    // What the *body* answers, which is a separate question and asked of the
    // one routine every other site asks. A function answering Unit still
    // answers the module's width, so a thunk that inferred the callee's result
    // from its own would call it with the wrong arity -- and the verifier, not
    // the compiler, would be the one to say so.
    const callee_answers = resultTypeOf(module, id, mir.return_type);

    switch (entry) {
        .exported => |name| try w.print("  func.func @{s}(", .{name}),
        .called_back => {
            try w.writeAll("  func.func private ");
            try writeCalledBackName(w, module, id);
            try w.writeAll("(");
        },
    }
    for (0..mir.param_count) |i| {
        if (i > 0) try w.writeAll(", ");
        const by_address = module.arrivesByAddress(mir, i);
        const ty = if (by_address) "!llvm.ptr" else foreignTypeOf(module, mir.locals[i]);
        try w.print("%p{d}: {s}", .{ i, ty });
        if (!by_address) try writeForeignExtension(w, module, mir.locals[i]);
    }
    try w.writeAll(")");
    if (answers) {
        if (foreignExtension(module, mir.return_type)) |extension| {
            try w.print(" -> ({s} {s})", .{ foreignTypeOf(module, mir.return_type), extension });
        } else {
            try w.print(" -> {s}", .{foreignTypeOf(module, mir.return_type)});
        }
    }
    // A callback's entry is reached only through the address the program
    // hands C, so the object publishes no symbol for it, as for a body.
    if (entry == .called_back) try w.writeAll(" attributes {llvm.linkage = #llvm.linkage<internal>}");
    try w.writeAll(" {\n");

    // A value narrower than the convention arrives narrow and is widened the
    // way a load of one is: what the bits mean is the declared type's
    // signedness, so an unsigned type widens with zeroes and a signed one with
    // its sign.
    for (0..mir.param_count) |i| {
        if (module.arrivesByAddress(mir, i)) continue;
        const ty = mir.locals[i];
        if (!adaptsAtBoundary(module, ty)) continue;
        try w.print("    %w{d} = arith.{s} %p{d} : {s} to {s}\n", .{
            i, widening(module, ty), i, foreignTypeOf(module, ty), int_type,
        });
    }

    // A float C hands over is canonicalised where it arrives, by value or at
    // the address of an `inout` parameter.
    for (0..mir.param_count) |i| {
        var tag_buffer: [32]u8 = undefined;
        const tag = std.fmt.bufPrint(&tag_buffer, "c{d}", .{i}) catch unreachable;
        if (module.arrivesByAddress(mir, i)) {
            var address_buffer: [32]u8 = undefined;
            const address = std.fmt.bufPrint(&address_buffer, "%p{d}", .{i}) catch unreachable;
            try writeCanonicalNanAt(w, module, mir.locals[i], address, tag, null);
            continue;
        }
        const bits = floatBitsOf(module.representationOf(mir.locals[i]).computation) orelse continue;
        var buffers: [4][32]u8 = undefined;
        try writeCanonicalNan(w, .{
            .result = std.fmt.bufPrint(&buffers[0], "{s}c", .{tag}) catch unreachable,
            .raw = std.fmt.bufPrint(&buffers[1], "p{d}", .{i}) catch unreachable,
            .unordered = std.fmt.bufPrint(&buffers[2], "{s}u", .{tag}) catch unreachable,
            .quiet = std.fmt.bufPrint(&buffers[3], "{s}q", .{tag}) catch unreachable,
        }, bits, null);
    }

    if (callee_answers != null) {
        try w.writeAll("    %answer = func.call @");
    } else {
        try w.writeAll("    func.call @");
    }
    try writeSymbol(w, module, id);
    try w.writeAll("(");
    for (0..mir.param_count) |i| {
        if (i > 0) try w.writeAll(", ");
        const by_value = !module.arrivesByAddress(mir, i);
        if (by_value and adaptsAtBoundary(module, mir.locals[i])) {
            try w.print("%w{d}", .{i});
        } else if (by_value and floatBitsOf(module.representationOf(mir.locals[i]).computation) != null) {
            try w.print("%c{d}c", .{i});
        } else {
            try w.print("%p{d}", .{i});
        }
    }
    try w.writeAll(") : (");
    for (0..mir.param_count) |i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll(paramTypeOf(module, id, mir, i));
    }
    try w.writeAll(") -> ");
    if (callee_answers) |t| try w.print("{s}\n", .{t}) else try w.writeAll("()\n");

    // A body that answers a width the thunk does not is answering Unit: the
    // value is bound and left, because nothing crosses.
    if (!answers) {
        try w.writeAll("    func.return\n  }\n");
        return;
    }

    const foreign = foreignTypeOf(module, mir.return_type);
    if (!adaptsAtBoundary(module, mir.return_type)) {
        try w.print("    func.return %answer : {s}\n  }}\n", .{foreign});
        return;
    }
    try w.print("    %narrow = arith.trunci %answer : {s} to {s}\n", .{ int_type, foreign });
    try w.print("    func.return %narrow : {s}\n  }}\n", .{foreign});
}

fn emitFunction(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    module: *const Module,
    mir: *const Mir,
    map: *const SourceMap,
    path: []const u8,
    id: FunctionId,
    file_symbol: u32,
) (std.mem.Allocator.Error || std.Io.Writer.Error)!void {
    // An answer too wide for a register is written into storage the caller
    // owns, handed in as a leading pointer. Asked of the module because the
    // call sites ask the same routine, so the two sides cannot disagree.
    const indirect = module.returnsIndirectly(id);
    var e: FunctionEmitter = .{
        .w = w,
        .mir = mir,
        .map = map,
        .path = path,
        .file_symbol = file_symbol,
        .module = module,
        .indirect = indirect,
    };

    try w.writeAll("  func.func private @");
    try writeSymbol(w, module, id);
    try w.writeAll("(");
    if (indirect) try w.writeAll("%sret: !llvm.ptr");
    for (0..mir.param_count) |i| {
        if (i > 0 or indirect) try w.writeAll(", ");
        try w.print("%a{d}: {s}", .{ i, paramTypeOf(module, id, mir, i) });
    }
    try w.writeAll(")");
    if (resultTypeOf(module, id, mir.return_type)) |t| {
        try w.print(" -> {s}", .{t});
    }
    // Internal to LLVM, not only private to MLIR: `private` hides the symbol
    // from other modules' lookups but translates to external linkage, under
    // which the optimiser must keep every out-of-line body and assume callers
    // it cannot see -- a two-instruction function survives as a real call.
    // Internal linkage says the module in hand holds every caller.
    //
    // True of every body here, a library's included: what something outside
    // reaches is the thunk, and the thunk is in this module and references the
    // body. So a library has the shape a program has, and neither has a body
    // the optimiser must keep on the chance of a caller it cannot see.
    if (mir.return_type == .never) {
        try w.writeAll(" attributes {llvm.linkage = #llvm.linkage<internal>, passthrough = [\"noreturn\"]} {\n");
    } else {
        try w.writeAll(" attributes {llvm.linkage = #llvm.linkage<internal>} {\n");
    }

    // The entry block, always first, because a function is entered at the block
    // its text begins with while `Mir` says which block that is. Every slot is
    // allocated here, where control certainly passes: allocating at each store
    // would allocate twice for a value written from two arms. Nothing in this
    // preamble carries a location: a slot or a spill serves the whole function
    // and claims no line of it.
    //
    // A slot is `llvm.alloca` rather than `memref.alloca`. What MIR says about
    // a local is a size and an alignment, and `memref` carries a layout map --
    // strides and offsets over a shaped buffer -- that nothing here has to say.
    // A dialect emitted for information the module does not carry is a dialect
    // earning nothing.
    for (0..mir.locals.len) |i| {
        const local = mir_mod.LocalId.at(@intCast(i));
        const representation = module.slotRepresentationOf(mir, local);
        const extent = module.slotExtentOf(mir, local);
        const alignment = module.slotAlignmentOf(mir, local);
        const count: u32 = switch (representation) {
            .managed_address => 1,
            .storage => |storage| switch (storage) {
                .bytes => extent,
                else => 1,
            },
        };
        const element = switch (representation) {
            .managed_address => "!llvm.ptr",
            .storage => |storage| switch (storage) {
                .bytes => "i8",
                else => storageType(storage),
            },
        };
        try w.print("    %z{d} = arith.constant {d} : i64\n", .{ i, count });
        try w.print(
            "    %s{d} = llvm.alloca %z{d} x {s} {{alignment = {d} : i64}} : (i64) -> !llvm.ptr\n",
            .{ i, i, element, alignment },
        );
    }
    // A parameter arrives in a register and is written to its slot, so the
    // body reads it exactly as it reads any other binding. One arriving as an
    // address stores the address itself -- writing back through it is what the
    // address is for.
    for (0..mir.param_count) |i| {
        if (!module.arrivesByAddress(mir, i)) {
            const storage = module.representationOf(mir.locals[i]).storage;
            switch (storage) {
                .integer => |integer| if (integer.bits < 64) {
                    const t = storageType(storage);
                    try w.print("    %pw{d} = arith.trunci %a{d} : {s} to {s}\n", .{ i, i, int_type, t });
                    try w.print("    llvm.store %pw{d}, %s{d} : {s}, !llvm.ptr\n", .{ i, i, t });
                } else {
                    try w.print("    llvm.store %a{d}, %s{d} : {s}, !llvm.ptr\n", .{ i, i, int_type });
                },
                .boolean => {
                    try w.print("    %pw{d} = arith.extui %a{d} : i1 to i8\n", .{ i, i });
                    try w.print("    llvm.store %pw{d}, %s{d} : i8, !llvm.ptr\n", .{ i, i });
                },
                .float, .enum_tag, .unit, .code_pointer, .data_pointer => try w.print("    llvm.store %a{d}, %s{d} : {s}, !llvm.ptr\n", .{
                    i, i, storageType(storage),
                }),
                .bytes, .no_value, .invalid => std.debug.panic("compiler defect: a scalar parameter has {s} storage", .{
                    @tagName(std.meta.activeTag(storage)),
                }),
            }
        } else if (mir.slotRoleOf(.at(@intCast(i))) == .managed_address) {
            try w.print("    llvm.store %a{d}, %s{d} : !llvm.ptr, !llvm.ptr\n", .{ i, i });
        } else {
            // A sink aggregate is copied into the callee's own slot, so what
            // the body does with it cannot be seen by the caller. Storing the
            // address instead would share one value between them.
            try w.print("    %pl{d} = arith.constant {d} : {s}\n", .{
                i, module.layoutOf(mir.locals[i]).size, int_type,
            });
            try w.print(
                "    \"llvm.intr.memcpy\"(%s{d}, %a{d}, %pl{d}) <{{isVolatile = false}}> : (!llvm.ptr, !llvm.ptr, {s}) -> ()\n",
                .{ i, i, i, int_type },
            );
        }
    }
    // Reachability follows the emitted graph: a forwarded aggregate call ends
    // its block before MIR's return join. The verifier's MIR reachability answers
    // a different question. A block nothing reaches is not printed: MLIR's
    // conversion driver walks only blocks
    // reachable from the entry, and a dead block's operations survive it
    // unconverted inside a converted function -- refused by the verifier the
    // pass runs afterwards. Sized by the function, as every per-function table
    // is.
    const reachable = try gpa.alloc(bool, mir.blockCount());
    defer gpa.free(reachable);
    @memset(reachable, false);
    var worklist: std.ArrayList(BlockId) = .empty;
    defer worklist.deinit(gpa);
    try worklist.append(gpa, mir.entry);
    reachable[mir.entry.index()] = true;
    var wi: usize = 0;
    while (wi < worklist.items.len) : (wi += 1) {
        const block = worklist.items[wi];
        if (e.tailReturn(block) != null) continue;
        const t = mir.terminatorOf(block);
        for (mir.successorsOf(t)) |successor| {
            const target = successor orelse continue;
            if (!reachable[target.index()]) {
                reachable[target.index()] = true;
                try worklist.append(gpa, target);
            }
        }
    }

    // Caller-owned storage for every answer too wide for a register, allocated
    // here where control certainly passes -- at the call site a loop would
    // grow the frame by one temporary per iteration.
    for (0..mir.blockCount()) |bi| {
        if (!reachable[bi]) continue;
        const block = BlockId.at(@intCast(bi));
        const tail = e.tailReturn(block);
        for (mir.instsOf(block)) |iid| {
            if (tail) |returned| if (returned.call == iid) continue;
            const result_type = switch (mir.tagOf(iid)) {
                .call => blk: {
                    const cc = mir.callOf(iid);
                    if (!module.returnsIndirectly(cc.func)) continue;
                    break :blk module.functionOf(cc.func).return_type;
                },
                .call_indirect => blk: {
                    if (!module.indirectReturnsByAddress(mir, iid)) continue;
                    break :blk module.indirectSignatureOf(mir, iid).result;
                },
                else => continue,
            };
            const l = module.layoutOf(result_type);
            try w.print("    %rz{d} = arith.constant {d} : i64\n", .{ iid.index(), l.size });
            try w.print(
                "    %rs{d} = llvm.alloca %rz{d} x i8 {{alignment = {d} : i64}} : (i64) -> !llvm.ptr\n",
                .{ iid.index(), iid.index(), l.alignment },
            );
        }
    }
    try w.print("    cf.br ^b{d}\n", .{mir.entry.index()});

    for (0..mir.blockCount()) |i| {
        if (!reachable[i]) continue;
        const b = BlockId.at(@intCast(i));
        const tail = e.tailReturn(b);
        e.return_call = if (tail) |returned| returned.call else .none;
        try w.print("  ^b{d}:\n", .{i});
        for (mir.instsOf(b)) |inst_id| {
            try e.inst(inst_id);
            if (tail) |returned| if (returned.call == inst_id) break;
        }
        if (tail) |returned| {
            try w.writeAll("    func.return");
            try e.here(mir.spanOf(returned.exit));
            continue;
        }
        // Every block has one: `Mir.Builder.finish` refuses to produce a
        // function where one does not.
        try e.inst(mir.terminatorOf(b));
    }

    try w.writeAll("  }\n");
}

/// Per-function emission state, named for the function because a module holds
/// nothing while it walks its functions.
const FunctionEmitter = struct {
    w: *std.Io.Writer,
    mir: *const Mir,
    map: *const SourceMap,
    /// The path of the file this function came from, spelled into every
    /// operation's location.
    path: []const u8,
    file_symbol: u32 = 0,
    module: *const Module,
    /// Whether this function writes its answer through a caller-owned pointer
    /// rather than returning it.
    indirect: bool,
    /// The terminal call writes directly to this function's caller-owned result.
    return_call: InstId = .none,
    /// Names the temporaries a check expands into, and the trap blocks it
    /// branches to. Per function, so two functions' checks cannot collide.
    next: u32 = 0,
    /// Expanded operations and trap arguments share their instruction's span.
    last_position: ?struct { offset: u32, at: source_mod.LineCol } = null,

    const TailReturn = struct { call: InstId, exit: InstId };

    /// Only a final call, optionally copied into an owned slot before an empty
    /// return join, can share the return destination. The destination itself
    /// is never exposed to Linea code: ordinary callers allocate fresh result
    /// storage, and forwarding carries that same storage through terminal calls.
    /// No argument, mutation, disposal or later read is moved across the call.
    /// Inspecting at most two trailing instructions and one join is O(1).
    fn tailReturn(self: *const FunctionEmitter, block: BlockId) ?TailReturn {
        if (!self.indirect) return null;
        const mir = self.mir;
        const body = mir.instsOf(block);
        if (body.len == 0) return null;
        var exit = mir.terminatorOf(block);
        if (mir.tagOf(exit) == .jump) {
            const join = mir.targetOf(exit);
            const joined = mir.instsOf(join);
            if (joined.len > 1 or (joined.len == 1 and mir.tagOf(joined[0]) != .addr_of)) return null;
            exit = mir.terminatorOf(join);
        }
        if (mir.tagOf(exit) != .ret) return null;
        const returned = mir.unaryOf(exit);
        var answer = body[body.len - 1];
        if (mir.tagOf(answer) == .copy_value or mir.tagOf(answer) == .move_value) {
            if (body.len < 2 or mir.typeOf(answer) != mir.return_type) return null;
            const copy = mir.binaryOf(answer);
            answer = body[body.len - 2];
            if (copy.rhs != answer or mir.tagOf(copy.lhs) != .addr_of or mir.tagOf(returned) != .addr_of) return null;
            const local = mir.localOf(copy.lhs);
            if (mir.localOf(returned) != local or mir.slotRoleOf(local) != .value or mir.locals[local.index()] != mir.return_type) return null;
        } else if (returned != answer) return null;
        if (mir.tagOf(answer) != .call or mir.typeOf(answer) != mir.return_type) return null;
        const target = mir.callOf(answer).func;
        if (self.module.isExternal(target) or !self.module.returnsIndirectly(target)) return null;
        if (self.module.functionOf(target).return_type != mir.return_type) return null;
        return .{ .call = answer, .exit = exit };
    }

    fn position(self: *FunctionEmitter, span: Span) source_mod.LineCol {
        if (self.last_position) |last| if (last.offset == span.start) return last.at;
        const at = self.map.lineCol(span.start);
        self.last_position = .{ .offset = span.start, .at = at };
        return at;
    }

    fn fresh(self: *FunctionEmitter) u32 {
        self.next += 1;
        return self.next;
    }

    /// Ends an operation with the source location of the instruction it
    /// renders. What is threaded here is what MIR already holds -- a span per
    /// instruction -- and threading it while the emitter is written is the
    /// mechanism owed to debug information: a location added after the fact
    /// means revisiting every operation this file prints. An expansion's every
    /// operation carries its instruction's location, because the expansion is
    /// that instruction, spelled out.
    fn here(self: *FunctionEmitter, span: Span) std.Io.Writer.Error!void {
        const at = self.position(span);
        try self.w.writeAll(" loc(\"");
        try writeMlirString(self.w, self.path);
        try self.w.print("\":{d}:{d})\n", .{ at.line, at.column });
    }

    fn writeValue(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        switch (self.mir.tagOf(id)) {
            .borrow, .observe => return self.writeValue(self.mir.unaryOf(id)),
            else => {},
        }
        if (self.mir.resultRoleOf(id) == .managed_address) switch (self.mir.tagOf(id)) {
            .addr_of => return self.w.print("%s{d}", .{self.mir.localOf(id).index()}),
            .field_addr => if (self.zeroOffsetBase(id)) |base| return self.writeValue(base),
            .call => if (self.module.returnsIndirectly(self.mir.callOf(id).func))
                return self.w.print("%rs{d}", .{id.index()}),
            .call_indirect => if (self.module.indirectReturnsByAddress(self.mir, id))
                return self.w.print("%rs{d}", .{id.index()}),
            .load_indirect => return self.writeValue(self.mir.unaryOf(id)),
            else => {},
        };
        try self.w.print("%v{d}", .{id.index()});
    }

    fn zeroOffsetBase(self: *const FunctionEmitter, id: InstId) ?InstId {
        const p = self.mir.binaryOf(id);
        if (self.mir.tagOf(p.rhs) != .constant or self.mir.constantOf(p.rhs) != 0) return null;
        return p.lhs;
    }

    fn inst(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const mir = self.mir;
        const span = mir.spanOf(id);
        switch (mir.tagOf(id)) {
            .constant => {
                const computation = self.module.representationOf(mir.typeOf(id)).computation;
                if (floatBitsOf(computation)) |width| {
                    // Spelled as the bits rather than as a decimal, because the
                    // bits are exact and a decimal is a rounding of them.
                    const bits = floatConstantBits(mir.floatConstantOf(id), width);
                    try self.w.print("    %v{d} = arith.constant 0x{X} : {s}", .{ id.index(), bits, floatType(width) });
                    try self.here(span);
                } else {
                    // The word holding the same bits: a `UInt64` above the
                    // signed maximum is spelled as its signed reading, which
                    // is the one spelling of that bit pattern an `i64`
                    // constant accepts.
                    const word: i64 = @truncate(mir.constantOf(id));
                    try self.w.print("    %v{d} = arith.constant {d} : {s}", .{
                        id.index(), word, computationType(computation),
                    });
                    try self.here(span);
                }
            },

            .store => {
                const s = mir.storeOf(id);
                const storage = self.module.slotRepresentationOf(mir, s.local).storage;
                switch (storage) {
                    .integer => |integer| if (integer.bits < 64) {
                        const t = storageType(storage);
                        try self.w.print("    %sw{d} = arith.trunci %v{d} : {s} to {s}", .{ id.index(), s.value.index(), int_type, t });
                        try self.here(span);
                        try self.w.print("    llvm.store %sw{d}, %s{d} : {s}, !llvm.ptr", .{ id.index(), s.local.index(), t });
                        try self.here(span);
                    } else {
                        try self.w.print("    llvm.store %v{d}, %s{d} : {s}, !llvm.ptr", .{ s.value.index(), s.local.index(), int_type });
                        try self.here(span);
                    },
                    .boolean => {
                        try self.w.print("    %sw{d} = arith.extui %v{d} : i1 to i8", .{ id.index(), s.value.index() });
                        try self.here(span);
                        try self.w.print("    llvm.store %sw{d}, %s{d} : i8, !llvm.ptr", .{ id.index(), s.local.index() });
                        try self.here(span);
                    },
                    .float, .enum_tag, .unit, .code_pointer, .data_pointer => {
                        try self.w.writeAll("    llvm.store ");
                        try self.writeValue(s.value);
                        try self.w.print(", %s{d} : {s}, !llvm.ptr", .{
                            s.local.index(), storageType(storage),
                        });
                        try self.here(span);
                    },
                    .bytes, .no_value, .invalid => std.debug.panic("compiler defect: a named store has {s} storage", .{
                        @tagName(std.meta.activeTag(storage)),
                    }),
                }
            },
            .load => {
                const local = mir.localOf(id);
                switch (self.module.slotRepresentationOf(mir, local)) {
                    .managed_address => {
                        try self.w.print("    %v{d} = llvm.load %s{d} : !llvm.ptr -> !llvm.ptr", .{ id.index(), local.index() });
                        try self.here(span);
                    },
                    .storage => |storage| switch (storage) {
                        .integer => |integer| if (integer.bits < 64) {
                            const t = storageType(storage);
                            try self.w.print("    %lw{d} = llvm.load %s{d} : !llvm.ptr -> {s}", .{ id.index(), local.index(), t });
                            try self.here(span);
                            try self.w.print("    %v{d} = arith.{s} %lw{d} : {s} to {s}", .{
                                id.index(), if (integer.signedness == .signed) "extsi" else "extui", id.index(), t, int_type,
                            });
                            try self.here(span);
                        } else {
                            try self.w.print("    %v{d} = llvm.load %s{d} : !llvm.ptr -> {s}", .{ id.index(), local.index(), int_type });
                            try self.here(span);
                        },
                        .boolean => {
                            try self.w.print("    %lw{d} = llvm.load %s{d} : !llvm.ptr -> i8", .{ id.index(), local.index() });
                            try self.here(span);
                            try self.w.print("    %lz{d} = arith.constant 0 : i8", .{id.index()});
                            try self.here(span);
                            try self.w.print("    %v{d} = arith.cmpi ne, %lw{d}, %lz{d} : i8", .{ id.index(), id.index(), id.index() });
                            try self.here(span);
                        },
                        .float, .enum_tag, .unit, .code_pointer, .data_pointer => {
                            try self.w.print("    %v{d} = llvm.load %s{d} : !llvm.ptr -> {s}", .{
                                id.index(), local.index(), storageType(storage),
                            });
                            try self.here(span);
                        },
                        .bytes, .no_value, .invalid => std.debug.panic("compiler defect: a named load has {s} storage", .{
                            @tagName(std.meta.activeTag(storage)),
                        }),
                    },
                }
            },

            .add => try self.binaryArith(id, "addi", "addf"),
            .sub => try self.binaryArith(id, "subi", "subf"),
            .mul => try self.multiply(id),
            .div, .rem => try self.division(id),
            .neg => {
                const n = id.index();
                const v = mir.unaryOf(id);
                switch (self.computationOf(id)) {
                    .float => |bits| {
                        try self.w.print("    %v{d} = arith.negf %v{d} : {s}", .{ n, v.index(), floatType(bits) });
                        try self.here(span);
                    },
                    .integer => {
                        // The dialect spells no integer negation, so it is
                        // written as the subtraction it is.
                        try self.w.print("    %nz{d} = arith.constant 0 : {s}", .{ n, int_type });
                        try self.here(span);
                        try self.w.print("    %v{d} = arith.subi %nz{d}, %v{d} : {s}", .{ n, n, v.index(), int_type });
                        try self.here(span);
                    },
                    else => |representation| std.debug.panic("compiler defect: cannot negate {s}", .{
                        @tagName(std.meta.activeTag(representation)),
                    }),
                }
            },

            .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => try self.comparison(id),

            .check => try self.check(id),

            .jump => {
                try self.w.print("    cf.br ^b{d}", .{mir.targetOf(id).index()});
                try self.here(span);
            },

            .branch => {
                const b = mir.branchOf(id);
                try self.w.print("    cf.cond_br %v{d}, ^b{d}, ^b{d}", .{
                    b.cond.index(), b.then_block.index(), b.else_block.index(),
                });
                try self.here(span);
            },

            .trap => {
                const n = self.fresh();
                const trap = mir.trapOf(id);
                if (trap.kind == .panic) {
                    try self.panicAndStop(n, trap.message, span);
                } else {
                    try self.trapAndStop(n, trap.kind, span);
                }
            },

            // Restore the checked value's storage width at this conversion
            // boundary so the backend retains its integer range. Arithmetic
            // still uses widened values before its overflow checks.
            .int_to_float => {
                const v = mir.unaryOf(id);
                const storage = self.module.representationOf(mir.typeOf(v)).storage;
                const integer = switch (storage) {
                    .integer => |integer| integer,
                    else => std.debug.panic("compiler defect: a non-integer reaches integer-to-float conversion", .{}),
                };
                const from = storageType(storage);
                const to = computationType(self.computationOf(id));
                const operation = if (integer.signedness == .signed) "sitofp" else "uitofp";
                if (integer.bits < 64) {
                    try self.w.print("    %fw{d} = arith.trunci %v{d} : {s} to {s}", .{ id.index(), v.index(), int_type, from });
                    try self.here(span);
                    try self.w.print("    %v{d} = arith.{s} %fw{d} : {s} to {s}", .{ id.index(), operation, id.index(), from, to });
                } else {
                    try self.w.print("    %v{d} = arith.{s} %v{d} : {s} to {s}", .{ id.index(), operation, v.index(), from, to });
                }
                try self.here(span);
            },
            .float_to_int => try self.floatToInt(id),
            // Neither carries a fast-math flag: widening is exact, and
            // narrowing rounds to nearest with ties to even.
            .float_extend, .float_truncate => {
                const v = mir.unaryOf(id);
                try self.w.print("    %nr{d} = arith.{s} %v{d} : {s} to {s}", .{
                    id.index(),
                    if (mir.tagOf(id) == .float_extend) "extf" else "truncf",
                    v.index(),
                    computationType(self.module.representationOf(mir.typeOf(v)).computation),
                    computationType(self.computationOf(id)),
                });
                try self.here(span);
                try self.canonicalNan(id, floatBitsOf(self.computationOf(id)).?, span);
            },
            // Every bit is kept: a bit cast is not arithmetic, so it neither
            // quiets nor canonicalises a NaN. An integer is computed in the
            // word, so a 32-bit one is narrowed to its width first or widened
            // after.
            .bit_cast => {
                const v = mir.unaryOf(id);
                const from = self.module.representationOf(mir.typeOf(v)).computation;
                if (floatBitsOf(from)) |bits| {
                    if (bits == 64) {
                        try self.w.print("    %v{d} = arith.bitcast %v{d} : f64 to {s}", .{ id.index(), v.index(), int_type });
                    } else {
                        try self.w.print("    %bc{d} = arith.bitcast %v{d} : f32 to i32", .{ id.index(), v.index() });
                        try self.here(span);
                        try self.w.print("    %v{d} = arith.extui %bc{d} : i32 to {s}", .{ id.index(), id.index(), int_type });
                    }
                } else {
                    const bits = floatBitsOf(self.computationOf(id)).?;
                    if (bits == 64) {
                        try self.w.print("    %v{d} = arith.bitcast %v{d} : {s} to f64", .{ id.index(), v.index(), int_type });
                    } else {
                        try self.w.print("    %bc{d} = arith.trunci %v{d} : {s} to i32", .{ id.index(), v.index(), int_type });
                        try self.here(span);
                        try self.w.print("    %v{d} = arith.bitcast %bc{d} : i32 to f32", .{ id.index(), id.index() });
                    }
                }
                try self.here(span);
            },
            .float_math => {
                const math = mir.floatMathOf(id);
                try self.w.print("    %nr{d} = func.call @{s}(%v{d}", .{ id.index(), math.operation.symbol(), math.lhs.index() });
                if (math.operation.arity() == 2) try self.w.print(", %v{d}", .{math.rhs.index()});
                try self.w.writeAll(")");
                try writeOwnedCallType(self.w, runtime_symbols.math_functions[@intFromEnum(math.operation)]);
                try self.here(span);
                try self.canonicalNan(id, 64, span);
            },

            .ret => {
                const v = mir.unaryOf(id);
                if (self.indirect) {
                    // The value lives at an address, and the caller's storage
                    // is where it must end up: returning the address of a slot
                    // in this frame would hand the caller storage that ends
                    // with the call.
                    const n = id.index();
                    try self.w.print("    %rl{d} = arith.constant {d} : {s}", .{
                        n, self.sizeOf(mir.return_type), int_type,
                    });
                    try self.here(span);
                    try self.w.writeAll("    \"llvm.intr.memcpy\"(%sret, ");
                    try self.writeValue(v);
                    try self.w.print(", %rl{d}) <{{isVolatile = false}}> : (!llvm.ptr, !llvm.ptr, {s}) -> ()", .{ n, int_type });
                    try self.here(span);
                    try self.w.writeAll("    func.return");
                    try self.here(span);
                } else {
                    try self.w.writeAll("    func.return ");
                    try self.writeValue(v);
                    try self.w.print(" : {s}", .{computationType(self.module.representationOf(mir.return_type).computation)});
                    try self.here(span);
                }
            },

            .addr_of, .borrow, .observe => {},

            .function_addr => {
                const n = id.index();
                const target = mir.functionOf(id);
                try self.w.print("    %fa{d} = func.constant @", .{n});
                try writeSymbol(self.w, self.module, target);
                try self.w.writeAll(" : ");
                try self.writeFunctionType(target);
                try self.here(span);
                try self.w.print("    %v{d} = builtin.unrealized_conversion_cast %fa{d} : ", .{ n, n });
                try self.writeFunctionType(target);
                try self.w.writeAll(" to !llvm.ptr");
                try self.here(span);
            },

            .foreign_function_addr => {
                const n = id.index();
                const target = mir.functionOf(id);
                const body = self.module.functionOf(target);
                try self.w.print("    %fa{d} = func.constant ", .{n});
                try writeCalledBackName(self.w, self.module, target);
                try self.w.writeAll(" : ");
                try writeForeignEntryType(self.w, self.module, body);
                try self.here(span);
                try self.w.print("    %v{d} = builtin.unrealized_conversion_cast %fa{d} : ", .{ n, n });
                try writeForeignEntryType(self.w, self.module, body);
                try self.w.writeAll(" to !llvm.ptr");
                try self.here(span);
            },

            .address_bits => {
                try self.w.print("    %v{d} = llvm.ptrtoint ", .{id.index()});
                try self.writeValue(mir.unaryOf(id));
                try self.w.print(" : !llvm.ptr to {s}", .{int_type});
                try self.here(span);
            },

            .static_addr => {
                try self.w.print("    %v{d} = llvm.mlir.addressof @linea_static{d} : !llvm.ptr", .{
                    id.index(), mir.staticOf(id),
                });
                try self.here(span);
            },

            .bytes_addr => {
                const n = id.index();
                try self.w.print("    %ba{d} = llvm.mlir.addressof @linea_str{d} : !llvm.ptr", .{
                    n, mir.bytesOf(id),
                });
                try self.here(span);
                try self.w.print("    %v{d} = llvm.ptrtoint %ba{d} : !llvm.ptr to {s}", .{ n, n, int_type });
                try self.here(span);
            },

            // An offset within a value cannot leave it, so this is a plain
            // add: there is no range for it to escape and nothing to check.
            .field_addr => {
                if (self.zeroOffsetBase(id) != null) return;
                const p = mir.binaryOf(id);
                try self.w.print("    %v{d} = llvm.getelementptr ", .{id.index()});
                try self.writeValue(p.lhs);
                try self.w.writeAll("[");
                try self.writeValue(p.rhs);
                try self.w.writeAll("] : (!llvm.ptr, i64) -> !llvm.ptr, i8");
                try self.here(span);
            },

            .storage_addr => {
                try self.w.print("    %v{d} = llvm.inttoptr ", .{id.index()});
                try self.writeValue(mir.rawAccessOf(id).address);
                try self.w.print(" : {s} to !llvm.ptr", .{int_type});
                try self.here(span);
            },

            .load_indirect, .load_raw => try self.loadIndirect(id),
            .store_indirect, .store_raw => try self.storeIndirect(id),

            // The size comes from the layout table rather than from the type,
            // which is the whole of what this pass knows about types. The
            // intrinsic requires the two regions not overlap, and they cannot:
            // a copy's destination is storage the destination binding owns
            // exclusively -- a distinct slot, or heap the program was handed
            // once -- which is what a copy means in a language where nothing
            // is duplicated implicitly.
            .copy_value, .move_value => {
                const p = mir.binaryOf(id);
                const n = id.index();
                try self.w.print("    %cl{d} = arith.constant {d} : {s}", .{
                    n, self.sizeOf(mir.typeOf(id)), int_type,
                });
                try self.here(span);
                try self.w.writeAll("    \"llvm.intr.memcpy\"(");
                try self.writeValue(p.lhs);
                try self.w.writeAll(", ");
                try self.writeValue(p.rhs);
                try self.w.print(", %cl{d}) <{{isVolatile = false}}> : (!llvm.ptr, !llvm.ptr, {s}) -> ()", .{ n, int_type });
                try self.here(span);
            },

            .call => try self.call(id, false),
            .call_indirect => try self.callIndirect(id, false),
            .call_noreturn => try self.call(id, true),
            .call_indirect_noreturn => try self.callIndirect(id, true),
        }
    }

    fn writeFunctionType(self: *FunctionEmitter, target: FunctionId) std.Io.Writer.Error!void {
        const function = self.module.functionOf(target);
        const returns_by_address = self.module.returnsIndirectly(target);
        try self.w.writeAll("(");
        if (returns_by_address) try self.w.writeAll("!llvm.ptr");
        for (0..function.param_count) |i| {
            if (i > 0 or returns_by_address) try self.w.writeAll(", ");
            try self.w.writeAll(paramTypeOf(self.module, target, function, i));
        }
        try self.w.writeAll(") -> ");
        if (resultTypeOf(self.module, target, function.return_type)) |result| {
            try self.w.writeAll(result);
        } else {
            try self.w.writeAll("()");
        }
    }

    /// A call, in the callee's convention rather than a copy of it: whether an
    /// answer comes back in a register or through the caller's storage is the
    /// module's decision, read from the same routine the definition reads.
    fn call(self: *FunctionEmitter, id: InstId, is_noreturn: bool) std.Io.Writer.Error!void {
        const w = self.w;
        const mir = self.mir;
        const module = self.module;
        const c = mir.callOf(id);
        const callee = module.functionOf(c.func);
        const n = id.index();
        const span = mir.spanOf(id);
        const external = module.isExternal(c.func);
        const indirect = module.returnsIndirectly(c.func);
        const ty = if (is_noreturn) TypeId.never else mir.typeOf(id);

        const widens = !is_noreturn and external and !indirect and ty != .unit and adaptsAtBoundary(module, ty);
        // A float C answers is canonicalised where it arrives, as a computed
        // one is where it is computed.
        const from_c: ?u8 = if (!is_noreturn and external and !indirect and ty != .unit)
            floatBitsOf(module.representationOf(ty).computation)
        else
            null;

        if (external) for (c.args, 0..) |a, i| {
            if (module.arrivesByAddress(callee, i)) continue;
            const parameter = callee.locals[i];
            if (!adaptsAtBoundary(module, parameter)) continue;
            try w.print("    %va{d}_{d} = arith.trunci %v{d} : {s} to {s}", .{
                n, i, a.index(), computationType(module.representationOf(parameter).computation), foreignTypeOf(module, parameter),
            });
            try self.here(span);
        };

        if (is_noreturn or indirect or (external and ty == .unit)) {
            try w.writeAll("    func.call @");
        } else if (widens) {
            try w.print("    %vr{d} = func.call @", .{n});
        } else if (from_c != null) {
            try w.print("    %nr{d} = func.call @", .{n});
        } else {
            try w.print("    %v{d} = func.call @", .{n});
        }
        try writeSymbol(w, module, c.func);
        try w.writeAll("(");
        if (indirect) {
            if (id == self.return_call) try w.writeAll("%sret") else try w.print("%rs{d}", .{n});
        }
        for (c.args, 0..) |a, i| {
            if (i > 0 or indirect) try w.writeAll(", ");
            const adapted = external and !module.arrivesByAddress(callee, i) and adaptsAtBoundary(module, callee.locals[i]);
            if (adapted) try w.print("%va{d}_{d}", .{ n, i }) else try self.writeValue(a);
        }
        try w.writeAll(") : (");
        if (indirect) try w.writeAll("!llvm.ptr");
        for (c.args, 0..) |_, i| {
            if (i > 0 or indirect) try w.writeAll(", ");
            try w.writeAll(paramTypeOf(module, c.func, callee, i));
        }
        try w.writeAll(") -> ");
        if (resultTypeOf(module, c.func, ty)) |t| {
            try w.print("{s}", .{t});
        } else {
            try w.writeAll("()");
        }
        try self.here(span);

        if (c.func == module.zeroed_allocator) try self.zeroedAllocation(id, c.args[0]);

        // C may have written any float through an `inout` parameter.
        if (external) for (c.args, 0..) |a, i| {
            if (!module.arrivesByAddress(callee, i)) continue;
            var address_buffer: [32]u8 = undefined;
            var address: std.Io.Writer = .fixed(&address_buffer);
            const saved = self.w;
            self.w = &address;
            try self.writeValue(a);
            self.w = saved;
            var tag_buffer: [32]u8 = undefined;
            const tag = std.fmt.bufPrint(&tag_buffer, "fc{d}_{d}", .{ n, i }) catch unreachable;
            try writeCanonicalNanAt(w, module, callee.locals[i], address.buffered(), tag, .{ .emitter = self, .span = span });
        };

        if (is_noreturn) {
            try w.writeAll("    llvm.unreachable");
            try self.here(span);
            return;
        }

        if (indirect) {
            // The result aliases the caller-owned return slot through
            // `writeValue`; no operation is needed.
        } else if (external and ty == .unit) {
            // The unit it stands for is read by a `ret`, so the value is
            // defined after the call instead of by it.
            try w.print("    %v{d} = arith.constant 0 : {s}", .{ n, int_type });
            try self.here(span);
        } else if (widens) {
            try w.print("    %v{d} = arith.{s} %vr{d} : {s} to {s}", .{
                n, widening(module, ty), n, foreignTypeOf(module, ty), computationType(module.representationOf(ty).computation),
            });
            try self.here(span);
        } else if (from_c) |bits| {
            try self.canonicalNan(id, bits, span);
        }
    }

    /// The allocator's ordinary call remains opaque. Only complete words in
    /// a small statically bounded allocation receive its genuine zero fact.
    /// Constant predicates can settle after inlining; otherwise these paths
    /// disappear before machine code, including at unoptimized call sites.
    fn zeroedAllocation(self: *FunctionEmitter, id: InstId, size: InstId) std.Io.Writer.Error!void {
        const w = self.w;
        const n = id.index();
        try w.print(
            \\    %az{0d}_limit = arith.constant 512 : i64
            \\    %az{0d}_zero = arith.constant 0 : i64
            \\    %az{0d}_small = arith.cmpi ule, %v{1d}, %az{0d}_limit : i64
            \\    %az{0d}_known = func.call @llvm.is.constant.i1(%az{0d}_small) : (i1) -> i1
            \\    %az{0d}_nonnull = arith.cmpi ne, %v{0d}, %az{0d}_zero : i64
            \\    %az{0d}_eligible = arith.andi %az{0d}_known, %az{0d}_small : i1
            \\    %az{0d}_guard = arith.andi %az{0d}_eligible, %az{0d}_nonnull : i1
            \\    cf.cond_br %az{0d}_guard, ^az{0d}_check0, ^az{0d}_done
            \\
        , .{ n, size.index() });
        for (0..8) |i| {
            try w.print(
                \\  ^az{0d}_check{1d}:
                \\    %az{0d}_end{1d} = arith.constant {2d} : i64
                \\    %az{0d}_has{1d} = arith.cmpi uge, %v{3d}, %az{0d}_end{1d} : i64
                \\    %az{0d}_known{1d} = func.call @llvm.is.constant.i1(%az{0d}_has{1d}) : (i1) -> i1
                \\    %az{0d}_safe{1d} = arith.andi %az{0d}_known{1d}, %az{0d}_has{1d} : i1
                \\    cf.cond_br %az{0d}_safe{1d}, ^az{0d}_word{1d}, ^az{0d}_done
                \\  ^az{0d}_word{1d}:
                \\    %az{0d}_base{1d} = llvm.inttoptr %v{0d} : i64 to !llvm.ptr
                \\    %az{0d}_ptr{1d} = llvm.getelementptr %az{0d}_base{1d}[{4d}] : (!llvm.ptr) -> !llvm.ptr, i8
                \\    %az{0d}_value{1d} = llvm.load %az{0d}_ptr{1d} {{alignment = 8 : i64}} : !llvm.ptr -> i64
                \\    %az{0d}_zero{1d} = arith.cmpi eq, %az{0d}_value{1d}, %az{0d}_zero : i64
                \\    func.call @llvm.assume(%az{0d}_zero{1d}) : (i1) -> ()
                \\
            , .{ n, i, (i + 1) * 8, size.index(), i * 8 });
            if (i + 1 < 8)
                try w.print("    cf.br ^az{d}_check{d}\n", .{ n, i + 1 })
            else
                try w.print("    cf.br ^az{d}_done\n", .{n});
        }
        try w.print("  ^az{d}_done:\n", .{n});
    }

    /// RawAccess verification establishes the base-plus-offset operation and
    /// every bounds witness before emission. A non-inbounds byte GEP retains
    /// the pointer relationship without introducing an arithmetic promise.
    fn rawPointer(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const address = self.mir.binaryOf(self.mir.rawAccessOf(id).address);
        const n = id.index();
        const span = self.mir.spanOf(id);
        try self.w.print("    %ib{d} = llvm.inttoptr %v{d} : i64 to !llvm.ptr", .{ n, address.lhs.index() });
        try self.here(span);
        try self.w.print("    %ip{d} = llvm.getelementptr %ib{d}[%v{d}] : (!llvm.ptr, i64) -> !llvm.ptr, i8", .{ n, n, address.rhs.index() });
        try self.here(span);
    }

    fn callIndirect(self: *FunctionEmitter, id: InstId, is_noreturn: bool) std.Io.Writer.Error!void {
        const indirect_call = self.mir.indirectCallOf(id);
        const signature = self.module.indirectSignatureOf(self.mir, id);
        const params = self.module.types.callableParams(signature);
        const returns_by_address = self.module.returnsByAddress(signature.result);
        const n = id.index();
        const span = self.mir.spanOf(id);

        if (!returns_by_address and !is_noreturn) try self.w.print("    %v{d} = ", .{n}) else try self.w.writeAll("    ");
        try self.w.writeAll("llvm.call ");
        try self.writeValue(indirect_call.callee);
        try self.w.writeAll("(");
        if (returns_by_address) try self.w.print("%rs{d}", .{n});
        for (indirect_call.args, 0..) |arg, i| {
            if (i > 0 or returns_by_address) try self.w.writeAll(", ");
            try self.writeValue(arg);
        }
        try self.w.writeAll(") : !llvm.ptr, (");
        if (returns_by_address) try self.w.writeAll("!llvm.ptr");
        for (params, 0..) |param, i| {
            if (i > 0 or returns_by_address) try self.w.writeAll(", ");
            try self.w.writeAll(callableParamType(self.module, param));
        }
        try self.w.writeAll(") -> ");
        if (returns_by_address or is_noreturn) {
            try self.w.writeAll("()");
        } else {
            try self.w.writeAll(computationType(self.module.representationOf(signature.result).computation));
        }
        try self.here(span);
        if (is_noreturn) {
            try self.w.writeAll("    llvm.unreachable");
            try self.here(span);
        }
    }

    /// A load through an address rather than from a named slot, at the width
    /// the layout table states -- an indirect access reaches into a value, and
    /// a part's width is the table's answer, not the register's.
    fn loadIndirect(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const mir = self.mir;
        const n = id.index();
        const span = mir.spanOf(id);
        const ty = mir.typeOf(id);
        const address = if (mir.tagOf(id) == .load_raw) mir.rawAccessOf(id).address else mir.unaryOf(id);
        if (mir.resultRoleOf(id) == .managed_address) return;
        const raw = mir.tagOf(id) == .load_raw;
        if (raw) try self.rawPointer(id);
        const storage = self.module.representationOf(ty).storage;
        switch (storage) {
            .integer => |integer| if (integer.bits < 64) {
                const t = storageType(storage);
                try self.w.print("    %iw{d} = llvm.load ", .{n});
                if (raw) try self.w.print("%ip{d}", .{n}) else try self.writeValue(address);
                try self.w.print(" : !llvm.ptr -> {s}", .{t});
                try self.here(span);
                try self.w.print("    %v{d} = arith.{s} %iw{d} : {s} to {s}", .{
                    n, if (integer.signedness == .signed) "extsi" else "extui", n, t, int_type,
                });
                try self.here(span);
            } else {
                try self.w.print("    %v{d} = llvm.load ", .{n});
                if (raw) try self.w.print("%ip{d}", .{n}) else try self.writeValue(address);
                try self.w.print(" : !llvm.ptr -> {s}", .{int_type});
                try self.here(span);
            },
            .boolean => {
                try self.w.print("    %iw{d} = llvm.load ", .{n});
                if (raw) try self.w.print("%ip{d}", .{n}) else try self.writeValue(address);
                try self.w.writeAll(" : !llvm.ptr -> i8");
                try self.here(span);
                try self.w.print("    %iz{d} = arith.constant 0 : i8", .{n});
                try self.here(span);
                try self.w.print("    %v{d} = arith.cmpi ne, %iw{d}, %iz{d} : i8", .{ n, n, n });
                try self.here(span);
            },
            .float, .enum_tag, .unit, .code_pointer, .data_pointer => {
                try self.w.print("    %v{d} = llvm.load ", .{n});
                if (raw) try self.w.print("%ip{d}", .{n}) else try self.writeValue(address);
                try self.w.print(" : !llvm.ptr -> {s}", .{storageType(storage)});
                try self.here(span);
            },
            .bytes, .no_value, .invalid => std.debug.panic("compiler defect: an indirect load has {s} storage", .{
                @tagName(std.meta.activeTag(storage)),
            }),
        }
    }

    /// A store through an address, truncating to the width the layout table
    /// states. Truncating needs no guard: a value reaching a part of this type
    /// has already passed a range check against that type's bounds, so the
    /// bits a narrow store drops are bits the checker proved were not there.
    fn storeIndirect(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const mir = self.mir;
        const n = id.index();
        const span = mir.spanOf(id);
        const lhs, const rhs = if (mir.tagOf(id) == .store_raw) blk: {
            const raw = mir.rawAccessOf(id);
            break :blk .{ raw.address, raw.value };
        } else blk: {
            const p = mir.binaryOf(id);
            break :blk .{ p.lhs, p.rhs };
        };
        const ty = mir.typeOf(id);
        const raw = mir.tagOf(id) == .store_raw;
        if (raw) try self.rawPointer(id);
        const storage = self.module.representationOf(ty).storage;
        switch (storage) {
            .integer => |integer| if (integer.bits < 64) {
                const t = storageType(storage);
                try self.w.print("    %iw{d} = arith.trunci %v{d} : {s} to {s}", .{ n, rhs.index(), int_type, t });
                try self.here(span);
                try self.w.print("    llvm.store %iw{d}, ", .{n});
                if (raw) try self.w.print("%ip{d}", .{n}) else try self.writeValue(lhs);
                try self.w.print(" : {s}, !llvm.ptr", .{t});
                try self.here(span);
            } else {
                try self.w.print("    llvm.store %v{d}, ", .{rhs.index()});
                if (raw) try self.w.print("%ip{d}", .{n}) else try self.writeValue(lhs);
                try self.w.print(" : {s}, !llvm.ptr", .{int_type});
                try self.here(span);
            },
            .boolean => {
                try self.w.print("    %iw{d} = arith.extui %v{d} : i1 to i8", .{ n, rhs.index() });
                try self.here(span);
                try self.w.print("    llvm.store %iw{d}, ", .{n});
                if (raw) try self.w.print("%ip{d}", .{n}) else try self.writeValue(lhs);
                try self.w.writeAll(" : i8, !llvm.ptr");
                try self.here(span);
            },
            .float, .enum_tag, .unit, .code_pointer, .data_pointer => {
                try self.w.writeAll("    llvm.store ");
                try self.writeValue(rhs);
                try self.w.writeAll(", ");
                if (raw) try self.w.print("%ip{d}", .{n}) else try self.writeValue(lhs);
                try self.w.print(" : {s}, !llvm.ptr", .{storageType(storage)});
                try self.here(span);
            },
            .bytes, .no_value, .invalid => std.debug.panic("compiler defect: an indirect store has {s} storage", .{
                @tagName(std.meta.activeTag(storage)),
            }),
        }
    }

    /// How wide a value of a type is. Read from the module's layout table,
    /// never computed: this pass cannot see the type pool, so there is no
    /// arrangement it could work out differently from the checker.
    fn sizeOf(self: *const FunctionEmitter, ty: TypeId) u32 {
        return self.module.layoutOf(ty).size;
    }

    fn computationOf(self: *const FunctionEmitter, id: InstId) mir_mod.ComputationRepresentation {
        return switch (self.module.resultRepresentationOf(self.mir, id)) {
            .computation => |computation| computation,
            else => |representation| std.debug.panic("compiler defect: result %{d} has {s} representation", .{
                id.index(), @tagName(representation),
            }),
        };
    }

    fn binaryArith(
        self: *FunctionEmitter,
        id: InstId,
        int_op: []const u8,
        float_op: []const u8,
    ) std.Io.Writer.Error!void {
        const p = self.mir.binaryOf(id);
        const computation = self.computationOf(id);
        const op = switch (computation) {
            .integer => int_op,
            .float => float_op,
            else => |representation| std.debug.panic("compiler defect: cannot apply arithmetic to {s}", .{
                @tagName(std.meta.activeTag(representation)),
            }),
        };
        const float = floatBitsOf(computation);
        try self.w.print("    %{s}{d} = arith.{s} %v{d}, %v{d} : {s}", .{
            if (float != null) "nr" else "v",
            id.index(),
            op,
            p.lhs.index(),
            p.rhs.index(),
            computationType(computation),
        });
        try self.here(self.mir.spanOf(id));
        if (float) |bits| try self.canonicalNan(id, bits, self.mir.spanOf(id));
    }

    /// Defines `%v{id}` from the float result `%nr{id}`, with every NaN made
    /// the positive quiet NaN.
    fn canonicalNan(self: *FunctionEmitter, id: InstId, bits: u8, span: Span) std.Io.Writer.Error!void {
        var buffers: [4][24]u8 = undefined;
        const n = id.index();
        try writeCanonicalNan(self.w, .{
            .result = std.fmt.bufPrint(&buffers[0], "v{d}", .{n}) catch unreachable,
            .raw = std.fmt.bufPrint(&buffers[1], "nr{d}", .{n}) catch unreachable,
            .unordered = std.fmt.bufPrint(&buffers[2], "nu{d}", .{n}) catch unreachable,
            .quiet = std.fmt.bufPrint(&buffers[3], "nq{d}", .{n}) catch unreachable,
        }, bits, .{ .emitter = self, .span = span });
    }

    /// Where a line an emitter writes came from.
    const Here = struct { emitter: *FunctionEmitter, span: Span };

    fn multiply(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const storage = self.module.representationOf(self.mir.typeOf(id)).storage;
        const full_width = switch (storage) {
            .integer => |integer| if (integer.bits == 64) integer else null,
            else => null,
        };
        if (full_width) |info| {
            // The intrinsic returns a defined wrapped product and an overflow
            // flag. The MIR check consumes the flag at its own source span;
            // producing it here lets the value and check share one multiply.
            const p = self.mir.binaryOf(id);
            const n = id.index();
            const span = self.mir.spanOf(id);
            try self.w.print("    %m{d} = \"llvm.intr.{s}mul.with.overflow\"(%v{d}, %v{d}) : ({s}, {s}) -> !llvm.struct<({s}, i1)>", .{
                n, if (info.signedness == .signed) "s" else "u", p.lhs.index(), p.rhs.index(), int_type, int_type, int_type,
            });
            try self.here(span);
            try self.w.print("    %v{d} = llvm.extractvalue %m{d}[0] : !llvm.struct<({s}, i1)>", .{ n, n, int_type });
            try self.here(span);
            return;
        }
        try self.binaryArith(id, "muli", "mulf");
    }

    /// A division the machine itself would refuse is guarded before it runs,
    /// not checked afterwards. The pair that asks is the minimum divided by
    /// minus one, at every signed width. A narrower *quotient* overflows as an
    /// ordinary 64-bit value the range check rejects, but a narrower
    /// *remainder* of that pair computes zero -- in range, and still an
    /// overflow, because a quotient that does not exist leaves nothing over --
    /// so the remainder is guarded here at every signed width and the quotient
    /// only where the range check cannot see it.
    fn division(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const mir = self.mir;
        const p = mir.binaryOf(id);
        const ty = mir.typeOf(id);
        const n = id.index();
        const span = mir.spanOf(id);
        const is_rem = mir.tagOf(id) == .rem;
        const computation = self.computationOf(id);

        if (floatBitsOf(computation)) |bits| {
            try self.w.print("    %nr{d} = arith.{s} %v{d}, %v{d} : {s}", .{
                n, if (is_rem) "remf" else "divf", p.lhs.index(), p.rhs.index(), floatType(bits),
            });
            try self.here(span);
            try self.canonicalNan(id, bits, span);
            return;
        }

        const signedness = switch (computation) {
            .integer => |signedness| signedness,
            else => |representation| std.debug.panic("compiler defect: cannot divide {s}", .{
                @tagName(std.meta.activeTag(representation)),
            }),
        };
        const integer = switch (self.module.representationOf(ty).storage) {
            .integer => |integer| integer,
            else => |representation| std.debug.panic("compiler defect: integer division has {s} storage", .{
                @tagName(std.meta.activeTag(representation)),
            }),
        };

        // An unsigned remainder by a constant power of two is the low bits.
        // Left as a division it is a hardware divide, on what includes every
        // checked buffer access's alignment test.
        if (is_rem and signedness == .unsigned) {
            if (mir.tagOf(p.rhs) == .constant) {
                const by = mir.constantOf(p.rhs);
                if (by > 0 and std.math.isPowerOfTwo(by)) {
                    try self.w.print("    %va{d} = arith.constant {d} : {s}", .{ n, by - 1, int_type });
                    try self.here(span);
                    try self.w.print("    %v{d} = arith.andi %v{d}, %va{d} : {s}", .{
                        n, p.lhs.index(), n, int_type,
                    });
                    try self.here(span);
                    return;
                }
            }
        }

        if (signedness == .signed and (integer.bits == 64 or is_rem)) {
            const t = self.fresh();
            const min: i64 = if (integer.bits == 64)
                std.math.minInt(i64)
            else
                -(@as(i64, 1) << @intCast(integer.bits - 1));
            try self.w.print("    %k{d}ca = arith.constant {d} : {s}", .{ t, min, int_type });
            try self.here(span);
            try self.w.print("    %k{d}a = arith.cmpi eq, %v{d}, %k{d}ca : {s}", .{ t, p.lhs.index(), t, int_type });
            try self.here(span);
            try self.w.print("    %k{d}cb = arith.constant -1 : {s}", .{ t, int_type });
            try self.here(span);
            try self.w.print("    %k{d}b = arith.cmpi eq, %v{d}, %k{d}cb : {s}", .{ t, p.rhs.index(), t, int_type });
            try self.here(span);
            try self.w.print("    %k{d} = arith.andi %k{d}a, %k{d}b : i1", .{ t, t, t });
            try self.here(span);
            try self.trapIf(t, .overflow, span);
        }

        // The signed operation serves every narrower unsigned type too: a
        // narrower unsigned value is held widened as a small positive number,
        // so only the full-width unsigned type needs the unsigned instruction.
        const op = if (signedness == .unsigned and integer.bits == 64)
            (if (is_rem) "remui" else "divui")
        else
            (if (is_rem) "remsi" else "divsi");
        try self.w.print("    %v{d} = arith.{s} %v{d}, %v{d} : {s}", .{
            n, op, p.lhs.index(), p.rhs.index(), int_type,
        });
        try self.here(span);
    }

    fn comparison(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const mir = self.mir;
        const p = mir.binaryOf(id);
        const computation = self.computationOf(p.lhs);
        const signed = switch (computation) {
            .integer => |signedness| signedness == .signed,
            else => false,
        };
        const n = id.index();
        const span = mir.spanOf(id);

        // Every float form but `ne` is *ordered*, so a NaN operand yields
        // false; `ne` is the unordered form, so a NaN operand yields true.
        // That pair is IEEE 754 read straight off. Float comparison carries no
        // signedness: a sign is part of the value, not of the reading.
        if (floatBitsOf(computation)) |bits| {
            const pred = switch (mir.tagOf(id)) {
                .cmp_eq => "oeq",
                .cmp_ne => "une",
                .cmp_lt => "olt",
                .cmp_le => "ole",
                .cmp_gt => "ogt",
                .cmp_ge => "oge",
                else => |t| std.debug.panic("compiler defect: {s} is not a comparison", .{@tagName(t)}),
            };
            try self.w.print("    %v{d} = arith.cmpf {s}, %v{d}, %v{d} : {s}", .{
                n, pred, p.lhs.index(), p.rhs.index(), floatType(bits),
            });
            try self.here(span);
        } else {
            const operand_type = computationType(computation);
            const pred = switch (mir.tagOf(id)) {
                .cmp_eq => "eq",
                .cmp_ne => "ne",
                .cmp_lt => if (signed) "slt" else "ult",
                .cmp_le => if (signed) "sle" else "ule",
                .cmp_gt => if (signed) "sgt" else "ugt",
                .cmp_ge => if (signed) "sge" else "uge",
                else => |t| std.debug.panic("compiler defect: {s} is not a comparison", .{@tagName(t)}),
            };
            try self.w.print("    %v{d} = arith.cmpi {s}, %v{d}, %v{d} : {s}", .{
                n, pred, p.lhs.index(), p.rhs.index(), operand_type,
            });
            try self.here(span);
        }
    }

    fn check(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const mir = self.mir;
        const c = mir.checkOf(id);
        const target = mir.typeOf(id);
        const span = mir.spanOf(id);

        switch (c.kind) {
            .division_by_zero => {
                const t = self.fresh();
                try self.w.print("    %k{d}z = arith.constant 0 : {s}", .{ t, int_type });
                try self.here(span);
                try self.w.print("    %k{d} = arith.cmpi eq, %v{d}, %k{d}z : {s}", .{
                    t, c.value.index(), t, int_type,
                });
                try self.here(span);
                try self.trapIf(t, .division_by_zero, span);
            },
            .overflow, .conversion_out_of_range => try self.range(id, c, target),

            // The value is the comparison lowering already emitted, so what is
            // left is to trap where it did not hold.
            .index_out_of_bounds, .misaligned_access => |k| {
                const t = self.fresh();
                try self.w.print("    %k{d}z = arith.constant true", .{t});
                try self.here(span);
                try self.w.print("    %k{d} = arith.xori %v{d}, %k{d}z : i1", .{
                    t, c.value.index(), t,
                });
                try self.here(span);
                try self.trapIf(t, k, span);
            },

            // Not verifications of a value. Lowering emits these as a trap
            // terminator, never as something to check.
            .unreachable_reached, .assertion_failed, .panic, .not_a_number => |k| std.debug.panic(
                "compiler defect: {s} is a trap, not a check",
                .{@tagName(k)},
            ),
        }

        // The checked value carries on under this instruction's name, so
        // everything downstream refers to the check rather than to what
        // produced it. SSA spells no copy, so use the representation's identity.
        if (self.module.representationOf(target).computation == .boolean) {
            try self.w.print("    %v{d} = arith.ori %v{d}, %v{d} : i1", .{
                id.index(), c.value.index(), c.value.index(),
            });
            try self.here(span);
        } else {
            try self.w.print("    %p{d} = arith.constant 0 : {s}", .{ id.index(), int_type });
            try self.here(span);
            try self.w.print("    %v{d} = arith.addi %v{d}, %p{d} : {s}", .{
                id.index(), c.value.index(), id.index(), int_type,
            });
            try self.here(span);
        }
    }

    /// Whether a full-width result still names a value of its type, tested
    /// against the type's own bounds. This is `[T-Overflow]`'s enforcement:
    /// arithmetic happens at full width, and whether the result survived is a
    /// question about the target's range, read through the source's
    /// signedness because a word carries no sign of its own.
    fn range(self: *FunctionEmitter, id: InstId, c: mir_mod.Inst.Check, target: TypeId) std.Io.Writer.Error!void {
        const mir = self.mir;
        // A poisoned region is never generated for, so there is nothing to
        // verify about it.
        const info = switch (self.module.representationOf(target).storage) {
            .integer => |integer| integer,
            else => return,
        };
        const span = mir.spanOf(id);
        const v = c.value.index();

        const source_storage = self.module.representationOf(mir.typeOf(c.value)).storage;
        const source_is_integer = switch (source_storage) {
            .integer => true,
            else => false,
        };
        const source_signed = switch (source_storage) {
            .integer => |integer| integer.signedness == .signed,
            else => false,
        };
        const source_bits = switch (source_storage) {
            .integer => |integer| integer.bits,
            else => 0,
        };

        // A value the machine holds as a word carries no sign of its own: what
        // the bits mean is the *source's* signedness, and an unsigned source at
        // the full width is where the readings disagree -- its large values are
        // negative words, and a signed comparison would call them small.
        const source_unsigned64 = source_is_integer and source_bits == 64 and !source_signed;
        const target_signed = info.signedness == .signed;

        if (info.bits < 64) {
            const limits = TypeId.boundsOf(target_signed, info.bits);
            if (source_unsigned64 or !target_signed) {
                // One unsigned comparison settles it: a result below zero has
                // wrapped to a large unsigned value and fails the same test
                // that catches one too high, and a signed target's negatives
                // are unreachable from an unsigned source.
                const t = self.fresh();
                try self.w.print("    %k{d}m = arith.constant {d} : {s}", .{ t, limits.max, int_type });
                try self.here(span);
                try self.w.print("    %k{d} = arith.cmpi ugt, %v{d}, %k{d}m : {s}", .{ t, v, t, int_type });
                try self.here(span);
                try self.trapIf(t, c.kind, span);
                return;
            }
            const hi = self.fresh();
            try self.w.print("    %k{d}m = arith.constant {d} : {s}", .{ hi, limits.max, int_type });
            try self.here(span);
            try self.w.print("    %k{d} = arith.cmpi sgt, %v{d}, %k{d}m : {s}", .{ hi, v, hi, int_type });
            try self.here(span);
            try self.trapIf(hi, c.kind, span);

            const lo = self.fresh();
            try self.w.print("    %k{d}m = arith.constant {d} : {s}", .{ lo, limits.min, int_type });
            try self.here(span);
            try self.w.print("    %k{d} = arith.cmpi slt, %v{d}, %k{d}m : {s}", .{ lo, v, lo, int_type });
            try self.here(span);
            try self.trapIf(lo, c.kind, span);
            return;
        }

        // Between the two full-width types, and from any narrower signed
        // source into the unsigned one, the bit patterns that do not survive
        // are exactly the negative ones.
        const crosses = (!target_signed and source_is_integer and source_signed) or
            (source_is_integer and source_bits == 64 and source_signed != target_signed);
        if (crosses) {
            const t = self.fresh();
            try self.w.print("    %k{d}z = arith.constant 0 : {s}", .{ t, int_type });
            try self.here(span);
            try self.w.print("    %k{d} = arith.cmpi slt, %v{d}, %k{d}z : {s}", .{ t, v, t, int_type });
            try self.here(span);
            try self.trapIf(t, c.kind, span);
            return;
        }

        // A 64-bit value has already wrapped by the time it is produced, so
        // what remains is decided by the operation that produced it.
        try self.overflow64(c.value, target_signed, c.kind, span);
    }

    fn overflow64(
        self: *FunctionEmitter,
        value: InstId,
        signed: bool,
        kind: TrapKind,
        span: Span,
    ) std.Io.Writer.Error!void {
        const w = self.w;
        const mir = self.mir;
        const v = value.index();

        switch (mir.tagOf(value)) {
            .add => {
                const p = mir.binaryOf(value);
                const t = self.fresh();
                if (!signed) {
                    // A sum that wrapped is smaller than either operand.
                    try w.print("    %k{d} = arith.cmpi ult, %v{d}, %v{d} : {s}", .{ t, v, p.lhs.index(), int_type });
                    try self.here(span);
                } else {
                    // The sign of the result disagrees with both operands only
                    // when the true sum left the range.
                    try w.print("    %k{d}a = arith.xori %v{d}, %v{d} : {s}", .{ t, p.lhs.index(), v, int_type });
                    try self.here(span);
                    try w.print("    %k{d}b = arith.xori %v{d}, %v{d} : {s}", .{ t, p.rhs.index(), v, int_type });
                    try self.here(span);
                    try w.print("    %k{d}c = arith.andi %k{d}a, %k{d}b : {s}", .{ t, t, t, int_type });
                    try self.here(span);
                    try w.print("    %k{d}z = arith.constant 0 : {s}", .{ t, int_type });
                    try self.here(span);
                    try w.print("    %k{d} = arith.cmpi slt, %k{d}c, %k{d}z : {s}", .{ t, t, t, int_type });
                    try self.here(span);
                }
                try self.trapIf(t, kind, span);
            },
            .sub => {
                const p = mir.binaryOf(value);
                const t = self.fresh();
                if (!signed) {
                    try w.print("    %k{d} = arith.cmpi ult, %v{d}, %v{d} : {s}", .{
                        t, p.lhs.index(), p.rhs.index(), int_type,
                    });
                    try self.here(span);
                } else {
                    try w.print("    %k{d}a = arith.xori %v{d}, %v{d} : {s}", .{
                        t, p.lhs.index(), p.rhs.index(), int_type,
                    });
                    try self.here(span);
                    try w.print("    %k{d}b = arith.xori %v{d}, %v{d} : {s}", .{ t, p.lhs.index(), v, int_type });
                    try self.here(span);
                    try w.print("    %k{d}c = arith.andi %k{d}a, %k{d}b : {s}", .{ t, t, t, int_type });
                    try self.here(span);
                    try w.print("    %k{d}z = arith.constant 0 : {s}", .{ t, int_type });
                    try self.here(span);
                    try w.print("    %k{d} = arith.cmpi slt, %k{d}c, %k{d}z : {s}", .{ t, t, t, int_type });
                    try self.here(span);
                }
                try self.trapIf(t, kind, span);
            },
            .mul => {
                const t = self.fresh();
                try w.print("    %k{d} = llvm.extractvalue %m{d}[1] : !llvm.struct<({s}, i1)>", .{ t, v, int_type });
                try self.here(span);
                try self.trapIf(t, kind, span);
            },
            .neg => {
                const operand = mir.unaryOf(value).index();
                const t = self.fresh();
                if (!signed) {
                    // Negating an unsigned value leaves the type unless it was
                    // zero.
                    try w.print("    %k{d}z = arith.constant 0 : {s}", .{ t, int_type });
                    try self.here(span);
                    try w.print("    %k{d} = arith.cmpi ne, %v{d}, %k{d}z : {s}", .{ t, operand, t, int_type });
                    try self.here(span);
                } else {
                    try w.print("    %k{d}z = arith.constant {d} : {s}", .{ t, std.math.minInt(i64), int_type });
                    try self.here(span);
                    try w.print("    %k{d} = arith.cmpi eq, %v{d}, %k{d}z : {s}", .{ t, operand, t, int_type });
                    try self.here(span);
                }
                try self.trapIf(t, kind, span);
            },
            // A division's failures are guarded where the division is emitted,
            // and a constant or a load of a value of the same type is already
            // in range.
            else => {},
        }
    }

    /// A `Float64` becoming the integer its instruction names, with the guards
    /// that are the conversion's own meaning: a NaN is no number, and a value
    /// whose truncation the target cannot hold has no honest result.
    ///
    /// The bounds are values of the source float type, tested exclusively --
    /// `v >= max + 1` and `v <= min - 1` -- so a fractional value whose
    /// *truncation* fits is admitted: `-0.5` becomes `0` in every integer
    /// type. `max + 1` is a power of two, exact in either float type. `min - 1`
    /// is not exact where the target is as wide as the source's significand or
    /// wider -- `Int64` from either float, `Int32` from `Float32` -- and there
    /// the test is `v < min` instead, which is the same set because no value of
    /// the source type lies between the two.
    fn floatToInt(self: *FunctionEmitter, id: InstId) std.Io.Writer.Error!void {
        const w = self.w;
        const mir = self.mir;
        const ty = mir.typeOf(id);
        // A poisoned region is never generated for.
        const info = switch (self.module.representationOf(ty).storage) {
            .integer => |integer| integer,
            else => return,
        };
        const span = mir.spanOf(id);
        const operand = mir.unaryOf(id);
        const v = operand.index();
        const width = floatBitsOf(self.module.representationOf(mir.typeOf(operand)).computation) orelse return;
        const float_type = floatType(width);
        const signed = info.signedness == .signed;
        const bounds = FloatToIntBounds.of(signed, info.bits, width);

        const nan = self.fresh();
        try w.print("    %k{d} = arith.cmpf une, %v{d}, %v{d} : {s}", .{ nan, v, v, float_type });
        try self.here(span);
        try self.trapIf(nan, .not_a_number, span);

        const hi = self.fresh();
        try w.print("    %k{d}c = arith.constant 0x{X} : {s}", .{ hi, floatConstantBits(bounds.upper, width), float_type });
        try self.here(span);
        try w.print("    %k{d} = arith.cmpf oge, %v{d}, %k{d}c : {s}", .{ hi, v, hi, float_type });
        try self.here(span);
        try self.trapIf(hi, .conversion_out_of_range, span);

        const lo = self.fresh();
        try w.print("    %k{d}c = arith.constant 0x{X} : {s}", .{ lo, floatConstantBits(bounds.lower, width), float_type });
        try self.here(span);
        try w.print("    %k{d} = arith.cmpf {s}, %v{d}, %k{d}c : {s}", .{ lo, if (bounds.lower_inclusive) "olt" else "ole", v, lo, float_type });
        try self.here(span);
        try self.trapIf(lo, .conversion_out_of_range, span);

        try w.print("    %v{d} = arith.{s} %v{d} : {s} to {s}", .{
            id.index(), if (signed) "fptosi" else "fptoui", v, float_type, int_type,
        });
        try self.here(span);
    }

    /// Branches to a block that reports the failure and aborts. The block sits
    /// between the two halves of the test, which costs nothing: control flow is
    /// explicit, so the order blocks appear in the text does not matter.
    fn trapIf(self: *FunctionEmitter, cond: u32, kind: TrapKind, span: Span) std.Io.Writer.Error!void {
        try self.w.print("    cf.cond_br %k{d}, ^t{d}, ^c{d}", .{ cond, cond, cond });
        try self.here(span);
        try self.w.print("  ^t{d}:\n", .{cond});
        try self.trapAndStop(cond, kind, span);
        try self.w.print("  ^c{d}:\n", .{cond});
    }

    /// Reports the failure to the runtime and ends the block it happened in.
    ///
    /// One operation rather than two, because a block that has called the trap
    /// is a block control never leaves, and every site that reports wants both.
    fn trapAndStop(self: *FunctionEmitter, n: u32, kind: TrapKind, span: Span) std.Io.Writer.Error!void {
        const at = self.position(span);
        try self.w.print("    %tk{d} = arith.constant {d} : {s}", .{ n, @intFromEnum(kind), runtime_int });
        try self.here(span);
        try self.w.print("    %{s}{d} = llvm.mlir.addressof @linea_file{d} : !llvm.ptr", .{
            trap_file_name, n, self.file_symbol,
        });
        try self.here(span);
        try self.w.print("    %{s}{d} = arith.constant {d} : {s}", .{ trap_line_name, n, at.line, runtime_int });
        try self.here(span);
        try self.w.print("    %{s}{d} = arith.constant {d} : {s}", .{ trap_col_name, n, at.column, runtime_int });
        try self.here(span);
        try self.w.print("    func.call @{s}(%tk{d}, %{s}{d}, %{s}{d}, %{s}{d})", .{
            runtime_symbols.trap, n, trap_file_name, n, trap_line_name, n, trap_col_name, n,
        });
        try writeOwnedCallType(self.w, runtime_symbols.trap_signature);
        try self.here(span);
        try self.w.writeAll("    llvm.unreachable");
        try self.here(span);
    }

    fn panicAndStop(self: *FunctionEmitter, n: u32, message: InstId, span: Span) std.Io.Writer.Error!void {
        const fields = self.module.types.textFields(self.module.panic_message_type).?;
        const at = self.position(span);

        try self.panicField(n, "a", message, fields.at.offset, span);
        try self.panicField(n, "l", message, fields.len.offset, span);
        try self.w.print("    %{s}{d} = llvm.mlir.addressof @linea_file{d} : !llvm.ptr", .{ panic_file_name, n, self.file_symbol });
        try self.here(span);
        try self.w.print("    %{s}{d} = arith.constant {d} : {s}", .{ trap_line_name, n, at.line, runtime_int });
        try self.here(span);
        try self.w.print("    %{s}{d} = arith.constant {d} : {s}", .{ trap_col_name, n, at.column, runtime_int });
        try self.here(span);
        try self.w.print("    func.call @{s}(%pva{d}, %pvl{d}, %{s}{d}, %{s}{d}, %{s}{d})", .{
            runtime_symbols.panic, n, n, panic_file_name, n, trap_line_name, n, trap_col_name, n,
        });
        try writeOwnedCallType(self.w, runtime_symbols.panic_signature);
        try self.here(span);
        try self.w.writeAll("    llvm.unreachable");
        try self.here(span);
    }

    fn panicField(
        self: *FunctionEmitter,
        n: u32,
        comptime suffix: []const u8,
        message: InstId,
        offset: u32,
        span: Span,
    ) std.Io.Writer.Error!void {
        try self.w.print("    %po{s}{d} = arith.constant {d} : {s}", .{ suffix, n, offset, int_type });
        try self.here(span);
        try self.w.print("    %pp{s}{d} = llvm.getelementptr ", .{ suffix, n });
        try self.writeValue(message);
        try self.w.print("[%po{s}{d}] : (!llvm.ptr, i64) -> !llvm.ptr, i8", .{ suffix, n });
        try self.here(span);
        try self.w.print("    %pv{s}{d} = llvm.load %pp{s}{d} : !llvm.ptr -> {s}", .{ suffix, n, suffix, n, int_type });
        try self.here(span);
    }
};

test "trap file symbols ignore unreferenced source prefixes and distinguish equal paths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: source_mod.Source = .{ .path = "same.lin", .text =
        \\fn helper(value: UInt8) -> UInt8 { value + 1 }
        \\fn main() -> UInt8 { helper(1) + 1 }
    };
    var sink = Sink.init(gpa);
    var interner: @import("../support/interner.zig").Interner = .empty;
    const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try @import("../sema/resolve.zig").resolveTree(gpa, &ast, &sink);
    var typing = try @import("../sema/typecheck.zig").typecheckTree(gpa, &resolved, &sink);
    var disposals = try @import("../ownership/check.zig").check(gpa, gpa, &resolved.expanded, &resolved.resolution, &typing, &sink);
    var module = (try @import("../mir/lower.zig").lowerProgram(gpa, &resolved.expanded, &resolved.resolution, &typing, &disposals, &sink, .program)).?;
    try testing.expect(!sink.hasErrors());
    try testing.expectEqual(@as(usize, 2), module.functions.len);
    const functions = try gpa.dupe(Mir, module.functions);
    module.functions = functions;
    var expected: []const u8 = undefined;
    for ([_]usize{ 0, 3 }) |prefix| {
        var table: FileTable = .{};
        for (0..prefix) |_| _ = try table.add(gpa, .{ .path = "unreferenced.lin", .text = "" });
        _ = try table.add(gpa, source);
        _ = try table.add(gpa, source);
        // Reverse file-table order to exercise first use independently of IDs.
        functions[0].file = .from(prefix + 1);
        functions[1].file = .from(prefix);
        var output: std.Io.Writer.Allocating = .init(gpa);
        try testing.expect(try emit(gpa, &output.writer, &module, &table, &sink));
        if (prefix == 0) {
            expected = try gpa.dupe(u8, output.written());
            try testing.expectEqual(@as(usize, 2), std.mem.count(u8, expected, "llvm.mlir.global internal constant @linea_file"));
            try testing.expect(std.mem.indexOf(u8, expected, "llvm.mlir.addressof @linea_file0") != null);
            try testing.expect(std.mem.indexOf(u8, expected, "llvm.mlir.addressof @linea_file1") != null);
        } else try testing.expectEqualStrings(expected, output.written());
    }
}

test "emitted locations follow repeated and reordered Unicode source spans" {
    const source: source_mod.Source = .{ .path = "t.lin", .text = "éx\nz" };
    var map = try SourceMap.init(testing.allocator, &source);
    defer map.deinit();
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var emitter: FunctionEmitter = .{
        .w = &writer,
        .mir = undefined,
        .module = undefined,
        .map = &map,
        .path = source.path,
        .indirect = false,
    };
    for ([_]u32{ 0, 0, 2, 4, 2 }) |offset| try emitter.here(.{ .start = offset, .end = offset });
    try testing.expectEqualStrings(
        " loc(\"t.lin\":1:1)\n" ++
            " loc(\"t.lin\":1:1)\n" ++
            " loc(\"t.lin\":1:2)\n" ++
            " loc(\"t.lin\":2:1)\n" ++
            " loc(\"t.lin\":1:2)\n",
        writer.buffered(),
    );
}

/// The values a float of `float_bits` bits truncates into an integer type
/// from, as two exclusive bounds: the conversion traps at or above `upper`, and
/// below `lower` -- or at it, unless `lower_inclusive`, where `lower` is the
/// type's minimum itself because the value one below it is not exact.
const FloatToIntBounds = struct {
    upper: f64,
    lower: f64,
    lower_inclusive: bool,

    fn of(signed: bool, integer_bits: u8, float_bits: u8) FloatToIntBounds {
        const limits = TypeId.boundsOf(signed, integer_bits);
        // `max + 1` and `min` are powers of two (or zero), so both are exact.
        const upper: f64 = @floatFromInt(limits.max + 1);
        const min: f64 = @floatFromInt(limits.min);
        const significand_bits: u8 = if (float_bits == 32) 24 else 53;
        // `min - 1` needs as many significant bits as the integer's magnitude.
        const below_is_exact = !signed or integer_bits <= significand_bits;
        return if (below_is_exact)
            .{ .upper = upper, .lower = min - 1.0, .lower_inclusive = false }
        else
            .{ .upper = upper, .lower = min, .lower_inclusive = true };
    }
};

test "a float truncates into an integer between exact bounds" {
    const int32_from_float32 = FloatToIntBounds.of(true, 32, 32);
    try std.testing.expectEqual(@as(f64, 2147483648.0), int32_from_float32.upper);
    try std.testing.expectEqual(@as(f64, -2147483648.0), int32_from_float32.lower);
    try std.testing.expect(int32_from_float32.lower_inclusive);
    const int32_from_float64 = FloatToIntBounds.of(true, 32, 64);
    try std.testing.expectEqual(@as(f64, -2147483649.0), int32_from_float64.lower);
    try std.testing.expect(!int32_from_float64.lower_inclusive);
    try std.testing.expect(FloatToIntBounds.of(true, 64, 64).lower_inclusive);
    const uint8 = FloatToIntBounds.of(false, 8, 32);
    try std.testing.expectEqual(@as(f64, 256.0), uint8.upper);
    try std.testing.expectEqual(@as(f64, -1.0), uint8.lower);
    // Every bound is exact in the source width.
    for ([_]u8{ 32, 64 }) |float_bits| for ([_]u8{ 8, 16, 32, 64 }) |integer_bits| for ([_]bool{ false, true }) |signed| {
        const bounds = FloatToIntBounds.of(signed, integer_bits, float_bits);
        if (float_bits == 32) {
            try std.testing.expectEqual(bounds.upper, @as(f64, @as(f32, @floatCast(bounds.upper))));
            try std.testing.expectEqual(bounds.lower, @as(f64, @as(f32, @floatCast(bounds.lower))));
        }
    };
}

fn computationType(representation: mir_mod.ComputationRepresentation) []const u8 {
    return switch (representation) {
        .integer, .enum_tag, .unit => int_type,
        .boolean => "i1",
        .float => |bits| floatType(bits),
        .code_pointer, .data_pointer => "!llvm.ptr",
        .indirect, .no_value, .invalid => std.debug.panic(
            "compiler defect: {s} is not a scalar computation",
            .{@tagName(std.meta.activeTag(representation))},
        ),
    };
}

fn storageType(representation: mir_mod.StorageRepresentation) []const u8 {
    return switch (representation) {
        .integer => |integer| switch (integer.bits) {
            8 => "i8",
            16 => "i16",
            32 => "i32",
            64 => int_type,
            else => std.debug.panic("compiler defect: integer storage is {d} bits wide", .{integer.bits}),
        },
        .boolean => "i8",
        .float => |bits| floatType(bits),
        .enum_tag, .unit => int_type,
        .code_pointer, .data_pointer => "!llvm.ptr",
        .bytes, .no_value, .invalid => std.debug.panic(
            "compiler defect: {s} is not scalar storage",
            .{@tagName(std.meta.activeTag(representation))},
        ),
    };
}

/// The elements of a static's packed structure, in order: a run of zero
/// bytes wherever the next part does not begin where the last one ended, each
/// part, and a run from the last part to the end of the static's type.
///
/// A packed structure places nothing of its own, so each part sits at the
/// offset its type's layout gives it. The type and the value of a static are
/// both written from this one walk, so their elements agree.
const StaticElements = struct {
    module: *const Module,
    entry: mir_mod.Static,
    at: u32 = 0,
    part: usize = 0,

    const Element = union(enum) { zeros: u32, part: mir_mod.StaticPart };

    fn next(self: *StaticElements) ?Element {
        if (self.part < self.entry.parts.len) {
            const part = self.entry.parts[self.part];
            if (part.offset > self.at) {
                defer self.at = part.offset;
                return .{ .zeros = part.offset - self.at };
            }
            self.part += 1;
            self.at = part.offset + self.module.layoutOf(part.ty).size;
            return .{ .part = part };
        }
        const size = self.module.layoutOf(self.entry.ty).size;
        if (size <= self.at) return null;
        defer self.at = size;
        return .{ .zeros = size - self.at };
    }
};

/// One static's type, named once as `!linea_static{i}` so every operation
/// building the static names it in a word rather than spelling all its parts.
/// A part is held in the storage type a store of it writes.
fn writeStaticType(w: *std.Io.Writer, module: *const Module, entry: mir_mod.Static, i: usize) std.Io.Writer.Error!void {
    try w.print("!linea_static{d} = !llvm.struct<packed (", .{i});
    var elements: StaticElements = .{ .module = module, .entry = entry };
    var first = true;
    while (elements.next()) |element| {
        if (!first) try w.writeAll(", ");
        first = false;
        switch (element) {
            .zeros => |count| try w.print("!llvm.array<{d} x i8>", .{count}),
            .part => |part| try w.writeAll(storageType(module.representationOf(part.ty).storage)),
        }
    }
    try w.writeAll(")>\n");
}

/// One static as a constant global of the type `writeStaticType` names,
/// aligned as the static's type is, so a load of any part is aligned.
///
/// A part is written as a store of its type would write it, and a blob's
/// address as the integer `bytes_addr` produces for it.
fn writeStatic(w: *std.Io.Writer, module: *const Module, entry: mir_mod.Static, i: usize) std.Io.Writer.Error!void {
    try w.print("  llvm.mlir.global internal constant @linea_static{d}() {{addr_space = 0 : i32, alignment = {d} : i64}} : !linea_static{d} {{\n", .{ i, module.layoutOf(entry.ty).alignment, i });
    try w.print("    %s0 = llvm.mlir.undef : !linea_static{d}\n", .{i});
    var elements: StaticElements = .{ .module = module, .entry = entry };
    var n: u32 = 0;
    while (elements.next()) |element| : (n += 1) {
        switch (element) {
            .zeros => |count| try w.print("    %e{d} = llvm.mlir.zero : !llvm.array<{d} x i8>\n", .{ n, count }),
            .part => |part| {
                const t = storageType(module.representationOf(part.ty).storage);
                switch (part.value) {
                    .constant => |value| {
                        // The part's bits read as a signed integer of its
                        // width: the one spelling of every bit pattern that
                        // width accepts.
                        const shift: u6 = @intCast(64 - module.layoutOf(part.ty).size * 8);
                        const word: u64 = @truncate(@as(u128, @bitCast(value)));
                        const signed: i64 = @as(i64, @bitCast(word << shift)) >> shift;
                        try w.print("    %e{d} = llvm.mlir.constant({d} : {s}) : {s}\n", .{ n, signed, t, t });
                    },
                    .bytes => |blob| {
                        try w.print("    %a{d} = llvm.mlir.addressof @linea_str{d} : !llvm.ptr\n", .{ n, blob });
                        try w.print("    %e{d} = llvm.ptrtoint %a{d} : !llvm.ptr to {s}\n", .{ n, n, int_type });
                    },
                }
            },
        }
        try w.print("    %s{d} = llvm.insertvalue %e{d}, %s{d}[{d}] : !linea_static{d}\n", .{ n + 1, n, n, n, i });
    }
    try w.print("    llvm.return %s{d} : !linea_static{d}\n", .{ n, i });
    try w.writeAll("  }\n");
}

test "a static is written as its parts with zero runs between them" {
    const gpa = testing.allocator;
    var representations = try mir_mod.TypeRepresentations.of(gpa, TypeId.builtins.len, .{ .computation = .invalid, .storage = .invalid });
    defer representations.deinit(gpa);
    representations.set(.u8, .{ .computation = .{ .integer = .unsigned }, .storage = .{ .integer = .{ .signedness = .unsigned, .bits = 8 } } });
    representations.set(.u64, .{ .computation = .{ .integer = .unsigned }, .storage = .{ .integer = .{ .signedness = .unsigned, .bits = 64 } } });
    const layouts = try gpa.alloc(types_mod.Layout, TypeId.builtins.len);
    defer gpa.free(layouts);
    @memset(layouts, .{ .size = 8, .alignment = 8 });
    layouts[@intFromEnum(TypeId.u8)] = .{ .size = 1, .alignment = 1 };
    // Read as a 24-byte record: a byte, a word naming a blob, and a tail.
    layouts[@intFromEnum(TypeId.i64)] = .{ .size = 24, .alignment = 8 };
    const module: Module = .{
        .functions = &.{},
        .external = &.{},
        .bytes = &.{"tea"},
        .names = &.{},
        .origins = &.{},
        .representations = representations,
        .layouts = layouts,
        .entry = .none,
    };
    const entry: mir_mod.Static = .{ .ty = .i64, .parts = &.{
        .{ .offset = 0, .ty = .u8, .value = .{ .constant = 255 } },
        .{ .offset = 8, .ty = .u64, .value = .{ .bytes = 0 } },
    } };
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try writeStaticType(&out.writer, &module, entry, 3);
    try writeStatic(&out.writer, &module, entry, 3);
    try testing.expectEqualStrings(
        \\!linea_static3 = !llvm.struct<packed (i8, !llvm.array<7 x i8>, i64, !llvm.array<8 x i8>)>
        \\  llvm.mlir.global internal constant @linea_static3() {addr_space = 0 : i32, alignment = 8 : i64} : !linea_static3 {
        \\    %s0 = llvm.mlir.undef : !linea_static3
        \\    %e0 = llvm.mlir.constant(-1 : i8) : i8
        \\    %s1 = llvm.insertvalue %e0, %s0[0] : !linea_static3
        \\    %e1 = llvm.mlir.zero : !llvm.array<7 x i8>
        \\    %s2 = llvm.insertvalue %e1, %s1[1] : !linea_static3
        \\    %a2 = llvm.mlir.addressof @linea_str0 : !llvm.ptr
        \\    %e2 = llvm.ptrtoint %a2 : !llvm.ptr to i64
        \\    %s3 = llvm.insertvalue %e2, %s2[2] : !linea_static3
        \\    %e3 = llvm.mlir.zero : !llvm.array<8 x i8>
        \\    %s4 = llvm.insertvalue %e3, %s3[3] : !linea_static3
        \\    llvm.return %s4 : !linea_static3
        \\  }
        \\
    , out.written());
}

/// Writes bytes as the contents of an MLIR string literal.
///
/// Everything outside printable ASCII, and the quote and the backslash, becomes
/// a two-digit hex escape -- the one escape form the format defines for
/// arbitrary bytes. The array type beside the literal counts decoded bytes, so
/// escaping changes nothing about the length written there.
fn writeMlirString(w: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!void {
    for (bytes) |b| {
        if (b == '"' or b == '\\' or b < 0x20 or b > 0x7e) {
            try w.print("\\{X:0>2}", .{b});
        } else {
            try w.writeByte(b);
        }
    }
}

/// The printed type of one parameter position, read where the function is
/// defined, where an extern is declared, and where any call types its
/// arguments. One routine, because a convention spelled at three sites is
/// three spellings that can disagree, and the disagreement compiles.
fn paramTypeOf(module: *const Module, id: FunctionId, callee: *const Mir, i: usize) []const u8 {
    // A parameter arriving by address is a pointer whatever it holds.
    if (module.arrivesByAddress(callee, i)) return "!llvm.ptr";
    const ty = callee.locals[i];
    if (module.isExternal(id)) return foreignTypeOf(module, ty);
    return computationType(module.representationOf(ty).computation);
}

fn callableParamType(module: *const Module, param: types_mod.CallableParam) []const u8 {
    if (module.parameterByAddress(param)) return "!llvm.ptr";
    const slot_ty = mir_mod.parameterSlotType(module.types.erased(param.ty));
    return computationType(module.representationOf(slot_ty).computation);
}

/// What one function's printed signature answers, or null for nothing --
/// the other half of the convention, read at the same three sites.
///
/// An external answering unit answers nothing, because a C function that sets
/// no return register must not be read as though it had; an indirect answer
/// travels through the caller's storage, not the signature. The entry is not
/// special here: it answers the module's width like any function, because a
/// program may call it like any function, and the runtime's narrower status
/// is the wrapper's business.
fn resultTypeOf(module: *const Module, id: FunctionId, ret: TypeId) ?[]const u8 {
    if (module.returnsIndirectly(id)) return null;
    if (ret == .never) return null;
    if (module.isExternal(id) and ret == .unit) return null;
    if (module.isExternal(id)) return foreignTypeOf(module, ret);
    return computationType(module.representationOf(ret).computation);
}

/// The name a function is emitted under. Read from the module rather than
/// rebuilt, because a name computed twice is a name that can differ, and every
/// reference to a declaration must spell it the way its definition does.
fn writeSymbol(w: *std.Io.Writer, module: *const Module, id: FunctionId) std.Io.Writer.Error!void {
    const name = module.nameOf(id);
    std.debug.assert(symbol_names.holds(name));
    if (module.isExternal(id)) {
        // Somebody else's symbol, spelled as they spelled it: the prefix is
        // this language's claim on a name it defined, and this is not one.
        try writeSymbolName(w, name, "");
    } else {
        std.debug.assert(name.len <= symbol_names.max_len);
        try writeSymbolName(w, name, symbol_names.defined_prefix);
    }
}

/// A symbol reference, quoted where this dialect's bare form cannot spell it.
///
/// What a symbol may hold and what `@name` may hold are two different sets, and
/// the wider one is the object formats'. An instantiation carries brackets and
/// a comma, which every assembler and linker this compiler runs takes -- and
/// which the dialect's bare identifier stops at, reporting a parse error about
/// the character rather than about the name. `@"..."` is the dialect's own
/// answer for exactly that, so a name that needs it gets it.
///
/// Asked of the name rather than of what produced it, because the emitter is
/// handed names from several places and a rule about their origin would be a
/// second thing to keep true.
fn writeSymbolName(
    w: *std.Io.Writer,
    name: []const u8,
    prefix: []const u8,
) std.Io.Writer.Error!void {
    if (bareInDialect(name)) {
        try w.print("{s}{s}", .{ prefix, name });
        return;
    }
    try w.writeByte('"');
    try w.print("{s}{s}", .{ prefix, name });
    try w.writeByte('"');
}

/// Whether every byte is one the dialect's unquoted `@name` accepts.
fn bareInDialect(name: []const u8) bool {
    for (name) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '.', '$', '-' => {},
        else => return false,
    };
    return true;
}

test "a byte outside printable ascii is a hex escape" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();

    try writeMlirString(&out.writer, "a\"b\\c\nd");
    try testing.expectEqualStrings("a\\22b\\5Cc\\0Ad", out.written());
}

test "storage types follow recorded representations" {
    try testing.expectEqualStrings("i64", computationType(.{ .integer = .unsigned }));
    try testing.expectEqualStrings("i1", computationType(.boolean));
    try testing.expectEqualStrings("f64", computationType(.{ .float = 64 }));
    try testing.expectEqualStrings("f32", computationType(.{ .float = 32 }));
    try testing.expectEqualStrings("i8", storageType(.{ .integer = .{ .signedness = .unsigned, .bits = 8 } }));
    try testing.expectEqualStrings("i16", storageType(.{ .integer = .{ .signedness = .signed, .bits = 16 } }));
    try testing.expectEqualStrings("i8", storageType(.boolean));
    try testing.expectEqualStrings("f64", storageType(.{ .float = 64 }));
    try testing.expectEqualStrings("f32", storageType(.{ .float = 32 }));
}

test "an integer is computed wider than its type names" {
    // `[T-Overflow]` is a `check` instruction over a full-width result, so the
    // arithmetic before it is not where overflow is decided. A `UInt8` add
    // printed as `i8` would decide it there instead, and the two answers would
    // differ exactly on the program that overflows.
    try testing.expectEqualStrings(int_type, computationType(.{ .integer = .unsigned }));
    try testing.expectEqualStrings(int_type, computationType(.{ .integer = .signed }));
}

test "integer to float emission preserves the recorded source width" {
    const gpa = testing.allocator;
    const source: source_mod.Source = .{ .path = "conversion.lin", .text = "Float64(value)" };
    var map = try SourceMap.init(gpa, &source);
    defer map.deinit();
    const Case = struct { ty: TypeId, width: u8, signedness: mir_mod.Signedness };
    const cases = [_]Case{
        .{ .ty = .i8, .width = 8, .signedness = .signed },
        .{ .ty = .i16, .width = 16, .signedness = .signed },
        .{ .ty = .i32, .width = 32, .signedness = .signed },
        .{ .ty = .i64, .width = 64, .signedness = .signed },
        .{ .ty = .u8, .width = 8, .signedness = .unsigned },
        .{ .ty = .u16, .width = 16, .signedness = .unsigned },
        .{ .ty = .u32, .width = 32, .signedness = .unsigned },
        .{ .ty = .u64, .width = 64, .signedness = .unsigned },
    };
    for (cases) |case| {
        var builder = Mir.Builder.init(gpa);
        defer builder.deinit();
        const block = try builder.addBlock();
        const value = try builder.addInst(block, .{
            .tag = .constant,
            .ty = case.ty,
            .span = Span.empty,
            .data = .{ .constant = 1 },
        });
        const converted = try builder.addInst(block, .{
            .tag = .int_to_float,
            .ty = .f64,
            .span = Span.empty,
            .data = .{ .unary = value },
        });
        _ = try builder.setTerminator(block, .{
            .tag = .ret,
            .ty = .unit,
            .span = Span.empty,
            .data = .{ .unary = converted },
        });
        var mir = try builder.finish(block, .from(0));
        defer mir.deinit(gpa);
        var representations = try mir_mod.TypeRepresentations.of(gpa, TypeId.builtins.len, .{ .computation = .invalid, .storage = .invalid });
        defer representations.deinit(gpa);
        representations.set(case.ty, .{
            .computation = .{ .integer = case.signedness },
            .storage = .{ .integer = .{ .signedness = case.signedness, .bits = case.width } },
        });
        representations.set(.f64, .{ .computation = .{ .float = 64 }, .storage = .{ .float = 64 } });
        const module: Module = .{
            .functions = &.{},
            .external = &.{},
            .bytes = &.{},
            .names = &.{},
            .origins = &.{},
            .representations = representations,
            .layouts = &.{},
            .entry = .none,
        };
        var out: std.Io.Writer.Allocating = .init(gpa);
        defer out.deinit();
        var emitter: FunctionEmitter = .{
            .w = &out.writer,
            .mir = &mir,
            .module = &module,
            .map = &map,
            .path = source.path,
            .indirect = false,
        };
        try emitter.inst(converted);
        const expected = try std.fmt.allocPrint(gpa, ": i{d} to f64", .{case.width});
        defer gpa.free(expected);
        try testing.expect(std.mem.indexOf(u8, out.written(), expected) != null);
        const operation = if (case.signedness == .signed) "arith.sitofp" else "arith.uitofp";
        try testing.expect(std.mem.indexOf(u8, out.written(), operation) != null);
        if (case.width == 64) try testing.expect(std.mem.indexOf(u8, out.written(), "arith.trunci") == null);
    }
}

test "borrow aliases survive named and payload pointer stores" {
    const gpa = testing.allocator;
    var types = try types_mod.Typing.Builder.init(gpa);
    defer types.deinit();
    const observed = try types.borrowOf(.u64);
    var builder = Mir.Builder.init(gpa);
    defer builder.deinit();
    const block = try builder.addBlock();
    const owner = try builder.addLocal(.u64, .value);
    const saved = try builder.addLocal(observed, .value);
    const address = try builder.addInst(block, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = .u64,
        .span = Span.empty,
        .data = .{ .local = owner },
    });
    const view = try builder.addInst(block, .{
        .tag = .borrow,
        .ty = observed,
        .span = Span.empty,
        .data = .{ .unary = address },
    });
    const named = try builder.addInst(block, .{
        .tag = .store,
        .ty = observed,
        .span = Span.empty,
        .data = .{ .store = .{ .local = saved, .value = view } },
    });
    const destination = try builder.addInst(block, .{
        .tag = .addr_of,
        .result_role = .managed_address,
        .ty = observed,
        .span = Span.empty,
        .data = .{ .local = saved },
    });
    const payload = try builder.addInst(block, .{
        .tag = .store_indirect,
        .ty = observed,
        .span = Span.empty,
        .data = .{ .binary = .{ .lhs = destination, .rhs = view } },
    });
    _ = try builder.setTerminator(block, .{
        .tag = .ret,
        .ty = .unit,
        .span = Span.empty,
        .data = .{ .unary = view },
    });
    var mir = try builder.finish(block, .from(0));
    defer mir.deinit(gpa);
    const layouts = try gpa.alloc(types_mod.Layout, types.pool.items.len);
    defer gpa.free(layouts);
    @memset(layouts, .{ .size = 8, .alignment = 8 });
    var representations = try mir_mod.deriveRepresentations(gpa, &types.view(), layouts);
    defer representations.deinit(gpa);
    const module: Module = .{
        .functions = &.{},
        .external = &.{},
        .bytes = &.{},
        .names = &.{},
        .origins = &.{},
        .types = types.view(),
        .representations = representations,
        .layouts = layouts,
        .entry = .none,
    };
    const source: source_mod.Source = .{ .path = "borrow.lin", .text = "borrow owner" };
    var map = try SourceMap.init(gpa, &source);
    defer map.deinit();
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var emitter: FunctionEmitter = .{
        .w = &output.writer,
        .mir = &mir,
        .module = &module,
        .map = &map,
        .path = source.path,
        .indirect = false,
    };
    try emitter.inst(named);
    try emitter.inst(payload);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, output.written(), "llvm.store %s0, %s1 : !llvm.ptr, !llvm.ptr"));
}

test "checked wide multiplication does not introduce division" {
    const source: source_mod.Source = .{ .path = "multiply.lin", .text = "lhs * rhs" };
    var map = try SourceMap.init(testing.allocator, &source);
    defer map.deinit();
    const span: Span = .{ .start = 4, .end = 5 };

    for ([_]bool{ false, true }) |signed| {
        const ty: TypeId = if (signed) .i64 else .u64;
        var builder = Mir.Builder.init(testing.allocator);
        defer builder.deinit();
        const block = try builder.addBlock();
        const lhs = try builder.addInst(block, .{
            .tag = .constant,
            .ty = ty,
            .span = span,
            .data = .{ .constant = 3 },
        });
        const rhs = try builder.addInst(block, .{
            .tag = .constant,
            .ty = ty,
            .span = span,
            .data = .{ .constant = 4 },
        });
        const product = try builder.addInst(block, .{
            .tag = .mul,
            .ty = ty,
            .span = span,
            .data = .{ .binary = .{ .lhs = lhs, .rhs = rhs } },
        });
        _ = try builder.setTerminator(block, .{
            .tag = .ret,
            .ty = .unit,
            .span = span,
            .data = .{ .unary = product },
        });
        var mir = try builder.finish(block, .from(0));
        defer mir.deinit(testing.allocator);
        var out: std.Io.Writer.Allocating = .init(testing.allocator);
        defer out.deinit();
        var emitter: FunctionEmitter = .{
            .w = &out.writer,
            .mir = &mir,
            .module = undefined,
            .map = &map,
            .path = source.path,
            .indirect = false,
        };
        try emitter.overflow64(product, signed, .overflow, span);
        try testing.expect(std.mem.indexOf(u8, out.written(), "arith.div") == null);
        try testing.expect(std.mem.indexOf(u8, out.written(), "cf.cond_br") != null);
        try testing.expect(std.mem.indexOf(u8, out.written(), "func.call @" ++ runtime_symbols.trap) != null);
        try testing.expect(std.mem.indexOf(u8, out.written(), "loc(\"multiply.lin\":1:5)") != null);
    }
}

test "aggregate tail calls use the final return destination only across an empty exit" {
    const gpa = testing.allocator;
    const Shape = enum { direct, copied_join, work_after_call, managed_destination };
    for (std.enums.values(Shape)) |shape| {
        var types = try types_mod.Typing.Builder.init(gpa);
        defer types.deinit();
        const aggregate = try types.arrayOf(.u64, 2);
        const signature = try types.internCallable(&.{.{
            .spelling = "input",
            .convention = .inout,
            .ty = aggregate,
            .default = .absent,
        }}, aggregate, &.{}, .read);
        var builder = Mir.Builder.init(gpa);
        defer builder.deinit();
        builder.return_type = aggregate;
        builder.signature = signature;
        const input = try builder.addLocal(aggregate, .managed_address);
        builder.param_count = 1;
        const result_slot = try builder.addLocal(aggregate, .value);
        const first = try builder.addBlock();
        const join = if (shape == .direct) first else try builder.addBlock();
        const argument = try builder.addInst(first, .{
            .tag = .load,
            .result_role = .managed_address,
            .ty = aggregate,
            .span = Span.empty,
            .data = .{ .local = input },
        });
        const destination = if (shape == .managed_destination) argument else try builder.addInst(first, .{
            .tag = .addr_of,
            .result_role = .managed_address,
            .ty = aggregate,
            .span = Span.empty,
            .data = .{ .local = result_slot },
        });
        const call = try builder.addCall(first, .managed_address, aggregate, Span.empty, .at(0), &.{argument});
        if (shape != .direct) {
            _ = try builder.addInst(first, .{
                .tag = .copy_value,
                .ty = aggregate,
                .span = Span.empty,
                .data = .{ .binary = .{ .lhs = destination, .rhs = call } },
            });
            if (shape == .work_after_call) {
                _ = try builder.addInst(first, .{
                    .tag = .copy_value,
                    .ty = aggregate,
                    .span = Span.empty,
                    .data = .{ .binary = .{ .lhs = argument, .rhs = destination } },
                });
            }
            _ = try builder.setTerminator(first, .{
                .tag = .jump,
                .ty = .unit,
                .span = Span.empty,
                .data = .{ .target = join },
            });
        }
        const returned = if (shape == .copied_join) try builder.addInst(join, .{
            .tag = .addr_of,
            .result_role = .managed_address,
            .ty = aggregate,
            .span = Span.empty,
            .data = .{ .local = result_slot },
        }) else if (shape == .direct) call else destination;
        _ = try builder.setTerminator(join, .{
            .tag = .ret,
            .ty = .unit,
            .span = Span.empty,
            .data = .{ .unary = returned },
        });
        var mir = try builder.finish(first, .from(0));
        defer mir.deinit(gpa);
        var functions = [_]Mir{mir};
        var names = [_][]const u8{"tail"};
        const layouts = try gpa.alloc(types_mod.Layout, types.pool.items.len);
        defer gpa.free(layouts);
        @memset(layouts, .{ .size = 8, .alignment = 8 });
        layouts[aggregate.index()] = .{ .size = 16, .alignment = 8, .indirect = true };
        var representations = try mir_mod.deriveRepresentations(gpa, &types.view(), layouts);
        defer representations.deinit(gpa);
        const module: Module = .{
            .functions = &functions,
            .external = &.{false},
            .bytes = &.{},
            .names = &names,
            .origins = &.{},
            .types = types.view(),
            .representations = representations,
            .layouts = layouts,
            .entry = .none,
        };
        const source: source_mod.Source = .{ .path = "tail.lin", .text = "tail(input)" };
        var map = try SourceMap.init(gpa, &source);
        defer map.deinit();
        var output: std.Io.Writer.Allocating = .init(gpa);
        defer output.deinit();
        try emitFunction(gpa, &output.writer, &module, &mir, &map, source.path, .at(0), 0);
        const forwards = shape == .direct or shape == .copied_join;
        try testing.expectEqual(forwards, std.mem.indexOf(u8, output.written(), "func.call @lin.tail(%sret,") != null);
        try testing.expectEqual(!forwards, std.mem.indexOf(u8, output.written(), "%rs") != null);
        if (forwards) try testing.expect(std.mem.indexOf(u8, output.written(), "llvm.intr.memcpy") == null);
    }
}

test "allocator zero facts require the exact library producer" {
    const program_mod = @import("../syntax/program.zig");
    // A declaration whose types or conventions are not the runtime's is
    // refused before anything is emitted ([T-ExternRuntime]).
    const cases = [_]struct { module: []const u8 = "mem", declaration: []const u8, facts: bool = false, refused: bool = false }{
        .{ .declaration = "extern fn linea_alloc(size: UInt64, align: UInt64) -> UInt64", .facts = true },
        .{ .module = "text", .declaration = "extern fn linea_alloc(size: UInt64, align: UInt64) -> UInt64" },
        .{ .declaration = "fn linea_alloc(size: UInt64, align: UInt64) -> UInt64 { size + align }" },
        // A parameter's name is a label, so a renamed one is still the producer.
        .{ .declaration = "extern fn linea_alloc(bytes: UInt64, align: UInt64) -> UInt64", .facts = true },
        .{ .declaration = "extern fn linea_alloc(size: UInt32, align: UInt64) -> UInt64", .refused = true },
        .{ .declaration = "extern fn linea_alloc(sink size: UInt64, align: UInt64) -> UInt64", .refused = true },
        .{ .declaration = "extern fn linea_alloc(size: UInt64, align: UInt64 = 8) -> UInt64" },
        .{ .declaration = "extern fn linea_alloc(size: UInt64, align: UInt64) -> UInt32", .refused = true },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = if (case.facts)
            try std.fmt.allocPrint(gpa, "{s}\nextern fn linea_raw_load(at: UInt64, len: UInt64, i: UInt64) -> UInt64\n" ++
                "fn main() -> UInt8 {{ let at = linea_alloc(64, 8); UInt8(linea_raw_load(at, 64, 8)) }}", .{case.declaration})
        else
            try std.fmt.allocPrint(gpa, "{s}\nfn main() -> UInt8 {{ UInt8(linea_alloc(64, 8)) }}", .{case.declaration});
        const source: source_mod.Source = .{ .path = "allocator.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: @import("../support/interner.zig").Interner = .empty;
        const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
        const ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
        var modules = [_]program_mod.Module{.{
            .name = case.module,
            .dir = "std/mem",
            .files = &.{.from(0)},
            .decls = .{ .start = 0, .end = ast.declCount() },
            .imports = &.{},
            .library = true,
            .externs = true,
        }};
        const program: program_mod.Program = .{ .modules = &modules, .ast = ast };
        var resolved = try @import("../sema/resolve.zig").resolve(gpa, &program, &interner, &sink, .program);
        var typing = try @import("../sema/typecheck.zig").typecheck(gpa, &resolved.expanded, &resolved.resolution, &sink);
        if (case.refused) {
            try testing.expectEqual(@as(u32, 1), sink.error_count);
            try testing.expectEqual(@import("../diagnostics/diagnostic.zig").Code.t_extern_runtime, sink.list.items[0].code);
            continue;
        }
        var disposals = try @import("../ownership/check.zig").check(gpa, gpa, &resolved.expanded, &resolved.resolution, &typing, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        const module = (try @import("../mir/lower.zig").lowerProgram(gpa, &resolved.expanded, &resolved.resolution, &typing, &disposals, &sink, .program)).?;
        var table: FileTable = .{};
        _ = try table.add(gpa, source);
        var out: std.Io.Writer.Allocating = .init(gpa);
        const emitted = try emit(gpa, &out.writer, &module, &table, &sink);
        if (!emitted) {
            std.debug.print("\nallocator fixture: {s}\n", .{case.declaration});
            for (sink.list.items) |diagnostic| std.debug.print("{s}\n", .{diagnostic.message});
        }
        try testing.expect(emitted);
        try testing.expectEqual(@as(usize, if (case.facts) 8 else 0), std.mem.count(u8, out.written(), "func.call @llvm.assume("));
        try testing.expectEqual(@as(usize, if (case.facts) 9 else 0), std.mem.count(u8, out.written(), "func.call @llvm.is.constant.i1("));
        try testing.expect(std.mem.indexOf(u8, out.written(), "func.call @linea_alloc(") != null or !std.mem.startsWith(u8, case.declaration, "extern"));
        if (case.facts) {
            try testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "= llvm.getelementptr %ib"));
            try testing.expect(std.mem.indexOf(u8, out.written(), "getelementptr inbounds") == null);
            for ([_]FunctionId{ .at(@intCast(module.functions.len)), module.entry }) |invalid| {
                var bad = module;
                bad.zeroed_allocator = invalid;
                var rejected = Sink.init(gpa);
                try testing.expect(!try verify(gpa, &bad, &rejected));
                try testing.expect(rejected.hasErrors());
            }
            var bad = module;
            bad.types.callable_params = try gpa.dupe(types_mod.CallableParam, module.types.callable_params);
            const signature = bad.types.get(module.functionOf(module.zeroed_allocator).signature).callable;
            @constCast(bad.types.callable_params)[signature.first_param].convention = .sink;
            var rejected = Sink.init(gpa);
            try testing.expect(!try verify(gpa, &bad, &rejected));
            try testing.expect(rejected.hasErrors());
        }
    }
}
