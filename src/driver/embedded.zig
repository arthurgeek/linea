//! What an `embed` or `embed_bytes` path names, and reading it.
//!
//! A path is relative to the directory of the file that writes it, and may
//! climb with a leading run of `..` as far as the root of the code writing it:
//! the directory holding its program's or library's `linea.json`, or the
//! file's own directory where no manifest marks one. Every input reads through
//! `resolve`, so a path means one thing to the command line, the conformance
//! runner and the editor alike; only where the bytes come from differs.

const std = @import("std");
const testing = std.testing;

/// The most bytes one file may embed. A larger file is refused before it is
/// read, so a mistaken path, a database or a video, is a diagnostic naming
/// the file rather than a compilation that exhausts memory.
pub const max_bytes: u64 = 16 * 1024 * 1024;

/// Why a written path names no file inside its root, from its spelling alone.
pub const Spelling = enum {
    /// Nothing was written.
    empty,
    /// It begins with `/`.
    absolute,
    /// Two `/` in a row, or one at the end.
    empty_component,
    /// A `.` component.
    dot,
    /// A `..` after a component that is not one.
    inner_parent,
    /// More `..` than directories between the root and the writing file.
    leaves_root,
    /// A backslash, which is a separator on some systems and a name byte on
    /// others.
    backslash,
    nul,
    /// A `:`, which names a drive or a stream on some systems.
    colon,
};

pub const Resolved = union(enum) {
    /// The path relative to the root, in `/`-separated components. Owned by
    /// the caller.
    path: []u8,
    refused: Spelling,
};

/// The root-relative path `written` names from a file whose directory is
/// `file_dir`, itself relative to the root ("" for the root itself).
pub fn resolve(gpa: std.mem.Allocator, file_dir: []const u8, written: []const u8) std.mem.Allocator.Error!Resolved {
    if (written.len == 0) return .{ .refused = .empty };
    if (written[0] == '/') return .{ .refused = .absolute };
    for (written) |c| switch (c) {
        '\\' => return .{ .refused = .backslash },
        0 => return .{ .refused = .nul },
        ':' => return .{ .refused = .colon },
        else => {},
    };

    var base: std.ArrayList([]const u8) = .empty;
    defer base.deinit(gpa);
    if (file_dir.len > 0) {
        var parts = std.mem.splitScalar(u8, file_dir, '/');
        while (parts.next()) |part| try base.append(gpa, part);
    }

    var rest: std.ArrayList([]const u8) = .empty;
    defer rest.deinit(gpa);
    var parts = std.mem.splitScalar(u8, written, '/');
    while (parts.next()) |part| {
        if (part.len == 0) return .{ .refused = .empty_component };
        if (std.mem.eql(u8, part, ".")) return .{ .refused = .dot };
        if (std.mem.eql(u8, part, "..")) {
            if (rest.items.len > 0) return .{ .refused = .inner_parent };
            if (base.items.len == 0) return .{ .refused = .leaves_root };
            _ = base.pop();
            continue;
        }
        try rest.append(gpa, part);
    }
    if (rest.items.len == 0) return .{ .refused = .empty };

    try base.appendSlice(gpa, rest.items);
    return .{ .path = try std.mem.join(gpa, "/", base.items) };
}

fn expectPath(expected: []const u8, file_dir: []const u8, written: []const u8) !void {
    const got = try resolve(testing.allocator, file_dir, written);
    switch (got) {
        .path => |p| {
            defer testing.allocator.free(p);
            try testing.expectEqualStrings(expected, p);
        },
        .refused => |why| {
            std.debug.print("refused as {s}\n", .{@tagName(why)});
            return error.TestUnexpectedResult;
        },
    }
}

fn expectRefused(expected: Spelling, file_dir: []const u8, written: []const u8) !void {
    const got = try resolve(testing.allocator, file_dir, written);
    switch (got) {
        .path => |p| {
            defer testing.allocator.free(p);
            std.debug.print("resolved to {s}\n", .{p});
            return error.TestUnexpectedResult;
        },
        .refused => |why| try testing.expectEqual(expected, why),
    }
}

