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
pub const Counting = struct {
    under: std.mem.Allocator,
    took: usize = 0,
    allow_growth: bool = true,
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
        const got = self.under.rawAlloc(n, a, ra) orelse return null;
        self.took += n;
        return got;
    }

    fn resize(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        if (!self.allow_growth and n > buf.len) return false;
        if (n > buf.len and self.past(n)) return false;
        if (!self.under.rawResize(buf, a, n, ra)) return false;
        if (n > buf.len) self.took += n;
        return true;
    }

    fn remap(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        if (!self.allow_growth and n > buf.len) return null;
        if (n > buf.len and self.past(n)) return null;
        const got = self.under.rawRemap(buf, a, n, ra) orelse return null;
        if (n > buf.len) self.took += n;
        return got;
    }

    fn past(self: *Counting, n: usize) bool {
        if (n <= self.most -| self.took) return false;
        self.refused = true;
        return true;
    }

    fn free(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, ra: usize) void {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        self.under.rawFree(buf, a, ra);
    }
};

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
