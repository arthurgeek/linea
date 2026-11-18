const std = @import("std");
const testing = std.testing;

/// An allocator that sums successful backing allocation and growth sizes.
/// Ordinary timing forwards the backing allocator's policy. Separate accounting
/// can refuse growth so nested arenas choose their fallback capacities.
///
/// A growing resize or remap charges its full resulting size because failure
/// followed by allocate-copy-free is the same logical growth. Outcome-equivalent
/// growth must contribute the same cost; failed growth, shrink, and free add
/// nothing.
///
/// Over `Regions`, where a large allocation always grows in place, a growth
/// may instead be charged the bytes it adds (`charge = .added`). A table that
/// grows then costs its final capacity, not the sum of every capacity it had.
pub const Counting = struct {
    under: std.mem.Allocator,
    took: usize = 0,
    allow_growth: bool = true,
    /// Backing alignment policy, unchanged while allocations are live. Keeping
    /// nested arena nodes aligned makes accounting independent of buffer offsets.
    minimum_alignment: std.mem.Alignment = .@"1",
    /// What a growth in place is charged.
    charge: enum { resulting, added } = .resulting,
    /// The most `took` may reach. An allocation or growth that would pass it
    /// is refused and recorded in `refused`, so a compilation whose work has
    /// no bound ends with `error.OutOfMemory` instead of exhausting memory.
    most: usize = std.math.maxInt(usize),
    refused: bool = false,

    pub fn allocator(self: *Counting) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }

    fn alloc(ctx: *anyopaque, n: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        if (self.past(n)) return null;
        const got = self.under.rawAlloc(n, self.backingAlignment(a), ra) orelse return null;
        self.took += n;
        return got;
    }

    fn resize(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        if (!self.allow_growth and n > buf.len) return false;
        if (n > buf.len and self.past(self.grown(buf.len, n))) return false;
        if (!self.under.rawResize(buf, self.backingAlignment(a), n, ra)) return false;
        if (n > buf.len) self.took += self.grown(buf.len, n);
        return true;
    }

    fn remap(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        if (!self.allow_growth and n > buf.len) return null;
        if (n > buf.len and self.past(self.grown(buf.len, n))) return null;
        const got = self.under.rawRemap(buf, self.backingAlignment(a), n, ra) orelse return null;
        if (n > buf.len) self.took += self.grown(buf.len, n);
        return got;
    }

    fn grown(self: *const Counting, from: usize, to: usize) usize {
        return switch (self.charge) {
            .resulting => to,
            .added => to - from,
        };
    }

    fn past(self: *Counting, n: usize) bool {
        if (n <= self.most -| self.took) return false;
        self.refused = true;
        return true;
    }

    fn free(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, ra: usize) void {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        self.under.rawFree(buf, self.backingAlignment(a), ra);
    }

    fn backingAlignment(self: *const Counting, requested: std.mem.Alignment) std.mem.Alignment {
        return requested.max(self.minimum_alignment);
    }
};

test "accounting nested arenas is independent of backing buffer offsets" {
    for (1..64) |count| {
        var expected: ?usize = null;
        for ([_]usize{ 0, 8 }) |offset| {
            var storage: [16384]u8 align(64) = undefined;
            var fixed = std.heap.FixedBufferAllocator.init(storage[offset..]);
            var outer = std.heap.ArenaAllocator.init(fixed.allocator());
            defer outer.deinit();
            var counting: Counting = .{
                .under = outer.allocator(),
                .allow_growth = false,
                .minimum_alignment = .fromByteUnits(@alignOf(u128)),
            };
            var inner = std.heap.ArenaAllocator.init(counting.allocator());
            defer inner.deinit();
            for (0..count) |_| _ = try inner.allocator().create(u128);
            if (expected) |value| try testing.expectEqual(value, counting.took);
            expected = counting.took;
        }
    }
}

