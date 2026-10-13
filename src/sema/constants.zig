const std = @import("std");

const display_byte_limit = 2048;
const display_node_limit = 128;
const display_depth_limit = 16;
const ellipsis = "...";

pub const ConstantId = enum(u32) {
    _,

    pub fn index(self: ConstantId) usize {
        return @intFromEnum(self);
    }
};

pub const Field = struct { name: []const u8, value: ConstantId };
pub const Variant = struct { name: []const u8, payloads: []const ConstantId };

pub const Node = union(enum) {
    integer: i128,
    truth: bool,
    string: []const u8,
    unit,
    record: []const Field,
    array: []const ConstantId,
    variant: Variant,

    const Context = struct {
        pub fn hash(_: Context, node: Node) u64 {
            var state = std.hash.Wyhash.init(@intFromEnum(std.meta.activeTag(node)));
            switch (node) {
                .integer => |value| state.update(std.mem.asBytes(&value)),
                .truth => |value| state.update(std.mem.asBytes(&value)),
                .string => |value| state.update(value),
                .unit => {},
                .record => |fields| for (fields) |field| {
                    state.update(std.mem.asBytes(&field.name.len));
                    state.update(field.name);
                    state.update(std.mem.asBytes(&field.value));
                },
                .array => |values| state.update(std.mem.sliceAsBytes(values)),
                .variant => |value| {
                    state.update(std.mem.asBytes(&value.name.len));
                    state.update(value.name);
                    state.update(std.mem.sliceAsBytes(value.payloads));
                },
            }
            return state.final();
        }

        pub fn eql(_: Context, left: Node, right: Node) bool {
            if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
            return switch (left) {
                .integer => |value| value == right.integer,
                .truth => |value| value == right.truth,
                .string => |value| std.mem.eql(u8, value, right.string),
                .unit => true,
                .record => |fields| blk: {
                    if (fields.len != right.record.len) break :blk false;
                    for (fields, right.record) |a, b| {
                        if (a.value != b.value or !std.mem.eql(u8, a.name, b.name)) break :blk false;
                    }
                    break :blk true;
                },
                .array => |values| std.mem.eql(ConstantId, values, right.array),
                .variant => |value| std.mem.eql(u8, value.name, right.variant.name) and
                    std.mem.eql(ConstantId, value.payloads, right.variant.payloads),
            };
        }
    };

    fn clone(node: Node, gpa: std.mem.Allocator) !Node {
        return switch (node) {
            .integer, .truth, .unit => node,
            .string => |bytes| .{ .string = try gpa.dupe(u8, bytes) },
            .array => |values| .{ .array = try gpa.dupe(ConstantId, values) },
            .variant => |value| blk: {
                const name = try gpa.dupe(u8, value.name);
                errdefer gpa.free(name);
                break :blk .{ .variant = .{ .name = name, .payloads = try gpa.dupe(ConstantId, value.payloads) } };
            },
            .record => |fields| blk: {
                const owned = try gpa.alloc(Field, fields.len);
                var copied: usize = 0;
                errdefer {
                    for (owned[0..copied]) |field| gpa.free(field.name);
                    gpa.free(owned);
                }
                for (fields, owned) |field, *into| {
                    into.* = .{ .name = try gpa.dupe(u8, field.name), .value = field.value };
                    copied += 1;
                }
                break :blk .{ .record = owned };
            },
        };
    }

    fn deinit(node: Node, gpa: std.mem.Allocator) void {
        switch (node) {
            .integer, .truth, .unit => {},
            .string => |bytes| gpa.free(bytes),
            .array => |values| gpa.free(values),
            .variant => |value| {
                gpa.free(value.name);
                gpa.free(value.payloads);
            },
            .record => |fields| {
                for (fields) |field| gpa.free(field.name);
                gpa.free(fields);
            },
        }
    }
};