test "a path is relative to the writing file's directory and climbs no further than the root" {
    try expectPath("page.txt", "", "page.txt");
    try expectPath("pages/card.txt", "pages", "card.txt");
    try expectPath("pages/cards/deep/x.txt", "pages/cards", "deep/x.txt");
    try expectPath("templates/page.txt", "pages", "../templates/page.txt");
    try expectPath("templates/page.txt", "pages/cards", "../../templates/page.txt");
    try expectPath("x.txt", "pages", "../x.txt");
    try expectRefused(.leaves_root, "pages", "../../x.txt");
    try expectRefused(.leaves_root, "", "../x.txt");
    // The standard library's root is its own directory: `std/http/page.lin`
    // reaches beside itself, and no further up than `std/`.
    try expectPath("http/error.html", "http", "error.html");
    try expectRefused(.leaves_root, "http", "../../x");
}

test "a path is spelled plainly or refused for its spelling" {
    try expectRefused(.empty, "", "");
    try expectRefused(.empty, "pages", "..");
    try expectRefused(.absolute, "", "/etc/hosts");
    try expectRefused(.empty_component, "", "notes//today.txt");
    try expectRefused(.empty_component, "", "notes/");
    try expectRefused(.dot, "", "./notes.txt");
    try expectRefused(.dot, "", "notes/./today.txt");
    try expectRefused(.inner_parent, "", "notes/../today.txt");
    try expectRefused(.backslash, "", "notes\\today.txt");
    try expectRefused(.nul, "", "notes\x00.txt");
    try expectRefused(.colon, "", "c:notes.txt");
}

/// Why a well-spelled path read no file.
pub const Unread = union(enum) {
    missing,
    /// The last component, or a directory on the way, matched a name only by
    /// letter case. Carries the spelling the directory holds.
    other_case: []const u8,
    /// A name matched only once the bytes outside ASCII are set aside: the
    /// same letters written with other Unicode characters, such as a
    /// precomposed `é` against `e` and a combining accent. Carries the
    /// spelling the directory holds.
    other_form: []const u8,
    /// A directory where a file was named.
    directory,
    /// A symbolic link on the path, the file's own name included. Carries the
    /// root-relative path of the link.
    symlink: []const u8,
    /// Something other than a regular file or a directory.
    special,
    /// More than `max_bytes`. Carries the size.
    too_large: u64,
    /// The filesystem refused to read it. Carries the error's name.
    unreadable: []const u8,
};

pub const Read = union(enum) {
    bytes: []u8,
    unread: Unread,
};

/// Reads `rel` beneath the directory `root` on disk, one component at a time,
/// so each is found by its exact spelling and none may be a symbolic link.
/// The root itself is opened as named, wherever a link above it leads.
///
/// Allocates the bytes, and any name an `Unread` carries, with `gpa`.
pub fn readFromDisk(gpa: std.mem.Allocator, io: std.Io, root: []const u8, rel: []const u8) std.mem.Allocator.Error!Read {
    var dir = std.Io.Dir.cwd().openDir(io, if (root.len == 0) "." else root, .{ .iterate = true }) catch |err|
        return .{ .unread = .{ .unreadable = @errorName(err) } };
    // Closes whichever directory the walk last opened.
    defer dir.close(io);

    var components = std.mem.splitScalar(u8, rel, '/');
    var walked: usize = 0;
    while (components.next()) |name| {
        walked += name.len + @intFromBool(walked > 0);
        const last = components.peek() == null;
        const kind = switch (try entryKind(gpa, io, dir, name)) {
            .kind => |k| k,
            .unread => |why| return .{ .unread = why },
        };
        switch (kind) {
            .sym_link => return .{ .unread = .{ .symlink = try gpa.dupe(u8, rel[0..walked]) } },
            .directory => {
                if (last) return .{ .unread = .directory };
                const next = dir.openDir(io, name, .{ .iterate = true, .follow_symlinks = false }) catch |err|
                    return .{ .unread = .{ .unreadable = @errorName(err) } };
                dir.close(io);
                dir = next;
            },
            .file => {
                if (!last) return .{ .unread = .missing };
                // Opened without waiting and without following a link, and
                // asked what it is once open: the entry may have been replaced
                // since the listing, and a pipe put there would otherwise block
                // the compiler opening it.
                const name_z = try gpa.dupeZ(u8, name);
                defer gpa.free(name_z);
                const fd = std.posix.openatZ(dir.handle, name_z, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .NOFOLLOW = true, .CLOEXEC = true }, 0) catch |err|
                    return .{ .unread = switch (err) {
                        error.SymLinkLoop => .{ .symlink = try gpa.dupe(u8, rel) },
                        else => .{ .unreadable = @errorName(err) },
                    } };
                const file: std.Io.File = .{ .handle = fd, .flags = .{ .nonblocking = true } };
                defer file.close(io);
                const stat = file.stat(io) catch |err| return .{ .unread = .{ .unreadable = @errorName(err) } };
                if (stat.kind != .file) return .{ .unread = .special };
                const size = stat.size;
                if (size > max_bytes) return .{ .unread = .{ .too_large = size } };
                const bytes = try gpa.alloc(u8, @intCast(size));
                const got = file.readPositionalAll(io, bytes, 0) catch |err| {
                    gpa.free(bytes);
                    return .{ .unread = .{ .unreadable = @errorName(err) } };
                };
                if (got != bytes.len) {
                    gpa.free(bytes);
                    return .{ .unread = .{ .unreadable = "ShortRead" } };
                }
                return .{ .bytes = bytes };
            },
            else => return .{ .unread = if (last) .special else .missing },
        }
    }
    return .{ .unread = .missing };
}

