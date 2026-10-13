//! What resolution mints, named where every pass that records something per
//! one of them can say so.
//!
//! The resolver declares these and the checker records a type for each, so
//! `Typing` holds one entry per binding. Held as `[]const TypeId` that needed
//! no name for its key, and so never asked where the key lived; a table whose
//! key is part of its type asks, and the answer was that `resolve.zig` imports
//! `types.zig` and the identifier sat on the wrong side of that.
//!
//! Below both, so both may name them and neither imports the other.

const std = @import("std");

/// A thing a name can refer to.
///
/// Today every binding is a `let`, but a parameter, a capture and a global will
/// all be bindings too, and none of those is a statement. Naming the handle for
/// what it means rather than where it currently lives is what keeps this API
/// from being renamed later.
pub const BindingId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: u32) BindingId {
        return @enumFromInt(i);
    }

    pub fn index(self: BindingId) u32 {
        return @intFromEnum(self);
    }
};

/// One lexical scope: the run of bindings declared in it, and the scope it
/// sits in.
///
/// The chain the resolver walks, kept rather than dropped. `visible` is that
/// chain while a body is being resolved and a scope's end truncates it; this
/// is the same nesting written down, so what a name could reach at a point is
/// read off what the pass that bound it decided.
pub const ScopeId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: u32) ScopeId {
        return @enumFromInt(i);
    }

    pub fn index(self: ScopeId) u32 {
        return @intFromEnum(self);
    }
};

/// One lambda expression's source identity.
pub const ClosureId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: u32) ClosureId {
        return @enumFromInt(i);
    }

    pub fn index(self: ClosureId) u32 {
        return @intFromEnum(self);
    }
};
