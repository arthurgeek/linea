const std = @import("std");
const testing = std.testing;

/// A name, reduced to an integer.
///
/// Two identifiers spell the same name exactly when their handles are equal, so
/// a scope lookup compares integers rather than bytes. `.none` is the handle a
/// token carries when it is not an identifier.
pub const StringId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(i: u32) StringId {
        return @enumFromInt(i);
    }

    pub fn index(self: StringId) u32 {
        return @intFromEnum(self);
    }
};

/// Hash-conses identifier text, so each distinct name is stored once and
/// referred to by handle.
///
/// An ordinary interner borrows text from source buffers. An expanded interner
/// borrows its exact source prefix and owns every spelling appended after it.
///
/// One per compilation unit rather than one per file. Handles are only
/// comparable within the interner that issued them, and resolution across files
/// compares names from different files.
pub const Interner = struct {
    /// Text to handle. Keys borrow source text or point into an owned suffix.
    ids: std.StringHashMapUnmanaged(StringId) = .empty,
    /// Handle to text, so a name can be printed without a span to hand. Index
    /// is the handle's own integer, which is what makes it a plain lookup.
    texts: std.ArrayList([]const u8) = .empty,
    /// The first owned text, or null when every insertion is borrowed.
    owned_start: ?u32 = null,

    pub const empty: Interner = .{};

    /// Rebuilds independent lookup storage with every source ID unchanged.
    pub fn initPrefix(gpa: std.mem.Allocator, source: *const Interner) !Interner {
        var out: Interner = .empty;
        errdefer out.deinit(gpa);

        for (source.texts.items, 0..) |text, i| {
            const id = try out.intern(gpa, text);
            std.debug.assert(id == StringId.at(@intCast(i)));
        }
        out.owned_start = source.count();
        return out;
    }

    pub fn deinit(self: *Interner, gpa: std.mem.Allocator) void {
        self.ids.deinit(gpa);
        if (self.owned_start) |start| {
            for (self.texts.items[start..]) |text| gpa.free(text);
        }
        self.texts.deinit(gpa);
        self.* = undefined;
    }

    pub fn intern(self: *Interner, gpa: std.mem.Allocator, text: []const u8) !StringId {
        if (self.ids.get(text)) |id| return id;

        const owns_text = self.owned_start != null;
        const stored = if (owns_text) try gpa.dupe(u8, text) else text;
        errdefer if (owns_text) gpa.free(stored);

        const id = StringId.at(@intCast(self.texts.items.len));
        try self.texts.append(gpa, stored);
        errdefer _ = self.texts.pop();
        try self.ids.put(gpa, stored, id);
        return id;
    }

    /// The text a handle was made from. `.none` has none.
    pub fn textOf(self: *const Interner, id: StringId) ?[]const u8 {
        if (id == .none) return null;
        return self.texts.items[id.index()];
    }

    pub fn count(self: *const Interner) u32 {
        return @intCast(self.texts.items.len);
    }
};

test "the same text interns to the same handle" {
    var it: Interner = .empty;
    defer it.deinit(testing.allocator);
    const gpa = testing.allocator;

    const a = try it.intern(gpa, "total");
    const b = try it.intern(gpa, "total");
    const c = try it.intern(gpa, "count");

    try testing.expectEqual(a, b);
    try testing.expect(a != c);
    try testing.expectEqual(@as(u32, 2), it.count());
}

test "equal text from different places interns alike" {
    var it: Interner = .empty;
    defer it.deinit(testing.allocator);
    const gpa = testing.allocator;

    // The point of interning: two occurrences in one file are separate slices
    // of the source, and must still compare equal by handle.
    const source = "let x = x;";
    const first = try it.intern(gpa, source[4..5]);
    const second = try it.intern(gpa, source[8..9]);
    try testing.expectEqual(first, second);
}

test "a handle round-trips to its text" {
    var it: Interner = .empty;
    defer it.deinit(testing.allocator);

    const id = try it.intern(testing.allocator, "answer");
    try testing.expectEqualStrings("answer", it.textOf(id).?);
    try testing.expect(it.textOf(.none) == null);
}

test "source string ids are a prefix" {
    const gpa = testing.allocator;
    var source: Interner = .empty;
    defer source.deinit(gpa);
    var first_text = [_]u8{ 'f', 'i', 'r', 's', 't' };
    const first = try source.intern(gpa, &first_text);
    const second = try source.intern(gpa, "second");

    var expanded = try Interner.initPrefix(gpa, &source);
    defer expanded.deinit(gpa);

    try testing.expectEqual(StringId.at(0), first);
    try testing.expectEqual(StringId.at(1), second);
    try testing.expectEqual(@as(u32, 2), expanded.count());
    try testing.expect(source.textOf(first).?.ptr == first_text[0..].ptr);
    try testing.expect(expanded.texts.items.ptr != source.texts.items.ptr);
    try testing.expect(expanded.textOf(first).?.ptr == source.textOf(first).?.ptr);
    try testing.expect(expanded.textOf(second).?.ptr == source.textOf(second).?.ptr);

    try testing.expectEqual(StringId.at(2), try source.intern(gpa, "source-only"));
    const generated = try gpa.dupe(u8, "generated-only");
    defer gpa.free(generated);
    const generated_id = try expanded.intern(gpa, generated);
    const stored = expanded.textOf(generated_id).?;
    try testing.expectEqual(StringId.at(2), generated_id);
    try testing.expect(stored.ptr != generated.ptr);
    try testing.expectEqualStrings("generated-only", stored);

    const duplicate = try gpa.dupe(u8, "generated-only");
    defer gpa.free(duplicate);
    var no_alloc = testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    try testing.expectEqual(generated_id, try expanded.intern(no_alloc.allocator(), duplicate));
    try testing.expect(expanded.textOf(generated_id).?.ptr == stored.ptr);
    try testing.expectEqual(@as(u32, 3), expanded.count());

    generated[0] = 'G';
    try testing.expectEqualStrings("source-only", source.textOf(.at(2)).?);
    try testing.expectEqualStrings("generated-only", expanded.textOf(.at(2)).?);
}

test "source string ids are a prefix after failed generated insertion" {
    const gpa = testing.allocator;
    var source: Interner = .empty;
    defer source.deinit(gpa);
    for (0..3) |fail_index| {
        var expanded = try Interner.initPrefix(gpa, &source);
        var failing = testing.FailingAllocator.init(gpa, .{ .fail_index = fail_index });
        defer expanded.deinit(failing.allocator());

        try testing.expectError(error.OutOfMemory, expanded.intern(failing.allocator(), "generated"));
        try testing.expectEqual(@as(u32, 0), expanded.count());
        try testing.expect(expanded.ids.get("generated") == null);
    }
}
