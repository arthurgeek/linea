const std = @import("std");
const testing = std.testing;
const loader = @import("../driver/loader.zig");
const source_mod = @import("../support/source.zig");

/// What the editor holds, which is not always what the disk holds.
///
/// Editor state, and no part of any representation a pass reads. Nothing here
/// answers a question about a program; it answers what the bytes currently
/// are.
pub const Documents = struct {
    gpa: std.mem.Allocator,
    open: std.StringHashMapUnmanaged([]const u8) = .empty,

    pub const Change = enum { inserted, changed, unchanged };

    pub fn deinit(self: *Documents) void {
        var it = self.open.iterator();
        while (it.next()) |e| {
            self.gpa.free(e.key_ptr.*);
            self.gpa.free(e.value_ptr.*);
        }
        self.open.deinit(self.gpa);
        self.* = undefined;
    }

    /// Replaces a document's text outright. Full-text sync: the design takes
    /// the re-check rather than an incremental parser, because the front end
    /// costs 0.091 s on a 310 KB function and an incremental one costs a
    /// representation nobody has yet.
    pub fn set(self: *Documents, uri: []const u8, text: []const u8) !Change {
        if (self.open.getPtr(uri)) |entry| {
            if (std.mem.eql(u8, entry.*, text)) return .unchanged;

            const owned = try self.gpa.dupe(u8, text);
            self.gpa.free(entry.*);
            entry.* = owned;
            return .changed;
        }

        const owned_uri = try self.gpa.dupe(u8, uri);
        errdefer self.gpa.free(owned_uri);
        const owned_text = try self.gpa.dupe(u8, text);
        errdefer self.gpa.free(owned_text);
        try self.open.put(self.gpa, owned_uri, owned_text);
        return .inserted;
    }

    pub fn close(self: *Documents, uri: []const u8) void {
        if (self.open.fetchRemove(uri)) |e| {
            self.gpa.free(e.key);
            self.gpa.free(e.value);
        }
    }

    /// Every `.lin` file in the module a file belongs to -- the directory it
    /// sits in, since a module is a directory -- with any open buffer's text
    /// substituted for what the file on disk holds. The caller owns every
    /// path and every text in the returned slice, and the slice itself.
    ///
    /// Membership is the loader's answer, asked rather than re-derived: a
    /// walk of its own agrees on every module without a subdirectory and
    /// disagrees on the first one with, which is a server analysing a
    /// different program than the compiler compiles. Enumerated fresh rather
    /// than from `open`, because `open` knows only what the editor has
    /// touched and a sibling it never opened is still part of the module.
    ///
    /// The root's manifest is among the files: `root` is what the caller's
    /// one walk found, so the editor reads what a root is exactly as the
    /// command line does.
    pub fn filesFor(
        self: *const Documents,
        gpa: std.mem.Allocator,
        io: std.Io,
        root: loader.Root,
    ) ![]const loader.InMemoryFile {
        const paths = try loader.pathsOfRoot(gpa, io, root);
        defer {
            for (paths) |p| gpa.free(p);
            gpa.free(paths);
        }

        var files: std.ArrayList(loader.InMemoryFile) = .empty;
        errdefer {
            for (files.items) |f| {
                gpa.free(f.path);
                gpa.free(f.text);
            }
            files.deinit(gpa);
        }

        for (paths) |disk_path| {
            const path = try gpa.dupe(u8, disk_path);
            errdefer gpa.free(path);

            // A buffer is keyed by the path its URI names, and found by the
            // path the loader's walk produced. The two are one string because
            // the entry the walk started from is spelled canonically, which is
            // what a manifest naming a source root can otherwise undo.
            const text = if (self.open.get(disk_path)) |buffer|
                try gpa.dupe(u8, buffer)
            else
                try source_mod.readFileAlloc(io, gpa, path);
            errdefer gpa.free(text);

            try files.append(gpa, .{ .path = path, .text = text });
        }

        return files.toOwnedSlice(gpa);
    }
};

test "a document reopened does not leak its previous text" {
    var docs: Documents = .{ .gpa = testing.allocator };
    defer docs.deinit();

    try testing.expectEqual(
        Documents.Change.inserted,
        try docs.set("main.lin", "fn main() -> UInt8 { 1 }\n"),
    );
    const first = docs.open.get("main.lin").?.ptr;
    try testing.expectEqual(
        Documents.Change.unchanged,
        try docs.set("main.lin", "fn main() -> UInt8 { 1 }\n"),
    );
    try testing.expect(first == docs.open.get("main.lin").?.ptr);
    try testing.expectEqual(
        Documents.Change.changed,
        try docs.set("main.lin", "fn main() -> UInt8 { 2 }\n"),
    );

    try testing.expectEqual(@as(usize, 1), docs.open.count());
    try testing.expectEqualStrings("fn main() -> UInt8 { 2 }\n", docs.open.get("main.lin").?);
}

test "closing an unopened document is not an error" {
    var docs: Documents = .{ .gpa = testing.allocator };
    defer docs.deinit();

    docs.close("main.lin");
    try testing.expectEqual(@as(usize, 0), docs.open.count());
}

test "an open buffer is what filesFor returns, not the file it shadows" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile(testing.io, "main.lin", .{});
        defer file.close(testing.io);
        try file.writeStreamingAll(testing.io, "fn main() -> UInt8 { let x: UInt8 = true\n    x\n}\n");
    }

    const path = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}/main.lin", .{tmp.sub_path});
    defer testing.allocator.free(path);

    var docs: Documents = .{ .gpa = testing.allocator };
    defer docs.deinit();

    _ = try docs.set(path, "fn main() -> UInt8 {\n    0\n}\n");

    const root = try loader.rootOf(testing.allocator, testing.io, path, .its_program, "");
    defer root.deinit(testing.allocator);
    const files = try docs.filesFor(testing.allocator, testing.io, root);
    defer {
        for (files) |f| {
            testing.allocator.free(f.path);
            testing.allocator.free(f.text);
        }
        testing.allocator.free(files);
    }

    try testing.expectEqual(@as(usize, 1), files.len);
    try testing.expectEqualStrings("fn main() -> UInt8 {\n    0\n}\n", files[0].text);
}

test "a root's files carry the manifest that identified it" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "linea.json", .data = "{ \"kind\": \"library\", \"name\": \"std\" }\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "std.lin", .data = "pub fn one() -> UInt8 {\n    1\n}\n" });
    const root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(root);

    var docs: Documents = .{ .gpa = testing.allocator };
    defer docs.deinit();
    const found = try loader.rootOf(testing.allocator, testing.io, root, .its_program, root);
    defer found.deinit(testing.allocator);
    const files = try docs.filesFor(testing.allocator, testing.io, found);
    defer {
        for (files) |f| {
            testing.allocator.free(f.path);
            testing.allocator.free(f.text);
        }
        testing.allocator.free(files);
    }

    // The editor reads the root as the command line does: the manifest is
    // among its files, so an editor on the library does not load it beside
    // the embedded copy.
    const declared = try loader.declaredGiven(testing.allocator, files);
    try testing.expectEqual(loader.Declared{ .kind = .library, .standard = true }, declared);
}