/// Edges name earlier nodes. Interning compares complete keys after hashing.
/// A cloned prefix retains its IDs and owns all spelling and edge storage.
pub const Pool = struct {
    nodes: std.ArrayList(Node) = .empty,
    index: std.HashMapUnmanaged(Node, ConstantId, Node.Context, std.hash_map.default_max_load_percentage) = .empty,

    pub fn deinit(self: *Pool, gpa: std.mem.Allocator) void {
        self.index.deinit(gpa);
        for (self.nodes.items) |node| node.deinit(gpa);
        self.nodes.deinit(gpa);
        self.* = .{};
    }

    pub fn get(self: *const Pool, id: ConstantId) Node {
        return self.nodes.items[id.index()];
    }

    pub fn intern(self: *Pool, gpa: std.mem.Allocator, value: Node) !ConstantId {
        if (self.index.get(value)) |id| return id;
        const owned = try value.clone(gpa);
        errdefer owned.deinit(gpa);
        try self.nodes.ensureUnusedCapacity(gpa, 1);
        const id: ConstantId = @enumFromInt(self.nodes.items.len);
        try self.index.put(gpa, owned, id);
        self.nodes.appendAssumeCapacity(owned);
        return id;
    }

    pub fn record(self: *Pool, gpa: std.mem.Allocator, fields: []const Field) !ConstantId {
        const sorted = try gpa.dupe(Field, fields);
        defer gpa.free(sorted);
        std.mem.sort(Field, sorted, {}, struct {
            fn less(_: void, a: Field, b: Field) bool {
                return std.mem.order(u8, a.name, b.name) == .lt;
            }
        }.less);
        return self.intern(gpa, .{ .record = sorted });
    }

    pub fn clone(self: *const Pool, gpa: std.mem.Allocator) !Pool {
        var result: Pool = .{};
        errdefer result.deinit(gpa);
        for (self.nodes.items, 0..) |node, expected| {
            const actual = try result.intern(gpa, node);
            std.debug.assert(actual.index() == expected);
        }
        return result;
    }

    /// Diagnostic expansion is capped at 128 nodes, 16 levels and 2048 bytes.
    /// Exact equality and symbol encoding do not use this abbreviated display.
    pub fn display(self: *const Pool, gpa: std.mem.Allocator, root: ConstantId) std.mem.Allocator.Error![]u8 {
        var buffer: [display_byte_limit]u8 = undefined;
        var writer = std.Io.Writer.fixed(buffer[0 .. display_byte_limit - ellipsis.len]);
        var remaining: usize = display_node_limit;
        self.writeDisplay(&writer, root, &remaining, display_depth_limit) catch {
            var end = writer.buffered().len;
            while (end > 0 and !std.unicode.utf8ValidateSlice(buffer[0..end])) end -= 1;
            @memcpy(buffer[end..][0..ellipsis.len], ellipsis);
            return gpa.dupe(u8, buffer[0 .. end + ellipsis.len]);
        };
        return gpa.dupe(u8, writer.buffered());
    }

    fn writeDisplay(self: *const Pool, writer: *std.Io.Writer, id: ConstantId, remaining: *usize, depth: usize) std.Io.Writer.Error!void {
        if (remaining.* == 0 or depth == 0) return writer.writeAll("...");
        remaining.* -= 1;
        switch (self.get(id)) {
            .integer => |value| try writer.print("{d}", .{value}),
            .truth => |value| try writer.writeAll(if (value) "true" else "false"),
            .string => |value| try writeString(writer, value),
            .unit => try writer.writeAll("()"),
            .record => |fields| {
                try writer.writeAll(".{ ");
                for (fields, 0..) |field, i| {
                    if (i != 0) try writer.writeAll(", ");
                    if (remaining.* == 0) {
                        try writer.writeAll("...");
                        break;
                    }
                    try writer.print(".{s} = ", .{field.name});
                    try self.writeDisplay(writer, field.value, remaining, depth - 1);
                }
                try writer.writeAll(" }");
            },
            .array => |values| {
                try writer.writeByte('[');
                try self.writeDisplayChildren(writer, values, remaining, depth);
                try writer.writeByte(']');
            },
            .variant => |value| {
                try writer.print(".{s}", .{value.name});
                if (value.payloads.len != 0) {
                    try writer.writeByte('(');
                    try self.writeDisplayChildren(writer, value.payloads, remaining, depth);
                    try writer.writeByte(')');
                }
            },
        }
    }

    fn writeDisplayChildren(self: *const Pool, writer: *std.Io.Writer, values: []const ConstantId, remaining: *usize, depth: usize) std.Io.Writer.Error!void {
        for (values, 0..) |value, i| {
            if (i != 0) try writer.writeAll(", ");
            try self.writeDisplay(writer, value, remaining, depth - 1);
            if (remaining.* == 0) {
                if (i + 1 != values.len) try writer.writeAll(", ...");
                break;
            }
        }
    }

    /// Breadth-first numbering depends on ordered edges, never pool insertion.
    /// Shared children are written once, bounding output by reachable graph size.
    pub fn encoding(self: *const Pool, gpa: std.mem.Allocator, root: ConstantId) std.mem.Allocator.Error![]u8 {
        return self.encode(gpa, root) catch return error.OutOfMemory;
    }

    fn encode(self: *const Pool, gpa: std.mem.Allocator, root: ConstantId) ![]u8 {
        var order: std.ArrayList(ConstantId) = .empty;
        defer order.deinit(gpa);
        var numbers: std.AutoHashMapUnmanaged(ConstantId, usize) = .empty;
        defer numbers.deinit(gpa);
        try order.append(gpa, root);
        try numbers.put(gpa, root, 0);
        var output: std.Io.Writer.Allocating = .init(gpa);
        defer output.deinit();
        var at: usize = 0;
        while (at < order.items.len) : (at += 1) {
            try output.writer.print("{d}=", .{at});
            switch (self.get(order.items[at])) {
                .integer => |value| try output.writer.print("i{d}", .{value}),
                .truth => |value| try output.writer.writeAll(if (value) "true" else "false"),
                .string => |value| {
                    try output.writer.print("s{d}:", .{value.len});
                    for (value) |byte| switch (byte) {
                        0...31, 127, '\\' => try output.writer.print("\\x{x:0>2}", .{byte}),
                        else => try output.writer.writeByte(byte),
                    };
                },
                .unit => try output.writer.writeAll("unit"),
                .record => |fields| {
                    try output.writer.writeAll("record[");
                    for (fields) |field| {
                        try output.writer.print("{d}:{s}@{d},", .{ field.name.len, field.name, try number(gpa, &order, &numbers, field.value) });
                    }
                    try output.writer.writeByte(']');
                },
                .array => |values| {
                    try output.writer.writeAll("array[");
                    for (values) |value| try output.writer.print("@{d},", .{try number(gpa, &order, &numbers, value)});
                    try output.writer.writeByte(']');
                },
                .variant => |value| {
                    try output.writer.print("variant{d}:{s}[", .{ value.name.len, value.name });
                    for (value.payloads) |child| try output.writer.print("@{d},", .{try number(gpa, &order, &numbers, child)});
                    try output.writer.writeByte(']');
                },
            }
            try output.writer.writeByte(';');
        }
        return output.toOwnedSlice();
    }

    fn number(gpa: std.mem.Allocator, order: *std.ArrayList(ConstantId), numbers: *std.AutoHashMapUnmanaged(ConstantId, usize), id: ConstantId) !usize {
        if (numbers.get(id)) |value| return value;
        const result = order.items.len;
        try order.append(gpa, id);
        try numbers.put(gpa, id, result);
        return result;
    }
};

