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

/// Whether `t` is a handle to an object C holds ([T-ExternHandle]): a newtype
/// that is not `copyable` and is either sealed in a module its root's
/// manifest grants `extern`, in any root, or a newtype over a handle. Only a
/// module trusted with C makes the innermost one from an address, and a newtype
/// around it names the same object, so each is a handle wherever it crosses an
/// `extern`. A copyable newtype is never one: anyone holding a copy names the
/// object, so nothing read through it can be kept alive by its place. Asked of
/// a pool being built or of a finished typing.
pub fn isForeignHandle(program: *const ExpandedProgram, ast: *const Ast, pool: anytype, t: TypeId) bool {
    var at = t;
    while (true) {
        if (at == .poison) return false;
        const newtype = switch (pool.get(at)) {
            .newtype => |newtype| newtype,
            else => return false,
        };
        const declared = pool.declOfType(at) orelse return false;
        if (ast.declOwnershipPolicy(declared) == .copyable) return false;
        if (ast.declVisibility(declared) == .opaque_ and program.get(program.moduleOf(declared)).externs) return true;
        at = newtype.base;
    }
}

/// Whether parameter `k` of the `extern` `d`, of type `t`, lends C a handle
/// it may change: a handle taken by a plain lend, without `read`. C receives
/// the handle by value, so the call lends the argument's place as `inout`
/// would, and only a place that may change can be lent so.
pub fn changesForeignHandle(program: *const ExpandedProgram, ast: *const Ast, pool: anytype, d: DeclId, k: usize, t: TypeId) bool {
    const param = ast.declParams(d)[k];
    if (param.convention != .read or ast.paramConventionToken(param) != .none) return false;
    return isForeignHandle(program, ast, pool, t);
}