const Found = union(enum) {
    kind: std.Io.File.Kind,
    unread: Unread,
};

/// What kind of entry `dir` holds under exactly `name`, read from the
/// directory's own listing so a case-insensitive filesystem does not answer
/// for a name spelled otherwise.
fn entryKind(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, name: []const u8) std.mem.Allocator.Error!Found {
    var other: ?[]const u8 = null;
    var other_form: ?[]const u8 = null;
    var it = dir.iterate();
    while (it.next(io) catch |err| return .{ .unread = .{ .unreadable = @errorName(err) } }) |entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            if (entry.kind != .unknown) return .{ .kind = entry.kind };
            const stat = dir.statFile(io, name, .{ .follow_symlinks = false }) catch |err|
                return .{ .unread = .{ .unreadable = @errorName(err) } };
            return .{ .kind = stat.kind };
        }
        if (other == null and std.ascii.eqlIgnoreCase(entry.name, name)) other = try gpa.dupe(u8, entry.name);
        if (other_form == null and sameOutsideAscii(entry.name, name)) other_form = try gpa.dupe(u8, entry.name);
    }
    if (other) |spelled| return .{ .unread = .{ .other_case = spelled } };
    if (other_form) |spelled| return .{ .unread = .{ .other_form = spelled } };
    return .{ .unread = .missing };
}

/// Whether two names differ and both hold bytes outside ASCII, yet read alike
/// once accents are set aside: the shape of one accented name written in two
/// Unicode forms, a precomposed `é` against `e` and a combining accent, which
/// a listing shows alike. Only a hint for a refusal, so the folding is the
/// Latin-1 letters and the combining accents, and no more.
fn sameOutsideAscii(a: []const u8, b: []const u8) bool {
    if (std.mem.eql(u8, a, b)) return false;
    if (!hasWide(a) or !hasWide(b)) return false;
    var x = Folded{ .text = a };
    var y = Folded{ .text = b };
    while (true) {
        const p = x.next();
        const q = y.next();
        if (p == null or q == null) return p == null and q == null;
        if (p.? != q.?) return false;
    }
}

fn hasWide(text: []const u8) bool {
    for (text) |c| if (c >= 0x80) return true;
    return false;
}

/// The scalars of a name with combining accents dropped, Latin-1 letters
/// written as their base letter, and ASCII in lower case.
const Folded = struct {
    text: []const u8,
    at: usize = 0,

    /// The base letter of each scalar from U+00C0 to U+00FF, or 0 where it has
    /// none.
    const latin1 = "aaaaaa\x00ceeeeiiii\x00nooooo\x00ouuuuy\x00\x00aaaaaa\x00ceeeeiiii\x00nooooo\x00ouuuuy\x00y";

    fn next(self: *Folded) ?u21 {
        while (self.at < self.text.len) {
            const len = std.unicode.utf8ByteSequenceLength(self.text[self.at]) catch 1;
            const end = @min(self.at + len, self.text.len);
            const scalar: u21 = std.unicode.utf8Decode(self.text[self.at..end]) catch self.text[self.at];
            self.at = end;
            if (scalar >= 0x300 and scalar <= 0x36f) continue;
            if (scalar < 0x80) return std.ascii.toLower(@intCast(scalar));
            if (scalar >= 0xc0 and scalar <= 0xff and latin1[scalar - 0xc0] != 0) return latin1[scalar - 0xc0];
            return scalar;
        }
        return null;
    }
};

