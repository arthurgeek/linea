const std = @import("std");
const testing = std.testing;

fn validateId(comptime Id: type) void {
    // An identifier, not any type: what makes a table safe is that its key
    // names one domain, and a domain is what an enum is.
    if (@typeInfo(Id) != .@"enum") {
        @compileError("a table's key must be an identifier, and " ++
            @typeName(Id) ++ " is not an enum");
    }
    if (!@hasDecl(Id, "index")) {
        @compileError("a table's key must be an identifier with an `index`, and " ++
            @typeName(Id) ++ " has none");
    }
}

/// One value per element, keyed by its domain's identifier.
/// `get` and `set` keep raw indexing inside the storage boundary; `pairs`
/// preserves those typed IDs during iteration. Positional argument runs and
/// body-local slots are not identity-keyed tables and remain ordinary slices.
///
/// The owner sizes the table by its domain and mutates it while producing a
/// representation. A later pass borrows `Reading`, which exposes const entries
/// and has no write or deallocation API. Zig fields remain accessible, so
/// callers must use these accessors to preserve the boundary.
pub fn Table(comptime Id: type, comptime T: type) type {
    comptime validateId(Id);

    return struct {
        const Self = @This();

        /// One entry per element.
        ///
        /// Reached through `get` and `set`, which take an `Id`. Not sealed --
        /// Zig has no way to seal it -- so this is the field a reader should
        /// treat as the storage's own and reach through the two functions
        /// above.
        entries: []T = &.{},

        /// A table of nothing, for a representation built without one.
        pub const empty: Self = .{};

        /// One entry per element, every one of them `fill`.
        ///
        /// The count comes from the caller because only the caller knows what
        /// the table is about: a table kept per function is sized by what that
        /// function holds, and one sized by what the program holds is quadratic
        /// in memory before it is quadratic in anything else.
        pub fn of(gpa: std.mem.Allocator, count: usize, fill: T) !Self {
            const entries = try gpa.alloc(T, count);
            @memset(entries, fill);
            return .{ .entries = entries };
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            gpa.free(self.entries);
            self.* = .empty;
        }

        /// How many elements the table was built for.
        pub fn len(self: Self) usize {
            return self.entries.len;
        }

        /// What is recorded for `id`.
        pub fn get(self: Self, id: Id) T {
            return self.entries[self.at(id)];
        }

        /// Records `value` for `id`.
        ///
        /// Takes a mutable table, so a pass holding one behind `*const` cannot
        /// write through it.
        pub fn set(self: *Self, id: Id, value: T) void {
            self.entries[self.at(id)] = value;
        }

        /// The same entries, readable and nothing else.
        ///
        /// What a borrow hands over. A table passed by value carries `set` and
        /// a `deinit` with it, so a pass that borrowed one could write into
        /// another pass's answer and could free memory it does not own; this
        /// carries neither, and says so in its type.
        pub const Reading = struct {
            entries: []const T = &.{},

            pub const empty: Reading = .{};

            pub fn get(self: Reading, id: Id) T {
                const i = id.index();
                if (i >= self.entries.len) {
                    std.debug.panic(
                        "a table of {d} {s} was asked for number {d}",
                        .{ self.entries.len, @typeName(Id), i },
                    );
                }
                return self.entries[i];
            }

            pub fn len(self: Reading) usize {
                return self.entries.len;
            }
        };

        /// This table, to be read and not written or freed.
        pub fn reading(self: Self) Reading {
            return .{ .entries = self.entries };
        }

        /// Every element, each beside the identifier that names it.
        ///
        /// The identifier rather than a position, so a loop over a table needs
        /// no `@intCast` of its own index and cannot mistake one domain's
        /// number for another's.
        pub fn pairs(self: Self) Pairs {
            return .{ .entries = self.entries };
        }

        pub const Pair = struct { id: Id, value: T };

        pub const Pairs = struct {
            entries: []const T,
            at: usize = 0,

            pub fn next(self: *Pairs) ?Pair {
                if (self.at == self.entries.len) return null;
                defer self.at += 1;
                return .{ .id = @enumFromInt(@as(u32, @intCast(self.at))), .value = self.entries[self.at] };
            }
        };

        /// Where `id` sits, checked.
        ///
        /// A table too short for the identifier handed to it is a table sized
        /// by the wrong thing, which is the second half of what this type is
        /// for -- and a silent read past the end is how that goes unnoticed
        /// until it is a crash somewhere else.
        ///
        /// Guarded rather than covered: a panic cannot be asserted from inside
        /// a Zig test, and this project has no harness that runs one in a child
        /// process to watch it die. So what this earns is a named abort where
        /// there would have been a read of somebody else's memory, and no case
        /// stands behind it. Said here because a check nothing exercises is one
        /// a reader should know is unexercised.
        fn at(self: Self, id: Id) usize {
            const i = id.index();
            if (i >= self.entries.len) {
                std.debug.panic(
                    "a table of {d} {s} was asked for number {d}",
                    .{ self.entries.len, @typeName(Id), i },
                );
            }
            return i;
        }
    };
}

