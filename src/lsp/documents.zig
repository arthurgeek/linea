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

    /// Which files `filesFor` reads from disk. A server gives the load a
    /// reader and leaves each source the editor has not opened on disk, so
    /// only the files the program reaches are read. A caller with no reader
    /// to give reads them all.
    pub const Reading = enum { open_and_manifests, every_file };

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
    ///
    /// Under `.open_and_manifests` a source with no open buffer is listed
    /// with its text left on disk (`InMemoryFile.deferred`): what the walk
    /// finds is every file of the program's directories, and a program
    /// reaches only those it imports.
    pub fn filesFor(
        self: *const Documents,
        gpa: std.mem.Allocator,
        io: std.Io,
        root: loader.Root,
        reading: Reading,
    ) ![]const loader.InMemoryFile {
        const paths = try loader.pathsOfRoot(gpa, io, root);
        defer {
            for (paths) |p| gpa.free(p);
            gpa.free(paths);
        }

        var files: std.ArrayList(loader.InMemoryFile) = .empty;
        errdefer {
            freeEach(gpa, files.items);
            files.deinit(gpa);
        }

        for (paths) |disk_path| {
            const path = try gpa.dupe(u8, disk_path);
            errdefer gpa.free(path);

            // A buffer is keyed by the path its URI names, and found by the
            // path the loader's walk produced. The two are one string because
            // the entry the walk started from is spelled canonically, which is
            // what a manifest naming a source root can otherwise undo.
            // A manifest is read by every load of its root, and an open
            // buffer is the text the editor shows. Any other source is left
            // on disk where the load can read it.
            const is_manifest = std.mem.eql(u8, std.fs.path.basename(path), loader.manifest_name);
            const buffer = self.open.get(disk_path);
            const deferred = buffer == null and !is_manifest and reading == .open_and_manifests;
            const text = if (buffer) |held|
                try gpa.dupe(u8, held)
            else if (deferred)
                try gpa.dupe(u8, "")
            else
                try source_mod.readFileAlloc(io, gpa, path);
            errdefer gpa.free(text);

            // A manifest carries where its directory is, so the load from
            // these files tells one library spelled two ways apart from two
            // libraries exactly as the load from disk does.
            const real: ?[:0]u8 = if (is_manifest)
                std.Io.Dir.cwd().realPathFileAlloc(io, std.fs.path.dirname(path) orelse ".", gpa) catch null
            else
                null;
            defer if (real) |held| gpa.free(held);
            const identity = try gpa.dupe(u8, if (real) |held| held else "");
            errdefer gpa.free(identity);

            try files.append(gpa, .{ .path = path, .text = text, .identity = identity, .deferred = deferred });
        }

        return files.toOwnedSlice(gpa);
    }

    /// Releases what `filesFor` returned.
    pub fn freeFiles(gpa: std.mem.Allocator, files: []const loader.InMemoryFile) void {
        freeEach(gpa, files);
        gpa.free(files);
    }

    fn freeEach(gpa: std.mem.Allocator, files: []const loader.InMemoryFile) void {
        for (files) |f| {
            gpa.free(f.path);
            gpa.free(f.text);
            gpa.free(f.identity);
        }
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
    const files = try docs.filesFor(testing.allocator, testing.io, root, .every_file);
    defer Documents.freeFiles(testing.allocator, files);

    try testing.expectEqual(@as(usize, 1), files.len);
    try testing.expectEqualStrings("fn main() -> UInt8 {\n    0\n}\n", files[0].text);
}

