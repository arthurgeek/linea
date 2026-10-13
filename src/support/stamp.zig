const std = @import("std");
const testing = std.testing;

/// A map filled for one run of a walk and forgotten before the next, where
/// forgetting costs nothing.
///
/// A hash map empties by clearing its metadata, which costs what the table has
/// room for and not what it holds. A walk that fills one per module therefore
/// pays for the widest module at every module, and the program pays that
/// product -- which is quadratic in a source tree of many modules, and priced
/// in memory bandwidth, so how much it costs is a fact about the machine
/// rather than about the program.
///
/// Here an entry carries the run it was written in and a run is a number that
/// goes up. An entry written before the current run is not there, so emptying
/// the whole table is an increment.
///
/// **Bound:** `restart` is `O(1)`. Every other operation is the map's, plus a
/// comparison. The table keeps the slot of a key written in an earlier run and
/// the next write of that key reuses it, so its memory is the distinct keys
/// the whole walk wrote rather than the most any one run held -- one table for
/// the walk, not one per run.
pub fn Stamped(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        /// A value and the run that wrote it.
        const Entry = struct { run: u32, value: V };

        /// The run no entry belongs to. A run never carries it, so an entry
        /// marked with it is absent whatever the walk is doing -- which is what
        /// makes forgetting one key a store rather than a rehash.
        const forgotten: u32 = 0;

        entries: std.AutoHashMapUnmanaged(K, Entry) = .empty,
        /// Which run a write joins and a read is answered from.
        run: u32 = forgotten + 1,

        pub const empty: Self = .{};

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.entries.deinit(gpa);
            self.* = undefined;
        }

        /// Reserves room for a known bound on distinct keys without adding any.
        pub fn ensureTotalCapacity(self: *Self, gpa: std.mem.Allocator, count: u32) !void {
            try self.entries.ensureTotalCapacity(gpa, count);
        }

        /// Forgets everything written, keeping the room it was written in.
        pub fn restart(self: *Self) void {
            self.run +%= 1;
            // The one place the table is emptied for real: a run number that
            // wrapped would hand back the entries of the run that first
            // carried the number, and they are as old as the walk gets.
            if (self.run == forgotten) {
                self.entries.clearRetainingCapacity();
                self.run = forgotten + 1;
            }
        }

        /// What this run wrote for `key`.
        pub fn get(self: *const Self, key: K) ?V {
            const held = self.entries.get(key) orelse return null;
            return if (held.run == self.run) held.value else null;
        }

        /// Whether this run wrote anything for `key`.
        pub fn contains(self: *const Self, key: K) bool {
            return self.get(key) != null;
        }

        pub fn put(self: *Self, gpa: std.mem.Allocator, key: K, value: V) !void {
            try self.entries.put(gpa, key, .{ .run = self.run, .value = value });
        }

        /// Writes where the key already has a slot, which a caller putting
        /// back what it took out has.
        pub fn putAssumeCapacity(self: *Self, key: K, value: V) void {
            self.entries.putAssumeCapacity(key, .{ .run = self.run, .value = value });
        }

        /// Forgets one key, leaving its slot for the next write of that key.
        pub fn forget(self: *Self, key: K) void {
            const held = self.entries.getPtr(key) orelse return;
            held.run = forgotten;
        }

        /// Where this run's value for `key` sits, and whether it wrote one.
        ///
        /// The slot belongs to this run either way, so a caller that finds it
        /// unwritten writes it -- what an entry left by an earlier run holds
        /// is not a value this run may read.
        pub fn getOrPut(self: *Self, gpa: std.mem.Allocator, key: K) !Slot {
            const slot = try self.entries.getOrPut(gpa, key);
            const written = slot.found_existing and slot.value_ptr.run == self.run;
            slot.value_ptr.run = self.run;
            return .{ .value = &slot.value_ptr.value, .found_existing = written };
        }

        pub const Slot = struct {
            value: *V,
            found_existing: bool,
        };
    };
}

test "a restart forgets what the run before it wrote" {
    const gpa = testing.allocator;
    var map: Stamped(u32, u32) = .empty;
    defer map.deinit(gpa);

    try map.put(gpa, 1, 10);
    try map.put(gpa, 2, 20);
    try testing.expectEqual(@as(?u32, 10), map.get(1));
    try testing.expect(map.contains(2));

    map.restart();
    try testing.expectEqual(@as(?u32, null), map.get(1));
    try testing.expect(!map.contains(2));

    // The slot the forgotten entry left is the slot the next write of that key
    // takes, which is what keeps a run of writes from growing the table again.
    try map.put(gpa, 1, 11);
    try testing.expectEqual(@as(?u32, 11), map.get(1));
    try testing.expectEqual(@as(?u32, null), map.get(2));
}

test "a slot is this run's, whatever an earlier run left in it" {
    const gpa = testing.allocator;
    var map: Stamped(u32, u32) = .empty;
    defer map.deinit(gpa);

    const first = try map.getOrPut(gpa, 7);
    try testing.expect(!first.found_existing);
    first.value.* = 1;

    const again = try map.getOrPut(gpa, 7);
    try testing.expect(again.found_existing);
    try testing.expectEqual(@as(u32, 1), again.value.*);

    map.restart();
    const after = try map.getOrPut(gpa, 7);
    try testing.expect(!after.found_existing);
    after.value.* = 2;
    try testing.expectEqual(@as(?u32, 2), map.get(7));
}

test "a forgotten key is absent until it is written again" {
    const gpa = testing.allocator;
    var map: Stamped(u32, u32) = .empty;
    defer map.deinit(gpa);

    try map.put(gpa, 3, 30);
    map.forget(3);
    try testing.expectEqual(@as(?u32, null), map.get(3));

    // Forgetting a key nothing wrote is what a caller putting back an absence
    // does, and it says the same thing.
    map.forget(4);
    try testing.expectEqual(@as(?u32, null), map.get(4));

    map.putAssumeCapacity(3, 31);
    try testing.expectEqual(@as(?u32, 31), map.get(3));
}

test "a run number that wraps empties the table rather than reviving it" {
    const gpa = testing.allocator;
    var map: Stamped(u32, u32) = .empty;
    defer map.deinit(gpa);

    try map.put(gpa, 5, 50);
    map.run = std.math.maxInt(u32);
    try map.put(gpa, 6, 60);

    map.restart();
    try testing.expectEqual(@as(?u32, null), map.get(5));
    try testing.expectEqual(@as(?u32, null), map.get(6));
}