/// One bit per element, keyed by the identifier that names the element.
pub fn BitTable(comptime Id: type) type {
    comptime validateId(Id);

    return struct {
        const Self = @This();
        const word_bits = @bitSizeOf(usize);

        words: []usize = &.{},
        count: usize = 0,

        pub const empty: Self = .{};

        pub fn initEmpty(gpa: std.mem.Allocator, count: usize) !Self {
            const word_count = std.math.divCeil(usize, count, word_bits) catch unreachable;
            const words = try gpa.alloc(usize, word_count);
            @memset(words, 0);
            return .{ .words = words, .count = count };
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            gpa.free(self.words);
            self.* = .empty;
        }

        pub fn len(self: Self) usize {
            return self.count;
        }

        pub fn get(self: Self, id: Id) bool {
            return getFrom(self.words, self.count, id);
        }

        /// Guarded rather than covered: a panic cannot be asserted from inside
        /// a Zig test, and this project has no harness that runs one in a child
        /// process to watch it die. So an out-of-domain set earns a named abort
        /// rather than writing outside the table, and no case stands behind it.
        pub fn set(self: *Self, id: Id, value: bool) void {
            const i = id.index();
            if (i >= self.count) {
                std.debug.panic(
                    "a bit table of {d} {s} was asked for number {d}",
                    .{ self.count, @typeName(Id), i },
                );
            }

            const word = &self.words[i / word_bits];
            const bit = mask(i);
            if (value) {
                word.* |= bit;
            } else {
                word.* &= ~bit;
            }
        }

        pub const Frozen = struct {
            words: []const usize = &.{},
            count: usize = 0,

            pub const empty: Frozen = .{};

            pub fn deinit(self: *Frozen, gpa: std.mem.Allocator) void {
                gpa.free(self.words);
                self.* = .empty;
            }

            pub fn len(self: Frozen) usize {
                return self.count;
            }

            pub fn get(self: Frozen, id: Id) bool {
                return Self.getFrom(self.words, self.count, id);
            }
        };

        pub fn freeze(self: *Self) Frozen {
            const frozen: Frozen = .{ .words = self.words, .count = self.count };
            self.* = .empty;
            return frozen;
        }

        fn getFrom(words: []const usize, count: usize, id: Id) bool {
            const i = id.index();
            if (i >= count) return false;
            return words[i / word_bits] & mask(i) != 0;
        }

        fn mask(i: usize) usize {
            const shift: std.math.Log2Int(usize) = @intCast(i % word_bits);
            return @as(usize, 1) << shift;
        }
    };
}

test "a table is read and written by the identifier that names an element" {
    const Id = enum(u32) {
        _,
        pub fn at(i: u32) @This() {
            return @enumFromInt(i);
        }
        pub fn index(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };

    var table = try Table(Id, u16).of(testing.allocator, 4, 7);
    defer table.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 4), table.len());
    // Filled, so a table read before anything wrote to it says what it was
    // built saying rather than whatever the allocator left there.
    try testing.expectEqual(@as(u16, 7), table.get(Id.at(3)));

    table.set(Id.at(2), 9);
    try testing.expectEqual(@as(u16, 9), table.get(Id.at(2)));
    try testing.expectEqual(@as(u16, 7), table.get(Id.at(1)));
}