pub const RawAccesses = struct {
    storage: DeclId = .none,
    buffer: DeclId = .none,
    slice: DeclId = .none,
    /// `mem.Carried`, the zero-sized field type that carries its argument's
    /// dependencies.
    carried: DeclId = .none,
    /// The `Dual` and `Step` that `session.Protocol` declares. Wherever `P`
    /// still awaits a type, `P.Dual.Dual` is read as `P` and `P.Dual.Step`
    /// as `P.Step.Dual`.
    protocol_dual: DeclId = .none,
    protocol_step: DeclId = .none,
    span: DeclId = .none,
    buffer_span: DeclId = .none,
    subspan: DeclId = .none,
    slice_place: DeclId = .none,
    /// `argument_span` and `environment_span` view text the process was
    /// started with; each lowers to the runtime's count, address and length
    /// for its source, which `processText` names.
    argument_span: DeclId = .none,
    argument_count: DeclId = .none,
    argument_at: DeclId = .none,
    argument_len: DeclId = .none,
    environment_span: DeclId = .none,
    environment_count: DeclId = .none,
    environment_at: DeclId = .none,
    environment_len: DeclId = .none,
    stride: DeclId = DeclId.none,
    take: DeclId = DeclId.none,
    put: DeclId = DeclId.none,
    place: DeclId = DeclId.none,
    store: DeclId = DeclId.none,
    load: DeclId = DeclId.none,
    store8: DeclId = DeclId.none,
    load8: DeclId = DeclId.none,
    /// `linea_float64_to_bits`, `linea_float64_from_bits` and their Float32
    /// forms: a float's bits reinterpreted as the unsigned integer of its
    /// width, and back. Each lowers to one bit cast.
    float_bits: [4]DeclId = @splat(DeclId.none),
    /// `mem.Closure`, the type every erased callable is kept behind, and
    /// `mem.ClosureEntry`, whose instance for a callable `S` is `S` with the
    /// stored callable's address and length appended.
    closure: DeclId = .none,
    closure_entry_type: DeclId = .none,
    /// `Closure.open_in` and `Closure.open`, whose callback must be callable
    /// as the closure's `S`. The second opens in the system allocator.
    closure_open_in: DeclId = .none,
    closure_open: DeclId = .none,
    /// The generated entry and release addresses for a callable type, and
    /// that type's size.
    closure_entry: DeclId = .none,
    closure_settle: DeclId = .none,
    closure_size: DeclId = .none,
    /// `task.prepare`, `task.prepare_in`, `task.start` and `task.start_in`,
    /// whose `body` argument crosses into a task ([O-Cross]), and the two
    /// `start` forms, which drop a body a failed start could not keep and so
    /// take only a Discardable one.
    task_prepare: DeclId = .none,
    task_prepare_in: DeclId = .none,
    task_start: DeclId = .none,
    task_start_in: DeclId = .none,
    /// `task.Unstarted`, the failure of a preparation, which holds the body.
    task_unstarted: DeclId = .none,
    /// `task.Slot.start`, the one function that may call a runtime symbol
    /// that starts a thread ([T-ThreadStart]): the handle it answers carries
    /// the body's dependencies until the thread is joined.
    task_slot_start: DeclId = .none,
    /// `ffi.Bytes`, `ffi.CText` and `ffi.CTextList`: copyable newtypes over a
    /// C address whose dependencies originate at the value, as a
    /// `mem.Slice`'s do, so a contract can tie one to what it views.
    foreign_views: [3]DeclId = .{ .none, .none, .none },
    /// `ffi.Errno`, which an `extern` answers to have `errno` read after the
    /// call, and the runtime's `linea_errno` that reads it.
    errno: DeclId = .none,
    errno_read: DeclId = .none,

    /// Identify private storage declarations before checking their generic signatures.
    pub fn init(program: *const ExpandedProgram, ast: *const Ast) RawAccesses {
        return .{
            .storage = program.libraryDeclIn("mem", "Storage") orelse .none,
            .buffer = program.libraryDeclIn("mem", "Buffer") orelse .none,
            .slice = program.libraryDeclIn("mem", "Slice") orelse .none,
            .carried = program.libraryDeclIn("mem", "Carried") orelse .none,
            .span = rawAccessDecl(program, ast, "slot_span", 4),
            .buffer_span = rawAccessDecl(program, ast, "buffer_span", 3),
            .subspan = rawAccessDecl(program, ast, "slice_subspan", 3),
            .slice_place = rawAccessDecl(program, ast, "slice_place", 2),
            .argument_span = rawAccessDecl(program, ast, "argument_span", 1),
            .environment_span = rawAccessDecl(program, ast, "environment_span", 1),
            .stride = rawAccessDecl(program, ast, "slot_stride", 1),
            .take = rawAccessDecl(program, ast, "slot_take", 4),
            .put = rawAccessDecl(program, ast, "slot_put", 5),
            .place = rawAccessDecl(program, ast, "slot_place", 5),
            .closure = program.libraryDeclIn("mem", "Closure") orelse .none,
            .closure_entry_type = program.libraryDeclIn("mem", "ClosureEntry") orelse .none,
            .closure_open_in = memberOf(program, ast, "mem", "Closure", "open_in"),
            .closure_open = memberOf(program, ast, "mem", "Closure", "open"),
            .closure_entry = rawAccessDecl(program, ast, "closure_entry", 1),
            .closure_settle = rawAccessDecl(program, ast, "closure_settle", 1),
            .closure_size = rawAccessDecl(program, ast, "closure_size", 1),
            .task_prepare = moduleFunction(program, ast, "task", "prepare"),
            .task_prepare_in = moduleFunction(program, ast, "task", "prepare_in"),
            .task_start = moduleFunction(program, ast, "task", "start"),
            .task_start_in = moduleFunction(program, ast, "task", "start_in"),
            .task_unstarted = program.libraryDeclIn("task", "Unstarted") orelse .none,
            .task_slot_start = memberOf(program, ast, "task", "Slot", "start"),
            .foreign_views = .{
                program.libraryDeclIn("ffi", "Bytes") orelse .none,
                program.libraryDeclIn("ffi", "CText") orelse .none,
                program.libraryDeclIn("ffi", "CTextList") orelse .none,
            },
            .errno = program.libraryDeclIn("ffi", "Errno") orelse .none,
        };
    }

    /// Scalar operations become intrinsics only after their complete signatures are checked.
    pub fn withCheckedScalars(self: RawAccesses, program: *const ExpandedProgram, ast: *const Ast, typing: *const Typing) RawAccesses {
        var checked = self;
        checked.argument_count = libraryExternDecl(program, ast, typing, "linea_arg_count");
        checked.argument_at = libraryExternDecl(program, ast, typing, "linea_arg_at");
        checked.argument_len = libraryExternDecl(program, ast, typing, "linea_arg_len");
        checked.environment_count = libraryExternDecl(program, ast, typing, "linea_env_count");
        checked.environment_at = libraryExternDecl(program, ast, typing, "linea_env_at");
        checked.environment_len = libraryExternDecl(program, ast, typing, "linea_env_len");
        checked.errno_read = libraryExternDecl(program, ast, typing, "linea_errno");
        checked.store = libraryExternDecl(program, ast, typing, "linea_raw_store");
        checked.load = libraryExternDecl(program, ast, typing, "linea_raw_load");
        checked.store8 = libraryExternDecl(program, ast, typing, "linea_raw_store8");
        checked.load8 = libraryExternDecl(program, ast, typing, "linea_raw_load8");
        for (float_bits_symbols, &checked.float_bits) |symbol, *d| d.* = libraryExternDecl(program, ast, typing, symbol);
        return checked;
    }

    /// The fields of `ffi.Errno`, in the order its declaration lists them:
    /// `value`, the `R` C returned, and `code`, the `errno` the runtime read
    /// after the call. The checker certifies the library's declaration
    /// against these names and positions, and lowering writes an `Errno`'s
    /// fields by them.
    pub const ErrnoField = enum(u32) { value, code };

    /// The fields of `mem.Closure`, in the order its declaration lists them.
    /// The checker certifies the library's declaration against these names
    /// and positions, and lowering reads a closure's fields by them.
    pub const ClosureField = enum(u32) { entry, settle, at, len, storage };

    /// The `R` of `ffi.Errno[R]` where `t` is one, asked of a pool being
    /// built or of a finished typing, or null where `t` is any other type.
    /// An `extern` answering `t` returns `R` from C.
    pub fn errnoValue(self: RawAccesses, pool: anytype, t: TypeId) ?TypeId {
        if (self.errno == .none) return null;
        const instance = pool.instanceOf(t) orelse return null;
        if (instance.decl != self.errno) return null;
        return pool.appliedTo(t)[0];
    }

    /// The signature C is called with for an `extern` of `signature`: the
    /// same parameters answering `R` where it answers `ffi.Errno[R]`, or null
    /// where it answers anything else. Discovery interns it before the pool
    /// closes and lowering finds it there.
    pub fn errnoSignature(self: RawAccesses, gpa: std.mem.Allocator, pool: *Typing.Builder, signature: TypeId) std.mem.Allocator.Error!?TypeId {
        const declared = pool.get(signature).callable;
        const value = self.errnoValue(pool, declared.result) orelse return null;
        const params = try gpa.dupe(types_mod.CallableParam, pool.callableParams(declared));
        defer gpa.free(params);
        const contracts = try gpa.dupe(types_mod.CallableContract, declared.contracts);
        defer gpa.free(contracts);
        return try pool.internCallable(params, value, contracts, declared.invocation);
    }

    /// The standard library's declarations of the float bit casts, by name
    /// before their signatures are checked, so the checker can hold each to
    /// the runtime table instead of to the foreign ABI, since no call to one
    /// reaches C.
    pub fn floatBitsCandidate(program: *const ExpandedProgram, ast: *const Ast, d: DeclId) bool {
        if (d == DeclId.none or !ast.declIsExtern(d)) return false;
        for (float_bits_symbols) |symbol| {
            if (program.libraryDeclIn("mem", symbol) == d) return true;
        }
        return false;
    }

    /// Whether `d` is a checked float bit cast.
    pub fn floatBits(self: RawAccesses, d: DeclId) bool {
        if (d == DeclId.none) return false;
        for (self.float_bits) |bits| if (bits == d) return true;
        return false;
    }

    /// Whether `d` opens a closure: its first type parameter is the callback,
    /// which must be callable as the closure's `S`.
    pub fn opensClosure(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.closure_open_in or d == self.closure_open);
    }

    pub fn contains(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and
            (d == self.store or d == self.load or d == self.store8 or d == self.load8 or self.floatBits(d) or self.typed(d));
    }
    /// Whether `d` prepares a joinable task (`prepare`, `prepare_in`).
    pub fn preparesTask(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.task_prepare or d == self.task_prepare_in);
    }

    /// Whether `d` prepares and starts a joinable task in one call (`start`, `start_in`).
    pub fn startsTask(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.task_start or d == self.task_start_in);
    }

    /// Whether `d` is one of the library functions whose `body` crosses into
    /// a task.
    pub fn crossesTask(self: RawAccesses, d: DeclId) bool {
        return self.preparesTask(d) or self.startsTask(d);
    }

    pub fn typed(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.stride or d == self.take or d == self.put or d == self.place or d == self.span or d == self.buffer_span or d == self.subspan or d == self.slice_place or self.processText(d) != null or self.erasure(d));
    }

    /// The runtime declarations a process-text span reads: how many entries
    /// its source holds, and one entry's address and length.
    pub const ProcessText = struct { count: DeclId, at: DeclId, len: DeclId };

    /// The runtime source `d` views when it is `argument_span` or
    /// `environment_span`, or null for any other declaration.
    pub fn processText(self: RawAccesses, d: DeclId) ?ProcessText {
        if (d == DeclId.none) return null;
        if (d == self.argument_span) return .{ .count = self.argument_count, .at = self.argument_at, .len = self.argument_len };
        if (d == self.environment_span) return .{ .count = self.environment_count, .at = self.environment_at, .len = self.environment_len };
        return null;
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
        const raw: RawAccesses = .{ .closure_entry = DeclId.at(1), .closure_settle = DeclId.at(2), .closure_size = DeclId.at(3), .closure_open_in = DeclId.at(4) };
        try std.testing.expect(raw.erasure(DeclId.at(1)) and raw.erasure(DeclId.at(2)) and raw.erasure(DeclId.at(3)));
        try std.testing.expect(!raw.erasure(DeclId.at(4)) and !raw.erasure(DeclId.none));
        // They are typed storage primitives, so a program cannot reach them.
        try std.testing.expect(raw.typed(DeclId.at(3)) and raw.contains(DeclId.at(1)));
    }
};

