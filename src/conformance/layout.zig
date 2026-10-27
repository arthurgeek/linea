const std = @import("std");
const testing = std.testing;

const types_mod = @import("../sema/types.zig");
const Typing = types_mod.Typing;
const TypeId = types_mod.TypeId;
const Layout = types_mod.Layout;

/// A second reading of the layout rule, written in C and performed by `cc`.
///
/// Every check the emitted-code verifier makes is relative to `module.layouts`,
/// so a wrong size there is agreed on by the table, the emitter, the verifier
/// and the running program alike. The corpus cannot reach it either: a rewrite
/// is a program compared against itself through one compiler, and a
/// systematically wrong offset moves on both sides. What contradicts a computed
/// fact is a second source for it.
///
/// `cc` is that source. It is already required to run the suite, it was written
/// by people who never read this compiler, and it decides nothing here -- it
/// can only disagree, and a disagreement stops the suite rather than reaching a
/// program.
///
/// **The C is derived from what a type *is*, never from what the table says it
/// measures.** A member's C type comes from the member's Linea type; the table
/// appears on the other side of the comparison and nowhere else. The moment a
/// size, an alignment or an offset flows from the table into the emitted C,
/// `cc` is confirming a number it was handed and the property passes while
/// checking nothing.
///
/// The comparison itself is `_Static_assert`, so `cc` performs the diff and a
/// disagreement is a compile error naming the type and the member. Nothing here
/// reads `cc`'s answer back and turns it into a layout.
pub const Oracle = struct {
    /// The C source to compile. Empty where the module holds no aggregate.
    text: []const u8,
    /// How many aggregate types were compared.
    ///
    /// A run in which the oracle compared none proved nothing and looks exactly
    /// like a clean one, so the caller holds this to a floor.
    compared: u32,

    pub fn deinit(self: Oracle, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
    }
};

/// Whether a type contributes no bytes, answered from its structure.
///
/// A part of width zero contributes no C member: ISO C has no zero-size member
/// and no empty structure, so there is no text that stands for one. Linea's own
/// arithmetic gives the rest -- `alignUp(at, 1) + 0 == at`, so such a part never
/// moves what follows it and never raises the enclosing alignment.
///
/// Read from the type and never from the table, which is the one place the
/// transcription is most tempting: a member's size looked up in `layouts` would
/// make `cc` confirm a number this property handed it.
fn isZeroWidth(typing: *const Typing, t: TypeId) bool {
    // An instantiation with its parts unwritten holds a parameter, and has
    // no parts to read: it is no width the oracle can state.
    if (typing.isShell(t)) return false;
    return switch (typing.get(t)) {
        .unit, .never => true,
        .newtype => |n| isZeroWidth(typing, n.base),
        .array => |a| a.count == 0 or isZeroWidth(typing, a.element),
        .struct_ => {
            for (0..typing.fieldCount(t)) |i| {
                if (!isZeroWidth(typing, typing.fieldType(t, @intCast(i)))) return false;
            }
            return true;
        },
        // A tag is a full word whatever its variants carry, so an enum is never
        // zero-width.
        .enum_ => false,
        else => false,
    };
}

/// Whether this type is one the oracle emits a declaration for.
fn isAggregate(typing: *const Typing, t: TypeId) bool {
    return switch (typing.get(t)) {
        .struct_, .enum_ => true,
        else => false,
    };
}

/// Named rather than inferred: `emit` and `needs` are mutually recursive,
/// and two inferred error sets that each name the other cannot be settled.
const Error = std.mem.Allocator.Error || std.Io.Writer.Error;

fn typeName(buf: []u8, namespace: usize, at: usize) []const u8 {
    return std.fmt.bufPrint(buf, "struct o{d}_t{d}", .{ namespace, at }) catch unreachable;
}

test "layout oracle type names include their case namespace" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("struct o7_t12", typeName(&buf, 7, 12));
    try testing.expectEqualStrings("struct o9_t12", typeName(&buf, 9, 12));
}

/// What a member could be said as: its C type, nothing because it occupies no
/// bytes, or nothing because this file has no form for it.
const Spelled = union(enum) { text: []const u8, zero_width, cannot };