test "a table of nothing is a table" {
    const Id = enum(u32) {
        _,
        pub fn index(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };

    var table: Table(Id, u16) = .empty;
    defer table.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), table.len());
}

test "a bit table packs zeroed logical elements across word boundaries" {
    const Id = enum(u32) {
        _,
        pub fn at(i: u32) @This() {
            return @enumFromInt(i);
        }
        pub fn index(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };
    const Bits = BitTable(Id);
    const word_bits = @bitSizeOf(usize);
    const count = 2 * word_bits + 5;

    var zero = try Bits.initEmpty(testing.allocator, 0);
    defer zero.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), zero.len());
    try testing.expectEqual(@as(usize, 0), zero.words.len);

    var bits = try Bits.initEmpty(testing.allocator, count);
    defer bits.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, count), bits.len());
    try testing.expectEqual(@as(usize, 3), bits.words.len);

    for (0..count) |i| {
        try testing.expect(!bits.get(Id.at(@intCast(i))));
    }

    const set_indices = [_]usize{ 0, word_bits - 1, word_bits, count - 1 };
    for (set_indices) |i| bits.set(Id.at(@intCast(i)), true);
    for (set_indices) |i| try testing.expect(bits.get(Id.at(@intCast(i))));

    try testing.expect(!bits.get(Id.at(1)));
    try testing.expect(!bits.get(Id.at(@intCast(word_bits - 2))));
    try testing.expect(!bits.get(Id.at(@intCast(word_bits + 1))));
    try testing.expect(!bits.get(Id.at(@intCast(count - 2))));
    try testing.expect(!bits.get(Id.at(@intCast(count))));

    bits.set(Id.at(@intCast(word_bits)), false);
    try testing.expect(!bits.get(Id.at(@intCast(word_bits))));
}

test "a bit table uses exact words at complete word boundaries" {
    const Id = enum(u32) {
        _,
        pub fn index(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };
    const Bits = BitTable(Id);
    const word_bits = @bitSizeOf(usize);

    var one_word = try Bits.initEmpty(testing.allocator, word_bits);
    defer one_word.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), one_word.words.len);

    var two_words = try Bits.initEmpty(testing.allocator, 2 * word_bits);
    defer two_words.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), two_words.words.len);
}

test "a bit table deinit restores empty" {
    const Id = enum(u32) {
        _,
        pub fn index(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };
    const Bits = BitTable(Id);

    var bits = try Bits.initEmpty(testing.allocator, 1);
    bits.deinit(testing.allocator);

    try testing.expectEqualDeep(Bits.empty, bits);
}

test "a bit table freezes into typed read-only transferred ownership" {
    const A = enum(u32) {
        _,
        pub fn at(i: u32) @This() {
            return @enumFromInt(i);
        }
        pub fn index(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };
    const B = enum(u32) {
        _,
        pub fn index(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };
    const Bits = BitTable(A);
    const Frozen = Bits.Frozen;
    try testing.expect(Frozen != BitTable(B).Frozen);
    try testing.expect(!@hasDecl(Frozen, "set"));
    try testing.expect(@FieldType(Frozen, "words") == []const usize);

    const count = @bitSizeOf(usize) + 3;
    var bits = try Bits.initEmpty(testing.allocator, count);
    bits.set(A.at(1), true);
    bits.set(A.at(@intCast(count - 1)), true);

    var frozen = bits.freeze();
    errdefer frozen.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), bits.len());
    try testing.expectEqual(@as(usize, 0), bits.words.len);
    try testing.expectEqual(@as(usize, count), frozen.len());
    try testing.expect(frozen.get(A.at(1)));
    try testing.expect(frozen.get(A.at(@intCast(count - 1))));
    try testing.expect(!frozen.get(A.at(0)));
    try testing.expect(!frozen.get(A.at(@intCast(count))));

    frozen.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), frozen.len());
    try testing.expectEqual(@as(usize, 0), frozen.words.len);
}
