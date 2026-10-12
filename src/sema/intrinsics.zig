const std = @import("std");
const DeclId = @import("../syntax/node.zig").DeclId;
const Ast = @import("../syntax/ast.zig").Ast;
const types_mod = @import("types.zig");
const Typing = types_mod.Typing;
const TypeId = types_mod.TypeId;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const FloatMathOperation = @import("../support/float_math.zig").Operation;
const runtime_symbols = @import("../support/runtime_symbols.zig");

pub const FloatMath = struct {
    declarations: [FloatMathOperation.count]DeclId = @splat(.none),

    /// Candidates retain malformed trusted declarations so checking diagnoses
    /// signature drift even when the written types fit the ordinary integer ABI.
    pub fn candidates(program: *const ExpandedProgram, ast: *const Ast) FloatMath {
        var result: FloatMath = .{};
        for (std.enums.values(FloatMathOperation), 0..) |operation, i| {
            const d = program.libraryDeclIn("scalar", operation.symbol()) orelse continue;
            if (ast.declIsExtern(d)) result.declarations[i] = d;
        }
        return result;
    }

    pub fn checked(self: FloatMath, ast: *const Ast, typing: *const Typing) FloatMath {
        const parameters = [_]TypeId{ .f64, .f64 };
        var result: FloatMath = .{};
        for (self.declarations, std.enums.values(FloatMathOperation), 0..) |d, operation, i| {
            if (d == .none or ast.declVisibility(d) != .private or ast.declIsExport(d) or
                ast.declContracts(d).len != 0 or ast.declWherePredicates(d).len != 0) continue;
            if (matchesExternSignature(ast, typing, d, parameters[0..operation.arity()], .f64))
                result.declarations[i] = d;
        }
        return result;
    }

    pub fn operationOf(self: FloatMath, d: DeclId) ?FloatMathOperation {
        if (d == .none) return null;
        for (self.declarations, std.enums.values(FloatMathOperation)) |declaration, operation| {
            if (declaration == d) return operation;
        }
        return null;
    }
};