const Emitter = struct {
    gpa: std.mem.Allocator,
    typing: *const Typing,
    layouts: []const Layout,
    out: *std.Io.Writer,
    done: []bool,
    namespace: usize,
    compared: u32 = 0,
    skipped: u32 = 0,

    /// What a member of this type is spelled as in C, or why it cannot be.
    ///
    /// Exhaustive over every kind a type can be, with no `else`: a kind added
    /// to the language answers this before the build succeeds. A permissive
    /// default here would drop the member from the emitted structure and then
    /// assert the enclosing size against a declaration missing a field, which
    /// reports a Linea defect that is an omission in this file.
    fn spell(self: *Emitter, t: TypeId, buf: []u8) Error!Spelled {
        return switch (self.typing.get(t)) {
            .integer => |i| switch (i.bits) {
                8 => .{ .text = if (i.signed) "int8_t" else "uint8_t" },
                16 => .{ .text = if (i.signed) "int16_t" else "uint16_t" },
                32 => .{ .text = if (i.signed) "int32_t" else "uint32_t" },
                64 => .{ .text = if (i.signed) "int64_t" else "uint64_t" },
                else => .cannot,
            },
            // One byte, one alignment, which `unsigned char` has on every
            // target. `_Bool` is not used: its width is implementation-defined
            // where this is not.
            .boolean => .{ .text = "unsigned char" },
            .float => |info| .{ .text = if (info.bits == 32) "float" else "double" },
            .borrow => .{ .text = "const void *" },
            // A newtype represents nothing of its own, so it has nothing for a
            // C declaration to say that its base does not.
            .newtype => |n| self.spell(n.base, buf),
            .struct_, .enum_ => blk: {
                const named = typeName(buf, self.namespace, @intFromEnum(t));
                break :blk .{ .text = named };
            },
            .unit, .never, .closure => .zero_width,
            // C spells an array's count at the member rather than in its type,
            // so an array is written by `member` and is not a thing this can
            // name. One nested inside another would need a declarator this
            // does not build, and is declined rather than guessed at.
            .array => .cannot,
            // Neither reaches a layout: a parameter never reaches the backend,
            // and poison never reaches code generation. Either arriving here
            // is a defect upstream rather than a type to spell.
            .parameter, .poison, .open_integer, .open_float, .open_type, .callable => .cannot,
        };
    }

    /// Writes one member, answering with what it was able to say.
    fn member(self: *Emitter, t: TypeId, index: u32) Error!Spelled {
        if (isZeroWidth(self.typing, t)) return .zero_width;

        var buf: [64]u8 = undefined;
        switch (self.typing.get(t)) {
            .array => |a| {
                var inner: [64]u8 = undefined;
                const elem = try self.spell(a.element, &inner);
                switch (elem) {
                    .text => |name| {
                        try self.out.print("  {s} m{d}[{d}];\n", .{ name, index, a.count });
                        return .{ .text = name };
                    },
                    // An array of a type with no C spelling, and an array whose
                    // element is itself zero-width -- neither has a member to
                    // write, and the second is not zero-width overall only
                    // because `isZeroWidth` already answered that above.
                    else => return .cannot,
                }
            },
            else => {
                const spelled = try self.spell(t, &buf);
                switch (spelled) {
                    .text => |name| {
                        try self.out.print("  {s} m{d};\n", .{ name, index });
                        return .{ .text = name };
                    },
                    else => return spelled,
                }
            },
        }
    }

    /// Whether every part of this type has a C form, asked before anything is
    /// written.
    ///
    /// All or nothing: a type one of whose parts cannot be spelled is left out
    /// entirely rather than emitted without it. A partial declaration would be
    /// measured against the whole type's entry and would report a disagreement
    /// that is this file's omission.
    fn expressible(self: *Emitter, t: TypeId) bool {
        switch (self.typing.get(t)) {
            .struct_ => {
                for (0..self.typing.fieldCount(t)) |i| {
                    if (!self.partExpressible(self.typing.fieldType(t, @intCast(i)))) return false;
                }
                return true;
            },
            .enum_ => {
                for (0..self.typing.variantCount(t)) |v| {
                    for (0..self.typing.variantFieldCount(t, @intCast(v))) |f| {
                        if (!self.partExpressible(self.typing.variantFieldType(t, @intCast(v), @intCast(f)))) return false;
                    }
                }
                return true;
            },
            else => return false,
        }
    }

    fn partExpressible(self: *Emitter, t: TypeId) bool {
        // An instantiation with its parts unwritten holds a parameter, which
        // has no C form.
        if (self.typing.isShell(t)) return false;
        if (isZeroWidth(self.typing, t)) return true;
        return switch (self.typing.get(t)) {
            .integer => |i| i.bits == 8 or i.bits == 16 or i.bits == 32 or i.bits == 64,
            .boolean, .float, .borrow => true,
            .newtype => |n| self.partExpressible(n.base),
            .struct_, .enum_ => self.expressible(t),
            .array => |a| switch (self.typing.get(a.element)) {
                // The element is written as the member's type, so an array of
                // arrays would need a declarator this does not build.
                .array => false,
                else => self.partExpressible(a.element),
            },
            .unit, .never, .parameter, .poison, .open_integer, .open_float, .open_type, .callable, .closure => false,
        };
    }

    /// Emits this type's declaration and every declaration it needs first.
    ///
    /// Depth-first so a member's type is complete before the member is written,
    /// which C requires and which the pool's own ordering does not promise.
    fn emit(self: *Emitter, t: TypeId) Error!void {
        const at = @intFromEnum(t);
        if (at >= self.done.len or self.done[at]) return;
        self.done[at] = true;
        if (!self.expressible(t)) {
            self.skipped += 1;
            return;
        }
        // A type of no width has no C form at all: there is no empty structure
        // in ISO C, so any declaration standing for one measures at least a
        // byte and would contradict a table that correctly says zero. The rule
        // is the same one a zero-width member is left out under, read of the
        // whole type rather than of a part.
        //
        // What this gives up is stated rather than hidden: such a type's size
        // is not diffed. It is also the one size the rule fixes outright,
        // where every other is arithmetic over parts.
        if (isZeroWidth(self.typing, t)) {
            self.skipped += 1;
            return;
        }

        switch (self.typing.get(t)) {
            .struct_ => {
                for (0..self.typing.fieldCount(t)) |i| {
                    try self.needs(self.typing.fieldType(t, @intCast(i)));
                }
                var name_buf: [64]u8 = undefined;
                try self.out.print("{s} {{\n", .{typeName(&name_buf, self.namespace, at)});
                for (0..self.typing.fieldCount(t)) |i| {
                    _ = try self.member(self.typing.fieldType(t, @intCast(i)), @intCast(i));
                }
                try self.out.writeAll("};\n");
                try self.assertMeasures(at);
                try self.assertOffsets(t);
            },
            .enum_ => {
                for (0..self.typing.variantCount(t)) |v| {
                    for (0..self.typing.variantFieldCount(t, @intCast(v))) |f| {
                        try self.needs(self.typing.variantFieldType(t, @intCast(v), @intCast(f)));
                    }
                }

                // The tag is a full word and every variant's run is overlaid
                // after it. The correspondence holds only *because* the tag is
                // a word: a union's alignment is at most eight, so the payload
                // begins at eight on both sides. A narrower tag stops this
                // form corresponding, and the oracle is re-derived rather than
                // adjusted.
                var name_buf: [64]u8 = undefined;
                try self.out.print("{s} {{\n  uint64_t tag;\n", .{typeName(&name_buf, self.namespace, at)});

                var arms: u32 = 0;
                var payload: std.Io.Writer.Allocating = .init(self.gpa);
                defer payload.deinit();
                for (0..self.typing.variantCount(t)) |vi| {
                    var carried: u32 = 0;
                    var arm: std.Io.Writer.Allocating = .init(self.gpa);
                    defer arm.deinit();
                    const held = self.out;
                    self.out = &arm.writer;
                    for (0..self.typing.variantFieldCount(t, @intCast(vi))) |i| {
                        const field_type = self.typing.variantFieldType(t, @intCast(vi), @intCast(i));
                        if ((try self.member(field_type, @intCast(i))) == .text) carried += 1;
                    }
                    self.out = held;
                    // A variant carrying nothing, or carrying only zero-width
                    // parts, contributes no union arm: there is no empty
                    // structure in C, and an arm of no bytes would widen
                    // nothing anyway.
                    if (carried == 0) continue;
                    try payload.writer.print("    struct {{\n{s}    }} v{d};\n", .{ arm.written(), vi });
                    arms += 1;
                }

                // No arm left means the type is a tag alone, which is what
                // `Maybe[()]` and every payloadless enum are.
                if (arms > 0) {
                    try self.out.print("  union {{\n{s}  }} payload;\n", .{payload.written()});
                }
                try self.out.writeAll("};\n");
                try self.assertMeasures(at);
            },
            else => {},
        }
    }

    /// Emits whatever a member's type needs, without emitting the member's own
    /// declaration where it is not an aggregate.
    fn needs(self: *Emitter, t: TypeId) Error!void {
        switch (self.typing.get(t)) {
            .struct_, .enum_ => try self.emit(t),
            .newtype => |n| try self.needs(n.base),
            .array => |a| try self.needs(a.element),
            else => {},
        }
    }

    /// The one place the table is read, and it is the other side of the
    /// comparison rather than an input to what was emitted.
    fn assertMeasures(self: *Emitter, at: usize) Error!void {
        if (at >= self.layouts.len) return;
        const layout = self.layouts[at];
        // A width the rule stopped at is not the type's own width, so there is
        // nothing for C to agree or disagree with.
        if (layout.too_wide) return;

        var name_buf: [64]u8 = undefined;
        const name = typeName(&name_buf, self.namespace, at);
        try self.out.print("_Static_assert(sizeof({s}) == {d}, \"size of o{d}_t{d}\");\n", .{
            name, layout.size, self.namespace, at,
        });
        try self.out.print("_Static_assert(_Alignof({s}) == {d}, \"alignment of o{d}_t{d}\");\n", .{
            name, layout.alignment, self.namespace, at,
        });
        self.compared += 1;
    }

    /// A member that was written gets its offset diffed. A zero-width part has
    /// no C member and so no `offsetof`: the compiler places it where the next
    /// part begins, and no C declaration can confirm or contradict that.
    fn assertOffsets(self: *Emitter, t: TypeId) Error!void {
        const at = @intFromEnum(t);
        if (at >= self.layouts.len or self.layouts[at].too_wide) return;
        var name_buf: [64]u8 = undefined;
        const name = typeName(&name_buf, self.namespace, at);
        for (0..self.typing.fieldCount(t)) |i| {
            if (isZeroWidth(self.typing, self.typing.fieldType(t, @intCast(i)))) continue;
            try self.out.print(
                "_Static_assert(offsetof({s}, m{d}) == {d}, \"offset {d} of o{d}_t{d}\");\n",
                .{ name, i, self.typing.fieldOffset(t, @intCast(i)), i, self.namespace, at },
            );
        }
    }
};

