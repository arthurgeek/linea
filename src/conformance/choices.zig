const std = @import("std");

/// A stream of decisions, taken from bytes.
///
/// Reading the bytes directly rather than seeding a generator with them is what
/// lets a fuzzer steer: one byte decides one choice, so a mutation changes the
/// program locally instead of producing an unrelated one. The same stream
/// filled from a seeded generator gives a standalone run that replays.
pub const Choices = struct {
    bytes: []const u8,
    at: usize = 0,

    /// A number below `n`. An exhausted stream repeats from the start rather
    /// than ending generation, so the shape of a program is decided by the
    /// bytes and its size by the caller's limits.
    pub fn below(self: *Choices, n: u32) u32 {
        if (n <= 1 or self.bytes.len == 0) return 0;
        const b = self.bytes[self.at % self.bytes.len];
        self.at += 1;
        return b % n;
    }

    pub fn between(self: *Choices, lo: u32, hi: u32) u32 {
        return lo + self.below(hi - lo + 1);
    }

    pub fn odds(self: *Choices, n: u32) bool {
        return self.below(n) == 0;
    }
};

/// Fills a choice stream from a seed, for a run that replays from one number.
pub fn fromSeed(gpa: std.mem.Allocator, seed: u64, len: usize) ![]u8 {
    const bytes = try gpa.alloc(u8, len);
    var prng = std.Random.DefaultPrng.init(seed);
    prng.random().bytes(bytes);
    return bytes;
}