test "a source the editor has not opened is listed with its text left on disk" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "linea.json", .data = "{}" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "main.lin", .data = "fn main() -> UInt8 {\n    0\n}\n" });
    try tmp.dir.createDirPath(testing.io, "notes");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "notes/notes.lin", .data = "pub fn size() -> UInt8 {\n    1\n}\n" });
    const root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(root);

    var docs: Documents = .{ .gpa = testing.allocator };
    defer docs.deinit();
    const main_path = try std.fs.path.join(testing.allocator, &.{ root, "main.lin" });
    defer testing.allocator.free(main_path);
    _ = try docs.set(main_path, "fn main() -> UInt8 {\n    7\n}\n");
    const found = try loader.rootOf(testing.allocator, testing.io, root, .its_program, root);
    defer found.deinit(testing.allocator);

    // The open buffer and the manifest carry their text. The module nobody
    // opened carries none.
    const files = try docs.filesFor(testing.allocator, testing.io, found, .open_and_manifests);
    defer Documents.freeFiles(testing.allocator, files);
    try testing.expectEqual(@as(usize, 3), files.len);
    for (files) |file| {
        if (std.mem.endsWith(u8, file.path, "notes/notes.lin")) {
            try testing.expect(file.deferred);
            try testing.expectEqualStrings("", file.text);
        } else {
            try testing.expect(!file.deferred);
            try testing.expect(file.text.len > 0);
        }
    }

    // A caller with no reader to give has every file read.
    const whole = try docs.filesFor(testing.allocator, testing.io, found, .every_file);
    defer Documents.freeFiles(testing.allocator, whole);
    for (whole) |file| {
        try testing.expect(!file.deferred);
        try testing.expect(file.text.len > 0);
    }
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
    const files = try docs.filesFor(testing.allocator, testing.io, found, .every_file);
    defer Documents.freeFiles(testing.allocator, files);

    // The editor reads the root as the command line does: the manifest is
    // among its files, so an editor on the library does not load it beside
    // the embedded copy.
    const declared = try loader.declaredGiven(testing.allocator, files, null);
    try testing.expectEqual(loader.Declared{ .kind = .library, .standard = true }, declared);
}

test "a root's files carry the libraries its manifest names, with open buffers" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "guests");
    try tmp.dir.createDirPath(testing.io, "names");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "guests/linea.json", .data = "{ \"dependencies\": { \"names\": { \"path\": \"../names\" } } }" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "guests/main.lin", .data = "" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "names/linea.json", .data = "{ \"kind\": \"library\", \"name\": \"names\" }" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "names/names.lin", .data = "on disk" });
    const guests = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}/guests", .{tmp.sub_path});
    defer testing.allocator.free(guests);
    const names = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}/names/names.lin", .{tmp.sub_path});
    defer testing.allocator.free(names);

    var docs: Documents = .{ .gpa = testing.allocator };
    defer docs.deinit();
    _ = try docs.set(names, "in the editor");

    const found = try loader.rootOf(testing.allocator, testing.io, guests, .its_program, "");
    defer found.deinit(testing.allocator);
    const files = try docs.filesFor(testing.allocator, testing.io, found, .every_file);
    defer Documents.freeFiles(testing.allocator, files);
    var held: ?[]const u8 = null;
    for (files) |f| if (std.mem.eql(u8, f.path, names)) {
        held = f.text;
    };
    try testing.expectEqualStrings("in the editor", held.?);
}

test "the editor loads one library a manifest reaches by two spellings, as the command line does" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    for ([_][]const u8{ "app", "a", "c" }) |dir| try tmp.dir.createDirPath(testing.io, dir);
    try tmp.dir.symLink(testing.io, "c", "clink", .{ .is_directory = true });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "app/linea.json", .data = "{ \"dependencies\": { \"a\": { \"path\": \"../a\" }, \"c\": { \"path\": \"../clink\" } } }" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "app/main.lin", .data = "import a\nimport c\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a/linea.json", .data = "{ \"kind\": \"library\", \"name\": \"a\", \"dependencies\": { \"c\": { \"path\": \"../c\" } } }" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a/a.lin", .data = "import c\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "c/linea.json", .data = "{ \"kind\": \"library\", \"name\": \"c\" }" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "c/c.lin", .data = "" });
    const app = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}/app", .{tmp.sub_path});
    defer gpa.free(app);

    var docs: Documents = .{ .gpa = gpa };
    defer docs.deinit();
    const found = try loader.rootOf(gpa, testing.io, app, .its_program, "");
    defer found.deinit(gpa);
    const files = try docs.filesFor(gpa, testing.io, found, .every_file);
    defer Documents.freeFiles(gpa, files);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var table: @import("../support/source.zig").FileTable = .empty;
    var sink = @import("../diagnostics/sink.zig").Sink.init(a);
    var interner: @import("../support/interner.zig").Interner = .empty;
    const program = try loader.loadFromMemory(a, &table, &sink, &interner, found.entry, files, .program, false, .borrow);
    try testing.expect(!sink.hasErrors());
    // The application, `a` and `c`, with `c` one library however it is named.
    try testing.expectEqual(@as(usize, 4), program.roots.len);
}