/// The member `member` of an implementation whose head names `owner`, the
/// library's type of that name in `module_name`: `Closure.open_in` and
/// `Closure.open` in `mem`, or `Slot.start` in `task`. Other types in a module
/// declare members of the same names, so the name alone does not identify it.
pub fn memberOf(program: *const ExpandedProgram, ast: *const Ast, module_name: []const u8, owner: []const u8, member: []const u8) DeclId {
    const declared = program.libraryDeclIn(module_name, owner) orelse return .none;
    for (program.declsOf(program.moduleOf(declared))) |d| {
        const name = ast.declName(d);
        const head = ast.memberOwner(d);
        if (name == .none or head == .none) continue;
        if (std.mem.eql(u8, ast.tokenText(name), member) and std.mem.eql(u8, ast.tokenText(head), owner)) return d;
    }
    return .none;
}

/// The library function `name` of `module_name` that is no type's member.
fn moduleFunction(program: *const ExpandedProgram, ast: *const Ast, module_name: []const u8, name: []const u8) DeclId {
    const declared = program.libraryDeclIn(module_name, name) orelse return .none;
    for (program.declsOf(program.moduleOf(declared))) |d| {
        const named = ast.declName(d);
        if (named == .none or ast.memberOwner(d) != .none or ast.declTag(d) != .function) continue;
        if (std.mem.eql(u8, ast.tokenText(named), name)) return d;
    }
    return .none;
}