pub const RawAccesses = struct {
    storage: DeclId = .none,
    buffer: DeclId = .none,
    slice: DeclId = .none,
    span: DeclId = .none,
    buffer_span: DeclId = .none,
    subspan: DeclId = .none,
    slice_place: DeclId = .none,
    argument_span: DeclId = .none,
    argument_count: DeclId = .none,
    argument_at: DeclId = .none,
    argument_len: DeclId = .none,
    stride: DeclId = DeclId.none,
    take: DeclId = DeclId.none,
    put: DeclId = DeclId.none,
    place: DeclId = DeclId.none,
    store: DeclId = DeclId.none,
    load: DeclId = DeclId.none,
    store8: DeclId = DeclId.none,
    load8: DeclId = DeclId.none,
    /// `mem.Closure`, the type every erased callable is kept behind, and
    /// `mem.ClosureEntry`, whose instance for a callable `S` is `S` with the
    /// stored callable's address and length appended.
    closure: DeclId = .none,
    closure_entry_type: DeclId = .none,
    /// `Closure.open_in` and `Closure.open`, whose callback must be callable
    /// as the closure's `S`. The second opens in the system allocator.
    closure_open: DeclId = .none,
    closure_open_system: DeclId = .none,
    /// The generated entry and release addresses for a callable type, and
    /// that type's size.
    closure_entry: DeclId = .none,
    closure_settle: DeclId = .none,
    closure_size: DeclId = .none,

    /// Identify private storage declarations before checking their generic signatures.
    pub fn init(program: *const ExpandedProgram, ast: *const Ast) RawAccesses {
        return .{
            .storage = program.libraryDeclIn("mem", "Storage") orelse .none,
            .buffer = program.libraryDeclIn("mem", "Buffer") orelse .none,
            .slice = program.libraryDeclIn("mem", "Slice") orelse .none,
            .span = rawAccessDecl(program, ast, "slot_span", 4),
            .buffer_span = rawAccessDecl(program, ast, "buffer_span", 3),
            .subspan = rawAccessDecl(program, ast, "slice_subspan", 3),
            .slice_place = rawAccessDecl(program, ast, "slice_place", 2),
            .argument_span = rawAccessDecl(program, ast, "argument_span", 1),
            .stride = rawAccessDecl(program, ast, "slot_stride", 1),
            .take = rawAccessDecl(program, ast, "slot_take", 4),
            .put = rawAccessDecl(program, ast, "slot_put", 5),
            .place = rawAccessDecl(program, ast, "slot_place", 5),
            .closure = program.libraryDeclIn("mem", "Closure") orelse .none,
            .closure_entry_type = program.libraryDeclIn("mem", "ClosureEntry") orelse .none,
            .closure_open = closureOpenDecl(program, ast, "open_in"),
            .closure_open_system = closureOpenDecl(program, ast, "open"),
            .closure_entry = rawAccessDecl(program, ast, "closure_entry", 1),
            .closure_settle = rawAccessDecl(program, ast, "closure_settle", 1),
            .closure_size = rawAccessDecl(program, ast, "closure_size", 1),
        };
    }

    /// Scalar operations become intrinsics only after their complete signatures are checked.
    pub fn withCheckedScalars(self: RawAccesses, program: *const ExpandedProgram, ast: *const Ast, typing: *const Typing) RawAccesses {
        var checked = self;
        checked.argument_count = libraryExternDecl(program, ast, typing, "linea_arg_count");
        checked.argument_at = libraryExternDecl(program, ast, typing, "linea_arg_at");
        checked.argument_len = libraryExternDecl(program, ast, typing, "linea_arg_len");
        checked.store = libraryExternDecl(program, ast, typing, "linea_raw_store");
        checked.load = libraryExternDecl(program, ast, typing, "linea_raw_load");
        checked.store8 = libraryExternDecl(program, ast, typing, "linea_raw_store8");
        checked.load8 = libraryExternDecl(program, ast, typing, "linea_raw_load8");
        return checked;
    }

    /// Whether `d` opens a closure: its first type parameter is the callback,
    /// which must be callable as the closure's `S`.
    pub fn opensClosure(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.closure_open or d == self.closure_open_system);
    }

    pub fn contains(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and
            (d == self.store or d == self.load or d == self.store8 or d == self.load8 or self.typed(d));
    }
    pub fn typed(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.stride or d == self.take or d == self.put or d == self.place or d == self.span or d == self.buffer_span or d == self.subspan or d == self.slice_place or d == self.argument_span or self.erasure(d));
    }

    /// Whether `d` is one of the declarations lowering replaces with what it
    /// generates for an erased closure's callable.
    pub fn erasure(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.closure_entry or d == self.closure_settle or d == self.closure_size);
    }

    /// The body a call to `closure_entry[S, F]` or `closure_settle[F]` takes
    /// the address of, from the type arguments the call settled; null for
    /// any other declaration. Discovery interns it and lowering finds it by
    /// this one reading of the intrinsics' parameter order.
    pub fn erasedBody(self: RawAccesses, d: DeclId, settled: []const TypeId) ?types_mod.BodyOrigin {
        if (d == DeclId.none) return null;
        if (d == self.closure_entry) return .{ .erased_entry = .{ .callable = settled[1], .signature = settled[0] } };
        if (d == self.closure_settle) return .{ .erased_settle = settled[0] };
        return null;
    }

    test "an erasure intrinsic names the body it generates" {
        const raw: RawAccesses = .{ .closure_entry = DeclId.at(1), .closure_settle = DeclId.at(2), .closure_size = DeclId.at(3) };
        const entry = raw.erasedBody(DeclId.at(1), &.{ .u8, .u16 }).?;
        try std.testing.expectEqual(TypeId.u16, entry.erased_entry.callable);
        try std.testing.expectEqual(TypeId.u8, entry.erased_entry.signature);
        try std.testing.expectEqual(TypeId.u32, raw.erasedBody(DeclId.at(2), &.{.u32}).?.erased_settle);
        try std.testing.expect(raw.erasedBody(DeclId.at(3), &.{.u8}) == null);
    }

    test "the erasure intrinsics are the closure entry, release and size" {
        const raw: RawAccesses = .{ .closure_entry = DeclId.at(1), .closure_settle = DeclId.at(2), .closure_size = DeclId.at(3), .closure_open = DeclId.at(4) };
        try std.testing.expect(raw.erasure(DeclId.at(1)) and raw.erasure(DeclId.at(2)) and raw.erasure(DeclId.at(3)));
        try std.testing.expect(!raw.erasure(DeclId.at(4)) and !raw.erasure(DeclId.none));
        // They are typed storage primitives, so a program cannot reach them.
        try std.testing.expect(raw.typed(DeclId.at(3)) and raw.contains(DeclId.at(1)));
    }
};

/// `Closure.open_in` or `Closure.open` in the library's `mem`: the member of
/// that name of an implementation whose head names `Closure`. Other types in
/// `mem` declare an `open` of their own, so the name alone does not identify it.
fn closureOpenDecl(program: *const ExpandedProgram, ast: *const Ast, member: []const u8) DeclId {
    const closure = program.libraryDeclIn("mem", "Closure") orelse return .none;
    const module = program.moduleOf(closure);
    for (program.declsOf(module)) |d| {
        const name = ast.declName(d);
        const owner = ast.declOwner(d);
        if (name == .none or owner == .none) continue;
        if (std.mem.eql(u8, ast.tokenText(name), member) and std.mem.eql(u8, ast.tokenText(owner), "Closure")) return d;
    }
    return .none;
}

