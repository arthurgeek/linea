const std = @import("std");

/// Copies `strings` and every string in it into `gpa`, for `free` to
/// release. A failure frees what it had copied.
pub fn dupe(gpa: std.mem.Allocator, strings: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    const out = try gpa.alloc([]const u8, strings.len);
    var made: usize = 0;
    errdefer {
        for (out[0..made]) |text| gpa.free(text);
        gpa.free(out);
    }
    for (strings, out) |text, *copy| {
        copy.* = try gpa.dupe(u8, text);
        made += 1;
    }
    return out;
}

test "a copied list of strings holds copies of its strings" {
    const gpa = std.testing.allocator;
    const original = [_][]const u8{ "counter.c", "", "score/score.h" };
    const copied = try dupe(gpa, &original);
    defer free(gpa, copied);
    try std.testing.expectEqual(original.len, copied.len);
    for (original, copied) |held, copy| {
        try std.testing.expectEqualStrings(held, copy);
        if (held.len > 0) try std.testing.expect(held.ptr != copy.ptr);
    }
    try std.testing.checkAllAllocationFailures(gpa, dupeAndFree, .{&original});
}

fn dupeAndFree(gpa: std.mem.Allocator, strings: []const []const u8) !void {
    free(gpa, try dupe(gpa, strings));
}

/// Frees a list of strings allocated in `gpa`, and every string in it.
pub fn free(gpa: std.mem.Allocator, strings: []const []const u8) void {
    for (strings) |text| gpa.free(text);
    gpa.free(strings);
}

test "freeing an empty list frees only the list" {
    const gpa = std.testing.allocator;
    free(gpa, try dupe(gpa, &.{}));
}
