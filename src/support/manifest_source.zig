//! Where a manifest's `source` key may point, and which directory it names.
//!
//! A manifest names the directory its root's files sit in, relative to the
//! directory holding the manifest. The loader applies the rule when it reads
//! a manifest, for a program and for a library alike, and the build applies
//! it when it checks which example files a root reaches; all of them read it
//! here, so none can disagree about a spelling. Depends on `std` alone, so the
//! build's own programs can import it.

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
/// directory inside that one by a path down from it: not absolute, and with
/// no `..` component. Such a path names one directory whether its spelling or
/// the filesystem resolves it, so a root read from disk and one read from
/// memory, a program and a library, name the same files. A `..` can climb out
/// of the directory, and even one that stays inside names, through a symbolic
/// link, a directory its spelling does not.
pub fn staysInside(source: []const u8) bool {
    if (source.len > 0 and source[0] == '/') return false;
    var segments = std.mem.tokenizeScalar(u8, source, '/');
    while (segments.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return false;
    }
    return true;
}

test "a manifest's source stays inside the directory holding it" {
    try testing.expect(staysInside("src"));
    try testing.expect(staysInside("./src/"));
    try testing.expect(staysInside("src/lib"));
    try testing.expect(!staysInside("src/../lib"));
    try testing.expect(!staysInside("../elsewhere/src"));
    try testing.expect(!staysInside("src/../../x"));
    try testing.expect(!staysInside("/tmp"));
}

/// The directory a manifest held in `dir` names with `source`: `dir` itself
/// where it names none, and otherwise each component of `source` beneath
/// `dir`, with `.` and empty components taken out. Asked only of a source
/// `staysInside` accepts, so the result is the directory the filesystem finds
/// too. The loader spells a program's and a library's source directory here,
/// and the build its example roots'. The caller owns the result.
pub fn directory(gpa: std.mem.Allocator, dir: []const u8, source: ?[]const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, dir);
    var segments = std.mem.tokenizeScalar(u8, named(source) orelse "", '/');
    while (segments.next()) |segment| {
        if (std.mem.eql(u8, segment, ".")) continue;
        if (out.items.len > 0 and out.items[out.items.len - 1] != '/') try out.append(gpa, '/');
        try out.appendSlice(gpa, segment);
    }
    return out.toOwnedSlice(gpa);
}

test "a manifest's source directory is spelled one way" {
    const gpa = testing.allocator;
    const cases = [_]struct { dir: []const u8, source: ?[]const u8, named: []const u8 }{
        .{ .dir = "app", .source = null, .named = "app" },
        .{ .dir = "app", .source = "", .named = "app" },
        .{ .dir = "app", .source = ".", .named = "app" },
        .{ .dir = "app", .source = "./src/", .named = "app/src" },
        .{ .dir = "app", .source = "src//lib", .named = "app/src/lib" },
        .{ .dir = "", .source = "src", .named = "src" },
        .{ .dir = "", .source = null, .named = "" },
        .{ .dir = "/", .source = "src", .named = "/src" },
    };
    for (cases) |case| {
        const got = try directory(gpa, case.dir, case.source);
        defer gpa.free(got);
        try testing.expectEqualStrings(case.named, got);
    }
}