test "accounting backing alignment also governs growth and release" {
    var counting: Counting = .{ .under = testing.allocator, .minimum_alignment = .fromByteUnits(@alignOf(u128)) };
    const a = counting.allocator();
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    for (0..64) |_| try bytes.append(a, 91);
    bytes.shrinkAndFree(a, 3);
    try testing.expectEqualSlices(u8, &.{ 91, 91, 91 }, bytes.items);
}

/// An allocator whose large allocations always grow in place.
///
/// Each allocation of `threshold` bytes or more is given `region` bytes of
/// address space of its own, which the system backs only where it is
/// written, so growing it never moves it. A smaller one comes from an arena
/// and grows by being replaced. A buffer that grows geometrically is
/// replaced a few times while small and grows in place after that.
///
/// A buffer that never moves hides a pointer kept into it across a growth,
/// which an allocator that moved it would leave dangling. Nothing here looks
/// for that; the corpus walk runs the same compiler over an allocator that
/// moves what grows.
///
/// The address space is asked of the system with no promise it is backed,
/// and where the system has a flag saying so, with that flag. Linux counts a
/// writable private mapping without it against what the system may commit,
/// and adjacent mappings are one mapping to it: a few dozen regions side by
/// side are then one mapping larger than memory and swap together, which a
/// process holding it cannot be forked with, so the runner could start no
/// compiler. A system that refuses to overcommit at all refuses the
/// reservation, which sets `failed`.
pub const Regions = struct {
    small: std.heap.ArenaAllocator,
    /// Whether the system refused a reservation or the room to record one.
    /// An allocation refused for that reason is the system's answer and not
    /// the caller's bound.
    failed: bool = false,
    /// The address of each large allocation.
    large: std.AutoHashMapUnmanaged(usize, void) = .empty,

    pub const threshold: usize = 64 << 10;
    /// The most one allocation holds. No check is allowed more work than
    /// this in all, so none asks for a larger buffer.
    pub const region: usize = 1 << 30;

    const pages = std.heap.page_allocator;

    pub fn init() Regions {
        return .{ .small = std.heap.ArenaAllocator.init(pages) };
    }

    pub fn deinit(self: *Regions) void {
        var held = self.large.iterator();
        while (held.next()) |entry| release(@ptrFromInt(entry.key_ptr.*));
        self.large.deinit(pages);
        self.small.deinit();
    }

    pub fn allocator(self: *Regions) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }

    fn alloc(ctx: *anyopaque, n: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Regions = @ptrCast(@alignCast(ctx));
        if (n < threshold) return self.small.allocator().rawAlloc(n, a, ra);
        if (n > region) return null;
        const memory = reserve(a) orelse {
            self.failed = true;
            return null;
        };
        self.large.put(pages, @intFromPtr(memory), {}) catch {
            release(memory);
            self.failed = true;
            return null;
        };
        return memory;
    }

    /// One region of address space, or null where the system gives none. A
    /// mapping starts on a page, so an alignment wider than a page is given
    /// none either.
    fn reserve(a: std.mem.Alignment) ?[*]u8 {
        if (a.toByteUnits() > std.heap.pageSize()) return null;
        var flags: std.posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
        if (@hasField(std.posix.MAP, "NORESERVE")) flags.NORESERVE = true;
        const memory = std.posix.mmap(null, region, .{ .READ = true, .WRITE = true }, flags, -1, 0) catch return null;
        return memory.ptr;
    }

    fn release(memory: [*]u8) void {
        const start: [*]align(std.heap.page_size_min) u8 = @alignCast(memory);
        std.posix.munmap(start[0..region]);
    }

    fn resize(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        _ = a;
        _ = ra;
        const self: *Regions = @ptrCast(@alignCast(ctx));
        if (n <= buf.len) return true;
        return self.large.contains(@intFromPtr(buf.ptr)) and n <= region;
    }

    fn remap(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        return if (resize(ctx, buf, a, n, ra)) buf.ptr else null;
    }

    fn free(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, ra: usize) void {
        const self: *Regions = @ptrCast(@alignCast(ctx));
        if (self.large.remove(@intFromPtr(buf.ptr))) {
            release(buf.ptr);
        } else {
            self.small.allocator().rawFree(buf, a, ra);
        }
    }
};

