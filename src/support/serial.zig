//! A deterministic binary encoding of plain data, derived from its type.
//!
//! The encoding is a function of the values alone: fields in declaration
//! order with no padding, integers as LEB128 (signed ones zigzagged), enums
//! as their integer, slices as a length and their elements, and a hash map's
//! entries in the order of their encoded keys, so two maps holding the same
//! entries encode alike whatever order they were filled in. Integer arrays
//! whose every bit pattern is a value (integers and non-exhaustive enums) are
//! written as their bytes in the machine's order, which is why an encoding is
//! read back only on the architecture that wrote it.
//!
//! A type the encoding cannot follow alone -- a single-item pointer, an
//! allocator, an untagged union -- is a compile error unless `Hooks` takes it:
//! `Hooks.custom(T)` says it does, and `Hooks.encode`/`Hooks.decode` write and
//! read it, usually by encoding the parts that are data and rebuilding the
//! rest. Decoding allocates every value in the supplied allocator, meant to be
//! an arena, and borrows `[]const u8` slices from the input, which must
//! therefore outlive what is decoded.
//!
//! A decoder never reads past its input and never builds a value of an
//! exhaustive enum or a union tag from a number naming none: such input is
//! `error.Corrupt`.

const std = @import("std");
const testing = std.testing;

pub const DecodeError = std.mem.Allocator.Error || error{Corrupt};