pub fn writeString(writer: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!void {
    try writer.writeByte('"');
    for (bytes) |byte| switch (byte) {
        '"', '\\' => {
            try writer.writeByte('\\');
            try writer.writeByte(byte);
        },
        '{', '}' => {
            try writer.writeByte(byte);
            try writer.writeByte(byte);
        },
        0...31, 127 => try writer.print("\\u{{{x}}}", .{byte}),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

test "aggregate constants intern sorted fields with exact child identity" {
    const gpa = std.testing.allocator;
    var pool: Pool = .{};
    defer pool.deinit(gpa);
    const one = try pool.intern(gpa, .{ .integer = 1 });
    const two = try pool.intern(gpa, .{ .integer = 2 });
    const first = try pool.record(gpa, &.{ .{ .name = "x", .value = one }, .{ .name = "y", .value = two } });
    const reordered = try pool.record(gpa, &.{ .{ .name = "y", .value = two }, .{ .name = "x", .value = one } });
    const different = try pool.record(gpa, &.{ .{ .name = "x", .value = two }, .{ .name = "y", .value = one } });
    try std.testing.expectEqual(first, reordered);
    try std.testing.expect(first != different);
}

test "aggregate constants preserve prefixes and compact deterministic shared encoding" {
    const Case = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var first: Pool = .{};
            defer first.deinit(gpa);
            var value = try first.intern(gpa, .{ .string = "leaf" });
            for (0..48) |_| value = try first.intern(gpa, .{ .array = &.{ value, value } });
            const encoded = try first.encoding(gpa, value);
            defer gpa.free(encoded);
            try std.testing.expect(encoded.len < 2048);
            var prefix = try first.clone(gpa);
            defer prefix.deinit(gpa);
            try std.testing.expectEqual(value, try prefix.intern(gpa, first.get(value)));
            var second: Pool = .{};
            defer second.deinit(gpa);
            _ = try second.intern(gpa, .{ .integer = 99 });
            var other = try second.intern(gpa, .{ .string = "leaf" });
            for (0..48) |_| other = try second.intern(gpa, .{ .array = &.{ other, other } });
            const equivalent = try second.encoding(gpa, other);
            defer gpa.free(equivalent);
            try std.testing.expectEqualStrings(encoded, equivalent);
        }
    };
    try Case.run(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Case.run, .{});
}

test "aggregate constants escape control bytes without changing identity" {
    const gpa = std.testing.allocator;
    var pool: Pool = .{};
    defer pool.deinit(gpa);
    const bytes = try pool.intern(gpa, .{ .string = "a\n\x00\\x00" });
    const record = try pool.record(gpa, &.{.{ .name = "text", .value = bytes }});
    const encoded = try pool.encoding(gpa, record);
    defer gpa.free(encoded);
    try std.testing.expect(std.mem.indexOfScalar(u8, encoded, 0) == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, encoded, '\n') == null);
    const other = try pool.intern(gpa, .{ .string = "a\\x0a\\x00\\x00" });
    try std.testing.expect(bytes != other);
}

