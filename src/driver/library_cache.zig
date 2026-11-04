//! The checked standard library, kept on disk between commands.
//!
//! Every command that checks a program checks the standard library first, and
//! the answer depends on nothing but the compiler: the library is carried in
//! the binary. An entry is therefore keyed by the compiler binary's own bytes
//! and the encoding's version, and is shared by every program compiled with
//! that binary.
//!
//! An entry is a fixed header and the library's encoding:
//!
//! | bytes | what |
//! | --- | --- |
//! | 8 | `magic` |
//! | 4 | `library_encoding.format_version`, little-endian |
//! | 32 | the SHA-256 of the compiler binary that wrote it |
//! | 8 | the encoding's length, little-endian |
//! | 8 | the XxHash3 of the encoding, little-endian |
//! | n | the encoding |
//!
//! An entry that is missing, shorter or longer than its header says, written
//! by another compiler or version, or whose encoding does not hash to what the
//! header records, is checked again and written again; it is never an error.
//! The encoding's hash detects an entry damaged on disk, and is read on every
//! command, so it is a fast checksum rather than a cryptographic hash: an
//! entry is trusted because only its user writes the directory, not because
//! of its hash.
//! A write goes to an unnamed file renamed over the entry, so a reader sees a
//! whole entry or none, whichever of several writers renames last.

const std = @import("std");
const testing = std.testing;
const Sha256 = std.crypto.hash.sha2.Sha256;
const loader = @import("loader.zig");
const CheckedLibrary = loader.CheckedLibrary;
const encoding = @import("library_encoding.zig");

/// The environment variable naming the cache directory. Set to the empty
/// string, it turns the cache off: every command checks the library afresh
/// and writes nothing.
pub const directory_variable = "LINEA_CACHE_DIR";

/// The directory beneath `HOME` the cache lives in when `LINEA_CACHE_DIR` is
/// not set.
pub const default_directory = ".linea-cache";

const magic = "LINEACHK";
const Digest = [Sha256.digest_length]u8;
const header_len = magic.len + 4 + Sha256.digest_length + 8 + 8;
/// What every entry's file name starts with, followed by its key in hex.
const entry_prefix = "checked-std-";
/// The most entries the directory keeps: writing one removes the oldest
/// beyond this many, so a compiler rebuilt many times leaves this many behind.
const kept_entries = 8;

/// Where the cache lives, allocated in `gpa`, or null where it is turned off or
/// `HOME` is not set.
pub fn directory(gpa: std.mem.Allocator, environ: std.process.Environ) std.mem.Allocator.Error!?[]const u8 {
    if (environ.getPosix(directory_variable)) |named| return if (named.len == 0) null else try gpa.dupe(u8, named);
    const home = environ.getPosix("HOME") orelse return null;
    if (home.len == 0) return null;
    return try std.fs.path.join(gpa, &.{ home, default_directory });
}

/// The checked library for this compiler: read from the cache in `dir`, or
/// checked and written there.
pub fn open(gpa: std.mem.Allocator, io: std.Io, dir: []const u8) !*CheckedLibrary {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const scratch = arena.allocator();
    const key = compilerIdentity(scratch, io) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        // A compiler that cannot read itself has no key, so it keeps nothing.
        else => return CheckedLibrary.init(gpa),
    };
    return openKeyed(gpa, io, dir, key);
}

fn openKeyed(gpa: std.mem.Allocator, io: std.Io, dir: []const u8, key: Digest) !*CheckedLibrary {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const scratch = arena.allocator();
    const name = try entryName(scratch, key);
    if (read(scratch, io, dir, name, key)) |payload| {
        if (encoding.decode(gpa, payload)) |library| return library else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Corrupt => {},
        }
    } else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {},
    }
    const library = try CheckedLibrary.init(gpa);
    errdefer library.deinit();
    const payload = try encoding.encode(scratch, library);
    write(io, dir, name, key, payload) catch |err| switch (err) {
        // A cache that cannot be written leaves the command as it would be
        // without one.
        else => {},
    };
    return library;
}