pub fn Encoder(comptime Hooks: type) type {
    return struct {
        const Self = @This();

        gpa: std.mem.Allocator,
        out: std.ArrayList(u8) = .empty,
        /// Scratch for sorting a hash map's entries by their encoded keys.
        scratch: std.mem.Allocator,
        hooks: *Hooks,

        pub fn deinit(self: *Self) void {
            self.out.deinit(self.gpa);
        }

        pub fn bytes(self: *Self, data: []const u8) std.mem.Allocator.Error!void {
            try self.out.appendSlice(self.gpa, data);
        }

        pub fn unsigned(self: *Self, n: u64) std.mem.Allocator.Error!void {
            var rest = n;
            while (true) {
                const low: u8 = @truncate(rest & 0x7f);
                rest >>= 7;
                if (rest == 0) return self.out.append(self.gpa, low);
                try self.out.append(self.gpa, low | 0x80);
            }
        }

        pub fn length(self: *Self, n: usize) std.mem.Allocator.Error!void {
            try self.unsigned(n);
        }

        pub fn value(self: *Self, comptime T: type, v: *const T) std.mem.Allocator.Error!void {
            if (comptime Hooks.custom(T)) return self.hooks.encode(self, T, v);
            switch (@typeInfo(T)) {
                .void => {},
                .bool => try self.out.append(self.gpa, @intFromBool(v.*)),
                .int => |info| try self.integer(info, v.*),
                .float => try self.value(std.meta.Int(.unsigned, @bitSizeOf(T)), &@as(std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(v.*))),
                .@"enum" => |info| try self.integer(@typeInfo(info.tag_type).int, @intFromEnum(v.*)),
                .optional => |info| if (v.*) |*payload| {
                    try self.out.append(self.gpa, 1);
                    try self.value(info.child, payload);
                } else try self.out.append(self.gpa, 0),
                .array => |info| try self.elements(info.child, &v.*),
                .pointer => |info| switch (info.size) {
                    .slice => {
                        try self.length(v.len);
                        try self.elements(info.child, v.*);
                    },
                    else => @compileError("serial: a pointer is not data: " ++ @typeName(T)),
                },
                .@"union" => |info| {
                    const Tag = info.tag_type orelse @compileError("serial: an untagged union: " ++ @typeName(T));
                    const tag: Tag = v.*;
                    try self.value(Tag, &tag);
                    switch (v.*) {
                        inline else => |*payload| try self.value(@TypeOf(payload.*), payload),
                    }
                },
                .@"struct" => |info| {
                    if (info.layout == .@"packed") {
                        const Backing = info.backing_integer.?;
                        return self.value(Backing, &@as(Backing, @bitCast(v.*)));
                    }
                    if (comptime isArrayList(T)) return self.value(@TypeOf(v.items), &v.items);
                    if (comptime isHashMap(T)) return self.hashMap(T, v);
                    if (comptime isArrayHashMap(T)) return self.arrayHashMap(T, v);
                    if (comptime isMultiArrayList(T)) return self.multiArrayList(T, v);
                    if (comptime isMultiArraySlice(T)) {
                        const list = v.toMultiArrayList();
                        return self.multiArrayList(@TypeOf(list), &list);
                    }
                    inline for (info.fields) |field| {
                        if (!field.is_comptime) try self.value(field.type, &@field(v.*, field.name));
                    }
                },
                else => @compileError("serial: no encoding for " ++ @typeName(T)),
            }
        }

        fn integer(self: *Self, comptime info: std.builtin.Type.Int, v: anytype) std.mem.Allocator.Error!void {
            if (info.bits > 64) {
                const Wide = std.meta.Int(.unsigned, info.bits);
                var raw: [@sizeOf(Wide)]u8 = undefined;
                std.mem.writeInt(Wide, &raw, @bitCast(v), .little);
                return self.bytes(&raw);
            }
            if (info.signedness == .unsigned) return self.unsigned(v);
            const wide: i64 = v;
            try self.unsigned(@bitCast((wide << 1) ^ (wide >> 63)));
        }

        fn elements(self: *Self, comptime E: type, items: []const E) std.mem.Allocator.Error!void {
            if (comptime rawElement(E) and !Hooks.custom(E)) return self.bytes(std.mem.sliceAsBytes(items));
            for (items) |*item| try self.value(E, item);
        }

        fn hashMap(self: *Self, comptime T: type, map: *const T) std.mem.Allocator.Error!void {
            const KV = T.KV;
            try self.length(map.count());
            // Each entry is encoded apart, then the entries are written in the
            // order of their encoded keys.
            const Row = struct { start: usize, key_end: usize, end: usize };
            var rows: std.ArrayList(Row) = .empty;
            defer rows.deinit(self.scratch);
            var held: Self = .{ .gpa = self.scratch, .scratch = self.scratch, .hooks = self.hooks };
            defer held.deinit();
            var it = map.iterator();
            while (it.next()) |entry| {
                const start = held.out.items.len;
                try held.value(@FieldType(KV, "key"), entry.key_ptr);
                const key_end = held.out.items.len;
                try held.value(@FieldType(KV, "value"), entry.value_ptr);
                try rows.append(self.scratch, .{ .start = start, .key_end = key_end, .end = held.out.items.len });
            }
            const encoded = held.out.items;
            std.mem.sort(Row, rows.items, encoded, struct {
                fn less(data: []const u8, a: Row, b: Row) bool {
                    return std.mem.order(u8, data[a.start..a.key_end], data[b.start..b.key_end]) == .lt;
                }
            }.less);
            for (rows.items) |row| try self.bytes(encoded[row.start..row.end]);
        }

        fn arrayHashMap(self: *Self, comptime T: type, map: *const T) std.mem.Allocator.Error!void {
            try self.length(map.count());
            for (map.keys(), map.values()) |*k, *v| {
                try self.value(@TypeOf(k.*), k);
                try self.value(@TypeOf(v.*), v);
            }
        }

        fn multiArrayList(self: *Self, comptime T: type, list: *const T) std.mem.Allocator.Error!void {
            try self.length(list.len);
            const slice = list.slice();
            inline for (comptime std.enums.values(T.Field)) |field| {
                try self.elements(ColumnOf(T, field), slice.items(field));
            }
        }
    };
}