/// Every builtin standing in the emitted C, asserted to satisfy the premise the
/// correspondence rests on.
///
/// `cc` implements its target's ABI, not [L-Layout]. The two coincide where a
/// builtin's alignment equals its size, which every 64-bit target in use
/// satisfies and some 32-bit ones do not. A host that does not satisfy it fails
/// here, at the premise, rather than reporting a Linea defect that is a C ABI
/// difference.
const premise =
    \\_Static_assert(_Alignof(uint8_t) == sizeof(uint8_t), "uint8_t");
    \\_Static_assert(_Alignof(uint16_t) == sizeof(uint16_t), "uint16_t");
    \\_Static_assert(_Alignof(uint32_t) == sizeof(uint32_t), "uint32_t");
    \\_Static_assert(_Alignof(uint64_t) == sizeof(uint64_t), "uint64_t");
    \\_Static_assert(_Alignof(double) == sizeof(double), "double");
    \\_Static_assert(sizeof(void *) == 8 && _Alignof(void *) == 8, "observation pointer");
    \\_Static_assert(sizeof(unsigned char) == 1, "unsigned char");
    \\
;

/// Builds the C that a module's layout table has to survive.
///
/// Only the concrete aggregates the module holds a layout for are reached: a
/// type no program builds has no entry and no oracle.
pub fn of(
    gpa: std.mem.Allocator,
    typing: *const Typing,
    layouts: []const Layout,
    namespace: usize,
) !Oracle {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    try out.writer.writeAll("#include <stdint.h>\n#include <stddef.h>\n\n");
    try out.writer.writeAll(premise);
    try out.writer.writeAll("\n");

    const done = try gpa.alloc(bool, typing.pool.len);
    defer gpa.free(done);
    @memset(done, false);

    var e: Emitter = .{
        .gpa = gpa,
        .typing = typing,
        .layouts = layouts,
        .out = &out.writer,
        .done = done,
        .namespace = namespace,
    };

    for (0..typing.pool.len) |i| {
        const t: TypeId = @enumFromInt(i);
        if (!isAggregate(typing, t) or typing.isShell(t)) continue;
        try e.emit(t);
    }

    return .{ .text = try gpa.dupe(u8, out.written()), .compared = e.compared };
}

