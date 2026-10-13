const std = @import("std");

const Choices = @import("choices.zig").Choices;

pub const Ty = union(enum) {
    u8_,
    /// A signed byte. Narrow and signed, which is the one combination that
    /// makes a load sign-extend rather than zero-extend.
    i8_,
    /// The type an unannotated literal takes, and the width at which the
    /// checked arithmetic runs out of a wider machine type to check against.
    i64_,
    /// The one type held in the float register class, so a binding, a
    /// parameter and a return of it exercise every seam a `d` value crosses.
    f64_,
    bool_,
    enum_: u32,
    struct_: u32,
    /// An instantiation of the one generic structure a program declares,
    /// indexing the arguments it was instantiated at rather than holding one.
    ///
    /// A `Ty` that held a `Ty` would be recursive, and the generator has no
    /// use for `G[G[u8]]`: what it is here to exercise is substitution, which
    /// one level shows and two only repeat.
    held: u32,
    /// A fixed-size array of a scalar.
    ///
    /// One level, for the reason `held` is one: what an array has to exercise
    /// is the element travelling through layout, the checked access and the
    /// literal, and `[[u8; 2]; 3]` only repeats that. A scalar element for the
    /// same reason -- an array of a structure adds a stride the generator
    /// cannot predict, and predicting it is the compiler's job rather than the
    /// generator's.
    array: Array,

    pub const Scalar = enum { u8_, i8_, i64_, bool_ };

    pub const Array = struct {
        of: Scalar,
        count: u32,

        /// The element as a type in its own right.
        pub fn element(self: Array) Ty {
            return switch (self.of) {
                .u8_ => .u8_,
                .i8_ => .i8_,
                .i64_ => .i64_,
                .bool_ => .bool_,
            };
        }
    };

    /// Whether values of this type are whole numbers, which is what decides
    /// whether arithmetic and negation apply to it.
    pub fn isInt(self: Ty) bool {
        return switch (self) {
            .u8_, .i8_, .i64_ => true,
            // Not an integer: `%` and `%=` are refused over it, and the
            // productions this gates write both.
            .f64_ => false,
            .bool_, .enum_, .struct_, .held, .array => false,
        };
    }

    /// Whether it holds negative values, which is what makes negation
    /// meaningful and a narrow load sign-extend.
    pub fn isSigned(self: Ty) bool {
        return switch (self) {
            .i8_, .i64_ => true,
            // A float holds negative values, and its negation traps on
            // nothing at all.
            .f64_ => true,
            .u8_, .bool_, .enum_, .struct_, .held, .array => false,
        };
    }

    pub fn eql(a: Ty, b: Ty) bool {
        return switch (a) {
            .u8_ => b == .u8_,
            .i8_ => b == .i8_,
            .i64_ => b == .i64_,
            .f64_ => b == .f64_,
            .bool_ => b == .bool_,
            .enum_ => |i| b == .enum_ and b.enum_ == i,
            .struct_ => |i| b == .struct_ and b.struct_ == i,
            .held => |i| b == .held and b.held == i,
            .array => |arr| b == .array and b.array.of == arr.of and b.array.count == arr.count,
        };
    }
};

pub const Binding = struct {
    name: []const u8,
    ty: Ty,
    mutable: bool,
    /// How deeply nested the block declaring it is. A binding may only be
    /// shadowed from strictly further in: redeclaring a name in the block that
    /// already holds it is a different thing, and not this one.
    depth: u32,
    /// A loop counter, which the body may not assign: the decrement is what
    /// ends the loop, and a generated program that does not end is a suite
    /// that hangs rather than one that fails.
    frozen: bool,
};

/// The bindings a generated program has in scope, innermost last.
///
/// Split from the writer because it answers a different kind of question: what
/// a name may refer to here, rather than what to write next. Everything that
/// decides whether a program is well-formed by construction lives on this
/// side, and the writer above only asks.
pub const Scope = struct {
    gpa: std.mem.Allocator,
    items: std.ArrayList(Binding) = .empty,
    /// Scratch for `visible`, held here so a lookup does not allocate.
    seen: std.ArrayList(Binding) = .empty,

    pub fn deinit(self: *Scope) void {
        self.items.deinit(self.gpa);
        self.seen.deinit(self.gpa);
    }

    pub fn mark(self: *const Scope) usize {
        return self.items.items.len;
    }

    pub fn shrinkTo(self: *Scope, n: usize) void {
        self.items.shrinkRetainingCapacity(n);
    }

    pub fn clear(self: *Scope) void {
        self.items.clearRetainingCapacity();
    }

    pub fn push(self: *Scope, b: Binding) !void {
        try self.items.append(self.gpa, b);
    }

    pub fn pushAll(self: *Scope, bs: []const Binding) !void {
        try self.items.appendSlice(self.gpa, bs);
    }

    /// The bindings a name can reach here, innermost first.
    ///
    /// A binding declared later hides an outer one of the same name, which is
    /// what shadowing means. A generator that read its scope in declaration
    /// order would write the outer binding's name in a place where the name no
    /// longer denotes it, and produce a program of the wrong type or the wrong
    /// value depending on what the shadow happened to be.
    ///
    /// The slice is scratch and lives only until the next call.
    pub fn visible(self: *Scope) ![]const Binding {
        self.seen.clearRetainingCapacity();
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            const b = self.items.items[i];
            var hidden = false;
            for (self.seen.items) |s| {
                if (std.mem.eql(u8, s.name, b.name)) hidden = true;
            }
            if (!hidden) try self.seen.append(self.gpa, b);
        }
        return self.seen.items;
    }

    /// A name already in use further out, for a binding that shadows it.
    pub fn outerName(self: *Scope, choices: *Choices, at: u32) ?[]const u8 {
        // Shadowing is what makes a scope rule observable, and it has to
        // survive being asked for three times over to reach a binding hidden
        // by one that is itself hidden.
        if (!choices.odds(2)) return null;

        // Half the time the innermost candidate, which is what builds a
        // chain: shadowing a name already shadowing another is how a binding
        // ends up hidden by one that is itself hidden, and picking uniformly
        // makes that less likely the more names are in scope.
        var floor: u32 = 0;
        if (choices.odds(2)) {
            for (self.items.items) |b| {
                if (b.depth < at and b.depth > floor) floor = b.depth;
            }
        }

        var n: u32 = 0;
        for (self.items.items) |b| {
            if (b.depth < at and b.depth >= floor) n += 1;
        }
        if (n == 0) return null;

        var nth = choices.below(n);
        for (self.items.items) |b| {
            if (b.depth >= at or b.depth < floor) continue;
            if (nth == 0) return b.name;
            nth -= 1;
        }
        unreachable;
    }

    pub fn assignableCount(self: *Scope) !u32 {
        var n: u32 = 0;
        for (try self.visible()) |b| {
            if (b.mutable and !b.frozen) n += 1;
        }
        return n;
    }

    /// The whole binding rather than its name: what may be assigned to it is
    /// its own type, and a caller that knew only the name assumed one.
    pub fn nthAssignable(self: *Scope, want: u32) !Binding {
        var n: u32 = 0;
        for (try self.visible()) |b| {
            if (!b.mutable or b.frozen) continue;
            if (n == want) return b;
            n += 1;
        }
        unreachable;
    }
};