pub fn Decoder(comptime Hooks: type) type {
    return struct {
        const Self = @This();

        input: []const u8,
        at: usize = 0,
        /// Where every decoded value is allocated.
        arena: std.mem.Allocator,
        hooks: *Hooks,

        pub fn bytes(self: *Self, n: usize) DecodeError![]const u8 {
            if (n > self.input.len - self.at) return error.Corrupt;
            defer self.at += n;
            return self.input[self.at..][0..n];
        }

        pub fn unsigned(self: *Self) DecodeError!u64 {
            var result: u64 = 0;
            var shift: u7 = 0;
            while (true) {
                const byte = (try self.bytes(1))[0];
                if (shift >= 64 or (shift == 63 and byte & 0x7e != 0)) return error.Corrupt;
                result |= @as(u64, byte & 0x7f) << @intCast(shift);
                if (byte & 0x80 == 0) return result;
                shift += 7;
            }
        }

        /// A length no larger than the bytes left, since every element takes
        /// at least one byte or is zero-sized.
        /// A length a hook reads, whose elements the hook decodes itself or
        /// does not encode at all.
        pub fn length(self: *Self) DecodeError!usize {
            const n = try self.unsigned();
            if (n > std.math.maxInt(u32)) return error.Corrupt;
            return @intCast(n);
        }

        /// The length of a run of `E`, which cannot exceed how many of them
        /// the input left could hold: a run that claims more is corrupt
        /// before anything is allocated for it.
        fn lengthOf(self: *Self, comptime E: type) DecodeError!usize {
            return self.lengthAtLeast(comptime leastEncoded(Hooks, E));
        }

        /// `lengthOf` for elements that each take at least `least` bytes.
        pub fn lengthAtLeast(self: *Self, comptime least: usize) DecodeError!usize {
            const n = try self.length();
            if (least != 0 and n > (self.input.len - self.at) / least) return error.Corrupt;
            return n;
        }

        pub fn finished(self: *const Self) bool {
            return self.at == self.input.len;
        }

        pub fn value(self: *Self, comptime T: type) DecodeError!T {
            if (comptime Hooks.custom(T)) return self.hooks.decode(self, T);
            switch (@typeInfo(T)) {
                .void => return {},
                .bool => return switch ((try self.bytes(1))[0]) {
                    0 => false,
                    1 => true,
                    else => error.Corrupt,
                },
                .int => |info| return self.integer(T, info),
                .float => return @bitCast(try self.value(std.meta.Int(.unsigned, @bitSizeOf(T)))),
                .@"enum" => |info| {
                    const raw = try self.integer(info.tag_type, @typeInfo(info.tag_type).int);
                    if (info.is_exhaustive) {
                        // An enum numbering its tags from zero without gaps
                        // names every value below its count, which a bound
                        // answers; `fromInt` compares against each tag.
                        if (comptime denseFromZero(T)) {
                            if (raw < 0 or raw >= info.fields.len) return error.Corrupt;
                            return @enumFromInt(raw);
                        }
                        return std.enums.fromInt(T, raw) orelse error.Corrupt;
                    }
                    return @enumFromInt(raw);
                },
                .optional => |info| return switch ((try self.bytes(1))[0]) {
                    0 => null,
                    1 => try self.value(info.child),
                    else => error.Corrupt,
                },
                .array => |info| {
                    var out: T = undefined;
                    try self.elements(info.child, &out);
                    return out;
                },
                .pointer => |info| switch (info.size) {
                    .slice => {
                        const n = try self.lengthOf(info.child);
                        if (info.child == u8 and info.is_const and info.sentinel_ptr == null and (info.alignment orelse 1) <= 1) {
                            return self.bytes(n);
                        }
                        const out = if (info.sentinel()) |s|
                            try self.arena.allocSentinel(info.child, n, s)
                        else
                            try self.arena.alignedAlloc(info.child, if (info.alignment) |a| .fromByteUnits(a) else null, n);
                        try self.elements(info.child, out);
                        return out;
                    },
                    else => @compileError("serial: a pointer is not data: " ++ @typeName(T)),
                },
                .@"union" => |info| {
                    const Tag = info.tag_type orelse @compileError("serial: an untagged union: " ++ @typeName(T));
                    const tag = try self.value(Tag);
                    switch (tag) {
                        inline else => |t| return @unionInit(T, @tagName(t), try self.value(@FieldType(T, @tagName(t)))),
                    }
                },
                .@"struct" => |info| {
                    if (info.layout == .@"packed") return @bitCast(try self.value(info.backing_integer.?));
                    if (comptime isArrayList(T)) {
                        const items = try self.value(@FieldType(T, "items"));
                        return .{ .items = @constCast(items), .capacity = items.len };
                    }
                    if (comptime isHashMap(T)) return self.hashMap(T);
                    if (comptime isArrayHashMap(T)) return self.arrayHashMap(T);
                    if (comptime isMultiArrayList(T)) return self.multiArrayList(T);
                    if (comptime isMultiArraySlice(T)) {
                        const list = try self.multiArrayList(@TypeOf(@as(T, undefined).toMultiArrayList()));
                        return list.slice();
                    }
                    var out: T = undefined;
                    inline for (info.fields) |field| {
                        if (!field.is_comptime) @field(out, field.name) = try self.value(field.type);
                    }
                    return out;
                },
                else => @compileError("serial: no encoding for " ++ @typeName(T)),
            }
        }

        fn integer(self: *Self, comptime T: type, comptime info: std.builtin.Type.Int) DecodeError!T {
            if (info.bits > 64) {
                const Wide = std.meta.Int(.unsigned, info.bits);
                const raw = try self.bytes(@sizeOf(Wide));
                return @bitCast(std.mem.readInt(Wide, raw[0..@sizeOf(Wide)], .little));
            }
            const raw = try self.unsigned();
            if (info.signedness == .unsigned) return std.math.cast(T, raw) orelse error.Corrupt;
            const wide: i64 = @bitCast((raw >> 1) ^ (0 -% (raw & 1)));
            return std.math.cast(T, wide) orelse error.Corrupt;
        }

        fn elements(self: *Self, comptime E: type, out: []E) DecodeError!void {
            if (comptime rawElement(E) and !Hooks.custom(E)) {
                @memcpy(std.mem.sliceAsBytes(out), try self.bytes(out.len * @sizeOf(E)));
                return;
            }
            for (out) |*item| item.* = try self.value(E);
        }

        fn hashMap(self: *Self, comptime T: type) DecodeError!T {
            const KV = T.KV;
            const n = try self.lengthOf(KV);
            var map: T = .empty;
            try map.ensureTotalCapacity(self.arena, std.math.cast(T.Size, n) orelse return error.Corrupt);
            for (0..n) |_| {
                const k = try self.value(@FieldType(KV, "key"));
                const v = try self.value(@FieldType(KV, "value"));
                const slot = map.getOrPutAssumeCapacity(k);
                if (slot.found_existing) return error.Corrupt;
                slot.value_ptr.* = v;
            }
            return map;
        }

        fn arrayHashMap(self: *Self, comptime T: type) DecodeError!T {
            const n = try self.lengthOf(T.KV);
            var map: T = .empty;
            try map.ensureTotalCapacity(self.arena, n);
            for (0..n) |_| {
                const k = try self.value(@TypeOf(map.keys()[0]));
                const v = try self.value(@TypeOf(map.values()[0]));
                const slot = map.getOrPutAssumeCapacity(k);
                if (slot.found_existing) return error.Corrupt;
                slot.value_ptr.* = v;
            }
            return map;
        }

        fn multiArrayList(self: *Self, comptime T: type) DecodeError!T {
            const n = try self.lengthAtLeast(comptime least: {
                var sum: usize = 0;
                for (std.enums.values(T.Field)) |field| sum += leastEncoded(Hooks, ColumnOf(T, field));
                break :least sum;
            });
            var list: T = .empty;
            try list.setCapacity(self.arena, n);
            list.len = n;
            const slice = list.slice();
            inline for (comptime std.enums.values(T.Field)) |field| {
                try self.elements(ColumnOf(T, field), slice.items(field));
            }
            return list;
        }
    };
}

