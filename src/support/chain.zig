const std = @import("std");
const testing = std.testing;

const Stamped = @import("stamp.zig").Stamped;

/// Which end of a chain a newly noted entry goes on, and so the order a walk
/// hands entries back in.
///
/// The choice is the caller's because it is load-bearing at every site: which
/// of two implementations answers a call, and which of two declarations of one
/// name is reported as the duplicate, are both decided by the order the walk
/// runs in.
pub const Order = enum {
    /// The most recently noted entry is walked first. One handle per chain,
    /// which is all a head-insertion needs.
    newest_first,
    /// The earliest noted entry is walked first. Costs a second handle per
    /// chain, because appending needs the tail as well as the head.
    oldest_first,
};

/// An index over a list the caller owns: a hash of keys to chains of positions
/// in that list.
///
/// The shape every "which entries carry this key" question in the compiler
/// takes. Asking it by reading the list makes one question cost the whole
/// program, so a pass that asks per call, per name or per instantiation pays
/// the product -- which is how the front end became quadratic more than once.
///
/// The list stays the caller's. This holds positions in it and nothing else, so
/// it is a way to reach an answer rather than a second copy of one: every
/// candidate a walk offers is still compared against the thing itself, which is
/// what makes a hash collision cost a comparison rather than a wrong answer.
/// Keys stay the caller's too, packed however the site's identity is packed --
/// what identifies an implementation is not what identifies a name.
///
/// An entry is its own successor at the end of its chain, so no position value
/// is reserved as a sentinel and every position the caller has is usable. One
/// successor per position is also one chain per position: an entry carrying two
/// keys at once wants two indices, because noting it again moves it.
pub fn Chain(comptime order: Order) type {
    return struct {
        const Self = @This();

        /// Where each key's chain begins, and for `.oldest_first` where it
        /// currently ends. Stamped, so a caller indexing one run of a list at a
        /// time forgets the chains of the run that ended in constant time.
        heads: Stamped(u64, Head) = .empty,
        /// The next position sharing a chain, parallel to the caller's list and
        /// reaching as far as the highest position noted.
        next: std.ArrayList(u32) = .empty,

        const Head = switch (order) {
            .newest_first => u32,
            .oldest_first => struct { first: u32, last: u32 },
        };

        pub const empty: Self = .{};

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.heads.deinit(gpa);
            self.next.deinit(gpa);
            self.* = undefined;
        }

        /// Reserves known key and position domains before bulk construction.
        /// The successor span is exact; hash capacity follows its load factor.
        /// No entries are added, and subsequent notes retain their usual order.
        pub fn reserve(self: *Self, gpa: std.mem.Allocator, keys: u32, positions: usize) !void {
            try self.heads.ensureTotalCapacity(gpa, keys);
            try self.next.ensureTotalCapacityPrecise(gpa, positions);
        }

        /// Forgets every chain while keeping the successors already written.
        ///
        /// What a caller indexing one run of a list at a time needs: the
        /// positions stay positions in the whole list, so the run that starts
        /// next carries the same numbering as the one that ended.
        ///
        /// **Bound:** `O(1)`, whatever the run held and whatever the widest
        /// run before it held.
        pub fn restart(self: *Self) void {
            self.heads.restart();
        }

        /// Whether any entry carries a key. The question a caller asks when the
        /// answer is existence rather than which entry.
        pub fn contains(self: *const Self, key: u64) bool {
            return self.heads.contains(key);
        }

        /// Records that the caller's entry at `at` carries `key`.
        ///
        /// **Bound:** amortised `O(1)`, and `O(highest position noted)` in
        /// memory. Noting positions downwards from the end of a list therefore
        /// grows the successor array once.
        pub fn note(self: *Self, gpa: std.mem.Allocator, key: u64, at: u32) !void {
            if (at >= self.next.items.len) {
                try self.next.ensureTotalCapacity(gpa, at + 1);
                // A position nothing noted stands at the end of a chain of its
                // own, which is what makes an unfilled gap unreachable rather
                // than a step into another key's chain.
                while (self.next.items.len <= at) {
                    self.next.appendAssumeCapacity(@intCast(self.next.items.len));
                }
            }

            const slot = try self.heads.getOrPut(gpa, key);
            switch (order) {
                .newest_first => {
                    self.next.items[at] = if (slot.found_existing) slot.value.* else at;
                    slot.value.* = at;
                },
                .oldest_first => {
                    self.next.items[at] = at;
                    if (slot.found_existing) {
                        self.next.items[slot.value.last] = at;
                        slot.value.last = at;
                    } else {
                        slot.value.* = .{ .first = at, .last = at };
                    }
                },
            }
        }

        /// The positions carrying `key`, in this chain's order.
        pub fn walk(self: *const Self, key: u64) Walk {
            const from = self.heads.get(key) orelse return .{ .successors = self.next.items, .at = null };
            return .{
                .successors = self.next.items,
                .at = switch (order) {
                    .newest_first => from,
                    .oldest_first => from.first,
                },
            };
        }

        pub const Walk = struct {
            successors: []const u32,
            at: ?u32,

            pub fn next(self: *Walk) ?u32 {
                const at = self.at orelse return null;
                const then = self.successors[at];
                self.at = if (then == at) null else then;
                return at;
            }
        };
    };
}

test "a chain walks the entries carrying one key and no others" {
    const gpa = testing.allocator;
    var index: Chain(.newest_first) = .empty;
    defer index.deinit(gpa);

    try index.note(gpa, 7, 0);
    try index.note(gpa, 9, 1);
    try index.note(gpa, 7, 2);

    var run = index.walk(7);
    try testing.expectEqual(@as(?u32, 2), run.next());
    try testing.expectEqual(@as(?u32, 0), run.next());
    try testing.expectEqual(@as(?u32, null), run.next());

    try testing.expect(index.contains(9));
    try testing.expect(!index.contains(8));
    var absent = index.walk(8);
    try testing.expectEqual(@as(?u32, null), absent.next());
}

test "the order says which end a noted entry goes on" {
    const gpa = testing.allocator;
    var oldest: Chain(.oldest_first) = .empty;
    defer oldest.deinit(gpa);

    for ([_]u32{ 4, 1, 3 }) |at| try oldest.note(gpa, 0, at);

    var run = oldest.walk(0);
    try testing.expectEqual(@as(?u32, 4), run.next());
    try testing.expectEqual(@as(?u32, 1), run.next());
    try testing.expectEqual(@as(?u32, 3), run.next());
    try testing.expectEqual(@as(?u32, null), run.next());

    // Noting downwards under the other order reaches the same walk, which is
    // what lets an index built in one pass over a finished list hand its
    // entries back in the order the list holds them.
    var newest: Chain(.newest_first) = .empty;
    defer newest.deinit(gpa);
    for ([_]u32{ 3, 1, 4 }) |at| try newest.note(gpa, 0, at);

    var same = newest.walk(0);
    try testing.expectEqual(@as(?u32, 4), same.next());
    try testing.expectEqual(@as(?u32, 1), same.next());
    try testing.expectEqual(@as(?u32, 3), same.next());
    try testing.expectEqual(@as(?u32, null), same.next());
}

test "a restart keeps the numbering the positions were noted under" {
    const gpa = testing.allocator;
    var index: Chain(.oldest_first) = .empty;
    defer index.deinit(gpa);

    try index.note(gpa, 5, 0);
    try index.note(gpa, 5, 1);
    index.restart();
    try index.note(gpa, 5, 2);

    var run = index.walk(5);
    try testing.expectEqual(@as(?u32, 2), run.next());
    try testing.expectEqual(@as(?u32, null), run.next());
}
