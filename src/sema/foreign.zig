//! The C prototype an `extern` declaration implies, read from the types the
//! checker settled ([T-ExternPrototype]).
//!
//! Each position says what lowering passes there: a value crosses as
//! `types.foreignScalar` answers for its type, an `inout` parameter as the
//! address of its slot, a callback as the address of a C-callable entry, and
//! a callback's context as an address C hands back untouched. The driver
//! holds the C compiler's prototype of the symbol to this.

const std = @import("std");
const DeclId = @import("../syntax/node.zig").DeclId;
const types_mod = @import("types.zig");
const Typing = types_mod.Typing;
const TypeId = types_mod.TypeId;
const ForeignScalar = types_mod.ForeignScalar;

/// What one parameter or result of an `extern` crosses as.
pub const Value = union(enum) {
    /// The value itself.
    scalar: ForeignScalar,
    /// The address of a place holding a value of this scalar, which C may
    /// write: an `inout` parameter.
    address_of: ForeignScalar,
    /// The address of a callback's context, which C hands back to the
    /// callback without reading it: C's `void *`.
    context,
    /// The address of a function C calls.
    callback: *const Prototype,
};

pub const Prototype = struct {
    params: []const Value,
    /// Null where the function answers nothing.
    result: ?Value,
    /// Whether the declaration answers `ffi.Errno[R]`, of which C returns
    /// the `R` `result` describes.
    errno: bool = false,
};

/// The prototype the `extern` or `export` `decl` implies, allocated in `arena`, or null
/// where its signature names a type that does not cross, which [T-Extern] or
/// [T-ExternCallback] has already refused.
pub fn externPrototype(arena: std.mem.Allocator, typing: *const Typing, decl: DeclId) std.mem.Allocator.Error!?Prototype {
    const signature = switch (typing.get(typing.declSignature(decl))) {
        .callable => |callable| callable,
        else => return null,
    };
    const params = typing.callableParams(signature);
    const values = try arena.alloc(Value, params.len);
    for (params, values) |param, *value| {
        if (param.convention == .inout) {
            value.* = if (isContext(typing, params, param.ty))
                .context
            else
                .{ .address_of = types_mod.foreignScalar(typing, param.ty) orelse return null };
            continue;
        }
        switch (typing.get(param.ty)) {
            .callable => |callback| {
                const called = try arena.create(Prototype);
                called.* = try callbackPrototype(arena, typing, callback) orelse return null;
                value.* = .{ .callback = called };
            },
            else => value.* = .{ .scalar = types_mod.foreignScalar(typing, param.ty) orelse return null },
        }
    }
    // An `extern` answering `ffi.Errno[R]` returns `R` from C, and the runtime
    // reads `errno` after it.
    const errno = typing.raw_accesses.errnoValue(typing, signature.result);
    const answered = errno orelse signature.result;
    const result: ?Value = if (answered == .unit) null else .{ .scalar = types_mod.foreignScalar(typing, answered) orelse return null };
    return .{ .params = values, .result = result, .errno = errno != null };
}

/// Whether `ty` is the context a callback among `params` takes first,
/// `inout`, which the `extern` lends C to hand back on every call
/// ([T-ExternCallback]). Asked of a pool being built or of a finished typing.
pub fn isContext(pool: anytype, params: []const types_mod.CallableParam, ty: TypeId) bool {
    for (params) |param| switch (pool.get(param.ty)) {
        .callable => |callback| {
            const taken = pool.callableParams(callback);
            if (taken.len > 0 and taken[0].convention == .inout and taken[0].ty == ty) return true;
        },
        else => {},
    };
    return false;
}

/// The function C calls through a callback parameter: a leading `inout`
/// parameter is the context, and every other parameter and the result cross
/// by value.
fn callbackPrototype(arena: std.mem.Allocator, typing: *const Typing, callback: types_mod.CallableSignature) std.mem.Allocator.Error!?Prototype {
    const params = typing.callableParams(callback);
    const values = try arena.alloc(Value, params.len);
    for (params, values, 0..) |param, *value, i| {
        if (i == 0 and param.convention == .inout) {
            value.* = .context;
            continue;
        }
        if (param.convention == .inout) return null;
        value.* = .{ .scalar = types_mod.foreignScalar(typing, param.ty) orelse return null };
    }
    const result: ?Value = if (callback.result == .unit) null else .{ .scalar = types_mod.foreignScalar(typing, callback.result) orelse return null };
    return .{ .params = values, .result = result };
}