/// A compile error naming the path from `T` to the first part of it the
/// encoding cannot follow and `Hooks` does not take, or nothing.
pub fn assertEncodable(comptime T: type, comptime Hooks: type) void {
    @setEvalBranchQuota(1_000_000);
    comptime if (unencodable(T, Hooks, @typeName(T), &.{})) |path| @compileError("serial: no encoding for " ++ path);
}

fn unencodable(comptime T: type, comptime Hooks: type, comptime path: []const u8, comptime seen: []const type) ?[]const u8 {
    if (Hooks.custom(T)) return null;
    for (seen) |s| if (s == T) return null;
    const now = seen ++ [_]type{T};
    return switch (@typeInfo(T)) {
        .void, .bool, .int, .float, .@"enum" => null,
        .optional => |info| unencodable(info.child, Hooks, path ++ ".?", now),
        .array => |info| unencodable(info.child, Hooks, path ++ "[_]", now),
        .pointer => |info| if (info.size == .slice) unencodable(info.child, Hooks, path ++ "[]", now) else path ++ " (" ++ @typeName(T) ++ ")",
        .@"union" => |info| blk: {
            if (info.tag_type == null) break :blk path ++ " (untagged)";
            for (info.fields) |field| if (unencodable(field.type, Hooks, path ++ "." ++ field.name, now)) |p| break :blk p;
            break :blk null;
        },
        .@"struct" => |info| blk: {
            if (info.layout == .@"packed") break :blk null;
            if (isArrayList(T)) break :blk unencodable(@FieldType(T, "items"), Hooks, path, now);
            if (isHashMap(T)) break :blk unencodable(@FieldType(T.KV, "key"), Hooks, path ++ ".key", now) orelse
                unencodable(@FieldType(T.KV, "value"), Hooks, path ++ ".value", now);
            if (isArrayHashMap(T)) break :blk unencodable(@typeInfo(@TypeOf(@as(T, undefined).keys())).pointer.child, Hooks, path ++ ".key", now) orelse
                unencodable(@typeInfo(@TypeOf(@as(T, undefined).values())).pointer.child, Hooks, path ++ ".value", now);
            if (isMultiArrayList(T)) {
                for (std.enums.values(T.Field)) |field| if (unencodable(ColumnOf(T, field), Hooks, path ++ "." ++ @tagName(field), now)) |p| break :blk p;
                break :blk null;
            }
            if (isMultiArraySlice(T)) break :blk unencodable(@TypeOf(@as(T, undefined).toMultiArrayList()), Hooks, path, now);
            for (info.fields) |field| {
                if (!field.is_comptime) if (unencodable(field.type, Hooks, path ++ "." ++ field.name, now)) |p| break :blk p;
            }
            break :blk null;
        },
        else => path ++ " (" ++ @typeName(T) ++ ")",
    };
}