/// A private library extern by its name and its number of parameters. The
/// checker holds each to its whole signature, so a parameter's name decides
/// nothing: a name is a label.
const float_bits_symbols = [_][]const u8{ "linea_float64_to_bits", "linea_float64_from_bits", "linea_float32_to_bits", "linea_float32_from_bits" };

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
        if (want.scalar == .callback) {
            // The function type must be the one C calls through the address:
            // the same scalars, each by value, and the same result.
            const shape = want.callback orelse return false;
            if (param.convention != .read) return false;
            const called = switch (typing.get(param.ty)) {
                .callable => |callable| callable,
                else => return false,
            };
            if (called.result != runtimeScalarType(shape.result)) return false;
            const taken = typing.callableParams(called);
            if (taken.len != shape.parameters.len) return false;
            for (taken, shape.parameters) |inner, scalar| {
                if (inner.ty != runtimeScalarType(scalar) or inner.convention != .read) return false;
            }
            continue;
        }
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
        .u32 => .u32,
        .i64 => .i64,
        .u64 => .u64,
        .f32 => .f32,
        .f64 => .f64,
        .unit => .unit,
        // Only the symbols the compiler owns take a pointer, and none of them
        // is declared in Linea. A callback is a callable type of its own
        // declaration, which `matchesRuntime` reads before asking here.
        .ptr, .callback => unreachable,
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