test "a module with no aggregate compares nothing" {
    const gpa = testing.allocator;
    var typing: Typing = .{
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
        .binding_types = .empty,
        .decl_returns = .empty,
    };
    const oracle = try of(gpa, &typing, &.{}, 0);
    defer oracle.deinit(gpa);

    try testing.expectEqual(@as(u32, 0), oracle.compared);
    // The premise is emitted whatever the module holds: a host that cannot
    // satisfy it is a host whose answer would mean nothing.
    try testing.expect(std.mem.indexOf(u8, oracle.text, "_Alignof(uint64_t)") != null);
}

test "layout oracle measures observations independently of their referents" {
    const gpa = testing.allocator;
    var builder = try Typing.Builder.init(gpa);
    defer builder.deinit();
    const observed = try builder.borrowOf(.unit);
    _ = try builder.addStruct("Observed", .copyable, &.{
        .{ .name = "before", .ty = .u8 },
        .{ .name = "observed", .ty = observed },
        .{ .name = "after", .ty = .u16 },
    });
    const layouts = try gpa.alloc(Layout, builder.pool.items.len);
    defer gpa.free(layouts);
    for (layouts, 0..) |*layout, i| layout.* = builder.layoutOf(@enumFromInt(i));
    const typing = builder.view();
    const oracle = try of(gpa, &typing, layouts, 0);
    defer oracle.deinit(gpa);
    try testing.expectEqual(@as(u32, 1), oracle.compared);
    try testing.expect(std.mem.indexOf(u8, oracle.text, "const void * m1;") != null);
    try testing.expect(std.mem.indexOf(u8, oracle.text, "offsetof(") != null);
}