/// An element written as its bytes: every bit pattern of it is a value and it
/// holds no padding.
/// The fewest bytes a value of `T` encodes to, which bounds how many of them
/// the rest of an input can hold. A type `Hooks` takes may encode to nothing.
fn leastEncoded(comptime Hooks: type, comptime T: type) usize {
    if (Hooks.custom(T)) return 0;
    return switch (@typeInfo(T)) {
        .void => 0,
        .bool, .float, .optional, .@"enum", .pointer, .@"union" => 1,
        .int => |info| if (info.bits > 64) @sizeOf(T) else 1,
        .array => |info| info.len * (if (rawElement(info.child)) @sizeOf(info.child) else leastEncoded(Hooks, info.child)),
        .@"struct" => |info| least: {
            if (info.layout == .@"packed" or isArrayList(T) or isHashMap(T) or isArrayHashMap(T) or isMultiArrayList(T) or isMultiArraySlice(T)) break :least 1;
            var sum: usize = 0;
            for (info.fields) |field| {
                if (!field.is_comptime) sum += leastEncoded(Hooks, field.type);
            }
            break :least sum;
        },
        else => 0,
    };
}

/// Whether an exhaustive enum's tags are exactly the integers below its count.
fn denseFromZero(comptime E: type) bool {
    const fields = @typeInfo(E).@"enum".fields;
    var seen = [_]bool{false} ** fields.len;
    for (fields) |field| {
        if (field.value < 0 or field.value >= fields.len or seen[field.value]) return false;
        seen[field.value] = true;
    }
    return true;
}