/// A private library extern by its name and its number of parameters. The
/// checker holds each to its whole signature, so a parameter's name decides
/// nothing: a name is a label.
fn rawAccessDecl(program: *const ExpandedProgram, ast: *const Ast, name: []const u8, arity: usize) DeclId {
    const d = program.libraryDeclIn("mem", name) orelse return DeclId.none;
    if (!ast.declIsExtern(d) or ast.declParams(d).len != arity) return DeclId.none;
    return d;
}

/// The standard library's `mem` declaration of the runtime symbol `symbol`,
/// where its checked signature is the one the runtime table gives it. The
/// checker reports one that is not ([T-ExternRuntime]), so a mismatched
/// declaration receives no intrinsic fact and is never left to the linker.
pub fn libraryExternDecl(program: *const ExpandedProgram, ast: *const Ast, typing: *const Typing, symbol: []const u8) DeclId {
    const expected = runtime_symbols.signatureOf(symbol) orelse return .none;
    const d = program.libraryDeclIn("mem", symbol) orelse return DeclId.none;
    if (!ast.declIsExtern(d) or ast.declTypeParams(d).len != 0) return .none;
    const signature = switch (typing.get(typing.declSignature(d))) {
        .callable => |signature| signature,
        else => return .none,
    };
    if (signature.invocation != .read or signature.contracts.len != 0) return .none;
    for (ast.declParams(d)) |written| if (written.default != .none) return .none;
    return if (matchesRuntime(typing, signature, expected.*)) d else .none;
}

/// Whether a checked `extern` signature is the one the runtime gives: its
/// parameters' types and conventions, and its result, by position.
pub fn matchesRuntime(typing: *const Typing, declared: types_mod.CallableSignature, expected: runtime_symbols.Signature) bool {
    if (declared.result != runtimeScalarType(expected.result)) return false;
    const params = typing.callableParams(declared);
    if (params.len != expected.parameters.len) return false;
    for (params, expected.parameters) |param, want| {
        if (param.ty != runtimeScalarType(want.scalar)) return false;
        const convention: @TypeOf(param.convention) = switch (want.passing) {
            .read => .read,
            .inout => .inout,
        };
        if (param.convention != convention) return false;
    }
    return true;
}

test matchesRuntime {
    var b = try Typing.Builder.init(std.testing.allocator);
    defer b.deinit();
    const load = try b.internCallable(&.{
        .{ .spelling = "", .convention = .read, .ty = .u64, .default = .absent },
        .{ .spelling = "", .convention = .read, .ty = .u64, .default = .absent },
        .{ .spelling = "", .convention = .read, .ty = .u64, .default = .absent },
    }, .u64, &.{}, .read);
    const view = b.view();
    try std.testing.expect(matchesRuntime(&view, view.get(load).callable, runtime_symbols.signatureOf("linea_raw_load").?.*));
    try std.testing.expect(!matchesRuntime(&view, view.get(load).callable, runtime_symbols.signatureOf("linea_raw_load8").?.*));
}

/// The type a runtime signature's scalar is in Linea.
pub fn runtimeScalarType(scalar: runtime_symbols.Scalar) TypeId {
    return switch (scalar) {
        .u8 => .u8,
        .i32 => .i32,
        .i64 => .i64,
        .u64 => .u64,
        .f64 => .f64,
        .unit => .unit,
        // Only the symbols the compiler owns take a pointer, and none of them
        // is declared in Linea.
        .ptr => unreachable,
    };
}

test runtimeScalarType {
    try std.testing.expectEqual(TypeId.i32, runtimeScalarType(.i32));
    try std.testing.expectEqual(TypeId.unit, runtimeScalarType(.unit));
}

/// Whether a scalar-math declaration takes `params` read by value, with no
/// default, and answers `result`.
fn matchesExternSignature(ast: *const Ast, typing: *const Typing, d: DeclId, params: []const TypeId, result: TypeId) bool {
    if (!ast.declIsExtern(d) or ast.declTypeParams(d).len != 0) return false;
    const signature = switch (typing.get(typing.declSignature(d))) {
        .callable => |signature| signature,
        else => return false,
    };
    if (signature.result != result or signature.invocation != .read or signature.contracts.len != 0) return false;
    const declared = typing.callableParams(signature);
    if (declared.len != params.len) return false;
    for (declared, params, ast.declParams(d)) |param, want, written| {
        if (param.ty != want or param.convention != .read or param.default != .absent or written.default != .none) return false;
    }
    return true;
}

// Makes every test build compile the tests `RawAccesses` holds, including a
// build filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = RawAccesses;
}