fn entryName(gpa: std.mem.Allocator, key: Digest) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(gpa, "{s}{x}", .{ entry_prefix, key });
}

/// The SHA-256 of the running compiler's executable, which changes whenever the
/// compiler's code or the library it carries does.
fn compilerIdentity(gpa: std.mem.Allocator, io: std.Io) !Digest {
    const path = try std.process.executablePathAlloc(io, gpa);
    const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);
    var hasher = Sha256.init(.{});
    var buffer: [256 * 1024]u8 = undefined;
    var offset: u64 = 0;
    while (true) {
        const n = try file.readPositionalAll(io, &buffer, offset);
        hasher.update(buffer[0..n]);
        offset += n;
        if (n < buffer.len) break;
    }
    return hasher.finalResult();
}

/// The encoding an entry holds, where its header matches `key` and the
/// encoding hashes to what the header records.
fn read(gpa: std.mem.Allocator, io: std.Io, dir: []const u8, name: []const u8, key: Digest) ![]const u8 {
    var cache = try std.Io.Dir.cwd().openDir(io, dir, .{});
    defer cache.close(io);
    const bytes = try cache.readFileAlloc(io, name, gpa, .unlimited);
    return payloadOf(bytes, key) orelse error.Corrupt;
}

fn payloadOf(bytes: []const u8, key: Digest) ?[]const u8 {
    if (bytes.len < header_len) return null;
    var at: usize = 0;
    const take = struct {
        fn take(b: []const u8, cursor: *usize, comptime n: usize) *const [n]u8 {
            defer cursor.* += n;
            return b[cursor.*..][0..n];
        }
    }.take;
    if (!std.mem.eql(u8, take(bytes, &at, magic.len), magic)) return null;
    if (std.mem.readInt(u32, take(bytes, &at, 4), .little) != encoding.format_version) return null;
    if (!std.mem.eql(u8, take(bytes, &at, Sha256.digest_length), &key)) return null;
    const len = std.mem.readInt(u64, take(bytes, &at, 8), .little);
    const checksum = std.mem.readInt(u64, take(bytes, &at, 8), .little);
    if (len != bytes.len - header_len) return null;
    const payload = bytes[header_len..];
    if (std.hash.XxHash3.hash(0, payload) != checksum) return null;
    return payload;
}

fn write(io: std.Io, dir: []const u8, name: []const u8, key: Digest, payload: []const u8) !void {
    var cache = try std.Io.Dir.cwd().createDirPathOpen(io, dir, .{ .open_options = .{ .iterate = true } });
    defer cache.close(io);
    var header: [header_len]u8 = undefined;
    var at: usize = 0;
    @memcpy(header[at..][0..magic.len], magic);
    at += magic.len;
    std.mem.writeInt(u32, header[at..][0..4], encoding.format_version, .little);
    at += 4;
    @memcpy(header[at..][0..Sha256.digest_length], &key);
    at += Sha256.digest_length;
    std.mem.writeInt(u64, header[at..][0..8], payload.len, .little);
    at += 8;
    std.mem.writeInt(u64, header[at..][0..8], std.hash.XxHash3.hash(0, payload), .little);

    var file = try cache.createFileAtomic(io, name, .{ .replace = true });
    defer file.deinit(io);
    try file.file.writeStreamingAll(io, &header);
    try file.file.writeStreamingAll(io, payload);
    try file.replace(io);
    evict(io, cache) catch {};
}