fn rawElement(comptime E: type) bool {
    return switch (@typeInfo(E)) {
        .int => |info| info.bits % 8 == 0 and @sizeOf(E) * 8 == info.bits,
        .@"enum" => |info| !info.is_exhaustive and rawElement(info.tag_type),
        else => false,
    };
}

fn isArrayList(comptime T: type) bool {
    const fields = @typeInfo(T).@"struct".fields;
    return fields.len == 2 and @hasField(T, "items") and @hasField(T, "capacity") and @hasDecl(T, "Slice");
}

fn isHashMap(comptime T: type) bool {
    return @hasField(T, "metadata") and @hasField(T, "available") and @hasDecl(T, "KV");
}

fn isArrayHashMap(comptime T: type) bool {
    return @hasField(T, "entries") and @hasField(T, "index_header");
}

fn isMultiArrayList(comptime T: type) bool {
    return @hasField(T, "bytes") and @hasField(T, "len") and @hasDecl(T, "Field") and @hasDecl(T, "Slice");
}

fn isMultiArraySlice(comptime T: type) bool {
    return @hasField(T, "ptrs") and @hasField(T, "len") and @hasField(T, "capacity") and @hasDecl(T, "toMultiArrayList");
}

/// The element type of one column of a `std.MultiArrayList`.
fn ColumnOf(comptime T: type, comptime field: T.Field) type {
    return @typeInfo(@TypeOf(@as(T.Slice, undefined).items(field))).pointer.child;
}

/// Hooks that take no type, for data the encoding follows alone.
pub const NoHooks = struct {
    pub fn custom(comptime _: type) bool {
        return false;
    }
    pub fn encode(_: *NoHooks, _: anytype, comptime _: type, _: anytype) std.mem.Allocator.Error!void {
        unreachable;
    }
    pub fn decode(_: *NoHooks, _: anytype, comptime T: type) DecodeError!T {
        unreachable;
    }
};

const Shape = enum { circle, square };
const Id = enum(u32) { none = std.math.maxInt(u32), _ };
const Pair = struct { a: u8, b: Id };
const Sample = struct {
    name: []const u8,
    flags: [3]bool,
    ids: []const Id,
    shape: Shape,
    offset: i32,
    ratio: f64,
    maybe: ?u16,
    choice: union(enum) { nothing, count: u8, label: []const u8 },
    list: std.ArrayList(u32),
    map: std.AutoHashMapUnmanaged(u32, []const u8),
    ordered: std.StringArrayHashMapUnmanaged(Id),
    columns: std.MultiArrayList(Pair),
    sliced: std.MultiArrayList(Pair).Slice,
};

fn sample(gpa: std.mem.Allocator, fill_reversed: bool) !Sample {
    var s: Sample = .{
        .name = "sample",
        .flags = .{ true, false, true },
        .ids = &.{ @enumFromInt(1), .none },
        .shape = .square,
        .offset = -300,
        .ratio = 0.25,
        .maybe = null,
        .choice = .{ .label = "chosen" },
        .list = .empty,
        .map = .empty,
        .ordered = .empty,
        .columns = .empty,
        .sliced = undefined,
    };
    try s.list.appendSlice(gpa, &.{ 1, 200, 70000 });
    const keys = [_]u32{ 9, 1, 400, 3 };
    for (0..keys.len) |i| {
        const k = keys[if (fill_reversed) keys.len - 1 - i else i];
        try s.map.put(gpa, k, if (k % 2 == 0) "even" else "odd");
    }
    try s.ordered.put(gpa, "b", @enumFromInt(2));
    try s.ordered.put(gpa, "a", @enumFromInt(1));
    try s.columns.append(gpa, .{ .a = 5, .b = .none });
    try s.columns.append(gpa, .{ .a = 6, .b = @enumFromInt(6) });
    var copied = try s.columns.clone(gpa);
    s.sliced = copied.toOwnedSlice();
    return s;
}