test "a name written in another Unicode form is told apart from a different name" {
    // `é` precomposed, and `e` followed by a combining acute accent.
    try testing.expect(sameOutsideAscii("caf\xc3\xa9.txt", "cafe\xcc\x81.txt"));
    try testing.expect(!sameOutsideAscii("caf\xc3\xa9.txt", "cafe.txt"));
    try testing.expect(!sameOutsideAscii("page.txt", "page.txt"));
    try testing.expect(!sameOutsideAscii("page.txt", "Page.txt"));
}

/// Reads `full` from files a caller supplied, found by exact path. Where none
/// is, a file beneath it says it is a directory and one differing only in
/// letter case says how it is spelled.
pub fn readFromFiles(comptime File: type, files: []const File, full: []const u8) Read {
    var other: ?[]const u8 = null;
    var other_form: ?[]const u8 = null;
    for (files) |f| {
        if (std.mem.eql(u8, f.path, full)) {
            if (f.text.len > max_bytes) return .{ .unread = .{ .too_large = f.text.len } };
            return .{ .bytes = @constCast(f.text) };
        }
    }
    for (files) |f| {
        if (f.path.len > full.len and std.mem.startsWith(u8, f.path, full) and f.path[full.len] == '/') return .{ .unread = .directory };
        if (other == null and std.ascii.eqlIgnoreCase(f.path, full)) other = std.fs.path.basename(f.path);
        if (other_form == null and sameOutsideAscii(f.path, full)) other_form = std.fs.path.basename(f.path);
    }
    if (other) |spelled| return .{ .unread = .{ .other_case = spelled } };
    if (other_form) |spelled| return .{ .unread = .{ .other_form = spelled } };
    return .{ .unread = .missing };
}

test "files in memory are found by exact path" {
    const File = struct { path: []const u8, text: []const u8 };
    const files = [_]File{
        .{ .path = "app/main.lin", .text = "" },
        .{ .path = "app/Page.txt", .text = "page" },
        .{ .path = "app/templates/x.txt", .text = "x" },
    };
    try testing.expectEqualStrings("x", readFromFiles(File, &files, "app/templates/x.txt").bytes);
    try testing.expectEqual(Unread.directory, readFromFiles(File, &files, "app/templates").unread);
    try testing.expectEqualStrings("Page.txt", readFromFiles(File, &files, "app/page.txt").unread.other_case);
    try testing.expectEqual(Unread.missing, readFromFiles(File, &files, "app/none.txt").unread);
}

test "a file on disk is read by its exact spelling, and no link on its path is followed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "app/pages");
    try tmp.dir.writeFile(io, .{ .sub_path = "app/pages/page.txt", .data = "beside" });
    try tmp.dir.writeFile(io, .{ .sub_path = "app/Upper.txt", .data = "upper" });
    try tmp.dir.writeFile(io, .{ .sub_path = "outside.txt", .data = "outside" });
    try tmp.dir.symLink(io, "../outside.txt", "app/linked.txt", .{});
    try tmp.dir.symLink(io, "pages", "app/aliased", .{ .is_directory = true });
    const big = try tmp.dir.createFile(io, "app/big.bin", .{});
    try big.setLength(io, max_bytes + 1);
    big.close(io);
    const exact = try tmp.dir.createFile(io, "app/exact.bin", .{});
    try exact.setLength(io, max_bytes);
    exact.close(io);
    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}/app", .{tmp.sub_path});

    try testing.expectEqualStrings("beside", (try readFromDisk(gpa, io, root, "pages/page.txt")).bytes);
    try testing.expectEqualStrings("Upper.txt", (try readFromDisk(gpa, io, root, "upper.txt")).unread.other_case);
    try testing.expectEqualStrings("linked.txt", (try readFromDisk(gpa, io, root, "linked.txt")).unread.symlink);
    try testing.expectEqualStrings("aliased", (try readFromDisk(gpa, io, root, "aliased/page.txt")).unread.symlink);
    try testing.expectEqual(Unread.directory, (try readFromDisk(gpa, io, root, "pages")).unread);
    try testing.expectEqual(Unread.missing, (try readFromDisk(gpa, io, root, "pages/none.txt")).unread);
    try testing.expectEqual(max_bytes + 1, (try readFromDisk(gpa, io, root, "big.bin")).unread.too_large);
    try testing.expectEqual(max_bytes, (try readFromDisk(gpa, io, root, "exact.bin")).bytes.len);
}