/// Removes the oldest entries beyond `kept_entries`.
fn evict(io: std.Io, cache: std.Io.Dir) !void {
    const Entry = struct { name: [entry_prefix.len + 2 * Sha256.digest_length]u8, modified: i96 };
    var entries: [kept_entries + 1]Entry = undefined;
    var count: usize = 0;
    var it = cache.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.startsWith(u8, entry.name, entry_prefix)) continue;
        if (entry.name.len != @sizeOf(@FieldType(Entry, "name"))) continue;
        const stat = cache.statFile(io, entry.name, .{}) catch continue;
        var row: Entry = .{ .name = undefined, .modified = stat.mtime.nanoseconds };
        @memcpy(&row.name, entry.name);
        // Hold the newest `kept_entries + 1`, oldest first, and remove the
        // oldest whenever there is one too many.
        var i = count;
        if (count < entries.len) count += 1 else if (row.modified <= entries[0].modified) {
            cache.deleteFile(io, entry.name) catch {};
            continue;
        } else {
            cache.deleteFile(io, &entries[0].name) catch {};
            std.mem.copyForwards(Entry, entries[0 .. entries.len - 1], entries[1..]);
            i = entries.len - 1;
        }
        while (i > 0 and entries[i - 1].modified > row.modified) : (i -= 1) entries[i] = entries[i - 1];
        entries[i] = row;
    }
    if (count > kept_entries) cache.deleteFile(io, &entries[0].name) catch {};
}

test "checked library cache: a missing, damaged or foreign entry is checked again and rewritten" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(dir);
    const key: Digest = @splat(7);
    const name = try entryName(testing.allocator, key);
    defer testing.allocator.free(name);

    // Missing: checked and written.
    const first = try openKeyed(testing.allocator, testing.io, dir, key);
    const expected = try encoding.encode(testing.allocator, first);
    defer testing.allocator.free(expected);
    first.deinit();
    const written = try tmp.dir.readFileAlloc(testing.io, name, testing.allocator, .unlimited);
    defer testing.allocator.free(written);
    try testing.expectEqualSlices(u8, expected, payloadOf(written, key).?);

    // Present: read back, and the same library.
    const second = try openKeyed(testing.allocator, testing.io, dir, key);
    const reread = try encoding.encode(testing.allocator, second);
    defer testing.allocator.free(reread);
    second.deinit();
    try testing.expectEqualSlices(u8, expected, reread);

    // Under another compiler's key the entry is not this compiler's.
    try testing.expect(payloadOf(written, @splat(8)) == null);

    const damaged = try testing.allocator.dupe(u8, written);
    defer testing.allocator.free(damaged);
    damaged[damaged.len / 2] ^= 1;
    for ([_][]const u8{ written[0 .. written.len - 1], damaged, written[0..10], "" }) |broken| {
        try tmp.dir.writeFile(testing.io, .{ .sub_path = name, .data = broken });
        const library = try openKeyed(testing.allocator, testing.io, dir, key);
        library.deinit();
        const rewritten = try tmp.dir.readFileAlloc(testing.io, name, testing.allocator, .unlimited);
        defer testing.allocator.free(rewritten);
        try testing.expectEqualSlices(u8, written, rewritten);
    }
}

test "checked library cache: an empty directory variable turns the cache off" {
    if (std.process.Environ.Block != std.process.Environ.PosixBlock) return error.SkipZigTest;
    const home = [_:null]?[*:0]const u8{"HOME=/home/someone"};
    const named = (try directory(testing.allocator, .{ .block = .{ .slice = &home } })).?;
    defer testing.allocator.free(named);
    try testing.expectEqualStrings("/home/someone/.linea-cache", named);

    const chosen = [_:null]?[*:0]const u8{ "HOME=/home/someone", "LINEA_CACHE_DIR=/elsewhere" };
    const elsewhere = (try directory(testing.allocator, .{ .block = .{ .slice = &chosen } })).?;
    defer testing.allocator.free(elsewhere);
    try testing.expectEqualStrings("/elsewhere", elsewhere);

    const off = [_:null]?[*:0]const u8{ "HOME=/home/someone", "LINEA_CACHE_DIR=" };
    try testing.expectEqual(@as(?[]const u8, null), try directory(testing.allocator, .{ .block = .{ .slice = &off } }));
}