test "aggregate constants display readable data with bounded shared expansion" {
    const gpa = std.testing.allocator;
    var pool: Pool = .{};
    defer pool.deinit(gpa);
    const two = try pool.intern(gpa, .{ .integer = 2 });
    const one = try pool.intern(gpa, .{ .integer = 1 });
    var value = try pool.intern(gpa, .{ .array = &.{ two, one } });
    const readable = try pool.display(gpa, value);
    defer gpa.free(readable);
    try std.testing.expectEqualStrings("[2, 1]", readable);
    for (0..48) |_| value = try pool.intern(gpa, .{ .array = &.{ value, value } });
    const bounded = try pool.display(gpa, value);
    defer gpa.free(bounded);
    try std.testing.expect(bounded.len <= display_byte_limit);
    try std.testing.expect(std.mem.indexOf(u8, bounded, "...") != null);
}

test "aggregate constants truncate diagnostic text on a UTF8 boundary" {
    const gpa = std.testing.allocator;
    var pool: Pool = .{};
    defer pool.deinit(gpa);
    const bytes = "a" ** 2041 ++ "€";
    const text = try pool.intern(gpa, .{ .string = bytes });
    const array = try pool.intern(gpa, .{ .array = &.{text} });
    const display = try pool.display(gpa, array);
    defer gpa.free(display);
    try std.testing.expect(std.unicode.utf8ValidateSlice(display));
    try std.testing.expect(std.mem.endsWith(u8, display, "..."));
}
