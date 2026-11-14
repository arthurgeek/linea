//! Where a manifest's `source` key may point.
//!
//! A manifest names the directory its root's files sit in, relative to the
//! directory holding the manifest. The loader applies the rule when it reads
//! a manifest, and the build applies it when it checks which example files a
//! root reaches; both read it here, so the two cannot disagree about a
//! spelling. Depends on `std` alone, so the build's own programs can import
//! it.

const std = @import("std");
const testing = std.testing;

/// The directory a manifest's `source` names, or null where the manifest
/// writes none or writes it empty, which both mean the manifest's own
/// directory.
pub fn named(source: ?[]const u8) ?[]const u8 {
    const written = source orelse return null;
    return if (written.len == 0) null else written;
}

test "an absent or empty source names the manifest's own directory" {
    try testing.expectEqual(@as(?[]const u8, null), named(null));
    try testing.expectEqual(@as(?[]const u8, null), named(""));
    try testing.expectEqualStrings("src", named("src").?);
}

/// Whether `source`, read from the directory holding the manifest, names a
/// directory inside that one. Decided by spelling, so a root read from disk
/// and one read from memory agree: an absolute path, and one whose `..`
/// climbs past the directory, name another directory's files.
pub fn staysInside(gpa: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!bool {
    if (source.len > 0 and source[0] == '/') return false;
    const resolved = try std.fs.path.resolvePosix(gpa, &.{source});
    defer gpa.free(resolved);
    return !(std.mem.eql(u8, resolved, "..") or std.mem.startsWith(u8, resolved, "../"));
}

test "a manifest's source stays inside the directory holding it" {
    const gpa = testing.allocator;
    try testing.expect(try staysInside(gpa, "src"));
    try testing.expect(try staysInside(gpa, "./src/"));
    try testing.expect(try staysInside(gpa, "src/../lib"));
    try testing.expect(!try staysInside(gpa, "../elsewhere/src"));
    try testing.expect(!try staysInside(gpa, "src/../../x"));
    try testing.expect(!try staysInside(gpa, "/tmp"));
}