test "a large allocation grows in place and is charged what it adds" {
    var regions = Regions.init();
    defer regions.deinit();
    var counting: Counting = .{ .under = regions.allocator(), .charge = .added };
    const a = counting.allocator();

    // A list that doubles is replaced while small and grows in place after.
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(a);
    const before = counting.took;
    for (0..4 * Regions.threshold) |_| try list.append(a, 7);
    // Every capacity under the threshold is charged whole, which sums to
    // under three thresholds, and past it the list is charged its capacity
    // once.
    try testing.expect(counting.took - before >= list.capacity);
    try testing.expect(counting.took - before < list.capacity + 3 * Regions.threshold);
    for (list.items) |byte| try testing.expectEqual(@as(u8, 7), byte);
}

test "allocation growth costs the same after remap success or fallback" {
    var remap_storage: [64]u8 = undefined;
    var remap_backing = std.heap.FixedBufferAllocator.init(&remap_storage);
    var remap_counting: Counting = .{ .under = remap_backing.allocator() };
    var remapped: std.Io.Writer.Allocating = .init(remap_counting.allocator());
    defer remapped.deinit();
    try remapped.ensureTotalCapacityPrecise(8);
    try remapped.ensureTotalCapacityPrecise(16);

    var fallback_storage: [64]u8 = undefined;
    var fallback_backing = std.heap.FixedBufferAllocator.init(&fallback_storage);
    var fallback_counting: Counting = .{ .under = fallback_backing.allocator() };
    var allocated: std.Io.Writer.Allocating = .init(fallback_counting.allocator());
    defer allocated.deinit();
    try allocated.ensureTotalCapacityPrecise(8);
    _ = try fallback_backing.allocator().alloc(u8, 1);
    try allocated.ensureTotalCapacityPrecise(16);

    try testing.expectEqual(remap_counting.took, fallback_counting.took);
    try testing.expectEqual(@as(usize, 24), remap_counting.took);
}

test "nested arena allocation work is independent of backing growth" {
    const Scenario = struct {
        fn cost(block_growth: bool) !usize {
            var storage: [4096]u8 align(64) = undefined;
            var backing = std.heap.FixedBufferAllocator.init(&storage);
            var counting: Counting = .{ .under = backing.allocator(), .allow_growth = false };
            var arena = std.heap.ArenaAllocator.init(counting.allocator());
            defer arena.deinit();

            const first = try arena.allocator().alloc(u8, 128);
            @memset(first, 17);
            // A separate backing allocation prevents resizing the arena's
            // first node without changing the requests made through it.
            if (block_growth) _ = try backing.allocator().alloc(u8, 1);
            const second = try arena.allocator().alloc(u8, 128);
            @memset(second, 29);
            for (first) |byte| try testing.expectEqual(@as(u8, 17), byte);
            for (second) |byte| try testing.expectEqual(@as(u8, 29), byte);
            return counting.took;
        }
    };

    try testing.expectEqual(try Scenario.cost(false), try Scenario.cost(true));
}

test "an allocation past the bound is refused and recorded" {
    var storage: [256]u8 = undefined;
    var backing = std.heap.FixedBufferAllocator.init(&storage);
    var counting: Counting = .{ .under = backing.allocator(), .most = 48 };
    const a = counting.allocator();

    _ = try a.alloc(u8, 32);
    try testing.expect(!counting.refused);
    try testing.expectError(error.OutOfMemory, a.alloc(u8, 32));
    try testing.expect(counting.refused);
    try testing.expectEqual(@as(usize, 32), counting.took);
    _ = try a.alloc(u8, 16);
    try testing.expectEqual(@as(usize, 48), counting.took);
}