fn encodeSample(gpa: std.mem.Allocator, s: *const Sample) ![]u8 {
    var hooks: NoHooks = .{};
    var e: Encoder(NoHooks) = .{ .gpa = gpa, .scratch = gpa, .hooks = &hooks };
    errdefer e.deinit();
    try e.value(Sample, s);
    return e.out.toOwnedSlice(gpa);
}

test "a value decodes to what was encoded, and maps encode alike however they were filled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const forward = try sample(gpa, false);
    const reversed = try sample(gpa, true);
    const a = try encodeSample(gpa, &forward);
    const b = try encodeSample(gpa, &reversed);
    try testing.expectEqualSlices(u8, a, b);

    var hooks: NoHooks = .{};
    var d: Decoder(NoHooks) = .{ .input = a, .arena = gpa, .hooks = &hooks };
    const back = try d.value(Sample);
    try testing.expect(d.finished());
    try testing.expectEqualStrings("sample", back.name);
    try testing.expectEqualSlices(Id, forward.ids, back.ids);
    try testing.expectEqual(@as(i32, -300), back.offset);
    try testing.expectEqual(@as(f64, 0.25), back.ratio);
    try testing.expectEqual(@as(?u16, null), back.maybe);
    try testing.expectEqualStrings("chosen", back.choice.label);
    try testing.expectEqualSlices(u32, forward.list.items, back.list.items);
    try testing.expectEqualStrings("even", back.map.get(400).?);
    try testing.expectEqualStrings("odd", back.map.get(9).?);
    try testing.expectEqualStrings("b", back.ordered.keys()[0]);
    try testing.expectEqual(Id.none, back.columns.items(.b)[0]);
    try testing.expectEqual(@as(u8, 6), back.columns.items(.a)[1]);
    try testing.expectEqual(@as(u8, 6), back.sliced.items(.a)[1]);
    try testing.expectEqualSlices(u8, a, try encodeSample(gpa, &back));
}

test "input that ends early or names no value is corrupt" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const s = try sample(gpa, false);
    const encoded = try encodeSample(gpa, &s);
    var hooks: NoHooks = .{};
    for (0..encoded.len) |cut| {
        var d: Decoder(NoHooks) = .{ .input = encoded[0..cut], .arena = gpa, .hooks = &hooks };
        try testing.expectError(error.Corrupt, d.value(Sample));
    }
    var d: Decoder(NoHooks) = .{ .input = &.{7}, .arena = gpa, .hooks = &hooks };
    try testing.expectError(error.Corrupt, d.value(Shape));
}

test "a length claiming more elements than the input holds is corrupt before anything is allocated" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var hooks: NoHooks = .{};
    // Four billion slices, then nothing to hold them.
    const input = [_]u8{ 0xff, 0xff, 0xff, 0xff, 0x0f } ++ [_]u8{0} ** 15;
    var d: Decoder(NoHooks) = .{ .input = &input, .arena = arena.allocator(), .hooks = &hooks };
    try testing.expectError(error.Corrupt, d.value([]const []const []const [4096]u8));
    // Elements that encode to nothing may be as many as a length says.
    var empty: Decoder(NoHooks) = .{ .input = &.{3}, .arena = arena.allocator(), .hooks = &hooks };
    try testing.expectEqual(@as(usize, 3), (try empty.value([]const void)).len);
}
